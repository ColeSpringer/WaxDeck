import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import 'sync_providers.dart';

/// Pulls the caller's server-state changes for a client that does not
/// mirror them.
///
/// The web build has no sync engine and no cursor, and an invalidation
/// frame carries no detail, so the bus walks `/sync/server` itself.
/// The first call mints a cursor and reports nothing: a session that
/// just started has observed nothing yet, and replaying last week as
/// "just now" would be a lie with a badge on it.
class UserEventPuller {
  UserEventPuller({
    required this.repository,
    required this.onEvent,
    this.onReset,
  });

  final WaxDeckRepository repository;
  final void Function(ServerSyncEvent event) onEvent;

  /// Called when the walk lost its place: the events between the old
  /// cursor and the fresh one are gone.
  final void Function()? onReset;

  String? _since;
  bool _running = false;
  bool _pending = false;
  bool _stopped = false;

  void stop() => _stopped = true;

  /// Reads everything after the held cursor. A hint arriving mid-walk is
  /// remembered rather than dropped: the first call only mints the
  /// cursor, so a change landing during boot had nothing to recover it.
  Future<void> pull() async {
    if (_stopped) return;
    if (_running) {
      _pending = true;
      return;
    }
    _running = true;
    try {
      do {
        _pending = false;
        await _walk();
      } while (_pending && !_stopped);
    } finally {
      _running = false;
    }
  }

  Future<void> _walk() async {
    var since = _since;
    try {
      if (since == null) {
        _since = (await repository.syncServer()).nextSince;
        return;
      }
      while (true) {
        final page = await repository.syncServer(since: since);
        if (_stopped) return;
        for (final event in page.events) {
          onEvent(event);
        }
        // Advanced per page, so a walk cut short does not re-report the
        // pages it already handed out.
        since = page.nextSince;
        _since = since;
        if (!page.more) break;
      }
    } on WaxDeckApiException catch (error) {
      // Nothing here mirrors anything, so a fresh cursor is the whole
      // recovery from one the server can no longer serve. It is minted
      // at once, or the next change would go unreported too, and what
      // fell between the two is told as lost.
      if (error.code == 'sync-reset' && since != null) {
        _since = null;
        _pending = true;
        onReset?.call();
      }
    }
  }
}

/// Every server-state change this session observed, from whichever
/// transport this build has.
///
/// One walk of the stream, many consumers: the bell, the account
/// refresh and the playlist-sync refetch all want the same events, and
/// a second cursor over the same feed would report a different set to
/// each of them. Broadcast and not replayed, because what it carries is
/// news rather than state: a listener attached later hears what happens
/// next, which is what a session-scoped surface means.
class ServerEventBus {
  final _events = StreamController<ServerSyncEvent>.broadcast();
  final _resets = StreamController<void>.broadcast();

  Stream<ServerSyncEvent> get events => _events.stream;

  /// The walk lost its place, so events went unreported: a consumer
  /// refreshes everything it holds.
  Stream<void> get resets => _resets.stream;

  void add(ServerSyncEvent event) {
    if (_events.isClosed) return;
    _events.add(event);
  }

  void reset() {
    if (_resets.isClosed) return;
    _resets.add(null);
  }

  Future<void> dispose() async {
    await _events.close();
    await _resets.close();
  }
}

/// The bus, wired to whichever transport this build runs.
///
/// Native reads the engine's own published stream, which the mirror is
/// already walking; web mints a cursor and walks it off the socket's
/// invalidation hints. Mounted for as long as the session is, so a
/// consumer that appears late (a screen, a binder) joins a walk already
/// in progress rather than starting one of its own.
final serverEventBusProvider = Provider.autoDispose<ServerEventBus>((ref) {
  final bus = ServerEventBus();
  ref.onDispose(bus.dispose);

  final engine = ref.watch(syncEngineProvider);
  if (engine != null) {
    final subscription = engine.serverEvents.listen(bus.add);
    ref.onDispose(subscription.cancel);
    return bus;
  }
  if (!kIsWeb) return bus;
  final puller = UserEventPuller(
    repository: ref.watch(repositoryProvider),
    onEvent: bus.add,
    onReset: bus.reset,
  );
  // Minted immediately, so the first change after a launch is reported
  // rather than swallowed by the mint it would have paid for.
  unawaited(puller.pull());
  final listener = ref.listen(userStreamTickProvider, (_, _) {
    unawaited(puller.pull());
  });
  ref.onDispose(() {
    listener.close();
    puller.stop();
  });
  return bus;
});

/// Bumped every time the user topic reports a change. A counter rather
/// than a callback, so the bus watches it as provider state and a test
/// can drive it without a socket.
class UserStreamTick extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

final userStreamTickProvider = NotifierProvider<UserStreamTick, int>(
  UserStreamTick.new,
);
