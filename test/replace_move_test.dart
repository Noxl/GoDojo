import 'package:flutter_test/flutter_test.dart';
import 'package:go_dojo/go/board.dart';
import 'package:go_dojo/go/point.dart';
import 'package:go_dojo/go/stone.dart';
import 'package:go_dojo/model/opening_document.dart';

void main() {
  OpeningDocument line() {
    final d = OpeningDocument.create(name: 'T', size: 9);
    d.play(const Point(2, 2)); // B
    d.play(const Point(6, 6)); // W
    d.play(const Point(2, 6)); // B
    d.play(const Point(6, 2)); // W
    return d;
  }

  test('a move changes place and the moves after it stay', () {
    final d = line();
    final second = d.root.children.single.children.single;
    final (r, broken) = d.replaceMove(const Point(5, 5), second);
    expect(r, MoveResult.ok);
    expect(broken, 0);
    expect(second.movePoint(9), const Point(5, 5));
    expect(second.moveColor, Stone.white);
    expect(second.descendants.where((n) => n.hasMove).length, 2);
    expect(d.root.leaves.single.movePoint(9), const Point(6, 2));
    d.undo();
    expect(
      d.root.children.single.children.single.movePoint(9),
      const Point(6, 6),
    );
  });

  test('a later move on the new place is reported', () {
    final d = line();
    final second = d.root.children.single.children.single;
    // Move 3 (black) is played at (2, 6): putting move 2 there breaks it.
    final (r, broken) = d.replaceMove(const Point(2, 6), second);
    expect(r, MoveResult.ok);
    expect(broken, 1);
  });

  test('an occupied point or an existing variation is refused', () {
    final d = line();
    final second = d.root.children.single.children.single;
    expect(d.replaceMove(const Point(2, 2), second).$1, MoveResult.occupied);
    d.goTo(d.root.children.single);
    d.play(const Point(4, 4)); // a second white answer
    expect(d.replaceMove(const Point(4, 4), second).$1, MoveResult.occupied);
  });

  test('a move becomes a tenuki and back, the moves after it stay', () {
    final d = line();
    final second = d.root.children.single.children.single;
    expect(d.replaceMove(null, second), (MoveResult.ok, 0));
    expect(second.isPass, isTrue);
    expect(second.moveColor, Stone.white);
    expect(second.descendants.where((n) => n.hasMove).length, 2);
    expect(d.replaceMove(const Point(6, 6), second), (MoveResult.ok, 0));
    expect(second.movePoint(9), const Point(6, 6));
  });
}
