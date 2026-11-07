import '../models.dart';

/// Browsing, searching and reading the library, and deleting its items.
abstract interface class LibraryApi {
  /// `GET /library/items`: keyset-paginated library listing, optionally
  /// filtered by media type.
  /// [facet] and [facetKey] together drill one bucket of a browse
  /// dimension, as enumerated by [listFacets]. [facetKey] is legitimately
  /// empty for a dimension's unknown bucket, so pass both or neither.
  Future<ItemPage> listItems({
    MediaType? mediaType,
    String? facet,
    String? facetKey,
    String? cursor,
    int? limit,
  });

  /// `GET /library/facets`: the buckets of one browse dimension
  /// (`genre`, `artist`, `album-artist`, `album`, `year`, `kind`, or
  /// `tag.<KEY>`) with counts, biggest first, or A to Z under
  /// [FacetSort.label]. Drill a bucket by passing its `key` back to
  /// [listItems] as `facetKey`.
  ///
  /// A [cursor] belongs to the [sort] it was issued under: flipping the
  /// order restarts the listing, and pairing the two is a request error
  /// rather than a quietly wrong page.
  ///
  /// [startsAt] opens the page at the first bucket sorting at or after a
  /// display-label prefix, which is what an alphabet rail taps. Needs
  /// [FacetSort.label] and refuses a [cursor].
  ///
  /// [facet]/[facetKey] scope the enumeration to one bucket of a second
  /// dimension: `dimension: 'album', facet: 'credit-artist'` answers the
  /// albums one artist is credited on, as album buckets. Scoping a
  /// dimension by itself is a request error, and a cursor belongs to the
  /// scope it was issued under.
  Future<FacetPage> listFacets(
    String dimension, {
    FacetSort? sort,
    String? cursor,
    String? startsAt,
    String? facet,
    String? facetKey,
    int? limit,
  });

  /// `GET /library/browse`: keyset-paginated discovery lists. [seed] keeps
  /// paging through the random list stable.
  ///
  /// [mediaType] narrows the list to one medium and [facet]/[facetKey]
  /// to one browse-dimension bucket, taking the same values [listItems]
  /// drills. Both narrow the list rather than the page. A cursor carries
  /// the scope it was issued under and is refused under another.
  Future<ItemPage> browse(
    DiscoveryList list, {
    MediaType? mediaType,
    String? facet,
    String? facetKey,
    String? cursor,
    int? limit,
    int? seed,
  });

  /// `GET /library/search`: grouped full-text search.
  Future<SearchResults> search(String q, {int? limit});

  /// `POST /library/entities`: the display facts behind a list of entity
  /// pids, in request order.
  ///
  /// What turns a stored handle back into a card - a pinned shelf holds
  /// pids, not snapshots. Pids that cannot be resolved (departed,
  /// unsubscribed, outside the caller's libraries) are silently dropped,
  /// so a short answer is normal and the caller must not index into it
  /// by request position.
  Future<EntityResolution> resolveEntities(List<String> pids);

  /// `POST /library/items/resolve`: the summaries behind a list of item
  /// pids, in request order, and the pids no item answers to any more.
  ///
  /// At most [itemLookupCap] pids a call. Pids out of the caller's sight
  /// are dropped without being named departed, so a short answer is
  /// normal; an item whose kind changed answers under its new prefix.
  Future<ItemResolution> resolveItems(List<String> pids);

  /// `GET /albums/{pid}`: one album entity's identity - barcode, label,
  /// catalog number, media, country - which no track row carries.
  Future<AlbumDetail> getAlbum(String pid);

  /// `GET /items/{pid}`: full detail for one item.
  Future<ItemDetail> getItem(String pid);

  /// `GET /items/{pid}/lyrics`: the item's words, or null when it has
  /// none.
  ///
  /// Null rather than a thrown 404, because having no lyrics is what
  /// most tracks in most libraries answer: it is the ordinary state of
  /// the field, not a failure to report. A caller that cannot reach the
  /// server still gets an exception.
  Future<Lyrics?> getItemLyrics(String pid);

  /// `GET /items/{pid}/art-roles`: the artwork slots an item, album, or
  /// artist holds at its own level (not inherited from the chain), each
  /// with its stored format and pixel dimensions.
  Future<ArtRoles> getItemArtRoles(String pid);

  /// `POST /library/items/delete`: deletes library items' files to
  /// the trash (or permanently). With [dryRun] nothing is touched and
  /// the result is the plan.
  Future<DeleteItemsResult> deleteLibraryItems({
    required List<String> pids,
    String? mode,
    bool dryRun = false,
  });

  /// `GET /items/{pid}/files`: the files behind one item, its own then
  /// its copies (the download permission or the admin role).
  Future<List<ItemFile>> getItemFiles(String pid);

  /// `POST /items/{pid}/files/delete`: deletes some of one item's files
  /// to the trash (or permanently). With [dryRun] nothing is touched and
  /// the result is the plan.
  Future<DeleteItemsResult> deleteItemFiles({
    required String pid,
    required List<String> filePids,
    String? mode,
    bool dryRun = false,
  });
}
