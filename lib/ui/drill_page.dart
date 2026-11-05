part of 'trainer_page.dart';

/// The "Global" tab: the global trainer, with the progress of every file.
class GlobalTrainerPage extends StatelessWidget {
  const GlobalTrainerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final d = state.drill;
    if (d == null) {
      if (!state.drillLoading) {
        WidgetsBinding.instance.addPostFrameCallback((_) => state.openDrill());
      }
      return const Center(child: CircularProgressIndicator());
    }
    return _DrillView(key: ObjectKey(d), drill: d);
  }
}

/// The global trainer: every line of every joseki, at random.
class _DrillView extends StatefulWidget {
  const _DrillView({super.key, required this.drill});
  final DrillSession drill;

  @override
  State<_DrillView> createState() => _DrillViewState();
}

class _DrillViewState extends State<_DrillView> {
  final _focus = FocusNode(debugLabel: 'drill');
  DrillSession get d => widget.drill;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyH): () =>
            d.session?.showHint(),
        const SingleActivator(LogicalKeyboardKey.keyT): () =>
            d.session?.userPlay(null),
        const SingleActivator(LogicalKeyboardKey.keyN): d.next,
        const SingleActivator(LogicalKeyboardKey.space): d.next,
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (d.round != null) d.next();
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {},
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {},
        const SingleActivator(LogicalKeyboardKey.arrowUp): () {},
        const SingleActivator(LogicalKeyboardKey.arrowDown): () {},
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: ListenableBuilder(
          listenable: d,
          builder: (context, _) => LayoutBuilder(
            builder: (context, outer) {
              _wide = outer.maxWidth >= 1150;
              if (!_wide) return _trainArea(context);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 330,
                    child: ExcludeFocus(child: _sidebar(context)),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: _trainArea(context)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// The files list is on the side (wide window) or in the panel.
  bool _wide = false;

  Widget _trainArea(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      if (c.maxWidth >= 900) {
        final side = c.maxHeight.clamp(320.0, c.maxWidth * 0.62);
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
              padding: const EdgeInsets.all(8),
              child: Center(child: _board()),
            ),
          ),
          Expanded(flex: 2, child: ExcludeFocus(child: _panel(context))),
        ],
      );
    },
  );

  Widget _board() {
    final s = d.session;
    final l = d.line;
    if (s == null || l == null) {
      return const AspectRatio(aspectRatio: 1, child: SizedBox());
    }
    final doc = l.doc.doc;
    final size = doc.size;
    final cur = s.current;
    final markup = <Point, MarkupShape>{};
    for (final shape in MarkupShape.values) {
      for (final v in cur.getAll(shape.sgfId)) {
        final p = Point.fromSgf(v, size);
        if (p != null) markup[p] = shape;
      }
    }
    return BoardView(
      style: AppScope.of(context).boardStyle,
      board: s.board,
      lastMove: cur.movePoint(size),
      markup: markup,
      labels: doc.labelsOf(cur),
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
      hoverStone: s.userToMove ? l.color : null,
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
        final side = _sideColumn(context);
        if (c.maxWidth >= 720) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: main),
                const SizedBox(width: 20),
                Expanded(flex: 2, child: side),
              ],
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [main, const SizedBox(height: 16), side],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------- main column

  Widget _mainColumn(BuildContext context) {
    final theme = Theme.of(context);
    final state = AppScope.read(context);
    final s = d.session;
    final l = d.line;
    final files = d.lines.map((l) => l.doc).toSet().length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.all_inclusive,
              size: 28,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Global trainer',
                style: theme.textTheme.headlineSmall,
              ),
            ),
            Tooltip(
              message: 'Read the library again (after editing files)',
              child: TextButton.icon(
                onPressed: state.startDrill,
                icon: const Icon(Icons.refresh),
                label: const Text('Reload'),
              ),
            ),
          ],
        ),
        Text(
          '${d.lines.length} lines from $files file${files == 1 ? '' : 's'}, '
          'at random. A missed line comes back until you play it without '
          'mistake.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        if (s == null || l == null)
          _nothingToTrain(context)
        else ...[
          _lineCard(context, l),
          const SizedBox(height: 12),
          _FeedbackCard(
            feedback: s.feedback,
            waiting: s.waitingForOpponent,
            autoNext: d.autoNextPending,
          ),
          if (s.opponentMistake case final m?) ...[
            const SizedBox(height: 12),
            _MistakeBox(node: m, size: l.doc.doc.size),
          ],
          if (d.round case final r?) ...[
            const SizedBox(height: 12),
            _RoundBanner(round: r),
          ],
          if (d.notice case final n?) ...[
            const SizedBox(height: 8),
            Text(
              n,
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: d.next,
                icon: const Icon(Icons.skip_next),
                label: const Text('Next line (N)'),
              ),
              OutlinedButton.icon(
                onPressed: s.userToMove ? () => s.userPlay(null) : null,
                icon: const Icon(Icons.call_split),
                label: const Text('Tenuki (T)'),
              ),
              OutlinedButton.icon(
                onPressed: s.userToMove ? s.showHint : null,
                icon: const Icon(Icons.lightbulb_outline),
                label: const Text('Hint (H)'),
              ),
              OutlinedButton.icon(
                onPressed: () => _editAt(context, l.doc.doc, s.current),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit here'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        _Section(title: 'Your knowledge', child: _knowledge(context)),
        const SizedBox(height: 20),
        _Section(title: 'This session', child: _sessionStats()),
      ],
    );
  }

  Widget _nothingToTrain(BuildContext context) {
    final theme = Theme.of(context);
    final kinds = d.settings.kinds.map((k) => k.plural).join(', ');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        d.docs.isEmpty
            ? 'Your library is empty. Create some joseki first.'
            : 'No line to train in your $kinds. Change the settings, or add '
                  'moves for the color you play.',
        style: theme.textTheme.bodyLarge,
      ),
    );
  }

  /// The joseki and line being played.
  Widget _lineCard(BuildContext context, DrillLine l) {
    final theme = Theme.of(context);
    final accent = kindAccent(l.doc.kind, l.color);
    final rec = d.recordOf(l);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              KindTag(
                kind: l.doc.kind,
                color: l.doc.kind.hasStartPosition ? null : l.color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l.doc.name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (d.reason case final why?) _ReasonChip(why),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              StoneIcon(l.color, size: 18),
              const SizedBox(width: 6),
              Text(
                'You play ${l.color.label}',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(width: 12),
              Icon(Icons.alt_route, size: 16, color: theme.colorScheme.outline),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  l.name,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _MasteryDots(rec),
            ],
          ),
        ],
      ),
    );
  }

  Widget _knowledge(BuildContext context) {
    final theme = Theme.of(context);
    final total = d.lines.length;
    final known = d.knownLines;
    final mastery = d.docMastery;
    final docsLabel = d.settings.kinds.length == 1
        ? d.settings.kinds.first.plural
        : 'Files';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _BigStat('Lines known', '$known / $total', const Color(0xFF2E9E44)),
            _BigStat(
              '$docsLabel known',
              '${d.knownDocs} / ${mastery.length}',
              const Color(0xFF13A08A),
            ),
            _BigStat(
              'To fix',
              '${d.mistakeLines.length}',
              d.mistakeLines.isEmpty ? null : const Color(0xFFD03030),
            ),
            _BigStat('New', '${d.newLines}', null),
            _BigStat(
              'To review',
              '${d.dueLines()}',
              d.dueLines() == 0 ? null : const Color(0xFFE08A00),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: total == 0 ? 0 : known / total,
          minHeight: 10,
          color: const Color(0xFF2E9E44),
          borderRadius: BorderRadius.circular(5),
        ),
        const SizedBox(height: 8),
        Text(
          'A line is known after $kKnownStreak runs in a row without mistake '
          'or hint. Known lines come back for review after a few days.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _sessionStats() {
    final accuracy = d.rounds == 0
        ? '-'
        : '${(100 * d.cleanRounds / d.rounds).round()}%';
    return Row(
      children: [
        _BigStat('Lines played', '${d.rounds}', null),
        _BigStat('Clean', accuracy, const Color(0xFF2E9E44)),
        _BigStat(
          'Mistakes',
          '${d.mistakes}',
          d.mistakes == 0 ? null : const Color(0xFFD03030),
        ),
        _BigStat('Fixed', '${d.fixed.length}', const Color(0xFF2F74D0)),
        _BigStat(
          'Streak (best ${d.bestStreak})',
          '${d.streak}',
          d.streak >= 5 ? const Color(0xFFE08A00) : null,
        ),
      ],
    );
  }

  // ---------------------------------------------------------- side column

  Widget _sideColumn(BuildContext context) {
    final mistakes = d.mistakeLines;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(
          title: mistakes.isEmpty
              ? 'Mistakes to fix'
              : 'Mistakes to fix (${mistakes.length})',
          child: _mistakeList(context, mistakes),
        ),
        if (!_wide) ...[
          const SizedBox(height: 16),
          _Section(
            title: 'By file',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _docTiles(context),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _Section(title: 'Settings', child: _settings(context)),
      ],
    );
  }

  Widget _mistakeList(BuildContext context, List<DrillLine> lines) {
    final theme = Theme.of(context);
    if (lines.isEmpty) {
      return Text(
        'Nothing to fix right now.',
        style: theme.textTheme.bodyMedium,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final l in lines.take(10))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                StoneIcon(l.color, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.doc.name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        l.name,
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD03030).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Tooltip(
                    message: 'Mistakes made in this line',
                    child: Text(
                      '×${d.recordOf(l)!.mistakes}',
                      style: const TextStyle(
                        color: Color(0xFFD03030),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => d.play(l),
                  child: const Text('Play'),
                ),
              ],
            ),
          ),
        if (lines.length > 10)
          Text(
            '… and ${lines.length - 10} more',
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }

  /// Sort the files by name, or the least learned first.
  bool _byProgress = false;

  /// Every file with how much of it is learned; a click trains only it.
  Widget _sidebar(BuildContext context) {
    final theme = Theme.of(context);
    final pct = (100 * d.learned).round();
    final docs = d.docStats;
    final toFix = d.mistakeLines.length;
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('What you know', style: theme.textTheme.titleLarge),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      '$pct%',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: _learnedColor(d.learned, theme),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${d.knownLines} / ${d.lines.length} lines known',
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            '${docs.where((x) => x.allKnown).length} / '
                            '${docs.length} files fully known',
                            style: theme.textTheme.bodySmall,
                          ),
                          if (toFix > 0)
                            Text(
                              '$toFix line${toFix == 1 ? '' : 's'} to fix',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFFD03030),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: d.learned,
                  minHeight: 8,
                  color: _learnedColor(d.learned, theme),
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Click a file to train only it.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _byProgress = !_byProgress),
                      icon: const Icon(Icons.sort, size: 18),
                      label: Text(_byProgress ? 'Least known' : 'A–Z'),
                    ),
                  ],
                ),
                if (d.only case final o?)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InputChip(
                      avatar: const Icon(Icons.filter_alt, size: 18),
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(
                          'Only: ${o.name}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      onDeleted: () => d.focusDoc(null),
                      deleteButtonTooltipMessage: 'Train every file',
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
              children: _docTiles(context),
            ),
          ),
        ],
      ),
    );
  }

  static Color _learnedColor(double v, ThemeData theme) => v >= 1
      ? const Color(0xFF2E9E44)
      : v >= 0.5
      ? const Color(0xFF13A08A)
      : v > 0
      ? const Color(0xFFE08A00)
      : theme.colorScheme.outline;

  /// One tile per file, grouped by kind (joseki, tricks, openings).
  List<Widget> _docTiles(BuildContext context) {
    final theme = Theme.of(context);
    final stats = d.docStats;
    if (_byProgress) {
      stats.sort((a, b) => a.learned.compareTo(b.learned));
    }
    if (stats.isEmpty) {
      return [Text('No file.', style: theme.textTheme.bodyMedium)];
    }
    final out = <Widget>[];
    for (final kind in DocumentKind.values) {
      final group = stats.where((x) => x.doc.kind == kind).toList();
      if (group.isEmpty) continue;
      final accent = kindAccent(kind, null);
      final ink = Color.lerp(accent, theme.colorScheme.onSurface, 0.3)!;
      out.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 12, 6, 4),
          child: Row(
            children: [
              Icon(kindIcon(kind), size: 18, color: ink),
              const SizedBox(width: 6),
              Text(
                '${kind.plural} (${group.length})',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Divider(color: accent.withValues(alpha: 0.5))),
            ],
          ),
        ),
      );
      for (final st in group) {
        out.add(_docTile(context, st));
      }
    }
    return out;
  }

  Widget _docTile(BuildContext context, DocStats st) {
    final theme = Theme.of(context);
    final doc = st.doc;
    final selected = d.only == doc;
    final playing = d.line?.doc == doc;
    final accent = kindAccent(doc.kind, doc.doc.color);
    final color = _learnedColor(st.learned, theme);
    final pct = (100 * st.learned).round();
    final small = theme.textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected
            ? accent.withValues(alpha: 0.18)
            : playing
            ? theme.colorScheme.surfaceContainerHighest
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: selected
              ? BorderSide(color: accent, width: 1.5)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => d.focusDoc(selected ? null : doc),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    KindIcon(
                      kind: doc.kind,
                      color: doc.kind.hasStartPosition ? null : doc.doc.color,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        doc.name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (playing)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Tooltip(
                          message: 'Being played',
                          child: Icon(
                            Icons.play_arrow,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    if (st.allKnown)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.verified,
                          size: 18,
                          color: Color(0xFF2E9E44),
                        ),
                      ),
                    Text(
                      '$pct%',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                LinearProgressIndicator(
                  value: st.learned,
                  minHeight: 6,
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    Text('${st.known}/${st.total} lines known', style: small),
                    if (st.failing > 0)
                      Text(
                        '${st.failing} to fix',
                        style: small?.copyWith(
                          color: const Color(0xFFD03030),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (st.fresh > 0)
                      Text(
                        '${st.fresh} new',
                        style: small?.copyWith(color: const Color(0xFF2F74D0)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _settings(BuildContext context) {
    final theme = Theme.of(context);
    final st = d.settings;
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(t, style: theme.textTheme.labelLarge),
    );
    Widget toggle(String text, bool value, ValueChanged<bool> on) => Row(
      children: [
        Expanded(child: Text(text)),
        Switch(value: value, onChanged: on),
      ],
    );
    int count(DocumentKind k) => d.docs.where((x) => x.kind == k).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label('Train on'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final k in DocumentKind.values)
              FilterChip(
                avatar: Icon(kindIcon(k), size: 18),
                label: Text('${k.plural} (${count(k)})'),
                selected: st.kinds.contains(k),
                onSelected: (on) {
                  final kinds = {...st.kinds};
                  on ? kinds.add(k) : kinds.remove(k);
                  if (kinds.isEmpty) return;
                  d.updateSettings(st.copyWith(kinds: kinds));
                },
              ),
          ],
        ),
        label('Play joseki and tricks as'),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'B',
              label: Text('Black'),
              icon: StoneIcon(Stone.black),
            ),
            ButtonSegment(
              value: 'W',
              label: Text('White'),
              icon: StoneIcon(Stone.white),
            ),
            ButtonSegment(value: 'BW', label: Text('Both')),
          ],
          selected: {st.colors.length == 2 ? 'BW' : st.colors.first.sgf},
          showSelectedIcon: false,
          onSelectionChanged: (v) => d.updateSettings(
            st.copyWith(
              colors: {
                if (v.first.contains('B')) Stone.black,
                if (v.first.contains('W')) Stone.white,
              },
            ),
          ),
        ),
        label('Choose the lines'),
        SegmentedButton<DrillFocus>(
          segments: [
            for (final f in DrillFocus.values)
              ButtonSegment(value: f, label: Text(f.label)),
          ],
          selected: {st.focus},
          showSelectedIcon: false,
          onSelectionChanged: (v) =>
              d.updateSettings(st.copyWith(focus: v.first)),
        ),
        const SizedBox(height: 4),
        Text(switch (st.focus) {
          DrillFocus.smart =>
            'Mostly your mistakes, new lines and lines to review, with '
                'some known lines.',
          DrillFocus.mistakes => 'Only the lines you missed last time.',
          DrillFocus.unknown => 'Only the lines you do not know yet.',
        }, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        toggle(
          'Include lines where the opponent plays a Bad move',
          st.opponentMistakes,
          (v) => d.updateSettings(st.copyWith(opponentMistakes: v)),
        ),
        toggle(
          'Show how my Bad moves get punished',
          st.showPunishment,
          (v) => d.updateSettings(st.copyWith(showPunishment: v)),
        ),
        toggle(
          'Start the next line automatically',
          st.autoNext,
          (v) => d.updateSettings(st.copyWith(autoNext: v)),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFD03030)),
          onPressed: () async {
            if (await confirm(
              context,
              'Reset the progress',
              'Forget which lines you know and your mistakes?',
              ok: 'Reset',
            )) {
              d.resetProgress();
            }
          },
          icon: const Icon(Icons.restart_alt),
          label: const Text('Reset my progress'),
        ),
      ],
    );
  }
}

/// Why the line was chosen.
class _ReasonChip extends StatelessWidget {
  const _ReasonChip(this.reason);
  final DrillReason reason;

  @override
  Widget build(BuildContext context) {
    final (text, color, icon) = switch (reason) {
      DrillReason.retry => (
        'Mistake to fix',
        const Color(0xFFD03030),
        Icons.replay,
      ),
      DrillReason.failing => (
        'Missed last time',
        const Color(0xFFD03030),
        Icons.history,
      ),
      DrillReason.fresh => (
        'New line',
        const Color(0xFF2F74D0),
        Icons.fiber_new,
      ),
      DrillReason.learning => (
        'Learning',
        const Color(0xFFE08A00),
        Icons.trending_up,
      ),
      DrillReason.review => (
        'Review',
        const Color(0xFF13A08A),
        Icons.event_repeat,
      ),
      DrillReason.extra => ('Known', const Color(0xFF2E9E44), Icons.verified),
      DrillReason.chosen => (
        'Your choice',
        const Color(0xFF888888),
        Icons.touch_app,
      ),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 9, 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Clean runs in a row toward "known".
class _MasteryDots extends StatelessWidget {
  const _MasteryDots(this.record);
  final LineRecord? record;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final n = min(r?.streak ?? 0, kKnownStreak);
    final known = r?.known ?? false;
    const green = Color(0xFF2E9E44);
    return Tooltip(
      message: r == null
          ? 'Never played'
          : known
          ? 'Known (${r.streak} clean runs in a row)'
          : '${r.streak} / $kKnownStreak clean runs in a row',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < kKnownStreak; i++)
            Container(
              width: 11,
              height: 11,
              margin: const EdgeInsets.only(left: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < n ? green : Colors.transparent,
                border: Border.all(color: green, width: 1.5),
              ),
            ),
          if (known) ...[
            const SizedBox(width: 4),
            const Icon(Icons.verified, size: 16, color: green),
          ],
        ],
      ),
    );
  }
}

/// The verdict at the end of a line.
class _RoundBanner extends StatelessWidget {
  const _RoundBanner({required this.round});
  final DrillRound round;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = round;
    final rec = r.record;
    final days = reviewInterval(rec.streak).inDays;
    final (color, icon, text) = r.newlyKnown
        ? (
            const Color(0xFFE0A030),
            Icons.emoji_events,
            'Known! $kKnownStreak clean runs in a row. '
                'It comes back for review in $days days.',
          )
        : r.clean && rec.known
        ? (
            const Color(0xFF2E9E44),
            Icons.verified,
            'Clean again (${rec.streak} in a row). Next review in $days days.',
          )
        : r.clean
        ? (
            const Color(0xFF2E9E44),
            Icons.check_circle,
            'Clean! ${rec.streak} / $kKnownStreak toward known.',
          )
        : r.mistakes == 0
        ? (
            const Color(0xFFE08A00),
            Icons.lightbulb,
            'Hint used: not clean. This line comes back soon.',
          )
        : (
            const Color(0xFFD03030),
            Icons.replay,
            '${r.mistakes} mistake${r.mistakes == 1 ? '' : 's'}'
                '${r.wasKnown ? ' in a line you knew' : ''}. '
                'It comes back in a few lines until you play it cleanly.',
          );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens [src] in the editor at [node] (same place in the tree).
Future<void> _editAt(
  BuildContext context,
  OpeningDocument src,
  SgfNode node,
) async {
  final state = AppScope.read(context);
  final path = <int>[];
  var n = node;
  while (n.parent != null) {
    path.add(n.parent!.children.indexOf(n));
    n = n.parent!;
  }
  final editor = state.editorDoc;
  final sameFile =
      editor != null &&
      editor.filePath != null &&
      editor.filePath == src.filePath;
  final OpeningDocument doc;
  if (sameFile) {
    doc = editor;
  } else {
    if (!await resolveUnsaved(context)) return;
    doc = OpeningDocument.fromSgf(src.toSgf(), filePath: src.filePath);
  }
  var target = doc.root;
  for (final i in path.reversed) {
    if (i >= target.children.length) break;
    target = target.children[i];
  }
  doc.goTo(target);
  state.openInEditor(doc);
}
