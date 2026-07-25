import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/library/library_controller.dart';
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

void main() {
  test('a filter change during loadMore is not overwritten', () async {
    final repo = GatedRepository(
      items: [
        for (var i = 0; i < 70; i++) testItem('tr-music-$i'),
        for (var i = 0; i < 65; i++)
          testItem('ep-pod-$i', mediaType: MediaType.podcast),
      ],
    );
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final keepAlive = container.listen(libraryControllerProvider, (_, _) {});
    addTearDown(keepAlive.close);

    final first = await container.read(libraryControllerProvider.future);
    expect(first.items, hasLength(LibraryController.pageSize));
    expect(first.hasMore, isTrue);

    // Start paging, then switch the filter while the fetch is in flight.
    repo.gate = Completer<void>();
    final loadMore = container
        .read(libraryControllerProvider.notifier)
        .loadMore();
    container
        .read(libraryFilterProvider.notifier)
        .select(LibraryFilter.podcasts);
    final rebuilt = await container.read(libraryControllerProvider.future);
    expect(rebuilt.items.first.mediaType, MediaType.podcast);

    // The stale page must be dropped, not appended over the new listing.
    repo.gate!.complete();
    await loadMore;
    final after = container.read(libraryControllerProvider).requireValue;
    expect(after.items, hasLength(LibraryController.pageSize));
    expect(
      after.items.every((i) => i.mediaType == MediaType.podcast),
      isTrue,
      reason: 'stale music page overwrote the podcast listing',
    );
  });

  test('a non-API failure mid-page does not wedge paging', () async {
    // loadingMore is the guard that keeps two fetches from racing, and
    // the repository only converts transport errors into
    // WaxDeckApiException: anything else (a socket error, a decode
    // failure) reaches the controller as itself. Escaping with the guard
    // still set would block every later page silently and permanently,
    // since the listing keeps its items and loadMore early-returns.
    final repo = GatedRepository(
      items: [for (var i = 0; i < 130; i++) testItem('tr-music-$i')],
    );
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final keepAlive = container.listen(libraryControllerProvider, (_, _) {});
    addTearDown(keepAlive.close);

    final first = await container.read(libraryControllerProvider.future);
    expect(first.items, hasLength(LibraryController.pageSize));
    expect(first.hasMore, isTrue);

    repo.failNextPage = StateError('deserialization failed');
    await expectLater(
      container.read(libraryControllerProvider.notifier).loadMore(),
      throwsA(isA<StateError>()),
      reason: 'a defect must still reach the zone, not vanish in the catch',
    );
    final afterFailure = container.read(libraryControllerProvider).requireValue;
    expect(afterFailure.items, hasLength(LibraryController.pageSize));
    expect(
      afterFailure.loadingMore,
      isFalse,
      reason: 'a failed page must release the paging guard',
    );

    // Scrolling again retries and appends the page that failed.
    await container.read(libraryControllerProvider.notifier).loadMore();
    expect(
      container.read(libraryControllerProvider).requireValue.items,
      hasLength(LibraryController.pageSize * 2),
    );
  });
}
