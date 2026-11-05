import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../go/stone.dart';
import '../model/annotations.dart';
import '../model/opening_document.dart';
import '../sgf/sgf_node.dart';

/// Grid position of every node in the tree diagram.
class TreeLayout {
  TreeLayout(SgfNode root) {
    _place(root, 0, 0, 0);
    for (final e in pos.entries) {
      (byColumn[e.value.$1] ??= []).add(e.key);
      cells[e.value] = e.key;
    }
  }

  final Map<SgfNode, (int col, int row)> pos = {};
  final Map<(int, int), SgfNode> cells = {};
  final Map<int, List<SgfNode>> byColumn = {};
  final Map<SgfNode, int> moveNumbers = {};
  final List<int> _nextFree = [];
  final Map<SgfNode, int> _heights = {};
  int columns = 0;
  int rows = 0;

  int _height(SgfNode n) {
    final cached = _heights[n];
    if (cached != null) return cached;
    // Iterative along the main line to avoid deep recursion on long lines.
    var h = 0;
    var cur = n;
    var best = 1;
    while (true) {
      h++;
      for (final c in cur.children.skip(1)) {
        best = math.max(best, h + _height(c));
      }
      if (cur.children.isEmpty) break;
      cur = cur.children.first;
    }
    return _heights[n] = math.max(best, h);
  }

  int _free(int col) => col < _nextFree.length ? _nextFree[col] : 0;

  void _reserve(int col, int row) {
    while (_nextFree.length <= col) {
      _nextFree.add(0);
    }
    _nextFree[col] = math.max(_nextFree[col], row + 1);
  }

  void _place(SgfNode start, int col, int row, int moveNumber) {
    // Place the first-child chain iteratively, then its variations from the
    // deepest branch point up, so each variation goes below what exists.
    final chain = <(SgfNode, int col, int number)>[];
    var node = start;
    var c = col;
    var number = moveNumber;
    while (true) {
      if (node.hasMove) number++;
      moveNumbers[node] = number;
      pos[node] = (c, row);
      _reserve(c, row);
      chain.add((node, c, number));
      if (node.children.isEmpty) break;
      node = node.children.first;
      c++;
    }
    columns = math.max(columns, c + 1);
    rows = math.max(rows, row + 1);
    for (final (parent, parentCol, parentNumber) in chain.reversed) {
      for (final child in parent.children.skip(1)) {
        var r = row + 1;
        final h = _height(child);
        for (var k = parentCol + 1; k < parentCol + 1 + h; k++) {
          r = math.max(r, _free(k));
        }
        _reserve(parentCol, r); // keep the vertical connector free
        _place(child, parentCol + 1, r, parentNumber);
      }
    }
  }
}

/// Scrollable, zoomable diagram of the game tree. Only the visible part is
/// painted, so very large trees stay fast.
class GameTreeView extends StatefulWidget {
  const GameTreeView({
    super.key,
    required this.root,
    required this.current,
    this.onSelect,
    this.onRename,
    this.marked,
    this.compact = false,
  });

  /// Tree of [doc], selecting a node navigates to it.
  GameTreeView.of(
    OpeningDocument doc, {
    Key? key,
    void Function(SgfNode)? onRename,
  }) : this(
         key: key,
         root: doc.root,
         current: doc.current,
         onSelect: doc.goTo,
         onRename: onRename,
       );

  final SgfNode root;
  final SgfNode current;

  /// Called on a click on a node.
  final void Function(SgfNode node)? onSelect;

  /// Called on right-click on a node to rename its variation.
  final void Function(SgfNode node)? onRename;

  /// A node drawn with an extra ring (e.g. the trainer's chosen branch).
  final SgfNode? marked;

  /// Small version without move numbers, labels or zoom buttons.
  final bool compact;

  @override
  State<GameTreeView> createState() => _GameTreeViewState();
}

class _GameTreeViewState extends State<GameTreeView> {
  final _h = ScrollController();
  final _v = ScrollController();
  late double _cell = widget.compact ? 15 : 34;

  /// Rows are taller than columns to leave room for variation labels.
  double get _rowH => _cell * (widget.compact ? 1.2 : 1.45);
  SgfNode? _lastCurrent;
  SgfNode? _layoutRoot;
  String? _layoutKey;
  TreeLayout? _layout;

  @override
  void dispose() {
    _h.dispose();
    _v.dispose();
    super.dispose();
  }

  TreeLayout get layout {
    // Recompute only when the tree structure changed.
    final root = widget.root;
    final key = '${root.hashCode}:${_structureHash(root)}';
    if (_layout == null || _layoutRoot != root || key != _layoutKey) {
      _layout = TreeLayout(root);
      _layoutRoot = root;
      _layoutKey = key;
    }
    return _layout!;
  }

  static int _structureHash(SgfNode root) {
    var h = 17;
    final stack = [root];
    while (stack.isNotEmpty) {
      final n = stack.removeLast();
      h = (h * 31 + n.children.length + identityHashCode(n)) & 0x3fffffff;
      stack.addAll(n.children);
    }
    return h;
  }

  bool _dragging = false;

  /// Drag with the mouse to move around the tree.
  void _pan(Offset delta) {
    void by(ScrollController c, double d) {
      if (!c.hasClients) return;
      c.jumpTo((c.offset - d).clamp(0.0, c.position.maxScrollExtent));
    }

    by(_h, delta.dx);
    by(_v, delta.dy);
  }

  void _zoom(double factor) {
    setState(
      () => _cell = (_cell * factor).clamp(widget.compact ? 8.0 : 16.0, 64.0),
    );
  }

  void _ensureVisible(TreeLayout layout, Size viewport) {
    final cur = widget.current;
    if (cur == _lastCurrent) return;
    _lastCurrent = cur;
    final p = layout.pos[cur];
    if (p == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      void scroll(ScrollController c, double target, double extent) {
        if (!c.hasClients) return;
        final off = c.offset;
        if (target - _cell < off || target + _cell * 2 > off + extent) {
          c.jumpTo(
            (target - extent / 3).clamp(0.0, c.position.maxScrollExtent),
          );
        }
      }

      scroll(_h, p.$1 * _cell, viewport.width);
      scroll(_v, p.$2 * _rowH, viewport.height);
    });
  }

  SgfNode? _nodeAt(TreeLayout layout, Offset o) =>
      layout.cells[((o.dx / _cell).floor(), (o.dy / _rowH).floor())];

  @override
  Widget build(BuildContext context) {
    final layout = this.layout;
    final scheme = Theme.of(context).colorScheme;
    final content = Size(
      (layout.columns + 2) * _cell,
      (layout.rows + 2) * _rowH,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        _ensureVisible(layout, constraints.biggest);
        return Stack(
          children: [
            Positioned.fill(
              child: ClipRect(
                child: CustomPaint(
                  painter: _TreePainter(
                    layout: layout,
                    current: widget.current,
                    marked: widget.marked,
                    compact: widget.compact,
                    cell: _cell,
                    rowH: _rowH,
                    scheme: scheme,
                    h: _h,
                    v: _v,
                  ),
                ),
              ),
            ),
            Listener(
              onPointerSignal: (e) {
                if (e is PointerScrollEvent &&
                    HardwareKeyboard.instance.isControlPressed) {
                  GestureBinding.instance.pointerSignalResolver.register(e, (
                    _,
                  ) {
                    _zoom(e.scrollDelta.dy < 0 ? 1.12 : 1 / 1.12);
                  });
                }
              },
              child: Scrollbar(
                controller: _v,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _v,
                  child: Scrollbar(
                    controller: _h,
                    thumbVisibility: true,
                    notificationPredicate: (n) => n.depth == 0,
                    child: SingleChildScrollView(
                      controller: _h,
                      scrollDirection: Axis.horizontal,
                      child: MouseRegion(
                        cursor: _dragging
                            ? SystemMouseCursors.grabbing
                            : SystemMouseCursors.basic,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (_) => setState(() => _dragging = true),
                          onPanUpdate: (d) => _pan(d.delta),
                          onPanEnd: (_) => setState(() => _dragging = false),
                          onPanCancel: () => setState(() => _dragging = false),
                          onTapUp: (d) {
                            final node = _nodeAt(layout, d.localPosition);
                            if (node != null) widget.onSelect?.call(node);
                          },
                          onSecondaryTapUp: (d) {
                            final node = _nodeAt(layout, d.localPosition);
                            if (node != null) widget.onRename?.call(node);
                          },
                          child: SizedBox.fromSize(size: content),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (!widget.compact)
              Positioned(
                right: 14,
                bottom: 14,
                child: Material(
                  elevation: 2,
                  borderRadius: BorderRadius.circular(20),
                  color: scheme.surfaceContainerHigh,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Zoom out (Ctrl+wheel)',
                        onPressed: () => _zoom(1 / 1.2),
                        icon: const Icon(Icons.remove, size: 18),
                      ),
                      Text(
                        '${layout.pos.length} nodes',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      IconButton(
                        tooltip: 'Zoom in (Ctrl+wheel)',
                        onPressed: () => _zoom(1.2),
                        icon: const Icon(Icons.add, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TreePainter extends CustomPainter {
  _TreePainter({
    required this.layout,
    required this.current,
    this.marked,
    this.compact = false,
    required this.cell,
    required this.rowH,
    required this.scheme,
    required this.h,
    required this.v,
  }) : super(repaint: Listenable.merge([h, v]));

  final TreeLayout layout;
  final SgfNode current;
  final SgfNode? marked;
  final bool compact;
  final double cell;
  final double rowH;
  final ColorScheme scheme;
  final ScrollController h;
  final ScrollController v;

  static final Map<String, TextPainter> _textCache = {};

  Offset _center((int, int) p, Offset scroll) =>
      Offset(p.$1 * cell + cell / 2, p.$2 * rowH + rowH - cell / 2) - scroll;

  @override
  void paint(Canvas canvas, Size size) {
    final scroll = Offset(
      h.hasClients ? h.offset : 0,
      v.hasClients ? v.offset : 0,
    );
    final c0 = (scroll.dx / cell).floor() - 1;
    final c1 = ((scroll.dx + size.width) / cell).ceil() + 1;
    final r0 = (scroll.dy / rowH).floor() - 1;
    final r1 = ((scroll.dy + size.height) / rowH).ceil() + 1;

    final activePath = <SgfNode>{};
    for (SgfNode? n = current; n != null; n = n.parent) {
      activePath.add(n);
    }
    final edge = Paint()
      ..color = scheme.outlineVariant
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final activeEdge = Paint()
      ..color = scheme.primary
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final visible = <SgfNode>[];
    for (var col = math.max(0, c0); col <= c1; col++) {
      for (final n in layout.byColumn[col] ?? const <SgfNode>[]) {
        final (_, row) = layout.pos[n]!;
        final parent = n.parent;
        if (parent != null) {
          final (_, prow) = layout.pos[parent]!;
          // The edge spans rows [prow, row] in columns col-1..col.
          if (row >= r0 && prow <= r1) {
            final a = _center(layout.pos[parent]!, scroll);
            final b = _center((col, row), scroll);
            final path = Path()..moveTo(a.dx, a.dy);
            if (b.dy != a.dy) path.lineTo(a.dx, b.dy - rowH / 2);
            path.lineTo(b.dx, b.dy);
            canvas.drawPath(path, activePath.contains(n) ? activeEdge : edge);
          }
        }
        if (row >= r0 && row <= r1) visible.add(n);
      }
    }

    final r = cell * 0.36;
    for (final n in visible) {
      final c = _center(layout.pos[n]!, scroll);
      final mc = n.moveColor;
      if (n == marked) {
        canvas.drawCircle(
          c,
          r + cell * 0.3,
          Paint()
            ..color = scheme.tertiary
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(2, cell * 0.12),
        );
      }
      if (n == current) {
        canvas.drawCircle(c, r + cell * 0.14, Paint()..color = scheme.primary);
      }
      if (mc == null) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: c, width: r * 1.7, height: r * 1.7),
            Radius.circular(r * 0.3),
          ),
          Paint()..color = scheme.secondary,
        );
      } else {
        final black = mc == Stone.black;
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..color = black ? const Color(0xFF1B1B1B) : const Color(0xFFF7F7F5),
        );
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..color = const Color(0xFF6B6B6B)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
        final number = layout.moveNumbers[n] ?? 0;
        if (cell >= 22 && !compact) {
          // A tenuki (pass) has no stone on the board: "T".
          final text = n.isPass ? 'T' : '$number';
          final tp = _label(text, black, number > 99 ? r * 0.72 : r * 0.9);
          tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
        }
      }
      final q = MoveQuality.of(n);
      if (q.color != null && q != MoveQuality.interesting) {
        canvas.drawCircle(
          c,
          r + cell * 0.06,
          Paint()
            ..color = q.color!
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(2.5, cell * 0.1),
        );
      }
      if (n.has('C')) {
        canvas.drawCircle(
          c + Offset(r * 0.85, -r * 0.85),
          math.max(3, cell * 0.1),
          Paint()..color = const Color(0xFF3B82F6),
        );
      }
    }

    // Variation labels ("2", "3 Taisha") in the band above each row.
    for (final n in visible) {
      if (compact) break;
      if (!n.startsVariation && n.variationName == null) continue;
      final c = _center(layout.pos[n]!, scroll);
      final named = n.variationName != null;
      final tp = TextPainter(
        text: TextSpan(
          text: n.variationLabel,
          style: TextStyle(
            fontSize: math.max(9, cell * 0.32),
            fontWeight: FontWeight.w600,
            color: named ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          ),
        ),
        maxLines: 1,
        ellipsis: '…',
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: cell * 6);
      final top = c.dy - cell / 2 - (rowH - cell) / 2 - tp.height / 2 - 1;
      final rect = Rect.fromLTWH(c.dx - r, top, tp.width + 10, tp.height + 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)),
        Paint()
          ..color = named
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
      );
      tp.paint(canvas, Offset(rect.left + 5, rect.top + 1));
    }
  }

  TextPainter _label(String text, bool onBlack, double fontSize) {
    final key = '$text|$onBlack|${fontSize.toStringAsFixed(1)}';
    return _textCache.putIfAbsent(key, () {
      if (_textCache.length > 4000) _textCache.clear();
      return TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: fontSize,
            color: onBlack ? Colors.white : Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  @override
  bool shouldRepaint(covariant _TreePainter old) => true;
}
