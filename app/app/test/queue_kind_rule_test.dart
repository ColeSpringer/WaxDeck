import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_refiller.dart';
import 'package:waxdeck/src/queue/queue_source_pager.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'app_host.dart';
import 'fakes.dart';

ItemSummary _book(String pid) =>
    testItem(pid, mediaType: MediaType.audiobook, durationMs: 43200000);

ItemSummary _episode(String pid) =>
    testItem(pid, mediaType: MediaType.podcast, durationMs: 3600000);

/// An unscoped bucket, as a whole-library listing mints one: its cursor
/// was issued under no scope.
const _genre = QueueSource(
  kind: QueueSourceKind.genre,
  label: 'Ambient',
  pid: 'ge-1',
  rolling: true,
  cursor: 'unscoped-cursor',
);

final _mixed = <ItemSummary>[
  testItem('tr-1'),
  _book('bk-1'),
  testItem('tr-2'),
  _episode('ep-1'),
  testItem('tr-3'),
  _episode('ep-2'),
];

extension on ProviderContainer {
  NowPlayingController get playback => read(nowPlayingProvider.notifier);
  QueueState get queueState => read(queueControllerProvider);
}

void main() {
  test('a kind continues itself and nothing else', () {
    expect(continuesKind(MediaType.music, testItem('tr-1')), isTrue);
    expect(continuesKind(MediaType.music, _book('bk-1')), isFalse);
    expect(continuesKind(MediaType.music, _episode('ep-1')), isFalse);
    expect(continuesKind(MediaType.podcast, _episode('ep-1')), isTrue);
    expect(continuesKind(MediaType.audiobook, testItem('tr-1')), isFalse);
  });

  group('play', () {
    ProviderContainer harness() =>
        appContainer(repo: FakeRepository(items: _mixed));

    test('a listing queues the tapped row\'s kind and lands on it', () async {
      final container = harness();

      container.playback.play(_mixed, source: _genre, startIndex: 4);
      await pumpEventQueue();

      expect(container.queueState.pids, ['tr-1', 'tr-2', 'tr-3']);
      expect(container.queueState.currentPid, 'tr-3');
      // Scoped to what it plays, and the unscoped cursor left behind: a
      // draw finds its place from the queue's last entry instead.
      final source = container.queueState.source;
      expect(source.mediaType, MediaType.music);
      expect(source.cursor, isEmpty);
      expect(source.rolling, isTrue);
    });

    test('an episode tapped in a listing queues its own kind', () async {
      final container = harness();

      container.playback.play(_mixed, source: _genre, startIndex: 5);
      await pumpEventQueue();

      expect(container.queueState.pids, ['ep-1', 'ep-2']);
      expect(container.queueState.currentPid, 'ep-2');
      expect(container.queueState.source.mediaType, MediaType.podcast);
    });

    test('a shuffle plays the source\'s kind, whatever row is first', () async {
      final container = harness();

      container.playback.play(
        [_book('bk-1'), ..._mixed],
        source: _genre,
        shuffle: true,
      );
      await pumpEventQueue();

      expect(container.queueState.pids.toSet(), {'tr-1', 'tr-2', 'tr-3'});
      expect(container.queueState.source.mediaType, MediaType.music);
    });

    test(
      'a listing scoped to another kind than the row is scoped anew',
      () async {
        // Unreachable from a scoped read today; held by construction.
        final container = harness();

        container.playback.play(
          _mixed,
          source: _genre.copyWith(
            cursor: 'books-cursor',
            mediaType: MediaType.audiobook,
          ),
        );
        await pumpEventQueue();

        expect(container.queueState.pids, ['tr-1', 'tr-2', 'tr-3']);
        expect(container.queueState.source.mediaType, MediaType.music);
        expect(container.queueState.source.cursor, isEmpty);
      },
    );

    test('a scoped listing keeps the cursor it was paged under', () async {
      final container = harness();
      final scoped = QueueSource(
        kind: QueueSourceKind.genre,
        label: 'Ambient',
        pid: 'ge-1',
        rolling: true,
        cursor: 'music-cursor',
        mediaType: MediaType.music,
      );

      container.playback.play(_mixed, source: scoped);
      await pumpEventQueue();

      expect(container.queueState.pids, ['tr-1', 'tr-2', 'tr-3']);
      expect(container.queueState.source, scoped);
    });

    test('a hand-built list plays as it was built', () async {
      for (final kind in <QueueSourceKind>[
        QueueSourceKind.playlist,
        QueueSourceKind.book,
        QueueSourceKind.show,
        QueueSourceKind.single,
        QueueSourceKind.unknown,
      ]) {
        final container = harness();
        final source = QueueSource(kind: kind, label: 'Mine', pid: 'pl-1');

        container.playback.play(_mixed, source: source, startIndex: 1);
        await pumpEventQueue();

        expect(container.queueState.pids, [
          for (final item in _mixed) item.pid,
        ], reason: kind.wireName);
        expect(container.queueState.currentPid, 'bk-1', reason: kind.wireName);
        expect(container.queueState.source, source, reason: kind.wireName);
      }
    });

    test('a listing with nothing of the kind queues nothing', () {
      final container = harness();

      final queued = container.playback.play(
        [_book('bk-1'), _episode('ep-1')],
        source: _genre,
        shuffle: true,
      );

      expect(queued, isFalse);
      expect(container.queueState.isEmpty, isTrue);
    });
  });

  group('a hand add before the first draw', () {
    // The play drops the unscoped cursor, so the first draw places itself
    // in the listing. An "Add to queue" lands at the queue's end before
    // then, and must not become the place the listing is read on from.
    final bucket = <ItemSummary>[
      for (var i = 0; i < 300; i++) testItem('tr-$i'),
    ];
    final listed = [for (final item in bucket) item.pid];

    Future<ProviderContainer> played() async {
      final repo = FakeRepository(items: [...bucket, testItem('tr-elsewhere')])
        ..facetItems['genre ge-1'] = bucket;
      final container = appContainer(repo: repo);
      final refill = container.listen(queueRefillProvider, (_, _) {});
      addTearDown(refill.close);
      final page = await repo.listItems(
        facet: 'genre',
        facetKey: 'ge-1',
        limit: 200,
      );
      container.playback.play(
        page.items,
        source: QueueSource(
          kind: QueueSourceKind.genre,
          label: 'Ambient',
          pid: 'ge-1',
          rolling: true,
          cursor: page.nextCursor!,
        ),
      );
      await pumpEventQueue();
      return container;
    }

    Future<void> drain(ProviderContainer container) async {
      container
          .read(queueControllerProvider.notifier)
          .jumpTo(container.queueState.length - 2);
      await pumpEventQueue();
    }

    test('from outside the listing, the listing still draws on', () async {
      final container = await played();
      container.playback.enqueue([testItem('tr-elsewhere')]);
      await pumpEventQueue();

      await drain(container);

      final pids = container.queueState.pids;
      expect(pids.where(listed.contains), listed);
      expect(pids, contains('tr-elsewhere'));
    });

    test('from inside the listing, nothing between is skipped', () async {
      final container = await played();
      container.playback.enqueue([testItem('tr-250')]);
      await pumpEventQueue();

      await drain(container);

      final pids = container.queueState.pids;
      expect(pids.toSet(), {...listed});
      expect(pids, hasLength(listed.length), reason: 'nothing twice');
    });
  });

  test('a shuffle of an unscoped bucket draws on without repeating or '
      'skipping what it queued', () async {
    // Half books, past a page: the first page is a shuffle's whole
    // window, and the rest arrives by draws under the scope the play
    // stamped. The fake lists a seeded random page in one order whatever
    // the scope, as the server's per-item shuffle key does.
    final bucket = <ItemSummary>[
      for (var i = 0; i < 700; i++)
        i % 3 == 1 ? _book('bk-$i') : testItem('tr-$i'),
    ];
    final music = [
      for (final item in bucket)
        if (item.mediaType == MediaType.music) item.pid,
    ];
    final repo = FakeRepository(items: bucket)
      ..facetItems['genre ge-1'] = bucket;
    final pager = _RecordingPager(RepositoryQueueSourcePager(repo));
    final container = appContainer(
      repo: repo,
      extra: [queueSourcePagerProvider.overrideWithValue(pager)],
    );
    final refill = container.listen(queueRefillProvider, (_, _) {});
    addTearDown(refill.close);

    final page = await repo.browse(
      DiscoveryList.random,
      facet: 'genre',
      facetKey: 'ge-1',
      limit: kQueueCap,
    );
    container.playback.play(
      page.items,
      shuffle: true,
      source: QueueSource(
        kind: QueueSourceKind.genre,
        label: 'Ambient',
        pid: 'ge-1',
        rolling: page.nextCursor != null,
        cursor: page.nextCursor ?? '',
        seed: page.seed,
      ),
    );
    await pumpEventQueue();
    final queued = container.queueState.pids.toSet();
    expect(queued.every((pid) => pid.startsWith('tr-')), isTrue);

    // Drained to the refill's lead, so it draws.
    container
        .read(queueControllerProvider.notifier)
        .jumpTo(container.queueState.length - 2);
    await pumpEventQueue();

    final drawn = [for (final draw in pager.draws) ...draw.pids];
    expect(drawn.where(queued.contains), isEmpty, reason: 'repeated');
    expect(drawn.toSet(), hasLength(drawn.length), reason: 'repeated');
    expect({...queued, ...drawn}, music.toSet(), reason: 'skipped');
    expect(container.queueState.source.rolling, isFalse);
  });
}

/// The real pager, with what each draw handed back kept.
class _RecordingPager implements QueueSourcePager {
  _RecordingPager(this._inner);

  final QueueSourcePager _inner;
  final List<QueueDraw> draws = [];

  @override
  Future<QueueDraw?> draw(QueueSource source, {String? afterPid}) async {
    final draw = await _inner.draw(source, afterPid: afterPid);
    if (draw != null) draws.add(draw);
    return draw;
  }
}
