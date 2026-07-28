import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

const _album = QueueSource(
  kind: QueueSourceKind.album,
  label: 'Kind of Blue',
  pid: 'al-1',
);
const _playlist = QueueSource(
  kind: QueueSourceKind.playlist,
  label: 'Roadtrip',
  pid: 'pl-1',
);

List<String> _tracks(int count) => [for (var i = 0; i < count; i++) 'tr-$i'];

/// A container with shuffle's randomness seeded, so a shuffled order is
/// an assertion rather than a probability.
({ProviderContainer container, QueueController queue}) _harness({
  int seed = 7,
}) {
  final container = ProviderContainer(
    overrides: [queueRandomProvider.overrideWithValue(Random(seed))],
  );
  addTearDown(container.dispose);
  return (
    container: container,
    queue: container.read(queueControllerProvider.notifier),
  );
}

void main() {
  late ProviderContainer container;
  late QueueController queue;

  QueueState get_() => container.read(queueControllerProvider);
  List<String> pids() => get_().pids;

  setUp(() {
    final h = _harness();
    container = h.container;
    queue = h.queue;
  });

  group('building a queue', () {
    test('a queue starts empty', () {
      expect(get_().isEmpty, isTrue);
      expect(get_().currentPid, isNull);
      expect(get_().nextEntry, isNull);
    });

    test('playing from a track queues its context from that track', () {
      queue.playNow(_tracks(5), source: _album, startIndex: 2);

      expect(pids(), _tracks(5));
      expect(get_().currentIndex, 2);
      expect(get_().currentPid, 'tr-2');
      expect(get_().source, _album);
      expect(get_().shuffled, isFalse);
    });

    test('entries carry ids that outlive their positions', () {
      queue.playNow(_tracks(3), source: _album);
      final ids = [for (final e in get_().entries) e.queueId];

      queue.reorder(2, 0);

      expect(
        [for (final e in get_().entries) e.queueId],
        [ids[2], ids[0], ids[1]],
      );
    });

    test('the same pid may sit in the queue twice', () {
      queue.playNow(['tr-A', 'tr-B', 'tr-A'], source: _playlist);

      expect(pids(), ['tr-A', 'tr-B', 'tr-A']);
      final ids = {for (final e in get_().entries) e.queueId};
      expect(ids, hasLength(3));
    });

    test('playing nothing empties the queue', () {
      queue.playNow(_tracks(3), source: _album);
      queue.playNow(const [], source: _playlist);

      expect(get_().isEmpty, isTrue);
    });

    test('a shuffled entry point shuffles the whole list', () {
      queue.playNow(_tracks(8), source: _album, startIndex: 5, shuffle: true);

      expect(get_().shuffled, isTrue);
      expect(get_().currentIndex, 0);
      expect(pids(), isNot(_tracks(8)));
      expect(pids().toSet(), _tracks(8).toSet());
    });

    test('a shuffled entry point still remembers the album order', () {
      queue.playNow(_tracks(8), source: _album, shuffle: true);
      final playing = get_().currentPid;
      queue.setShuffle(false);

      // What is playing keeps playing; everything it has not reached is
      // back in album order, which the old build could never do because
      // the album order was thrown away when the queue was drawn.
      expect(pids().first, playing);
      expect(pids().skip(1), _tracks(8).where((pid) => pid != playing));
    });

    test('the standing shuffle applies to a queue built without it', () {
      queue.setShuffle(true);
      queue.playNow(_tracks(8), source: _album, startIndex: 2);

      // The tapped track plays; what follows it is shuffled.
      expect(get_().shuffled, isTrue);
      expect(get_().currentPid, 'tr-2');
      expect(pids().take(3), ['tr-0', 'tr-1', 'tr-2']);
      expect(
        pids().skip(3).toList(),
        isNot(['tr-3', 'tr-4', 'tr-5', 'tr-6', 'tr-7']),
      );

      queue.setShuffle(false);
      expect(pids(), _tracks(8));
    });

    test('playing a queue does not answer the shuffle toggle for you', () {
      queue.setShuffle(true);
      queue.playNow(_tracks(3), source: _album);

      expect(get_().shuffled, isTrue);
    });
  });

  group('the cap', () {
    test('a longer list is windowed from where play starts', () {
      queue.playNow(_tracks(900), source: _album, startIndex: 100);

      expect(get_().length, kQueueCap);
      expect(get_().currentPid, 'tr-100');
      expect(get_().currentIndex, 0);
      expect(pids().last, 'tr-${100 + kQueueCap - 1}');
    });

    test('a start near the end backs the window up to stay full', () {
      queue.playNow(_tracks(900), source: _album, startIndex: 880);

      expect(get_().length, kQueueCap);
      expect(get_().currentPid, 'tr-880');
      expect(get_().currentIndex, 880 - (900 - kQueueCap));
      expect(pids().last, 'tr-899');
    });

    test('appending past the cap evicts history, not what is playing', () {
      queue.playNow(_tracks(kQueueCap), source: _album, startIndex: 10);
      queue.addToEnd(['tr-new-1', 'tr-new-2']);

      expect(get_().length, kQueueCap);
      expect(get_().currentPid, 'tr-10');
      expect(get_().currentIndex, 8);
      expect(pids().first, 'tr-2');
      expect(pids().last, 'tr-new-2');
    });

    test('a shuffled draw past the cap keeps the order it drew from', () {
      queue.playNow(_tracks(900), source: _album, shuffle: true);
      queue.setShuffle(false);

      expect(get_().length, kQueueCap);
      // The draw is random, but the survivors know where they came
      // from: what has not played is back in source order.
      final drawn = [
        for (final pid in pids().skip(1))
          int.parse(pid.substring('tr-'.length)),
      ];
      expect(drawn, [...drawn]..sort());
    });

    test('with no history to evict, the far end goes instead', () {
      queue.playNow(_tracks(kQueueCap), source: _album);
      queue.addToEnd(['tr-new']);

      expect(get_().length, kQueueCap);
      expect(get_().currentIndex, 0);
      expect(get_().currentPid, 'tr-0');
      expect(pids().last, 'tr-new');
      expect(pids(), isNot(contains('tr-${kQueueCap - 1}')));
    });
  });

  group('the rolling window', () {
    const paged = QueueSource(
      kind: QueueSourceKind.genre,
      label: 'Jazz',
      pid: 'ge-1',
      rolling: true,
      cursor: 'c-500',
    );

    test('a window that took the whole list keeps its cursor', () {
      queue.playNow(_tracks(kQueueCap), source: paged);

      expect(get_().source.rolling, isTrue);
      expect(get_().source.cursor, 'c-500');
    });

    test('an ordered window cut short of the list drops its cursor', () {
      // The listing had 900 loaded and its cursor names item 900; the
      // window ends at 500, so resuming there would step over 400.
      queue.playNow(_tracks(900), source: paged);

      expect(get_().source.rolling, isTrue);
      expect(get_().source.cursor, isEmpty);
      expect(get_().frontierPid, 'tr-${kQueueCap - 1}');
    });

    test('a list that fits under a source with more still rolls', () {
      queue.playNow(_tracks(10), source: paged);

      expect(get_().source.rolling, isTrue);
      expect(get_().source.cursor, 'c-500');
    });

    test('a shuffled draw keeps the cursor: it sampled, it did not run', () {
      queue.playNow(_tracks(900), source: paged, shuffle: true);

      expect(get_().source.cursor, 'c-500');
    });

    test('a window over a list that fits and has no more does not roll', () {
      queue.playNow(_tracks(10), source: _album);

      expect(get_().source.rolling, isFalse);
    });

    test('the frontier is the last entry taken, not the last played', () {
      queue.playNow(_tracks(5), source: paged);
      queue.setShuffle(true);

      expect(pids().last, isNot('tr-4'));
      expect(get_().frontierPid, 'tr-4');
    });

    test('a draw never re-adds what the queue already holds', () {
      // A hand reorder rewrites the source order, so the frontier a
      // draw places itself by can sit one short of the window's real
      // end, and the page it comes back with overlaps.
      queue.playNow(_tracks(5), source: paged);
      queue.appendWindow(['tr-3', 'tr-4', 'tr-5'], cursor: 'c', more: true);

      expect(pids(), [..._tracks(5), 'tr-5']);
    });

    test('a draw appends and moves the cursor on', () {
      queue.playNow(_tracks(5), source: paged);
      queue.appendWindow(['tr-5', 'tr-6'], cursor: 'c-600', more: true);

      expect(pids(), [..._tracks(5), 'tr-5', 'tr-6']);
      expect(get_().source.cursor, 'c-600');
      expect(get_().source.rolling, isTrue);
      expect(get_().frontierPid, 'tr-6');
    });

    test('a draw onto a full queue evicts history and keeps playing', () {
      queue.playNow(_tracks(kQueueCap), source: paged, startIndex: 400);
      queue.appendWindow(['tr-a', 'tr-b'], cursor: 'c-600', more: true);

      expect(get_().length, kQueueCap);
      expect(get_().currentPid, 'tr-400');
      expect(pids().first, 'tr-2');
      expect(pids().last, 'tr-b');
    });

    test('the last draw seals the window', () {
      queue.playNow(_tracks(5), source: paged);
      queue.appendWindow(['tr-5'], cursor: '', more: false);

      expect(get_().source.rolling, isFalse);
      expect(pids().last, 'tr-5');
    });

    test('an empty page moves the cursor without touching the queue', () {
      queue.playNow(_tracks(5), source: paged);
      queue.appendWindow(const [], cursor: 'c-700', more: true);

      expect(pids(), _tracks(5));
      expect(get_().source.cursor, 'c-700');
    });

    test('sealing stops the claim without stopping the queue', () {
      queue.playNow(_tracks(5), source: paged);
      queue.sealWindow();

      expect(get_().source.rolling, isFalse);
      expect(pids(), _tracks(5));
    });

    test('a draw into a shuffled queue is shuffled among itself', () {
      queue.playNow(_tracks(3), source: paged);
      queue.setShuffle(true);
      queue.appendWindow(
        _tracks(20).map((p) => '$p-b').toList(),
        cursor: 'c-600',
        more: true,
      );

      final arrivals = pids().sublist(3);
      expect(arrivals, isNot(orderedEquals(_tracks(20).map((p) => '$p-b'))));
      expect(arrivals.toSet(), _tracks(20).map((p) => '$p-b').toSet());
      // Un-shuffling puts the arrivals back the way the source sent
      // them, so the draw's own order survives the toggle.
      queue.setShuffle(false);
      expect(pids().sublist(3), _tracks(20).map((p) => '$p-b'));
    });

    test('a draw needs a queue to be a window over', () {
      queue.appendWindow(['tr-1'], cursor: 'c', more: true);

      expect(get_().isEmpty, isTrue);
    });

    test('the cursor and its seed survive a restart together', () {
      queue.playNow(
        _tracks(3),
        source: const QueueSource(
          kind: QueueSourceKind.library,
          label: 'All music',
          rolling: true,
          cursor: 'c-500',
          seed: 4242,
        ),
      );
      final restored = QueueState.fromStored(
        get_().toStored(updatedAt: DateTime.utc(2026, 7, 28)),
      );

      expect(restored.source.cursor, 'c-500');
      expect(restored.source.seed, 4242);
      expect(restored.source.rolling, isTrue);
    });

    test('a stored cursor with no seed reads back as a plain cursor', () {
      final restored = QueueState.fromStored(
        StoredQueue(
          entries: const [
            StoredQueueEntry(queueId: 'q0', pid: 'tr-A', sourceRank: 0),
          ],
          currentIndex: 0,
          shuffled: false,
          repeat: 'off',
          sourceKind: 'genre',
          sourceLabel: 'Jazz',
          sourceRolling: true,
          sourceCursor: 'YmFzZTY0dXJs',
          nextQueueId: 1,
          updatedAt: DateTime.utc(2026, 7, 28),
        ),
      );

      expect(restored.source.cursor, 'YmFzZTY0dXJs');
      expect(restored.source.seed, isNull);
    });
  });

  group('adding without replacing', () {
    test('play next lands right after the current entry', () {
      queue.playNow(_tracks(4), source: _album, startIndex: 1);
      queue.playNext(['ep-1']);

      expect(pids(), ['tr-0', 'tr-1', 'ep-1', 'tr-2', 'tr-3']);
      expect(get_().currentPid, 'tr-1');
      expect(get_().nextEntry!.pid, 'ep-1');
    });

    test('add to queue lands at the end', () {
      queue.playNow(_tracks(2), source: _album);
      queue.addToEnd(['bk-1']);

      expect(pids(), ['tr-0', 'tr-1', 'bk-1']);
      expect(get_().currentIndex, 0);
    });

    test('adding to nothing starts a queue with no provenance', () {
      queue.setRepeat(QueueRepeat.all);
      queue.addToEnd(['ep-1']);

      expect(pids(), ['ep-1']);
      expect(get_().currentIndex, 0);
      expect(get_().source, QueueSource.none);
      expect(get_().repeat, QueueRepeat.all);
    });

    test('a queue started under shuffle is shuffled', () {
      queue.setShuffle(true);
      queue.addToEnd(_tracks(8));

      expect(get_().shuffled, isTrue);
      expect(pids(), isNot(_tracks(8)));
      expect(pids().first, 'tr-0');
      queue.setShuffle(false);
      expect(pids(), _tracks(8));
    });

    test('added entries keep their place when shuffle goes off', () {
      queue.playNow(_tracks(6), source: _album);
      queue.setShuffle(true);
      queue.playNext(['ep-1']);
      queue.setShuffle(false);

      expect(pids(), ['tr-0', 'ep-1', 'tr-1', 'tr-2', 'tr-3', 'tr-4', 'tr-5']);
    });
  });

  group('moving through the queue', () {
    test('advance walks to the end and stops there', () {
      queue.playNow(_tracks(2), source: _album);

      expect(queue.advance(), QueueAdvance.advanced);
      expect(get_().currentIndex, 1);
      expect(queue.advance(), QueueAdvance.ended);
      expect(get_().currentIndex, 1);
    });

    test('repeat-all wraps in both directions', () {
      queue.playNow(_tracks(3), source: _album, startIndex: 2);
      queue.setRepeat(QueueRepeat.all);

      expect(queue.advance(), QueueAdvance.advanced);
      expect(get_().currentIndex, 0);
      expect(queue.retreat(), QueueRetreat.moved);
      expect(get_().currentIndex, 2);
    });

    test('repeat-one leaves the queue alone and says so', () {
      queue.playNow(_tracks(3), source: _album);
      queue.setRepeat(QueueRepeat.one);

      expect(queue.advance(), QueueAdvance.repeatedCurrent);
      expect(get_().currentIndex, 0);
      expect(get_().nextEntry, isNull);
    });

    test('a lone entry on repeat-all repeats rather than advancing', () {
      queue.playNow(['tr-0'], source: _album);
      queue.setRepeat(QueueRepeat.all);

      // Nothing to preload: the next item is the one already playing.
      expect(get_().nextEntry, isNull);
      expect(queue.advance(), QueueAdvance.repeatedCurrent);
      expect(get_().currentIndex, 0);
    });

    test('retreat at the front asks for a restart instead', () {
      queue.playNow(_tracks(3), source: _album);

      expect(queue.retreat(), QueueRetreat.atStart);
      expect(get_().currentIndex, 0);
    });

    test('an empty queue answers empty rather than moving', () {
      expect(queue.advance(), QueueAdvance.empty);
      expect(queue.retreat(), QueueRetreat.empty);
    });

    test('jumping picks an entry and clamps to the queue', () {
      queue.playNow(_tracks(4), source: _album);

      queue.jumpTo(3);
      expect(get_().currentIndex, 3);
      queue.jumpTo(99);
      expect(get_().currentIndex, 3);
      queue.jumpTo(-1);
      expect(get_().currentIndex, 0);
    });

    test('the next entry is what an advance would land on', () {
      queue.playNow(_tracks(2), source: _album);
      expect(get_().nextEntry!.pid, 'tr-1');

      queue.advance();
      expect(get_().nextEntry, isNull);

      queue.setRepeat(QueueRepeat.all);
      expect(get_().nextEntry!.pid, 'tr-0');
    });
  });

  group('editing the queue', () {
    test('removing an entry before the current one keeps it playing', () {
      queue.playNow(_tracks(4), source: _album, startIndex: 2);
      queue.removeAt(0);

      expect(pids(), ['tr-1', 'tr-2', 'tr-3']);
      expect(get_().currentPid, 'tr-2');
    });

    test('removing what is playing promotes the entry after it', () {
      queue.playNow(_tracks(4), source: _album, startIndex: 1);
      queue.removeAt(1);

      expect(pids(), ['tr-0', 'tr-2', 'tr-3']);
      expect(get_().currentIndex, 1);
      expect(get_().currentPid, 'tr-2');
    });

    test('removing the last entry while it plays steps back', () {
      queue.playNow(_tracks(3), source: _album, startIndex: 2);
      queue.removeAt(2);

      expect(pids(), ['tr-0', 'tr-1']);
      expect(get_().currentIndex, 1);
    });

    test('removing the only entry empties the queue', () {
      queue.playNow(['tr-0'], source: _album);
      queue.removeAt(0);

      expect(get_().isEmpty, isTrue);
      expect(get_().currentPid, isNull);
    });

    test('reordering follows the current entry rather than its index', () {
      queue.playNow(_tracks(4), source: _album, startIndex: 1);
      queue.reorder(3, 0);

      expect(pids(), ['tr-3', 'tr-0', 'tr-1', 'tr-2']);
      expect(get_().currentPid, 'tr-1');
      expect(get_().currentIndex, 2);
    });

    test('a drag that lands nowhere changes nothing', () {
      queue.playNow(_tracks(4), source: _album);
      queue.setShuffle(true);
      final order = pids();
      final sourceOrder = [...get_().sourceOrder];

      queue.reorder(3, 99);

      expect(pids(), order);
      expect(get_().sourceOrder, sourceOrder);
    });

    test('a hand-placed entry outranks the source order', () {
      queue.playNow(_tracks(4), source: _album);
      queue.setShuffle(true);
      queue.reorder(3, 1);
      final moved = get_().entries[1].pid;
      queue.setShuffle(false);

      expect(pids()[1], moved);
    });

    test('clearing keeps the standing preferences', () {
      queue.playNow(_tracks(3), source: _album);
      queue.setRepeat(QueueRepeat.all);
      queue.setShuffle(true);
      queue.clear();

      expect(get_().isEmpty, isTrue);
      expect(get_().repeat, QueueRepeat.all);
      expect(get_().shuffled, isTrue);
      expect(get_().source, QueueSource.none);
    });
  });

  group('shuffle', () {
    test('shuffling leaves the current entry and its history alone', () {
      queue.playNow(_tracks(10), source: _album, startIndex: 3);
      queue.setShuffle(true);

      expect(pids().take(4), ['tr-0', 'tr-1', 'tr-2', 'tr-3']);
      expect(get_().currentPid, 'tr-3');
      expect(pids().skip(4).toSet(), {
        'tr-4',
        'tr-5',
        'tr-6',
        'tr-7',
        'tr-8',
        'tr-9',
      });
      expect(
        pids().skip(4).toList(),
        isNot(['tr-4', 'tr-5', 'tr-6', 'tr-7', 'tr-8', 'tr-9']),
      );
    });

    test('un-shuffling puts the remainder back in source order', () {
      queue.playNow(_tracks(8), source: _album, startIndex: 1);
      queue.setShuffle(true);
      queue.setShuffle(false);

      expect(pids(), _tracks(8));
      expect(get_().shuffled, isFalse);
    });

    test('un-shuffling keeps the order actually played, not the source', () {
      queue.playNow(_tracks(8), source: _album);
      queue.setShuffle(true);
      queue.advance();
      queue.advance();
      final played = pids().take(3).toList();
      queue.setShuffle(false);

      expect(pids().take(3), played);
      final remainder = pids().skip(3).toList();
      expect(remainder, [...remainder]..sort());
    });

    test('shuffle on an empty queue is just the flag', () {
      queue.setShuffle(true);

      expect(get_().shuffled, isTrue);
      expect(get_().isEmpty, isTrue);
    });

    test('the flag does not flap when set to what it already is', () {
      queue.playNow(_tracks(6), source: _album);
      queue.setShuffle(true);
      final shuffled = pids();
      queue.setShuffle(true);

      expect(pids(), shuffled);
    });
  });

  group('undo', () {
    test('a replacement can be taken back with where it stood', () {
      queue.playNow(_tracks(4), source: _album, startIndex: 2);
      queue.setRepeat(QueueRepeat.all);
      queue.playNow(
        ['ep-1', 'ep-2'],
        source: _playlist,
        replacedPositionMs: 91000,
      );

      expect(pids(), ['ep-1', 'ep-2']);
      expect(queue.undoReplace(), 91000);
      expect(pids(), _tracks(4));
      expect(get_().currentIndex, 2);
      expect(get_().source, _album);
      expect(get_().repeat, QueueRepeat.all);
    });

    test('taking back a shuffle takes the toggle back with it', () {
      queue.playNow(_tracks(4), source: _album);
      queue.playNow(_tracks(6), source: _playlist, shuffle: true);
      expect(get_().shuffled, isTrue);

      queue.undoReplace();

      // The tap turned shuffle on; undoing the tap undoes that too.
      expect(get_().shuffled, isFalse);
      expect(pids(), _tracks(4));
    });

    test('there is nothing to take back before the first replacement', () {
      queue.playNow(_tracks(2), source: _album);

      expect(queue.undoReplace(), isNull);
      expect(pids(), _tracks(2));
    });

    test('undo does not chain: one step back, not a history', () {
      queue.playNow(['tr-A'], source: _album);
      queue.playNow(['tr-B'], source: _playlist);
      queue.playNow(['tr-C'], source: _playlist);

      expect(queue.undoReplace(), 0);
      expect(pids(), ['tr-B']);
      expect(queue.undoReplace(), isNull);
    });
  });

  group('serialization', () {
    test('a queue round-trips through what is persisted', () {
      queue.playNow(_tracks(6), source: _album, startIndex: 2);
      queue.setShuffle(true);
      queue.setRepeat(QueueRepeat.all);
      final before = get_();

      final restored = QueueState.fromStored(
        before.toStored(updatedAt: DateTime.utc(2026, 7, 25)),
      );

      expect(restored.pids, before.pids);
      expect(
        [for (final e in restored.entries) e.queueId],
        [for (final e in before.entries) e.queueId],
      );
      expect(restored.sourceOrder, before.sourceOrder);
      expect(restored.currentIndex, before.currentIndex);
      expect(restored.shuffled, isTrue);
      expect(restored.repeat, QueueRepeat.all);
      expect(restored.source, _album);
      expect(restored.nextQueueId, before.nextQueueId);
      expect(restored.undo, isNull);
    });

    test('a restored queue un-shuffles to the order it was built in', () {
      queue.playNow(_tracks(6), source: _album);
      queue.setShuffle(true);
      final stored = get_().toStored(updatedAt: DateTime.utc(2026, 7, 25));

      queue.restore(QueueState.fromStored(stored));
      queue.setShuffle(false);

      expect(pids(), _tracks(6));
    });

    test('a restored queue mints ids that cannot collide', () {
      queue.playNow(_tracks(3), source: _album);
      final stored = get_().toStored(updatedAt: DateTime.utc(2026, 7, 25));
      final live = [for (final e in get_().entries) e.queueId];

      // A counter left behind its entries by a torn write.
      queue.restore(
        QueueState.fromStored(
          StoredQueue(
            entries: stored.entries,
            currentIndex: stored.currentIndex,
            shuffled: stored.shuffled,
            repeat: stored.repeat,
            sourceKind: stored.sourceKind,
            sourceLabel: stored.sourceLabel,
            nextQueueId: 0,
            updatedAt: stored.updatedAt,
          ),
        ),
      );
      queue.addToEnd(['tr-new']);

      expect(live, isNot(contains(get_().entries.last.queueId)));
    });

    test('ranks that collide fall back to play order', () {
      // What a torn write or an older build could leave behind: every
      // entry claiming the same place in the source order.
      final restored = QueueState.fromStored(
        StoredQueue(
          entries: const [
            StoredQueueEntry(queueId: 'q0', pid: 'tr-A', sourceRank: 0),
            StoredQueueEntry(queueId: 'q1', pid: 'tr-B', sourceRank: 0),
            StoredQueueEntry(queueId: 'q2', pid: 'tr-C', sourceRank: 0),
          ],
          currentIndex: 0,
          shuffled: true,
          repeat: 'off',
          sourceKind: 'album',
          sourceLabel: 'Kind of Blue',
          nextQueueId: 3,
          updatedAt: DateTime.utc(2026, 7, 25),
        ),
      );

      expect(restored.sourceOrder, ['q0', 'q1', 'q2']);
      queue.restore(restored);
      queue.setShuffle(false);
      expect(pids(), ['tr-A', 'tr-B', 'tr-C']);
    });

    test('restoring drops any undo the live queue was holding', () {
      queue.playNow(_tracks(2), source: _album);
      queue.playNow(['ep-1'], source: _playlist);
      queue.restore(
        QueueState.fromStored(
          get_().toStored(updatedAt: DateTime.utc(2026, 7, 25)),
        ),
      );

      expect(queue.undoReplace(), isNull);
    });
  });
}
