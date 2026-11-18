import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../url_strategy/url_strategy_web.dart';
import 'browser_history_port.dart';

export 'browser_history_port.dart';

BrowserHistoryPort? createBrowserHistory() {
  _keepNewest();
  return BrowserSessionHistory(before: _entriesBefore);
}

/// How the app's document loaded, as its Navigation Timing entry says.
final String _load = switch (web.window.performance
    .getEntriesByType('navigation')
    .toDart
    .firstOrNull) {
  final entry? => (entry as web.PerformanceNavigationTiming).type,
  null => '',
};

/// How many of the tab's entries lie before the app's first: counted
/// once, as the app starts, before the engine has pushed an entry, and
/// kept for the tab across its reloads and returns.
final int _entriesBefore = _countEntriesBefore();

const _entriesBeforeKey = 'waxdeck.entriesBefore';

const _newestKey = 'waxdeck.newestEntry';

var _newestKept = false;

/// Keeps the app's newest entry for the tab as the engine moves it, and
/// takes it up again after a reload (see [newestAcrossLoad]): once, as
/// the app starts, before the engine writes.
void _keepNewest() {
  if (_newestKept) return;
  _newestKept = true;
  int? kept;
  try {
    kept = int.tryParse(web.window.sessionStorage.getItem(_newestKey) ?? '');
  } on Object {
    // Storage the browser refuses reads as nothing kept.
  }
  if (newestAcrossLoad(_load, kept: kept) case final newest?) {
    seedTopEntry(newest);
  } else {
    try {
      web.window.sessionStorage.removeItem(_newestKey);
    } on Object {
      // Nothing kept to drop.
    }
  }
  topEntryMoved = (top) {
    try {
      web.window.sessionStorage.setItem(_newestKey, '$top');
    } on Object {
      // Not kept, and a reload knows nothing of it.
    }
  };
}

int _countEntriesBefore() {
  final load = _load;
  int? kept;
  try {
    kept = int.tryParse(
      web.window.sessionStorage.getItem(_entriesBeforeKey) ?? '',
    );
  } on Object {
    // Storage the browser refuses reads as nothing kept.
  }
  final before = entriesBeforeApp(
    load,
    length: web.window.history.length,
    kept: kept,
  );
  try {
    web.window.sessionStorage.setItem(_entriesBeforeKey, '$before');
  } on Object {
    // Nor is it kept then, and a reload reads nothing.
  }
  return before;
}

/// The tab's session history, through `window.history`, and its moves
/// through the app's url strategy.
class BrowserSessionHistory implements BrowserHistoryPort {
  const BrowserSessionHistory({required this.before});

  /// How many of the tab's entries lie before the app's first.
  final int before;

  @override
  bool get canStepBack => position > 0;

  @override
  bool get canStepForward {
    final top = topEntry;
    return top != null && position < top;
  }

  /// From the count taken as the app loaded, so neither the app's own
  /// entries nor those of a page ahead of them read as a page before it
  /// (see [entriesBeforeApp]).
  @override
  bool get canLeave => before > 0;

  @override
  bool get newestKnown => topEntry != null || _load == 'navigate';

  /// Each entry's state carries its number: 0 for the one the app opened
  /// on, and one up from the entry it was pushed past for every other
  /// (see [numberedFrom]).
  @override
  int get position {
    final state = web.window.history.state;
    if (state == null || !state.isA<JSObject>()) return 0;
    final count = (state as JSObject).getProperty<JSAny?>('serialCount'.toJS);
    if (count == null || !count.isA<JSNumber>()) return 0;
    return (count as JSNumber).toDartDouble.toInt();
  }

  /// As the url strategy saw the engine write or hear it; the entry shown
  /// before the engine has done either, as after a reload.
  @override
  int get shown => shownEntry ?? position;

  @override
  String get location => entryLocation;

  @override
  List<String> get pushes => pushedLocations(entryState);

  @override
  List<String> get pushKeys => pushedKeys(entryState);

  @override
  void back() => web.window.history.back();

  @override
  void forward(int entries) => web.window.history.go(entries);

  @override
  bool handOn() => handOnTaken();

  @override
  void hold() => holdWrites();

  @override
  bool release({bool past = false, bool over = false}) =>
      releaseWrites(past: past, over: over);

  @override
  void drop() => dropWrites();

  /// Heard through the app's url strategy, which the engine hears the
  /// browser through.
  @override
  VoidCallback listen(bool Function() onMove) => hearBrowserMoves(onMove);
}
