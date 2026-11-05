import 'package:flutter/foundation.dart';

import '../go/board.dart';
import '../go/point.dart';
import '../go/stone.dart';
import '../sgf/sgf.dart';
import '../sgf/sgf_node.dart';
import 'annotations.dart';
import '../storage/storage.dart';

/// Root property used to store which color the opening is studied for.
/// It is not part of the SGF standard, but unknown properties are preserved
/// by other SGF editors.
const kOpeningColorProp = 'OC';

/// Root property telling whether the file is an opening or a joseki.
const kKindProp = 'GK';

enum DocumentKind {
  opening('Opening', 'Openings'),
  joseki('Joseki', 'Joseki'),
  tricks('Trick', 'Tricks');

  const DocumentKind(this.label, this.plural);
  final String label;
  final String plural;

  /// Joseki and tricks start from a position set up by the user, and the
  /// color is chosen when training.
  bool get hasStartPosition => this != opening;

  static DocumentKind of(SgfNode root) => switch (root.get(kKindProp)) {
    'joseki' => joseki,
    'tricks' => tricks,
    _ => opening,
  };
}

const kBoardSizes = [9, 13, 19];

/// Computes the position after [node] by replaying the path from the root.
Board positionAt(SgfNode node, int size) {
  final board = Board(size);
  for (final n in node.pathFromRoot) {
    applyNode(board, n, size);
  }
  return board;
}

/// Applies setup properties (AB/AW/AE) and the move of [n] to [board].
void applyNode(Board board, SgfNode n, int size) {
  for (final (id, stone) in const [
    ('AE', Stone.empty),
    ('AB', Stone.black),
    ('AW', Stone.white),
  ]) {
    for (final v in n.getAll(id)) {
      final p = Point.fromSgf(v, size);
      if (p != null) board[p] = stone;
    }
  }
  final c = n.moveColor;
  if (c != null) board.forcePlay(n.movePoint(size), c);
}

/// The color expected to play after [node].
Stone nextToPlay(SgfNode node) {
  final pl = Stone.fromSgf(node.get('PL'));
  if (pl != null) return pl;
  SgfNode? n = node;
  while (n != null) {
    final c = n.moveColor;
    if (c != null) return c.opponent;
    final pl = Stone.fromSgf(n.get('PL'));
    if (pl != null) return pl;
    n = n.parent;
  }
  // Handicap stones and no moves yet: white plays first.
  final root = node.root;
  if (root.getAll('AB').isNotEmpty && root.getAll('AW').isEmpty) {
    return Stone.white;
  }
  return Stone.black;
}

/// An opening being edited: an SGF tree, a cursor and undo history.
class OpeningDocument extends ChangeNotifier {
  OpeningDocument._(this._root, {this.filePath}) : _current = _root {
    _boardCache = positionAt(_current, size);
  }

  /// A new opening studied as [color], or a joseki (no color: the side is
  /// chosen when training) whose start position is edited by the user.
  factory OpeningDocument.create({
    required String name,
    required int size,
    Stone color = Stone.black,
    DocumentKind kind = DocumentKind.opening,
  }) {
    final root = SgfNode()
      ..set('GM', '1')
      ..set('FF', '4')
      ..set('CA', 'UTF-8')
      ..set('AP', 'GoDojo:1.0')
      ..set('SZ', '$size')
      ..set('GN', name);
    if (kind.hasStartPosition) {
      root
        ..set(kKindProp, kind.name)
        ..set('PL', 'B');
    } else {
      root.set(kOpeningColorProp, color.sgf);
    }
    return OpeningDocument._(root).._dirty = true;
  }

  factory OpeningDocument.fromSgf(String text, {String? filePath}) {
    return OpeningDocument._(parseSgf(text), filePath: filePath);
  }

  static Future<OpeningDocument> load(String path) async {
    final text = await storage.read(path);
    return OpeningDocument.fromSgf(text, filePath: path);
  }

  SgfNode _root;
  SgfNode _current;
  late Board _boardCache;
  String? filePath;
  bool _dirty = false;

  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];

  SgfNode get root => _root;
  SgfNode get current => _current;
  Board get board => _boardCache;
  bool get dirty => _dirty;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  // ------------------------------------------------------------ metadata

  int get size {
    final v = int.tryParse((_root.get('SZ') ?? '19').split(':').first);
    return (v == null || v < 2 || v > 25) ? 19 : v;
  }

  String get name => _root.get('GN') ?? 'Untitled ${kind.label.toLowerCase()}';

  DocumentKind get kind => DocumentKind.of(_root);
  bool get hasStartPosition => kind.hasStartPosition;

  /// The color the user studies this opening for.
  Stone get color => Stone.fromSgf(_root.get(kOpeningColorProp)) ?? Stone.black;

  /// True if the tree contains anything besides the root.
  bool get hasMoves =>
      _root.children.isNotEmpty ||
      _root.getAll('AB').isNotEmpty ||
      _root.getAll('AW').isNotEmpty;

  void setName(String v) => _mutate(() => _root.set('GN', v), coalesce: 'GN');

  void setColor(Stone c) => _mutate(() => _root.set(kOpeningColorProp, c.sgf));

  /// Changing the size is only allowed while the board is empty.
  bool setSize(int s) {
    if (hasMoves) return false;
    _mutate(() => _root.set('SZ', '$s'));
    return true;
  }

  // ------------------------------------------------------ start position

  /// The stones of the start position (setup of the root).
  bool get hasStartStones =>
      _root.getAll('AB').isNotEmpty || _root.getAll('AW').isNotEmpty;

  /// Puts [stone] on [p] in the start position, or removes the stone there
  /// if it already has that color ([Stone.empty] always removes).
  void setStartStone(Point p, Stone stone) {
    _mutate(() {
      final had = _root
          .getAll(stone == Stone.white ? 'AW' : 'AB')
          .contains(p.sgf);
      for (final id in const ['AB', 'AW']) {
        _root.setAll(id, _root.getAll(id).where((v) => v != p.sgf).toList());
      }
      if (stone != Stone.empty && !had) {
        final id = stone == Stone.black ? 'AB' : 'AW';
        _root.setAll(id, [..._root.getAll(id), p.sgf]);
      }
    });
  }

  void clearStartPosition() => _mutate(() {
    _root.remove('AB');
    _root.remove('AW');
  });

  /// The color that plays first from the start position.
  Stone get firstToPlay => nextToPlay(_root);

  void setFirstToPlay(Stone c) => _mutate(() => _root.set('PL', c.sgf));

  // ---------------------------------------------------------- navigation

  void goTo(SgfNode node) {
    if (node == _current) return;
    _current = node;
    _refresh();
  }

  void forward() {
    if (_current.children.isNotEmpty) goTo(_current.children.first);
  }

  void back() {
    final p = _current.parent;
    if (p != null) goTo(p);
  }

  void toStart() => goTo(_root);

  void toEnd() {
    var n = _current;
    while (n.children.isNotEmpty) {
      n = n.children.first;
    }
    goTo(n);
  }

  /// Switches to the previous (-1) or next (+1) sibling variation.
  void siblingVariation(int delta) {
    final p = _current.parent;
    if (p == null) return;
    final i = p.children.indexOf(_current) + delta;
    if (i >= 0 && i < p.children.length) goTo(p.children[i]);
  }

  // ------------------------------------------------------------- editing

  Stone get toPlay => nextToPlay(_current);

  /// Plays [p] (or passes when null) for the side to move. Navigates to an
  /// existing child if the move is already in the tree.
  MoveResult play(Point? p, {Stone? color}) {
    final c = color ?? toPlay;
    for (final child in _current.children) {
      if (child.moveColor == c &&
          (p == null ? child.isPass : child.movePoint(size) == p)) {
        goTo(child);
        return MoveResult.ok;
      }
    }
    if (p != null) {
      final r = _boardCache.check(p, c);
      if (r != MoveResult.ok) return r;
    }
    _mutate(() {
      final child = SgfNode()..setMove(c, p);
      _current.addChild(child);
      _current = child;
    });
    return MoveResult.ok;
  }

  /// Adds the moves in [points] as replies after the current position,
  /// without moving there. Existing and illegal moves are skipped.
  /// Returns the number of variations added.
  int addReplies(List<Point> points) {
    final c = toPlay;
    final existing = {
      for (final child in _current.children)
        if (child.moveColor == c) child.movePoint(size),
    };
    final fresh = [
      for (final p in points)
        if (!existing.contains(p) && _boardCache.check(p, c) == MoveResult.ok)
          p,
    ];
    if (fresh.isEmpty) return 0;
    _mutate(() {
      for (final p in fresh) {
        _current.addChild(SgfNode()..setMove(c, p));
      }
    });
    return fresh.length;
  }

  /// Adds/removes a setup stone. [stone] is empty for the erase tool.
  void setupStone(Point p, Stone stone) {
    _mutate(() {
      // Setup properties should not be mixed with moves: use a new node.
      if (_current.hasMove) {
        final child = SgfNode();
        _current.addChild(child);
        _current = child;
      }
      final n = _current;
      final existing = _boardCache[p];
      for (final id in const ['AB', 'AW', 'AE']) {
        n.setAll(id, n.getAll(id).where((v) => v != p.sgf).toList());
      }
      // Clicking a stone of the same color with its tool removes it.
      final target = existing == stone ? Stone.empty : stone;
      if (target == Stone.empty) {
        // Only record AE if the stone came from an earlier node.
        final before = n.parent == null
            ? Board(size)
            : positionAt(n.parent!, size);
        if (before[p] != Stone.empty) {
          n.setAll('AE', [...n.getAll('AE'), p.sgf]);
        }
      } else {
        final id = target == Stone.black ? 'AB' : 'AW';
        n.setAll(id, [...n.getAll(id), p.sgf]);
      }
    });
  }

  /// Toggles a markup shape on [p], replacing any other shape there.
  void toggleMarkup(Point p, MarkupShape shape) {
    _mutate(() {
      final had = _current.getAll(shape.sgfId).contains(p.sgf);
      for (final s in MarkupShape.values) {
        _current.setAll(
          s.sgfId,
          _current.getAll(s.sgfId).where((v) => v != p.sgf).toList(),
        );
      }
      if (!had) {
        _current.setAll(shape.sgfId, [..._current.getAll(shape.sgfId), p.sgf]);
      }
    });
  }

  /// Labels on the current node, keyed by point.
  Map<Point, String> labelsOf(SgfNode n) {
    final out = <Point, String>{};
    for (final v in n.getAll('LB')) {
      final i = v.indexOf(':');
      if (i != 2) continue;
      final p = Point.fromSgf(v.substring(0, 2), size);
      if (p != null) out[p] = v.substring(3);
    }
    return out;
  }

  /// Toggles a label on [p]. With [numeric] the next free number is used,
  /// otherwise the next free capital letter.
  void toggleLabel(Point p, {bool numeric = false}) {
    _mutate(() {
      final labels = labelsOf(_current);
      if (labels.containsKey(p)) {
        labels.remove(p);
      } else {
        labels[p] = _nextLabel(labels.values.toSet(), numeric);
      }
      _current.setAll('LB', [
        for (final e in labels.entries) '${e.key.sgf}:${e.value}',
      ]);
    });
  }

  static String _nextLabel(Set<String> used, bool numeric) {
    if (numeric) {
      var i = 1;
      while (used.contains('$i')) {
        i++;
      }
      return '$i';
    }
    for (var c = 65; c <= 90; c++) {
      final l = String.fromCharCode(c);
      if (!used.contains(l)) return l;
    }
    return '?';
  }

  void clearMarkup() {
    _mutate(() {
      for (final s in MarkupShape.values) {
        _current.remove(s.sgfId);
      }
      _current.remove('LB');
    });
  }

  void setComment(String text) {
    _mutate(() => _current.set('C', text.isEmpty ? null : text), coalesce: 'C');
  }

  void setMoveQuality(MoveQuality q, [SgfNode? node]) =>
      _mutate(() => q.applyTo(node ?? _current));

  void setJudgement(PositionJudgement j) => _mutate(() => j.applyTo(_current));

  /// Puts the move of [node] (the current one by default) on [p] instead,
  /// keeping every move after it. Returns the result and the number of
  /// later moves that are no longer legal (they are kept: fix or delete
  /// them).
  (MoveResult, int) replaceMove(Point p, [SgfNode? node]) {
    final n = node ?? _current;
    final c = n.moveColor;
    final parent = n.parent;
    if (c == null || parent == null) return (MoveResult.offBoard, 0);
    if (n.movePoint(size) == p) return (MoveResult.ok, 0);
    final before = positionAt(parent, size);
    final r = before.check(p, c);
    if (r != MoveResult.ok) return (r, 0);
    // Already a variation from here.
    if (parent.children.any(
      (s) => s.moveColor == c && s.movePoint(size) == p,
    )) {
      return (MoveResult.occupied, 0);
    }
    _mutate(() => n.setMove(c, p));

    // Replay what follows on the new position.
    var broken = 0;
    void walk(SgfNode node, Board board) {
      for (final child in node.children) {
        final b = board.copy();
        final cc = child.moveColor;
        final cp = child.movePoint(size);
        if (cc != null && cp != null && b.check(cp, cc) != MoveResult.ok) {
          broken++;
        }
        applyNode(b, child, size);
        walk(child, b);
      }
    }

    final after = before.copy();
    applyNode(after, n, size);
    walk(n, after);
    return (MoveResult.ok, broken);
  }

  /// Deletes [node] and its subtree. The root cannot be deleted.
  void deleteNode([SgfNode? node]) {
    final n = node ?? _current;
    final parent = n.parent;
    if (parent == null) return;
    _mutate(() {
      final onPath = _current.pathFromRoot.contains(n);
      parent.removeChild(n);
      if (onPath) _current = parent;
    });
  }

  /// Names the variation starting at [start] (empty clears the name).
  void renameVariation(SgfNode start, String name) {
    _mutate(
      () => start.set('N', name.trim().isEmpty ? null : name),
      coalesce: 'N',
    );
  }

  /// Moves [node] among its siblings by [delta] (-1 = up, +1 = down).
  void moveVariation(int delta, [SgfNode? node]) {
    final n = node ?? _current;
    final p = n.parent;
    if (p == null) return;
    final i = p.children.indexOf(n);
    final j = i + delta;
    if (j < 0 || j >= p.children.length) return;
    _mutate(() {
      p.children
        ..removeAt(i)
        ..insert(j, n);
    });
  }

  // ---------------------------------------------------------- undo/redo

  String? _lastCoalesce;

  void _mutate(void Function() fn, {String? coalesce}) {
    // Consecutive edits of the same text field form a single undo step.
    final sameField =
        coalesce != null &&
        coalesce == _lastCoalesce &&
        _undo.isNotEmpty &&
        _undo.last.path.join(',') == _pathOf(_current).join(',');
    if (!sameField) {
      _undo.add(_snapshot());
      if (_undo.length > 300) _undo.removeAt(0);
    }
    _lastCoalesce = coalesce;
    _redo.clear();
    fn();
    _dirty = true;
    _refresh();
  }

  void undo() => _restoreFrom(_undo, _redo);
  void redo() => _restoreFrom(_redo, _undo);

  void _restoreFrom(List<_Snapshot> from, List<_Snapshot> to) {
    if (from.isEmpty) return;
    to.add(_snapshot());
    final s = from.removeLast();
    _root = parseSgf(s.sgf);
    var n = _root;
    for (final i in s.path) {
      if (i < n.children.length) n = n.children[i];
    }
    _current = n;
    _lastCoalesce = null;
    _dirty = true;
    _refresh();
  }

  _Snapshot _snapshot() => _Snapshot(writeSgf(_root), _pathOf(_current));

  static List<int> _pathOf(SgfNode node) {
    final path = <int>[];
    var n = node;
    while (n.parent != null) {
      path.add(n.parent!.children.indexOf(n));
      n = n.parent!;
    }
    return path.reversed.toList();
  }

  void _refresh() {
    _boardCache = positionAt(_current, size);
    notifyListeners();
  }

  // ---------------------------------------------------------------- I/O

  String toSgf() => writeSgf(_root);

  /// Marks the document as having unsaved changes (e.g. opened from a file
  /// that is not in the library yet).
  void markDirty() {
    _dirty = true;
    notifyListeners();
  }

  Future<void> saveTo(String path) async {
    await storage.write(path, toSgf());
    filePath = path;
    _dirty = false;
    notifyListeners();
  }
}

class _Snapshot {
  _Snapshot(this.sgf, this.path);
  final String sgf;
  final List<int> path;
}
