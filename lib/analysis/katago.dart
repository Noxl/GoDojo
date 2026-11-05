import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../go/point.dart';
import '../go/stone.dart';
import '../model/opening_document.dart';
import '../sgf/sgf_node.dart';

/// One candidate move proposed by the engine. Values are from the point of
/// view of the player to move.
class MoveAnalysis {
  const MoveAnalysis({
    required this.point,
    required this.visits,
    required this.winrate,
    required this.scoreLead,
    required this.order,
    required this.pv,
  });

  /// Null for a pass.
  final Point? point;
  final int visits;
  final double winrate;
  final double scoreLead;
  final int order;
  final List<Point?> pv;
}

/// Engine result for a position. Values are from the point of view of
/// [toMove].
class PositionAnalysis {
  const PositionAnalysis({
    required this.toMove,
    required this.winrate,
    required this.scoreLead,
    required this.visits,
    required this.moves,
    required this.complete,
  });

  final Stone toMove;
  final double winrate;
  final double scoreLead;
  final int visits;
  final List<MoveAnalysis> moves;

  /// False while the search is still running.
  final bool complete;

  MoveAnalysis? get best => moves.isEmpty ? null : moves.first;

  MoveAnalysis? moveAt(Point? point) =>
      moves.where((m) => m.point == point).firstOrNull;

  /// Winrate for Black (0..1).
  double get blackWinrate => toMove == Stone.black ? winrate : 1 - winrate;

  /// Score lead for Black, in points.
  double get blackScore => toMove == Stone.black ? scoreLead : -scoreLead;
}

/// A position to analyze, in KataGo terms.
class AnalysisQuery {
  AnalysisQuery({
    required this.size,
    required this.komi,
    required this.initialStones,
    required this.initialPlayer,
    required this.moves,
  });

  /// Builds the query for the position after [node].
  factory AnalysisQuery.at(SgfNode node, int size) {
    final path = node.pathFromRoot;
    // Moves after the last node containing setup stones; everything before
    // it becomes initial stones.
    var setupIndex = 0;
    for (var i = 0; i < path.length; i++) {
      final n = path[i];
      if (n.has('AB') || n.has('AW') || n.has('AE')) setupIndex = i;
    }
    final setupBoard = positionAt(path[setupIndex], size);
    final stones = <(Stone, Point)>[];
    for (final pt in setupBoard.points) {
      if (setupBoard[pt] != Stone.empty) stones.add((setupBoard[pt], pt));
    }
    final moves = <(Stone, Point?)>[];
    for (final n in path.skip(setupIndex + 1)) {
      final c = n.moveColor;
      if (c != null) moves.add((c, n.movePoint(size)));
    }
    final initialPlayer = nextToPlay(path[setupIndex]);
    final komi = double.tryParse(node.root.get('KM') ?? '') ?? 6.5;
    return AnalysisQuery(
      size: size,
      komi: (komi * 2).round() / 2,
      initialStones: stones,
      initialPlayer: initialPlayer,
      moves: moves,
    );
  }

  final int size;
  final double komi;
  final List<(Stone, Point)> initialStones;
  final Stone initialPlayer;
  final List<(Stone, Point?)> moves;

  /// The same position with one more move played.
  AnalysisQuery withMove(Point? point) => AnalysisQuery(
    size: size,
    komi: komi,
    initialStones: initialStones,
    initialPlayer: initialPlayer,
    moves: [...moves, (toMove, point)],
  );

  Stone get toMove => moves.isEmpty ? initialPlayer : moves.last.$1.opponent;

  /// Identifies the position (used for caching).
  String get key {
    final b = StringBuffer('$size|$komi|${initialPlayer.sgf}|');
    for (final (s, pt) in initialStones) {
      b.write('${s.sgf}${pt.sgf}');
    }
    b.write('|');
    for (final (s, pt) in moves) {
      b.write('${s.sgf}${pt?.sgf ?? 'pass'};');
    }
    return b.toString();
  }

  String _coord(Point? pt) => pt == null ? 'pass' : pt.display(size);

  Map<String, Object?> toJson(String id, int maxVisits) => {
    'id': id,
    'boardXSize': size,
    'boardYSize': size,
    'rules': 'japanese',
    'komi': komi,
    'initialPlayer': initialPlayer.sgf,
    'initialStones': [
      for (final (s, pt) in initialStones) [s.sgf, _coord(pt)],
    ],
    'moves': [
      for (final (s, pt) in moves) [s.sgf, _coord(pt)],
    ],
    'maxVisits': maxVisits,
    'reportDuringSearchEvery': 0.4,
  };
}

/// Parses a GTP coordinate such as "Q16" or "pass".
Point? parseGtpPoint(String s, int size) {
  if (s.toLowerCase() == 'pass' || s.length < 2) return null;
  const letters = 'ABCDEFGHJKLMNOPQRSTUVWXYZ';
  final x = letters.indexOf(s[0].toUpperCase());
  final row = int.tryParse(s.substring(1));
  if (x < 0 || row == null) return null;
  final pt = Point(x, size - row);
  return pt.isOnBoard(size) ? pt : null;
}

enum EngineStatus { stopped, starting, ready, failed }

/// Paths needed to run KataGo.
class KataGoPaths {
  const KataGoPaths({
    required this.exe,
    required this.model,
    required this.config,
  });
  final String exe;
  final String model;
  final String config;

  bool get complete =>
      File(exe).existsSync() &&
      File(model).existsSync() &&
      File(config).existsSync();

  /// Looks for katago.exe, a network and analysis_example.cfg in [dir].
  static KataGoPaths? detect(String dir) {
    final d = Directory(p.normalize(p.absolute(dir)));
    if (!d.existsSync()) return null;
    String? exe, config;
    final models = <File>[];
    for (final f in d.listSync(recursive: true).whereType<File>()) {
      final name = p.basename(f.path).toLowerCase();
      if (name == 'katago.exe' || name == 'katago') exe ??= f.path;
      if (name == 'analysis_example.cfg' || name == 'analysis.cfg') {
        config ??= f.path;
      }
      if (name.endsWith('.bin.gz') || name.endsWith('.txt.gz')) models.add(f);
    }
    if (exe == null || models.isEmpty) return null;
    models.sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));
    return KataGoPaths(
      exe: exe,
      model: models.first.path,
      config: config ?? p.join(p.dirname(exe), 'analysis_example.cfg'),
    );
  }
}

/// Runs `katago analysis` and talks to it with its JSON protocol.
class KataGoEngine extends ChangeNotifier {
  KataGoEngine(this.paths);

  final KataGoPaths paths;
  Process? _process;
  EngineStatus status = EngineStatus.stopped;
  String? error;

  /// Last lines of KataGo's log (useful while it starts or tunes).
  final List<String> log = [];

  int _nextId = 0;
  final Map<String, (StreamController<PositionAnalysis>, Stone)> _queries = {};

  Future<void> start() async {
    if (status == EngineStatus.starting || status == EngineStatus.ready) return;
    status = EngineStatus.starting;
    error = null;
    log.clear();
    notifyListeners();
    try {
      final logDir = p.join(Directory.systemTemp.path, 'goopener_katago_logs');
      final process = await Process.start(p.absolute(paths.exe), [
        'analysis',
        '-config',
        p.absolute(paths.config),
        '-model',
        p.absolute(paths.model),
        '-override-config',
        'reportAnalysisWinratesAs=SIDETOMOVE,logDir=${logDir.replaceAll('\\', '/')}',
      ], workingDirectory: p.dirname(paths.exe));
      _process = process;
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onLine);
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onLog);
      unawaited(process.exitCode.then(_onExit));
    } catch (e) {
      status = EngineStatus.failed;
      error = 'Could not start KataGo: $e';
      notifyListeners();
    }
  }

  void _onLog(String line) {
    log.add(line);
    if (log.length > 30) log.removeAt(0);
    if (line.contains('ready to begin handling requests')) {
      status = EngineStatus.ready;
    }
    notifyListeners();
  }

  void _onExit(int code) {
    _process = null;
    if (status != EngineStatus.stopped) {
      status = EngineStatus.failed;
      error = 'KataGo stopped (exit code $code).\n${log.join('\n')}';
    }
    for (final (c, _) in _queries.values) {
      c.close();
    }
    _queries.clear();
    notifyListeners();
  }

  void _onLine(String line) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final id = json['id'] as String?;
    final entry = id == null ? null : _queries[id];
    if (entry == null) return;
    final (controller, toMove) = entry;
    if (json.containsKey('error')) {
      controller.addError(json['error'].toString());
      controller.close();
      _queries.remove(id);
      return;
    }
    if (!json.containsKey('rootInfo')) return; // warnings, acks
    final size = _sizes[id] ?? 19;
    final root = json['rootInfo'] as Map<String, dynamic>;
    final infos = (json['moveInfos'] as List).cast<Map<String, dynamic>>();
    final moves = [
      for (final m in infos)
        MoveAnalysis(
          point: parseGtpPoint(m['move'] as String, size),
          visits: (m['visits'] as num).toInt(),
          winrate: (m['winrate'] as num).toDouble(),
          scoreLead: (m['scoreLead'] as num).toDouble(),
          order: (m['order'] as num).toInt(),
          pv: [
            for (final s in (m['pv'] as List? ?? const []).cast<String>())
              parseGtpPoint(s, size),
          ],
        ),
    ]..sort((a, b) => a.order.compareTo(b.order));
    final complete = json['isDuringSearch'] != true;
    controller.add(
      PositionAnalysis(
        toMove: toMove,
        winrate: (root['winrate'] as num).toDouble(),
        scoreLead: (root['scoreLead'] as num).toDouble(),
        visits: (root['visits'] as num).toInt(),
        moves: moves,
        complete: complete,
      ),
    );
    if (complete) {
      controller.close();
      _queries.remove(id);
      _sizes.remove(id);
    }
  }

  final Map<String, int> _sizes = {};

  /// Analyzes [query]; the stream emits progressively better results and
  /// closes when the search is done. Cancel the subscription to stop it.
  Stream<PositionAnalysis> analyze(AnalysisQuery query, {int maxVisits = 500}) {
    final id = 'q${_nextId++}';
    late final StreamController<PositionAnalysis> controller;
    controller = StreamController<PositionAnalysis>(
      onCancel: () {
        if (_queries.remove(id) != null) {
          _send({'id': 'cancel_$id', 'action': 'terminate', 'terminateId': id});
        }
        _sizes.remove(id);
      },
    );
    _queries[id] = (controller, query.toMove);
    _sizes[id] = query.size;
    _send(query.toJson(id, maxVisits));
    return controller.stream;
  }

  void _send(Map<String, Object?> json) {
    _process?.stdin.writeln(jsonEncode(json));
  }

  Future<void> stop() async {
    status = EngineStatus.stopped;
    final proc = _process;
    _process = null;
    if (proc != null) {
      await proc.stdin.close();
      proc.kill();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

/// Score loss of the move in [node], in points, from its player's view.
/// Needs the analysis of the position before the move ([before]) and,
/// when the move isn't among the engine's candidates, after it ([after]).
double? moveLoss(
  SgfNode node,
  int size,
  PositionAnalysis? before,
  PositionAnalysis? after,
) {
  if (before == null || !node.hasMove) return null;
  final best = before.best;
  if (best == null) return null;
  final candidate = before.moveAt(node.movePoint(size));
  final double score;
  if (candidate != null && candidate.visits >= 10) {
    score = candidate.scoreLead;
  } else if (after != null) {
    score = -after.scoreLead;
  } else {
    return null;
  }
  return (best.scoreLead - score).clamp(0, double.infinity).toDouble();
}
