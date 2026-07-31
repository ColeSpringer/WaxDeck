import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import '../artwork/artwork_providers.dart';
import '../books/books_controller.dart';
import '../connect/connect_providers.dart';
import '../downloads/downloads_controller.dart';
import '../library/library_controller.dart';
import '../metadata/metadata_controller.dart';
import '../player/entity_play_state_controller.dart';
import '../player/play_progress.dart';
import '../player/play_state_controller.dart';
import '../playlists/playlists_controller.dart';
import '../podcasts/podcast_shelves.dart';
import '../podcasts/podcasts_controller.dart';
import '../providers.dart';
import '../review/review_controller.dart';
import '../settings/prefs_controller.dart';
import '../shell/adaptive_shell.dart';
import '../shell/lifecycle_banners.dart';
import '../tools/tasks_screen.dart';
import '../uploads/uploads_controller.dart';
import 'live_invalidations.dart';
import 'refresh_pacing.dart';
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
  // The ledger of in-flight first builds, registered on the root
  // container in main.dart. Absent (a test container that did not
  // register one), the fan-outs invalidate unconditionally, which is
  // the pre-deferral behavior.
  final firstBuilds = ref.container.observers
      .whereType<FirstBuildObserver>()
      .firstOrNull;

  final catalogFanOut = InvalidationFanOut(
    container: ref.container,
    firstBuilds: firstBuilds,
    // Covers appear as part of the catalog changing - a scan reading
    // embedded art, enrichment landing, another device writing one -
    // and the store has been remembering which ones answered 404 so it
    // can draw the monogram without asking again. Those answers are
    // exactly what a catalog change can falsify, and this is the only
    // signal that sees it: the cover editors call `evict`, and nothing
    // else does.
    prelude: () => ref.read(artworkStoreProvider).forgetAbsences(),
    providers: [
      libraryControllerProvider,
      continueListeningProvider,
      booksProvider,
      // Whether a domain has anything behind it is a catalog fact, and
      // it decides whether the chrome offers its tab. This is what turns
      // the Audiobooks tab on when a first scan finds books, instead of
      // at the next launch.
      emptyDomainsProvider,
      // What is downloaded is local, but who each row is comes from the
      // mirror, so a retitled item has to reach an open manager.
      downloadsProvider,
      // A feed refresh that adds episodes is a catalog change, and the
      // hub's shelves are the surface that is about what just arrived.
      upNextEpisodesProvider,
      latestEpisodesProvider,
    ],
    families: [
      // Shows and episodes are catalog entities too: a server-side fetch
      // flipping an episode to downloaded must reach an open show screen.
      podcastDetailProvider,
      episodesProvider,
      episodeDetailProvider,
      // A catalog change can shift any smart playlist's evaluation.
      playlistDetailProvider,
      // Applied review decisions and enrichment rewrite item metadata
      // server-side; an open editor must refetch what it shows.
      metadataControllerProvider,
    ],
  );

  final userFanOut = InvalidationFanOut(
    container: ref.container,
    firstBuilds: firstBuilds,
    providers: [
      continueListeningProvider,
      prefsControllerProvider,
      // Subscriptions and their settings ride the user stream, and a
      // membership change also reshapes the caller's own catalog view
      // (episodes scope to subscriptions), so the grid refetches too.
      // The unplayed count on each row and both hub shelves are read
      // against the caller's positions, so a checkpoint anywhere (this
      // device or another) is what makes them stale.
      subscriptionsProvider,
      upNextEpisodesProvider,
      latestEpisodesProvider,
      libraryControllerProvider,
      // Playlist rows ride the user stream, and play-state changes (a
      // star, a rating) can shift a user-state smart rule's evaluation.
      playlistsProvider,
      // Review, upload, and tool-task markers ride the user stream; the
      // curation screens refetch their lists and open details.
      reviewQueueProvider,
      reviewStatsProvider,
      uploadsProvider,
      toolTasksProvider,
    ],
    families: [
      playStateControllerProvider,
      // Entity stars and ratings ride the same user stream, as the
      // entity-state marker kind.
      entityPlayStateControllerProvider,
      podcastDetailProvider,
      playProgressProvider,
      playlistDetailProvider,
      reviewEntryProvider,
    ],
  );

  // Both transports hand their hints to the same pacers: the fan-out
  // is what a hint costs, and running it on every one of them is what
  // starved a screen still on its first build.
  final catalog = PacedRefresh(
    fanOut: catalogFanOut.sweep,
    retry: catalogFanOut.retry,
  );
  final user = PacedRefresh(fanOut: userFanOut.sweep, retry: userFanOut.retry);
  ref.onDispose(() {
    catalog.dispose();
    user.dispose();
  });

  final engine = ref.watch(syncEngineProvider);
  final connect = ref.watch(connectBinderProvider);
  if (engine != null) {
    final catalogSub = engine.catalogChanged.listen((_) => catalog.hint());
    final stateSub = engine.playStateChanged.listen((_) => user.hint());
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
      onCatalog: catalog.hint,
      onUser: user.hint,
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
    // not touch `ref` at all - the element is already marked disposed
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
