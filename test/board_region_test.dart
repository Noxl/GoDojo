import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_dojo/go/board_region.dart';
import 'package:go_dojo/go/point.dart';
import 'package:go_dojo/sgf/sgf.dart';

void main() {
  test('a corner joseki: zoomed on its corner, edges included, square', () {
    final root = parseSgf(
      File('assets/starter/44 approach.sgf').readAsStringSync(),
    );
    final r = josekiRegion(root, 19)!;
    for (final n in [root, ...root.descendants]) {
      final p = n.movePoint(19);
      if (p != null) expect(r.contains(p), isTrue, reason: '$p');
    }
    expect(r.contains(Point(15, 3)), isTrue); // A start stone (pd).
    expect(r.y0, 0);
    expect(r.x1, 18);
    expect(r.columns, greaterThanOrEqualTo(r.rows));
    expect(r.columns * r.rows, lessThan(19 * 19 / 2));
  });

  test('start stones far from the moves (other corners) are left out', () {
    final root = parseSgf('(;SZ[19]AB[pd][dp]AW[dd];W[qc];B[qd];W[rd])');
    final r = josekiRegion(root, 19)!;
    expect(r.contains(Point(15, 3)), isTrue);
    expect(r.contains(Point(3, 3)), isFalse);
    expect(r.contains(Point(3, 15)), isFalse);
  });

  test('a lone move far away: out of the view until the line goes there', () {
    final root = parseSgf('(;SZ[19]AB[pd];W[qc];B[qd];W[rd];B[re];W[dp])');
    final far = Point(3, 15);
    expect(josekiRegion(root, 19)!.contains(far), isFalse);
    final last = root.leaves.single;
    expect(josekiRegion(root, 19, at: last.parent), isNull); // Next: dp.
    expect(
      josekiRegion(root, 19, at: root.children.single)!.contains(far),
      isFalse,
    );
  });

  test('a few stones: still a readable corner', () {
    final r = BoardRegion.around([Point(15, 3), Point(16, 5)], 19)!;
    expect(r.contains(Point(15, 3)) && r.contains(Point(16, 5)), isTrue);
    expect((r.x1, r.y0), (18, 0));
    expect(r.columns, greaterThanOrEqualTo(7));
    expect(r.rows, greaterThanOrEqualTo(7));
  });

  test('stones all over the board: the whole board', () {
    expect(BoardRegion.around([Point(3, 3), Point(15, 15)], 19), isNull);
    expect(BoardRegion.around(const [], 19), isNull);
  });

  test('a tall region is made as wide as it is tall', () {
    final r = BoardRegion.around([Point(16, 3), Point(16, 12)], 19)!;
    expect(r.columns, r.rows);
  });
}
