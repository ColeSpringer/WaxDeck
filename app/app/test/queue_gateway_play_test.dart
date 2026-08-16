import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/connect/queue_gateway.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

/// What a play raised outside the app means: the lock screen, a headset
/// button, a head unit, a Bluetooth remote.
///
/// It has to answer the way the deck's own play button answers, and
/// going straight at the engine does not. The engine restarts a finished
/// item and starts a station, but a queue standing with no session - a
/// start that failed, and is waiting to be asked again - is not
/// something it can begin.
void main() {
  const pid = 'tr-01JZX5N8QW3F4V9T2B7KDTRACK1';

  ({ProviderContainer container, FakeEngine engine, FakeRepository repo})
  build() {
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(mediaDuration: const Duration(seconds: 30));
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        audioEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, engine: engine, repo: repo);
  }

  /// Puts a queue in play whose start fails, which is how a queue comes
  /// to stand with nothing driving it.
  Future<NowPlayingController> withFailedStart(
    ({ProviderContainer container, FakeEngine engine, FakeRepository repo}) h,
  ) async {
    h.repo.playInfoError = const WaxDeckApiException(
      code: 'transport',
      message: 'network unreachable',
    );
    h.container
        .read(queueControllerProvider.notifier)
        .restore(
          QueueState.empty.copyWith(
            entries: const [QueueEntry(queueId: 'q0', pid: pid)],
            sourceOrder: const ['q0'],
          ),
        );
    final playback = h.container.read(nowPlayingProvider.notifier);
    await pumpEventQueue();
    await playback.settled;
    await pumpEventQueue();
    expect(playback.liveSession, isNull, reason: 'the start did not take');
    expect(h.container.read(queueControllerProvider).isNotEmpty, isTrue);
    return playback;
  }

  test(
    'a start that failed on something else is reported, not swallowed',
    () async {
      // The gateway answers the media session as well as a routed
      // command, so it reports the failure and words no wire code; what a
      // controller sends back is connect_endpoint_test's. An Error is
      // wrapped because both callers catch by Exception, and an Error is
      // not one.
      const other = 'tr-01JZX5N8QW3F4V9T2B7KDTRACK2';
      final repo = FakeRepository(items: [testItem(pid), testItem(other)]);
      final container = ProviderContainer(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          audioEngineProvider.overrideWithValue(
            FakeEngine(mediaDuration: const Duration(seconds: 30)),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(queueControllerProvider.notifier)
          .restore(
            QueueState.empty.copyWith(
              entries: const [
                QueueEntry(queueId: 'q0', pid: pid),
                QueueEntry(queueId: 'q1', pid: other),
              ],
              sourceOrder: const ['q0', 'q1'],
            ),
          );
      await pumpEventQueue();
      await container.read(nowPlayingProvider.notifier).settled;
      repo.playInfoError = StateError('no decoder for that file');

      await expectLater(
        container.read(queueGatewayProvider).jumpTo(1),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('no decoder for that file'),
          ),
        ),
      );
    },
  );

  test('a play asks a failed start again, as the deck does', () async {
    final h = build();
    final playback = await withFailedStart(h);
    // The server comes back.
    h.repo.playInfoError = null;
    final startsBefore = playback.startGeneration;

    await h.container.read(queueGatewayProvider).play();
    await pumpEventQueue();
    await playback.settled;

    // On the start rather than on the engine: poking the engine directly
    // also leaves it playing, and the queue listener loads media once it
    // is, so the engine alone cannot tell the two routes apart. Only
    // beginning an entry moves this.
    expect(
      playback.startGeneration,
      greaterThan(startsBefore),
      reason: 'a play from a car has to retry the entry, not sit dead',
    );
    expect(playback.liveSession, isNotNull);
  });

  test('a play with nothing queued at all starts nothing', () async {
    final h = build();

    await h.container.read(queueGatewayProvider).play();
    await h.container.read(nowPlayingProvider.notifier).settled;

    expect(h.engine.loadedUrl, isNull);
    expect(h.engine.playing, isFalse);
  });
}
