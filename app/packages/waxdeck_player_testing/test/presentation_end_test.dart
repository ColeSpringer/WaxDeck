import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

import 'scripted_platform.dart';

/// An HLS presentation's length is its playlist's, exact. mpv hands HLS to
/// libavformat, which steps over a segment it cannot fetch (a refusal, an
/// engine with no slot free) instead of failing, then plays what it had
/// and ends: the platform calls the item over well short of its length.
/// That is a failure the listener has to hear about, never the end of the
/// item. A progressive stream's length is an estimate, so it is left
/// alone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScriptedPlatform platform;
  setUp(() => JustAudioPlatform.instance = platform = ScriptedPlatform());

  const presentation = 'http://x/media/hls/master.m3u8?it=k&mt=t';

  JustAudioEngine engineAsking([StreamAsk? ask]) => scriptedEngine(
    ask: ask ?? answering(const ProbeAnswer(StreamProbe.answered)),
  );

  // The ScriptedPlayer reports three minutes for whatever it loads.
  const length = Duration(minutes: 3);

  /// Plays [url] to the platform's end. [reached] is the last position it
  /// reports and [read] how far it says it had read by then; [runOn] is
  /// how long it keeps playing before the end arrives. The media_kit
  /// bridge zeroes the position as it completes ([endPosition] zero);
  /// ExoPlayer reports where it ended.
  Future<({List<void> completions, List<MediaFailure> failures})> playToAnEnd(
    JustAudioEngine engine,
    String url, {
    required Duration reached,
    Duration? read,
    Duration runOn = Duration.zero,
    Duration endPosition = Duration.zero,
    ProcessingStateMessage lastState = ProcessingStateMessage.ready,
  }) async {
    final completions = <void>[];
    final failures = <MediaFailure>[];
    engine.completed.listen(completions.add);
    engine.mediaFailed.listen(failures.add);
    await engine.load(url);
    await engine.play();
    await settle();
    platform.player.emit(
      state: lastState,
      position: reached,
      buffered: read ?? reached,
    );
    await Future<void>.delayed(runOn + const Duration(milliseconds: 20));
    platform.player.emit(
      state: ProcessingStateMessage.completed,
      position: endPosition,
    );
    await settle();
    return (completions: completions, failures: failures);
  }

  test('a presentation that ends well short of its length fails', () async {
    final engine = engineAsking();
    final shown = <EngineProcessingState>[];
    engine.processingStateStream.listen(shown.add);
    final seen = await playToAnEnd(
      engine,
      presentation,
      reached: const Duration(seconds: 8),
      runOn: const Duration(milliseconds: 150),
    );

    expect(seen.completions, isEmpty, reason: 'it did not end');
    expect(seen.failures, hasLength(1));
    expect(seen.failures.single.fault, MediaFault.transport);
    expect(seen.failures.single.wasPlaying, isTrue);
    expect(engine.playing, isFalse);
    expect(engine.processingState, isNot(EngineProcessingState.completed));
    expect(shown, isNot(contains(EngineProcessingState.completed)));
    // Where it got to stands, so a recovery picks up there: the last
    // position reported, run on to the end.
    expect(engine.position.inMilliseconds, inInclusiveRange(8150, 8500));
  });

  test('the refusal the presentation met rides along', () async {
    final engine = engineAsking(
      answering(
        const ProbeAnswer(
          StreamProbe.unreachable,
          StreamRefusal(status: 429, code: 'transcode-limited'),
        ),
      ),
    );
    final seen = await playToAnEnd(
      engine,
      presentation,
      reached: const Duration(seconds: 8),
    );
    expect(seen.failures.single.refusal?.code, 'transcode-limited');
  });

  test('a presentation that ends at its length completes', () async {
    final engine = engineAsking();
    final seen = await playToAnEnd(
      engine,
      presentation,
      reached: length - const Duration(milliseconds: 100),
    );
    expect(seen.completions, hasLength(1));
    expect(seen.failures, isEmpty);
  });

  test('an end the output was still draining completes', () async {
    // mpv raises its end as the decoder runs dry, while the output still
    // holds its buffer: the position it last reports is what was heard,
    // behind the end by the speed times the output's delay. What it had
    // read is the end.
    final engine = engineAsking();
    final seen = await playToAnEnd(
      engine,
      presentation,
      reached: length - const Duration(milliseconds: 2500),
      read: length,
      lastState: ProcessingStateMessage.buffering,
    );
    expect(seen.completions, hasLength(1));
    expect(seen.failures, isEmpty);
  });

  test('stepped-over segments fail whatever the output still held', () async {
    final engine = engineAsking();
    final seen = await playToAnEnd(
      engine,
      presentation,
      reached: const Duration(seconds: 7),
      read: const Duration(seconds: 8),
      lastState: ProcessingStateMessage.buffering,
    );
    expect(seen.completions, isEmpty);
    expect(seen.failures, hasLength(1));
  });

  test('the bridge repeating its end is one end', () async {
    // After its end media_kit raises a second end-state event at position
    // zero, and more as the output drains: none of them is a failure.
    final engine = engineAsking();
    final seen = await playToAnEnd(
      engine,
      presentation,
      reached: length - const Duration(milliseconds: 100),
      read: length,
    );
    platform.player.emit(state: ProcessingStateMessage.completed);
    await settle();
    platform.player.emit(state: ProcessingStateMessage.completed);
    await settle();
    expect(seen.completions, hasLength(1));
    expect(seen.failures, isEmpty);
  });

  test('an end the platform reports at its length completes', () async {
    // ExoPlayer: its last event before the end can be far behind, but
    // the end itself says where it stopped.
    final engine = engineAsking();
    final seen = await playToAnEnd(
      engine,
      presentation,
      reached: const Duration(seconds: 2),
      endPosition: length,
    );
    expect(seen.completions, hasLength(1));
    expect(seen.failures, isEmpty);
  });

  test('a progressive stream ending short is left to complete', () async {
    // A live encode's length is an estimate, and a VBR file's can be off
    // by more than any slack worth having.
    final engine = engineAsking();
    final seen = await playToAnEnd(
      engine,
      'http://x/media/stream?pid=tr-1&mt=t',
      reached: const Duration(seconds: 8),
    );
    expect(seen.completions, hasLength(1));
    expect(seen.failures, isEmpty);
  });

  test('a play after it ended short resumes where it got to', () async {
    final engine = engineAsking();
    await playToAnEnd(
      engine,
      presentation,
      reached: const Duration(seconds: 8),
    );
    final held = engine.position;
    await engine.play();
    await settle();
    final asked = [
      ...platform.players.expand((p) => p.seeks),
      ...platform.players.expand((p) => p.loadStarts),
    ];
    expect(asked, contains(held), reason: 'not from the top');
  });

  test('an end still being probed is not announced once stopped', () async {
    final probe = Completer<ProbeAnswer>();
    final engine = engineAsking((_, {segmentAt}) => probe.future);
    final seen = await playToAnEnd(
      engine,
      presentation,
      reached: const Duration(seconds: 8),
    );
    await engine.stop();
    probe.complete(ProbeAnswer.unreachable);
    await settle();
    expect(seen.failures, isEmpty);
    expect(seen.completions, isEmpty);
  });

  test('an end that lands while the presentation is loading is not its '
      'end', () async {
    // mpv can raise its end of an all-refused presentation before the
    // load that opened it has settled: the load is what answers then.
    final engine = engineAsking();
    final completions = <void>[];
    final failures = <MediaFailure>[];
    engine.completed.listen(completions.add);
    engine.mediaFailed.listen(failures.add);
    await engine.load(presentation);
    await engine.play();
    await settle();
    final gate = Completer<void>();
    platform.loadGate = gate;
    final reload = engine.load(
      presentation,
      initialPosition: const Duration(seconds: 8),
    );
    await settle();
    platform.player.emit(state: ProcessingStateMessage.completed);
    await settle();
    expect(completions, isEmpty);
    expect(engine.processingState, isNot(EngineProcessingState.completed));

    gate.complete();
    await reload;
    await settle();
    expect(completions, isEmpty, reason: 'the load answered ready');
    expect(failures, isEmpty);
  });

  test('the next load starts clean', () async {
    final engine = engineAsking();
    await playToAnEnd(
      engine,
      presentation,
      reached: const Duration(seconds: 8),
    );
    await engine.load(presentation);
    platform.player.emit(position: const Duration(seconds: 3));
    await settle();
    expect(engine.processingState, EngineProcessingState.ready);
    expect(engine.position, const Duration(seconds: 3));
  });

  group('the refusal a presentation met', () {
    // The engine's slots are taken only by segment fetches: with them all
    // held, a segment answers the busy refusal while both playlists, a
    // string build, still answer. Served over loopback the way the server
    // hands an item's rendering out.
    Future<({String url, List<String> asked})> serve({
      required int refuseFrom,
    }) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final asked = <String>[];
      server.listen((req) async {
        final path = req.uri.path;
        asked.add(path);
        final response = req.response;
        final segment = RegExp(r'/seg/(\d+)\.m4s$').firstMatch(path);
        if (path.endsWith('/master.m3u8')) {
          response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
          );
          response.write(
            '#EXTM3U\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=160000,CODECS="opus"\n'
            'media.m3u8?c=v&mt=t\n',
          );
        } else if (path.endsWith('/media.m3u8')) {
          response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
          );
          response.write(
            '#EXTM3U\n#EXT-X-TARGETDURATION:4\n'
            '#EXT-X-MAP:URI="init.mp4?c=i&mt=t"\n'
            '${[for (var n = 0; n < 45; n++) '#EXTINF:4.000,\nseg/$n.m4s?c=s&mt=t\n'].join()}'
            '#EXT-X-ENDLIST\n',
          );
        } else if (segment != null && int.parse(segment[1]!) >= refuseFrom) {
          response.statusCode = HttpStatus.tooManyRequests;
          response.headers.contentType = ContentType.json;
          response.write(
            '{"code":"transcode-limited",'
            '"message":"the streaming engine is busy; retry shortly"}',
          );
        } else {
          response.headers.contentType = ContentType('audio', 'mp4');
          response.add(List<int>.filled(64, 0));
        }
        await response.close();
      });
      return (
        url: 'http://127.0.0.1:${server.port}/media/hls/master.m3u8?it=k&mt=t',
        asked: asked,
      );
    }

    test('is read off the segment it met, not the playlist', () async {
      // The test binding answers every HTTP request itself; this one is
      // meant for the server above.
      final mocked = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = mocked);
      final served = await serve(refuseFrom: 2);
      final engine = scriptedEngine(ask: askStream);
      final failures = <MediaFailure>[];
      engine.mediaFailed.listen(failures.add);
      await engine.load(served.url);
      await engine.play();
      await settle();
      // Played to the end of the second segment, as far as it could read:
      // the third is the one it could not fetch.
      platform.player.emit(
        position: const Duration(seconds: 7),
        buffered: const Duration(seconds: 8),
      );
      await settle();
      platform.player.fail(0, 'Source error');
      for (var i = 0; i < 100 && failures.isEmpty; i++) {
        await settle();
      }

      expect(failures.single.refusal?.code, 'transcode-limited');
      expect(failures.single.fault, MediaFault.transport);
      expect(served.asked.last, '/media/hls/seg/2.m4s');
    });
  });

  group('behind a presentation', () {
    // mpv steps over refused segments into a preloaded entry, which reads
    // as a crossing and never as the early end it is, so the desktops do
    // not preload behind one. ExoPlayer fails a refused segment instead.
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('the desktops preload nothing', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final engine = engineAsking();
      await engine.load(presentation);
      expect(engine.canPreload, isFalse);
      await engine.load('http://x/media/stream?pid=tr-1&mt=t');
      expect(engine.canPreload, isTrue, reason: 'a file is preloaded behind');
    });

    test('a presentation is known by how the platform reads it', () async {
      // just_audio reads an extension in the fragment as HLS too, which a
      // look at the URL's path never sees.
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final engine = engineAsking();
      await engine.load('http://x/media/stream?pid=tr-1&mt=t#.m3u8');
      expect(
        platform.players.expand((p) => p.loadedSources).last,
        isA<HlsAudioSourceMessage>(),
      );
      expect(engine.canPreload, isFalse);
    });

    test('Android still does', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final engine = engineAsking();
      await engine.load(presentation);
      expect(engine.canPreload, isTrue);
    });
  });
}
