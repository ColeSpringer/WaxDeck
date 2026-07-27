import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import '../library/library_controller.dart';
import '../metadata/metadata_controller.dart';
import '../player/entity_play_state_controller.dart';
import '../player/play_state_controller.dart';
import '../playlists/playlists_controller.dart';
import '../podcasts/podcasts_controller.dart';
import '../providers.dart';
import '../review/review_controller.dart';
import '../settings/prefs_controller.dart';
import '../shell/lifecycle_banners.dart';
import '../tools/tasks_screen.dart';
import '../uploads/uploads_controller.dart';
import '../connect/connect_providers.dart';
import 'live_invalidations.dart';
import 'test_env/test_env.dart';

/// The local mirror database. Native only: the web SPA stays
/// server-backed and rides invalidations directly.
final mirrorDatabaseProvider = Provider<MirrorDatabase?>((ref) {
  if (kIsWeb || inFlutterTest) return null;
  final db = openMirrorDatabase();
  ref.onDispose(db.close);
  return db;
});

/// The delta-sync engine (native). Tests get null unless they override.
final syncEngineProvider = Provider<SyncEngine?>((ref) {
  final db = ref.watch(mirrorDatabaseProvider);
  if (db == null) return null;
  final repository = ref.watch(repositoryProvider);
  final engine = SyncEngine(
    db: db,
    repository: repository,
    channelFactory: eventsChannelFactory(
      baseUrl: waxDeckBaseUrl,
      token: () => repository.authToken,
    ),
  );
  ref.onDispose(engine.dispose);
  return engine;
});

/// Downloads of original files for offline playback (native).
final downloadManagerProvider = Provider<DownloadManagerPort?>((ref) {
  final db = ref.watch(mirrorDatabaseProvider);
  if (db == null) return null;
  final manager = BackgroundDownloadManager(
    db: db,
    repository: ref.watch(repositoryProvider),
    baseUrl: waxDeckBaseUrl,
  );
  ref.onDispose(manager.dispose);
  return manager;
});

/// Engine status for the offline banner; empty stream when no engine.
final syncStatusProvider = StreamProvider.autoDispose<SyncStatus>((ref) {
  final engine = ref.watch(syncEngineProvider);
  if (engine == null) return const Stream.empty();
  return engine.status;
});

/// True when the engine has decided the server is unreachable; the UI
/// shows the offline affordances and reads flip to the mirror.
final offlineProvider = Provider.autoDispose<bool>((ref) {
  final engine = ref.watch(syncEngineProvider);
  if (engine == null) return false;
  final status = ref.watch(syncStatusProvider).value ?? engine.current;
  return engine.started && !status.online;
});

/// Binds the sync machinery to the authenticated subtree: watched by the
/// signed-in UI, disposed on sign-out. Native starts the engine and
/// relays its change streams into provider invalidations; web opens the
/// invalidation listener straight off the event channel.
final syncBinderProvider = Provider.autoDispose<void>((ref) {
  void invalidateCatalog() {
    ref.invalidate(libraryControllerProvider);
    ref.invalidate(continueListeningProvider);
    // Shows and episodes are catalog entities too: a server-side fetch
    // flipping an episode to downloaded must reach an open show screen.
    ref.invalidate(podcastDetailProvider);
    ref.invalidate(episodesProvider);
    ref.invalidate(episodeDetailProvider);
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
    // (episodes scope to subscriptions), so the grid refetches too.
    ref.invalidate(subscriptionsProvider);
    ref.invalidate(podcastDetailProvider);
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
