import 'point.dart';
import 'stone.dart';

enum MoveResult { ok, occupied, suicide, ko, offBoard }

/// A Go position with capture and simple-ko handling.
class Board {
  Board(this.size)
    : _cells = List.filled(size * size, Stone.empty),
      captures = {Stone.black: 0, Stone.white: 0};

  Board._copy(Board o)
    : size = o.size,
      _cells = List.of(o._cells),
      koPoint = o.koPoint,
      captures = Map.of(o.captures);

  final int size;
  final List<Stone> _cells;

  /// Point that cannot be retaken immediately (simple ko), if any.
  Point? koPoint;

  /// Number of stones captured *by* each color.
  final Map<Stone, int> captures;

  Board copy() => Board._copy(this);

  Stone operator [](Point p) => _cells[p.y * size + p.x];
  void operator []=(Point p, Stone s) => _cells[p.y * size + p.x] = s;

  Iterable<Point> get points sync* {
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        yield Point(x, y);
      }
    }
  }

  /// Star points (hoshi) for the standard board sizes.
  List<Point> get starPoints {
    final edge = size >= 13 ? 3 : 2;
    final far = size - 1 - edge;
    final mid = size ~/ 2;
    final pts = [
      Point(edge, edge),
      Point(far, edge),
      Point(edge, far),
      Point(far, far),
    ];
    if (size.isOdd) {
      pts.add(Point(mid, mid));
      if (size >= 15) {
        pts.addAll([
          Point(mid, edge),
          Point(mid, far),
          Point(edge, mid),
          Point(far, mid),
        ]);
      }
    }
    return size < 7 ? const [] : pts;
  }

  /// Returns the group containing [p] and its liberties.
  (Set<Point>, Set<Point>) groupAt(Point p) {
    final color = this[p];
    final group = <Point>{p};
    final liberties = <Point>{};
    final stack = [p];
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      for (final n in cur.neighbors(size)) {
        final s = this[n];
        if (s == Stone.empty) {
          liberties.add(n);
        } else if (s == color && group.add(n)) {
          stack.add(n);
        }
      }
    }
    return (group, liberties);
  }

  /// Checks whether [color] may legally play at [p] without modifying the board.
  MoveResult check(Point p, Stone color) {
    if (!p.isOnBoard(size)) return MoveResult.offBoard;
    if (this[p] != Stone.empty) return MoveResult.occupied;
    if (p == koPoint) return MoveResult.ko;
    final test = copy();
    test._place(p, color);
    if (test[p] == Stone.empty) return MoveResult.suicide;
    return MoveResult.ok;
  }

  /// Plays a move after checking legality. The board is unchanged unless
  /// the result is [MoveResult.ok].
  MoveResult play(Point p, Stone color) {
    final r = check(p, color);
    if (r == MoveResult.ok) _place(p, color);
    return r;
  }

  /// Plays a move without legality checks (used when replaying SGF files,
  /// which may contain anything). Captures are still resolved.
  void forcePlay(Point? p, Stone color) {
    if (p == null) {
      koPoint = null; // pass
      return;
    }
    if (!p.isOnBoard(size)) return;
    _place(p, color);
  }

  void _place(Point p, Stone color) {
    this[p] = color;
    final opp = color.opponent;
    final captured = <Point>{};
    for (final n in p.neighbors(size)) {
      if (this[n] == opp) {
        final (group, libs) = groupAt(n);
        if (libs.isEmpty) captured.addAll(group);
      }
    }
    for (final c in captured) {
      this[c] = Stone.empty;
    }
    captures[color] = captures[color]! + captured.length;

    // Suicide: remove own group if it has no liberties left.
    final (own, ownLibs) = groupAt(p);
    if (ownLibs.isEmpty) {
      for (final c in own) {
        this[c] = Stone.empty;
      }
      captures[opp] = captures[opp]! + own.length;
    }

    // Simple ko: a single stone captured a single stone and is in atari.
    koPoint = null;
    if (captured.length == 1 && own.length == 1 && ownLibs.length == 1) {
      koPoint = captured.first;
    }
  }
}
