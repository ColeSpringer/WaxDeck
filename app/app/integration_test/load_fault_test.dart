// What the real players do when a load fails, on the devices that have
// one. A characterization test: it pins what the platforms actually
// report rather than what their documentation says they report, because
// the fault taxonomy in `waxdeck_player` is built on the difference and
// nothing else in the suite can see it.
//
// Run it by hand, like the conformance suite beside it:
//   flutter test integration_test/load_fault_test.dart -d emulator-5554
//   flutter test integration_test/load_fault_test.dart -d linux
//
// Both halves pin platform behaviour WaxDeck builds on. On Android
// every failure arrives as one code and one constant string, and the
// engine's reachability probe (`probedMediaFaultOf`) is what tells
// them apart - so the split asserted there is the probe working end to
// end, on a real device, against this file's own server. On desktop
// the failure never arrives at all, which is the open bug in
// `docs/bugs.md`; the desktop half starting to fail is mpv starting to
// report, and the signal to go close that entry.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

/// How long a load gets before it counts as never answering. Generous:
/// the point is to tell "throws late" apart from "does not throw".
const _budget = Duration(seconds: 20);

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
  ensureAudioEngineInitialized();
  final engine = JustAudioEngine();
  // Silenced before anything is asked of it: whoever is at the keyboard
  // should not hear a test, and a load that half-succeeds can start.
  await engine.setVolume(0);
  try {
    await engine.load(url).timeout(_budget);
    return const Loaded();
  } on TimeoutException {
    return const Hung();
  } on MediaLoadException catch (e) {
    return Threw(e.fault, e.cause.toString());
  } finally {
    await engine.dispose();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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
      req.response.statusCode = req.uri.path.contains('502') ? 502 : 404;
      req.response.close();
    });
    final base = 'http://127.0.0.1:${server.port}';
    urls = <String, String>{
      // The bytes are the problem.
      'undecodable bytes': 'file://${dir.path}/garbage.mp3',
      'truncated file': 'file://${dir.path}/truncated.mp3',
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
    // The control. Without it every expectation here would also pass
    // against an engine that cannot load anything at all.
    final media = const String.fromEnvironment('WAXDECK_CONFORMANCE_MEDIA');
    if (media.isEmpty) {
      markTestSkipped('WAXDECK_CONFORMANCE_MEDIA names the synthesized tone');
      return;
    }
    expect(await _attempt('file://$media'), isA<Loaded>());
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
      // Measured on wax-conformance-35: all seven arrive as
      // PlayerException(0, "Source error"). ExoPlayer's TYPE_SOURCE
      // covers an unreadable container and a refused request alike,
      // and the cause that separates them does not cross just_audio's
      // platform channel - if a cause below ever stops being that
      // constant, the platform has started saying more and the probe
      // is doing a job the code could. Until then the reachability
      // probe is the classifier: media the device can fetch while the
      // player refuses it is the media's own fault, so the two bad
      // files split from the five bad paths.
      const badMedia = <String>{'undecodable bytes', 'truncated file'};
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
          badMedia.contains(o.key) ? MediaFault.source : MediaFault.transport,
          reason: o.key,
        );
      }
      return;
    }

    // Desktop (mpv through media_kit): the load future never settles at
    // all - no throw, no completion - so there is nothing to classify
    // and, worse, nothing for the session to give up on. That is the
    // bug in docs/bugs.md, and this is what closing it changes.
    for (final o in outcomes.entries) {
      expect(o.value, isA<Hung>(), reason: '${o.key} answered after all');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
