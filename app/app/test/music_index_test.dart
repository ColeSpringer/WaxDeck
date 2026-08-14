import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/home/home_shelves.dart';
import 'package:waxdeck/src/home/pinned_controller.dart';
import 'package:waxdeck/src/music/artist_screen.dart';
import 'package:waxdeck/src/music/index_screen.dart';
import 'package:waxdeck/src/music/listing_screen.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/music/music_hub_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/settings/prefs_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

FacetBucket _artist(String name, {int count = 3}) => FacetBucket(
  key: '01JZX$name',
  label: name,
  count: count,
  entityPid: 'ar-01JZX$name',
);

FacetBucket _album(String name, {int count = 9}) => FacetBucket(
  key: '01JZX$name',
  label: name,
  count: count,
  entityPid: 'al-01JZX$name',
);

ItemSummary _track(String title, {String artist = 'Nightjar'}) => ItemSummary(
  pid: 'tr-$title',
  mediaType: MediaType.music,
  title: title,
  artist: artist,
  durationMs: 245000,
);

/// Overridden rather than reached through the real controller, which
/// waits on a session a widget test's container has nobody signed in to.
class _StubPrefs extends PrefsController {
  _StubPrefs(this._prefs);

  final Prefs _prefs;

  @override
  Future<Prefs> build() async => _prefs;
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget screen,
  FakeRepository repository, {
  Size size = const Size(900, 1200),
  bool engine = false,
  Prefs? prefs,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repository),
      if (engine) audioEngineProvider.overrideWithValue(FakeEngine()),
      if (prefs != null)
        prefsControllerProvider.overrideWith(() => _StubPrefs(prefs)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: routedHost(screen)),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('the artists index asks for the A-to-Z order and rails it', (
    tester,
  ) async {
    final repository = FakeRepository()
      ..facets['artist'] = <FacetBucket>[
        _artist('Zebra', count: 9),
        _artist('abba', count: 2),
        _artist('Mogwai', count: 5),
      ];
    await _pump(
      tester,
      const MusicIndexScreen(dimension: MusicDimension.artists),
      repository,
    );

    // Artists lead with an alphabet: the rail is only honest over one, so
    // the order it is drawn beside has to be the one the server sorted.
    expect(repository.facetSorts, contains(FacetSort.label));
    expect(find.byType(FastScrollRail), findsOneWidget);

    // Case folded, which byte order gets wrong: "abba" leads, not "Mogwai".
    final rows = tester.widgetList<MediaListRow>(find.byType(MediaListRow));
    expect(rows.map((row) => row.data.title).toList(), <String>[
      'abba',
      'Mogwai',
      'Zebra',
    ]);
  });

  testWidgets('an artist row draws its monogram without asking, and an '
      'album row still asks', (tester) async {
    // Nothing automatic writes artist-level artwork - every art-bearing
    // enrichment provider targets the release group, and the one way an
    // artist gets a cover is an admin setting it by hand - so a
    // five-hundred-artist index would fire five hundred requests for an
    // answer that is statically known. Albums are the opposite case and
    // must keep their covers.
    final repository = FakeRepository()
      ..facets['artist'] = <FacetBucket>[_artist('Nightjar')]
      ..facets['album'] = <FacetBucket>[_album('Gullwing')];

    await _pump(
      tester,
      const MusicIndexScreen(dimension: MusicDimension.artists),
      repository,
    );
    expect(
      tester.widget<MediaListRow>(find.byType(MediaListRow)).data.artwork,
      isNull,
      reason: 'an artist bucket row asks for no artwork at all',
    );

    await _pump(
      tester,
      const MusicIndexScreen(dimension: MusicDimension.albums),
      repository,
    );
    expect(
      tester.widget<MediaListRow>(find.byType(MediaListRow)).data.artwork,
      isNotNull,
      reason: 'the album index keeps its covers',
    );
  });

  testWidgets('the sort toggle restarts the listing in the other order', (
    tester,
  ) async {
    final repository = FakeRepository()
      ..facets['artist'] = <FacetBucket>[
        _artist('Zebra', count: 9),
        _artist('abba', count: 2),
      ];
    await _pump(
      tester,
      const MusicIndexScreen(dimension: MusicDimension.artists),
      repository,
    );

    // The settings picker's own words for this FacetSort: one order, one
    // name, so a stored default and the chip that arrives selected agree.
    await tester.tap(find.text('Most first'));
    await tester.pumpAndSettle();

    // A separate listing with a cursor space of its own - the server
    // refuses a cursor carried across the two - so the request goes out
    // fresh rather than paging on what the alphabet had.
    expect(repository.facetSorts.last, FacetSort.count);
    // And the rail goes with it: in count order the letters are scattered
    // down the list, so a rail beside it would be lying.
    expect(find.byType(FastScrollRail), findsNothing);
  });

  testWidgets('a bucket opens its own location, entity pid and all', (
    tester,
  ) async {
    final repository = FakeRepository()
      ..facets['artist'] = <FacetBucket>[_artist('Nightjar')]
      ..facetItems['artist 01JZXNightjar'] = <ItemSummary>[_track('Gullwing')];
    await _pump(
      tester,
      const MusicIndexScreen(dimension: MusicDimension.artists),
      repository,
    );

    await tester.tap(find.text('Nightjar'));
    await tester.pumpAndSettle();

    // An artist bucket opens the artist, not a filtered list: same
    // location either way, because a bucket's key is its entity pid
    // without the type prefix, which is what lets one address name the
    // entity and still drill the listing behind it.
    //
    // `contains` rather than `.last`: the screen also drills
    // `credit-artist` for its "appears on" shelf, and which of the two
    // settles second is not what this is about.
    expect(find.byType(ArtistScreen), findsOneWidget);
    expect(repository.facetDrills, contains(('artist', '01JZXNightjar')));
  });

  testWidgets('shuffling a bucket draws a page rather than what scrolled by', (
    tester,
  ) async {
    // Sampling an accumulated list longer than the cap drops whatever it
    // did not sample: the queue cannot hold it and the cursor beside it
    // points past all of it. A page is one window's worth, and its
    // cursor is that window's frontier.
    final repository = FakeRepository()
      ..facetItems['genre ge-1'] = <ItemSummary>[
        for (var i = 0; i < 900; i++) _track('Track $i'),
      ];
    final container = await _pump(
      tester,
      const MusicListingScreen(
        dimension: MusicDimension.genres,
        segment: 'ge-1',
      ),
      repository,
      engine: true,
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.listingShuffle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final queue = container.read(queueControllerProvider);
    expect(queue.shuffled, isTrue);
    expect(queue.length, kQueueCap);
    // The cursor is the page's, so the refill continues where the
    // window ends rather than past everything the screen had loaded.
    expect(queue.source.rolling, isTrue);
    expect(queue.source.cursor, '$kQueueCap');
    container.read(queueControllerProvider.notifier).clear();
    await tester.pumpAndSettle();
  });

  testWidgets('shuffling a bucket seeds a permutation over the whole bucket', (
    tester,
  ) async {
    // Without a seed on the source the refill pages the bucket's own
    // listing and shuffles each arriving page among itself.
    final repository = FakeRepository()
      ..facetItems['genre ge-1'] = <ItemSummary>[
        for (var i = 0; i < 900; i++) _track('Track $i'),
      ];
    final container = await _pump(
      tester,
      const MusicListingScreen(
        dimension: MusicDimension.genres,
        segment: 'ge-1',
      ),
      repository,
      engine: true,
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.listingShuffle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repository.scopedBrowses.last.facet, 'genre');
    expect(repository.scopedBrowses.last.facetKey, 'ge-1');
    final source = container.read(queueControllerProvider).source;
    expect(
      source.seed,
      isNotNull,
      reason: 'without a seed the refill pages the listing, not the shuffle',
    );
    container.read(queueControllerProvider.notifier).clear();
    await tester.pumpAndSettle();
  });

  testWidgets('shuffling all music walks one seeded permutation', (
    tester,
  ) async {
    final repository = FakeRepository(
      items: <ItemSummary>[for (var i = 0; i < 900; i++) _track('Track $i')],
    );
    final container = await _pump(
      tester,
      const MusicListingScreen(),
      repository,
      engine: true,
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.listingShuffle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final source = container.read(queueControllerProvider).source;
    expect(source.kind, QueueSourceKind.library);
    // The seed the first page came back with, which is what keeps the
    // pages of a rolling shuffle from overlapping.
    expect(source.seed, repository.randomSeed);
    expect(source.rolling, isTrue);
    container.read(queueControllerProvider.notifier).clear();
    await tester.pumpAndSettle();
  });

  testWidgets('a shuffle the server refuses says so', (tester) async {
    final repository = FakeRepository()
      ..facetItems['genre ge-1'] = <ItemSummary>[_track('Track 0')];
    final container = await _pump(
      tester,
      const MusicListingScreen(
        dimension: MusicDimension.genres,
        segment: 'ge-1',
      ),
      repository,
    );
    // The listing loaded; it is the shuffle's own fetch that fails.
    repository.listError = const WaxDeckApiException(
      code: 'internal',
      message: 'the catalog is busy',
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.listingShuffle));
    await tester.pumpAndSettle();

    // The button is fire-and-forget, so a swallowed failure would be a
    // control that does nothing.
    expect(
      find.text('The server ran into a problem it could not handle.'),
      findsOneWidget,
    );
    expect(container.read(queueControllerProvider).isEmpty, isTrue);
  });

  testWidgets('the unknown bucket travels as a sentinel, not an empty path', (
    tester,
  ) async {
    final repository = FakeRepository()
      ..facets['genre'] = <FacetBucket>[
        const FacetBucket(
          key: '',
          label: '[No Genre]',
          count: 4,
          unknown: true,
        ),
      ]
      ..facetItems['genre '] = <ItemSummary>[_track('Gullwing')];
    await _pump(
      tester,
      const MusicIndexScreen(dimension: MusicDimension.genres),
      repository,
    );

    await tester.tap(find.text('[No Genre]'));
    await tester.pumpAndSettle();

    expect(find.byType(MusicListingScreen), findsOneWidget);
    // An empty key is a real bucket and an empty path segment is not a
    // location, so the sentinel carries it there and back.
    expect(repository.facetDrills.last, ('genre', ''));
  });

  testWidgets('the unknown bucket goes where the preference says', (
    tester,
  ) async {
    final repository = FakeRepository()
      ..facets['genre'] = <FacetBucket>[
        const FacetBucket(key: '01JZXA', label: 'Ambient', count: 6),
        const FacetBucket(
          key: '',
          label: '[No Genre]',
          count: 4,
          unknown: true,
        ),
      ];
    await _pump(
      tester,
      const MusicIndexScreen(dimension: MusicDimension.genres),
      repository,
      prefs: const Prefs(browseShowUnknown: false),
    );

    expect(find.text('Ambient'), findsOneWidget);
    expect(
      find.text('[No Genre]'),
      findsNothing,
      reason: 'hiding it is the index screen, not a server filter',
    );
  });

  testWidgets('an index opens in the order the account stored', (tester) async {
    // Artists lead A-to-Z by default; this account said otherwise.
    final repository = FakeRepository()
      ..facets['artist'] = <FacetBucket>[_artist('Zebra'), _artist('abba')];
    await _pump(
      tester,
      const MusicIndexScreen(dimension: MusicDimension.artists),
      repository,
      prefs: const Prefs(browseSorts: <String, String>{'artist': 'count'}),
    );

    expect(repository.facetSorts.last, FacetSort.count);
    expect(
      find.byType(FastScrollRail),
      findsNothing,
      reason: 'a rail over a biggest-first list would be lying about it',
    );
  });

  testWidgets('setting the default outranks an earlier toolbar tap', (
    tester,
  ) async {
    // The provider outlives its screen, so a session-local choice would
    // otherwise make the setting look dead for the rest of the session.
    final repository = FakeRepository()
      ..facets['artist'] = <FacetBucket>[_artist('Zebra'), _artist('abba')];
    final container = await _pump(
      tester,
      const MusicIndexScreen(dimension: MusicDimension.artists),
      repository,
      prefs: const Prefs(),
    );
    final sort = container.read(
      musicIndexSortProvider(MusicDimension.artists).notifier,
    );
    sort.select(FacetSort.count);
    await tester.pumpAndSettle();
    expect(
      container.read(musicIndexSortProvider(MusicDimension.artists)),
      FacetSort.count,
    );

    container.read(prefsControllerProvider.notifier).state = const AsyncData(
      Prefs(browseSorts: <String, String>{'artist': 'label'}),
    );
    await tester.pumpAndSettle();
    expect(
      container.read(musicIndexSortProvider(MusicDimension.artists)),
      FacetSort.label,
      reason: 'a stored default set later wins over an earlier tap',
    );
  });

  testWidgets('a listing opened cold names itself from what it loads', (
    tester,
  ) async {
    // No `extra`: a reload and a shared link both drop it, so the screen
    // has to be able to title itself from the URL and the answer alone.
    final repository = FakeRepository()
      ..facetItems['artist 01JZXNightjar'] = <ItemSummary>[
        _track('Gullwing', artist: 'Nightjar'),
      ];
    await _pump(
      tester,
      const MusicListingScreen(
        dimension: MusicDimension.artists,
        segment: 'ar-01JZXNightjar',
      ),
      repository,
    );

    expect(find.text('Nightjar'), findsWidgets);
    expect(find.text('Gullwing'), findsOneWidget);
  });

  testWidgets('the tracks index plays one row, not the whole library', (
    tester,
  ) async {
    final repository = FakeRepository()
      ..libraryItems.addAll(<ItemSummary>[
        _track('Alpha'),
        _track('Bravo'),
        _track('Charlie'),
      ]);
    await _pump(tester, const MusicListingScreen(), repository);

    expect(find.text('Alpha'), findsOneWidget);
    // Every row is present but none of them is a queue: the index is the
    // whole library in title order, and tapping one is not a request to
    // queue forty thousand tracks.
    expect(find.byType(MediaListRow), findsNWidgets(3));
  });

  testWidgets('a mixed bucket queues what plays in sequence', (tester) async {
    // A bucket counts whatever carries its artist, books included, and
    // the drill honours that so the count and the list agree. The queue
    // is a different question: a twelve-hour book dropped between two
    // tracks, captioned with the artist's name, is not what the tap
    // asked for.
    final container = await _pump(
      tester,
      const MusicListingScreen(
        dimension: MusicDimension.artists,
        segment: 'ar-01JZXAda',
      ),
      FakeRepository()
        ..facetItems['artist 01JZXAda'] = <ItemSummary>[
          const ItemSummary(
            pid: 'bk-1',
            mediaType: MediaType.audiobook,
            title: 'The Chaptered Fixture',
            artist: 'Ada Author',
            durationMs: 43200000,
          ),
          _track('Alpha', artist: 'Ada Author'),
          _track('Bravo', artist: 'Ada Author'),
        ],
      // Playing pushes the player, which needs an engine and then never
      // settles: the VU needle repeats for as long as something plays.
      engine: true,
    );

    await tester.tap(find.text('Bravo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final queue = container.read(queueControllerProvider);
    expect(queue.entries.map((e) => e.pid).toList(), <String>[
      'tr-Alpha',
      'tr-Bravo',
    ]);
    // And the row that was tapped is the one that plays, which the index
    // shift would otherwise get wrong.
    expect(queue.currentPid, 'tr-Bravo');

    // Stop the session before the tree comes down: a playing engine keeps
    // its position ticker, and a pending timer fails the test at
    // teardown rather than where it was started.
    container.read(queueControllerProvider.notifier).clear();
    await tester.pumpAndSettle();
  });

  testWidgets('the hub tiles fit their labels at twice the text size', (
    tester,
  ) async {
    // A fixed cell extent stopped fitting at about 1.25x: the glyph does
    // not grow and the two text lines do, and a grid cell too small for
    // its child overflows rather than reflowing.
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(FakeRepository())],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: routedHost(const MusicHubScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('a rail tap to a loaded letter costs no request', (tester) async {
    // Everything is loaded, so the tap is a scroll.
    final repository = FakeRepository()
      ..facets['artist'] = <FacetBucket>[
        _artist('Abba'),
        _artist('Mogwai'),
        _artist('Zebra'),
      ];
    await _pump(
      tester,
      const MusicIndexScreen(dimension: MusicDimension.artists),
      repository,
    );
    final before = repository.facetStartsAt.length;

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.indexRailLetter('M')),
    );
    await tester.pumpAndSettle();

    expect(repository.facetStartsAt, hasLength(before));
  });

  testWidgets('a rail tap to an unloaded letter re-anchors on the server', (
    tester,
  ) async {
    // Larger than one page, so Z is genuinely not loaded - the whole
    // condition this branch turns on.
    final repository = FakeRepository()
      ..facets['artist'] = <FacetBucket>[
        for (var i = 0; i <= MusicIndexController.pageSize; i++)
          _artist('Abba $i'),
        _artist('Zebra'),
      ];
    await _pump(
      tester,
      const MusicIndexScreen(dimension: MusicDimension.artists),
      repository,
    );
    expect(find.text('Zebra'), findsNothing);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.indexRailLetter('Z')),
    );
    await tester.pumpAndSettle();

    expect(repository.facetStartsAt.last, 'Z');
    expect(find.text('Zebra'), findsOneWidget);
  });

  testWidgets('an anchored window offers the way back to the start', (
    tester,
  ) async {
    final repository = FakeRepository()
      ..facets['artist'] = <FacetBucket>[_artist('Abba'), _artist('Zebra')];
    final container = await _pump(
      tester,
      const MusicIndexScreen(dimension: MusicDimension.artists),
      repository,
    );
    const key = (dimension: MusicDimension.artists, sort: FacetSort.label);

    // Directly: a rail tap only re-anchors an unloaded letter.
    await container.read(musicIndexProvider(key).notifier).anchorAt('z');
    await tester.pumpAndSettle();

    expect(repository.facetStartsAt.last, 'z');
    expect(find.text('Abba'), findsNothing);
    // The floor is not a dead end.
    final start = find.bySemanticsIdentifier(SemanticsIds.indexRailStart);
    expect(start, findsOneWidget);

    await tester.tap(start);
    await tester.pumpAndSettle();

    expect(find.text('Abba'), findsOneWidget);
    expect(start, findsNothing);
  });

  testWidgets('a rail tap below the floor re-anchors backwards', (
    tester,
  ) async {
    // at-or-after means every loaded bucket matches a letter sorting
    // before the window, so a floored window would answer index 0 and
    // never ask for the A's.
    final repository = FakeRepository()
      ..facets['artist'] = <FacetBucket>[_artist('Abba'), _artist('Zebra')];
    final container = await _pump(
      tester,
      const MusicIndexScreen(dimension: MusicDimension.artists),
      repository,
    );
    const key = (dimension: MusicDimension.artists, sort: FacetSort.label);
    await container.read(musicIndexProvider(key).notifier).anchorAt('z');
    await tester.pumpAndSettle();
    expect(find.text('Abba'), findsNothing);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.indexRailLetter('A')),
    );
    await tester.pumpAndSettle();

    expect(repository.facetStartsAt.last, 'A');
    expect(find.text('Abba'), findsOneWidget);
  });

  testWidgets('a seek past the last bucket keeps the listing', (tester) async {
    // The server answers an empty page, correctly. Committing it would
    // trade the whole index - and the rail, which needs a bucket to
    // draw - for nothing.
    final repository = FakeRepository()
      ..facets['artist'] = <FacetBucket>[_artist('Abba'), _artist('Mogwai')];
    final container = await _pump(
      tester,
      const MusicIndexScreen(dimension: MusicDimension.artists),
      repository,
    );
    const key = (dimension: MusicDimension.artists, sort: FacetSort.label);

    final moved = await container
        .read(musicIndexProvider(key).notifier)
        .anchorAt('z');
    await tester.pumpAndSettle();

    expect(moved, isFalse);
    expect(find.text('Abba'), findsOneWidget);
    expect(find.byType(FastScrollRail), findsOneWidget);
  });

  testWidgets('a failed re-anchor leaves paging usable', (tester) async {
    // The generation bump abandons an in-flight loadMore without
    // clearing its guard, so a snapshot restored with it still set would
    // wedge every later page for the provider's life.
    final repository = FakeRepository()
      ..facets['artist'] = <FacetBucket>[
        for (var i = 0; i <= MusicIndexController.pageSize; i++)
          _artist('Abba $i'),
      ];
    final container = await _pump(
      tester,
      const MusicIndexScreen(dimension: MusicDimension.artists),
      repository,
    );
    const key = (dimension: MusicDimension.artists, sort: FacetSort.label);
    final notifier = container.read(musicIndexProvider(key).notifier);

    // A page genuinely in flight, so the snapshot the failed anchor
    // restores is the one carrying loadingMore.
    final gate = Completer<void>();
    repository.facetGate = gate;
    final paging = notifier.loadMore();
    await tester.pump();

    repository.listError = const WaxDeckApiException(
      code: 'internal',
      message: 'the catalog is busy',
    );
    final anchored = notifier.anchorAt('m');
    gate.complete();
    repository.facetGate = null;
    expect(await paging, isFalse);
    expect(await anchored, isFalse);
    repository.listError = null;
    await tester.pumpAndSettle();

    expect(await notifier.loadMore(), isTrue);
  });

  testWidgets('an append keeps the floor', (tester) async {
    final repository = FakeRepository()
      ..facets['artist'] = <FacetBucket>[
        for (var i = 0; i <= MusicIndexController.pageSize; i++)
          _artist('Mogwai $i'),
      ];
    final container = await _pump(
      tester,
      const MusicIndexScreen(dimension: MusicDimension.artists),
      repository,
    );
    const key = (dimension: MusicDimension.artists, sort: FacetSort.label);
    final notifier = container.read(musicIndexProvider(key).notifier);

    await notifier.anchorAt('m');
    await tester.pumpAndSettle();
    expect(container.read(musicIndexProvider(key)).value!.hasFloor, isTrue);

    await notifier.loadMore();
    await tester.pumpAndSettle();

    expect(container.read(musicIndexProvider(key)).value!.hasFloor, isTrue);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.indexRailStart),
      findsOneWidget,
    );
  });

  testWidgets('the # row starts at the head rather than seeking', (
    tester,
  ) async {
    // `#` members sort both before A and after Z, so no prefix names
    // them and it never becomes a startsAt.
    final repository = FakeRepository()
      ..facets['artist'] = <FacetBucket>[_artist('Abba'), _artist('Zebra')];
    final container = await _pump(
      tester,
      const MusicIndexScreen(dimension: MusicDimension.artists),
      repository,
    );
    const key = (dimension: MusicDimension.artists, sort: FacetSort.label);
    await container.read(musicIndexProvider(key).notifier).anchorAt('z');
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.indexRailLetter('#')),
    );
    await tester.pumpAndSettle();

    expect(repository.facetStartsAt.last, isNull);
    expect(find.text('Abba'), findsOneWidget);
  });

  testWidgets('dragging the sort chips does not fetch a page', (tester) async {
    // The paging listener wraps the whole screen and the chips are a
    // horizontal scroller inside it, sitting at pixel zero of a very
    // short extent - which reads as "near the end" to anything that only
    // looks at the numbers.
    final repository = FakeRepository()
      ..facets['artist'] = <FacetBucket>[
        for (var i = 0; i < 3; i++) _artist('Artist $i'),
      ];
    await _pump(
      tester,
      const MusicIndexScreen(dimension: MusicDimension.artists),
      repository,
      size: const Size(400, 800),
    );
    final before = repository.facetSorts.length;

    await tester.drag(find.byType(FilterChipRow), const Offset(-120, 0));
    await tester.pumpAndSettle();

    expect(repository.facetSorts, hasLength(before));
  });

  test('a bucket listing pages at the queue cap, not under it', () {
    // Playing a row plays the bucket from there, and the screen can only
    // hand over what it has loaded. A page under the cap would queue a
    // prefix of an artist and label it the artist; at the cap, every
    // bucket the queue could hold whole is loaded whole before the first
    // row can be tapped.
    expect(MusicItemsController.pageSize, kQueueCap);
  });

  testWidgets('the hub offers a way into each index', (tester) async {
    final repository = FakeRepository()
      ..facets['artist'] = <FacetBucket>[_artist('Nightjar')];
    await _pump(tester, const MusicHubScreen(), repository);

    for (final name in <String>[
      'artists',
      'albums',
      'tracks',
      'genres',
      'years',
      'playlists',
    ]) {
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.identifier == SemanticsIds.musicTile(name),
        ),
        findsWidgets,
        reason: '$name has no tile',
      );
    }
  });

  testWidgets('compact browses through tiles; wide gets the chip row', (
    tester,
  ) async {
    final repository = FakeRepository();
    await _pump(
      tester,
      const MusicHubScreen(),
      repository,
      size: const Size(500, 900),
    );
    expect(find.byType(SliverGrid), findsOneWidget);
  });

  testWidgets('the wide hub leads with content, not a wall of tiles', (
    tester,
  ) async {
    final repository = FakeRepository();
    await _pump(tester, const MusicHubScreen(), repository);
    // The index entries are a slim chip row, not the tile grid.
    expect(find.byType(SliverGrid), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.identifier == SemanticsIds.musicTile('artists'),
      ),
      findsWidgets,
    );
  });

  testWidgets('a loading shelf ghosts instead of vanishing', (tester) async {
    final repository = FakeRepository(items: [_track('Coastal')])
      ..browseGate = Completer<void>();
    await _pump(tester, const MusicHubScreen(), repository);

    // Before the delay: nothing, exactly like a warm cache would show.
    expect(find.text('Recently added'), findsNothing);

    // Past the delay the shelf's name and its ghost cards hold the
    // room, instead of the hub degrading to bare navigation.
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Recently added'), findsOneWidget);
    expect(find.byType(SkeletonShapes), findsWidgets);

    repository.browseGate!.complete();
    repository.browseGate = null;
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonShapes), findsNothing);
    expect(find.text('Coastal'), findsWidgets);
  });

  testWidgets('a failed shelf keeps its name and offers a retry', (
    tester,
  ) async {
    final repository = FakeRepository(items: [_track('Coastal')])
      ..listError = const WaxDeckApiException(
        code: 'internal',
        message: 'the server did not answer',
      );
    await _pump(tester, const MusicHubScreen(), repository);

    expect(find.text('Recently added'), findsOneWidget);
    expect(find.text('Try again'), findsNWidgets(3));

    repository.listError = null;
    await tester.tap(find.text('Try again').first);
    await tester.pumpAndSettle();
    expect(find.text('Coastal'), findsWidgets);
  });

  testWidgets('a hub with nothing gets an invitation, not bare tiles', (
    tester,
  ) async {
    final repository = FakeRepository();
    final container = await _pump(tester, const MusicHubScreen(), repository);
    expect(find.text('No music yet'), findsOneWidget);

    // A sync fan-out refetch is loading WITH the old value; the
    // invitation must not blink out for the round trip and reappear.
    container.invalidate(mixCardsProvider);
    await tester.pump();
    expect(
      find.text('No music yet'),
      findsOneWidget,
      reason: 'a refresh is not an unanswered read',
    );
    await tester.pumpAndSettle();
    expect(find.text('No music yet'), findsOneWidget);
  });

  test('a bucket handle survives the round trip through a location', () {
    // The two halves of the same contract: what a location carries, and
    // what the listing behind it filters on.
    const bucket = FacetBucket(
      key: '01JZXABC',
      label: 'Nightjar',
      count: 3,
      entityPid: 'ar-01JZXABC',
    );
    final segment = musicBucketSegment(MusicDimension.artists, bucket);
    expect(segment, 'ar-01JZXABC');
    expect(musicFacetKey(MusicDimension.artists, segment), '01JZXABC');

    // A year is its own handle, and the unknown bucket is a sentinel that
    // drills back to the empty key it stands for.
    const year = FacetBucket(key: '1997', label: '1997', count: 8);
    expect(musicBucketSegment(MusicDimension.years, year), '1997');
    expect(musicFacetKey(MusicDimension.years, '1997'), '1997');
    const unknown = FacetBucket(
      key: '',
      label: '[Unknown Year]',
      count: 2,
      unknown: true,
    );
    expect(
      musicBucketSegment(MusicDimension.years, unknown),
      musicUnknownSegment,
    );
    expect(musicFacetKey(MusicDimension.years, musicUnknownSegment), isEmpty);

    // And the route builder puts it where the table expects it.
    expect(
      WaxRoute.musicBucket(MusicDimension.artists, segment),
      '/music/artists/ar-01JZXABC',
    );
  });

  testWidgets('an entity bucket pins from its overflow without opening', (
    tester,
  ) async {
    final repository = FakeRepository()
      ..facets['album'] = <FacetBucket>[_album('Gullwing')];
    final container = await _pump(
      tester,
      const MusicIndexScreen(dimension: MusicDimension.albums),
      repository,
      prefs: const Prefs(),
    );

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.indexBucketMore(0)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pin album to Home'), findsOneWidget);

    await tester.tap(
      find.bySemanticsIdentifier(
        SemanticsIds.pinSheetTarget('al-01JZXGullwing'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(pinnedEntitiesProvider),
      contains('al-01JZXGullwing'),
    );
    expect(repository.prefs.pinned, contains('al-01JZXGullwing'));
  });

  testWidgets('a genre bucket offers no overflow', (tester) async {
    // A genre is a filter, not a thing: there is no entity behind the
    // row, so there is nothing a pin could hold.
    final repository = FakeRepository()
      ..facets['genre'] = <FacetBucket>[
        const FacetBucket(key: 'rock', label: 'Rock', count: 4),
      ];
    await _pump(
      tester,
      const MusicIndexScreen(dimension: MusicDimension.genres),
      repository,
    );

    expect(
      find.bySemanticsIdentifier(SemanticsIds.indexBucketMore(0)),
      findsNothing,
    );
  });

  testWidgets('a listing row pins the album or artist it belongs to', (
    tester,
  ) async {
    // The track itself cannot be pinned - a kept set of tracks is a
    // playlist - so the overflow offers the row's handles instead.
    final repository = FakeRepository()
      ..facetItems['genre ge-1'] = <ItemSummary>[
        ItemSummary(
          pid: 'tr-1',
          mediaType: MediaType.music,
          title: 'Wide Angle',
          artist: 'Field Notes',
          album: 'Long Exposure',
          albumPid: 'al-01JZXLONG',
          artistPid: 'ar-01JZXFIELD',
          durationMs: 245000,
        ),
        ItemSummary(
          pid: 'tr-2',
          mediaType: MediaType.music,
          title: 'Orphan Line',
          durationMs: 200000,
        ),
      ];
    final container = await _pump(
      tester,
      const MusicListingScreen(
        dimension: MusicDimension.genres,
        segment: 'ge-1',
      ),
      repository,
      prefs: const Prefs(),
    );

    // A row that carries no handles offers nothing.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.listingRowMore('tr-2')),
      findsNothing,
    );

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.listingRowMore('tr-1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pin album to Home'), findsOneWidget);
    expect(find.text('Pin artist to Home'), findsOneWidget);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.pinSheetTarget('ar-01JZXFIELD')),
    );
    await tester.pumpAndSettle();

    expect(container.read(pinnedEntitiesProvider), contains('ar-01JZXFIELD'));
    expect(
      container.read(pinnedEntitiesProvider),
      isNot(contains('al-01JZXLONG')),
    );
  });
}
