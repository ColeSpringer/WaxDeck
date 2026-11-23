import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/playback_session.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player/waxdeck_player.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

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
        // Boosted: a downloaded book streams for that alone.
        final repo = FakeRepository()
          ..books[bookPid] = testBook(
            bookPid,
            durationMs: 180000,
            partCount: 3,
            settings: const BookSettings(voiceBoost: true),
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
      // crossing like any other. Boosted: a downloaded book streams for that
      // alone.
      final repo = FakeRepository()
        ..books[bookPid] = testBook(
          bookPid,
          durationMs: 180000,
          partCount: 3,
          settings: const BookSettings(voiceBoost: true),
        );
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

    test('a crossing with nothing downloaded says so and plays on', () async {
      // The fallback is not a swallow: with no local parts the failure
      // is said for the layer above to show. The part playing never
      // stopped, though, so it is not let go of: the move is what failed.
      // Not rethrown from `seek`, whose call sites are unawaited (a
      // chapter row, a bookmark, a transcript cue) - an escape there is
      // an unhandled async error and a dead tap.
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
      final failures = <Object>[];
      final moves = <Object>[];
      final sub = session.sessionFailed.listen((f) => failures.add(f.error));
      final said = session.moveFailed.listen(moves.add);
      expect(await session.seek(const Duration(seconds: 150)), isFalse);
      await pumpEventQueue();

      expect(moves, [unreachable]);
      expect(failures, isEmpty);
      expect(engine.playing, isTrue);
      // The loaded part is untouched by the refused resolve, timeline
      // state included: a checkpoint now still reads on part 0.
      expect(engine.loadedUrl, contains('part=0'));
      await sub.cancel();
      await said.cancel();
      await session.dispose();
    });

    test('a replay that cannot reach the first part starts nothing', () async {
      // Repeat-one at the end of a book is a jump back to part 0. When
      // that jump fails it is already on the error surface, and starting
      // the engine anyway would play the head of the last part under the
      // pane - and move the checkpoint the release writes there.
      final repo = FakeRepository()
        ..books[bookPid] = testBook(bookPid, durationMs: 180000, partCount: 3);
      final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
      final session = PlaybackSession(
        repository: repo,
        engine: engine,
        item: bookItem(),
        clientId: 'test',
        initialPositionMs: 120000,
        downloads: FakeDownloads(),
      );
      await session.start();
      engine.advance(const Duration(minutes: 1, seconds: 1));
      await pumpEventQueue();
      expect(engine.processingState, EngineProcessingState.completed);

      repo.playInfoError = unreachable;
      final failures = <Object>[];
      final sub = session.sessionFailed.listen((f) => failures.add(f.error));
      await session.replay();
      await pumpEventQueue();

      expect(failures, [unreachable]);
      expect(engine.playing, isFalse);
      await sub.cancel();
      await session.dispose();
    });

    test(
      'a book that loses the server mid-read carries on from disk',
      () async {
        // Boosted: a downloaded book streams for that alone.
        final repo = FakeRepository()
          ..books[bookPid] = testBook(
            bookPid,
            durationMs: 180000,
            partCount: 3,
            settings: const BookSettings(voiceBoost: true),
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

  // On the test binding's clock: a deadline is crossed by pumping to it.
  group('a start beside a download', () {
    const bookPid = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK02';
    const showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW02';
    const episodePid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0002';
    const wait = PlaybackSession.unansweredStartWait;

    const book = ItemSummary(
      pid: bookPid,
      mediaType: MediaType.audiobook,
      title: 'There And Back Again',
      durationMs: 180000,
    );

    /// The book as the server keeps it: three parts of a minute each, by
    /// default read at 1.5x and trimmed.
    BookDetail storedBook({
      BookSettings? settings = const BookSettings(
        speed: 1.5,
        trimSilence: true,
      ),
    }) =>
        testBook(bookPid, durationMs: 180000, partCount: 3, settings: settings);

    /// A silence over most of a part, on that part's own timeline.
    const silence = SkipMap(
      state: 'ready',
      spans: [SkipSpan(startMs: 1000, endMs: 50000)],
    );

    late MirrorDatabase db;

    setUp(() => db = inMemoryMirrorDatabase());
    tearDown(() => db.close());

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(Duration.zero);
      }
    }

    Future<void> mirrored(String pid, int positionMs) => db
        .into(db.mirrorPlayStates)
        .insert(
          MirrorPlayStatesCompanion.insert(
            pid: pid,
            positionMs: Value(positionMs),
          ),
        );

    /// An engine started over [factory], once its first connect has gone
    /// out. Stopped by [done], so no reconnect is left waiting on the clock.
    Future<SyncEngine> engineOver(
      WidgetTester tester,
      WaxDeckRepository repo,
      EventsChannelFactory factory,
    ) async {
      final sync = SyncEngine(
        db: db,
        repository: repo,
        channelFactory: factory,
      );
      addTearDown(sync.dispose);
      await sync.start();
      await settle(tester);
      return sync;
    }

    /// A server holding its reads behind an engine whose connects fail.
    Future<(_Holding, SyncEngine)> outOfReach(
      WidgetTester tester, {
      BookDetail? book,
    }) async {
      final repo = _Holding(book: book);
      final sync = await engineOver(tester, repo, deadChannelFactory());
      expect(sync.current.retrying, isTrue);
      return (repo, sync);
    }

    /// A server holding its reads behind a link that is down, which the
    /// test can bring back.
    Future<(_Holding, SyncEngine, FakeLink)> cutOff(
      WidgetTester tester, {
      BookDetail? book,
    }) async {
      final repo = _Holding(book: book);
      final link = FakeLink()..reachable = false;
      final sync = await engineOver(tester, repo, link.factory);
      expect(sync.current.retrying, isTrue);
      return (repo, sync, link);
    }

    /// Brings [link] back and lets the engine's next connect answer.
    Future<void> back(
      WidgetTester tester,
      SyncEngine sync,
      FakeLink link,
    ) async {
      link.reachable = true;
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(sync.current.online, isTrue);
    }

    /// A server holding its reads while the engine's first connect is out.
    Future<(_Holding, SyncEngine)> notKnown(
      WidgetTester tester, {
      BookDetail? book,
    }) async {
      final repo = _Holding(book: book);
      final sync = await engineOver(tester, repo, _heldConnects);
      expect(sync.current.retrying, isFalse);
      return (repo, sync);
    }

    PlaybackSession bookSession(
      WaxDeckRepository repo,
      SyncEngine sync,
      FakeEngine engine, {
      bool defaultTrimSilence = false,
    }) => PlaybackSession(
      repository: repo,
      engine: engine,
      item: book,
      clientId: 'test',
      sync: sync,
      defaultTrimSilence: defaultTrimSilence,
      downloads: FakeDownloads(local: {bookPid: testLocalParts(3)}),
    );

    PlaybackSession trackSession(
      WaxDeckRepository repo,
      SyncEngine sync,
      FakeEngine engine, {
      DownloadManagerPort? downloads,
    }) => PlaybackSession(
      repository: repo,
      engine: engine,
      item: testItem('tr-AAA'),
      clientId: 'test',
      sync: sync,
      downloads:
          downloads ??
          FakeDownloads(local: {'tr-AAA': testLocal('/downloads/AAA.flac')}),
    );

    /// The show as the server keeps it, subscribed, with [settings].
    void storedShow(_Holding repo, SubscriptionSettings settings) => repo
      ..addSubscription(testShow(showPid), settings: settings)
      ..episodesByShow[showPid] = [testEpisode(episodePid, showPid: showPid)];

    PlaybackSession episodeSession(
      WaxDeckRepository repo,
      SyncEngine sync,
      FakeEngine engine, {
      bool defaultVoiceBoost = false,
    }) => PlaybackSession(
      repository: repo,
      engine: engine,
      item: testEpisode(episodePid, showPid: showPid),
      clientId: 'test',
      sync: sync,
      defaultVoiceBoost: defaultVoiceBoost,
      downloads: FakeDownloads(
        local: {episodePid: testLocal('/downloads/EP.mp3')},
      ),
    );

    Future<void> done(
      WidgetTester tester,
      SyncEngine sync,
      List<PlaybackSession> sessions,
    ) async {
      for (final session in sessions) {
        await session.dispose();
      }
      await sync.stop();
      await settle(tester);
    }

    final part1 = Uri.file('/downloads/part1.flac').toString();

    group('with the server known out of reach', () {
      testWidgets('plays a downloaded track from the device at once, at the '
          'mirrored position, asking the server nothing', (tester) async {
        final (repo, sync) = await outOfReach(tester);
        await mirrored('tr-AAA', 42000);
        final engine = FakeEngine();
        final session = trackSession(repo, sync, engine);

        unawaited(session.start());
        await settle(tester);

        expect(engine.loadedUrl, Uri.file('/downloads/AAA.flac').toString());
        expect(engine.position, const Duration(seconds: 42));
        expect(engine.playing, isTrue);
        expect(repo.asked, isEmpty);

        // What it plays is written as the offline path writes it: to the
        // server first, which here answers.
        for (var i = 0; i < 6; i++) {
          engine.advance(const Duration(seconds: 1));
          await settle(tester);
        }
        await session.dispose();
        expect(repo.putPlayStateCalls.last.pid, 'tr-AAA');
        expect(repo.reportedSessions.single.pid, 'tr-AAA');
        await done(tester, sync, const []);
      });

      testWidgets('plays a downloaded book from the part its mirrored '
          'position falls in at once, asking only for its config, which it '
          'does not wait for', (tester) async {
        final (repo, sync) = await outOfReach(tester, book: storedBook());
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);

        unawaited(session.start());
        await settle(tester);

        expect(engine.loadedUrl, part1);
        expect(engine.position, const Duration(seconds: 30));
        expect(engine.playing, isTrue);
        expect(repo.asked, ['book $bookPid']);
        await done(tester, sync, [session]);
      });

      testWidgets('takes up the config the server answers meanwhile, in '
          'place: the rate and trimming, nothing reloaded or moved', (
        tester,
      ) async {
        final (repo, sync) = await outOfReach(tester, book: storedBook());
        repo.skipMaps['$bookPid#1'] = const SkipMap(
          state: 'ready',
          spans: [SkipSpan(startMs: 31000, endMs: 50000)],
        );
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        unawaited(session.start());
        await settle(tester);
        expect(engine.loadedUrl, part1);
        expect(engine.speed, 1.0, reason: 'no config yet: the defaults');
        final loads = engine.loadedUrls.length;
        final seeks = engine.seekCalls.length;

        repo.answerConfig();
        await settle(tester);

        expect(engine.speed, 1.5);
        expect(session.trimEnabled.value, isTrue);
        expect(repo.skipMapParts, [1]);
        expect(engine.loadedUrls, hasLength(loads), reason: 'nothing reloaded');
        expect(engine.seekCalls, hasLength(seeks), reason: 'nothing moved');
        expect(engine.position, const Duration(seconds: 30));

        // Trimmed from here on.
        engine.advance(const Duration(seconds: 1));
        await settle(tester);
        expect(engine.position, const Duration(seconds: 50));
        await done(tester, sync, [session]);
      });

      testWidgets('asks the server for an item not downloaded, and fails as '
          'it always has when the server is out of reach', (tester) async {
        final (_, sync) = await outOfReach(tester);
        final server = FakeRepository(items: [testItem('tr-AAA')])
          ..playInfoError = unreachable;
        final session = trackSession(
          server,
          sync,
          FakeEngine(),
          downloads: FakeDownloads(),
        );
        await expectLater(session.start(), throwsA(unreachable));
        expect(server.playStateReads, ['tr-AAA']);
        await done(tester, sync, const []);
      });

      testWidgets('a paused load asks the server and waits for it, however '
          'long it takes, then stands where the server says, and writes back '
          'nothing older', (tester) async {
        final (repo, sync) = await outOfReach(tester, book: storedBook());
        repo.playPositions[bookPid] = 75000;
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);

        unawaited(session.start(autoplay: false));
        await tester.pump(const Duration(seconds: 10));
        expect(engine.loadedUrl, isNull);

        repo
          ..answerReads()
          ..answerConfig();
        await settle(tester);
        expect(engine.loadedUrl, part1);
        expect(engine.position, const Duration(seconds: 15));
        expect(engine.playing, isFalse);

        await session.dispose();
        expect(repo.putPlayStateCalls.map((c) => c.positionMs), [75000]);
        await done(tester, sync, const []);
      });

      testWidgets('a paused load the listener presses play on while the '
          'server is silent plays the device copy at once', (tester) async {
        final (repo, sync) = await outOfReach(tester, book: storedBook());
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);

        unawaited(session.start(autoplay: false));
        await tester.pump(const Duration(seconds: 5));
        expect(engine.loadedUrl, isNull);

        unawaited(session.play());
        await settle(tester);
        expect(engine.loadedUrl, part1);
        expect(engine.position, const Duration(seconds: 30));
        expect(engine.playing, isTrue);

        // The reads still out land on a start already made.
        repo
          ..answerReads()
          ..answerConfig();
        await settle(tester);
        expect(engine.loadedUrl, part1);
        expect(engine.speed, 1.5);
        await done(tester, sync, [session]);
      });

      testWidgets('a press made while the download is still being looked up '
          'is heard: the device copy plays at once', (tester) async {
        final (repo, sync) = await outOfReach(tester, book: storedBook());
        await mirrored(bookPid, 90000);
        final downloads = _HeldDownloads(local: {bookPid: testLocalParts(3)});
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = PlaybackSession(
          repository: repo,
          engine: engine,
          item: book,
          clientId: 'test',
          sync: sync,
          downloads: downloads,
        );

        unawaited(session.start(autoplay: false));
        await settle(tester);
        unawaited(session.play());
        await settle(tester);
        downloads.lookup.complete();
        await settle(tester);
        expect(engine.loadedUrl, part1);
        expect(engine.playing, isTrue);
        await done(tester, sync, [session]);
      });

      testWidgets('a book write after a config read that failed reads the '
          'stored settings again first, and writes over them only what the '
          'listener chose', (tester) async {
        final (repo, sync) = await outOfReach(
          tester,
          book: storedBook(
            settings: const BookSettings(
              speed: 1.5,
              trimSilence: true,
              voiceBoost: false,
            ),
          ),
        );
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        unawaited(session.start());
        await settle(tester);
        repo.failConfig(unreachable);
        await settle(tester);
        expect(engine.speed, 1.0);

        // The server answers again; the socket is still down.
        repo
          ..answerConfig()
          ..answerReads();
        expect(await session.setVoiceBoost(true), isTrue);
        await settle(tester);
        expect(repo.putBookSettingsCalls.map((c) => _stored(c.settings)), [
          (speed: 1.5, voiceBoost: true, trimSilence: true),
        ]);
        expect(session.voiceBoost.value, isTrue);
        expect(engine.speed, 1.5, reason: 'the config read is taken up');
        await done(tester, sync, [session]);
      });

      testWidgets('a book rate chosen while its stored settings cannot be '
          'read waits, kept, and is written over them once a read works', (
        tester,
      ) async {
        final (repo, sync, link) = await cutOff(
          tester,
          book: storedBook(
            settings: const BookSettings(
              speed: 1.5,
              trimSilence: true,
              voiceBoost: false,
            ),
          ),
        );
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        unawaited(session.start());
        await settle(tester);
        repo.failConfig(unreachable);
        await settle(tester);

        await session.setSpeed(1.25);
        await settle(tester);
        expect(engine.speed, 1.25);
        expect(repo.putBookSettingsCalls, isEmpty, reason: 'nothing read yet');

        repo.answerConfig();
        await back(tester, sync, link);
        expect(repo.putBookSettingsCalls.map((c) => _stored(c.settings)), [
          (speed: 1.25, voiceBoost: false, trimSilence: true),
        ]);
        expect(engine.speed, 1.25);
        await done(tester, sync, [session]);
      });

      testWidgets('a show write after a config read that failed reads the '
          'stored settings again first, and writes over them only what the '
          'listener chose', (tester) async {
        final (repo, sync) = await outOfReach(tester);
        storedShow(
          repo,
          const SubscriptionSettings(
            speed: 1.5,
            trimSilence: true,
            voiceBoost: false,
          ),
        );
        final engine = FakeEngine();
        final session = episodeSession(repo, sync, engine);
        unawaited(session.start());
        await settle(tester);
        repo.failConfig(unreachable);
        await settle(tester);
        expect(engine.speed, 1.0);

        // The server answers again; the socket is still down.
        repo
          ..answerConfig()
          ..answerReads();
        expect(await session.setVoiceBoost(true), isTrue);
        await settle(tester);
        expect(
          repo.putSubscriptionSettingsCalls.map((c) => _shown(c.settings)),
          [(speed: 1.5, voiceBoost: true, trimSilence: true)],
        );
        expect(session.voiceBoost.value, isTrue);
        expect(engine.speed, 1.5, reason: 'the config read is taken up');
        await done(tester, sync, [session]);
      });

      testWidgets('a show rate chosen while its stored settings cannot be '
          'read waits, kept, and is written over them once a read works', (
        tester,
      ) async {
        final (repo, sync, link) = await cutOff(tester);
        storedShow(
          repo,
          const SubscriptionSettings(
            speed: 1.5,
            trimSilence: true,
            voiceBoost: false,
          ),
        );
        final engine = FakeEngine();
        final session = episodeSession(repo, sync, engine);
        unawaited(session.start());
        await settle(tester);
        repo.failConfig(unreachable);
        await settle(tester);

        await session.setSpeed(1.25);
        await settle(tester);
        expect(engine.speed, 1.25);
        expect(repo.putSubscriptionSettingsCalls, isEmpty);

        repo.answerConfig();
        await back(tester, sync, link);
        expect(
          repo.putSubscriptionSettingsCalls.map((c) => _shown(c.settings)),
          [(speed: 1.25, voiceBoost: false, trimSilence: true)],
        );
        expect(engine.speed, 1.25);
        await done(tester, sync, [session]);
      });

      testWidgets('a waiting book boost the server refuses once it answers '
          'puts the chip back to the stored setting', (tester) async {
        final (repo, sync, link) = await cutOff(
          tester,
          book: storedBook(
            settings: const BookSettings(speed: 1.5, voiceBoost: false),
          ),
        );
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        unawaited(session.start());
        await settle(tester);
        repo.failConfig(unreachable);
        await settle(tester);
        expect(await session.setVoiceBoost(true), isTrue, reason: 'kept');
        expect(session.voiceBoost.value, isTrue);

        repo
          ..putBookSettingsError = _refused
          ..answerConfig();
        await back(tester, sync, link);
        // At the start, at the write, and at the server's return.
        expect(repo.asked.where((a) => a == 'book $bookPid'), hasLength(3));
        expect(repo.putBookSettingsCalls, hasLength(1), reason: 'refused');
        expect(session.voiceBoost.value, isFalse);
        await done(tester, sync, [session]);
      });

      testWidgets('a waiting show boost the server refuses once it answers '
          'puts the chip back to the stored setting', (tester) async {
        final (repo, sync, link) = await cutOff(tester);
        storedShow(
          repo,
          const SubscriptionSettings(speed: 1.5, voiceBoost: false),
        );
        final engine = FakeEngine();
        final session = episodeSession(repo, sync, engine);
        unawaited(session.start());
        await settle(tester);
        repo.failConfig(unreachable);
        await settle(tester);
        expect(await session.setVoiceBoost(true), isTrue, reason: 'kept');
        expect(session.voiceBoost.value, isTrue);

        repo
          ..putSubscriptionSettingsError = _refused
          ..answerConfig();
        await back(tester, sync, link);
        expect(repo.putSubscriptionSettingsCalls, hasLength(1));
        expect(session.voiceBoost.value, isFalse);
        await done(tester, sync, [session]);
      });

      for (final refusedFirst in [true, false]) {
        testWidgets(
          'a boost tapped while the server\'s return is storing a '
          'waiting choice waits its turn, and its answer and the chip agree '
          'with the server: the '
          '${refusedFirst ? 'return\'s write refused, the tap\'s answered' : 'return\'s write answered, the tap\'s refused'}',
          (tester) async {
            final (repo, sync, link) = await cutOff(
              tester,
              book: storedBook(
                settings: const BookSettings(speed: 1.5, voiceBoost: false),
              ),
            );
            await mirrored(bookPid, 90000);
            final engine = FakeEngine(
              mediaDuration: const Duration(minutes: 1),
            );
            final session = bookSession(repo, sync, engine);
            unawaited(session.start());
            await settle(tester);
            repo.failConfig(unreachable);
            await settle(tester);
            expect(await session.setVoiceBoost(true), isTrue, reason: 'kept');

            final returnRead = repo.holdNextConfig();
            repo
              ..holdBookWrites = true
              ..answerConfig();
            await back(tester, sync, link);
            returnRead.complete();
            await settle(tester);
            expect(repo.bookWrites.map((w) => w.settings.voiceBoost), [
              true,
            ], reason: 'the return\'s store alone');

            // Each refused write differs from what the server keeps, so a
            // chip left on it shows.
            final tapped = refusedFirst;
            bool? took;
            unawaited(session.setVoiceBoost(tapped).then((v) => took = v));
            await settle(tester);
            expect(repo.bookWrites, hasLength(1), reason: 'the tap waits');
            if (refusedFirst) {
              repo.bookWrites.first.refuse(_refused);
            } else {
              repo.bookWrites.first.answer();
            }
            await settle(tester);
            expect(took, isNull);
            expect(repo.bookWrites.map((w) => w.settings.voiceBoost), [
              true,
              tapped,
            ], reason: 'then the tap\'s');
            if (refusedFirst) {
              repo.bookWrites.last.answer();
            } else {
              repo.bookWrites.last.refuse(_refused);
            }
            await settle(tester);

            final stored = repo.storedBookSettings[bookPid]?.voiceBoost;
            expect(stored, refusedFirst ? tapped : true);
            expect(took, refusedFirst);
            expect(session.voiceBoost.value, stored);
            await done(tester, sync, [session]);
          },
        );
      }

      testWidgets('a config read that failed is asked again once the server '
          'is back, once, and taken up in place', (tester) async {
        final (repo, sync, link) = await cutOff(tester, book: storedBook());
        repo.skipMaps['$bookPid#1'] = const SkipMap(
          state: 'ready',
          spans: [SkipSpan(startMs: 31000, endMs: 50000)],
        );
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        unawaited(session.start());
        await settle(tester);
        repo.failConfig(unreachable);
        await settle(tester);
        expect(engine.speed, 1.0);
        expect(session.trimEnabled.value, isFalse);
        repo.answerConfig();
        await tester.pump(const Duration(milliseconds: 500));
        await settle(tester);
        expect(repo.asked.where((a) => a == 'book $bookPid'), hasLength(1));

        await back(tester, sync, link);
        expect(repo.asked.where((a) => a == 'book $bookPid'), hasLength(2));
        expect(engine.speed, 1.5);
        expect(session.trimEnabled.value, isTrue);
        expect(repo.skipMapParts, [1]);
        expect(engine.loadedUrl, part1, reason: 'nothing reloaded');

        await tester.pump(const Duration(seconds: 30));
        await settle(tester);
        expect(repo.asked.where((a) => a == 'book $bookPid'), hasLength(2));
        await done(tester, sync, [session]);
      });

      testWidgets('voice boost chosen out of reach and stored by an ask '
          'again before the socket is back switches the book to the '
          'server\'s stream', (tester) async {
        final (repo, sync, _) = await cutOff(tester, book: storedBook());
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        unawaited(session.start());
        await settle(tester);
        expect(engine.loadedUrl, part1);
        repo.failConfig(unreachable);
        await settle(tester);
        bool? took;
        unawaited(session.setVoiceBoost(true).then((v) => took = v));
        await settle(tester);
        expect(took, isTrue, reason: 'kept');
        expect(engine.loadedUrl, part1);

        repo
          ..answerReads()
          ..answerConfig();
        await tester.pump(const Duration(seconds: 2));
        await settle(tester);

        expect(sync.current.online, isFalse, reason: 'the socket still down');
        expect(repo.putBookSettingsCalls.single.settings.voiceBoost, isTrue);
        expect(engine.loadedUrl, contains('pid=$bookPid&part=1'));
        expect(session.displayPosition, const Duration(seconds: 90));
        expect(engine.playing, isTrue);
        await done(tester, sync, [session]);
      });

      testWidgets('a downloaded book whose parts the server, back, lays out '
          'otherwise streams from its next part on', (tester) async {
        final (repo, sync, link) = await cutOff(tester, book: storedBook());
        await mirrored(bookPid, 75000);
        final engine = FakeEngine(mediaDuration: const Duration(seconds: 50));
        final session = PlaybackSession(
          repository: repo,
          engine: engine,
          item: book,
          clientId: 'test',
          sync: sync,
          downloads: FakeDownloads(
            local: {bookPid: testLocalParts(3, partMs: 50000)},
          ),
        );
        unawaited(session.start());
        await settle(tester);
        expect(engine.loadedUrl, part1);
        expect(session.displayPosition, const Duration(seconds: 75));

        repo
          ..answerReads()
          ..answerConfig();
        await back(tester, sync, link);
        expect(engine.loadedUrl, part1, reason: 'nothing reloaded');

        engine.advance(const Duration(seconds: 26));
        await settle(tester);

        expect(engine.loadedUrl, contains('pid=$bookPid&part=1'));
        expect(session.displayPosition, const Duration(seconds: 100));
        expect(engine.playing, isTrue);
        await done(tester, sync, [session]);
      });

      testWidgets('a config read that keeps failing is asked again once per '
          'return of the server, and between returns only on the growing '
          'wait', (tester) async {
        final (repo, sync, link) = await cutOff(tester, book: storedBook());
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        unawaited(session.start());
        await settle(tester);
        repo.failConfig(unreachable);
        await settle(tester);
        int reads() => repo.asked.where((a) => a == 'book $bookPid').length;

        // The wait's ask at 1 s, and the return's.
        await back(tester, sync, link);
        expect(reads(), 3);
        // The wait's at 3, 7, 15 and 31 s.
        await tester.pump(const Duration(seconds: 30));
        await settle(tester);
        expect(reads(), 7);

        link.attempts.last.drop(null);
        await settle(tester);
        expect(sync.current.online, isFalse);
        await back(tester, sync, link);
        expect(reads(), 8);
        await done(tester, sync, [session]);
      });

      testWidgets('a downloaded copy that will not load turns to the server, '
          'which plays the item as it answers', (tester) async {
        final (repo, sync) = await outOfReach(tester);
        repo.playPositions['tr-AAA'] = 15000;
        final engine = FakeEngine()..failNextLoad = true;
        final session = trackSession(repo, sync, engine);
        Object? failed;

        unawaited(session.start().catchError((Object e) => failed = e));
        await settle(tester);
        expect(engine.loadedUrls, [Uri.file('/downloads/AAA.flac').toString()]);
        expect(
          repo.asked,
          containsAll(['play-info tr-AAA', 'play-state tr-AAA']),
        );

        repo.answerReads();
        await settle(tester);
        expect(failed, isNull);
        expect(engine.loadedUrl, contains('pid=tr-AAA'));
        expect(engine.position, const Duration(seconds: 15));
        expect(engine.playing, isTrue);
        await done(tester, sync, [session]);
      });
    });

    group('while the first connect is still out', () {
      testWidgets('asks a server that answers, and plays the device copy at '
          'its position with its config', (tester) async {
        final repo = FakeRepository()..books[bookPid] = storedBook();
        repo.playPositions[bookPid] = 75000;
        final sync = await engineOver(tester, repo, _heldConnects);
        expect(sync.current.connection, SyncConnection.connecting);
        expect(sync.current.retrying, isFalse);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);

        await session.start();

        expect(engine.loadedUrls, [part1]);
        expect(engine.position, const Duration(seconds: 15));
        expect(engine.speed, 1.5);
        expect(session.trimEnabled.value, isTrue);
        await done(tester, sync, [session]);
      });

      testWidgets('plays the device copy once the server has not answered '
          'within the short wait, not before it and not after the full one', (
        tester,
      ) async {
        final (repo, sync) = await notKnown(tester, book: storedBook());
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);

        unawaited(session.start());
        await settle(tester);
        await tester.pump(wait - const Duration(milliseconds: 1));
        expect(engine.loadedUrl, isNull, reason: 'the server still has time');
        expect(
          repo.asked,
          containsAll(['play-state $bookPid', 'book $bookPid']),
        );

        await tester.pump(const Duration(milliseconds: 1));
        await settle(tester);
        expect(engine.loadedUrl, part1);
        expect(engine.position, const Duration(seconds: 30));
        expect(engine.playing, isTrue);
        expect(engine.speed, 1.0, reason: 'no config yet: the defaults');
        await done(tester, sync, [session]);
      });

      testWidgets('takes up the config the server answers late, in place: the '
          'rate and trimming, with the listener left where they are', (
        tester,
      ) async {
        final (repo, sync) = await notKnown(tester, book: storedBook());
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        unawaited(session.start());
        await tester.pump(wait);
        await settle(tester);
        expect(engine.loadedUrl, part1);
        engine.advance(const Duration(seconds: 2));
        await settle(tester);
        final loads = engine.loadedUrls.length;
        final seeks = engine.seekCalls.length;

        repo.answerConfig();
        await settle(tester);

        expect(engine.speed, 1.5);
        expect(session.trimEnabled.value, isTrue);
        expect(repo.skipMapsAsked, [bookPid]);
        expect(engine.loadedUrls, hasLength(loads), reason: 'nothing reloaded');
        expect(engine.seekCalls, hasLength(seeks), reason: 'nothing moved');
        expect(engine.position, const Duration(seconds: 32));
        expect(engine.loadedUrl, part1);
        await done(tester, sync, [session]);
      });

      testWidgets('keeps a rate the listener chose before the late config', (
        tester,
      ) async {
        final (repo, sync) = await notKnown(tester, book: storedBook());
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        unawaited(session.start());
        await tester.pump(wait);
        await settle(tester);
        unawaited(session.setSpeed(1.25, persist: false));
        await settle(tester);

        repo.answerConfig();
        await settle(tester);

        expect(engine.speed, 1.25);
        await done(tester, sync, [session]);
      });

      testWidgets('asks the server for an item not downloaded as it always '
          'has, with no short wait', (tester) async {
        final (repo, sync) = await notKnown(tester);
        final engine = FakeEngine();
        final session = trackSession(
          repo,
          sync,
          engine,
          downloads: FakeDownloads(),
        );
        unawaited(session.start());
        await tester.pump(wait * 2);
        await settle(tester);
        expect(engine.loadedUrl, isNull);

        repo.answerReads();
        await settle(tester);
        expect(engine.loadedUrl, isNot(isNull));
        expect(engine.playing, isTrue);
        await done(tester, sync, [session]);
      });

      testWidgets('a paused load asks a slow server and waits for it, then '
          'stands where the server says, and writes back nothing older', (
        tester,
      ) async {
        final (repo, sync) = await notKnown(tester, book: storedBook());
        repo.playPositions[bookPid] = 75000;
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);

        unawaited(session.start(autoplay: false));
        await tester.pump(wait * 4);
        await settle(tester);
        expect(engine.loadedUrl, isNull);

        repo
          ..answerReads()
          ..answerConfig();
        await settle(tester);
        expect(engine.loadedUrl, part1);
        expect(engine.position, const Duration(seconds: 15));
        expect(engine.playing, isFalse);

        // Let go without a press: the server's position is the one kept.
        await session.dispose();
        expect(repo.putPlayStateCalls.map((c) => c.positionMs), [75000]);
        await done(tester, sync, const []);
      });

      testWidgets('a paused load the listener presses play on gives the '
          'server the short wait from the press, then plays the device copy', (
        tester,
      ) async {
        final (repo, sync) = await notKnown(tester, book: storedBook());
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);

        unawaited(session.start(autoplay: false));
        await tester.pump(wait * 4);
        unawaited(session.play());
        await settle(tester);
        await tester.pump(wait - const Duration(milliseconds: 1));
        expect(engine.loadedUrl, isNull, reason: 'the server still has time');

        await tester.pump(const Duration(milliseconds: 1));
        await settle(tester);
        expect(engine.loadedUrl, part1);
        expect(engine.position, const Duration(seconds: 30));
        expect(engine.playing, isTrue);
        await done(tester, sync, [session]);
      });

      testWidgets('a press taken back before anything sounded makes it a '
          'paused load again: it waits for the server, stands where it says, '
          'and writes back nothing older', (tester) async {
        final (repo, sync) = await notKnown(tester, book: storedBook());
        repo.playPositions[bookPid] = 75000;
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);

        unawaited(session.start(autoplay: false));
        await settle(tester);
        unawaited(session.play());
        await tester.pump(wait ~/ 2);
        unawaited(session.pause());
        await tester.pump(wait * 2);
        await settle(tester);
        expect(engine.loadedUrl, isNull);

        repo
          ..answerReads()
          ..answerConfig();
        await settle(tester);
        expect(engine.loadedUrl, part1);
        expect(engine.position, const Duration(seconds: 15));
        expect(engine.playing, isFalse);

        await session.dispose();
        expect(repo.putPlayStateCalls.map((c) => c.positionMs), [75000]);
        await done(tester, sync, const []);
      });

      testWidgets('a boost write the server refuses puts the chip back to '
          'the stored setting', (tester) async {
        final (repo, sync) = await notKnown(
          tester,
          book: storedBook(
            settings: const BookSettings(speed: 1.5, voiceBoost: true),
          ),
        );
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        unawaited(session.start());
        await tester.pump(wait);
        await settle(tester);
        expect(session.voiceBoost.value, isFalse, reason: 'the device default');
        repo.putBookSettingsError = const WaxDeckApiException(
          code: 'bad-request',
          message: 'refused',
          statusCode: 400,
        );
        bool? took;
        unawaited(session.setVoiceBoost(true).then((v) => took = v));
        await settle(tester);

        repo.answerConfig();
        await settle(tester);
        expect(took, isFalse);
        expect(session.voiceBoost.value, isTrue, reason: 'what is stored');
        await done(tester, sync, [session]);
      });

      testWidgets('takes up trimming the server answers late for a book with '
          'no stored settings, on the device default', (tester) async {
        final (repo, sync) = await notKnown(
          tester,
          book: storedBook(settings: null),
        );
        repo.skipMaps['$bookPid#1'] = const SkipMap(
          state: 'ready',
          spans: [SkipSpan(startMs: 31000, endMs: 50000)],
        );
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(
          repo,
          sync,
          engine,
          defaultTrimSilence: true,
        );
        unawaited(session.start());
        await tester.pump(wait);
        await settle(tester);
        expect(engine.loadedUrl, part1);
        expect(session.trimEnabled.value, isTrue);
        expect(repo.skipMapParts, isEmpty, reason: 'no server answer yet');

        repo.answerConfig();
        await settle(tester);
        expect(repo.skipMapParts, [1]);

        engine.advance(const Duration(seconds: 1));
        await settle(tester);
        expect(engine.position, const Duration(seconds: 50));
        await done(tester, sync, [session]);
      });

      testWidgets('trims every later part of a book started from the device '
          'once the server has answered', (tester) async {
        final (repo, sync) = await notKnown(tester, book: storedBook());
        repo.skipMaps['$bookPid#2'] = silence;
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        unawaited(session.start());
        await tester.pump(wait);
        await settle(tester);
        repo.answerConfig();
        await settle(tester);
        expect(repo.skipMapParts, [1]);

        // At 1.5x, 21 seconds runs part one's last 30 out.
        engine.advance(const Duration(seconds: 21));
        await settle(tester);
        expect(engine.loadedUrl, Uri.file('/downloads/part2.flac').toString());
        expect(repo.skipMapParts, [1, 2]);

        engine.advance(const Duration(seconds: 1));
        await settle(tester);
        expect(engine.position, const Duration(seconds: 50));
        await done(tester, sync, [session]);
      });

      testWidgets('a rate the listener set during the silence stands through '
          'the device start and the late config, and is the one stored', (
        tester,
      ) async {
        final (repo, sync) = await notKnown(tester);
        repo
          ..addSubscription(
            testShow(showPid),
            settings: const SubscriptionSettings(speed: 1.5),
          )
          ..episodesByShow[showPid] = [
            testEpisode(episodePid, showPid: showPid),
          ];
        final engine = FakeEngine();
        final session = PlaybackSession(
          repository: repo,
          engine: engine,
          item: testEpisode(episodePid, showPid: showPid),
          clientId: 'test',
          sync: sync,
          downloads: FakeDownloads(
            local: {episodePid: testLocal('/downloads/EP.mp3')},
          ),
        );
        unawaited(session.start());
        await tester.pump(wait ~/ 2);
        unawaited(session.setSpeed(1.25));
        await tester.pump(wait ~/ 2);
        await settle(tester);
        expect(engine.loadedUrl, Uri.file('/downloads/EP.mp3').toString());
        expect(engine.speed, 1.25);

        repo.answerConfig();
        await settle(tester);
        expect(engine.speed, 1.25);
        expect(repo.putSubscriptionSettingsCalls.last.settings.speed, 1.25);
        await done(tester, sync, [session]);
      });

      testWidgets('trimming the listener turned off after the device start '
          'stays off when the config lands', (tester) async {
        final (repo, sync) = await notKnown(tester, book: storedBook());
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(
          repo,
          sync,
          engine,
          defaultTrimSilence: true,
        );
        unawaited(session.start());
        await tester.pump(wait);
        await settle(tester);
        expect(session.trimEnabled.value, isTrue);
        session.setTrimEnabled(false);
        await settle(tester);
        final asked = repo.skipMapParts.length;

        repo.answerConfig();
        await settle(tester);
        expect(session.trimEnabled.value, isFalse);
        expect(repo.skipMapParts, hasLength(asked));
        await done(tester, sync, [session]);
      });

      testWidgets('voice boost the listener turned on after the device start '
          'stays on when the config lands, stored with the server\'s other '
          'settings', (tester) async {
        final (repo, sync) = await notKnown(
          tester,
          book: storedBook(
            settings: const BookSettings(
              speed: 1.5,
              trimSilence: true,
              voiceBoost: false,
            ),
          ),
        );
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        unawaited(session.start());
        await tester.pump(wait);
        await settle(tester);
        unawaited(session.setVoiceBoost(true));
        await settle(tester);

        repo.answerConfig();
        await settle(tester);
        expect(session.voiceBoost.value, isTrue);
        expect(repo.putBookSettingsCalls.map((c) => _stored(c.settings)), [
          (speed: 1.5, voiceBoost: true, trimSilence: true),
        ]);
        await done(tester, sync, [session]);
      });

      testWidgets('a book rate the listener set after the device start is '
          'stored with the server\'s other settings, and the next write '
          'carries it', (tester) async {
        final (repo, sync) = await notKnown(tester, book: storedBook());
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        unawaited(session.start());
        await tester.pump(wait);
        await settle(tester);
        unawaited(session.setSpeed(1.25));
        await settle(tester);

        repo
          ..answerConfig()
          ..answerReads();
        await settle(tester);
        expect(engine.speed, 1.25);
        await session.setVoiceBoost(true);
        await settle(tester);
        expect(repo.putBookSettingsCalls.map((c) => _stored(c.settings)), [
          (speed: 1.25, voiceBoost: null, trimSilence: true),
          (speed: 1.25, voiceBoost: true, trimSilence: true),
        ]);
        await done(tester, sync, [session]);
      });

      testWidgets('voice boost the listener turns on, stored while the socket '
          'is still connecting, switches the book to the server\'s stream, '
          'and its next part streams too', (tester) async {
        final repo = _Holding(book: storedBook())
          ..answerReads()
          ..answerConfig();
        repo.playPositions[bookPid] = 75000;
        final sync = await engineOver(tester, repo, _heldConnects);
        expect(sync.current.online, isFalse);
        expect(sync.current.retrying, isFalse);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        await session.start();
        expect(engine.loadedUrls, [part1]);

        expect(await session.setVoiceBoost(true), isTrue);
        await settle(tester);

        expect(repo.putBookSettingsCalls.single.settings.voiceBoost, isTrue);
        expect(engine.loadedUrl, contains('pid=$bookPid&part=1'));
        expect(session.displayPosition, const Duration(seconds: 75));
        expect(engine.playing, isTrue);

        engine.advance(const Duration(seconds: 46));
        await settle(tester);
        expect(engine.loadedUrl, contains('pid=$bookPid&part=2'));
        expect(session.displayPosition, const Duration(seconds: 120));
        expect(engine.playing, isTrue);
        await done(tester, sync, [session]);
      });

      testWidgets('a session let go before its config lands takes up nothing '
          'from it', (tester) async {
        final (repo, sync) = await notKnown(tester, book: storedBook());
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        unawaited(session.start());
        await tester.pump(wait);
        await settle(tester);
        expect(engine.loadedUrl, part1);
        await session.dispose();

        repo.answerConfig();
        await settle(tester);
        expect(engine.speed, 1.0);
        expect(session.trimEnabled.value, isFalse);
        expect(repo.skipMapParts, isEmpty);
        await done(tester, sync, const []);
      });

      testWidgets('a session whose engine another took before its config '
          'lands takes up nothing from it', (tester) async {
        final (repo, sync) = await notKnown(tester, book: storedBook());
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final first = bookSession(repo, sync, engine);
        unawaited(first.start());
        await tester.pump(wait);
        await settle(tester);
        expect(engine.loadedUrl, part1);
        final next = PlaybackSession(
          repository: FakeRepository(items: [testItem('tr-BBB')]),
          engine: engine,
          item: testItem('tr-BBB'),
          clientId: 'test',
        );
        await next.start();
        expect(engine.speed, 1.0);

        repo.answerConfig();
        await settle(tester);
        expect(engine.speed, 1.0, reason: 'the next item\'s rate');
        expect(first.trimEnabled.value, isFalse);
        expect(repo.skipMapParts, isEmpty);
        await done(tester, sync, [first, next]);
      });

      testWidgets('a downloaded copy that will not load turns to the server, '
          'which plays the item as it answers', (tester) async {
        final (repo, sync) = await notKnown(tester, book: storedBook());
        repo.playPositions[bookPid] = 75000;
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1))
          ..failNextLoad = true;
        final session = bookSession(repo, sync, engine);
        Object? failed;

        unawaited(session.start().catchError((Object e) => failed = e));
        await tester.pump(wait);
        await settle(tester);
        expect(engine.loadedUrls, [part1]);

        repo
          ..answerReads()
          ..answerConfig();
        await settle(tester);
        expect(failed, isNull);
        expect(engine.loadedUrl, contains('part=1'));
        expect(engine.position, const Duration(seconds: 15));
        expect(engine.playing, isTrue);
        expect(engine.speed, 1.5);
        expect(session.trimEnabled.value, isTrue);
        await done(tester, sync, [session]);
      });

      testWidgets('a downloaded book in one file that will not load turns to '
          'the server, which trims it as it plays it', (tester) async {
        // No parts: its play-info names none, as the part before it would.
        final (repo, sync) = await notKnown(
          tester,
          book: const BookDetail(
            pid: bookPid,
            title: 'There And Back Again',
            durationMs: 180000,
            settings: BookSettings(trimSilence: true),
          ),
        );
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 3))
          ..failNextLoad = true;
        final session = PlaybackSession(
          repository: repo,
          engine: engine,
          item: book,
          clientId: 'test',
          sync: sync,
          downloads: FakeDownloads(
            local: {bookPid: testLocal('/downloads/book.m4b')},
          ),
        );

        unawaited(session.start());
        await tester.pump(wait);
        await settle(tester);
        expect(engine.loadedUrls, [Uri.file('/downloads/book.m4b').toString()]);

        repo
          ..answerReads()
          ..answerConfig();
        await settle(tester);
        expect(engine.loadedUrl, contains('pid=$bookPid'));
        expect(repo.skipMapParts, [null]);
        await done(tester, sync, [session]);
      });

      testWidgets('a downloaded copy that will not load, the server out of '
          'reach too, fails as the copy failed', (tester) async {
        final (repo, sync) = await notKnown(tester);
        final engine = FakeEngine()..failNextLoad = true;
        final session = trackSession(repo, sync, engine);
        Object? failed;

        unawaited(session.start().catchError((Object e) => failed = e));
        await tester.pump(wait);
        await settle(tester);
        expect(failed, isNull, reason: 'the server still has its say');

        repo.failReads(unreachable);
        await settle(tester);
        expect(failed, isA<MediaLoadException>());
        expect(engine.playing, isFalse);
        await done(tester, sync, [session]);
      });

      testWidgets('looks the download up once, its unreachable server '
          'included', (tester) async {
        final (repo, sync) = await notKnown(tester);
        final downloads = _CountingDownloads(
          local: {'tr-AAA': testLocal('/downloads/AAA.flac')},
        );
        final engine = FakeEngine();
        final session = trackSession(repo, sync, engine, downloads: downloads);

        unawaited(session.start());
        await settle(tester);
        repo.failReads(unreachable);
        await settle(tester);
        expect(engine.loadedUrl, Uri.file('/downloads/AAA.flac').toString());
        expect(downloads.lookedUp, 1);
        await done(tester, sync, [session]);
      });
    });

    group('the settings writer', () {
      /// A server in reach answering every read, behind a link the test can
      /// cut and bring back.
      Future<(_Holding, SyncEngine, FakeLink)> inReach(
        WidgetTester tester, {
        BookDetail? book,
      }) async {
        final repo = _Holding(book: book)
          ..answerReads()
          ..answerConfig();
        final link = FakeLink();
        final sync = await engineOver(tester, repo, link.factory);
        expect(sync.current.online, isTrue);
        return (repo, sync, link);
      }

      /// Cuts [link]: the socket drops and reconnects fail.
      Future<void> cut(
        WidgetTester tester,
        SyncEngine sync,
        FakeLink link,
      ) async {
        link.reachable = false;
        link.attempts.last.drop(null);
        await settle(tester);
        expect(sync.current.online, isFalse);
      }

      int reads(_Holding repo) =>
          repo.asked.where((a) => a == 'book $bookPid').length;

      testWidgets('a speed tap after the book\'s settings sheet saved '
          'trimming writes the sheet\'s trimming back with it', (tester) async {
        final (repo, sync, _) = await inReach(
          tester,
          book: storedBook(
            settings: const BookSettings(
              speed: 1.5,
              trimSilence: false,
              voiceBoost: false,
            ),
          ),
        );
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        await session.start();
        expect(engine.speed, 1.5);

        // The sheet sends its whole object, as it does.
        await repo.putBookSettings(
          bookPid,
          const BookSettings(speed: 1.5, voiceBoost: false, trimSilence: true),
        );
        unawaited(session.setSpeed(1.25));
        await settle(tester);
        expect(_stored(repo.putBookSettingsCalls.last.settings), (
          speed: 1.25,
          voiceBoost: false,
          trimSilence: true,
        ));
        await done(tester, sync, [session]);
      });

      testWidgets('a speed tap after the show\'s settings were saved '
          'elsewhere writes every one of them back with it', (tester) async {
        final (repo, sync, _) = await inReach(tester);
        storedShow(repo, const SubscriptionSettings(speed: 1.5));
        final engine = FakeEngine();
        final session = episodeSession(repo, sync, engine);
        await session.start();
        expect(engine.speed, 1.5);

        // The subscription sheet, or another device.
        const saved = SubscriptionSettings(
          retentionKeep: 3,
          autoDownload: true,
          autoDownloadFilter: EpisodeFilter(
            include: ['interview'],
            exclude: ['trailer'],
          ),
          folder: 'News/Daily',
          private: true,
          speed: 1.5,
          trimSilence: true,
          voiceBoost: true,
          skipIntroSeconds: 30,
          skipOutroSeconds: 45,
        );
        await repo.putSubscriptionSettings(showPid, saved);
        unawaited(session.setSpeed(1.25));
        await settle(tester);
        final written = repo.putSubscriptionSettingsCalls.last.settings;
        expect(_everyField(written), (
          retentionKeep: 3,
          autoDownload: true,
          folder: 'News/Daily',
          private: true,
          speed: 1.25,
          trimSilence: true,
          voiceBoost: true,
          skipIntroSeconds: 30,
          skipOutroSeconds: 45,
        ));
        expect(written.autoDownloadFilter?.include, ['interview']);
        expect(written.autoDownloadFilter?.exclude, ['trailer']);
        await done(tester, sync, [session]);
      });

      for (final status in [503, 500, 429]) {
        testWidgets('a stored-settings read answered $status lets nothing be '
            'written until a read answers', (tester) async {
          final (repo, sync, _) = await inReach(
            tester,
            book: storedBook(
              settings: const BookSettings(
                speed: 1.5,
                trimSilence: true,
                voiceBoost: false,
              ),
            ),
          );
          repo.failConfig(
            WaxDeckApiException(
              code: 'unavailable',
              message: 'not now',
              statusCode: status,
            ),
          );
          final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
          final session = bookSession(repo, sync, engine);
          await session.start();
          expect(engine.speed, 1.0, reason: 'nothing read: the defaults');

          unawaited(session.setSpeed(1.25));
          await settle(tester);
          expect(repo.putBookSettingsCalls, isEmpty);

          repo.answerConfig();
          bool? took;
          unawaited(session.setVoiceBoost(true).then((v) => took = v));
          await settle(tester);
          expect(took, isTrue);
          // Out of reach (503) the rate waited for this read; answered with
          // an error, its store failed then, and it stands unstored.
          expect(repo.putBookSettingsCalls.map((c) => _stored(c.settings)), [
            (
              speed: status == 503 ? 1.25 : 1.5,
              voiceBoost: true,
              trimSilence: true,
            ),
          ]);
          await done(tester, sync, [session]);
        });
      }

      for (final writeFails in [false, true]) {
        testWidgets(
          'a speed and a boost tapped after the network went mid-listen are '
          'kept, the chip standing, and both written when the server is '
          'back: ${writeFails ? 'the read answered, the write failing' : 'the read failing'}',
          (tester) async {
            final (repo, sync, link) = await inReach(
              tester,
              book: storedBook(
                settings: const BookSettings(
                  speed: 1.5,
                  trimSilence: true,
                  voiceBoost: false,
                ),
              ),
            );
            final engine = FakeEngine(
              mediaDuration: const Duration(minutes: 1),
            );
            final session = bookSession(repo, sync, engine);
            await session.start();
            expect(engine.speed, 1.5);

            await cut(tester, sync, link);
            repo.putBookSettingsError = unreachable;
            if (!writeFails) repo.failConfig(unreachable);
            unawaited(session.setSpeed(1.25));
            bool? took;
            unawaited(session.setVoiceBoost(true).then((v) => took = v));
            await settle(tester);
            expect(took, isTrue, reason: 'kept, not failed');
            expect(session.voiceBoost.value, isTrue);
            expect(engine.speed, 1.25);
            expect(repo.storedBookSettings, isEmpty);
            final loads = engine.loadedUrls.length;

            repo
              ..putBookSettingsError = null
              ..answerConfig();
            await back(tester, sync, link);
            expect(_stored(repo.storedBookSettings[bookPid]!), (
              speed: 1.25,
              voiceBoost: true,
              trimSilence: true,
            ));
            expect(session.voiceBoost.value, isTrue);
            expect(engine.speed, 1.25);
            expect(
              engine.loadedUrls,
              hasLength(loads + 1),
              reason: 'reopened for the boost',
            );
            await done(tester, sync, [session]);
          },
        );
      }

      testWidgets('a return of the server while the config is being read '
          'again is not missed', (tester) async {
        final (repo, sync, link) = await cutOff(tester, book: storedBook());
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        unawaited(session.start());
        await settle(tester);
        repo.failConfig(unreachable);
        await settle(tester);

        final reread = repo.holdNextConfig();
        await back(tester, sync, link);
        expect(reads(repo), 2);
        await cut(tester, sync, link);
        await back(tester, sync, link);
        expect(reads(repo), 2, reason: 'one at a time');

        // The read out across the second return fails; the next answers.
        repo.answerConfig();
        reread.complete(unreachable);
        await settle(tester);
        expect(reads(repo), 3);
        expect(engine.speed, 1.5);
        expect(session.trimEnabled.value, isTrue);
        await done(tester, sync, [session]);
      });

      testWidgets('a config read that fails after the engine reconnected is '
          'asked again at once', (tester) async {
        final (repo, sync, link) = await cutOff(tester, book: storedBook());
        await mirrored(bookPid, 90000);
        final startRead = repo.holdNextConfig();
        repo.answerConfig();
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        unawaited(session.start());
        await settle(tester);
        expect(engine.loadedUrl, part1);

        // Back on a new route while the start's read hangs on the old one.
        await back(tester, sync, link);
        expect(reads(repo), 1);
        startRead.complete(unreachable);
        await settle(tester);
        expect(reads(repo), 2);
        expect(engine.speed, 1.5);
        expect(session.trimEnabled.value, isTrue);
        await done(tester, sync, [session]);
      });

      /// A session on [book] with no sync engine, as on the web.
      PlaybackSession engineless(_Holding repo, FakeEngine engine) =>
          PlaybackSession(
            repository: repo,
            engine: engine,
            item: book,
            clientId: 'test',
          );

      testWidgets('with no sync engine, a speed and a boost whose write '
          'fails for want of the server are stored once it answers '
          'again', (tester) async {
        final repo =
            _Holding(
                book: storedBook(
                  settings: const BookSettings(
                    speed: 1.5,
                    trimSilence: true,
                    voiceBoost: false,
                  ),
                ),
              )
              ..answerReads()
              ..answerConfig();
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = engineless(repo, engine);
        await session.start();
        expect(engine.speed, 1.5);

        repo.putBookSettingsError = unreachable;
        unawaited(session.setSpeed(1.25));
        bool? took;
        unawaited(session.setVoiceBoost(true).then((v) => took = v));
        await settle(tester);
        expect(took, isTrue, reason: 'kept, not failed');
        expect(session.voiceBoost.value, isTrue);
        expect(repo.storedBookSettings, isEmpty);
        final loads = engine.loadedUrls.length;

        repo.putBookSettingsError = null;
        await tester.pump(const Duration(seconds: 1));
        await settle(tester);
        expect(_stored(repo.storedBookSettings[bookPid]!), (
          speed: 1.25,
          voiceBoost: true,
          trimSilence: true,
        ));
        expect(session.voiceBoost.value, isTrue);
        expect(
          engine.loadedUrls,
          hasLength(loads + 1),
          reason: 'reopened for the boost',
        );
        final writes = repo.putBookSettingsCalls.length;
        await tester.pump(const Duration(minutes: 5));
        await settle(tester);
        expect(
          repo.putBookSettingsCalls,
          hasLength(writes),
          reason: 'stored: nothing asked again',
        );

        // A choice kept after that starts the pace over.
        repo.putBookSettingsError = unreachable;
        unawaited(session.setSpeed(1.1));
        await settle(tester);
        repo.putBookSettingsError = null;
        await tester.pump(const Duration(seconds: 1));
        await settle(tester);
        expect(repo.storedBookSettings[bookPid]?.speed, 1.1);
        await session.dispose();
        await settle(tester);
      });

      testWidgets('a speed kept while the socket stays up and the stored '
          'settings read answers 503 is stored on the clock once it '
          'answers', (tester) async {
        final (repo, sync, _) = await inReach(
          tester,
          book: storedBook(
            settings: const BookSettings(
              speed: 1.5,
              trimSilence: true,
              voiceBoost: false,
            ),
          ),
        );
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        await session.start();
        expect(reads(repo), 1);

        repo.failConfig(
          const WaxDeckApiException(
            code: 'catalog-maintenance',
            message: 'the catalog is being rebuilt',
            statusCode: 503,
          ),
        );
        unawaited(session.setSpeed(1.25));
        await settle(tester);
        // The tap's read, and the engine's at-once return.
        expect(reads(repo), 3);
        expect(repo.putBookSettingsCalls, isEmpty);
        expect(sync.current.online, isTrue);

        repo.answerConfig();
        await tester.pump(const Duration(seconds: 1));
        await settle(tester);
        expect(reads(repo), 4);
        expect(repo.putBookSettingsCalls.map((c) => _stored(c.settings)), [
          (speed: 1.25, voiceBoost: false, trimSilence: true),
        ]);
        await done(tester, sync, [session]);
      });

      for (final chosen in [false, true]) {
        testWidgets(
          'with no sync engine, a start whose stored settings read '
          'failed for want of the server asks again on the clock and takes '
          'them up in place${chosen ? ', one read serving a speed chosen meanwhile too' : ''}',
          (tester) async {
            final repo = _Holding(
              book: storedBook(
                settings: const BookSettings(
                  speed: 1.5,
                  trimSilence: true,
                  voiceBoost: false,
                ),
              ),
            )..answerReads();
            repo.failConfig(unreachable);
            final engine = FakeEngine(
              mediaDuration: const Duration(minutes: 1),
            );
            final session = engineless(repo, engine);
            await session.start();
            expect(engine.speed, 1.0, reason: 'nothing read: the defaults');
            expect(session.trimEnabled.value, isFalse);
            if (chosen) {
              unawaited(session.setSpeed(1.25));
              await settle(tester);
            }
            final asked = reads(repo);
            final loads = engine.loadedUrls.length;

            repo.answerConfig();
            await tester.pump(const Duration(seconds: 1));
            await settle(tester);
            expect(reads(repo), asked + 1);
            expect(engine.speed, chosen ? 1.25 : 1.5);
            expect(session.trimEnabled.value, isTrue);
            expect(engine.loadedUrls, hasLength(loads), reason: 'in place');
            expect(
              repo.putBookSettingsCalls.map((c) => _stored(c.settings)),
              chosen
                  ? [(speed: 1.25, voiceBoost: false, trimSilence: true)]
                  : isEmpty,
            );

            await tester.pump(const Duration(minutes: 5));
            await settle(tester);
            expect(reads(repo), asked + 1, reason: 'answered: asked no more');
            await session.dispose();
            await settle(tester);
          },
        );
      }

      testWidgets('a choice waiting for the server is asked about at a '
          'pace growing to a minute, and no longer once the item '
          'changed', (tester) async {
        const nextPid = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK03';
        final repo = _Holding(book: storedBook())
          ..answerReads()
          ..answerConfig();
        repo.books[nextPid] = testBook(
          nextPid,
          durationMs: 180000,
          partCount: 3,
          settings: const BookSettings(speed: 1.1),
        );
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = engineless(repo, engine);
        await session.start();

        repo.failConfig(unreachable);
        unawaited(session.setSpeed(1.25));
        await settle(tester);
        expect(reads(repo), 2);

        const tick = Duration(milliseconds: 1);
        var asked = 2;
        for (final seconds in [1, 2, 4, 8, 16, 32, 60, 60, 60]) {
          await tester.pump(Duration(seconds: seconds) - tick);
          await settle(tester);
          expect(reads(repo), asked, reason: 'not before ${seconds}s');
          await tester.pump(tick);
          await settle(tester);
          expect(reads(repo), ++asked, reason: 'at ${seconds}s');
        }

        await session.dispose();
        repo.answerConfig();
        final next = PlaybackSession(
          repository: repo,
          engine: engine,
          item: const ItemSummary(
            pid: nextPid,
            mediaType: MediaType.audiobook,
            title: 'The Return',
            durationMs: 180000,
          ),
          clientId: 'test',
        );
        await next.start();
        await tester.pump(const Duration(minutes: 10));
        await settle(tester);
        expect(reads(repo), asked, reason: 'the old book is asked no more');
        expect(engine.speed, 1.1);
        expect(repo.putBookSettingsCalls, isEmpty);
        await next.dispose();
        await settle(tester);
      });

      testWidgets('a choice waiting for the server is kept for its session '
          'only: let go, nothing is written for it, nor for what plays '
          'next', (tester) async {
        const nextPid = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK03';
        final (repo, sync, link) = await cutOff(tester, book: storedBook());
        repo.books[nextPid] = testBook(
          nextPid,
          durationMs: 180000,
          partCount: 3,
          settings: const BookSettings(speed: 1.1),
        );
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        unawaited(session.start());
        await settle(tester);
        repo.failConfig(unreachable);
        await settle(tester);
        unawaited(session.setSpeed(1.25));
        bool? took;
        unawaited(session.setVoiceBoost(true).then((v) => took = v));
        await settle(tester);
        expect(took, isTrue, reason: 'kept');
        await session.dispose();

        repo
          ..answerReads()
          ..answerConfig();
        await back(tester, sync, link);
        final next = PlaybackSession(
          repository: repo,
          engine: engine,
          item: const ItemSummary(
            pid: nextPid,
            mediaType: MediaType.audiobook,
            title: 'The Return',
            durationMs: 180000,
          ),
          clientId: 'test',
          sync: sync,
        );
        await next.start();
        await tester.pump(const Duration(seconds: 30));
        await settle(tester);
        expect(engine.speed, 1.1, reason: 'its own stored rate');
        expect(repo.putBookSettingsCalls, isEmpty);
        await done(tester, sync, [next]);
      });

      testWidgets('ten speed presses and a boost tap against a hanging '
          'server keep the rate and the chip live, answer each press at '
          'once, and make one read and one write once it answers', (
        tester,
      ) async {
        final (repo, sync) = await notKnown(
          tester,
          book: storedBook(
            settings: const BookSettings(
              speed: 1.0,
              trimSilence: true,
              voiceBoost: false,
            ),
          ),
        );
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        unawaited(session.start());
        await tester.pump(wait);
        await settle(tester);
        expect(engine.loadedUrl, part1);

        var answered = 0;
        for (var i = 1; i <= 10; i++) {
          unawaited(session.setSpeed(1 + i / 20).then((_) => answered++));
        }
        bool? took;
        unawaited(session.setVoiceBoost(true).then((v) => took = v));
        await settle(tester);
        expect(answered, 10, reason: 'as a routed set-rate is answered');
        expect(engine.speed, 1.5);
        expect(session.voiceBoost.value, isTrue);
        expect(reads(repo), 1);

        repo.answerConfig();
        await settle(tester);
        expect(reads(repo), 2);
        expect(repo.putBookSettingsCalls.map((c) => _stored(c.settings)), [
          (speed: 1.5, voiceBoost: true, trimSilence: true),
        ]);
        expect(took, isTrue);
        await done(tester, sync, [session]);
      });

      testWidgets('ten speed presses and a boost tap made while the stored '
          'settings read hangs make no read of their own once it fails for '
          'want of the server, and one read and one write at its return', (
        tester,
      ) async {
        final (repo, sync, link) = await cutOff(
          tester,
          book: storedBook(
            settings: const BookSettings(
              speed: 1.0,
              trimSilence: true,
              voiceBoost: false,
            ),
          ),
        );
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        unawaited(session.start());
        await settle(tester);
        expect(engine.loadedUrl, part1);

        for (var i = 1; i <= 10; i++) {
          unawaited(session.setSpeed(1 + i / 20));
        }
        bool? took;
        unawaited(session.setVoiceBoost(true).then((v) => took = v));
        await settle(tester);
        expect(took, isNull, reason: 'the read still out');

        repo.failConfig(unreachable);
        await settle(tester);
        expect(took, isTrue, reason: 'kept');
        expect(reads(repo), 1);
        expect(engine.speed, 1.5);
        expect(session.voiceBoost.value, isTrue);

        repo.answerConfig();
        await back(tester, sync, link);
        expect(reads(repo), 2);
        expect(repo.putBookSettingsCalls.map((c) => _stored(c.settings)), [
          (speed: 1.5, voiceBoost: true, trimSilence: true),
        ]);
        await done(tester, sync, [session]);
      });

      testWidgets('a waiting boost a speed tap stores reopens the stream for '
          'it', (tester) async {
        final (repo, sync, _) = await inReach(
          tester,
          book: storedBook(
            settings: const BookSettings(
              speed: 1.5,
              trimSilence: false,
              voiceBoost: false,
            ),
          ),
        );
        repo.failConfig(unreachable);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        await session.start();
        bool? took;
        unawaited(session.setVoiceBoost(true).then((v) => took = v));
        await settle(tester);
        expect(took, isTrue, reason: 'kept');
        expect(repo.putBookSettingsCalls, isEmpty);
        final loads = engine.loadedUrls.length;

        repo.answerConfig();
        unawaited(session.setSpeed(1.25));
        await settle(tester);
        expect(repo.putBookSettingsCalls.map((c) => _stored(c.settings)), [
          (speed: 1.25, voiceBoost: true, trimSilence: false),
        ]);
        expect(
          engine.loadedUrls,
          hasLength(loads + 1),
          reason: 'the boost made audible',
        );
        await done(tester, sync, [session]);
      });

      testWidgets('a store under way when its session is let go finishes for '
          'its own item, and touches nothing of the session', (tester) async {
        final (repo, sync) = await notKnown(
          tester,
          book: storedBook(
            settings: const BookSettings(
              speed: 1.5,
              trimSilence: true,
              voiceBoost: false,
            ),
          ),
        );
        await mirrored(bookPid, 90000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        unawaited(session.start());
        await tester.pump(wait);
        await settle(tester);
        unawaited(session.setSpeed(1.25));
        bool? took;
        unawaited(session.setVoiceBoost(true).then((v) => took = v));
        await settle(tester);
        await session.dispose();

        repo
          ..putBookSettingsError = _refused
          ..answerConfig();
        await settle(tester);
        expect(repo.putBookSettingsCalls.map((c) => _stored(c.settings)), [
          (speed: 1.25, voiceBoost: true, trimSilence: true),
        ]);
        expect(took, isFalse);
        await done(tester, sync, const []);
      });
    });

    group('with the socket up', () {
      /// A server answering every read, its socket up.
      Future<(_Holding, SyncEngine)> socketUp(
        WidgetTester tester, {
        BookDetail? book,
      }) async {
        final repo = _Holding(book: book)
          ..answerReads()
          ..answerConfig();
        final sync = await engineOver(tester, repo, FakeLink().factory);
        expect(sync.current.online, isTrue);
        return (repo, sync);
      }

      /// Nothing the engine was handed came from the server, and the server
      /// was asked for no stream.
      void noMediaAsked(FakeEngine engine, _Holding repo) {
        expect(engine.loadedUrls, isNotEmpty);
        expect(engine.loadedUrls, everyElement(startsWith('file://')));
        expect(repo.playInfoCalls, isEmpty);
        expect(repo.asked.where((a) => a.startsWith('play-info')), isEmpty);
      }

      final track = Uri.file('/downloads/AAA.flac').toString();
      final episodeCopy = Uri.file('/downloads/EP.mp3').toString();

      testWidgets('a downloaded track plays the device copy at the server\'s '
          'position, asking the server for no media', (tester) async {
        final (repo, sync) = await socketUp(tester);
        repo.playPositions['tr-AAA'] = 15000;
        await mirrored('tr-AAA', 42000);
        final engine = FakeEngine();
        final session = trackSession(repo, sync, engine);

        await session.start();

        expect(engine.loadedUrls, [track]);
        expect(engine.position, const Duration(seconds: 15));
        expect(engine.playing, isTrue);
        noMediaAsked(engine, repo);
        await done(tester, sync, [session]);
      });

      testWidgets('a downloaded episode plays the device copy at the server\'s '
          'position and its show\'s stored rate, asking the server for no '
          'media', (tester) async {
        final (repo, sync) = await socketUp(tester);
        storedShow(repo, const SubscriptionSettings(speed: 1.5));
        repo.playPositions[episodePid] = 40000;
        await mirrored(episodePid, 90000);
        final engine = FakeEngine();
        final session = episodeSession(repo, sync, engine);

        await session.start();

        expect(engine.loadedUrls, [episodeCopy]);
        expect(engine.position, const Duration(seconds: 40));
        expect(engine.speed, 1.5);
        expect(engine.playing, isTrue);
        noMediaAsked(engine, repo);
        await done(tester, sync, [session]);
      });

      testWidgets('a downloaded episode whose show has voice boost on plays '
          'the server\'s stream, which carries it', (tester) async {
        final (repo, sync) = await socketUp(tester);
        storedShow(
          repo,
          const SubscriptionSettings(speed: 1.5, voiceBoost: true),
        );
        repo
          ..voiceBoostPids.add(episodePid)
          ..playPositions[episodePid] = 40000;
        final engine = FakeEngine();
        final session = episodeSession(repo, sync, engine);

        await session.start();

        expect(repo.playInfoCalls.map((c) => c.pid), contains(episodePid));
        expect(engine.loadedUrls, isNot(contains(episodeCopy)));
        expect(engine.loadedUrl, contains('pid=$episodePid'));
        expect(session.displayPosition, const Duration(seconds: 40));
        expect(engine.speed, 1.5);
        expect(engine.playing, isTrue);
        await done(tester, sync, [session]);
      });

      testWidgets('a downloaded episode with the device default on and '
          'nothing stored plays the server\'s stream, asked for the default', (
        tester,
      ) async {
        final (repo, sync) = await socketUp(tester);
        storedShow(repo, const SubscriptionSettings(speed: 1.5));
        repo
          ..voiceBoostPids.add(episodePid)
          ..playPositions[episodePid] = 40000;
        final engine = FakeEngine();
        final session = episodeSession(
          repo,
          sync,
          engine,
          defaultVoiceBoost: true,
        );

        await session.start();

        expect(session.voiceBoost.value, isTrue);
        expect(engine.loadedUrls, isNot(contains(episodeCopy)));
        expect(engine.loadedUrl, contains('pid=$episodePid'));
        expect(repo.playInfoBoosts, isNotEmpty);
        expect(
          repo.playInfoBoosts,
          everyElement((voiceBoost: null, voiceBoostDefault: true)),
        );
        expect(session.displayPosition, const Duration(seconds: 40));
        expect(engine.speed, 1.5);
        expect(engine.playing, isTrue);
        await done(tester, sync, [session]);
      });

      testWidgets('a downloaded episode whose show stores the boost off plays '
          'the device copy whatever the device default says', (tester) async {
        final (repo, sync) = await socketUp(tester);
        storedShow(repo, const SubscriptionSettings(voiceBoost: false));
        repo.playPositions[episodePid] = 40000;
        final engine = FakeEngine();
        final session = episodeSession(
          repo,
          sync,
          engine,
          defaultVoiceBoost: true,
        );

        await session.start();

        expect(session.voiceBoost.value, isFalse);
        expect(engine.loadedUrls, [episodeCopy]);
        expect(engine.position, const Duration(seconds: 40));
        noMediaAsked(engine, repo);
        await done(tester, sync, [session]);
      });

      testWidgets('a downloaded copy that will not load turns to the '
          'server\'s stream, at the server\'s position', (tester) async {
        final (repo, sync) = await socketUp(tester);
        repo.playPositions['tr-AAA'] = 15000;
        final engine = FakeEngine()..failNextLoad = true;
        final session = trackSession(repo, sync, engine);

        await session.start();

        expect(engine.loadedUrls.first, track);
        expect(engine.loadedUrls, hasLength(2));
        expect(engine.loadedUrl, contains('pid=tr-AAA'));
        expect(engine.position, const Duration(seconds: 15));
        expect(engine.playing, isTrue);
        await done(tester, sync, [session]);
      });

      testWidgets('a downloaded book plays the device\'s parts at the '
          'server\'s position and stored rate, trimmed, part after part', (
        tester,
      ) async {
        final (repo, sync) = await socketUp(tester, book: storedBook());
        repo
          ..playPositions[bookPid] = 75000
          ..skipMaps['$bookPid#1'] = const SkipMap(
            state: 'ready',
            spans: [SkipSpan(startMs: 16000, endMs: 50000)],
          )
          ..skipMaps['$bookPid#2'] = silence;
        await mirrored(bookPid, 100000);
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);

        await session.start();
        await settle(tester);

        expect(engine.loadedUrls, [part1]);
        expect(engine.position, const Duration(seconds: 15));
        expect(engine.speed, 1.5);
        expect(session.trimEnabled.value, isTrue);
        expect(repo.skipMapParts, [1]);
        engine.advance(const Duration(seconds: 1));
        await settle(tester);
        expect(engine.position, const Duration(seconds: 50), reason: 'trimmed');

        engine.advance(const Duration(seconds: 11));
        await settle(tester);
        expect(engine.loadedUrl, Uri.file('/downloads/part2.flac').toString());
        expect(repo.skipMapParts, [1, 2]);
        engine.advance(const Duration(seconds: 1));
        await settle(tester);
        expect(engine.position, const Duration(seconds: 50), reason: 'trimmed');
        expect(session.displayPosition, const Duration(seconds: 170));
        noMediaAsked(engine, repo);
        await done(tester, sync, [session]);
      });

      testWidgets('a device play records its checkpoints and its listens as '
          'a streamed play does', (tester) async {
        final (repo, sync) = await socketUp(tester);

        /// Plays tr-AAA from the server's 15 s to its end at 30 s, pausing
        /// and seeking on the way, and answers what the server was told.
        Future<
          ({
            String? source,
            List<int> checkpoints,
            List<
              ({int msPlayed, bool finished, int? skippedMs, String? client})
            >
            listens,
          })
        >
        play({required bool downloaded}) async {
          repo
            ..playPositions['tr-AAA'] = 15000
            ..putPlayStateCalls.clear()
            ..reportedSessions.clear();
          final engine = FakeEngine(mediaDuration: const Duration(seconds: 30));
          final session = trackSession(
            repo,
            sync,
            engine,
            downloads: downloaded
                ? FakeDownloads(
                    local: {'tr-AAA': testLocal('/downloads/AAA.flac')},
                  )
                : FakeDownloads(),
          );
          await session.start();
          final source = engine.loadedUrl;
          for (var i = 0; i < 6; i++) {
            engine.advance(const Duration(seconds: 1));
            await tester.pump(const Duration(seconds: 1));
          }
          await session.pause();
          await settle(tester);
          await session.seek(const Duration(seconds: 25));
          await session.play();
          await settle(tester);
          for (var i = 0; i < 6; i++) {
            engine.advance(const Duration(seconds: 1));
            await tester.pump(const Duration(seconds: 1));
          }
          await settle(tester);
          await session.dispose();
          await settle(tester);
          return (
            source: source,
            checkpoints: [for (final c in repo.putPlayStateCalls) c.positionMs],
            listens: [
              for (final l in repo.reportedSessions)
                (
                  msPlayed: l.msPlayed,
                  finished: l.finished,
                  skippedMs: l.skippedMs,
                  client: l.client,
                ),
            ],
          );
        }

        final streamed = await play(downloaded: false);
        final device = await play(downloaded: true);

        expect(streamed.source, contains('pid=tr-AAA'));
        expect(device.source, track);
        expect(streamed.checkpoints, isNotEmpty);
        expect(streamed.listens, isNotEmpty);
        expect(streamed.listens.last.finished, isTrue);
        expect(device.checkpoints, streamed.checkpoints);
        expect(device.listens, streamed.listens);
        expect(await db.select(db.outboxMutations).get(), isEmpty);
        expect(await db.select(db.outboxListens).get(), isEmpty);
        await done(tester, sync, const []);
      });

      testWidgets('an item not downloaded streams as it always has, its '
          'stream asked beside the other reads', (tester) async {
        final repo = _Holding();
        final sync = await engineOver(tester, repo, FakeLink().factory);
        expect(sync.current.online, isTrue);
        repo.playPositions['tr-AAA'] = 15000;
        final engine = FakeEngine();
        final session = trackSession(
          repo,
          sync,
          engine,
          downloads: FakeDownloads(),
        );

        unawaited(session.start());
        await settle(tester);
        expect(
          repo.asked,
          containsAll(['play-info tr-AAA', 'play-state tr-AAA']),
        );
        expect(engine.loadedUrl, isNull);

        repo.answerReads();
        await settle(tester);
        expect(engine.loadedUrls, hasLength(1));
        expect(engine.loadedUrl, contains('pid=tr-AAA'));
        expect(engine.position, const Duration(seconds: 15));
        expect(engine.playing, isTrue);
        await done(tester, sync, [session]);
      });

      testWidgets('voice boost turned on while the device copy plays reopens '
          'the item from the server\'s stream, where it stands', (
        tester,
      ) async {
        final (repo, sync) = await socketUp(tester);
        storedShow(repo, const SubscriptionSettings());
        repo
          ..voiceBoostPids.add(episodePid)
          ..playPositions[episodePid] = 40000;
        final engine = FakeEngine();
        final session = episodeSession(repo, sync, engine);
        await session.start();
        expect(engine.loadedUrls, [episodeCopy]);
        engine.advance(const Duration(seconds: 2));
        await settle(tester);

        final took = await session.setVoiceBoost(true);
        await settle(tester);

        expect(took, isTrue);
        expect(
          repo.putSubscriptionSettingsCalls.single.settings.voiceBoost,
          true,
        );
        expect(engine.loadedUrl, contains('pid=$episodePid'));
        expect(session.displayPosition, const Duration(seconds: 42));
        expect(engine.playing, isTrue);
        await done(tester, sync, [session]);
      });

      testWidgets('voice boost turned off while a downloaded item streams for '
          'it goes back to the device copy, where it stands', (tester) async {
        final (repo, sync) = await socketUp(tester);
        storedShow(repo, const SubscriptionSettings(voiceBoost: true));
        repo
          ..voiceBoostPids.add(episodePid)
          ..playPositions[episodePid] = 40000;
        final engine = FakeEngine();
        final session = episodeSession(repo, sync, engine);
        await session.start();
        expect(engine.loadedUrl, contains('pid=$episodePid'));
        engine.advance(const Duration(seconds: 2));
        await settle(tester);
        final mints = repo.playInfoCalls.length;

        final took = await session.setVoiceBoost(false);
        await settle(tester);

        expect(took, isTrue);
        expect(engine.loadedUrl, episodeCopy);
        expect(engine.position, const Duration(seconds: 42));
        expect(engine.playing, isTrue);
        expect(repo.playInfoCalls, hasLength(mints), reason: 'no new stream');
        await done(tester, sync, [session]);
      });

      testWidgets('voice boost turned on while a downloaded book loads a part '
          'switches the book to the server\'s stream', (tester) async {
        final (repo, sync) = await socketUp(tester, book: storedBook());
        repo
          ..voiceBoostPids.add(bookPid)
          ..playPositions[bookPid] = 75000;
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        await session.start();
        expect(engine.loadedUrls, [part1]);

        final gate = Completer<void>();
        engine.loadGate = gate;
        unawaited(session.seek(const Duration(seconds: 130)));
        await settle(tester);
        expect(engine.loadedUrl, Uri.file('/downloads/part2.flac').toString());
        expect(await session.setVoiceBoost(true), isTrue);
        gate.complete();
        await settle(tester);

        expect(engine.loadedUrl, contains('pid=$bookPid&part=2'));
        expect(session.displayPosition, const Duration(seconds: 130));
        expect(engine.playing, isTrue);
        await done(tester, sync, [session]);
      });

      testWidgets('a downloaded book whose stored boost the server will not '
          'mint plays the device\'s parts, unboosted', (tester) async {
        final (repo, sync) = await socketUp(
          tester,
          book: storedBook(
            settings: const BookSettings(
              speed: 1.5,
              trimSilence: true,
              voiceBoost: true,
            ),
          ),
        );
        repo
          ..playPositions[bookPid] = 75000
          ..playInfoError = _capped;
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);

        await session.start();

        expect(engine.loadedUrls, [part1]);
        expect(engine.position, const Duration(seconds: 15));
        expect(engine.speed, 1.5);
        expect(engine.playing, isTrue);
        await done(tester, sync, [session]);
      });

      testWidgets('a downloaded episode whose stored boost the server will not '
          'mint plays the device copy, unboosted', (tester) async {
        final (repo, sync) = await socketUp(tester);
        storedShow(repo, const SubscriptionSettings(voiceBoost: true));
        repo
          ..playPositions[episodePid] = 40000
          ..playInfoError = _capped;
        final engine = FakeEngine();
        final session = episodeSession(repo, sync, engine);

        await session.start();

        expect(engine.loadedUrls, [episodeCopy]);
        expect(engine.position, const Duration(seconds: 40));
        expect(engine.playing, isTrue);
        await done(tester, sync, [session]);
      });

      testWidgets('a boost the server will not mint leaves a downloaded book '
          'on the device, across its next part', (tester) async {
        final (repo, sync) = await socketUp(tester, book: storedBook());
        repo.playPositions[bookPid] = 75000;
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        final failures = <Object>[];
        final sub = session.sessionFailed.listen((f) => failures.add(f.error));
        await session.start();
        expect(engine.loadedUrls, [part1]);

        repo.playInfoError = _capped;
        expect(await session.setVoiceBoost(true), isTrue);
        await settle(tester);
        expect(engine.loadedUrl, part1);
        expect(engine.playing, isTrue);

        engine.advance(const Duration(seconds: 46));
        await settle(tester);

        expect(engine.loadedUrl, Uri.file('/downloads/part2.flac').toString());
        expect(session.displayPosition, const Duration(seconds: 120));
        expect(engine.playing, isTrue);
        expect(failures, isEmpty);
        unawaited(sub.cancel());
        await done(tester, sync, [session]);
      });

      int mintsAsked(_Holding repo) =>
          repo.asked.where((a) => a.startsWith('play-info')).length;

      testWidgets('a boost the server will not mint leaves the device part '
          'playing as it was, not loaded again', (tester) async {
        final (repo, sync) = await socketUp(tester, book: storedBook());
        repo.playPositions[bookPid] = 75000;
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        await session.start();
        engine.advance(const Duration(seconds: 2));
        await settle(tester);
        final seeks = engine.seekCalls.length;
        final at = session.displayPosition;

        repo.playInfoError = _capped;
        expect(await session.setVoiceBoost(true), isTrue);
        await settle(tester);

        expect(mintsAsked(repo), 1);
        expect(engine.loadedUrls, [part1]);
        expect(engine.seekCalls, hasLength(seeks));
        expect(session.displayPosition, at);
        expect(engine.playing, isTrue);
        await done(tester, sync, [session]);
      });

      testWidgets('a boost whose mint finds the server out of reach leaves the '
          'device part playing as it was, and the next part streams once '
          'the server answers', (tester) async {
        final (repo, sync) = await socketUp(tester, book: storedBook());
        repo.playPositions[bookPid] = 75000;
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        await session.start();
        engine.advance(const Duration(seconds: 2));
        await settle(tester);
        final seeks = engine.seekCalls.length;
        final at = session.displayPosition;

        repo.playInfoError = unreachable;
        expect(await session.setVoiceBoost(true), isTrue);
        await settle(tester);

        expect(repo.putBookSettingsCalls.single.settings.voiceBoost, isTrue);
        expect(engine.loadedUrls, [part1]);
        expect(engine.seekCalls, hasLength(seeks));
        expect(session.displayPosition, at);
        expect(engine.playing, isTrue);

        repo.playInfoError = null;
        engine.advance(const Duration(seconds: 44));
        await settle(tester);

        expect(engine.loadedUrl, contains('pid=$bookPid&part=2'));
        expect(session.displayPosition, const Duration(seconds: 120));
        expect(engine.playing, isTrue);
        await done(tester, sync, [session]);
      });

      testWidgets('a boost the server would not mint in a reload is not asked '
          'for again at the book\'s next parts', (tester) async {
        final (repo, sync) = await socketUp(tester, book: storedBook());
        repo.playPositions[bookPid] = 75000;
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        await session.start();
        repo.playInfoError = _capped;
        expect(await session.setVoiceBoost(true), isTrue);
        await settle(tester);
        expect(mintsAsked(repo), 1);

        engine.advance(const Duration(seconds: 46));
        await settle(tester);

        expect(engine.loadedUrl, Uri.file('/downloads/part2.flac').toString());
        expect(session.displayPosition, const Duration(seconds: 120));
        expect(engine.playing, isTrue);
        expect(mintsAsked(repo), 1);
        await done(tester, sync, [session]);
      });

      testWidgets('a stored boost the server would not mint at the start is '
          'not asked for again at the book\'s next parts', (tester) async {
        final (repo, sync) = await socketUp(
          tester,
          book: storedBook(
            settings: const BookSettings(speed: 1.5, voiceBoost: true),
          ),
        );
        repo
          ..playPositions[bookPid] = 75000
          ..playInfoError = _capped;
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        await session.start();
        expect(engine.loadedUrls, [part1]);
        expect(mintsAsked(repo), 1);

        engine.advance(const Duration(seconds: 46));
        await settle(tester);

        expect(engine.loadedUrl, Uri.file('/downloads/part2.flac').toString());
        expect(session.displayPosition, const Duration(seconds: 120));
        expect(engine.playing, isTrue);
        expect(mintsAsked(repo), 1);
        await done(tester, sync, [session]);
      });

      testWidgets('a device copy that fails while playing turns to the '
          'server\'s stream where it stood', (tester) async {
        final (repo, sync) = await socketUp(tester);
        storedShow(repo, const SubscriptionSettings());
        repo.playPositions[episodePid] = 40000;
        final engine = FakeEngine();
        final session = episodeSession(repo, sync, engine);
        final failures = <Object>[];
        final sub = session.sessionFailed.listen((f) => failures.add(f.error));
        await session.start();
        expect(engine.loadedUrls, [episodeCopy]);
        engine.advance(const Duration(seconds: 2));
        await settle(tester);

        engine.failPlayback(fault: MediaFault.source);
        await settle(tester);

        expect(engine.loadedUrl, contains('pid=$episodePid'));
        expect(session.displayPosition, const Duration(seconds: 42));
        expect(engine.playing, isTrue);
        expect(failures, isEmpty);
        unawaited(sub.cancel());
        await done(tester, sync, [session]);
      });

      testWidgets('a downloaded part loaded again keeps its skip map', (
        tester,
      ) async {
        final (repo, sync) = await socketUp(tester, book: storedBook());
        repo
          ..voiceBoostPids.add(bookPid)
          ..playPositions[bookPid] = 75000
          ..skipMaps['$bookPid#1'] = silence;
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(repo, sync, engine);
        await session.start();
        await settle(tester);
        expect(repo.skipMapParts, [1]);

        expect(await session.setVoiceBoost(true), isTrue);
        await settle(tester);
        expect(engine.loadedUrl, contains('part=1'));
        expect(await session.setVoiceBoost(false), isTrue);
        await settle(tester);

        expect(engine.loadedUrl, part1);
        expect(repo.skipMapParts, [1]);
        await done(tester, sync, [session]);
      });

      testWidgets('a downloaded part asks for its skip map when the book\'s '
          'settings read was answered with an error', (tester) async {
        final repo = _Holding(book: storedBook())
          ..answerReads()
          ..failConfig(
            const WaxDeckApiException(
              code: 'not-found',
              message: 'gone',
              statusCode: 404,
            ),
          );
        final sync = await engineOver(tester, repo, FakeLink().factory);
        expect(sync.current.online, isTrue);
        repo
          ..playPositions[bookPid] = 75000
          ..skipMaps['$bookPid#1'] = silence;
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = bookSession(
          repo,
          sync,
          engine,
          defaultTrimSilence: true,
        );

        await session.start();
        await settle(tester);

        expect(engine.loadedUrls, [part1]);
        expect(session.trimEnabled.value, isTrue);
        expect(repo.skipMapParts, [1]);
        await done(tester, sync, [session]);
      });

      testWidgets('the start asks for the play state before the download '
          'lookup answers, and for no stream once it finds a copy', (
        tester,
      ) async {
        final repo = _Holding();
        final sync = await engineOver(tester, repo, FakeLink().factory);
        expect(sync.current.online, isTrue);
        repo.playPositions['tr-AAA'] = 15000;
        final downloads = _HeldDownloads(
          local: {'tr-AAA': testLocal('/downloads/AAA.flac')},
        );
        final engine = FakeEngine();
        final session = trackSession(repo, sync, engine, downloads: downloads);

        unawaited(session.start());
        await settle(tester);
        expect(repo.asked, ['play-state tr-AAA']);

        downloads.lookup.complete();
        await settle(tester);
        expect(repo.asked, ['play-state tr-AAA']);
        repo.answerReads();
        await settle(tester);

        expect(engine.loadedUrls, [track]);
        expect(engine.position, const Duration(seconds: 15));
        await done(tester, sync, [session]);
      });

      testWidgets('an item not downloaded asks for its stream once the '
          'download lookup answers', (tester) async {
        final repo = _Holding();
        final sync = await engineOver(tester, repo, FakeLink().factory);
        repo.playPositions['tr-AAA'] = 15000;
        final downloads = _HeldDownloads();
        final engine = FakeEngine();
        final session = trackSession(repo, sync, engine, downloads: downloads);

        unawaited(session.start());
        await settle(tester);
        expect(repo.asked, ['play-state tr-AAA']);

        downloads.lookup.complete();
        await settle(tester);
        expect(repo.asked, ['play-state tr-AAA', 'play-info tr-AAA']);
        repo.answerReads();
        await settle(tester);

        expect(engine.loadedUrl, contains('pid=tr-AAA'));
        expect(engine.position, const Duration(seconds: 15));
        await done(tester, sync, [session]);
      });

      testWidgets('a downloaded book whose parts no longer match the server\'s '
          'streams', (tester) async {
        final (repo, sync) = await socketUp(tester, book: storedBook());
        repo.playPositions[bookPid] = 75000;
        final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
        final session = PlaybackSession(
          repository: repo,
          engine: engine,
          item: book,
          clientId: 'test',
          sync: sync,
          downloads: FakeDownloads(
            local: {bookPid: testLocalParts(3, partMs: 50000)},
          ),
        );

        await session.start();

        expect(engine.loadedUrls, everyElement(contains('pid=$bookPid')));
        expect(engine.loadedUrl, contains('part=1'));
        expect(session.displayPosition, const Duration(seconds: 75));
        await done(tester, sync, [session]);
      });
    });

    testWidgets('known out of reach, a downloaded book whose parts no longer '
        'match the server\'s plays from the device as before', (tester) async {
      final (repo, sync) = await outOfReach(tester, book: storedBook());
      await mirrored(bookPid, 75000);
      final engine = FakeEngine(mediaDuration: const Duration(minutes: 1));
      final session = PlaybackSession(
        repository: repo,
        engine: engine,
        item: book,
        clientId: 'test',
        sync: sync,
        downloads: FakeDownloads(
          local: {bookPid: testLocalParts(3, partMs: 50000)},
        ),
      );

      await session.start();

      expect(engine.loadedUrls, [part1]);
      expect(session.displayPosition, const Duration(seconds: 75));
      await done(tester, sync, [session]);
    });
  });
}

/// A boosted stream the server will not mint: the caller's transcodes are
/// at their limit.
const _capped = WaxDeckApiException(
  code: 'transcode-limited',
  message: 'too many streams',
  statusCode: 429,
);

/// A write the server refuses.
const _refused = WaxDeckApiException(
  code: 'bad-request',
  message: 'refused',
  statusCode: 400,
);

/// The stored fields of a show's [settings], comparable.
({double? speed, bool? voiceBoost, bool? trimSilence}) _shown(
  SubscriptionSettings settings,
) => (
  speed: settings.speed,
  voiceBoost: settings.voiceBoost,
  trimSilence: settings.trimSilence,
);

/// Every field of a show's [settings] but its filter, comparable.
({
  int? retentionKeep,
  bool autoDownload,
  String? folder,
  bool private,
  double? speed,
  bool? trimSilence,
  bool? voiceBoost,
  int? skipIntroSeconds,
  int? skipOutroSeconds,
})
_everyField(SubscriptionSettings settings) => (
  retentionKeep: settings.retentionKeep,
  autoDownload: settings.autoDownload,
  folder: settings.folder,
  private: settings.private,
  speed: settings.speed,
  trimSilence: settings.trimSilence,
  voiceBoost: settings.voiceBoost,
  skipIntroSeconds: settings.skipIntroSeconds,
  skipOutroSeconds: settings.skipOutroSeconds,
);

/// The stored fields of [settings], comparable.
({double? speed, bool? voiceBoost, bool? trimSilence}) _stored(
  BookSettings settings,
) => (
  speed: settings.speed,
  voiceBoost: settings.voiceBoost,
  trimSilence: settings.trimSilence,
);

/// A first connect that never answers: the engine connecting, nothing
/// failed.
EventsChannel _heldConnects({
  required void Function(String) onFrame,
  required void Function() onDone,
  required Future<String> Function() subscribe,
}) => _HeldChannel(onFrame: onFrame, onDone: onDone, subscribe: subscribe);

class _HeldChannel extends EventsChannel {
  _HeldChannel({
    required super.onFrame,
    required super.onDone,
    required super.subscribe,
  }) : super(url: 'ws://held', authToken: null);

  @override
  Future<void> connect() => Completer<void>().future;

  @override
  Future<void> close() async {}
}

/// A server that takes a start's reads and holds them: play-info and
/// play-state until [answerReads] or [failReads], the item's config until
/// [answerConfig]; as one behind a connect that hangs, until it is let go.
class _Holding extends FakeRepository {
  _Holding({BookDetail? book}) : super(items: [testItem('tr-AAA')]) {
    if (book != null) books[book.pid] = book;
  }

  final _reads = Completer<void>();
  final _config = Completer<void>();
  Object? _configError;

  /// Config reads held one each, the next read first.
  final _configHolds = <Completer<Object?>>[];

  /// Holds the next config read until the hold this returns completes: with
  /// nothing it answers as the other reads do, with an error it fails so.
  Completer<Object?> holdNextConfig() {
    final hold = Completer<Object?>();
    _configHolds.add(hold);
    return hold;
  }

  /// While set, each book-settings write is held, to be answered or
  /// refused by the test.
  bool holdBookWrites = false;
  final bookWrites = <_HeldWrite>[];

  /// What a book-settings or show-settings write throws while set, the
  /// write recorded as made.
  WaxDeckApiException? putBookSettingsError;
  WaxDeckApiException? putSubscriptionSettingsError;

  /// What a start asked of it.
  final asked = <String>[];

  /// Whose skip maps were asked for.
  final skipMapsAsked = <String>[];

  /// Which parts' skip maps were asked for.
  final skipMapParts = <int?>[];

  void answerReads() => _reads.complete();

  /// The held reads fail with [error], as a connect's deadline fails them.
  void failReads(Object error) {
    _reads.future.ignore();
    _reads.completeError(error);
  }

  /// Config reads answer from now on.
  void answerConfig() {
    _configError = null;
    if (!_config.isCompleted) _config.complete();
  }

  /// Config reads, held and later, fail with [error] until [answerConfig].
  void failConfig(Object error) {
    _configError = error;
    if (!_config.isCompleted) _config.complete();
  }

  @override
  Future<PlayInfo> getPlayInfo(
    String pid, {
    int? positionMs,
    bool? voiceBoost,
    bool? voiceBoostDefault,
    int? maxBitrateKbps,
    bool? hls,
  }) async {
    asked.add('play-info $pid');
    await _reads.future;
    return super.getPlayInfo(
      pid,
      positionMs: positionMs,
      voiceBoost: voiceBoost,
      voiceBoostDefault: voiceBoostDefault,
      maxBitrateKbps: maxBitrateKbps,
      hls: hls,
    );
  }

  @override
  Future<PlayState> getPlayState(String pid) async {
    asked.add('play-state $pid');
    await _reads.future;
    return super.getPlayState(pid);
  }

  @override
  Future<BookDetail> getBook(String pid) async {
    asked.add('book $pid');
    await _configRead();
    return super.getBook(pid);
  }

  @override
  Future<PodcastDetail> getPodcast(String pid) async {
    asked.add('show $pid');
    await _configRead();
    return super.getPodcast(pid);
  }

  Future<void> _configRead() async {
    final hold = _configHolds.isEmpty ? null : _configHolds.removeAt(0);
    await _config.future;
    if (await hold?.future case final error?) throw error;
    if (_configError case final error?) throw error;
  }

  @override
  Future<Subscription> putSubscriptionSettings(
    String pid,
    SubscriptionSettings settings,
  ) {
    if (putSubscriptionSettingsError case final error?) {
      putSubscriptionSettingsCalls.add((pid: pid, settings: settings));
      throw error;
    }
    return super.putSubscriptionSettings(pid, settings);
  }

  @override
  Future<BookSettings> putBookSettings(
    String pid,
    BookSettings settings,
  ) async {
    if (putBookSettingsError case final error?) {
      putBookSettingsCalls.add((pid: pid, settings: settings));
      throw error;
    }
    if (holdBookWrites) {
      final write = _HeldWrite(settings);
      bookWrites.add(write);
      if (await write._answer.future case final error?) {
        putBookSettingsCalls.add((pid: pid, settings: settings));
        throw error;
      }
    }
    return super.putBookSettings(pid, settings);
  }

  @override
  Future<SkipMap> getSkipMap(String pid, {int? partIndex}) {
    skipMapsAsked.add(pid);
    skipMapParts.add(partIndex);
    return super.getSkipMap(pid, partIndex: partIndex);
  }
}

/// Downloads that count how often a start looks one up.
class _CountingDownloads extends FakeDownloads {
  _CountingDownloads({super.local});

  var lookedUp = 0;

  @override
  Future<LocalPlayback?> localFor(String pid) {
    lookedUp++;
    return super.localFor(pid);
  }
}

/// Downloads whose lookup is held until [lookup] completes.
class _HeldDownloads extends FakeDownloads {
  _HeldDownloads({super.local});

  final lookup = Completer<void>();

  @override
  Future<LocalPlayback?> localFor(String pid) async {
    await lookup.future;
    return super.localFor(pid);
  }
}

/// A book-settings write the server holds until the test answers it.
class _HeldWrite {
  _HeldWrite(this.settings);

  final BookSettings settings;
  final _answer = Completer<Object?>();

  void answer() => _answer.complete();

  void refuse(Object error) => _answer.complete(error);
}
