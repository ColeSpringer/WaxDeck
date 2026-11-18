import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/shell/browser_history/browser_history_port.dart';

/// An entry of the tab: its location, the router's state for it, and the
/// number the engine keeps beside that state.
typedef FakeEntry = ({String location, Object? state, int serial});

/// An entry the engine writes: pushed past the one the browser is on, or
/// written over it.
typedef _Write = ({String location, Object? state, bool pushed});

/// A browser tab's session history for a whole-app test: the entries the
/// router reports, and the buttons that walk them.
///
/// It answers the navigation channel the way the web engine does, keeping
/// an entry per report and replacing one only when the report says so,
/// and numbering each as the app's url strategy has it numbered: from the
/// entry the browser is on as it is written, one up for a push and the
/// same for a write in place, so the numbers of two entries are as far
/// apart as the entries. A report waits its turn in the engine's line, so
/// its entry is written a moment after the report was made, not within
/// it. A move is the engine's too:
/// later, the app's listener first, then, unless the listener took it,
/// the entry handed to the router as `pushRouteInformation`; a move taken
/// is never heard by the engine, which goes on writing as if the browser
/// had not moved, except while the app holds its writes (as the app's url
/// strategy does). A step back from the first entry leaves the tab's
/// entries of the app where a page of another document lies before them,
/// and otherwise goes nowhere, as one forward from the last does. Past
/// [kept] entries, those pages counted, the oldest are dropped, and a
/// step back from the oldest kept goes nowhere either. The app's document
/// loads by a fresh navigation in a tab holding [before] such pages, and
/// again by a [reload] on the entry the tab is on.
class FakeBrowser implements BrowserHistoryPort {
  /// A fresh navigation of the tab to the app, past [before] pages:
  /// answers the navigation channel until the test ends, on the entry the
  /// app's document loads on, which the engine numbers 0 and the router's
  /// first report writes over. Made before the app is pumped.
  FakeBrowser({this._before = 1}) {
    entries.add((
      location: TestWidgetsFlutterBinding
          .instance
          .platformDispatcher
          .defaultRouteName,
      state: null,
      serial: 0,
    ));
    _loaded('navigate');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.navigation, _reported);
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.navigation, null),
    );
  }

  final entries = <FakeEntry>[];
  var index = 0;

  /// Steps back the app asked for.
  var backs = 0;

  /// Steps forward the app asked for.
  var forwards = 0;

  /// What [canStepBack] answers in place of the entries' own count.
  bool? stepsBack;

  /// Whether a step the app asks for lands only after a frame has drawn
  /// the entry it leaves, as a browser's may.
  var framed = false;

  /// How long after it is asked a step the app asks for lands, where it
  /// is not at once.
  Duration? latency;

  /// How many entries the tab keeps, the pages before the app's counted:
  /// a browser drops the oldest past its own bound (Chrome's is 50) and
  /// the engine numbers on, so the oldest it keeps is not numbered 0, and
  /// nothing lies behind it.
  var kept = 50;

  /// Whether a step went back from the app's first entry, which in a
  /// browser leaves the app for the page before it.
  var left = false;

  /// How many pages of other documents the tab holds before the app's
  /// first entry, which it drops first past [kept].
  int _before;

  /// What the tab keeps for the app's documents across their loads, as
  /// its session storage does.
  final _session = <String, int>{};

  /// How many entries the app's document counted before its first as it
  /// last loaded.
  var _entriesBefore = 0;

  bool Function()? _onMove;

  /// The number of the entry the router was last told of, by a report or
  /// a move; none before either, as the web half has none after a load.
  int? _shown;

  /// Whether the listener took the last move, and nothing moved since.
  var _taken = false;

  /// What the engine wrote while [hold] held it, in order.
  List<_Write>? _held;

  @override
  String get location => entries[index].location;

  /// Read from the state the router reported for the entry, which the
  /// engine keeps in it.
  @override
  List<String> get pushes => pushesAt(index);

  /// The locations pushed in the entry at [at], as [pushes] reads them.
  List<String> pushesAt(int at) => pushedLocations(entries[at].state);

  /// Read from the entry's state, as the web half does.
  @override
  List<String> get pushKeys => pushedKeys(entries[index].state);

  /// Read off the entry's number, as the web half does: one the tab
  /// dropped the entries behind still says there are some.
  @override
  bool get canStepBack => stepsBack ?? position > 0;

  /// Answered as the web half answers it: from the newest entry the
  /// engine pushed since the document loaded, none after a reload until it
  /// pushes again, whatever lies ahead in the tab.
  @override
  bool get canStepForward {
    final top = _top;
    return top != null && position < top;
  }

  /// The number of the newest entry the engine has written since the
  /// document loaded, as the web half keeps it.
  int? _top;

  /// Answered as the web half answers it, from the count the app's
  /// document took as it loaded, which entries the tab dropped since do
  /// not change.
  @override
  bool get canLeave => _entriesBefore > 0;

  /// Answered as the web half answers it: after a fresh navigation, once
  /// the engine pushed, or with the newest kept across a reload.
  @override
  bool get newestKnown => _top != null || _load == 'navigate';

  /// How the app's document last loaded.
  var _load = 'navigate';

  /// Read from the entry's state, as the web half does.
  @override
  int get position => entries[index].serial;

  @override
  int get shown => _shown ?? position;

  @override
  void back() {
    backs++;
    _asked(-1);
  }

  @override
  void forward(int entries) {
    if (entries < 0) {
      backs++;
    } else {
      forwards++;
    }
    _asked(entries);
  }

  @override
  bool handOn() {
    if (!_taken) return false;
    _taken = false;
    _hand(index);
    return true;
  }

  @override
  void hold() => _held ??= <_Write>[];

  @override
  bool release({bool past = false, bool over = false}) {
    final held = _held;
    _held = null;
    if (held == null || held.isEmpty) return false;
    for (final (i, write) in held.indexed) {
      final first = i == 0;
      _write((
        location: write.location,
        state: write.state,
        pushed: first && over ? false : write.pushed || (past && first),
      ));
    }
    return true;
  }

  @override
  void drop() => _held = null;

  @override
  VoidCallback listen(bool Function() onMove) {
    _onMove = onMove;
    return () {
      if (identical(_onMove, onMove)) _onMove = null;
    };
  }

  /// The tab reloads the app's document on the entry it is on: the
  /// entries stay, numbered as they were, and the engine starts over,
  /// having written and heard nothing; the newest entry is taken up from
  /// the tab's session storage, as the web half keeps it. With
  /// [returning], the document loads again by a return to it from
  /// another, after which the web half knows no newest. Before the app is
  /// pumped again there.
  void reload({bool returning = false}) {
    _shown = null;
    _taken = false;
    _held = null;
    _loaded(returning ? 'back_forward' : 'reload');
    _top = newestAcrossLoad(_load, kept: _session['newest']);
    if (_top == null) _session.remove('newest');
  }

  /// The app's document loading by [load], as its Navigation Timing entry
  /// says, counting the entries before its first as the web half does.
  void _loaded(String load) {
    _load = load;
    _entriesBefore = entriesBeforeApp(
      load,
      length: _before + entries.length,
      kept: _session['entriesBefore'],
    );
    _session['entriesBefore'] = _entriesBefore;
  }

  /// The browser's own back button.
  void goBack() => _move(-1);

  /// The browser's own forward button.
  void goForward() => _move(1);

  /// The list a held back or forward button opens, which jumps [by]
  /// entries at once.
  void jump(int by) => _move(by);

  void _asked(int by) {
    final wait = latency;
    if (wait != null) {
      Timer(wait, () => _move(by));
      return;
    }
    if (!framed) {
      _move(by);
      return;
    }
    // A frame after it too, so a settling test pumps on to the move.
    final binding = WidgetsBinding.instance;
    binding
      ..addPostFrameCallback((_) {
        _move(by);
        binding.scheduleFrame();
      })
      ..scheduleFrame();
  }

  /// The end of the engine's line of navigation messages: it handles one
  /// at a time, each once those sent before it are done.
  Future<void> _endOfTheLine = Future<void>.value();

  /// Takes [call] in its turn, as the engine's window does.
  Future<Object?> _reported(MethodCall call) async {
    final ahead = _endOfTheLine;
    final done = Completer<void>();
    _endOfTheLine = done.future;
    await ahead;
    try {
      await _handled(call);
    } finally {
      done.complete();
    }
    return null;
  }

  Future<void> _handled(MethodCall call) async {
    if (call.method != 'routeInformationUpdated') {
      // Choosing the kind of history is a message of its own.
      await Future<void>.value();
      return;
    }
    final arguments = call.arguments as Map<Object?, Object?>;
    final write = (
      location: arguments['uri']! as String,
      state: arguments['state'],
      pushed: arguments['replace'] != true,
    );
    if (_held case final held?) {
      held.add(write);
    } else {
      _write(write);
    }
  }

  /// Writes [write] over the entry the browser is on, or pushed past it,
  /// dropping every entry ahead, numbered from that entry.
  void _write(_Write write) {
    final pushed = write.pushed;
    final entry = (
      location: write.location,
      state: write.state,
      serial: entries[index].serial + (pushed ? 1 : 0),
    );
    if (pushed) {
      entries
        ..removeRange(index + 1, entries.length)
        ..add(entry);
      index = entries.length - 1;
      var over = _before + entries.length - kept;
      if (over > 0) {
        final pages = math.min(over, _before);
        _before -= pages;
        over -= pages;
        entries.removeRange(0, over);
        index -= over;
      }
    } else {
      entries[index] = entry;
    }
    _shown = entry.serial;
    final top = _top;
    if (pushed || (top != null && entry.serial > top)) {
      _top = entry.serial;
      _session['newest'] = entry.serial;
    }
    _taken = false;
  }

  void _move(int by) {
    Timer.run(() {
      final to = index + by;
      if (to < 0 && _before > 0) {
        // The app's document goes, and what it took with it.
        left = true;
        _taken = false;
      }
      if (to < 0 || to >= entries.length) return;
      index = to;
      // A move the app takes itself is never handed to the router.
      _taken = _onMove?.call() ?? false;
      if (!_taken) _hand(to);
    });
  }

  /// Hands the router the entry at [to], as the engine does a move it
  /// hears of.
  void _hand(int to) {
    final entry = entries[to];
    _shown = entry.serial;
    unawaited(
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            SystemChannels.navigation.name,
            SystemChannels.navigation.codec.encodeMethodCall(
              MethodCall('pushRouteInformation', <String, Object?>{
                'location': entry.location,
                'state': entry.state,
              }),
            ),
            (_) {},
          ),
    );
  }
}
