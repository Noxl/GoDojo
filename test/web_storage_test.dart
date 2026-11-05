@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:go_opener/model/drill.dart';
import 'package:go_opener/model/library.dart';
import 'package:go_opener/model/opening_document.dart';
import 'package:go_opener/storage/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Run with: flutter test --platform chrome test/web_storage_test.dart
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await storage.init();
  });

  test('the library works in the browser storage', () async {
    expect(storage.inBrowser, isTrue);
    final lib = Library();
    await lib.init();
    expect(lib.directory, '/GoOpener Library');
    await lib.importFiles([('J.sgf', '(;GN[J]GK[joseki]SZ[9];B[cc])')]);
    expect(lib.entries.single.name, 'J');
    expect(lib.entries.single.kind, DocumentKind.joseki);

    final doc = await OpeningDocument.load(lib.entries.single.path);
    doc.setName('Renamed');
    await doc.saveTo(doc.filePath!);
    await lib.refresh();
    expect(lib.entries.single.name, 'Renamed');

    final dest = await lib.rename(lib.entries.single, 'Other');
    expect(dest, '/GoOpener Library/Other.sgf');
    await lib.delete(lib.entries.single);
    expect(lib.entries, isEmpty);
  });

  test('the progress is kept in the browser', () async {
    final p = DrillProgress(path: '/app/training_progress.json')
      ..record('k', mistakes: 0, hinted: false);
    await p.save();
    final loaded = await DrillProgress.load('/app/training_progress.json');
    expect(loaded.records['k']!.streak, 1);
  });
}
