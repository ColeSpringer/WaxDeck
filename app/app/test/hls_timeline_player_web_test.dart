@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_player/waxdeck_player.dart';
import 'package:web/web.dart' as web;

import 'hls_stub.dart';

/// The timeline engine against a real `<audio>` element.
///
/// hls.js is stubbed - a browser suite has no server to fetch fragments
/// from - but the element is the browser's own: `currentTime`, `seeked`,
/// `ended`, and the autoplay policy all behave the way they will in
/// front of a listener. What is under test is the arithmetic between
/// them: which member a position names, what is announced when playback
/// crosses a seam, and which server answers mean mint again rather than
/// give up.
void main() {
  late web.HTMLAudioElement element;
  late HlsTimelinePlayer engine;

  /// Three one-second members over the three seconds of silence the
  /// stub attaches, at the rate the mint reports in samples.
  TimelineMedia media({
    String url = '/media/hls/master.m3u8?tl=a&rk=flac~off~0',
  }) {
    const rate = 48000;
    return TimelineMedia(
      url: url,
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

  /// Polls until [test] holds, so a wait is for the thing rather than
  /// for a duration somebody guessed.
  Future<void> waitFor(
    bool Function() test, {
    Duration timeout = const Duration(seconds: 10),
    String what = 'the condition',
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (test()) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    fail('timed out waiting for $what');
  }

  setUp(() {
    installHlsStub(src: silentWavDataUri());
    element = web.document.createElement('audio') as web.HTMLAudioElement;
    element.muted = true;
    engine = HlsTimelinePlayer(element: element);
  });

  tearDown(() async {
    await engine.dispose();
    removeHlsStub();
  });

  test('a load lands on the member it was asked for', () async {
    final tl = media();
    await engine.loadTimeline(tl, member: 1);

    expect(engine.loadedTimeline?.url, tl.url);
    expect(engine.currentMember, 1);
    expect(engine.processingState, EngineProcessingState.ready);
    expect(engine.duration, const Duration(seconds: 1));
    expect(element.currentTime, closeTo(1.0, 0.2));
    // No window to fill: the next member is already in the stream.
    expect(engine.canPreload, isFalse);
  });

  test('a start no gesture led to is refused rather than failed', () async {
    final refusals = <Object>[];
    final r = engine.playbackRefused.listen(refusals.add);
    addTearDown(r.cancel);

    await engine.loadTimeline(media());
    // The headless runner has no interaction behind this, which is the
    // same answer a browser gives a Connect handoff or a restored queue
    // put back into play. The media stays where it is; only the start
    // was turned down.
    await engine.play();
    await waitFor(() => refusals.isNotEmpty, what: 'the refusal to arrive');

    expect(engine.loadedTimeline, isNotNull);
    expect(engine.currentMember, 0);
  });

  test(
    'crossing a seam announces the new member before the crossing',
    () async {
      final tl = media();
      final order = <String>[];
      final d = engine.durationStream.listen((_) => order.add('duration'));
      final b = engine.itemBoundary.listen((_) => order.add('boundary'));
      addTearDown(() async {
        await d.cancel();
        await b.cancel();
      });

      await engine.loadTimeline(tl);
      order.clear();
      grantPlayback(element);
      stepElement(element, const Duration(milliseconds: 1200));
      await waitFor(
        () => engine.currentMember >= 1,
        what: 'playback to cross the first seam',
      );

      expect(order, contains('boundary'));
      expect(
        order.indexOf('duration'),
        lessThan(order.indexOf('boundary')),
        reason: 'the new member reads true before anything is told it changed',
      );
      expect(engine.playing, isTrue, reason: 'a seam does not stop playback');
      expect(engine.position, const Duration(milliseconds: 200));
    },
  );

  test('a member shorter than a tick still crosses once', () async {
    final tl = media();
    var crossings = 0;
    final b = engine.itemBoundary.listen((_) => crossings++);
    addTearDown(b.cancel);

    await engine.loadTimeline(tl);
    grantPlayback(element);
    // Two seams inside one step. One crossing is announced and the
    // member read is the one actually playing, which is what the caller
    // resyncs from.
    stepElement(element, const Duration(milliseconds: 2400));
    await waitFor(() => crossings > 0, what: 'the crossing');

    expect(crossings, 1);
    expect(engine.currentMember, 2);
  });

  test('seekToMember moves without announcing a crossing', () async {
    final tl = media();
    await engine.loadTimeline(tl);
    var crossings = 0;
    final b = engine.itemBoundary.listen((_) => crossings++);
    addTearDown(b.cancel);

    await engine.seekToMember(2, const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(engine.currentMember, 2);
    expect(element.currentTime, closeTo(2.2, 0.2));
    expect(crossings, 0, reason: 'nothing played its way over');
  });

  test('running off the end of the last member ends the queue', () async {
    final tl = media();
    var ended = 0;
    final c = engine.completed.listen((_) => ended++);
    addTearDown(c.cancel);

    await engine.loadTimeline(
      tl,
      member: 2,
      position: const Duration(milliseconds: 600),
    );
    grantPlayback(element);
    endElement(element);
    await waitFor(() => ended > 0, what: 'the stream to run out');

    expect(engine.processingState, EngineProcessingState.completed);
    expect(engine.playing, isFalse);
  });

  test('a fetch the server will not answer means mint again', () async {
    var lost = 0;
    final l = engine.timelineLost.listen((_) => lost++);
    addTearDown(l.cancel);

    await engine.loadTimeline(media());
    grantPlayback(element);
    fireHlsError(status: 404);
    await waitFor(() => lost == 1, what: 'the timeline to be given up on');

    expect(engine.playing, isFalse);
  });

  test('a loss says whether it was playing when it happened', () async {
    final losses = <bool>[];
    final l = engine.timelineLost.listen(losses.add);
    addTearDown(l.cancel);

    await engine.loadTimeline(media());
    grantPlayback(element);
    fireHlsError(status: 404);
    await waitFor(() => losses.isNotEmpty, what: 'the loss to be announced');

    // Silencing the stream is part of losing it, so `playing` reads
    // false by the time anybody hears about it: a recovery that
    // consulted the engine would bring the music back stopped.
    expect(losses, <bool>[true]);
    expect(engine.playing, isFalse);
  });

  test(
    'a fetch refused before anything plays fails the load at once',
    () async {
      // Not after the load deadline. The refusal is known at the first
      // fetch, and fifteen seconds of a spinner over an answer the server
      // already gave is fifteen seconds of nothing, ending in a timeout
      // that reads as transport trouble rather than as the cap.
      final codes = <String>[];
      final r = engine.timelineRefused.listen(codes.add);
      addTearDown(r.cancel);

      // No media attached, so nothing answers the load but the error:
      // what a fetch refused at the very first request looks like.
      setStubStalled(true);
      forgetHlsPlayer();
      addTearDown(() => setStubStalled(false));
      final loading = engine.loadTimeline(media());
      await waitFor(hlsPlayerExists, what: 'the player to be constructed');
      fireHlsError(status: 429);

      await expectLater(loading, throwsA(isA<MediaLoadException>()));
      expect(codes, <String>['transcode-limited']);
    },
  );

  test('a fetch hls.js is still retrying does not end the stream', () async {
    var lost = 0;
    final codes = <String>[];
    final l = engine.timelineLost.listen((_) => lost++);
    final r = engine.timelineRefused.listen(codes.add);
    addTearDown(() async {
      await l.cancel();
      await r.cancel();
    });

    await engine.loadTimeline(media());
    grantPlayback(element);
    // Non-fatal is hls.js saying it has not given up: it retries eight
    // times over sixteen seconds, well inside the minute it holds
    // buffered. Tearing the stream down here is a re-mint, a transcode
    // slot and an audible reload over a fetch that would have been made
    // good.
    fireHlsError(status: 404, fatal: false);
    fireHlsError(status: 429, fatal: false);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(lost, 0);
    expect(codes, isEmpty);
    expect(engine.loadedTimeline, isNotNull);
  });

  test('a refused fetch is reported rather than recovered from', () async {
    final codes = <String>[];
    final r = engine.timelineRefused.listen(codes.add);
    var lost = 0;
    final l = engine.timelineLost.listen((_) => lost++);
    addTearDown(() async {
      await r.cancel();
      await l.cancel();
    });

    await engine.loadTimeline(media());
    grantPlayback(element);
    fireHlsError(status: 429);
    await waitFor(() => codes.isNotEmpty, what: 'the refusal to be published');

    expect(codes, <String>['transcode-limited']);
    expect(lost, 0, reason: 're-minting does not get past a session cap');
  });

  test(
    'a browser with no media source refuses the whole arrangement',
    () async {
      setStubMseSupported(false);
      // Read through the same channel the engine reads, so the stub's
      // answer is what is being asserted on rather than a Dart flag.
      expect(
        (globalContext['Hls'] as JSObject)
            .callMethod<JSBoolean>('isMSESupported'.toJS)
            .toDart,
        isFalse,
      );

      await expectLater(
        engine.loadTimeline(media()),
        throwsA(isA<MediaLoadException>()),
      );
      expect(engine.loadedTimeline, isNull);
    },
  );

  test('the same stream loaded again is a seek, not a reload', () async {
    final tl = media();
    await engine.loadTimeline(tl);
    final attached = element.src;

    await engine.loadTimeline(
      media(url: tl.url),
      member: 2,
      position: const Duration(milliseconds: 400),
    );

    expect(element.src, attached, reason: 'nothing was re-attached');
    expect(engine.currentMember, 2);
    expect(element.currentTime, closeTo(2.4, 0.2));
  });
}
