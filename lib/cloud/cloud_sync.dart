import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../model/drill.dart';
import '../model/library.dart';
import '../storage/storage.dart';

/// The Supabase project keeping the accounts and their files. The key is
/// the public one: the database rules let each user read and write only
/// their own rows.
const kSupabaseUrl = 'https://lfkiafzomxqcwjrdtvsj.supabase.co';
const kSupabaseKey = 'sb_publishable_vBZGsPDW-tBco1-OmwhXuA_BX4zizTp';

/// Where the e-mails (confirmation, new password) send the user back.
const kSiteUrl = 'https://noxl.github.io/GoDojo/';

/// Keeps the library and the training progress of the signed-in user in
/// the cloud, the same on every device. The files stay on the device too:
/// the app works the same offline and without an account.
class CloudSync extends ChangeNotifier {
  CloudSync({required this.library, required this.progress});

  final Library library;

  /// The training progress in use (the global trainer's, when it runs).
  final Future<DrillProgress> Function() progress;

  SupabaseClient? _client;
  StreamSubscription<AuthState>? _authSub;
  Timer? _timer;
  Timer? _debounce;
  bool _running = false;
  bool _again = false;

  bool syncing = false;
  DateTime? lastSync;
  String? error;

  /// The user came back from a "new password" e-mail.
  bool recovering = false;

  /// Called when [recovering] becomes true.
  VoidCallback? onPasswordRecovery;

  /// False in tests, or when Supabase could not start.
  bool get available => _client != null;

  User? get user => _client?.auth.currentUser;
  bool get signedIn => user != null;

  /// Starts syncing with [client] (after `Supabase.initialize`).
  void attach(SupabaseClient client) {
    _client = client;
    _authSub = client.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.passwordRecovery) {
        recovering = true;
        onPasswordRecovery?.call();
      }
      if (s.event == AuthChangeEvent.signedIn ||
          s.event == AuthChangeEvent.initialSession && s.session != null) {
        sync();
      }
      notifyListeners();
    });
    library.addListener(_onLibraryChanged);
    // Changes made on the other devices, and the training progress.
    _timer = Timer.periodic(const Duration(seconds: 90), (_) => sync());
  }

  void _onLibraryChanged() {
    if (_running || !signedIn) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), sync);
  }

  // ------------------------------------------------------------ account

  Future<void> signIn(String email, String password) async {
    await _client!.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Creates an account. Returns false when the e-mail must be confirmed
  /// first.
  Future<bool> signUp(String email, String password) async {
    final r = await _client!.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: kSiteUrl,
    );
    return r.session != null;
  }

  Future<void> sendPasswordReset(String email) =>
      _client!.auth.resetPasswordForEmail(email.trim(), redirectTo: kSiteUrl);

  Future<void> setNewPassword(String password) async {
    await _client!.auth.updateUser(UserAttributes(password: password));
    recovering = false;
    notifyListeners();
  }

  Future<void> signOut() async {
    await _client!.auth.signOut();
    lastSync = null;
    error = null;
    notifyListeners();
  }

  // ------------------------------------------------------------ sync

  /// Brings the device and the cloud to the same files and progress.
  Future<void> sync() async {
    if (!signedIn) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    syncing = true;
    notifyListeners();
    try {
      do {
        _again = false;
        await _syncFiles();
        await _syncProgress();
      } while (_again);
      lastSync = DateTime.now();
      error = null;
    } catch (e) {
      error = e is PostgrestException ? e.message : '$e';
      debugPrint('Sync failed: $e');
    } finally {
      _running = false;
      syncing = false;
      notifyListeners();
    }
  }

  Future<String> _statePath() async =>
      p.join(await storage.appDataDir(), 'cloud_sync.json');

  /// What both sides looked like at the last sync, per file:
  /// `{r: cloud time, l: device time}` (milliseconds).
  Future<Map<String, Map<String, Object?>>> _loadState(String uid) async {
    try {
      final path = await _statePath();
      if (!await storage.exists(path)) return {};
      final j = jsonDecode(await storage.read(path)) as Map;
      if (j['user'] != uid) return {};
      return {
        for (final e in (j['files'] as Map).entries)
          '${e.key}': (e.value as Map).cast<String, Object?>(),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveState(
    String uid,
    Map<String, Map<String, Object?>> files,
  ) async => storage.write(
    await _statePath(),
    jsonEncode({'user': uid, 'files': files}),
  );

  static String _rel(String path, String dir) =>
      p.relative(path, from: dir).replaceAll(r'\', '/');

  static String? _abs(String rel, String dir) {
    final parts = rel.split('/').where((s) => s.isNotEmpty && s != '..');
    return parts.isEmpty ? null : p.joinAll([dir, ...parts]);
  }

  static int _ms(Object? iso) =>
      DateTime.parse('$iso').toUtc().millisecondsSinceEpoch;

  Future<void> _syncFiles() async {
    final client = _client!;
    final uid = user!.id;
    final dir = library.directory;
    if (dir == null) return;
    final state = await _loadState(uid);

    // The cloud: path -> (time, deleted).
    final rows = await client.from('files').select('path, updated_at, deleted');
    final remote = <String, (int, bool)>{
      for (final r in rows)
        r['path'] as String: (_ms(r['updated_at']), r['deleted'] == true),
    };
    // The device: path -> time.
    final local = <String, int>{
      for (final f in await storage.listSgf(dir))
        _rel(f.path, dir): f.modified.millisecondsSinceEpoch,
    };

    final upload = <String>{};
    final download = <String>{};
    final deleteHere = <String>{};
    final deleteThere = <String>{};
    final conflicts = <String>{};
    for (final path in {...remote.keys, ...local.keys}) {
      final l = local[path];
      final r = remote[path];
      final s = state[path];
      final localChanged = l != null && (s == null || s['l'] != l);
      final remoteChanged = r != null && (s == null || s['r'] != r.$1);
      if (l != null && (r == null || r.$2)) {
        // Only here (or deleted in the cloud).
        if (r != null && s != null && !localChanged) {
          deleteHere.add(path);
        } else {
          upload.add(path);
        }
      } else if (l == null && r != null && !r.$2) {
        // Only in the cloud (or deleted here).
        if (s != null && !remoteChanged) {
          deleteThere.add(path);
        } else {
          download.add(path);
        }
      } else if (l != null && r != null) {
        if (localChanged && remoteChanged) {
          conflicts.add(path);
        } else if (localChanged) {
          upload.add(path);
        } else if (remoteChanged) {
          download.add(path);
        }
      }
    }

    // Both changed: the most recent keeps the name, the other one is kept
    // next to it, so nothing is lost.
    final texts = <String, String>{};
    if (download.isNotEmpty || conflicts.isNotEmpty) {
      final got = await client.from('files').select('path, sgf').inFilter(
        'path',
        [...download, ...conflicts],
      );
      for (final r in got) {
        texts[r['path'] as String] = r['sgf'] as String? ?? '';
      }
    }
    var keptCopies = 0;
    for (final path in conflicts) {
      final abs = _abs(path, dir);
      final theirs = texts[path];
      if (abs == null || theirs == null) continue;
      final mine = await storage.read(abs);
      if (mine == theirs) {
        download.add(path); // Same content: just remember it.
        continue;
      }
      final copy = _copyPath(abs);
      if (remote[path]!.$1 > local[path]!) {
        await storage.write(copy, mine);
        download.add(path);
      } else {
        await storage.write(copy, theirs);
        upload.add(path);
      }
      keptCopies++;
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final sent = <Map<String, Object?>>[
      for (final path in upload)
        if (_abs(path, dir) case final abs?)
          {
            'user_id': uid,
            'path': path,
            'sgf': await storage.read(abs),
            'deleted': false,
            'updated_at': now,
          },
      for (final path in deleteThere)
        {
          'user_id': uid,
          'path': path,
          'sgf': null,
          'deleted': true,
          'updated_at': now,
        },
    ];
    final newRemote = <String, int>{
      for (final e in remote.entries) e.key: e.value.$1,
    };
    // A few at a time: a request has a size limit.
    for (var i = 0; i < sent.length; i += 50) {
      final back = await client
          .from('files')
          .upsert(sent.sublist(i, (i + 50).clamp(0, sent.length)))
          .select('path, updated_at');
      for (final r in back) {
        newRemote[r['path'] as String] = _ms(r['updated_at']);
      }
    }
    for (final path in download) {
      final abs = _abs(path, dir);
      final text = texts[path];
      if (abs != null && text != null) await storage.write(abs, text);
    }
    for (final path in deleteHere) {
      final abs = _abs(path, dir);
      if (abs != null && await storage.exists(abs)) await storage.delete(abs);
    }

    // Remember both sides as they are now.
    final after = <String, int>{
      for (final f in await storage.listSgf(dir))
        _rel(f.path, dir): f.modified.millisecondsSinceEpoch,
    };
    final next = <String, Map<String, Object?>>{
      for (final e in after.entries)
        if (newRemote[e.key] case final r?) e.key: {'r': r, 'l': e.value},
    };
    await _saveState(uid, next);

    if (download.isNotEmpty || deleteHere.isNotEmpty || keptCopies > 0) {
      await library.refresh();
    }
    if (keptCopies > 0) _again = true; // Send the copies too.
  }

  /// `name (other copy).sgf`, `name (other copy 2).sgf`…
  static String _copyPath(String abs) {
    final base = p.withoutExtension(abs);
    var candidate = '$base (other copy).sgf';
    var i = 2;
    while (storage.existsSync(candidate)) {
      candidate = '$base (other copy $i).sgf';
      i++;
    }
    return candidate;
  }

  Future<void> _syncProgress() async {
    final client = _client!;
    final mine = await progress();
    final row = await client.from('progress').select('data').maybeSingle();
    if (row?['data'] case final Map data) {
      final theirs = DrillProgress()..readJson(jsonEncode(data));
      if (mine.merge(theirs) > 0) {
        await mine.save();
        notifyListeners();
      }
      // The cloud already has every line as it is here: nothing to send.
      int? time(LineRecord? r) => r?.last?.millisecondsSinceEpoch;
      if (mine.records.length == theirs.records.length &&
          mine.records.entries.every(
            (e) => time(theirs.records[e.key]) == time(e.value),
          )) {
        return;
      }
    }
    await client.from('progress').upsert({
      'user_id': user!.id,
      'data': mine.toJson(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _timer?.cancel();
    _debounce?.cancel();
    library.removeListener(_onLibraryChanged);
    super.dispose();
  }
}
