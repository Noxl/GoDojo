import 'package:flutter_test/flutter_test.dart';
import 'package:go_dojo/analysis/katago.dart';
import 'package:go_dojo/go/point.dart';
import 'package:go_dojo/go/stone.dart';
import 'package:go_dojo/sgf/sgf.dart';

void main() {
  test('GTP coordinates', () {
    expect(parseGtpPoint('Q16', 19), const Point(15, 3));
    expect(parseGtpPoint('A1', 19), const Point(0, 18));
    expect(parseGtpPoint('J9', 9), const Point(8, 0));
    expect(parseGtpPoint('pass', 19), isNull);
  });

  test('query from a plain game', () {
    final root = parseSgf('(;SZ[19]KM[7.5];B[pd];W[dp];B[pp])');
    final node = root.children.single.children.single.children.single;
    final q = AnalysisQuery.at(node, 19);
    final json = q.toJson('x', 100);
    expect(json['moves'], [
      ['B', 'Q16'],
      ['W', 'D4'],
      ['B', 'Q4'],
    ]);
    expect(json['initialStones'], isEmpty);
    expect(json['komi'], 7.5);
    expect(q.toMove, Stone.white);
  });

  test('setup stones become initial stones', () {
    final root = parseSgf('(;SZ[9]AB[cc][gg];W[ee];B[cg])');
    final node = root.children.single.children.single;
    final q = AnalysisQuery.at(node, 9);
    expect(q.initialStones.length, 2);
    expect(q.initialPlayer, Stone.white);
    expect(q.toJson('x', 10)['moves'], [
      ['W', 'E5'],
      ['B', 'C3'],
    ]);
    expect(q.key, isNot(AnalysisQuery.at(root, 9).key));
  });

  test('move loss uses the candidate list, else the position after', () {
    const before = PositionAnalysis(
      toMove: Stone.black,
      winrate: 0.5,
      scoreLead: 1,
      visits: 100,
      complete: true,
      moves: [
        MoveAnalysis(
          point: Point(15, 3),
          visits: 60,
          winrate: 0.5,
          scoreLead: 1.0,
          order: 0,
          pv: [],
        ),
        MoveAnalysis(
          point: Point(3, 15),
          visits: 30,
          winrate: 0.45,
          scoreLead: -0.5,
          order: 1,
          pv: [],
        ),
      ],
    );
    final root = parseSgf('(;SZ[19](;B[dp])(;B[aa]))');
    final good = root.children[0];
    final bad = root.children[1];
    expect(moveLoss(good, 19, before, null), closeTo(1.5, 1e-9));
    expect(moveLoss(bad, 19, before, null), isNull);
    const after = PositionAnalysis(
      toMove: Stone.white,
      winrate: 0.7,
      scoreLead: 4,
      visits: 50,
      complete: true,
      moves: [],
    );
    expect(moveLoss(bad, 19, before, after), closeTo(5, 1e-9));
  });
}
