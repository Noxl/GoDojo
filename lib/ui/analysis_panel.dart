import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../analysis/analysis_service.dart';
import '../analysis/katago.dart';
import '../model/annotations.dart';
import '../model/opening_document.dart';
import '../sgf/sgf_node.dart';
import 'board_view.dart';

/// Score loss thresholds (points): up to [kGoodMaxLoss] the move is fine,
/// past [kBadMinLoss] KataGo suggests marking it Bad.
const kGoodMaxLoss = 0.7;
const kBadMinLoss = 2.0;

MoveQuality qualityForLoss(double loss) =>
    loss <= kBadMinLoss ? MoveQuality.good : MoveQuality.bad;

Color lossColor(double loss) {
  if (loss < 0.15) return const Color(0xFF2F74D0);
  if (loss <= kGoodMaxLoss) return const Color(0xFF2E9E44);
  if (loss <= kBadMinLoss) return const Color(0xFFE08A00);
  return const Color(0xFFD03030);
}

String formatLoss(double loss) =>
    loss < 0.05 ? '0' : '-${loss.toStringAsFixed(1)}';

String formatScore(double blackScore) {
  final side = blackScore >= 0 ? 'B' : 'W';
  return '$side+${blackScore.abs().toStringAsFixed(1)}';
}

/// Engine suggestions to draw on the board for [r].
List<AnalysisMark> analysisMarks(PositionAnalysis r) {
  final best = r.best;
  if (best == null) return const [];
  final minVisits = math.max(2, (r.visits * 0.02).round());
  return [
    for (final m in r.moves.take(8))
      if (m.point != null && (m.order == 0 || m.visits >= minVisits))
        AnalysisMark(
          m.point!,
          m.order == 0 ? '★' : formatLoss(best.scoreLead - m.scoreLead),
          lossColor(m.order == 0 ? 0 : best.scoreLead - m.scoreLead),
          m.pv,
          r.toMove,
        ),
  ];
}

/// KataGo information for the current position of the editor.
class AnalysisPanel extends StatelessWidget {
  const AnalysisPanel({super.key, required this.doc, required this.service});

  final OpeningDocument doc;
  final AnalysisService service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final engine = service.engine;
    if (kIsWeb) {
      return _note(
        context,
        Icons.desktop_windows_outlined,
        'KataGo analysis is only in the PC version.',
      );
    }
    if (!service.configured) {
      return _note(
        context,
        Icons.settings,
        'Set up KataGo in Settings (gear icon, bottom left).',
      );
    }
    if (engine == null || engine.status == EngineStatus.starting) {
      final last = engine?.log.lastOrNull ?? '';
      return _note(
        context,
        Icons.hourglass_top,
        'KataGo is starting… The very first launch tunes the graphics card '
        'and can take a few minutes.${last.isEmpty ? '' : '\n$last'}',
        busy: true,
      );
    }
    if (engine.status == EngineStatus.failed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _note(context, Icons.error_outline, engine.error ?? 'KataGo failed.'),
          TextButton(onPressed: service.retry, child: const Text('Retry')),
        ],
      );
    }

    final cur = doc.current;
    final size = doc.size;
    final r = service.resultFor(cur, size);
    if (r == null) {
      return _note(context, Icons.hourglass_top, 'Analyzing…', busy: true);
    }

    final before = cur.parent == null
        ? null
        : service.resultFor(cur.parent!, size);
    final loss = moveLoss(cur, size, before, r);
    final best = r.best;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: WinrateBar(blackWinrate: r.blackWinrate)),
            const SizedBox(width: 12),
            Text(
              formatScore(r.blackScore),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${r.visits} visits${r.complete ? '' : '…'}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (loss != null) ...[
              Text('This move: ', style: theme.textTheme.bodyMedium),
              Text(
                loss < 0.05 ? 'best' : '${formatLoss(loss)} pts',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: lossColor(loss),
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_suggestedMark(cur, loss) case final q?)
                TextButton(
                  onPressed: () => doc.setMoveQuality(q),
                  child: Text(
                    q == MoveQuality.none
                        ? 'Remove mark'
                        : 'Mark as ${q.label.split(' ').first}',
                  ),
                ),
            ] else if (cur.hasMove)
              Text('This move: …', style: theme.textTheme.bodyMedium),
            if (best?.point != null)
              TextButton.icon(
                onPressed: () {
                  final pts = [
                    for (final m in analysisMarks(r).take(3)) m.point,
                  ];
                  final n = doc.addReplies(pts);
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(
                          n == 0
                              ? 'The best moves are already in the tree.'
                              : 'Added $n variation${n == 1 ? '' : 's'}.',
                        ),
                      ),
                    );
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add top moves'),
              ),
          ],
        ),
        Text(
          'Hover a suggestion to see the expected sequence.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  /// The mark KataGo suggests for [node], or null if it already has it.
  /// Unmarked moves count as good.
  static MoveQuality? _suggestedMark(SgfNode node, double loss) {
    var q = qualityForLoss(loss);
    if (q == MoveQuality.good) q = MoveQuality.none;
    var current = MoveQuality.of(node);
    if (current == MoveQuality.good || current == MoveQuality.interesting) {
      current = MoveQuality.none;
    }
    return q == current ? null : q;
  }

  Widget _note(
    BuildContext context,
    IconData icon,
    String text, {
    bool busy = false,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (busy)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Icon(icon, size: 18, color: theme.colorScheme.outline),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Black/White winrate bar.
class WinrateBar extends StatelessWidget {
  const WinrateBar({super.key, required this.blackWinrate});
  final double blackWinrate;

  @override
  Widget build(BuildContext context) {
    final b = (blackWinrate * 100).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 22,
        child: Row(
          children: [
            Expanded(
              flex: math.max(1, b),
              child: Container(
                color: const Color(0xFF1B1B1B),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  'B $b%',
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: math.max(1, 100 - b),
              child: Container(
                color: const Color(0xFFF2F2EF),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  '${100 - b}% W',
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Positions the editor needs analyzed for [node]: the node itself and the
/// position before it (to measure the move's loss).
List<SgfNode> positionsToAnalyze(SgfNode node) => [node, ?node.parent];
