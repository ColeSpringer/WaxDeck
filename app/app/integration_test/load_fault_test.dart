// What the real players do when a load fails, on the devices that have
// one. A characterization test: it pins what the platforms actually
// report rather than what their documentation says they report, because
// the fault taxonomy in `waxdeck_player` is built on the difference and
// nothing else in the suite can see it.
//
// Both halves run in CI: the desktop one through e2e/run-desktop.sh,
// the Android one on the emulator the conformance workflow already
// boots. By hand it is the same two commands:
//   flutter test integration_test/load_fault_test.dart -d emulator-5554
//   flutter test integration_test/load_fault_test.dart -d linux
//
// A characterization test is worth its last run and no more, which is
// why neither half is left to be remembered.
//
// Both halves pin platform behaviour WaxDeck builds on, and both end
// in the same split for the same reason. On Android every failure
// arrives as one code and one constant string, so the engine's stream
// probe is what tells them apart. On desktop mpv reports no failure at
// all - the load simply never finishes - so the engine's load deadline
// is what produces a failure to classify, and the probe is then the
// whole verdict rather than a refinement of one. Two different
// silences, one answer: media the device can fetch while the player
// cannot finish with it is the media's own fault, and so is media the
// server answers 415 for.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

/// The tone's location, from a define or the environment.
///
/// Both channels, because both callers exist and neither can use the
/// other's: `flutter test -d <device>` runs inside the app process on
/// the device, which cannot see the shell that launched it, so an
/// emulator run needs a define; run-desktop.sh runs on this machine and
/// a define would mean recompiling per invocation, so it exports the
/// variable instead. The conformance suite beside this one resolves it
/// the same way.
const _mediaDefine = String.fromEnvironment('WAXDECK_CONFORMANCE_MEDIA');

/// A local path becomes a file URI; a URL is passed through. The
/// emulator run serves the tone over loopback HTTP, because an app on a
/// device has no host path to open.
String _mediaUrl(String value) =>
    value.startsWith('http://') || value.startsWith('https://')
    ? value
    : Uri.file(value).toString();

/// The rows in `urls` whose fault is the media rather than the way to
/// it, and so the ones a queue may step past.
///
/// One list for both platforms, because agreeing is the point: the
/// halves reach it from opposite directions - a code that says nothing
/// on Android, no report at all on desktop - and a split that differed
/// between them would be the bug this file exists to catch.
const _badMedia = <String>{'undecodable bytes', 'truncated file', 'http 415'};

/// How long a load gets before it counts as never answering.
///
/// Comfortably outside the engine's own fifteen-second deadline and the
/// stop and probe that follow it, so a load this calls hung is one the
/// engine failed to give up on rather than one still giving up.
const _budget = Duration(seconds: 30);

/// What one attempted load did.
sealed class Outcome {
  const Outcome();
}

class Loaded extends Outcome {
  const Loaded();

  @override
  String toString() => 'loaded';
}

class Hung extends Outcome {
  const Hung();

  @override
  String toString() => 'never settled in ${_budget.inSeconds}s';
}

class Threw extends Outcome {
  const Threw(this.fault, this.cause);
  final MediaFault fault;

  /// The plugin's own exception, as its own `toString`. Not matched on
  /// by type: only `waxdeck_player` may name just_audio's types, and
  /// this file sits in the app.
  final String cause;

  @override
  String toString() => 'threw ${fault.name}: $cause';
}

Future<Outcome> _attempt(String url) async {
  final engine = await _silentEngine();
  try {
    return await _attemptOn(engine, url);
  } finally {
    await engine.dispose();
  }
}

Future<Outcome> _attemptOn(JustAudioEngine engine, String url) async {
  try {
    await engine.load(url).timeout(_budget);
    return const Loaded();
  } on TimeoutException {
    return const Hung();
  } on MediaLoadException catch (e) {
    return Threw(e.fault, e.cause.toString());
  }
}

Future<JustAudioEngine> _silentEngine() async {
  ensureAudioEngineInitialized();
  final engine = JustAudioEngine();
  // Silenced before anything is asked of it: whoever is at the keyboard
  // should not hear a test, and a load that half-succeeds can start.
  await engine.setVolume(0);
  return engine;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final media = _mediaDefine.isNotEmpty
      ? _mediaDefine
      : Platform.environment['WAXDECK_CONFORMANCE_MEDIA'] ?? '';
  if (media.isEmpty) {
    // The control below is what makes every expectation in this file
    // mean something: without it the taxonomy passes just as well
    // against an engine that cannot load anything at all. Skipping
    // quietly would leave the desktop-conformance job green having
    // proved nothing, so this fails loudly instead - the same rule the
    // conformance suite beside it follows.
    throw StateError(
      'WAXDECK_CONFORMANCE_MEDIA must name the synthesized tone, as a '
      '--dart-define or in the environment; run this through '
      'e2e/run-desktop.sh or the android-conformance workflow',
    );
  }

  late Directory dir;
  late HttpServer server;
  late Map<String, String> urls;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('loadfault');
    File(
      '${dir.path}/garbage.mp3',
    ).writeAsBytesSync(Uint8List.fromList(List<int>.filled(4096, 0x41)));
    File('${dir.path}/truncated.mp3').writeAsBytesSync(
      Uint8List.fromList(<int>[0xFF, 0xFB, 0x90, 0x00, ...List.filled(64, 0)]),
    );
    // On the device's own loopback, so no host networking is involved
    // and the emulator case needs no port forwarding.
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      // Exact paths rather than substring guards: the table is then
      // exhaustive over what `urls` below asks for, and reading it does
      // not depend on the order the arms happen to be in.
      req.response.statusCode = switch (req.uri.path) {
        '/502.mp3' => HttpStatus.badGateway,
        '/415.mp3' => HttpStatus.unsupportedMediaType,
        _ => HttpStatus.notFound,
      };
      req.response.close();
    });
    final base = 'http://127.0.0.1:${server.port}';
    urls = <String, String>{
      // The bytes are the problem.
      'undecodable bytes': 'file://${dir.path}/garbage.mp3',
      'truncated file': 'file://${dir.path}/truncated.mp3',
      // The bytes are the problem and the server says so: what
      // WaxDeck's own stream endpoint answers when it cannot make
      // audio out of the file (`unsupported-format`, the sidecar's
      // 415). The player is told nothing either way, so the split has
      // to come from the probe reading the status.
      'http 415': '$base/415.mp3',
      // Getting the bytes is the problem.
      'missing file': 'file://${dir.path}/absent.mp3',
      'http 404': '$base/nope.mp3',
      'http 502': '$base/502.mp3',
      'connection refused': 'http://127.0.0.1:1/nope.mp3',
      'dns failure': 'http://no-such-host.invalid/a.mp3',
    };
  });

  tearDownAll(() async {
    await server.close(force: true);
    dir.deleteSync(recursive: true);
  });

  testWidgets('a real file loads, so a failure below means the file', (
    _,
  ) async {
    expect(await _attempt(_mediaUrl(media)), isA<Loaded>());
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('every way a load can fail lands on the right side', (_) async {
    final outcomes = <String, Outcome>{};
    for (final entry in urls.entries) {
      outcomes[entry.key] = await _attempt(entry.value);
    }
    for (final o in outcomes.entries) {
      debugPrint('LOAD FAULT | ${o.key} | ${o.value}');
    }

    if (Platform.isAndroid) {
      // Measured on wax-conformance-35, and again on wax-phone-36 when
      // the refusal row joined them: all of them arrive as
      // PlayerException(0, "Source error"). ExoPlayer's TYPE_SOURCE
      // covers an unreadable container and a refused request alike,
      // and the cause that separates them does not cross just_audio's
      // platform channel - if a cause below ever stops being that
      // constant, the platform has started saying more and the probe
      // is doing a job the code could. Until then the stream probe is
      // the classifier: media the device can fetch while the player
      // refuses it is the media's own fault, and so is media the
      // server itself refuses to decode. The two bad files and the
      // refusal split from the five bad paths.
      for (final o in outcomes.entries) {
        final threw = o.value;
        expect(threw, isA<Threw>(), reason: '${o.key} did not throw');
        // `PlayerException.toString` is "($code) $message".
        expect(
          (threw as Threw).cause,
          '(0) Source error',
          reason: '${o.key} reported something worth telling apart',
        );
        expect(
          threw.fault,
          _badMedia.contains(o.key) ? MediaFault.source : MediaFault.transport,
          reason: o.key,
        );
      }
      return;
    }

    // Desktop (mpv through media_kit): the platform reports nothing at
    // all - the load future used to never settle, no throw and no
    // completion, so there was nothing to classify and nothing for the
    // session to give up on. The engine's load deadline is what ends
    // that wait, and past it the stream probe is the only evidence
    // there is. No cause is asserted: what threw is the deadline, so
    // the cause is the engine's own TimeoutException rather than
    // anything the platform said.
    for (final o in outcomes.entries) {
      final threw = o.value;
      expect(threw, isA<Threw>(), reason: '${o.key} never gave up');
      expect(
        (threw as Threw).fault,
        _badMedia.contains(o.key) ? MediaFault.source : MediaFault.transport,
        reason: o.key,
      );
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('an engine that gave up on one load can play the next', (
    _,
  ) async {
    // The abandoned load is stopped rather than cancelled - just_audio
    // has no cancel - and that stop runs against a player that has
    // already declined to finish something. If it left the engine
    // wedged, every fault above would cost the rest of the session.
    final engine = await _silentEngine();
    addTearDown(engine.dispose);

    final failed = await _attemptOn(engine, urls['undecodable bytes']!);
    expect(failed, isA<Threw>(), reason: 'nothing to recover from');
    expect(await _attemptOn(engine, _mediaUrl(media)), isA<Loaded>());
  }, timeout: const Timeout(Duration(minutes: 2)));
}
