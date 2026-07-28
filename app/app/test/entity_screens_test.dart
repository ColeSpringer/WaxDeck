import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/music/album_screen.dart';
import 'package:waxdeck/src/music/artist_screen.dart';
import 'package:waxdeck/src/music/entity_facts.dart';
import 'package:waxdeck/src/music/listing_screen.dart';
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

    test('a running time reads the way an album sleeve does', () {
      expect(formatRunningTime(const Duration(minutes: 41)), '41 min');
      expect(formatRunningTime(const Duration(hours: 1)), '1 hr');
      expect(
        formatRunningTime(const Duration(hours: 1, minutes: 12)),
        '1 hr 12 min',
      );
    });
  });
}
