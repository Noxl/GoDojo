import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'storage.dart';

Storage createStorage() => IoStorage();

/// Files on the disk.
class IoStorage implements Storage {
  @override
  bool get inBrowser => false;

  @override
  Future<void> init() async {
    try {
      await _migrateFromGoOpener();
    } catch (_) {
      // Best effort: the app works without the old data.
    }
  }

  static const _oldLibrary = 'GoOpener Library';
  static const _library = 'Go Dojo Library';

  /// The app was called GoOpener: moves its library folder, settings and
  /// training progress to the Go Dojo places, once.
  Future<void> _migrateFromGoOpener() async {
    final support = await getApplicationSupportDirectory();
    final old = Directory(
      p.join(p.dirname(p.dirname(support.path)), 'com.goopener', 'GoOpener'),
    );
    final prefs = File(p.join(support.path, 'shared_preferences.json'));
    if (!await prefs.exists() && await old.exists()) {
      await support.create(recursive: true);
      await for (final f in old.list()) {
        if (f is! File) continue;
        var text = await f.readAsString();
        // Paths into the library folder (the chosen folder, the colors
        // chosen per file) follow it.
        text = text.replaceAll(_oldLibrary, _library);
        await File(
          p.join(support.path, p.basename(f.path)),
        ).writeAsString(text);
      }
    }
    final docs = (await getApplicationDocumentsDirectory()).path;
    final oldLib = Directory(p.join(docs, _oldLibrary));
    final newLib = Directory(p.join(docs, _library));
    if (await oldLib.exists() && !await newLib.exists()) {
      await oldLib.rename(newLib.path);
    }
  }

  @override
  Future<String> defaultLibraryDir() async {
    final docs = (await getApplicationDocumentsDirectory()).path;
    final dir = p.join(docs, _library);
    // The old folder could not be moved (open elsewhere): keep using it.
    final old = p.join(docs, _oldLibrary);
    if (!await Directory(dir).exists() && await Directory(old).exists()) {
      return old;
    }
    return dir;
  }

  @override
  Future<String> appDataDir() async =>
      (await getApplicationSupportDirectory()).path;

  @override
  Future<String> read(String path) => File(path).readAsString();

  @override
  Future<void> write(String path, String text) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    // Through a temporary file, so a crash never leaves half a file.
    final tmp = File('$path.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(path);
  }

  @override
  Future<bool> exists(String path) => File(path).exists();

  @override
  bool existsSync(String path) => File(path).existsSync();

  @override
  Future<bool> dirExists(String dir) => Directory(dir).exists();

  @override
  Future<void> createDir(String dir) => Directory(dir).create(recursive: true);

  @override
  Future<void> delete(String path) => File(path).delete();

  @override
  Future<void> rename(String from, String to) async {
    await File(to).parent.create(recursive: true);
    await File(from).rename(to);
  }

  @override
  Future<List<StoredFile>> listSgf(String dir) async {
    final out = <StoredFile>[];
    await for (final f in Directory(dir).list(recursive: true)) {
      if (f is! File || p.extension(f.path).toLowerCase() != '.sgf') continue;
      out.add(StoredFile(f.path, (await f.stat()).modified));
    }
    return out;
  }
}
