import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import '../sync/sync_providers.dart';
import 'notifications_controller.dart';

/// Pulls the caller's server-state changes for a client that does not
/// mirror them.
///
/// The web build has no sync engine and no cursor of its own: it reacts
/// to user invalidations by refetching whatever is on screen, and an
/// invalidation frame carries no detail at all. So the bell needs its own
/// walk of `/sync/server`, which is what this is.
///
/// The first call mints a cursor and reports nothing, which is the point:
/// a session that has just started has not observed anything yet, and
/// replaying whatever the account did on another device last week as
/// "just now" would be a lie with a badge on it.
class UserEventPuller {
  UserEventPuller({required this.repository, required this.onEvent});

  final WaxDeckRepository repository;
  final void Function(ServerSyncEvent event) onEvent;

  String? _since;
  bool _running = false;
  bool _stopped = false;

  void stop() => _stopped = true;

  /// Reads everything after the held cursor. Re-entrant calls are
  /// dropped rather than queued: the hint that prompted them says the
  /// stream moved, and a walk already in flight will see it.
  Future<void> pull() async {
    if (_running || _stopped) return;
    _running = true;
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
        // Advanced per page rather than once at the end: a walk cut
        // short - a page that throws, a session that stopped - would
        // otherwise leave the cursor where it started and re-report
        // every page it had already handed out. The rows deduplicate on
        // their kind, so the cost of getting this wrong is small, but
        // keeping the progress costs nothing.
        since = page.nextSince;
        _since = since;
        if (!page.more) break;
      }
    } on WaxDeckApiException catch (error) {
      // A cursor the server can no longer serve contiguously answers
      // sync-reset. Nothing here mirrors anything, so re-minting is the
      // whole recovery: the gap is events this session did not see, and
      // the bell already promises only what it saw.
      if (error.code == 'sync-reset') _since = null;
    } finally {
      _running = false;
    }
  }
}

/// Feeds the bell for as long as a session lasts.
///
/// Both transports end at the same recorder. Native has an engine that
/// already reads this stream to keep its mirror current, so it publishes
/// what it read; web has no engine and walks the stream itself off the
/// same invalidation hint the rest of the client refetches on.
final notificationsBinderProvider = Provider.autoDispose<void>((ref) {
  final notifications = ref.read(notificationsProvider.notifier);

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
    final subscription = engine.serverEvents.listen(
      notifications.recordServerEvent,
    );
    // Nothing to clear on the way out: the list empties when the account
    // changes, which the controller watches for itself. A disposal
    // callback that modified another provider would assert in debug and
    // be swallowed in release.
    ref.onDispose(subscription.cancel);
    return;
  }
  if (!kIsWeb) return;
  final puller = UserEventPuller(
    repository: ref.watch(repositoryProvider),
    onEvent: notifications.recordServerEvent,
  );
  // Minted immediately rather than on the first hint, so the first
  // change after a launch is reported rather than swallowed by the
  // cursor mint it would otherwise have paid for.
  unawaited(puller.pull());
  final listener = ref.listen(userStreamTickProvider, (_, _) {
    unawaited(puller.pull());
  });
  ref.onDispose(() {
    listener.close();
    puller.stop();
  });
});

/// Bumped every time the user topic reports a change.
///
/// A counter rather than a callback, so the binder can watch it the way
/// every other consumer of the live channel watches provider state, and
/// so a test can drive it without a socket.
class UserStreamTick extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

final userStreamTickProvider = NotifierProvider<UserStreamTick, int>(
  UserStreamTick.new,
);
