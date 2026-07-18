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

  @override
  Future<ItemPage> listItems({
    MediaType? mediaType,
    String? cursor,
    int? limit,
  }) async {
    final g = gate;
    if (g != null && cursor != null) await g.future;
    return super.listItems(mediaType: mediaType, cursor: cursor, limit: limit);
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
}
