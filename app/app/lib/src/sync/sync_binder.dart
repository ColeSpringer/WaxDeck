import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import '../artwork/artwork_providers.dart';
import '../books/books_controller.dart';
import '../connect/connect_providers.dart';
import '../downloads/downloads_controller.dart';
import '../home/home_shelves.dart';
import '../metadata/metadata_controller.dart';
import '../notifications/notifications_binder.dart';
import '../player/entity_play_state_controller.dart';
import '../player/play_progress.dart';
import '../player/play_state_controller.dart';
import '../playlists/playlists_controller.dart';
import '../podcasts/podcast_shelves.dart';
import '../podcasts/podcasts_controller.dart';
import '../providers.dart';
import '../radio/radio_controller.dart';
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
      // The home shelves are all catalog reads: what was added, what is
      // sealed, what is worth going back to. A scan lands on every one
      // of them at once.
      ...homeShelfProviders,
      // The music hub's shelves are the same reads scoped to one medium.
      ...musicShelfProviders,
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
      // The shelves that are per-user selections: what the caller
      // played, starred, rated, or has never opened. A checkpoint
      // anywhere - this device or another - is what makes them stale.
      // The catalog-only ones are not here; a checkpoint says nothing
      // about what the library gained.
      ...homeUserShelfProviders,
      ...musicUserShelfProviders,
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
  // Paced like the other two, and for a sharper reason: the server has no
  // record of who is tuned to what, so a cover landing for anyone marks
  // this topic on every connection - unpaced, each frame is a round trip.
  final radio = PacedRefresh(
    fanOut: () {
      if (ref.mounted) {
        ref.read(radioPlaybackProvider.notifier).refreshNowPlaying();
      }
      return true;
    },
  );

  ref.onDispose(() {
    catalog.dispose();
    user.dispose();
    radio.dispose();
  });

  final engine = ref.watch(syncEngineProvider);
  final connect = ref.watch(connectBinderProvider);
  final tick = ref.read(userStreamTickProvider.notifier);
  if (engine != null) {
    final catalogSub = engine.catalogChanged.listen((_) => catalog.hint());
    final stateSub = engine.playStateChanged.listen((_) => user.hint());
    // An item whose audio the server cannot give back takes its download
    // and its pinned artwork with it. Only `removed` reaches this stream:
    // trash tombstones the mirror row as well and keeps the bytes,
    // because a restore would otherwise cost the whole transfer again.
    // `remove` is the one call that does both halves.
    //
    // Chained rather than fired in parallel, for the reason `removeAll`
    // is sequential: `remove` decides whether to unlink a file by asking
    // whether any *other* row still holds the same essence, so two items
    // sharing one (CUE siblings share an image) reclaimed at once each
    // see the other's row, each conclude the file is shared, and leave it
    // on disk with nothing pointing at it. A delta page that retires a
    // pair delivers both tombstones together, so this is the ordinary
    // case rather than a race. It also keeps N reclaims from launching N
    // concurrent rebuilds of the downloads list.
    var reclaiming = Future<void>.value();
    final removedSub = engine.itemsRemoved.listen((pid) {
      reclaiming = reclaiming.then((_) async {
        // Checked per link rather than once: the chain outlives the
        // frame that queued it, and signing out disposes this binder
        // while reclaims are still draining. Reading `ref` past that
        // throws, which would take the rest of the queue with it.
        if (!ref.mounted) return;
        try {
          await ref.read(downloadsProvider.notifier).remove(pid);
        } catch (_) {
          // One pid that cannot be reclaimed must not stall the queue
          // behind it; the bytes stay and the next sweep sees them.
        }
      });
      unawaited(reclaiming);
    });
    connect.bind(
      sender: engine.sendControl,
      routeControl: (handler) => engine.onControlFrame = handler,
    );
    engine.onConnected = connect.onConnected;
    engine.onPlayerInvalidate = connect.onPlayerInvalidate;
    engine.onRadioInvalidate = radio.hint;
    engine.start();
    ref.onDispose(() {
      catalogSub.cancel();
      stateSub.cancel();
      removedSub.cancel();
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
      // Two consumers of the same signal. The pacer refetches whatever
      // is on screen; the tick is what lets the notifications bell walk
      // the user stream for itself, which is the only way a build with
      // no sync engine learns what a change was about (an invalidation
      // frame carries no detail).
      //
      // Held rather than read from the callback, for the reason the
      // link below is: a frame can arrive between `stop()` and the
      // socket actually closing, and `ref` on a disposed element throws
      // into a container that swallows it.
      onUser: () {
        user.hint();
        tick.bump();
      },
    );
    connect.bind(
      sender: live.sendControl,
      routeControl: (handler) => live.onControlFrame = handler,
    );
    live.onConnected = connect.onConnected;
    live.onPlayer = connect.onPlayerInvalidate;
    live.onRadio = radio.hint;
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
