/// A board intersection. (0,0) is the top-left corner, as in SGF.
class Point {
  const Point(this.x, this.y);

  final int x;
  final int y;

  static const _letters = 'abcdefghijklmnopqrstuvwxyz';
  // Go coordinates skip the letter I.
  static const _goLetters = 'ABCDEFGHJKLMNOPQRSTUVWXYZ';

  /// Parses an SGF coordinate such as "pd". Returns null for passes
  /// ("" or "tt" on boards up to 19x19) and invalid values.
  static Point? fromSgf(String s, int boardSize) {
    if (s.length != 2) return null;
    final x = _letters.indexOf(s[0]);
    final y = _letters.indexOf(s[1]);
    if (x < 0 || y < 0 || x >= boardSize || y >= boardSize) return null;
    return Point(x, y);
  }

  String get sgf => '${_letters[x]}${_letters[y]}';

  /// Human readable coordinate such as "Q16".
  String display(int boardSize) => '${_goLetters[x]}${boardSize - y}';

  bool isOnBoard(int size) => x >= 0 && y >= 0 && x < size && y < size;

  Iterable<Point> neighbors(int size) sync* {
    if (x > 0) yield Point(x - 1, y);
    if (x < size - 1) yield Point(x + 1, y);
    if (y > 0) yield Point(x, y - 1);
    if (y < size - 1) yield Point(x, y + 1);
  }

  @override
  bool operator ==(Object other) =>
      other is Point && other.x == x && other.y == y;

  @override
  int get hashCode => x * 64 + y;

  @override
  String toString() => 'Point($x, $y)';
}
