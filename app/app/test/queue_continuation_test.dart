import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_continuation.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/settings/client_prefs.dart';
import 'package:waxdeck/src/settings/client_settings_providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

const _a = 'tr-01JZX5N8QW3F4V9T2B7KDTRACKA';
const _b = 'tr-01JZX5N8QW3F4V9T2B7KDTRACKB';
const _mixed = 'tr-01JZX5N8QW3F4V9T2B7KDMIXED1';
const _book = 'tr-01JZX5N8QW3F4V9T2B7KDBOOK01';

const _album = QueueSource(
  kind: QueueSourceKind.album,
  label: 'Kind of Blue',
  pid: 'al-1',
);

/// A container with the continuation bound the way the signed-in shell
/// binds it, so the queue's own notifications reach it.
({ProviderContainer container, FakeRepository repo}) _harness({
  List<ItemSummary>? items,
}) {
  final repo = FakeRepository(
    items:
        items ??
        <ItemSummary>[
          testItem(_a),
          testItem(_b),
          testItem(_mixed),
          testItem(_book, mediaType: MediaType.audiobook),
        ],
  );
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      audioEngineProvider.overrideWithValue(FakeEngine()),
      clientSettingsStoreProvider.overrideWithValue(
        MemoryClientSettingsStore(),
      ),
    ],
  );
  addTearDown(container.dispose);
  final sub = container.listen(queueContinuationProvider, (_, _) {});
  addTearDown(sub.close);
  return (container: container, repo: repo);
}

extension on ProviderContainer {
  NowPlayingController get playback => read(nowPlayingProvider.notifier);
  QueueController get queue => read(queueControllerProvider.notifier);
  QueueState get queueState => read(queueControllerProvider);
}

void main() {
  late InstantMix mix;

  setUp(() {
    mix = InstantMix(
      basis: MixBasis.sonic,
      items: <ItemSummary>[testItem(_mixed)],
    );
  });

  test('a music queue that runs out keeps going', () async {
    final h = _harness();
    h.repo.instantMixResult = mix;

    // One track from a shelf is the case the report named: its
    // `unplayed` is zero the moment it starts.
    h.container.playback.play([testItem(_a)], source: _album);
    await pumpEventQueue();

    expect(h.container.queueState.pids, <String>[_a, _mixed]);
    // And the appended entry is marked, which is what the queue surface
    // draws its divider above.
    expect(h.container.read(queueContinuationProvider), <String>{
      h.container.queueState.entries.last.queueId,
    });
  });

  test('the mix does not repeat anything the queue held', () async {
    final h = _harness();
    h.repo.instantMixResult = mix;

    // The whole queue, played history included: the continuation runs
    // standing on the last entry, and the seed's nearest neighbours are
    // what just played - excluding only the upcoming side would loop a
    // small library's album straight back with repeat off.
    h.container.playback.play(
      [testItem(_a), testItem(_b)],
      source: _album,
      startIndex: 1,
    );
    await pumpEventQueue();

    expect(h.repo.instantMixCalls, hasLength(1));
    expect(h.repo.instantMixCalls.single.seedPid, _b);
    expect(h.repo.instantMixCalls.single.excludePids, <String>[_a, _b]);
  });

  test('turned off, the queue ends where it was built to end', () async {
    final h = _harness();
    h.repo.instantMixResult = mix;
    h.container.read(keepPlayingSimilarProvider.notifier).set(false);

    h.container.playback.play([testItem(_a)], source: _album);
    await pumpEventQueue();

    expect(h.repo.instantMixCalls, isEmpty);
    expect(h.container.queueState.pids, <String>[_a]);
  });

  test('a rolling window refills itself instead', () async {
    final h = _harness();
    h.repo.instantMixResult = mix;

    h.container.playback.play(
      [testItem(_a)],
      source: const QueueSource(
        kind: QueueSourceKind.library,
        label: '',
        rolling: true,
      ),
    );
    await pumpEventQueue();

    expect(h.repo.instantMixCalls, isEmpty);
  });

  test('repeat-all loops rather than growing', () async {
    final h = _harness();
    h.repo.instantMixResult = mix;
    // Set before the queue is built: `unplayed` is zero on the last
    // track whatever the repeat mode is, so the continuation would fire
    // on the first notification otherwise.
    h.container.queue.setRepeat(QueueRepeat.all);

    h.container.playback.play([testItem(_a), testItem(_b)], source: _album);
    await pumpEventQueue();
    h.container.queue.jumpTo(1);
    await pumpEventQueue();

    expect(h.repo.instantMixCalls, isEmpty);
    expect(h.container.queueState.pids, <String>[_a, _b]);
  });

  test('spoken word is left alone', () async {
    final h = _harness();
    h.repo.instantMixResult = mix;

    h.container.playback.play([
      testItem(_book, mediaType: MediaType.audiobook),
    ], source: const QueueSource(kind: QueueSourceKind.book, label: 'A Book'));
    await pumpEventQueue();

    expect(h.repo.instantMixCalls, isEmpty);
    expect(h.container.queueState.pids, <String>[_book]);
  });

  test('a restored queue continues without knowing what it played', () async {
    final h = _harness();
    h.repo.instantMixResult = mix;

    // A queue adopted whole: nothing has resolved the entry before the
    // current one, so nothing knows it was music. Asking the whole queue
    // rather than the seed is what used to leave a resumed session
    // stopping dead where a fresh one carried on.
    h.container.playback.restore(
      QueueState.fromStored(
        StoredQueue(
          entries: const <StoredQueueEntry>[
            StoredQueueEntry(queueId: 'q0', pid: _a, sourceRank: 0),
            StoredQueueEntry(queueId: 'q1', pid: _b, sourceRank: 1),
          ],
          currentIndex: 1,
          shuffled: false,
          repeat: 'off',
          sourceKind: 'album',
          sourceLabel: 'Kind of Blue',
          nextQueueId: 2,
          updatedAt: DateTime.utc(2026, 8, 22),
        ),
      ),
    );
    await pumpEventQueue();

    expect(h.container.playback.summaryFor(_a), isNull);
    expect(h.repo.instantMixCalls, hasLength(1));
    expect(h.container.queueState.pids, <String>[_a, _b, _mixed]);
  });

  test('switching it on continues a queue that has already run out', () async {
    final h = _harness();
    h.repo.instantMixResult = mix;
    h.container.read(keepPlayingSimilarProvider.notifier).set(false);

    h.container.playback.play([testItem(_a)], source: _album);
    await pumpEventQueue();
    expect(h.repo.instantMixCalls, isEmpty);

    // The moment the switch is most likely to be reached is the moment
    // the music has just stopped - and a queue that has run out sends no
    // further notification, so the switch has to be its own trigger.
    h.container.read(keepPlayingSimilarProvider.notifier).set(true);
    await pumpEventQueue();

    expect(h.repo.instantMixCalls, hasLength(1));
    expect(h.container.queueState.pids, <String>[_a, _mixed]);
  });

  test('a queue replaced mid-request is continued in its turn', () async {
    final h = _harness();
    h.repo.instantMixResult = mix;

    h.container.playback.play([testItem(_a)], source: _album);
    // Replaced before the first mix lands: that mix is for a queue that
    // is gone and is dropped on arrival, and the queue standing now has
    // run out too - with nothing left to notify anyone about it.
    h.container.playback.play([testItem(_b)], source: _album);
    await pumpEventQueue();

    expect(h.container.queueState.pids, <String>[_b, _mixed]);
    expect(h.repo.instantMixCalls.last.seedPid, _b);
  });

  test('a mix that comes back empty does not retry in a loop', () async {
    final h = _harness();
    h.repo.instantMixResult = const InstantMix(basis: MixBasis.sonic);

    h.container.playback.play([testItem(_a)], source: _album);
    await pumpEventQueue();
    // The queue cannot move on its own once it has run out, so every
    // later notification would be another attempt without the block.
    h.container.queue.setShuffle(true);
    await pumpEventQueue();

    expect(h.repo.instantMixCalls, hasLength(1));
  });
}
