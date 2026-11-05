import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_dojo/go/point.dart';
import 'package:go_dojo/go/stone.dart';
import 'package:go_dojo/model/trainer_session.dart';
import 'package:go_dojo/sgf/sgf.dart';

const _instant = TrainerOptions(
  opponentDelay: Duration.zero,
  autoNext: false,
  replayDelay: Duration.zero,
);

void main() {
  // White repertoire: Black opens, White answers.
  const sgf =
      '(;SZ[9]OC[W]'
      ';B[ee]'
      '(;W[cc];B[gg];W[cg])'
      '(;W[gg]BM[1]C[Bad idea];B[cc])'
      '(;W[gc]))';

  TrainerSession session({TrainerOptions options = _instant, int seed = 1}) =>
      TrainerSession(
        root: parseSgf(sgf),
        size: 9,
        color: Stone.white,
        options: options,
        random: Random(seed),
      );

  test('opponent plays first, then waits for the user', () {
    final s = session();
    expect(s.current.movePoint(9), const Point(4, 4));
    expect(s.userToMove, isTrue);
  });

  test('wrong, bad and correct moves', () {
    final s = session();
    s.userPlay(const Point(0, 0));
    expect(s.feedback.kind, FeedbackKind.notInRepertoire);
    s.userPlay(const Point(6, 6)); // annotated as bad
    expect(s.feedback.kind, FeedbackKind.mistake);
    expect(s.feedback.comment, 'Bad idea');
    expect(s.mistakes, 2);
    s.userPlay(const Point(2, 2));
    expect(s.correctMoves, 1);
    // Opponent replied, user to move again.
    expect(s.current.movePoint(9), const Point(6, 6));
    s.userPlay(const Point(2, 6));
    expect(s.lineDone, isTrue);
    expect(s.linesCovered, 1);
  });

  test(
    'a bad move of the user is punished, then the position comes back',
    () async {
      final s = session(
        options: const TrainerOptions(
          opponentDelay: Duration.zero,
          autoNext: false,
          replayDelay: Duration.zero,
          followMistakes: true,
          punishDelay: Duration(milliseconds: 5),
        ),
      );
      final before = s.current;
      s.userPlay(const Point(6, 6)); // annotated as bad
      expect(s.mistakes, 1);
      expect(s.punishing, isTrue);
      expect(s.userToMove, isFalse);
      expect(s.feedback.message, startsWith('Bad move!'));
      // The opponent's punishment is played automatically.
      while (s.current.movePoint(9) != const Point(2, 2)) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      while (s.punishing) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      // Back before the mistake: the user must find the right move.
      expect(s.current, before);
      expect(s.lineDone, isFalse);
      expect(s.userToMove, isTrue);
      expect(s.feedback.comment, 'Bad idea');
      s.userPlay(const Point(6, 2));
      expect(s.lineDone, isTrue);
    },
  );

  test('any good move of the user is followed to the end of its branch', () {
    for (var seed = 0; seed < 10; seed++) {
      final s = session(seed: seed);
      s.userPlay(const Point(2, 2));
      expect(s.current.movePoint(9), const Point(6, 6));
      s.userPlay(const Point(2, 6));
      expect(s.lineDone, isTrue);
      s.nextLine();
      s.userPlay(const Point(6, 2));
      expect(s.lineDone, isTrue);
    }
  });

  test('a node with moves of both colors allows tenuki', () {
    // After B[ee], White answers at cc or plays elsewhere (Black plays gc).
    const tree = '(;SZ[9]GK[joseki]PL[B];B[ee](;W[cc];B[gg])(;B[gc];W[gg]))';
    final seen = <Point>{};
    for (var seed = 0; seed < 20; seed++) {
      final s = TrainerSession(
        root: parseSgf(tree),
        size: 9,
        color: Stone.white,
        options: _instant,
        random: Random(seed),
      );
      if (s.userToMove && s.current.movePoint(9) == const Point(4, 4)) {
        s.userPlay(const Point(2, 2));
        seen.add(const Point(2, 2));
      } else {
        expect(s.current.movePoint(9), const Point(6, 2));
        seen.add(const Point(6, 2));
        s.userPlay(const Point(6, 6));
      }
      expect(s.lineDone, isTrue);
    }
    expect(seen, hasLength(2));
  });

  test('every line has the same chance, whatever the size of its branch', () {
    // Opponent: cc leads to one line, gg to three.
    const tree =
        '(;SZ[9];B[ee]'
        '(;W[cc];B[cg])'
        '(;W[gg](;B[cc])(;B[gc])(;B[cg])))';
    var short = 0;
    for (var seed = 0; seed < 400; seed++) {
      final s = TrainerSession(
        root: parseSgf(tree),
        size: 9,
        color: Stone.black,
        options: _instant,
        random: Random(seed),
      );
      s.userPlay(const Point(4, 4));
      if (s.current.movePoint(9) == const Point(2, 2)) short++;
    }
    expect(short, inInclusiveRange(60, 140)); // about 1 in 4
  });

  test('tenuki is a move to find when it is in the tree', () {
    const tree = '(;SZ[9]OC[W];B[ee](;W[];B[cc])(;W[cc]BM[1]))';
    final s = TrainerSession(
      root: parseSgf(tree),
      size: 9,
      color: Stone.white,
      options: _instant,
    );
    s.showHint();
    expect(s.feedback.message, contains('tenuki'));
    s.userPlay(null);
    expect(s.correctMoves, 1);
    // Black plays again, then the line is over.
    expect(s.current.movePoint(9), const Point(2, 2));
    expect(s.lineDone, isTrue);
  });

  test('tenuki not in the tree is refused', () {
    final s = session();
    s.userPlay(null);
    expect(s.feedback.kind, FeedbackKind.notInRepertoire);
    expect(s.mistakes, 1);
    expect(s.userToMove, isTrue);
  });

  test('hint shows only good moves', () {
    final s = session();
    s.showHint();
    expect(s.hints.toSet(), {const Point(2, 2), const Point(6, 2)});
  });

  test('reachable lines exclude the user\'s bad moves', () {
    final s = session();
    expect(s.reachableLeaves, hasLength(2));
  });

  test('opponent mistakes are played when the rate is 1', () {
    const tree = '(;SZ[9];B[ee](;W[cc])(;W[gg]BM[1]))';
    final s = TrainerSession(
      root: parseSgf(tree),
      size: 9,
      color: Stone.black,
      options: const TrainerOptions(
        opponentDelay: Duration.zero,
        autoNext: false,
        opponentMistakeRate: 1,
      ),
    );
    s.userPlay(const Point(4, 4));
    expect(s.current.movePoint(9), const Point(6, 6));
    expect(s.lineDone, isTrue);
  });

  test('unvisited lines are preferred', () {
    const tree = '(;SZ[9];B[ee](;W[cc])(;W[gg])(;W[cg]))';
    final s = TrainerSession(
      root: parseSgf(tree),
      size: 9,
      color: Stone.black,
      options: _instant,
      random: Random(3),
    );
    final seen = <Point?>{};
    for (var i = 0; i < 3; i++) {
      s.userPlay(const Point(4, 4));
      seen.add(s.current.movePoint(9));
      s.nextLine();
    }
    expect(seen, hasLength(3));
  });

  // Long trunk, then a branch where White chooses.
  const trunk =
      '(;SZ[9];B[ee];W[cc];B[gg];W[cg];B[gc]'
      '(;W[ec];B[ce])(;W[ge];B[eg]))';

  TrainerSession branchSession(int seed, {Duration replay = Duration.zero}) =>
      TrainerSession(
        root: parseSgf(trunk),
        size: 9,
        color: Stone.black,
        options: TrainerOptions(
          opponentDelay: Duration.zero,
          autoNext: false,
          start: StartPoint.randomBranch,
          replayDelay: replay,
        ),
        random: Random(seed),
      );

  void playLine(TrainerSession s) {
    while (s.userToMove) {
      s.showHint();
      s.userPlay(s.hints.first);
    }
  }

  test('random branch start only after the branch was reached', () {
    final starts = <int>{};
    for (var seed = 0; seed < 30; seed++) {
      final s = branchSession(seed);
      expect(s.skippedMoves, 0, reason: 'nothing played yet');
      playLine(s);
      expect(s.lineDone, isTrue);
      s.nextLine();
      starts.add(s.skippedMoves);
      expect(s.userToMove, isTrue, reason: 'user always has a move to find');
      s.dispose();
    }
    expect(starts, containsAll([0, 5]));
  });

  test('random start replays the moves one by one', () async {
    for (var seed = 0; seed < 30; seed++) {
      final s = branchSession(seed, replay: const Duration(milliseconds: 5));
      playLine(s);
      s.nextLine();
      if (s.skippedMoves == 0) {
        s.dispose();
        continue;
      }
      expect(s.replaying, isTrue);
      expect(s.userToMove, isFalse);
      final seen = <int>{};
      s.addListener(() => seen.add(s.current.moveNumber));
      while (s.replaying) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(seen, containsAll([1, 2, 3, 4, 5]));
      expect(s.userToMove, isTrue);
      s.dispose();
      return;
    }
    fail('no random start found');
  });

  test('next line starts automatically', () async {
    const tree = '(;SZ[9];B[ee](;W[cc])(;W[gg]))';
    final s = TrainerSession(
      root: parseSgf(tree),
      size: 9,
      color: Stone.black,
      options: const TrainerOptions(
        opponentDelay: Duration.zero,
        autoNextDelay: Duration(milliseconds: 10),
      ),
    );
    s.userPlay(const Point(4, 4));
    expect(s.lineDone, isTrue);
    expect(s.autoNextPending, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(s.lineDone, isFalse);
    expect(s.userToMove, isTrue);
    s.dispose();
  });

  test('training from a chosen branch stays in that branch', () {
    final root = parseSgf(trunk);
    // The "W[ge]" variation after move 5.
    final branch = root.descendants.firstWhere((n) => n.get('W') == 'ge');
    for (var seed = 0; seed < 10; seed++) {
      final s = TrainerSession(
        root: root,
        size: 9,
        color: Stone.black,
        options: _instant,
        branch: branch,
        random: Random(seed),
      );
      expect(s.current, branch, reason: 'starts at the branch');
      expect(s.reachableLeaves.length, 1);
      playLine(s);
      expect(s.lineDone, isTrue);
      expect(s.current.get('B'), 'eg');
      s.setBranch(null);
      expect(s.reachableLeaves.length, 2);
      expect(s.skippedMoves, 0);
      s.dispose();
    }
  });

  test('an opponent mistake from the tree is remembered for the line', () {
    // Black repertoire; White's W[gg] is marked bad.
    const tree = '(;SZ[9];B[ee](;W[gg]BM[1]C[Too far];B[gc])(;W[cc];B[cg]))';
    final s = TrainerSession(
      root: parseSgf(tree),
      size: 9,
      color: Stone.black,
      options: const TrainerOptions(
        opponentDelay: Duration.zero,
        autoNext: false,
        replayDelay: Duration.zero,
        opponentMistakeRate: 1,
      ),
      random: Random(1),
    );
    s.userPlay(const Point(4, 4));
    expect(s.opponentMistake?.get('C'), 'Too far');
    s.userPlay(const Point(6, 2)); // the punishing move
    expect(s.opponentMistake, isNull, reason: 'only shown until answered');
    s.nextLine();
    expect(s.opponentMistake, isNull);
    s.dispose();
  });
}
