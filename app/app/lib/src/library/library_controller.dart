import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import '../providers.dart';
import '../sync/sync_providers.dart';

/// Media-type filter shown above the grid.
enum LibraryFilter {
  all(null, 'All'),
  music(MediaType.music, 'Music'),
  podcasts(MediaType.podcast, 'Podcasts'),
  audiobooks(MediaType.audiobook, 'Audiobooks');

  const LibraryFilter(this.mediaType, this.label);

  /// Server-side filter, null for the whole library.
  final MediaType? mediaType;

  final String label;
}

class LibraryFilterController extends Notifier<LibraryFilter> {
  @override
  LibraryFilter build() => LibraryFilter.all;

  void select(LibraryFilter filter) => state = filter;
}

final libraryFilterProvider =
    NotifierProvider<LibraryFilterController, LibraryFilter>(
      LibraryFilterController.new,
    );

/// Accumulated pages of the library listing.
class LibraryState {
  const LibraryState({
    required this.items,
    this.nextCursor,
    this.loadingMore = false,
  });

  final List<ItemSummary> items;
  final String? nextCursor;
  final bool loadingMore;

  bool get hasMore => nextCursor != null;

  LibraryState copyWith({bool? loadingMore}) => LibraryState(
    items: items,
    nextCursor: nextCursor,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// Pages the library with keyset cursors. Changing the filter re-runs
/// [build], which starts over from the first page.
class LibraryController extends AsyncNotifier<LibraryState> {
  static const pageSize = 60;

  /// Bumped by every [build] so an in-flight [loadMore] can tell its
  /// listing was replaced (filter change, refresh) and drop its result
  /// instead of overwriting the new listing with the old one's items.
  var _generation = 0;

  @override
  Future<LibraryState> build() async {
    _generation++;
    final filter = ref.watch(libraryFilterProvider);
    // Offline, the local mirror serves the listing (native builds with
    // a started engine only; everything else stays server-backed).
    if (ref.watch(offlineProvider)) {
      final page = await mirrorItemsPage(
        ref.read(mirrorDatabaseProvider)!,
        mediaType: filter.mediaType,
        limit: pageSize,
      );
      return LibraryState(items: page.items, nextCursor: page.nextCursor);
    }
    final page = await ref
        .watch(repositoryProvider)
        .listItems(mediaType: filter.mediaType, limit: pageSize);
    return LibraryState(items: page.items, nextCursor: page.nextCursor);
  }

  /// Fetches the next page and appends it. No-op while a fetch is running
  /// or once the last page was reached.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final generation = _generation;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final cursor = current.nextCursor;
      final ItemPage page;
      if (cursor != null && isMirrorCursor(cursor)) {
        page = await mirrorItemsPage(
          ref.read(mirrorDatabaseProvider)!,
          mediaType: ref.read(libraryFilterProvider).mediaType,
          cursor: cursor,
          limit: pageSize,
        );
      } else {
        page = await ref
            .read(repositoryProvider)
            .listItems(
              mediaType: ref.read(libraryFilterProvider).mediaType,
              cursor: cursor,
              limit: pageSize,
            );
      }
      if (generation != _generation) return;
      state = AsyncData(
        LibraryState(
          items: [...current.items, ...page.items],
          nextCursor: page.nextCursor,
        ),
      );
    } on WaxDeckApiException {
      // An expected transport or server error. Keep what we have;
      // scrolling near the end again retries.
      if (generation != _generation) return;
      // Keep what we have; scrolling near the end again retries.
      state = AsyncData(current.copyWith(loadingMore: false));
    } catch (_) {
      // Anything else is a defect, not a hiccup: a decode failure,
      // a bad cast. Release the paging guard first — loadingMore is
      // what keeps two fetches from racing, so leaving it set would
      // wedge paging permanently and silently — then let the error
      // reach the zone's handler instead of vanishing here.
      if (generation == _generation) {
        state = AsyncData(current.copyWith(loadingMore: false));
      }
      rethrow;
    }
  }
}

final libraryControllerProvider =
    AsyncNotifierProvider<LibraryController, LibraryState>(
      LibraryController.new,
    );

/// The most recently played item, for the continue-listening banner.
/// Server-driven on purpose: killing and reopening the app resumes purely
/// from server state.
final continueListeningProvider = FutureProvider<ItemSummary?>((ref) async {
  final page = await ref
      .watch(repositoryProvider)
      .browse(DiscoveryList.recentlyPlayed, limit: 1);
  return page.items.isEmpty ? null : page.items.first;
});
