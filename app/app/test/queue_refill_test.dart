import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_refiller.dart';
import 'package:waxdeck/src/queue/queue_source_pager.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

const _genre = QueueSource(
  kind: QueueSourceKind.genre,
  label: 'Jazz',
  pid: 'ge-1',
  rolling: true,
  cursor: 'c-1',
);

List<String> _tracks(int count, {int from = 0}) => [
  for (var i = from; i < from + count; i++) 'tr-$i',
];

/// A pager whose answers a test writes, and which records what it was
/// asked. Standing in for the network, so the refill's own decisions -
/// when to draw, when to stop, what a failure costs - are what is under
/// test.
class _FakePager implements QueueSourcePager {
  _FakePager(this.answers);

  /// Answered in order; the last one repeats once the list runs out.
  final List<Object?> answers;
  final List<({String cursor, String? afterPid})> asks = [];
  var _at = 0;

  @override
  Future<QueueDraw?> draw(QueueSource source, {String? afterPid}) async {
    asks.add((cursor: source.cursor, afterPid: afterPid));
    final answer = answers[_at < answers.length ? _at : answers.length - 1];
    _at++;
    if (answer is Object && answer is! QueueDraw) throw answer;
    return answer as QueueDraw?;
  }
}

void main() {
  /// A container with the refiller held open the way the signed-in
  /// scope holds it: it is auto-disposing, so a container that only read
  /// it once would drop it before the queue ever drained.
  ProviderContainer harness(QueueSourcePager pager) {
    final container = ProviderContainer(
      overrides: [queueSourcePagerProvider.overrideWithValue(pager)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(queueRefillProvider, (_, _) {});
    addTearDown(subscription.close);
    return container;
  }

  group('the refiller', () {
    test('a draining window draws more of its scope', () async {
      final pager = _FakePager([
        QueueDraw(pids: _tracks(4, from: 5), cursor: 'c-2', more: true),
      ]);
      final container = harness(pager);
      final queue = container.read(queueControllerProvider.notifier);

      queue.playNow(_tracks(5), source: _genre);
      await pumpEventQueue();

      expect(container.read(queueControllerProvider).pids, _tracks(9));
      expect(container.read(queueControllerProvider).source.cursor, 'c-2');
      expect(pager.asks.single.cursor, 'c-1');
    });

    test('a window with plenty ahead of it is left alone', () async {
      final pager = _FakePager([
        const QueueDraw(pids: [], cursor: '', more: true),
      ]);
      final container = harness(pager);
      final queue = container.read(queueControllerProvider.notifier);

      queue.playNow(_tracks(kQueueRefillLead + 5), source: _genre);
      await pumpEventQueue();

      expect(pager.asks, isEmpty);
    });

    test('a queue that is not a window is never drawn against', () async {
      final pager = _FakePager([
        const QueueDraw(pids: [], cursor: '', more: true),
      ]);
      final container = harness(pager);
      final queue = container.read(queueControllerProvider.notifier);

      queue.playNow(
        _tracks(3),
        source: const QueueSource(
          kind: QueueSourceKind.album,
          label: 'Kind of Blue',
        ),
      );
      await pumpEventQueue();

      expect(pager.asks, isEmpty);
    });

    test('a scope with nothing left seals the window', () async {
      final pager = _FakePager([
        const QueueDraw(pids: [], cursor: '', more: false),
      ]);
      final container = harness(pager);
      final queue = container.read(queueControllerProvider.notifier);

      queue.playNow(_tracks(3), source: _genre);
      await pumpEventQueue();

      expect(container.read(queueControllerProvider).source.rolling, isFalse);
      expect(pager.asks, hasLength(1));
    });

    test('a source nothing can page seals the window once', () async {
      final pager = _FakePager([null]);
      final container = harness(pager);
      final queue = container.read(queueControllerProvider.notifier);

      queue.playNow(_tracks(3), source: _genre);
      await pumpEventQueue();
      queue.jumpTo(1);
      await pumpEventQueue();

      expect(container.read(queueControllerProvider).source.rolling, isFalse);
      expect(pager.asks, hasLength(1));
    });

    test('an empty page moves on rather than giving up', () async {
      final pager = _FakePager([
        const QueueDraw(pids: [], cursor: 'c-2', more: true),
        QueueDraw(pids: _tracks(2, from: 3), cursor: 'c-3', more: true),
      ]);
      final container = harness(pager);
      final queue = container.read(queueControllerProvider.notifier);

      queue.playNow(_tracks(3), source: _genre);
      await pumpEventQueue();

      expect(container.read(queueControllerProvider).pids, _tracks(5));
      expect(pager.asks.map((a) => a.cursor), ['c-1', 'c-2']);
    });

    test('a run of empty pages stops rather than walking the scope', () async {
      final pager = _FakePager([
        const QueueDraw(pids: [], cursor: 'c-x', more: true),
      ]);
      final container = harness(pager);
      final queue = container.read(queueControllerProvider.notifier);

      queue.playNow(_tracks(3), source: _genre);
      await pumpEventQueue();

      expect(pager.asks.length, lessThanOrEqualTo(5));
    });

    test(
      'a failed draw waits for the next entry before trying again',
      () async {
        final pager = _FakePager([
          const WaxDeckApiException(code: 'internal', message: 'down'),
          QueueDraw(pids: _tracks(2, from: 3), cursor: 'c-2', more: true),
        ]);
        final container = harness(pager);
        final queue = container.read(queueControllerProvider.notifier);

        queue.playNow(_tracks(3), source: _genre);
        await pumpEventQueue();
        expect(pager.asks, hasLength(1));

        // An edit that leaves the queue on the same entry does not retry.
        queue.setRepeat(QueueRepeat.all);
        await pumpEventQueue();
        expect(pager.asks, hasLength(1));

        // Moving on does.
        queue.jumpTo(1);
        await pumpEventQueue();
        expect(pager.asks, hasLength(2));
        expect(container.read(queueControllerProvider).pids, _tracks(5));
      },
    );

    test(
      'the draw is placed by the frontier when there is no cursor',
      () async {
        final pager = _FakePager([
          QueueDraw(pids: _tracks(2, from: 5), cursor: 'c-2', more: true),
        ]);
        final container = harness(pager);
        final queue = container.read(queueControllerProvider.notifier);

        // An ordered window cut short of what its caller had loaded keeps
        // no cursor, so the frontier entry is how the draw finds its place.
        queue.playNow(
          _tracks(kQueueCap + 20),
          source: const QueueSource(
            kind: QueueSourceKind.genre,
            label: 'Jazz',
            pid: 'ge-1',
            rolling: true,
            cursor: 'c-1',
          ),
        );
        queue.jumpTo(kQueueCap - 1);
        await pumpEventQueue();

        expect(pager.asks.last.cursor, isEmpty);
        expect(pager.asks.last.afterPid, 'tr-${kQueueCap - 1}');
      },
    );
  });

  group('the repository pager', () {
    RepositoryQueueSourcePager pagerOver(FakeRepository repository) =>
        RepositoryQueueSourcePager(repository);

    test('a bucket draws its facet from the cursor it was given', () async {
      final repository = FakeRepository();
      repository.facetItems['genre ge-1'] = [
        for (var i = 0; i < 250; i++) testItem('tr-$i'),
      ];
      final draw = await pagerOver(repository).draw(
        const QueueSource(
          kind: QueueSourceKind.genre,
          label: 'Jazz',
          pid: 'ge-1',
          rolling: true,
          cursor: '100',
        ),
      );

      expect(draw!.pids.first, 'tr-100');
      expect(draw.pids, hasLength(kQueueDrawSize));
      expect(draw.more, isTrue);
      expect(repository.facetDrills.last, ('genre', 'ge-1'));
    });

    test('a bucket draw leaves the audiobooks in it behind', () async {
      final repository = FakeRepository();
      repository.facetItems['artist 1'] = [
        testItem('tr-1'),
        testItem('bk-1', mediaType: MediaType.audiobook),
        testItem('tr-2'),
      ];
      final draw = await pagerOver(repository).draw(
        const QueueSource(
          kind: QueueSourceKind.artist,
          label: 'Miles',
          pid: 'ar-1',
          rolling: true,
          cursor: '0',
        ),
      );

      expect(draw!.pids, ['tr-1', 'tr-2']);
    });

    test('an entity bucket drills by its key, not by its pid', () async {
      final repository = FakeRepository();
      repository.facetItems['artist 01ABC'] = [testItem('tr-1')];
      await pagerOver(repository).draw(
        const QueueSource(
          kind: QueueSourceKind.artist,
          label: 'Miles',
          pid: 'ar-01ABC',
          rolling: true,
          cursor: '0',
        ),
      );

      expect(repository.facetDrills.last, ('artist', '01ABC'));
    });

    test('a cursorless draw pages from the head to find its place', () async {
      final repository = FakeRepository();
      repository.facetItems['genre ge-1'] = [
        for (var i = 0; i < 900; i++) testItem('tr-$i'),
      ];
      final draw = await pagerOver(repository).draw(
        const QueueSource(
          kind: QueueSourceKind.genre,
          label: 'Jazz',
          pid: 'ge-1',
          rolling: true,
        ),
        afterPid: 'tr-620',
      );

      expect(draw!.pids.first, 'tr-621');
      expect(draw.more, isFalse);
    });

    test('a frontier the source no longer holds draws nothing', () async {
      final repository = FakeRepository();
      repository.facetItems['genre ge-1'] = [testItem('tr-1')];
      final draw = await pagerOver(repository).draw(
        const QueueSource(
          kind: QueueSourceKind.genre,
          label: 'Jazz',
          pid: 'ge-1',
          rolling: true,
        ),
        afterPid: 'tr-gone',
      );

      expect(draw, isNull);
    });

    test('a seeded library window walks the same permutation', () async {
      final repository = FakeRepository(
        items: [for (var i = 0; i < 300; i++) testItem('tr-$i')],
      );
      final draw = await pagerOver(repository).draw(
        const QueueSource(
          kind: QueueSourceKind.library,
          label: 'All music',
          rolling: true,
          cursor: '100',
          seed: 99,
        ),
      );

      expect(draw!.pids.first, 'tr-100');
      expect(repository.randomBrowses.single, (seed: 99, cursor: '100'));
    });

    test('a source with no listing behind it cannot be drawn from', () async {
      final repository = FakeRepository();
      final draw = await pagerOver(repository).draw(
        const QueueSource(
          kind: QueueSourceKind.mix,
          label: 'Instant mix',
          rolling: true,
          cursor: 'c-1',
        ),
      );

      expect(draw, isNull);
    });

    // Persisted cursors outlive a server upgrade, so a rejected one
    // reaches clients. Without the fallback the window blocks and the
    // rolling queue silently ends at its last entry.
    // Paging the bucket's listing shuffled each page among itself.
    // Scoped, it is one permutation over the whole.
    test('a seeded bucket draws the random list scoped to itself', () async {
      final repository = FakeRepository();
      repository.facetItems['genre ge-1'] = [
        for (var i = 0; i < 250; i++) testItem('tr-$i'),
      ];
      final draw = await pagerOver(repository).draw(
        const QueueSource(
          kind: QueueSourceKind.genre,
          label: 'Jazz',
          pid: 'ge-1',
          rolling: true,
          cursor: '0',
          seed: 42,
        ),
      );

      expect(draw, isNotNull);
      expect(repository.scopedBrowses.single, (
        facet: 'genre',
        facetKey: 'ge-1',
        seed: 42,
      ));
    });

    test('an unseeded bucket still pages its own listing', () async {
      // No seed is no shuffle.
      final repository = FakeRepository();
      repository.facetItems['genre ge-1'] = [
        for (var i = 0; i < 250; i++) testItem('tr-$i'),
      ];
      await pagerOver(repository).draw(
        const QueueSource(
          kind: QueueSourceKind.genre,
          label: 'Jazz',
          pid: 'ge-1',
          rolling: true,
          cursor: '0',
        ),
      );

      expect(repository.scopedBrowses, isEmpty);
      expect(repository.facetDrills.last, ('genre', 'ge-1'));
    });

    test('a refused cursor falls through to a placed draw', () async {
      final repository = FakeRepository();
      repository.facetItems['genre ge-1'] = [
        for (var i = 0; i < 900; i++) testItem('tr-$i'),
      ];
      repository.rejectedCursors.add('stale-cursor');
      final draw = await pagerOver(repository).draw(
        const QueueSource(
          kind: QueueSourceKind.genre,
          label: 'Jazz',
          pid: 'ge-1',
          rolling: true,
          cursor: 'stale-cursor',
        ),
        afterPid: 'tr-620',
      );

      expect(draw, isNotNull);
      expect(draw!.pids.first, 'tr-621');
    });

    test('a refused cursor on a browse-backed source places too', () async {
      // The seeded library window reads through browse rather than
      // listItems, and persists its cursor the same way.
      final repository = FakeRepository(
        items: [for (var i = 0; i < 900; i++) testItem('tr-$i')],
      );
      repository.rejectedCursors.add('stale-cursor');
      final draw = await pagerOver(repository).draw(
        const QueueSource(
          kind: QueueSourceKind.library,
          label: 'All music',
          rolling: true,
          cursor: 'stale-cursor',
          seed: 99,
        ),
        afterPid: 'tr-620',
      );

      expect(draw, isNotNull);
      expect(draw!.pids.first, 'tr-621');
    });

    test(
      'a refused cursor with no frontier seals rather than retries',
      () async {
        // A rejected cursor is permanently rejected, so rethrowing would
        // block the window and retry per track forever while it kept
        // claiming there was more. Null is what the no-cursor path answers
        // in the same spot, and it seals.
        final repository = FakeRepository();
        repository.facetItems['genre ge-1'] = [testItem('tr-1')];
        repository.rejectedCursors.add('stale-cursor');
        final draw = await pagerOver(repository).draw(
          const QueueSource(
            kind: QueueSourceKind.genre,
            label: 'Jazz',
            pid: 'ge-1',
            rolling: true,
            cursor: 'stale-cursor',
          ),
        );

        expect(draw, isNull);
      },
    );

    test('any other failure still throws', () async {
      // Only a rejected cursor is recoverable. Swallowing a transport
      // failure would seal a window that is merely offline.
      final repository = FakeRepository();
      repository.facetItems['genre ge-1'] = [testItem('tr-1')];
      repository.listError = const WaxDeckApiException(
        code: 'internal',
        message: 'the catalog is busy',
      );
      await expectLater(
        pagerOver(repository).draw(
          const QueueSource(
            kind: QueueSourceKind.genre,
            label: 'Jazz',
            pid: 'ge-1',
            rolling: true,
            cursor: 'c-1',
          ),
          afterPid: 'tr-1',
        ),
        throwsA(isA<WaxDeckApiException>()),
      );
    });
  });
}
