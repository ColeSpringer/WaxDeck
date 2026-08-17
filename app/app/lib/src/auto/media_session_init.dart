import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_player/waxdeck_player.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../connect/queue_gateway.dart';
import '../providers.dart';
import '../sync/sync_providers.dart';
import 'auto_browse.dart';

/// Registers the OS media session: the Android notification and Auto's
/// browse tree, the browser's MediaSession, MPRIS on Linux, and the
/// Windows transport controls.
///
/// One registration for all of them. audio_service is federated, so
/// Linux and Windows are implementations of the same interface the
/// handler already speaks (`audio_service_mpris`, `audio_service_win`)
/// rather than a port of their own: a second port per desktop would be
/// three ways to describe one thing that is playing, which is three
/// chances for them to disagree.
///
/// Every control lands on the same queue the screen is looking at, so a
/// leaf tapped on the head unit plays through a full playback session
/// (resume, checkpoints, listen accounting, skip maps, and the offline
/// download fallback all work from the car exactly as they do on
/// screen, and it mirrors to Connect like any other), and a skip there
/// steps the queue rather than something only the car can see.
Future<void> initMediaSession(ProviderContainer container) async {
  if (!_hasMediaSession) {
    container.read(mediaSessionProvider).unavailable();
    return;
  }
  final db = container.read(mirrorDatabaseProvider);
  final queue = container.read(queueGatewayProvider);
  try {
    final handler = await initWaxDeckAudioService(
      engine: container.read(audioEngineProvider),
      // Only where there is a mirror to serve it from, which is what
      // makes the tree work offline. The web build has neither a mirror
      // nor a drawer to appear in.
      browse: db == null ? null : MirrorBrowseSource(db),
      onPlay: queue.play,
      // The engine cannot let go of a tuned station. Pause stays its
      // own, being a gap rather than an end.
      onStop: queue.stop,
      onSkipNext: queue.next,
      onSkipPrevious: queue.previous,
      onPlayFromMediaId: queue.playItem,
      onSkipToQueueItem: queue.jumpTo,
      // Passed from here because this is the side of the boundary that
      // can see the design system: waxdeck_player has no waxdeck_ui to
      // read the token from. The dark palette's accent is
      // the one to send - a notification tint is read against the
      // system's own surface, not against the app's current theme.
      notificationColor: WaxColors.dark.accent,
    ).timeout(_registrationLimit);
    // The sleep timer's extension button, the now-playing metadata, and
    // the queue a head unit renders all reach the session through this.
    container.read(mediaSessionProvider).bind(handler);
  } on Object catch (failure) {
    // A media session is an amenity, not a dependency: a Linux session
    // with no D-Bus to talk to, or a platform that refuses the
    // registration, must cost the lock screen and nothing else. Failing
    // here would be an app that will not launch because the shell it was
    // started from has no notification area.
    debugPrint('OS media session unavailable: $failure');
    container.read(mediaSessionProvider).unavailable();
  }
}

/// How long registration may take before the app goes on without it.
///
/// Awaited before `runApp`, and a `try` catches a throw but not a hang -
/// which is the realistic failure on the desktops, where a session bus
/// can accept a connection and never answer.
const Duration _registrationLimit = Duration(seconds: 5);

/// Whether this platform has a media session to register.
///
/// Everything WaxDeck ships on does.
bool get _hasMediaSession =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.linux ||
    defaultTargetPlatform == TargetPlatform.windows;
