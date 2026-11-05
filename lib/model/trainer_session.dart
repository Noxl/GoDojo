import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../go/board.dart';
import '../go/point.dart';
import '../go/stone.dart';
import '../sgf/sgf_node.dart';
import 'annotations.dart';
import 'opening_document.dart';

enum StartPoint {
  beginning('From the start'),
  randomBranch('Random branch point');

  const StartPoint(this.label);
  final String label;
}

enum FeedbackKind { info, correct, mistake, notInRepertoire, illegal, complete }

class TrainerFeedback {
  const TrainerFeedback(this.kind, this.message, {this.comment});
  final FeedbackKind kind;
  final String message;

  /// The SGF comment of the relevant node, if any.
  final String? comment;
}

class TrainerOptions {
  const TrainerOptions({
    this.start = StartPoint.beginning,
    this.autoNext = true,
    this.opponentMistakeRate = 0.25,
    this.opponentDelay = const Duration(milliseconds: 450),
    this.autoNextDelay = const Duration(milliseconds: 1600),
    this.replayDelay = const Duration(milliseconds: 25),
    this.followMistakes = false,
    this.punishDelay = const Duration(milliseconds: 550),
  });

  /// Where a new line starts: at the beginning, or at a random branch point
  /// of the line already reached by the user in an earlier line (the moves
  /// before it are replayed quickly).
  final StartPoint start;

  /// Start another line automatically when one is finished.
  final bool autoNext;

  /// Probability that the opponent plays a move annotated as bad (when
  /// such a move exists), so you practice punishing it.
  final double opponentMistakeRate;
  final Duration opponentDelay;
  final Duration autoNextDelay;

  /// Pause between the moves replayed up to a random start point.
  final Duration replayDelay;

  /// When the user plays a move of the tree marked Bad, its
  /// branch is played automatically (to show how it is punished), then the
  /// position comes back and the user has to find the right move.
  /// Lines also go on when the tree only has such moves for the user.
  final bool followMistakes;

  /// Pause between the moves of a punishment shown after a mistake.
  final Duration punishDelay;

  TrainerOptions copyWith({
    StartPoint? start,
    bool? autoNext,
    double? opponentMistakeRate,
    bool? followMistakes,
  }) => TrainerOptions(
    start: start ?? this.start,
    autoNext: autoNext ?? this.autoNext,
    opponentMistakeRate: opponentMistakeRate ?? this.opponentMistakeRate,
    opponentDelay: opponentDelay,
    autoNextDelay: autoNextDelay,
    replayDelay: replayDelay,
    followMistakes: followMistakes ?? this.followMistakes,
    punishDelay: punishDelay,
  );
}

/// Returns the next move nodes after [node], looking through nodes that
/// carry no move (comment or setup nodes).
List<SgfNode> moveChildren(SgfNode node) {
  final out = <SgfNode>[];
  for (final c in node.children) {
    if (c.hasMove) {
      out.add(c);
    } else {
      out.addAll(moveChildren(c));
    }
  }
  return out;
}

bool isMistake(SgfNode n) => MoveQuality.of(n) == MoveQuality.bad;

/// The moves the trainer considers after [n] when the user plays [color]:
/// the user's good moves (or all of them when the tree has only mistakes
/// and [TrainerOptions.followMistakes] is on) and the opponent's allowed
/// moves. Both colors can have moves at the same node (tenuki).
List<SgfNode> trainerChoices(SgfNode n, Stone color, TrainerOptions options) {
  final kids = moveChildren(n);
  final mine = kids.where((k) => k.moveColor == color).toList();
  final theirs = kids.where((k) => k.moveColor != color).toList();
  final good = mine.where((k) => !isMistake(k)).toList();
  final normal = theirs.where((k) => !isMistake(k)).toList();
  return [
    ...good.isNotEmpty || !options.followMistakes ? good : mine,
    ...options.opponentMistakeRate > 0 || normal.isEmpty ? theirs : normal,
  ];
}

/// The ends of the lines the trainer can lead to from [origin]: each one is
/// a line to learn.
Set<SgfNode> trainableLeaves(
  SgfNode origin,
  Stone color,
  TrainerOptions options,
) {
  final out = <SgfNode>{};
  final stack = [origin];
  while (stack.isNotEmpty) {
    final n = stack.removeLast();
    final next = trainerChoices(n, color, options);
    if (next.isEmpty) {
      out.add(n);
    } else {
      stack.addAll(next);
    }
  }
  return out;
}

/// Plays through an opening tree: the user plays [color], the app answers
/// with moves from the tree.
class TrainerSession extends ChangeNotifier {
  TrainerSession({
    required this.root,
    required this.size,
    required this.color,
    this.options = const TrainerOptions(),
    SgfNode? branch,
    SgfNode? target,
    Random? random,
  }) : _random = random ?? Random(),
       _forcedTarget = target,
       _branch = branch == root ? null : branch,
       _current = root,
       _board = Board(size) {
    nextLine();
  }

  final SgfNode root;
  final int size;
  final Stone color;
  TrainerOptions options;
  final Random _random;

  SgfNode _current;
  Board _board;

  /// When set, only the lines going through this node are trained and every
  /// line starts there.
  SgfNode? _branch;
  SgfNode? get branch => _branch;

  /// Trains only the lines through [node] (null: the whole tree).
  void setBranch(SgfNode? node) {
    _branch = node == root ? null : node;
    _visitedLeaves.clear();
    nextLine();
  }

  /// Whether the user has at least one move to play after [node].
  bool canTrainFrom(SgfNode node) =>
      node.descendants.any((d) => d.moveColor == color);

  /// The node lines start from.
  SgfNode get _origin => _branch ?? root;

  /// The leaf the current line is heading to (chosen at random).
  SgfNode? _target;

  /// The line to play first, given by the caller (global trainer).
  SgfNode? _forcedTarget;

  /// Mistakes made in the current line, and whether a hint was used.
  int lineMistakes = 0;
  bool lineHinted = false;
  TrainerFeedback feedback = const TrainerFeedback(FeedbackKind.info, '');
  List<Point> hints = const [];
  Point? wrongPoint;
  bool waitingForOpponent = false;

  /// The opponent move just played if it is marked Bad in the
  /// tree (the user is expected to punish it). Cleared by the next move.
  SgfNode? opponentMistake;
  bool lineDone = false;

  /// The moves before a random start point are being replayed.
  bool replaying = false;

  /// The branch of the user's mistake is being shown.
  bool punishing = false;

  /// A new line will start automatically shortly.
  bool autoNextPending = false;

  /// Moves of the line that were played automatically before the user's
  /// first move (random start point).
  int skippedMoves = 0;

  int correctMoves = 0;
  int mistakes = 0;
  int linesCompleted = 0;

  /// Correct moves in a row, and the best run of the session.
  int streak = 0;
  int bestStreak = 0;

  /// Positions where the user went wrong, with the number of errors.
  final Map<SgfNode, int> mistakesAt = {};
  final Set<SgfNode> _visitedLeaves = {};

  /// Positions the user has already reached by playing (not by skipping).
  late final Set<SgfNode> _played = {root};
  Timer? _timer;

  SgfNode get current => _current;
  Board get board => _board;

  /// The user is expected to move.
  bool get userToMove =>
      !lineDone &&
      !replaying &&
      !punishing &&
      !waitingForOpponent &&
      _userCandidates().isNotEmpty;

  // ------------------------------------------------------------ choices

  /// The moves the trainer considers after [n]: the user's good moves (or
  /// all of them when the tree has only mistakes and [followMistakes] is
  /// on) and the opponent's allowed moves. Both colors can have moves at
  /// the same node (tenuki).
  List<SgfNode> _options(SgfNode n) => trainerChoices(n, color, options);

  /// Random choice among [opts], honoring the mistake rate for opponent
  /// moves. Each option is weighted by the number of lines not seen yet
  /// below it, so every line has the same chance (a big branch is not
  /// drawn as often as a single short line).
  SgfNode _pick(List<SgfNode> opts) {
    var pool = opts;
    final bad = opts
        .where((k) => k.moveColor != color && isMistake(k))
        .toList();
    if (bad.isNotEmpty) {
      final normal = opts.where((k) => !bad.contains(k)).toList();
      pool =
          normal.isEmpty || _random.nextDouble() < options.opponentMistakeRate
          ? bad
          : normal;
    }
    final counts = _lineCounts;
    var weights = [for (final k in pool) counts[k]?.$1 ?? 0];
    if (weights.every((w) => w == 0)) {
      weights = [for (final k in pool) max(1, counts[k]?.$2 ?? 0)];
    }
    var r = _random.nextInt(weights.reduce((a, b) => a + b));
    for (var i = 0; i < pool.length; i++) {
      r -= weights[i];
      if (r < 0) return pool[i];
    }
    return pool.last;
  }

  /// A random line (leaf) from [from], using the rules of [_pick].
  SgfNode _chooseTarget(SgfNode from) {
    var n = from;
    while (true) {
      final opts = _options(n);
      if (opts.isEmpty) return n;
      n = _pick(opts);
    }
  }

  static bool _isAncestor(SgfNode a, SgfNode b) {
    for (SgfNode? n = b; n != null; n = n.parent) {
      if (n == a) return true;
    }
    return false;
  }

  // ------------------------------------------------------------ coverage

  Set<SgfNode>? _reachableCache;

  /// Leaves the trainer can actually lead to with the current options.
  Set<SgfNode> get reachableLeaves =>
      _reachableCache ??= trainableLeaves(_origin, color, options);

  Map<SgfNode, (int, int)>? _countsCache;

  /// For each node: the number of reachable lines below it not seen yet,
  /// and the total number of reachable lines below it.
  Map<SgfNode, (int, int)> get _lineCounts {
    final cached = _countsCache;
    if (cached != null) return cached;
    final out = <SgfNode, (int, int)>{};
    for (final leaf in reachableLeaves) {
      final fresh = _visitedLeaves.contains(leaf) ? 0 : 1;
      for (SgfNode? n = leaf; n != null; n = n.parent) {
        final (f, t) = out[n] ?? (0, 0);
        out[n] = (f + fresh, t + 1);
      }
    }
    return _countsCache = out;
  }

  int get linesCovered => reachableLeaves.where(_visitedLeaves.contains).length;

  /// Call after changing [options].
  void optionsChanged() {
    _reachableCache = null;
    _countsCache = null;
    notifyListeners();
  }

  // ----------------------------------------------------------- flow

  /// Starts a new line, chosen at random among the lines not seen yet.
  void nextLine() {
    _timer?.cancel();
    _reachableCache = null;
    _countsCache = null;
    hints = const [];
    wrongPoint = null;
    opponentMistake = null;
    punishing = false;
    lineDone = false;
    lineMistakes = 0;
    lineHinted = false;
    waitingForOpponent = false;
    replaying = false;
    autoNextPending = false;
    final reachable = reachableLeaves;
    if (reachable.isNotEmpty && reachable.every(_visitedLeaves.contains)) {
      _visitedLeaves.clear();
      _countsCache = null;
    }

    final n = _target = _forcedTarget ?? _chooseTarget(_origin);
    _forcedTarget = null;

    var start = _origin;
    if (options.start == StartPoint.randomBranch) {
      start = _randomStart(n.pathFromRoot);
    }
    skippedMoves = start.moveNumber;
    final intro = skippedMoves == 0
        ? 'You play ${color.label}.'
        : 'You play ${color.label}. Starting after move $skippedMoves.';
    void begin() {
      replaying = false;
      _advanceTo(start);
      feedback = TrainerFeedback(
        FeedbackKind.info,
        intro,
        comment: start.get('C'),
      );
      _continue();
    }

    if (start == root || options.replayDelay == Duration.zero) {
      begin();
      return;
    }
    // Replay the moves up to the start point quickly, one by one.
    final path = start.pathFromRoot;
    var i = 0;
    replaying = true;
    _advanceTo(root);
    feedback = TrainerFeedback(FeedbackKind.info, intro);
    notifyListeners();
    _timer = Timer.periodic(options.replayDelay, (t) {
      i++;
      if (i >= path.length - 1) {
        t.cancel();
        begin();
      } else {
        _advanceTo(path[i]);
        notifyListeners();
      }
    });
  }

  /// A random branch point on [path] that the user already reached in an
  /// earlier line and that still leaves at least one move to find.
  SgfNode _randomStart(List<SgfNode> path) {
    var lastUserDecision = -1;
    for (var i = 0; i < path.length - 1; i++) {
      if (path[i + 1].moveColor == color) lastUserDecision = i;
    }
    final first = path.indexOf(_origin);
    final candidates = <SgfNode>[_origin];
    for (var i = first + 1; i <= lastUserDecision; i++) {
      // A branch point: more than one possible continuation here, or the
      // node right after one (so the user sees where the line diverged).
      if (!_played.contains(path[i])) break;
      if (_options(path[i]).length > 1 || _options(path[i - 1]).length > 1) {
        candidates.add(path[i]);
      }
    }
    return candidates[_random.nextInt(candidates.length)];
  }

  /// Decides what happens after the current node: user turn, opponent
  /// reply or end of line.
  void _continue() {
    // The user may have left the planned line: aim for a new one from here.
    final target = _target;
    if (target == null || !_isAncestor(_current, target)) {
      _target = _chooseTarget(_current);
    }
    final kids = moveChildren(_current);
    final userKids = kids.where((k) => k.moveColor == color).toList();
    final theirs = _options(_current).where((k) => k.moveColor != color);
    // When both colors have moves here, the opponent plays twice in a row
    // only if the planned line goes that way.
    final opponentNext =
        theirs.isNotEmpty &&
        (userKids.isEmpty || theirs.any((k) => _isAncestor(k, _target!)));
    if (!opponentNext &&
        (userKids.isEmpty ||
            (_goodUserMoves().isEmpty && !options.followMistakes))) {
      _finishLine();
      return;
    }
    if (!opponentNext) {
      notifyListeners();
      return;
    }
    waitingForOpponent = true;
    notifyListeners();
    if (options.opponentDelay == Duration.zero) {
      _playOpponent();
    } else {
      _timer = Timer(options.opponentDelay, _playOpponent);
    }
  }

  void _playOpponent() {
    waitingForOpponent = false;
    final opts = _options(_current).where((k) => k.moveColor != color).toList();
    if (opts.isEmpty) {
      _finishLine();
      return;
    }
    final tenuki = _userCandidates().isNotEmpty;
    final target = _target;
    final towardTarget = target == null
        ? null
        : opts.where((k) => _isAncestor(k, target)).firstOrNull;
    final pick = towardTarget ?? _pick(opts);
    _advanceTo(pick);
    final where = _describe(pick);
    opponentMistake = isMistake(pick) ? pick : null;
    feedback = TrainerFeedback(
      FeedbackKind.info,
      '${tenuki ? 'You play elsewhere (tenuki). ' : ''}'
      '${isMistake(pick) ? 'Opponent played $where, a mistake. Punish it!' : 'Opponent played $where.'}',
      // The comment of a mistake is shown in its own box.
      comment: isMistake(pick) ? null : pick.get('C'),
    );
    _continue();
  }

  List<SgfNode> _userCandidates() =>
      moveChildren(_current).where((k) => k.moveColor == color).toList();

  List<SgfNode> _goodUserMoves() =>
      _userCandidates().where((k) => !isMistake(k)).toList();

  /// Handles a click of the user on [p], or a tenuki when [p] is null
  /// (stored as a pass in the SGF: no stone on this board).
  void userPlay(Point? p) {
    if (!userToMove) return;
    hints = const [];
    final candidates = _userCandidates();
    final match = candidates
        .where((k) => p == null ? k.isPass : k.movePoint(size) == p)
        .firstOrNull;
    if (match == null && p == null) {
      _miss();
      wrongPoint = null;
      feedback = const TrainerFeedback(
        FeedbackKind.notInRepertoire,
        'Tenuki is not in your repertoire here. Try again.',
      );
      notifyListeners();
      return;
    }
    if (match == null) {
      final legal = _board.check(p!, color);
      wrongPoint = p;
      if (legal == MoveResult.ok) {
        _miss();
        feedback = const TrainerFeedback(
          FeedbackKind.notInRepertoire,
          'Not in your repertoire. Try again.',
        );
      } else {
        feedback = TrainerFeedback(
          FeedbackKind.illegal,
          'Illegal move (${legal.name}).',
        );
      }
      notifyListeners();
      return;
    }
    final good = _goodUserMoves();
    if (isMistake(match) && good.isNotEmpty && options.followMistakes) {
      _miss();
      _showPunishment(match);
      return;
    }
    if (isMistake(match) && good.isNotEmpty) {
      _miss();
      wrongPoint = p;
      feedback = TrainerFeedback(
        FeedbackKind.mistake,
        'That is a known bad move. Try again.',
        comment: match.get('C'),
      );
      notifyListeners();
      return;
    }
    correctMoves++;
    streak++;
    // The mistake is only called out until the user answers it.
    opponentMistake = null;
    if (streak > bestStreak) bestStreak = streak;
    wrongPoint = null;
    final others = good.where((k) => k != match).map(_describe).toList();
    _advanceTo(match);
    feedback = TrainerFeedback(
      FeedbackKind.correct,
      'Correct! ${_describe(match)}'
      '${others.isEmpty ? '' : '  (also good here: ${others.join(', ')})'}',
      comment: match.get('C'),
    );
    _continue();
  }

  /// Plays the branch of the user's mistake [move] automatically, then
  /// goes back to the position before it: the user has to find the right
  /// move.
  void _showPunishment(SgfNode move) {
    final before = _current;
    const title = 'Bad move!';
    // The branch: the main (first good) continuation at each node.
    final path = <SgfNode>[move];
    while (path.length < 30) {
      final kids = moveChildren(path.last);
      if (kids.isEmpty) break;
      path.add(kids.where((k) => !isMistake(k)).firstOrNull ?? kids.first);
    }
    final comments = [
      for (final n in path)
        if (n.get('C') case final c? when c.trim().isNotEmpty) c,
    ];
    hints = const [];
    opponentMistake = null;
    wrongPoint = null;
    punishing = true;

    void show(int i) {
      _advanceTo(path[i]);
      feedback = TrainerFeedback(
        FeedbackKind.mistake,
        path.length == 1 ? title : '$title Watch how the opponent punishes it.',
        comment: comments.isEmpty ? null : comments.join('\n\n'),
      );
    }

    void back() {
      _timer?.cancel();
      punishing = false;
      _advanceTo(before);
      wrongPoint = move.movePoint(size);
      feedback = TrainerFeedback(
        FeedbackKind.mistake,
        '$title ${_describe(move)} is punished like that. '
        'Now find the right move.',
        comment: comments.isEmpty ? null : comments.join('\n\n'),
      );
      notifyListeners();
    }

    if (options.punishDelay == Duration.zero) {
      for (var i = 0; i < path.length; i++) {
        show(i);
      }
      back();
      return;
    }
    show(0);
    notifyListeners();
    var i = 0;
    _timer = Timer.periodic(options.punishDelay, (t) {
      i++;
      if (i < path.length) {
        show(i);
        notifyListeners();
      } else if (i >= path.length + 2) {
        // A short pause on the final position before coming back.
        back();
      }
    });
  }

  void _miss() {
    mistakes++;
    lineMistakes++;
    streak = 0;
    mistakesAt[_current] = (mistakesAt[_current] ?? 0) + 1;
  }

  /// Shows the expected moves on the board.
  void showHint() {
    if (!userToMove) return;
    streak = 0;
    lineHinted = true;
    final good = _goodUserMoves();
    final pool = good.isNotEmpty ? good : _userCandidates();
    hints = [
      for (final k in pool)
        if (k.movePoint(size) != null) k.movePoint(size)!,
    ];
    // A tenuki has no point to show on the board.
    if (pool.any((k) => k.isPass)) {
      feedback = TrainerFeedback(
        FeedbackKind.info,
        hints.isEmpty
            ? 'Hint: tenuki (play elsewhere).'
            : 'Hint: one of the marked moves, or tenuki.',
      );
    }
    notifyListeners();
  }

  void _advanceTo(SgfNode node) {
    if (!replaying && !punishing) _played.add(node);
    _current = node;
    _board = positionAt(node, size);
  }

  void _finishLine() {
    lineDone = true;
    linesCompleted++;
    _visitedLeaves
      ..add(_current)
      ..addAll(_current.leaves);
    _countsCache = null;
    final total = reachableLeaves.length;
    final prev = feedback;
    final keep =
        prev.kind == FeedbackKind.correct || prev.kind == FeedbackKind.mistake;
    feedback = TrainerFeedback(
      FeedbackKind.complete,
      '${keep ? '${prev.message}\n' : ''}'
      'Line complete! ($linesCovered/$total lines covered)',
      comment: prev.comment,
    );
    if (options.autoNext) {
      autoNextPending = true;
      _timer = Timer(options.autoNextDelay, nextLine);
    }
    notifyListeners();
  }

  String _describe(SgfNode n) {
    final p = n.movePoint(size);
    return p == null ? 'tenuki' : p.display(size);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
