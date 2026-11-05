import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_dojo/model/backup.dart';
import 'package:go_dojo/model/drill.dart';
import 'package:go_dojo/model/library.dart';
import 'package:go_dojo/storage/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('goopener_store');
  });
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a file can be written again (replaced)', () async {
    final path = '${dir.path}/sub/a.sgf';
    await storage.write(path, '(;GN[1])');
    await storage.write(path, '(;GN[2])');
    expect(await storage.read(path), '(;GN[2])');
    final files = await storage.listSgf(dir.path);
    expect(files.map((f) => f.path.replaceAll(r'\', '/')), [
      '${dir.path.replaceAll(r'\', '/')}/sub/a.sgf',
    ]);
  });

  test('backup and restore the library and the progress', () async {
    final lib = Library();
    await lib.setDirectory('${dir.path}/lib');
    await lib.importFiles([
      ('Joseki A.sgf', '(;GN[Joseki A]GK[joseki]SZ[9];B[cc])'),
      ('Opening.sgf', '(;GN[Opening]OC[B]SZ[9];B[ee])'),
    ]);
    expect(lib.entries.length, 2);
    final progress = DrillProgress()
      ..record('line', mistakes: 0, hinted: false, now: DateTime(2026));
    final text = await buildBackup(lib, progress);

    // Another device: empty library, older progress of the same line.
    final other = Library();
    await other.setDirectory('${dir.path}/other');
    final otherProgress = DrillProgress(path: '${dir.path}/p.json')
      ..record('line', mistakes: 2, hinted: false, now: DateTime(2025));
    final (files, lines) = await restoreBackup(other, otherProgress, text);
    expect(files, 2);
    expect(lines, 1);
    expect(other.entries.map((e) => e.name).toSet(), {'Joseki A', 'Opening'});
    expect(otherProgress.records['line']!.streak, 1);
    final saved = await DrillProgress.load('${dir.path}/p.json');
    expect(saved.records['line']!.streak, 1);
  });

  test('a file that is not a backup is refused', () async {
    final lib = Library();
    await lib.setDirectory('${dir.path}/lib');
    expect(
      () => restoreBackup(lib, DrillProgress(), '{"a": 1}'),
      throwsFormatException,
    );
  });
}
