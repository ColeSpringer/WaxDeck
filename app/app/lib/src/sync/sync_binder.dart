import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import '../admin/admin_providers.dart';
import '../artwork/artwork_palette.dart';
import '../artwork/artwork_providers.dart';
import '../auth/auth_controller.dart';
import '../books/book_screen.dart';
import '../connect/connect_providers.dart';
import '../downloads/downloads_controller.dart';
import '../downloads/held_covers.dart';
import '../health/health_controller.dart';
import '../home/home_shelves.dart';
import '../organize/organize_screen.dart';
import '../player/entity_play_state_controller.dart';
import '../player/play_progress.dart';
import '../player/play_state_controller.dart';
import '../playlists/playlists_controller.dart';
import '../podcasts/podcast_shelves.dart';
import '../podcasts/podcasts_controller.dart';
import '../providers.dart';
import '../queue/queue_recheck.dart';
import '../radio/radio_controller.dart';
import '../review/review_controller.dart';
import '../settings/prefs_controller.dart';
import '../shell/lifecycle_banners.dart';
import '../shell/server_health.dart';
import '../stats/stats_controller.dart';
import '../tools/tool_tasks_provider.dart';
import '../uploads/uploads_controller.dart';
import 'catalog_cursor.dart';
import 'catalog_reads.dart';
import 'catalog_writes.dart';
import 'live_invalidations.dart';
import 'network_back/network_back.dart';
import 'page_resume/page_resume.dart';
import 'refresh_in_place.dart';
import 'refresh_pacing.dart';
import 'server_event_bus.dart';
import 'session_doubt.dart';
import 'streamed_play_states.dart';
import 'sync_providers.dart';

/// How close together two catalog passes may come. A running scan
/// reports a change about once a second, and every shelf an open home
/// holds is a catalog read; the first change after a quiet spell still
/// lands at once.
const kCatalogRefreshWindow = kRefreshWindow;

/// The same for the user stream. Longer than the pacer's default because
/// this client's own writes come back on it (a star, a rating, a mark)
/// and nothing on a report says whose write it was, so the window holds
/// for every report; the first after a quiet spell still lands at once.
const kUserRefreshWindow = Duration(seconds: 5);

/// Whether the session follows the event channel straight, with no
/// mirror: the web build's way. The platform decides; a test can too.
final liveListenerProvider = Provider<bool>((ref) => kIsWeb);

/// Each time the browser says the network is back; never, natively.
final networkReturnsProvider = Provider<Stream<void>>(
  (ref) => networkReturns(),
);

/// Each time the browser thaws this page (resumed from frozen, or restored
/// from the back/forward cache); never, natively.
final pageResumesProvider = Provider<Stream<void>>((ref) => pageResumes());

/// The session a binder left in doubt as it went.
final _doubtCarriedProvider = Provider<_DoubtCarried>((ref) => _DoubtCarried());

class _DoubtCarried {
  String? session;

  /// Whether [now] is the session left in doubt, forgetting it either way.
  bool take(String? now) {
    final carried = session != null && session == now;
    session = null;
    return carried;
  }
}

/// The sockets that listener opens, for as long as its binder lives.
final liveChannelFactoryProvider = Provider.autoDispose<EventsChannelFactory>((
  ref,
) {
  final repository = ref.watch(apiClientProvider);
  return eventsChannelFactory(
    baseUrl: ref.watch(serverBaseUrlProvider),
    token: () => repository.authToken,
  );
});

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

  // Every catalog read, in the one registry a local write sweeps too.
  final catalogFanOut = ref.watch(catalogFanOutProvider);
  final owed = ref.watch(owedDepthsProvider);
  final failedRefreshes = ref.watch(failedRefreshesProvider);

  final userFanOut = InvalidationFanOut(
    container: ref.container,
    firstBuilds: firstBuilds,
    // The queue pages, so a pass refreshes it in place.
    pagedProviders: [reviewQueueProvider],
    owed: owed,
    failed: failedRefreshes,
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
      // Listens are what the stats count, and a listen that moved a play
      // state arrives here as that state. The top list and the recaps are
      // on the catalog's quiet path as well, for the names they rank.
      ..._listenReads,
    ],
    families: [
      ..._listenFamilies,
      playStateControllerProvider,
      // Entity stars and ratings have a marker and a fan-out of their
      // own below; a full pass still covers them, for the walks that
      // cannot say by kind what changed (a native re-mint).
      entityPlayStateControllerProvider,
      podcastDetailProvider,
      playProgressProvider,
      playlistDetailProvider,
      reviewEntryProvider,
      // Where the caller left off in a book, which another device's play
      // moves.
      bookResumeProvider,
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
  // A listen the server accepted, which may have moved no play state.
  // The log refreshes in place, through what it has loaded.
  final listensFanOut = InvalidationFanOut(
    container: ref.container,
    firstBuilds: firstBuilds,
    pagedProviders: [listenLogProvider],
    owed: owed,
    failed: failedRefreshes,
    providers: [..._listenReads, listenLogProvider],
    families: _listenFamilies,
  );
  // A library added, restored or flagged anywhere, the CLI included. Home's
  // probe rides it: a library coming or going can change its answer
  // either way. So do the organize profiles, which count the libraries
  // they can lay out.
  final librariesFanOut = InvalidationFanOut(
    container: ref.container,
    firstBuilds: firstBuilds,
    providers: [
      librariesProvider,
      libraryCountsProvider,
      libraryHasAnythingProvider,
      organizeProfilesProvider,
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
  final probeFanOut = ref.watch(probeFanOutProvider);
  final probeOnceQuiet = QuietRefresh(
    fanOut: probeFanOut.sweep,
    retry: probeFanOut.retry,
    quiet: kCatalogRefreshWindow,
  );
  // The libraries' item counts lag a running scan and cost a count per
  // root, and no library marker says that items landed: asked once a run
  // of catalog changes goes quiet, so a scan's burst is one read.
  final countsFanOut = InvalidationFanOut(
    container: ref.container,
    firstBuilds: firstBuilds,
    providers: [libraryCountsProvider],
  );
  final countsOnceQuiet = QuietRefresh(
    fanOut: countsFanOut.sweep,
    retry: countsFanOut.retry,
    quiet: kCatalogRefreshWindow,
  );
  // The queue's items, read again once a run of catalog changes goes
  // quiet: what a kind change made anywhere did to them reaches the queue
  // here (see [QueueRecheck]). Once a run, not once a pass, like the
  // counts.
  final recheck = ref.read(queueRecheckProvider);
  final queueOnceQuiet = QuietRefresh(
    fanOut: () {
      unawaited(recheck.run());
      return true;
    },
    quiet: kCatalogRefreshWindow,
  );

  // A pass re-reads a paged listing's head alone, so a change made
  // elsewhere to a row past it shows here: the loaded extent, read once
  // a run of catalog changes goes quiet. Once a run, not once a pass:
  // a long listing is a request a page.
  final pagedOnceQuiet = QuietRefresh(
    fanOut: () => catalogFanOut.sweepPaged(CatalogRefresh.loaded),
    retry: catalogFanOut.retryPaged,
    quiet: kCatalogRefreshWindow,
  );

  // What a catalog frame says of the entities that changed, as covers
  // this client drops before the refresh the frame prompts rebuilds a
  // row. The store keys a replacement by its entity, so the front's URL
  // stands for every picture the entity can hold, and a colour is only
  // read off a front. The store notes the replacement before its first
  // await; what it drops after that fails alone.
  final container = ref.container;
  final covers = NamedCovers(
    replaced: (pid) {
      final url = container.read(repositoryProvider).artUrlFor(pid);
      unawaited(
        container.read(artworkStoreProvider).evict(url).catchError((
          Object error,
        ) {
          debugPrint('named cover: the cached cover did not clear: $error');
        }),
      );
      container.read(paletteCacheProvider).forget(url);
    },
    owed: () => container.read(artworkStoreProvider).oweEvictAll(),
    // Nothing is swept for it: every cover on screen hears the store and
    // asks again by itself, and one not on screen asks when it is built.
    allReplaced: () {
      unawaited(
        container.read(artworkStoreProvider).evictAll().catchError((
          Object error,
        ) {
          debugPrint('named covers: the cached covers did not clear: $error');
        }),
      );
      container.read(paletteCacheProvider).clear();
    },
  );

  // The reads that audit the catalog are asked once a run of changes
  // goes quiet, never on a pass of it.
  final quietFanOut = ref.watch(catalogQuietFanOutProvider);
  final auditsOnceQuiet = QuietRefresh(
    fanOut: quietFanOut.sweep,
    retry: quietFanOut.retry,
    quiet: kCatalogRefreshWindow,
  );

  // The same for the review queue under the user topic's hints: an
  // entry decided elsewhere past the head a pass re-reads stays listed
  // without it.
  final reviewFanOut = InvalidationFanOut(
    container: ref.container,
    firstBuilds: firstBuilds,
    providers: [reviewQueueProvider],
    pagedProviders: [reviewQueueProvider],
    owed: owed,
  );
  final reviewOnceQuiet = QuietRefresh(
    fanOut: () => reviewFanOut.sweep(CatalogRefresh.loaded),
    retry: reviewFanOut.retry,
    quiet: kUserRefreshWindow,
  );

  // A write's lookup is asked again with the pass it is owed, echo or not.
  var redrawOwed = false;
  bool catalogPass(CatalogRefresh depth) {
    if (redrawOwed) {
      redrawOwed = false;
      unawaited(recheck.redraw());
    }
    final applied = catalogFanOut.sweep(depth);
    // Otherwise only what a write left alone on its first build.
    final probed = _probeReadsEmpty(container)
        ? probeFanOut.sweep()
        : probeFanOut.retry();
    // The audits are never swept here: only what was left alone.
    final audits = quietFanOut.retry();
    return probed && applied && audits;
  }

  // Both transports hand their hints to the same pacers: the fan-out
  // is what a hint costs, and running it on every one of them is what
  // starved a screen still on its first build.
  final catalog = PacedRefresh(
    // A hint's pass reads the head: the quiet edge reads the loaded
    // extent once the run ends. The pass a write is owed, echo or not,
    // reads that far itself, since the run may not end for a long while.
    fanOut: () => catalogPass(CatalogRefresh.head),
    owed: () => catalogPass(CatalogRefresh.loaded),
    retry: () {
      final applied = catalogFanOut.retry();
      final audits = quietFanOut.retry();
      return probeFanOut.retry() && applied && audits;
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
    countsOnceQuiet.hint();
    queueOnceQuiet.hint();
    pagedOnceQuiet.hint();
    auditsOnceQuiet.hint();
  }

  // The server said nothing in the catalog changed after the cursor a
  // reconnect presented: what was read is current, but a read that failed
  // meanwhile is asked again, at once, as a write's run is, the reads a
  // run's quiet edge asks included. Neither kind is a first build, so
  // nothing is deferred.
  void catalogCurrent() {
    catalogFanOut.sweepUnhealthy();
    probeFanOut.sweepUnhealthy();
    countsFanOut.sweepUnhealthy();
    quietFanOut.sweepUnhealthy();
    // One under way may yet miss; asked now, it runs once more after.
    if (recheck.missedLast || recheck.running) unawaited(recheck.run());
  }

  void userHint() {
    user.hint();
    reviewOnceQuiet.hint();
  }

  // The pass a write made here is owed, for [CatalogWrites.landed] to
  // ask of this session's pacer.
  void catalogOwed() {
    redrawOwed = true;
    catalog.owe();
  }

  final writes = ref.read(catalogWritesProvider)..bindPass(catalogOwed);
  ref.onDispose(() => writes.unbindPass(catalogOwed));

  final jobs = PacedRefresh(fanOut: jobsFanOut.sweep, retry: jobsFanOut.retry);
  final health = PacedRefresh(
    fanOut: healthFanOut.sweep,
    retry: healthFanOut.retry,
  );
  final tasks = PacedRefresh(
    fanOut: tasksFanOut.sweep,
    retry: tasksFanOut.retry,
  );
  final listens = PacedRefresh(
    fanOut: () => listensFanOut.sweep(CatalogRefresh.loaded),
    retry: listensFanOut.retry,
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
      listens,
      libraries,
      radio,
    ]) {
      pacer.dispose();
    }
    probeOnceQuiet.dispose();
    countsOnceQuiet.dispose();
    queueOnceQuiet.dispose();
    pagedOnceQuiet.dispose();
    auditsOnceQuiet.dispose();
    reviewOnceQuiet.dispose();
    covers.dispose();
  });

  // A walk that lost its place, or a catch-up that may have lost changes,
  // cannot say by kind what changed, a `server` marker included.
  void everyStateTopic() {
    userHint();
    listens.hint();
    entities.hint();
    jobs.hint();
    health.hint();
    libraries.hint();
    container.invalidate(serverHealthProvider);
  }

  // The same reads, only those not current: a link that came back with
  // nothing to report leaves one that failed meanwhile in its error.
  final serverHealthFanOut = InvalidationFanOut(
    container: ref.container,
    firstBuilds: firstBuilds,
    providers: [serverHealthProvider],
  );
  void stateUnhealthy() {
    for (final fanOut in [
      userFanOut,
      entityFanOut,
      jobsFanOut,
      healthFanOut,
      tasksFanOut,
      listensFanOut,
      librariesFanOut,
      serverHealthFanOut,
    ]) {
      fanOut.sweepUnhealthy();
    }
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
      userHint();
    } else {
      positions.hint();
    }
  }

  // A transport says the session may have ended or changed hands: the
  // socket closed as ended or its reconnect was refused (in a browser,
  // which cannot tell a refusal from a dead network, any failed reconnect,
  // and a return, across which the cookie may have changed hands); or the
  // server refused a request for want of one. The session is read again
  // until the server answers, and the controller acts on the answer.
  final doubt = SessionDoubt(
    read: () {
      // Only a session the client holds can be in doubt, whether or not it
      // names a user.
      if (!ref.mounted ||
          ref.read(authControllerProvider).value?.authenticated != true) {
        return Future.value(SessionRecheck.left);
      }
      return ref.read(authControllerProvider.notifier).refreshSession();
    },
  );
  // A rebuild (a provider this binder watches moved) does not end a
  // doubt: the same session is still unanswered for, so the next binder
  // for it starts in doubt. An account that left, or a new session (a
  // sign-in here since), carries nothing.
  final carried = ref.read(_doubtCarriedProvider);
  final session = ref.read(authControllerProvider).value?.sessionId;
  if (carried.take(session)) doubt.suspect();
  ref.onDispose(() {
    if (doubt.inDoubt) carried.session = session;
  });
  ref.onDispose(doubt.dispose);

  // The platform says the network came back. A socket that outlived the
  // outage brings no reconnect, so what failed meanwhile is read again
  // here. One down, or on its way up, is hurried, and its reconnect reads
  // what failed once the session it rides answers: read here first, a
  // read could find the session handed to another account. With no
  // socket at all nothing else reads them, so they are read here.
  bool Function()? socketBack;
  void networkBack() {
    if (!(socketBack?.call() ?? true)) return;
    catalogCurrent();
    stateUnhealthy();
  }

  final browserReturns = ref
      .watch(networkReturnsProvider)
      .listen((_) => networkBack());
  final transportReturns = ref
      .watch(connectivityProvider)
      .returns
      .listen((_) => networkBack());
  ref.onDispose(() {
    unawaited(browserReturns.cancel());
    unawaited(transportReturns.cancel());
  });

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
      case 'listens':
        listens.hint();
      case 'libraries':
        libraries.hint();
      case 'server':
        // What /health reports moved: the streaming engine went away or
        // came back. Rare, and read whole, so not paced.
        container.invalidate(serverHealthProvider);
      case 'play-state' || 'entity-state' || 'bookmarks' when engine != null:
        break;
      case 'play-state':
        if (event.playState case final state?) {
          onPlayState(state);
        } else {
          userHint();
        }
      case 'entity-state':
        entities.hint();
      case 'playlist':
        _playlistCoversReplaced(container, event.pid);
        userHint();
      default:
        userHint();
    }
  });
  ref.onDispose(eventSub.cancel);
  final resetSub = bus.resets.listen((_) => everyStateTopic());
  ref.onDispose(resetSub.cancel);
  // The walk read another account's events: the cookie changed hands. The
  // session is read again, and what this tab sends meanwhile waits on it.
  final strangerSub = bus.anotherAccount.listen((_) {
    doubt.suspect();
    doubt.ask().ignore();
  });
  ref.onDispose(strangerSub.cancel);
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
    // What a frame says of names is on its stream before its pull
    // starts, so it is heard ahead of the change that pull ends in.
    final namedSub = engine.catalogNamed.listen(covers.heard);
    final catalogSub = engine.catalogChanged.listen((_) => catalogHint());
    final currentSub = engine.catalogCurrent.listen((_) => catalogCurrent());
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
    // Each time the socket comes up: a cover drawn off a pin still owed
    // its refresh asks the server, whatever holds the pin walk back, and
    // a download with no cover pinned gets one. A walk that finds nothing
    // of the user's makes no pass, so what failed meanwhile is asked here.
    final reachSub = engine.status
        .map((status) => status.online)
        .distinct()
        .where((online) => online)
        .listen((_) {
          container.read(artworkStoreProvider).serverReached();
          unawaited(pinHeldCovers(container));
          stateUnhealthy();
        });
    socketBack = engine.networkBack;
    ref.onDispose(reachSub.cancel);
    // An item whose audio the server cannot give back takes its download
    // and its pinned artwork with it. Of the tombstones only `removed`
    // reaches this stream: trash tombstones the mirror row as well and
    // keeps the bytes, because a restore would otherwise cost the whole
    // transfer again. The other pids on it are a download a kind change
    // left behind, and those a re-mirror (which carries no tombstones)
    // asked the server about and was told are gone, which can be many at
    // once (see `SyncEngine.itemsRemoved`). `DownloadsController.freeOwed`
    // is the one call that does both halves: the downloads manager's free,
    // which stops a transfer still under way, then the exact unpin.
    //
    // The commit that drops an item also records, with it, that its bytes
    // are owed a free, and this is where the free is kept: the downloads
    // manager decides in its own chain whether a pid is still owed (the
    // mirror may list it again, or the device have taken it up again,
    // since the commit) and takes the rows the record lists and no others,
    // and the record is cleared only once the bytes are gone. A kill, or a
    // failed free, leaves it for the next start (below).
    //
    // Chained rather than fired in parallel, for the reason `removeAll`
    // is sequential: the manager's discard decides whether to unlink a
    // file by asking whether any *other* row still holds the same essence,
    // so two items sharing one (CUE siblings share an image) reclaimed at
    // once each see the other's row, each conclude the file is shared, and
    // leave it on disk with nothing pointing at it. A delta page that
    // retires a pair delivers both tombstones together, so this is the
    // ordinary case rather than a race.
    //
    // A run of frees shares one rebuild of the downloads list, which reads
    // every stored item: it is asked for once the chain has run dry and
    // stayed dry through the turn, so what one commit or one delta page
    // publishes is one run however quickly each free goes.
    var reclaiming = Future<void>.value();
    var queued = 0;
    var changed = false;
    Timer? settled;
    ref.onDispose(() => settled?.cancel());
    Future<void> free(String pid) {
      queued++;
      settled?.cancel();
      return reclaiming = reclaiming.then((_) async {
        try {
          // Checked per link rather than once: the chain outlives the
          // frame that queued it, and signing out disposes this binder
          // while reclaims are still draining. Reading `ref` past that
          // throws, which would take the rest of the queue with it.
          if (!ref.mounted) return;
          try {
            if (await ref.read(downloadsProvider.notifier).freeOwed(pid)) {
              changed = true;
            }
            await engine.settleFree(pid);
          } catch (_) {
            // One pid that cannot be reclaimed must not stall the queue
            // behind it; its bytes stay owed, and the next start frees
            // them. Part of it may have gone, so the list is read again.
            changed = true;
          }
        } finally {
          if (--queued == 0) {
            settled = Timer(Duration.zero, () {
              settled = null;
              if (!changed || !ref.mounted) return;
              changed = false;
              ref.invalidate(downloadsProvider);
            });
          }
        }
      });
    }

    final removedSub = engine.itemsRemoved.listen(
      (pid) => unawaited(free(pid)),
    );
    // What an earlier run owed and did not finish, before this one syncs:
    // the engine's first sync waits behind it, and the downloads store
    // does not resume what it frees (see `BackgroundDownloadManager`).
    unawaited(
      engine
          .beforeSync(() async {
            // One run, so the downloads list is rebuilt once for the lot.
            for (final pid in await engine.pendingFrees()) {
              await free(pid);
            }
          })
          .catchError((Object _) {}),
    );
    connect.bind(
      sender: engine.sendControl,
      routeControl: (handler) => engine.onControlFrame = handler,
    );
    engine.onConnected = () {
      connect.onConnected();
      // The server is reached: a session a start opened on from memory is
      // the server's to confirm, or to end. One the server answered is
      // not read again here.
      if (ref.mounted &&
          ref.read(authControllerProvider.notifier).unconfirmed) {
        doubt.ask().ignore();
      }
    };
    engine.onAuthExpired = () => doubt.ask().ignore();
    engine.onSessionInDoubt = () => doubt.ask().ignore();
    // A refused request stops the engine. Once the session is seen to
    // stand it starts again, after the refused walk has run out: at once,
    // then a second later, doubling to a minute, so a server that refuses
    // the sync while it vouches for the session is not asked in a loop.
    final restartAfter = Backoff(startsAtOnce: true);
    var restarting = false;
    Timer? restart;
    ref.onDispose(() => restart?.cancel());
    doubt.onStands = () {
      if (engine.started || restarting) return;
      restarting = true;
      restart = Timer(restartAfter.take(), () async {
        await engine.beforeSync(() async {});
        restarting = false;
        // Not told the server is out of reach: this runs only once it has
        // answered for the session, and the stop cleared what was known.
        if (ref.mounted && !engine.started) unawaited(engine.start());
      });
    };
    // The waits start over once a whole walk has run out with nothing
    // refusing it, the questions it puts last included.
    engine.onReconciled = restartAfter.reset;
    engine.onPlayerInvalidate = connect.onPlayerInvalidate;
    engine.onRadioInvalidate = radio.hint;
    // The account whose queued writes a flush sends; each waits for the
    // account that queued it. Read, not watched: this binder lives inside
    // one session, and the preference controller keeps the name current.
    engine.account = ref.read(signedInAccountProvider);
    // A session opened from memory is a server already found out of reach.
    engine.start(
      unreached: ref.read(authControllerProvider.notifier).unconfirmed,
    );
    ref.onDispose(() {
      namedSub.cancel();
      catalogSub.cancel();
      currentSub.cancel();
      stateSub.cancel();
      removedSub.cancel();
      engine.stop();
    });
    return;
  }
  if (ref.watch(liveListenerProvider)) {
    final server = ref.watch(serverBaseUrlProvider);
    final live = LiveInvalidations(
      channelFactory: ref.watch(liveChannelFactoryProvider),
      // Read, not watched, as the engine's account is: this binder lives
      // inside one session.
      cursor: CatalogCursor(
        storage: ref.read(catalogCursorStorageProvider),
        server: server,
        account: ref.read(signedInAccountProvider),
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
    // Whether a socket that came back may catch up: not for an account
    // that left, whose screens go.
    live.onSessionInDoubt = () async =>
        await doubt.ask() != SessionRecheck.left;
    // Said in the same turn as the frame's `onCatalog`, and before it.
    live.onCatalogNamed = covers.heard;
    live.onCatalogCurrent = catalogCurrent;
    live.onPlayer = connect.onPlayerInvalidate;
    live.onRadio = radio.hint;
    // The web listener has no status of its own to read, so it reports
    // one: the shell's reconnecting banner is downstream of this. A drop
    // puts the session in doubt: another tab can sign in over the cookie
    // while this one is away.
    live.onConnectionChanged = (connected) {
      if (!connected) doubt.suspect();
      ref.read(liveLinkProvider.notifier).report(connected: connected);
    };
    // A page the browser froze ran nothing meanwhile, so on its thaw it
    // can send before it handles its socket's close: thawed, it asks.
    final thaws = ref.watch(pageResumesProvider).listen((_) => doubt.suspect());
    ref.onDispose(() => unawaited(thaws.cancel()));
    // Whatever this tab sends for the account while the session is in
    // doubt waits for the answer, and goes only for an account that
    // stands: a Riverpod retry, a first read or a tap sent before it
    // could go out through a cookie another account holds.
    final gate = ref.read(sessionGateProvider);
    final pass = doubt.pass;
    gate.bind(pass);
    ref.onDispose(() => gate.unbind(pass));
    // Held, not read from the callback below: a disposal callback may
    // not touch `ref` at all - the element is already marked disposed
    // and the container swallows what that throws, so the reset would
    // silently never happen and the banner would stand over the login
    // screen of the next session.
    final link = ref.read(liveLinkProvider.notifier);
    socketBack = live.networkBack;
    live.start();
    ref.onDispose(() {
      live.stop();
      // A session that ended is not a client with a broken connection.
      // After the disposal: no provider may be changed inside another's
      // lifecycle, and a container gone by then has no banner to clear.
      Future.microtask(link.forget).ignore();
    });
  }
});

/// What a listen moves, on the user pass and the listens marker's alike.
/// The log rides the marker alone, which every accepted listen sends.
final List<ProviderBase<Object?>> _listenReads = [
  listeningStatsProvider,
  listeningHeatmapProvider,
  topListProvider,
];

/// The same, as families: a year's recap.
final List<Family> _listenFamilies = [yearInReviewProvider];

/// The most entities one catalog invalidation names: the contract's
/// bound on its `pids`.
const kCatalogFrameNames = 64;

/// What catalog invalidations do to covers, by what they say of the
/// entities that changed.
///
/// A frame names the entities whose rows changed, not the covers that
/// did, and a scan names a frameful several times a second or says only
/// that entities went unnamed. So busy is a rate. Time runs in windows of
/// [window], the first opening at the first word heard after none. While
/// a window has named no more than a single frame can and carried no
/// unnamed marker, each name is told replaced as it is heard, ahead of
/// the refresh its frame prompts. Past either the stretch is busy:
/// every cover is owed a fresh ask and nothing is told by name, window
/// after window, until one stays within the bound and carries no marker.
/// At that window's end every cover is asked afresh, one time, and the
/// stretch is over.
class NamedCovers {
  NamedCovers({
    required this.replaced,
    required this.owed,
    required this.allReplaced,
    this.window = kCatalogRefreshWindow,
  });

  /// The pictures of one named entity changed.
  final void Function(String pid) replaced;

  /// A stretch became busy: every cover is owed a fresh ask, which a
  /// session that ends first never makes.
  final void Function() owed;

  /// A busy stretch ended: every cover is asked afresh.
  final void Function() allReplaced;

  final Duration window;

  /// The open window's end; null between windows.
  Timer? _end;

  /// What the open window has named, counted no further than past the
  /// bound.
  final _named = <String>{};

  /// Whether the open window heard that entities went unnamed.
  var _unnamed = false;
  var _busy = false;
  var _disposed = false;

  bool get _over => _unnamed || _named.length > kCatalogFrameNames;

  /// What a frame said, before the refresh it prompts. A name heard
  /// again is told again: its cover may have been replaced again.
  void heard(CatalogNames names) {
    if (_disposed) return;
    _end ??= Timer(window, _close);
    if (!_over) {
      _named.addAll(names.pids);
      _unnamed = names.unnamed;
    }
    if (_busy) return;
    if (_over) {
      _busy = true;
      owed();
      return;
    }
    names.pids.forEach(replaced);
  }

  void _close() {
    final over = _over;
    _named.clear();
    _unnamed = false;
    if (_busy && over) {
      _end = Timer(window, _close);
      return;
    }
    _end = null;
    if (!_busy) return;
    _busy = false;
    allReplaced();
  }

  /// Ignores every later call, for a session that ended. What a busy
  /// stretch owed stays owed.
  void dispose() {
    _disposed = true;
    _end?.cancel();
    _end = null;
  }
}

/// A playlist changed, on this device or another: its picture is minted
/// by this server at one URL for as long as the playlist lasts, whatever
/// it holds, so it is told replaced. A change that names no playlist
/// tells every one held, there being few.
void _playlistCoversReplaced(ProviderContainer container, String? pid) {
  final repository = container.read(repositoryProvider);
  final Iterable<String> urls;
  if (pid != null) {
    urls = [repository.artUrlFor(pid)];
  } else if (container.exists(playlistsProvider)) {
    urls = [
      for (final playlist
          in container.read(playlistsProvider).value ?? const <Playlist>[])
        ?playlist.artUrl,
    ];
  } else {
    return;
  }
  final store = container.read(artworkStoreProvider);
  final palettes = container.read(paletteCacheProvider);
  for (final url in urls) {
    unawaited(
      store.evict(url).catchError((Object error) {
        debugPrint('playlist cover: the cached cover did not clear: $error');
      }),
    );
    palettes.forget(url);
  }
}

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
