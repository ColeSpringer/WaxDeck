import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/connect/remote_session.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/player/now_playing_slot.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_persistence.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

const _a = 'tr-01JZX5N8QW3F4V9T2B7KDTRACKA';
const _b = 'tr-01JZX5N8QW3F4V9T2B7KDTRACKB';
const _c = 'tr-01JZX5N8QW3F4V9T2B7KDTRACKC';

const _album = QueueSource(
  kind: QueueSourceKind.album,
  label: 'Kind of Blue',
  pid: 'al-1',
);

final _station = RadioStation(
  pid: 'rs-1',
  name: 'Prancing Pony FM',
  streamUrl: 'https://pony.example/stream',
  createdAt: DateTime.utc(2026, 7, 25),
);

const _entry = QueueEntry(queueId: 'q0', pid: _a);

final _item = NowPlaying(entry: _entry, item: testItem(_a));

const _parked = ParkedEntry(entry: _entry);

final _remote = RemoteSession(
  session: PlaybackSessionInfo(
    id: 'ps-kitchen',
    endpointId: 'pe-kitchen',
    endpointName: 'Kitchen speaker',
    mine: true,
    authority: 'remote',
    playing: true,
    index: 0,
    positionMs: 0,
    positionAt: DateTime.utc(2026, 7, 25),
    rate: 1,
    queueVersion: 1,
    entries: const [],
  ),
  entries: const [],
);

final _offer = RestorableQueue(
  queue: QueueState.empty.copyWith(
    entries: const [_entry],
    sourceOrder: const ['q0'],
  ),
  savedAt: DateTime.utc(2026, 7, 25),
);

/// The slot with each source standing as given, the rest empty.
NowPlayingSlot _slotOf({
  bool station = false,
  NowPlaying now = NowPlaying.nothing,
  ParkedEntry? parked,
  RemoteSession? remote,
  RestorableQueue? offer,
}) {
  final container = ProviderContainer(
    overrides: [
      radioPlaybackProvider.overrideWithBuild(
        (ref, _) =>
            station ? RadioPlayback(station: _station) : const RadioPlayback(),
      ),
      nowPlayingProvider.overrideWithBuild((ref, _) => now),
      parkedEntryProvider.overrideWithValue(parked),
      remoteSessionProvider.overrideWithBuild((ref, _) => remote),
      queueRestoreProvider.overrideWithBuild((ref, _) => offer),
    ],
  );
  addTearDown(container.dispose);
  return container.read(nowPlayingSlotProvider);
}

({ProviderContainer container, FakeEngine engine}) _harness() {
  final repo = FakeRepository(
    items: [testItem(_a), testItem(_b), testItem(_c)],
  );
  final engine = FakeEngine(mediaDuration: const Duration(minutes: 3));
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      audioEngineProvider.overrideWithValue(engine),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, engine: engine);
}

void main() {
  group('the order', () {
    test('a station wins over everything else standing', () {
      final slot = _slotOf(
        station: true,
        now: _item,
        parked: _parked,
        remote: _remote,
        offer: _offer,
      );
      expect(slot, isA<StationSlot>());
      expect((slot as StationSlot).playback.station?.pid, 'rs-1');
    });

    test('an item with an entry outranks a remote session and an offer', () {
      final slot = _slotOf(now: _item, remote: _remote, offer: _offer);
      expect(slot, isA<ItemSlot>());
      expect((slot as ItemSlot).now, same(_item));
    });

    test('an item without an entry is not an item slot', () {
      final slot = _slotOf(now: NowPlaying(item: testItem(_a), loading: true));
      expect(slot, isA<EmptySlot>());
    });

    test('a parked entry comes before a remote session', () {
      final slot = _slotOf(parked: _parked, remote: _remote, offer: _offer);
      expect(slot, isA<ParkedSlot>());
      expect((slot as ParkedSlot).parked, same(_parked));
    });

    test('a remote session comes before the launch offer', () {
      final slot = _slotOf(remote: _remote, offer: _offer);
      expect(slot, isA<RemoteSlot>());
      expect((slot as RemoteSlot).remote, same(_remote));
    });

    test('the launch offer comes before nothing', () {
      final slot = _slotOf(offer: _offer);
      expect(slot, isA<OfferSlot>());
      expect((slot as OfferSlot).offer, same(_offer));
    });

    test('nothing standing is the empty slot', () {
      expect(_slotOf(), isA<EmptySlot>());
    });

    test('a parked entry while a station plays is a station slot', () {
      expect(_slotOf(station: true, parked: _parked), isA<StationSlot>());
    });
  });

  group('following the park', () {
    /// Plays [_a] then [_b] from a queue, tunes a station over it and
    /// stops the station, leaving the queue parked. The slots seen go
    /// into [seen].
    Future<({ProviderContainer container, FakeEngine engine})> parked(
      List<NowPlayingSlot> seen,
    ) async {
      final h = _harness();
      h.container.listen<NowPlayingSlot>(
        nowPlayingSlotProvider,
        (_, next) => seen.add(next),
        fireImmediately: true,
      );
      h.container.read(nowPlayingProvider.notifier).play([
        testItem(_a),
        testItem(_b),
      ], source: _album);
      await pumpEventQueue();
      final radio = h.container.read(radioPlaybackProvider.notifier);
      await radio.play(_station);
      await pumpEventQueue();
      expect(h.container.read(nowPlayingSlotProvider), isA<StationSlot>());
      await radio.stop();
      await pumpEventQueue();
      expect(seen.last, isA<ParkedSlot>());
      expect((seen.last as ParkedSlot).parked.entry.pid, _a);
      return h;
    }

    test('dismissing the offer leaves nothing standing', () async {
      final seen = <NowPlayingSlot>[];
      final h = await parked(seen);

      h.container.read(queueControllerProvider.notifier).clear();
      await pumpEventQueue();

      expect(seen.last, isA<EmptySlot>());
      expect(h.container.read(nowPlayingSlotProvider), isA<EmptySlot>());
    });

    test(
      'a queue edit while parked keeps the park and starts nothing',
      () async {
        final seen = <NowPlayingSlot>[];
        final h = await parked(seen);
        final loads = h.engine.loadedUrls.length;

        h.container.read(queueControllerProvider.notifier).addToEnd([_c]);
        await pumpEventQueue();

        expect(seen.last, isA<ParkedSlot>());
        expect((seen.last as ParkedSlot).parked.entry.pid, _a);
        expect(h.engine.loadedUrls, hasLength(loads));
        expect(h.engine.playing, isFalse);
      },
    );

    test('taking the parked entry back makes it the item again', () async {
      final seen = <NowPlayingSlot>[];
      final h = await parked(seen);
      final playback = h.container.read(nowPlayingProvider.notifier);

      await playback.playEntryAt(
        h.container.read(queueControllerProvider).currentIndex,
      );
      await pumpEventQueue();

      expect(seen.last, isA<ItemSlot>());
      expect((seen.last as ItemSlot).now.entry?.pid, _a);
    });
  });
}
