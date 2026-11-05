import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../go/point.dart';
import '../go/stone.dart';
import '../model/library.dart';
import '../model/opening_document.dart';
import '../sgf/sgf_node.dart';
import '../storage/storage.dart';
import 'actions.dart';
import 'account.dart';
import 'app_logo.dart';
import '../main.dart' show showSettings;
import 'board_view.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

/// A group of the library list.
enum _Group {
  black('Openings · Black'),
  white('Openings · White'),
  opening('Openings (no color)'),
  joseki('Joseki'),
  tricks('Tricks'),
  unreadable('Unreadable files');

  const _Group(this.title);
  final String title;

  static _Group of(LibraryEntry e) {
    if (e.error != null) return unreadable;
    if (e.kind == DocumentKind.joseki) return joseki;
    if (e.kind == DocumentKind.tricks) return tricks;
    return switch (e.color) {
      Stone.black => black,
      Stone.white => white,
      _ => opening,
    };
  }

  Color get accent => switch (this) {
    black => kindAccent(DocumentKind.opening, Stone.black),
    white => kindAccent(DocumentKind.opening, Stone.white),
    joseki => kindAccent(DocumentKind.joseki, null),
    tricks => kindAccent(DocumentKind.tricks, null),
    _ => const Color(0xFF888888),
  };
}

class _LibraryPageState extends State<LibraryPage> {
  String _query = '';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Stone? _color;
  DocumentKind? _kind;
  int? _size;

  /// Path of the entry shown in the preview.
  String? _selected;

  /// Phone: the filters are shown (folded by default).
  bool _showFilters = false;

  /// No navigation rail: a phone, or a very narrow window.
  bool _narrow(BuildContext context) => MediaQuery.sizeOf(context).width < 700;

  bool get _filtering => _color != null || _kind != null || _size != null;
  final Set<_Group> _collapsed = {};

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final lib = state.library;
    return ListenableBuilder(
      listenable: Listenable.merge([lib, state.cloud]),
      builder: (context, _) {
        final entries = lib.entries.where((e) {
          if (_color != null && e.color != _color) return false;
          if (_kind != null && e.kind != _kind) return false;
          if (_size != null && e.size != _size) return false;
          final q = _query.toLowerCase();
          return q.isEmpty ||
              e.name.toLowerCase().contains(q) ||
              e.relativePath.toLowerCase().contains(q);
        }).toList();
        // Phone: the header and filters scroll away with the list.
        if (_narrow(context) && entries.isNotEmpty) {
          return _list(
            context,
            lib,
            entries,
            null,
            leading: [
              _header(context, lib),
              _filters(context, lib),
              const Divider(height: 1),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, lib),
            _filters(context, lib),
            const Divider(height: 1),
            Expanded(
              child: lib.loading && lib.entries.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : entries.isEmpty
                  ? _empty(context, lib.entries.isEmpty)
                  : LayoutBuilder(
                      builder: (context, c) {
                        final wide = c.maxWidth >= 980;
                        if (!wide) return _list(context, lib, entries, null);
                        // The selected entry, or the first one.
                        final readable = entries.where((e) => e.error == null);
                        final shown =
                            readable
                                .where((e) => e.path == _selected)
                                .firstOrNull ??
                            readable.firstOrNull;
                        final list = _list(context, lib, entries, shown);
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: list),
                            const VerticalDivider(width: 1),
                            SizedBox(
                              width: (c.maxWidth * 0.4).clamp(380.0, 520.0),
                              child: shown == null
                                  ? const SizedBox()
                                  : _Preview(
                                      key: ValueKey(shown.path),
                                      entry: shown,
                                      onTrain: () => _train(context, shown),
                                      onEdit: () => _edit(context, shown),
                                    ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  /// The entries in groups (Black openings, White openings, joseki…), each
  /// with a header that folds it.
  Widget _list(
    BuildContext context,
    Library lib,
    List<LibraryEntry> entries,
    LibraryEntry? shown, {
    List<Widget> leading = const [],
  }) {
    final groups = <_Group, List<LibraryEntry>>{};
    for (final e in entries) {
      (groups[_Group.of(e)] ??= []).add(e);
    }
    final items = <Widget>[...leading];
    for (final g in _Group.values) {
      final list = groups[g];
      if (list == null) continue;
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      items.add(_groupHeader(context, g, list.length));
      if (_collapsed.contains(g)) continue;
      for (final e in list) {
        items.add(_tile(context, lib, e, shown));
      }
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: items.length,
      itemBuilder: (c, i) => items[i],
    );
  }

  Widget _groupHeader(BuildContext context, _Group g, int count) {
    final theme = Theme.of(context);
    final ink = Color.lerp(g.accent, theme.colorScheme.onSurface, 0.3)!;
    final folded = _collapsed.contains(g);
    return InkWell(
      onTap: () => setState(() {
        if (!_collapsed.remove(g)) _collapsed.add(g);
      }),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 6),
        child: Row(
          children: [
            Icon(folded ? Icons.chevron_right : Icons.expand_more, color: ink),
            const SizedBox(width: 4),
            switch (g) {
              _Group.black => const StoneIcon(Stone.black, size: 18),
              _Group.white => const StoneIcon(Stone.white, size: 18),
              _Group.joseki => Icon(Icons.crop_free, size: 20, color: ink),
              _Group.tricks => Icon(Icons.auto_fix_high, size: 20, color: ink),
              _Group.opening => Icon(Icons.help_outline, size: 20, color: ink),
              _Group.unreadable => Icon(
                Icons.error_outline,
                size: 20,
                color: ink,
              ),
            },
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                g.title,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(
                color: g.accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(color: ink, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Divider(color: g.accent.withValues(alpha: 0.5))),
          ],
        ),
      ),
    );
  }

  /// Where the files are kept, under the title.
  String _whereKept(Library lib) {
    if (AppScope.read(context).cloud.signedIn) {
      return 'Synced with your account.';
    }
    return storage.inBrowser
        ? 'Kept in this browser. Sign in or back up to keep it safe.'
        : lib.directory ?? '';
  }

  /// Phone: the title with the account and settings on the right, then the
  /// two main actions; the rest is in a menu.
  Widget _phoneHeader(BuildContext context, Library lib) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const AppLogo(size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Library', style: theme.textTheme.headlineSmall),
              ),
              const AccountButton(),
              IconButton(
                tooltip: 'Settings',
                onPressed: () => showSettings(context),
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
          Text(_whereKept(lib), style: theme.textTheme.bodySmall),
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.icon(
                onPressed: () => _newOpening(context),
                icon: const Icon(Icons.add),
                label: const Text('New'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: () => AppScope.read(context).openDrill(),
                    icon: const Icon(Icons.all_inclusive),
                    label: const Text(
                      'Train all joseki',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (v) => switch (v) {
                  'import' => _import(context, lib),
                  'backup' => _backup(context),
                  'restore' => _restore(context),
                  _ => lib.refresh(),
                },
                itemBuilder: (c) => const [
                  PopupMenuItem(
                    value: 'import',
                    child: ListTile(
                      leading: Icon(Icons.file_download_outlined),
                      title: Text('Import SGF'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'backup',
                    child: ListTile(
                      leading: Icon(Icons.download),
                      title: Text('Back up library and progress'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'restore',
                    child: ListTile(
                      leading: Icon(Icons.upload),
                      title: Text('Restore a backup'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'refresh',
                    child: ListTile(
                      leading: Icon(Icons.refresh),
                      title: Text('Refresh'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Phone: the search, and the filters behind a button.
  Widget _phoneFilters(BuildContext context, Library lib) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _searchField()),
              IconButton(
                tooltip: _showFilters ? 'Hide the filters' : 'Filters',
                isSelected: _showFilters || _filtering,
                onPressed: () => setState(() => _showFilters = !_showFilters),
                icon: Badge(
                  isLabelVisible: _filtering && !_showFilters,
                  smallSize: 8,
                  child: const Icon(Icons.tune),
                ),
              ),
            ],
          ),
          if (_showFilters) ...[
            const SizedBox(height: 8),
            _filterChips(context, lib),
          ],
        ],
      ),
    );
  }

  Widget _searchField() => TextField(
    decoration: const InputDecoration(
      prefixIcon: Icon(Icons.search),
      hintText: 'Search',
      isDense: true,
      border: OutlineInputBorder(),
    ),
    controller: _search,
    onChanged: (v) => setState(() => _query = v),
  );

  Widget _header(BuildContext context, Library lib) {
    if (_narrow(context)) return _phoneHeader(context, lib);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Library', style: theme.textTheme.headlineSmall),
              Text(_whereKept(lib), style: theme.textTheme.bodySmall),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => _newOpening(context),
                icon: const Icon(Icons.add),
                label: const Text('New'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => AppScope.read(context).openDrill(),
                icon: const Icon(Icons.all_inclusive),
                label: const Text('Train all joseki'),
              ),
              OutlinedButton.icon(
                onPressed: () => _import(context, lib),
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Import SGF'),
              ),
              if (!storage.inBrowser)
                OutlinedButton.icon(
                  onPressed: () => _chooseFolder(context, lib),
                  icon: const Icon(Icons.drive_folder_upload_outlined),
                  label: const Text('Change folder'),
                ),
              PopupMenuButton<String>(
                tooltip: 'Back up or restore',
                icon: const Icon(Icons.save_alt),
                onSelected: (v) =>
                    v == 'backup' ? _backup(context) : _restore(context),
                itemBuilder: (c) => const [
                  PopupMenuItem(
                    value: 'backup',
                    child: ListTile(
                      leading: Icon(Icons.download),
                      title: Text('Back up library and progress'),
                      subtitle: Text(
                        'One file with all your SGF and what '
                        'you know',
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'restore',
                    child: ListTile(
                      leading: Icon(Icons.upload),
                      title: Text('Restore a backup'),
                      subtitle: Text(
                        'Also moves your files between the PC '
                        'and the web',
                      ),
                    ),
                  ),
                ],
              ),
              if (!kIsWeb && Platform.isWindows)
                IconButton(
                  tooltip: 'Open folder in Explorer',
                  onPressed: () => Process.run('explorer', [lib.directory!]),
                  icon: const Icon(Icons.open_in_new),
                ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: lib.refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filters(BuildContext context, Library lib) {
    if (_narrow(context)) return _phoneFilters(context, lib);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(width: 260, child: _searchField()),
          _filterChips(context, lib),
        ],
      ),
    );
  }

  /// The kind, color and size filters.
  Widget _filterChips(BuildContext context, Library lib) {
    int count(DocumentKind? k) =>
        lib.entries.where((e) => k == null || e.kind == k).length;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'all', label: Text('All (${count(null)})')),
              ButtonSegment(
                value: DocumentKind.opening.name,
                icon: _Dot([
                  kindAccent(DocumentKind.opening, Stone.black),
                  kindAccent(DocumentKind.opening, Stone.white),
                ]),
                label: Text('Openings (${count(DocumentKind.opening)})'),
              ),
              for (final k in const [DocumentKind.joseki, DocumentKind.tricks])
                ButtonSegment(
                  value: k.name,
                  icon: _Dot([kindAccent(k, null)]),
                  label: Text('${k.plural} (${count(k)})'),
                ),
            ],
            selected: {_kind?.name ?? 'all'},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() {
              _kind = DocumentKind.values
                  .where((k) => k.name == v.first)
                  .firstOrNull;
              if (_kind?.hasStartPosition ?? false) _color = null;
            }),
          ),
        ),
        // Joseki and tricks have no color: only openings are filtered.
        if (!(_kind?.hasStartPosition ?? false))
          for (final c in const [Stone.black, Stone.white])
            FilterChip(
              avatar: StoneIcon(c),
              label: Text(c.label),
              side: BorderSide(color: kindAccent(DocumentKind.opening, c)),
              selected: _color == c,
              onSelected: (on) => setState(() => _color = on ? c : null),
            ),
        for (final s in const [9, 13, 19])
          FilterChip(
            label: Text('$s×$s'),
            selected: _size == s,
            onSelected: (on) => setState(() => _size = on ? s : null),
          ),
      ],
    );
  }

  Widget _empty(BuildContext context, bool libraryEmpty) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_stories_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            libraryEmpty
                ? 'Your library is empty. Create an opening or a joseki, or import SGF files.'
                : 'No opening matches the filters.',
          ),
        ],
      ),
    );
  }

  /// [shown]: the entry in the preview (wide window only), or null.
  Widget _tile(
    BuildContext context,
    Library lib,
    LibraryEntry e,
    LibraryEntry? shown,
  ) {
    final wide = shown != null;
    final selected = e == shown;
    final narrow = _narrow(context);
    final details = [
      '${e.size}×${e.size}',
      if (!narrow) '${e.positions} moves',
      '${e.lines} line${e.lines == 1 ? '' : 's'}',
      if (e.folder.isNotEmpty) e.folder,
      if (!narrow) _date(e.modified),
    ].join('  ·  ');
    final accent = kindAccent(e.kind, e.color);
    final tile = ListTile(
      leading: KindIcon(kind: e.kind, color: e.color, size: 26),
      title: Text(e.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(e.error == null ? details : 'Unreadable: ${e.error}'),
      // Wide window: a click shows the preview on the right.
      onTap: e.error == null
          ? () => wide ? setState(() => _selected = e.path) : _edit(context, e)
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Train',
            icon: const Icon(Icons.school_outlined),
            onPressed: e.error == null ? () => _train(context, e) : null,
          ),
          // A phone: a tap on the file edits it.
          if (!narrow)
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: e.error == null ? () => _edit(context, e) : null,
            ),
          PopupMenuButton<String>(
            onSelected: (v) =>
                v == 'edit' ? _edit(context, e) : _menu(context, lib, e, v),
            itemBuilder: (_) => [
              if (narrow && e.error == null)
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(value: 'rename', child: Text('Rename…')),
              const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
    // Tinted card with a colored stripe on the left: teal for joseki,
    // indigo for Black openings, amber for White openings.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: accent.withValues(alpha: selected ? 0.22 : 0.07),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: selected
              ? BorderSide(color: accent, width: 1.5)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Padding(padding: const EdgeInsets.only(left: 5), child: tile),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 5, color: accent),
            ),
          ],
        ),
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _newOpening(BuildContext context) async {
    final doc = await newOpeningDialog(context);
    if (doc != null && context.mounted) await openInEditor(context, doc);
  }

  Future<void> _edit(BuildContext context, LibraryEntry e) async {
    final state = AppScope.read(context);
    if (state.editorDoc?.filePath == e.path) {
      state.goTo(AppSection.editor);
      return;
    }
    final doc = await loadDocument(context, e.path);
    if (doc != null && context.mounted) await openInEditor(context, doc);
  }

  Future<void> _train(BuildContext context, LibraryEntry e) async {
    final state = AppScope.read(context);
    // Train on the editor version if it's open (it may have unsaved edits).
    final open = state.editorDoc;
    if (open != null && open.filePath == e.path) {
      state.train(open);
      return;
    }
    final doc = await loadDocument(context, e.path);
    if (doc != null) state.train(doc);
  }

  Future<void> _import(BuildContext context, Library lib) async {
    final files = await pickTextFiles();
    if (files.isEmpty) return;
    try {
      final n = await lib.importFiles([
        for (final f in files) (f.name, f.text),
      ]);
      if (context.mounted) {
        showMessage(context, 'Imported $n file${n == 1 ? '' : 's'}');
      }
    } catch (e) {
      if (context.mounted) showMessage(context, 'Import failed: $e');
    }
  }

  Future<void> _backup(BuildContext context) async {
    final state = AppScope.read(context);
    final text = await state.backup();
    final d = DateTime.now();
    if (!context.mounted) return;
    await saveTextFile(
      context,
      'Go Dojo backup ${_date(d)}.json',
      text,
      mimeType: 'application/json',
    );
  }

  Future<void> _restore(BuildContext context) async {
    final state = AppScope.read(context);
    final files = await pickTextFiles(extension: 'json', multiple: false);
    if (files.isEmpty || !context.mounted) return;
    if (!await confirm(
      context,
      'Restore a backup',
      'The files of the backup are added to your library (a file with the '
          'same name is replaced). For each line, the most recent progress '
          'is kept.',
      ok: 'Restore',
    )) {
      return;
    }
    try {
      final (n, lines) = await state.restore(files.first.text);
      if (context.mounted) {
        showMessage(
          context,
          'Restored $n file${n == 1 ? '' : 's'} and the progress of '
          '$lines line${lines == 1 ? '' : 's'}.',
        );
      }
    } catch (e) {
      if (context.mounted) showMessage(context, 'Restore failed: $e');
    }
  }

  Future<void> _chooseFolder(BuildContext context, Library lib) async {
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose the library folder',
      initialDirectory: lib.directory,
    );
    if (dir != null) await lib.setDirectory(dir);
  }

  Future<void> _menu(
    BuildContext context,
    Library lib,
    LibraryEntry e,
    String action,
  ) async {
    final state = AppScope.read(context);
    final openHere = state.editorDoc?.filePath == e.path;
    try {
      switch (action) {
        case 'rename':
          final name = await askText(
            context,
            'Rename opening',
            initial: e.name,
          );
          if (name == null || name.isEmpty) return;
          if (openHere && state.editorDoc!.dirty) {
            if (context.mounted) {
              showMessage(context, 'Save or close the editor first.');
            }
            return;
          }
          final dest = await lib.rename(e, name);
          if (openHere && context.mounted) {
            final doc = await loadDocument(context, dest);
            if (doc != null) state.replaceEditorDoc(doc);
          }
        case 'duplicate':
          await lib.duplicate(e);
        case 'delete':
          if (!await confirm(
            context,
            'Delete opening',
            'Delete "${e.name}"? The file will be removed from disk.',
            ok: 'Delete',
          )) {
            return;
          }
          await lib.delete(e);
          if (openHere) state.closeEditor();
      }
    } catch (err) {
      if (context.mounted) showMessage(context, 'Failed: $err');
    }
  }
}

/// Small colored dot used in the filter chips as a legend (half and half
/// when given two colors).
class _Dot extends StatelessWidget {
  const _Dot(this.colors);
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: colors.first,
      gradient: colors.length < 2
          ? null
          : LinearGradient(
              colors: [colors[0], colors[0], colors[1], colors[1]],
              stops: const [0, 0.5, 0.5, 1],
            ),
    ),
  );
}

/// Right panel of the library: the board with a line of the selected
/// file, played move by move.
class _Preview extends StatefulWidget {
  const _Preview({
    super.key,
    required this.entry,
    required this.onTrain,
    required this.onEdit,
  });
  final LibraryEntry entry;
  final VoidCallback onTrain;
  final VoidCallback onEdit;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  OpeningDocument? _doc;
  Object? _error;
  List<SgfNode> _lines = const [];
  int _line = 0;

  /// Number of moves of the line shown on the board.
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_Preview old) {
    super.didUpdateWidget(old);
    // The file was saved again: reload it.
    if (old.entry.modified != widget.entry.modified) _load();
  }

  Future<void> _load() async {
    try {
      final doc = await OpeningDocument.load(widget.entry.path);
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _error = null;
        _lines = doc.root.leaves.toList();
        _line = _lines.isEmpty ? 0 : _line.clamp(0, _lines.length - 1);
        _step = _moves.length;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// The moves of the selected line.
  List<SgfNode> get _moves => _lines.isEmpty
      ? const []
      : [
          for (final n in _lines[_line].pathFromRoot)
            if (n.hasMove) n,
        ];

  void _setLine(int i) => setState(() {
    _line = i;
    _step = _moves.length;
  });

  /// "Name › Sub-variation" of the line, if its nodes are named.
  String? _lineName(SgfNode leaf) {
    final names = [for (final n in leaf.pathFromRoot) ?n.variationName];
    return names.isEmpty ? null : names.join('  ›  ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = widget.entry;
    final doc = _doc;
    if (_error != null) {
      return Center(child: Text('Could not read this file: $_error'));
    }
    if (doc == null) return const Center(child: CircularProgressIndicator());
    // A joseki or a trick is previewed by its starting position only.
    final joseki = doc.hasStartPosition;
    final moves = joseki ? const <SgfNode>[] : _moves;
    final node = _step == 0 || joseki ? doc.root : moves[_step - 1];
    final size = doc.size;
    final board = positionAt(node, size);
    // Move numbers on the stones still on the board.
    final labels = <Point, String>{};
    for (final m in moves.take(joseki ? 0 : _step)) {
      final p = m.movePoint(size);
      if (p != null && board[p] == m.moveColor) labels[p] = '${m.moveNumber}';
    }
    final comment = node.get('C');
    final name = _lines.isEmpty ? null : _lineName(_lines[_line]);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  e.name,
                  style: theme.textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              KindTag(kind: e.kind, color: e.color),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${e.size}×${e.size}  ·  ${e.positions} moves  ·  '
            '${e.lines} line${e.lines == 1 ? '' : 's'}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 1,
            child: BoardView(
              style: AppScope.of(context).boardStyle,
              board: board,
              lastMove: node.movePoint(size),
              labels: labels,
              showCoordinates: false,
            ),
          ),
          const SizedBox(height: 8),
          if (joseki)
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Starting position  ·  first move: ',
                  style: theme.textTheme.titleSmall,
                ),
                StoneIcon(doc.firstToPlay, size: 16),
                const SizedBox(width: 4),
                Text(doc.firstToPlay.label, style: theme.textTheme.titleSmall),
              ],
            ),
          // Moves of the line.
          if (!joseki)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Start',
                  onPressed: _step > 0 ? () => setState(() => _step = 0) : null,
                  icon: const Icon(Icons.first_page),
                ),
                IconButton(
                  tooltip: 'Previous move',
                  onPressed: _step > 0 ? () => setState(() => _step--) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                SizedBox(
                  width: 110,
                  child: Text(
                    'Move $_step / ${moves.length}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Next move',
                  onPressed: _step < moves.length
                      ? () => setState(() => _step++)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
                IconButton(
                  tooltip: 'End of the line',
                  onPressed: _step < moves.length
                      ? () => setState(() => _step = moves.length)
                      : null,
                  icon: const Icon(Icons.last_page),
                ),
              ],
            ),
          // Lines of the tree.
          if (!joseki && _lines.length > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Previous line',
                    onPressed: _line > 0 ? () => _setLine(_line - 1) : null,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Line ${_line + 1} / ${_lines.length}',
                          style: theme.textTheme.titleSmall,
                        ),
                        if (name != null)
                          Text(
                            name,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next line',
                    onPressed: _line < _lines.length - 1
                        ? () => _setLine(_line + 1)
                        : null,
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ],
              ),
            ),
          if (comment != null && comment.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Text(comment, style: theme.textTheme.bodyMedium),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: widget.onTrain,
                  icon: const Icon(Icons.school_outlined),
                  label: const Text('Train'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
