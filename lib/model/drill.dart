import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../go/stone.dart';
import '../sgf/sgf_node.dart';
import '../storage/storage.dart';
import 'library.dart';
import 'opening_document.dart';
import 'trainer_session.dart';

/// Clean runs in a row (no mistake, no hint) after which a line is known.
const kKnownStreak = 3;

/// What the user knows of one line, played with one color.
class LineRecord {
  LineRecord();

  /// Clean runs in a row; reset by a run with a mistake or a hint.
  int streak = 0;
  int attempts = 0;
  int cleanRuns = 0;
  int failedRuns = 0;

  /// Mistakes made in this line, in all runs.
  int mistakes = 0;
  DateTime? last;

  /// When a known line should be reviewed.
  DateTime? due;

  bool get known => streak >= kKnownStreak;

  /// The last run had a mistake (or a hint): the line has to be fixed.
  bool get failing => streak == 0 && failedRuns > 0;

  bool isDue(DateTime now) => due == null || !now.isBefore(due!);

  Map<String, Object?> toJson() => {
    's': streak,
    'a': attempts,
    'c': cleanRuns,
    'f': failedRuns,
    'm': mistakes,
    if (last != null) 'l': last!.millisecondsSinceEpoch,
    if (due != null) 'd': due!.millisecondsSinceEpoch,
  };

  factory LineRecord.fromJson(Map<String, Object?> j) {
    DateTime? time(Object? v) =>
        v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    int n(Object? v) => v is int ? v : 0;
    return LineRecord()
      ..streak = n(j['s'])
      ..attempts = n(j['a'])
      ..cleanRuns = n(j['c'])
      ..failedRuns = n(j['f'])
      ..mistakes = n(j['m'])
      ..last = time(j['l'])
      ..due = time(j['d']);
  }
}

/// Delay before a known line comes back, by clean streak (spaced
/// repetition).
Duration reviewInterval(int streak) => switch (streak) {
  < kKnownStreak => Duration.zero,
  kKnownStreak => const Duration(days: 2),
  4 => const Duration(days: 5),
  5 => const Duration(days: 12),
  _ => const Duration(days: 30),
};

enum DrillFocus {
  smart('Smart mix'),
  mistakes('My mistakes'),
  unknown('Not known yet');

  const DrillFocus(this.label);
  final String label;
}

/// Settings of the global trainer.
class DrillSettings {
  const DrillSettings({
    this.kinds = const {DocumentKind.joseki, DocumentKind.tricks},
    this.colors = const {Stone.black, Stone.white},
    this.focus = DrillFocus.smart,
    this.opponentMistakes = true,
    this.showPunishment = true,
    this.autoNext = true,
    this.docColors = const {},
  });

  final Set<DocumentKind> kinds;

  /// Colors chosen for some files (by path), instead of the default ones.
  /// An empty set leaves the file out of the training.
  final Map<String, Set<Stone>> docColors;

  /// Colors played in joseki and tricks (an opening keeps its own color).
  final Set<Stone> colors;
  final DrillFocus focus;

  /// Include the lines where the opponent plays a move marked Bad.
  final bool opponentMistakes;
  final bool showPunishment;
  final bool autoNext;

  DrillSettings copyWith({
    Set<DocumentKind>? kinds,
    Set<Stone>? colors,
    DrillFocus? focus,
    bool? opponentMistakes,
    bool? showPunishment,
    bool? autoNext,
    Map<String, Set<Stone>>? docColors,
  }) => DrillSettings(
    kinds: kinds ?? this.kinds,
    colors: colors ?? this.colors,
    focus: focus ?? this.focus,
    opponentMistakes: opponentMistakes ?? this.opponentMistakes,
    showPunishment: showPunishment ?? this.showPunishment,
    autoNext: autoNext ?? this.autoNext,
    docColors: docColors ?? this.docColors,
  );

  TrainerOptions get trainerOptions => TrainerOptions(
    autoNext: false,
    opponentMistakeRate: opponentMistakes ? 0.25 : 0,
    followMistakes: showPunishment,
  );

  Map<String, Object?> toJson() => {
    'kinds': [for (final k in kinds) k.name],
    'colors': [for (final c in colors) c.sgf],
    'focus': focus.name,
    'opponentMistakes': opponentMistakes,
    'showPunishment': showPunishment,
    'autoNext': autoNext,
    'docColors': {
      for (final e in docColors.entries)
        e.key: e.value.map((c) => c.sgf).join(),
    },
  };

  factory DrillSettings.fromJson(Map<String, Object?> j) {
    const d = DrillSettings();
    final kinds = {
      for (final k in (j['kinds'] as List?) ?? const [])
        ?DocumentKind.values.asNameMap()[k],
    };
    final colors = {
      for (final c in (j['colors'] as List?) ?? const [])
        ?Stone.fromSgf(c as String?),
    };
    return DrillSettings(
      kinds: kinds.isEmpty ? d.kinds : kinds,
      colors: colors.isEmpty ? d.colors : colors,
      focus: DrillFocus.values.asNameMap()[j['focus']] ?? d.focus,
      opponentMistakes: j['opponentMistakes'] as bool? ?? d.opponentMistakes,
      showPunishment: j['showPunishment'] as bool? ?? d.showPunishment,
      autoNext: j['autoNext'] as bool? ?? d.autoNext,
      docColors: {
        for (final e in ((j['docColors'] as Map?) ?? const {}).entries)
          '${e.key}': {
            if ('${e.value}'.contains('B')) Stone.black,
            if ('${e.value}'.contains('W')) Stone.white,
          },
      },
    );
  }
}

/// The knowledge of every line, saved in a JSON file.
class DrillProgress {
  DrillProgress({this.path});

  /// Where it is saved. Null: kept in memory only (tests).
  final String? path;
  final Map<String, LineRecord> records = {};
  DrillSettings settings = const DrillSettings();
  Future<void> _saving = Future.value();

  static Future<DrillProgress> load(String path) async {
    final p = DrillProgress(path: path);
    try {
      if (await storage.exists(path)) p.readJson(await storage.read(path));
    } catch (e) {
      debugPrint('Could not read the training progress: $e');
    }
    return p;
  }

  /// Reads the records and settings saved by [toJson].
  void readJson(String text) {
    final j = jsonDecode(text) as Map<String, Object?>;
    final lines = (j['lines'] as Map?)?.cast<String, Object?>() ?? {};
    for (final e in lines.entries) {
      records[e.key] = LineRecord.fromJson(
        (e.value as Map).cast<String, Object?>(),
      );
    }
    if (j['settings'] case final Map s) {
      settings = DrillSettings.fromJson(s.cast<String, Object?>());
    }
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'settings': settings.toJson(),
    'lines': {for (final e in records.entries) e.key: e.value.toJson()},
  };

  /// Adds the records of [other], keeping for each line the most recent.
  /// Returns the number of lines taken from [other].
  int merge(DrillProgress other) {
    var n = 0;
    for (final e in other.records.entries) {
      final mine = records[e.key];
      final theirs = e.value;
      final newer =
          mine == null ||
          (theirs.last ?? DateTime(0)).isAfter(mine.last ?? DateTime(0));
      if (newer) {
        records[e.key] = theirs;
        n++;
      }
    }
    return n;
  }

  Future<void> save() {
    final f = path;
    if (f == null) return Future.value();
    final text = jsonEncode(toJson());
    // One write at a time, in order.
    return _saving = _saving.then((_) async {
      try {
        await storage.write(f, text);
      } catch (e) {
        debugPrint('Could not save the training progress: $e');
      }
    });
  }

  /// Records a run of the line [key]. Returns its record.
  LineRecord record(
    String key, {
    required int mistakes,
    required bool hinted,
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();
    final r = records[key] ??= LineRecord();
    r.attempts++;
    r.last = t;
    r.mistakes += mistakes;
    if (mistakes == 0 && !hinted) {
      r.cleanRuns++;
      r.streak++;
    } else {
      r.failedRuns++;
      r.streak = 0;
    }
    r.due = t.add(reviewInterval(r.streak));
    return r;
  }
}

/// A file of the global trainer.
class DrillDoc {
  DrillDoc(this.path, this.doc);
  final String path;
  final OpeningDocument doc;
  String get name => doc.name;
  DocumentKind get kind => doc.kind;
}

/// A line to learn: the way to [end] in [doc], played as [color].
class DrillLine {
  DrillLine(this.doc, this.end, this.color, this.number)
    : key = lineKey(end, doc.doc.size, color);

  final DrillDoc doc;
  final SgfNode end;
  final Stone color;

  /// 1-based number among the lines of [doc] for [color].
  final int number;

  /// Identifies the line by its content (start position and moves), so its
  /// progress survives renaming or reordering the file.
  final String key;

  /// "Name › Sub-variation", or "Line 3".
  String get name {
    final names = [for (final n in end.pathFromRoot) ?n.variationName];
    return names.isEmpty ? 'Line $number' : names.join('  ›  ');
  }

  int get moves => end.moveNumber;
}

String lineKey(SgfNode end, int size, Stone color) {
  final root = end.root;
  String setup(String id) => (List.of(root.getAll(id))..sort()).join(',');
  final moves = [
    for (final n in end.pathFromRoot)
      if (n.moveColor case final c?) '${c.sgf}${n.isPass ? '' : n.get(c.sgf)}',
  ];
  return '$size|${color.sgf}|${setup('AB')}|${setup('AW')}|'
      '${root.get('PL') ?? ''}|${moves.join(';')}';
}

/// The result of one line of the global trainer.
class DrillRound {
  DrillRound(this.line, this.mistakes, this.hinted, this.record, this.wasKnown);
  final DrillLine line;
  final int mistakes;
  final bool hinted;
  final LineRecord record;
  final bool wasKnown;
  bool get clean => mistakes == 0 && !hinted;
  bool get newlyKnown => !wasKnown && record.known;
}

/// How much of one file the user knows.
class DocStats {
  DocStats(this.doc);
  final DrillDoc doc;
  int total = 0;
  int known = 0;
  int failing = 0;
  int fresh = 0;

  /// Sum over the lines of their progress toward known (0 to 1 each).
  double score = 0;

  /// Part learned, from 0 to 1 (a line counts by its clean runs in a row).
  double get learned => total == 0 ? 0 : score / total;
  bool get allKnown => total > 0 && known == total;
}

/// Why a line was chosen.
enum DrillReason { retry, failing, fresh, learning, review, extra, chosen }

/// Trains every line of many files at random, brings the lines with
/// mistakes back until they are played cleanly, and keeps track of the
/// lines the user knows.
class DrillSession extends ChangeNotifier {
  DrillSession({
    required this.docs,
    required this.progress,
    Random? random,
    this.trainerOptions,
    this.autoNextDelay = const Duration(milliseconds: 1800),
  }) : _random = random ?? Random() {
    _buildLines();
  }

  final List<DrillDoc> docs;
  final DrillProgress progress;
  final Random _random;

  /// Overrides the trainer options (tests).
  final TrainerOptions? trainerOptions;
  final Duration autoNextDelay;

  DrillSettings get settings => progress.settings;

  /// The lines matching the settings.
  List<DrillLine> lines = [];

  TrainerSession? session;
  DrillLine? line;
  DrillReason? reason;

  /// The result of the current line, once finished.
  DrillRound? round;

  /// A message about the choice of lines (e.g. no mistake left).
  String? notice;
  bool autoNextPending = false;

  // Session statistics.
  int rounds = 0;
  int cleanRounds = 0;
  int mistakes = 0;
  int streak = 0;
  int bestStreak = 0;

  /// Lines missed in this session, then played cleanly.
  final Set<String> fixed = {};

  /// Lines missed in this session, to play again after a few other lines.
  final Map<String, int> _retries = {};
  Timer? _timer;

  // ------------------------------------------------------------ lines

  /// The colors the user may play in [d]: black and white for joseki and
  /// tricks, the studied color for an opening.
  static Set<Stone> possibleColors(DrillDoc d) => d.kind.hasStartPosition
      ? const {Stone.black, Stone.white}
      : {d.doc.color};

  /// The colors trained in [d] by default (no choice made for it).
  Set<Stone> defaultColors(DrillDoc d) =>
      d.kind.hasStartPosition ? settings.colors : {d.doc.color};

  /// The colors trained in [d]; empty when the file is left out.
  Set<Stone> colorsFor(DrillDoc d) =>
      settings.docColors[d.path]?.intersection(possibleColors(d)) ??
      defaultColors(d);

  bool isIncluded(DrillDoc d) => colorsFor(d).isNotEmpty;

  /// The files of the chosen kinds, in name order.
  List<DrillDoc> get kindDocs =>
      docs.where((d) => settings.kinds.contains(d.kind)).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// Trains [d] with [colors] (empty: leaves it out).
  void setDocColors(DrillDoc d, Set<Stone> colors) {
    final map = {...settings.docColors};
    if (colors.length == defaultColors(d).length &&
        colors.containsAll(defaultColors(d))) {
      map.remove(d.path);
    } else {
      map[d.path] = colors;
    }
    updateSettings(settings.copyWith(docColors: map));
  }

  /// Includes every file with its default colors, or leaves them all out.
  void setAllDocs(bool on) {
    final map = {...settings.docColors};
    for (final d in kindDocs) {
      if (on) {
        if (!isIncluded(d)) map.remove(d.path);
      } else {
        map[d.path] = const {};
      }
    }
    updateSettings(settings.copyWith(docColors: map));
  }

  /// The lines of [d] played with [colors].
  List<DrillLine> _linesOf(DrillDoc d, Iterable<Stone> colors) {
    final opts = trainerOptions ?? settings.trainerOptions;
    final out = <DrillLine>[];
    for (final c in const [Stone.black, Stone.white]) {
      if (!colors.contains(c)) continue;
      final ends = trainableLeaves(d.doc.root, c, opts).toList()
        ..sort((a, b) => _order(a).compareTo(_order(b)));
      var i = 0;
      for (final end in ends) {
        // The user must have something to play in the line.
        if (!end.pathFromRoot.any((n) => n.moveColor == c)) continue;
        out.add(DrillLine(d, end, c, ++i));
      }
    }
    return out;
  }

  void _buildLines() {
    lines = [
      for (final d in docs)
        if (settings.kinds.contains(d.kind)) ..._linesOf(d, colorsFor(d)),
    ];
    if (only != null && !lines.any((l) => l.doc == only)) only = null;
    _retries.removeWhere((k, _) => !lines.any((l) => l.key == k));
  }

  /// Position of a node in the tree in display order (for line numbers).
  static String _order(SgfNode n) => [
    for (final p in n.pathFromRoot.skip(1))
      p.parent!.children.indexOf(p).toString().padLeft(4, '0'),
  ].join();

  LineRecord? recordOf(DrillLine l) => progress.records[l.key];

  void updateSettings(DrillSettings s) {
    progress.settings = s;
    unawaited(progress.save());
    final keep = line;
    _buildLines();
    notifyListeners();
    // The current line no longer matches: take another one.
    if (keep == null || !lines.any((l) => l.key == keep.key)) next();
  }

  // ------------------------------------------------------------ stats

  int get knownLines => lines.where((l) => recordOf(l)?.known ?? false).length;
  int get newLines => lines.where((l) => recordOf(l) == null).length;

  /// Lines whose last run had a mistake.
  List<DrillLine> get mistakeLines {
    final out = lines.where((l) => recordOf(l)?.failing ?? false).toList()
      ..sort((a, b) => recordOf(b)!.mistakes.compareTo(recordOf(a)!.mistakes));
    return out;
  }

  int dueLines([DateTime? now]) {
    final t = now ?? DateTime.now();
    return lines.where((l) {
      final r = recordOf(l);
      return r != null && r.known && r.isDue(t);
    }).length;
  }

  /// For each file: (known lines, lines), in the library order.
  List<(DrillDoc, int, int)> get docMastery {
    final out = <DrillDoc, (int, int)>{};
    for (final l in lines) {
      final (k, t) = out[l.doc] ?? (0, 0);
      out[l.doc] = (k + ((recordOf(l)?.known ?? false) ? 1 : 0), t + 1);
    }
    return [for (final e in out.entries) (e.key, e.value.$1, e.value.$2)];
  }

  /// Files whose lines are all known.
  int get knownDocs => docMastery.where((m) => m.$2 == m.$3).length;

  /// Files being trained.
  int get includedDocs => kindDocs.where(isIncluded).length;

  // ------------------------------------------------------------ choice

  double _weight(DrillLine l, DateTime now) {
    final r = recordOf(l);
    if (r == null) return 4;
    if (r.failing) return 8;
    if (!r.known) return 3;
    return r.isDue(now) ? 3 : 0.3;
  }

  /// The next line: a missed line whose turn has come back, otherwise a
  /// random line, favoring mistakes, new lines and lines to review.
  (DrillLine, DrillReason)? _choose() {
    if (this.lines.isEmpty) return null;
    notice = null;
    final last = line;
    final lines = only == null
        ? this.lines
        : this.lines.where((l) => l.doc == only).toList();
    // A missed line comes back after a few other lines.
    for (final k in _retries.keys.toList()) {
      _retries[k] = _retries[k]! - 1;
    }
    final ready = _retries.entries.where((e) => e.value <= 0).toList();
    if (ready.isNotEmpty) {
      final l = lines.where((l) => l.key == ready.first.key).firstOrNull;
      if (l != null && (l.key != last?.key || lines.length == 1)) {
        return (l, DrillReason.retry);
      }
    }
    final now = DateTime.now();
    var pool = switch (settings.focus) {
      DrillFocus.smart => lines,
      DrillFocus.mistakes =>
        lines
            .where(
              (l) =>
                  (recordOf(l)?.failing ?? false) ||
                  _retries.containsKey(l.key),
            )
            .toList(),
      DrillFocus.unknown =>
        lines.where((l) => !(recordOf(l)?.known ?? false)).toList(),
    };
    if (pool.isEmpty) {
      notice = switch (settings.focus) {
        DrillFocus.mistakes => 'No mistake left to fix. Smart mix instead.',
        _ => 'You know every line! Smart mix instead.',
      };
      pool = lines;
    }
    final weights = [
      for (final l in pool)
        _weight(l, now) *
            (l.key == last?.key && pool.length > 1
                ? 0
                : l.doc == last?.doc && pool.length > 2
                ? 0.35
                : 1),
    ];
    final total = weights.fold<double>(0, (a, b) => a + b);
    var r = _random.nextDouble() * total;
    var pick = pool.last;
    for (var i = 0; i < pool.length; i++) {
      r -= weights[i];
      if (r < 0 && weights[i] > 0) {
        pick = pool[i];
        break;
      }
    }
    final rec = recordOf(pick);
    return (
      pick,
      rec == null
          ? DrillReason.fresh
          : rec.failing
          ? DrillReason.failing
          : !rec.known
          ? DrillReason.learning
          : rec.isDue(now)
          ? DrillReason.review
          : DrillReason.extra,
    );
  }

  // ------------------------------------------------------------ flow

  /// Goes to the next line.
  void next() {
    _abandon();
    final c = _choose();
    if (c == null) {
      _setSession(null);
      line = null;
      reason = null;
      round = null;
      notifyListeners();
      return;
    }
    _start(c.$1, c.$2);
  }

  /// Plays [l] now (chosen by the user).
  void play(DrillLine l) {
    _abandon();
    notice = null;
    _start(l, DrillReason.chosen);
  }

  /// Plays a line of [d] not known yet (or any line of it).
  void playDoc(DrillDoc d) {
    final mine = lines.where((l) => l.doc == d).toList();
    if (mine.isEmpty) return;
    final todo = mine.where((l) => !(recordOf(l)?.known ?? false)).toList();
    final pool = todo.isEmpty ? mine : todo;
    play(pool[_random.nextInt(pool.length)]);
  }

  /// Leaving a line before its end: its mistakes still count.
  void _abandon() {
    _timer?.cancel();
    autoNextPending = false;
    final s = session;
    final l = line;
    if (s != null && l != null && round == null && s.lineMistakes > 0) {
      _record(l, s.lineMistakes, s.lineHinted);
    }
  }

  void _start(DrillLine l, DrillReason why) {
    line = l;
    reason = why;
    round = null;
    _retries.remove(l.key);
    _setSession(
      TrainerSession(
        root: l.doc.doc.root,
        size: l.doc.doc.size,
        color: l.color,
        options: trainerOptions ?? settings.trainerOptions,
        target: l.end,
        random: _random,
      ),
    );
    _onSession();
  }

  void _setSession(TrainerSession? s) {
    final old = session;
    session = s;
    s?.addListener(_onSession);
    old
      ?..removeListener(_onSession)
      ..dispose();
  }

  void _onSession() {
    final s = session;
    final l = line;
    if (s == null || l == null) return;
    if (s.lineDone && round == null) {
      // The user may have chosen another good move: the line played is
      // the one that ended.
      final played =
          lines
              .where((x) => x.color == l.color && x.end == s.current)
              .firstOrNull ??
          l;
      line = played;
      _record(played, s.lineMistakes, s.lineHinted);
      if (settings.autoNext) {
        autoNextPending = true;
        _timer = Timer(
          round!.clean ? autoNextDelay : autoNextDelay * 1.6,
          next,
        );
      }
    }
    notifyListeners();
  }

  void _record(DrillLine l, int lineMistakes, bool hinted) {
    final wasKnown = recordOf(l)?.known ?? false;
    final failedBefore = recordOf(l)?.failing ?? false;
    final r = progress.record(l.key, mistakes: lineMistakes, hinted: hinted);
    round = DrillRound(l, lineMistakes, hinted, r, wasKnown);
    rounds++;
    mistakes += lineMistakes;
    if (round!.clean) {
      cleanRounds++;
      streak++;
      if (streak > bestStreak) bestStreak = streak;
      _retries.remove(l.key);
      if (failedBefore) fixed.add(l.key);
    } else {
      streak = 0;
      fixed.remove(l.key);
      // Back after a few other lines (sooner when there are few lines).
      _retries[l.key] = min(lines.length - 1, 2 + _random.nextInt(3));
    }
    unawaited(progress.save());
  }

  /// Only the lines of this file are trained (null: all files).
  DrillDoc? only;

  /// Trains only [doc] (null: every file again).
  void focusDoc(DrillDoc? doc) {
    only = doc;
    next();
  }

  /// Progress of each file, in name order.
  List<DocStats> get docStats {
    final out = <DrillDoc, DocStats>{for (final d in kindDocs) d: DocStats(d)};
    final all = [
      ...lines,
      // A file left out still shows what you know of it.
      for (final d in kindDocs)
        if (!isIncluded(d)) ..._linesOf(d, defaultColors(d)),
    ];
    for (final l in all) {
      final st = out[l.doc] ??= DocStats(l.doc);
      final r = recordOf(l);
      st.total++;
      if (r == null) {
        st.fresh++;
      } else {
        if (r.known) st.known++;
        if (r.failing) st.failing++;
        st.score += min(r.streak, kKnownStreak) / kKnownStreak;
      }
    }
    return out.values.toList()..sort(
      (a, b) => a.doc.name.toLowerCase().compareTo(b.doc.name.toLowerCase()),
    );
  }

  /// Part of all the lines learned, from 0 to 1.
  double get learned {
    if (lines.isEmpty) return 0;
    var score = 0.0;
    for (final l in lines) {
      score += min(recordOf(l)?.streak ?? 0, kKnownStreak) / kKnownStreak;
    }
    return score / lines.length;
  }

  /// Lines missed in this session waiting to come back.
  int get pendingRetries => _retries.length;

  /// Forgets all the progress.
  void resetProgress() {
    progress.records.clear();
    _retries.clear();
    fixed.clear();
    unawaited(progress.save());
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _setSession(null);
    super.dispose();
  }

  /// Loads the readable files of [entries].
  static Future<List<DrillDoc>> loadDocs(Iterable<LibraryEntry> entries) async {
    final out = <DrillDoc>[];
    for (final e in entries) {
      if (e.error != null) continue;
      try {
        out.add(DrillDoc(e.path, await OpeningDocument.load(e.path)));
      } catch (err) {
        debugPrint('Skipping ${e.path}: $err');
      }
    }
    return out;
  }
}
