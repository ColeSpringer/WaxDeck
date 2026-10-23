import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/l10n/l10n.dart';
import 'package:waxdeck/src/player/playback_session.dart';
import 'package:waxdeck/src/player/smart_rewind.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player/waxdeck_player.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

const _trackPid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';
const _episodePid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';
const _showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';

/// What a stream only the engine makes answers while the engine is away.
const _engineAway = StreamRefusal(
  status: 503,
  code: 'feature-unavailable',
  params: <String, String>{'feature': 'streaming-engine'},
);

/// A clock a test can move without waiting.
class _Clock {
  DateTime now = DateTime.utc(2026, 10, 15, 12);

  DateTime call() => now;

  void advance(Duration by) => now = now.add(by);
}

/// A stream URL lives fifteen minutes; a long pause, a long episode, or a
/// dropped connection outlives it. The session re-mints and reloads where
/// the listener stood, and only calls the file bad when the server never
/// said otherwise.
void main() {
  late _Clock clock;
  late FakeRepository repo;
  late FakeEngine engine;
  late List<Object> failures;

  setUp(() {
    clock = _Clock();
    repo = FakeRepository(items: [testItem(_trackPid)])
      ..numberMints = true
      ..playInfoClock = clock.call
      ..playInfoLifetime = const Duration(minutes: 15);
    engine = FakeEngine(mediaDuration: const Duration(minutes: 10));
    failures = <Object>[];
  });

  Future<PlaybackSession> started({
    ItemSummary? item,
    SmartRewind rewind = SmartRewind.off,
    FakeDownloads? downloads,
    bool autoplay = true,
  }) async {
    final session = PlaybackSession(
      repository: repo,
      engine: engine,
      item: item ?? testItem(_trackPid),
      clientId: 'test',
      clock: clock.call,
      smartRewind: rewind,
      downloads: downloads,
    );
    session.sessionFailed.listen((f) => failures.add(f.error));
    addTearDown(session.dispose);
    await session.start(autoplay: autoplay);
    return session;
  }

  Future<void> settle() => pumpEventQueue();

  StreamRefusal refusal(int status, String code) =>
      StreamRefusal(status: status, code: code);

  group('a token that lapsed while paused', () {
    test('is minted again on play, at the place the listener stood', () async {
      final session = await started();
      engine.advance(const Duration(minutes: 1));
      await engine.pause();
      clock.advance(const Duration(minutes: 20));

      await session.play();
      await settle();

      expect(repo.playInfoCalls, hasLength(2));
      expect(engine.loadedUrls, hasLength(2));
      expect(engine.loadedUrl, contains('mt=2'));
      expect(engine.position, const Duration(minutes: 1));
      expect(engine.playing, isTrue);
      expect(failures, isEmpty);
    });

    test('is not reloaded while it is still good', () async {
      final session = await started();
      engine.advance(const Duration(minutes: 1));
      await engine.pause();
      clock.advance(const Duration(minutes: 5));

      await session.play();
      await settle();

      expect(repo.playInfoCalls, hasLength(1));
      expect(engine.loadedUrls, hasLength(1));
      expect(engine.playing, isTrue);
    });

    test('steps a spoken-word item back once, not twice', () async {
      final episode = testEpisode(_episodePid, durationMs: 600000);
      repo
        ..addSubscription(testShow(_showPid))
        ..episodesByShow[_showPid] = [episode];
      final session = await started(item: episode, rewind: SmartRewind.short);
      engine.advance(const Duration(minutes: 5));
      await engine.pause();
      clock.advance(const Duration(hours: 2));

      await session.play();
      await settle();

      // Two hours paused is the short ladder's ten seconds, applied to the
      // reload rather than as a seek after it.
      expect(
        engine.position,
        const Duration(minutes: 5) - const Duration(seconds: 10),
      );
      expect(engine.loadedUrls, hasLength(2));
    });
  });

  test('a device clock running fast does not reload every play', () async {
    // The server's tokens live fifteen minutes on the server's clock; a
    // device twenty minutes ahead would read every one as expired.
    final server = _Clock();
    repo.playInfoClock = server.call;
    clock.advance(const Duration(minutes: 20));
    final session = await started();
    engine.advance(const Duration(seconds: 30));
    await engine.pause();
    clock.advance(const Duration(minutes: 5));
    await session.play();
    await settle();
    expect(engine.loadedUrls, hasLength(1));

    await engine.pause();
    clock.advance(const Duration(minutes: 10));
    await session.play();
    await settle();
    expect(engine.loadedUrls, hasLength(2), reason: 'past the lifetime');
  });

  group('a stream that fails while it plays', () {
    test('is minted again and resumes where it stood', () async {
      await started();
      engine.advance(const Duration(seconds: 30));

      engine.failPlayback(refusal: refusal(401, 'unauthenticated'));
      await settle();

      expect(engine.loadedUrls, hasLength(2));
      expect(engine.loadedUrl, contains('mt=2'));
      expect(engine.position, const Duration(seconds: 30));
      expect(engine.playing, isTrue);
      expect(failures, isEmpty);
    });

    test('a connection that dropped is minted again too', () async {
      await started();
      engine.advance(const Duration(seconds: 30));
      engine.failPlayback();
      await settle();
      expect(engine.loadedUrls, hasLength(2));
      expect(engine.playing, isTrue);
    });

    test('a stream that failed while paused comes back paused', () async {
      await started();
      engine.advance(const Duration(seconds: 30));
      await engine.pause();
      engine.failPlayback();
      await settle();
      expect(engine.loadedUrls, hasLength(2));
      expect(engine.playing, isFalse);
      expect(engine.position, const Duration(seconds: 30));
    });

    test('failing again at once is tried twice, then said', () async {
      await started();
      engine.advance(const Duration(seconds: 30));
      for (var i = 0; i < 3; i++) {
        engine.failPlayback();
        await settle();
      }
      expect(engine.loadedUrls, hasLength(3), reason: 'two recoveries');
      expect(failures, hasLength(1));
      expect(failures.single, isA<MediaTrouble>());
    });

    test('recoveries are forgiven once the stream plays on', () async {
      await started();
      for (var i = 0; i < 3; i++) {
        engine.advance(const Duration(seconds: 6));
        await settle();
        engine.failPlayback();
        await settle();
      }
      expect(engine.loadedUrls, hasLength(4));
      expect(failures, isEmpty);
      expect(engine.playing, isTrue);
    });

    test('a refusal no mint cures is said in the server\'s words', () async {
      await started();
      engine.failPlayback(refusal: refusal(429, 'transcode-limited'));
      await settle();
      expect(engine.loadedUrls, hasLength(1));
      expect(repo.playInfoCalls, hasLength(1));
      final error = failures.single as WaxDeckApiException;
      expect(error.code, 'transcode-limited');
      expect(error.statusCode, 429);
    });

    test('the file itself failing is the file, minted no more', () async {
      await started();
      engine.failPlayback(fault: MediaFault.source);
      await settle();
      expect(engine.loadedUrls, hasLength(1));
      expect((failures.single as MediaTrouble).fault, MediaFault.source);
    });

    test('a downloaded file is never minted again', () async {
      repo.playInfoError = const WaxDeckApiException(
        code: 'transport-unreachable',
        message: 'offline',
      );
      await started(
        downloads: FakeDownloads(
          local: {_trackPid: testLocal('/downloads/a.flac')},
        ),
      );
      final calls = repo.playInfoCalls.length;
      engine.failPlayback();
      await settle();
      expect(repo.playInfoCalls, hasLength(calls));
      expect(failures, hasLength(1));
    });

    test('a session let go never reloads', () async {
      final session = await started();
      await session.dispose();
      engine.failPlayback();
      await settle();
      expect(engine.loadedUrls, hasLength(1));
    });

    test('a press of play during the recovery starts nothing new', () async {
      final session = await started();
      await engine.pause();
      final gate = Completer<void>();
      repo.playInfoGate = gate;
      engine.failPlayback();
      await settle();
      await session.play();
      await session.play();
      gate.complete();
      repo.playInfoGate = null;
      await settle();
      await settle();
      expect(repo.playInfoCalls, hasLength(2));
      expect(engine.loadedUrls, hasLength(2));
      expect(engine.playing, isTrue, reason: 'the press asked for sound');
    });
  });

  group('the first load', () {
    test('a stale refusal is minted again and plays', () async {
      engine
        ..failNextLoad = true
        ..loadFault = MediaFault.transport
        ..loadRefusal = refusal(401, 'unauthenticated');
      await started();
      expect(repo.playInfoCalls, hasLength(2));
      expect(engine.loadedUrls, hasLength(2));
      expect(engine.loadedUrls.last, isNot(engine.loadedUrls.first));
      expect(engine.playing, isTrue);
    });

    test('the engine being away is minted again', () async {
      engine
        ..failNextLoad = true
        ..loadFault = MediaFault.transport
        ..loadRefusal = refusal(502, 'internal');
      await started();
      expect(engine.loadedUrls, hasLength(2));
      expect(engine.playing, isTrue);
    });

    test('a stream only the engine makes, refused while it is away, is '
        'minted again', () async {
      engine
        ..failNextLoad = true
        ..loadFault = MediaFault.transport
        ..loadRefusal = _engineAway;
      await started();
      expect(repo.playInfoCalls, hasLength(2));
      expect(engine.loadedUrls, hasLength(2));
      expect(engine.playing, isTrue);
    });

    test('the engine away again after the mint is said in its words', () async {
      engine
        ..failEveryLoad = true
        ..loadFault = MediaFault.transport
        ..loadRefusal = _engineAway;
      Object? thrown;
      try {
        await started();
      } on Object catch (error) {
        thrown = error;
      }
      expect(engine.loadedUrls, hasLength(2));
      expect(
        thrown,
        isA<WaxDeckApiException>().having(
          (e) => e.params?['feature'],
          'feature',
          'streaming-engine',
        ),
      );
      final en = AppLocalizationsEn();
      expect(explainError(en, thrown!), en.errorStreamingEngine);
    });

    test('a refusal a mint cannot cure is the server\'s sentence', () async {
      engine
        ..failNextLoad = true
        ..loadFault = MediaFault.transport
        ..loadRefusal = refusal(429, 'transcode-limited');
      await expectLater(
        started(),
        throwsA(
          isA<WaxDeckApiException>().having(
            (e) => e.code,
            'code',
            'transcode-limited',
          ),
        ),
      );
      expect(repo.playInfoCalls, hasLength(1));
    });

    test('a refusal with no envelope reads as the network', () async {
      engine
        ..failNextLoad = true
        ..loadFault = MediaFault.transport
        ..loadRefusal = const StreamRefusal(status: 429);
      await expectLater(
        started(),
        throwsA(
          isA<WaxDeckApiException>()
              .having((e) => e.code, 'code', 'transport')
              .having((e) => e.statusCode, 'status', 429),
        ),
      );
    });

    test('a second failure after the re-mint is not tried again', () async {
      engine
        ..failEveryLoad = true
        ..loadFault = MediaFault.transport
        ..loadRefusal = refusal(502, 'internal');
      await expectLater(
        started(),
        throwsA(
          isA<WaxDeckApiException>().having((e) => e.statusCode, 'status', 502),
        ),
      );
      expect(engine.loadedUrls, hasLength(2));
    });

    test('a file that will not decode is not minted again', () async {
      engine
        ..failNextLoad = true
        ..loadFault = MediaFault.source;
      await expectLater(started(), throwsA(isA<MediaLoadException>()));
      expect(repo.playInfoCalls, hasLength(1));
    });
  });
}
