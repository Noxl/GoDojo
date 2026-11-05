import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'analysis/analysis_service.dart';
import 'model/backup.dart';
import 'model/drill.dart';
import 'model/library.dart';
import 'model/opening_document.dart';
import 'sgf/sgf_node.dart';
import 'storage/storage.dart';
import 'ui/board_view.dart';

enum AppSection { library, editor, trainer, drill }

/// What the trainer should train on.
class TrainerTarget {
  TrainerTarget(this.doc, {this.branchPath});

  /// A snapshot of the opening (the editor may keep changing its own copy).
  final OpeningDocument doc;

  /// Child indexes from the root to the branch to train, if any.
  final List<int>? branchPath;

  /// The node at [branchPath] in [doc].
  SgfNode? get branch {
    final path = branchPath;
    if (path == null) return null;
    var n = doc.root;
    for (final i in path) {
      if (i >= n.children.length) return null;
      n = n.children[i];
    }
    return n;
  }
}

class AppState extends ChangeNotifier {
  final library = Library();
  final analysis = AnalysisService();
  AppSection section = AppSection.library;
  OpeningDocument? editorDoc;
  TrainerTarget? trainerTarget;

  /// The global trainer (all the joseki of the library), when running.
  DrillSession? drill;
  bool drillLoading = false;

  /// Where the progress of the global trainer is saved (null: default).
  String? drillProgressPath;
  ThemeMode themeMode = ThemeMode.system;
  BoardStyle boardStyle = BoardStyle.wood;

  /// Key toggling the KataGo analysis in the editor.
  String analysisKey = '&';

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    themeMode =
        ThemeMode.values.asNameMap()[prefs.getString('themeMode')] ?? themeMode;
    boardStyle =
        BoardStyle.values.asNameMap()[prefs.getString('boardStyle')] ??
        boardStyle;
    analysisKey = prefs.getString('analysisKey') ?? analysisKey;
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(
      'themeMode',
      m.name,
    );
  }

  Future<void> setBoardStyle(BoardStyle s) async {
    boardStyle = s;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(
      'boardStyle',
      s.name,
    );
  }

  Future<void> setAnalysisKey(String key) async {
    if (key.isEmpty) return;
    analysisKey = key;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString('analysisKey', key);
  }

  void goTo(AppSection s) {
    section = s;
    notifyListeners();
  }

  void openInEditor(OpeningDocument doc) {
    editorDoc = doc;
    section = AppSection.editor;
    notifyListeners();
  }

  /// Replaces the editor document without switching section.
  void replaceEditorDoc(OpeningDocument doc) {
    editorDoc = doc;
    notifyListeners();
  }

  /// Opens the trainer on a snapshot of [doc], optionally only for the
  /// lines going through [from].
  void train(OpeningDocument doc, {SgfNode? from}) {
    List<int>? path;
    if (from != null && from != doc.root) {
      path = [];
      for (var n = from; n.parent != null; n = n.parent!) {
        path.add(n.parent!.children.indexOf(n));
      }
      path = path.reversed.toList();
    }
    trainerTarget = TrainerTarget(
      OpeningDocument.fromSgf(doc.toSgf(), filePath: doc.filePath),
      branchPath: path,
    );
    section = AppSection.trainer;
    notifyListeners();
  }

  /// The file of the global trainer progress.
  Future<String> progressPath() async =>
      drillProgressPath ??
      p.join(await storage.appDataDir(), 'training_progress.json');

  /// Starts the global trainer on the files of the library.
  Future<void> startDrill() async {
    if (drillLoading) return;
    drillLoading = true;
    section = AppSection.drill;
    notifyListeners();
    try {
      await library.refresh();
      final progress = await DrillProgress.load(await progressPath());
      final docs = await DrillSession.loadDocs(library.entries);
      stopDrill(notify: false);
      drill = DrillSession(docs: docs, progress: progress)..next();
    } finally {
      drillLoading = false;
      notifyListeners();
    }
  }

  /// A backup of the library and the training progress (JSON).
  Future<String> backup() async {
    final progress =
        drill?.progress ?? await DrillProgress.load(await progressPath());
    return buildBackup(library, progress);
  }

  /// Restores a backup made by [backup]. Returns (files, lines).
  Future<(int, int)> restore(String text) async {
    // The global trainer saves its progress: start it again afterwards.
    final wasOpen = drill != null;
    stopDrill();
    final progress = await DrillProgress.load(await progressPath());
    final r = await restoreBackup(library, progress, text);
    if (wasOpen) {
      final s = section;
      await startDrill();
      goTo(s);
    }
    return r;
  }

  /// Shows the global trainer tab, starting it if needed.
  void openDrill() {
    if (drill == null) {
      startDrill();
    } else {
      goTo(AppSection.drill);
    }
  }

  void stopDrill({bool notify = true}) {
    drill?.dispose();
    drill = null;
    if (notify) notifyListeners();
  }

  void closeEditor() {
    editorDoc = null;
    notifyListeners();
  }
}

/// Gives widgets access to the [AppState].
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
