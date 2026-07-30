import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/music/artist_screen.dart';
import 'package:waxdeck/src/music/index_screen.dart';
import 'package:waxdeck/src/music/listing_screen.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/music/music_hub_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
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

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget screen,
  FakeRepository repository, {
  Size size = const Size(900, 1200),
  bool engine = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repository),
      if (engine) audioEngineProvider.overrideWithValue(FakeEngine()),
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

    await tester.tap(find.text('Most items'));
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
    expect(find.byType(ArtistScreen), findsOneWidget);
    expect(repository.facetDrills.last, ('artist', '01JZXNightjar'));
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

    // The button is fire-and-forget, so a failure it swallowed would be
    // a control that does nothing at all.
    expect(find.text('the catalog is busy'), findsOneWidget);
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
}
