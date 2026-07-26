import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

import '../connect/queue_gateway.dart';
import '../providers.dart';
import '../sync/sync_providers.dart';
import 'auto_browse.dart';

/// Registers the OS media session on Android: lock-screen and Bluetooth
/// controls, and the Android Auto browse tree over the local mirror.
///
/// Every control lands on the same queue the screen is looking at, so a
/// leaf tapped on the head unit plays through a full playback session
/// (resume, checkpoints, listen accounting, skip maps, and the offline
/// download fallback all work from the car exactly as they do on
/// screen, and it mirrors to Connect like any other), and a skip there
/// steps the queue rather than something only the car can see.
Future<void> initMediaSession(ProviderContainer container) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  final db = container.read(mirrorDatabaseProvider);
  if (db == null) return;
  final queue = container.read(queueGatewayProvider);
  await initWaxDeckAudioService(
    engine: container.read(audioEngineProvider),
    browse: MirrorBrowseSource(db),
    onSkipNext: queue.next,
    onSkipPrevious: queue.previous,
    onPlayFromMediaId: queue.playItem,
  );
}
