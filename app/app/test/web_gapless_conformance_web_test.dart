@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_player/waxdeck_player.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:web/web.dart' as web;

import 'hls_stub.dart';

/// The browser engine as an implementation of the port, held to the
/// same contract every other one is.
///
/// This is the fourth implementation slot: the deterministic fake, mpv
/// through media_kit, ExoPlayer, and now the composite. It runs the
/// whole suite, including the timeline group, which only a harness that
/// can supply a playable timeline declares.
///
/// The standard half is the deterministic fake. Not a shortcut: what a
/// composite adds over its halves is the routing, the silencing, and the
/// merged streams, and every one of those is asserted here against a
/// half whose clock the test owns. The half that is really a browser -
/// the timeline one, over a real `<audio>` element - is the one the
/// timeline group drives, in wall time.
///
/// `preloads: false` is the honest answer for the composite: a
/// browser's element re-points its `src` at a boundary, which is a load
/// and a gap, so the suite asserts the degraded contract for single
/// items and the gapless one for a timeline.
class WebGaplessHarness extends AudioEngineHarness {
  WebGaplessHarness(this._timelineSrc);

  final String _timelineSrc;

  /// The fake behind each composite, so [advance] can step its clock.
  final _standards = Expando<FakeEngine>();

  /// The element behind each composite's timeline half, for the same
  /// reason: a headless runner refuses a programmatic play, so the
  /// suite moves the media clock itself.
  final _elements = Expando<web.HTMLAudioElement>();

  @override
  String get mediaUrl => '/media/stream?pid=tr-test&mt=token';

  @override
  Duration get mediaDuration => const Duration(seconds: 3);

  /// A real element interpolates its own clock, and a data URI decodes
  /// on the browser's schedule rather than the test's.
  @override
  Duration get tolerance => const Duration(milliseconds: 500);

  @override
  bool get preloads => false;

  @override
  Future<AudioEnginePort> createEngine() async {
    final engine = await createUnsilencedEngine();
    await engine.setVolume(0);
    return engine;
  }

  @override
  Future<AudioEnginePort> createUnsilencedEngine() async {
    installHlsStub(src: _timelineSrc);
    final element = web.document.createElement('audio') as web.HTMLAudioElement;
    // Muted at the element besides the level the suite sets: the
    // timeline half drives real media, and whoever runs this should not
    // have to hear it whatever a test does to the volume.
    element.muted = true;
    final standard = FakeEngine(mediaDuration: mediaDuration);
    final engine = WebGaplessEngine(
      standard,
      timeline: HlsTimelinePlayer(element: element),
    );
    _standards[engine] = standard;
    _elements[engine] = element;
    return engine;
  }

  @override
  TimelineMedia get timeline {
    const rate = 48000;
    return TimelineMedia(
      url: '/media/hls/master.m3u8?tl=conformance&rk=flac~off~0',
      mimeType: 'application/vnd.apple.mpegurl',
      durationMs: 3000,
      envelopeRate: rate,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      members: <TimelineMember>[
        for (var i = 0; i < 3; i++)
          TimelineMember(
            pid: 'tr-$i',
            offsetSamples: i * rate,
            durationSamples: rate,
          ),
      ],
    );
  }

  @override
  Future<void> loseTimeline(AudioEnginePort engine) async {
    fireHlsError(status: 410);
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  @override
  Future<void> advance(AudioEnginePort engine, Duration amount) async {
    final onTimeline =
        engine is TimelineAudioEngine && engine.loadedTimeline != null;
    if (!onTimeline) {
      // The standard half's clock is the test's, so a single item
      // advances exactly and instantly.
      _standards[engine]?.advance(amount);
      await Future<void>.delayed(Duration.zero);
      return;
    }
    if (amount <= Duration.zero) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      return;
    }
    // The timeline half is a real element, and a headless browser
    // refuses a play no gesture led to - muted or not, with no flag
    // `flutter test` will pass through. So the gesture and the clock
    // are both supplied here: what the element publishes, and what the
    // engine reads off it, is the browser's own behaviour either way.
    final element = _elements[engine]!;
    final total = engine.loadedTimeline!.durationMs;
    grantPlayback(element);
    final target = (element.currentTime * 1000).round() + amount.inMilliseconds;
    if (target >= total) {
      stepElement(element, Duration(milliseconds: total));
      endElement(element);
    } else {
      stepElement(element, Duration(milliseconds: target));
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  @override
  Future<void> disposeEngine(AudioEnginePort engine) async {
    await engine.dispose();
    removeHlsStub();
  }
}

void main() {
  runAudioEngineConformance(
    'WebGaplessEngine',
    WebGaplessHarness(silentWavDataUri()),
  );
}
