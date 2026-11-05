import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'storage.dart';

Storage createStorage() => WebStorage();

/// Files kept in the browser (local storage), one entry per file.
class WebStorage implements Storage {
  static const _prefix = 'fs:';
  late SharedPreferences _prefs;

  @override
  bool get inBrowser => true;

  @override
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  @override
  Future<String> defaultLibraryDir() async => '/GoOpener Library';

  @override
  Future<String> appDataDir() async => '/app';

  String _key(String path) => '$_prefix$path';

  @override
  Future<String> read(String path) async {
    final v = _prefs.getString(_key(path));
    if (v == null) throw StateError('No file $path');
    return (jsonDecode(v) as Map)['text'] as String;
  }

  @override
  Future<void> write(String path, String text) async {
    final ok = await _prefs.setString(
      _key(path),
      jsonEncode({
        'text': text,
        'mtime': DateTime.now().millisecondsSinceEpoch,
      }),
    );
    if (!ok) throw StateError('The browser storage is full.');
  }

  @override
  Future<bool> exists(String path) async => existsSync(path);

  @override
  bool existsSync(String path) => _prefs.containsKey(_key(path));

  @override
  Future<bool> dirExists(String dir) async => true;

  @override
  Future<void> createDir(String dir) async {}

  @override
  Future<void> delete(String path) async {
    await _prefs.remove(_key(path));
  }

  @override
  Future<void> rename(String from, String to) async {
    final v = _prefs.getString(_key(from));
    if (v == null) throw StateError('No file $from');
    await _prefs.setString(_key(to), v);
    await _prefs.remove(_key(from));
  }

  @override
  Future<List<StoredFile>> listSgf(String dir) async {
    final start = _key(dir.endsWith('/') ? dir : '$dir/');
    final out = <StoredFile>[];
    for (final k in _prefs.getKeys()) {
      if (!k.startsWith(start) || !k.toLowerCase().endsWith('.sgf')) continue;
      final v = jsonDecode(_prefs.getString(k) ?? '{}') as Map;
      out.add(
        StoredFile(
          k.substring(_prefix.length),
          DateTime.fromMillisecondsSinceEpoch(v['mtime'] as int? ?? 0),
        ),
      );
    }
    return out;
  }
}
