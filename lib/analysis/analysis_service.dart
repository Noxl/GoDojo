import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../go/point.dart';
import '../sgf/sgf_node.dart';
import 'katago.dart';

/// Owns the KataGo engine, its settings and a cache of results.
class AnalysisService extends ChangeNotifier {
  KataGoPaths? paths;
  int maxVisits = 500;
  KataGoEngine? _engine;
  final Map<String, PositionAnalysis> _cache = {};
  final Map<String, StreamSubscription<PositionAnalysis>> _running = {};

  KataGoEngine? get engine => _engine;
  bool get configured => !kIsWeb && (paths?.complete ?? false);

  Future<void> load() async {
    // A browser cannot run KataGo.
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final exe = prefs.getString('katagoExe');
    final model = prefs.getString('katagoModel');
    final config = prefs.getString('katagoConfig');
    maxVisits = prefs.getInt('katagoVisits') ?? maxVisits;
    if (exe != null && model != null && config != null) {
      paths = KataGoPaths(exe: exe, model: model, config: config);
    }
    if (!configured) {
      // Look for a "KataGo" folder next to the app or in the working dir.
      for (final dir in {
        Directory.current.path,
        p.dirname(Platform.resolvedExecutable),
      }) {
        final found = KataGoPaths.detect(p.join(dir, 'KataGo'));
        if (found != null && found.complete) {
          await setPaths(found);
          break;
        }
      }
    }
  }

  Future<void> setPaths(KataGoPaths value) async {
    paths = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('katagoExe', value.exe);
    await prefs.setString('katagoModel', value.model);
    await prefs.setString('katagoConfig', value.config);
    await _restart();
  }

  Future<void> setMaxVisits(int v) async {
    maxVisits = v;
    _cache.clear();
    notifyListeners();
    await (await SharedPreferences.getInstance()).setInt('katagoVisits', v);
  }

  Future<void> _restart() async {
    final old = _engine;
    _engine = null;
    _cancelAll();
    _cache.clear();
    old?.removeListener(notifyListeners);
    await old?.stop();
    notifyListeners();
  }

  /// Starts the engine if needed and returns it, or null if not configured.
  KataGoEngine? ensureEngine() {
    if (!configured) return null;
    var e = _engine;
    if (e == null || e.status == EngineStatus.failed) {
      e?.removeListener(notifyListeners);
      e = _engine = KataGoEngine(paths!)..addListener(notifyListeners);
    }
    if (e.status == EngineStatus.stopped) e.start();
    return e;
  }

  Future<void> retry() async {
    await _restart();
    ensureEngine();
  }

  /// Latest result for the position after [node] (maybe still running).
  PositionAnalysis? resultFor(SgfNode node, int size) =>
      _cache[AnalysisQuery.at(node, size).key];

  /// Makes sure the positions in [nodes] are being analyzed, and stops
  /// analyses of positions not in the list.
  void analyze(List<SgfNode> nodes, int size) {
    final engine = ensureEngine();
    if (engine == null) return;
    final wanted = <String, AnalysisQuery>{
      for (final n in nodes)
        if (AnalysisQuery.at(n, size) case final q) q.key: q,
    };
    for (final key in _running.keys.toList()) {
      if (!wanted.containsKey(key)) _running.remove(key)!.cancel();
    }
    for (final e in wanted.entries) {
      final done = _cache[e.key]?.complete ?? false;
      if (done || _running.containsKey(e.key)) continue;
      _running[e.key] = engine
          .analyze(e.value, maxVisits: maxVisits)
          .listen(
            (r) {
              _cache[e.key] = r;
              notifyListeners();
            },
            onError: (_) => _running.remove(e.key),
            onDone: () => _running.remove(e.key),
          );
    }
  }

  /// One-off evaluation of [query]; resolves with the final result, or
  /// null if KataGo isn't available.
  Future<PositionAnalysis?> evaluate(AnalysisQuery query, {int? visits}) async {
    final cached = _cache[query.key];
    if (cached != null && cached.complete) return cached;
    final engine = ensureEngine();
    if (engine == null) return null;
    PositionAnalysis? last;
    try {
      await for (final r in engine.analyze(
        query,
        maxVisits: visits ?? maxVisits,
      )) {
        last = r;
      }
    } catch (_) {
      return null;
    }
    if (last != null) _cache[query.key] = last;
    return last;
  }

  /// Score loss of playing [point] in the position after [node], or null.
  Future<double?> lossOf(SgfNode node, int size, Point point) async {
    final q = AnalysisQuery.at(node, size);
    final visits = maxVisits.clamp(50, 400);
    final results = await Future.wait([
      evaluate(q, visits: visits),
      evaluate(q.withMove(point), visits: visits),
    ]);
    final before = results[0], after = results[1];
    final best = before?.best;
    if (best == null || after == null) return null;
    final candidate = before!.moveAt(point);
    final score = candidate != null && candidate.visits >= 10
        ? candidate.scoreLead
        : -after.scoreLead;
    return (best.scoreLead - score).clamp(0, double.infinity).toDouble();
  }

  void stopAnalysis() => _cancelAll();

  void _cancelAll() {
    for (final s in _running.values) {
      s.cancel();
    }
    _running.clear();
  }

  @override
  void dispose() {
    _cancelAll();
    _engine?.dispose();
    super.dispose();
  }
}
