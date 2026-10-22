import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/playback_session.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player/waxdeck_player.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

const _trackPid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';
const _episodePid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';
const _showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
const _bookPid = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';

/// A clock a test can move without waiting.
class _Clock {
  DateTime now = DateTime.utc(2026, 10, 16, 12);

  DateTime call() => now;

  void advance(Duration by) => now = now.add(by);
}

/// An engine whose media reports no length, as a stream nothing has
/// measured; it plays on all the same, to an end at [runsFor].
class _LengthlessEngine extends FakeEngine {
  _LengthlessEngine(Duration runsFor) : super(mediaDuration: runsFor);

  @override
  Duration? get duration => null;
}

/// A book in [count] parts of a minute each, whose own length says
/// [totalMs] (its chapter timeline can run past the parts).
BookDetail _book({int count = 2, int? totalMs}) => BookDetail(
  pid: _bookPid,
  title: 'There And Back Again',
  authors: const ['B. Baggins'],
  narrators: const ['Frodo'],
  durationMs: totalMs ?? count * 60000,
  chapters: const [],
  parts: [
    for (var i = 0; i < count; i++)
      BookPart(index: i, startMs: i * 60000, durationMs: 60000),
  ],
);

ItemSummary _bookItem({int durationMs = 120000}) => ItemSummary(
  pid: _bookPid,
  mediaType: MediaType.audiobook,
  title: 'There And Back Again',
  durationMs: durationMs,
);

/// Every load a session makes of its own (the first, a reload, a move into
/// another part, a replay) is one thing under way: a press made meanwhile
/// changes what it ends with, a seek made meanwhile changes where it lands,
/// and nothing starts a second load beside it.
void main() {
  late _Clock clock;
  late FakeRepository repo;
  late FakeEngine engine;
  late List<SessionFailure> failures;

  setUp(() {
    clock = _Clock();
    repo = FakeRepository(items: [testItem(_trackPid)])
      ..numberMints = true
      ..playInfoClock = clock.call
      ..playInfoLifetime = const Duration(minutes: 15);
    engine = FakeEngine(mediaDuration: const Duration(milliseconds: 214000));
    failures = <SessionFailure>[];
  });

  Future<void> settle() => pumpEventQueue();

  PlaybackSession build(ItemSummary item, {FakeDownloads? downloads}) {
    final session = PlaybackSession(
      repository: repo,
      engine: engine,
      item: item,
      clientId: 'test',
      clock: clock.call,
      downloads: downloads,
      initialPositionMs: 0,
    );
    session.sessionFailed.listen(failures.add);
    addTearDown(session.dispose);
    return session;
  }

  Future<PlaybackSession> started({
    ItemSummary? item,
    FakeDownloads? downloads,
  }) async {
    final session = build(item ?? testItem(_trackPid), downloads: downloads);
    await session.start();
    return session;
  }

  Future<PlaybackSession> startedBook({int count = 2, int? totalMs}) {
    repo.books[_bookPid] = _book(count: count, totalMs: totalMs);
    engine.mediaDuration = const Duration(minutes: 1);
    return started(item: _bookItem(durationMs: totalMs ?? count * 60000));
  }

  /// A stream the server re-encodes on an engine that restarts such a
  /// stream at any seek (ExoPlayer): every move is a fresh cut.
  Future<PlaybackSession> startedCut() {
    repo.transcodedPids.add(_trackPid);
    engine.seeksWithinUnrangedStream = false;
    return started();
  }

  /// Holds every mint until the returned gate is completed.
  Completer<void> holdMints() {
    final gate = Completer<void>();
    repo.playInfoGate = gate;
    return gate;
  }

  void letMintsGo(Completer<void> gate) {
    repo.playInfoGate = null;
    gate.complete();
  }

  group('a press made while the session loads', () {
    test('keeps a book paused that a pause stopped while it moved into '
        'another part', () async {
      final session = await startedBook();
      final gate = holdMints();
      final moving = session.seek(const Duration(seconds: 90));
      await settle();
      expect(session.meansToPlay, isTrue, reason: 'it was playing');
      await session.toggle();
      expect(session.meansToPlay, isFalse);
      letMintsGo(gate);
      expect(await moving, isTrue);
      await settle();
      expect(engine.loadedUrl, contains('part=1'));
      expect(engine.position, const Duration(seconds: 30));
      expect(engine.playing, isFalse);
    });

    test('keeps a book paused that a pause stopped while it rolled into '
        'its next part', () async {
      final session = await startedBook();
      final gate = holdMints();
      engine.advance(const Duration(seconds: 61));
      await settle();
      await session.toggle();
      letMintsGo(gate);
      await settle();
      expect(engine.loadedUrl, contains('part=1'));
      expect(engine.playing, isFalse);
      expect(failures, isEmpty);
    });

    test('plays the next part, from its head, when play is pressed while an '
        'end-of-chapter stop loads it', () async {
      final session = await startedBook();
      session.stopAt(60000);
      final gate = holdMints();
      engine.advance(const Duration(seconds: 61));
      await settle();
      expect(engine.playing, isFalse, reason: 'the stop paused it');
      await session.play();
      letMintsGo(gate);
      await settle();
      expect(
        engine.loadedUrls.where((url) => url.contains('part=0')),
        hasLength(1),
        reason: 'nothing went back to the top of the book',
      );
      expect(engine.loadedUrl, contains('part=1'));
      expect(engine.position, Duration.zero);
      expect(engine.playing, isTrue);
      expect(failures, isEmpty);
    });

    test(
      'keeps a replay paused that a pause stopped while it reloaded',
      () async {
        final session = await startedCut();
        engine.advance(const Duration(seconds: 215));
        await settle();
        expect(engine.processingState, EngineProcessingState.completed);
        final gate = holdMints();
        final replaying = session.replay();
        await settle();
        await session.pause();
        letMintsGo(gate);
        await replaying;
        await settle();
        expect(engine.position, Duration.zero);
        expect(engine.playing, isFalse);
      },
    );
  });

  group('a move made while the session loads', () {
    test(
      'lands once, at the newest of two quick moves into other parts',
      () async {
        final session = await startedBook(count: 3);
        final gate = holdMints();
        final first = session.seek(const Duration(seconds: 70));
        await settle();
        final second = session.seek(const Duration(seconds: 150));
        await settle();
        letMintsGo(gate);
        expect(await first, isTrue);
        expect(await second, isTrue);
        await settle();
        expect(failures, isEmpty);
        expect(
          engine.loadedUrls.where((url) => url.contains('part=1')),
          isEmpty,
          reason: 'the target in between is never loaded',
        );
        expect(engine.loadedUrl, contains('part=2'));
        expect(engine.position, const Duration(seconds: 30));
        expect(engine.playing, isTrue);
      },
    );

    test('counts from where the reload is going, not from the media it '
        'replaces', () async {
      final session = await startedCut();
      final gate = holdMints();
      unawaited(
        session.seek(session.displayPosition + const Duration(seconds: 30)),
      );
      await settle();
      expect(session.displayPosition, const Duration(seconds: 30));
      unawaited(
        session.seek(session.displayPosition + const Duration(seconds: 30)),
      );
      await settle();
      letMintsGo(gate);
      await settle();
      expect(repo.playInfoCalls.last.positionMs, 60000);
      expect(session.displayPosition, const Duration(seconds: 60));
    });

    test('is dropped with a reload whose mint fails, and answers that it did '
        'not land', () async {
      final episode = testEpisode(_episodePid, durationMs: 600000);
      repo
        ..addSubscription(testShow(_showPid))
        ..episodesByShow[_showPid] = [episode];
      engine.mediaDuration = const Duration(minutes: 10);
      final session = await started(item: episode);
      engine.advance(const Duration(minutes: 1));
      await settle();
      final gate = holdMints();
      repo.playInfoFailures.add(
        const WaxDeckApiException(code: 'transport', message: 'offline'),
      );
      final boosting = session.setVoiceBoost(true);
      await settle();
      final seeking = session.seek(const Duration(minutes: 5));
      await settle();
      letMintsGo(gate);
      await boosting;
      expect(await seeking, isFalse, reason: 'nothing moved');
      await settle();
      expect(engine.position, const Duration(minutes: 1));
      expect(engine.playing, isTrue);

      // The next reload starts from where the listener stands, not from a
      // target the failed one carried.
      await session.pause();
      clock.advance(const Duration(minutes: 20));
      await session.play();
      await settle();
      expect(repo.playInfoCalls.last.positionMs, 60000);
      expect(engine.position, const Duration(minutes: 1));
    });
  });

  group('a move whose mint fails before any load', () {
    test('keeps the media playing where it was', () async {
      final session = await startedCut();
      engine.advance(const Duration(minutes: 1));
      await settle();
      repo.playInfoFailures.add(
        const WaxDeckApiException(code: 'transport', message: 'offline'),
      );
      expect(
        await session.seek(const Duration(seconds: 75)),
        isFalse,
        reason: 'it did not land',
      );
      await settle();
      expect(failures, isEmpty);
      expect(engine.playing, isTrue);
      expect(session.displayPosition, const Duration(minutes: 1));
    });
  });

  group('before the first load', () {
    test(
      'a seek lands once the load does, and moves nothing before it',
      () async {
        await engine.load('/media/stream?pid=previous');
        await engine.play();
        engine.advance(const Duration(seconds: 45));
        final gate = holdMints();
        final session = build(testItem(_trackPid));
        final starting = session.start();
        await settle();
        final seeking = session.seek(const Duration(seconds: 75));
        await settle();
        expect(engine.position, const Duration(seconds: 45), reason: 'not yet');
        letMintsGo(gate);
        await starting;
        expect(await seeking, isTrue);
        await settle();
        expect(engine.loadedUrl, contains(_trackPid));
        expect(engine.position, const Duration(seconds: 75));
        expect(engine.playing, isTrue);
        expect(
          repo.putPlayStateCalls.where((c) => c.pid == 'previous'),
          isEmpty,
        );
      },
    );

    test('a pause lands the start paused', () async {
      final gate = holdMints();
      final session = build(testItem(_trackPid));
      final starting = session.start();
      await settle();
      await session.pause();
      letMintsGo(gate);
      await starting;
      await settle();
      expect(engine.loadedUrl, contains(_trackPid));
      expect(engine.playing, isFalse);
    });

    test('a book with no measured length resumes where it stopped, over a '
        'shorter item still loaded', () async {
      await engine.load('/media/stream?pid=previous');
      repo.books[_bookPid] = _book(count: 1, totalMs: 0);
      repo.playPositions[_bookPid] = 2400000;
      final session = PlaybackSession(
        repository: repo,
        engine: engine,
        item: _bookItem(durationMs: 0),
        clientId: 'test',
        clock: clock.call,
      );
      addTearDown(session.dispose);
      await session.start();
      expect(repo.playInfoCalls.last.positionMs, 2400000);
    });
  });

  group('a replay', () {
    test('of an item whose token lapsed at its end mints it again', () async {
      final session = await started();
      engine.advance(const Duration(seconds: 215));
      await settle();
      clock.advance(const Duration(minutes: 20));
      await session.play();
      await settle();
      expect(repo.playInfoCalls, hasLength(2));
      expect(engine.loadedUrl, contains('mt=2'));
      expect(engine.position, Duration.zero);
      expect(engine.playing, isTrue);
    });
  });

  test('a book in one file trims its silences from the first load', () async {
    // The server names no part for a book that is one file, so the part
    // the map was fetched for and the part loaded both read as none.
    repo
      ..books[_bookPid] = const BookDetail(
        pid: _bookPid,
        title: 'There And Back Again',
        authors: ['B. Baggins'],
        narrators: ['Frodo'],
        durationMs: 120000,
        chapters: [],
        parts: [],
        settings: BookSettings(trimSilence: true),
      )
      ..skipMaps[_bookPid] = const SkipMap(
        state: 'ready',
        spans: [SkipSpan(startMs: 10000, endMs: 20000)],
      );
    engine.mediaDuration = const Duration(minutes: 2);
    await started(item: _bookItem());
    await settle();
    engine.advance(const Duration(seconds: 12));
    await settle();
    expect(engine.seekCalls, contains(const Duration(seconds: 20)));
  });

  group('the end of a book', () {
    test('a seek to its very end lands short of the last part end', () async {
      final session = await startedBook();
      expect(await session.seek(const Duration(seconds: 120)), isTrue);
      expect(engine.loadedUrl, contains('part=1'));
      expect(engine.position, const Duration(seconds: 59));
    });

    test('an end-of-chapter stop past where the last part ends still holds '
        'the end', () async {
      final session = await startedBook(totalMs: 121000);
      final ends = <Object?>[];
      session.sessionCompleted.listen(ends.add);
      await session.seek(const Duration(seconds: 110));
      session.stopAt(121000);
      engine.advance(const Duration(seconds: 11));
      await settle();
      expect(ends, isEmpty, reason: 'the queue does not move under a sleeper');
      expect(engine.playing, isFalse);
    });

    test('the media ending again after a held end moves nothing', () async {
      final session = await startedBook();
      await session.seek(const Duration(seconds: 115));
      session.stopAt(120000);
      engine.advance(const Duration(seconds: 5));
      await settle();
      final ends = <Object?>[];
      session.sessionCompleted.listen(ends.add);
      engine.announceEnd();
      await settle();
      expect(ends, isEmpty);
    });
  });

  test('a stop the outgoing media crosses while a reload mints starts no '
      'load of its own', () async {
    final session = await startedCut();
    engine.advance(const Duration(seconds: 59));
    await settle();
    session.stopAt(60000);
    final gate = holdMints();
    final back = session.seek(const Duration(seconds: 50));
    await settle();
    // The media being replaced plays on while the mint is out, across the
    // boundary.
    engine.advance(const Duration(seconds: 2));
    await settle();
    final further = session.seek(const Duration(seconds: 40));
    await settle();
    letMintsGo(gate);
    expect(await back, isTrue);
    expect(await further, isTrue);
    await settle();
    expect(engine.loadedUrls, hasLength(2), reason: 'one load, the newest');
    expect(engine.loadedUrl, contains('&t=40'));
    expect(engine.playing, isTrue);
    expect(failures, isEmpty);
  });

  test('a seek back past an outro cutoff is written where it went, and the '
      'cutoff stops it again', () async {
    final episode = testEpisode(_episodePid, durationMs: 600000);
    repo
      ..addSubscription(
        testShow(_showPid),
        settings: const SubscriptionSettings(skipOutroSeconds: 300),
      )
      ..episodesByShow[_showPid] = [episode];
    engine.mediaDuration = const Duration(minutes: 10);
    final session = await started(item: episode);
    await session.seek(const Duration(seconds: 298));
    engine.advance(const Duration(seconds: 2));
    await settle();
    expect(engine.playing, isFalse, reason: 'the outro cutoff paused it');

    await session.seek(const Duration(seconds: 10));
    await session.play();
    engine.advance(const Duration(seconds: 2));
    await settle();
    await session.pause();
    await settle();
    expect(repo.putPlayStateCalls.last.positionMs, 12000);

    await session.seek(const Duration(seconds: 298));
    await session.play();
    engine.advance(const Duration(seconds: 2));
    await settle();
    expect(engine.playing, isFalse, reason: 'the cutoff stopped it again');
    await session.dispose();
    expect(repo.putPlayStateCalls.last.positionMs, 600000);
  });

  test(
    'a seek back past an outro cutoff is where letting go writes it',
    () async {
      final episode = testEpisode(_episodePid, durationMs: 600000);
      repo
        ..addSubscription(
          testShow(_showPid),
          settings: const SubscriptionSettings(skipOutroSeconds: 300),
        )
        ..episodesByShow[_showPid] = [episode];
      engine.mediaDuration = const Duration(minutes: 10);
      final session = await started(item: episode);
      await session.seek(const Duration(seconds: 298));
      engine.advance(const Duration(seconds: 2));
      await settle();
      expect(engine.playing, isFalse, reason: 'the outro cutoff paused it');

      await session.seek(const Duration(seconds: 10));
      await session.play();
      engine.advance(const Duration(seconds: 2));
      await settle();
      await session.dispose();
      expect(repo.putPlayStateCalls.last.positionMs, 12000);
    },
  );

  group('an outro cutoff on an episode streamed from its feed', () {
    // The feed declares ten minutes for twenty minutes of audio.
    final episode = testEpisode(
      _episodePid,
      durationMs: 600000,
      downloaded: false,
    );

    setUp(() {
      repo
        ..addSubscription(
          testShow(_showPid),
          settings: const SubscriptionSettings(skipOutroSeconds: 300),
        )
        ..episodesByShow[_showPid] = [episode];
    });

    test(
      'counts back from the end of the audio, not the declared length',
      () async {
        engine.mediaDuration = const Duration(minutes: 20);
        final session = await started(item: episode);
        await session.seek(const Duration(seconds: 298));
        engine.advance(const Duration(seconds: 2));
        await settle();
        expect(
          engine.playing,
          isTrue,
          reason: 'mid-audio, whatever the feed says',
        );

        await session.seek(const Duration(seconds: 898));
        engine.advance(const Duration(seconds: 2));
        await settle();
        expect(
          engine.playing,
          isFalse,
          reason: 'five minutes before the audio ends',
        );
        await session.dispose();
        expect(repo.putPlayStateCalls.last.positionMs, 1200000);
      },
    );

    test('cuts nothing where the audio reports no length', () async {
      engine = _LengthlessEngine(const Duration(minutes: 20));
      final session = await started(item: episode);
      await session.seek(const Duration(seconds: 298));
      engine.advance(const Duration(seconds: 2));
      await settle();
      expect(engine.playing, isTrue);
      expect(repo.reportedSessions.where((s) => s.finished), isEmpty);
      await session.dispose();
    });
  });

  test('a stop armed behind the playhead is spent, not reached', () async {
    final session = await started();
    engine.advance(const Duration(seconds: 70));
    await settle();
    final spent = <Object?>[];
    session.stopReached.listen(spent.add);
    session.stopAt(60000);
    engine.advance(const Duration(seconds: 1));
    await settle();
    expect(engine.playing, isTrue);
    expect(engine.position, const Duration(seconds: 71));
    expect(spent, hasLength(1));
  });

  test('a failure said mid-stream keeps where the listener stood when the '
      'engine forgets it', () async {
    final session = await started();
    engine.advance(const Duration(minutes: 2));
    await settle();
    engine.failPlayback(
      refusal: const StreamRefusal(status: 429, code: 'transcode-limited'),
      dropPosition: true,
    );
    await settle();
    expect(failures.single.atMs, 120000);
    await session.dispose();
    expect(repo.putPlayStateCalls.last.positionMs, 120000);
  });

  test('a downloaded item whose stream dies offline plays on from the '
      'download', () async {
    final downloads = FakeDownloads(
      local: {
        _trackPid: testLocal('/downloads/track.flac', durationMs: 214000),
      },
    );
    await started(downloads: downloads);
    engine.advance(const Duration(minutes: 1));
    await settle();
    repo.playInfoError = const WaxDeckApiException(
      code: 'transport',
      message: 'offline',
    );
    engine.failPlayback();
    await settle();
    expect(failures, isEmpty);
    expect(engine.loadedUrl, startsWith('file://'));
    expect(engine.position, const Duration(minutes: 1));
    expect(engine.playing, isTrue);
  });

  group('checkpoints', () {
    test('queued behind a stalled write collapse to the newest', () async {
      final session = await started();
      final stall = Completer<void>();
      repo.putPlayStateGate = stall;
      for (var i = 1; i <= 5; i++) {
        await session.seek(Duration(seconds: 10 * i));
      }
      repo.putPlayStateGate = null;
      stall.complete();
      await settle();
      expect(repo.putPlayStateCalls.map((c) => c.positionMs), [10000, 50000]);
    });

    test(
      'letting go silences the media before writes that may stall',
      () async {
        final session = await started();
        final stall = Completer<void>();
        repo.putPlayStateGate = stall;
        final letting = session.dispose();
        await settle();
        expect(engine.playing, isFalse);
        expect(engine.processingState, EngineProcessingState.idle);
        repo.putPlayStateGate = null;
        stall.complete();
        await letting;
      },
    );
  });

  test(
    'a timeline member crossed into never mints a stream of its own',
    () async {
      final media = TimelineMedia(
        url: '/media/timeline/tl-1.m3u8?mt=t',
        mimeType: 'application/vnd.apple.mpegurl',
        durationMs: 428000,
        envelopeRate: 1000,
        members: const [
          TimelineMember(
            pid: 'tr-a',
            offsetSamples: 0,
            durationSamples: 214000,
          ),
          TimelineMember(
            pid: _trackPid,
            offsetSamples: 214000,
            durationSamples: 214000,
          ),
        ],
        expiresAt: clock.now.add(const Duration(minutes: 15)),
      );
      await engine.loadTimeline(media, member: 1);
      await engine.play();
      final session = PlaybackSession(
        repository: repo,
        engine: engine,
        item: testItem(_trackPid),
        clientId: 'test',
        clock: clock.call,
        timeline: TimelineSlot(media, 1),
      );
      addTearDown(session.dispose);
      await session.adopt(
        PlayInfo(
          pid: _trackPid,
          url: media.url,
          mimeType: media.mimeType,
          durationMs: 214000,
          seekable: true,
          expiresAt: media.expiresAt,
        ),
      );
      await session.pause();
      clock.advance(const Duration(hours: 1));
      await session.play();
      await settle();
      expect(repo.playInfoCalls, isEmpty);
      expect(engine.playing, isTrue);
    },
  );
}
