import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/playback_session.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

const _trackPid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';
const _episodePid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';
const _showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
const _bookPid = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';

/// A stream the server re-encodes answers no range requests. An engine
/// that plays HLS (ExoPlayer, mpv) asks for it as the item's own HLS
/// presentation instead, which it seeks itself: no cut is ever minted for
/// it, and silence trimming jumps. The browser's element plays no HLS, so
/// the web keeps the cut.
void main() {
  late FakeRepository repo;
  late FakeEngine engine;

  setUp(() {
    repo = FakeRepository(items: [testItem(_trackPid)])
      ..transcodedPids.add(_trackPid);
    engine = FakeEngine(mediaDuration: const Duration(milliseconds: 214000))
      ..buffered = const Duration(seconds: 10);
  });

  Future<PlaybackSession> started({
    ItemSummary? item,
    int? initialPositionMs = 0,
  }) async {
    final session = PlaybackSession(
      repository: repo,
      engine: engine,
      item: item ?? testItem(_trackPid),
      clientId: 'test',
      initialPositionMs: initialPositionMs,
    );
    addTearDown(session.dispose);
    await session.start();
    return session;
  }

  Future<void> settle() => pumpEventQueue();

  group('an engine that plays HLS', () {
    setUp(() {
      engine
        ..playsHls = true
        // ExoPlayer: a live encode restarts from its head on any seek.
        ..seeksWithinUnrangedStream = false;
    });

    test('is handed a re-encode as a presentation and seeks it', () async {
      final session = await started();
      expect(repo.playInfoHls, [true]);
      expect(engine.loadedUrl, contains('/media/hls/master.m3u8'));

      expect(await session.seek(const Duration(milliseconds: 90500)), isTrue);
      expect(repo.playInfoCalls, hasLength(1), reason: 'nothing to cut');
      expect(engine.loadedUrls, hasLength(1));
      expect(engine.seekCalls.last, const Duration(milliseconds: 90500));
      expect(session.displayPosition, const Duration(milliseconds: 90500));

      await session.seek(const Duration(seconds: 20));
      expect(repo.playInfoCalls, hasLength(1));
      expect(engine.seekCalls.last, const Duration(seconds: 20));
    });

    test('resumes inside it with one mint and no cut', () async {
      repo.playPositions[_trackPid] = 90000;
      final session = await started(initialPositionMs: null);
      expect(repo.playInfoCalls, hasLength(1));
      expect(engine.loadedUrl, isNot(contains('&t=')));
      expect(engine.position, const Duration(seconds: 90));
      expect(session.displayPosition, const Duration(seconds: 90));
    });

    test('jumps a silence in it without a mint', () async {
      final episode = testEpisode(_episodePid, durationMs: 600000);
      repo
        ..addSubscription(
          testShow(_showPid),
          settings: const SubscriptionSettings(trimSilence: true),
        )
        ..episodesByShow[_showPid] = [episode]
        ..voiceBoostPids.add(_episodePid)
        ..skipMaps[_episodePid] = const SkipMap(
          state: 'ready',
          spans: [SkipSpan(startMs: 2000, endMs: 6000)],
        );
      engine.mediaDuration = const Duration(milliseconds: 600000);
      final session = await started(item: episode);
      await settle();
      for (var i = 0; i < 3; i++) {
        engine.advance(const Duration(seconds: 1));
        await settle();
      }
      expect(engine.seekCalls, contains(const Duration(milliseconds: 6000)));
      expect(repo.playInfoCalls, hasLength(1));
      expect(engine.loadedUrls, hasLength(1));
      expect(
        session.displayPosition,
        greaterThanOrEqualTo(const Duration(seconds: 6)),
      );
    });

    test('asks for each part of a book as a presentation', () async {
      repo
        ..books[_bookPid] = testBook(
          _bookPid,
          durationMs: 1200000,
          partCount: 2,
        )
        ..voiceBoostPids.add(_bookPid);
      engine.mediaDuration = const Duration(milliseconds: 600000);
      final session = await started(
        item: testItem(
          _bookPid,
          mediaType: MediaType.audiobook,
          durationMs: 1200000,
        ),
      );
      expect(repo.playInfoHls, everyElement(isTrue));
      expect(engine.loadedUrl, contains('/media/hls/master.m3u8'));
      final mints = repo.playInfoCalls.length;

      await session.seek(const Duration(seconds: 300));
      expect(repo.playInfoCalls, hasLength(mints), reason: 'inside the part');
      expect(engine.seekCalls.last, const Duration(seconds: 300));

      await session.seek(const Duration(seconds: 700));
      expect(repo.playInfoCalls, hasLength(mints + 1), reason: 'the next part');
      expect(repo.playInfoHls.last, isTrue);
      expect(engine.loadedUrl, isNot(contains('&t=')));
    });

    test('keeps the cut where the server renders no HLS', () async {
      repo.rendersHls = false;
      final session = await started();
      await session.seek(const Duration(seconds: 90));
      expect(repo.playInfoCalls, hasLength(2));
      expect(engine.loadedUrl, contains('&t=90'));
      expect(session.displayPosition, const Duration(seconds: 90));
    });
  });

  test('the web keeps cutting: it never asks for HLS', () async {
    final session = await started();
    expect(repo.playInfoHls, [null]);
    await session.seek(const Duration(seconds: 90));
    expect(repo.playInfoHls, [null, null]);
    expect(engine.loadedUrl, contains('&t=90'));
    expect(session.displayPosition, const Duration(seconds: 90));
  });
}
