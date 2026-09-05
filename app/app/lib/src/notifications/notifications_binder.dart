import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../playlists/playlist_sync_controller.dart';
import '../playlists/playlists_controller.dart';
import '../sync/server_event_bus.dart';
import '../sync/sync_providers.dart';
import 'notifications_controller.dart';

/// Feeds the bell for as long as a session lasts.
///
/// A listener on the shared server-event bus rather than a walk of its
/// own: whichever transport this build has, the bell wants the same
/// events the account refresh and the mirror already read.
final notificationsBinderProvider = Provider.autoDispose<void>((ref) {
  final local = ref.read(localNotificationsProvider.notifier);

  // One refetch per burst, not one per row. Each inbox row is its own
  // marker with its own pid, so the delta coalesces none of them: a
  // podcast sweep filing forty episodes arrives as forty markers, and
  // a page read apiece would be forty requests for one answer.
  Timer? coalescing;
  ref.onDispose(() => coalescing?.cancel());

  // The bell row plus the one refetch the marker calls for: the sync
  // chip and sheet watch the binding, and nothing else would tell an
  // open playlist screen that a background run just moved it.
  final subscription = ref.watch(serverEventBusProvider).events.listen((event) {
    local.recordServerEvent(event);
    // The inbox is where the announcements land, so its own marker is
    // the one that refetches it. Invalidated rather than appended to:
    // the row carries a read stamp and an id this client has not seen.
    if (event.kind == 'notification') {
      coalescing?.cancel();
      coalescing = Timer(const Duration(milliseconds: 300), () {
        if (ref.mounted) ref.invalidate(notificationsProvider);
      });
    }
    final pid = event.pid;
    if (event.kind == 'playlist-synced' && pid != null) {
      ref.invalidate(playlistSyncProvider(pid));
      ref.invalidate(playlistDetailProvider(pid));
    }
  });
  // Nothing to clear on the way out: the controller empties the list
  // on an account change, and a disposal callback may not touch it.
  ref.onDispose(subscription.cancel);

  // This device's own transfers, which no server event describes. Null
  // on web, which has no local download manager.
  final downloads = ref.watch(downloadManagerProvider);
  if (downloads != null) {
    final transfers = downloads.progress.listen((update) {
      if (update.complete) local.recordDownloadCompleted();
    });
    ref.onDispose(transfers.cancel);
  }
});
