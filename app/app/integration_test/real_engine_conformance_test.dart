// Runs the shared engine conformance suite against the real desktop
// engine: mpv via media_kit behind just_audio, with real decoding and
// wall-clock waits. The suite lives in waxdeck_player_testing; this file
// only supplies the real-engine harness. run-desktop.sh synthesizes the
// tone fixture and passes its path in WAXDECK_CONFORMANCE_MEDIA.
import 'dart:io';

import 'package:integration_test/integration_test.dart';
import 'package:waxdeck_player/waxdeck_player.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

class RealEngineHarness extends AudioEngineHarness {
  RealEngineHarness(this.mediaUrl);

  @override
  final String mediaUrl;

  @override
  Duration get mediaDuration => const Duration(seconds: 8);

  @override
  Duration get tolerance => const Duration(milliseconds: 500);

  @override
  Future<AudioEnginePort> createEngine() async {
    ensureAudioEngineInitialized();
    return JustAudioEngine();
  }

  @override
  Future<void> advance(AudioEnginePort engine, Duration amount) async {
    // Media time is wall time on a real engine. Short amounts play out
    // for real; large ones seek to just before the target and play the
    // remainder, so reaching the end never costs the whole file.
    if (amount <= Duration.zero) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return;
    }
    final duration = engine.duration;
    if (amount > const Duration(seconds: 3) && duration != null) {
      const runway = Duration(milliseconds: 500);
      var target = engine.position + amount;
      if (target > duration - runway) {
        target = duration - runway;
      }
      await engine.seek(target);
      await Future<void>.delayed(runway + const Duration(seconds: 1));
      return;
    }
    await Future<void>.delayed(amount + const Duration(milliseconds: 300));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final mediaPath = Platform.environment['WAXDECK_CONFORMANCE_MEDIA'];
  if (mediaPath == null || mediaPath.isEmpty) {
    // Without media there is nothing honest to test; fail loudly rather
    // than skip silently.
    throw StateError(
      'WAXDECK_CONFORMANCE_MEDIA must point at the synthesized tone; '
      'run this through e2e/run-desktop.sh',
    );
  }

  runAudioEngineConformance(
    'JustAudioEngine on desktop mpv',
    RealEngineHarness(Uri.file(mediaPath).toString()),
  );
}
