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

/// A stream the server re-encodes (a bitrate cap, voice boost, a track
/// carved from a rip) answers no range requests, so the media element can
/// move only inside what it has buffered. Anywhere else is reached by
/// asking the server to cut the stream there, and the session adds where
/// it was cut to every position it reports.
void main() {
  late FakeRepository repo;
  late FakeEngine engine;

  setUp(() {
    repo = FakeRepository(items: [testItem(_trackPid)])
      ..transcodedPids.add(_trackPid);
    engine = FakeEngine(mediaDuration: const Duration(milliseconds: 214000))
      // A live encode has only reached so far.
      ..buffered = const Duration(seconds: 10);
  });

  Future<PlaybackSession> started({ItemSummary? item}) async {
    final session = PlaybackSession(
      repository: repo,
      engine: engine,
      item: item ?? testItem(_trackPid),
      clientId: 'test',
      initialPositionMs: item == null ? 0 : null,
    );
    addTearDown(session.dispose);
    await session.start();
    return session;
  }

  Future<void> settle() => pumpEventQueue();

  test('a seek past what is buffered mints the cut and loads it', () async {
    final session = await started();
    expect(await session.seek(const Duration(milliseconds: 90500)), isTrue);

    expect(repo.playInfoCalls.last.positionMs, 90500);
    expect(engine.loadedUrl, contains('&t=90'));
    // The cut lands on the whole second before the target, and the rest
    // is a seek inside media that is already arriving.
    expect(engine.position, const Duration(milliseconds: 500));
    expect(session.displayPosition, const Duration(milliseconds: 90500));
    expect(engine.playing, isTrue, reason: 'it was playing before the seek');
  });

  test('voice boost toggled at the very end starts the item over', () async {
    final episode = testEpisode(_episodePid, durationMs: 600000);
    repo
      ..addSubscription(testShow(_showPid))
      ..episodesByShow[_showPid] = [episode]
      ..transcodedPids.add(_episodePid);
    engine.mediaDuration = const Duration(milliseconds: 600000);
    final session = await started(item: episode);
    engine.advance(const Duration(milliseconds: 600500));
    await settle();

    await session.setVoiceBoost(true);
    await settle();
    expect(engine.loadedUrl, isNot(contains('&t=')));
    expect(session.displayPosition, Duration.zero);
  });

  group('voice boost whose reopen fails', () {
    Future<(PlaybackSession, List<SessionFailure>)> boostable() async {
      final episode = testEpisode(_episodePid, durationMs: 600000);
      repo
        ..addSubscription(testShow(_showPid))
        ..episodesByShow[_showPid] = [episode];
      engine.mediaDuration = const Duration(milliseconds: 600000);
      final session = await started(item: episode);
      final failures = <SessionFailure>[];
      session.sessionFailed.listen(failures.add);
      return (session, failures);
    }

    test('at the load says so, since the old media has stopped', () async {
      final (session, failures) = await boostable();
      engine
        ..failNextLoad = true
        ..loadFault = MediaFault.transport
        ..loadRefusal = const StreamRefusal(
          status: 429,
          code: 'transcode-limited',
        );
      await session.setVoiceBoost(true);
      await settle();
      expect(failures, hasLength(1));
      expect(failures.single.meantToPlay, isTrue);
    });

    test('at the mint keeps playing what it had', () async {
      final (session, failures) = await boostable();
      repo.playInfoFailures.add(
        const WaxDeckApiException(code: 'transport', message: 'offline'),
      );
      await session.setVoiceBoost(true);
      await settle();
      expect(failures, isEmpty);
      expect(engine.playing, isTrue);
    });
  });

  test('voice boost toggled during a reload joins it', () async {
    final episode = testEpisode(_episodePid, durationMs: 600000);
    repo
      ..addSubscription(testShow(_showPid))
      ..episodesByShow[_showPid] = [episode]
      ..transcodedPids.add(_episodePid);
    engine.mediaDuration = const Duration(milliseconds: 600000);
    final session = await started(item: episode);
    final gate = Completer<void>();
    engine.loadGate = gate;
    final seeking = session.seek(const Duration(seconds: 90));
    await settle();
    expect(engine.playing, isFalse, reason: 'the load stopped it');
    final boosting = session.setVoiceBoost(true);
    await settle();
    gate.complete();
    await seeking;
    await boosting;
    await settle();
    expect(engine.playing, isTrue, reason: 'the seek was made playing');
    expect(engine.loadedUrl, contains('&t=90'));
    expect(
      repo.playInfoCalls.last.positionMs,
      90000,
      reason: 'the boost is minted where the listener stands',
    );
  });

  test('voice boost toggled as a reload starts playing is not lost', () async {
    final episode = testEpisode(_episodePid, durationMs: 600000);
    repo
      ..addSubscription(testShow(_showPid))
      ..episodesByShow[_showPid] = [episode]
      ..transcodedPids.add(_episodePid);
    engine.mediaDuration = const Duration(milliseconds: 600000);
    final session = await started(item: episode);
    final gate = Completer<void>();
    engine.playGate = gate;
    final seeking = session.seek(const Duration(seconds: 90));
    await settle();
    expect(gate.isCompleted, isFalse);
    final mints = repo.playInfoCalls.length;
    await session.setVoiceBoost(true);
    gate.complete();
    await seeking;
    await settle();
    expect(
      repo.playInfoCalls.length,
      mints + 1,
      reason: 'the boost is minted once the reload lets go',
    );
    expect(repo.playInfoCalls.last.positionMs, 90000);
    expect(engine.playing, isTrue);
  });

  test('an episode that runs past its feed\'s length is seeked to the end of '
      'its audio', () async {
    // A relayed enclosure's length is the feed's word for it, which an
    // inserted ad outruns; the bar is drawn against the audio's own.
    final episode = testEpisode(_episodePid, durationMs: 600000);
    repo
      ..addSubscription(testShow(_showPid))
      ..episodesByShow[_showPid] = [episode];
    engine.mediaDuration = const Duration(milliseconds: 700000);
    final session = await started(item: episode);
    expect(session.mediaDuration, const Duration(milliseconds: 700000));

    await session.seek(const Duration(milliseconds: 680000));
    expect(session.displayPosition, const Duration(milliseconds: 680000));
    await session.seek(const Duration(milliseconds: 650000));
    await session.seek(session.displayPosition + const Duration(seconds: 30));
    expect(session.displayPosition, const Duration(milliseconds: 680000));
  });

  test(
    'an episode whose feed gave no length is still cut where it resumes',
    () async {
      final episode = testEpisode(_episodePid, durationMs: 0);
      repo
        ..addSubscription(testShow(_showPid))
        ..episodesByShow[_showPid] = [episode]
        ..transcodedPids.add(_episodePid)
        ..playPositions[_episodePid] = 90000;
      final session = PlaybackSession(
        repository: repo,
        engine: engine,
        item: episode,
        clientId: 'test',
      );
      addTearDown(session.dispose);
      await session.start();

      expect(engine.loadedUrl, contains('&t=90'));
      expect(engine.position, Duration.zero);
      expect(session.displayPosition, const Duration(seconds: 90));
    },
  );

  group('an engine that cannot seek inside an unranged stream', () {
    // ExoPlayer restarts a stream that answers no ranges from its head on
    // any seek, so there every move on such a stream is a cut.
    setUp(() => engine.seeksWithinUnrangedStream = false);

    test('a seek inside what is buffered is cut too', () async {
      final session = await started();
      await session.seek(const Duration(seconds: 8));
      expect(repo.playInfoCalls.last.positionMs, 8000);
      expect(engine.loadedUrl, contains('&t=8'));
      expect(session.displayPosition, const Duration(seconds: 8));
    });

    test('a silence is not jumped over', () async {
      final episode = testEpisode(_episodePid, durationMs: 600000);
      repo
        ..addSubscription(
          testShow(_showPid),
          settings: const SubscriptionSettings(trimSilence: true),
        )
        ..episodesByShow[_showPid] = [episode]
        ..transcodedPids.add(_episodePid)
        ..skipMaps[_episodePid] = const SkipMap(
          state: 'ready',
          spans: [SkipSpan(startMs: 2000, endMs: 6000)],
        );
      engine.mediaDuration = const Duration(milliseconds: 600000);
      await started(item: episode);
      await settle();
      for (var i = 0; i < 3; i++) {
        engine.advance(const Duration(seconds: 1));
        await settle();
      }
      expect(engine.seekCalls, isEmpty, reason: 'a seek would restart it');
      expect(engine.loadedUrls, hasLength(1));
    });
  });

  test('a paused cut says where it landed', () async {
    final session = await started();
    await session.pause();
    final shown = <Duration>[];
    final feed = session.displayPositionStream.listen(shown.add);
    addTearDown(feed.cancel);
    // The element reports where the cut stands before its load answers,
    // as a browser's does.
    final gate = Completer<void>();
    engine.loadGate = gate;
    final seeking = session.seek(const Duration(seconds: 90));
    await settle();
    gate.complete();
    await seeking;
    await settle();
    expect(engine.playing, isFalse);
    expect(shown.last, const Duration(seconds: 90));
  });

  test('a pause while the cut is being minted keeps it paused', () async {
    final session = await started();
    final gate = Completer<void>();
    repo.playInfoGate = gate;
    final seeking = session.seek(const Duration(seconds: 90));
    await settle();
    // The outgoing media still plays while the mint is out, so the
    // transport reads Pause and a press means pause.
    expect(engine.playing, isTrue);
    await session.toggle();
    repo.playInfoGate = null;
    gate.complete();
    await seeking;
    await settle();
    expect(engine.loadedUrl, contains('&t=90'));
    expect(engine.playing, isFalse);
  });

  test('a pause from outside while the cut is minted is kept too', () async {
    final session = await started();
    final gate = Completer<void>();
    repo.playInfoGate = gate;
    final seeking = session.seek(const Duration(seconds: 90));
    await settle();
    // The lock screen, a headset, the platform's own interruption: the
    // engine pauses with no word to the session.
    await engine.pause();
    await settle();
    repo.playInfoGate = null;
    gate.complete();
    await seeking;
    await settle();
    expect(engine.playing, isFalse);
  });

  test('the session\'s own pause holds through a reload', () async {
    final session = await started();
    final gate = Completer<void>();
    repo.playInfoGate = gate;
    final seeking = session.seek(const Duration(seconds: 90));
    await settle();
    await session.pause();
    repo.playInfoGate = null;
    gate.complete();
    await seeking;
    await settle();
    expect(engine.playing, isFalse);
  });

  test(
    'a skip pressed while the cut loads counts from where it is going',
    () async {
      final session = await started();
      final gate = Completer<void>();
      engine.loadGate = gate;
      final seeking = session.seek(const Duration(seconds: 90));
      await settle();
      expect(session.displayPosition, const Duration(seconds: 90));

      // The deck's skip: thirty seconds from where the position reads.
      final skip = session.seek(
        session.displayPosition + const Duration(seconds: 30),
      );
      gate.complete();
      await seeking;
      await skip;
      await settle();
      expect(repo.playInfoCalls.last.positionMs, 120000);
    },
  );

  test('a press while the reload loads is a pause, as it reads', () async {
    final session = await started();
    final gate = Completer<void>();
    engine.loadGate = gate;
    final seeking = session.seek(const Duration(seconds: 90));
    await settle();
    expect(engine.playing, isFalse, reason: 'the load stopped it');
    expect(session.meansToPlay, isTrue, reason: 'it reads as playing');

    await session.toggle();
    expect(session.meansToPlay, isFalse);
    gate.complete();
    await seeking;
    await settle();
    expect(engine.playing, isFalse);
  });

  test(
    'a seek inside what is buffered moves the element, mints nothing',
    () async {
      final session = await started();
      await session.seek(const Duration(seconds: 8));
      expect(repo.playInfoCalls, hasLength(1));
      expect(engine.seekCalls.last, const Duration(seconds: 8));
    },
  );

  test('a seek back before the cut cuts again', () async {
    final session = await started();
    await session.seek(const Duration(seconds: 90));
    await session.seek(const Duration(seconds: 20));
    expect(repo.playInfoCalls.last.positionMs, 20000);
    expect(engine.loadedUrl, contains('&t=20'));
    expect(session.displayPosition, const Duration(seconds: 20));
  });

  test('a seek inside a cut stream is relative to the cut', () async {
    final session = await started();
    await session.seek(const Duration(seconds: 90));
    await session.seek(const Duration(seconds: 95));
    expect(repo.playInfoCalls, hasLength(2));
    expect(engine.seekCalls.last, const Duration(seconds: 5));
    expect(session.displayPosition, const Duration(seconds: 95));
  });

  test(
    'seeks made while a cut is being minted load once, at the last',
    () async {
      final session = await started();
      final gate = Completer<void>();
      repo.playInfoGate = gate;
      final first = session.seek(const Duration(seconds: 90));
      await settle();
      // Folded into the load under way, these answer once it lands.
      final second = session.seek(const Duration(seconds: 100));
      final third = session.seek(const Duration(seconds: 120));
      repo.playInfoGate = null;
      gate.complete();
      await first;
      expect(await second, isTrue);
      expect(await third, isTrue);
      await settle();

      // Every distinct cut is a full encode of the rest of the item, so the
      // ones nobody is waiting for are never loaded.
      expect(engine.loadedUrls, hasLength(2));
      expect(engine.loadedUrl, contains('&t=120'));
      expect(session.displayPosition, const Duration(seconds: 120));
    },
  );

  test('positions, checkpoints and the listen add the cut', () async {
    final session = await started();
    await session.seek(const Duration(seconds: 90));
    engine.advance(const Duration(seconds: 2));
    await settle();
    expect(engine.position, const Duration(seconds: 2), reason: 'cut media');
    expect(session.displayPosition, const Duration(seconds: 92));
    await engine.pause();
    await settle();
    expect(repo.putPlayStateCalls.last.positionMs, 92000);
    await session.dispose();
    expect(repo.putPlayStateCalls.last.positionMs, 92000);
  });

  test('a cut reload never checkpoints a half-moved position', () async {
    final session = await started();
    engine.advance(const Duration(seconds: 2));
    await settle();
    engine.advance(const Duration(seconds: 2));
    await settle();
    final before = repo.putPlayStateCalls.length;
    await session.seek(const Duration(seconds: 90));
    await settle();
    final written = repo.putPlayStateCalls
        .skip(before)
        .map((c) => c.positionMs)
        .toList();
    expect(written, isNotEmpty, reason: 'a discrete seek is written');
    expect(written, everyElement(90000));
  });

  test('the seek bar keeps the item\'s length on a cut stream', () async {
    final session = await started();
    // The cut stream's own clock covers only what is left.
    engine.mediaDuration = const Duration(milliseconds: 124000);
    await session.seek(const Duration(seconds: 90));
    expect(engine.duration, const Duration(milliseconds: 124000));
    expect(session.mediaDuration, const Duration(milliseconds: 214000));
  });

  test('a seekable stream is never cut, however little is buffered', () async {
    repo.transcodedPids.clear();
    final session = await started();
    await session.seek(const Duration(seconds: 90));
    expect(repo.playInfoCalls, hasLength(1));
    expect(engine.seekCalls.last, const Duration(seconds: 90));
  });

  test('a resume into a stream that cannot be ranged is cut at the resume '
      'point', () async {
    final episode = testEpisode(_episodePid, durationMs: 600000);
    repo
      ..addSubscription(testShow(_showPid))
      ..episodesByShow[_showPid] = [episode]
      ..transcodedPids.add(_episodePid)
      ..playPositions[_episodePid] = 120000;
    final session = await started(item: episode);

    expect(repo.playInfoCalls.map((c) => c.positionMs), [null, 120000]);
    expect(engine.loadedUrls, hasLength(1));
    expect(engine.loadedUrl, contains('&t=120'));
    expect(
      engine.position,
      Duration.zero,
      reason: 'no seek into a live encode',
    );
    expect(session.displayPosition, const Duration(seconds: 120));
  });

  test('the trim jump and the outro read the file\'s own time', () async {
    final episode = testEpisode(_episodePid, durationMs: 600000);
    repo
      ..addSubscription(
        testShow(_showPid),
        settings: const SubscriptionSettings(
          trimSilence: true,
          skipOutroSeconds: 300,
        ),
      )
      ..episodesByShow[_showPid] = [episode]
      ..transcodedPids.add(_episodePid)
      ..skipMaps[_episodePid] = const SkipMap(
        state: 'ready',
        spans: [SkipSpan(startMs: 95000, endMs: 100000)],
      );
    engine.mediaDuration = const Duration(milliseconds: 600000);
    final session = await started(item: episode);
    await settle();
    await session.seek(const Duration(seconds: 90));

    // Five seconds into the cut is 95 s into the file: inside the span,
    // which ends 10 s into the cut.
    engine.advance(const Duration(seconds: 1));
    await settle();
    engine.advance(const Duration(seconds: 1));
    await settle();
    engine.advance(const Duration(seconds: 1));
    await settle();
    engine.advance(const Duration(seconds: 1));
    await settle();
    engine.advance(const Duration(seconds: 1));
    await settle();
    expect(engine.seekCalls.last, const Duration(seconds: 10));
    expect(session.displayPosition, const Duration(seconds: 100));

    // The outro cuts at 300 s into the file, 1 s into a cut at 299 s.
    await session.seek(const Duration(seconds: 299));
    engine.advance(const Duration(seconds: 2));
    await settle();
    expect(engine.playing, isFalse, reason: 'the outro cutoff paused it');
    await session.dispose();
    expect(repo.putPlayStateCalls.last.positionMs, 600000);
  });
}
