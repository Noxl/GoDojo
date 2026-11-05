import 'package:flutter_test/flutter_test.dart';
import 'package:go_opener/go/board.dart';
import 'package:go_opener/go/point.dart';
import 'package:go_opener/go/stone.dart';
import 'package:go_opener/model/annotations.dart';
import 'package:go_opener/model/opening_document.dart';
import 'package:go_opener/sgf/sgf.dart';
import 'package:go_opener/sgf/sgf_node.dart';
import 'package:go_opener/ui/tree_view.dart';

void main() {
  group('SGF', () {
    test('parses moves, variations, escapes and compressed points', () {
      final root = parseSgf(
        '(;GM[1]FF[4]SZ[19]GN[Test]AB[aa:bb]C[a \\] b\\\\]'
        ';B[pd];W[dp](;B[pp]TE[1])(;B[dd]BM[1]C[slow]))',
      );
      expect(root.get('GN'), 'Test');
      expect(root.getAll('AB'), ['aa', 'ab', 'ba', 'bb']);
      expect(root.get('C'), r'a ] b\');
      final w = root.children.single.children.single;
      expect(w.moveColor, Stone.white);
      expect(w.movePoint(19), const Point(3, 15));
      expect(w.children, hasLength(2));
      expect(MoveQuality.of(w.children[0]), MoveQuality.good);
      expect(MoveQuality.of(w.children[1]), MoveQuality.bad);
    });

    test('round-trips through the writer', () {
      const text =
          '(;GM[1]SZ[9]C[x\\]y];B[ee](;W[cc]C[two\nlines])(;W[gg]LB[cc:A]))';
      final again = writeSgf(parseSgf(writeSgf(parseSgf(text))));
      expect(again, writeSgf(parseSgf(text)));
      final root = parseSgf(again);
      expect(root.get('C'), 'x]y');
      expect(root.children.single.children[0].get('C'), 'two\nlines');
      expect(root.children.single.children[1].getAll('LB'), ['cc:A']);
    });

    test('accepts FF3 long property names and passes', () {
      final root = parseSgf('(;AddBlack[dd];W[])');
      expect(root.getAll('AB'), ['dd']);
      expect(root.children.single.isPass, isTrue);
    });
  });

  group('Board', () {
    test('captures and ko', () {
      final b = Board(9);
      // Build a ko shape.
      for (final (x, y, c) in [
        (1, 0, Stone.black),
        (0, 1, Stone.black),
        (1, 2, Stone.black),
        (2, 0, Stone.white),
        (3, 1, Stone.white),
        (2, 2, Stone.white),
        (2, 1, Stone.black),
      ]) {
        b[Point(x, y)] = c;
      }
      expect(b.play(const Point(1, 1), Stone.white), MoveResult.ok);
      expect(b[const Point(2, 1)], Stone.empty);
      expect(b.captures[Stone.white], 1);
      expect(b.play(const Point(2, 1), Stone.black), MoveResult.ko);
    });

    test('suicide is illegal', () {
      final b = Board(9)
        ..[const Point(1, 0)] = Stone.black
        ..[const Point(0, 1)] = Stone.black;
      expect(b.play(const Point(0, 0), Stone.white), MoveResult.suicide);
    });
  });

  group('OpeningDocument', () {
    test('play creates variations and reuses existing moves', () {
      final doc = OpeningDocument.create(
        name: 'T',
        size: 19,
        color: Stone.white,
      );
      doc.play(const Point(15, 3));
      doc.back();
      doc.play(const Point(3, 3));
      doc.back();
      doc.play(const Point(15, 3)); // existing
      expect(doc.root.children, hasLength(2));
      expect(doc.current, doc.root.children.first);
      expect(doc.toPlay, Stone.white);
    });

    test('undo / redo / reorder / rename / delete', () {
      final doc = OpeningDocument.create(
        name: 'T',
        size: 9,
        color: Stone.black,
      );
      doc.play(const Point(4, 4));
      doc.back();
      doc.play(const Point(2, 2));
      final second = doc.current;
      expect(second.variationStart, second);
      expect(second.variationNumber, 2);
      doc.renameVariation(second, 'Komoku');
      expect(second.variationLabel, '2 Komoku');
      doc.undo();
      expect(doc.current.variationName, isNull);
      doc.redo();
      doc.moveVariation(-1);
      expect(doc.root.children.first.movePoint(9), const Point(2, 2));
      expect(doc.root.children.first.variationLabel, '1 Komoku');
      doc.undo();
      expect(doc.root.children.first.movePoint(9), const Point(4, 4));
      doc.redo();
      expect(doc.root.children.first.movePoint(9), const Point(2, 2));
      doc.deleteNode();
      expect(doc.root.children, hasLength(1));
      expect(doc.current, doc.root);
    });

    test('setup stones, markup, labels and annotations', () {
      final doc = OpeningDocument.create(
        name: 'T',
        size: 9,
        color: Stone.black,
      );
      doc.setupStone(const Point(2, 2), Stone.black);
      expect(doc.board[const Point(2, 2)], Stone.black);
      doc.setupStone(const Point(2, 2), Stone.black); // toggle off
      expect(doc.board[const Point(2, 2)], Stone.empty);
      doc.toggleMarkup(const Point(1, 1), MarkupShape.cross);
      doc.toggleLabel(const Point(3, 3));
      doc.toggleLabel(const Point(4, 3));
      expect(doc.labelsOf(doc.root).values, ['A', 'B']);
      doc.play(const Point(4, 4));
      doc.setMoveQuality(MoveQuality.bad);
      doc.setComment('Too slow');
      final again = parseSgf(doc.toSgf());
      expect(again.getAll('MA'), ['bb']);
      expect(again.children.single.has('BM'), isTrue);
      expect(again.children.single.get('C'), 'Too slow');
      expect(again.get(kOpeningColorProp), 'B');
    });
  });

  test('any move can be named, even without siblings', () {
    final doc = OpeningDocument.create(name: 'T', size: 9, color: Stone.black);
    doc.play(const Point(4, 4));
    doc.play(const Point(2, 2));
    final only = doc.current;
    doc.renameVariation(only, 'Approach');
    expect(only.get('N'), 'Approach');
    expect(only.variationNumber, 1);
    expect(only.variationLabel, 'Approach');
    expect(
      parseSgf(doc.toSgf()).children.single.children.single.get('N'),
      'Approach',
    );
  });

  test('tree layout puts variations on separate rows', () {
    final root = parseSgf('(;SZ[9];B[ee](;W[cc];B[gg])(;W[gg];B[cc])(;W[cg]))');
    final l = TreeLayout(root);
    final rows = {
      for (final n in [root, ...root.descendants]) l.pos[n],
    };
    expect(rows.length, 1 + root.descendants.length, reason: 'no overlap');
    expect(l.rows, 3);
  });

  test('tree layout handles huge trees quickly', () {
    // ~20k nodes: a branch every 3 moves, 4 levels deep, long lines.
    final root = SgfNode();
    var count = 0;
    void grow(SgfNode n, int depth) {
      var cur = n;
      for (var i = 0; i < 40; i++) {
        final child = SgfNode()
          ..setMove(i.isEven ? Stone.black : Stone.white, Point(i % 19, depth));
        cur.addChild(child);
        cur = child;
        count++;
        if (depth < 3 && i % 3 == 0) grow(cur, depth + 1);
      }
    }

    grow(root, 0);
    final sw = Stopwatch()..start();
    final l = TreeLayout(root);
    sw.stop();
    expect(l.pos.length, count + 1);
    expect(l.cells.length, l.pos.length, reason: 'no two nodes share a cell');
    expect(sw.elapsedMilliseconds, lessThan(1000));
  });

  test('joseki: start position, first player and kind survive saving', () {
    final doc = OpeningDocument.create(
      name: 'J',
      size: 19,
      kind: DocumentKind.joseki,
    );
    expect(doc.hasStartPosition, isTrue);
    expect(doc.root.get(kOpeningColorProp), isNull);
    doc.setStartStone(const Point(15, 3), Stone.black);
    doc.setStartStone(const Point(16, 2), Stone.white);
    doc.setStartStone(const Point(16, 2), Stone.white); // toggles off
    doc.setStartStone(const Point(13, 2), Stone.white);
    doc.setFirstToPlay(Stone.white);
    expect(doc.board[const Point(15, 3)], Stone.black);
    expect(doc.board[const Point(16, 2)], Stone.empty);
    expect(doc.toPlay, Stone.white);
    doc.play(const Point(16, 5));
    expect(doc.current.moveColor, Stone.white);

    final reloaded = OpeningDocument.fromSgf(doc.toSgf());
    expect(reloaded.hasStartPosition, isTrue);
    expect(reloaded.firstToPlay, Stone.white);
    expect(reloaded.board[const Point(13, 2)], Stone.white);
    expect(OpeningDocument.fromSgf('(;SZ[19])').kind, DocumentKind.opening);
  });

  test('tricks are a kind of their own, with a start position', () {
    final doc = OpeningDocument.create(
      name: 'T',
      size: 19,
      kind: DocumentKind.tricks,
    );
    expect(doc.hasStartPosition, isTrue);
    final reloaded = OpeningDocument.fromSgf(doc.toSgf());
    expect(reloaded.kind, DocumentKind.tricks);
    expect(reloaded.root.get(kOpeningColorProp), isNull);
  });

  test('old Doubtful marks count as Bad', () {
    final root = parseSgf('(;SZ[9];B[ee]DO[])');
    expect(MoveQuality.of(root.children.single), MoveQuality.bad);
  });
}
