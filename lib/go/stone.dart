enum Stone {
  empty,
  black,
  white;

  Stone get opponent => switch (this) {
    Stone.black => Stone.white,
    Stone.white => Stone.black,
    Stone.empty => Stone.empty,
  };

  /// SGF property id for a move of this color ("B" / "W").
  String get sgf => this == Stone.white ? 'W' : 'B';

  String get label => switch (this) {
    Stone.black => 'Black',
    Stone.white => 'White',
    Stone.empty => 'None',
  };

  static Stone? fromSgf(String? v) => switch (v) {
    'B' => Stone.black,
    'W' => Stone.white,
    _ => null,
  };
}
