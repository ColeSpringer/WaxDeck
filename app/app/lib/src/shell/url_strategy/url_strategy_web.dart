import 'package:flutter/foundation.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

/// Puts WaxDeck's locations in the path rather than the fragment.
///
/// The fragment never reaches the server, so under the default strategy
/// every location was one origin as far as a proxy, a crawler, or a
/// share preview was concerned. The server's SPA fallback answers a
/// document navigation for any unknown path with the shell
/// (`server/internal/web`), which is the whole requirement; the hash
/// links minted before this flip are rewritten by the shim in
/// `web/index.html` before the engine boots.
void useWaxUrlStrategy() {
  setUrlStrategy(_strategy = _WaxUrlStrategy());
}

_WaxUrlStrategy? _strategy;

final _hearing = <bool Function()>[];

int? _shown;

int? _top;

/// The last browser move a listener took, to hand the engine later.
VoidCallback? _taken;

/// Whether the engine is numbering an entry it is being handed.
var _numbering = false;

/// The number of the entry the engine holds the app to be on: the one it
/// last wrote, or the last browser move it was handed. Null until it has
/// done either.
int? get shownEntry => _shown;

/// The number of the newest entry the engine has written: each one up to
/// it is the app's, as a push drops those ahead. Null until it has pushed
/// one, unless one kept from before a reload was given (see
/// [seedTopEntry]).
int? get topEntry => _top;

/// Starts [topEntry] at [top], the newest entry kept from before a reload,
/// as the document loads, before the engine writes.
void seedTopEntry(int top) => _top = top;

/// Told the number of the newest entry each time it moves, so it can be
/// kept across a reload.
void Function(int top)? topEntryMoved;

/// The location of the entry the browser is on, as the engine reads it.
String get entryLocation => _strategy?.getPath() ?? '/';

/// The router's state for the entry the browser is on, which the engine
/// keeps beside the entry's number.
Object? get entryState => switch (_strategy?.getState()) {
  {'state': final Object? state} => state,
  _ => null,
};

/// Calls [onMove] at each browser back or forward, before the engine
/// hands the entry it moved to on to the router; where [onMove] answers
/// true, the engine is not handed it. The function returned stops it.
/// Heard only once [useWaxUrlStrategy] has run.
VoidCallback hearBrowserMoves(bool Function() onMove) {
  _hearing.add(onMove);
  return () => _hearing.remove(onMove);
}

/// Hands the engine the last browser move a listener of
/// [hearBrowserMoves] took, where nothing has moved or been written
/// since, as if it had not been taken; false where there is none.
bool handOnTaken() {
  final taken = _taken;
  _taken = null;
  taken?.call();
  return taken != null;
}

/// Holds every entry the engine writes from here on, until
/// [releaseWrites] or [dropWrites] (see [EngineWrites.hold]).
void holdWrites() => _strategy?._writes.hold();

/// Writes what [holdWrites] held (see [EngineWrites.release]).
bool releaseWrites({bool past = false, bool over = false}) =>
    _strategy?._writes.release(past: past, over: over) ?? false;

/// Forgets what [holdWrites] held (see [EngineWrites.drop]).
void dropWrites() => _strategy?._writes.drop();

/// Puts back everything this file keeps as a document starts, for a test
/// that changes it.
@visibleForTesting
void resetUrlStrategyState() {
  _strategy = null;
  _hearing.clear();
  _shown = null;
  _top = null;
  _taken = null;
  _numbering = false;
  topEntryMoved = null;
}

/// An entry the engine writes: its state, title and location, pushed or
/// written over the one the browser is on.
typedef EngineWrite = ({Object? state, String title, String url, bool pushed});

/// The entries the engine writes, through to the browser, or held while
/// the browser is not on the entry the engine writes to.
@visibleForTesting
class EngineWrites {
  EngineWrites(this._write);

  /// Writes one to the browser.
  final void Function(EngineWrite write) _write;

  List<EngineWrite>? _held;

  /// Writes [write], or holds it.
  void write(EngineWrite write) {
    if (_held case final held?) {
      held.add(write);
    } else {
      _write(write);
    }
  }

  /// Holds every write from here on, until [release] or [drop]: the
  /// browser is away from the entry the engine writes to, on a step the
  /// app asked of it or on an entry a move the app took hid from it.
  void hold() => _held ??= <EngineWrite>[];

  /// Writes what was held, in order, now the browser is on the engine's
  /// entry again; with [past], the first is pushed past the entry the
  /// browser is on instead, which never came back to the engine's; with
  /// [over], it is written over that entry, which shows nothing to keep.
  /// False, having written nothing, where nothing was held.
  bool release({bool past = false, bool over = false}) {
    assert(!(past && over), 'the first is pushed or written over, not both');
    final held = _held;
    _held = null;
    if (held == null || held.isEmpty) return false;
    for (final (i, write) in held.indexed) {
      _write(
        (past || over) && i == 0
            ? (
                state: write.state,
                title: write.title,
                url: write.url,
                pushed: past,
              )
            : write,
      );
    }
    return true;
  }

  /// Forgets what was held: the browser moved elsewhere, and the router
  /// follows it there.
  void drop() => _held = null;
}

class _WaxUrlStrategy extends PathUrlStrategy {
  late final _writes = EngineWrites((write) {
    final state = numberedFrom(getState(), write.state, pushed: write.pushed);
    if (write.pushed) {
      super.pushState(state, write.title, write.url);
    } else {
      super.replaceState(state, write.title, write.url);
    }
    entryWritten(state, pushed: write.pushed);
  });

  late final _engine = EngineMoveHandlers(
    (fn) => super.addPopStateListener(fn),
  );

  // The engine hears a browser move through this, so the app is told
  // here, in the same call and ahead of the engine. A listener of the
  // app's own on `window` would come too late: listeners there run in
  // the order they were added, and the engine adds its own first.
  @override
  VoidCallback addPopStateListener(void Function(Object? state) fn) =>
      _engine.add(fn);

  // Every entry the engine makes or renumbers goes through these.
  @override
  void pushState(Object? state, String title, String url) =>
      _writes.write((state: state, title: title, url: url, pushed: true));

  @override
  void replaceState(Object? state, String title, String url) =>
      _writes.write((state: state, title: title, url: url, pushed: false));
}

/// [state], an entry the engine writes, numbered from the entry the
/// browser is on, whose state is [on]: one up where [pushed], the same
/// in place. The engine numbers it from the entry it holds the app to be
/// on, which is not where a write held and released elsewhere lands, and
/// two entries' numbers are how far apart a step between them goes. As
/// the engine numbered it where [on] has no number of its own (an entry
/// the browser made itself, which the engine numbers as it hears of it).
@visibleForTesting
Object? numberedFrom(Object? on, Object? state, {required bool pushed}) {
  if (on is! Map || on['serialCount'] is! num) return state;
  if (state is! Map || state['serialCount'] is! num) return state;
  final count = (on['serialCount'] as num).toInt() + (pushed ? 1 : 0);
  return <Object?, Object?>{...state, 'serialCount': count.toDouble()};
}

/// Notes an entry the engine wrote with [state]: pushed, or written over
/// the one shown.
@visibleForTesting
void entryWritten(Object? state, {required bool pushed}) {
  _taken = null;
  final serial = _shown = _serialOf(state);
  final top = _top;
  if (pushed || _numbering || (top != null && serial > top)) {
    _top = serial;
    if (serial != top) topEntryMoved?.call(serial);
  }
}

/// The handlers the engine registers for a browser move through the
/// strategy: its history's, and the one its `go` adds while it waits for
/// the move it made. All are heard through one listener of the browser's,
/// so the app's listeners run once per move, ahead of them all, and a move
/// they take reaches none of them.
@visibleForTesting
class EngineMoveHandlers {
  EngineMoveHandlers(this._listen);

  /// Registers one listener of the browser's moves, and answers its
  /// remover.
  final VoidCallback Function(void Function(Object? state) fn) _listen;

  final _handlers = <void Function(Object? state)>[];
  VoidCallback? _stop;

  /// Adds [fn], and answers its remover.
  VoidCallback add(void Function(Object? state) fn) {
    // A closure of its own, so each add has a remover of its own.
    void handler(Object? state) => fn(state);
    _handlers.add(handler);
    _stop ??= _listen(heardFirst(_moved));
    return () {
      if (!_handlers.remove(handler) || _handlers.isNotEmpty) return;
      _stop?.call();
      _stop = null;
    };
  }

  void _moved(Object? state) {
    for (final handler in List.of(_handlers)) {
      handler(state);
    }
  }
}

/// [fn], the engine's handler for a browser move, with each listener of
/// [hearBrowserMoves] called ahead of it in the same call, and not called
/// for a move one of them took. One that throws still leaves the engine
/// its move, or the router would hear no browser back or forward again.
@visibleForTesting
void Function(Object? state) heardFirst(void Function(Object? state) fn) =>
    (state) {
      _taken = null;
      var taken = false;
      try {
        for (final onMove in List.of(_hearing)) {
          if (onMove()) taken = true;
        }
      } finally {
        if (taken) {
          _taken = () => _handOn(fn, state);
        } else {
          _handOn(fn, state);
        }
      }
    };

void _handOn(void Function(Object? state) fn, Object? state) {
  _shown = _serialOf(state);
  // An entry the browser made itself, which dropped any ahead of it: the
  // engine numbers it as it is handed on.
  _numbering = state is! Map || state['serialCount'] == null;
  try {
    fn(state);
  } finally {
    _numbering = false;
  }
}

/// The number the engine wrote into an entry's state, 0 where it wrote
/// none; it then writes the entry again with one.
int _serialOf(Object? state) => switch (state) {
  {'serialCount': final num count} => count.toInt(),
  _ => 0,
};
