import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../playlists/playlist_sync_controller.dart';
import '../playlists/playlists_controller.dart';
import '../providers.dart';
import '../sync/sync_providers.dart';
import 'notifications_controller.dart';

/// Pulls the caller's server-state changes for a client that does not
/// mirror them.
///
/// The web build has no sync engine and no cursor, and an invalidation
/// frame carries no detail, so the bell walks `/sync/server` itself.
/// The first call mints a cursor and reports nothing: a session that
/// just started has observed nothing yet, and replaying last week as
/// "just now" would be a lie with a badge on it.
class UserEventPuller {
  UserEventPuller({required this.repository, required this.onEvent});

  final WaxDeckRepository repository;
  final void Function(ServerSyncEvent event) onEvent;

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
    try {
      var since = _since;
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
      // Nothing here mirrors anything, so re-minting is the whole
      // recovery from a cursor the server can no longer serve.
      if (error.code == 'sync-reset') _since = null;
    }
  }
}

/// Feeds the bell for as long as a session lasts. Native's engine
/// already reads this stream for its mirror and publishes what it read;
/// web has no engine and walks it off the same invalidation hint.
final notificationsBinderProvider = Provider.autoDispose<void>((ref) {
  final notifications = ref.read(notificationsProvider.notifier);

  // The bell row plus the one refetch the marker calls for: the sync
  // chip and sheet watch the binding, and nothing else would tell an
  // open playlist screen that a background run just moved it.
  void onServerEvent(ServerSyncEvent event) {
    notifications.recordServerEvent(event);
    final pid = event.pid;
    if (event.kind == 'playlist-synced' && pid != null) {
      ref.invalidate(playlistSyncProvider(pid));
      ref.invalidate(playlistDetailProvider(pid));
    }
  }

  // This device's own transfers, which no server event describes. Null
  // on web, which has no local download manager.
  final downloads = ref.watch(downloadManagerProvider);
  if (downloads != null) {
    final transfers = downloads.progress.listen((update) {
      if (update.complete) notifications.recordDownloadCompleted();
    });
    ref.onDispose(transfers.cancel);
  }

  final engine = ref.watch(syncEngineProvider);
  if (engine != null) {
    final subscription = engine.serverEvents.listen(onServerEvent);
    // Nothing to clear on the way out: the controller empties the list
    // on an account change, and a disposal callback may not touch it.
    ref.onDispose(subscription.cancel);
    return;
  }
  if (!kIsWeb) return;
  final puller = UserEventPuller(
    repository: ref.watch(repositoryProvider),
    onEvent: onServerEvent,
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
});

/// Bumped every time the user topic reports a change. A counter rather
/// than a callback, so the binder watches it as provider state and a
/// test can drive it without a socket.
class UserStreamTick extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

final userStreamTickProvider = NotifierProvider<UserStreamTick, int>(
  UserStreamTick.new,
);
