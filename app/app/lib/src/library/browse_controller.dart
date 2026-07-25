import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';

/// A browse dimension: the wire name the server enumerates and filters
/// by, with the labels the tabs and drill screens show.
enum BrowseDimension {
  genre('genre', 'Genres', 'genre'),
  artist('artist', 'Artists', 'artist'),
  albumArtist('album-artist', 'Album artists', 'album artist'),
  album('album', 'Albums', 'album'),
  year('year', 'Years', 'year'),
  kind('kind', 'Kinds', 'kind');

  const BrowseDimension(this.wireName, this.label, this.singular);

  /// The `dimension` the server enumerates and the `facet` a listing
  /// filters by. The two are the same string by contract.
  final String wireName;

  /// Tab label.
  final String label;

  /// Used in a drill screen's empty state ("no items in this genre").
  final String singular;
}

/// Accumulated pages of one dimension's buckets.
class BrowseState {
  const BrowseState({
    required this.buckets,
    this.nextCursor,
    this.loadingMore = false,
  });

  final List<FacetBucket> buckets;
  final String? nextCursor;
  final bool loadingMore;

  bool get hasMore => nextCursor != null;

  BrowseState copyWith({bool? loadingMore}) => BrowseState(
    buckets: buckets,
    nextCursor: nextCursor,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// Pages one browse dimension's buckets. One instance per dimension, so
/// switching tabs keeps each tab's accumulated pages.
class BrowseController extends AsyncNotifier<BrowseState> {
  BrowseController(this.dimension);

  final BrowseDimension dimension;
  static const pageSize = 100;

  /// Bumped by every [build] so an in-flight [loadMore] can tell its
  /// listing was replaced and drop its result rather than appending to
  /// a list that no longer exists.
  var _generation = 0;

  @override
  Future<BrowseState> build() async {
    _generation++;
    final page = await ref
        .watch(repositoryProvider)
        .listFacets(dimension.wireName, limit: pageSize);
    return BrowseState(buckets: page.buckets, nextCursor: page.nextCursor);
  }

  /// Fetches the next page and appends it. No-op while a fetch is
  /// running or once the last page was reached.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final generation = _generation;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref
          .read(repositoryProvider)
          .listFacets(
            dimension.wireName,
            cursor: current.nextCursor,
            limit: pageSize,
          );
      if (generation != _generation) return;
      state = AsyncData(
        BrowseState(
          buckets: [...current.buckets, ...page.buckets],
          nextCursor: page.nextCursor,
        ),
      );
    } on WaxDeckApiException {
      // An expected transport or server error. Keep what we have;
      // scrolling near the end again retries.
      if (generation != _generation) return;
      state = AsyncData(current.copyWith(loadingMore: false));
    } catch (_) {
      // Anything else is a defect, not a hiccup: a decode failure, a bad
      // cast. Release the paging guard first — loadingMore is what keeps
      // two fetches from racing, so leaving it set would wedge paging
      // permanently and silently — then let the error reach the zone's
      // handler instead of vanishing here.
      if (generation == _generation) {
        state = AsyncData(current.copyWith(loadingMore: false));
      }
      rethrow;
    }
  }
}

final browseControllerProvider =
    AsyncNotifierProvider.family<
      BrowseController,
      BrowseState,
      BrowseDimension
    >(BrowseController.new);

/// One bucket being drilled: which dimension and which bucket key. The
/// key is legitimately empty (a dimension's unknown bucket), so the pair
/// travels together rather than the key standing alone.
typedef BrowseDrill = ({BrowseDimension dimension, String key});

/// Accumulated pages of a drilled bucket's items.
class BrowseItemsState {
  const BrowseItemsState({
    required this.items,
    this.nextCursor,
    this.loadingMore = false,
  });

  final List<ItemSummary> items;
  final String? nextCursor;
  final bool loadingMore;

  bool get hasMore => nextCursor != null;

  BrowseItemsState copyWith({bool? loadingMore}) => BrowseItemsState(
    items: items,
    nextCursor: nextCursor,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// Pages the items in one bucket of one dimension.
class BrowseItemsController extends AsyncNotifier<BrowseItemsState> {
  BrowseItemsController(this.drill);

  final BrowseDrill drill;
  static const pageSize = 60;

  var _generation = 0;

  @override
  Future<BrowseItemsState> build() async {
    _generation++;
    final page = await ref
        .watch(repositoryProvider)
        .listItems(
          facet: drill.dimension.wireName,
          facetKey: drill.key,
          limit: pageSize,
        );
    return BrowseItemsState(items: page.items, nextCursor: page.nextCursor);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final generation = _generation;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref
          .read(repositoryProvider)
          .listItems(
            facet: drill.dimension.wireName,
            facetKey: drill.key,
            cursor: current.nextCursor,
            limit: pageSize,
          );
      if (generation != _generation) return;
      state = AsyncData(
        BrowseItemsState(
          items: [...current.items, ...page.items],
          nextCursor: page.nextCursor,
        ),
      );
    } on WaxDeckApiException {
      if (generation != _generation) return;
      state = AsyncData(current.copyWith(loadingMore: false));
    } catch (_) {
      // Same split as BrowseController.loadMore: release the guard for
      // every failure, surface the ones that are defects.
      if (generation == _generation) {
        state = AsyncData(current.copyWith(loadingMore: false));
      }
      rethrow;
    }
  }
}

/// Auto-disposed, unlike the per-dimension provider above: a dimension
/// is one of six, but a bucket is any artist, album, genre, or year in
/// the library. Keeping each drilled bucket's accumulated pages alive
/// for the app's lifetime would grow without bound as someone browsed,
/// and would serve the stale page set when they reopened a bucket.
final browseItemsControllerProvider = AsyncNotifierProvider.autoDispose
    .family<BrowseItemsController, BrowseItemsState, BrowseDrill>(
      BrowseItemsController.new,
    );
