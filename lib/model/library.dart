import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../go/stone.dart';
import '../sgf/sgf.dart';
import '../storage/storage.dart';
import 'opening_document.dart';

class LibraryEntry {
  LibraryEntry({
    required this.path,
    required this.relativePath,
    required this.name,
    required this.size,
    required this.color,
    this.kind = DocumentKind.opening,
    required this.positions,
    required this.lines,
    required this.modified,
    this.error,
  });

  final String path;
  final String relativePath;
  final String name;
  final int size;
  final Stone? color;
  final DocumentKind kind;
  final int positions;
  final int lines;
  final DateTime modified;
  final String? error;

  String get folder {
    final d = p.dirname(relativePath);
    return d == '.' ? '' : d;
  }
}

/// A folder of SGF openings (searched recursively).
class Library extends ChangeNotifier {
  static const _prefKey = 'libraryDir';

  String? directory;
  List<LibraryEntry> entries = [];
  bool loading = false;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    var dir = prefs.getString(_prefKey);
    if (dir == null || !await storage.dirExists(dir)) {
      dir = await storage.defaultLibraryDir();
    }
    await setDirectory(dir);
  }

  Future<void> setDirectory(String dir) async {
    directory = dir;
    await storage.createDir(dir);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, dir);
    await refresh();
  }

  Future<void> refresh() async {
    final dir = directory;
    if (dir == null) return;
    loading = true;
    notifyListeners();
    final out = <LibraryEntry>[];
    try {
      for (final f in await storage.listSgf(dir)) {
        out.add(await _readEntry(f, dir));
      }
    } catch (e) {
      debugPrint('Library scan failed: $e');
    }
    out.sort(
      (a, b) =>
          a.relativePath.toLowerCase().compareTo(b.relativePath.toLowerCase()),
    );
    entries = out;
    loading = false;
    notifyListeners();
  }

  static Future<LibraryEntry> _readEntry(StoredFile f, String dir) async {
    final rel = p.relative(f.path, from: dir);
    try {
      final root = parseSgf(await storage.read(f.path));
      final size =
          int.tryParse((root.get('SZ') ?? '19').split(':').first) ?? 19;
      return LibraryEntry(
        path: f.path,
        relativePath: rel,
        name: root.get('GN') ?? p.basenameWithoutExtension(f.path),
        size: size,
        color: DocumentKind.of(root).hasStartPosition
            ? null
            : Stone.fromSgf(root.get(kOpeningColorProp)),
        kind: DocumentKind.of(root),
        positions: root.descendants.where((n) => n.hasMove).length,
        lines: root.leaves.length,
        modified: f.modified,
      );
    } catch (e) {
      return LibraryEntry(
        path: f.path,
        relativePath: rel,
        name: p.basenameWithoutExtension(f.path),
        size: 19,
        color: null,
        positions: 0,
        lines: 0,
        modified: f.modified,
        error: '$e',
      );
    }
  }

  /// A free file path in the library for an opening called [name].
  String suggestPath(String name, {String subfolder = ''}) {
    final base = sanitizeFileName(name);
    final dir = p.join(directory!, subfolder);
    var candidate = p.join(dir, '$base.sgf');
    var i = 2;
    while (storage.existsSync(candidate)) {
      candidate = p.join(dir, '$base ($i).sgf');
      i++;
    }
    return candidate;
  }

  static String sanitizeFileName(String name) {
    final s = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    return s.isEmpty ? 'opening' : s;
  }

  /// Adds SGF files (file name, content) to the library. Returns the number
  /// imported.
  Future<int> importFiles(List<(String, String)> files) async {
    var count = 0;
    for (final (name, text) in files) {
      final dest = suggestPath(p.basenameWithoutExtension(name));
      await storage.write(dest, text);
      count++;
    }
    await refresh();
    return count;
  }

  Future<void> delete(LibraryEntry e) async {
    await storage.delete(e.path);
    await refresh();
  }

  Future<String> rename(LibraryEntry e, String newName) async {
    final dest = suggestPath(newName, subfolder: e.folder);
    await storage.rename(e.path, dest);
    // Keep the game name in sync with the file name.
    final doc = await OpeningDocument.load(dest);
    doc.setName(newName);
    await doc.saveTo(dest);
    await refresh();
    return dest;
  }

  Future<String> duplicate(LibraryEntry e) async {
    final dest = suggestPath('${e.name} copy', subfolder: e.folder);
    final doc = await OpeningDocument.load(e.path);
    doc.setName('${e.name} copy');
    await doc.saveTo(dest);
    await refresh();
    return dest;
  }
}
