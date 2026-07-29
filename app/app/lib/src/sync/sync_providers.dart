import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import '../providers.dart';
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
