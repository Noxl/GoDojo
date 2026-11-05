import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../go/stone.dart';
import '../model/opening_document.dart';

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
    );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String ok = 'OK',
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Cancel'),
        ),
        // Focused so Enter confirms.
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> askText(
  BuildContext context,
  String title, {
  String initial = '',
  String label = 'Name',
}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(c, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, ctrl.text.trim()),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Dialog to create a new opening or joseki. Returns the document or null.
Future<OpeningDocument?> newOpeningDialog(BuildContext context) {
  final name = TextEditingController(text: 'New opening');
  var kind = DocumentKind.opening;
  var size = 19;
  var color = Stone.black;
  return showDialog<OpeningDocument>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text('New ${kind.label.toLowerCase()}'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<DocumentKind>(
                segments: [
                  for (final k in DocumentKind.values)
                    ButtonSegment(
                      value: k,
                      label: Text(k.label),
                      icon: Icon(kindIcon(k)),
                    ),
                ],
                selected: {kind},
                onSelectionChanged: (v) => setState(() {
                  final was = 'New ${kind.label.toLowerCase()}';
                  kind = v.first;
                  if (name.text == was) {
                    name.text = 'New ${kind.label.toLowerCase()}';
                  }
                }),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 16),
              const Text('Board size'),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                segments: [
                  for (final s in kBoardSizes)
                    ButtonSegment(value: s, label: Text('$s×$s')),
                ],
                selected: {size},
                onSelectionChanged: (v) => setState(() => size = v.first),
              ),
              const SizedBox(height: 16),
              if (kind == DocumentKind.opening) ...[
                const Text('I study this opening as'),
                const SizedBox(height: 6),
                ColorSelector(
                  value: color,
                  onChanged: (v) => setState(() => color = v),
                ),
              ] else
                Text(
                  'You will first set up the starting position (stones already '
                  'on the board). The color is chosen when you train.'
                  '${kind == DocumentKind.tricks ? ' A trick works like a joseki, '
                            'shown apart in the library.' : ''}',
                  style: Theme.of(c).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              c,
              OpeningDocument.create(
                name: name.text.trim().isEmpty
                    ? 'New ${kind.label.toLowerCase()}'
                    : name.text.trim(),
                size: size,
                color: color,
                kind: kind,
              ),
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    ),
  );
}

/// Icon for a library entry: the studied color, or a joseki symbol.
class KindIcon extends StatelessWidget {
  const KindIcon({super.key, required this.kind, this.color, this.size = 24});
  final DocumentKind kind;
  final Stone? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (kind.hasStartPosition) {
      return Tooltip(
        message: kind.label,
        child: Icon(kindIcon(kind), size: size, color: kindAccent(kind, null)),
      );
    }
    final c = color;
    return c == null
        ? Icon(Icons.help_outline, size: size)
        : StoneIcon(c, size: size);
  }
}

IconData kindIcon(DocumentKind kind) => switch (kind) {
  DocumentKind.opening => Icons.public,
  DocumentKind.joseki => Icons.crop_free,
  DocumentKind.tricks => Icons.auto_fix_high,
};

/// Accent color telling joseki, tricks, Black openings and White openings
/// apart.
Color kindAccent(DocumentKind kind, Stone? color) {
  if (kind == DocumentKind.joseki) return const Color(0xFF13A08A);
  if (kind == DocumentKind.tricks) return const Color(0xFFB04FD0);
  return color == Stone.white
      ? const Color(0xFFE0A030)
      : const Color(0xFF5C6BC0);
}

String kindLabel(DocumentKind kind, Stone? color) {
  if (kind.hasStartPosition) return kind.label;
  return color == null ? 'Opening' : 'Opening · ${color.label}';
}

/// Small colored tag: "Joseki", "Opening · Black" or "Opening · White".
class KindTag extends StatelessWidget {
  const KindTag({super.key, required this.kind, this.color});
  final DocumentKind kind;
  final Stone? color;

  @override
  Widget build(BuildContext context) {
    final accent = kindAccent(kind, color);
    // Slightly toward the text color so it stays readable on any theme.
    final ink = Color.lerp(
      accent,
      Theme.of(context).colorScheme.onSurface,
      0.3,
    )!;
    final c = color;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 2, 8, 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (kind.hasStartPosition)
            Icon(kindIcon(kind), size: 13, color: ink)
          else if (c != null)
            StoneIcon(c, size: 12),
          const SizedBox(width: 5),
          Text(
            kindLabel(kind, color),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

class ColorSelector extends StatelessWidget {
  const ColorSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final Stone value;
  final ValueChanged<Stone> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<Stone>(
      segments: const [
        ButtonSegment(
          value: Stone.black,
          label: Text('Black'),
          icon: StoneIcon(Stone.black),
        ),
        ButtonSegment(
          value: Stone.white,
          label: Text('White'),
          icon: StoneIcon(Stone.white),
        ),
      ],
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: (v) => onChanged(v.first),
    );
  }
}

class StoneIcon extends StatelessWidget {
  const StoneIcon(this.stone, {super.key, this.size = 16});
  final Stone stone;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: stone == Stone.black
            ? const Color(0xFF151515)
            : const Color(0xFFF5F2EA),
        border: Border.all(color: const Color(0xFF777777)),
      ),
    );
  }
}

/// Saves [doc]; new documents go into the library folder.
Future<bool> saveDocument(
  BuildContext context,
  OpeningDocument doc, {
  bool asCopy = false,
}) async {
  final state = AppScope.read(context);
  try {
    final path = (doc.filePath == null || asCopy)
        ? state.library.suggestPath(asCopy ? '${doc.name} copy' : doc.name)
        : doc.filePath!;
    await doc.saveTo(path);
    await state.library.refresh();
    if (context.mounted) showMessage(context, 'Saved to $path');
    return true;
  } catch (e) {
    if (context.mounted) showMessage(context, 'Save failed: $e');
    return false;
  }
}

/// Asks what to do with unsaved changes in the editor. Returns false if the
/// user cancelled.
Future<bool> resolveUnsaved(BuildContext context) async {
  final state = AppScope.read(context);
  final doc = state.editorDoc;
  if (doc == null || !doc.dirty) return true;
  final r = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Unsaved changes'),
      content: Text('"${doc.name}" has unsaved changes.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, 'discard'),
          child: const Text('Discard'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, 'save'),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (r == 'save' && context.mounted) return saveDocument(context, doc);
  return r == 'discard';
}

/// Opens [doc] in the editor after handling unsaved changes.
Future<void> openInEditor(BuildContext context, OpeningDocument doc) async {
  if (!await resolveUnsaved(context)) return;
  if (context.mounted) AppScope.read(context).openInEditor(doc);
}

Future<OpeningDocument?> loadDocument(BuildContext context, String path) async {
  try {
    return await OpeningDocument.load(path);
  } catch (e) {
    if (context.mounted) showMessage(context, 'Could not open $path: $e');
    return null;
  }
}

/// A file chosen by the user: its name, text and, on desktop, its path.
class PickedFile {
  const PickedFile(this.name, this.text, this.path);
  final String name;
  final String text;
  final String? path;
}

/// Lets the user pick files with [extension] (from the disk, or the phone).
Future<List<PickedFile>> pickTextFiles({
  String extension = 'sgf',
  bool multiple = true,
}) async {
  final files = await FilePicker.pickFiles(
    dialogTitle: 'Choose files',
    type: FileType.custom,
    allowedExtensions: [extension],
  );
  final out = <PickedFile>[];
  for (final f in multiple ? files : files.take(1)) {
    final bytes = await f.readAsBytes();
    out.add(
      PickedFile(
        f.name,
        utf8.decode(bytes, allowMalformed: true),
        kIsWeb ? null : f.path,
      ),
    );
  }
  return out;
}

/// Saves [text] as a file the user chooses (desktop) or downloads it (web).
Future<void> saveTextFile(
  BuildContext context,
  String fileName,
  String text, {
  String mimeType = 'text/plain',
}) async {
  try {
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save $fileName',
      fileName: fileName,
      bytes: utf8.encode(text),
      mimeType: mimeType,
    );
    if (context.mounted && (uri != null || kIsWeb)) {
      showMessage(
        context,
        kIsWeb || uri!.scheme != 'file'
            ? 'Downloaded $fileName'
            : 'Saved to ${uri.toFilePath()}',
      );
    }
  } catch (e) {
    if (context.mounted) showMessage(context, 'Could not save: $e');
  }
}
