import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import '../artwork/artwork_providers.dart';
import '../connect/connect_providers.dart';
import '../library/library_controller.dart';
import '../metadata/metadata_controller.dart';
import '../player/entity_play_state_controller.dart';
import '../player/play_state_controller.dart';
import '../playlists/playlists_controller.dart';
import '../podcasts/podcast_shelves.dart';
import '../podcasts/podcasts_controller.dart';
import '../providers.dart';
import '../review/review_controller.dart';
import '../settings/prefs_controller.dart';
import '../shell/lifecycle_banners.dart';
import '../tools/tasks_screen.dart';
import '../uploads/uploads_controller.dart';
import 'live_invalidations.dart';
import 'sync_providers.dart';

/// Binds the sync machinery to the authenticated subtree: watched by the
/// signed-in UI, disposed on sign-out. Native starts the engine and
/// relays its change streams into provider invalidations; web opens the
/// invalidation listener straight off the event channel.
///
/// This lives apart from the declarations in `sync_providers.dart`
/// because the fan-out below reaches up into every feature controller,
/// two of which import the declarations back down. Keeping the binder
/// here leaves that file importing nothing upward, and the one screen
/// that watches the binder is the only file that reads this one.
final syncBinderProvider = Provider.autoDispose<void>((ref) {
  void invalidateCatalog() {
    // Covers appear as part of the catalog changing — a scan reading
    // embedded art, enrichment landing, another device writing one —
    // and the store has been remembering which ones answered 404 so it
    // can draw the monogram without asking again. Those answers are
    // exactly what a catalog change can falsify, and this is the only
    // signal that sees it: the cover editors call `evict`, and nothing
    // else does.
    ref.read(artworkStoreProvider).forgetAbsences();
    ref.invalidate(libraryControllerProvider);
    ref.invalidate(continueListeningProvider);
    // Shows and episodes are catalog entities too: a server-side fetch
    // flipping an episode to downloaded must reach an open show screen.
    ref.invalidate(podcastDetailProvider);
    ref.invalidate(episodesProvider);
    ref.invalidate(episodeDetailProvider);
    // A feed refresh that adds episodes is a catalog change, and the
    // hub's shelves are the surface that is about what just arrived.
    ref.invalidate(upNextEpisodesProvider);
    ref.invalidate(latestEpisodesProvider);
    // A catalog change can shift any smart playlist's evaluation.
    ref.invalidate(playlistDetailProvider);
    // Applied review decisions and enrichment rewrite item metadata
    // server-side; an open editor must refetch what it shows.
    ref.invalidate(metadataControllerProvider);
  }

  void invalidateUserState() {
    ref.invalidate(playStateControllerProvider);
    // Entity stars and ratings ride the same user stream, as the
    // entity-state marker kind.
    ref.invalidate(entityPlayStateControllerProvider);
    ref.invalidate(continueListeningProvider);
    ref.invalidate(prefsControllerProvider);
    // Subscriptions and their settings ride the user stream, and a
    // membership change also reshapes the caller's own catalog view
    // (episodes scope to subscriptions), so the grid refetches too. The
    // unplayed count on each row and both hub shelves are read against
    // the caller's positions, so a checkpoint anywhere (this device or
    // another) is what makes them stale.
    ref.invalidate(subscriptionsProvider);
    ref.invalidate(podcastDetailProvider);
    ref.invalidate(episodeProgressProvider);
    ref.invalidate(upNextEpisodesProvider);
    ref.invalidate(latestEpisodesProvider);
    ref.invalidate(libraryControllerProvider);
    // Playlist rows ride the user stream, and play-state changes (a
    // star, a rating) can shift a user-state smart rule's evaluation.
    ref.invalidate(playlistsProvider);
    ref.invalidate(playlistDetailProvider);
    // Review, upload, and tool-task markers ride the user stream; the
    // curation screens refetch their lists and open details.
    ref.invalidate(reviewQueueProvider);
    ref.invalidate(reviewStatsProvider);
    ref.invalidate(reviewEntryProvider);
    ref.invalidate(uploadsProvider);
    ref.invalidate(toolTasksProvider);
  }

  final engine = ref.watch(syncEngineProvider);
  final connect = ref.watch(connectBinderProvider);
  if (engine != null) {
    final catalogSub = engine.catalogChanged.listen((_) => invalidateCatalog());
    final stateSub = engine.playStateChanged.listen(
      (_) => invalidateUserState(),
    );
    connect.bind(
      sender: engine.sendControl,
      routeControl: (handler) => engine.onControlFrame = handler,
    );
    engine.onConnected = connect.onConnected;
    engine.onPlayerInvalidate = connect.onPlayerInvalidate;
    engine.start();
    ref.onDispose(() {
      catalogSub.cancel();
      stateSub.cancel();
      engine.stop();
    });
    return;
  }
  if (kIsWeb) {
    final repository = ref.watch(repositoryProvider);
    final live = LiveInvalidations(
      channelFactory: eventsChannelFactory(
        baseUrl: waxDeckBaseUrl,
        token: () => repository.authToken,
      ),
      onCatalog: invalidateCatalog,
      onUser: invalidateUserState,
    );
    connect.bind(
      sender: live.sendControl,
      routeControl: (handler) => live.onControlFrame = handler,
    );
    live.onConnected = connect.onConnected;
    live.onPlayer = connect.onPlayerInvalidate;
    // The web listener has no status of its own to read, so it reports
    // one: the shell's reconnecting banner is downstream of this.
    live.onConnectionChanged = (connected) =>
        ref.read(liveLinkProvider.notifier).report(connected: connected);
    // Held, not read from the callback below: a disposal callback may
    // not touch `ref` at all — the element is already marked disposed
    // and the container swallows what that throws, so the reset would
    // silently never happen and the banner would stand over the login
    // screen of the next session.
    final link = ref.read(liveLinkProvider.notifier);
    live.start();
    ref.onDispose(() {
      live.stop();
      // A session that ended is not a client with a broken connection.
      link.forget();
    });
  }
});
