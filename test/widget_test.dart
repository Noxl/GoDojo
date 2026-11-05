import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_dojo/app_state.dart';
import 'package:go_dojo/go/point.dart';
import 'package:go_dojo/go/stone.dart';
import 'package:go_dojo/main.dart';
import 'package:go_dojo/model/drill.dart';
import 'package:go_dojo/model/trainer_session.dart';
import 'package:go_dojo/model/opening_document.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester, AppState state) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(GoDojoApp(state: state));
    await tester.pumpAndSettle();
  }

  testWidgets('library groups the files and previews the selected one', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    final dir = Directory.systemTemp.createTempSync('goopener_lib');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Still locked on Windows: the temp folder is cleaned later.
      }
    });
    await tester.runAsync(() async {
      File('${dir.path}/a.sgf').writeAsStringSync(
        '(;SZ[9]GN[Sanrensei]OC[B];B[ee];W[cc](;B[gg])(;B[gc]))',
      );
      File(
        '${dir.path}/b.sgf',
      ).writeAsStringSync('(;SZ[9]GN[Corner]GK[joseki]PL[B];B[cc];W[dc])');
      await state.library.setDirectory(dir.path);
    });
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(GoDojoApp(state: state));
    // Lets the preview read its file.
    Future<void> load() async {
      for (var i = 0; i < 5; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      await tester.pump();
    }

    await load();
    expect(find.text('Openings · Black'), findsOneWidget);
    expect(find.text('Joseki'), findsWidgets);
    // The first file is previewed at the end of its first line.
    expect(find.text('Move 3 / 3'), findsOneWidget);
    expect(find.text('Line 1 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous move'));
    await tester.pump();
    expect(find.text('Move 2 / 3'), findsOneWidget);
    // A joseki shows only its starting position.
    await tester.tap(find.text('Corner'));
    await load();
    expect(find.textContaining('Starting position'), findsOneWidget);
    expect(find.textContaining('Move '), findsNothing);
    expect(state.section, AppSection.library);
  });

  testWidgets('phone size: library, editor and trainer fit', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    final dir = Directory.systemTemp.createTempSync('goopener_phone');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Still locked on Windows.
      }
    });
    await tester.runAsync(() async {
      File('${dir.path}/a.sgf').writeAsStringSync(
        '(;SZ[19]GN[A rather long opening name]OC[W];B[pd];W[dp](;B[pp])(;B[dd]))',
      );
      File('${dir.path}/b.sgf').writeAsStringSync(
        '(;SZ[19]GN[Corner joseki]GK[joseki]PL[B];B[qd];W[oc])',
      );
      await state.library.setDirectory(dir.path);
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(GoDojoApp(state: state));
    for (var i = 0; i < 3; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    }
    await tester.pump();
    expect(find.text('A rather long opening name'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Corner joseki'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Corner joseki'), findsOneWidget);
    expect(find.text('Global'), findsOneWidget);

    final doc = OpeningDocument.fromSgf(
      '(;SZ[19]GN[A rather long opening name]OC[W];B[pd];W[dp](;B[pp])(;B[dd]))',
    );
    state.openInEditor(doc);
    await tester.pumpAndSettle();
    expect(find.byType(AspectRatio), findsWidgets);

    state.train(doc);
    await tester.pump(const Duration(seconds: 1));
    // The opponent's timer starts with the first frame of the trainer.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('A rather long opening name'), findsOneWidget);
    expect(find.textContaining('Opponent played'), findsOneWidget);
  });

  testWidgets('editor plays a move by tapping the board', (tester) async {
    final state = AppState();
    final doc = OpeningDocument.create(
      name: 'Test',
      size: 9,
      color: Stone.black,
    );
    state.openInEditor(doc);
    await pumpApp(tester, state);

    final board = find.byType(CustomPaint).first;
    final box = tester.getRect(find.byType(AspectRatio).first);
    expect(board, findsOneWidget);
    await tester.tapAt(box.center);
    await tester.pumpAndSettle();
    expect(doc.current.movePoint(9), const Point(4, 4));
    expect(find.text('Your move'), findsOneWidget);
  });

  testWidgets('editor shows the first move of a variation', (tester) async {
    final state = AppState();
    final doc = OpeningDocument.create(
      name: 'Test',
      size: 9,
      color: Stone.black,
    );
    doc.play(const Point(4, 4));
    doc.back();
    doc.play(const Point(2, 2)); // second variation at move 1
    state.openInEditor(doc);
    await pumpApp(tester, state);
    expect(tester.takeException(), isNull);
    expect(find.text('Variation 2'), findsOneWidget);
    expect(find.text('Comment'), findsOneWidget);
  });

  testWidgets('Delete key asks for confirmation, Enter accepts', (
    tester,
  ) async {
    final state = AppState();
    final doc = OpeningDocument.create(
      name: 'Test',
      size: 9,
      color: Stone.black,
    );
    doc.play(const Point(4, 4));
    doc.play(const Point(2, 2));
    doc.play(const Point(6, 6));
    doc.back();
    doc.back(); // on move 1, two moves after it
    state.openInEditor(doc);
    await pumpApp(tester, state);

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(
      find.text('Delete move 1 and the 2 moves after it?'),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(doc.root.children, isEmpty);
    expect(doc.current, doc.root);
  });

  testWidgets('trainer renders and accepts the expected move', (tester) async {
    final state = AppState();
    final doc = OpeningDocument.fromSgf('(;SZ[9]OC[B];B[ee];W[cc])');
    state.train(doc);
    await pumpApp(tester, state);
    expect(find.textContaining('You play Black'), findsOneWidget);
    final box = tester.getRect(find.byType(AspectRatio).first);
    await tester.tapAt(box.center);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Line complete'), findsOneWidget);
    expect(find.textContaining('Next line starting'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('Line complete'), findsNothing);
  });

  for (final width in [1500.0, 1000.0, 600.0, 390.0]) {
    testWidgets('global trainer shows the line, knowledge and mistakes '
        '(width $width)', (tester) async {
      final state = AppState();
      final progress = DrillProgress()
        ..settings = const DrillSettings(autoNext: false);
      state
        ..drill = (DrillSession(
          docs: [
            DrillDoc(
              'a.sgf',
              OpeningDocument.fromSgf(
                '(;GN[Low approach]GK[joseki]SZ[9]PL[B];B[cc]'
                '(;W[dc];B[cd])(;W[cd];B[dc]))',
              ),
            ),
          ],
          progress: progress,
          trainerOptions: const TrainerOptions(
            opponentDelay: Duration.zero,
            autoNext: false,
            replayDelay: Duration.zero,
            followMistakes: true,
          ),
        )..next())
        ..section = AppSection.drill;
      tester.view.physicalSize = Size(width, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(GoDojoApp(state: state));
      await tester.pumpAndSettle();
      expect(find.text('Global trainer'), findsOneWidget);
      expect(find.textContaining('to play'), findsWidgets);
      expect(find.text('Low approach'), findsWidgets);
      if (width >= 1150) {
        expect(find.text('What you know'), findsOneWidget);
        expect(find.text('0/4 lines known'), findsOneWidget);
      } else {
        expect(find.text('By file'), findsOneWidget);
      }
      // A wrong move, then the line: it becomes a mistake to fix.
      final d = state.drill!;
      d.session!.userPlay(const Point(8, 8));
      final path = d.line!.end.pathFromRoot;
      while (d.session!.userToMove) {
        final s = d.session!;
        s.userPlay(path[path.indexOf(s.current) + 1].movePoint(9));
      }
      await tester.pumpAndSettle();
      expect(find.textContaining('comes back in a few lines'), findsOneWidget);
      expect(d.mistakeLines, hasLength(1));
      state
        ..goTo(AppSection.library)
        ..stopDrill();
      await tester.pumpAndSettle();
    });
  }

  testWidgets('a new joseki opens in start position mode', (tester) async {
    final state = AppState();
    final doc = OpeningDocument.create(
      name: 'J',
      size: 9,
      kind: DocumentKind.joseki,
    );
    state.openInEditor(doc);
    await pumpApp(tester, state);
    expect(find.text('Joseki'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    final box = tester.getRect(find.byType(AspectRatio).first);
    await tester.tapAt(box.center);
    await tester.pumpAndSettle();
    expect(doc.root.getAll('AB'), ['ee']);
    expect(doc.root.children, isEmpty);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    final after = tester.getRect(find.byType(AspectRatio).first);
    await tester.tapAt(after.center + Offset(after.width / 4.5, 0));
    await tester.pumpAndSettle();
    expect(doc.root.children.single.moveColor, Stone.black);
  });

  testWidgets('typing in a text field does not trigger editor shortcuts', (
    tester,
  ) async {
    final state = AppState();
    final doc = OpeningDocument.create(name: 'T', size: 9, color: Stone.black);
    state.openInEditor(doc);
    await pumpApp(tester, state);
    await tester.tap(find.widgetWithText(TextField, 'Comment'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Comment'), 'a&');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(find.text('Analyze (&)'), findsOneWidget);
    expect(doc.current.get('C'), 'a&');
  });
}
