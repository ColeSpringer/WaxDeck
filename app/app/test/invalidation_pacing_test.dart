import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/admin/admin_providers.dart';
import 'package:waxdeck/src/artwork/artwork_palette.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/artwork/artwork_store.dart';
import 'package:waxdeck/src/books/book_screen.dart';
import 'package:waxdeck/src/books/books_controller.dart';
import 'package:waxdeck/src/books/series_controller.dart';
import 'package:waxdeck/src/discovery/track_list_screen.dart';
import 'package:waxdeck/src/health/health_controller.dart';
import 'package:waxdeck/src/home/home_shelves.dart';
import 'package:waxdeck/src/metadata/entity_editor_screen.dart';
import 'package:waxdeck/src/metadata/metadata_controller.dart';
import 'package:waxdeck/src/music/album_detail.dart';
import 'package:waxdeck/src/music/artist_screen.dart';
import 'package:waxdeck/src/music/entity_facts.dart';
import 'package:waxdeck/src/music/listing_screen.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/player/lyrics.dart';
import 'package:waxdeck/src/playlists/playlist_screen.dart';
import 'package:waxdeck/src/playlists/playlists_controller.dart';
import 'package:waxdeck/src/podcasts/podcasts_controller.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/review/review_controller.dart';
import 'package:waxdeck/src/search/search_controller.dart';
import 'package:waxdeck/src/settings/prefs_controller.dart';
import 'package:waxdeck/src/sharing/shares_controller.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/stats/stats_controller.dart';
import 'package:waxdeck/src/sync/catalog_reads.dart';
import 'package:waxdeck/src/sync/catalog_writes.dart';
import 'package:waxdeck/src/sync/refresh_pacing.dart';
import 'package:waxdeck/src/sync/server_event_bus.dart';
import 'package:waxdeck/src/sync/sync_binder.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck/src/uploads/uploads_controller.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

// The starvation the pacer closes: a live invalidation used to rebuild
// every controller its topic touched, and a rebuild landing on a
// provider still doing its *first* build abandons work it cannot
// cancel, so hints arriving faster than a build completes held the
// screen on its skeleton for as long as they kept coming. The pacer
// bounds how often the fan-out runs; the ledger and the fan-out below
// keep a run from touching an in-flight first build at all, so even a
// build slower than the pacer's window finishes and renders.

const _track = ItemSummary(
  pid: 'tr-01JZX5N8QW3F4V9T2B7KD3M9R6',
  mediaType: MediaType.music,
  title: 'Prancing Pony Blues',
  artist: 'The Bree Trio',
  durationMs: 214000,
);

/// Holds one playlist's `getPlaylist` behind [gate], so a test can keep
/// that detail's first build in flight for exactly as long as it needs
/// while every other playlist stays readable. Completed detail builds
/// are visible through the base fake's `playlistItemPageCalls`.
class _GatedRepository extends FakeRepository {
  _GatedRepository({super.items});

  Completer<void>? gate;
  String? gatedPid;
  var listingReads = 0;

  @override
  Future<Playlist> getPlaylist(String pid) async {
    final g = gate;
    if (g != null && pid == gatedPid) await g.future;
    return super.getPlaylist(pid);
  }

  @override
  Future<PlaylistPage> listPlaylists({
    String? cursor,
    int? limit,
    String? containsItem,
  }) async {
    listingReads++;
    return super.listPlaylists(
      cursor: cursor,
      limit: limit,
      containsItem: containsItem,
    );
  }
}

/// Reads slow enough that a detail's first build outlasts the pacer's
/// window, which is the case pacing alone could not save.
class _SlowRepository extends FakeRepository {
  _SlowRepository({super.items});

  static const latency = Duration(milliseconds: 700);

  @override
  Future<Playlist> getPlaylist(String pid) async {
    await Future<void>.delayed(latency);
    return super.getPlaylist(pid);
  }

  @override
  Future<PlaylistItemsPage> listPlaylistItems(
    String pid, {
    String? cursor,
    int? limit,
  }) async {
    await Future<void>.delayed(latency);
    return super.listPlaylistItems(pid, cursor: cursor, limit: limit);
  }
}

/// The tracks index: the listing that pages the whole library.
const MusicListing _tracks = (
  dimension: null,
  segment: '',
  domain: BrowseDomain.music,
);

const _page = MusicItemsController.pageSize;

/// A track pid that sorts by [at], with room below the first for rows
/// that arrive at the head.
String _pid(int at) => 'tr-${(at + 1000).toString().padLeft(7, '0')}';

ItemSummary _row(int at, {String? title}) =>
    testItem(_pid(at), title: title ?? 'Track $at');

/// One instance of each family the registry holds, by family.
Map<Family, ProviderBase<Object?>> _oneOfEachFamily() {
  const artist = 'ar-01JZX5N8QW3F4V9T2B7KDREG01';
  const album = 'al-01JZX5N8QW3F4V9T2B7KDREG01';
  const track = 'tr-01JZX5N8QW3F4V9T2B7KDREG01';
  return {
    podcastDetailProvider: podcastDetailProvider('pc-1'),
    episodesProvider: episodesProvider('pc-1'),
    episodeDetailProvider: episodeDetailProvider('ep-1'),
    playlistDetailProvider: playlistDetailProvider('pl-1'),
    metadataControllerProvider: metadataControllerProvider(track),
    bookSeriesDetailProvider: bookSeriesDetailProvider('se-1'),
    bookDetailProvider: bookDetailProvider('bk-1'),
    bookResumeProvider: bookResumeProvider('bk-1'),
    musicIndexCountProvider: musicIndexCountProvider((
      dimension: MusicDimension.artists,
      domain: BrowseDomain.music,
    )),
    musicItemsProvider: musicItemsProvider(_tracks),
    musicIndexProvider: musicIndexProvider((
      dimension: MusicDimension.artists,
      sort: FacetSort.label,
      domain: BrowseDomain.music,
    )),
    albumDetailProvider: albumDetailProvider(album),
    albumCurationProvider: albumCurationProvider(album),
    entityCardProvider: entityCardProvider(artist),
    appearsOnProvider: appearsOnProvider(artist),
    itemArtRolesProvider: itemArtRolesProvider(track),
    itemDetailProvider: itemDetailProvider(track),
    itemFilesProvider: itemFilesProvider(track),
    lyricsProvider: lyricsProvider(track),
    entityCurationProvider: entityCurationProvider((
      type: 'artist',
      pid: artist,
    )),
    trackListRowsProvider: trackListRowsProvider(_answer),
    reviewEntryProvider: reviewEntryProvider('rv-1'),
  };
}

/// A computed list as it was handed to the screen that shows it.
const _answer = <ItemSummary>[_track];

/// Every read asked once a run of changes goes quiet: the plain ones,
/// and one instance of each family.
List<ProviderBase<Object?>> _quietReads() {
  final open = <Family, ProviderBase<Object?>>{
    yearInReviewProvider: yearInReviewProvider(2026),
    serverYearInReviewProvider: serverYearInReviewProvider(2026),
  };
  expect(
    open.keys.toSet(),
    catalogQuietFamilies.toSet(),
    reason: 'a family that joins or leaves the quiet reads is opened here',
  );
  return [...catalogQuietReads, ...open.values];
}

/// A tracks listing read as the server reads it: pages cut by key, so a
/// row that arrives at the head moves no cursor after it. Counts its
/// requests, and holds, slows or fails them.
class _Library extends FakeRepository {
  _Library(int rows) : tracks = [for (var i = 0; i < rows; i++) _row(i)];

  /// The listing, in order.
  List<ItemSummary> tracks;

  /// The cursor each request asked from, in call order.
  final requests = <String?>[];

  /// How long each request takes.
  Duration? latency;

  /// Held open, every request waits on it.
  Completer<void>? gate;

  /// Thrown by every request while set.
  WaxDeckApiException? failure;

  /// Called as each request is made.
  void Function()? asked;

  var _inFlight = 0;

  /// The most requests ever out at once.
  var widest = 0;

  @override
  Future<ItemPage> listItems({
    MediaType? mediaType,
    String? facet,
    String? facetKey,
    String? cursor,
    int? limit,
  }) async {
    requests.add(cursor);
    asked?.call();
    widest = widest > ++_inFlight ? widest : _inFlight;
    try {
      final wait = latency;
      if (wait != null) await Future<void>.delayed(wait);
      await gate?.future;
      final error = failure;
      if (error != null) throw error;
      final rest = cursor == null
          ? tracks
          : tracks.where((t) => t.pid.compareTo(cursor) > 0).toList();
      final size = limit ?? 100;
      final page = rest.take(size).toList();
      return ItemPage(
        items: page,
        nextCursor: rest.length > size ? page.last.pid : null,
      );
    } finally {
      _inFlight--;
    }
  }

  /// A catalog change for the sync engine's next pull to find.
  void changeCatalog() => catalogPages.add(
    CatalogSyncPage(
      entries: [
        CatalogSyncEntry(
          op: 'upsert',
          pid: tracks.first.pid,
          item: tracks.first,
        ),
      ],
      nextSince: 'since-${catalogPages.length}',
    ),
  );
}

/// Counts the reads of the health lists that audit the catalog.
class _Audits extends _Library {
  _Audits(super.rows);

  var duplicateAsks = 0;

  (int, int) get asks => (duplicateAsks, listUpgradesCalls);

  /// Held open, the duplicates read waits on it.
  Completer<void>? auditGate;

  @override
  Future<List<DuplicateGroup>> listDuplicates() async {
    duplicateAsks++;
    await auditGate?.future;
    return super.listDuplicates();
  }
}

List<String> _pids(Iterable<ItemSummary> items) => [
  for (final item in items) item.pid,
];

/// The tracks index held open over [repo], as a mounted screen holds it,
/// with [pages] pages loaded.
Future<ProviderContainer> _holdTracks(_Library repo, {int pages = 1}) async {
  final container = appContainer(repo: repo);
  final held = container.listen(musicItemsProvider(_tracks), (_, _) {});
  addTearDown(held.close);
  await container.read(musicItemsProvider(_tracks).future);
  for (var i = 1; i < pages; i++) {
    await container.read(musicItemsProvider(_tracks).notifier).loadMore();
  }
  repo.requests.clear();
  return container;
}

MusicItemsState _held(ProviderContainer container) =>
    container.read(musicItemsProvider(_tracks)).requireValue;

/// A refresh under way, landed. Not the provider's future: a page that
/// lands while a refresh waits behind it completes that first.
Future<MusicItemsState> _landed(ProviderContainer container) async {
  await container.pump();
  await pumpEventQueue();
  return _held(container);
}

/// A bound session: its container, its engine, and the binder's own
/// subscription, which closing ends as leaving the signed-in tree does.
typedef _Session = ({
  ProviderContainer container,
  SyncEngine sync,
  ProviderSubscription<void> binder,
});

/// The binder over a sync engine's mirror, so a catalog hint is the
/// engine's own: a pull that found a change.
///
/// Over [link] its socket comes up, and a frame said on it is the
/// server's.
_Session _bound(
  FakeRepository repo, {
  List<ProviderObserver>? observers,
  FakeLink? link,
  ArtworkStore? artwork,
}) {
  final db = inMemoryMirrorDatabase();
  addTearDown(db.close);
  final downloads = FakeDownloads();
  addTearDown(downloads.dispose);
  final sync = SyncEngine(
    db: db,
    repository: repo,
    channelFactory: link?.factory ?? deadChannelFactory(),
  );
  addTearDown(sync.dispose);
  final container = appContainer(
    repo: repo,
    mirror: db,
    downloads: downloads,
    sync: sync,
    artwork: artwork,
    observers: observers,
  );
  final binder = container.listen(syncBinderProvider, (_, _) {});
  return (container: container, sync: sync, binder: binder);
}

/// A catalog invalidation said on [link]'s socket, naming [pids] when
/// given or carrying the [unnamed] marker, and the pull it prompts
/// landed.
Future<void> _frame(
  WidgetTester tester,
  _Session s,
  FakeLink link, [
  List<String>? pids,
  bool? unnamed,
]) async {
  link.attempts.last.onFrame(
    jsonEncode({
      'type': 'invalidate',
      'topic': 'catalog',
      'pids': ?pids,
      'unnamed': ?unnamed,
    }),
  );
  await s.sync.beforeSync(() async {});
  await tester.pump(_tick);
}

/// Long enough for a rebuild an invalidation scheduled to start, and for
/// reads that answer at once to land.
const _tick = Duration(milliseconds: 1);

/// Ends a bound session inside the test: its pacers and the engine's
/// reconnect are timers.
Future<void> _unbind(WidgetTester tester, ProviderContainer container) async {
  await tester.pump(const Duration(seconds: 1));
  container.dispose();
  await tester.pump();
}

/// Counts the review queue's page reads.
class _ReviewQueue extends FakeRepository {
  /// The cursor each read asked from, in call order.
  final cursors = <String?>[];

  @override
  Future<ReviewEntryPage> listReviewQueue({
    String? status,
    String? cursor,
    int? limit,
  }) {
    cursors.add(cursor);
    return super.listReviewQueue(status: status, cursor: cursor, limit: limit);
  }
}

/// Holds every facet read from the head of a dimension while [headGate]
/// is set; a read from a letter answers at once.
class _HeldHead extends FakeRepository {
  Completer<void>? headGate;

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
    final page = super.listFacets(
      dimension,
      sort: sort,
      cursor: cursor,
      startsAt: startsAt,
      facet: facet,
      facetKey: facetKey,
      limit: limit,
    );
    if (startsAt == null) await headGate?.future;
    return page;
  }
}

/// The account's preferences, as a test sets them.
class _Prefs extends PrefsController {
  @override
  Future<Prefs> build() async => const Prefs();

  void showUnknown(bool shown) =>
      state = AsyncData(Prefs(browseShowUnknown: shown));
}

/// A store whose eviction fails past its first await, as a file drop
/// can.
class _StuckArtwork extends FakeArtworkStore {
  @override
  Future<void> evict(String artUrl) async {
    await null;
    throw StateError('disk full');
  }
}

/// Which providers were invalidated, from the hook every invalidation
/// runs.
final class _Invalidations extends ProviderObserver {
  final seen = <ProviderBase<Object?>>{};

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    seen.add(context.provider);
  }
}

/// A server whose tracks listing answers [rows], over the app's real
/// client: the repository is the client, so building it again is what a
/// change of server or account does to every read under it.
class _TracksServer implements HttpClientAdapter {
  List<ItemSummary> rows = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path.replaceFirst('/api/v1', '');
    final query = options.uri.queryParameters;
    final (status, body) = switch ((options.method, path)) {
      ('GET', '/library/items') => (200, _itemsPage(query)),
      _ => (404, {'code': 'not-found', 'message': 'not found'}),
    };
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  Map<String, Object?> _itemsPage(Map<String, String> query) {
    final cursor = query['cursor'];
    final size = int.parse(query['limit'] ?? '100');
    final rest = cursor == null
        ? rows
        : rows.where((t) => t.pid.compareTo(cursor) > 0).toList();
    final page = rest.take(size).toList();
    return {
      'items': [
        for (final item in page)
          {
            'pid': item.pid,
            'mediaType': 'music',
            'title': item.title,
            'durationMs': item.durationMs,
          },
      ],
      if (rest.length > size) 'nextCursor': page.last.pid,
    };
  }

  @override
  void close({bool force = false}) {}
}

/// The caller's upload sessions, paged by position as the server pages
/// them, with the cursor each read asked from.
class _PagedUploads extends FakeRepository {
  _PagedUploads(int count)
    : sessions = [
        for (var i = 0; i < count; i++)
          UploadSession(
            id: 'up-$i',
            fileName: 'take-$i.flac',
            sizeBytes: 1,
            receivedBytes: 1,
            idle: Duration.zero,
            mediaType: MediaType.music,
            state: 'staged',
            createdAt: DateTime.utc(2026, 7, 20),
          ),
      ];

  final List<UploadSession> sessions;
  final cursors = <String?>[];

  @override
  Future<UploadPage> listUploads({String? cursor, int? limit}) async {
    cursors.add(cursor);
    final start = cursor == null ? 0 : int.parse(cursor);
    final end = (start + (limit ?? 50)).clamp(0, sessions.length);
    return UploadPage(
      uploads: sessions.sublist(start, end),
      nextCursor: end < sessions.length ? '$end' : null,
    );
  }
}

void main() {
  group('QuietRefresh', () {
    testWidgets('runs once a run of hints goes quiet, not during it', (
      tester,
    ) async {
      var runs = 0;
      final quiet = QuietRefresh(
        fanOut: () {
          runs++;
          return true;
        },
        quiet: const Duration(seconds: 5),
      );

      for (var i = 0; i < 10; i++) {
        quiet.hint();
        await tester.pump(const Duration(seconds: 1));
      }
      expect(runs, 0, reason: 'the run is still going');

      await tester.pump(const Duration(seconds: 5));
      expect(runs, 1);
      await tester.pump(const Duration(seconds: 30));
      expect(runs, 1, reason: 'once a run, not once a hint');
      quiet.dispose();
    });

    QuietRefresh timed(List<Duration> runs, WidgetTester tester) {
      final started = tester.binding.clock.now();
      return QuietRefresh(
        fanOut: () {
          runs.add(tester.binding.clock.now().difference(started));
          return true;
        },
        quiet: const Duration(seconds: 5),
      );
    }

    testWidgets('a run that pauses runs once, at the pause', (tester) async {
      final runs = <Duration>[];
      final quiet = timed(runs, tester);

      // A hint a second for twenty seconds, then nothing.
      for (var i = 0; i < 20; i++) {
        quiet.hint();
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(minutes: 2));

      expect(runs, [const Duration(seconds: 24)]);
      quiet.dispose();
    });

    testWidgets('a run that never pauses runs six quiet spells after its '
        'first hint, every six after that, and at the pause it ends in', (
      tester,
    ) async {
      final runs = <Duration>[];
      final quiet = timed(runs, tester);

      // A hint a second for seventy seconds.
      for (var i = 0; i < 70; i++) {
        quiet.hint();
        await tester.pump(const Duration(seconds: 1));
      }
      expect(runs, [const Duration(seconds: 30), const Duration(seconds: 60)]);

      await tester.pump(const Duration(minutes: 2));
      expect(runs, [
        const Duration(seconds: 30),
        const Duration(seconds: 60),
        const Duration(seconds: 74),
      ], reason: 'the hints after the last ceiling, at the pause');

      // The next run counts from its own first hint, at 190 seconds.
      runs.clear();
      for (var i = 0; i < 30; i++) {
        quiet.hint();
        await tester.pump(const Duration(seconds: 1));
      }
      expect(runs, [const Duration(seconds: 220)]);
      quiet.dispose();
    });

    testWidgets('a pause with no hint since the ceiling runs nothing more', (
      tester,
    ) async {
      final runs = <Duration>[];
      final quiet = timed(runs, tester);

      // Hints from 0 to 26 seconds, and one at 29.5.
      for (var i = 0; i < 27; i++) {
        quiet.hint();
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 2500));
      quiet.hint();
      await tester.pump(const Duration(minutes: 2));

      expect(runs, [const Duration(seconds: 30)]);
      quiet.dispose();
    });

    testWidgets('what a run left owed is applied a quiet spell later', (
      tester,
    ) async {
      var retries = 0;
      var owed = true;
      final quiet = QuietRefresh(
        fanOut: () => !owed,
        retry: () {
          retries++;
          return !owed;
        },
        quiet: const Duration(seconds: 5),
      );

      quiet.hint();
      await tester.pump(const Duration(seconds: 5));
      expect(retries, 0);
      await tester.pump(const Duration(seconds: 5));
      expect(retries, 1, reason: 'still owed, so asked again');

      owed = false;
      await tester.pump(const Duration(seconds: 5));
      expect(retries, 2);
      await tester.pump(const Duration(seconds: 30));
      expect(retries, 2, reason: 'nothing left to owe');
      quiet.dispose();
    });

    testWidgets('a disposed one runs nothing', (tester) async {
      var runs = 0;
      final quiet = QuietRefresh(
        fanOut: () {
          runs++;
          return true;
        },
        quiet: const Duration(seconds: 5),
      );

      quiet.hint();
      quiet.dispose();
      quiet.hint();
      await tester.pump(const Duration(seconds: 30));
      expect(runs, 0);
    });
  });

  group('PacedRefresh', () {
    testWidgets('the first hint after a quiet spell fans out at once', (
      tester,
    ) async {
      var runs = 0;
      final paced = PacedRefresh(
        fanOut: () {
          runs++;
          return true;
        },
      );

      paced.hint();
      expect(runs, 1, reason: 'a lone change still lands immediately');
      paced.dispose();
    });

    testWidgets('hints inside the window collapse into one at its end', (
      tester,
    ) async {
      var runs = 0;
      final paced = PacedRefresh(
        fanOut: () {
          runs++;
          return true;
        },
      );

      paced.hint();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        paced.hint();
      }
      expect(runs, 1, reason: 'the window is still open');

      await tester.pump(const Duration(seconds: 1));
      expect(runs, 2, reason: 'the ones that arrived during it, as one');

      // And nothing more: the collapsed fan-out already covered them.
      await tester.pump(const Duration(seconds: 5));
      expect(runs, 2);
      paced.dispose();
    });

    testWidgets('a sustained stream costs one fan-out per window', (
      tester,
    ) async {
      var runs = 0;
      final paced = PacedRefresh(
        fanOut: () {
          runs++;
          return true;
        },
      );

      // The server's own ceiling: a hint per topic per 250 ms, and both
      // topics reach the same controllers.
      for (var tick = 0; tick < 40; tick++) {
        paced.hint();
        await tester.pump(const Duration(milliseconds: 125));
      }
      expect(runs, 6, reason: '5 seconds of hints, one fan-out per second');
      paced.dispose();
    });

    testWidgets('an incomplete run retries at the window, not before', (
      tester,
    ) async {
      var sweeps = 0;
      var retries = 0;
      var complete = false;
      final paced = PacedRefresh(
        fanOut: () {
          sweeps++;
          return complete;
        },
        retry: () {
          retries++;
          return complete;
        },
      );

      paced.hint();
      expect(sweeps, 1);
      expect(retries, 0);

      // Still owed at the first window's end, applied at the second.
      await tester.pump(const Duration(seconds: 1));
      expect(retries, 1, reason: 'the deferred part is re-attempted');
      complete = true;
      await tester.pump(const Duration(seconds: 1));
      expect(retries, 2, reason: 'retries continue until one completes');
      await tester.pump(const Duration(seconds: 5));
      expect(retries, 2, reason: 'a complete retry ends the loop');
      expect(sweeps, 1, reason: 'no hint arrived, so no full run');
      paced.dispose();
    });

    testWidgets('a hint during the cooldown outranks the owed retry', (
      tester,
    ) async {
      var sweeps = 0;
      var retries = 0;
      final paced = PacedRefresh(
        fanOut: () {
          sweeps++;
          return sweeps > 1;
        },
        retry: () {
          retries++;
          return true;
        },
      );

      paced.hint();
      paced.hint();
      await tester.pump(const Duration(seconds: 1));
      expect(sweeps, 2, reason: 'the full run covers what the retry would');
      expect(retries, 0);
      await tester.pump(const Duration(seconds: 5));
      expect(retries, 0, reason: 'the full run recomputed what was owed');
      paced.dispose();
    });

    testWidgets('disposal drops the pending retry and hint alike', (
      tester,
    ) async {
      var runs = 0;
      final paced = PacedRefresh(
        fanOut: () {
          runs++;
          return false;
        },
      );

      paced.hint();
      paced.hint();
      paced.dispose();
      await tester.pump(const Duration(seconds: 5));
      expect(runs, 1, reason: 'the trailing work belonged to a live session');
    });

    testWidgets('a hint after disposal is a no-op', (tester) async {
      var runs = 0;
      final paced = PacedRefresh(
        fanOut: () {
          runs++;
          return true;
        },
      );

      paced.dispose();
      // The web transport's connect future can resolve after stop() and
      // deliver a hint to a pacer whose session is already gone.
      paced.hint();
      expect(runs, 0, reason: 'a dead pacer runs nothing');
      await tester.pump(const Duration(seconds: 5));
      expect(runs, 0, reason: 'and schedules nothing either');
    });

    testWidgets('a throwing run keeps the window and the hint', (tester) async {
      var runs = 0;
      var explode = true;
      final paced = PacedRefresh(
        fanOut: () {
          runs++;
          if (explode) throw StateError('fan-out bug');
          return true;
        },
      );

      expect(paced.hint, throwsStateError);
      expect(runs, 1, reason: 'the exception surfaces to the caller');

      // No second hint: the thrown one was not consumed, so it re-runs
      // on its own at the window's end - a throw partway leaves an
      // unknown remainder, and a lost hint would stay lost until the
      // next unrelated change.
      explode = false;
      await tester.pump(const Duration(seconds: 1));
      expect(runs, 2, reason: 'the broken run did not consume the hint');
      await tester.pump(const Duration(seconds: 5));
      expect(runs, 2, reason: 'and the clean re-run did');
      paced.dispose();
    });

    testWidgets('a throwing retry escalates to a full run', (tester) async {
      var sweeps = 0;
      var retries = 0;
      final paced = PacedRefresh(
        fanOut: () {
          sweeps++;
          return sweeps > 1;
        },
        retry: () {
          retries++;
          throw StateError('retry bug');
        },
      );

      // The timers fire in the zone the first hint created them in, so
      // guarding the hint is what catches the retry's timer-fired throw.
      final surfaced = <Object>[];
      runZonedGuarded(paced.hint, (error, _) => surfaced.add(error));
      expect(sweeps, 1, reason: 'the first sweep defers something');
      await tester.pump(const Duration(seconds: 1));
      expect(surfaced, [isA<StateError>()]);
      expect(retries, 1, reason: 'the retry ran and broke');
      // A broken retry's coverage is unknown, so the next window runs
      // the full sweep, which recomputes what is owed from scratch.
      await tester.pump(const Duration(seconds: 1));
      expect(sweeps, 2, reason: 'escalated to the full sweep');
      await tester.pump(const Duration(seconds: 5));
      expect(retries, 1);
      expect(sweeps, 2);
      paced.dispose();
    });

    PacedRefresh counting(List<Duration> runs, WidgetTester tester) {
      final started = tester.binding.clock.now();
      return PacedRefresh(
        fanOut: () {
          runs.add(tester.binding.clock.now().difference(started));
          return true;
        },
        window: const Duration(seconds: 5),
      );
    }

    testWidgets('a pass owed after a write runs on the echo, inside the '
        'window', (tester) async {
      final runs = <Duration>[];
      final paced = counting(runs, tester);

      paced.owe();
      expect(runs, isEmpty, reason: 'the write swept already, this instant');

      await tester.pump(const Duration(milliseconds: 300));
      paced.hint();
      expect(runs, [const Duration(milliseconds: 300)]);

      await tester.pump(const Duration(seconds: 20));
      expect(runs, hasLength(1), reason: 'one pass was owed');
      paced.dispose();
    });

    testWidgets('the echo runs the pass a write is owed, and a hint after it '
        'the hinted one', (tester) async {
      final runs = <String>[];
      final paced = PacedRefresh(
        fanOut: () {
          runs.add('hinted');
          return true;
        },
        owed: () {
          runs.add('owed');
          return true;
        },
        window: const Duration(seconds: 5),
      );

      paced.owe();
      await tester.pump(const Duration(milliseconds: 300));
      paced.hint();
      expect(runs, ['owed']);
      await tester.pump(const Duration(milliseconds: 100));
      paced.hint();
      await tester.pump(const Duration(seconds: 5));
      expect(runs, ['owed', 'hinted']);
      paced.dispose();
    });

    testWidgets('with no echo the owed pass runs at the end of the window', (
      tester,
    ) async {
      final runs = <Duration>[];
      final paced = counting(runs, tester);

      paced.owe();
      await tester.pump(const Duration(milliseconds: 4999));
      expect(runs, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(runs, [const Duration(seconds: 5)]);

      await tester.pump(const Duration(seconds: 20));
      expect(runs, hasLength(1));
      paced.dispose();
    });

    testWidgets('a hint after the echo waits for the window', (tester) async {
      final runs = <Duration>[];
      final paced = counting(runs, tester);

      paced.owe();
      await tester.pump(const Duration(milliseconds: 300));
      paced.hint();
      await tester.pump(const Duration(milliseconds: 100));
      paced.hint();
      expect(runs, hasLength(1), reason: 'paced as ever after the echo');

      await tester.pump(const Duration(milliseconds: 4900));
      expect(runs, [
        const Duration(milliseconds: 300),
        const Duration(milliseconds: 5300),
      ]);
      paced.dispose();
    });

    testWidgets('a write inside a window restarts it, and its echo does not '
        'wait', (tester) async {
      final runs = <Duration>[];
      final paced = counting(runs, tester);

      paced.hint();
      await tester.pump(const Duration(seconds: 4));
      paced.hint();
      paced.owe();
      await tester.pump(const Duration(seconds: 1));
      expect(runs, hasLength(1), reason: 'the write was a pass of its own');

      await tester.pump(const Duration(seconds: 3));
      paced.hint();
      expect(runs.last, const Duration(seconds: 8));

      paced.owe();
      await tester.pump(const Duration(seconds: 5));
      expect(runs, [
        Duration.zero,
        const Duration(seconds: 8),
        const Duration(seconds: 13),
      ]);
      paced.dispose();
    });

    testWidgets('two writes together owe one pass', (tester) async {
      final runs = <Duration>[];
      final paced = counting(runs, tester);

      paced.owe();
      paced.owe();
      await tester.pump(const Duration(seconds: 20));
      expect(runs, [const Duration(seconds: 5)]);
      paced.dispose();
    });

    testWidgets('a pass owed to a disposed pacer starts no timer', (
      tester,
    ) async {
      final runs = <Duration>[];
      final paced = counting(runs, tester)..dispose();

      // Not pumped: a timer started here outlives the test, which the
      // binding refuses.
      paced.owe();
      expect(runs, isEmpty);
    });

    testWidgets('a retry owed when a write lands is covered by the pass the '
        'write is owed', (tester) async {
      var sweeps = 0;
      var retries = 0;
      final paced = PacedRefresh(
        fanOut: () => ++sweeps > 1,
        retry: () {
          retries++;
          return true;
        },
      );

      paced.hint();
      expect(sweeps, 1, reason: 'the first sweep defers something');
      await tester.pump(const Duration(milliseconds: 500));
      paced.owe();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        (sweeps, retries),
        (1, 0),
        reason: 'the retry went with its window',
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect((sweeps, retries), (2, 0), reason: 'a full run, not the retry');
      await tester.pump(const Duration(seconds: 5));
      expect((sweeps, retries), (2, 0));
      paced.dispose();
    });

    testWidgets('an owed pass that throws is run again as an owed pass', (
      tester,
    ) async {
      final runs = <String>[];
      var explode = true;
      final paced = PacedRefresh(
        fanOut: () {
          runs.add('hinted');
          return true;
        },
        owed: () {
          runs.add('owed');
          if (explode) throw StateError('fan-out bug');
          return true;
        },
      );

      // The owed run is a timer's, fired in the zone that started it.
      final surfaced = <Object>[];
      runZonedGuarded(paced.owe, (error, _) => surfaced.add(error));
      await tester.pump(const Duration(seconds: 1));
      expect(runs, ['owed']);
      expect(surfaced, [isA<StateError>()]);

      explode = false;
      await tester.pump(const Duration(seconds: 1));
      expect(runs, ['owed', 'owed'], reason: 'still nothing follows it');
      await tester.pump(const Duration(seconds: 5));
      expect(runs, hasLength(2));
      paced.dispose();
    });

    testWidgets('a hint behind an owed pass that threw leaves the rerun an '
        'owed one', (tester) async {
      final runs = <String>[];
      var explode = true;
      final paced = PacedRefresh(
        fanOut: () {
          runs.add('hinted');
          return true;
        },
        owed: () {
          runs.add('owed');
          if (explode) throw StateError('fan-out bug');
          return true;
        },
      );

      runZonedGuarded(paced.owe, (_, _) {});
      await tester.pump(const Duration(seconds: 1));
      explode = false;
      paced.hint();
      expect(runs, ['owed'], reason: 'inside the window the throw kept');
      await tester.pump(const Duration(seconds: 1));
      expect(runs, ['owed', 'owed'], reason: 'it covers what the hint asks');
      paced.dispose();
    });
  });

  group('the catalog registry', () {
    testWidgets('a catalog hint invalidates one instance of every registered '
        'family', (tester) async {
      final open = _oneOfEachFamily();
      expect(
        open.keys.toSet(),
        catalogReadFamilies.toSet(),
        reason: 'a family that joins or leaves the registry is opened here',
      );

      final invalidations = _Invalidations();
      final repo = _Library(3);
      final s = _bound(repo, observers: [invalidations]);
      for (final read in [...open.values, ...catalogReadProviders]) {
        s.container.listen(read, (_, _) {});
      }
      // Past the engine's own start, so the hint below is the first of
      // a quiet spell and lands at once.
      await tester.pump(kCatalogRefreshWindow * 2);
      invalidations.seen.clear();

      repo.changeCatalog();
      await s.sync.pullCatalog();
      await tester.pump();

      expect(invalidations.seen, containsAll(open.values));
      expect(invalidations.seen, containsAll(catalogReadProviders));
      expect(catalogReadProviders, contains(searchResultsProvider));
      // A feed refresh the server runs lands episodes, and the count a
      // show's tile draws is on its subscription row.
      expect(catalogReadProviders, contains(subscriptionsProvider));
      await _unbind(tester, s.container);
    });
  });

  group('the reads asked once a run goes quiet', () {
    testWidgets('are none of them asked under a run of hints, and each '
        'once when the run goes quiet', (tester) async {
      final invalidations = _Invalidations();
      final repo = _Library(3);
      final s = _bound(repo, observers: [invalidations]);
      final quiet = _quietReads();
      for (final read in quiet) {
        s.container.listen(read, (_, _) {});
      }
      // Past the engine's own start and whatever it prompted.
      await tester.pump(kCatalogRefreshWindow * 3);
      invalidations.seen.clear();

      // A scan reports a change about once a second.
      for (var second = 0; second < 12; second++) {
        repo.changeCatalog();
        await s.sync.pullCatalog();
        await tester.pump(const Duration(seconds: 1));
      }
      expect(
        invalidations.seen.intersection(quiet.toSet()),
        isEmpty,
        reason: 'no pass of the run asks for one',
      );

      await tester.pump(kCatalogRefreshWindow);
      expect(invalidations.seen, containsAll(quiet));
      invalidations.seen.clear();
      await tester.pump(kCatalogRefreshWindow * 3);
      expect(
        invalidations.seen.intersection(quiet.toSet()),
        isEmpty,
        reason: 'once a run',
      );
      await _unbind(tester, s.container);
    });

    // Three pages of each paged list, all loaded, then a quiet sweep.
    Future<void> keepsItsExtent(
      WidgetTester tester, {
      required FakeRepository repo,
      required ProviderListenable<AsyncValue<Object?>> listing,
      required Future<void> Function(ProviderContainer) loadMore,
      required int Function(Object? state) rows,
      required List<String?> Function() cursors,
    }) async {
      final container = appContainer(repo: repo);
      container.listen(listing, (_, _) {});
      await tester.pump(_tick);
      await loadMore(container);
      await loadMore(container);
      expect(rows(container.read(listing).value), 120);
      final before = cursors().length;

      container.read(catalogQuietFanOutProvider).sweep();
      await tester.pump(_tick);

      expect(rows(container.read(listing).value), 120);
      expect(cursors().skip(before), [
        null,
        '50',
        '100',
      ], reason: 'the loaded extent read where the list stands, once');
    }

    testWidgets('keep the listen log a reader scrolled where it stands', (
      tester,
    ) async {
      final repo = FakeRepository()
        ..listenLog = [
          for (var i = 0; i < 120; i++)
            ListenLogEntry(
              sessionId: 's-$i',
              pid: 'tr-$i',
              mediaType: StatsMediaType.music,
              startedAt: DateTime.utc(2026, 7, 20).subtract(Duration(hours: i)),
              msPlayed: 1,
              finished: true,
              client: 'web',
              source: 'local',
            ),
        ];
      await keepsItsExtent(
        tester,
        repo: repo,
        listing: listenLogProvider,
        loadMore: (c) => c.read(listenLogProvider.notifier).loadMore(),
        rows: (state) => (state! as ListenLogState).entries.length,
        cursors: () => [for (final call in repo.listenLogCalls) call.cursor],
      );
    });

    for (final all in [false, true]) {
      testWidgets(
        'keep ${all ? 'every account\'s' : 'the caller\'s'} share links '
        'where a reader scrolled them',
        (tester) async {
          final repo = FakeRepository();
          (all ? repo.allShares : repo.shares).addAll([
            for (var i = 0; i < 120; i++)
              Share(
                pid: 'sh-$i',
                url: '/s/$i',
                targetPid: 'tr-$i',
                targetKind: 'track',
                targetTitle: 'Track $i',
                allowDownload: false,
                createdAt: DateTime.utc(2026, 7, 20),
                plays: 0,
              ),
          ]);
          final listing = all ? adminSharesProvider : sharesProvider;
          await keepsItsExtent(
            tester,
            repo: repo,
            listing: listing,
            loadMore: (c) => c.read(listing.notifier).loadMore(),
            rows: (state) => (state! as SharesState).shares.length,
            cursors: () => repo.listSharesCursors,
          );
        },
      );
    }

    testWidgets('keep the uploads list where a reader scrolled it, across a '
        'quiet sweep and a write landed here', (tester) async {
      final repo = _PagedUploads(120);
      await keepsItsExtent(
        tester,
        repo: repo,
        listing: uploadsProvider,
        loadMore: (c) => c.read(uploadsProvider.notifier).loadMore(),
        rows: (state) => (state! as UploadsState).uploads.length,
        cursors: () => repo.cursors,
      );

      // A write made here sweeps it too.
      final container = appContainer(repo: repo);
      container.listen(uploadsProvider, (_, _) {});
      await tester.pump(_tick);
      final notifier = container.read(uploadsProvider.notifier);
      await notifier.loadMore();
      await notifier.loadMore();
      repo.cursors.clear();
      container.read(catalogWritesProvider).landed();
      await tester.pump(_tick);
      expect(
        container.read(uploadsProvider).requireValue.uploads,
        hasLength(120),
      );
      expect(repo.cursors, [null, '50', '100']);
    });
  });

  group('the health lists that audit the catalog', () {
    testWidgets('are each read once under a run of hints, when the run goes '
        'quiet', (tester) async {
      final repo = _Audits(3);
      final s = _bound(repo);
      s.container
        ..listen(duplicatesProvider, (_, _) {})
        ..listen(upgradesProvider, (_, _) {});
      // Past the engine's own start and whatever it prompted.
      await tester.pump(kCatalogRefreshWindow * 3);
      final (duplicates, upgrades) = repo.asks;

      // A scan reports a change about once a second.
      for (var second = 0; second < 12; second++) {
        repo.changeCatalog();
        await s.sync.pullCatalog();
        await tester.pump(const Duration(seconds: 1));
      }
      expect(repo.asks, (
        duplicates,
        upgrades,
      ), reason: 'no pass of the run asks for an audit');

      await tester.pump(kCatalogRefreshWindow);
      expect(repo.asks, (duplicates + 1, upgrades + 1));
      await tester.pump(kCatalogRefreshWindow * 3);
      expect(repo.asks, (duplicates + 1, upgrades + 1), reason: 'once a run');
      await _unbind(tester, s.container);
    });
  });

  group('a paged listing refreshed in place', () {
    test('a listing holding 12 pages costs at most 2 requests per hint '
        'pass', () async {
      final repo = _Library(12 * _page);
      final container = await _holdTracks(repo, pages: 12);
      expect(_held(container).items, hasLength(12 * _page));

      for (var pass = 0; pass < 3; pass++) {
        repo.requests.clear();
        container.read(catalogFanOutProvider).sweep(CatalogRefresh.head);
        final state = await _landed(container);

        expect(repo.requests, [null, _pid(_page - 1)]);
        expect(_pids(state.items), _pids(repo.tracks));
      }
    });

    test('three rows inserted at the head of a three-page listing lose and '
        'double nothing at the seam', () async {
      final repo = _Library(4 * _page);
      final container = await _holdTracks(repo, pages: 3);

      repo.tracks = [for (var i = -3; i < 0; i++) _row(i), ...repo.tracks];
      container.read(catalogFanOutProvider).sweep(CatalogRefresh.head);
      final state = await _landed(container);

      expect(repo.requests, hasLength(2));
      expect(_pids(state.items), _pids(repo.tracks.take(3 * _page + 3)));
      expect(state.hasMore, isTrue);

      // Paging goes on from the tail that was kept.
      await container.read(musicItemsProvider(_tracks).notifier).loadMore();
      expect(_pids(_held(container).items), _pids(repo.tracks));
      expect(_held(container).hasMore, isFalse);
    });

    test('a head that holds no row of the old list is the listing', () async {
      final repo = _Library(3 * _page);
      final container = await _holdTracks(repo, pages: 3);

      // Another library entirely, sorting ahead of every row held.
      repo.tracks = [
        for (var i = 0; i < 3 * _page; i++)
          testItem('tr-0-${i.toString().padLeft(5, '0')}'),
      ];
      container.read(catalogFanOutProvider).sweep(CatalogRefresh.head);
      final state = await _landed(container);

      expect(repo.requests, hasLength(2));
      expect(_pids(state.items), _pids(repo.tracks.take(2 * _page)));
      // Paged on from its own end, not from where the old list stood.
      await container.read(musicItemsProvider(_tracks).notifier).loadMore();
      expect(_pids(_held(container).items), _pids(repo.tracks));
    });

    test('a head read that reaches the end is the whole listing', () async {
      final repo = _Library(3 * _page);
      final container = await _holdTracks(repo, pages: 3);

      repo.tracks = repo.tracks.take(40).toList();
      container.read(catalogFanOutProvider).sweep(CatalogRefresh.head);
      final state = await _landed(container);

      expect(_pids(state.items), _pids(repo.tracks));
      expect(state.hasMore, isFalse);
    });

    test('a loadMore in flight when a hint lands loses and doubles '
        'nothing', () async {
      final repo = _Library(3 * _page);
      final container = await _holdTracks(repo);
      final notifier = container.read(musicItemsProvider(_tracks).notifier);

      final gate = repo.gate = Completer<void>();
      final more = notifier.loadMore();
      repo.tracks = [_row(-2), _row(-1), ...repo.tracks];
      container.read(catalogFanOutProvider).sweep(CatalogRefresh.head);
      await container.pump();
      await pumpEventQueue();
      expect(repo.requests, [
        _pid(_page - 1),
      ], reason: 'the refresh waits for the page rather than reading over it');

      repo.gate = null;
      gate.complete();
      await more;
      final state = await _landed(container);

      expect(repo.requests, hasLength(3));
      expect(_pids(state.items), _pids(repo.tracks.take(2 * _page + 2)));
      expect(state.loadingMore, isFalse);
      expect(state.hasMore, isTrue);
    });

    test('an invalidation during a first read waits for it rather than '
        'restarting it', () async {
      final repo = _Library(3 * _page);
      final gate = repo.gate = Completer<void>();
      final container = appContainer(repo: repo);
      final held = container.listen(musicItemsProvider(_tracks), (_, _) {});
      addTearDown(held.close);
      await pumpEventQueue();
      expect(repo.requests, [null]);

      for (var pass = 0; pass < 3; pass++) {
        container.read(catalogFanOutProvider).sweep(CatalogRefresh.head);
        await container.pump();
        await pumpEventQueue();
      }
      expect(repo.requests, [null], reason: 'a pass restarted the first read');

      repo.gate = null;
      gate.complete();
      final state = await _landed(container);
      expect(repo.requests, [null, null], reason: 'the read, then one pass');
      expect(_pids(state.items), _pids(repo.tracks.take(_page)));
    });

    test('a pass that lands while an index starts over waits for that '
        'read', () async {
      const key = (
        dimension: MusicDimension.artists,
        sort: FacetSort.label,
        domain: BrowseDomain.music,
      );
      final repo = FakeRepository()
        ..facets['artist'] = [
          for (var i = 0; i < 600; i++)
            FacetBucket(key: 'k$i', label: 'Artist $i', count: 1),
        ];
      final container = appContainer(repo: repo);
      final held = container.listen(musicIndexProvider(key), (_, _) {});
      addTearDown(held.close);
      await container.read(musicIndexProvider(key).future);
      repo.facetReads.clear();

      final gate = repo.facetGate = Completer<void>();
      container.read(musicIndexProvider(key).notifier).reset();
      await container.pump();
      await pumpEventQueue();
      expect(repo.facetReads, hasLength(1));

      for (var pass = 0; pass < 3; pass++) {
        container.read(catalogFanOutProvider).sweep(CatalogRefresh.head);
        await container.pump();
        await pumpEventQueue();
      }
      expect(repo.facetReads, hasLength(1), reason: 'a pass restarted it');

      repo.facetGate = null;
      gate.complete();
      await container.pump();
      await pumpEventQueue();
      final state = container.read(musicIndexProvider(key));
      expect((state.isLoading, state.hasError), (false, false));
      expect(repo.facetReads, hasLength(2), reason: 'the head, then one pass');
      expect(state.requireValue.buckets, hasLength(500));
    });

    test('a loaded refresh re-reads the extent once and replaces it', () async {
      final repo = _Library(3 * _page);
      final container = await _holdTracks(repo, pages: 3);

      repo.tracks[2 * _page + 7] = _row(2 * _page + 7, title: 'Retitled');
      container.read(catalogFanOutProvider).sweep(CatalogRefresh.loaded);
      final state = await _landed(container);

      expect(repo.requests, [null, _pid(_page - 1), _pid(2 * _page - 1)]);
      expect(state.items[2 * _page + 7].title, 'Retitled');
      expect(state.items, hasLength(3 * _page));
    });

    test('an invalidation that names no depth re-reads the loaded extent, '
        'never the first page alone', () async {
      final repo = _Library(3 * _page);
      final container = await _holdTracks(repo, pages: 3);

      container.invalidate(musicItemsProvider(_tracks));
      final state = await _landed(container);

      expect(repo.requests, hasLength(3));
      expect(state.items, hasLength(3 * _page));
    });

    test(
      'the strongest depth owed wins, and telling costs no request',
      () async {
        final repo = _Library(3 * _page);
        final container = appContainer(repo: repo);
        final held = container.listen(musicItemsProvider(_tracks), (_, _) {});
        addTearDown(held.close);
        await container.read(musicItemsProvider(_tracks).future);
        final notifier = container.read(musicItemsProvider(_tracks).notifier);
        await notifier.loadMore();
        await notifier.loadMore();
        repo.requests.clear();

        // Covered: nothing reads it, as under a pushed page.
        held.pause();
        final fanOut = container.read(catalogFanOutProvider);
        fanOut.sweep(CatalogRefresh.loaded);
        fanOut.sweep(CatalogRefresh.head);
        await container.pump();
        await pumpEventQueue();
        expect(repo.requests, isEmpty);

        held.resume();
        await _landed(container);
        expect(repo.requests, hasLength(3), reason: 'loaded outranks head');

        // Honoured, so cleared: the next pass is a head pass again.
        repo.requests.clear();
        fanOut.sweep(CatalogRefresh.head);
        await _landed(container);
        expect(repo.requests, hasLength(2));
      },
    );

    test('a failed refresh keeps the rows and stays owed', () async {
      final repo = _Library(3 * _page);
      final container = await _holdTracks(repo, pages: 3);
      final before = _held(container).items;

      repo.failure = const WaxDeckApiException(
        code: 'transport',
        message: 'connection refused',
      );
      container.read(catalogFanOutProvider).sweep(CatalogRefresh.head);
      await container.pump();
      await pumpEventQueue();

      final failed = container.read(musicItemsProvider(_tracks));
      expect((failed.hasError, failed.isLoading), (false, false));
      expect(failed.requireValue.items, same(before));

      // Still owed its head: an invalidation that names no depth reads
      // two pages, where one owed nothing reads the three it holds.
      repo.failure = null;
      repo.requests.clear();
      repo.tracks[3] = _row(3, title: 'Retitled');
      container.invalidate(musicItemsProvider(_tracks));
      final state = await _landed(container);

      expect(repo.requests, hasLength(2));
      expect(state.items[3].title, 'Retitled');
      expect(state.items, hasLength(3 * _page));
    });

    test('an account swap under a held listing starts over', () async {
      final server = _TracksServer()
        ..rows = [for (var i = 0; i < 3 * _page; i++) _row(i)];
      final container = appContainer(server: server);
      final held = container.listen(musicItemsProvider(_tracks), (_, _) {});
      addTearDown(held.close);
      await container.read(musicItemsProvider(_tracks).future);
      final notifier = container.read(musicItemsProvider(_tracks).notifier);
      await notifier.loadMore();
      await notifier.loadMore();
      expect(_held(container).items, hasLength(3 * _page));

      // The server answers for whoever signs in next, through a client
      // built again: an account whose grants stop short of the rows the
      // last one had loaded. A head pass was owed besides, and a head
      // laid over the rows held would keep the last account's tail.
      server.rows = server.rows.take(2 * _page + 100).toList();
      container.read(catalogFanOutProvider).sweep(CatalogRefresh.head);
      container.invalidate(apiClientProvider);
      final state = await _landed(container);

      expect(_pids(state.items), _pids(server.rows.take(_page)));
      expect(state.hasMore, isTrue);
    });

    test('an anchored index keeps its floor and re-reads from it', () async {
      const key = (
        dimension: MusicDimension.artists,
        sort: FacetSort.label,
        domain: BrowseDomain.music,
      );
      FacetBucket artist(String name) => FacetBucket(
        key: name.toLowerCase().replaceAll(' ', '-'),
        label: name,
        count: 1,
      );
      final repo = FakeRepository()
        ..facets['artist'] = [
          for (var i = 0; i < 600; i++)
            artist('Able ${i.toString().padLeft(3, '0')}'),
          for (var i = 0; i < 40; i++)
            artist('Mole ${i.toString().padLeft(3, '0')}'),
        ];
      final container = appContainer(repo: repo);
      final held = container.listen(musicIndexProvider(key), (_, _) {});
      addTearDown(held.close);
      await container.read(musicIndexProvider(key).future);
      final notifier = container.read(musicIndexProvider(key).notifier);
      expect(await notifier.anchorAt('m'), isTrue);

      repo.facets['artist']!.add(artist('Mole 999'));
      repo.facetStartsAt.clear();
      container.read(catalogFanOutProvider).sweep(CatalogRefresh.head);
      await container.pump();
      final state = await container.read(musicIndexProvider(key).future);

      expect(state.anchoredAt, 'm');
      expect(repo.facetStartsAt, ['m']);
      expect(state.buckets.first.label, 'Mole 000');
      expect(state.buckets.last.label, 'Mole 999');
    });

    test('a letter seek while a refresh is out replaces the window, and the '
        'refresh does not lay its rows over it', () async {
      const key = (
        dimension: MusicDimension.artists,
        sort: FacetSort.label,
        domain: BrowseDomain.music,
      );
      FacetBucket artist(String name) =>
          FacetBucket(key: name, label: name, count: 1);
      final repo = _HeldHead()
        ..facets['artist'] = [
          for (var i = 0; i < 600; i++)
            artist('Able ${i.toString().padLeft(3, '0')}'),
          for (var i = 0; i < 40; i++)
            artist('Mole ${i.toString().padLeft(3, '0')}'),
        ];
      final container = appContainer(repo: repo);
      final held = container.listen(musicIndexProvider(key), (_, _) {});
      addTearDown(held.close);
      await container.read(musicIndexProvider(key).future);
      final notifier = container.read(musicIndexProvider(key).notifier);
      repo.facetStartsAt.clear();

      // The refresh's read of the head is still out when the seek lands.
      final gate = repo.headGate = Completer<void>();
      container.read(catalogFanOutProvider).sweep(CatalogRefresh.head);
      await container.pump();
      await pumpEventQueue();
      expect(await notifier.anchorAt('m'), isTrue);
      expect(repo.facetStartsAt, [null, 'm']);

      repo.headGate = null;
      gate.complete();
      await pumpEventQueue();

      final state = container.read(musicIndexProvider(key));
      expect((state.isLoading, state.hasError), (false, false));
      expect(state.requireValue.anchoredAt, 'm');
      expect(state.requireValue.buckets.first.label, 'Mole 000');
      expect(state.requireValue.buckets, hasLength(40));
      // The pass it still owed is read from the floor that stands.
      expect(repo.facetStartsAt, [null, 'm', 'm']);
    });

    test('a preference that changes what an index lists starts it over, '
        'whatever was owed', () async {
      const key = (
        dimension: MusicDimension.artists,
        sort: FacetSort.label,
        domain: BrowseDomain.music,
      );
      final repo = FakeRepository()
        ..facets['artist'] = [
          for (var i = 0; i < 1100; i++)
            FacetBucket(key: 'k$i', label: 'Artist $i', count: 1),
          const FacetBucket(key: '', label: '', count: 4, unknown: true),
        ];
      final prefs = _Prefs();
      final container = appContainer(
        repo: repo,
        extra: [prefsControllerProvider.overrideWith(() => prefs)],
      );
      await container.read(prefsControllerProvider.future);
      final held = container.listen(musicIndexProvider(key), (_, _) {});
      addTearDown(held.close);
      await container.read(musicIndexProvider(key).future);
      final notifier = container.read(musicIndexProvider(key).notifier);
      await notifier.loadMore();
      await notifier.loadMore();
      expect(
        container.read(musicIndexProvider(key)).requireValue.buckets.last,
        isA<FacetBucket>().having((b) => b.unknown, 'unknown', isTrue),
      );

      // Covered, a head pass owed, and then the unknown bucket is
      // switched off: a head laid over the rows held would keep it.
      held.pause();
      container.read(catalogFanOutProvider).sweep(CatalogRefresh.head);
      prefs.showUnknown(false);
      held.resume();
      await container.pump();
      await pumpEventQueue();

      final state = container.read(musicIndexProvider(key)).requireValue;
      expect(state.buckets, hasLength(MusicIndexController.pageSize));
      expect(state.buckets.where((b) => b.unknown), isEmpty);
      expect(state.hasMore, isTrue);
    });

    testWidgets('a scrolled listing keeps its extent and offset across a '
        'refresh', (tester) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = _Library(2 * _page + 200);
      final container = appContainer(repo: repo);
      await pumpApp(tester, const MusicListingScreen(), container: container);
      final notifier = container.read(musicItemsProvider(_tracks).notifier);
      await notifier.loadMore();
      await notifier.loadMore();
      await tester.pumpAndSettle();
      expect(_held(container).items, hasLength(2 * _page + 200));

      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      // Deep into the second page, clear of the end where a scroll pages.
      position.jumpTo(position.maxScrollExtent * 0.55);
      await tester.pumpAndSettle();
      final offset = position.pixels;
      final shown = tester
          .widgetList<MediaListRow>(find.byType(MediaListRow))
          .map((row) => row.data.title)
          .toList();
      expect(shown, isNotEmpty);

      // One of the rows on screen is retitled elsewhere.
      final at = repo.tracks.indexWhere((t) => t.title == shown[2]);
      repo.tracks[at] = _row(at, title: 'Retitled');
      final gate = repo.gate = Completer<void>();
      container.read(catalogFanOutProvider).sweep(CatalogRefresh.head);
      await tester.pump();
      await tester.pump();

      // In flight: the rows held are still what is drawn.
      expect(find.byType(SkeletonShapes), findsNothing);
      expect(find.text(shown[2]), findsOneWidget);
      expect(position.pixels, offset);

      repo.gate = null;
      gate.complete();
      await tester.pumpAndSettle();

      expect(find.byType(SkeletonShapes), findsNothing);
      expect(find.text('Retitled'), findsOneWidget);
      expect(find.text(shown[2]), findsNothing);
      expect(find.text(shown[3]), findsOneWidget);
      expect(position.pixels, offset);
      expect(_held(container).items, hasLength(2 * _page + 200));
    });

    testWidgets('a three-page listing under a pushed editor shows a write to '
        'a row on page three once the editor pops', (tester) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = _Library(3 * _page);
      final container = appContainer(repo: repo);
      await pumpApp(tester, const MusicListingScreen(), container: container);
      final notifier = container.read(musicItemsProvider(_tracks).notifier);
      await notifier.loadMore();
      await notifier.loadMore();
      await tester.pumpAndSettle();
      expect(_held(container).items, hasLength(3 * _page));

      const at = 2 * _page + 40;
      final router = GoRouter.of(
        tester.element(find.byType(MusicListingScreen)),
      );
      unawaited(router.push<void>(WaxRoute.metadata(_pid(at))));
      await tester.pumpAndSettle();
      expect(
        find.byType(MusicListingScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(find.byType(MusicListingScreen), findsNothing);
      repo.requests.clear();

      // The write lands: what this device's write path sweeps at once,
      // then the server's hint for the same change, both while the
      // listing is covered.
      repo.tracks[at] = _row(at, title: 'Retitled');
      final fanOut = container.read(catalogFanOutProvider);
      fanOut.sweep(CatalogRefresh.loaded);
      await tester.pumpAndSettle();
      fanOut.sweep(CatalogRefresh.head);
      await tester.pumpAndSettle();
      expect(repo.requests, isEmpty, reason: 'a covered listing reads nothing');

      router.pop();
      await tester.pumpAndSettle();

      expect(find.byType(MusicListingScreen), findsOneWidget);
      expect(repo.requests, hasLength(3), reason: 'the loaded depth survived');
      expect(_held(container).items[at].title, 'Retitled');
    });

    testWidgets('a user change refreshes the review queue from its head and '
        'keeps the rows loaded', (tester) async {
      const page = ReviewQueueController.pageSize;
      final repo = _ReviewQueue()
        ..sessionState = const SessionState(
          authenticated: true,
          user: WaxDeckUser(id: 'us-1', username: 'admin'),
        )
        ..reviewEntries = [
          for (var i = 0; i < 3 * page + 10; i++) testReviewEntry('rv-$i'),
        ];
      final s = _bound(repo);
      // The user stream is walked for an account, which the preference
      // controller names to the engine.
      s.container.listen(prefsControllerProvider, (_, _) {});
      await s.container.read(prefsControllerProvider.future);
      s.container.listen(reviewQueueProvider, (_, _) {});
      await tester.pump();
      final notifier = s.container.read(reviewQueueProvider.notifier);
      await notifier.loadMore();
      await notifier.loadMore();
      // The walk's first pull mints its cursor and reports nothing.
      await s.sync.pullServer();
      await tester.pump(kUserRefreshWindow * 2);
      repo.cursors.clear();

      // Another reviewer decides the first entry.
      repo.reviewEntries = repo.reviewEntries.skip(1).toList();
      repo.serverPages.add(
        const ServerSyncPage(
          userId: 'us-1',
          events: [ServerSyncEvent(kind: 'review', pid: 'rv-0')],
          nextSince: 'scur-1',
        ),
      );
      await s.sync.pullServer();
      await tester.pump(const Duration(seconds: 1));

      expect(repo.cursors, hasLength(2));
      expect(
        s.container
            .read(reviewQueueProvider)
            .requireValue
            .entries
            .map((entry) => entry.id),
        [for (var i = 1; i < 3 * page; i++) 'rv-$i'],
      );
      await _unbind(tester, s.container);
    });

    testWidgets('an entry decided elsewhere past the head of the review '
        'queue leaves it once the user changes go quiet', (tester) async {
      const page = ReviewQueueController.pageSize;
      final repo = _ReviewQueue()
        ..sessionState = const SessionState(
          authenticated: true,
          user: WaxDeckUser(id: 'us-1', username: 'admin'),
        )
        ..reviewEntries = [
          for (var i = 0; i < 3 * page + 10; i++) testReviewEntry('rv-$i'),
        ];
      final s = _bound(repo);
      s.container.listen(prefsControllerProvider, (_, _) {});
      await s.container.read(prefsControllerProvider.future);
      s.container.listen(reviewQueueProvider, (_, _) {});
      await tester.pump();
      final notifier = s.container.read(reviewQueueProvider.notifier);
      await notifier.loadMore();
      await notifier.loadMore();
      await s.sync.pullServer();
      await tester.pump(kUserRefreshWindow * 3);
      repo.cursors.clear();
      List<String> listed() => [
        for (final entry
            in s.container.read(reviewQueueProvider).requireValue.entries)
          entry.id,
      ];

      // Another reviewer decides an entry on the third page.
      const decided = 'rv-${2 * page + 5}';
      repo.reviewEntries = [
        for (final entry in repo.reviewEntries)
          if (entry.id != decided) entry,
      ];
      repo.serverPages.add(
        const ServerSyncPage(
          userId: 'us-1',
          events: [ServerSyncEvent(kind: 'review', pid: decided)],
          nextSince: 'scur-1',
        ),
      );
      await s.sync.pullServer();
      await tester.pump(const Duration(seconds: 1));
      expect(repo.cursors, hasLength(2), reason: 'the pass reads the head');
      expect(listed(), contains(decided));

      await tester.pump(kUserRefreshWindow);
      expect(repo.cursors, hasLength(5), reason: 'then the loaded extent');
      expect(listed(), isNot(contains(decided)));
      expect(listed(), hasLength(3 * page));

      repo.cursors.clear();
      await tester.pump(kUserRefreshWindow * 3);
      expect(repo.cursors, isEmpty, reason: 'once a run');
      await _unbind(tester, s.container);
    });

    testWidgets('a 20-pass scan over a slow listing reads the loaded extent '
        'once every six windows, and once at its end, and ends settled', (
      tester,
    ) async {
      final repo = _Library(3 * _page);
      final s = _bound(repo);
      final listing = musicItemsProvider(_tracks);
      s.container.listen(listing, (_, _) {});
      await tester.pump();
      final notifier = s.container.read(listing.notifier);
      await notifier.loadMore();
      await notifier.loadMore();
      expect(_held(s.container).items, hasLength(3 * _page));
      await tester.pump(kCatalogRefreshWindow * 2);
      repo.requests.clear();

      // Two pages take longer than the window between two passes.
      repo.latency = const Duration(seconds: 3);
      // A scan reports a change about once a second: a hundred seconds
      // of it is the first pass and twenty more, a window apart.
      for (var second = 0; second < 100; second++) {
        repo.changeCatalog();
        await s.sync.pullCatalog();
        await tester.pump(const Duration(seconds: 1));
      }
      expect(repo.requests, isNotEmpty);
      expect(
        repo.requests.where((cursor) => cursor == _pid(2 * _page - 1)),
        hasLength(3),
        reason:
            'a hint\'s pass reads the head; the quiet edge\'s ceiling, '
            '30, 60 and 90 seconds in, the extent',
      );

      // The run goes quiet, and what is under way drains.
      for (var second = 0; second < 40; second++) {
        await tester.pump(const Duration(seconds: 1));
      }

      final state = s.container.read(listing);
      expect((state.isLoading, state.hasError), (false, false));
      expect(state.requireValue.items, hasLength(3 * _page));
      expect(
        repo.requests.where((cursor) => cursor == _pid(2 * _page - 1)),
        hasLength(4),
        reason: 'and once more when the run goes quiet',
      );
      expect(repo.widest, 1, reason: 'a pass waits for the walk before it');
      await _unbind(tester, s.container);
    });
  });

  group('a write that landed', () {
    /// The three requests that re-read three loaded pages.
    final loaded = [null, _pid(_page - 1), _pid(2 * _page - 1)];

    /// The tracks index held open under a bound session, three pages in
    /// and past the engine's own start.
    Future<_Session> boundTracks(WidgetTester tester, _Library repo) async {
      final s = _bound(repo);
      final listing = musicItemsProvider(_tracks);
      s.container.listen(listing, (_, _) {});
      await tester.pump(_tick);
      final notifier = s.container.read(listing.notifier);
      await notifier.loadMore();
      await notifier.loadMore();
      expect(_held(s.container).items, hasLength(3 * _page));
      await tester.pump(kCatalogRefreshWindow * 2);
      repo.requests.clear();
      return s;
    }

    testWidgets('sweeps every open read at once, to the loaded depth, with '
        'no session bound', (tester) async {
      final repo = _Library(3 * _page);
      final invalidations = _Invalidations();
      final container = appContainer(repo: repo, observers: [invalidations]);
      addTearDown(container.dispose);
      final listing = musicItemsProvider(_tracks);
      for (final read in [listing, ...catalogReadProviders]) {
        container.listen(read, (_, _) {});
      }
      await tester.pump(_tick);
      final notifier = container.read(listing.notifier);
      await notifier.loadMore();
      await notifier.loadMore();
      repo.requests.clear();
      invalidations.seen.clear();

      const at = 2 * _page + 40;
      repo.tracks[at] = _row(at, title: 'Retitled');
      container.read(catalogWritesProvider).landed();
      await tester.pump(_tick);

      expect(repo.requests.where((cursor) => cursor != null), loaded.skip(1));
      expect(_held(container).items[at].title, 'Retitled');
      expect(invalidations.seen, containsAll(catalogReadProviders));

      // Nothing is owed where no session paces a pass, and nothing throws.
      repo.requests.clear();
      await tester.pump(kCatalogRefreshWindow * 3);
      expect(repo.requests, isEmpty);
    });

    testWidgets('invalidates one instance of every registered family', (
      tester,
    ) async {
      final open = _oneOfEachFamily();
      expect(open.keys.toSet(), catalogReadFamilies.toSet());
      final invalidations = _Invalidations();
      final container = appContainer(
        repo: _Library(3),
        observers: [invalidations],
      );
      addTearDown(container.dispose);
      for (final read in [...open.values, ...catalogReadProviders]) {
        container.listen(read, (_, _) {});
      }
      await tester.pump(_tick);
      invalidations.seen.clear();

      container.read(catalogWritesProvider).landed();

      expect(invalidations.seen, containsAll(open.values));
      expect(invalidations.seen, containsAll(catalogReadProviders));
      // Kept for the session, and a delete made anywhere adds to it.
      expect(catalogReadProviders, contains(trashProvider));
      // What the reads the sweep prompted leave behind.
      await tester.pump(kCatalogRefreshWindow * 3);
    });

    testWidgets('has every read a pass leaves alone read again, once', (
      tester,
    ) async {
      final invalidations = _Invalidations();
      final container = appContainer(
        repo: _Library(1),
        observers: [invalidations],
      );
      addTearDown(container.dispose);
      final quiet = _quietReads();
      for (final read in quiet) {
        container.listen(read, (_, _) {});
      }
      await tester.pump(_tick);
      invalidations.seen.clear();

      container.read(catalogWritesProvider).landed();
      expect(invalidations.seen, containsAll(quiet));
      await tester.pump(_tick);
      invalidations.seen.clear();

      await tester.pump(kCatalogRefreshWindow * 3);
      expect(
        invalidations.seen.intersection(quiet.toSet()),
        isEmpty,
        reason: 'once, where no session paces more',
      );
    });

    testWidgets('has the health lists that audit the catalog read again', (
      tester,
    ) async {
      final repo = _Audits(1);
      final container = appContainer(repo: repo);
      addTearDown(container.dispose);
      container
        ..listen(duplicatesProvider, (_, _) {})
        ..listen(upgradesProvider, (_, _) {});
      await tester.pump(_tick);
      expect(repo.asks, (1, 1));

      container.read(catalogWritesProvider).landed();
      await tester.pump(_tick);
      expect(repo.asks, (2, 2), reason: 'a merge or a delete moves both');

      await tester.pump(kCatalogRefreshWindow * 3);
      expect(repo.asks, (2, 2), reason: 'once, where no session paces more');
    });

    testWidgets('evicts the covers it names before any read asks again', (
      tester,
    ) async {
      const cover = '/api/v1/items/al-01JZX5N8QW3F4V9T2B7KDREG01/art';
      final store = FakeArtworkStore();
      final repo = _Library(_page);
      final container = appContainer(repo: repo, artwork: store);
      addTearDown(container.dispose);
      container.listen(musicItemsProvider(_tracks), (_, _) {});
      await container.read(musicItemsProvider(_tracks).future);
      container.read(paletteCacheProvider).remember(cover, null);
      repo.requests.clear();
      final evictedWhenAsked = <int>[];
      repo.asked = () => evictedWhenAsked.add(store.evicted.length);

      container.read(catalogWritesProvider).landed(artUrls: {cover});
      await tester.pump(_tick);

      expect(store.evicted, [cover]);
      expect(evictedWhenAsked, [1], reason: 'the re-read came after');
      expect(
        container.read(paletteCacheProvider).holds(cover),
        isFalse,
        reason: 'the colour read off the old bytes went with them',
      );
    });

    testWidgets('asks the home probe again, which a delete can empty', (
      tester,
    ) async {
      final repo = _Library(1);
      final container = appContainer(repo: repo);
      addTearDown(container.dispose);
      container.listen(libraryHasAnythingProvider, (_, _) {});
      expect(await container.read(libraryHasAnythingProvider.future), isTrue);

      repo.tracks = [];
      container.read(catalogWritesProvider).landed();
      await tester.pump(_tick);

      expect(container.read(libraryHasAnythingProvider).value, isFalse);
    });

    testWidgets('a cover that will not evict is reported, and the sweep '
        'still runs', (tester) async {
      const cover = '/api/v1/items/al-01JZX5N8QW3F4V9T2B7KDREG01/art';
      final printed = <String?>[];
      final print = debugPrint;
      debugPrint = (message, {wrapWidth}) => printed.add(message);
      final repo = _Library(_page);
      final container = appContainer(repo: repo, artwork: _StuckArtwork());
      container.listen(musicItemsProvider(_tracks), (_, _) {});
      await container.read(musicItemsProvider(_tracks).future);
      repo.requests.clear();

      container.read(catalogWritesProvider).landed(artUrls: {cover});
      await tester.pump(_tick);
      // The binding refuses a test that ends with it replaced.
      debugPrint = print;

      expect(repo.requests, [null]);
      expect(printed, [contains('disk full')]);
    });

    testWidgets('leaves a probe on its first build to finish, and asks it '
        'on the pass it owes', (tester) async {
      final repo = _Library(1);
      final s = _bound(repo, observers: [FirstBuildObserver()]);
      await tester.pump(kCatalogRefreshWindow * 2);
      repo.requests.clear();
      final gate = repo.gate = Completer<void>();
      s.container.listen(libraryHasAnythingProvider, (_, _) {});
      await tester.pump(_tick);
      expect(repo.requests, [null]);

      s.container.read(catalogWritesProvider).landed();
      await tester.pump(_tick);
      expect(repo.requests, [null], reason: 'the read under way is kept');

      repo.gate = null;
      gate.complete();
      await tester.pump(_tick);
      expect(s.container.read(libraryHasAnythingProvider).value, isTrue);

      // What that read answered can predate the write.
      repo.tracks = [];
      await tester.pump(kCatalogRefreshWindow);
      expect(repo.requests, [null, null]);
      expect(s.container.read(libraryHasAnythingProvider).value, isFalse);
      await _unbind(tester, s.container);
    });

    testWidgets('leaves a health list on its first build to finish, and '
        'asks it on the pass it owes', (tester) async {
      final repo = _Audits(1);
      final s = _bound(repo, observers: [FirstBuildObserver()]);
      await tester.pump(kCatalogRefreshWindow * 2);
      final gate = repo.auditGate = Completer<void>();
      s.container.listen(duplicatesProvider, (_, _) {});
      await tester.pump(_tick);
      expect(repo.duplicateAsks, 1);

      s.container.read(catalogWritesProvider).landed();
      await tester.pump(_tick);
      expect(repo.duplicateAsks, 1, reason: 'the read under way is kept');

      repo.auditGate = null;
      gate.complete();
      await tester.pump(_tick);
      // What that read answered can predate the write.
      await tester.pump(kCatalogRefreshWindow);
      expect(repo.duplicateAsks, 2);
      await _unbind(tester, s.container);
    });

    testWidgets('a pass taken back is not asked', (tester) async {
      final writes = appContainer().read(catalogWritesProvider);
      var asked = 0;
      void pass() => asked++;

      writes.bindPass(pass);
      writes.landed();
      expect(asked, 1);
      writes.unbindPass(pass);
      writes.landed();
      expect(asked, 1);
    });

    testWidgets('a session that ends after the next one bound leaves the '
        'next one its pass', (tester) async {
      final writes = appContainer().read(catalogWritesProvider);
      final asked = <String>[];
      void last() => asked.add('last');
      void next() => asked.add('next');

      writes.bindPass(last);
      writes.bindPass(next);
      writes.unbindPass(last);
      writes.landed();
      expect(asked, ['next']);
    });

    testWidgets('the pass it owes runs on the echo, and a hint after that '
        'waits for the window', (tester) async {
      final repo = _Library(3 * _page);
      final s = await boundTracks(tester, repo);

      s.container.read(catalogWritesProvider).landed();
      await tester.pump(_tick);
      expect(repo.requests, loaded, reason: 'at once, outside the pacer');
      repo.requests.clear();

      // The server's echo of the write.
      await tester.pump(const Duration(milliseconds: 300));
      repo.changeCatalog();
      await s.sync.pullCatalog();
      await tester.pump(_tick);
      expect(
        repo.requests,
        loaded,
        reason:
            'the owed pass, over the loaded extent, without waiting for '
            'the window',
      );
      repo.requests.clear();

      await tester.pump(const Duration(milliseconds: 100));
      repo.changeCatalog();
      await s.sync.pullCatalog();
      await tester.pump(const Duration(milliseconds: 4800));
      expect(repo.requests, isEmpty, reason: 'paced as any hint is');
      await tester.pump(const Duration(milliseconds: 200));
      expect(repo.requests, isNotEmpty);
      await _unbind(tester, s.container);
    });

    testWidgets('an index the server answered from before the write is '
        'right once the echo lands', (tester) async {
      const ambient = FacetBucket(key: '01JZXA', label: 'Ambient', count: 6);
      const drone = FacetBucket(key: '01JZXD', label: 'Drone', count: 1);
      final repo = _Library(_page)..facets['genre'] = [ambient];
      final s = _bound(repo);
      final index = musicIndexProvider((
        dimension: MusicDimension.genres,
        sort: FacetSort.label,
        domain: BrowseDomain.music,
      ));
      s.container.listen(index, (_, _) {});
      await tester.pump(kCatalogRefreshWindow * 2);
      List<String> listed() => [
        for (final bucket in s.container.read(index).requireValue.buckets)
          bucket.label,
      ];
      expect(listed(), ['Ambient']);

      // The write lands, and the facet read behind it still answers from
      // before it: the server's cache moves with its feed.
      s.container.read(catalogWritesProvider).landed();
      await tester.pump(_tick);
      expect(listed(), ['Ambient']);

      // The feed catches up, then the server says so.
      await tester.pump(const Duration(milliseconds: 300));
      repo.facets['genre'] = [ambient, drone];
      repo.changeCatalog();
      await s.sync.pullCatalog();
      await tester.pump(_tick);
      expect(listed(), ['Ambient', 'Drone']);
      await _unbind(tester, s.container);
    });

    testWidgets('under a running scan, a save to a bucket past the head of a '
        'deep index shows once the echo lands', (tester) async {
      String label(int at) => 'G${at.toString().padLeft(4, '0')}';
      FacetBucket bucket(int at, {int count = 1}) =>
          FacetBucket(key: 'k$at', label: label(at), count: count);
      final repo = _Library(_page)
        ..facets['genre'] = [for (var i = 0; i < 1500; i++) bucket(i)];
      final s = _bound(repo);
      final index = musicIndexProvider((
        dimension: MusicDimension.genres,
        sort: FacetSort.label,
        domain: BrowseDomain.music,
      ));
      s.container.listen(index, (_, _) {});
      await tester.pump(_tick);
      // Three pages, loaded by scrolling: no floor under the window.
      final notifier = s.container.read(index.notifier);
      await notifier.loadMore();
      await notifier.loadMore();
      await tester.pump(kCatalogRefreshWindow * 2);
      int count() => s.container
          .read(index)
          .requireValue
          .buckets
          .singleWhere((b) => b.key == 'k1200')
          .count;
      expect(count(), 1);

      // A scan, a change a second.
      Future<void> scanTick() async {
        repo.changeCatalog();
        await s.sync.pullCatalog();
        await tester.pump(const Duration(seconds: 1));
      }

      for (var i = 0; i < 3; i++) {
        await scanTick();
      }

      // The save lands, and the facet read behind it still answers from
      // before it.
      s.container.read(catalogWritesProvider).landed();
      await tester.pump(_tick);
      expect(count(), 1);

      // The feed catches up, and the next hint of the scan is the echo.
      await tester.pump(const Duration(milliseconds: 300));
      repo.facets['genre'] = [
        for (var i = 0; i < 1500; i++) bucket(i, count: i == 1200 ? 2 : 1),
      ];
      await scanTick();
      expect(count(), 2, reason: 'the scan is still running');

      for (var i = 0; i < 3; i++) {
        await scanTick();
      }
      await _unbind(tester, s.container);
    });

    testWidgets('with no echo the pass it owes re-reads the loaded extent at '
        'the end of the window, once', (tester) async {
      final repo = _Library(3 * _page);
      final s = await boundTracks(tester, repo);

      s.container.read(catalogWritesProvider).landed();
      await tester.pump(_tick);
      expect(repo.requests, loaded);
      repo.requests.clear();

      await tester.pump(kCatalogRefreshWindow - const Duration(seconds: 1));
      expect(repo.requests, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(repo.requests, loaded, reason: 'no trailing pass is coming');

      repo.requests.clear();
      await tester.pump(kCatalogRefreshWindow * 4);
      expect(repo.requests, isEmpty);
      await _unbind(tester, s.container);
    });

    testWidgets('a session that ended takes its pass with it', (tester) async {
      final repo = _Library(_page);
      final s = _bound(repo);
      final listing = s.container.listen(
        musicItemsProvider(_tracks),
        (_, _) {},
      );
      await tester.pump(kCatalogRefreshWindow * 2);
      // The binder goes as the signed-in tree does.
      s.binder.close();
      await tester.pump(_tick);
      repo.requests.clear();

      s.container.read(catalogWritesProvider).landed();
      await tester.pump(_tick);
      expect(repo.requests, [null], reason: 'the sweep still runs');

      repo.requests.clear();
      await tester.pump(kCatalogRefreshWindow * 3);
      expect(repo.requests, isEmpty, reason: 'and nothing is owed');
      listing.close();
      await _unbind(tester, s.container);
    });
  });

  group('NamedCovers', () {
    const window = kCatalogRefreshWindow;
    const second = Duration(seconds: 1);

    /// The rule, with what it told by name and what it said of every
    /// cover (`owed` as a stretch goes busy, `all` as it ends), in order.
    ({NamedCovers covers, List<String> told, List<String> said}) rule() {
      final told = <String>[];
      final said = <String>[];
      final covers = NamedCovers(
        replaced: told.add,
        owed: () => said.add('owed'),
        allReplaced: () => said.add('all'),
      );
      return (covers: covers, told: told, said: said);
    }

    List<String> names(int from, int to) => [
      for (var i = from; i < to; i++) 'al-$i',
    ];

    CatalogNames named(List<String> pids) => CatalogNames.of(pids);
    const unnamed = CatalogNames.unnamed();

    test('a frame\'s worth is the contract\'s bound on the names a frame '
        'carries', () {
      final spec = File('../../api/openapi.yaml').readAsStringSync();
      const header = '\n    WsEventFrame:\n';
      final frame = spec.indexOf(header);
      expect(frame, isNonNegative, reason: 'the frame is no longer a schema');
      // The frame's own schema: to the next header at its depth.
      final body = frame + header.length - 1;
      final next = RegExp(r'\n    \w+:\n').firstMatch(spec.substring(body));
      final schema = spec.substring(
        frame,
        next == null ? spec.length : body + next.start,
      );
      expect(schema, contains('\n        topic:\n'));
      final bound = RegExp(
        r'\n        pids:\n          type: array\n          maxItems: (\d+)\n',
      ).firstMatch(schema);
      expect(bound, isNotNull, reason: 'pids no longer states a bound');
      expect(kCatalogFrameNames, int.parse(bound!.group(1)!));
    });

    test('the browser suite waits by the same window', () {
      final driver = File(
        '../../e2e/tests/driver/surfaces/artwork.ts',
      ).readAsStringSync();
      final window = RegExp(
        r'^const catalogWindow = ([\d_]+);$',
        multiLine: true,
      ).firstMatch(driver);
      expect(window, isNotNull, reason: 'the driver no longer names it');
      expect(
        int.parse(window!.group(1)!.replaceAll('_', '')),
        kCatalogRefreshWindow.inMilliseconds,
      );
    });

    testWidgets('tells each name of a small frame as it is heard', (
      tester,
    ) async {
      final r = rule();
      r.covers.heard(named(['al-A', 'tr-B']));
      expect(r.told, ['al-A', 'tr-B']);
      // Named again, a cover may have been replaced again.
      r.covers.heard(named(['al-A']));
      expect(r.told, ['al-A', 'tr-B', 'al-A']);
      await tester.pump(window * 3);
      expect(r.said, isEmpty);
    });

    testWidgets('a window that names exactly one frame\'s worth is not '
        'busy', (tester) async {
      final r = rule();
      r.covers.heard(named(names(0, 40)));
      await tester.pump(second);
      r.covers.heard(named(names(20, kCatalogFrameNames)));
      expect(r.told, [...names(0, 40), ...names(20, kCatalogFrameNames)]);
      await tester.pump(window * 3);
      expect(r.said, isEmpty);
    });

    testWidgets('one name past a frame\'s worth in a window makes the '
        'stretch busy: the frame that crosses is not told, nor any after '
        'it, and every cover is owed once', (tester) async {
      final r = rule();
      r.covers.heard(named(names(0, kCatalogFrameNames)));
      await tester.pump(second);
      r.covers.heard(named(['ar-one-more', 'al-0']));
      expect(r.said, ['owed']);
      r.covers.heard(named(['al-1']));
      r.covers.heard(named(names(100, 200)));
      expect(r.told, names(0, kCatalogFrameNames));
      expect(r.said, ['owed']);
      r.covers.dispose();
    });

    testWidgets('a busy stretch ends a window after the one that ran over, '
        'in one ask', (tester) async {
      final r = rule();
      r.covers.heard(named(names(0, 65)));
      expect(r.said, ['owed']);

      // The window that ran over ends: the stretch goes on.
      await tester.pump(window);
      expect(r.said, ['owed']);
      // A window that stayed within the bound: the names it heard are
      // not told, the ask at its end covers them.
      await tester.pump(second);
      r.covers.heard(named(['al-A']));
      await tester.pump(window - second * 2);
      expect(r.said, ['owed']);
      await tester.pump(second);
      expect(r.said, ['owed', 'all']);
      expect(r.told, isEmpty);

      await tester.pump(window * 3);
      expect(r.said, ['owed', 'all'], reason: 'once a stretch');
    });

    testWidgets('busy is a rate: a trickle that never pauses is told by '
        'name, window after window', (tester) async {
      final r = rule();
      // Ten new names a second for a minute: fifty a window.
      for (var i = 0; i < 60; i++) {
        r.covers.heard(named(names(i * 10, i * 10 + 10)));
        await tester.pump(second);
      }
      expect(r.told, names(0, 600));
      expect(r.said, isEmpty);
      r.covers.dispose();
    });

    testWidgets('a stretch is busy for as long as its windows run over', (
      tester,
    ) async {
      final r = rule();
      // A frame past the bound every second for twelve.
      for (var i = 0; i < 12; i++) {
        r.covers.heard(named(names(i * 100, i * 100 + 65)));
        await tester.pump(second);
      }
      // Windows end at 5, 10 and 15 seconds, each having run over; the
      // one that ends at 20 heard nothing.
      await tester.pump(second * 7);
      expect(r.said, ['owed']);
      await tester.pump(second);
      expect(r.said, ['owed', 'all']);
      expect(r.told, isEmpty);
    });

    testWidgets('an unnamed marker makes the stretch busy at once, however '
        'little was named', (tester) async {
      final r = rule();
      r.covers.heard(named(['al-A']));
      r.covers.heard(unnamed);
      expect(r.said, ['owed']);
      r.covers.heard(named(['al-B']));
      expect(r.told, ['al-A']);

      await tester.pump(window * 2 - second);
      expect(r.said, ['owed']);
      await tester.pump(second);
      expect(r.said, ['owed', 'all']);
    });

    testWidgets('a marker alone opens a window, and one in a later window '
        'keeps the stretch going', (tester) async {
      final r = rule();
      // A marker every second for eight: windows end at 5, 10 and 15.
      for (var i = 0; i < 8; i++) {
        r.covers.heard(unnamed);
        await tester.pump(second);
      }
      await tester.pump(second * 6);
      expect(r.said, ['owed']);
      await tester.pump(second);
      expect(r.said, ['owed', 'all']);
    });

    testWidgets('the count starts over with each window, and after a busy '
        'stretch a name is told again', (tester) async {
      final r = rule();
      r.covers.heard(named(names(0, 60)));
      await tester.pump(window + second);
      r.covers.heard(named(names(60, 120)));
      expect(r.told, names(0, 120));
      await tester.pump(window * 3);
      expect(r.said, isEmpty);

      r.told.clear();
      r.covers.heard(named(names(0, 65)));
      await tester.pump(window * 2);
      expect(r.said, ['owed', 'all']);
      r.covers.heard(named(['al-A']));
      expect(r.told, ['al-A']);
      await tester.pump(window * 3);
      expect(r.said, ['owed', 'all']);
    });

    testWidgets('a session that ended tells nothing and asks nothing: what '
        'it owed stands', (tester) async {
      final r = rule();
      r.covers.heard(named(names(0, 65)));
      r.covers.dispose();
      r.covers.heard(named(['al-A']));
      r.covers.heard(unnamed);
      await tester.pump(window * 3);
      expect(r.told, isEmpty);
      expect(r.said, ['owed']);
    });
  });

  group('the names on a catalog frame', () {
    const window = kCatalogRefreshWindow;
    const second = Duration(seconds: 1);

    String shown(NetworkArtworkStore store, String artUrl) =>
        ((store.imageFor(artUrl, 64)! as ResizeImage).imageProvider
                as NetworkImage)
            .url;

    Matcher tagged(String artUrl) => matches(
      RegExp(
        '^${RegExp.escape(artUrl)}'
        r'[?&]size=64&v=\d+$',
      ),
    );

    List<String> albums(int from, int to) => [
      for (var i = from; i < to; i++) 'al-$i',
    ];

    /// What the store is told of [pid]: its front cover, once. The store
    /// keys a replacement by its entity, so that one URL stands for every
    /// picture the entity can hold.
    List<String> covers(FakeRepository repo, String pid) => [
      repo.artUrlFor(pid),
    ];

    /// Two frames a second apart that name more than a frame's worth
    /// between them. The first forty are told.
    Future<void> runOver(WidgetTester tester, _Session s, FakeLink link) async {
      await _frame(tester, s, link, albums(0, 40));
      await tester.pump(second);
      await _frame(tester, s, link, albums(40, 70));
    }

    testWidgets('are told replaced in the turn they are heard, before the '
        'refresh they prompt asks for anything', (tester) async {
      final repo = _Library(3);
      final store = NetworkArtworkStore(baseUrl: '');
      addTearDown(store.dispose);
      final link = FakeLink();
      final s = _bound(repo, link: link, artwork: store);
      s.container.listen(musicItemsProvider(_tracks), (_, _) {});
      await tester.pump(window * 2);
      final named = repo.artUrlFor('ar-A');
      final back = repo.artUrlFor('ar-A', role: 'back');
      final other = repo.artUrlFor('ar-B');
      expect(shown(store, named), '$named?size=64');
      // What a row would ask for, as the next listener of the same names
      // hears them: the turn after the binder's, so an eviction made any
      // later than on hearing them is not in it.
      final atNames = <String>[];
      final next = s.sync.catalogNamed.listen(
        (_) => atNames
          ..add(shown(store, named))
          ..add(shown(store, back)),
      );
      addTearDown(next.cancel);
      // And at each read the refresh makes.
      final atRead = <String>[];
      repo.requests.clear();
      repo.asked = () => atRead.add(shown(store, named));

      await _frame(tester, s, link, ['ar-A']);

      expect(atNames, [tagged(named), tagged(back)]);
      // The refresh is the one a frame that names nothing prompts.
      expect(repo.requests, [null]);
      expect(atRead.single, tagged(named));
      expect(shown(store, other), '$other?size=64');
      await _unbind(tester, s.container);
    });

    testWidgets('a small frame\'s names are told at once, whatever they '
        'name: once a name, by its front cover', (tester) async {
      final repo = _Library(3);
      final store = FakeArtworkStore();
      final link = FakeLink();
      final s = _bound(repo, link: link, artwork: store);
      final palettes = s.container.read(paletteCacheProvider);
      await tester.pump(window * 2);
      // A gone item is spelled as a track whatever it was.
      const pids = ['al-A', 'ar-B', 'bk-C', 'tr-GONE'];
      final urls = [for (final pid in pids) ...covers(repo, pid)];
      expect(urls, hasLength(pids.length));
      for (final url in urls) {
        palettes.remember(url, null);
      }

      await _frame(tester, s, link, pids);

      expect(store.evicted, urls);
      // The colour read off the old bytes goes with them.
      for (final url in urls) {
        expect(palettes.holds(url), isFalse);
      }

      // A frame that says nothing of what changed tells nothing.
      await _frame(tester, s, link);
      expect(store.evicted, hasLength(urls.length));
      await tester.pump(window * 3);
      expect(store.owedEvictAll, 0);
      expect(store.evictedAll, 0, reason: 'a small window asks nothing afresh');
      await _unbind(tester, s.container);
    });

    testWidgets('a window that runs over tells nothing by name after the '
        'bound, owes every cover at once, and asks each afresh exactly once '
        'a window later, sweeping no read', (tester) async {
      final repo = _Library(3);
      final store = FakeArtworkStore();
      final invalidations = _Invalidations();
      final link = FakeLink();
      final s = _bound(
        repo,
        observers: [invalidations],
        link: link,
        artwork: store,
      );
      // A paged listing and a plain read, both held open.
      final listing = musicItemsProvider(_tracks);
      final plain = booksProvider;
      s.container
        ..listen(listing, (_, _) {})
        ..listen(plain, (_, _) {});
      final palettes = s.container.read(paletteCacheProvider)
        ..remember('/art/any', null);
      await tester.pump(window * 2);

      await runOver(tester, s, link);
      expect(store.owedEvictAll, 1, reason: 'as the bound is crossed');
      await _frame(tester, s, link, ['al-0', 'ar-new']);

      expect(store.evicted, [
        for (final pid in albums(0, 40)) ...covers(repo, pid),
      ]);
      expect(store.evictedAll, 0, reason: 'not while the stretch goes on');

      // The window that ran over ends four seconds on; the one after it
      // hears nothing.
      await tester.pump(window * 2 - second * 2);
      expect(store.evictedAll, 0);
      invalidations.seen.clear();
      await tester.pump(second);

      expect(store.evictedAll, 1);
      expect(store.owedEvictAll, 1);
      expect(store.evicted, hasLength(40));
      expect(palettes.holds('/art/any'), isFalse);
      // The store tells every cover on screen to ask again; no read is
      // rebuilt for it.
      expect(invalidations.seen, isNot(contains(listing)));
      expect(invalidations.seen, isNot(contains(plain)));

      await tester.pump(window * 3);
      expect(store.evictedAll, 1);
      await _unbind(tester, s.container);
    });

    testWidgets('a scan that never rests is busy for as long as it runs, '
        'and once it slows to a trickle is answered by one ask and told by '
        'name again', (tester) async {
      final repo = _Library(3);
      final store = FakeArtworkStore();
      final link = FakeLink();
      final s = _bound(repo, link: link, artwork: store);
      await tester.pump(window * 2);

      // A frame past the bound every second for twelve.
      for (var i = 0; i < 12; i++) {
        await _frame(tester, s, link, albums(i * 100, i * 100 + 65));
        await tester.pump(second);
      }
      // Then a name every two seconds: the catalog is never silent for
      // a window, and no window runs over.
      for (var i = 0; i < 8; i++) {
        await _frame(tester, s, link, ['ar-$i']);
        await tester.pump(second * 2);
      }

      expect(store.owedEvictAll, 1);
      expect(store.evictedAll, 1);
      // The scan's names were not told; nor were the trickle's first, in
      // the window the ask at its end covers. The rest were.
      expect(store.evicted, isNot(contains(repo.artUrlFor('al-0'))));
      expect(store.evicted, isNot(contains(repo.artUrlFor('ar-0'))));
      expect(store.evicted, containsAll(covers(repo, 'ar-7')));
      await _unbind(tester, s.container);
    });

    testWidgets('a run of frames that left entities unnamed is busy, and '
        'ends in one ask', (tester) async {
      final repo = _Library(3);
      final store = FakeArtworkStore();
      final link = FakeLink();
      final s = _bound(repo, link: link, artwork: store);
      await tester.pump(window * 2);

      // A marker a second for eight: windows end at 5, 10 and 15.
      for (var i = 0; i < 8; i++) {
        await _frame(tester, s, link, null, true);
        await tester.pump(second);
      }
      expect(store.owedEvictAll, 1);
      await tester.pump(second * 6);
      expect(store.evictedAll, 0);
      await tester.pump(second);

      expect(store.evictedAll, 1);
      expect(store.owedEvictAll, 1);
      expect(store.evicted, isEmpty);
      await tester.pump(window * 3);
      expect(store.evictedAll, 1);
      await _unbind(tester, s.container);
    });

    testWidgets('a marker inside a small named run does the same', (
      tester,
    ) async {
      final repo = _Library(3);
      final store = FakeArtworkStore();
      final link = FakeLink();
      final s = _bound(repo, link: link, artwork: store);
      await tester.pump(window * 2);

      await _frame(tester, s, link, ['al-A']);
      await tester.pump(second);
      await _frame(tester, s, link, null, true);
      expect(store.owedEvictAll, 1);
      await _frame(tester, s, link, ['al-B']);
      expect(store.evicted, covers(repo, 'al-A'));

      await tester.pump(window * 2 - second * 2);
      expect(store.evictedAll, 0);
      await tester.pump(second);
      expect(store.evictedAll, 1);
      expect(store.evicted, covers(repo, 'al-A'));
      await _unbind(tester, s.container);
    });

    testWidgets('a resync of the catalog is a busy stretch of its own', (
      tester,
    ) async {
      final repo = _Library(3);
      final store = FakeArtworkStore();
      final link = FakeLink();
      final s = _bound(repo, link: link, artwork: store);
      await tester.pump(window * 2);

      link.attempts.last.onFrame(
        jsonEncode({'type': 'resync', 'topic': 'catalog'}),
      );
      await s.sync.beforeSync(() async {});
      await tester.pump(_tick);
      expect(store.owedEvictAll, 1);

      await tester.pump(window * 2 - second);
      expect(store.evictedAll, 0);
      await tester.pump(second);
      expect(store.evictedAll, 1);
      expect(store.evicted, isEmpty);
      await _unbind(tester, s.container);
    });

    testWidgets('a frame with neither names nor the marker changes '
        'nothing, however many come', (tester) async {
      final repo = _Library(3);
      final store = FakeArtworkStore();
      final link = FakeLink();
      final s = _bound(repo, link: link, artwork: store);
      await tester.pump(window * 2);

      await _frame(tester, s, link, albums(0, 60));
      for (var i = 0; i < 100; i++) {
        await _frame(tester, s, link);
      }
      await _frame(tester, s, link, ['al-0']);

      expect(store.evicted, hasLength(61));
      await tester.pump(window * 3);
      expect(store.owedEvictAll, 0);
      expect(store.evictedAll, 0);
      await _unbind(tester, s.container);
    });

    testWidgets('the next small frame after a busy stretch is told by name '
        'again', (tester) async {
      final repo = _Library(3);
      final store = FakeArtworkStore();
      final link = FakeLink();
      final s = _bound(repo, link: link, artwork: store);
      await tester.pump(window * 2);
      await runOver(tester, s, link);
      await tester.pump(window * 2);
      expect(store.evictedAll, 1);
      store.evicted.clear();

      await _frame(tester, s, link, ['al-41', 'ar-B']);

      expect(store.evicted, [
        ...covers(repo, 'al-41'),
        ...covers(repo, 'ar-B'),
      ]);
      await tester.pump(window * 3);
      expect(store.evictedAll, 1);
      expect(store.owedEvictAll, 1);
      await _unbind(tester, s.container);
    });

    testWidgets('the quiet edge re-reads the paged listings alone, after a '
        'busy stretch too', (tester) async {
      final repo = _Library(3);
      final invalidations = _Invalidations();
      final link = FakeLink();
      final s = _bound(repo, observers: [invalidations], link: link);
      final listing = musicItemsProvider(_tracks);
      final plain = booksProvider;
      s.container
        ..listen(listing, (_, _) {})
        ..listen(plain, (_, _) {});
      await tester.pump(window * 2);

      await _frame(tester, s, link, ['al-A']);
      await tester.pump(second);
      invalidations.seen.clear();
      await tester.pump(window);

      expect(invalidations.seen, contains(listing));
      expect(invalidations.seen, isNot(contains(plain)));

      // The edge inside a busy stretch is the same pass: the ask at the
      // stretch's end rebuilds no read. Half a second past
      // the paced pass the run's second frame was owed, the edge is half
      // a second off.
      await runOver(tester, s, link);
      await tester.pump(window - second + const Duration(milliseconds: 500));
      invalidations.seen.clear();
      await tester.pump(second);

      expect(invalidations.seen, contains(listing));
      expect(invalidations.seen, isNot(contains(plain)));
      await _unbind(tester, s.container);
    });

    /// A named frame said on [socket] as the server would, with nothing
    /// awaited: the session that would land its pull may be gone.
    void sayNamed(LinkedChannel socket, List<String> pids) => socket.onFrame(
      jsonEncode({'type': 'invalidate', 'topic': 'catalog', 'pids': pids}),
    );

    testWidgets('a session that ended is told nothing', (tester) async {
      final repo = _Library(3);
      final store = FakeArtworkStore();
      final link = FakeLink();
      final s = _bound(repo, link: link, artwork: store);
      await tester.pump(window * 2);
      final socket = link.attempts.last;

      // The binder goes as the signed-in tree does.
      s.binder.close();
      await tester.pump(_tick);
      // A frame can still arrive between the stop and the close, and
      // nothing before it made the stretch busy.
      sayNamed(socket, ['al-A']);
      await tester.pump(_tick);

      expect(store.evicted, isEmpty);
      await _unbind(tester, s.container);
    });

    testWidgets('a session that ended in a busy stretch asks nothing '
        'afresh: what it owed stands', (tester) async {
      final repo = _Library(3);
      final store = FakeArtworkStore();
      final link = FakeLink();
      final s = _bound(repo, link: link, artwork: store);
      await tester.pump(window * 2);
      await runOver(tester, s, link);
      expect(store.owedEvictAll, 1);

      s.binder.close();
      await tester.pump(_tick);
      await tester.pump(window * 3);

      expect(store.evictedAll, 0);
      expect(store.owedEvictAll, 1);
      await _unbind(tester, s.container);
    });
  });

  group('a playlist changed on the user stream', () {
    testWidgets('has its cover told replaced, and its colour forgotten', (
      tester,
    ) async {
      final repo = _Library(3);
      final store = FakeArtworkStore();
      final s = _bound(repo, artwork: store);
      await tester.pump(kUserRefreshWindow * 2);
      const pid = 'pl-01JZX5N8QW3F4V9T2B7KDPL001';
      final cover = repo.artUrlFor(pid);
      final palettes = s.container.read(paletteCacheProvider)
        ..remember(cover, null);

      // Another device changed it: its mosaic or its upload moved under
      // the one URL this server mints for it.
      s.container
          .read(serverEventBusProvider)
          .add(const ServerSyncEvent(kind: 'playlist', pid: pid));
      await tester.pump(_tick);

      expect(store.evicted, [cover]);
      expect(palettes.holds(cover), isFalse);
      await _unbind(tester, s.container);
    });

    testWidgets('that the stream does not name has every held playlist\'s '
        'cover told replaced', (tester) async {
      final repo = _Library(3);
      final store = FakeArtworkStore();
      final s = _bound(repo, artwork: store);
      for (final (pid, art) in [
        ('pl-A', true),
        ('pl-B', true),
        ('pl-C', false),
      ]) {
        repo.playlistsByPid[pid] = Playlist(
          pid: pid,
          name: pid,
          kind: 'static',
          visibility: 'private',
          ownerName: 'me',
          isOwner: true,
          artUrl: art ? repo.artUrlFor(pid) : null,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );
      }
      final listed = s.container.listen(playlistsProvider, (_, _) {});
      await tester.pump(kUserRefreshWindow * 2);
      expect(s.container.read(playlistsProvider).requireValue, hasLength(3));

      s.container
          .read(serverEventBusProvider)
          .add(const ServerSyncEvent(kind: 'playlist'));
      await tester.pump(_tick);

      expect(store.evicted, [repo.artUrlFor('pl-A'), repo.artUrlFor('pl-B')]);
      listed.close();
      await _unbind(tester, s.container);
    });
  });

  group('a window longer than a second', () {
    for (final (name, window) in <(String, Duration)>[
      ('catalog', kCatalogRefreshWindow),
      ('user', kUserRefreshWindow),
    ]) {
      testWidgets('the $name window still lets the first hint through at once '
          'and holds the rest to its end', (tester) async {
        var runs = 0;
        final paced = PacedRefresh(
          fanOut: () {
            runs++;
            return true;
          },
          window: window,
        );

        paced.hint();
        expect(runs, 1, reason: 'a lone change still lands immediately');
        await tester.pump(const Duration(seconds: 1));
        paced.hint();
        await tester.pump(window - const Duration(seconds: 1, milliseconds: 1));
        expect(runs, 1, reason: 'a second later is still inside the window');
        await tester.pump(const Duration(milliseconds: 2));
        expect(runs, 2, reason: 'and it runs at the end of it');
        paced.dispose();
      });

      testWidgets('the $name window costs one pass per window under a scan', (
        tester,
      ) async {
        var runs = 0;
        final paced = PacedRefresh(
          fanOut: () {
            runs++;
            return true;
          },
          window: window,
        );

        // A scan's catalog hint about once a second, for ten seconds.
        for (var second = 0; second < 10; second++) {
          paced.hint();
          await tester.pump(const Duration(seconds: 1));
        }
        await tester.pump(window);
        expect(runs, 1 + 10 ~/ window.inSeconds);
        paced.dispose();
      });
    }
  });

  group('FirstBuildObserver', () {
    test('tracks a first build from birth to landing', () async {
      final observer = FirstBuildObserver();
      final repository = _GatedRepository(items: const [_track]);
      final created = await repository.createPlaylist(
        name: 'By Hand',
        kind: 'static',
      );
      final container = appContainer(repo: repository, observers: [observer]);

      repository.gatedPid = created.pid;
      final gate = repository.gate = Completer<void>();
      final instance = playlistDetailProvider(created.pid);
      final sub = container.listen(instance, (_, _) {});
      addTearDown(sub.close);
      expect(observer.inFirstBuild(instance), isTrue);

      gate.complete();
      repository.gate = null;
      await container.read(instance.future);
      expect(observer.inFirstBuild(instance), isFalse);

      // A refresh is not a first build: the previous value rides along,
      // so the screen never shows a skeleton and the ledger stays out.
      container.invalidate(instance);
      expect(observer.inFirstBuild(instance), isFalse);
      await container.read(instance.future);
      expect(observer.inFirstBuild(instance), isFalse);
    });

    test(
      'an invalidation that cancels a first build prunes its entry',
      () async {
        final observer = FirstBuildObserver();
        final repository = _GatedRepository(items: const [_track]);
        final created = await repository.createPlaylist(
          name: 'By Hand',
          kind: 'static',
        );
        final container = appContainer(repo: repository, observers: [observer]);
        final fanOut = InvalidationFanOut(
          container: container,
          firstBuilds: observer,
          families: [playlistDetailProvider],
        );

        repository.gatedPid = created.pid;
        final gate = repository.gate = Completer<void>();
        final instance = playlistDetailProvider(created.pid);
        final sub = container.listen(instance, (_, _) {});
        expect(observer.inFirstBuild(instance), isTrue);

        // The screen leaves mid-build; the keep-alive element stays,
        // still building. A mutation then invalidates it from outside
        // the fan-out (appendTo on an unopened playlist has exactly this
        // shape), which cancels the build: the landing this entry was
        // waiting for will never notify.
        sub.close();
        container.invalidate(instance);
        expect(
          observer.inFirstBuild(instance),
          isFalse,
          reason: 'a cancelled build is pruned, not deferred forever',
        );
        expect(
          fanOut.sweep(),
          isTrue,
          reason: 'nothing is owed for it, so no retry timer re-arms',
        );
        gate.complete();
      },
    );

    test('a first build that fails is a landing, not a hang', () async {
      // The edge the entry named: a first build that never lands kept
      // its topic's retry timer re-arming for the life of the session.
      // Request deadlines close it - a hung request now ends in a
      // timeout, and an error landing prunes the ledger exactly as a
      // value landing does.
      final observer = FirstBuildObserver();
      final repository = _GatedRepository(items: const [_track]);
      final created = await repository.createPlaylist(
        name: 'By Hand',
        kind: 'static',
      );
      final container = appContainer(repo: repository, observers: [observer]);
      final fanOut = InvalidationFanOut(
        container: container,
        firstBuilds: observer,
        families: [playlistDetailProvider],
      );

      repository.gatedPid = created.pid;
      final gate = repository.gate = Completer<void>();
      final instance = playlistDetailProvider(created.pid);
      final sub = container.listen(instance, (_, _) {});
      addTearDown(sub.close);
      expect(observer.inFirstBuild(instance), isTrue);

      gate.completeError(
        const WaxDeckApiException(
          code: 'timeout',
          message: 'the server did not answer in time',
        ),
      );
      await pumpEventQueue();
      // Riverpod 3 retries a failed provider on its own, so the state
      // that follows is a loading carrying the error rather than a bare
      // AsyncError. Either way the build landed, which is what the
      // ledger keys on.
      expect(container.read(instance).hasError, isTrue);

      expect(
        observer.inFirstBuild(instance),
        isFalse,
        reason: 'an error is a landing',
      );
      expect(
        fanOut.sweep(),
        isTrue,
        reason: 'nothing is owed for it, so no retry timer re-arms',
      );
    });
  });

  group('InvalidationFanOut', () {
    test(
      'defers the building instance and invalidates the loaded one',
      () async {
        final observer = FirstBuildObserver();
        final repository = _GatedRepository(items: const [_track]);
        final loaded = await repository.createPlaylist(
          name: 'Loaded',
          kind: 'static',
        );
        final opening = await repository.createPlaylist(
          name: 'Opening',
          kind: 'static',
        );
        final container = appContainer(repo: repository, observers: [observer]);
        final fanOut = InvalidationFanOut(
          container: container,
          firstBuilds: observer,
          families: [playlistDetailProvider],
        );
        int builds(String pid) =>
            repository.playlistItemPageCalls.where((p) => p == pid).length;

        final loadedSub = container.listen(
          playlistDetailProvider(loaded.pid),
          (_, _) {},
        );
        addTearDown(loadedSub.close);
        await container.read(playlistDetailProvider(loaded.pid).future);
        expect(builds(loaded.pid), 1);

        repository.gatedPid = opening.pid;
        final gate = repository.gate = Completer<void>();
        final openingSub = container.listen(
          playlistDetailProvider(opening.pid),
          (_, _) {},
        );
        addTearDown(openingSub.close);

        expect(fanOut.sweep(), isFalse, reason: 'one instance was deferred');
        await container.read(playlistDetailProvider(loaded.pid).future);
        expect(builds(loaded.pid), 2, reason: 'the loaded instance refetched');
        expect(
          builds(opening.pid),
          0,
          reason: 'the building one was left alone',
        );

        // Still in flight at the retry: still deferred, still untouched.
        expect(fanOut.retry(), isFalse);

        gate.complete();
        repository.gate = null;
        await container.read(playlistDetailProvider(opening.pid).future);
        expect(
          builds(opening.pid),
          1,
          reason: 'exactly one build: the first was never restarted',
        );

        expect(fanOut.retry(), isTrue, reason: 'the landing releases the debt');
        await container.read(playlistDetailProvider(opening.pid).future);
        expect(
          builds(opening.pid),
          2,
          reason: 'the deferred invalidation applied once the build landed',
        );
      },
    );

    test('without the ledger everything invalidates at once', () async {
      final repository = _GatedRepository(items: const [_track]);
      final created = await repository.createPlaylist(
        name: 'By Hand',
        kind: 'static',
      );
      final container = appContainer(repo: repository);
      final fanOut = InvalidationFanOut(
        container: container,
        families: [playlistDetailProvider],
      );

      repository.gatedPid = created.pid;
      final gate = repository.gate = Completer<void>();
      final sub = container.listen(
        playlistDetailProvider(created.pid),
        (_, _) {},
      );
      addTearDown(sub.close);

      expect(
        fanOut.sweep(),
        isTrue,
        reason: 'no ledger means nothing defers: the pre-deferral behavior',
      );
      gate.complete();
      repository.gate = null;
    });

    test(
      'an unwatched invalidation stays lazy: no build is triggered',
      () async {
        final observer = FirstBuildObserver();
        final repository = _GatedRepository(items: const [_track]);
        await repository.createPlaylist(name: 'By Hand', kind: 'static');
        final container = appContainer(repo: repository, observers: [observer]);
        final fanOut = InvalidationFanOut(
          container: container,
          firstBuilds: observer,
          providers: [playlistsProvider],
        );

        // Built once, then left: the keep-alive element persists with no
        // listener, which is every screen the user has visited and left.
        final sub = container.listen(playlistsProvider, (_, _) {});
        await container.read(playlistsProvider.future);
        sub.close();
        expect(repository.listingReads, 1);

        for (var i = 0; i < 3; i++) {
          expect(fanOut.sweep(), isTrue);
          await container.pump();
        }
        expect(
          repository.listingReads,
          1,
          reason: 'marking an unwatched element dirty must not rebuild it',
        );

        // The mark was real: the next watcher rebuilds from it.
        final again = container.listen(playlistsProvider, (_, _) {});
        addTearDown(again.close);
        await container.read(playlistsProvider.future);
        expect(repository.listingReads, 2);
      },
    );

    test('a provider outside the targets is untouched', () async {
      final observer = FirstBuildObserver();
      final repository = _GatedRepository(items: const [_track]);
      final created = await repository.createPlaylist(
        name: 'By Hand',
        kind: 'static',
      );
      final container = appContainer(repo: repository, observers: [observer]);
      final fanOut = InvalidationFanOut(
        container: container,
        firstBuilds: observer,
        providers: [playlistsProvider],
      );

      final sub = container.listen(
        playlistDetailProvider(created.pid),
        (_, _) {},
      );
      addTearDown(sub.close);
      await container.read(playlistDetailProvider(created.pid).future);
      final builds = repository.playlistItemPageCalls.length;

      expect(fanOut.sweep(), isTrue);
      await container.pump();
      await container.read(playlistDetailProvider(created.pid).future);
      expect(repository.playlistItemPageCalls.length, builds);
    });
  });

  testWidgets('a first build slower than the window still lands', (
    tester,
  ) async {
    final observer = FirstBuildObserver();
    final repository = _SlowRepository(items: const [_track]);
    final created = await repository.createPlaylist(
      name: 'By Hand',
      kind: 'static',
    );
    final container = appContainer(
      repo: repository,
      extra: [filePickerProvider.overrideWithValue(null)],
      observers: [observer],
    );
    final fanOut = InvalidationFanOut(
      container: container,
      firstBuilds: observer,
      families: [playlistDetailProvider],
    );
    final paced = PacedRefresh(fanOut: fanOut.sweep, retry: fanOut.retry);

    await mountApp(
      tester,
      PlaylistScreen(pid: created.pid),
      container: container,
      pushed: true,
    );

    // Five seconds of an unrelenting server. The build takes 1.4 s
    // against a 1 s window, so pacing alone restarts it forever; the
    // deferral is what lets it land.
    var settled = false;
    for (var tick = 0; tick < 40; tick++) {
      paced.hint();
      await tester.pump(const Duration(milliseconds: 125));
      if (_showsAddField()) settled = true;
    }
    paced.dispose();
    expect(
      settled,
      isTrue,
      reason: 'the first build finished while the hints kept coming',
    );
    // Lets the deferred invalidation's own refetch land.
    for (var i = 0; i < 6; i++) {
      await tester.pump(_SlowRepository.latency * 2);
    }
    expect(_showsAddField(), isTrue);
  });

  testWidgets('without the ledger the same storm starves the build', (
    tester,
  ) async {
    final repository = _SlowRepository(items: const [_track]);
    final created = await repository.createPlaylist(
      name: 'By Hand',
      kind: 'static',
    );
    final container = appContainer(
      repo: repository,
      extra: [filePickerProvider.overrideWithValue(null)],
    );
    // No FirstBuildObserver: this is the pre-deferral wiring, kept
    // failing on purpose so the mechanism above cannot quietly rot.
    final fanOut = InvalidationFanOut(
      container: container,
      families: [playlistDetailProvider],
    );
    final paced = PacedRefresh(fanOut: fanOut.sweep, retry: fanOut.retry);

    await mountApp(
      tester,
      PlaylistScreen(pid: created.pid),
      container: container,
      pushed: true,
    );

    var settled = false;
    for (var tick = 0; tick < 40; tick++) {
      paced.hint();
      await tester.pump(const Duration(milliseconds: 125));
      if (_showsAddField()) settled = true;
    }
    paced.dispose();
    expect(
      settled,
      isFalse,
      reason: 'a 1.4 s build never survives 1 s restart windows',
    );
    // The storm over, the last restart completes.
    for (var i = 0; i < 6; i++) {
      await tester.pump(_SlowRepository.latency * 2);
    }
    expect(_showsAddField(), isTrue);
  });
}

bool _showsAddField() => find
    .bySemanticsIdentifier(SemanticsIds.playlistAddField)
    .evaluate()
    .isNotEmpty;
