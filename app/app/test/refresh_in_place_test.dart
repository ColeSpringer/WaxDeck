import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/review/review_controller.dart';
import 'package:waxdeck/src/review/review_entry_screen.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/sync/catalog_reads.dart';
import 'package:waxdeck/src/sync/refresh_in_place.dart';
import 'package:waxdeck/src/sync/refresh_pacing.dart';
import 'package:waxdeck/src/sync/sync_binder.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

/// The tracks index: the listing that pages the whole library.
const MusicListing _tracks = (
  dimension: null,
  segment: '',
  domain: BrowseDomain.music,
);

const _page = MusicItemsController.pageSize;

String _pid(int at) => 'tr-${at.toString().padLeft(7, '0')}';

ItemSummary _row(int at, {String? title}) =>
    testItem(_pid(at), title: title ?? 'Track $at');

/// A tracks listing sorted by a key apart from its rows' pids, so a row
/// can move and stay itself. Pages are cut by key, as the server cuts
/// them: a row that arrives ahead of a cursor moves nothing after it.
/// Counts its requests, and holds or fails them.
class _Library extends FakeRepository {
  _Library(Iterable<int> keys) {
    place(keys);
  }

  final _rows = SplayTreeMap<int, ItemSummary>();

  /// The listing, in order.
  List<ItemSummary> get tracks => _rows.values.toList();

  /// Adds a row at each of [keys] that holds none.
  void place(Iterable<int> keys) {
    for (final key in keys) {
      _rows.putIfAbsent(key, () => _row(key));
    }
  }

  /// Moves the row at [from] to [to], as a rename moves a sorted row.
  void move(int from, int to) => _rows[to] = _rows.remove(from)!;

  void retitle(int at, String title) => _rows[at] = _row(at, title: title);

  /// Pids dropped from a page after it is cut, its cursor still counting
  /// them.
  final hidden = <String>{};

  /// The cursor each request asked from, in call order.
  final requests = <String?>[];

  /// Called as each request arrives, before it is answered.
  void Function(String? cursor)? onRequest;

  /// Held open, every request waits on it.
  Completer<void>? gate;

  /// Thrown by every request while set: [failure] as a server refuses,
  /// [defect] as a bug does.
  WaxDeckApiException? failure;
  Error? defect;

  @override
  Future<ItemPage> listItems({
    MediaType? mediaType,
    String? facet,
    String? facetKey,
    String? cursor,
    int? limit,
  }) async {
    requests.add(cursor);
    onRequest?.call(cursor);
    await gate?.future;
    final error = failure;
    if (error != null) throw error;
    final bug = defect;
    if (bug != null) throw bug;
    final after = cursor == null ? -1 : int.parse(cursor);
    final rest = [
      for (final MapEntry(:key, :value) in _rows.entries)
        if (key > after) (key: key, item: value),
    ];
    final size = limit ?? 100;
    final page = rest.take(size).toList();
    return ItemPage(
      items: [
        for (final row in page)
          if (!hidden.contains(row.item.pid)) row.item,
      ],
      nextCursor: rest.length > size ? '${page.last.key}' : null,
    );
  }

  /// A catalog change for the sync engine's next pull to find.
  void changeCatalog() => catalogPages.add(
    CatalogSyncPage(
      entries: [
        CatalogSyncEntry(
          op: 'upsert',
          pid: tracks.first.pid,
          item: tracks.first,
        ),
      ],
      nextSince: 'since-${catalogPages.length}',
    ),
  );
}

List<String> _pids(Iterable<ItemSummary> items) => [
  for (final item in items) item.pid,
];

/// The tracks index held open over [repo], as a mounted screen holds it,
/// with [pages] pages loaded.
Future<ProviderContainer> _holdTracks(_Library repo, {int pages = 1}) async {
  final container = appContainer(repo: repo);
  final held = container.listen(musicItemsProvider(_tracks), (_, _) {});
  addTearDown(held.close);
  await container.read(musicItemsProvider(_tracks).future);
  for (var i = 1; i < pages; i++) {
    await container.read(musicItemsProvider(_tracks).notifier).loadMore();
  }
  repo.requests.clear();
  return container;
}

MusicItemsState _held(ProviderContainer container) =>
    container.read(musicItemsProvider(_tracks)).requireValue;

/// A refresh under way, landed. Not the provider's future: a page that
/// lands while a refresh waits behind it completes that first.
Future<MusicItemsState> _landed(ProviderContainer container) async {
  await container.pump();
  await pumpEventQueue();
  return _held(container);
}

/// Pages the tracks index to its end.
Future<MusicItemsState> _pagedOut(ProviderContainer container) async {
  final notifier = container.read(musicItemsProvider(_tracks).notifier);
  for (var page = 0; _held(container).hasMore; page++) {
    expect(page, lessThan(40), reason: 'paging never reached an end');
    await notifier.loadMore();
  }
  return _held(container);
}

/// The binder over a sync engine's mirror, so a catalog hint is the
/// engine's own: a pull that found a change.
({ProviderContainer container, SyncEngine sync}) _bound(FakeRepository repo) {
  final db = inMemoryMirrorDatabase();
  addTearDown(db.close);
  final downloads = FakeDownloads();
  addTearDown(downloads.dispose);
  final sync = SyncEngine(
    db: db,
    repository: repo,
    channelFactory: deadChannelFactory(),
  );
  addTearDown(sync.dispose);
  final container = appContainer(
    repo: repo,
    mirror: db,
    downloads: downloads,
    sync: sync,
  );
  container.listen(syncBinderProvider, (_, _) {});
  return (container: container, sync: sync);
}

/// Holds the review queue's next-page reads while [pageGate] is set; a
/// read from its head answers at once.
class _HeldPages extends FakeRepository {
  Completer<void>? pageGate;

  /// The cursor each read asked from, in call order.
  final reads = <String?>[];

  @override
  Future<ReviewEntryPage> listReviewQueue({
    String? status,
    String? cursor,
    int? limit,
  }) async {
    reads.add(cursor);
    if (cursor != null) await pageGate?.future;
    return super.listReviewQueue(status: status, cursor: cursor, limit: limit);
  }
}

/// Holds a dimension's reads from its head while [headGate] is set, and
/// its reads from a letter while [letterGate] is.
class _HeldFacets extends FakeRepository {
  Completer<void>? headGate;
  Completer<void>? letterGate;

  @override
  Future<FacetPage> listFacets(
    String dimension, {
    FacetSort? sort,
    String? cursor,
    String? startsAt,
    String? facet,
    String? facetKey,
    int? limit,
  }) async {
    final page = super.listFacets(
      dimension,
      sort: sort,
      cursor: cursor,
      startsAt: startsAt,
      facet: facet,
      facetKey: facetKey,
      limit: limit,
    );
    await (startsAt == null ? headGate : letterGate)?.future;
    return page;
  }
}

void main() {
  group('a listing read to its end, under a head pass', () {
    test('has more once it grows past the head, and pages to its '
        'end', () async {
      final repo = _Library([for (var i = 0; i < 300; i++) i * 10]);
      final container = await _holdTracks(repo);
      expect(_held(container).hasMore, isFalse);

      // A scan lands rows all through it: past one page, then past two.
      for (final step in [2, 1]) {
        repo.place([for (var key = 0; key <= 2990; key += step) key]);
        repo.requests.clear();
        container.read(catalogFanOutProvider).sweep(CatalogRefresh.head);
        final state = await _landed(container);

        expect(repo.tracks.length, greaterThan(state.items.length));
        expect(state.hasMore, isTrue, reason: 'an end the listing outgrew');
        expect(repo.requests.length, lessThanOrEqualTo(2));
      }

      final end = await _pagedOut(container);
      expect(end.items.last.pid, repo.tracks.last.pid);
      expect(_pids(end.items).toSet(), hasLength(end.items.length));

      // What the head passes could not see, the loaded pass reads.
      container.read(catalogFanOutProvider).sweep(CatalogRefresh.loaded);
      expect(_pids((await _landed(container)).items), _pids(repo.tracks));
    });

    test('is walked through the extent it held when it grows, once', () async {
      final repo = _Library([for (var i = 0; i < 1200; i++) i * 10]);
      final container = await _holdTracks(repo, pages: 3);
      expect(_held(container).items, hasLength(1200));
      expect(_held(container).hasMore, isFalse);

      repo.place([for (var key = 0; key <= 11990; key += 5) key]);
      container.read(catalogFanOutProvider).sweep(CatalogRefresh.head);
      var state = await _landed(container);

      // The head's two pages, read on through the rows held.
      expect(repo.requests, [null, '2495', '4995']);
      expect(_pids(state.items), _pids(repo.tracks.take(3 * _page)));
      expect(state.hasMore, isTrue);

      // It has a cursor of its own now: the next pass is a head pass.
      repo.place([for (var key = 2; key <= 11990; key += 5) key]);
      repo.requests.clear();
      container.read(catalogFanOutProvider).sweep(CatalogRefresh.head);
      state = await _landed(container);

      expect(repo.requests, hasLength(2));
      expect(state.hasMore, isTrue);

      final end = await _pagedOut(container);
      expect(end.items.last.pid, repo.tracks.last.pid);
      expect(_pids(end.items).toSet(), hasLength(end.items.length));
    });
  });

  group('a paged listing refreshed in place', () {
    test('a head pass a start-over overtakes owes nothing back', () async {
      const key = (
        dimension: MusicDimension.artists,
        sort: FacetSort.label,
        domain: BrowseDomain.music,
      );
      final repo = FakeRepository()
        ..facets['artist'] = [
          for (var i = 0; i < 1300; i++)
            FacetBucket(
              key: 'k$i',
              label: 'Artist ${i.toString().padLeft(4, '0')}',
              count: 1,
            ),
        ];
      final container = appContainer(repo: repo);
      final held = container.listen(musicIndexProvider(key), (_, _) {});
      addTearDown(held.close);
      await container.read(musicIndexProvider(key).future);
      final notifier = container.read(musicIndexProvider(key).notifier);
      await notifier.loadMore();
      await notifier.loadMore();
      repo.facetReads.clear();

      // A head pass is out when the index is started over.
      final gate = repo.facetGate = Completer<void>();
      container.read(catalogFanOutProvider).sweep(CatalogRefresh.head);
      await container.pump();
      await pumpEventQueue();
      expect(repo.facetReads, hasLength(1));
      notifier.reset();
      await container.pump();
      await pumpEventQueue();
      expect(repo.facetReads, hasLength(2));

      repo.facetGate = null;
      gate.complete();
      await container.pump();
      await pumpEventQueue();
      final restarted = container.read(musicIndexProvider(key));
      expect((restarted.isLoading, restarted.hasError), (false, false));
      expect(restarted.requireValue.buckets, hasLength(500));
      expect(repo.facetReads, hasLength(2), reason: 'read whole: no pass');

      // Nothing is owed: an invalidation that names no depth reads the
      // three pages held, where a head left owed would read two.
      await notifier.loadMore();
      await notifier.loadMore();
      repo.facetReads.clear();
      container.invalidate(musicIndexProvider(key));
      await container.pump();
      await pumpEventQueue();

      expect(repo.facetReads, hasLength(3));
      expect(
        container.read(musicIndexProvider(key)).requireValue.buckets,
        hasLength(1300),
      );
    });

    for (final depth in CatalogRefresh.values) {
      test('a row that moves past a page boundary under a ${depth.name} '
          'walk is listed once', () async {
        final repo = _Library([for (var i = 0; i < 2000; i++) i * 10]);
        final container = await _holdTracks(repo, pages: 3);

        // Renamed between the walk's first page, which held it, and its
        // second, which holds it now.
        var moved = false;
        repo.onRequest = (cursor) {
          if (cursor == null || moved) return;
          moved = true;
          repo.move(30, 5005);
        };
        container.read(catalogFanOutProvider).sweep(depth);
        final state = await _landed(container);

        expect(moved, isTrue);
        expect(_pids(state.items).where((pid) => pid == _pid(30)), [_pid(30)]);
        expect(_pids(state.items).toSet(), hasLength(state.items.length));
      });
    }

    test('a head read that comes back empty short of the end keeps the '
        'listing', () async {
      final repo = _Library([for (var i = 0; i < 2000; i++) i * 10]);
      final container = await _holdTracks(repo, pages: 3);
      final before = _pids(_held(container).items);

      // Two pages the server emptied after it cut them.
      repo.hidden.addAll(_pids(repo.tracks.take(2 * _page)));
      container.read(catalogFanOutProvider).sweep(CatalogRefresh.head);
      final state = await _landed(container);

      expect(repo.requests, [null, '4990']);
      expect(_pids(state.items), before);
      expect(state.hasMore, isTrue);
    });

    testWidgets('a head pass that fails is read again once the run goes '
        'quiet', (tester) async {
      final repo = _Library([for (var i = 0; i < 1500; i++) i * 10]);
      final s = _bound(repo);
      final listing = musicItemsProvider(_tracks);
      s.container.listen(listing, (_, _) {});
      await tester.pump();
      final notifier = s.container.read(listing.notifier);
      await notifier.loadMore();
      await notifier.loadMore();
      expect(_held(s.container).items, hasLength(3 * _page));
      await tester.pump(kCatalogRefreshWindow * 2);
      repo.requests.clear();

      // One hint, and the pass it prompts cannot reach the server.
      repo.retitle(30, 'Retitled');
      repo.failure = const WaxDeckApiException(
        code: 'transport',
        message: 'connection refused',
      );
      repo.changeCatalog();
      await s.sync.pullCatalog();
      await tester.pump(const Duration(seconds: 1));

      expect(repo.requests, [null]);
      final failed = s.container.read(listing);
      expect((failed.isLoading, failed.hasError), (false, false));
      expect(failed.requireValue.items[3].title, 'Track 30');

      // No further hint: the run's trailing pass is what asks again.
      repo.failure = null;
      repo.requests.clear();
      await tester.pump(kCatalogRefreshWindow);
      await tester.pump(const Duration(seconds: 1));

      expect(repo.requests, [null, '4990', '9990']);
      expect(_held(s.container).items[3].title, 'Retitled');

      await tester.pump(const Duration(seconds: 1));
      s.container.dispose();
      await tester.pump();
    });
  });

  group('a refresh that fails asks again by itself', () {
    final listing = musicItemsProvider(_tracks);
    const down = WaxDeckApiException(
      code: 'transport',
      message: 'connection refused',
    );
    const second = Duration(seconds: 1);

    /// Long enough for a rebuild an invalidation scheduled to run.
    const tick = Duration(milliseconds: 1);

    /// The tracks index watched over [repo] with three pages loaded, under
    /// the test's clock. The test disposes the container itself: its
    /// timers must be gone before the binding checks for any.
    Future<(ProviderContainer, ProviderSubscription<Object?>)> watched(
      WidgetTester tester,
      _Library repo,
    ) async {
      final container = appContainer(repo: repo);
      final held = container.listen(listing, (_, _) {});
      await tester.pump();
      final notifier = container.read(listing.notifier);
      await notifier.loadMore();
      await notifier.loadMore();
      expect(_held(container).items, hasLength(3 * _page));
      repo.requests.clear();
      return (container, held);
    }

    /// A refresh of the loaded extent that the server refuses.
    Future<void> failOnce(
      WidgetTester tester,
      ProviderContainer container,
      _Library repo,
    ) async {
      repo.failure = down;
      container.read(listing.notifier).owe(CatalogRefresh.loaded);
      container.invalidate(listing);
      await tester.pump(tick);
    }

    testWidgets('a trailing pass that fails is read again with no further '
        'hint', (tester) async {
      final repo = _Library([for (var i = 0; i < 1500; i++) i * 10]);
      final s = _bound(repo);
      s.container.listen(listing, (_, _) {});
      await tester.pump();
      final notifier = s.container.read(listing.notifier);
      await notifier.loadMore();
      await notifier.loadMore();
      await tester.pump(kCatalogRefreshWindow * 2);
      repo.requests.clear();

      // One hint; its pass and the run's trailing pass both fail.
      repo.retitle(12000, 'Retitled');
      repo.failure = down;
      repo.changeCatalog();
      await s.sync.pullCatalog();
      await tester.pump(second);
      await tester.pump(kCatalogRefreshWindow);
      await tester.pump(second);
      expect(repo.requests, [null, null]);
      expect(_held(s.container).items[1200].title, 'Track 12000');

      repo.failure = null;
      repo.requests.clear();
      for (var i = 0; i < 12; i++) {
        await tester.pump(second);
      }

      expect(repo.requests, [null, '4990', '9990']);
      expect(_held(s.container).items[1200].title, 'Retitled');

      s.container.dispose();
      await tester.pump();
    });

    testWidgets('each time after twice as long, and no more than five '
        'times', (tester) async {
      final repo = _Library([for (var i = 0; i < 1500; i++) i * 10]);
      final (container, _) = await watched(tester, repo);
      await failOnce(tester, container, repo);
      expect(repo.requests, hasLength(1));

      var wait = kRefreshRetryAfter;
      for (var attempt = 1; attempt <= kRefreshRetries; attempt++) {
        await tester.pump(wait - second);
        expect(repo.requests, hasLength(attempt), reason: 'not before');
        await tester.pump(second);
        expect(repo.requests, hasLength(attempt + 1));
        wait *= 2;
      }
      await tester.pump(const Duration(hours: 1));
      expect(repo.requests, hasLength(kRefreshRetries + 1));
      final state = container.read(listing);
      expect((state.isLoading, state.hasError), (false, false));
      expect(state.requireValue.items, hasLength(3 * _page));

      container.dispose();
      await tester.pump();
    });

    testWidgets('from the first wait again after a refresh that lands', (
      tester,
    ) async {
      final repo = _Library([for (var i = 0; i < 1500; i++) i * 10]);
      final (container, _) = await watched(tester, repo);
      await failOnce(tester, container, repo);
      await tester.pump(kRefreshRetryAfter);
      await tester.pump(kRefreshRetryAfter * 2);
      expect(repo.requests, hasLength(3));

      // The third attempt lands.
      repo.failure = null;
      repo.retitle(30, 'Retitled');
      await tester.pump(kRefreshRetryAfter * 4);
      expect(_held(container).items[3].title, 'Retitled');
      await tester.pump(const Duration(hours: 1));

      repo.requests.clear();
      await failOnce(tester, container, repo);
      expect(repo.requests, hasLength(1));
      await tester.pump(kRefreshRetryAfter);
      expect(repo.requests, hasLength(2));

      container.dispose();
      await tester.pump();
    });

    testWidgets('an invalidation meanwhile takes the timer\'s place, and '
        'no second timer runs beside it', (tester) async {
      final repo = _Library([for (var i = 0; i < 1500; i++) i * 10]);
      final (container, _) = await watched(tester, repo);
      await failOnce(tester, container, repo);
      // A timed attempt, which fails too: the next wait is twice as long.
      await tester.pump(kRefreshRetryAfter);
      expect(repo.requests, hasLength(2));

      // A hint two seconds in: asked at once, and the wait starts over
      // from there, from the first.
      await tester.pump(second * 2);
      container.read(catalogFanOutProvider).sweep(CatalogRefresh.head);
      await tester.pump(tick);
      expect(repo.requests, hasLength(3));
      await tester.pump(kRefreshRetryAfter - second);
      expect(repo.requests, hasLength(3), reason: 'the first timer is gone');
      await tester.pump(second);
      expect(repo.requests, hasLength(4));

      container.dispose();
      await tester.pump();
    });

    testWidgets('only its own timed attempts spend the budget: a trailing '
        'pass that fails after five failed hint passes is asked again', (
      tester,
    ) async {
      final repo = _Library([for (var i = 0; i < 1500; i++) i * 10]);
      final (container, _) = await watched(tester, repo);
      // Five hint passes and the trailing pass, each failing before the
      // timer the one before it set has fired.
      for (var pass = 0; pass < 6; pass++) {
        await failOnce(tester, container, repo);
        await tester.pump(second * 2);
      }
      expect(repo.requests, hasLength(6));

      repo.failure = null;
      repo.retitle(30, 'Retitled');
      await tester.pump(kRefreshRetryAfter);
      expect(repo.requests, hasLength(9), reason: 'the extent, read again');
      expect(_held(container).items[3].title, 'Retitled');

      container.dispose();
      await tester.pump();
    });

    testWidgets('a listing nobody watches is only marked', (tester) async {
      final repo = _Library([for (var i = 0; i < 1500; i++) i * 10]);
      final (container, held) = await watched(tester, repo);
      await failOnce(tester, container, repo);

      // Covered, as under a pushed page.
      held.pause();
      repo.failure = null;
      repo.retitle(30, 'Retitled');
      await tester.pump(const Duration(hours: 1));
      expect(repo.requests, hasLength(1));

      held.resume();
      await tester.pump(tick);
      expect(repo.requests, hasLength(4));
      expect(_held(container).items[3].title, 'Retitled');

      container.dispose();
      await tester.pump();
    });

    testWidgets('nothing is asked once the listing is disposed', (
      tester,
    ) async {
      final repo = _Library([for (var i = 0; i < 1500; i++) i * 10]);
      final (container, _) = await watched(tester, repo);
      await failOnce(tester, container, repo);

      // Ended here, short of the wait: the binding fails a test that
      // leaves a timer running.
      container.dispose();
      repo.failure = null;
      await tester.pump(second);

      expect(repo.requests, hasLength(1));
    });

    testWidgets('the review queue asks again too', (tester) async {
      const page = ReviewQueueController.pageSize;
      final repo = _HeldPages()
        ..reviewEntries = [
          for (var i = 0; i < page + 10; i++) testReviewEntry('rv-$i'),
        ];
      final container = appContainer(repo: repo);
      container.listen(reviewQueueProvider, (_, _) {});
      await tester.pump();
      await container.read(reviewQueueProvider.notifier).loadMore();
      repo.reads.clear();

      // A decision's refresh cannot reach the server.
      repo.reviewError = down;
      container.read(reviewQueueProvider.notifier).owe(CatalogRefresh.loaded);
      container.invalidate(reviewQueueProvider);
      await tester.pump(tick);
      expect(repo.reads, [null]);
      repo.reviewError = null;
      repo.reviewEntries = repo.reviewEntries.skip(1).toList();
      expect(
        container.read(reviewQueueProvider).requireValue.entries.first.id,
        'rv-0',
      );

      await tester.pump(kRefreshRetryAfter - second);
      expect(repo.reads, [null]);
      await tester.pump(second);
      expect(repo.reads, [null, null, '50']);
      final entries = container.read(reviewQueueProvider).requireValue.entries;
      expect(entries.first.id, 'rv-1');
      expect(entries, hasLength(page + 9));

      container.dispose();
      await tester.pump();
    });
  });

  group('a sweep of the reads that are not current', () {
    final listing = musicItemsProvider(_tracks);
    const down = WaxDeckApiException(
      code: 'transport',
      message: 'connection refused',
    );
    const tick = Duration(milliseconds: 1);

    /// The tracks index watched over [repo] under the ledger the app
    /// registers, with what it asked so far forgotten.
    Future<ProviderContainer> watched(
      WidgetTester tester,
      _Library repo,
    ) async {
      final container = appContainer(
        repo: repo,
        observers: [FirstBuildObserver()],
      );
      container.listen(listing, (_, _) {});
      await tester.pump();
      repo.requests.clear();
      return container;
    }

    Future<void> sweep(WidgetTester tester, ProviderContainer container) async {
      container.read(catalogFanOutProvider).sweepUnhealthy();
      await tester.pump(tick);
    }

    Future<void> done(WidgetTester tester, ProviderContainer container) async {
      container.dispose();
      await tester.pump();
    }

    testWidgets('leaves a listing that is current alone', (tester) async {
      final repo = _Library([for (var i = 0; i < 10; i++) i * 10]);
      final container = await watched(tester, repo);
      await sweep(tester, container);
      expect(repo.requests, isEmpty);
      await done(tester, container);
    });

    testWidgets('refreshes a listing whose refresh failed and gave up', (
      tester,
    ) async {
      final repo = _Library([for (var i = 0; i < 10; i++) i * 10]);
      final container = await watched(tester, repo);
      repo.failure = down;
      container.read(listing.notifier).owe(CatalogRefresh.head);
      container.invalidate(listing);
      await tester.pump(const Duration(hours: 1));
      expect(repo.requests, hasLength(kRefreshRetries + 1));

      repo
        ..failure = null
        ..retitle(0, 'Retitled')
        ..requests.clear();
      await sweep(tester, container);
      expect(repo.requests, [null]);
      expect(_held(container).items.first.title, 'Retitled');
      await done(tester, container);
    });

    testWidgets('reads a listing whose refresh failed through the extent it '
        'held, as the quiet edge would have', (tester) async {
      final repo = _Library([for (var i = 0; i < 3 * _page; i++) i * 10]);
      final container = await watched(tester, repo);
      for (var page = 1; page < 3; page++) {
        await container.read(listing.notifier).loadMore();
        await tester.pump(tick);
      }
      // Past the pages a head refresh reads.
      expect(_held(container).items, hasLength(3 * _page));
      repo.failure = down;
      container.read(listing.notifier).owe(CatalogRefresh.head);
      container.invalidate(listing);
      await tester.pump(const Duration(hours: 1));

      repo
        ..failure = null
        ..requests.clear();
      await sweep(tester, container);
      await tester.pump(tick);
      expect(repo.requests, [null, '4990', '9990']);
      await done(tester, container);
    });

    testWidgets('leaves one alone once a refresh after the failure landed', (
      tester,
    ) async {
      final repo = _Library([for (var i = 0; i < 10; i++) i * 10]);
      final container = await watched(tester, repo);
      repo.failure = down;
      container.read(listing.notifier).owe(CatalogRefresh.head);
      container.invalidate(listing);
      await tester.pump(tick);
      repo.failure = null;
      await tester.pump(kRefreshRetryAfter);
      expect(repo.requests, hasLength(2), reason: 'the retry landed');

      repo.requests.clear();
      await sweep(tester, container);
      expect(repo.requests, isEmpty);
      await done(tester, container);
    });

    testWidgets('reads again a listing whose first read failed', (
      tester,
    ) async {
      final repo = _Library([for (var i = 0; i < 10; i++) i * 10])
        ..failure = down;
      final container = appContainer(
        repo: repo,
        observers: [FirstBuildObserver()],
        retry: (_, _) => null,
      );
      container.listen(listing, (_, _) {});
      await tester.pump(tick);
      expect(container.read(listing).hasError, isTrue);

      repo
        ..failure = null
        ..requests.clear();
      await sweep(tester, container);
      await tester.pump(tick);
      expect(repo.requests, [null]);
      expect(container.read(listing).hasValue, isTrue);
      await done(tester, container);
    });
  });

  group('the review pane', () {
    testWidgets('moves on by the queue read after its decision, not by a '
        'page that lands first', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const rows = 2 * ReviewQueueController.pageSize + 10;
      final repo = _HeldPages()
        ..reviewEntries = [
          for (var i = 0; i < rows; i++)
            testReviewEntry('rv-$i', title: 'Album $i'),
        ];
      final container = appContainer(repo: repo);
      await mountApp(tester, const Scaffold(), container: container);
      final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      router.go(WaxRoute.reviewEntry('rv-3'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier(SemanticsIds.reviewPane),
        findsOneWidget,
      );

      // A next page is out, and another reviewer takes the next entry.
      final gate = repo.pageGate = Completer<void>();
      unawaited(container.read(reviewQueueProvider.notifier).loadMore());
      await tester.pump();
      repo.reviewEntries = [
        for (final entry in repo.reviewEntries)
          entry.id == 'rv-4'
              ? testReviewEntry('rv-4', status: 'skipped', title: 'Album 4')
              : entry,
      ];
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewSkip));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(repo.decideReviewCalls.single.entryId, 'rv-3');

      repo.pageGate = null;
      gate.complete();
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        WaxRoute.reviewEntry('rv-5'),
      );
      expect(
        tester.widget<ReviewEntryView>(find.byType(ReviewEntryView)).entryId,
        'rv-5',
      );
    });
  });

  group('refreshed', () {
    final listing = musicItemsProvider(_tracks);
    const down = WaxDeckApiException(
      code: 'transport',
      message: 'connection refused',
    );

    test('waits for the refresh a next page is ahead of', () async {
      final repo = _Library([for (var i = 0; i < 2000; i++) i * 10]);
      final container = await _holdTracks(repo, pages: 2);
      final notifier = container.read(listing.notifier);

      final page = repo.gate = Completer<void>();
      final more = notifier.loadMore();
      repo.retitle(30, 'Retitled');
      notifier.owe(CatalogRefresh.loaded);
      container.invalidate(listing);
      var landed = false;
      final refreshed = container.read(listing.notifier).refreshed()
        ..whenComplete(() => landed = true);

      // The page lands and the state stops loading, on the rows from
      // before the refresh, whose own read is then held.
      final read = Completer<void>();
      repo.onRequest = (cursor) {
        if (cursor == null) repo.gate = read;
      };
      repo.gate = null;
      page.complete();
      await more;
      await pumpEventQueue();
      expect(repo.requests, ['9990', null]);
      final settled = container.read(listing);
      expect(settled.isLoading, isFalse);
      expect(settled.requireValue.items[3].title, 'Track 30');
      expect(landed, isFalse);

      repo.onRequest = null;
      repo.gate = null;
      read.complete();
      final state = await refreshed;

      expect(state!.items[3].title, 'Retitled');
      expect(state.items, hasLength(3 * _page));
    });

    test('waits past a pass that began before it was asked', () async {
      final repo = _Library([for (var i = 0; i < 2000; i++) i * 10]);
      final container = await _holdTracks(repo, pages: 3);
      final notifier = container.read(listing.notifier);

      // A head pass is out when a write here owes the loaded extent.
      final head = repo.gate = Completer<void>();
      container.read(catalogFanOutProvider).sweep(CatalogRefresh.head);
      await container.pump();
      await pumpEventQueue();
      expect(repo.requests, [null]);
      repo.retitle(12000, 'Retitled');
      notifier.owe(CatalogRefresh.loaded);
      container.invalidate(listing);
      var landed = false;
      final refreshed = container.read(listing.notifier).refreshed()
        ..whenComplete(() => landed = true);

      final loaded = Completer<void>();
      repo.onRequest = (cursor) {
        if (cursor == null) repo.gate = loaded;
      };
      repo.gate = null;
      head.complete();
      await container.pump();
      await pumpEventQueue();
      expect(repo.requests, [null, '4990', null]);
      expect(landed, isFalse, reason: 'the head pass is not the one owed');

      repo.onRequest = null;
      repo.gate = null;
      loaded.complete();
      final state = await refreshed;

      expect(state!.items[1200].title, 'Retitled');
    });

    test('answers at once when nothing was asked', () async {
      final repo = _Library([for (var i = 0; i < 2000; i++) i * 10]);
      final container = await _holdTracks(repo, pages: 2);

      final state = await container.read(listing.notifier).refreshed();

      expect(state!.items, hasLength(2 * _page));
      expect(repo.requests, isEmpty);
    });

    test('answers a refresh that fails with the rows kept', () async {
      final repo = _Library([for (var i = 0; i < 2000; i++) i * 10]);
      final container = await _holdTracks(repo, pages: 2);
      final before = _held(container).items;
      final notifier = container.read(listing.notifier);

      repo.failure = down;
      notifier.owe(CatalogRefresh.loaded);
      container.invalidate(listing);
      final state = await container.read(listing.notifier).refreshed();

      expect(repo.requests, [null]);
      expect(state!.items, same(before));
    });

    test('answers a waiter whose listing is then disposed', () async {
      final repo = _Library([for (var i = 0; i < 2000; i++) i * 10]);
      final container = await _holdTracks(repo, pages: 2);
      final notifier = container.read(listing.notifier);

      // The refresh waits behind a next page when the listing goes: the
      // pass waited on is never begun.
      final page = repo.gate = Completer<void>();
      unawaited(notifier.loadMore());
      notifier.owe(CatalogRefresh.loaded);
      container.invalidate(listing);
      final refreshed = container.read(listing.notifier).refreshed();
      await pumpEventQueue();
      container.dispose();
      repo.gate = null;
      page.complete();

      expect(await refreshed.timeout(const Duration(seconds: 2)), isNull);
    });

    for (final turn in [true, false]) {
      test('answers a waiter whose listing is marked and then disposed '
          '${turn ? 'a turn later' : 'at once'}', () async {
        final repo = _Library([for (var i = 0; i < 2000; i++) i * 10]);
        final container = appContainer(repo: repo);
        final held = container.listen(listing, (_, _) {});
        addTearDown(held.close);
        await container.read(listing.future);
        final notifier = container.read(listing.notifier);

        final gate = repo.gate = Completer<void>();
        notifier.owe(CatalogRefresh.loaded);
        container.invalidate(listing);
        final refreshed = container.read(listing.notifier).refreshed();
        await pumpEventQueue();
        expect(repo.requests, [null, null]);

        // Covered, a hint marks it, and it goes before it is read again:
        // the build that would have heard the disposal was ended by the
        // hint.
        held.pause();
        container.read(catalogFanOutProvider).sweep(CatalogRefresh.head);
        if (turn) await pumpEventQueue();
        container.dispose();
        repo.gate = null;
        gate.complete();

        expect(await refreshed.timeout(const Duration(seconds: 2)), isNull);
      });
    }

    test('answers a waiter whose pass a letter seek overtakes', () async {
      const key = (
        dimension: MusicDimension.artists,
        sort: FacetSort.label,
        domain: BrowseDomain.music,
      );
      FacetBucket artist(String name) =>
          FacetBucket(key: name, label: name, count: 1);
      final repo = _HeldFacets()
        ..facets['artist'] = [
          for (var i = 0; i < 600; i++)
            artist('Able ${i.toString().padLeft(3, '0')}'),
          for (var i = 0; i < 40; i++)
            artist('Mole ${i.toString().padLeft(3, '0')}'),
        ];
      final container = appContainer(repo: repo);
      final held = container.listen(musicIndexProvider(key), (_, _) {});
      addTearDown(held.close);
      await container.read(musicIndexProvider(key).future);
      final notifier = container.read(musicIndexProvider(key).notifier);

      final head = repo.headGate = Completer<void>();
      container.read(catalogFanOutProvider).sweep(CatalogRefresh.loaded);
      final refreshed = container
          .read(musicIndexProvider(key).notifier)
          .refreshed();
      await pumpEventQueue();
      final letter = repo.letterGate = Completer<void>();
      final seek = notifier.anchorAt('m');
      await pumpEventQueue();

      // The read the seek overtook lands first, and is dropped: no pass
      // follows it, the seek having read the listing whole.
      repo.headGate = null;
      head.complete();
      await pumpEventQueue();
      repo.letterGate = null;
      letter.complete();
      expect(await seek, isTrue);

      final state = await refreshed.timeout(const Duration(seconds: 2));
      expect(state!.anchoredAt, 'm');
      expect(state.buckets.first.label, 'Mole 000');
    });

    test('answers a waiter whose pass ends on a defect', () async {
      final repo = _Library([for (var i = 0; i < 2000; i++) i * 10]);
      final container = appContainer(repo: repo);
      final held = container.listen(listing, (_, _) {}, onError: (_, _) {});
      addTearDown(held.close);
      await container.read(listing.future);
      final notifier = container.read(listing.notifier);

      repo.defect = StateError('a page that cannot be read');
      notifier.owe(CatalogRefresh.loaded);
      container.invalidate(listing);
      final refreshed = container.read(listing.notifier).refreshed();

      final state = await refreshed.timeout(const Duration(seconds: 2));
      expect(state!.items, hasLength(_page));
      // Nor does a later caller wait on the pass that threw.
      repo.defect = null;
      final later = notifier.refreshed();
      expect(await later.timeout(const Duration(seconds: 2)), isNotNull);
    });

    test('answers a listing started over with its head', () async {
      const key = (
        dimension: MusicDimension.artists,
        sort: FacetSort.label,
        domain: BrowseDomain.music,
      );
      final repo = FakeRepository()
        ..facets['artist'] = [
          for (var i = 0; i < 1300; i++)
            FacetBucket(key: 'k$i', label: 'Artist $i', count: 1),
        ];
      final container = appContainer(repo: repo);
      final held = container.listen(musicIndexProvider(key), (_, _) {});
      addTearDown(held.close);
      await container.read(musicIndexProvider(key).future);
      final notifier = container.read(musicIndexProvider(key).notifier);
      await notifier.loadMore();

      // The pass it waits on is overtaken: the read that replaces the
      // listing answers.
      final gate = repo.facetGate = Completer<void>();
      container.read(catalogFanOutProvider).sweep(CatalogRefresh.loaded);
      final refreshed = container
          .read(musicIndexProvider(key).notifier)
          .refreshed();
      await pumpEventQueue();
      notifier.reset();
      await container.pump();
      repo.facetGate = null;
      gate.complete();

      expect((await refreshed)!.buckets, hasLength(500));
    });
  });

  test(
    'a walk of any row keeps what it read when a later page fails',
    () async {
      final walk = await walkRows<int>(
        (cursor) async {
          if (cursor != null) {
            throw const WaxDeckApiException(
              code: 'transport',
              message: 'connection refused',
            );
          }
          return (rows: [1, 2], nextCursor: 'c1');
        },
        want: 5,
        keepOnFailure: true,
      );

      expect(walk.rows, [1, 2]);
      expect(walk.nextCursor, 'c1');
    },
  );

  test('a walk that wants nothing is refused, whatever it reads', () {
    expect(
      walkRows<int>((_) async => (rows: <int>[1], nextCursor: null), want: 0),
      throwsAssertionError,
    );
  });
}
