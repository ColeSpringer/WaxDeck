import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/player/session_registry.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player/waxdeck_player.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

/// The messages playback raises carry what to say rather than the words
/// themselves - a notifier has no `BuildContext` to read a locale from -
/// so a test that asserts on one picks the locale here.
final _l10n = AppLocalizationsEn();

const _a = 'tr-01JZX5N8QW3F4V9T2B7KDTRACKA';
const _b = 'tr-01JZX5N8QW3F4V9T2B7KDTRACKB';
const _c = 'tr-01JZX5N8QW3F4V9T2B7KDTRACKC';
const _showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
const _episode = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';

/// Every fake stream is this long, and so is every play-info the fake
/// answers, so a checkpoint at an item's end is an exact number.
const _trackMs = 214000;

const _album = QueueSource(
  kind: QueueSourceKind.album,
  label: 'Kind of Blue',
  pid: 'al-1',
);

({ProviderContainer container, FakeRepository repo, FakeEngine engine})
_harness({List<ItemSummary>? items}) {
  final repo = FakeRepository(
    items: items ?? [testItem(_a), testItem(_b), testItem(_c)],
  );
  final engine = FakeEngine(
    mediaDuration: const Duration(milliseconds: _trackMs),
  );
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      audioEngineProvider.overrideWithValue(engine),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, repo: repo, engine: engine);
}

extension on ProviderContainer {
  NowPlayingController get playback => read(nowPlayingProvider.notifier);
  QueueController get queue => read(queueControllerProvider.notifier);
  QueueState get queueState => read(queueControllerProvider);
}

/// Plays [ms] of media in steps small enough to count as listening
/// (deltas above two seconds read as seeks), letting the engine's events
/// land between them the way a real position stream does.
Future<void> _play(FakeEngine engine, int ms, {int stepMs = 2000}) async {
  for (var played = 0; played < ms; played += stepMs) {
    engine.advance(Duration(milliseconds: stepMs));
    await pumpEventQueue();
  }
}

/// Skips ahead without listening to it, for getting near the end of a
/// track the test does not care about the middle of.
Future<void> _skipTo(FakeEngine engine, int ms) async {
  engine.advance(Duration(milliseconds: ms - engine.position.inMilliseconds));
  await pumpEventQueue();
}

/// Runs the playing item off its end.
Future<void> _runOut(FakeEngine engine) async {
  engine.advance(const Duration(milliseconds: _trackMs + 1000));
  await pumpEventQueue();
}

void main() {
  group('following the queue', () {
    test('playing an item starts a session for it', () async {
      final h = _harness();
      h.container.playback.play([testItem(_a)], source: _album);
      await pumpEventQueue();

      expect(h.engine.loadedUrl, contains(_a));
      expect(h.engine.playing, isTrue);
      expect(h.container.read(nowPlayingProvider).item?.pid, _a);
      expect(h.container.read(nowPlayingProvider).session, isNotNull);
    });

    test('a jump in the queue moves playback to that entry', () async {
      final h = _harness();
      h.container.playback.play([
        testItem(_a),
        testItem(_b),
        testItem(_c),
      ], source: _album);
      await pumpEventQueue();

      h.container.queue.jumpTo(2);
      await pumpEventQueue();

      expect(h.engine.loadedUrl, contains(_c));
      expect(h.container.read(nowPlayingProvider).item?.pid, _c);
    });

    test(
      'a new queue hands the engine over and finalizes the old item',
      () async {
        final h = _harness();
        h.container.playback.play([testItem(_a)], source: _album);
        await pumpEventQueue();
        await _play(h.engine, 4000);

        // A tap somewhere else, while the first item is still playing.
        h.container.playback.play([testItem(_c)], source: _album);
        await pumpEventQueue();

        expect(h.engine.loadedUrl, contains(_c));
        // The engine belongs to the new session, so the old one's teardown
        // cannot stop it.
        expect(h.engine.playing, isTrue);
        final reported = h.repo.reportedSessions.where((s) => s.pid == _a);
        expect(reported, hasLength(1));
        expect(reported.single.msPlayed, 4000);
        expect(reported.single.finished, isFalse);
        expect(h.repo.putPlayStateCalls.last.pid, _a);
        expect(h.repo.putPlayStateCalls.last.positionMs, 4000);
      },
    );

    test('a queue that empties mid-start never gets its media', () async {
      final h = _harness();
      final gate = Completer<void>();
      h.repo.playInfoGate = gate;
      h.container.playback.play([testItem(_a)], source: _album);
      await pumpEventQueue();

      // The listener clears the queue while play-info is still
      // resolving. The session it started has to notice: loading here
      // would put audio on an engine nothing can reach any more.
      h.container.queue.clear();
      await pumpEventQueue();
      h.repo.playInfoGate = null;
      gate.complete();
      await pumpEventQueue();

      expect(h.engine.loadedUrl, isNull);
      expect(h.engine.playing, isFalse);
      expect(h.container.read(nowPlayingProvider).item, isNull);
    });

    test('a start that fails lets go of the engine and Connect', () async {
      final h = _harness();
      h.repo.playInfoError = const WaxDeckApiException(
        code: 'transport',
        message: 'network unreachable',
      );
      h.container.playback.play([testItem(_a)], source: _album);
      await pumpEventQueue();

      // Installed before it was known to work, so it has to be let go
      // of when it is not: a session that never loaded cannot drive the
      // engine, and anything holding it would act on the item before it.
      expect(h.container.read(nowPlayingProvider).error, isNotNull);
      expect(h.container.read(nowPlayingProvider).session, isNull);
      expect(h.container.read(currentSessionRegistryProvider).current, isNull);
    });

    test('an emptied queue stops playback and lets the item go', () async {
      final h = _harness();
      h.container.playback.play([testItem(_a)], source: _album);
      await pumpEventQueue();
      await _play(h.engine, 3000);

      h.container.queue.clear();
      await pumpEventQueue();

      expect(h.engine.playing, isFalse);
      expect(h.container.read(nowPlayingProvider).item, isNull);
      expect(h.repo.reportedSessions, hasLength(1));
      expect(h.repo.reportedSessions.single.pid, _a);
    });

    test(
      'a queue that was there first is picked up when playback wakes',
      () async {
        final h = _harness();
        // The queue built before anything read the playback layer, which
        // is what a restore accepted through a container that never had
        // one looks like.
        h.container.queue.playNow([_a], source: _album);
        await pumpEventQueue();
        expect(h.engine.loadedUrl, isNull);

        h.container.playback;
        await pumpEventQueue();

        expect(h.engine.loadedUrl, contains(_a));
        expect(h.container.read(nowPlayingProvider).item?.pid, _a);
      },
    );

    test('a restored queue comes back paused at its checkpoint', () async {
      final h = _harness();
      h.repo.playPositions[_a] = 60000;

      h.container.playback.restore(
        QueueState.fromStored(
          StoredQueue(
            entries: const [
              StoredQueueEntry(queueId: 'q0', pid: _a, sourceRank: 0),
            ],
            currentIndex: 0,
            shuffled: false,
            repeat: 'off',
            sourceKind: 'album',
            sourceLabel: 'Kind of Blue',
            nextQueueId: 1,
            updatedAt: DateTime.utc(2026, 7, 25),
          ),
        ),
      );
      await pumpEventQueue();

      expect(h.engine.loadedUrl, contains(_a));
      expect(h.engine.position, const Duration(seconds: 60));
      expect(h.engine.playing, isFalse);
    });

    test('restoring a session while playing replaces the audio', () async {
      final h = _harness();
      h.repo.playPositions[_b] = 60000;
      h.container.playback.play([testItem(_a)], source: _album);
      await pumpEventQueue();
      expect(h.engine.loadedUrl, contains(_a));
      expect(h.engine.playing, isTrue);

      // A restored session mints entry ids from zero, and so did the
      // live queue's first playNow: the current ids collide, and the
      // entry-change guard alone saw nothing to do - track A kept
      // playing under B's face forever, with the snackbar naming B.
      h.container.playback.restore(
        QueueState.fromStored(
          StoredQueue(
            entries: const [
              StoredQueueEntry(queueId: 'q0', pid: _b, sourceRank: 0),
            ],
            currentIndex: 0,
            shuffled: false,
            repeat: 'off',
            sourceKind: 'album',
            sourceLabel: 'Blue Train',
            nextQueueId: 1,
            updatedAt: DateTime.utc(2026, 7, 25),
          ),
        ),
      );
      await pumpEventQueue();

      expect(h.engine.loadedUrl, contains(_b));
      expect(h.engine.position, const Duration(seconds: 60));
      expect(
        h.engine.playing,
        isFalse,
        reason: 'restore means put it back, paused',
      );
    });

    test('restoring the identical session reloads it', () async {
      final h = _harness();
      h.repo.playPositions[_a] = 60000;
      h.container.playback.play([testItem(_a)], source: _album);
      await pumpEventQueue();
      expect(h.engine.playing, isTrue);
      expect(h.repo.playInfoCalls.where((c) => c.pid == _a), hasLength(1));

      h.container.playback.restore(
        QueueState.fromStored(
          StoredQueue(
            entries: const [
              StoredQueueEntry(queueId: 'q0', pid: _a, sourceRank: 0),
            ],
            currentIndex: 0,
            shuffled: false,
            repeat: 'off',
            sourceKind: 'album',
            sourceLabel: 'Kind of Blue',
            nextQueueId: 1,
            updatedAt: DateTime.utc(2026, 7, 25),
          ),
        ),
      );
      await pumpEventQueue();

      // A real reload at the checkpoint, not the old load left standing.
      expect(h.repo.playInfoCalls.where((c) => c.pid == _a), hasLength(2));
      expect(h.engine.playing, isFalse);
    });

    test('the pending pause never leaks into a later advance', () async {
      final h = _harness();
      h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
      await pumpEventQueue();

      // A colliding restore: the forced start consumes the paused flag.
      h.container.playback.restore(
        QueueState.fromStored(
          StoredQueue(
            entries: const [
              StoredQueueEntry(queueId: 'q0', pid: _a, sourceRank: 0),
              StoredQueueEntry(queueId: 'q1', pid: _b, sourceRank: 1),
            ],
            currentIndex: 0,
            shuffled: false,
            repeat: 'off',
            sourceKind: 'album',
            sourceLabel: 'Kind of Blue',
            nextQueueId: 2,
            updatedAt: DateTime.utc(2026, 7, 25),
          ),
        ),
      );
      await pumpEventQueue();
      expect(h.engine.playing, isFalse);

      // Pressing play and running A out must start B playing, not
      // stand it silently paused on a flag nothing consumed.
      await h.engine.play();
      await pumpEventQueue();
      await _runOut(h.engine);

      expect(h.container.queueState.currentPid, _b);
      expect(h.engine.playing, isTrue);
    });
  });

  group('the end of an item', () {
    test('running out advances the queue and loads the next entry', () async {
      final h = _harness();
      h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
      await pumpEventQueue();
      await _play(h.engine, 4000);

      // Nothing was preloaded (the engine is not near the end yet), so
      // this is the degraded path the port allows: load on advance.
      await _runOut(h.engine);

      expect(h.container.queueState.currentPid, _b);
      expect(h.engine.loadedUrl, contains(_b));
      expect(h.engine.playing, isTrue);
      // The item that ran out is reported finished, exactly once.
      final finished = h.repo.reportedSessions.where((s) => s.pid == _a);
      expect(finished, hasLength(1));
      expect(finished.single.finished, isTrue);
    });

    test(
      'an engine with no preload window still advances and reports',
      () async {
        // just_audio on the web has no window: appending behind the item
        // playing breaks it, so the port declines and every item ends by
        // running off the end. That path used to be reached only by a
        // queue's last entry - a queue with more to play stopped dead on
        // the track it was on and never reported the listen.
        final h = _harness();
        h.engine.canPreloadWindow = false;
        h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
        await pumpEventQueue();
        // Some of it actually listened to, so the session it reports is a
        // real one, then inside the lead a windowed engine would have
        // prepared on - and nothing was: the app does not pay for a
        // window that is not there.
        await _play(h.engine, 4000);
        await _skipTo(h.engine, 190000);
        expect(h.engine.preloadedUrl, isNull);
        expect(h.repo.playInfoCalls.where((c) => c.pid == _b), isEmpty);

        await _runOut(h.engine);

        expect(h.container.queueState.currentPid, _b);
        expect(h.engine.loadedUrl, contains(_b));
        expect(h.engine.playing, isTrue);
        final finished = h.repo.reportedSessions.where((s) => s.pid == _a);
        expect(finished, hasLength(1));
        expect(finished.single.finished, isTrue);
      },
    );

    test(
      'the last entry ends the queue and keeps showing what played',
      () async {
        final h = _harness();
        h.container.playback.play([testItem(_a)], source: _album);
        await pumpEventQueue();
        await _play(h.engine, 4000);

        await _runOut(h.engine);

        expect(h.engine.playing, isFalse);
        expect(h.container.read(nowPlayingProvider).item?.pid, _a);
        expect(h.repo.reportedSessions.single.finished, isTrue);
      },
    );

    test('repeat-one plays it again as its own listen session', () async {
      final h = _harness();
      h.container.queue.setRepeat(QueueRepeat.one);
      h.container.playback.play([testItem(_a)], source: _album);
      await pumpEventQueue();
      await _play(h.engine, 4000);

      await _runOut(h.engine);

      // Back at the top, playing, with the first pass already reported.
      expect(h.engine.position, Duration.zero);
      expect(h.engine.playing, isTrue);
      expect(h.container.queueState.currentPid, _a);
      expect(h.repo.reportedSessions, hasLength(1));

      await _play(h.engine, 4000);
      h.container.queue.clear();
      await pumpEventQueue();

      expect(h.repo.reportedSessions, hasLength(2));
      expect(
        h.repo.reportedSessions.first.sessionId,
        isNot(h.repo.reportedSessions.last.sessionId),
      );
    });
  });

  group('preloading the next entry', () {
    test('prepares the next item only as the playing one runs out', () async {
      final h = _harness();
      h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
      await pumpEventQueue();

      // Well before the end: nothing is prepared, because the stream URL
      // it would mint expires long before the crossing.
      await _skipTo(h.engine, 60000);
      expect(h.engine.preloadedUrl, isNull);

      await _skipTo(h.engine, 190000);
      expect(h.engine.preloadedUrl, contains(_b));
    });

    test('an entry the queue no longer wants next is dropped', () async {
      final h = _harness();
      h.container.playback.play([
        testItem(_a),
        testItem(_b),
        testItem(_c),
      ], source: _album);
      await pumpEventQueue();
      await _skipTo(h.engine, 190000);
      expect(h.engine.preloadedUrl, contains(_b));

      // Drag the third track above the second: what follows changed.
      h.container.queue.reorder(2, 1);
      await pumpEventQueue();

      expect(h.engine.preloadedUrl, contains(_c));
    });

    test('a cut stream is not prepared, it loads on advance', () async {
      final h = _harness();
      h.repo.transcodedPids.add(_b);
      h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
      await pumpEventQueue();
      await _skipTo(h.engine, 190000);

      expect(h.engine.preloadedUrl, isNull);

      // And the refusal is remembered: the last thirty seconds are
      // hundreds of position ticks, and asking again on each of them
      // mints a stream token per tick for an item that will never be
      // prepared.
      final asked = h.repo.playInfoCalls.where((c) => c.pid == _b).length;
      await _play(h.engine, 10000);
      expect(h.repo.playInfoCalls.where((c) => c.pid == _b), hasLength(asked));
    });

    test('a saved position no longer blocks the arm', () async {
      // It used to: the port prepares an item at the head of its window,
      // so anything that would have resumed elsewhere had to load on
      // advance. Music always starts at the head now, so the guard was
      // refusing the gapless crossing into every track the listener had
      // once heard part of.
      final h = _harness();
      h.repo.playPositions[_b] = 45000;
      h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
      await pumpEventQueue();
      await _skipTo(h.engine, 190000);

      expect(h.engine.preloadedUrl, contains(_b));
    });

    test('a queue edited while an arm is in flight drops it', () async {
      final h = _harness();
      h.container.playback.play([
        testItem(_a),
        testItem(_b),
        testItem(_c),
      ], source: _album);
      await pumpEventQueue();

      // Hold the next item's resolution open and edit the queue inside
      // that window: the request that arrives while an arm is in flight
      // has to run after it, not be dropped.
      final gate = Completer<void>();
      h.repo.playInfoGate = gate;
      await _skipTo(h.engine, 190000);
      h.container.queue.removeAt(1);
      await pumpEventQueue();
      expect(h.engine.preloadedUrl, isNull, reason: 'nothing armed yet');

      h.repo.playInfoGate = null;
      gate.complete();
      await pumpEventQueue();

      // The entry that was armed is gone from the queue; what follows
      // now is the one the engine holds.
      expect(h.engine.preloadedUrl, contains(_c));
    });

    test(
      'a paused queue that drops its next entry drops the preload',
      () async {
        final h = _harness();
        h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
        await pumpEventQueue();
        await _skipTo(h.engine, 190000);
        expect(h.engine.preloadedUrl, contains(_b));

        // Paused, so no position tick will come along to reconcile it.
        await h.engine.pause();
        await pumpEventQueue();
        h.container.queue.removeAt(1);
        await pumpEventQueue();

        expect(h.engine.preloadedUrl, isNull);
      },
    );

    test(
      'spoken word is not prepared on either side of the crossing',
      () async {
        final h = _harness(items: [testItem(_a)]);
        h.repo
          ..addSubscription(testShow(_showPid))
          ..episodesByShow[_showPid] = [testEpisode(_episode)];

        // An episode followed by a track: the episode plays at its own
        // remembered speed, which the crossing could not apply in time.
        h.container.playback.play([
          testEpisode(_episode),
          testItem(_a),
        ], source: _album);
        await pumpEventQueue();
        await _skipTo(h.engine, 190000);

        expect(h.engine.preloadedUrl, isNull);
      },
    );
  });

  group('resolving an entry', () {
    test('an episode reached by pid alone still finds its show', () async {
      final h = _harness(items: [testItem(_a), testEpisode(_episode)]);
      h.repo
        ..addSubscription(
          testShow(_showPid),
          settings: const SubscriptionSettings(speed: 1.5),
        )
        ..episodesByShow[_showPid] = [testEpisode(_episode)];

      // No summary in hand, which is what a queue handed over by
      // another device and a browse leaf on a head unit both look like.
      await h.container.playback.playPids([_episode], source: QueueSource.none);
      await pumpEventQueue();

      expect(h.container.read(nowPlayingProvider).item, isA<EpisodeSummary>());
      // The show's remembered speed is the visible half of it: without
      // the show, an item detail plays every episode at 1.0.
      expect(h.engine.speed, 1.5);
    });
  });

  group('crossing into the prepared item', () {
    // A guard on the decision, not on a bug: a crossing must not
    // publish a state with no session, because the item never stopped
    // playing and the transport would blink out for a frame.
    test('publishes the new session in one step, never an empty one', () async {
      final h = _harness();
      h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
      await pumpEventQueue();
      await _skipTo(h.engine, 190000);

      final published = <NowPlaying>[];
      final sub = h.container.listen(
        nowPlayingProvider,
        (_, next) => published.add(next),
      );
      addTearDown(sub.close);
      await _runOut(h.engine);

      // Nothing that leaves a surface with a session it cannot use: the
      // outgoing one has let go by then, and the item never stopped
      // playing, so there is no honest frame with no session at all.
      expect(published, isNotEmpty);
      expect(published.where((s) => s.session == null), isEmpty);
      expect(published.last.item?.pid, _b);
    });

    test('rolls the session over without reloading the stream', () async {
      final h = _harness();
      h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
      await pumpEventQueue();
      await _skipTo(h.engine, 186000);
      await _play(h.engine, 4000);
      expect(h.engine.preloadedUrl, contains(_b));

      // Cross the boundary: playback never stops.
      await _runOut(h.engine);

      expect(h.container.queueState.currentPid, _b);
      expect(h.engine.loadedUrl, contains(_b));
      expect(h.engine.playing, isTrue);
      expect(h.container.read(nowPlayingProvider).item?.pid, _b);
      // One play-info per item: the adopted session plays the stream the
      // preload minted rather than resolving its own.
      expect(h.repo.playInfoCalls.where((c) => c.pid == _b), hasLength(1));

      // The outgoing item is finalized at its own end, not at the
      // engine's position, which by then belongs to the new item.
      final checkpoint = h.repo.putPlayStateCalls.where((c) => c.pid == _a);
      expect(checkpoint.last.positionMs, _trackMs);
      final reported = h.repo.reportedSessions.where((s) => s.pid == _a);
      expect(reported, hasLength(1));
      expect(reported.single.finished, isTrue);
    });

    test('the item crossed into keeps its own listen session', () async {
      final h = _harness();
      h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
      await pumpEventQueue();
      await _skipTo(h.engine, 190000);
      await _runOut(h.engine);

      await _play(h.engine, 6000);
      h.container.queue.clear();
      await pumpEventQueue();

      final reported = h.repo.reportedSessions.where((s) => s.pid == _b);
      expect(reported, hasLength(1));
      expect(reported.single.msPlayed, greaterThan(0));
      expect(reported.single.finished, isFalse);
    });
  });

  test('radio taking the engine takes the item off it too', () async {
    final h = _harness();
    h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
    await pumpEventQueue();
    await _play(h.engine, 4000);

    await h.container
        .read(radioPlaybackProvider.notifier)
        .play(
          RadioStation(
            pid: 'st-1',
            name: 'Prancing Pony FM',
            streamUrl: 'https://pony.example/stream',
            createdAt: DateTime.utc(2026, 7, 25),
          ),
        );
    await pumpEventQueue();

    // The item let go where it stood, so the station's stream is never
    // counted as time listened to it.
    expect(h.container.read(nowPlayingProvider).session, isNull);
    expect(h.repo.reportedSessions, hasLength(1));
    expect(h.repo.reportedSessions.single.pid, _a);
    expect(h.repo.reportedSessions.single.msPlayed, 4000);
    expect(h.repo.reportedSessions.single.finished, isFalse);
    expect(h.repo.putPlayStateCalls.last.positionMs, 4000);

    // Radio plays on: nothing stopped the engine it had just taken.
    expect(h.engine.loadedUrl, contains('/media/radio/'));
    expect(h.engine.playing, isTrue);

    // And the stream dropping is not the end of a queue entry.
    final before = h.repo.reportedSessions.length;
    await _runOut(h.engine);
    expect(h.container.queueState.currentPid, _a);
    expect(h.repo.reportedSessions, hasLength(before));
  });

  test('radio taking the engine does not advance the queue', () async {
    final h = _harness();
    h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
    await pumpEventQueue();

    await h.container
        .read(radioPlaybackProvider.notifier)
        .play(
          RadioStation(
            pid: 'st-1',
            name: 'Prancing Pony FM',
            streamUrl: 'https://pony.example/stream',
            createdAt: DateTime.utc(2026, 7, 25),
          ),
        );
    await pumpEventQueue();

    // The stream ends (a dropped connection, a station going off air):
    // that is not the end of a queue entry.
    await _runOut(h.engine);

    expect(h.container.queueState.currentPid, _a);
    expect(h.engine.loadedUrl, contains('/media/radio/'));
  });

  group('engine rate across switches', () {
    test('a station tuned after a 1.5x show broadcasts at 1x', () async {
      final h = _harness(items: [testEpisode(_episode)]);
      h.repo
        ..addSubscription(
          testShow(_showPid),
          settings: const SubscriptionSettings(speed: 1.5),
        )
        ..episodesByShow[_showPid] = [testEpisode(_episode)];
      h.container.playback.play([testEpisode(_episode)], source: _album);
      await pumpEventQueue();
      expect(h.engine.speed, 1.5);

      await h.container
          .read(radioPlaybackProvider.notifier)
          .play(
            RadioStation(
              pid: 'st-1',
              name: 'Prancing Pony FM',
              streamUrl: 'https://pony.example/stream',
              createdAt: DateTime.utc(2026, 7, 25),
            ),
          );
      await pumpEventQueue();

      expect(h.engine.speed, 1.0);
      expect(h.engine.playing, isTrue);
    });

    test('a cross-media tap never re-rates the outgoing item', () async {
      final h = _harness(items: [testItem(_a), testEpisode(_episode)]);
      h.repo
        ..addSubscription(
          testShow(_showPid),
          settings: const SubscriptionSettings(speed: 1.5),
        )
        ..episodesByShow[_showPid] = [testEpisode(_episode)];
      h.container.playback.play([testEpisode(_episode)], source: _album);
      await pumpEventQueue();
      expect(h.engine.speed, 1.5);

      // Hold the track's stream resolution open: the show is audible
      // through this whole window and must keep its own rate rather
      // than drop to the track's before the track has any media.
      final gate = Completer<void>();
      h.repo.playInfoGate = gate;
      h.container.playback.play([testItem(_a)], source: _album);
      await pumpEventQueue();
      expect(
        h.engine.speed,
        1.5,
        reason: 'the outgoing show keeps its rate while the track resolves',
      );

      h.repo.playInfoGate = null;
      gate.complete();
      await pumpEventQueue();

      expect(h.engine.loadedUrl, contains(_a));
      expect(h.engine.speed, 1.0);
    });

    test('a 1.5x show still starts at 1.5x', () async {
      final h = _harness(items: [testItem(_a), testEpisode(_episode)]);
      h.repo
        ..addSubscription(
          testShow(_showPid),
          settings: const SubscriptionSettings(speed: 1.5),
        )
        ..episodesByShow[_showPid] = [testEpisode(_episode)];
      // From a 1x track into the show: the relocated rate write still
      // lands before the show becomes audible.
      h.container.playback.play([testItem(_a)], source: _album);
      await pumpEventQueue();
      expect(h.engine.speed, 1.0);

      h.container.playback.play([testEpisode(_episode)], source: _album);
      await pumpEventQueue();

      expect(h.engine.speed, 1.5);
      expect(h.engine.playing, isTrue);
    });
  });

  test('an item start silences the station before it resolves', () async {
    final h = _harness();
    await h.container
        .read(radioPlaybackProvider.notifier)
        .play(
          RadioStation(
            pid: 'st-1',
            name: 'Prancing Pony FM',
            streamUrl: 'https://pony.example/stream',
            createdAt: DateTime.utc(2026, 7, 25),
          ),
        );
    await pumpEventQueue();
    expect(h.engine.playing, isTrue);

    // Hold the item's stream resolution open: an item start runs several
    // round trips before its load replaces the source, and this is the
    // window the station used to keep playing through, audibly, under an
    // item face that said the podcast was on.
    final gate = Completer<void>();
    h.repo.playInfoGate = gate;
    h.container.playback.play([testItem(_a)], source: _album);
    await pumpEventQueue();

    expect(
      h.engine.playing,
      isFalse,
      reason: 'the station goes quiet as the start begins, not when it ends',
    );
    expect(h.container.read(radioPlaybackProvider).station, isNull);

    h.repo.playInfoGate = null;
    gate.complete();
    await pumpEventQueue();

    expect(h.engine.loadedUrl, contains(_a));
    expect(h.engine.playing, isTrue);
  });

  test('an empty-queue start racing a tune loses to the station', () async {
    final h = _harness();
    // A pid-only start with its resolution held open: the window before
    // any session exists, which the hand-over's session guard used to
    // skip entirely - the parked start woke unsuperseded and loaded its
    // item over the station that had just won the engine.
    final gate = Completer<void>();
    h.repo.getItemGate = gate;
    final started = h.container.playback.playPids([
      _a,
    ], source: QueueSource.none);
    await pumpEventQueue();

    await h.container
        .read(radioPlaybackProvider.notifier)
        .play(
          RadioStation(
            pid: 'st-1',
            name: 'Prancing Pony FM',
            streamUrl: 'https://pony.example/stream',
            createdAt: DateTime.utc(2026, 7, 25),
          ),
        );
    await pumpEventQueue();
    expect(h.engine.playing, isTrue);

    h.repo.getItemGate = null;
    gate.complete();
    await started;
    await pumpEventQueue();

    expect(
      h.engine.loadedUrl,
      contains('/media/radio/'),
      reason: 'the parked start must not load its item over the station',
    );
    expect(h.engine.playing, isTrue);
    expect(h.container.read(nowPlayingProvider).session, isNull);
    expect(h.container.read(currentSessionRegistryProvider).current, isNull);
    expect(h.container.read(radioPlaybackProvider).station, isNotNull);
  });

  test(
    'a tune landing in the boundary window never adopts the crossing',
    () async {
      final h = _harness();
      h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
      await pumpEventQueue();
      await _skipTo(h.engine, 190000);
      expect(h.engine.preloadedUrl, contains(_b));

      // Cross the boundary and land a tune before the boundary event is
      // dispatched: the crossing's adopt has no media load of its own, so
      // a session built here would run its checkpoint timer against the
      // station's stream and write the crossed-into item's pid at the
      // station's position.
      h.engine.advance(const Duration(milliseconds: _trackMs));
      final tune = h.container
          .read(radioPlaybackProvider.notifier)
          .play(
            RadioStation(
              pid: 'st-1',
              name: 'Prancing Pony FM',
              streamUrl: 'https://pony.example/stream',
              createdAt: DateTime.utc(2026, 7, 25),
            ),
          );
      await pumpEventQueue();
      await tune;
      await pumpEventQueue();

      expect(h.engine.loadedUrl, contains('/media/radio/'));
      expect(h.engine.playing, isTrue);
      expect(h.container.read(nowPlayingProvider).session, isNull);
      expect(h.container.read(currentSessionRegistryProvider).current, isNull);
      expect(h.repo.putPlayStateCalls.where((c) => c.pid == _b), isEmpty);
    },
  );

  test(
    'a start that dies before its session leaves the radio silent',
    () async {
      final h = _harness();
      await h.container
          .read(radioPlaybackProvider.notifier)
          .play(
            RadioStation(
              pid: 'st-1',
              name: 'Prancing Pony FM',
              streamUrl: 'https://pony.example/stream',
              createdAt: DateTime.utc(2026, 7, 25),
            ),
          );
      await pumpEventQueue();
      expect(h.engine.playing, isTrue);

      // A pid the server does not know (a routed queue, a restored one):
      // the resolve throws before any session exists, so no session
      // teardown will ever run. The engine has to be silent already, or
      // the station plays forever under the error pane.
      await h.container.playback.playPids([
        'tr-01JZX5N8QW3F4V9T2B7KDGONE01',
      ], source: QueueSource.none);
      await pumpEventQueue();

      expect(h.engine.playing, isFalse);
      expect(h.container.read(nowPlayingProvider).error, isNotNull);
      expect(h.container.read(radioPlaybackProvider).station, isNull);
    },
  );

  test('previous at the front leaves a paused queue paused', () async {
    final h = _harness();
    h.container.playback.play([testItem(_a)], source: _album);
    await pumpEventQueue();
    await _play(h.engine, 4000);
    await h.engine.pause();
    await pumpEventQueue();

    // A skip is not a play command: it puts the entry back at its
    // start, it does not start it.
    expect(await h.container.playback.previous(), isTrue);
    await pumpEventQueue();
    expect(h.engine.position, Duration.zero);
    expect(h.engine.playing, isFalse);
  });

  test('a skip while radio has the engine does nothing', () async {
    final h = _harness();
    h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
    await pumpEventQueue();

    await h.container
        .read(radioPlaybackProvider.notifier)
        .play(
          RadioStation(
            pid: 'st-1',
            name: 'Prancing Pony FM',
            streamUrl: 'https://pony.example/stream',
            createdAt: DateTime.utc(2026, 7, 25),
          ),
        );
    await pumpEventQueue();

    // A head unit or a controller pressing next: there is no queue
    // playing to step, and stepping would take the engine back from
    // the station.
    expect(await h.container.playback.next(), isFalse);
    expect(await h.container.playback.previous(), isFalse);
    await pumpEventQueue();

    expect(h.container.queueState.currentPid, _a);
    expect(h.engine.loadedUrl, contains('/media/radio/'));
  });

  group('an unplayable file', () {
    test('is skipped past rather than stopping the queue', () async {
      final h = _harness();
      // Read so the controller exists to follow the queue; nothing
      // plays until something is watching.
      h.container.playback;
      h.container.queue.playNow([_a, _b, _c], source: _album);
      await pumpEventQueue();
      expect(h.container.read(nowPlayingProvider).session, isNotNull);

      // The next load throws the way media that will not open throws.
      // The queue behind it is fine, and stopping there is what left a
      // whole album dead behind one bad rip.
      h.engine.failNextLoad = true;
      await h.container.playback.next();
      await pumpEventQueue();
      await pumpEventQueue();

      expect(h.container.queueState.currentPid, _c);
      final now = h.container.read(nowPlayingProvider);
      expect(now.error, isNull, reason: 'the queue moved, so there is no pane');
      expect(now.session, isNotNull);
      expect(
        h.container.read(shellMessengerProvider)?.resolve(_l10n),
        contains('Skipped'),
      );

      h.container.queue.clear();
      await pumpEventQueue();
    });

    test('a stream that could not be fetched is not one of them', () async {
      // The other half of the split, and the one that costs a listener
      // their queue if it is read wrong: a server restart, a 502, a
      // token that aged out. Nothing is wrong with the file, so walking
      // past it would spend a library one track at a time on a dropped
      // connection - and the retry the pane offers is a real offer,
      // because the state it failed on is one that changes.
      final h = _harness();
      h.container.playback;
      h.container.queue.playNow([_a, _b, _c], source: _album);
      await pumpEventQueue();

      h.engine.failNextLoad = true;
      h.engine.loadFault = MediaFault.transport;
      await h.container.playback.next();
      await pumpEventQueue();
      await pumpEventQueue();

      expect(h.container.queueState.currentPid, _b, reason: 'it stayed put');
      final now = h.container.read(nowPlayingProvider);
      expect(now.error, isA<MediaLoadException>());
      expect(now.session, isNull);

      h.container.queue.clear();
      await pumpEventQueue();
    });

    test('stops with the pane when there is nowhere to go', () async {
      final h = _harness();
      // One entry, and it is the one that refuses. A skip has nothing
      // to skip to, so the failure is the end of the line and the pane
      // with its retry is the honest answer.
      h.engine.failNextLoad = true;
      h.container.playback;
      h.container.queue.playNow([_a], source: _album);
      await pumpEventQueue();
      await pumpEventQueue();

      final now = h.container.read(nowPlayingProvider);
      expect(now.error, isA<MediaLoadException>());
      expect(now.session, isNull);
      expect(h.container.queueState.currentPid, _a);

      h.container.queue.clear();
      await pumpEventQueue();
    });

    test(
      'gives up after a run of them rather than walking the queue',
      () async {
        // Deliberately longer than the cap plus one: the point of the cap
        // is that it stops while the queue still has somewhere to go, so
        // a queue that runs out from under it would prove nothing.
        final broken = <String>[for (var i = 0; i < 6; i++) 'tr-broken-$i'];
        final h = _harness(items: [for (final pid in broken) testItem(pid)]);
        h.container.playback;
        // Every message the run raises, since the messenger holds only
        // the newest and what matters here is that they line up.
        final raised = <ShellMessage>[];
        h.container.listen(shellMessengerProvider, (_, next) {
          if (next != null) raised.add(next);
        });
        h.container.queue.playNow(broken, source: _album);
        await pumpEventQueue();
        expect(h.container.read(nowPlayingProvider).session, isNotNull);

        // Every load from here refuses. Without the cap this walks the
        // whole queue, one toast per entry, and calls it playback.
        h.engine.failEveryLoad = true;
        await h.container.playback.next();
        for (var i = 0; i < 12; i++) {
          await pumpEventQueue();
        }

        expect(
          h.container.read(nowPlayingProvider).error,
          isA<MediaLoadException>(),
        );
        final gaveUp = h.container.read(shellMessengerProvider);
        expect(gaveUp?.resolve(_l10n), contains('Stopped after 3'));
        // On the channel the skips used, so the shell replaces the
        // count still standing rather than stacking a second bar over
        // it. A channel rather than a button identifier: none of these
        // messages has a button, and inventing one to be coalesced by
        // is a hand-typed semantics string.
        expect(gaveUp?.channel, isNotNull);
        expect(gaveUp?.channel, raised.first.channel);
        expect(gaveUp?.actionSemanticsId, isNull);
        // And it stopped where it stopped rather than at the end: the
        // last entry is still ahead of it.
        expect(h.container.queueState.currentPid, isNot(broken.last));

        h.container.queue.clear();
        await pumpEventQueue();
      },
    );
  });
}
