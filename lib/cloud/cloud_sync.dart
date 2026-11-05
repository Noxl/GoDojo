import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
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

/// Where the session is kept: on the device when "Keep me signed in" is
/// ticked (the default), else in memory only, so closing the app (or the
/// browser tab) signs out.
class SessionStore extends LocalStorage {
  SessionStore()
    : _device = SharedPreferencesLocalStorage(
        persistSessionKey: 'sb-lfkiafzomxqcwjrdtvsj-auth-token',
      );

  static const _prefKey = 'keepSignedIn';
  final SharedPreferencesLocalStorage _device;
  String? _memory;
  bool keep = true;

  @override
  Future<void> initialize() async {
    await _device.initialize();
    keep = (await SharedPreferences.getInstance()).getBool(_prefKey) ?? true;
  }

  Future<void> setKeep(bool value) async {
    keep = value;
    await (await SharedPreferences.getInstance()).setBool(_prefKey, value);
  }

  @override
  Future<bool> hasAccessToken() async =>
      keep ? _device.hasAccessToken() : _memory != null;

  @override
  Future<String?> accessToken() async => keep ? _device.accessToken() : _memory;

  @override
  Future<void> removePersistedSession() async {
    _memory = null;
    await _device.removePersistedSession();
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    if (keep) {
      await _device.persistSession(persistSessionString);
    } else {
      _memory = persistSessionString;
      await _device.removePersistedSession();
    }
  }
}

/// Keeps the library and the training progress of the signed-in user in
/// the cloud, the same on every device. The files stay on the device too:
/// the app works the same offline and without an account.
class CloudSync extends ChangeNotifier {
  CloudSync({required this.library, required this.progress});

  final Library library;

  /// The training progress in use (the global trainer's, when it runs).
  final Future<DrillProgress> Function() progress;

  SupabaseClient? _client;

  /// Where the session is kept ("Keep me signed in").
  final sessionStore = SessionStore();
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

  /// The sync itself refreshes the library: not a change to send.
  bool _selfRefresh = false;

  void _onLibraryChanged() {
    if (_selfRefresh || !signedIn) return;
    // During a sync: one more pass at its end.
    if (_running) {
      _again = true;
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), sync);
  }

  // ------------------------------------------------------------ account

  Future<void> signIn(
    String email,
    String password, {
    bool keepSignedIn = true,
  }) async {
    await sessionStore.setKeep(keepSignedIn);
    await _client!.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Creates an account. Returns false when the e-mail must be confirmed
  /// first.
  Future<bool> signUp(
    String email,
    String password, {
    bool keepSignedIn = true,
  }) async {
    await sessionStore.setKeep(keepSignedIn);
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

  /// Stops a password change started from the account (not an e-mail).
  void cancelPasswordChange() {
    recovering = false;
    notifyListeners();
  }

  /// Asks for a new password in the account dialog.
  void startPasswordChange() {
    recovering = true;
    notifyListeners();
  }

  Future<void> signOut() async {
    await _client!.auth.signOut();
    lastSync = null;
    error = null;
    notifyListeners();
  }

  // ------------------------------------------------------------ sync
  //
  // Each device remembers, per file, what the cloud and the file looked
  // like at its last sync. A change on one side only is copied to the
  // other. A change on both sides keeps both versions (the most recent
  // keeps the name). A file is only written to the cloud if the cloud
  // still has the version this device saw: a change made meanwhile by
  // another device is never overwritten, the next pass sees it. A file is
  // only overwritten or deleted here if it was not changed during the sync.

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
      // Again when something changed meanwhile (a few times at most).
      var passes = 0;
      do {
        _again = false;
        await _syncFiles();
        await _syncProgress();
      } while (_again && ++passes < 4);
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

  /// A time read from the cloud, written back as is (to the microsecond)
  /// in a filter, with "Z" for UTC: no "+" in the address.
  static String _exact(Object? iso) =>
      '$iso'.replaceFirst(RegExp(r'\+00(:?00)?$'), 'Z');

  /// The time of the file at [abs] now (null: no file).
  static Future<int?> _localTime(String abs) async =>
      (await storage.modified(abs))?.millisecondsSinceEpoch;

  /// Writes a row of the cloud (a null [sgf] marks the file deleted), only
  /// if it is still at [seen] (its `updated_at` read at the start; null:
  /// there was no row). Returns the new time, or null when another device
  /// changed it meanwhile.
  Future<int?> _put(String uid, String path, String? sgf, String? seen) async {
    final row = {
      'sgf': sgf,
      'deleted': sgf == null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final files = _client!.from('files');
    try {
      final back = seen == null
          ? await files
                .insert({...row, 'user_id': uid, 'path': path})
                .select('updated_at')
          : await files
                .update(row)
                .eq('path', path)
                .eq('updated_at', seen)
                .select('updated_at');
      return back.isEmpty ? null : _ms(back.first['updated_at']);
    } on PostgrestException catch (e) {
      // Created meanwhile by another device.
      if (e.code == '23505') return null;
      rethrow;
    }
  }

  Future<void> _syncFiles() async {
    final client = _client!;
    final uid = user!.id;
    final dir = library.directory;
    if (dir == null) return;
    final state = await _loadState(uid);

    // The cloud: path -> (time, deleted, time as stored).
    final rows = await client.from('files').select('path, updated_at, deleted');
    final remote = <String, (int, bool, String)>{
      for (final r in rows)
        r['path'] as String: (
          _ms(r['updated_at']),
          r['deleted'] == true,
          _exact(r['updated_at']),
        ),
    };
    // The device: path -> time.
    final local = <String, int>{
      for (final f in await storage.listSgf(dir))
        _rel(f.path, dir): f.modified.millisecondsSinceEpoch,
    };

    final plan = SyncPlan.of(
      remote: {for (final e in remote.entries) e.key: (e.value.$1, e.value.$2)},
      local: local,
      state: state,
    );
    final upload = plan.upload;
    final download = plan.download;
    final deleteHere = plan.deleteHere;
    final deleteThere = plan.deleteThere;
    final conflicts = plan.conflicts;
    final next = plan.unchanged;

    // The contents to bring here.
    final texts = <String, String>{};
    final wanted = [...download, ...conflicts];
    for (var i = 0; i < wanted.length; i += 50) {
      final got = await client
          .from('files')
          .select('path, sgf')
          .inFilter(
            'path',
            wanted.sublist(i, (i + 50).clamp(0, wanted.length)),
          );
      for (final r in got) {
        texts[r['path'] as String] = r['sgf'] as String? ?? '';
      }
    }

    var changedHere = false;

    // Still as listed at the start (not changed during the sync)?
    Future<bool> untouched(String abs, String path) async =>
        await _localTime(abs) == local[path];

    // Both changed: the most recent keeps the name, the other one is kept
    // next to it ("name (other copy).sgf"), so nothing is lost.
    for (final path in conflicts) {
      final abs = _abs(path, dir);
      final theirs = texts[path];
      if (abs == null || theirs == null || !await untouched(abs, path)) {
        _again = true;
        continue;
      }
      final mine = await storage.read(abs);
      final r = remote[path]!;
      if (mine == theirs) {
        next[path] = {'r': r.$1, 'l': local[path]};
        continue;
      }
      if (r.$1 > local[path]!) {
        await storage.write(_copyPath(abs), mine);
        await storage.write(abs, theirs);
        next[path] = {'r': r.$1, 'l': await _localTime(abs)};
      } else {
        await storage.write(_copyPath(abs), theirs);
        final t = await _put(uid, path, mine, r.$3);
        if (t != null) next[path] = {'r': t, 'l': local[path]};
      }
      changedHere = true;
      _again = true; // Send the copy.
    }

    for (final path in upload) {
      final abs = _abs(path, dir);
      if (abs == null) continue;
      final text = await storage.read(abs);
      if (!await untouched(abs, path)) {
        _again = true; // Changed while reading: next pass.
        if (state[path] case final s?) next[path] = s;
        continue;
      }
      final t = await _put(uid, path, text, remote[path]?.$3);
      if (t == null) {
        _again = true; // Changed meanwhile in the cloud: next pass.
        if (state[path] case final s?) next[path] = s;
      } else {
        next[path] = {'r': t, 'l': local[path]};
      }
    }

    for (final path in deleteThere) {
      final t = await _put(uid, path, null, remote[path]!.$3);
      if (t == null) {
        _again = true;
        if (state[path] case final s?) next[path] = s;
      }
    }

    for (final path in download) {
      final abs = _abs(path, dir);
      final text = texts[path];
      if (abs == null || text == null) continue;
      // Created or changed here during the sync: the next pass decides.
      if (await _localTime(abs) != local[path]) {
        _again = true;
        if (state[path] case final s?) next[path] = s;
        continue;
      }
      await storage.write(abs, text);
      next[path] = {'r': remote[path]!.$1, 'l': await _localTime(abs)};
      changedHere = true;
    }

    for (final path in deleteHere) {
      final abs = _abs(path, dir);
      if (abs == null) continue;
      if (!await untouched(abs, path)) {
        _again = true; // Edited here meanwhile: it goes back to the cloud.
        if (state[path] case final s?) next[path] = s;
        continue;
      }
      await storage.delete(abs);
      changedHere = true;
    }

    await _saveState(uid, next);
    if (changedHere) {
      _selfRefresh = true;
      try {
        await library.refresh();
      } finally {
        _selfRefresh = false;
      }
    }
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

  /// The training progress: merged line by line (the most recent run of
  /// each line wins), and written back only if the cloud did not change
  /// meanwhile; otherwise merged again.
  Future<void> _syncProgress() async {
    final client = _client!;
    final mine = await progress();
    for (var attempt = 0; attempt < 3; attempt++) {
      final row = await client
          .from('progress')
          .select('data, updated_at')
          .maybeSingle();
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
      final data = {
        'data': mine.toJson(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      try {
        final back = row == null
            ? await client
                  .from('progress')
                  .insert({...data, 'user_id': user!.id})
                  .select('user_id')
            : await client
                  .from('progress')
                  .update(data)
                  .eq('user_id', user!.id)
                  .eq('updated_at', _exact(row['updated_at']))
                  .select('user_id');
        if (back.isNotEmpty) return;
      } on PostgrestException catch (e) {
        if (e.code != '23505') rethrow;
      }
      // Another device wrote it meanwhile: merge its version too.
    }
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

/// What a sync does with each file, from the cloud ([remote]: path ->
/// (time, deleted)), the device ([local]: path -> time) and what both
/// looked like at the last sync ([state]: path -> {r, l}).
class SyncPlan {
  SyncPlan._();

  final upload = <String>{};
  final download = <String>{};
  final deleteHere = <String>{};
  final deleteThere = <String>{};
  final conflicts = <String>{};

  /// The files already the same on both sides, with their state.
  final unchanged = <String, Map<String, Object?>>{};

  factory SyncPlan.of({
    required Map<String, (int, bool)> remote,
    required Map<String, int> local,
    required Map<String, Map<String, Object?>> state,
  }) {
    final plan = SyncPlan._();
    for (final path in {...remote.keys, ...local.keys}) {
      final l = local[path];
      final r = remote[path];
      final s = state[path];
      final localChanged = l != null && (s == null || s['l'] != l);
      final remoteChanged = r != null && (s == null || s['r'] != r.$1);
      if (l != null && (r == null || r.$2)) {
        // Only here (or deleted in the cloud since the last sync).
        if (r != null && s != null && !localChanged) {
          plan.deleteHere.add(path);
        } else {
          plan.upload.add(path);
        }
      } else if (l == null && r != null && !r.$2) {
        // Only in the cloud (or deleted here since the last sync).
        if (s != null && !remoteChanged) {
          plan.deleteThere.add(path);
        } else {
          plan.download.add(path);
        }
      } else if (l != null && r != null) {
        if (localChanged && remoteChanged) {
          plan.conflicts.add(path);
        } else if (localChanged) {
          plan.upload.add(path);
        } else if (remoteChanged) {
          plan.download.add(path);
        } else {
          plan.unchanged[path] = {'r': r.$1, 'l': l};
        }
      }
    }
    return plan;
  }
}
