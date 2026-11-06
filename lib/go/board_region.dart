import 'dart:math' as math;

import '../sgf/sgf_node.dart';
import 'point.dart';

/// A rectangle of the board (inclusive bounds), shown zoomed in.
class BoardRegion {
  const BoardRegion(this.x0, this.y0, this.x1, this.y1);

  final int x0, y0, x1, y1;

  int get columns => x1 - x0 + 1;
  int get rows => y1 - y0 + 1;

  bool contains(Point p) => p.x >= x0 && p.x <= x1 && p.y >= y0 && p.y <= y1;

  /// The smallest view that shows every stone of [points] with a line of
  /// room around them. A side near the edge of the board goes to the edge
  /// (the edge matters in Go). Never taller than wide, so a phone screen
  /// does not need more height than for the whole board. Null when it
  /// would be (nearly) the whole board.
  static BoardRegion? around(Iterable<Point> points, int size) {
    if (points.isEmpty || size < 9) return null;
    var x0 = size, y0 = size, x1 = -1, y1 = -1;
    for (final p in points) {
      x0 = math.min(x0, p.x);
      y0 = math.min(y0, p.y);
      x1 = math.max(x1, p.x);
      y1 = math.max(y1, p.y);
    }
    // A line of room, and the edge when it is close.
    const room = 1, snap = 3;
    int low(int v) => v - room <= snap ? 0 : v - room;
    int high(int v) => v + room >= size - 1 - snap ? size - 1 : v + room;
    x0 = low(x0);
    y0 = low(y0);
    x1 = high(x1);
    y1 = high(y1);

    // Not too small (a joseki of three stones stays readable).
    const minSide = 7;
    (x0, x1) = _grow(x0, x1, minSide, size);
    (y0, y1) = _grow(y0, y1, minSide, size);
    // Not taller than wide.
    if (y1 - y0 > x1 - x0) (x0, x1) = _grow(x0, x1, y1 - y0 + 1, size);

    final r = BoardRegion(x0, y0, x1, y1);
    // Little to gain: the whole board.
    if (r.columns * r.rows >= size * size * 0.85) return null;
    return r;
  }

  /// Widens [lo]..[hi] to [length] points, away from the edge of the board.
  static (int, int) _grow(int lo, int hi, int length, int size) {
    while (hi - lo + 1 < length && (lo > 0 || hi < size - 1)) {
      // Grow on the side with more board left (the open side).
      if (hi < size - 1 && (lo == 0 || size - 1 - hi >= lo)) {
        hi++;
      } else {
        lo--;
      }
    }
    return (lo, hi);
  }

  @override
  bool operator ==(Object other) =>
      other is BoardRegion &&
      other.x0 == x0 &&
      other.y0 == y0 &&
      other.x1 == x1 &&
      other.y1 == y1;

  @override
  int get hashCode => Object.hash(x0, y0, x1, y1);

  @override
  String toString() => 'BoardRegion($x0,$y0 – $x1,$y1)';
}

/// The part of the board a joseki uses: every move of every line of the
/// tree of [root], with the stones of the start position
/// that are near them. Stones far away (other corners, given as context)
/// are left out, and so are lone moves far from the rest (a move played
/// elsewhere) — unless [at] is given: then the moves played to reach it,
/// and the moves that can follow it, are always in the view (the view
/// grows when the line goes there). Null: the whole board.
BoardRegion? josekiRegion(SgfNode root, int size, {SgfNode? at}) {
  final setup = <Point>{};
  final moves = <Point>{};
  void add(Set<Point> out, String v) {
    // "pd", "pd:A" (label), or "pd:qe" (a rectangle of points).
    final parts = v.split(':');
    final a = Point.fromSgf(parts.first, size);
    if (a == null) return;
    out.add(a);
    if (parts.length > 1 && parts[1].length == 2) {
      final b = Point.fromSgf(parts[1], size);
      if (b != null) out.add(b);
    }
  }

  for (final n in [root, ...root.descendants]) {
    for (final id in const ['B', 'W']) {
      for (final v in n.getAll(id)) {
        add(moves, v);
      }
    }
    for (final id in const ['AB', 'AW']) {
      for (final v in n.getAll(id)) {
        add(n == root ? setup : moves, v);
      }
    }
  }
  if (moves.isEmpty) return BoardRegion.around(setup, size);

  // Lone moves (nothing else within a few lines) are not the joseki.
  int dist(Point a, Point b) => math.max((a.x - b.x).abs(), (a.y - b.y).abs());
  const alone = 3;
  final core = moves
      .where((p) => moves.any((q) => q != p && dist(p, q) <= alone))
      .toList();
  if (core.isEmpty) core.addAll(moves);

  // The start position near the moves (a few lines away at most).
  const near = 3;
  final xs = core.map((p) => p.x), ys = core.map((p) => p.y);
  final x0 = xs.reduce(math.min) - near, x1 = xs.reduce(math.max) + near;
  final y0 = ys.reduce(math.min) - near, y1 = ys.reduce(math.max) + near;
  final shown = [
    ...core,
    ...setup.where((p) => p.x >= x0 && p.x <= x1 && p.y >= y0 && p.y <= y1),
  ];

  // The line being played: its moves and the next ones.
  if (at != null) {
    // Its marks and labels, too.
    final marks = <Point>{};
    for (final id in const ['TR', 'SQ', 'CR', 'MA', 'LB']) {
      for (final v in at.getAll(id)) {
        add(marks, v);
      }
    }
    shown.addAll(marks);
    for (SgfNode? n = at; n != null; n = n.parent) {
      if (n.movePoint(size) case final p?) shown.add(p);
    }
    for (final c in at.children) {
      if (c.movePoint(size) case final p?) shown.add(p);
    }
  }
  return BoardRegion.around(shown, size);
}
