import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../library/page_walk.dart';
import '../providers.dart';
import '../queue/queue_state.dart';
import '../settings/prefs_controller.dart';
import '../sync/refresh_in_place.dart';

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
    glyph: WaxIcons.artists,
    entityPrefix: 'ar-',
    shape: ArtworkShape.circle,
  ),
  albums(
    segment: 'albums',
    wireName: 'album',
    glyph: WaxIcons.albums,
    entityPrefix: 'al-',
  ),
  releaseGroups(
    segment: 'release-groups',
    wireName: 'release-group',
    glyph: WaxIcons.albums,
    entityPrefix: 'rg-',
  ),
  genres(segment: 'genres', wireName: 'genre', glyph: WaxIcons.filter),
  years(segment: 'years', wireName: 'year', glyph: WaxIcons.recent);

  const MusicDimension({
    required this.segment,
    required this.wireName,
    required this.glyph,
    this.entityPrefix,
    this.shape = ArtworkShape.square,
  });

  /// The path segment under `/music`. Plural, because it names a list.
  final String segment;

  /// The `dimension` the server enumerates and the `facet` a listing
  /// filters by. The two are the same string by contract.
  final String wireName;

  final WaxGlyph glyph;

  /// What this dimension is called, as a heading. Selected on `name`
  /// rather than `wireName`, which is not an identifier.
  String titleOf(AppLocalizations l10n) => l10n.musicDimensionTitle(name);

  /// The API type prefix a bucket's `entityPid` carries, for the
  /// dimensions whose buckets are catalog entities. The contract spells
  /// out that the pid is the bucket key with this in front, which is what
  /// lets one location carry both: the URL names the entity, the drill
  /// sends the key.
  final String? entityPrefix;

  /// How this dimension's buckets are drawn. Artists are discs, which is
  /// the shape signal the design language uses for a person.
  final ArtworkShape shape;

  /// Whether a bucket of this dimension is a catalog entity, and so
  /// travels in a location as its pid rather than its key.
  bool get isEntity => entityPrefix != null;

  /// The dimensions whose buckets have artwork worth fetching.
  ///
  /// Albums and artists. Artists earned their place when the server
  /// grew its artist-art walk: artist-level artwork now exists without an
  /// admin setting it by hand, so the index row's ask stopped being a
  /// round trip for a statically known no. Genre and year buckets carry
  /// no `entityPid` on this surface (the server deliberately mints none
  /// for them), so their rows have nothing to ask with. Release groups
  /// do carry one, but the item art endpoint's pid resolver has no
  /// `rg-` arm, so asking would 404 on every row; if that arm ever
  /// lands, this is where release groups join.
  bool get hasArtwork =>
      this == MusicDimension.albums || this == MusicDimension.artists;
}

/// The URL segment the unknown bucket takes.
///
/// Its key is legitimately empty - it is the bucket for items a dimension
/// is absent from - and an empty path segment is not a location. No real
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
  return dimension.isEntity && entityPid != null && entityPid.isNotEmpty
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

/// Which part of the library an index browses: the scope its buckets
/// are counted under, and the media type a bucket drills with, so a
/// bucket's count and the list it opens agree.
enum BrowseDomain {
  music(scopeFacet: 'kind', scopeKey: 'track', drillMediaType: MediaType.music),
  books(
    scopeFacet: 'kind',
    scopeKey: 'book',
    drillMediaType: MediaType.audiobook,
  ),

  /// No scope and no media type: the entity pages and the editor, reached
  /// from search, mixes and the health folds, where the medium is unknown
  /// and an author-only artist must not open to an empty page.
  wholeLibrary();

  const BrowseDomain({this.scopeFacet, this.scopeKey, this.drillMediaType});

  final String? scopeFacet;
  final String? scopeKey;
  final MediaType? drillMediaType;
}

/// Which index a caller is looking at, and in which order.
typedef MusicIndexKey = ({
  MusicDimension dimension,
  FacetSort sort,
  BrowseDomain domain,
});

/// Accumulated pages of one dimension's buckets.
class MusicIndexState {
  const MusicIndexState({
    required this.buckets,
    this.nextCursor,
    this.loadingMore = false,
    this.anchoredAt,
  });

  final List<FacetBucket> buckets;
  final String? nextCursor;
  final bool loadingMore;

  /// The rail letter this window was re-anchored on; null when it starts
  /// at the head. Non-null means the window has a floor.
  final String? anchoredAt;

  bool get hasMore => nextCursor != null;

  bool get hasFloor => anchoredAt != null;
}

/// Pages one index's buckets. One instance per (dimension, order): the
/// two orders are two listings with two cursor spaces, and the server
/// refuses a cursor carried across them.
///
/// A catalog change refreshes it in place: the window it has loaded and
/// the floor it was anchored on are kept.
class MusicIndexController extends AsyncNotifier<MusicIndexState>
    with RefreshedInPlace<FacetBucket, MusicIndexState> {
  MusicIndexController(this.key);

  final MusicIndexKey key;

  /// Big enough that the common index arrives whole in one round trip.
  static const pageSize = 500;

  /// Watched in [build], so flipping the preference reloads open indexes.
  var _showUnknown = true;

  /// The rail letter the window starts at; null when it starts at the
  /// head.
  String? _anchoredAt;

  /// Here rather than at the three places the screen reads a bucket list,
  /// so rows, rail, and letter seek cannot disagree. Paging is unharmed:
  /// the cursor is minted from the unfiltered page.
  List<FacetBucket> _shown(List<FacetBucket> buckets) {
    if (_showUnknown) return buckets;
    return <FacetBucket>[
      for (final bucket in buckets)
        if (!bucket.unknown) bucket,
    ];
  }

  @override
  ProviderBase<Object?> get self => musicIndexProvider(key);

  @override
  int get pageRows => pageSize;

  @override
  int? get walkLimit => 1;

  @override
  Object rowKey(FacetBucket row) => row.key;

  @override
  MusicIndexState shape(
    PagedRows<FacetBucket> held, {
    required bool loadingMore,
  }) => MusicIndexState(
    buckets: held.rows,
    nextCursor: held.nextCursor,
    loadingMore: loadingMore,
    anchoredAt: _anchoredAt,
  );

  @override
  void startingOver() => _anchoredAt = null;

  Future<FacetPage> _page(
    WaxDeckRepository repository, {
    String? cursor,
    String? startsAt,
  }) => repository.listFacets(
    key.dimension.wireName,
    sort: key.sort,
    cursor: cursor,
    startsAt: startsAt,
    facet: key.domain.scopeFacet,
    facetKey: key.domain.scopeKey,
    limit: pageSize,
  );

  /// From the head of the window: the floor of an anchored one, which a
  /// refresh re-reads from rather than from the first bucket.
  @override
  Future<PagedRows<FacetBucket>> readRows({
    required int want,
    String? from,
    int? maxPages,
    bool Function()? stop,
  }) {
    final repository = ref.read(repositoryProvider);
    final floor = _anchoredAt;
    return walkRows(
      (cursor) async {
        final page = await _page(
          repository,
          cursor: cursor,
          startsAt: cursor == null ? floor : null,
        );
        return (rows: _shown(page.buckets), nextCursor: page.nextCursor);
      },
      want: want,
      from: from,
      maxPages: maxPages,
      stop: stop,
    );
  }

  @override
  Future<MusicIndexState> build() {
    _showUnknown = ref.watch(
      prefsControllerProvider.select(
        (prefs) => prefs.value?.browseShowUnknown ?? true,
      ),
    );
    return buildInPlace(source: (ref.watch(repositoryProvider), _showUnknown));
  }

  /// Fetches the next page and appends it. Answers whether anything was
  /// added, so a caller paging toward a letter knows when to stop.
  Future<bool> loadMore() => loadMoreInPlace();

  /// Re-anchors the listing on [letter], replacing what was loaded with
  /// a window starting at the server's seek. Only for a letter not
  /// already on the list. The window then has a floor, which [reset]
  /// drops. The rail's `#` never reaches here; no prefix names it.
  Future<bool> anchorAt(String letter) async {
    if (key.sort != FacetSort.label) return false;
    final repository = ref.read(repositoryProvider);
    return replaceInPlace(() async {
      final page = await _page(repository, startsAt: letter);
      // Past the last bucket is a legitimately empty page. Committing
      // it would trade the listing, and the rail with it, for nothing.
      if (page.buckets.isEmpty) return null;
      return (rows: _shown(page.buckets), nextCursor: page.nextCursor);
    }, adopt: () => _anchoredAt = letter);
  }

  /// Drops any floor and reloads from the head.
  void reset() => startOver();
}

/// Disposed with the index: a visit reads the account's library as it
/// stands, and while it is open the catalog fan-out refreshes it in
/// place.
final musicIndexProvider = AsyncNotifierProvider.autoDispose
    .family<MusicIndexController, MusicIndexState, MusicIndexKey>(
      MusicIndexController.new,
    );

/// What an index opens in with no stored order. A-to-Z where an alphabet
/// is how anyone looks for a thing; biggest-first for genres and years,
/// since an alphabet of years is the years again.
FacetSort defaultBrowseSort(MusicDimension dimension) => switch (dimension) {
  MusicDimension.artists ||
  MusicDimension.albums ||
  MusicDimension.releaseGroups => FacetSort.label,
  MusicDimension.genres || MusicDimension.years => FacetSort.count,
};

String browseSortLabel(AppLocalizations l10n, FacetSort sort) => switch (sort) {
  FacetSort.label => l10n.libraryBrowseSortAtoZ,
  FacetSort.count => l10n.libraryBrowseSortMostFirst,
};

/// Which index: a dimension over a domain.
typedef MusicIndexId = ({MusicDimension dimension, BrowseDomain domain});

/// Which order an index is showing. Per index, because the choice is
/// about the list in front of you: sorting Books > Authors leaves Music >
/// Artists alone. Both start from the one stored default per dimension.
class MusicIndexSort extends Notifier<FacetSort> {
  MusicIndexSort(this.key);

  final MusicIndexId key;

  MusicDimension get dimension => key.dimension;

  /// Outranks the stored default. Dropped when that value itself
  /// changes: the provider outlives its screen, so a toolbar tap would
  /// otherwise make the setting dead for the session.
  FacetSort? _chosen;
  FacetSort? _storedAtChoice;

  @override
  FacetSort build() {
    // Watched: an index opened before the document landed would keep the
    // built-in order for the rest of the session.
    final stored = ref.watch(
      prefsControllerProvider.select(
        (prefs) => prefs.value?.browseSortFor(dimension.wireName),
      ),
    );
    if (stored != _storedAtChoice) _chosen = null;
    return _chosen ?? stored ?? defaultBrowseSort(dimension);
  }

  void select(FacetSort sort) {
    _chosen = sort;
    _storedAtChoice = ref.read(
      prefsControllerProvider.select(
        (prefs) => prefs.value?.browseSortFor(dimension.wireName),
      ),
    );
    state = sort;
  }
}

final musicIndexSortProvider =
    NotifierProvider.family<MusicIndexSort, FacetSort, MusicIndexId>(
      MusicIndexSort.new,
    );

/// One drilled listing: a dimension bucket, or the whole tracks index
/// when [dimension] is null.
typedef MusicListing = ({
  MusicDimension? dimension,
  String segment,
  BrowseDomain domain,
});

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
}

/// Pages the items of one bucket, or of the whole music library. A
/// catalog change refreshes it in place, the rows it has loaded kept.
class MusicItemsController extends AsyncNotifier<MusicItemsState>
    with RefreshedInPlace<ItemSummary, MusicItemsState> {
  MusicItemsController(this.listing);

  final MusicListing listing;

  /// The queue cap, deliberately.
  ///
  /// Playing a row plays the bucket from there, and what the screen hands
  /// over is what it has loaded - so a page smaller than the cap would
  /// queue a prefix of an artist and call it the artist. At the cap, any
  /// bucket the queue could hold whole is loaded whole before the first
  /// row can be tapped, and a bucket bigger than that is windowed by the
  /// queue itself from the row that was chosen, which is the same answer
  /// a smaller page could not give. It costs a larger first page on a
  /// long list, which is what the index pages at for the same reason.
  static const pageSize = kQueueCap;

  @override
  ProviderBase<Object?> get self => musicItemsProvider(listing);

  @override
  int get pageRows => pageSize;

  @override
  Object rowKey(ItemSummary row) => row.pid;

  @override
  MusicItemsState shape(
    PagedRows<ItemSummary> held, {
    required bool loadingMore,
  }) => MusicItemsState(
    items: held.rows,
    nextCursor: held.nextCursor,
    loadingMore: loadingMore,
  );

  /// A page reader over the repository as it is now, so a walk reads its
  /// pages through one repository rather than through the ref each time.
  Future<ItemPage> Function(String? cursor) _pages() {
    final repository = ref.read(repositoryProvider);
    return (cursor) => _page(repository, cursor);
  }

  Future<ItemPage> _page(WaxDeckRepository repository, String? cursor) {
    final dimension = listing.dimension;
    return repository.listItems(
      // A bucket drills under its domain's media type, which is the
      // scope its count was taken over: a count that disagrees with the
      // list it opens is the one thing faceted browse cannot do. The
      // tracks index is "every track", not a bucket of anything.
      mediaType: dimension == null
          ? MediaType.music
          : listing.domain.drillMediaType,
      facet: dimension?.wireName,
      facetKey: dimension == null
          ? null
          : musicFacetKey(dimension, listing.segment),
      cursor: cursor,
      limit: pageSize,
    );
  }

  /// A first read and a next page ask for one row and no page limit: to
  /// the first page with rows on it, past pages the listing emptied
  /// (rows the caller may not see are dropped after the page is cut),
  /// never "nothing here" over rows a page further on. No further, so a
  /// later page that fails takes nothing this read showed and a run of
  /// short pages is not walked to fill a quota; the screen asks for more
  /// as it needs it, a list too short to scroll included.
  @override
  Future<PagedRows<ItemSummary>> readRows({
    required int want,
    String? from,
    int? maxPages,
    bool Function()? stop,
  }) {
    final page = _pages();
    return walkRows(
      (cursor) async {
        final next = await page(cursor);
        return (rows: next.items, nextCursor: next.nextCursor);
      },
      want: want,
      from: from,
      maxPages: maxPages,
      stop: stop,
    );
  }

  @override
  Future<MusicItemsState> build() {
    // Watched rather than read so a sign-in swap rebuilds the listing.
    return buildInPlace(source: ref.watch(repositoryProvider));
  }

  /// The listing's items to its end, or until more than [atMost] are
  /// known, for a verb that names a bucket whole or not at all. Pages
  /// past the held ones are read without being shown; one that fails
  /// throws, and the walk runs to its answer even if the listing is left
  /// meanwhile, since its caller is waiting on it.
  Future<List<ItemSummary>> readThrough({required int atMost}) async {
    final held = await future;
    final from = held.nextCursor;
    if (from == null || held.items.length > atMost) return held.items;
    final rest = await readPages(
      _pages(),
      from: from,
      want: atMost + 1 - held.items.length,
    );
    return <ItemSummary>[...held.items, ...rest.items];
  }

  Future<void> loadMore() async {
    await loadMoreInPlace();
  }
}

/// Auto-disposed, as the index pages are: a bucket is any artist, album,
/// genre, or year in the library, and keeping every drilled bucket's
/// pages alive for the app's lifetime would grow without bound as
/// someone browsed, and would serve the stale page set when they came
/// back.
/// A refusal is about the request rather than the connection (a key a
/// bucket cannot take is `invalid-request`), so the screen draws its
/// error state instead of spinning through the ladder. A key that names
/// nothing is not a refusal: it drills an empty page, and the screens
/// over one ask the entity's own read whether it is there.
final musicItemsProvider = AsyncNotifierProvider.autoDispose
    .family<MusicItemsController, MusicItemsState, MusicListing>(
      MusicItemsController.new,
      retry: retryUnlessRefused,
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

/// Cached for the session rather than auto-disposed: a hub is a
/// destination people come back to, and a hub's counts are not a fetch
/// worth repeating on every visit. The account, the catalog fan-out and
/// a kind change move it. It counts what the index lists, so the
/// unknown bucket only while the account shows it. A refusal is final,
/// as for the Series count beside it.
final musicIndexCountProvider =
    FutureProvider.family<MusicIndexCount, MusicIndexId>((ref, key) async {
      ref.watch(signedInAccountProvider);
      final showUnknown = ref.watch(
        prefsControllerProvider.select(
          (prefs) => prefs.value?.browseShowUnknown ?? true,
        ),
      );
      final page = await ref
          .watch(repositoryProvider)
          .listFacets(
            key.dimension.wireName,
            facet: key.domain.scopeFacet,
            facetKey: key.domain.scopeKey,
            limit: MusicIndexController.pageSize,
          );
      return MusicIndexCount(
        buckets: page.buckets.where((b) => showUnknown || !b.unknown).length,
        atLeast: page.hasMore,
      );
    }, retry: retryUnlessRefused);

/// One entity's card, for a screen that arrived at its pid without the
/// name that goes with it.
///
/// A shared link and a reload both drop the label a caller had, and an
/// artist page derived its title from the first track it loaded
/// instead - which is a *credit* ("Dom Kennedy feat. Ty Dolla $ign"),
/// not an artist. The card carries the entity's own title, which is the
/// only thing that is right for every row underneath it.
///
/// Decoration, so a failure is final: the screen falls back to its
/// localized placeholder rather than sitting through ten retries with
/// the title blank.
final entityCardProvider = FutureProvider.autoDispose
    .family<EntityCard?, String>((ref, pid) async {
      final resolution = await ref.watch(repositoryProvider).resolveEntities(
        <String>[pid],
      );
      for (final card in resolution.cards) {
        if (card.pid == pid) return card;
      }
      return null;
    }, retry: (_, _) => null);
