import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

import '../providers.dart';
import '../sync/sync_providers.dart';
import 'auto_browse.dart';

/// Registers the OS media session on Android: lock-screen and Bluetooth
/// controls, and the Android Auto browse tree over the local mirror.
/// A tap on a browse leaf resolves the stream online or falls back to
/// the downloaded original; the full session bookkeeping (queues,
/// listen accounting in Auto) matures in a later slice.
Future<void> initMediaSession(ProviderContainer container) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  final db = container.read(mirrorDatabaseProvider);
  if (db == null) return;
  await initWaxDeckAudioService(
    engine: container.read(audioEngineProvider),
    browse: MirrorBrowseSource(db),
    onPlayFromMediaId: (pid) async {
      final engine = container.read(audioEngineProvider);
      try {
        final info = await container.read(repositoryProvider).getPlayInfo(pid);
        await engine.load(info.url, mimeType: info.mimeType);
      } on WaxDeckApiException {
        final local = await container
            .read(downloadManagerProvider)
            ?.localFor(pid);
        if (local == null) rethrow;
        await engine.load(Uri.file(local.paths.first).toString());
      }
      await engine.play();
    },
  );
}
