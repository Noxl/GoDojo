import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analysis/analysis_service.dart';
import '../app_state.dart';
import '../go/board_region.dart';
import '../go/point.dart';
import '../go/stone.dart';
import '../model/annotations.dart';
import '../model/drill.dart';
import '../model/opening_document.dart';
import '../model/trainer_session.dart';
import '../sgf/sgf_node.dart';
import 'actions.dart';
import 'analysis_panel.dart';
import 'board_view.dart';
import 'tree_view.dart';

part 'drill_page.dart';

/// A phone: narrow screen, the trainers are laid out for the thumb.
bool _isPhone(BuildContext context) => MediaQuery.sizeOf(context).width < 600;

/// Phone: one page that scrolls, the board as wide as the screen at the
/// top (it keeps the finger for itself: the page scrolls from the rest).
Widget _phoneLayout({
  required Widget board,
  required Widget main,
  required Widget side,
}) => SingleChildScrollView(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(padding: const EdgeInsets.all(2), child: board),
      ExcludeFocus(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [main, const SizedBox(height: 16), side],
          ),
        ),
      ),
    ],
  ),
);

/// Next line, tenuki, hint and edit: a row of big buttons on a phone.
Widget _trainButtons(
  BuildContext context, {
  required VoidCallback onNext,
  required VoidCallback? onTenuki,
  required VoidCallback? onHint,
  required VoidCallback onEdit,
}) {
  if (!_isPhone(context)) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: onNext,
          icon: const Icon(Icons.skip_next),
          label: const Text('Next line (N)'),
        ),
        OutlinedButton.icon(
          onPressed: onTenuki,
          icon: const Icon(Icons.call_split),
          label: const Text('Tenuki (T)'),
        ),
        OutlinedButton.icon(
          onPressed: onHint,
          icon: const Icon(Icons.lightbulb_outline),
          label: const Text('Hint (H)'),
        ),
        OutlinedButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit here'),
        ),
      ],
    );
  }
  Widget button(
    IconData icon,
    String label,
    VoidCallback? onPressed,
    bool main,
  ) {
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
    const pad = EdgeInsets.symmetric(vertical: 8);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: main
            ? FilledButton(
                onPressed: onPressed,
                style: FilledButton.styleFrom(padding: pad),
                child: child,
              )
            : OutlinedButton(
                onPressed: onPressed,
                style: OutlinedButton.styleFrom(padding: pad),
                child: child,
              ),
      ),
    );
  }

  return Row(
    children: [
      button(Icons.skip_next, 'Next', onNext, true),
      button(Icons.call_split, 'Tenuki', onTenuki, false),
      button(Icons.lightbulb_outline, 'Hint', onHint, false),
      button(Icons.edit_outlined, 'Edit', onEdit, false),
    ],
  );
}

class TrainerPage extends StatelessWidget {
  const TrainerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final target = AppScope.of(context).trainerTarget;
    if (target == null) return const _ChooseOpening();
    return _Trainer(
      key: ObjectKey(target),
      doc: target.doc,
      branch: target.branch,
    );
  }
}

class _ChooseOpening extends StatelessWidget {
  const _ChooseOpening();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final entries = state.library.entries
        .where((e) => e.error == null)
        .toList();
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choose an opening or joseki to train',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Card(
                color: theme.colorScheme.primaryContainer,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: Icon(
                    Icons.all_inclusive,
                    size: 34,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  title: Text(
                    'Global trainer',
                    style: theme.textTheme.titleLarge,
                  ),
                  subtitle: const Text(
                    'All your joseki and tricks at random. Your mistakes come '
                    'back until you know them, and you see how many lines '
                    'you know.',
                  ),
                  trailing: FilledButton(
                    onPressed: state.openDrill,
                    child: const Text('Open'),
                  ),
                  onTap: state.openDrill,
                ),
              ),
              const SizedBox(height: 16),
              if (state.editorDoc != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.edit),
                    title: Text(state.editorDoc!.name),
                    subtitle: const Text('Opening currently in the editor'),
                    onTap: () => state.train(state.editorDoc!),
                  ),
                ),
              Expanded(
                child: entries.isEmpty
                    ? const Center(child: Text('Your library is empty.'))
                    : ListView(
                        children: [
                          for (final e in entries)
                            ListTile(
                              leading: KindIcon(kind: e.kind, color: e.color),
                              title: Text(e.name),
                              subtitle: Text(
                                '${e.size}×${e.size} · ${e.lines} lines',
                              ),
                              onTap: () async {
                                final doc = await loadDocument(context, e.path);
                                if (doc != null) state.train(doc);
                              },
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Trainer extends StatefulWidget {
  const _Trainer({super.key, required this.doc, this.branch});
  final OpeningDocument doc;

  /// Train only the lines through this node.
  final SgfNode? branch;

  @override
  State<_Trainer> createState() => _TrainerState();
}

class _TrainerState extends State<_Trainer> {
  late Stone _color = widget.doc.color;
  late final AnalysisService _analysisService;
  late SgfNode? _branch = widget.branch;
  // A mistake of the tree shows its punishment before asking again.
  TrainerOptions _options = const TrainerOptions(followMistakes: true);
  late TrainerSession _session = _newSession();
  final _focus = FocusNode(debugLabel: 'trainer');

  TrainerSession _newSession() => TrainerSession(
    root: widget.doc.root,
    size: widget.doc.size,
    color: _color,
    options: _options,
    branch: _branch,
  );

  void _rebuildSession() {
    final old = _session;
    setState(() => _session = _newSession());
    old.dispose();
    _session
      ..addListener(_checkMoveWithKataGo)
      ..addListener(_syncEval);
    _evaluated = null;
    _syncEval();
  }

  // KataGo verdict for the last move played outside the repertoire.
  TrainerFeedback? _aiFeedback;
  double? _aiLoss;
  bool _aiBusy = false;

  @override
  void initState() {
    super.initState();
    _analysisService = AppScope.read(context).analysis;
    _session
      ..addListener(_checkMoveWithKataGo)
      ..addListener(_syncEval);
  }

  // ------------------------------------------------------ side column

  /// Live KataGo evaluation of the trainer position.
  bool _showEval = false;
  SgfNode? _evaluated;

  void _syncEval() {
    final analysis = _analysisService;
    final s = _session;
    if (!_showEval) {
      if (_evaluated != null) analysis.stopAnalysis();
      _evaluated = null;
      return;
    }
    if (s.replaying || s.punishing || s.current == _evaluated) return;
    _evaluated = s.current;
    analysis.analyze([s.current], widget.doc.size);
  }

  void _setShowEval(bool on) {
    setState(() => _showEval = on);
    _syncEval();
  }

  Widget _sideColumn(BuildContext context) {
    final analysis = AppScope.read(context).analysis;
    final tricky = _session.mistakesAt.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(title: 'This line', child: _lineMoves(context)),
        if (analysis.configured) ...[
          const SizedBox(height: 16),
          _Section(title: 'KataGo', child: _evalSection(context)),
        ],
        if (tricky.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Section(
            title: 'Tricky spots',
            child: _trickySpots(context, tricky.take(5).toList()),
          ),
        ],
        const SizedBox(height: 16),
        _Section(title: 'Settings', child: _settings(context)),
      ],
    );
  }

  /// The moves played so far in this line, as small stones.
  Widget _lineMoves(BuildContext context) {
    final theme = Theme.of(context);
    final s = _session;
    final size = widget.doc.size;
    final moves = [
      for (final n in s.current.pathFromRoot)
        if (n.hasMove) n,
    ];
    if (moves.isEmpty) {
      return Text('No move yet.', style: theme.textTheme.bodySmall);
    }
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final n in moves)
          Opacity(
            opacity: n.moveNumber <= s.skippedMoves ? 0.45 : 1,
            child: Tooltip(
              message: n.get('C') ?? '',
              child: Container(
                padding: const EdgeInsets.fromLTRB(2, 2, 8, 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        MoveQuality.of(n).color ??
                        (n == s.current
                            ? theme.colorScheme.primary
                            : Colors.transparent),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _NumberedStone(n.moveColor!, n.moveNumber),
                    const SizedBox(width: 4),
                    Text(
                      n.movePoint(size)?.display(size) ?? 'tenuki',
                      style: theme.textTheme.labelMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _evalSection(BuildContext context) {
    final theme = Theme.of(context);
    final analysis = AppScope.read(context).analysis;
    return ListenableBuilder(
      listenable: analysis,
      builder: (context, _) {
        final r = _showEval
            ? analysis.resultFor(_session.current, widget.doc.size)
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Show the evaluation of the position'),
                ),
                Switch(value: _showEval, onChanged: _setShowEval),
              ],
            ),
            if (_showEval) ...[
              const SizedBox(height: 6),
              if (r == null)
                Text('Thinking…', style: theme.textTheme.bodySmall)
              else
                Row(
                  children: [
                    Expanded(child: WinrateBar(blackWinrate: r.blackWinrate)),
                    const SizedBox(width: 10),
                    Text(
                      formatScore(r.blackScore),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
            ],
          ],
        );
      },
    );
  }

  /// Positions where the user made the most mistakes, to drill them.
  Widget _trickySpots(
    BuildContext context,
    List<MapEntry<SgfNode, int>> spots,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in spots)
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFD03030).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '×${e.value}',
                  style: const TextStyle(
                    color: Color(0xFFD03030),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  e.key.isRoot ? 'First move' : 'After ${_describeNode(e.key)}',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              TextButton(
                onPressed: () => _chooseBranch(e.key),
                child: const Text('Drill'),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _checkMoveWithKataGo() async {
    final s = _session;
    final fb = s.feedback;
    final point = s.wrongPoint;
    if (fb.kind != FeedbackKind.notInRepertoire || point == null) return;
    if (identical(fb, _aiFeedback)) return;
    final analysis = AppScope.read(context).analysis;
    if (!analysis.configured) return;
    setState(() {
      _aiFeedback = fb;
      _aiLoss = null;
      _aiBusy = true;
    });
    final loss = await analysis.lossOf(s.current, widget.doc.size, point);
    if (!mounted || !identical(_aiFeedback, fb)) return;
    setState(() {
      _aiLoss = loss;
      _aiBusy = false;
    });
  }

  /// Text shown under a "not in repertoire" message.
  (String, Color)? get _aiVerdict {
    if (!identical(_session.feedback, _aiFeedback)) return null;
    if (_aiBusy) return ('KataGo is evaluating this move…', Colors.grey);
    final loss = _aiLoss;
    if (loss == null) return null;
    final text = loss <= kGoodMaxLoss
        ? 'KataGo: ${formatLoss(loss)} pts. Playable, just not your repertoire.'
        : loss <= kBadMinLoss
        ? 'KataGo: ${formatLoss(loss)} pts. Slightly worse than your move.'
        : 'KataGo: ${formatLoss(loss)} pts. A real mistake.';
    return (text, lossColor(loss));
  }

  /// Click in the tree: train only the lines through [node].
  void _chooseBranch(SgfNode? node) {
    if (node != null && !node.isRoot && !_session.canTrainFrom(node)) {
      showMessage(
        context,
        'No ${_color.label} move after this point to train.',
      );
      return;
    }
    setState(() => _branch = node == null || node.isRoot ? null : node);
    _session.setBranch(_branch);
  }

  String _describeNode(SgfNode n) {
    final c = n.moveColor;
    final p = n.movePoint(widget.doc.size);
    if (c == null) return 'this position';
    return 'move ${n.moveNumber} (${c == Stone.black ? 'B' : 'W'} '
        '${p?.display(widget.doc.size) ?? 'tenuki'})';
  }

  Widget _treeSection(BuildContext context) {
    final theme = Theme.of(context);
    final s = _session;
    final branch = s.branch;
    return _Section(
      title: 'Tree',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                branch == null
                    ? Icons.account_tree_outlined
                    : Icons.filter_center_focus,
                size: 18,
                color: branch == null
                    ? theme.colorScheme.outline
                    : theme.colorScheme.tertiary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  branch == null
                      ? 'All lines. Click a move to train only from there.'
                      : 'Only the lines from ${_describeNode(branch)}.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (branch != null)
                TextButton(
                  onPressed: () => _chooseBranch(null),
                  child: const Text('All lines'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 340,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: GameTreeView(
                  root: widget.doc.root,
                  current: s.current,
                  marked: branch,
                  compact: true,
                  onSelect: _chooseBranch,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Applies options that don't require a new session.
  void _updateOptions(TrainerOptions o) {
    setState(() => _options = o);
    _session
      ..options = o
      ..optionsChanged();
  }

  @override
  void dispose() {
    if (_showEval) _analysisService.stopAnalysis();
    _session.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyH): () =>
            _session.showHint(),
        const SingleActivator(LogicalKeyboardKey.keyT): () =>
            _session.userPlay(null),
        const SingleActivator(LogicalKeyboardKey.keyN): () =>
            _session.nextLine(),
        const SingleActivator(LogicalKeyboardKey.space): () =>
            _session.nextLine(),
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (_session.lineDone) _session.nextLine();
        },
        // Arrow keys do nothing here (they must not move focus to a setting).
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {},
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {},
        const SingleActivator(LogicalKeyboardKey.arrowUp): () {},
        const SingleActivator(LogicalKeyboardKey.arrowDown): () {},
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: ListenableBuilder(
          listenable: _session,
          builder: (context, _) => LayoutBuilder(
            builder: (context, c) {
              if (_isPhone(context)) {
                return _phoneLayout(
                  board: _board(),
                  main: _mainColumn(context),
                  side: _sideColumn(context),
                );
              }
              if (c.maxWidth >= 900) {
                final side = (c.maxHeight * BoardView.aspect(_region)).clamp(
                  320.0,
                  c.maxWidth * 0.62,
                );
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: side,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Center(child: _board()),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: ExcludeFocus(child: _panel(context))),
                  ],
                );
              }
              return Column(
                children: [
                  Flexible(
                    flex: 3,
                    child: Padding(
                      padding: EdgeInsets.all(_isPhone(context) ? 4 : 8),
                      child: Center(child: _board()),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: ExcludeFocus(child: _panel(context)),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// The part of the board the joseki uses, in all its lines.
  BoardRegion? get _region => AppScope.read(context).zoomTraining
      ? josekiRegion(widget.doc.root, widget.doc.size, at: _session.current)
      : null;

  Widget _board() {
    final s = _session;
    final cur = s.current;
    final size = widget.doc.size;
    final markup = <Point, MarkupShape>{};
    for (final shape in MarkupShape.values) {
      for (final v in cur.getAll(shape.sgfId)) {
        final p = Point.fromSgf(v, size);
        if (p != null) markup[p] = shape;
      }
    }
    return BoardView(
      style: AppScope.of(context).boardStyle,
      region: _region,
      board: s.board,
      lastMove: cur.movePoint(size),
      markup: markup,
      labels: widget.doc.labelsOf(cur),
      hints: s.hints,
      wrongPoint: s.wrongPoint,
      mistake: switch (s.opponentMistake) {
        final m? when m.movePoint(size) != null => MistakeMark(
          m.movePoint(size)!,
          MoveQuality.of(m).color!,
          MoveQuality.of(m).symbol,
        ),
        _ => null,
      },
      hoverStone: s.userToMove ? _color : null,
      onTap: (p) {
        _focus.requestFocus();
        s.userPlay(p);
      },
    );
  }

  Widget _panel(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final main = _mainColumn(context);
        final settings = _sideColumn(context);
        if (c.maxWidth >= 720) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: main),
                const SizedBox(width: 20),
                Expanded(flex: 2, child: settings),
              ],
            ),
          );
        }
        return SingleChildScrollView(
          padding: EdgeInsets.all(_isPhone(context) ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [main, const SizedBox(height: 16), settings],
          ),
        );
      },
    );
  }

  Widget _mainColumn(BuildContext context) {
    final theme = Theme.of(context);
    final s = _session;
    final total = s.reachableLeaves.length;
    final attempts = s.correctMoves + s.mistakes;
    final accuracy = attempts == 0
        ? null
        : (100 * s.correctMoves / attempts).round();
    final phone = _isPhone(context);
    final buttons = _trainButtons(
      context,
      onNext: s.nextLine,
      onTenuki: s.userToMove ? () => s.userPlay(null) : null,
      onHint: s.userToMove ? s.showHint : null,
      onEdit: () => _editHere(context),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // On a phone the buttons are right under the board.
        if (phone) ...[buttons, const SizedBox(height: 12)],
        Row(
          children: [
            StoneIcon(_color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.doc.name,
                style: theme.textTheme.headlineSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${widget.doc.size}×${widget.doc.size}',
              style: theme.textTheme.titleSmall,
            ),
          ],
        ),
        if (_lineName(s.current) case final name?) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.alt_route, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        _FeedbackCard(
          feedback: s.feedback,
          waiting: s.waitingForOpponent,
          autoNext: s.autoNextPending,
          verdict: _aiVerdict,
        ),
        if (s.opponentMistake case final m?) ...[
          const SizedBox(height: 12),
          _MistakeBox(node: m, size: widget.doc.size),
        ],
        if (!phone) ...[const SizedBox(height: 12), buttons],
        const SizedBox(height: 20),
        _treeSection(context),
        const SizedBox(height: 20),
        _Section(
          title: 'Progress',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _BigStat(
                    'Correct',
                    '${s.correctMoves}',
                    const Color(0xFF2E9E44),
                  ),
                  _BigStat(
                    'Mistakes',
                    '${s.mistakes}',
                    const Color(0xFFD03030),
                  ),
                  _BigStat(
                    'Accuracy',
                    accuracy == null ? '-' : '$accuracy%',
                    null,
                  ),
                  _BigStat(
                    'Streak (best ${s.bestStreak})',
                    '${s.streak}',
                    s.streak >= 5 ? const Color(0xFFE08A00) : null,
                  ),
                  _BigStat('Lines done', '${s.linesCompleted}', null),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : s.linesCovered / total,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('${s.linesCovered} / $total lines covered'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Names of the named variations along the current line, e.g.
  /// "Taisha › Hane variation".
  static String? _lineName(SgfNode node) {
    final names = [for (final n in node.pathFromRoot) ?n.variationName];
    return names.isEmpty ? null : names.join('  ›  ');
  }

  Widget _settings(BuildContext context) {
    final theme = Theme.of(context);
    final state = AppScope.read(context);
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(t, style: theme.textTheme.labelLarge),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label('Play as'),
        ColorSelector(
          value: _color,
          onChanged: (c) {
            _color = c;
            _rebuildSession();
          },
        ),
        label('New lines start'),
        SegmentedButton<StartPoint>(
          segments: [
            for (final p in StartPoint.values)
              ButtonSegment(value: p, label: Text(p.label)),
          ],
          selected: {_options.start},
          onSelectionChanged: (v) =>
              _updateOptions(_options.copyWith(start: v.first)),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(child: Text('Start the next line automatically')),
            Switch(
              value: _options.autoNext,
              onChanged: (v) => _updateOptions(_options.copyWith(autoNext: v)),
            ),
          ],
        ),
        Row(
          children: [
            const Expanded(child: Text('Show how my Bad moves get punished')),
            Switch(
              value: _options.followMistakes,
              onChanged: (v) =>
                  _updateOptions(_options.copyWith(followMistakes: v)),
            ),
          ],
        ),
        ...[
          label(
            'Opponent mistakes: ${(_options.opponentMistakeRate * 100).round()}%',
          ),
          Slider(
            value: _options.opponentMistakeRate,
            divisions: 10,
            label: '${(_options.opponentMistakeRate * 100).round()}%',
            onChanged: (v) =>
                _updateOptions(_options.copyWith(opponentMistakeRate: v)),
          ),
          Text(
            'How often the opponent plays a move you marked Bad.',
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () => _chooseAnother(state),
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Train another opening'),
        ),
      ],
    );
  }

  void _chooseAnother(AppState state) {
    state.trainerTarget = null;
    state.goTo(AppSection.trainer);
  }

  /// Opens the opening in the editor, at the current trainer position.
  Future<void> _editHere(BuildContext context) =>
      _editAt(context, widget.doc, _session.current);
}

/// Calls out an opponent move marked Bad in the tree.
class _MistakeBox extends StatelessWidget {
  const _MistakeBox({required this.node, required this.size});
  final SgfNode node;
  final int size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = MoveQuality.of(node);
    final color = q.color!;
    final p = node.movePoint(size);
    final who = node.moveColor == Stone.black ? 'Black' : 'White';
    final comment = node.get('C');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Text(
                  q.symbol,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Opponent mistake: $who ${p?.display(size) ?? 'tenuki'} '
                  '(bad move)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            comment == null || comment.isEmpty
                ? 'Find the move that punishes it.'
                : comment,
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({
    required this.feedback,
    required this.waiting,
    required this.autoNext,
    this.verdict,
  });
  final TrainerFeedback feedback;
  final bool waiting;
  final bool autoNext;
  final (String, Color)? verdict;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, icon) = switch (feedback.kind) {
      FeedbackKind.correct => (const Color(0xFF2E9E44), Icons.check_circle),
      FeedbackKind.mistake => (const Color(0xFFD03030), Icons.cancel),
      FeedbackKind.notInRepertoire => (const Color(0xFFE08A00), Icons.help),
      FeedbackKind.illegal => (const Color(0xFFD03030), Icons.block),
      FeedbackKind.complete => (const Color(0xFF2F74D0), Icons.flag),
      FeedbackKind.info => (theme.colorScheme.primary, Icons.info_outline),
    };
    final comment = feedback.comment;
    return Container(
      constraints: BoxConstraints(minHeight: _isPhone(context) ? 0 : 96),
      padding: EdgeInsets.all(_isPhone(context) ? 12 : 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border(left: BorderSide(color: color, width: 5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  waiting ? 'Opponent is thinking…' : feedback.message,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (comment != null && comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(comment, style: theme.textTheme.bodyLarge),
          ],
          if (verdict case (final text, final c)?) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.psychology, size: 20, color: c),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: c,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (autoNext) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text('Next line starting…', style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// A small stone with its move number.
class _NumberedStone extends StatelessWidget {
  const _NumberedStone(this.stone, this.number);
  final Stone stone;
  final int number;

  @override
  Widget build(BuildContext context) {
    final black = stone == Stone.black;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: black ? const Color(0xFF151515) : const Color(0xFFF5F2EA),
        border: Border.all(color: const Color(0xFF777777)),
      ),
      child: Text(
        '$number',
        style: TextStyle(
          fontSize: number > 99 ? 8 : 10,
          fontWeight: FontWeight.w700,
          color: black ? Colors.white : Colors.black,
        ),
      ),
    );
  }
}

class _BigStat extends StatelessWidget {
  const _BigStat(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
