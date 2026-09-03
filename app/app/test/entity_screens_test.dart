import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/music/album_screen.dart';
import 'package:waxdeck/src/music/artist_screen.dart';
import 'package:waxdeck/src/music/entity_facts.dart';
import 'package:waxdeck/src/music/listing_screen.dart';
import 'package:waxdeck/src/metadata/metadata_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

ItemSummary _track(
  String title, {
  String artist = 'Nightjar',
  String album = 'Gullwing',
  String albumPid = 'al-1',
  int? track,
  int? disc,
  int durationMs = 240000,
}) => ItemSummary(
  pid: 'tr-$title',
  mediaType: MediaType.music,
  title: title,
  artist: artist,
  album: album,
  artistPid: 'ar-1',
  albumPid: albumPid,
  trackNumber: track,
  discNumber: disc,
  durationMs: durationMs,
);

Finder _byId(String id) => find.bySemanticsIdentifier(id);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget screen,
  FakeRepository repository, {
  Size size = const Size(900, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repository),
      audioEngineProvider.overrideWithValue(FakeEngine()),
      // The preference document a pin lives in is only fetched for an
      // authenticated session, and the session needs somewhere to keep a
      // credential.
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: routedHost(screen)),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Stops what a test started. A playing engine keeps a position ticker
/// running, and a pending timer fails at teardown rather than where it
/// was started.
Future<void> _stop(WidgetTester tester, ProviderContainer container) async {
  container.read(queueControllerProvider.notifier).clear();
  await tester.pumpAndSettle();
}

List<String> _rowTitles(WidgetTester tester) => tester
    .widgetList<MediaListRow>(find.byType(MediaListRow))
    .map((row) => row.data.title)
    .toList();

void main() {
  group('the album screen', () {
    testWidgets('lists a release in the order it was pressed', (tester) async {
      // The listing arrives in the catalog's own stable order, which is
      // not track order. A release that came back alphabetically and was
      // rendered that way would be wrong on every album with more than
      // one track.
      final repository = FakeRepository()
        ..facetItems['album 1'] = <ItemSummary>[
          _track('Anthem', track: 3),
          _track('Bellwether', track: 1),
          _track('Cinder', track: 2),
        ];

      await _pump(tester, const AlbumScreen(pid: 'al-1'), repository);

      expect(_rowTitles(tester), ['Bellwether', 'Cinder', 'Anthem']);
    });

    testWidgets('a multi-disc release separates its discs', (tester) async {
      final repository = FakeRepository()
        ..facetItems['album 1'] = <ItemSummary>[
          _track('Second side', track: 1, disc: 2),
          _track('First side', track: 1, disc: 1),
        ];

      await _pump(tester, const AlbumScreen(pid: 'al-1'), repository);

      expect(_rowTitles(tester), ['First side', 'Second side']);
      expect(find.text('DISC 2'), findsOneWidget);
    });

    testWidgets('the header names the release from its own tracks', (
      tester,
    ) async {
      final repository = FakeRepository()
        ..facetItems['album 1'] = <ItemSummary>[
          _track('One', track: 1, durationMs: 120000),
          _track('Two', track: 2, durationMs: 180000),
        ];

      await _pump(tester, const AlbumScreen(pid: 'al-1'), repository);

      expect(find.text('Gullwing'), findsWidgets);
      expect(find.text('Nightjar'), findsOneWidget);
      expect(find.text('2 tracks · 5 min'), findsOneWidget);
    });

    testWidgets('a compilation says so rather than naming one artist', (
      tester,
    ) async {
      final repository = FakeRepository()
        ..facetItems['album 1'] = <ItemSummary>[
          _track('One', artist: 'Nightjar', track: 1),
          _track('Two', artist: 'Mogwai', track: 2),
        ];

      await _pump(tester, const AlbumScreen(pid: 'al-1'), repository);

      expect(find.text('Various artists'), findsOneWidget);
    });

    testWidgets('playing a row queues the album from there', (tester) async {
      final repository = FakeRepository()
        ..facetItems['album 1'] = <ItemSummary>[
          _track('One', track: 1),
          _track('Two', track: 2),
          _track('Three', track: 3),
        ];
      final container = await _pump(
        tester,
        const AlbumScreen(pid: 'al-1'),
        repository,
      );

      await tester.tap(find.text('Two'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final queue = container.read(queueControllerProvider);
      expect(queue.pids, ['tr-One', 'tr-Two', 'tr-Three']);
      expect(queue.currentPid, 'tr-Two');
      expect(queue.source.kind, QueueSourceKind.album);
      expect(queue.source.pid, 'al-1');
      await _stop(tester, container);
    });

    testWidgets('shuffle plays the album in an order it did not arrive in', (
      tester,
    ) async {
      final repository = FakeRepository()
        ..facetItems['album 1'] = <ItemSummary>[
          for (var i = 0; i < 12; i++) _track('Track $i', track: i + 1),
        ];
      final container = await _pump(
        tester,
        const AlbumScreen(pid: 'al-1'),
        repository,
      );

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.entityShuffle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final queue = container.read(queueControllerProvider);
      expect(queue.shuffled, isTrue);
      expect(queue.length, 12);
      expect(queue.pids, isNot([for (var i = 0; i < 12; i++) 'tr-Track $i']));
      await _stop(tester, container);
    });

    testWidgets('an album with nothing in it says so', (tester) async {
      await _pump(tester, const AlbumScreen(pid: 'al-1'), FakeRepository());

      expect(find.text('Nothing in this album'), findsOneWidget);
    });

    testWidgets('the release identity is drawn where the entity has one', (
      tester,
    ) async {
      // The five columns a track row cannot carry. Not behind the
      // technical-details switch: that line is file versus release, and a
      // catalog number is printed on the sleeve.
      final repository = FakeRepository()
        ..facetItems['album 1'] = <ItemSummary>[_track('One', track: 1)];
      repository.albums['al-1'] = const AlbumDetail(
        pid: 'al-1',
        title: 'Gullwing',
        barcode: '036000291452',
        media: '2xVinyl',
      );

      await _pump(tester, const AlbumScreen(pid: 'al-1'), repository);

      expect(_byId(SemanticsIds.albumIdentity), findsOneWidget);
      expect(find.text('036000291452'), findsOneWidget);
      expect(find.text('2xVinyl'), findsOneWidget);
      // Absent fields draw nothing rather than a blank row.
      expect(find.text('Catalog number'), findsNothing);
    });

    testWidgets('an album carrying no identity draws no block at all', (
      tester,
    ) async {
      final repository = FakeRepository()
        ..facetItems['album 1'] = <ItemSummary>[_track('One', track: 1)];
      repository.albums['al-1'] = const AlbumDetail(
        pid: 'al-1',
        title: 'Gullwing',
      );

      await _pump(tester, const AlbumScreen(pid: 'al-1'), repository);

      expect(_byId(SemanticsIds.albumIdentity), findsNothing);
    });

    testWidgets('the overflow pins the release and opens its editor', (
      tester,
    ) async {
      final repository = FakeRepository(
        sessionState: const SessionState(
          authenticated: true,
          user: WaxDeckUser(
            id: 'us-1',
            username: 'admin',
            roles: <String>['admin'],
          ),
        ),
      )..facetItems['album 1'] = <ItemSummary>[_track('One', track: 1)];

      await _pump(tester, const AlbumScreen(pid: 'al-1'), repository);

      await tester.tap(_byId(SemanticsIds.entityOverflow));
      await tester.pumpAndSettle();
      expect(find.text('Pin to Home'), findsOneWidget);
      // The editor door is beside it for an administrator; the entity
      // edit endpoint answers 403 to anyone else.
      expect(find.text('Edit album details'), findsOneWidget);
      await tester.tap(_byId(SemanticsIds.entityPin));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();

      expect(repository.putPrefsCalls.single.pinned, <String>['al-1']);

      // And the label flips, because the same row is what unpins it.
      await tester.tap(_byId(SemanticsIds.entityOverflow));
      await tester.pumpAndSettle();
      expect(find.text('Unpin from Home'), findsOneWidget);
    });

    testWidgets('the overflow offers the release mix and share', (
      tester,
    ) async {
      final repository = FakeRepository()
        ..facetItems['album 1'] = <ItemSummary>[_track('One', track: 1)];

      await _pump(tester, const AlbumScreen(pid: 'al-1'), repository);

      await tester.tap(_byId(SemanticsIds.entityOverflow));
      await tester.pumpAndSettle();
      expect(_byId(SemanticsIds.entityInstantMix), findsOneWidget);
      expect(_byId(SemanticsIds.entityShare), findsOneWidget);

      await tester.tap(_byId(SemanticsIds.entityShare));
      await tester.pumpAndSettle();
      // The share dialog minted for the album's own pid.
      expect(find.text('Share link'), findsOneWidget);
    });

    testWidgets('a track row menu edits and navigates, but never points '
        'at the screen it is on', (tester) async {
      final repository = FakeRepository(
        sessionState: const SessionState(
          authenticated: true,
          user: WaxDeckUser(
            id: 'us-1',
            username: 'admin',
            roles: <String>['admin'],
          ),
        ),
      )..facetItems['album 1'] = <ItemSummary>[_track('One', track: 1)];

      // The editor screen the menu opens at the end lays out cleanly at
      // the size its own suite uses.
      await _pump(
        tester,
        const AlbumScreen(pid: 'al-1'),
        repository,
        size: const Size(800, 3000),
      );

      await tester.tap(_byId(SemanticsIds.albumTrackMore(0)));
      await tester.pumpAndSettle();
      // Everything the row's pids support, except the album the screen
      // already is.
      expect(find.text('Go to album'), findsNothing);
      expect(find.text('Go to artist'), findsOneWidget);
      expect(_byId(SemanticsIds.itemMenuMix), findsOneWidget);
      expect(_byId(SemanticsIds.itemMenuShare), findsOneWidget);

      await tester.tap(_byId(SemanticsIds.editMetadata('tr-One')));
      await tester.pumpAndSettle();
      expect(find.byType(MetadataScreen), findsOneWidget);
    });

    testWidgets('a track row detaches from the release it sits on', (
      tester,
    ) async {
      final repository = FakeRepository(
        sessionState: const SessionState(
          authenticated: true,
          user: WaxDeckUser(
            id: 'us-1',
            username: 'admin',
            roles: <String>['admin'],
          ),
        ),
      )..facetItems['album 1'] = <ItemSummary>[_track('One', track: 1)];
      // The row is offered only where there is an mbid-pinned release to
      // leave; the server refuses a chain that carries none.
      repository.albums['al-1'] = const AlbumDetail(
        pid: 'al-1',
        title: 'Long Exposure',
        mbid: '33333333-3333-3333-3333-333333333333',
      );

      await _pump(tester, const AlbumScreen(pid: 'al-1'), repository);

      await tester.tap(_byId(SemanticsIds.albumTrackMore(0)));
      await tester.pumpAndSettle();
      await tester.tap(_byId(SemanticsIds.itemMenuDetach));
      await tester.pumpAndSettle();
      // Nothing is written until the confirmation is answered: the
      // track's file loses its release tags.
      expect(repository.detachCalls, isEmpty);
      await tester.tap(_byId(SemanticsIds.itemMenuDetachConfirm));
      await tester.pumpAndSettle();

      expect(repository.detachCalls.single.pid, 'tr-One');
      expect(repository.detachCalls.single.writeBack, isTrue);
    });

    testWidgets('a member is offered the pin and not the editor', (
      tester,
    ) async {
      final repository = FakeRepository(
        sessionState: const SessionState(
          authenticated: true,
          user: WaxDeckUser(
            id: 'us-2',
            username: 'listener',
            roles: <String>['member'],
          ),
        ),
      )..facetItems['album 1'] = <ItemSummary>[_track('One', track: 1)];
      // An mbid-pinned release, so the detach row's other precondition
      // is satisfied and the permission gate is the only thing left
      // that can hide it.
      repository.albums['al-1'] = const AlbumDetail(
        pid: 'al-1',
        title: 'Long Exposure',
        mbid: '33333333-3333-3333-3333-333333333333',
      );

      await _pump(tester, const AlbumScreen(pid: 'al-1'), repository);

      await tester.tap(_byId(SemanticsIds.entityOverflow));
      await tester.pumpAndSettle();
      expect(find.text('Pin to Home'), findsOneWidget);
      expect(find.text('Edit album details'), findsNothing);

      // The entity sheet is dismissed first. Left open, its modal
      // barrier swallows the next tap, the row menu never opens, and
      // every findsNothing below passes for the wrong reason.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(_byId(SemanticsIds.itemMenuSheet('tr-One')), findsNothing);

      // The detach is a catalog write, so it sits behind the same door
      // the editor does.
      await tester.tap(_byId(SemanticsIds.albumTrackMore(0)));
      await tester.pumpAndSettle();
      expect(
        _byId(SemanticsIds.itemMenuSheet('tr-One')),
        findsOneWidget,
        reason:
            'the row menu must actually open for the assertion below to mean anything',
      );
      expect(_byId(SemanticsIds.itemMenuDetach), findsNothing);
    });
  });

  group('the artist screen', () {
    testWidgets('a release opens over the artist, and back returns to it', (
      tester,
    ) async {
      // An album is declared under the albums index, which is not where
      // this is: going to it would rebuild that ancestry and throw the
      // artist away, so back from a release would land on the index
      // rather than on the artist whose release it is.
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[_track('One', track: 1)]
        ..facetItems['album 1'] = <ItemSummary>[_track('One', track: 1)];
      await _pump(tester, const ArtistScreen(pid: 'ar-1'), repository);

      await tester.tap(find.byType(MediaCard));
      await tester.pumpAndSettle();
      expect(find.byType(AlbumScreen), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(ArtistScreen), findsOneWidget);
    });

    testWidgets('groups the tracks into releases by entity, not by title', (
      tester,
    ) async {
      // Two different albums that happen to share a title stay two
      // releases; grouping by the display text would merge them.
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[
          _track('One', album: 'Live', albumPid: 'al-1'),
          _track('Two', album: 'Live', albumPid: 'al-2'),
        ];

      await _pump(tester, const ArtistScreen(pid: 'ar-1'), repository);

      expect(find.byType(MediaCard), findsNWidgets(2));
    });

    testWidgets('two releases that share a title open their own pids', (
      tester,
    ) async {
      // Grouping keeps them apart by entity; a tap handler that matched
      // on the display text would open the first of them from both
      // tiles, which is the ambiguity albumPid exists to remove.
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[
          _track('One', album: 'Live', albumPid: 'al-1'),
          _track('Two', album: 'Live', albumPid: 'al-2'),
        ]
        ..facetItems['album 2'] = <ItemSummary>[
          _track('Two', album: 'Live', albumPid: 'al-2'),
        ];
      await _pump(tester, const ArtistScreen(pid: 'ar-1'), repository);

      await tester.tap(find.byType(MediaCard).last);
      await tester.pumpAndSettle();

      expect(tester.widget<AlbumScreen>(find.byType(AlbumScreen)).pid, 'al-2');
    });

    testWidgets('Appears on asks for album buckets, scoped to the artist', (
      tester,
    ) async {
      // One read, and it answers albums. This used to page the items
      // endpoint and collapse track rows client-side, bounded at four
      // pages because the dimension buckets the artist's own tracks too.
      final repository = FakeRepository()
        // One loaded track, so the Releases shelf above draws a single
        // album. The artist's second release is deliberately outside that
        // window: the exclusion must not depend on what the listing
        // happened to page in.
        ..facetItems['artist 1'] = <ItemSummary>[
          _track('Own', album: 'Their Record', albumPid: 'al-own'),
        ]
        ..facets['album|credit-artist|1'] = const <FacetBucket>[
          FacetBucket(
            key: 'own',
            label: 'Their Record',
            count: 1,
            entityPid: 'al-own',
          ),
          FacetBucket(
            key: 'unloaded',
            label: 'Past The Window',
            count: 3,
            entityPid: 'al-unloaded',
          ),
          FacetBucket(
            key: 'guest',
            label: 'Big Compilation',
            count: 4,
            entityPid: 'al-guest',
          ),
          FacetBucket(key: '', label: '[Non-Album]', count: 2, unknown: true),
        ]
        ..facets['album|artist|1'] = const <FacetBucket>[
          FacetBucket(
            key: 'own',
            label: 'Their Record',
            count: 1,
            entityPid: 'al-own',
          ),
          FacetBucket(
            key: 'unloaded',
            label: 'Past The Window',
            count: 3,
            entityPid: 'al-unloaded',
          ),
        ];

      await _pump(tester, const ArtistScreen(pid: 'ar-1'), repository);

      // Two scoped reads, and both are bucket reads: the credited albums,
      // and the ones this artist heads. The second is what the exclusion
      // is taken from, so it holds however little of the listing loaded.
      expect(repository.facetScopes, <(String, String, String)>[
        ('album', 'credit-artist', '1'),
        ('album', 'artist', '1'),
      ]);
      expect(find.text('Appears on'), findsOneWidget);
      // A release the artist heads is drawn above under Releases, and
      // [Non-Album] has no entity to open, so neither is a card here -
      // and neither is the own release whose tracks never loaded.
      expect(find.text('Big Compilation'), findsOneWidget);
      expect(find.text('4 tracks'), findsOneWidget);
      expect(_byId(SemanticsIds.entityAlbum('al-guest')), findsOneWidget);
      expect(_byId(SemanticsIds.entityAlbum('al-own')), findsOneWidget);
      expect(
        find.text('Past The Window'),
        findsNothing,
        reason: 'an own release outside the loaded window is still own',
      );
      expect(find.text('[Non-Album]'), findsNothing);
    });

    testWidgets('a top track queues the same window the header does', (
      tester,
    ) async {
      // Three entry points on one screen queue the same scope; a row
      // that built a source without the window would queue the loaded
      // prefix and stop, which is what the refill exists to prevent.
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[
          for (var i = 0; i < kQueueCap + 20; i++) _track('Track $i'),
        ];
      final container = await _pump(
        tester,
        const ArtistScreen(pid: 'ar-1'),
        repository,
      );

      await tester.tap(find.text('Track 2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final source = container.read(queueControllerProvider).source;
      expect(source.rolling, isTrue);
      expect(source.pid, 'ar-1');
      await _stop(tester, container);
    });

    testWidgets('the top tracks stop and hand the rest to the full list', (
      tester,
    ) async {
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[
          for (var i = 0; i < 9; i++) _track('Track $i'),
        ];

      await _pump(tester, const ArtistScreen(pid: 'ar-1'), repository);

      expect(_rowTitles(tester), hasLength(5));
      expect(find.text('Show all'), findsOneWidget);

      await tester.tap(find.text('Show all'));
      await tester.pumpAndSettle();

      expect(find.byType(MusicListingScreen), findsOneWidget);
    });

    testWidgets('an artist whose whole catalogue fits offers no Show all', (
      tester,
    ) async {
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[_track('One'), _track('Two')];

      await _pump(tester, const ArtistScreen(pid: 'ar-1'), repository);

      expect(find.text('Show all'), findsNothing);
    });

    testWidgets('the audiobooks in an artist bucket stay out of the queue', (
      tester,
    ) async {
      // A bucket counts whatever carried the artist, and a book carries
      // one. The list shows all of it, so the count and the list agree;
      // the queue is the different question, because a twelve-hour file
      // dropped between two tracks is not what Play was asked for.
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[
          _track('One'),
          ItemSummary(
            pid: 'bk-1',
            mediaType: MediaType.audiobook,
            title: 'A long book',
            artist: 'Nightjar',
            durationMs: 43200000,
          ),
        ];
      final container = await _pump(
        tester,
        const ArtistScreen(pid: 'ar-1'),
        repository,
      );

      expect(_rowTitles(tester), ['One', 'A long book']);
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.entityPlay));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(container.read(queueControllerProvider).pids, ['tr-One']);
      await _stop(tester, container);
    });

    testWidgets('an artist bigger than a page hands the queue its cursor', (
      tester,
    ) async {
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[
          for (var i = 0; i < kQueueCap + 20; i++) _track('Track $i'),
        ];
      final container = await _pump(
        tester,
        const ArtistScreen(pid: 'ar-1'),
        repository,
      );

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.entityPlay));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final source = container.read(queueControllerProvider).source;
      expect(source.rolling, isTrue, reason: 'the queue is a window over it');
      expect(source.pid, 'ar-1');
      await _stop(tester, container);
    });
  });

  group('album facts', () {
    test('tracks with no numbers keep the order they arrived in', () {
      final ordered = albumOrder(<ItemSummary>[
        _track('Later'),
        _track('Earlier'),
      ]);

      expect([for (final t in ordered) t.title], ['Later', 'Earlier']);
    });

    test('numbered tracks lead the ones with no number at all', () {
      final ordered = albumOrder(<ItemSummary>[
        _track('Untagged'),
        _track('Second', track: 2),
        _track('First', track: 1),
      ]);

      expect(
        [for (final t in ordered) t.title],
        ['First', 'Second', 'Untagged'],
      );
    });

    test('a codec chip says whatever half of it is known', () {
      ItemDetail detail({String? codec, int? rate}) => ItemDetail(
        pid: 'tr-1',
        mediaType: MediaType.music,
        title: 'One',
        durationMs: 1000,
        codec: codec,
        sampleRate: rate,
      );

      expect(
        codecChipLabel(detail(codec: 'flac', rate: 44100)),
        'FLAC 44.1 kHz',
      );
      expect(codecChipLabel(detail(codec: 'flac', rate: 48000)), 'FLAC 48 kHz');
      expect(codecChipLabel(detail(codec: 'flac')), 'FLAC');
      // A rate with no codec is still worth saying, and saying it must
      // not leave the space the codec would have filled.
      expect(codecChipLabel(detail(rate: 44100)), '44.1 kHz');
      expect(codecChipLabel(detail(codec: '', rate: 44100)), '44.1 kHz');
      expect(codecChipLabel(detail()), isEmpty);
    });

    test('a running time reads the way an album sleeve does', () async {
      final wax = await WaxLocalizations.delegate.load(const Locale('en'));
      expect(formatRunningTime(wax, const Duration(minutes: 41)), '41 min');
      expect(formatRunningTime(wax, const Duration(hours: 1)), '1 hr');
      expect(
        formatRunningTime(wax, const Duration(hours: 1, minutes: 12)),
        '1 hr 12 min',
      );
      // The design system's own words, elided the sleeve's way: the
      // control's span would say "1 min" here and collapse past ten.
      expect(formatRunningTime(wax, Duration.zero), '0 min');
      expect(formatRunningTime(wax, const Duration(hours: 12)), '12 hr');
    });
  });
}
