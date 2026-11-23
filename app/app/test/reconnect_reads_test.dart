import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderBase;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/admin_providers.dart';
import 'package:waxdeck/src/connectivity/connectivity_port.dart';
import 'package:waxdeck/src/health/health_controller.dart';
import 'package:waxdeck/src/home/home_screen.dart';
import 'package:waxdeck/src/home/home_shelves.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/playlists/playlists_controller.dart';
import 'package:waxdeck/src/providers.dart' show connectivityProvider;
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_recheck.dart';
import 'package:waxdeck/src/review/review_controller.dart';
import 'package:waxdeck/src/sharing/shares_controller.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/sync/refresh_in_place.dart';
import 'package:waxdeck/src/sync/refresh_pacing.dart';
import 'package:waxdeck/src/sync/sync_binder.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import 'app_host.dart';
import 'fakes.dart';

// A client that comes back after an outage presents the catalog cursor
// its mirror holds, and the server answers it with one catalog
// invalidation saying what changed after it. An answer saying nothing in
// the catalog changed leaves Home's shelves, built as the socket comes up,
// and any list held open across the outage current, so nothing is read
// again for it. Any other answer, one naming nothing included, is a pass.

const _held = 'c-held';
const _head = 'c-head';

const _away = 'tr-01JZX5N8QW3F4V9T2B7KDAWAY01';

/// A server the device was away from: a pull from the cursor it holds
/// finds [whileAway], and one from the head finds nothing. Each pull
/// takes a while, as over a real link, so the shelves Home builds as the
/// socket comes up have landed before the pull the answer prompts ends.
class _Server extends FakeRepository {
  _Server() : super(items: [testItem(_away, title: 'Changed While Away')]);

  List<CatalogSyncEntry> whileAway = const [];

  /// Refuses every list read while set, as a server out of reach does.
  bool down = false;

  static const _refused = WaxDeckApiException(
    code: 'transport',
    message: 'connection refused',
  );

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
    if (down) throw _refused;
    return super.browse(
      list,
      mediaType: mediaType,
      facet: facet,
      facetKey: facetKey,
      cursor: cursor,
      limit: limit,
      seed: seed,
    );
  }

  @override
  Future<ItemPage> listItems({
    MediaType? mediaType,
    String? facet,
    String? facetKey,
    String? cursor,
    int? limit,
  }) async {
    if (down) throw _refused;
    return super.listItems(
      mediaType: mediaType,
      facet: facet,
      facetKey: facetKey,
      cursor: cursor,
      limit: limit,
    );
  }

  @override
  Future<List<LibraryInfo>> listLibraries({bool counts = false}) async {
    if (down) throw _refused;
    return super.listLibraries(counts: counts);
  }

  /// Every read of the review queue answered.
  var reviewReads = 0;

  @override
  Future<ReviewEntryPage> listReviewQueue({
    String? status,
    String? cursor,
    int? limit,
  }) async {
    final page = await super.listReviewQueue(
      status: status,
      cursor: cursor,
      limit: limit,
    );
    reviewReads++;
    return page;
  }

  /// Every read of the caller's playlists answered.
  var playlistReads = 0;

  @override
  Future<PlaylistPage> listPlaylists({
    String? cursor,
    int? limit,
    String? containsItem,
  }) async {
    if (down) throw _refused;
    playlistReads++;
    return super.listPlaylists(
      cursor: cursor,
      limit: limit,
      containsItem: containsItem,
    );
  }

  /// Every read of the duplicate groups answered.
  var duplicateReads = 0;

  @override
  Future<List<DuplicateGroup>> listDuplicates() async {
    if (down) throw _refused;
    duplicateReads++;
    return super.listDuplicates();
  }

  /// Every read of the caller's share links answered.
  var shareReads = 0;

  @override
  Future<SharePage> listShares({
    String? cursor,
    int? limit,
    bool all = false,
  }) async {
    if (down) throw _refused;
    if (!all) shareReads++;
    return super.listShares(cursor: cursor, limit: limit, all: all);
  }

  /// Holds the next lookup until completed; completed with an error, the
  /// lookup fails with it.
  Completer<void>? lookupHeld;

  @override
  Future<ItemResolution> resolveItems(List<String> pids) async {
    final held = lookupHeld;
    lookupHeld = null;
    if (held != null) await held.future;
    if (down) throw _refused;
    return super.resolveItems(pids);
  }

  @override
  Future<CatalogSyncPage> syncCatalog({
    String? since,
    String? cursor,
    int? limit,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (since == _held) {
      return CatalogSyncPage(entries: whileAway, nextSince: _head);
    }
    return const CatalogSyncPage(nextSince: _head);
  }
}

/// Every list Home reads, with how many times it was asked.
Map<DiscoveryList, int> _reads(_Server server) {
  final counts = <DiscoveryList, int>{};
  for (final call in server.browseCalls) {
    counts.update(call.list, (n) => n + 1, ifAbsent: () => 1);
  }
  return counts;
}

const _shelves = [
  DiscoveryList.inProgress,
  DiscoveryList.recentlyAdded,
  DiscoveryList.neverPlayed,
  DiscoveryList.rediscover,
  DiscoveryList.mostPlayed,
];

Map<DiscoveryList, int> _each(int n) => {for (final list in _shelves) list: n};

/// The tracks index: a listing that refreshes in place.
const MusicListing _tracks = (
  dimension: null,
  segment: '',
  domain: BrowseDomain.music,
);

/// How many times the tracks index was read and answered.
int _listingReads(_Server server) => server.listItemsCalls
    .where(
      (call) =>
          call.facet == null &&
          call.mediaType == MediaType.music &&
          call.limit == MusicItemsController.pageSize,
    )
    .length;

/// Home on its offline state, its engine's socket out of reach, and the
/// mirror holding the cursor of an earlier session, or none ([cursor]
/// false: a first start).
typedef _Home = ({
  _Server server,
  FakeLink link,
  SyncEngine sync,
  ProviderContainer container,
});

Future<_Home> _offlineHome(
  WidgetTester tester, {
  bool cursor = true,
  Duration? Function(int retryCount, Object error)? retry,
}) async {
  final home = await _offlineSession(cursor: cursor, retry: retry);
  await mountApp(tester, const HomeScreen(), container: home.container);
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.bySemanticsIdentifier(SemanticsIds.offlineBanner), findsOne);
  expect(home.server.browseCalls, isEmpty);
  return home;
}

/// [_offlineHome] with no screen mounted: the session's binder alone.
Future<_Home> _offlineSession({
  bool cursor = true,
  Duration? Function(int retryCount, Object error)? retry,
  List<Override> extra = const [],
}) async {
  final db = inMemoryMirrorDatabase();
  addTearDown(db.close);
  if (cursor) {
    await db
        .into(db.syncCursors)
        .insert(SyncCursorsCompanion.insert(catalogSince: const Value(_held)));
  }
  final server = _Server();
  final link = FakeLink()..reachable = false;
  final sync = SyncEngine(
    db: db,
    repository: server,
    channelFactory: link.factory,
  );
  addTearDown(sync.dispose);
  final downloads = FakeDownloads();
  addTearDown(downloads.dispose);
  final container = appContainer(
    repo: server,
    mirror: db,
    downloads: downloads,
    sync: sync,
    observers: [FirstBuildObserver()],
    retry: retry,
    extra: extra,
  );
  final binder = container.listen(syncBinderProvider, (_, _) {});
  addTearDown(binder.close);
  return (server: server, link: link, sync: sync, container: container);
}

/// The server comes back, the socket comes up on its next attempt, and
/// everything the reconnect prompts has had its windows to run in.
Future<void> _comeBack(WidgetTester tester, _Home home) async {
  home.link.reachable = true;
  await _settle(tester);
  expect(find.bySemanticsIdentifier(SemanticsIds.offlineBanner), findsNothing);
}

/// Long enough for every pass a word prompts, window ends included.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// [list] held open from before the outage, as a screen left mounted
/// holds it, read once there.
Future<void> _holdOpen(
  WidgetTester tester,
  _Home home,
  ProviderBase<Object?> list,
) async {
  final held = home.container.listen(list, (_, _) {});
  addTearDown(held.close);
  await tester.pump(const Duration(milliseconds: 50));
}

/// The socket comes up on its next attempt, answered [answer], and what
/// that prompts has run.
Future<void> _reconnect(
  WidgetTester tester,
  _Home session,
  Map<String, Object?> answer,
) async {
  session.link
    ..catalogAnswer = answer
    ..reachable = true;
  // The socket's waits may have grown to their longest meanwhile.
  await tester.pump(const Duration(seconds: 70));
  await _settle(tester);
  expect(session.sync.current.online, isTrue);
}

/// [read] held open, then failing while the server refuses until every
/// retry is spent, and the server back.
Future<void> _failWhileAway(
  WidgetTester tester,
  _Home session,
  ProviderBase<Object?> read,
) async {
  await _holdOpen(tester, session, read);
  session.server.down = true;
  session.container.invalidate(read);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(seconds: 10));
  }
  expect(session.container.read(read), isA<AsyncError<Object?>>());
  session.server.down = false;
}

/// Ends [session] inside the test: playback's and the pacers' timers go
/// with it.
Future<void> _end(WidgetTester tester, _Home session) async {
  session.container.read(queueControllerProvider.notifier).clear();
  await tester.pump(const Duration(seconds: 1));
  session.container.dispose();
  await tester.pump();
}

/// The platform's transports as the plugin reports them: [now] when
/// asked, and each change.
class _Transports extends ConnectivityPlatform {
  _Transports(this.now);

  List<ConnectivityResult> now;
  final _changes = StreamController<List<ConnectivityResult>>.broadcast();

  void change(List<ConnectivityResult> to) {
    now = to;
    _changes.add(to);
  }

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => now;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _changes.stream;
}

/// [_offlineSession] over the port the device runs, on [transports].
Future<_Home> _portSession(_Transports transports) {
  final previous = ConnectivityPlatform.instance;
  ConnectivityPlatform.instance = transports;
  addTearDown(() => ConnectivityPlatform.instance = previous);
  return _offlineSession(
    extra: [connectivityProvider.overrideWithValue(PluginConnectivity())],
  );
}

/// [_portSession] whose socket came up and stays up.
Future<_Home> _connectedSession(
  WidgetTester tester,
  _Transports transports,
) async {
  final s = await _portSession(transports);
  await _reconnect(tester, s, const {'unchanged': true});
  return s;
}

/// How many times the library's newest was read and answered.
int _newestReads(_Server server) =>
    _reads(server)[DiscoveryList.recentlyAdded] ?? 0;

/// How many times Home's probe was answered.
int _probeReads(_Server server) =>
    server.listItemsCalls.where((call) => call.mediaType == null).length;

/// How many times the libraries' counts were answered.
int _countReads(_Server server) =>
    server.listLibrariesCalls.where((counts) => counts).length;

CatalogSyncEntry get _changed => CatalogSyncEntry(
  op: 'upsert',
  pid: _away,
  item: testItem(_away, title: 'Changed While Away'),
);

void main() {
  testWidgets('a reconnect answered with nothing changed reads each home '
      'list once', (tester) async {
    final home = await _offlineHome(tester);
    home.link.catalogAnswer = {'unchanged': true};
    await _comeBack(tester, home);
    expect(_reads(home.server), _each(1));
  });

  testWidgets('a reconnect answered with a change named since the cursor '
      'reads the lists again', (tester) async {
    final home = await _offlineHome(tester);
    home.server.whileAway = [_changed];
    home.link.catalogAnswer = {
      'pids': [_away],
    };
    await _comeBack(tester, home);
    // The pull from the held cursor finds the change, and the answer's
    // pull reads the shelves again a window later.
    expect(_reads(home.server), _each(3));
  });

  testWidgets('a reconnect answered with nothing named and nothing unnamed, '
      'as for a genre changed while away, reads the lists again', (
    tester,
  ) async {
    final home = await _offlineHome(tester);
    await _comeBack(tester, home);
    expect(_reads(home.server), _each(2));
  });

  testWidgets('a reconnect answered with entities changed and not named '
      'reads the lists again', (tester) async {
    final home = await _offlineHome(tester);
    home.link.catalogAnswer = {'unnamed': true};
    await _comeBack(tester, home);
    expect(_reads(home.server), _each(2));
  });

  testWidgets('a first start, which presents no cursor, reads the lists '
      'again once the mirror is taken', (tester) async {
    final home = await _offlineHome(tester, cursor: false);
    await _comeBack(tester, home);
    expect(_reads(home.server), _each(2));
  });

  testWidgets('a list open from before the outage is not read again when the '
      'answer says nothing changed', (tester) async {
    final home = await _offlineHome(tester);
    await _holdOpen(tester, home, recentlyAddedShelfProvider);
    expect(_reads(home.server), {DiscoveryList.recentlyAdded: 1});
    home.link.catalogAnswer = {'unchanged': true};
    await _comeBack(tester, home);
    expect(_reads(home.server), _each(1));
  });

  testWidgets('a list that failed during the outage is read again, once, '
      'when the answer says nothing changed', (tester) async {
    final home = await _offlineHome(tester, retry: (_, _) => null);
    home.server.down = true;
    await _holdOpen(tester, home, recentlyAddedShelfProvider);
    expect(home.container.read(recentlyAddedShelfProvider).hasError, isTrue);
    home.server.down = false;
    home.link.catalogAnswer = {'unchanged': true};
    await _comeBack(tester, home);
    expect(_reads(home.server), _each(1));
  });

  testWidgets('a list that held rows and whose read again failed during the '
      'outage is read again when the answer says nothing changed', (
    tester,
  ) async {
    final home = await _offlineHome(tester, retry: (_, _) => null);
    await _holdOpen(tester, home, recentlyAddedShelfProvider);
    home.server.down = true;
    home.container.invalidate(recentlyAddedShelfProvider);
    await tester.pump(const Duration(milliseconds: 50));
    final failed = home.container.read(recentlyAddedShelfProvider);
    expect((failed.hasError, failed.hasValue), (true, true));
    home.server.down = false;
    home.link.catalogAnswer = {'unchanged': true};
    await _comeBack(tester, home);
    expect(_reads(home.server), {..._each(1), DiscoveryList.recentlyAdded: 2});
  });

  testWidgets('a listing whose refresh failed and gave up is refreshed when '
      'the answer says nothing changed', (tester) async {
    final home = await _offlineHome(tester);
    final listing = musicItemsProvider(_tracks);
    await _holdOpen(tester, home, listing);
    expect(_listingReads(home.server), 1);
    home.server.down = true;
    home.container.read(listing.notifier).owe(CatalogRefresh.head);
    home.container.invalidate(listing);
    // The refresh and every attempt after it fail, and it stops asking.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(seconds: 10));
    }
    expect(_listingReads(home.server), 1, reason: 'each attempt refused');
    home.server.down = false;
    home.link.catalogAnswer = {'unchanged': true};
    // The socket's waits have grown to their longest meanwhile.
    home.link.reachable = true;
    await tester.pump(const Duration(seconds: 70));
    await _comeBack(tester, home);
    expect(_listingReads(home.server), 2);
    expect(_reads(home.server), _each(1));
  });

  testWidgets('a list open from before the outage is read again when the '
      'answer names nothing and leaves nothing unnamed', (tester) async {
    final home = await _offlineHome(tester);
    await _holdOpen(tester, home, recentlyAddedShelfProvider);
    await _comeBack(tester, home);
    expect(_reads(home.server), _each(2));
  });

  testWidgets('a list open from before the outage is read again when the '
      'answer names a change', (tester) async {
    final home = await _offlineHome(tester);
    await _holdOpen(tester, home, recentlyAddedShelfProvider);
    home.link.catalogAnswer = {
      'pids': [_away],
    };
    await _comeBack(tester, home);
    // Held or built as the socket came up, each list is read again.
    expect(_reads(home.server), _each(2));
  });

  group('the reads asked once a run of changes goes quiet', () {
    const nothingChanged = {'unchanged': true};

    testWidgets('are not read again when the answer says nothing changed '
        'and each read went through', (tester) async {
      final s = await _offlineSession();
      for (final read in <ProviderBase<Object?>>[
        libraryHasAnythingProvider,
        libraryCountsProvider,
        duplicatesProvider,
        musicItemsProvider(_tracks),
      ]) {
        await _holdOpen(tester, s, read);
      }
      s.container.read(queueControllerProvider.notifier).addToEnd([_away]);
      await s.container.read(queueRecheckProvider).run();
      final (probe, counts, duplicates, listing, lookups) = (
        _probeReads(s.server),
        _countReads(s.server),
        s.server.duplicateReads,
        _listingReads(s.server),
        s.server.resolvedItemPids.length,
      );
      expect((probe, counts, duplicates, listing, lookups), (1, 1, 1, 1, 1));
      await _reconnect(tester, s, nothingChanged);
      expect(
        (
          _probeReads(s.server),
          _countReads(s.server),
          s.server.duplicateReads,
          _listingReads(s.server),
          s.server.resolvedItemPids.length,
        ),
        (probe, counts, duplicates, listing, lookups),
      );
      await _end(tester, s);
    });

    testWidgets('read Home\'s probe again when it failed', (tester) async {
      final s = await _offlineSession();
      await _failWhileAway(tester, s, libraryHasAnythingProvider);
      final before = _probeReads(s.server);
      await _reconnect(tester, s, nothingChanged);
      expect(_probeReads(s.server), before + 1);
      await _end(tester, s);
    });

    testWidgets('read the libraries\' counts again when they failed', (
      tester,
    ) async {
      final s = await _offlineSession();
      await _failWhileAway(tester, s, libraryCountsProvider);
      final before = _countReads(s.server);
      await _reconnect(tester, s, nothingChanged);
      expect(_countReads(s.server), before + 1);
      await _end(tester, s);
    });

    testWidgets('read an audit again when it failed', (tester) async {
      final s = await _offlineSession();
      await _failWhileAway(tester, s, duplicatesProvider);
      final before = s.server.duplicateReads;
      await _reconnect(tester, s, nothingChanged);
      expect(s.server.duplicateReads, before + 1);
      await _end(tester, s);
    });

    testWidgets('read an audit again when its refresh failed and gave up', (
      tester,
    ) async {
      final s = await _offlineSession();
      await _holdOpen(tester, s, sharesProvider);
      expect(s.server.shareReads, 1);
      s.server.down = true;
      s.container.invalidate(sharesProvider);
      // The refresh and every attempt after it fail, and it stops asking.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(seconds: 10));
      }
      expect(s.container.read(sharesProvider).hasError, isFalse);
      s.server.down = false;
      await _reconnect(tester, s, nothingChanged);
      expect(s.server.shareReads, 2);
      await _end(tester, s);
    });

    testWidgets('look the queue\'s items up again when the last lookup '
        'failed', (tester) async {
      final s = await _offlineSession();
      s.container.read(queueControllerProvider.notifier).addToEnd([_away]);
      s.server.down = true;
      await s.container.read(queueRecheckProvider).run();
      s.server.down = false;
      final before = s.server.resolvedItemPids.length;
      await _reconnect(tester, s, nothingChanged);
      expect(s.server.resolvedItemPids.length, before + 1);
      await _end(tester, s);
    });

    testWidgets('look the queue\'s items up again when a lookup under way '
        'as the answer arrives then fails', (tester) async {
      final s = await _offlineSession();
      s.container.read(queueControllerProvider.notifier).addToEnd([_away]);
      final held = s.server.lookupHeld = Completer<void>();
      final pass = s.container.read(queueRecheckProvider).run();
      await _reconnect(tester, s, nothingChanged);
      final before = s.server.resolvedItemPids.length;
      held.completeError(_Server._refused);
      await tester.pump(const Duration(seconds: 1));
      await pass;
      expect(s.server.resolvedItemPids.length, before + 1);
      await _end(tester, s);
    });
  });

  group('the device\'s network coming back', () {
    const none = [ConnectivityResult.none];
    const wifi = [ConnectivityResult.wifi];

    testWidgets('with the socket up, reads a list in error again, '
        'once', (tester) async {
      final transports = _Transports(wifi);
      final s = await _connectedSession(tester, transports);
      transports.change(none);
      await _failWhileAway(tester, s, recentlyAddedShelfProvider);
      final (before, attempts) = (
        _newestReads(s.server),
        s.link.attempts.length,
      );
      transports.change(wifi);
      await _settle(tester);
      expect(_newestReads(s.server), before + 1);
      expect(s.link.attempts, hasLength(attempts));
      expect(s.sync.current.online, isTrue);
      await _end(tester, s);
    });

    testWidgets('with the socket up, leaves a healthy list '
        'alone', (tester) async {
      final transports = _Transports(wifi);
      final s = await _connectedSession(tester, transports);
      await _holdOpen(tester, s, recentlyAddedShelfProvider);
      await _settle(tester);
      transports.change(none);
      await _settle(tester);
      final before = _newestReads(s.server);
      transports.change(wifi);
      await _settle(tester);
      expect(_newestReads(s.server), before);
      await _end(tester, s);
    });

    testWidgets('with the socket up, reads a user list in error again, '
        'once', (tester) async {
      final transports = _Transports(wifi);
      final s = await _connectedSession(tester, transports);
      transports.change(none);
      await _failWhileAway(tester, s, playlistsProvider);
      final before = s.server.playlistReads;
      transports.change(wifi);
      await _settle(tester);
      expect(s.server.playlistReads, before + 1);
      await _end(tester, s);
    });

    testWidgets('with the socket up, refreshes a user listing whose refresh '
        'failed and gave up', (tester) async {
      final transports = _Transports(wifi);
      final s = await _connectedSession(tester, transports);
      await _holdOpen(tester, s, reviewQueueProvider);
      expect(s.server.reviewReads, 1);
      transports.change(none);
      s.server.reviewError = _Server._refused;
      s.container.invalidate(reviewQueueProvider);
      // The refresh and every attempt after it fail, and it stops asking.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(seconds: 10));
      }
      expect(s.container.read(reviewQueueProvider).hasError, isFalse);
      expect(s.server.reviewReads, 1, reason: 'each attempt refused');
      s.server.reviewError = null;
      transports.change(wifi);
      await _settle(tester);
      expect(s.server.reviewReads, 2);
      await _end(tester, s);
    });

    testWidgets('with the socket up, leaves a healthy user list '
        'alone', (tester) async {
      final transports = _Transports(wifi);
      final s = await _connectedSession(tester, transports);
      await _holdOpen(tester, s, playlistsProvider);
      await _settle(tester);
      transports.change(none);
      await _settle(tester);
      final before = s.server.playlistReads;
      expect(before, greaterThan(0));
      transports.change(wifi);
      await _settle(tester);
      expect(s.server.playlistReads, before);
      await _end(tester, s);
    });

    testWidgets('makes a socket waiting out its backoff try at once', (
      tester,
    ) async {
      final transports = _Transports(wifi);
      final s = await _portSession(transports);
      transports.change(none);
      // The waits between attempts grow to their longest.
      await tester.pump(const Duration(seconds: 70));
      final attempts = s.link.attempts.length;
      s.link.reachable = true;
      transports.change(wifi);
      await tester.pump(const Duration(milliseconds: 100));
      expect(s.link.attempts, hasLength(attempts + 1));
      await _settle(tester);
      expect(s.sync.current.online, isTrue);
      await _end(tester, s);
    });

    testWidgets('with the socket down, leaves what failed to the reconnect '
        'it hurries: each read once', (tester) async {
      final transports = _Transports(wifi);
      final s = await _portSession(transports);
      transports.change(none);
      await _failWhileAway(tester, s, recentlyAddedShelfProvider);
      await _failWhileAway(tester, s, playlistsProvider);
      final (newest, playlists, attempts) = (
        _newestReads(s.server),
        s.server.playlistReads,
        s.link.attempts.length,
      );
      final connecting = s.link.gate = Completer<void>();
      s.link
        ..catalogAnswer = const {'unchanged': true}
        ..reachable = true;
      transports.change(wifi);
      await tester.pump(const Duration(milliseconds: 100));
      expect(s.link.attempts, hasLength(attempts + 1), reason: 'at once');
      await tester.pump(const Duration(seconds: 6));
      expect(
        (_newestReads(s.server), s.server.playlistReads),
        (newest, playlists),
        reason: 'nothing is read before the socket is up',
      );
      s.link.gate = null;
      connecting.complete();
      await _settle(tester);
      expect(s.sync.current.online, isTrue);
      expect(_newestReads(s.server), newest + 1);
      expect(s.server.playlistReads, playlists + 1);
      await _end(tester, s);
    });

    testWidgets('reads nothing again when wifi gives way to cellular', (
      tester,
    ) async {
      final transports = _Transports(wifi);
      final s = await _connectedSession(tester, transports);
      await _failWhileAway(tester, s, recentlyAddedShelfProvider);
      final before = _newestReads(s.server);
      transports.change(const [ConnectivityResult.mobile]);
      await _settle(tester);
      expect(_newestReads(s.server), before);
      await _end(tester, s);
    });
  });

  testWidgets('a user list that failed during the outage is read again, '
      'once, at a reconnect whose user pull finds nothing', (tester) async {
    final s = await _offlineSession();
    await _failWhileAway(tester, s, playlistsProvider);
    final before = s.server.playlistReads;
    await _reconnect(tester, s, const {'unchanged': true});
    expect(s.server.playlistReads, before + 1);
    await _end(tester, s);
  });

  testWidgets('a healthy user list is not read again at a reconnect whose '
      'user pull finds nothing', (tester) async {
    final s = await _offlineSession();
    await _holdOpen(tester, s, playlistsProvider);
    final before = s.server.playlistReads;
    expect(before, 1);
    await _reconnect(tester, s, const {'unchanged': true});
    expect(s.server.playlistReads, before);
    await _end(tester, s);
  });

  testWidgets('a catalog frame after an answer that said nothing changed '
      'reads the lists again', (tester) async {
    final home = await _offlineHome(tester);
    home.link.catalogAnswer = {'unchanged': true};
    await _comeBack(tester, home);
    expect(_reads(home.server), _each(1));
    home.link.attempts.last.onFrame(
      jsonEncode({'type': 'invalidate', 'topic': 'catalog'}),
    );
    await _settle(tester);
    expect(_reads(home.server), _each(2));
  });
}
