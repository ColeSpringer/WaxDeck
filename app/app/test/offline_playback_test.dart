import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/playback_session.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'offline_home_test.dart' show deadChannelFactory;

void main() {
  const unreachable = WaxDeckApiException(
    code: 'transport',
    message: 'network unreachable',
  );

  test('offline start plays the downloaded original from disk', () async {
    final repo = FakeRepository(items: [testItem('tr-AAA')]);
    repo.playInfoError = unreachable;
    final engine = FakeEngine();
    final session = PlaybackSession(
      repository: repo,
      engine: engine,
      item: testItem('tr-AAA'),
      clientId: 'test',
      downloads: FakeDownloads(
        local: {'tr-AAA': testLocal('/downloads/AAA.flac')},
      ),
    );
    await session.start();
    expect(engine.loadedUrl, Uri.file('/downloads/AAA.flac').toString());
    expect(engine.loadedClipStart, isNull);
    expect(engine.playing, isTrue);
    await session.dispose();
  });

  test('an offline carved track clips to its stored window', () async {
    final repo = FakeRepository(items: [testItem('tr-AAA')]);
    repo.playInfoError = unreachable;
    final engine = FakeEngine();
    final session = PlaybackSession(
      repository: repo,
      engine: engine,
      item: testItem('tr-AAA'),
      clientId: 'test',
      downloads: FakeDownloads(
        local: {
          'tr-AAA': testLocal(
            '/downloads/rip.flac',
            spanStartMs: 60000,
            spanEndMs: 240000,
          ),
        },
      ),
    );
    await session.start();
    expect(engine.loadedClipStart, const Duration(minutes: 1));
    expect(engine.loadedClipEnd, const Duration(minutes: 4));
    await session.dispose();
  });

  test('a stored open-ended window clips the start only', () async {
    final repo = FakeRepository(items: [testItem('tr-AAA')]);
    repo.playInfoError = unreachable;
    final engine = FakeEngine();
    final session = PlaybackSession(
      repository: repo,
      engine: engine,
      item: testItem('tr-AAA'),
      clientId: 'test',
      downloads: FakeDownloads(
        local: {
          'tr-AAA': testLocal(
            '/downloads/rip.flac',
            spanStartMs: 60000,
            spanEndMs: 0,
          ),
        },
      ),
    );
    await session.start();
    expect(engine.loadedClipStart, const Duration(minutes: 1));
    expect(engine.loadedClipEnd, isNull);
    await session.dispose();
  });

  test('an online direct span clips the served file to the track', () async {
    final repo = FakeRepository(items: [testItem('tr-AAA')]);
    repo.playInfoSpans['tr-AAA'] = (startMs: 1000, endMs: 2000);
    final engine = FakeEngine();
    final session = PlaybackSession(
      repository: repo,
      engine: engine,
      item: testItem('tr-AAA'),
      clientId: 'test',
    );
    await session.start();
    expect(engine.loadedClipStart, const Duration(seconds: 1));
    expect(engine.loadedClipEnd, const Duration(seconds: 2));
    expect(engine.playing, isTrue);
    await session.dispose();
  });

  test('without a download, an unreachable start propagates', () async {
    final repo = FakeRepository(items: [testItem('tr-AAA')]);
    repo.playInfoError = unreachable;
    final session = PlaybackSession(
      repository: repo,
      engine: FakeEngine(),
      item: testItem('tr-AAA'),
      clientId: 'test',
      downloads: FakeDownloads(),
    );
    await expectLater(session.start(), throwsA(unreachable));
  });

  group('offline multi-part books', () {
    const bookPid = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';

    ItemSummary bookItem({int durationMs = 180000}) => ItemSummary(
      pid: bookPid,
      mediaType: MediaType.audiobook,
      title: 'There And Back Again',
      durationMs: durationMs,
    );

    /// Three downloaded parts of one minute each, and no server.
    PlaybackSession offlineBook({
      required FakeEngine engine,
      required FakeRepository repo,
      int? initialPositionMs,
      SyncEngine? sync,
      bool durations = true,
    }) {
      // No book detail either: `books` is empty, so the config fetch
      // 404s and the session runs on the item summary, which is what an
      // offline launch actually gets.
      repo.playInfoError = unreachable;
      return PlaybackSession(
        repository: repo,
        engine: engine,
        item: bookItem(),
        clientId: 'test',
        sync: sync,
        initialPositionMs: initialPositionMs,
        downloads: FakeDownloads(
          local: {bookPid: testLocalParts(3, durations: durations)},
        ),
      );
    }

    test('a resume position inside part two loads part two', () async {
      final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
      final session = offlineBook(
        engine: engine,
        repo: FakeRepository(),
        // 90s on the book timeline: half way through the second part.
        initialPositionMs: 90000,
      );
      await session.start();

      expect(engine.loadedUrl, Uri.file('/downloads/part1.flac').toString());
      expect(engine.position, const Duration(seconds: 30));
      expect(engine.playing, isTrue);
      await session.dispose();
    });

    test('positions are checkpointed on the book timeline', () async {
      final repo = FakeRepository();
      final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
      final session = offlineBook(
        engine: engine,
        repo: repo,
        initialPositionMs: 60000,
      );
      await session.start();
      engine.advance(const Duration(seconds: 5));
      await pumpEventQueue();
      await session.dispose();

      // 60s of part one plus five seconds into part two, not five
      // seconds: the part offset rides every write.
      expect(repo.putPlayStateCalls.last.positionMs, 65000);
    });

    test('a finished part rolls into the next one from disk', () async {
      final repo = FakeRepository();
      final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
      final session = offlineBook(engine: engine, repo: repo);
      await session.start();
      expect(engine.loadedUrl, Uri.file('/downloads/part0.flac').toString());

      engine.advance(const Duration(minutes: 1, seconds: 1));
      await pumpEventQueue();

      expect(engine.loadedUrl, Uri.file('/downloads/part1.flac').toString());
      expect(engine.playing, isTrue);
      expect(engine.position, Duration.zero);
      // The boundary checkpoint is where part two begins on the book
      // timeline, not zero.
      expect(repo.putPlayStateCalls.last.positionMs, 60000);
      await session.dispose();
    });

    test('a seek out of the loaded part loads the part holding it', () async {
      final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
      final session = offlineBook(engine: engine, repo: FakeRepository());
      await session.start();

      await session.seek(const Duration(seconds: 150));

      expect(engine.loadedUrl, Uri.file('/downloads/part2.flac').toString());
      expect(engine.position, const Duration(seconds: 30));
      await session.dispose();
    });

    test('the item is over only when the last part runs out', () async {
      final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
      final session = offlineBook(
        engine: engine,
        repo: FakeRepository(),
        initialPositionMs: 120000,
      );
      var completions = 0;
      session.sessionCompleted.listen((_) => completions++);
      await session.start();
      expect(engine.loadedUrl, Uri.file('/downloads/part2.flac').toString());

      engine.advance(const Duration(minutes: 1, seconds: 1));
      await pumpEventQueue();

      expect(completions, 1, reason: 'the last part ending ends the book');
      await session.dispose();
    });

    test('parts with no stored durations play the first file only', () async {
      // Records written before download-info carried durations: the parts
      // cannot be placed on the timeline, so this behaves as it did then
      // rather than resuming somewhere invented.
      final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
      final session = offlineBook(
        engine: engine,
        repo: FakeRepository(),
        initialPositionMs: 90000,
        durations: false,
      );
      await session.start();

      expect(engine.loadedUrl, Uri.file('/downloads/part0.flac').toString());
      engine.advance(const Duration(minutes: 1, seconds: 1));
      await pumpEventQueue();
      expect(
        engine.loadedUrl,
        Uri.file('/downloads/part0.flac').toString(),
        reason: 'nothing rolls forward without offsets to roll to',
      );
      await session.dispose();
    });

    test(
      'a seek across parts falls back to disk when the server went',
      () async {
        // A book is listened to for hours, so the server goes away mid-read
        // more often here than anywhere else. Every way of crossing a
        // boundary has to survive it, not just the roll off the end of a
        // part: three of `seek`'s callers do not await it, so an escaping
        // exception would be an unhandled async error rather than a failure
        // anyone sees.
        final repo = FakeRepository()
          ..books[bookPid] = testBook(
            bookPid,
            durationMs: 180000,
            partCount: 3,
          );
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = PlaybackSession(
          repository: repo,
          engine: engine,
          item: bookItem(),
          clientId: 'test',
          downloads: FakeDownloads(local: {bookPid: testLocalParts(3)}),
        );
        await session.start();
        expect(engine.loadedUrl, contains('part=0'));

        repo.playInfoError = unreachable;
        await session.seek(const Duration(seconds: 150));

        expect(engine.loadedUrl, Uri.file('/downloads/part2.flac').toString());
        expect(engine.position, const Duration(seconds: 30));
        await session.dispose();
      },
    );

    test('repeat-one goes back to part one with no server', () async {
      // `replay` seeks to zero, which for a book on its last part is a
      // crossing like any other.
      final repo = FakeRepository()
        ..books[bookPid] = testBook(bookPid, durationMs: 180000, partCount: 3);
      final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
      final session = PlaybackSession(
        repository: repo,
        engine: engine,
        item: bookItem(),
        clientId: 'test',
        initialPositionMs: 120000,
        downloads: FakeDownloads(local: {bookPid: testLocalParts(3)}),
      );
      await session.start();
      expect(engine.loadedUrl, contains('part=2'));

      repo.playInfoError = unreachable;
      await session.replay();

      expect(engine.loadedUrl, Uri.file('/downloads/part0.flac').toString());
      expect(engine.playing, isTrue);
      await session.dispose();
    });

    test('a crossing with nothing downloaded reports the failure', () async {
      // The fallback is not a swallow: with no local parts the exception
      // reaches the caller, which is what lets `start`'s own offline
      // branch decide what to do about those.
      final repo = FakeRepository()
        ..books[bookPid] = testBook(bookPid, durationMs: 180000, partCount: 3);
      final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
      final session = PlaybackSession(
        repository: repo,
        engine: engine,
        item: bookItem(),
        clientId: 'test',
        downloads: FakeDownloads(),
      );
      await session.start();

      repo.playInfoError = unreachable;
      await expectLater(
        session.seek(const Duration(seconds: 150)),
        throwsA(unreachable),
      );
      await session.dispose();
    });

    test(
      'a book that loses the server mid-read carries on from disk',
      () async {
        final repo = FakeRepository()
          ..books[bookPid] = testBook(
            bookPid,
            durationMs: 180000,
            partCount: 3,
          );
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = PlaybackSession(
          repository: repo,
          engine: engine,
          item: bookItem(),
          clientId: 'test',
          downloads: FakeDownloads(local: {bookPid: testLocalParts(3)}),
        );
        await session.start();
        expect(engine.loadedUrl, contains('part=0'));

        // The train enters the tunnel, then part one ends.
        repo.playInfoError = unreachable;
        engine.advance(const Duration(minutes: 1, seconds: 1));
        await pumpEventQueue();

        expect(engine.loadedUrl, Uri.file('/downloads/part1.flac').toString());
        expect(engine.playing, isTrue);
        await session.dispose();
      },
    );
  });

  test('failed checkpoints and listens queue in the outbox', () async {
    final db = inMemoryMirrorDatabase();
    final repo = FakeRepository(items: [testItem('tr-AAA')]);
    final sync = SyncEngine(
      db: db,
      repository: repo,
      channelFactory: deadChannelFactory(),
    );
    addTearDown(() async {
      sync.dispose();
      await db.close();
    });

    final engine = FakeEngine();
    final session = PlaybackSession(
      repository: repo,
      engine: engine,
      item: testItem('tr-AAA'),
      clientId: 'test',
      sync: sync,
      downloads: FakeDownloads(
        local: {'tr-AAA': testLocal('/downloads/AAA.flac')},
      ),
    );
    repo.playInfoError = unreachable;
    await session.start();

    // Playback progresses; the server rejects every write like a dead
    // network would.
    repo.putPlayStateError = unreachable;
    repo.reportError = unreachable;
    for (var i = 0; i < 6; i++) {
      engine.advance(const Duration(seconds: 1));
      await pumpEventQueue();
    }
    await session.dispose();

    final queued = await db.select(db.outboxMutations).get();
    expect(queued, hasLength(1), reason: 'checkpoints coalesce per item');
    expect(queued.single.kind, 'position');
    expect(queued.single.pid, 'tr-AAA');
    final listens = await db.select(db.outboxListens).get();
    expect(listens, hasLength(1));
    expect(listens.single.pid, 'tr-AAA');
    expect(listens.single.msPlayed, greaterThan(0));
  });
}
