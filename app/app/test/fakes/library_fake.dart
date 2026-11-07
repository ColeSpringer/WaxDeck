import 'dart:async';

import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// One `FakeRepository.listItems` call, as it was asked.
typedef ListItemsCall = ({
  MediaType? mediaType,
  String? facet,
  String? facetKey,
  String? cursor,
  int? limit,
});

/// In-memory [LibraryApi] for `FakeRepository`.
mixin FakeLibrary on FakeRepositoryState implements LibraryApi {
  /// Lyrics by pid. An unseeded pid answers null, which is what a
  /// server says about a track nobody has words for.
  final Map<String, Lyrics> lyrics = {};

  /// Pids [getItemLyrics] was asked about, so a test can pin that a
  /// face with no lyrics affordance does not ask.
  final List<String> lyricsCalls = [];

  /// Thrown by [getItemLyrics] when set.
  WaxDeckApiException? lyricsError;

  /// Buckets [listFacets] answers, keyed by dimension. A scoped read
  /// takes the key "dimension|facet|facetKey" and falls back to the plain
  /// dimension, so a test that does not care about the scope seeds one
  /// list and a test that does seeds both.
  final Map<String, List<FacetBucket>> facets = {};

  /// Every (dimension, facet, facetKey) triple [listFacets] was scoped
  /// by, in call order, so a test can prove a shelf asked for buckets
  /// rather than paging items.
  final List<(String, String, String)> facetScopes = [];

  /// Every (dimension, key) pair a listing drilled, in call order.
  final List<(String, String)> facetDrills = [];

  /// Every sort [listFacets] was asked for, in call order, so a test can
  /// tell an A-to-Z index from a biggest-first one.
  final List<FacetSort?> facetSorts = [];

  /// Every [listFacets] call whole, in call order: its sort and its scope
  /// in one record, so a test reads both off the same call.
  final List<
    ({String dimension, FacetSort? sort, String? facet, String? facetKey})
  >
  facetReads = [];

  /// So a rail test can tell a re-anchor from a free scroll.
  final List<String?> facetStartsAt = [];

  /// Held open, every facet listing waits on it, so a test can have one
  /// genuinely in flight while it starts another.
  Completer<void>? facetGate;

  /// Thrown by a facet listing once [facetGate] opens, so a read can fail
  /// after the reader that started it has gone.
  Object? facetErrorAfterGate;

  /// Held open, every item listing waits on it. What a screen's refresh
  /// test needs: a reload genuinely in flight, which is the state that
  /// carries the previous value and used to blank a screen.
  Completer<void>? listItemsGate;

  /// Cursors this fake refuses with `invalid-request`, the way a server
  /// refuses one minted by a build with a different encoding.
  final Set<String> rejectedCursors = {};

  /// Pids every listing drops after it has cut the page, with the cursor
  /// still counting them: what the server does with rows the caller's
  /// content settings refuse, which the listing contract allows. A page
  /// can come back short, or empty, and still carry a cursor.
  final Set<String> hiddenFromListings = {};

  /// Every [listItems] call, browse fallthroughs included, in call order.
  final List<ListItemsCall> listItemsCalls = [];

  List<ItemSummary> _visible(List<ItemSummary> items) => <ItemSummary>[
    for (final item in items)
      if (!hiddenFromListings.contains(item.pid)) item,
  ];

  @override
  Future<ItemPage> listItems({
    MediaType? mediaType,
    String? facet,
    String? facetKey,
    String? cursor,
    int? limit,
  }) async {
    listItemsCalls.add((
      mediaType: mediaType,
      facet: facet,
      facetKey: facetKey,
      cursor: cursor,
      limit: limit,
    ));
    final error = listError;
    if (error != null) throw error;
    await listItemsGate?.future;
    if (cursor != null && rejectedCursors.contains(cursor)) {
      throw const WaxDeckApiException(
        code: 'invalid-request',
        message: 'cursor was issued for another scope',
      );
    }
    var filtered = mediaType == null
        ? libraryItems
        : libraryItems.where((i) => i.mediaType == mediaType).toList();
    if (facet != null) {
      facetDrills.add((facet, facetKey ?? ''));
      filtered = facetItems['$facet ${facetKey ?? ''}'] ?? const [];
      // Narrowed as the server narrows a drill, so a screen that asks
      // for the wrong medium is answered with the wrong rows.
      if (mediaType != null) {
        filtered = filtered.where((i) => i.mediaType == mediaType).toList();
      }
    }
    final start = cursor == null ? 0 : int.parse(cursor);
    final pageSize = limit ?? 100;
    final end = (start + pageSize).clamp(0, filtered.length);
    return ItemPage(
      items: _visible(filtered.sublist(start.clamp(0, filtered.length), end)),
      nextCursor: end < filtered.length ? '$end' : null,
    );
  }

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
    final error = listError;
    if (error != null) throw error;
    facetSorts.add(sort);
    facetReads.add((
      dimension: dimension,
      sort: sort,
      facet: facet,
      facetKey: facetKey,
    ));
    facetStartsAt.add(startsAt);
    if (facet != null) {
      facetScopes.add((dimension, facet, facetKey ?? ''));
    }
    final gate = facetGate;
    if (gate != null) await gate.future;
    final failure = facetErrorAfterGate;
    if (failure != null) throw failure;
    final scoped = facet == null
        ? null
        : facets['$dimension|$facet|${facetKey ?? ''}'];
    final all = <FacetBucket>[...?(scoped ?? facets[dimension])];
    // The server serves the A-to-Z order itself; the fake sorts here so
    // a screen test sees the arrangement its rail is built on.
    if (sort == FacetSort.label) {
      all.sort((a, b) {
        if (a.unknown != b.unknown) return a.unknown ? 1 : -1;
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
    }
    var start = cursor == null ? 0 : int.parse(cursor);
    if (startsAt != null) {
      // The server's rule: at-or-after, real buckets only.
      final real = all.where((b) => !b.unknown).toList();
      final fold = startsAt.trimLeft().toLowerCase();
      final at = real.indexWhere(
        (b) => b.label.trimLeft().toLowerCase().compareTo(fold) >= 0,
      );
      start = at < 0 ? all.length : all.indexOf(real[at]);
    }
    final pageSize = limit ?? 100;
    final end = (start + pageSize).clamp(0, all.length);
    return FacetPage(
      dimension: dimension,
      buckets: all.sublist(start.clamp(0, all.length), end),
      nextCursor: end < all.length ? '$end' : null,
    );
  }

  /// The seed the server would pick for an unseeded random browse.
  int randomSeed = 4242;

  /// Every random browse this fake answered, as the (seed, cursor) pair
  /// it was asked for: a rolling shuffle is only stable if later pages
  /// carry the first page's seed, and this is what lets a test say so.
  final List<({int? seed, String? cursor})> randomBrowses = [];

  /// What each discovery list answers, for the shelves that ask for one
  /// by name. An unlisted list falls through to the whole listing, which
  /// is what most callers want and what every list did before shelves
  /// existed.
  final Map<DiscoveryList, List<ItemSummary>> browseLists = {};

  /// Every browse this fake answered, so a test can say which lists a
  /// screen asked for and how it scoped them.
  final List<({DiscoveryList list, MediaType? mediaType})> browseCalls = [];

  /// So a test can tell a bucket-wide shuffle from a page of it.
  final List<({String facet, String facetKey, int? seed})> scopedBrowses = [];

  /// When set, every [browse] waits on it before answering, so a shelf
  /// can be held loading while a test looks at what it draws meanwhile.
  Completer<void>? browseGate;

  /// A discovery list scripted page by page, answered by cursor index: a
  /// null cursor reads the first page, `'1'` the second. Each page keeps
  /// the cursor it was written with, so a list can answer two empty pages
  /// that continue and then a full one. Ahead of [browseLists].
  final Map<DiscoveryList, List<ItemPage>> browsePages = {};

  @override
  Future<ItemPage> browse(
    DiscoveryList list, {
    MediaType? mediaType,
    String? facet,
    String? facetKey,
    String? cursor,
    int? limit,
    int? seed,
  }) async {
    browseCalls.add((list: list, mediaType: mediaType));
    await browseGate?.future;
    if (facet != null) {
      scopedBrowses.add((facet: facet, facetKey: facetKey ?? '', seed: seed));
    }
    if (cursor != null && rejectedCursors.contains(cursor)) {
      throw const WaxDeckApiException(
        code: 'invalid-request',
        message: 'cursor was issued for another scope',
      );
    }
    if (browsePages[list] case final pages?) {
      final page = pages[cursor == null ? 0 : int.parse(cursor)];
      return ItemPage(items: _visible(page.items), nextCursor: page.nextCursor);
    }
    if (list == DiscoveryList.recentlyPlayed &&
        !browseLists.containsKey(list)) {
      final item = recentlyPlayed;
      return ItemPage(items: item == null ? const [] : [item]);
    }
    if (list == DiscoveryList.inProgress && !browseLists.containsKey(list)) {
      return _page(_inProgress(mediaType), cursor: cursor, limit: limit);
    }
    final scripted = browseLists[list];
    if (scripted != null) {
      return ItemPage(
        items: _visible(<ItemSummary>[
          for (final item in scripted)
            if (mediaType == null || item.mediaType == mediaType) item,
        ]),
      );
    }
    final page = await listItems(
      mediaType: mediaType,
      facet: facet,
      facetKey: facetKey,
      cursor: cursor,
      limit: limit,
    );
    if (list != DiscoveryList.random) return page;
    randomBrowses.add((seed: seed, cursor: cursor));
    return ItemPage(
      items: page.items,
      nextCursor: page.nextCursor,
      seed: seed ?? randomSeed,
    );
  }

  /// The in-progress list as the server keeps it, read off this fake's
  /// play states: a saved position on something unfinished, a track only
  /// once a play of it has counted, most recently progressed first. A
  /// state with no stamp sorts after those with one.
  List<ItemSummary> _inProgress(MediaType? mediaType) {
    bool held(ItemSummary item) =>
        (mediaType == null || item.mediaType == mediaType) &&
        (playPositions[item.pid] ?? 0) > 0 &&
        !finishedPids.contains(item.pid) &&
        (item.mediaType != MediaType.music ||
            playStateLastPlayedAt.containsKey(item.pid));
    final stamped =
        <ItemSummary>[
          for (final item in libraryItems)
            if (held(item) && playStateUpdatedAt.containsKey(item.pid)) item,
        ]..sort(
          (a, b) =>
              playStateUpdatedAt[b.pid]!.compareTo(playStateUpdatedAt[a.pid]!),
        );
    return <ItemSummary>[
      ...stamped,
      for (final item in libraryItems)
        if (held(item) && !playStateUpdatedAt.containsKey(item.pid)) item,
    ];
  }

  /// One page of [items] at [cursor], the index-cursor shape every
  /// listing here answers with.
  ItemPage _page(List<ItemSummary> items, {String? cursor, int? limit}) {
    final start = cursor == null ? 0 : int.parse(cursor);
    final end = (start + (limit ?? 100)).clamp(0, items.length);
    return ItemPage(
      items: _visible(items.sublist(start.clamp(0, items.length), end)),
      nextCursor: end < items.length ? '$end' : null,
    );
  }

  /// What [search] answers, keyed by query. An unlisted query answers an
  /// empty result set, which is the "nothing matched" screen.
  final Map<String, SearchResults> searchResults = {};

  /// Every query [search] was asked for, in call order, so a test can see
  /// what the debounce let through.
  final List<String> searchCalls = [];

  /// Thrown by [search] when set, for the screens that draw a library
  /// failure beside a surface that answered.
  WaxDeckApiException? searchError;

  /// Holds [search] until completed, with the call recorded.
  Completer<void>? searchGate;

  @override
  Future<SearchResults> search(String q, {int? limit}) async {
    searchCalls.add(q);
    if (searchGate case final gate?) await gate.future;
    final error = searchError;
    if (error != null) throw error;
    return searchResults[q] ?? SearchResults(query: q);
  }

  /// When set, [getItem] waits on it before answering, so a test can
  /// hold an entry's resolution open - the window before any session
  /// exists - and act while it is in flight.
  Completer<void>? getItemGate;

  /// Cards [resolveEntities] answers, keyed by pid. A pid with no entry
  /// is dropped, which is the endpoint's own behaviour for anything it
  /// cannot resolve.
  final Map<String, EntityCard> entityCards = {};

  /// The pids [resolveEntities] names departed - gone for everyone -
  /// when asked for them. A dropped pid not listed here is a plain
  /// omission, the server's shape for merely-invisible.
  final Set<String> departedEntityPids = {};

  /// Every pid list [resolveEntities] was asked for, in call order.
  final List<List<String>> resolvedEntityPids = [];

  @override
  Future<EntityResolution> resolveEntities(List<String> pids) async {
    resolvedEntityPids.add(List<String>.of(pids));
    final error = listError;
    if (error != null) throw error;
    return EntityResolution(
      cards: <EntityCard>[for (final pid in pids) ?entityCards[pid]],
      departed: <String>[
        for (final pid in pids)
          if (departedEntityPids.contains(pid)) pid,
      ],
    );
  }

  /// Item pids [resolveItems] leaves out without naming departed: the
  /// server's shape for an item out of the caller's sight.
  final Set<String> hiddenItemPids = {};

  /// Every pid list [resolveItems] was asked for, in call order.
  final List<List<String>> resolvedItemPids = [];

  /// Thrown by [resolveItems] while set.
  WaxDeckApiException? resolveItemsError;

  /// Answers from [libraryItems] by ULID, as the server reaches an item
  /// under either a track's or a book's prefix; a pid nothing answers to
  /// is departed.
  @override
  Future<ItemResolution> resolveItems(List<String> pids) async {
    resolvedItemPids.add(List<String>.of(pids));
    final error = resolveItemsError;
    if (error != null) throw error;
    if (pids.length > itemLookupCap) {
      throw const WaxDeckApiException(
        code: 'invalid-request',
        message: 'too many pids',
        statusCode: 400,
      );
    }
    final items = <ItemSummary>[];
    final departed = <String>[];
    for (final pid in pids) {
      if (hiddenItemPids.contains(pid)) continue;
      final item = libraryItems
          .where((i) => ulidOf(i.pid) == ulidOf(pid))
          .firstOrNull;
      if (item != null) {
        items.add(item);
      } else if (!departed.contains(pid)) {
        departed.add(pid);
      }
    }
    return ItemResolution(items: items, departed: departed);
  }

  @override
  Future<AlbumDetail> getAlbum(String pid) async {
    final album = albums[pid];
    if (album == null) {
      throw WaxDeckApiException(
        statusCode: 404,
        code: 'not-found',
        message: 'no album with pid $pid',
      );
    }
    return album;
  }

  /// The copies [getItem] reports per item, none by default.
  final Map<String, int> itemDetailCopies = {};

  @override
  Future<ItemDetail> getItem(String pid) async {
    await getItemGate?.future;
    // The server's own answer for a pid it does not hold, as getAlbum
    // above gives it: a `StateError` out of `firstWhere` is a bug in
    // the test, and the surfaces that draw an error state need the
    // refusal that tells them to stop asking.
    final item = libraryItems.where((i) => i.pid == pid).firstOrNull;
    if (item == null) {
      throw WaxDeckApiException(
        statusCode: 404,
        code: 'not-found',
        message: 'no item with pid $pid',
      );
    }
    return ItemDetail(
      pid: item.pid,
      mediaType: item.mediaType,
      title: item.title,
      artist: item.artist,
      album: item.album,
      // The real read carries the entity handles; the item menus are
      // built from them, so a fake that dropped them would certify
      // menus the app never draws.
      artistPid: item.artistPid,
      albumPid: item.albumPid,
      trackNumber: item.trackNumber,
      discNumber: item.discNumber,
      sortKey: item.sortKey,
      artistSort: item.artistSort,
      artistSortKey: item.artistSortKey,
      durationMs: item.durationMs,
      artUrl: item.artUrl,
      // The technical half a real detail carries. Kept on the fake
      // rather than left null because the facts sheet is entirely these
      // rows, and a fake answering none of them would certify a sheet
      // that draws nothing.
      year: itemDetailYear,
      genres: itemDetailGenres,
      bpm: itemDetailBpm[pid],
      trackTotal: itemDetailTrackTotal[pid],
      discTotal: itemDetailDiscTotal[pid],
      partTotal: itemDetailPartTotal[pid],
      codec: itemDetailCodec,
      container: itemDetailContainer,
      sampleRate: itemDetailSampleRate,
      bitrate: itemDetailBitrate,
      addedAt: itemDetailAddedAt,
      copies: itemDetailCopies[pid] ?? 0,
      mbid: itemDetailMbid[pid],
      isrc: itemDetailIsrc[pid],
    );
  }

  /// What [getItem] answers for the fields an item summary does not
  /// carry. One set for every item, since no test wants two different
  /// codecs; the per-pid maps are for the fields a test does vary.
  int? itemDetailYear = 1975;
  List<String> itemDetailGenres = const ['Blues'];
  String? itemDetailCodec = 'flac';
  String? itemDetailContainer = 'flac';
  int? itemDetailSampleRate = 44100;
  int? itemDetailBitrate = 986;
  DateTime? itemDetailAddedAt = DateTime.utc(2026, 1, 2, 3, 4);
  final Map<String, int> itemDetailBpm = {};
  final Map<String, int> itemDetailTrackTotal = {};
  final Map<String, int> itemDetailDiscTotal = {};
  final Map<String, int> itemDetailPartTotal = {};
  final Map<String, String> itemDetailMbid = {};
  final Map<String, String> itemDetailIsrc = {};

  /// Holds [getItemLyrics] until completed, with the call
  /// already recorded.
  Completer<void>? lyricsGate;

  @override
  Future<Lyrics?> getItemLyrics(String pid) async {
    lyricsCalls.add(pid);
    await lyricsGate?.future;
    final error = lyricsError;
    if (error != null) throw error;
    return lyrics[pid];
  }

  /// Slots per pid, for a read that asks about more than one entity (a
  /// track and its album); a pid with no entry answers [artRoles].
  final Map<String, List<ArtRoleInfo>> artRolesByPid = {};

  /// Per pid: a read held until its gate completes, and one that throws.
  final Map<String, Completer<void>> artRolesGates = {};
  final Map<String, Object> artRolesErrors = {};

  /// Every pid a roles read asked about, in order.
  final List<String> artRolesReads = [];

  /// Where the cover the entity resolves came from, which the roles
  /// read reports beside the slots it holds.
  ArtSource? artSource;

  @override
  Future<ArtRoles> getItemArtRoles(String pid) async {
    artRolesReads.add(pid);
    await artRolesGates[pid]?.future;
    if (artRolesErrors[pid] case final error?) throw error;
    return ArtRoles(
      roles: List.unmodifiable(artRolesByPid[pid] ?? artRoles),
      artSource: artSource,
    );
  }

  /// Preset delete plans by pid; absent pids get one file of 1 MiB.
  final Map<String, DeletePlanEntry> deletePlansByPid = {};

  /// Thrown by [deleteLibraryItems] when set.
  WaxDeckApiException? deleteItemsError;

  /// Decides per call whether [deleteLibraryItems] refuses, and with
  /// what; the call is recorded either way.
  WaxDeckApiException? Function(List<String> pids, bool dryRun)?
  deleteItemsRefusal;

  /// Files an applied delete tries and leaves where they were.
  int deleteItemsFailed = 0;

  /// What an applied [deleteLibraryItems] says beside removing files.
  List<String> deleteItemsWarnings = const [];

  final List<({List<String> pids, String? mode, bool dryRun})>
  deleteItemsCalls = [];

  @override
  Future<DeleteItemsResult> deleteLibraryItems({
    required List<String> pids,
    String? mode,
    bool dryRun = false,
  }) async {
    final error = deleteItemsError;
    if (error != null) throw error;
    deleteItemsCalls.add((pids: pids, mode: mode, dryRun: dryRun));
    final refusal = deleteItemsRefusal?.call(pids, dryRun);
    if (refusal != null) throw refusal;
    final entries = [
      for (final pid in pids)
        deletePlansByPid[pid] ??
            DeletePlanEntry(pid: pid, files: 1, bytes: 1048576),
    ];
    if (!dryRun) {
      libraryItems.removeWhere((item) => pids.contains(item.pid));
    }
    return _deleteResult(
      mode ?? 'trash',
      dryRun,
      entries,
      dryRun ? const [] : deleteItemsWarnings,
    );
  }

  /// A delete's answer, with an applied one's totals: every planned file
  /// gone but [deleteItemsFailed].
  DeleteItemsResult _deleteResult(
    String mode,
    bool dryRun,
    List<DeletePlanEntry> entries,
    List<String> warnings,
  ) {
    final went = dryRun
        ? 0
        : entries.fold(0, (sum, e) => sum + e.files) - deleteItemsFailed;
    return DeleteItemsResult(
      applied: !dryRun,
      mode: mode,
      entries: entries,
      warnings: warnings,
      trashed: mode == 'permanent' ? 0 : went,
      deleted: mode == 'permanent' ? went : 0,
      failed: dryRun ? 0 : deleteItemsFailed,
    );
  }

  /// The files [getItemFiles] answers and [deleteItemFiles] removes from,
  /// by item pid.
  final Map<String, List<ItemFile>> itemFilesByPid = {};

  /// Thrown by [getItemFiles] when set.
  WaxDeckApiException? itemFilesError;

  @override
  Future<List<ItemFile>> getItemFiles(String pid) async {
    final error = itemFilesError;
    if (error != null) throw error;
    return itemFilesByPid[pid] ?? const [];
  }

  final List<({String pid, List<String> filePids, String? mode, bool dryRun})>
  deleteItemFilesCalls = [];

  /// Decides per call whether [deleteItemFiles] refuses, and with what;
  /// the call is recorded either way.
  WaxDeckApiException? Function(List<String> filePids, bool dryRun)?
  deleteItemFilesRefusal;

  @override
  Future<DeleteItemsResult> deleteItemFiles({
    required String pid,
    required List<String> filePids,
    String? mode,
    bool dryRun = false,
  }) async {
    final error = deleteItemsError;
    if (error != null) throw error;
    deleteItemFilesCalls.add((
      pid: pid,
      filePids: filePids,
      mode: mode,
      dryRun: dryRun,
    ));
    final refusal = deleteItemFilesRefusal?.call(filePids, dryRun);
    if (refusal != null) throw refusal;
    final files = itemFilesByPid[pid] ?? const <ItemFile>[];
    final going = [
      for (final f in files)
        if (filePids.contains(f.filePid))
          DeletePlanFile(
            filePid: f.filePid,
            name: f.name,
            sizeBytes: f.sizeBytes,
            role: f.role,
          ),
    ];
    if (!dryRun) {
      itemFilesByPid[pid] = [
        for (final f in files)
          if (!filePids.contains(f.filePid)) f,
      ];
    }
    return _deleteResult(mode ?? 'trash', dryRun, [
      DeletePlanEntry(
        pid: pid,
        files: going.length,
        bytes: going.fold(0, (sum, f) => sum + (f.sizeBytes ?? 0)),
        fileList: going,
        itemSurvives: files.any((f) => !filePids.contains(f.filePid)),
      ),
    ], const []);
  }
}
