import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_opener/go/point.dart';
import 'package:go_opener/go/stone.dart';
import 'package:go_opener/model/drill.dart';
import 'package:go_opener/model/opening_document.dart';
import 'package:go_opener/model/trainer_session.dart';

const _instant = TrainerOptions(
  opponentDelay: Duration.zero,
  autoNext: false,
  replayDelay: Duration.zero,
  punishDelay: Duration.zero,
  followMistakes: true,
);

// Two joseki: 2 lines each, for each color.
const _a =
    '(;GN[A]GK[joseki]SZ[9]PL[B];B[cc]'
    '(;W[dc];B[cd])'
    '(;W[cd];B[dc]))';
const _b =
    '(;GN[B]GK[joseki]SZ[9]PL[B];B[gg]'
    '(;W[fg];B[gf])'
    '(;W[gf];B[fg]))';

DrillSession _drill({
  DrillProgress? progress,
  DrillSettings settings = const DrillSettings(autoNext: false),
  int seed = 1,
}) {
  final p = progress ?? DrillProgress();
  p.settings = settings;
  return DrillSession(
    docs: [
      DrillDoc('a.sgf', OpeningDocument.fromSgf(_a)),
      DrillDoc('b.sgf', OpeningDocument.fromSgf(_b)),
    ],
    progress: p,
    trainerOptions: _instant,
    random: Random(seed),
  );
}

/// Plays the current line without mistake.
void _playClean(DrillSession d) {
  final s = d.session!;
  final path = d.line!.end.pathFromRoot;
  while (s.userToMove) {
    final next = path[path.indexOf(s.current) + 1];
    s.userPlay(next.movePoint(9));
  }
}

/// Plays the current line with one mistake at the first user move.
void _playWithMistake(DrillSession d) {
  d.session!.userPlay(const Point(0, 8));
  _playClean(d);
}

void main() {
  test('lines of every joseki, for both colors', () {
    final d = _drill();
    expect(d.lines.length, 8);
    expect(d.lines.map((l) => l.key).toSet().length, 8);
    expect(d.lines.where((l) => l.color == Stone.white).length, 4);
    // One color only.
    d.updateSettings(
      const DrillSettings(autoNext: false, colors: {Stone.black}),
    );
    expect(d.lines.length, 4);
  });

  test('the key of a line does not depend on the file', () {
    final a = OpeningDocument.fromSgf(_a);
    final b = OpeningDocument.fromSgf(_a.replaceFirst('GN[A]', 'GN[Copy]'));
    expect(
      lineKey(a.root.leaves.first, 9, Stone.black),
      lineKey(b.root.leaves.first, 9, Stone.black),
    );
  });

  test('a line is known after 3 clean runs in a row', () {
    final d = _drill()..next();
    final line = d.line!;
    for (var i = 0; i < kKnownStreak; i++) {
      d.play(line);
      _playClean(d);
      expect(d.round!.clean, isTrue);
    }
    expect(d.recordOf(line)!.known, isTrue);
    expect(d.round!.newlyKnown, isTrue);
    expect(d.knownLines, 1);
    expect(d.knownDocs, 0);
  });

  test('a file is known when all its lines are known', () {
    final d = _drill(
      settings: const DrillSettings(autoNext: false, colors: {Stone.black}),
    )..next();
    for (final l in d.lines.where((l) => l.doc.name == 'A').toList()) {
      for (var i = 0; i < kKnownStreak; i++) {
        d.play(l);
        _playClean(d);
      }
    }
    expect(d.knownDocs, 1);
    expect(d.knownLines, 2);
  });

  test('a missed line comes back after a few lines until it is clean', () {
    final d = _drill()..next();
    final missed = d.line!;
    _playWithMistake(d);
    expect(d.round!.clean, isFalse);
    expect(d.round!.mistakes, 1);
    expect(d.recordOf(missed)!.failing, isTrue);
    expect(d.mistakeLines, [missed]);
    expect(d.pendingRetries, 1);

    var back = false;
    for (var i = 0; i < 6 && !back; i++) {
      d.next();
      if (d.line!.key == missed.key) {
        back = true;
        expect(d.reason, DrillReason.retry);
        _playClean(d);
      } else {
        _playClean(d);
      }
    }
    expect(back, isTrue);
    expect(d.pendingRetries, 0);
    expect(d.mistakeLines, isEmpty);
    expect(d.fixed, contains(missed.key));
  });

  test('a hint makes the run not clean', () {
    final d = _drill()..next();
    d.session!.showHint();
    _playClean(d);
    expect(d.round!.clean, isFalse);
    expect(d.round!.hinted, isTrue);
    expect(d.recordOf(d.line!)!.streak, 0);
  });

  test('the mistakes focus only plays missed lines', () {
    final d = _drill()..next();
    final missed = d.line!;
    _playWithMistake(d);
    d.updateSettings(
      const DrillSettings(autoNext: false, focus: DrillFocus.mistakes),
    );
    for (var i = 0; i < 5; i++) {
      d.next();
      expect(d.line!.key, missed.key);
    }
  });

  test('percent learned per file and training one file only', () {
    final d = _drill(
      settings: const DrillSettings(autoNext: false, colors: {Stone.black}),
    )..next();
    final a = d.lines.firstWhere((l) => l.doc.name == 'A');
    d.play(a);
    _playClean(d);
    final stats = {for (final s in d.docStats) s.doc.name: s};
    // One line of two, one clean run of three: 1/3 / 2.
    expect(stats['A']!.learned, closeTo(1 / 6, 1e-9));
    expect(stats['A']!.fresh, 1);
    expect(stats['B']!.learned, 0);
    expect(d.learned, closeTo(1 / 12, 1e-9));

    d.focusDoc(a.doc);
    for (var i = 0; i < 5; i++) {
      expect(d.line!.doc, a.doc);
      d.next();
    }
    d.focusDoc(null);
    expect(d.only, isNull);
  });

  test('files and colors chosen one by one', () {
    final d = _drill()..next();
    final a = d.docs.firstWhere((x) => x.name == 'A');
    final b = d.docs.firstWhere((x) => x.name == 'B');
    d.setDocColors(b, const {});
    expect(d.isIncluded(b), isFalse);
    expect(d.lines.every((l) => l.doc == a), isTrue);
    expect(d.lines.length, 4);
    // A file left out still shows its progress.
    expect(d.docStats.map((s) => s.doc), containsAll([a, b]));

    d.setDocColors(a, const {Stone.white});
    expect(d.lines.length, 2);
    expect(d.lines.every((l) => l.color == Stone.white), isTrue);
    for (var i = 0; i < 4; i++) {
      d.next();
      expect(d.line!.doc, a);
      expect(d.line!.color, Stone.white);
    }

    // Kept in the saved settings.
    final copy = DrillSettings.fromJson(d.settings.toJson());
    expect(copy.docColors[b.path], isEmpty);
    expect(copy.docColors[a.path], {Stone.white});

    d.setAllDocs(false);
    expect(d.lines, isEmpty);
    d.next();
    expect(d.line, isNull);
    d.setAllDocs(true);
    // Every file back with the default colors (both).
    expect(d.lines.length, 8);
  });

  test('progress is saved and loaded', () async {
    final dir = await Directory.systemTemp.createTemp('drill');
    final file = '${dir.path}/progress.json';
    final p = DrillProgress(path: file);
    final d = _drill(progress: p)..next();
    final line = d.line!;
    _playClean(d);
    await p.save();
    final loaded = await DrillProgress.load(file);
    expect(loaded.records[line.key]!.streak, 1);
    expect(loaded.settings.autoNext, isFalse);
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });
}
