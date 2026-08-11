// Runs the shared engine conformance suite against whatever real player
// just_audio resolves to here - mpv via media_kit on the desktops,
// ExoPlayer on Android - with real decoding and wall-clock waits. The
// suite lives in waxdeck_player_testing; this file only supplies the
// real-engine harness. The caller synthesizes the tone fixture and names
// it in WAXDECK_CONFORMANCE_MEDIA: run-desktop.sh as a path in the
// environment, the emulator workflow as a loopback URL in a define.
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
    final engine = await createUnsilencedEngine();
    // Silent: this suite plays several minutes of a test tone through
    // the machine's real audio output, and whoever is at the keyboard
    // should not have to hear it. The one case that does assert on the
    // engine's own initial volume asks for an unsilenced engine instead,
    // and never plays through it.
    await engine.setVolume(0);
    return engine;
  }

  @override
  Future<AudioEnginePort> createUnsilencedEngine() async {
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
      // The wall clock is not the media clock behind this seek: the
      // seam only arrives once the audio pipeline drains, and a pulse
      // null sink holds about two seconds where CoreAudio holds under
      // one - a fixed wait raced that drain and lost on exactly one
      // platform, which read as eight engine failures on linux CI. So
      // the wait is for evidence the seam passed: the position falling
      // away from the runway (a boundary reset), or playback ending
      // (completion), with a cap for an engine that does neither.
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (!engine.playing) break;
        if (engine.position < target - const Duration(seconds: 1)) break;
      }
      // A beat for the seam's own events to reach their listeners.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return;
    }
    // Short amounts play out for real, measured on the engine's own
    // clock rather than the wall: a fresh pipeline (a replay's reload,
    // a cold sink) spends wall time before the position moves, and a
    // fixed sleep charged that spin-up against the media time it was
    // supposed to advance. A paused or completed engine cannot advance
    // media time at all, so the wait ends rather than burning the cap.
    final from = engine.position;
    final deadline = DateTime.now().add(amount + const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!engine.playing) break;
      if (engine.position - from >= amount) break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
}

/// The tone's location, compiled in.
///
/// `flutter test -d <device>` runs the test inside the app process on
/// the device, which cannot see the shell that launched it, so a define
/// is the only channel that reaches an emulator or a phone. Empty when
/// the caller uses the environment instead - which is what
/// run-desktop.sh does, because it runs the suite on this machine and a
/// define would mean recompiling per invocation.
const _mediaDefine = String.fromEnvironment('WAXDECK_CONFORMANCE_MEDIA');

/// A local path becomes a file URI; a URL is passed through.
///
/// An app on a device has no host path to open, so the emulator run
/// serves the tone over loopback HTTP instead - which is also the shape
/// a real library stream takes.
String _mediaUrl(String value) =>
    value.startsWith('http://') || value.startsWith('https://')
    ? value
    : Uri.file(value).toString();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final media = _mediaDefine.isNotEmpty
      ? _mediaDefine
      : Platform.environment['WAXDECK_CONFORMANCE_MEDIA'] ?? '';
  if (media.isEmpty) {
    // Without media there is nothing honest to test; fail loudly rather
    // than skip silently.
    throw StateError(
      'WAXDECK_CONFORMANCE_MEDIA must name the synthesized tone, as a '
      '--dart-define or in the environment; run this through '
      'e2e/run-desktop.sh or the android-conformance workflow',
    );
  }

  runAudioEngineConformance(
    'JustAudioEngine on ${Platform.operatingSystem}',
    RealEngineHarness(_mediaUrl(media)),
  );
}
