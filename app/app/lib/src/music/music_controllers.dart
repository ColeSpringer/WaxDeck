import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../providers.dart';
import '../queue/queue_state.dart';

/// A dimension the music hub offers an index of.
///
/// The server enumerates more of them (`album-artist`, `kind`, custom
/// tags) and the endpoint still serves every one; these are the four the
/// route map names, which is what a hub can offer without becoming a
/// list of lists.
enum MusicDimension {
  artists(
    segment: 'artists',
    wireName: 'artist',
    label: 'Artists',
    singular: 'artist',
    glyph: WaxIcons.artists,
    entityPrefix: 'ar-',
    shape: ArtworkShape.circle,
  ),
  albums(
    segment: 'albums',
    wireName: 'album',
    label: 'Albums',
    singular: 'album',
    glyph: WaxIcons.albums,
    entityPrefix: 'al-',
  ),
  genres(
    segment: 'genres',
    wireName: 'genre',
    label: 'Genres',
    singular: 'genre',
    glyph: WaxIcons.filter,
  ),
  years(
    segment: 'years',
    wireName: 'year',
    label: 'Years',
    singular: 'year',
    glyph: WaxIcons.recent,
  );

  const MusicDimension({
    required this.segment,
    required this.wireName,
    required this.label,
    required this.singular,
    required this.glyph,
    this.entityPrefix,
    this.shape = ArtworkShape.square,
  });

  /// The path segment under `/music`. Plural, because it names a list.
  final String segment;

  /// The `dimension` the server enumerates and the `facet` a listing
  /// filters by. The two are the same string by contract.
  final String wireName;

  final String label;

  /// For a drilled bucket's empty state ("nothing in this genre").
  final String singular;

  final WaxGlyph glyph;

  /// The API type prefix a bucket's `entityPid` carries, for the
  /// dimensions whose buckets are catalog entities. The contract spells
  /// out that the pid is the bucket key with this in front, which is what
  /// lets one location carry both: the URL names the entity, the drill
  /// sends the key.
  final String? entityPrefix;

  /// How this dimension's buckets are drawn. Artists are discs, which is
  /// the shape signal the design language uses for a person.
  final ArtworkShape shape;

  /// The dimensions whose buckets have artwork worth fetching.
  bool get hasArtwork => entityPrefix != null;

  static MusicDimension? bySegment(String segment) =>
      MusicDimension.values.where((d) => d.segment == segment).firstOrNull;
}

/// The URL segment the unknown bucket takes.
///
/// Its key is legitimately empty — it is the bucket for items a dimension
/// is absent from — and an empty path segment is not a location. No real
/// key collides: entity keys are ULIDs behind a type prefix, year keys
/// are digits, and a genre key is a ULID.
const musicUnknownSegment = 'unknown';

/// The handle a bucket travels under in a location, and the `facetKey`
/// that handle drills with.
///
/// Entity dimensions put the prefixed pid in the URL, because that is
/// what the entity endpoints take and what the detail screens will be
/// addressed by; everything else carries the key as it stands.
String musicBucketSegment(MusicDimension dimension, FacetBucket bucket) {
  if (bucket.unknown || bucket.key.isEmpty) return musicUnknownSegment;
  final entityPid = bucket.entityPid;
  return dimension.hasArtwork && entityPid != null && entityPid.isNotEmpty
      ? entityPid
      : bucket.key;
}

/// The reverse: the `facetKey` a location's segment drills with.
String musicFacetKey(MusicDimension dimension, String segment) {
  if (segment == musicUnknownSegment) return '';
  final prefix = dimension.entityPrefix;
  return prefix != null && segment.startsWith(prefix)
      ? segment.substring(prefix.length)
      : segment;
}

/// Which index a caller is looking at, and in which order.
typedef MusicIndexKey = ({MusicDimension dimension, FacetSort sort});

/// Accumulated pages of one dimension's buckets.
class MusicIndexState {
  const MusicIndexState({
    required this.buckets,
    this.nextCursor,
    this.loadingMore = false,
  });

  final List<FacetBucket> buckets;
  final String? nextCursor;
  final bool loadingMore;

  bool get hasMore => nextCursor != null;

  MusicIndexState copyWith({bool? loadingMore}) => MusicIndexState(
    buckets: buckets,
    nextCursor: nextCursor,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// Pages one index's buckets. One instance per (dimension, order): the
/// two orders are two listings with two cursor spaces, and the server
/// refuses a cursor carried across them.
class MusicIndexController extends AsyncNotifier<MusicIndexState> {
  MusicIndexController(this.key);

  final MusicIndexKey key;

  /// The A-to-Z index is what the alphabet rail scrolls, and a jump to a
  /// letter pages forward until it finds one. Big pages are what keep
  /// that from being a dozen round trips; the server computes the whole
  /// enumeration either way and serves it from one cache.
  static const pageSize = 500;

  /// Bumped by every [build] so an in-flight [loadMore] can tell its
  /// listing was replaced and drop its result rather than appending to a
  /// list that no longer exists.
  var _generation = 0;

  @override
  Future<MusicIndexState> build() async {
    _generation++;
    final page = await ref
        .watch(repositoryProvider)
        .listFacets(key.dimension.wireName, sort: key.sort, limit: pageSize);
    return MusicIndexState(buckets: page.buckets, nextCursor: page.nextCursor);
  }

  /// Fetches the next page and appends it. Answers whether anything was
  /// added, so a caller paging toward a letter knows when to stop.
  Future<bool> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) {
      return false;
    }
    final generation = _generation;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref
          .read(repositoryProvider)
          .listFacets(
            key.dimension.wireName,
            sort: key.sort,
            cursor: current.nextCursor,
            limit: pageSize,
          );
      if (generation != _generation) return false;
      state = AsyncData(
        MusicIndexState(
          buckets: <FacetBucket>[...current.buckets, ...page.buckets],
          nextCursor: page.nextCursor,
        ),
      );
      return page.buckets.isNotEmpty;
    } on WaxDeckApiException {
      // An expected transport or server error. Keep what we have;
      // scrolling near the end again retries.
      if (generation == _generation) {
        state = AsyncData(current.copyWith(loadingMore: false));
      }
      return false;
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

final musicIndexProvider =
    AsyncNotifierProvider.family<
      MusicIndexController,
      MusicIndexState,
      MusicIndexKey
    >(MusicIndexController.new);

/// Which order an index is showing. Per dimension, because the choice is
/// about the list in front of you.
///
/// A-to-Z leads where an alphabet is how anyone looks for a thing:
/// artists, albums. Genres and years lead biggest-first, because an
/// alphabet of years is the years again, and the genre with two tracks in
/// it is not where a visitor starts. Either way the toggle is there.
class MusicIndexSort extends Notifier<FacetSort> {
  MusicIndexSort(this.dimension);

  final MusicDimension dimension;

  @override
  FacetSort build() => switch (dimension) {
    MusicDimension.artists || MusicDimension.albums => FacetSort.label,
    MusicDimension.genres || MusicDimension.years => FacetSort.count,
  };

  void select(FacetSort sort) => state = sort;
}

final musicIndexSortProvider =
    NotifierProvider.family<MusicIndexSort, FacetSort, MusicDimension>(
      MusicIndexSort.new,
    );

/// One drilled listing: a dimension bucket, or the whole tracks index
/// when [dimension] is null.
typedef MusicListing = ({MusicDimension? dimension, String segment});

/// Accumulated pages of a listing's items.
class MusicItemsState {
  const MusicItemsState({
    required this.items,
    this.nextCursor,
    this.loadingMore = false,
  });

  final List<ItemSummary> items;
  final String? nextCursor;
  final bool loadingMore;

  bool get hasMore => nextCursor != null;

  MusicItemsState copyWith({bool? loadingMore}) => MusicItemsState(
    items: items,
    nextCursor: nextCursor,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// Pages the items of one bucket, or of the whole music library.
class MusicItemsController extends AsyncNotifier<MusicItemsState> {
  MusicItemsController(this.listing);

  final MusicListing listing;

  /// The queue cap, deliberately.
  ///
  /// Playing a row plays the bucket from there, and what the screen hands
  /// over is what it has loaded — so a page smaller than the cap would
  /// queue a prefix of an artist and call it the artist. At the cap, any
  /// bucket the queue could hold whole is loaded whole before the first
  /// row can be tapped, and a bucket bigger than that is windowed by the
  /// queue itself from the row that was chosen, which is the same answer
  /// a smaller page could not give. It costs a larger first page on a
  /// long list, which is what the index pages at for the same reason.
  static const pageSize = kQueueCap;

  var _generation = 0;

  Future<ItemPage> _page(String? cursor) {
    final dimension = listing.dimension;
    return ref
        .read(repositoryProvider)
        .listItems(
          // A bucket is drilled exactly as its count was computed, with
          // no media type on top. The music dimensions already leave
          // podcast episodes out server-side, and they take in whatever
          // else carries an artist or a year — an audiobook has both — so
          // narrowing to music here would open a bucket of two to an
          // empty list. A count that disagrees with the list it opens is
          // the one thing faceted browse cannot do.
          //
          // The tracks index is the other case and does filter: it is
          // "every track", not a bucket of anything.
          mediaType: dimension == null ? MediaType.music : null,
          facet: dimension?.wireName,
          facetKey: dimension == null
              ? null
              : musicFacetKey(dimension, listing.segment),
          cursor: cursor,
          limit: pageSize,
        );
  }

  @override
  Future<MusicItemsState> build() async {
    _generation++;
    // Watched rather than read so a sign-in swap rebuilds the listing.
    ref.watch(repositoryProvider);
    final page = await _page(null);
    return MusicItemsState(items: page.items, nextCursor: page.nextCursor);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final generation = _generation;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await _page(current.nextCursor);
      if (generation != _generation) return;
      state = AsyncData(
        MusicItemsState(
          items: <ItemSummary>[...current.items, ...page.items],
          nextCursor: page.nextCursor,
        ),
      );
    } on WaxDeckApiException {
      if (generation != _generation) return;
      state = AsyncData(current.copyWith(loadingMore: false));
    } catch (_) {
      // Same split as the index controller: release the guard for every
      // failure, surface the ones that are defects.
      if (generation == _generation) {
        state = AsyncData(current.copyWith(loadingMore: false));
      }
      rethrow;
    }
  }
}

/// Auto-disposed, unlike the index providers: a dimension is one of four,
/// but a bucket is any artist, album, genre, or year in the library.
/// Keeping every drilled bucket's pages alive for the app's lifetime
/// would grow without bound as someone browsed, and would serve the stale
/// page set when they came back.
final musicItemsProvider = AsyncNotifierProvider.autoDispose
    .family<MusicItemsController, MusicItemsState, MusicListing>(
      MusicItemsController.new,
    );

/// How many buckets an index holds, as far as one page can say.
///
/// The facet page carries no total, so this is the first page's length
/// and whether there was more after it. A library with more artists than
/// one page reads "500+" on its tile, which is the truth and is what a
/// tile is for; the alternative is paging an entire dimension to render
/// a caption.
@immutable
class MusicIndexCount {
  const MusicIndexCount({required this.buckets, required this.atLeast});

  final int buckets;

  /// True when the page was full and the dimension runs past it.
  final bool atLeast;

  bool get isEmpty => buckets == 0;

  String get label => atLeast ? '$buckets+' : '$buckets';
}

/// Cached for the session rather than auto-disposed: the hub is a
/// destination people come back to, and four dimensions of buckets is
/// not a fetch worth repeating on every visit.
final musicIndexCountProvider =
    FutureProvider.family<MusicIndexCount, MusicDimension>((
      ref,
      dimension,
    ) async {
      final page = await ref
          .watch(repositoryProvider)
          .listFacets(dimension.wireName, limit: MusicIndexController.pageSize);
      return MusicIndexCount(
        buckets: page.buckets.length,
        atLeast: page.hasMore,
      );
    });
