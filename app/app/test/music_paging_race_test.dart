import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

/// Blocks paging fetches (cursor calls) on [gate]; first-page builds pass
/// through untouched.
class GatedRepository extends FakeRepository {
  GatedRepository({super.items});

  Completer<void>? gate;

  /// Thrown by the next paging fetch, once.
  Object? failNextPage;

  @override
  Future<ItemPage> listItems({
    MediaType? mediaType,
    String? facet,
    String? facetKey,
    String? cursor,
    int? limit,
  }) async {
    final g = gate;
    if (g != null && cursor != null) await g.future;
    final failure = failNextPage;
    if (failure != null && cursor != null) {
      failNextPage = null;
      throw failure;
    }
    return super.listItems(
      mediaType: mediaType,
      facet: facet,
      facetKey: facetKey,
      cursor: cursor,
      limit: limit,
    );
  }
}

/// The tracks index: the listing with no bucket, which is the one that
/// pages the whole library and the surface the deleted library grid's
/// paging behaviour moved onto.
const MusicListing _tracks = (dimension: null, segment: '');

/// One page and a bit, so there is a second page to race against.
final _library = <ItemSummary>[
  for (var i = 0; i < MusicItemsController.pageSize + 20; i++)
    testItem('tr-music-$i'),
];

void main() {
  test('a rebuild during loadMore is not overwritten', () async {
    final repo = GatedRepository(items: _library);
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final keepAlive = container.listen(musicItemsProvider(_tracks), (_, _) {});
    addTearDown(keepAlive.close);

    final first = await container.read(musicItemsProvider(_tracks).future);
    expect(first.items, hasLength(MusicItemsController.pageSize));
    expect(first.hasMore, isTrue);

    // Start paging, then restart the listing while the fetch is in
    // flight, which is what a catalog invalidation does to an index that
    // is loading its second page.
    repo.gate = Completer<void>();
    final loadMore = container
        .read(musicItemsProvider(_tracks).notifier)
        .loadMore();
    container.invalidate(musicItemsProvider(_tracks));
    final rebuilt = await container.read(musicItemsProvider(_tracks).future);
    expect(rebuilt.items, hasLength(MusicItemsController.pageSize));

    // The stale page must be dropped, not appended over the new listing.
    repo.gate!.complete();
    await loadMore;
    final after = container.read(musicItemsProvider(_tracks)).requireValue;
    expect(
      after.items,
      hasLength(MusicItemsController.pageSize),
      reason: 'a stale page was appended to a listing that had restarted',
    );
  });

  test('a non-API failure mid-page does not wedge paging', () async {
    // loadingMore is the guard that keeps two fetches from racing, and
    // the repository only converts transport errors into
    // WaxDeckApiException: anything else (a socket error, a decode
    // failure) reaches the controller as itself. Escaping with the guard
    // still set would block every later page silently and permanently,
    // since the listing keeps its items and loadMore early-returns.
    final repo = GatedRepository(items: _library);
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final keepAlive = container.listen(musicItemsProvider(_tracks), (_, _) {});
    addTearDown(keepAlive.close);

    final first = await container.read(musicItemsProvider(_tracks).future);
    expect(first.items, hasLength(MusicItemsController.pageSize));
    expect(first.hasMore, isTrue);

    repo.failNextPage = StateError('deserialization failed');
    await expectLater(
      container.read(musicItemsProvider(_tracks).notifier).loadMore(),
      throwsA(isA<StateError>()),
      reason: 'a defect must still reach the zone, not vanish in the catch',
    );
    final afterFailure = container
        .read(musicItemsProvider(_tracks))
        .requireValue;
    expect(afterFailure.items, hasLength(MusicItemsController.pageSize));
    expect(
      afterFailure.loadingMore,
      isFalse,
      reason: 'a failed page must release the paging guard',
    );

    // Scrolling again retries and appends the page that failed.
    await container.read(musicItemsProvider(_tracks).notifier).loadMore();
    expect(
      container.read(musicItemsProvider(_tracks)).requireValue.items,
      hasLength(_library.length),
    );
  });
}
