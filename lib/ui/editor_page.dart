import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../go/board.dart';
import '../go/point.dart';
import '../go/stone.dart';
import '../model/annotations.dart';
import '../model/library.dart';
import '../model/opening_document.dart';
import '../sgf/sgf_node.dart';
import '../analysis/analysis_service.dart';
import 'actions.dart';
import 'analysis_panel.dart';
import 'board_view.dart';
import 'tree_view.dart';

enum EditTool {
  play('Play moves (alternating)', Icons.ads_click),
  black('Add black stone', null),
  white('Add white stone', null),
  erase('Remove stone', Icons.backspace_outlined),
  triangle('Triangle', Icons.change_history),
  square('Square', Icons.crop_square),
  circle('Circle', Icons.circle_outlined),
  cross('X mark', Icons.close),
  letter('Letter label (A, B, C…)', Icons.abc),
  number('Number label (1, 2, 3…)', Icons.pin_outlined);

  const EditTool(this.tooltip, this.icon);
  final String tooltip;
  final IconData? icon;

  MarkupShape? get shape => switch (this) {
    triangle => MarkupShape.triangle,
    square => MarkupShape.square,
    circle => MarkupShape.circle,
    cross => MarkupShape.cross,
    _ => null,
  };
}

class EditorPage extends StatelessWidget {
  const EditorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final doc = AppScope.of(context).editorDoc;
    if (doc == null) return const _NoDocument();
    return _Editor(key: ObjectKey(doc), doc: doc);
  }
}

class _NoDocument extends StatelessWidget {
  const _NoDocument();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.edit_note,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          const Text('No opening or joseki open.'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () async {
                  final doc = await newOpeningDialog(context);
                  if (doc != null && context.mounted) {
                    await openInEditor(context, doc);
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('New opening or joseki'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    AppScope.read(context).goTo(AppSection.library),
                icon: const Icon(Icons.folder_open),
                label: const Text('Open from library'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Editor extends StatefulWidget {
  const _Editor({super.key, required this.doc});
  final OpeningDocument doc;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  EditTool _tool = EditTool.play;
  final _focus = FocusNode(debugLabel: 'editor');

  /// Editing the starting position (stones on the board before move 1).
  /// A new joseki opens in this mode.
  late bool _editStart =
      doc.hasStartPosition && doc.root.children.isEmpty && !doc.hasStartStones;
  Stone _startStone = Stone.black;

  /// A phone: the page scrolls, with the board as wide as the screen.
  bool get _isPhone => MediaQuery.sizeOf(context).width < 600;

  /// The move being moved to another place (the next click), if any.
  SgfNode? _replacing;

  /// Changing the place of the current move.
  bool get _isReplacing =>
      _replacing != null && _replacing == doc.current && !_editStart;

  /// KataGo analysis of the current position is shown.
  bool _analyze = false;
  late final AnalysisService _analysis = AppScope.read(context).analysis;

  OpeningDocument get doc => widget.doc;

  @override
  void initState() {
    super.initState();
    doc.addListener(_syncAnalysis);
  }

  @override
  void dispose() {
    doc.removeListener(_syncAnalysis);
    if (_analyze) _analysis.stopAnalysis();
    _focus.dispose();
    super.dispose();
  }

  void _toggleAnalysis() {
    setState(() => _analyze = !_analyze);
    _syncAnalysis();
  }

  void _syncAnalysis() {
    if (_analyze) {
      _analysis.analyze(positionsToAnalyze(doc.current), doc.size);
    } else {
      _analysis.stopAnalysis();
    }
  }

  // ------------------------------------------------------------- actions

  void _onBoardTap(Point p) {
    _focus.requestFocus();
    if (_editStart) {
      doc.toStart();
      doc.setStartStone(p, _startStone);
      return;
    }
    if (_isReplacing) {
      _replaceAt(p);
      return;
    }
    switch (_tool) {
      case EditTool.play:
        final r = doc.play(p);
        if (r != MoveResult.ok && r != MoveResult.occupied) {
          showMessage(context, 'Illegal move: ${r.name}');
        }
      case EditTool.black:
        doc.setupStone(p, Stone.black);
      case EditTool.white:
        doc.setupStone(p, Stone.white);
      case EditTool.erase:
        if (doc.board[p] != Stone.empty) doc.setupStone(p, Stone.empty);
      case EditTool.letter:
        doc.toggleLabel(p);
      case EditTool.number:
        doc.toggleLabel(p, numeric: true);
      case EditTool.triangle ||
          EditTool.square ||
          EditTool.circle ||
          EditTool.cross:
        doc.toggleMarkup(p, _tool.shape!);
    }
  }

  /// Starts (or stops) changing the place of the current move.
  void _toggleReplace() {
    final n = doc.current;
    setState(() => _replacing = _isReplacing || !n.hasMove ? null : n);
  }

  void _replaceAt(Point? p) {
    final n = _replacing!;
    final number = n.moveNumber;
    final (r, broken) = doc.replaceMove(p, n);
    if (r != MoveResult.ok) {
      showMessage(
        context,
        r == MoveResult.occupied
            ? p == null
                  ? 'Not possible: tenuki is already a variation here.'
                  : 'Not possible: there is a stone there, or this move is '
                        'already a variation here.'
            : 'Illegal move: ${r.name}',
      );
      return;
    }
    setState(() => _replacing = null);
    showMessage(
      context,
      broken == 0
          ? 'Move $number ${p == null ? 'is now a tenuki' : 'changed'}. '
                'The moves after it are kept '
                '(Ctrl+Z to undo).'
          : 'Move $number changed, but $broken move${broken == 1 ? ' after it is' : 's after it are'} '
                'no longer legal (on a stone, or now suicide). Check the '
                'lines after it, or Ctrl+Z to undo.',
    );
  }

  Future<void> _deleteBranch() async {
    final n = doc.current;
    if (n.isRoot) return;
    final after = n.descendants.where((d) => d.hasMove).length;
    final what = n.hasMove ? 'move ${n.moveNumber}' : 'this node';
    final ok = await confirm(
      context,
      'Delete',
      after == 0
          ? 'Delete $what?'
          : 'Delete $what and the $after move${after == 1 ? '' : 's'} after it?',
      ok: 'Delete',
    );
    if (ok) doc.deleteNode(n);
  }

  /// Right-click in the tree: name the variation at [node].
  Future<void> _renameVariation(SgfNode node) async {
    if (node.isRoot) return;
    doc.goTo(node);
    final name = await askText(
      context,
      'Rename variation ${node.variationNumber}',
      initial: node.variationName ?? '',
      label: 'Name (empty to remove)',
    );
    if (name != null) doc.renameVariation(node, name);
  }

  Future<void> _export() => saveTextFile(
    context,
    '${Library.sanitizeFileName(doc.name)}.sgf',
    doc.toSgf(),
    mimeType: 'application/x-go-sgf',
  );

  Future<void> _openFile() async {
    final files = await pickTextFiles(multiple: false);
    if (files.isEmpty || !mounted) return;
    final f = files.first;
    // Desktop: the file is edited in place. Web: a copy, saved in the
    // library.
    final OpeningDocument? d;
    if (f.path != null) {
      d = await loadDocument(context, f.path!);
    } else {
      try {
        d = OpeningDocument.fromSgf(f.text)..markDirty();
      } catch (e) {
        showMessage(context, 'Could not open ${f.name}: $e');
        return;
      }
    }
    if (d != null && mounted) await openInEditor(context, d);
  }

  Future<void> _close() async {
    if (!await resolveUnsaved(context)) return;
    if (mounted) AppScope.read(context).closeEditor();
  }

  /// A text field (name, comment…) has the keyboard focus.
  static bool get _typing =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorStateOfType<EditableTextState>() !=
      null;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    // While typing, keys belong to the text field (except Ctrl+S).
    if (_typing &&
        !(keyboard.isControlPressed &&
            event.logicalKey == LogicalKeyboardKey.keyS)) {
      return KeyEventResult.ignored;
    }
    for (final e in _shortcuts.entries) {
      if (e.key.accepts(event, keyboard)) {
        e.value();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
    const SingleActivator(LogicalKeyboardKey.arrowLeft): doc.back,
    const SingleActivator(LogicalKeyboardKey.arrowRight): doc.forward,
    const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
        doc.siblingVariation(-1),
    const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
        doc.siblingVariation(1),
    const SingleActivator(LogicalKeyboardKey.home): doc.toStart,
    const SingleActivator(LogicalKeyboardKey.end): doc.toEnd,
    const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
        saveDocument(context, doc),
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true): doc.undo,
    const SingleActivator(LogicalKeyboardKey.keyY, control: true): doc.redo,
    const SingleActivator(LogicalKeyboardKey.delete): _deleteBranch,
    const SingleActivator(LogicalKeyboardKey.keyR): _toggleReplace,
    const SingleActivator(LogicalKeyboardKey.escape): () {
      if (_replacing != null) setState(() => _replacing = null);
    },
    const SingleActivator(LogicalKeyboardKey.keyT): () {
      if (_isReplacing) {
        _replaceAt(null);
      } else if (!_editStart) {
        doc.play(null);
      }
    },
    CharacterActivator(AppScope.read(context).analysisKey): _toggleAnalysis,
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true):
        doc.redo,
  };

  void _setEditStart(bool on) {
    setState(() => _editStart = on);
    if (on) doc.toStart();
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: ListenableBuilder(
        listenable: Listenable.merge([doc, _analysis]),
        builder: (context, _) => LayoutBuilder(
          builder: (context, c) => c.maxWidth >= 1000
              ? _wide(context)
              : _isPhone
              ? _phone(context)
              : _narrow(context),
        ),
      ),
    );
  }

  Widget _wide(BuildContext context) {
    return Column(
      children: [
        _header(context),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              // The board column is just wide enough for a square board; the
              // tree gets all the remaining space.
              const chrome = 104.0; // toolbar + navigation rows
              final side = (c.maxHeight - chrome).clamp(
                320.0,
                c.maxWidth * 0.6,
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: side,
                    child: Column(
                      children: [
                        _toolbar(context),
                        Expanded(child: Center(child: _board())),
                        _navigation(context),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _nodePanel(context),
                        const Divider(height: 1),
                        _treeHeader(context),
                        Expanded(child: _tree()),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// Phone: everything in one scrolling page; the board is as wide as the
  /// screen, the notes and the tree are under it.
  Widget _phone(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: LayoutBuilder(
        builder: (context, c) => ListView(
          padding: EdgeInsets.zero,
          children: [
            _header(context),
            SizedBox(
              height: c.maxWidth,
              child: Padding(padding: const EdgeInsets.all(4), child: _board()),
            ),
            _navigation(context),
            _toolbar(context),
            const TabBar(
              tabs: [
                Tab(text: 'Notes'),
                Tab(text: 'Tree'),
              ],
            ),
            SizedBox(
              height: (c.maxHeight * 0.75).clamp(320.0, 900.0),
              child: TabBarView(
                children: [
                  SingleChildScrollView(child: _nodePanel(context)),
                  Column(
                    children: [
                      _treeHeader(context),
                      Expanded(child: _tree()),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _narrow(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          _header(context),
          _toolbar(context),
          Flexible(flex: 3, child: Center(child: _board())),
          _navigation(context),
          const TabBar(
            tabs: [
              Tab(text: 'Notes'),
              Tab(text: 'Tree'),
            ],
          ),
          Expanded(
            flex: 2,
            child: TabBarView(
              children: [
                SingleChildScrollView(child: _nodePanel(context)),
                Column(
                  children: [
                    _treeHeader(context),
                    Expanded(child: _tree()),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _controls(BuildContext context) => [
    if (doc.hasStartPosition)
      Tooltip(
        message: '${doc.kind.label}: you choose the color when you train',
        child: Chip(
          avatar: Icon(kindIcon(doc.kind), size: 18),
          label: Text(doc.kind.label),
        ),
      )
    else
      ColorSelector(value: doc.color, onChanged: doc.setColor),
    const SizedBox(width: 8),
    Tooltip(
      message: doc.hasMoves
          ? 'The board size can only be changed while the board is empty'
          : 'Board size',
      child: DropdownButton<int>(
        value: doc.size,
        underline: const SizedBox(),
        items: [
          for (final s in {...kBoardSizes, doc.size})
            DropdownMenuItem(value: s, child: Text('$s×$s')),
        ],
        onChanged: doc.hasMoves ? null : (v) => doc.setSize(v!),
      ),
    ),
    _analysisButton(context),
    const SizedBox(width: 4),
    IconButton(
      tooltip: 'Save (Ctrl+S)',
      onPressed: () => saveDocument(context, doc),
      icon: const Icon(Icons.save_outlined),
    ),
    FilledButton.tonalIcon(
      onPressed: () => AppScope.read(context).train(doc),
      icon: const Icon(Icons.school_outlined),
      label: const Text('Train'),
    ),
  ];

  /// Phone: the color, size and analysis of the file, in a sheet.
  void _fileSheet() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) => ListenableBuilder(
      listenable: doc,
      builder: (c, _) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Wrap(
          spacing: 8,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: _controls(c),
        ),
      ),
    ),
  );

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final name = Expanded(
      child: _NameField(key: ObjectKey(doc.root), doc: doc),
    );
    final dirty = <Widget>[
      if (doc.dirty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Tooltip(
            message: 'Unsaved changes',
            child: Icon(
              Icons.circle,
              size: 10,
              color: theme.colorScheme.tertiary,
            ),
          ),
        ),
    ];
    final controls = _controls(context);
    final menu = PopupMenuButton<String>(
      onSelected: (v) => switch (v) {
        'copy' => saveDocument(context, doc, asCopy: true),
        'export' => _export(),
        'open' => _openFile(),
        'new' => newOpeningDialog(context).then((d) {
          if (d != null && context.mounted) openInEditor(context, d);
        }),
        'close' => _close(),
        'file' => _fileSheet(),
        _ => null,
      },
      itemBuilder: (_) => [
        if (_isPhone)
          const PopupMenuItem(
            value: 'file',
            child: Text('Color, board size, analysis…'),
          ),
        const PopupMenuItem(
          value: 'new',
          child: Text('New opening or joseki…'),
        ),
        const PopupMenuItem(value: 'open', child: Text('Open SGF file…')),
        const PopupMenuItem(
          value: 'copy',
          child: Text('Save as copy in library'),
        ),
        const PopupMenuItem(value: 'export', child: Text('Export SGF…')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'close', child: Text('Close')),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: LayoutBuilder(
        builder: (context, c) {
          if (c.maxWidth >= 640) {
            return Row(
              children: [
                name,
                ...dirty,
                const SizedBox(width: 8),
                ...controls,
                menu,
              ],
            );
          }
          if (_isPhone) {
            // One row; the rest of the controls are in the menu.
            return Row(
              children: [
                name,
                ...dirty,
                IconButton(
                  tooltip: 'Save',
                  onPressed: () => saveDocument(context, doc),
                  icon: const Icon(Icons.save_outlined),
                ),
                IconButton(
                  tooltip: 'Train',
                  onPressed: () => AppScope.read(context).train(doc),
                  icon: const Icon(Icons.school_outlined),
                ),
                menu,
              ],
            );
          }
          // Narrow window: the name on its own line.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [name, ...dirty, menu]),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: controls,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _toolbar(BuildContext context) {
    if (_editStart) return _startToolbar(context);
    final scheme = Theme.of(context).colorScheme;
    Widget toolButton(EditTool t) {
      final selected = _tool == t;
      final Widget icon = switch (t) {
        EditTool.black => const _AddStoneIcon(Stone.black),
        EditTool.white => const _AddStoneIcon(Stone.white),
        _ => Icon(t.icon),
      };
      return IconButton(
        tooltip: t.tooltip,
        isSelected: selected,
        style: IconButton.styleFrom(
          backgroundColor: selected ? scheme.secondaryContainer : null,
        ),
        onPressed: () => setState(() => _tool = t),
        icon: icon,
      );
    }

    // Wraps on several rows when the board column is narrow, so no button
    // is ever hidden.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final t in EditTool.values.take(4)) toolButton(t),
          const SizedBox(height: 24, child: VerticalDivider()),
          for (final t in EditTool.values.skip(4)) toolButton(t),
          const SizedBox(height: 24, child: VerticalDivider()),
          IconButton(
            tooltip: 'Clear marks on this move',
            onPressed: doc.clearMarkup,
            icon: const Icon(Icons.layers_clear_outlined),
          ),
          _tenukiButton(),
          const SizedBox(height: 24, child: VerticalDivider()),
          IconButton(
            tooltip: 'Undo (Ctrl+Z)',
            onPressed: doc.canUndo ? doc.undo : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Redo (Ctrl+Y)',
            onPressed: doc.canRedo ? doc.redo : null,
            icon: const Icon(Icons.redo),
          ),
          const SizedBox(height: 24, child: VerticalDivider()),
          TextButton.icon(
            onPressed: () => _setEditStart(true),
            icon: const Icon(Icons.grid_on, size: 18),
            label: const Text('Start position'),
          ),
        ],
      ),
    );
  }

  Widget _analysisButton(BuildContext context) {
    final key = AppScope.of(context).analysisKey;
    return _analyze
        ? FilledButton.icon(
            onPressed: _toggleAnalysis,
            icon: const Icon(Icons.psychology),
            label: Text('Analyzing ($key)'),
          )
        : OutlinedButton.icon(
            onPressed: _toggleAnalysis,
            icon: const Icon(Icons.psychology_outlined),
            label: Text('Analyze ($key)'),
          );
  }

  /// Toolbar of the starting position editor.
  Widget _startToolbar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget stoneButton(Stone s, String tip, Widget icon) {
      final selected = _startStone == s;
      return IconButton(
        tooltip: tip,
        isSelected: selected,
        style: IconButton.styleFrom(
          backgroundColor: selected ? scheme.secondaryContainer : null,
        ),
        onPressed: () => setState(() => _startStone = s),
        icon: icon,
      );
    }

    return Container(
      color: scheme.tertiaryContainer.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 4,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Start position',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          stoneButton(
            Stone.black,
            'Black stone',
            const _AddStoneIcon(Stone.black),
          ),
          stoneButton(
            Stone.white,
            'White stone',
            const _AddStoneIcon(Stone.white),
          ),
          stoneButton(
            Stone.empty,
            'Remove stone',
            const Icon(Icons.backspace_outlined),
          ),
          IconButton(
            tooltip: 'Remove all stones',
            onPressed: doc.hasStartStones ? doc.clearStartPosition : null,
            icon: const Icon(Icons.layers_clear_outlined),
          ),
          const SizedBox(height: 24, child: VerticalDivider()),
          const Text('First move: '),
          const SizedBox(width: 6),
          SegmentedButton<Stone>(
            segments: const [
              ButtonSegment(
                value: Stone.black,
                icon: StoneIcon(Stone.black),
                label: Text('B'),
              ),
              ButtonSegment(
                value: Stone.white,
                icon: StoneIcon(Stone.white),
                label: Text('W'),
              ),
            ],
            selected: {doc.firstToPlay},
            showSelectedIcon: false,
            onSelectionChanged: (v) => doc.setFirstToPlay(v.first),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: () => _setEditStart(false),
            icon: const Icon(Icons.check),
            label: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _board() {
    final cur = doc.current;
    final size = doc.size;
    if (_isReplacing) return _replaceBoard(cur, size);
    final markup = <Point, MarkupShape>{};
    for (final s in MarkupShape.values) {
      for (final v in cur.getAll(s.sgfId)) {
        final p = Point.fromSgf(v, size);
        if (p != null) markup[p] = s;
      }
    }
    final variations = <VariationMark>[];
    for (var i = 0; i < cur.children.length; i++) {
      final c = cur.children[i];
      final p = c.movePoint(size);
      if (p == null) continue;
      final q = MoveQuality.of(c);
      variations.add(
        VariationMark(
          p,
          cur.children.length == 1 ? '' : String.fromCharCode(65 + i % 26),
          color: q == MoveQuality.interesting ? null : q.color,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: BoardView(
        style: AppScope.of(context).boardStyle,
        board: doc.board,
        lastMove: cur.movePoint(size),
        markup: markup,
        labels: doc.labelsOf(cur),
        variations: _editStart ? const [] : variations,
        analysis: switch (_analyze ? _analysis.resultFor(cur, size) : null) {
          final r? => analysisMarks(r),
          null => const [],
        },
        hoverStone: _editStart
            ? (_startStone == Stone.empty ? null : _startStone)
            : switch (_tool) {
                EditTool.play => doc.toPlay,
                EditTool.black => Stone.black,
                EditTool.white => Stone.white,
                _ => null,
              },
        onTap: _onBoardTap,
      ),
    );
  }

  /// The position before the move being changed, its old place crossed:
  /// a click puts it somewhere else.
  Widget _replaceBoard(SgfNode cur, int size) {
    final scheme = Theme.of(context).colorScheme;
    final old = cur.movePoint(size);
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.swap_horiz, color: scheme.onTertiaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Click the new place of move ${cur.moveNumber}, or '
                      'tenuki. Everything after it is kept.',
                      style: TextStyle(color: scheme.onTertiaryContainer),
                    ),
                  ),
                ],
              ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  if (!cur.isPass)
                    OutlinedButton.icon(
                      onPressed: () => _replaceAt(null),
                      icon: const Icon(Icons.call_split, size: 18),
                      label: const Text('Tenuki (T)'),
                    ),
                  TextButton(
                    onPressed: () => setState(() => _replacing = null),
                    child: const Text('Cancel (Esc)'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: BoardView(
              style: AppScope.of(context).boardStyle,
              board: positionAt(cur.parent!, size),
              lastMove: null,
              markup: {?old: MarkupShape.cross},
              labels: const {},
              variations: const [],
              analysis: const [],
              hoverStone: cur.moveColor,
              onTap: _onBoardTap,
            ),
          ),
        ),
      ],
    );
  }

  Widget _navigation(BuildContext context) {
    final cur = doc.current;
    final p = cur.parent;
    final siblings = p?.children.length ?? 1;
    final index = p == null ? 0 : p.children.indexOf(cur);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            tooltip: 'Start (Home)',
            onPressed: doc.toStart,
            icon: const Icon(Icons.first_page),
          ),
          IconButton(
            tooltip: 'Back (←)',
            onPressed: doc.back,
            icon: const Icon(Icons.chevron_left),
          ),
          SizedBox(
            width: 150,
            child: Text(
              _moveTitle(cur),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          IconButton(
            tooltip: 'Forward (→)',
            onPressed: doc.forward,
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            tooltip: 'End of line (End)',
            onPressed: doc.toEnd,
            icon: const Icon(Icons.last_page),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Previous variation (↑)',
            onPressed: index > 0 ? () => doc.siblingVariation(-1) : null,
            icon: const Icon(Icons.keyboard_arrow_up),
          ),
          Text('Var ${index + 1}/$siblings'),
          IconButton(
            tooltip: 'Next variation (↓)',
            onPressed: index < siblings - 1
                ? () => doc.siblingVariation(1)
                : null,
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
        ],
      ),
    );
  }

  /// Plays a tenuki: the move is played elsewhere on the board, so no stone
  /// here (a pass in the SGF). Highlighted when the tree has one.
  Widget _tenukiButton() {
    final exists = doc.current.children.any((c) => c.isPass);
    return Tooltip(
      message: exists
          ? 'A tenuki variation exists here (T)'
          : 'Play elsewhere: no stone on this board (T)',
      child: exists
          ? FilledButton.tonalIcon(
              onPressed: () => doc.play(null),
              icon: const Icon(Icons.call_split, size: 18),
              label: const Text('Tenuki'),
            )
          : TextButton(
              onPressed: () => doc.play(null),
              child: const Text('Tenuki'),
            ),
    );
  }

  String _moveTitle(SgfNode n) {
    final c = n.moveColor;
    if (c == null) return n.isRoot ? 'Start' : 'Setup';
    final p = n.movePoint(doc.size);
    return 'Move ${n.moveNumber}: ${c == Stone.black ? 'B' : 'W'} '
        '${p?.display(doc.size) ?? 'tenuki'}';
  }

  Widget _nodePanel(BuildContext context) {
    final theme = Theme.of(context);
    final cur = doc.current;
    final mc = cur.moveColor;
    // In a joseki both sides are studied: no "your move" notion.
    final bool? mine = doc.hasStartPosition ? null : mc == doc.color;
    if (_editStart && cur.isRoot) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Text(
          'Place the stones that are on the board before the first move '
          '(e.g. the corner stones of the joseki), choose who plays first, '
          'then click Done. Training and the tree start from this position.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(_moveTitle(cur), style: theme.textTheme.titleMedium),
              if (mc != null && mine != null)
                _Tag(
                  mine ? 'Your move' : "Opponent's move",
                  mine ? const Color(0xFF2E7D32) : const Color(0xFF8D5524),
                ),
              if (cur.children.length > 1)
                _Tag(
                  '${cur.children.length} replies',
                  theme.colorScheme.tertiary,
                ),
              if (mc != null) ...[
                const SizedBox(width: 8),
                _QualityToggle(
                  value: MoveQuality.of(cur),
                  mine: mine,
                  onChanged: doc.setMoveQuality,
                ),
              ],
            ],
          ),
          if (_analyze) ...[
            const SizedBox(height: 10),
            AnalysisPanel(doc: doc, service: _analysis),
          ],
          if (!cur.isRoot) ...[
            const SizedBox(height: 10),
            _VariationNameField(
              key: ValueKey(('name', cur)),
              doc: doc,
              node: cur,
            ),
          ],
          const SizedBox(height: 10),
          _CommentField(key: ValueKey(('comment', cur)), doc: doc),
        ],
      ),
    );
  }

  Widget _treeHeader(BuildContext context) {
    final cur = doc.current;
    // Up/down reorder the variation the current move belongs to.
    final start = cur.variationStart;
    final p = start?.parent;
    final i = start?.variationNumber ?? 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
      child: Row(
        children: [
          Text('Tree', style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          IconButton(
            tooltip: 'Move variation up',
            onPressed: p != null && i > 1
                ? () => doc.moveVariation(-1, start)
                : null,
            icon: const Icon(Icons.arrow_upward),
          ),
          IconButton(
            tooltip: 'Move variation down',
            onPressed: p != null && i < p.children.length
                ? () => doc.moveVariation(1, start)
                : null,
            icon: const Icon(Icons.arrow_downward),
          ),
          IconButton(
            tooltip: 'Change the place of this move, keeping what follows (R)',
            isSelected: _isReplacing,
            onPressed: cur.hasMove ? _toggleReplace : null,
            icon: const Icon(Icons.swap_horiz),
          ),
          IconButton(
            tooltip: 'Train only the lines from this move',
            onPressed: () => AppScope.read(context).train(doc, from: cur),
            icon: const Icon(Icons.school_outlined),
          ),
          IconButton(
            tooltip: 'Delete this move and everything after it (Del)',
            onPressed: cur.isRoot ? null : _deleteBranch,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  Widget _tree() {
    return Listener(
      onPointerDown: (_) => _focus.requestFocus(),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: GameTreeView.of(doc, onRename: _renameVariation),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color),
        color: color.withValues(alpha: 0.12),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, color: color)),
    );
  }
}

/// Bad button (unmarked moves are good). Clicking it again clears it.
class _QualityToggle extends StatelessWidget {
  const _QualityToggle({
    required this.value,
    required this.mine,
    required this.onChanged,
  });

  final MoveQuality value;

  /// Whether the move is the user's (null in a joseki: either side).
  final bool? mine;
  final ValueChanged<MoveQuality> onChanged;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outlineVariant;
    final badTip = switch (mine) {
      true => 'The trainer refuses this move and shows your comment',
      false => 'The trainer sometimes plays it so you learn to punish it',
      null => 'Refused when it is your move, sometimes played by the opponent',
    };
    Widget button(MoveQuality q, IconData icon, String label, String tip) {
      final selected = value == q;
      final color = q.color!;
      return Tooltip(
        message: tip,
        child: Material(
          color: selected ? color : Colors.transparent,
          shape: StadiumBorder(
            side: BorderSide(color: selected ? color : outline),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => onChanged(selected ? MoveQuality.none : q),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: selected ? Colors.white : color),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 6,
      children: [button(MoveQuality.bad, Icons.close, 'Bad', badTip)],
    );
  }
}

class _AddStoneIcon extends StatelessWidget {
  const _AddStoneIcon(this.stone);
  final Stone stone;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        children: [
          Center(child: StoneIcon(stone, size: 18)),
          const Positioned(
            right: 0,
            bottom: 0,
            child: Icon(Icons.add, size: 12),
          ),
        ],
      ),
    );
  }
}

class _NameField extends StatefulWidget {
  const _NameField({super.key, required this.doc});
  final OpeningDocument doc;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final _ctrl = TextEditingController(text: widget.doc.name);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      style: Theme.of(context).textTheme.titleLarge,
      decoration: const InputDecoration(
        border: InputBorder.none,
        hintText: 'Opening name',
        isDense: true,
      ),
      onChanged: widget.doc.setName,
    );
  }
}

class _VariationNameField extends StatefulWidget {
  const _VariationNameField({super.key, required this.doc, required this.node});
  final OpeningDocument doc;
  final SgfNode node;

  @override
  State<_VariationNameField> createState() => _VariationNameFieldState();
}

class _VariationNameFieldState extends State<_VariationNameField> {
  late final _ctrl = TextEditingController(
    text: widget.node.variationName ?? '',
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    return TextField(
      controller: _ctrl,
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 12, right: 8),
          child: Text(
            'Variation ${node.variationNumber}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(),
        hintText: 'Name this variation',
      ),
      onChanged: (v) => widget.doc.renameVariation(node, v),
    );
  }
}

class _CommentField extends StatefulWidget {
  const _CommentField({super.key, required this.doc});
  final OpeningDocument doc;

  @override
  State<_CommentField> createState() => _CommentFieldState();
}

class _CommentFieldState extends State<_CommentField> {
  late final _ctrl = TextEditingController(
    text: widget.doc.current.get('C') ?? '',
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      minLines: 2,
      maxLines: 5,
      decoration: const InputDecoration(
        labelText: 'Comment',
        hintText: 'Why is this move good or bad? What should you remember?',
        border: OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
      onChanged: widget.doc.setComment,
    );
  }
}
