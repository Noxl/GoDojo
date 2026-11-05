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
  Future<void> init() async {}

  @override
  Future<String> defaultLibraryDir() async => p.join(
    (await getApplicationDocumentsDirectory()).path,
    'GoOpener Library',
  );

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
