import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../go/board.dart';
import '../go/point.dart';
import '../go/stone.dart';
import '../model/annotations.dart';

enum BoardStyle {
  wood('Wood', Color(0xFFD9BC8C), Color(0xFFC9A673), Color(0xFF3B2F22)),
  paleWood(
    'Pale wood',
    Color(0xFFEADBC0),
    Color(0xFFDDC9A6),
    Color(0xFF4A4034),
  ),
  slate('Slate gray', Color(0xFFC3C8CE), Color(0xFFAFB5BD), Color(0xFF2C3036)),
  green('Green', Color(0xFFA9C2A4), Color(0xFF94B08F), Color(0xFF243022));

  const BoardStyle(this.label, this.light, this.dark, this.line);
  final String label;
  final Color light;
  final Color dark;
  final Color line;
}

/// A letter (A, B, C…) marking a next move that exists in the tree. An
/// empty letter draws a plain circle (used when there is only one move).
/// An engine suggestion: a colored disc with a short label (score loss),
/// and the expected continuation shown when hovered.
class AnalysisMark {
  const AnalysisMark(this.point, this.label, this.color, this.pv, this.toMove);
  final Point point;
  final String label;
  final Color color;
  final List<Point?> pv;

  /// Color of the first move of [pv].
  final Stone toMove;
}

class VariationMark {
  const VariationMark(this.point, this.letter, {this.color});
  final Point point;
  final String letter;

  /// Annotation color (bad), or null for a plain move.
  final Color? color;
}

/// A stone called out as a mistake (see [BoardView.mistake]).
class MistakeMark {
  const MistakeMark(this.point, this.color, this.symbol);
  final Point point;
  final Color color;
  final String symbol;
}

class BoardView extends StatefulWidget {
  const BoardView({
    super.key,
    required this.board,
    this.lastMove,
    this.markup = const {},
    this.labels = const {},
    this.variations = const [],
    this.analysis = const [],
    this.hints = const [],
    this.wrongPoint,
    this.mistake,
    this.hoverStone,
    this.onTap,
    this.showCoordinates = true,
    this.style = BoardStyle.wood,
  });

  final BoardStyle style;

  final Board board;
  final Point? lastMove;
  final Map<Point, MarkupShape> markup;
  final Map<Point, String> labels;
  final List<VariationMark> variations;
  final List<AnalysisMark> analysis;
  final List<Point> hints;
  final Point? wrongPoint;

  /// A stone to call out as a mistake: a colored ring and a "?" badge.
  final MistakeMark? mistake;

  /// Stone previewed under the mouse cursor, or null for none.
  final Stone? hoverStone;
  final void Function(Point p)? onTap;
  final bool showCoordinates;

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> {
  Point? _hover;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final geo = _Geometry(
            constraints.biggest.shortestSide,
            widget.board.size,
            widget.showCoordinates,
          );
          return MouseRegion(
            cursor: widget.onTap == null
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            onHover: (e) => _setHover(geo.pointAt(e.localPosition)),
            onExit: (_) => _setHover(null),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                final p = geo.pointAt(d.localPosition);
                if (p != null) widget.onTap?.call(p);
              },
              child: CustomPaint(
                size: Size.square(geo.extent),
                painter: _BoardPainter(widget, geo, _hover),
              ),
            ),
          );
        },
      ),
    );
  }

  void _setHover(Point? p) {
    if (p != _hover) setState(() => _hover = p);
  }
}

class _Geometry {
  _Geometry(this.extent, this.size, bool coords) {
    // Space for coordinates on all sides when enabled.
    final slots = size - 1 + (coords ? 2.6 : 1.2);
    cell = extent / slots;
    origin = (extent - cell * (size - 1)) / 2;
  }

  final double extent;
  final int size;
  late final double cell;
  late final double origin;

  Offset center(Point p) => Offset(origin + p.x * cell, origin + p.y * cell);

  Point? pointAt(Offset o) {
    final x = ((o.dx - origin) / cell).round();
    final y = ((o.dy - origin) / cell).round();
    final p = Point(x, y);
    return p.isOnBoard(size) ? p : null;
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter(this.w, this.g, this.hover);

  final BoardView w;
  final _Geometry g;
  final Point? hover;

  Color get _wood => w.style.light;
  Color get _woodDark => w.style.dark;
  static const _goLetters = 'ABCDEFGHJKLMNOPQRSTUVWXYZ';

  @override
  void paint(Canvas canvas, Size size) {
    final board = w.board;
    final n = board.size;
    final rect = Offset.zero & size;
    final r = g.cell / 2 * 0.96;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_wood, _woodDark],
        ).createShader(rect),
    );

    // Grid.
    final line = Paint()
      ..color = w.style.line
      ..strokeWidth = math.max(1, g.cell / 30);
    final start = g.origin, end = g.origin + g.cell * (n - 1);
    for (var i = 0; i < n; i++) {
      final v = g.origin + i * g.cell;
      canvas.drawLine(Offset(start, v), Offset(end, v), line);
      canvas.drawLine(Offset(v, start), Offset(v, end), line);
    }
    final border = Paint()
      ..color = line.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = line.strokeWidth * 1.8;
    canvas.drawRect(Rect.fromLTRB(start, start, end, end), border);
    for (final s in board.starPoints) {
      canvas.drawCircle(g.center(s), g.cell * 0.11, line);
    }

    // Coordinates.
    if (w.showCoordinates) {
      final style = TextStyle(
        color: w.style.line.withValues(alpha: 0.8),
        fontSize: g.cell * 0.36,
        fontWeight: FontWeight.w600,
      );
      final off = g.cell * 0.85;
      for (var i = 0; i < n; i++) {
        final v = g.origin + i * g.cell;
        final letter = _goLetters[i];
        final number = '${n - i}';
        _text(canvas, letter, Offset(v, start - off), style);
        _text(canvas, letter, Offset(v, end + off), style);
        _text(canvas, number, Offset(start - off, v), style);
        _text(canvas, number, Offset(end + off, v), style);
      }
    }

    // Labels on empty points hide the grid underneath.
    for (final e in w.labels.entries) {
      if (board[e.key] == Stone.empty) {
        canvas.drawCircle(g.center(e.key), r * 0.8, Paint()..color = _wood);
      }
    }

    // Stones.
    for (final p in board.points) {
      final s = board[p];
      if (s != Stone.empty) _stone(canvas, g.center(p), r, s, 1);
    }

    // Hover preview (under the variation letters).
    final hs = w.hoverStone;
    if (hover != null && hs != null && board[hover!] == Stone.empty) {
      _stone(canvas, g.center(hover!), r, hs, 0.4);
    }

    // Engine suggestions (hidden while a continuation is previewed).
    final hovered = w.analysis.where((a) => a.point == hover).firstOrNull;
    final analysisPoints = <Point>{};
    if (hovered == null) {
      for (final a in w.analysis) {
        if (board[a.point] != Stone.empty) continue;
        analysisPoints.add(a.point);
        final c = g.center(a.point);
        canvas.drawCircle(
          c,
          r * 0.95,
          Paint()..color = a.color.withValues(alpha: 0.9),
        );
        _text(
          canvas,
          a.label,
          c,
          TextStyle(
            color: Colors.white,
            fontSize: g.cell * (a.label.length > 3 ? 0.32 : 0.38),
            fontWeight: FontWeight.w700,
          ),
        );
      }
    }

    // Next moves present in the tree, as letters.
    for (final v in w.variations) {
      if (board[v.point] != Stone.empty || w.labels.containsKey(v.point)) {
        continue;
      }
      if (analysisPoints.contains(v.point)) {
        // Small badge on the engine disc.
        final c = g.center(v.point) + Offset(r * 0.7, -r * 0.7);
        canvas.drawCircle(c, r * 0.38, Paint()..color = _wood);
        canvas.drawCircle(
          c,
          r * 0.38,
          Paint()
            ..color = v.color ?? w.style.line
            ..style = PaintingStyle.stroke
            ..strokeWidth = g.cell * 0.04,
        );
        if (v.letter.isNotEmpty) {
          _text(
            canvas,
            v.letter,
            c,
            TextStyle(
              color: v.color ?? w.style.line,
              fontSize: g.cell * 0.28,
              fontWeight: FontWeight.w800,
            ),
          );
        }
        continue;
      }
      final c = g.center(v.point);
      final color = v.color ?? w.style.line;
      if (v.letter.isEmpty) {
        // Single continuation: a plain circle.
        canvas.drawCircle(
          c,
          r * 0.5,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = g.cell * 0.07,
        );
        continue;
      }
      canvas.drawCircle(c, r * 0.78, Paint()..color = _wood);
      canvas.drawCircle(
        c,
        r * 0.78,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = g.cell * 0.06,
      );
      _text(
        canvas,
        v.letter,
        c,
        TextStyle(
          color: color,
          fontSize: g.cell * 0.5,
          fontWeight: FontWeight.w800,
        ),
      );
    }

    // Expected continuation of the hovered suggestion.
    if (hovered != null) {
      final pvBoard = board.copy();
      var color = hovered.toMove;
      var i = 1;
      for (final pt in hovered.pv.take(12)) {
        if (pt != null && pvBoard[pt] == Stone.empty) {
          pvBoard.forcePlay(pt, color);
          final c = g.center(pt);
          _stone(canvas, c, r, color, 0.75);
          _text(
            canvas,
            '$i',
            c,
            TextStyle(
              color: color == Stone.black ? Colors.white : Colors.black,
              fontSize: g.cell * 0.42,
              fontWeight: FontWeight.w700,
            ),
          );
        }
        color = color.opponent;
        i++;
      }
    }

    // Last move marker.
    final lm = w.lastMove;
    if (lm != null &&
        board[lm] != Stone.empty &&
        !w.markup.containsKey(lm) &&
        !w.labels.containsKey(lm)) {
      canvas.drawCircle(
        g.center(lm),
        r * 0.42,
        Paint()
          ..color = board[lm] == Stone.black ? Colors.white : Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = g.cell * 0.07,
      );
    }

    // Markup.
    for (final e in w.markup.entries) {
      _markup(canvas, e.key, e.value, _contrast(board[e.key]), r);
    }
    for (final e in w.labels.entries) {
      final s = board[e.key];
      _text(
        canvas,
        e.value,
        g.center(e.key),
        TextStyle(
          color: _contrast(s),
          fontSize: g.cell * (e.value.length > 2 ? 0.38 : 0.52),
          fontWeight: FontWeight.bold,
        ),
      );
    }

    // Trainer hints and errors.
    for (final h in w.hints) {
      canvas.drawCircle(
        g.center(h),
        r * 0.75,
        Paint()..color = const Color(0xAA2E9E44),
      );
    }
    final m = w.mistake;
    if (m != null) {
      final c = g.center(m.point);
      canvas.drawCircle(
        c,
        r * 1.08,
        Paint()
          ..color = m.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = g.cell * 0.12,
      );
      final badge = c + Offset(r * 0.8, -r * 0.8);
      canvas.drawCircle(badge, r * 0.48, Paint()..color = m.color);
      _text(
        canvas,
        m.symbol,
        badge,
        TextStyle(
          color: Colors.white,
          fontSize: g.cell * 0.36,
          fontWeight: FontWeight.w900,
        ),
      );
    }
    final wp = w.wrongPoint;
    if (wp != null) {
      _markup(
        canvas,
        wp,
        MarkupShape.cross,
        const Color(0xFFD03030),
        r,
        width: g.cell * 0.12,
      );
    }
  }

  Color _contrast(Stone s) =>
      s == Stone.black ? Colors.white : const Color(0xFF111111);

  void _stone(Canvas canvas, Offset c, double r, Stone s, double opacity) {
    if (opacity >= 1) {
      canvas.drawCircle(
        c + Offset(r * 0.08, r * 0.1),
        r,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.3)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.12),
      );
    }
    final rect = Rect.fromCircle(center: c, radius: r);
    final colors = s == Stone.black
        ? const [Color(0xFF5A5A5A), Color(0xFF0E0E0E)]
        : const [Color(0xFFFFFFFF), Color(0xFFD6D2C8)];
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 0.9,
          colors: [for (final col in colors) col.withValues(alpha: opacity)],
        ).createShader(rect),
    );
    if (s == Stone.white) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = const Color(0xFF8C8577).withValues(alpha: opacity * 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, r * 0.05),
      );
    }
  }

  void _markup(
    Canvas canvas,
    Point p,
    MarkupShape shape,
    Color color,
    double r, {
    double? width,
  }) {
    final c = g.center(p);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width ?? g.cell * 0.08
      ..strokeCap = StrokeCap.round;
    final s = r * 0.5;
    switch (shape) {
      case MarkupShape.triangle:
        final path = Path()
          ..moveTo(c.dx, c.dy - s * 1.1)
          ..lineTo(c.dx + s, c.dy + s * 0.65)
          ..lineTo(c.dx - s, c.dy + s * 0.65)
          ..close();
        canvas.drawPath(path, paint);
      case MarkupShape.square:
        canvas.drawRect(
          Rect.fromCenter(center: c, width: s * 1.6, height: s * 1.6),
          paint,
        );
      case MarkupShape.circle:
        canvas.drawCircle(c, s * 0.95, paint);
      case MarkupShape.cross:
        canvas.drawLine(c + Offset(-s, -s), c + Offset(s, s), paint);
        canvas.drawLine(c + Offset(s, -s), c + Offset(-s, s), paint);
    }
  }

  void _text(Canvas canvas, String text, Offset center, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) => true;
}
