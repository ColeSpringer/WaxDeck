import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

import '../connect/connect_providers.dart';
import '../player/playback_session.dart';
import '../player/session_registry.dart';
import '../providers.dart';
import '../sync/sync_providers.dart';
import 'auto_browse.dart';

/// Registers the OS media session on Android: lock-screen and Bluetooth
/// controls, and the Android Auto browse tree over the local mirror.
/// A tap on a browse leaf plays through a full playback session, so
/// resume, checkpoints, listen accounting, skip maps, and the offline
/// download fallback all work from the head unit exactly as they do on
/// screen, and the playback mirrors to Connect like any other.
Future<void> initMediaSession(ProviderContainer container) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  final db = container.read(mirrorDatabaseProvider);
  if (db == null) return;
  PlaybackSession? active;
  await initWaxDeckAudioService(
    engine: container.read(audioEngineProvider),
    browse: MirrorBrowseSource(db),
    onSkipNext: () async {
      await container.read(connectControllerProvider).nextInQueue();
    },
    onSkipPrevious: () async {
      await container.read(connectControllerProvider).previousInQueue();
    },
    onPlayFromMediaId: (pid) async {
      final registry = container.read(currentSessionRegistryProvider);
      final old = active;
      if (old != null) {
        registry.unregister(old);
        unawaited(old.dispose());
      }
      final detail = await container.read(repositoryProvider).getItem(pid);
      final session = PlaybackSession(
        repository: container.read(repositoryProvider),
        engine: container.read(audioEngineProvider),
        item: detail,
        clientId: listenClientId,
        sync: container.read(syncEngineProvider),
        downloads: container.read(downloadManagerProvider),
      );
      active = session;
      registry.register(session);
      container.read(connectControllerProvider).attachLocal(session, pid);
      await session.start();
    },
  );
}
