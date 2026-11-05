import '../go/point.dart';
import '../go/stone.dart';

/// A node of an SGF game tree.
///
/// Properties are stored as an ordered map of property id -> list of raw
/// (unescaped) values, so unknown properties survive a load/save round trip.
class SgfNode {
  SgfNode({Map<String, List<String>>? props}) : props = props ?? {};

  SgfNode? parent;
  final List<SgfNode> children = [];
  final Map<String, List<String>> props;

  bool get isRoot => parent == null;
  bool get isLeaf => children.isEmpty;

  // ---------------------------------------------------------------- props

  String? get(String id) {
    final v = props[id];
    return (v == null || v.isEmpty) ? null : v.first;
  }

  List<String> getAll(String id) => props[id] ?? const [];

  bool has(String id) => props.containsKey(id);

  void set(String id, String? value) {
    if (value == null) {
      props.remove(id);
    } else {
      props[id] = [value];
    }
  }

  void setAll(String id, List<String> values) {
    if (values.isEmpty) {
      props.remove(id);
    } else {
      props[id] = List.of(values);
    }
  }

  void remove(String id) => props.remove(id);

  // ---------------------------------------------------------------- move

  /// The color of the move played in this node, or null for a non-move node.
  Stone? get moveColor {
    if (props.containsKey('B')) return Stone.black;
    if (props.containsKey('W')) return Stone.white;
    return null;
  }

  bool get hasMove => moveColor != null;

  /// The point of the move, or null for a pass or a non-move node.
  Point? movePoint(int boardSize) {
    final c = moveColor;
    if (c == null) return null;
    return Point.fromSgf(get(c.sgf) ?? '', boardSize);
  }

  bool get isPass {
    final c = moveColor;
    if (c == null) return false;
    final v = get(c.sgf) ?? '';
    return v.isEmpty || v == 'tt';
  }

  void setMove(Stone color, Point? point) {
    props.remove('B');
    props.remove('W');
    props[color.sgf] = [point?.sgf ?? ''];
  }

  // ---------------------------------------------------------------- tree

  void addChild(SgfNode child, {int? index}) {
    child.parent = this;
    if (index == null) {
      children.add(child);
    } else {
      children.insert(index, child);
    }
  }

  void removeChild(SgfNode child) {
    children.remove(child);
    child.parent = null;
  }

  /// Path from the root down to this node (inclusive).
  List<SgfNode> get pathFromRoot {
    final path = <SgfNode>[];
    SgfNode? n = this;
    while (n != null) {
      path.add(n);
      n = n.parent;
    }
    return path.reversed.toList();
  }

  SgfNode get root {
    var n = this;
    while (n.parent != null) {
      n = n.parent!;
    }
    return n;
  }

  int get depth {
    var d = 0;
    var n = this;
    while (n.parent != null) {
      d++;
      n = n.parent!;
    }
    return d;
  }

  /// True when this node starts a variation (its parent has several children).
  bool get startsVariation => parent != null && parent!.children.length > 1;

  /// The node starting the innermost variation containing this node, or
  /// null if no branching happened above it.
  SgfNode? get variationStart {
    for (SgfNode n = this; n.parent != null; n = n.parent!) {
      if (n.startsVariation) return n;
    }
    return null;
  }

  /// 1-based number of this variation among its siblings.
  int get variationNumber =>
      parent == null ? 1 : parent!.children.indexOf(this) + 1;

  /// User-given variation name (SGF node name `N`), if any.
  String? get variationName {
    final v = get('N')?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  /// Label shown in the tree: "2" or "2 Taisha" at a branch, the bare
  /// name for a named move without siblings.
  String get variationLabel {
    final name = variationName;
    if (!startsVariation) return name ?? '';
    return name == null ? '$variationNumber' : '$variationNumber $name';
  }

  /// Number of moves played from the root up to and including this node.
  int get moveNumber {
    var count = 0;
    SgfNode? n = this;
    while (n != null) {
      if (n.hasMove) count++;
      n = n.parent;
    }
    return count;
  }

  Iterable<SgfNode> get descendants sync* {
    for (final c in children) {
      yield c;
      yield* c.descendants;
    }
  }

  Iterable<SgfNode> get leaves sync* {
    if (children.isEmpty) {
      yield this;
    } else {
      for (final c in children) {
        yield* c.leaves;
      }
    }
  }

  /// Deep copy of this node and its subtree (parent is not copied).
  SgfNode clone() {
    final copy = SgfNode(
      props: {for (final e in props.entries) e.key: List.of(e.value)},
    );
    for (final c in children) {
      copy.addChild(c.clone());
    }
    return copy;
  }
}
