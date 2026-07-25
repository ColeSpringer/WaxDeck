import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/library/browse_controller.dart';
import 'package:waxdeck/src/library/browse_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';
import 'routed_host.dart';

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: routedHost(const BrowseScreen()),
);

/// Serves one bucket per page (so paging happens at all under the
/// controller's real page size) and fails one paging fetch with a
/// non-API error, the class the controller's catch has to survive.
class _PagingFailureRepository extends FakeRepository {
  Object? failNextPage;

  @override
  Future<FacetPage> listFacets(
    String dimension, {
    String? cursor,
    int? limit,
  }) async {
    final failure = failNextPage;
    if (failure != null && cursor != null) {
      failNextPage = null;
      throw failure;
    }
    return super.listFacets(dimension, cursor: cursor, limit: 1);
  }
}

FakeRepository _repo() {
  final repo = FakeRepository();
  repo.facets['genre'] = const [
    FacetBucket(key: 'ge-1', label: 'Hip Hop', count: 3),
    FacetBucket(key: 'ge-2', label: 'Jazz', count: 1),
    FacetBucket(key: '', label: '[No Genre]', count: 2, unknown: true),
  ];
  repo.facets['artist'] = const [
    FacetBucket(
      key: '01ARTIST',
      label: 'Vocabulary Test',
      count: 4,
      entityPid: 'ar-01ARTIST',
    ),
  ];
  repo.facetItems['genre ge-1'] = [
    testItem('tr-hh-1', title: 'Lowercase'),
    testItem('tr-hh-2', title: 'Synonym'),
    testItem('tr-hh-3', title: 'Run Together'),
  ];
  repo.facetItems['genre '] = [testItem('tr-none-1', title: 'Untagged')];
  return repo;
}

void main() {
  testWidgets('lists a dimension\'s buckets with their counts', (tester) async {
    await tester.pumpWidget(_host(_repo()));
    await tester.pumpAndSettle();

    expect(find.text('Hip Hop'), findsOneWidget);
    expect(find.text('Jazz'), findsOneWidget);
    expect(find.text('[No Genre]'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('a bucket opens the items in it', (tester) async {
    final repo = _repo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('browse-genre-0')));
    await tester.pumpAndSettle();

    expect(repo.facetDrills, contains(('genre', 'ge-1')));
    expect(find.text('Lowercase'), findsOneWidget);
    expect(find.text('Run Together'), findsOneWidget);
  });

  testWidgets('the unknown bucket drills on its empty key', (tester) async {
    final repo = _repo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    // The unknown bucket's key is empty by contract, so the drill has to
    // send the pair rather than treating the missing key as "no filter".
    await tester.tap(find.byKey(const Key('browse-genre-2')));
    await tester.pumpAndSettle();

    expect(repo.facetDrills, contains(('genre', '')));
    expect(find.text('Untagged'), findsOneWidget);
  });

  testWidgets('switching tabs enumerates the other dimension', (tester) async {
    await tester.pumpWidget(_host(_repo()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('browse-tab-artist')));
    await tester.pumpAndSettle();

    expect(find.text('Vocabulary Test'), findsOneWidget);
  });

  testWidgets('an empty dimension shows its empty state', (tester) async {
    await tester.pumpWidget(_host(_repo()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('browse-tab-year')));
    await tester.pumpAndSettle();

    expect(find.text('No years yet'), findsOneWidget);
  });

  test('a non-API failure mid-page does not wedge paging', () async {
    // loadingMore is the guard that keeps two fetches from racing, so a
    // failure that escaped with it still set would block every later
    // load silently and permanently. The repository only converts
    // transport errors into WaxDeckApiException, so anything else (a
    // socket error, a decode failure) reaches the controller as itself.
    final repo = _PagingFailureRepository();
    repo.facets['genre'] = [
      for (var i = 0; i < 3; i++)
        FacetBucket(key: 'ge-$i', label: 'Genre $i', count: 1),
    ];
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final provider = browseControllerProvider(BrowseDimension.genre);
    final keepAlive = container.listen(provider, (_, _) {});
    addTearDown(keepAlive.close);

    final first = await container.read(provider.future);
    expect(first.buckets, hasLength(1));
    expect(first.hasMore, isTrue);

    repo.failNextPage = const SocketException('connection reset');
    await expectLater(
      container.read(provider.notifier).loadMore(),
      throwsA(isA<SocketException>()),
      reason: 'a defect must still reach the zone, not vanish in the catch',
    );
    final afterFailure = container.read(provider).value!;
    expect(afterFailure.buckets, hasLength(1), reason: 'kept what we had');
    expect(
      afterFailure.loadingMore,
      isFalse,
      reason: 'a failed page must release the paging guard',
    );

    // Scrolling again retries and succeeds.
    await container.read(provider.notifier).loadMore();
    expect(container.read(provider).value!.buckets, hasLength(2));
  });

  testWidgets('a failing enumeration offers a retry', (tester) async {
    final repo = _repo();
    repo.listError = const WaxDeckApiException(
      statusCode: 503,
      code: 'catalog-maintenance',
      message: 'the catalog is busy',
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(find.text('the catalog is busy'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
