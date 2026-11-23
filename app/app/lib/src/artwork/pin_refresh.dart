/// Bringing the covers pinned for offline up to date after covers
/// changed and nothing says which, and pinning the cover of a download
/// held with none.
library;

import 'dart:async';

import 'package:waxdeck_data/waxdeck_data.dart';

/// What asking the server about one pinned cover came to.
enum PinAnswer {
  /// It had another picture, which is now the pinned one. Of a pin there
  /// was to make: it is made.
  replaced,

  /// The pinned copy is the server's.
  unchanged,

  /// Not this walk's to ask about: nothing was asked, so nothing was
  /// heard.
  skipped,

  /// The server has no cover there, or none any more. A pinned copy
  /// stays: it is what the item has offline.
  gone,

  /// The server answered and would not give this cover. It may be this
  /// cover's trouble or the server's: the pins after it say which.
  refused,

  /// The server could not be asked, or would not hear this session.
  unanswered,
}

/// Where a walk of every pin stands, as it is remembered across a
/// restart.
class PinWalk {
  const PinWalk({
    this.after,
    this.again = false,
    this.tries = 0,
    this.passed = const <PinCursor>[],
    this.retried,
    this.named = const <PinCursor>[],
    this.whole = true,
  });

  /// The last pin asked about, null before the first.
  final PinCursor? after;

  /// Pins whose covers were replaced, asked about ahead of the rest.
  final List<PinCursor> named;

  /// Every pin is owed; false where only [named] are.
  final bool whole;

  /// Covers changed again after the walk set out: one more walk is owed
  /// when this one ends.
  final bool again;

  /// How often the refusals just past [after] have stopped the walk.
  final int tries;

  /// Pins the server refused and the walk passed, to be asked again once
  /// the rest have been.
  final List<PinCursor> passed;

  /// Null while the rest are being asked; then how many times [passed]
  /// has been asked again.
  final int? retried;

  /// Whether none of it is owed. A walk with only pins to make is one:
  /// those are not its to remember.
  bool get _idle =>
      !whole && named.isEmpty && passed.isEmpty && retried == null;

  PinWalk _with({
    PinCursor? after,
    bool? again,
    int? tries,
    List<PinCursor>? passed,
    List<PinCursor>? named,
    bool? whole,
  }) => PinWalk(
    after: after ?? this.after,
    again: again ?? this.again,
    tries: tries ?? this.tries,
    passed: passed ?? this.passed,
    retried: retried,
    named: named ?? this.named,
    whole: whole ?? this.whole,
  );

  @override
  bool operator ==(Object other) =>
      other is PinWalk &&
      other.after == after &&
      other.again == again &&
      other.tries == tries &&
      other.retried == retried &&
      other.whole == whole &&
      _sameCursors(other.passed, passed) &&
      _sameCursors(other.named, named);

  @override
  int get hashCode => Object.hash(
    after,
    again,
    tries,
    retried,
    whole,
    Object.hashAll(passed),
    Object.hashAll(named),
  );

  @override
  String toString() =>
      'PinWalk(after: $after, again: $again, tries: $tries, '
      'passed: $passed, retried: $retried, named: $named, whole: $whole)';
}

bool _sameCursors(List<PinCursor> a, List<PinCursor> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Walks every pinned cover and asks the server about each.
///
/// One request at a time with [pace] between two, and none while [gate]
/// is shut. A walk the gate or the server stops keeps its place and goes
/// on from it: when the gate opens, [retryAfter] later, or at the next
/// start, from what [remember] was last told.
///
/// A pin the server answers for and will not give ([PinAnswer.refused])
/// is passed, and the walk asks it again once it has asked the rest:
/// [retryRounds] times at most, each wait twice the last, and what is
/// still refused then waits for the next walk. Whose trouble a refusal
/// is, the pins around it say: one of them answering makes it that
/// cover's. [refusedRun] refusals in a row, or every pin left, ask the
/// last pin that answered again; refused too, the walk goes back to the
/// first of them and stops as it does for no answer. The third time the
/// same pins stop it they are passed whatever follows, so no refusal
/// holds a walk for ever.
///
/// Pins whose own covers were replaced ([requestFor]) are asked about
/// ahead of the rest, under the same gate and pace, and with no walk of
/// the rest where none is owed.
///
/// Pins there are to make ([want]: a download held with no cover) are
/// asked for after those and ahead of the rest, one request each under
/// the same gate and pace. One the server refuses is asked again with
/// the walk's other refusals, and a run of them stops the walk as a run
/// of those does. One still refused when the rounds are spent, or past
/// the [passedHeld] kept, is given up: not wanted again until its cover
/// may be another ([wantAgain]). One it does not answer for
/// stops the walk as any pin does, and is set aside with its item's
/// other sizes: asked for again no sooner than [retryAfter] later,
/// whoever wants it meanwhile, and behind a turn of the rest of the
/// walk. Which pins are wanted is not remembered across a restart:
/// [want] says again.
class PinRefresh {
  PinRefresh({
    required this._pins,
    required this._gate,
    required this._ask,
    required this._remember,
    this._make,
    this.pace = const Duration(milliseconds: 250),
    this.retryAfter = const Duration(minutes: 2),
    this.pageSize = 32,
  });

  /// How many refusals in a row before the walk asks whether the server
  /// still answers. Not a sign of the server's trouble by itself: one
  /// cover the server cannot read refuses for both rungs of every
  /// downloaded track that shows it, so the last pin that answered is
  /// asked again, and its answer says. The number only sets how often
  /// that costs a request.
  static const int refusedRun = 4;

  /// How many times one run of refusals stops the walk before it is
  /// passed.
  static const int refusedTries = 3;

  /// How many times the passed pins are asked again.
  static const int retryRounds = 3;

  /// The most passed pins kept to ask again; any more wait for the next
  /// walk.
  static const int passedHeld = 256;

  /// The most pins named ahead of the rest; past it every pin is walked.
  static const int namedHeld = 256;

  final ArtworkPinStore _pins;
  final TransferGate _gate;
  final Future<PinAnswer> Function(ArtworkPinRecord pin) _ask;

  /// Asks for a pin that does not exist, at the art URL [want] gave it.
  /// Null where none are made.
  final Future<PinAnswer> Function(PinCursor at, String artUrl)? _make;

  /// Told where the walk stands, null once it is over: at each stop, and
  /// once per [pageSize] pins.
  final Future<void> Function(PinWalk? walk) _remember;

  /// The least time between two requests.
  final Duration pace;

  /// How long a stopped walk waits before it looks again unprompted.
  final Duration retryAfter;

  /// How many pins are read, and asked about, between two [_remember]s.
  final int pageSize;

  PinWalk? _walk;

  /// The art URL of each pin there is to make, as [want] last gave them.
  final Map<PinCursor, String> _toMake = <PinCursor, String>{};

  /// Those of them still to ask for, in the order they are asked.
  final Set<PinCursor> _wanted = <PinCursor>{};

  /// Those the server did not answer for, each with its item's other
  /// sizes: wanted again once [_back] has run, the last of the wanted.
  final Set<PinCursor> _aside = <PinCursor>{};
  Timer? _back;
  bool _backDue = false;

  /// Whether the rest of the walk goes ahead of [_aside] coming back:
  /// from one of them going unanswered until a run reaches the rest.
  bool _restFirst = false;

  /// Those the server refused to the end of the rounds, or past the
  /// [passedHeld] kept: not wanted again until [wantAgain] names them.
  final Set<PinCursor> _givenUp = <PinCursor>{};

  /// Whether the walk has asked about a pin since it last set out.
  bool _moved = false;

  /// What the gate was last known to say, by a word or a full look, and
  /// how many words it has had.
  bool? _open;
  int _said = 0;

  /// Where the walk stood before the first of the refusals it is in the
  /// middle of, with how many pins were passed by then, and how many
  /// refusals there have been since.
  ({PinCursor? after, int passed})? _refusedFrom;
  int _refused = 0;

  /// The pins to make among them, wanted again if they stop the walk.
  final List<PinCursor> _refusedMade = <PinCursor>[];

  /// The run of refusals that last stopped the walk, and how often.
  ({PinCursor? after})? _triedFrom;
  int _tries = 0;

  /// Whether a pin has answered since the walk set out or went on.
  bool _heard = false;

  /// The last pin that answered, to ask again about refusals.
  PinCursor? _lastHeard;

  /// How far the round asking the passed pins again has got, null
  /// between rounds.
  int? _roundAt;

  bool _running = false;

  /// Moves when the walk is dropped. A run from before that goes no
  /// further than the step it is on.
  int _era = 0;
  int _runEra = 0;

  /// Whether the run in hand has nothing more to do.
  bool get _gone => _disposed || _walk == null || _runEra != _era;

  /// Something asked for the walk while it was running.
  bool _nudged = false;

  /// Something that ends a rest asked for it: anything but named pins.
  bool _nudgeEnds = false;

  /// The named pin being asked about, and whether it was named again
  /// meanwhile.
  PinCursor? _asking;
  bool _namedAgain = false;

  Future<void> _loop = Future<void>.value();
  Timer? _waiting;

  /// Whether the gate opening ends the wait in hand.
  bool _gateEnds = true;

  /// Looks again for what was asked ahead of the rest and stopped while
  /// a wait the gate does not end was in hand, and whether the gate
  /// opening ends it.
  Timer? _ahead;
  bool _aheadGateEnds = true;
  Completer<void>? _pausing;
  Timer? _paced;
  StreamSubscription<bool>? _gateSaid;
  bool _disposed = false;

  /// Covers changed and nothing says which: every pin is asked about
  /// from here on. During a walk this starts no second one; the walk in
  /// hand is followed by one more.
  void request() {
    if (_disposed) return;
    final walk = _walk;
    if (walk == null) {
      _moved = false;
      _clearRun();
      _walk = const PinWalk();
      unawaited(_tell());
    } else if (!walk.whole && walk.retried == null) {
      // Only named pins were owed: the rest set out from the top.
      _walk = walk._with(whole: true);
      unawaited(_tell());
    } else if (!walk.again &&
        (walk.after != null || _moved || walk.retried != null)) {
      _walk = walk._with(again: true);
      unawaited(_tell());
    }
    _go();
  }

  /// The covers under [pins] were replaced: each is asked about ahead of
  /// whatever else is owed, under the same gate and pace. Past
  /// [namedHeld] waiting, every pin is walked instead.
  void requestFor(Iterable<PinCursor> pins) {
    if (_disposed) return;
    final walk = _walk;
    final named = [...?walk?.named];
    for (final at in pins) {
      if (!named.contains(at)) {
        named.add(at);
      } else if (at == _asking) {
        // Its answer in flight is from before this change.
        _namedAgain = true;
      }
    }
    if (walk != null && named.length == walk.named.length) return;
    if (named.length > namedHeld) return request();
    if (walk == null) {
      _moved = false;
      _clearRun();
    }
    _walk = (walk ?? const PinWalk(whole: false))._with(named: named);
    unawaited(_tell());
    _go(named: true);
  }

  /// [pins], each with its art URL, do not exist and are to be made:
  /// asked for after the named, under the same gate and pace. They are
  /// every pin there is to make: one wanted before and not among them is
  /// dropped. Each call sets a stopped walk looking again.
  void want(Map<PinCursor, String> pins) {
    if (_disposed || _make == null) return;
    _toMake
      ..clear()
      ..addAll(pins);
    _wanted.retainWhere(pins.containsKey);
    _aside.retainWhere(pins.containsKey);
    // One the server refused keeps its turn among the refusals, and one
    // given up is not asked for at every reach. One set aside waits its
    // own wait out.
    final passed = <PinCursor>{...?_walk?.passed};
    for (final at in pins.keys) {
      if (passed.contains(at) || _givenUp.contains(at)) continue;
      if (!_aside.contains(at)) _wanted.add(at);
    }
    if (_wanted.isEmpty) return;
    if (_walk == null) {
      _moved = false;
      _clearRun();
      _walk = const PinWalk(whole: false);
    }
    _go(named: true);
  }

  /// The cover of [pid], or any where null, may be another now: a pin to
  /// make there that was given up is wanted again by the next [want].
  void wantAgain(String? pid) =>
      _givenUp.removeWhere((at) => pid == null || at.pid == pid);

  /// Takes up the walk an earlier run left.
  void resume(PinWalk walk) {
    if (_disposed) return;
    _walk = walk;
    _clearRun();
    if (walk.tries > 0) {
      _triedFrom = (after: walk.after);
      _tries = walk.tries;
    }
    _go();
  }

  /// Drops the walk: there is nothing pinned to ask about any more, and
  /// no pin to make that was wanted before.
  void forget() {
    _era++;
    _walk = null;
    _toMake.clear();
    _wanted.clear();
    _aside.clear();
    _backDue = false;
    _restFirst = false;
    _givenUp.clear();
    _clearRun();
    _lastHeard = null;
    _quiet();
  }

  /// Done when the walk is over or has stopped to wait.
  Future<void> get settled => _loop;

  void dispose() {
    _disposed = true;
    _era++;
    _quiet();
  }

  void _quiet() {
    _waiting?.cancel();
    _waiting = null;
    _ahead?.cancel();
    _ahead = null;
    _back?.cancel();
    _back = null;
    _paced?.cancel();
    _paced = null;
    _pausing?.complete();
    _pausing = null;
    unawaited(_gateSaid?.cancel());
    _gateSaid = null;
  }

  /// The refusal bookkeeping, which belongs to one walk.
  void _clearRun() {
    _refused = 0;
    _refusedFrom = null;
    _refusedMade.clear();
    _tries = 0;
    _triedFrom = null;
    _roundAt = null;
  }

  /// Sets the walk going. [named] pins, and pins to make, do not end a
  /// rest the gate does not end either: the walk asks them and goes back
  /// to resting.
  void _go({bool byGate = false, bool named = false}) {
    if (_disposed || _walk == null) return;
    // Under a wait the gate does not end, its word is only for what
    // stopped there to look again, and the wait stands.
    final under = byGate && _waiting != null && !_gateEnds;
    if (under && (_ahead == null || !_aheadGateEnds)) return;
    final ahead = named || under;
    if (_running) {
      _nudged = true;
      if (!ahead) _nudgeEnds = true;
      return;
    }
    if (!ahead || _gateEnds) {
      _waiting?.cancel();
      _waiting = null;
    }
    _ahead?.cancel();
    _ahead = null;
    // Listened to afresh each time: what the gate reads may have been
    // built since the walk set out.
    unawaited(_gateSaid?.cancel());
    _gateSaid = _gate.changes.listen((open) {
      _said++;
      final was = _open;
      _open = open;
      // One that repeats what was known, as a new listener's first word
      // does, is no news.
      if (open && was != true) _go(byGate: true);
    }, onError: (Object _) {});
    _running = true;
    _nudged = false;
    _nudgeEnds = false;
    _loop = _run();
  }

  /// Stops for [after], or until the gate says it opened where
  /// [gateEnds]. A wait in hand that the gate does not end stands: what
  /// stopped under it looks again by itself, and the rest of the walk
  /// when that wait is up.
  void _waitFor(Duration after, {bool gateEnds = true}) {
    if (_disposed || _walk == null) return;
    if (_waiting != null && !_gateEnds) {
      _ahead?.cancel();
      _aheadGateEnds = gateEnds;
      _ahead = Timer(after, () {
        _ahead = null;
        _go(named: true);
      });
      return;
    }
    _waiting?.cancel();
    _gateEnds = gateEnds;
    _waiting = Timer(after, () {
      _waiting = null;
      _go();
    });
  }

  Future<void> _run() async {
    _runEra = _era;
    // Whether this run has reached the rest of the walk.
    var rest = false;
    try {
      _heard = false;
      while (!_gone) {
        if (_walk!.named.isNotEmpty) {
          if (await _askNamed()) return;
          continue;
        }
        // Pins set aside are wanted again once their wait is up, behind
        // a turn the rest of the walk is owed or is in the middle of.
        if (_backDue && !(_restToAsk && (rest || _restFirst))) {
          _backDue = false;
          _wanted.addAll(_aside);
          _aside.clear();
        }
        if (_wanted.isNotEmpty) {
          if (await _askWanted()) return;
          continue;
        }
        // A rest the named pins came in during goes on.
        if (_waiting != null) return;
        rest = true;
        _restFirst = false;
        if (_walk!.retried != null) {
          if (await _askAgain()) return;
          continue;
        }
        // The pins before the gate: with none left there is nothing to
        // wait at it for.
        final page = _walk!.whole
            ? await _pins.pinsAfter(_walk!.after, limit: pageSize)
            : const <ArtworkPinRecord>[];
        if (_gone) return;
        if (page.isEmpty) {
          // Refusals with no answer anywhere near them may be no answer.
          if (_refused > 0 && !_heard && await _refusalsStop()) return;
          if (_gone) return;
          final walk = _walk!;
          _moved = false;
          _clearRun();
          if (walk.again) {
            // One more from the top, which asks the passed pins too.
            _walk = PinWalk(named: walk.named);
          } else if (walk.passed.isNotEmpty) {
            _walk = PinWalk(
              after: walk.after,
              passed: walk.passed,
              retried: 0,
              named: walk.named,
              whole: walk.whole,
            );
            return await _hold(retryAfter);
          } else {
            _over();
          }
          await _tell();
          if (_gone) return;
          // Only pins set aside are left: their wait brings the walk
          // back.
          if (_aside.isNotEmpty &&
              !_backDue &&
              _wanted.isEmpty &&
              _walk!.named.isEmpty &&
              !_walk!.whole) {
            return;
          }
          continue;
        }
        final open = await _look();
        if (_gone) return;
        if (!open) return _waitFor(retryAfter);
        for (final pin in page) {
          // Pins named meanwhile go first; the page is read again after.
          if (_walk!.named.isNotEmpty) break;
          if (_open != true) return await _stop();
          // From the asking on: an answer in flight is from before any
          // change that comes after it.
          _moved = true;
          final before = _walk!.after;
          final answer = await _ask(pin);
          if (_gone) return;
          if (answer == PinAnswer.unanswered) {
            // The refusals before it wait for the same answer.
            if (_refused > 0) _backTo(_refusedFrom!);
            _fromTheTop();
            return await _stop();
          }
          final at = (pid: pin.pid, sizePx: pin.sizePx);
          _walk = _walk!._with(after: at, tries: 0);
          // Nothing was asked: neither an answer nor a refusal.
          if (answer == PinAnswer.skipped) continue;
          if (answer == PinAnswer.refused) {
            if (_refused++ == 0) {
              _refusedFrom = (after: before, passed: _walk!.passed.length);
            }
            if (_walk!.passed.length < passedHeld) {
              _walk = _walk!._with(passed: [..._walk!.passed, at]);
            }
            if (_refused % refusedRun == 0 && await _refusalsStop()) return;
            if (_gone) return;
          } else {
            // The server answers: what it refused was those covers'.
            _heard = true;
            _lastHeard = at;
            _refused = 0;
            _refusedMade.clear();
          }
          await _pause();
          if (_gone) return;
        }
        await _tell();
      }
    } catch (_) {
      // A run from before the walk was dropped leaves the next alone.
      if (_runEra != _era) return;
      // The pin store, or the server's answer, could not be kept. The
      // walk stands where it was last remembered, and the gate opening
      // mends neither.
      _nudged = false;
      _waitFor(retryAfter, gateEnds: false);
    } finally {
      _running = false;
      if (_walk == null) {
        _quiet();
      } else if (_nudged) {
        // Asked for, or the gate opened, while this was stopping.
        _go(named: !_nudgeEnds);
      }
    }
  }

  /// A full look at the gate. A word said while it was being asked is
  /// newer.
  Future<bool> _look() async {
    final said = _said;
    final open = await _gate.isOpen();
    if (_said == said) _open = open;
    return _open == true;
  }

  /// Asks the passed pins again, a round at a time. True once the walk
  /// has stopped, or rests until its next round.
  Future<bool> _askAgain() async {
    if (_walk!.again) {
      // Covers changed again: a walk from the top asks these too.
      _walk = PinWalk(named: _walk!.named);
      _moved = false;
      _clearRun();
      await _tell();
      return false;
    }
    if (_roundAt == null) {
      final walk = _walk!;
      if (walk.passed.isEmpty || walk.retried! >= retryRounds) {
        // What is still refused waits for the next walk, and so does
        // any count of refusals: pins to make are refused during rounds.
        // Those of them still refused are given up.
        _givenUp.addAll(walk.passed.where(_toMake.containsKey));
        _over();
        _clearRun();
        await _tell();
        return false;
      }
      // Counted as it sets out, so a restart part-way spends it, and a
      // restart stands for the wait before it.
      _walk = PinWalk(
        after: walk.after,
        passed: walk.passed,
        retried: walk.retried! + 1,
        named: walk.named,
        whole: walk.whole,
      );
      _roundAt = 0;
      await _tell();
      if (_gone) return true;
    }
    final open = await _look();
    if (_gone) return true;
    if (!open) {
      _waitFor(retryAfter);
      return true;
    }
    while (!_walk!.again && _roundAt! < _walk!.passed.length) {
      // Pins named meanwhile go first; the round goes on after.
      if (_walk!.named.isNotEmpty) return false;
      if (_open != true) {
        await _stop();
        return true;
      }
      final at = _walk!.passed[_roundAt!];
      final pin = await _pinAt(at);
      if (_gone) return true;
      final artUrl = pin == null ? _toMake[at] : null;
      // Unpinned since, and not one to make: nothing to ask.
      if (pin == null && artUrl == null) {
        _dropPassed(_roundAt!);
        continue;
      }
      final answer = pin == null ? await _make!(at, artUrl!) : await _ask(pin);
      if (_gone) return true;
      switch (answer) {
        case PinAnswer.unanswered:
          // A pin to make leaves the round for its own wait, as one
          // asked for the first time does.
          if (pin == null) {
            _dropPassed(_roundAt!);
            _setAside(at);
          }
          await _stop();
          return true;
        case PinAnswer.refused:
          _roundAt = _roundAt! + 1;
        case PinAnswer.skipped:
          _dropPassed(_roundAt!);
          // Of a pin there is, nothing was asked. One to make may have
          // been asked for and not kept: the pace follows it.
          if (pin != null) continue;
        case _:
          _dropPassed(_roundAt!);
      }
      await _pause();
      if (_gone) return true;
    }
    if (_walk!.again) return false;
    _roundAt = null;
    final walk = _walk!;
    if (walk.passed.isEmpty || walk.retried! >= retryRounds) return false;
    await _hold(retryAfter * (1 << walk.retried!));
    return true;
  }

  void _dropPassed(int at) {
    _walk = _walk!._with(passed: [..._walk!.passed]..removeAt(at));
  }

  /// Asks the pins named ahead of the rest. True once the walk has
  /// stopped.
  Future<bool> _askNamed() async {
    final open = await _look();
    if (_gone) return true;
    if (!open) {
      _waitFor(retryAfter);
      return true;
    }
    while (_walk!.named.isNotEmpty) {
      if (_open != true) {
        await _stop();
        return true;
      }
      final at = _walk!.named.first;
      final pin = await _pinAt(at);
      if (_gone) return true;
      // Unpinned since: nothing to ask.
      if (pin == null) {
        _dropNamed(at);
        continue;
      }
      _asking = at;
      _namedAgain = false;
      final PinAnswer answer;
      try {
        answer = await _ask(pin);
      } finally {
        _asking = null;
      }
      if (_gone) return true;
      _dropNamed(at);
      // Named again while asked: once more, after the rest named.
      if (_namedAgain && answer != PinAnswer.skipped) {
        _walk = _walk!._with(named: [..._walk!.named, at]);
      }
      switch (answer) {
        case PinAnswer.unanswered:
          // Still owed.
          _walk = _walk!._with(
            named: [at, ..._walk!.named.where((other) => other != at)],
          );
          await _stop();
          return true;
        case PinAnswer.skipped:
          continue;
        case PinAnswer.refused:
          // Asked again with the walk's other refusals.
          final passed = _walk!.passed;
          if (!passed.contains(at) && passed.length < passedHeld) {
            _walk = _walk!._with(passed: [...passed, at]);
          }
        case _:
          _heard = true;
          _lastHeard = at;
      }
      await _pause();
      if (_gone) return true;
    }
    await _tell();
    return false;
  }

  void _dropNamed(PinCursor at) {
    _walk = _walk!._with(named: [..._walk!.named]..remove(at));
  }

  /// Asks for the pins there are to make, a page of them between two
  /// looks at the gate. True once the walk has stopped.
  Future<bool> _askWanted() async {
    final open = await _look();
    if (_gone) return true;
    if (!open) {
      _waitFor(retryAfter);
      return true;
    }
    for (var asked = 0; asked < pageSize && _wanted.isNotEmpty; asked++) {
      // Pins named meanwhile go first.
      if (_walk!.named.isNotEmpty) return false;
      if (_open != true) {
        await _stop();
        return true;
      }
      final at = _wanted.first;
      final artUrl = _toMake[at];
      final pinned = artUrl != null && await _pinAt(at) != null;
      if (_gone) return true;
      // Pinned since, as its download's own start pins it: nothing to
      // make.
      if (artUrl == null || pinned) {
        _wanted.remove(at);
        continue;
      }
      final answer = await _make!(at, artUrl);
      if (_gone) return true;
      _wanted.remove(at);
      switch (answer) {
        case PinAnswer.unanswered:
          _setAside(at);
          await _stop();
          return true;
        case PinAnswer.skipped:
          // It may have been asked for and not kept: the pace follows
          // it.
          break;
        case PinAnswer.refused:
          if (_refused++ == 0) {
            _refusedFrom = (after: _walk!.after, passed: _walk!.passed.length);
          }
          // Asked again with the walk's other refusals, where its turn
          // among them does not stand already.
          final passed = _walk!.passed;
          if (!passed.contains(at)) {
            _refusedMade.add(at);
            if (passed.length < passedHeld) {
              _walk = _walk!._with(passed: [...passed, at]);
            } else {
              _givenUp.add(at);
            }
          }
          if (_refused % refusedRun == 0 && await _refusalsStop()) return true;
          if (_gone) return true;
        case PinAnswer.replaced:
          _heard = true;
          _lastHeard = at;
          _refused = 0;
          _refusedMade.clear();
        case _:
          // No pin there to ask again about a refusal.
          _heard = true;
          _refused = 0;
          _refusedMade.clear();
      }
      await _pause();
      if (_gone) return true;
    }
    await _tell();
    return false;
  }

  /// Sets [at], which the server did not answer for, aside with its
  /// item's other sizes, so one that never answers is asked for once a
  /// [retryAfter] whatever sets the walk going meanwhile, and holds back
  /// neither the rest wanted nor the rest of the walk.
  void _setAside(PinCursor at) {
    _aside
      ..add(at)
      ..addAll(_wanted.where((other) => other.pid == at.pid));
    _wanted.removeAll(_aside);
    _restFirst = true;
    _backDue = false;
    _back?.cancel();
    _back = Timer(retryAfter, () {
      _back = null;
      _backDue = true;
      _go(named: true);
    });
  }

  /// Whether the walk has pinned covers it could ask about now.
  bool get _restToAsk =>
      _waiting == null && (_walk!.whole || _walk!.retried != null);

  /// The walk is over, bar pins named or wanted while it ended, and
  /// those set aside.
  void _over() {
    final named = _walk?.named ?? const <PinCursor>[];
    _walk = named.isEmpty && _wanted.isEmpty && _aside.isEmpty
        ? null
        : PinWalk(named: named, whole: false);
  }

  /// Back at the top, the walk asks every pin after any change so far:
  /// none is owed a second walk for it.
  void _fromTheTop() {
    if (_walk!.after != null) return;
    _moved = false;
    if (_walk!.again) _walk = _walk!._with(again: false);
  }

  Future<ArtworkPinRecord?> _pinAt(PinCursor at) async {
    for (final pin in await _pins.pinsFor(at.pid)) {
      if (pin.sizePx == at.sizePx) return pin;
    }
    return null;
  }

  /// Back to before the refusals in hand, with what stopping there has
  /// cost so far. The pins to make among them are wanted again, ahead of
  /// the rest wanted.
  void _backTo(({PinCursor? after, int passed}) place) {
    final walk = _walk!;
    // While the passed pins are asked again, only pins to make are among
    // the refusals in hand: the places of the passed have moved, and the
    // walk has not gone back.
    final rounds = walk.retried != null;
    final kept = rounds
        ? walk.passed
        : walk.passed.sublist(0, place.passed.clamp(0, walk.passed.length));
    _walk = PinWalk(
      after: place.after,
      again: walk.again,
      tries: _triedFrom == (after: place.after) ? _tries : 0,
      passed: [
        for (final at in kept)
          if (!_refusedMade.contains(at)) at,
      ],
      retried: walk.retried,
      named: walk.named,
      whole: walk.whole,
    );
    final wanted = [..._refusedMade, ..._wanted];
    _wanted
      ..clear()
      ..addAll(wanted);
    _givenUp.removeAll(_refusedMade);
    _refusedMade.clear();
    _refused = 0;
    if (!rounds) _fromTheTop();
  }

  /// Writes the place and waits to be let on.
  Future<void> _stop() async {
    _nudged = false;
    await _tell();
    if (_runEra != _era) return;
    _waitFor(retryAfter);
  }

  /// Writes the place and rests for [after], which the gate's word does
  /// not cut short: an open gate is no news to a server that refused.
  Future<void> _hold(Duration after) async {
    _nudged = false;
    // What asked to end a rest during the run asked before this one.
    _nudgeEnds = false;
    _waitFor(after, gateEnds: false);
    await _tell();
    // Pins wanted during the run, and pins set aside whose wait was up,
    // are asked for under it, as they are when they come during it.
    if (_backDue || _wanted.isNotEmpty) _nudged = true;
  }

  /// Whether the refusals in hand stop the walk. The last pin that
  /// answered is asked again: answering, the refusals are those covers';
  /// refused too, they are the server's, and the walk stalls.
  Future<bool> _refusalsStop() async {
    final from = _refusedFrom!;
    if (_triedFrom == (after: from.after) && _tries >= refusedTries) {
      return false;
    }
    if (_lastHeard case final probe?) {
      if (_open != true) {
        await _stop();
        return true;
      }
      await _pause();
      if (_gone) return true;
      final pin = await _pinAt(probe);
      if (_gone) return true;
      if (pin != null) {
        final answer = await _ask(pin);
        if (_gone) return true;
        switch (answer) {
          case PinAnswer.unanswered:
            _backTo(from);
            await _stop();
            return true;
          // Nothing asked proves nothing.
          case PinAnswer.refused || PinAnswer.skipped:
            break;
          case _:
            _heard = true;
            return false;
        }
      }
    }
    return _stall();
  }

  /// Takes the refusals in hand for the server's trouble: back to the
  /// first of them, to stop and ask again later. False once they have
  /// stopped it [refusedTries] times, and the walk goes on past them.
  Future<bool> _stall() async {
    final from = _refusedFrom!;
    _tries = _triedFrom == (after: from.after) ? _tries + 1 : 1;
    _triedFrom = (after: from.after);
    if (_tries >= refusedTries) return false;
    _backTo(from);
    await _stop();
    return true;
  }

  Future<void> _pause() {
    final pausing = _pausing = Completer<void>();
    _paced = Timer(pace, () {
      _paced = null;
      _pausing = null;
      pausing.complete();
    });
    return pausing.future;
  }

  Future<void> _tell() async {
    try {
      final walk = _walk;
      await _remember(walk == null || walk._idle ? null : walk);
    } catch (_) {
      // A place that cannot be kept costs a longer walk next time.
    }
  }
}

/// What holds a walk of the pinned covers back: the server out of
/// reach, the network the download setting does not allow, a download
/// in flight, or playback waiting on the network. Background work with
/// nobody waiting for it yields to all four.
class PinRefreshGate implements TransferGate {
  PinRefreshGate({
    required this._reachable,
    required this._playbackWaiting,
    required this._transfers,
    required this._downloading,
    required this._moved,
  });

  final bool Function() _reachable;
  final bool Function() _playbackWaiting;

  /// The gate downloads themselves wait at.
  final TransferGate Function() _transfers;
  final Future<bool> Function() _downloading;

  /// Streams that say one of the others may have moved.
  final List<Stream<void>> Function() _moved;

  @override
  Future<bool> isOpen() async {
    try {
      if (!_reachable() || _playbackWaiting()) return false;
      if (!await _transfers().isOpen()) return false;
      return !await _downloading();
    } catch (_) {
      // Read off providers that may be gone: shut is the safe answer.
      return false;
    }
  }

  @override
  Stream<bool> get changes {
    final heard = <StreamSubscription<Object?>>[];
    late final StreamController<bool> out;
    // Only the latest answer is said, as the wifi gate's is.
    var asked = 0;
    Future<void> say() async {
      final ask = ++asked;
      final open = await isOpen();
      if (ask == asked && !out.isClosed) out.add(open);
    }

    out = StreamController<bool>(
      onListen: () {
        try {
          for (final stream in <Stream<Object?>>[
            ..._moved(),
            _transfers().changes,
          ]) {
            heard.add(
              stream.listen((_) => unawaited(say()), onError: (Object _) {}),
            );
          }
        } catch (_) {
          // Nothing to hear from: the walk looks again on its own.
          unawaited(out.close());
        }
      },
      onCancel: () => Future.wait([for (final sub in heard) sub.cancel()]),
    );
    return out.stream.distinct();
  }
}

/// The moments a download starts or stops moving, out of a manager's
/// progress: the only ones that can shut the gate or open it. The rest
/// (a transfer reporting how far it has got) would have the gate asked
/// as often as the transfers report.
Stream<void> downloadTurns(Stream<DownloadProgress> progress) {
  final moving = <String>{};
  return progress.where((event) {
    if (event.complete || event.failed || event.stopped || event.paused) {
      moving.remove(event.pid);
      return true;
    }
    return moving.add(event.pid);
  });
}
