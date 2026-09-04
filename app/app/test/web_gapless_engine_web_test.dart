@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_player/waxdeck_player.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:web/web.dart' as web;

import 'hls_stub.dart';

/// The composite engine: which half owns the sound, and what the
/// surfaces watching it are told while it changes hands.
///
/// The standard half is the deterministic fake rather than just_audio,
/// because what is under test here is the composition - the silencing,
/// the routing, the merged streams - and a real backend would only make
/// those answers slower and less exact. The conformance suite runs the
/// real pairing.
void main() {
  late FakeEngine standard;
  late web.HTMLAudioElement element;
  late WebGaplessEngine engine;

  TimelineMedia media() {
    const rate = 48000;
    return TimelineMedia(
      url: '/media/hls/master.m3u8?tl=a&rk=flac~off~0',
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

  setUp(() {
    installHlsStub(src: silentWavDataUri());
    standard = FakeEngine(mediaDuration: const Duration(seconds: 3));
    element = web.document.createElement('audio') as web.HTMLAudioElement;
    element.muted = true;
    engine = WebGaplessEngine(
      standard,
      timeline: HlsTimelinePlayer(element: element),
    );
  });

  tearDown(() async {
    await engine.dispose();
    removeHlsStub();
  });

  test('a single item plays on the standard half', () async {
    await engine.load('/media/stream?pid=tr-1&mt=t', mimeType: 'audio/flac');

    expect(standard.loadedUrl, '/media/stream?pid=tr-1&mt=t');
    expect(engine.loadedTimeline, isNull);
    expect(element.src, isEmpty, reason: 'the timeline half never attached');
  });

  test('a timeline silences the standard half and takes over', () async {
    await engine.load('/media/stream?pid=tr-1&mt=t');
    await engine.play();
    expect(standard.playing, isTrue);

    await engine.loadTimeline(media(), member: 1);

    expect(standard.playing, isFalse, reason: 'one half makes sound at a time');
    expect(standard.processingState, EngineProcessingState.idle);
    expect(engine.loadedTimeline, isNotNull);
    expect(engine.currentMember, 1);
    expect(engine.duration, const Duration(seconds: 1));
  });

  test('a single item after a timeline silences the timeline half', () async {
    await engine.loadTimeline(media());
    await engine.load('/media/stream?pid=tr-9&mt=t');

    expect(engine.loadedTimeline, isNull);
    expect(standard.loadedUrl, '/media/stream?pid=tr-9&mt=t');
    expect(element.paused, isTrue);
  });

  test('a member is only reported while a timeline is playing', () async {
    await engine.loadTimeline(media(), member: 2);
    expect(engine.currentMember, 2);

    await engine.load('/media/stream?pid=tr-9&mt=t');

    // The port describes these two as a pair, and a reader that trusts
    // one has to be able to trust the other: a stale member beside a
    // null timeline is a member of nothing.
    expect(engine.loadedTimeline, isNull);
    expect(engine.currentMember, 0);

    // And a seek into a member goes nowhere while the other half has
    // the sound, rather than moving a silent element.
    final before = element.currentTime;
    await engine.seekToMember(1, Duration.zero);
    expect(element.currentTime, before);
  });

  test('a surface that watches twice watches the same stream', () async {
    // Built once and held, not merged afresh on every read. Every
    // surface that draws playback passes these into a `StreamBuilder`
    // inside `build`, so a getter that answered a new stream each time
    // handed every rebuild two new upstream subscriptions - and the
    // merge replays nothing, so each of those started blank.
    expect(identical(engine.positionStream, engine.positionStream), isTrue);
    expect(identical(engine.playingStream, engine.playingStream), isTrue);
    expect(identical(engine.itemBoundary, engine.itemBoundary), isTrue);
    expect(identical(engine.timelineLost, engine.timelineLost), isTrue);
  });

  test('the surfaces watching hear only the half that is playing', () async {
    final positions = <Duration>[];
    final sub = engine.positionStream.listen(positions.add);
    addTearDown(sub.cancel);

    await engine.load('/media/stream?pid=tr-1&mt=t');
    await engine.play();
    standard.advance(const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);
    expect(positions, isNotEmpty);

    // Once the timeline half owns the sound, the standard half's ticks
    // are somebody else's: a surface drawing them would show a position
    // from media nobody can hear.
    await engine.loadTimeline(media());
    // The load's own seeks reach the element on the browser's event
    // loop rather than on a microtask, so what they publish is drained
    // before the assertion rather than counted by it.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    positions.clear();

    // Driven behind the composite's back, which is what a half that was
    // silenced but not disposed can still do.
    await standard.load('/media/stream?pid=tr-1&mt=t');
    await standard.play();
    standard.advance(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(positions, isEmpty);
  });

  test('the level and the speed survive the switch', () async {
    await engine.setVolume(0.4);
    await engine.setSpeed(1.5);

    await engine.loadTimeline(media());
    expect(engine.volume, closeTo(0.4, 0.001));
    expect(engine.speed, closeTo(1.5, 0.001));

    await engine.load('/media/stream?pid=tr-1&mt=t');
    expect(engine.volume, closeTo(0.4, 0.001));
    expect(engine.speed, closeTo(1.5, 0.001));
  });

  test('the level is replayed to a surface built after it moved', () async {
    await engine.setVolume(0.25);
    expect(await engine.volumeStream.first, closeTo(0.25, 0.001));
  });

  test('the formats offered are the ones this browser can decode', () {
    // Non-empty is the assertion that matters. The list is asked for at
    // the mint, before hls.js has been fetched, and an empty one lets
    // the server fall back to its own ladder - which is AAC, the one
    // format a Chromium without the proprietary codecs cannot play. A
    // browser that could decode none of them would be caught here too,
    // and there is none.
    expect(engine.supportedTimelineFormats, isNotEmpty);
    expect(
      engine.supportedTimelineFormats,
      everyElement(isIn(<String>['flac', 'alac', 'opus', 'aac'])),
    );
    // Lossless first: a lossy re-encode of a lossless library is a loss
    // nobody asked for, and bandwidth on a LAN is not the scarce thing.
    expect(engine.supportedTimelineFormats.first, isNot('aac'));

    // And answered without hls.js on the page, which is where the mint
    // asks: the script is fetched by the load this answer causes.
    removeHlsStub();
    expect(engine.supportedTimelineFormats, isNotEmpty);
  });
}
