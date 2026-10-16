import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import '../admin/admin_providers.dart';
import '../artwork/artwork_providers.dart';
import '../auth/auth_controller.dart';
import '../books/books_controller.dart';
import '../books/series_controller.dart';
import '../books/series_merge.dart';
import '../connect/connect_providers.dart';
import '../downloads/downloads_controller.dart';
import '../health/health_controller.dart';
import '../home/home_shelves.dart';
import '../metadata/metadata_controller.dart';
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
import '../tools/tool_tasks_provider.dart';
import '../uploads/uploads_controller.dart';
import 'live_invalidations.dart';
import 'refresh_pacing.dart';
import 'server_event_bus.dart';
import 'streamed_play_states.dart';
import 'sync_providers.dart';

/// How close together two catalog passes may come. A running scan
/// reports a change about once a second, and every shelf an open home
/// holds is a catalog read; the first change after a quiet spell still
/// lands at once.
const kCatalogRefreshWindow = Duration(seconds: 5);

/// The same for the user stream. Longer than the pacer's default because
/// this client's own writes come back on it (a star, a rating, a mark)
/// and nothing on a report says whose write it was, so the window holds
/// for every report; the first after a quiet spell still lands at once.
const kUserRefreshWindow = Duration(seconds: 5);

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
      // of them at once. The probe is not here; see [_reprobeWhileEmpty].
      ...homeCatalogShelfProviders,
      // The music hub's shelves are the same reads scoped to one medium.
      ...musicShelfProviders,
      booksProvider,
      // The series a book's tags name are a catalog fact too, and the
      // books hub stays mounted as a shell branch - so without this a
      // scan that lands a new series leaves the shelf drawing the old
      // set until the app is relaunched.
      bookSeriesProvider,
      bookSeriesShelfProvider,
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
      // An open series screen is a catalog read like a show's.
      bookSeriesDetailProvider,
    ],
  );

  final userFanOut = InvalidationFanOut(
    container: ref.container,
    firstBuilds: firstBuilds,
    providers: [
      // The shelves that are per-user selections: what the caller
      // played, starred, rated, or has never opened. A play-state change
      // anywhere - this device or another - is what makes them stale; a
      // checkpoint that only moves a position is not, and moves the
      // rings instead (`onPlayState` below). The catalog-only ones are
      // not here; a checkpoint says nothing about what the library
      // gained.
      ...homeUserShelfProviders,
      ...musicUserShelfProviders,
      prefsControllerProvider,
      // Subscriptions and their settings ride the user stream, and a
      // membership change also reshapes the caller's own catalog view
      // (episodes scope to subscriptions), so the grid refetches too.
      // The unplayed count on each row and both hub shelves are read
      // against the caller's positions, so a play-state change anywhere
      // (this device or another) is what makes them stale.
      subscriptionsProvider,
      upNextEpisodesProvider,
      latestEpisodesProvider,
      // Playlist rows ride the user stream, and a play-state change
      // other than a position can shift a user-state smart rule's
      // evaluation.
      playlistsProvider,
      // Review, upload, and tool-task markers ride the user stream; the
      // curation screens refetch their lists and open details, and
      // home's review notice moves with them.
      reviewQueueProvider,
      reviewStatsProvider,
      pendingReviewCountProvider,
      uploadsProvider,
      toolTasksProvider,
    ],
    families: [
      playStateControllerProvider,
      // Entity stars and ratings have a marker and a fan-out of their
      // own below; a full pass still covers them, for the walks that
      // cannot say by kind what changed (a native re-mint).
      entityPlayStateControllerProvider,
      podcastDetailProvider,
      playProgressProvider,
      playlistDetailProvider,
      reviewEntryProvider,
    ],
  );

  // An artist's or album's star or rating moved. The marker names no
  // item, so nothing else the user stream feeds has changed.
  final entityFanOut = InvalidationFanOut(
    container: ref.container,
    firstBuilds: firstBuilds,
    families: [entityPlayStateControllerProvider],
  );

  // A report that moves only a position still reorders what is ordered
  // by progress: the podcast hub's Up next is the episodes most recently
  // progressed first. Home's resume shelf is ordered so too, and reorders
  // itself from the report without a read. No playlist rule reads a
  // position, and an open unseeded random list would reshuffle on every
  // re-read.
  final positionFanOut = InvalidationFanOut(
    container: ref.container,
    firstBuilds: firstBuilds,
    providers: [upNextEpisodesProvider],
  );

  // The catalog's job and health news have fan-outs of their own: a
  // running scan announces itself every five percent and its message
  // every fifteen seconds, and the user fan-out on each would refetch
  // every open list for the length of it.
  final jobsFanOut = InvalidationFanOut(
    container: ref.container,
    firstBuilds: firstBuilds,
    providers: [adminJobsProvider],
  );
  final healthFanOut = InvalidationFanOut(
    container: ref.container,
    firstBuilds: firstBuilds,
    providers: [healthProvider],
    families: [healthIssuesProvider],
  );
  // A task's progress moves only its own list.
  final tasksFanOut = InvalidationFanOut(
    container: ref.container,
    firstBuilds: firstBuilds,
    providers: [toolTasksProvider],
  );
  // A library added, restored or flagged anywhere, the CLI included. Home's
  // probe rides it: a library coming or going can change its answer
  // either way.
  final librariesFanOut = InvalidationFanOut(
    container: ref.container,
    firstBuilds: firstBuilds,
    providers: [
      librariesProvider,
      libraryCountsProvider,
      libraryHasAnythingProvider,
    ],
  );
  // Home's probe is out of the catalog fan-out, where it was one of the
  // reads every pass of a scan cost an open home. A first scan or upload
  // ends the first-run state, though, and its first pass is the first
  // sign, so while the probe reads empty every pass asks it; and a
  // library can empty under a probe that said it held something (a scan
  // that finds its files gone, a delete made on another device), so once
  // a run of catalog changes goes quiet it is asked again: once a run,
  // not once a pass.
  final probeFanOut = InvalidationFanOut(
    container: ref.container,
    firstBuilds: firstBuilds,
    providers: [libraryHasAnythingProvider],
  );
  final probeOnceQuiet = QuietRefresh(
    fanOut: probeFanOut.sweep,
    retry: probeFanOut.retry,
    quiet: kCatalogRefreshWindow,
  );

  // Both transports hand their hints to the same pacers: the fan-out
  // is what a hint costs, and running it on every one of them is what
  // starved a screen still on its first build.
  final container = ref.container;
  final catalog = PacedRefresh(
    fanOut: () {
      final applied = catalogFanOut.sweep();
      if (!_probeReadsEmpty(container)) return applied;
      return probeFanOut.sweep() && applied;
    },
    retry: () {
      final applied = catalogFanOut.retry();
      return probeFanOut.retry() && applied;
    },
    window: kCatalogRefreshWindow,
  );
  final user = PacedRefresh(
    fanOut: userFanOut.sweep,
    retry: userFanOut.retry,
    window: kUserRefreshWindow,
  );
  final entities = PacedRefresh(
    fanOut: entityFanOut.sweep,
    retry: entityFanOut.retry,
    window: kUserRefreshWindow,
  );
  final positions = PacedRefresh(
    fanOut: positionFanOut.sweep,
    retry: positionFanOut.retry,
    window: kUserRefreshWindow,
  );
  void catalogHint() {
    catalog.hint();
    probeOnceQuiet.hint();
  }

  final jobs = PacedRefresh(fanOut: jobsFanOut.sweep, retry: jobsFanOut.retry);
  final health = PacedRefresh(
    fanOut: healthFanOut.sweep,
    retry: healthFanOut.retry,
  );
  final tasks = PacedRefresh(
    fanOut: tasksFanOut.sweep,
    retry: tasksFanOut.retry,
  );
  final libraries = PacedRefresh(
    fanOut: librariesFanOut.sweep,
    retry: librariesFanOut.retry,
  );
  // Paced like the other two: a station whose stream announces a new
  // title every few minutes can land two rungs of artwork for it, and
  // unpaced each frame is a round trip.
  final radio = PacedRefresh(
    fanOut: () {
      if (ref.mounted) {
        ref.read(radioPlaybackProvider.notifier).refreshNowPlaying();
      }
      return true;
    },
  );

  ref.onDispose(() {
    for (final pacer in <PacedRefresh>[
      catalog,
      user,
      entities,
      positions,
      jobs,
      health,
      tasks,
      libraries,
      radio,
    ]) {
      pacer.dispose();
    }
    probeOnceQuiet.dispose();
  });

  // A walk that lost its place, or a catch-up that may have lost changes,
  // cannot say by kind what changed.
  void everyStateTopic() {
    user.hint();
    entities.hint();
    jobs.hint();
    health.hint();
    libraries.hint();
  }

  // Held for the session: what the stream last said about each item is
  // what the next report is measured against.
  ref.listen(streamedPlayStatesProvider, (_, _) {});
  // The report is the state, so every progress window holding the item
  // takes it at once, whatever else it moved. One that moved more than
  // the position is news for the user surfaces; one that moved only the
  // position reorders only what is ordered by progress.
  void onPlayState(PlayState state) {
    final moved = container
        .read(streamedPlayStatesProvider.notifier)
        .record(state);
    _echoReport(container, state);
    if (moved) {
      // The item's own controller draws what moved (a star, a rating, a
      // count), so it is read again now rather than at the end of the
      // user pass's window: another device's edit shows in about a
      // second. Only this item, and only a report that moved more than a
      // position.
      final item = playStateControllerProvider(state.pid);
      if (container.exists(item)) container.invalidate(item);
      user.hint();
    } else {
      positions.hint();
    }
  }

  final engine = ref.watch(syncEngineProvider);
  // Every server event this session observes, by kind, from whichever
  // transport it came over. On native the mirror stores play states,
  // entity states and bookmarks and hints for them itself.
  final bus = ref.watch(serverEventBusProvider);
  final eventSub = bus.events.listen((event) {
    switch (event.kind) {
      case 'job':
        jobs.hint();
      case 'health':
        health.hint();
      case 'task-progress':
        tasks.hint();
      case 'libraries':
        libraries.hint();
      case 'play-state' || 'entity-state' || 'bookmarks' when engine != null:
        break;
      case 'play-state':
        if (event.playState case final state?) {
          onPlayState(state);
        } else {
          user.hint();
        }
      case 'entity-state':
        entities.hint();
      default:
        user.hint();
    }
  });
  ref.onDispose(eventSub.cancel);
  final resetSub = bus.resets.listen((_) => everyStateTopic());
  ref.onDispose(resetSub.cancel);
  final connect = ref.watch(connectBinderProvider);
  // What makes the radio invalidation addressed rather than broadcast:
  // the server holds the station per connection and wakes only the
  // sockets listening to the one a cover landed for. Tuning to nothing
  // when playback stops is half the point - a client that walked away
  // from the dial stops being told about covers it has nothing to draw.
  ref.listen(radioPlaybackProvider.select((p) => p.station?.pid), (
    _,
    stationPid,
  ) {
    connect.bus.tune(stationPid);
  }, fireImmediately: true);
  final tick = ref.read(userStreamTickProvider.notifier);
  if (engine != null) {
    final catalogSub = engine.catalogChanged.listen((_) => catalogHint());
    // The mirror has stored the state by the time it says so, and says
    // it with the state. An artist or album marker stores nothing, entity
    // state being a live read.
    final stateSub = engine.playStateChanged.listen((change) {
      if (change.state case final state?) {
        onPlayState(state);
      } else {
        entities.hint();
      }
    });
    // An item whose audio the server cannot give back takes its download
    // and its pinned artwork with it. Of the tombstones only `removed`
    // reaches this stream: trash tombstones the mirror row as well and
    // keeps the bytes, because a restore would otherwise cost the whole
    // transfer again. The other pid on it is a download a kind change
    // left behind (see `SyncEngine.itemsRemoved`). `remove` is the one
    // call that does both halves, and stops a transfer still under way.
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
    // The account whose queued writes a flush sends; each waits for the
    // account that queued it. Read, not watched: this binder lives inside
    // one session, and the preference controller keeps the name current.
    engine.account = ref.read(signedInAccountProvider);
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
        baseUrl: ref.watch(serverBaseUrlProvider),
        token: () => repository.authToken,
      ),
      onCatalog: catalogHint,
      // An invalidation frame carries no detail, so the tick walks the
      // user stream, and the walk's events reach the fan-outs above by
      // kind. A catch-up may have lost changes the walk cannot report,
      // so it refreshes everything as well.
      //
      // Held rather than read from the callback, for the reason the
      // link below is: a frame can arrive between `stop()` and the
      // socket actually closing, and `ref` on a disposed element throws
      // into a container that swallows it.
      onUser: tick.bump,
      onUserCatchUp: () {
        everyStateTopic();
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

/// Whether home's probe last said the library is empty, which opens it
/// to every catalog pass.
bool _probeReadsEmpty(ProviderContainer container) =>
    container.exists(libraryHasAnythingProvider) &&
    container.read(libraryHasAnythingProvider).value == false;

/// Puts a reported state into every live progress window holding the
/// item, without a read: the report is the state.
///
/// The item's own play-state controller is left to the user pass: it
/// draws stars and counts, and folds them over its pending writes, which
/// a value set from outside would skip.
void _echoReport(ProviderContainer container, PlayState state) {
  for (final window in container.read(liveProgressWindowsProvider).toList()) {
    window.apply(state);
  }
}
