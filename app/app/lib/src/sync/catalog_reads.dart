import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../admin/admin_providers.dart';
import '../artwork/artwork_providers.dart';
import '../books/book_screen.dart';
import '../books/books_controller.dart';
import '../books/series_controller.dart';
import '../books/series_merge.dart';
import '../connect/connect_providers.dart';
import '../discovery/track_list_screen.dart';
import '../downloads/downloads_controller.dart';
import '../health/health_controller.dart';
import '../home/home_shelves.dart';
import '../metadata/entity_editor_screen.dart';
import '../metadata/metadata_controller.dart';
import '../music/album_detail.dart';
import '../music/artist_screen.dart';
import '../music/entity_facts.dart';
import '../music/music_controllers.dart';
import '../player/lyrics.dart';
import '../playlists/playlists_controller.dart';
import '../podcasts/podcast_shelves.dart';
import '../podcasts/podcasts_controller.dart';
import '../review/review_controller.dart';
import '../search/search_controller.dart';
import '../sharing/shares_controller.dart';
import '../stats/stats_controller.dart';
import '../uploads/uploads_controller.dart';
import 'refresh_in_place.dart';
import 'refresh_pacing.dart';

export 'refresh_in_place.dart' show CatalogRefresh;

/// Every read of the catalog a screen can hold open, in one place: what
/// a catalog change makes stale, whoever made it. The server's hint
/// sweeps it through the binder's pacer, and a write made on this device
/// sweeps it at once.
///
/// The plain providers, invalidated as themselves.
final List<ProviderBase<Object?>> catalogReadProviders =
    <ProviderBase<Object?>>[
      // The home shelves are all catalog reads: what was added, what is
      // sealed, what is worth going back to. A scan lands on every one
      // of them at once. The probe is not here; the binder asks it while
      // it reads empty, and once a run of changes goes quiet.
      ...homeCatalogShelfProviders,
      // The music hub's shelves are the same reads scoped to one medium.
      ...musicShelfProviders,
      booksProvider,
      // The series a book's tags name are a catalog fact too, and the
      // books hub stays mounted as a shell branch - so without this a
      // scan that lands a new series leaves the shelf drawing the old
      // set until the app is relaunched.
      bookSeriesProvider,
      bookSeriesShelfProvider,
      bookSeriesCountProvider,
      // What is downloaded is local, but who each row is comes from the
      // mirror, so a retitled item has to reach an open manager.
      downloadsProvider,
      // A feed refresh that adds episodes is a catalog change, and the
      // hub's shelves are the surface that is about what just arrived.
      upNextEpisodesProvider,
      latestEpisodesProvider,
      // The count a show's tile draws is on its subscription row, and
      // only a subscription changed here is reported on the user topic:
      // episodes the server fetched on its own schedule are not.
      subscriptionsProvider,
      // Kept for the session and keyed on the query alone, so without
      // this a search asked again answers from before the change. With
      // nobody on the search screen the sweep only marks it.
      searchResultsProvider,
      // Kept for the session too, and what a delete moves out of every
      // listing is what this one gains.
      trashProvider,
      // What plays on the caller's other devices, each entry named from
      // the catalog when the list is read.
      playbackSessionsProvider,
    ];

/// The families, applied per live instance.
final List<Family> catalogReadFamilies = <Family>[
  // Shows and episodes are catalog entities too: a server-side fetch
  // flipping an episode to downloaded must reach an open show screen.
  podcastDetailProvider,
  episodeDetailProvider,
  // A catalog change can shift any smart playlist's evaluation.
  playlistDetailProvider,
  // Applied review decisions and enrichment rewrite item metadata
  // server-side; an open editor must refetch what it shows.
  metadataControllerProvider,
  // An open series screen is a catalog read like a show's, and so is a
  // book's own: a series merge and a kind change both move it.
  bookSeriesDetailProvider,
  bookDetailProvider,
  // Where the caller left off names its chapter, which an edit of the
  // book's chapters renames.
  bookResumeProvider,
  // The hubs' tile counts, which a scan or an import moves.
  musicIndexCountProvider,
  // Every drilled listing (an artist's page, an album's tracks, a genre
  // or year bucket, the tracks index) and every index of buckets. A page
  // under a pushed editor stays mounted, so leaving and coming back is
  // not what refreshes it.
  ...catalogPagedFamilies,
  // An album's header and editor, and the overrides curated on it.
  albumDetailProvider,
  albumCurationProvider,
  // An artist page's own reads: the entity's name, the albums it
  // appears on, the art its header draws.
  entityCardProvider,
  appearsOnProvider,
  itemArtRolesProvider,
  // One item's facts, for the sheet and an album's release line, and
  // the files the sheet lists under them.
  itemDetailProvider,
  itemFilesProvider,
  // The words the player draws for what is playing, which the item's
  // editor writes.
  lyricsProvider,
  // The artist and release-group editors' stored fields. A field being
  // typed in outranks the refetch, as in the item editor.
  entityCurationProvider,
  // A mix or a similar-tracks answer, pushed as a list of its own: its
  // rows, looked up again.
  trackListRowsProvider,
  // A review entry names, for each file that duplicates the library,
  // the item it duplicates as the catalog has it when read.
  reviewEntryProvider,
];

/// Those of [catalogReadFamilies] that page: each refreshes in place, to
/// the depth the sweep tells it.
final List<Family> catalogPagedFamilies = <Family>[
  musicItemsProvider,
  musicIndexProvider,
  // A show's episodes, which a feed refresh adds to at the head.
  episodesProvider,
];

/// Reads no pass of a scan asks for: a write made here does at once,
/// being one read of each, and the server's hints do once a run of them
/// goes quiet. Either the read costs the server a walk of the whole
/// catalog or of the caller's whole listening, or it is a paged list a
/// pass would read through its loaded extent, a request a page.
final List<ProviderBase<Object?>> catalogQuietReads = <ProviderBase<Object?>>[
  // The health screen's groups, kept for the session. A merge, a rename
  // onto a name another entity has and a delete each move them.
  duplicatesProvider,
  upgradesProvider,
  // The stats screen's ranking, kept for the session: every listen in
  // its range, grouped under names and covers the catalog gives now.
  topListProvider,
  // The log of what played, each row under its item's title and artist
  // as the catalog has them when the page is read. It, the share links
  // and the uploads refresh in place.
  listenLogProvider,
  // Share links, each under its target's title as it is when read.
  sharesProvider,
  adminSharesProvider,
  // Home's mixes, seeded by the caller's top genres and artists: two
  // top lists.
  mixCardsProvider,
  // The uploads being staged, each naming the item it duplicates as the
  // catalog has it when the page is read.
  uploadsProvider,
];

/// The families asked on the same terms.
final List<Family> catalogQuietFamilies = <Family>[
  // A year's recap ranks artists, tracks and shows by their names now.
  yearInReviewProvider,
  serverYearInReviewProvider,
];

/// [catalogQuietReads] and [catalogQuietFamilies] as a fan-out, shared
/// by a write and the session's passes so either applies what the other
/// left deferred.
final catalogQuietFanOutProvider = Provider<InvalidationFanOut>((ref) {
  final container = ref.container;
  return InvalidationFanOut(
    container: container,
    firstBuilds: container.observers
        .whereType<FirstBuildObserver>()
        .firstOrNull,
    providers: catalogQuietReads,
    families: catalogQuietFamilies,
    failed: ref.watch(failedRefreshesProvider),
  );
});

/// The catalog topic's fan-out over the registry above.
///
/// [sweep] and [sweepPaged] apply at once, whoever calls: pacing is the
/// caller's. Each answers whether everything was applied; false means a
/// first build in flight was left alone and the matching retry is owed,
/// which a pacer schedules and a caller outside one has to arrange.
class CatalogFanOut {
  CatalogFanOut({
    required ProviderContainer container,
    required OwedDepths owed,
    FailedRefreshes? failed,
    FirstBuildObserver? firstBuilds,
    void Function()? prelude,
  }) : _reads = InvalidationFanOut(
         container: container,
         providers: catalogReadProviders,
         families: catalogReadFamilies,
         pagedFamilies: catalogPagedFamilies,
         owed: owed,
         failed: failed,
         firstBuilds: firstBuilds,
         prelude: prelude,
       ),
       _paged = InvalidationFanOut(
         container: container,
         families: catalogPagedFamilies,
         pagedFamilies: catalogPagedFamilies,
         owed: owed,
         firstBuilds: firstBuilds,
       );

  final InvalidationFanOut _reads;

  /// Apart from [_reads] because a sweep recomputes what it deferred
  /// from scratch: one fan-out for both would have the trailing pass
  /// drop the retry a full pass still owes a plain provider.
  final InvalidationFanOut _paged;

  /// Invalidates every registered read, each paged listing owed [depth].
  bool sweep(CatalogRefresh depth) => _reads.sweep(depth);

  /// Applies what the last [sweep] deferred.
  bool retry() => _reads.retry();

  /// The registered reads that are not current alone: in error, or a
  /// paged listing whose last refresh failed.
  bool sweepUnhealthy() => _reads.sweepUnhealthy();

  /// The paged listings alone, owed [depth]: the trailing pass of a run
  /// of hints, for a change past what a head pass reads.
  bool sweepPaged(CatalogRefresh depth) => _paged.sweep(depth);

  /// Applies what the last [sweepPaged] deferred.
  bool retryPaged() => _paged.retry();
}

final catalogFanOutProvider = Provider<CatalogFanOut>((ref) {
  final container = ref.container;
  return CatalogFanOut(
    container: container,
    owed: ref.watch(owedDepthsProvider),
    failed: ref.watch(failedRefreshesProvider),
    // The ledger of in-flight first builds, registered on the root
    // container in main.dart. Absent (a test container that did not
    // register one), the fan-out invalidates unconditionally.
    firstBuilds: container.observers
        .whereType<FirstBuildObserver>()
        .firstOrNull,
    // Covers appear as part of the catalog changing - a scan reading
    // embedded art, enrichment landing, another device writing one -
    // and the store has been remembering which ones answered 404 so it
    // can draw the monogram without asking again. Those answers are
    // exactly what a catalog change can falsify, and this is the only
    // signal that sees it: the cover editors call `evict`, and nothing
    // else does.
    prelude: () => container.read(artworkStoreProvider).forgetAbsences(),
  );
});
