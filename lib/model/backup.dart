import 'dart:convert';

import 'package:path/path.dart' as p;

import '../storage/storage.dart';
import 'drill.dart';
import 'library.dart';

/// One JSON file holding every SGF of the library and the training
/// progress: to move them between the PC and the web version, or to keep
/// a copy.
Future<String> buildBackup(Library lib, DrillProgress progress) async {
  final files = <String, String>{};
  for (final e in lib.entries) {
    try {
      files[e.relativePath.replaceAll(r'\', '/')] = await storage.read(e.path);
    } catch (_) {
      // Unreadable file: left out.
    }
  }
  return const JsonEncoder.withIndent(' ').convert({
    'app': 'Go Dojo',
    'type': 'backup',
    'version': 1,
    'created': DateTime.now().toIso8601String(),
    'files': files,
    'progress': progress.toJson(),
  });
}

/// Writes the files of a backup into the library (a file with the same
/// name is replaced) and merges its progress (the most recent run of each
/// line wins). Returns (files, lines).
Future<(int, int)> restoreBackup(
  Library lib,
  DrillProgress progress,
  String text,
) async {
  final j = jsonDecode(text);
  if (j is! Map || j['type'] != 'backup' || j['files'] is! Map) {
    throw const FormatException('This is not a Go Dojo backup.');
  }
  final dir = lib.directory!;
  var files = 0;
  for (final e in (j['files'] as Map).entries) {
    final rel = '${e.key}';
    final parts = rel.split('/').where((s) => s.isNotEmpty && s != '..');
    if (parts.isEmpty || e.value is! String) continue;
    await storage.write(p.joinAll([dir, ...parts]), e.value as String);
    files++;
  }
  var lines = 0;
  if (j['progress'] case final Map saved) {
    final other = DrillProgress()..readJson(jsonEncode(saved));
    lines = progress.merge(other);
    await progress.save();
  }
  await lib.refresh();
  return (files, lines);
}
