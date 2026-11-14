import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/books/book_bucket_screen.dart';
import 'package:waxdeck/src/books/book_dimension.dart';
import 'package:waxdeck/src/books/book_screen.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/library/item_kind.dart';
import 'package:waxdeck/src/music/album_screen.dart';
import 'package:waxdeck/src/music/artist_screen.dart';
import 'package:waxdeck/src/music/entity_facts.dart';
import 'package:waxdeck/src/music/listing_screen.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/player/play_progress.dart';
import 'package:waxdeck/src/metadata/metadata_screen.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/shell/async_sliver_face.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'entity_header_bar.dart';
import 'fakes.dart';
import 'secondary_click.dart';
import 'wax_finders.dart';

const _adminSession = SessionState(
  authenticated: true,
  user: WaxDeckUser(id: 'us-1', username: 'admin', roles: <String>['admin']),
);

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
  // The preference document a pin lives in is only fetched for an
  // authenticated session.
  return pumpApp(tester, screen, container: appContainer(repo: repository));
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

/// Asserts the rows' play counts in order, by title: the number, its words
/// on the count's own node at the row's position, and at zero no words and
/// no node. All of them from one read.
void _expectPlayCounts(
  WidgetTester tester,
  FakeRepository repository,
  Map<String, int> byTitle,
) {
  final words = AppLocalizationsEn();
  final rows = tester.widgetList<MediaListRow>(find.byType(MediaListRow));
  for (final (index, MapEntry(key: title, value: count))
      in byTitle.entries.indexed) {
    final row = rows.singleWhere((row) => row.data.title == title);
    final node = _byId(SemanticsIds.trackPlays(index));
    expect(row.data.playCount, count, reason: title);
    if (count == 0) {
      expect(row.data.playCountLabel, isNull, reason: title);
      expect(node, findsNothing, reason: title);
    } else {
      expect(row.data.playCountLabel, words.musicTrackPlaysSpoken(count));
      expect(tester.getSemantics(node).label, row.data.playCountLabel);
    }
  }
  expect(repository.playStateBatches, hasLength(1), reason: 'one read');
}

/// The windows of [kPlayProgressWindow] rows that a list's built rows sit
/// in, the cache extent's included, for rows titled `T` and their index.
Set<int> _builtWindows(WidgetTester tester) => <int>{
  for (final row in tester.widgetList<MediaListRow>(
    find.byType(MediaListRow, skipOffstage: false),
  ))
    int.parse(row.data.title.substring(1)) ~/ kPlayProgressWindow,
};

/// The windows a key was made for in the windows value a list's built rows
/// were given.
Set<int> _windowsAsked(WidgetTester tester) => <int>{
  for (final row in tester.widgetList<PlayCountBuilder>(
    find.byType(PlayCountBuilder, skipOffstage: false),
  ))
    ...row.windows.windowsAsked,
};

/// The windows [repository]'s play-state reads covered, from batch [from] on,
/// for rows titled `T` and their index.
Set<int> _windowsRead(FakeRepository repository, {int from = 0}) => <int>{
  for (final batch in repository.playStateBatches.skip(from))
    int.parse(batch.first.substring(4)) ~/ kPlayProgressWindow,
};

/// Hands [state] to every live progress window, as the user stream's echo
/// of a play report does.
void _echo(ProviderContainer container, PlayState state) {
  for (final window in container.read(liveProgressWindowsProvider).toList()) {
    window.apply(state);
  }
}

/// A report for a track finished [count] times, at [positionMs], stamped
/// [second] seconds into a fixed minute so each one is newer.
PlayState _report(
  String pid, {
  required int count,
  required int positionMs,
  required int second,
}) => PlayState(
  pid: pid,
  positionMs: positionMs,
  played: true,
  finished: true,
  playCount: count,
  starred: false,
  updatedAt: DateTime.utc(2026, 11, 1, 12, 0, second),
);

/// Records every element rebuilt from here on, until the test ends.
List<Element> _recordRebuilds() {
  final rebuilt = <Element>[];
  debugOnRebuildDirtyWidget = (element, _) => rebuilt.add(element);
  addTearDown(() => debugOnRebuildDirtyWidget = null);
  return rebuilt;
}

/// The titles of the rows among [rebuilt].
List<String> _rowsIn(List<Element> rebuilt) => <String>[
  for (final element in rebuilt)
    if (element.widget case MediaListRow(:final data)) data.title,
];

/// Holds a reload in flight and asserts the screen keeps drawing the
/// rows it already has, through the shared face rather than a switch on
/// the state's runtime type.
///
/// Both halves matter. The face is what fixes the order - value, then
/// error, then skeleton - so a state that carries a value while loading
/// or failing cannot fall through to a skeleton arm and blank a screen
/// the reader was reading; asserting the screen uses it is what keeps a
/// hand-rolled switch from coming back.
Future<void> _expectRefreshKeepsRows(
  WidgetTester tester,
  ProviderContainer container,
  FakeRepository repository,
  MusicListing listing,
) async {
  expect(
    find.byType(AsyncSliverFace<MusicItemsState>),
    findsOneWidget,
    reason: 'the screen decides its face from the value, not the type',
  );
  final before = _rowTitles(tester);
  expect(before, isNotEmpty, reason: 'nothing to keep');
  final gate = Completer<void>();
  repository.listItemsGate = gate;
  container.invalidate(musicItemsProvider(listing));
  // Twice: Riverpod schedules the rebuild against the frame, so the
  // first pump is the one that runs it and the second draws what it
  // produced.
  await tester.pump();
  await tester.pump();

  expect(_rowTitles(tester), before);
  expect(
    find.byType(SkeletonShapes),
    findsNothing,
    reason: 'a reload must not blank rows the screen already holds',
  );
  gate.complete();
  repository.listItemsGate = null;
  await tester.pumpAndSettle();
}

void main() {
  group('the album screen', () {
    testWidgets('a refresh redraws the tracks it already has', (tester) async {
      final repository = FakeRepository()
        ..facetItems['album 1'] = <ItemSummary>[
          _track('Bellwether', track: 1),
          _track('Cinder', track: 2),
        ];
      final container = await _pump(
        tester,
        const AlbumScreen(pid: 'al-1'),
        repository,
      );

      await _expectRefreshKeepsRows(tester, container, repository, (
        dimension: MusicDimension.albums,
        segment: 'al-1',
        domain: BrowseDomain.wholeLibrary,
      ));
    });

    testWidgets('the header row is one action bar with the menu', (
      tester,
    ) async {
      final repository = FakeRepository()
        ..facetItems['album 1'] = <ItemSummary>[_track('Bellwether', track: 1)];
      await _pump(tester, const AlbumScreen(pid: 'al-1'), repository);

      expectHeaderOnActionBar();
      for (final id in <String>[
        SemanticsIds.entityPlay,
        SemanticsIds.entityShuffle,
        SemanticsIds.entityOverflow,
      ]) {
        expect(inActionBar(id), findsOneWidget, reason: id);
      }
    });

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
      // The whole library: an album reached from search may hold a book.
      expect(
        repository.listItemsCalls.map((call) => call.mediaType),
        everyElement(isNull),
      );
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
      // The album is there; the caller can see none of its tracks.
      final repository = FakeRepository()
        ..albums['al-1'] = const AlbumDetail(pid: 'al-1', title: 'Gullwing');
      await _pump(tester, const AlbumScreen(pid: 'al-1'), repository);

      expect(find.text('Nothing in this album'), findsOneWidget);
    });

    testWidgets('an album that does not exist is not drawn as an empty album', (
      tester,
    ) async {
      // Its track listing answers an empty page for any key, so a page
      // built from the listing alone is a fake one.
      await _pump(tester, const AlbumScreen(pid: 'al-gone'), FakeRepository());

      expect(find.text('Nothing in this album'), findsNothing);
      expect(find.text('Could not load this album'), findsOneWidget);
      expect(find.text('That is not here any more.'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(_byId(SemanticsIds.entityPlay), findsNothing);
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
      // The heading names the block; no kicker repeats it.
      expect(find.text('Release'), findsOneWidget);
      expect(find.text('THIS EDITION'), findsNothing);
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

    testWidgets('a row wears its play count beside its running time', (
      tester,
    ) async {
      // The count is the caller's own, read in one batch for the whole
      // release; a track nobody has finished shows nothing rather than
      // a zero, which would put a column of noughts down a fresh
      // library.
      final repository = FakeRepository()
        ..facetItems['album 1'] = <ItemSummary>[
          _track('One', track: 1),
          _track('Two', track: 2),
        ]
        ..finishedPids.add('tr-One');

      await _pump(tester, const AlbumScreen(pid: 'al-1'), repository);

      _expectPlayCounts(tester, repository, <String, int>{'One': 1, 'Two': 0});
    });

    testWidgets('a count from a thousand is drawn compact and spoken whole', (
      tester,
    ) async {
      final repository = FakeRepository()
        ..facetItems['album 1'] = <ItemSummary>[_track('One', track: 1)]
        ..playCounts['tr-One'] = 1234;

      await _pump(tester, const AlbumScreen(pid: 'al-1'), repository);

      expect(find.text('1.2K'), findsOneWidget);
      expect(
        tester.getSemantics(_byId(SemanticsIds.trackPlays(0))).label,
        'played 1,234 times',
      );
    });

    testWidgets('a long release reads only the windows its drawn rows sit '
        'in', (tester) async {
      final tracks = <ItemSummary>[
        for (var i = 0; i < 120; i++)
          _track('T${i.toString().padLeft(3, '0')}', track: i + 1),
      ];
      final repository = FakeRepository()
        ..facetItems['album 1'] = tracks
        ..finishedPids.add('tr-T002');

      await _pump(
        tester,
        const AlbumScreen(pid: 'al-1'),
        repository,
        size: const Size(800, 600),
      );

      expect(_builtWindows(tester), <int>{0});
      expect(repository.playStateBatches, <List<String>>[
        <String>[for (final track in tracks.take(50)) track.pid],
      ]);
      expect(
        tester
            .widgetList<MediaListRow>(find.byType(MediaListRow))
            .singleWhere((row) => row.data.title == 'T002')
            .data
            .playCount,
        1,
      );
    });

    testWidgets('a track row menu opens the facts sheet', (tester) async {
      // Also in the library list, which is where the fake's item detail
      // reads from: the sheet's rows are that read, not the listing's.
      final repository = FakeRepository(items: [_track('One', track: 1)])
        ..facetItems['album 1'] = <ItemSummary>[_track('One', track: 1)]
        ..itemDetailBpm['tr-One'] = 128;

      await _pump(tester, const AlbumScreen(pid: 'al-1'), repository);

      await tester.tap(_byId(SemanticsIds.albumTrackMore(0)));
      await tester.pumpAndSettle();
      await tester.tap(_byId(SemanticsIds.itemMenuDetails));
      await tester.pumpAndSettle();

      expect(_byId(SemanticsIds.itemFactsSheet('tr-One')), findsOneWidget);
      expect(_byId(SemanticsIds.itemFactsRow('bpm')), findsOneWidget);
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
      expect(
        infoTipContaining('next scan'),
        findsOneWidget,
        reason: 'the write-back switch explains itself in a tip',
      );
      expect(find.textContaining('next scan'), findsNothing);
      // Nothing is written until the confirmation is answered: the
      // track's file loses its release tags.
      expect(repository.detachCalls, isEmpty);
      await tester.tap(_byId(SemanticsIds.itemMenuDetachConfirm));
      await tester.pumpAndSettle();

      expect(repository.detachCalls.single.pid, 'tr-One');
      expect(repository.detachCalls.single.writeBack, isTrue);
    });

    testWidgets(
      'an uploader is offered the change only on what they may edit',
      (tester) async {
        final repository =
            FakeRepository(
                sessionState: const SessionState(
                  authenticated: true,
                  user: WaxDeckUser(
                    id: 'us-2',
                    username: 'sam',
                    roles: <String>['user'],
                    uploadEnabled: true,
                  ),
                ),
              )
              ..mayCurateItems = false
              ..facetItems['album 1'] = <ItemSummary>[_track('One', track: 1)];
        await _pump(tester, const AlbumScreen(pid: 'al-1'), repository);

        await tester.tap(_byId(SemanticsIds.albumTrackMore(0)));
        await tester.pumpAndSettle();
        expect(_byId(SemanticsIds.itemMenuSheet('tr-One')), findsOneWidget);
        expect(_byId(SemanticsIds.itemMenuKindBook), findsNothing);
      },
    );

    testWidgets('a track row becomes an audiobook, and the book opens', (
      tester,
    ) async {
      final repository = FakeRepository(sessionState: _adminSession)
        ..facetItems['album 1'] = <ItemSummary>[_track('One', track: 1)];
      await _pump(tester, const AlbumScreen(pid: 'al-1'), repository);

      await tester.tap(_byId(SemanticsIds.albumTrackMore(0)));
      await tester.pumpAndSettle();
      await tester.tap(_byId(SemanticsIds.itemMenuKindBook));
      await tester.pumpAndSettle();
      expect(find.text('Make this an audiobook?'), findsOneWidget);
      expect(repository.setKindCalls, isEmpty);

      await tester.tap(_byId(SemanticsIds.kindConfirm));
      await tester.pump();
      await tester.pump(kindChangePoll);
      await tester.pumpAndSettle();
      expect(repository.setKindCalls.single.pids, ['tr-One']);
      expect(repository.setKindCalls.single.mediaType, 'audiobook');
      expect(repository.setKindCalls.single.writeBack, isFalse);
      expect(
        find.byWidgetPredicate((w) => w is BookScreen && w.pid == 'bk-One'),
        findsOneWidget,
      );
    });

    testWidgets('an album becomes one audiobook from its overflow', (
      tester,
    ) async {
      final repository = FakeRepository(sessionState: _adminSession)
        ..facetItems['album 1'] = <ItemSummary>[
          _track('One', track: 1),
          _track('Two', track: 2),
        ];
      await _pump(tester, const AlbumScreen(pid: 'al-1'), repository);

      await tester.tap(_byId(SemanticsIds.entityOverflow));
      await tester.pumpAndSettle();
      await tester.tap(_byId(SemanticsIds.itemMenuKindAlbum));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('2 tracks become one audiobook'),
        findsOneWidget,
      );
      await tester.tap(_byId(SemanticsIds.kindWriteBack));
      await tester.pump();
      await tester.tap(_byId(SemanticsIds.kindConfirm));
      await tester.pump();
      await tester.pump(kindChangePoll);
      await tester.pumpAndSettle();
      expect(repository.setKindCalls.single.pids, ['tr-One', 'tr-Two']);
      expect(repository.setKindCalls.single.writeBack, isTrue);
      expect(
        find.byWidgetPredicate((w) => w is BookScreen && w.pid == 'bk-One'),
        findsOneWidget,
      );
    });

    testWidgets('an album past what one change takes says so and sends '
        'nothing', (tester) async {
      // A long book ripped as one album: more tracks than a page, and
      // more than one change may name.
      final repository = FakeRepository(sessionState: _adminSession)
        ..facetItems['album 1'] = <ItemSummary>[
          for (var i = 1; i <= 650; i++) _track('T$i', track: i),
        ];
      await _pump(tester, const AlbumScreen(pid: 'al-1'), repository);
      final drills = repository.facetDrills.length;

      await tester.tap(_byId(SemanticsIds.entityOverflow));
      await tester.pumpAndSettle();
      await tester.tap(_byId(SemanticsIds.itemMenuKindAlbum));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'This album has more than 500 tracks, too many to change in one go.',
        ),
        findsOneWidget,
      );
      expect(_byId(SemanticsIds.kindConfirm), findsNothing);
      expect(repository.setKindCalls, isEmpty);
      // One page past the one on screen is what tells.
      expect(repository.facetDrills.length - drills, 1);
    });

    testWidgets('an album is deleted whole from its overflow', (tester) async {
      final repository = FakeRepository(sessionState: _adminSession)
        ..facetItems['album 1'] = <ItemSummary>[
          _track('One', track: 1),
          _track('Two', track: 2),
        ];
      await _pump(tester, const AlbumScreen(pid: 'al-1'), repository);

      await tester.tap(_byId(SemanticsIds.entityOverflow));
      await tester.pumpAndSettle();
      await tester.tap(_byId(SemanticsIds.itemMenuDelete));
      await tester.pumpAndSettle();
      // The plan first, of every track of the release.
      expect(repository.deleteItemsCalls.single.pids, ['tr-One', 'tr-Two']);
      expect(repository.deleteItemsCalls.single.dryRun, isTrue);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.itemDeleteConfirm),
      );
      await tester.pumpAndSettle();

      expect(repository.deleteItemsCalls.last.dryRun, isFalse);
      expect(repository.deleteItemsCalls.last.pids, ['tr-One', 'tr-Two']);
      expect(
        find.byType(AlbumScreen),
        findsNothing,
        reason: 'the release is gone; the screen leaves it',
      );
    });

    testWidgets('an album delete a file shares offers the file\'s other '
        'tracks with the album\'s', (tester) async {
      final repository = FakeRepository(sessionState: _adminSession)
        ..facetItems['album 1'] = <ItemSummary>[
          _track('One', track: 1),
          _track('Two', track: 2),
        ];
      // Two is cut from one file with Three, a track of another album.
      repository.deleteItemsRefusal = (pids, dryRun) =>
          pids.contains('tr-Three')
          ? null
          : const WaxDeckApiException(
              code: 'invalid-request',
              message: "a cue rip's tracks share one file",
              statusCode: 400,
              params: {'reason': 'cue-rip', 'tracks': 'tr-Two,tr-Three'},
            );
      await _pump(tester, const AlbumScreen(pid: 'al-1'), repository);

      await tester.tap(_byId(SemanticsIds.entityOverflow));
      await tester.pumpAndSettle();
      await tester.tap(_byId(SemanticsIds.itemMenuDelete));
      await tester.pumpAndSettle();
      // What was picked and what more goes with it, apart: the one more
      // is another album's.
      expect(
        find.text(
          '1 more track is cut from the same file as tracks you picked; '
          'they are deleted together or not at all.',
        ),
        findsOneWidget,
      );
      await tester.tap(_byId(SemanticsIds.itemDeleteRip));
      await tester.pumpAndSettle();
      expect(repository.deleteItemsCalls.last.pids, [
        'tr-One',
        'tr-Two',
        'tr-Three',
      ], reason: 'the album asked for, then the rest of the file');
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.itemDeleteConfirm),
      );
      await tester.pumpAndSettle();

      expect(repository.deleteItemsCalls.last.dryRun, isFalse);
      expect(
        find.byType(AlbumScreen),
        findsNothing,
        reason: 'every track of the release went; the screen leaves it',
      );
    });

    testWidgets('an album whose shared files would take the delete past '
        'what one names says so and offers nothing', (tester) async {
      final repository = FakeRepository(sessionState: _adminSession)
        ..facetItems['album 1'] = <ItemSummary>[
          for (var i = 1; i <= 499; i++) _track('T$i', track: i),
        ];
      // The last track shares its file with two of another album.
      repository.deleteItemsRefusal = (pids, dryRun) =>
          const WaxDeckApiException(
            code: 'invalid-request',
            message: "a cue rip's tracks share one file",
            statusCode: 400,
            params: {'reason': 'cue-rip', 'tracks': 'tr-T499,tr-X1,tr-X2'},
          );
      await _pump(tester, const AlbumScreen(pid: 'al-1'), repository);

      await tester.tap(_byId(SemanticsIds.entityOverflow));
      await tester.pumpAndSettle();
      await tester.tap(_byId(SemanticsIds.itemMenuDelete));
      await tester.pumpAndSettle();

      expect(_byId(SemanticsIds.itemDeleteRip), findsNothing);
      expect(
        shellMessageText(raisedMessage(tester)),
        'With the tracks that share their files, this is more than 500 '
        'tracks, too many to delete in one go.',
      );
      expect(repository.deleteItemsCalls, hasLength(1));
    });

    testWidgets('a partial album delete keeps the album screen', (
      tester,
    ) async {
      final repository = FakeRepository(sessionState: _adminSession)
        ..facetItems['album 1'] = <ItemSummary>[
          _track('One', track: 1),
          _track('Two', track: 2),
        ]
        ..deleteItemsFailed = 1;
      await _pump(tester, const AlbumScreen(pid: 'al-1'), repository);

      await tester.tap(_byId(SemanticsIds.entityOverflow));
      await tester.pumpAndSettle();
      await tester.tap(_byId(SemanticsIds.itemMenuDelete));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.itemDeleteConfirm),
      );
      await tester.pumpAndSettle();

      expect(repository.deleteItemsCalls.last.dryRun, isFalse);
      expect(
        find.byType(AlbumScreen),
        findsOneWidget,
        reason: 'a file stayed, so the release did',
      );
    });

    testWidgets('an album past what one delete names says so and sends '
        'nothing', (tester) async {
      final repository = FakeRepository(sessionState: _adminSession)
        ..facetItems['album 1'] = <ItemSummary>[
          for (var i = 1; i <= 650; i++) _track('T$i', track: i),
        ];
      await _pump(tester, const AlbumScreen(pid: 'al-1'), repository);

      await tester.tap(_byId(SemanticsIds.entityOverflow));
      await tester.pumpAndSettle();
      await tester.tap(_byId(SemanticsIds.itemMenuDelete));
      await tester.pumpAndSettle();

      expect(
        shellMessageText(raisedMessage(tester)),
        'This album has more than 500 tracks, too many to delete in one go.',
      );
      expect(repository.deleteItemsCalls, isEmpty);
    });

    testWidgets('a track row deletes its track', (tester) async {
      final repository = FakeRepository(sessionState: _adminSession)
        ..facetItems['album 1'] = <ItemSummary>[_track('One', track: 1)];
      await _pump(tester, const AlbumScreen(pid: 'al-1'), repository);

      await tester.tap(_byId(SemanticsIds.albumTrackMore(0)));
      await tester.pumpAndSettle();
      await tester.tap(_byId(SemanticsIds.itemMenuDelete));
      await tester.pumpAndSettle();
      expect(repository.deleteItemsCalls.single.pids, ['tr-One']);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.itemDeleteConfirm),
      );
      await tester.pumpAndSettle();

      expect(repository.deleteItemsCalls.last.dryRun, isFalse);
    });

    testWidgets('a member without the delete right is offered no delete', (
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
      await _pump(tester, const AlbumScreen(pid: 'al-1'), repository);

      await tester.tap(_byId(SemanticsIds.entityOverflow));
      await tester.pumpAndSettle();
      expect(find.text('Pin to Home'), findsOneWidget);
      expect(_byId(SemanticsIds.itemMenuDelete), findsNothing);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      await tester.tap(_byId(SemanticsIds.albumTrackMore(0)));
      await tester.pumpAndSettle();
      expect(_byId(SemanticsIds.itemMenuSheet('tr-One')), findsOneWidget);
      expect(_byId(SemanticsIds.itemMenuDelete), findsNothing);
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
      expect(_byId(SemanticsIds.itemMenuKindBook), findsNothing);
    });
  });

  group('the music listing', () {
    testWidgets('a refresh redraws the tracks it already has', (tester) async {
      final repository = FakeRepository()
        ..facetItems['genre ge-1'] = <ItemSummary>[
          _track('One'),
          _track('Two'),
        ];
      final container = await _pump(
        tester,
        const MusicListingScreen(
          dimension: MusicDimension.genres,
          segment: 'ge-1',
        ),
        repository,
      );

      await _expectRefreshKeepsRows(tester, container, repository, (
        dimension: MusicDimension.genres,
        segment: 'ge-1',
        domain: BrowseDomain.music,
      ));
    });

    testWidgets('counts are read for the windows of fifty rows the listing '
        'draws, never for every window it holds', (tester) async {
      // A page of the listing is five hundred rows, ten windows of them,
      // and a screen draws a dozen.
      const listing = (
        dimension: MusicDimension.genres,
        segment: 'ge-1',
        domain: BrowseDomain.music,
      );
      final tracks = <ItemSummary>[
        for (var i = 0; i < MusicItemsController.pageSize + 20; i++)
          _track('T${i.toString().padLeft(3, '0')}'),
      ];
      List<String> window(int n) => <String>[
        for (final track in tracks.skip(n * 50).take(50)) track.pid,
      ];
      final repository = FakeRepository()
        ..facetItems['genre ge-1'] = tracks
        ..finishedPids.addAll(<String>['tr-T001', 'tr-T070']);
      final container = await _pump(
        tester,
        const MusicListingScreen(
          dimension: MusicDimension.genres,
          segment: 'ge-1',
        ),
        repository,
        size: const Size(800, 600),
      );
      MediaTileData row(String title) => tester
          .widgetList<MediaListRow>(find.byType(MediaListRow))
          .singleWhere((r) => r.data.title == title)
          .data;
      final scroll = tester.state<ScrollableState>(
        find
            .ancestor(
              of: find.byType(MediaListRow).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final pitch = tester.getSize(find.byType(MediaListRow).first).height;

      expect(_builtWindows(tester), <int>{
        0,
      }, reason: 'the top of the page is all window 0');
      expect(repository.playStateBatches, <List<String>>[window(0)]);
      expect(row('T001').playCount, 1);
      expect(row('T000').playCount, 0);

      // A page arriving out of sight is not drawn, so it reads nothing.
      await container.read(musicItemsProvider(listing).notifier).loadMore();
      await tester.pumpAndSettle();
      expect(repository.playStateBatches, hasLength(1));

      // Past row fifty: the rows built there read their window, once.
      scroll.position.jumpTo(70 * pitch);
      await tester.pumpAndSettle();
      expect(_builtWindows(tester), <int>{1});
      expect(repository.playStateBatches.skip(1), <List<String>>[window(1)]);
      expect(row('T070').playCount, 1);

      // A play-state change reads again only what is drawn.
      container.invalidate(playProgressProvider);
      await tester.pumpAndSettle();
      expect(repository.playStateBatches.skip(2), <List<String>>[window(1)]);

      // Back at the top. A window is held only while a row of it is
      // built, so the first one is read again, and only it.
      scroll.position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(_builtWindows(tester), <int>{0});
      expect(repository.playStateBatches.skip(3), <List<String>>[window(0)]);
      expect(row('T001').playCount, 1);
    });

    testWidgets('a listing of two thousand rows makes keys only for the '
        'windows it builds', (tester) async {
      const listing = (
        dimension: MusicDimension.genres,
        segment: 'ge-1',
        domain: BrowseDomain.music,
      );
      final repository = FakeRepository()
        ..facetItems['genre ge-1'] = <ItemSummary>[
          for (var i = 0; i < 4 * MusicItemsController.pageSize; i++)
            _track('T${i.toString().padLeft(4, '0')}'),
        ];
      final container = await _pump(
        tester,
        const MusicListingScreen(
          dimension: MusicDimension.genres,
          segment: 'ge-1',
        ),
        repository,
        size: const Size(800, 600),
      );
      final notifier = container.read(musicItemsProvider(listing).notifier);
      for (var page = 1; page < 4; page++) {
        await notifier.loadMore();
        await tester.pumpAndSettle();
      }
      expect(
        container.read(musicItemsProvider(listing)).value!.items,
        hasLength(2000),
      );

      expect(_builtWindows(tester), <int>{0});
      expect(_windowsAsked(tester), <int>{
        0,
      }, reason: 'the other thirty-nine are idle');

      final scroll = tester.state<ScrollableState>(
        find
            .ancestor(
              of: find.byType(MediaListRow).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(_windowsRead(repository), <int>{0});

      // A jump to the far end lays out every row on the way, and none of
      // them reads: only the rows that are still there afterwards do.
      final before = repository.playStateBatches.length;
      scroll.position.jumpTo(
        1900 * tester.getSize(find.byType(MediaListRow).first).height,
      );
      await tester.pumpAndSettle();
      expect(_builtWindows(tester), contains(38));
      expect(_windowsAsked(tester), <int>{0, ..._builtWindows(tester)});
      expect(
        _windowsRead(repository, from: before),
        _builtWindows(tester),
        reason: 'the windows on screen, and not the ones passed over',
      );
    });

    testWidgets('a listing flung fast reads nothing for the windows it passes '
        'and reads the one it settles in', (tester) async {
      final repository = FakeRepository()
        ..facetItems['genre ge-1'] = <ItemSummary>[
          for (var i = 0; i < MusicItemsController.pageSize; i++)
            _track('T${i.toString().padLeft(4, '0')}'),
        ];
      await _pump(
        tester,
        const MusicListingScreen(
          dimension: MusicDimension.genres,
          segment: 'ge-1',
        ),
        repository,
        size: const Size(800, 600),
      );
      expect(_windowsRead(repository), <int>{0});

      final before = repository.playStateBatches.length;
      // Faster than the screen is long a second: the framework's own
      // signal that nobody is reading what goes by.
      await tester.fling(
        find.byType(MediaListRow).first,
        const Offset(0, -300),
        8000,
      );
      await tester.pumpAndSettle();
      final settled = _builtWindows(tester);
      expect(
        settled.first,
        greaterThan(1),
        reason: 'the fling passed over at least one whole window',
      );
      expect(_windowsRead(repository, from: before), settled);
    });

    testWidgets('a report that moves only a position rebuilds no row, and a '
        'new count rebuilds only its own', (tester) async {
      final repository = FakeRepository()
        ..facetItems['genre ge-1'] = <ItemSummary>[
          for (var i = 0; i < 20; i++)
            _track('T${i.toString().padLeft(3, '0')}'),
        ]
        ..finishedPids.add('tr-T001');
      final container = await _pump(
        tester,
        const MusicListingScreen(
          dimension: MusicDimension.genres,
          segment: 'ge-1',
        ),
        repository,
        size: const Size(800, 600),
      );
      final rebuilt = _recordRebuilds();

      // A player checkpoints every few seconds while the track plays.
      _echo(
        container,
        _report('tr-T001', count: 1, positionMs: 30000, second: 5),
      );
      await tester.pump();
      expect(_rowsIn(rebuilt), isEmpty);

      _echo(container, _report('tr-T001', count: 2, positionMs: 0, second: 10));
      await tester.pump();
      expect(_rowsIn(rebuilt), <String>['T001']);
      expect(
        tester
            .widgetList<MediaListRow>(find.byType(MediaListRow))
            .singleWhere((row) => row.data.title == 'T001')
            .data
            .playCount,
        2,
      );
    });

    testWidgets('rows scrolled back to draw the counts their window last '
        'answered while it is read again', (tester) async {
      final tracks = <ItemSummary>[
        for (var i = 0; i < 120; i++)
          _track('T${i.toString().padLeft(3, '0')}'),
      ];
      final repository = FakeRepository()
        ..facetItems['genre ge-1'] = tracks
        ..finishedPids.add('tr-T001');
      await _pump(
        tester,
        const MusicListingScreen(
          dimension: MusicDimension.genres,
          segment: 'ge-1',
        ),
        repository,
        size: const Size(800, 600),
      );
      MediaTileData row(String title) => tester
          .widgetList<MediaListRow>(find.byType(MediaListRow))
          .singleWhere((r) => r.data.title == title)
          .data;
      final scroll = tester.state<ScrollableState>(
        find
            .ancestor(
              of: find.byType(MediaListRow).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final pitch = tester.getSize(find.byType(MediaListRow).first).height;
      expect(row('T001').playCount, 1);

      // Far enough that no row of the first window is built, so it goes.
      scroll.position.jumpTo(70 * pitch);
      await tester.pumpAndSettle();
      expect(_builtWindows(tester), <int>{1});

      final gate = Completer<void>();
      repository.playStatesGate = gate;
      scroll.position.jumpTo(0);
      await tester.pump();
      expect(row('T001').playCount, 1, reason: 'drawn on the first frame');
      // A row asks for its window the frame after it is built.
      await tester.pump();
      expect(repository.playStateBatches.last, <String>[
        for (final track in tracks.take(50)) track.pid,
      ], reason: 'the first window is being read again');
      expect(row('T001').playCount, 1, reason: 'and kept while it is read');

      gate.complete();
      repository.playStatesGate = null;
      await tester.pumpAndSettle();
      expect(row('T001').playCount, 1);
    });
  });

  group('the artist screen', () {
    testWidgets('a refresh redraws the tracks it already has', (tester) async {
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[_track('One', track: 1)];
      final container = await _pump(
        tester,
        const ArtistScreen(pid: 'ar-1', label: 'Nightjar'),
        repository,
      );

      await _expectRefreshKeepsRows(tester, container, repository, (
        dimension: MusicDimension.artists,
        segment: 'ar-1',
        domain: BrowseDomain.wholeLibrary,
      ));
    });

    testWidgets('a top track wears its play count as an album row does', (
      tester,
    ) async {
      // The same component as the album page's rows, fed the same read:
      // a count where the listener finished the track, nothing where they
      // never did.
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[
          _track('One', track: 1),
          _track('Two', track: 2),
        ]
        ..finishedPids.add('tr-One');

      await _pump(
        tester,
        const ArtistScreen(pid: 'ar-1', label: 'Nightjar'),
        repository,
      );

      _expectPlayCounts(tester, repository, <String, int>{'One': 1, 'Two': 0});
    });

    testWidgets('a top track never played draws no count at all', (
      tester,
    ) async {
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[_track('One', track: 1)];

      await _pump(
        tester,
        const ArtistScreen(pid: 'ar-1', label: 'Nightjar'),
        repository,
      );

      _expectPlayCounts(tester, repository, <String, int>{'One': 0});
      expect(find.text('0'), findsNothing);
    });

    testWidgets('a report that moves only a position rebuilds nothing of the '
        'page outside its top tracks', (tester) async {
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[
          _track('One', track: 1),
          _track('Two', track: 2),
        ]
        ..finishedPids.add('tr-One');
      final container = await _pump(
        tester,
        const ArtistScreen(pid: 'ar-1', label: 'Nightjar'),
        repository,
      );
      final releases = tester.element(
        find.byWidgetPredicate(
          (widget) =>
              widget is ShelfRow &&
              widget.title == AppLocalizationsEn().musicArtistReleases,
        ),
      );
      final rebuilt = _recordRebuilds();

      _echo(
        container,
        _report('tr-One', count: 1, positionMs: 30000, second: 5),
      );
      await tester.pump();
      expect(
        container
            .read(
              playProgressProvider(playPidsKey(<String>['tr-One', 'tr-Two'])),
            )
            .value!['tr-One']!
            .positionMs,
        30000,
        reason: 'the window the page reads took the report',
      );
      // The release shelf and what holds it, up to the page. The provider
      // scope above rebuilds on any provider change and passes it down to
      // no one.
      final page = tester.element(find.byType(ArtistScreen));
      bool holdsReleases(Element element) {
        var held = identical(element, releases);
        if (!held) {
          releases.visitAncestorElements((above) {
            held = identical(above, element);
            return !held && !identical(above, page);
          });
        }
        return held;
      }

      expect(rebuilt.where(holdsReleases), isEmpty);
    });

    testWidgets('the header row is one action bar with the menu', (
      tester,
    ) async {
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[_track('One', track: 1)];
      await _pump(
        tester,
        const ArtistScreen(pid: 'ar-1', label: 'Nightjar'),
        repository,
      );

      expectHeaderOnActionBar();
      for (final id in <String>[
        SemanticsIds.entityPlay,
        SemanticsIds.entityShuffle,
        SemanticsIds.entityOverflow,
      ]) {
        expect(inActionBar(id), findsOneWidget, reason: id);
      }
    });

    testWidgets('is titled by the artist, never by a track credit', (
      tester,
    ) async {
      // A track's artist field is what the record credits, features and
      // all. Naming the page from the first row it happened to load put
      // "Dom Kennedy feat. Ty Dolla \$ign" over the whole catalogue.
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[
          _track('One', artist: 'Dom Kennedy feat. Ty Dolla \$ign', track: 1),
        ];
      await _pump(
        tester,
        const ArtistScreen(pid: 'ar-1', label: 'Dom Kennedy'),
        repository,
      );

      expect(find.text('Dom Kennedy'), findsWidgets);
      expect(find.textContaining('feat. Ty Dolla'), findsNothing);
    });

    testWidgets('a link with no name reads the artist off their own card', (
      tester,
    ) async {
      // A shared link and a reload both drop the label the opener had,
      // which is exactly when the old fallback took over.
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[
          _track('One', artist: 'Dom Kennedy feat. Ty Dolla \$ign', track: 1),
        ]
        ..entityCards['ar-1'] = const EntityCard(
          pid: 'ar-1',
          kind: EntityCardKind.artist,
          title: 'Dom Kennedy',
        );
      await _pump(tester, const ArtistScreen(pid: 'ar-1'), repository);

      expect(repository.resolvedEntityPids, contains(equals(<String>['ar-1'])));
      expect(find.text('Dom Kennedy'), findsWidgets);
      expect(find.textContaining('feat. Ty Dolla'), findsNothing);
    });

    testWidgets('an artist that does not exist is not drawn as an empty '
        'artist', (tester) async {
      // The listing answers an empty page for any key, and the entity
      // read drops a pid it cannot answer for.
      await _pump(tester, const ArtistScreen(pid: 'ar-gone'), FakeRepository());

      expect(find.text('Nothing by this artist'), findsNothing);
      expect(find.text('Could not load this artist'), findsOneWidget);
      expect(find.text('That is not here any more.'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(_byId(SemanticsIds.entityPlay), findsNothing);
    });

    testWidgets('an artist with no card falls back to the placeholder', (
      tester,
    ) async {
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[
          _track('One', artist: 'Dom Kennedy feat. Ty Dolla \$ign', track: 1),
        ];
      await _pump(tester, const ArtistScreen(pid: 'ar-1'), repository);

      expect(find.textContaining('feat. Ty Dolla'), findsNothing);
    });

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

    testWidgets('a release card opens the release sheet, a loose one none', (
      tester,
    ) async {
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[
          _track('One', track: 1),
          const ItemSummary(
            pid: 'tr-loose',
            mediaType: MediaType.music,
            title: 'Loose',
            artist: 'Nightjar',
            album: 'Tape Box',
            artistPid: 'ar-1',
            durationMs: 200000,
          ),
        ];
      await _pump(tester, const ArtistScreen(pid: 'ar-1'), repository);

      await rightClick(tester, _byId(SemanticsIds.entityAlbum('al-1')));
      expect(_byId(SemanticsIds.itemMenuSheet('al-1')), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      final loose = find.widgetWithText(MediaCard, 'Tape Box');
      expect(tester.widget<MediaCard>(loose).onPlay, isNull);
      await rightClick(tester, loose);
      expect(find.byType(WaxOptionRow), findsNothing);
    });

    testWidgets('an Appears on card opens the release sheet', (tester) async {
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[_track('Own', track: 1)]
        ..facets['album|credit-artist|1'] = const <FacetBucket>[
          FacetBucket(
            key: 'guest',
            label: 'Big Compilation',
            count: 4,
            entityPid: 'al-guest',
          ),
        ];
      await _pump(tester, const ArtistScreen(pid: 'ar-1'), repository);

      await rightClick(tester, _byId(SemanticsIds.entityAlbum('al-guest')));
      expect(_byId(SemanticsIds.itemMenuSheet('al-guest')), findsOneWidget);
    });

    testWidgets('a release card plays the release from its cover', (
      tester,
    ) async {
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[_track('Two', track: 2)]
        ..facetItems['album 1'] = <ItemSummary>[
          _track('Two', track: 2),
          _track('One', track: 1),
        ];
      final container = await _pump(
        tester,
        const ArtistScreen(pid: 'ar-1'),
        repository,
      );

      await hoverPlay(
        tester,
        find.byType(MediaCard).first,
        label: 'Play Gullwing',
      );
      final queue = container.read(queueControllerProvider);
      expect(queue.source.kind, QueueSourceKind.album);
      expect(queue.source.pid, 'al-1');
      expect(
        <String>[for (final e in queue.entries) e.pid],
        <String>['tr-One', 'tr-Two'],
      );
      await _stop(tester, container);
    });

    testWidgets('a top track opens the item menu', (tester) async {
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[_track('One', track: 1)];
      await _pump(tester, const ArtistScreen(pid: 'ar-1'), repository);

      await rightClick(tester, _byId(SemanticsIds.indexItem(0)));
      expect(_byId(SemanticsIds.itemMenuSheet('tr-One')), findsOneWidget);
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

      // Music, like every listing under /music: the tracks this section
      // listed, not the books beside them.
      expect(
        tester
            .widget<MusicListingScreen>(find.byType(MusicListingScreen))
            .domain,
        BrowseDomain.music,
      );
    });

    testWidgets('an artist whose whole catalogue fits offers no Show all', (
      tester,
    ) async {
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[_track('One'), _track('Two')];

      await _pump(tester, const ArtistScreen(pid: 'ar-1'), repository);

      expect(find.text('Show all'), findsNothing);
    });

    ItemSummary book(String n) => ItemSummary(
      pid: 'bk-$n',
      mediaType: MediaType.audiobook,
      title: 'A long book $n',
      artist: 'Nightjar',
      durationMs: 43200000,
    );

    testWidgets('an artist\'s page splits its tracks from its books', (
      tester,
    ) async {
      // A bucket counts whatever carried the artist, and a book carries
      // one. The page reads it all, so an author still gets their books,
      // but each medium is counted and listed as itself: the music index
      // says "3 tracks" and so does this page.
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[
          _track('One'),
          book('1'),
          _track('Two'),
          book('2'),
          _track('Three'),
        ];
      final container = await _pump(
        tester,
        const ArtistScreen(pid: 'ar-1'),
        repository,
      );

      expect(find.textContaining('3 tracks · 2 books'), findsOneWidget);
      expect(_rowTitles(tester), ['One', 'Two', 'Three']);
      expect(find.text('Tracks'), findsOneWidget);
      expect(find.text('Audiobooks'), findsOneWidget);
      for (final pid in <String>['bk-1', 'bk-2']) {
        expect(find.bySemanticsIdentifier(SemanticsIds.book(pid)), findsOne);
      }

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.entityPlay));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(container.read(queueControllerProvider).pids, [
        'tr-One',
        'tr-Two',
        'tr-Three',
      ]);
      await _stop(tester, container);
    });

    testWidgets('the books shelf goes to the author\'s books', (tester) async {
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[_track('One'), book('1')];
      await _pump(tester, const ArtistScreen(pid: 'ar-1'), repository);

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.entityAllBooks));
      await tester.pumpAndSettle();
      final page = tester.widget<BookBucketScreen>(
        find.byType(BookBucketScreen),
      );
      expect((page.dimension, page.segment), (BookDimension.authors, 'ar-1'));
    });

    testWidgets('a cover on the books shelf resumes its book in place, and '
        'its menu carries the book\'s verbs', (tester) async {
      const authored = ItemSummary(
        pid: 'bk-1',
        mediaType: MediaType.audiobook,
        title: 'A long book 1',
        artist: 'Nightjar',
        artistPid: 'ar-1',
        durationMs: 43200000,
      );
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[_track('One'), authored]
        ..playPositions['bk-1'] = 600000;
      final container = await _pump(
        tester,
        const ArtistScreen(pid: 'ar-1'),
        repository,
      );

      await semanticsPlay(
        tester,
        _byId(SemanticsIds.book('bk-1')),
        playId: SemanticsIds.bookPlay('bk-1'),
        label: 'Resume A long book 1',
      );
      expect(container.read(queueControllerProvider).pids, ['bk-1']);
      expect(find.byType(ArtistScreen), findsOneWidget);
      await _stop(tester, container);

      await rightClick(tester, _byId(SemanticsIds.book('bk-1')));
      expect(_byId(SemanticsIds.itemMenuPlay), findsOneWidget);
      expect(_byId(SemanticsIds.itemMenuGoAuthor), findsOneWidget);
    });

    testWidgets('an author with no tracks draws the books shelf alone', (
      tester,
    ) async {
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[book('1'), book('2')];
      await _pump(tester, const ArtistScreen(pid: 'ar-1'), repository);

      expect(find.textContaining('2 books'), findsOneWidget);
      expect(find.textContaining('tracks'), findsNothing);
      expect(find.text('Tracks'), findsNothing);
      expect(_rowTitles(tester), isEmpty);
      expect(find.text('Audiobooks'), findsOneWidget);
    });

    testWidgets('a music artist draws no books shelf', (tester) async {
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[_track('One')];
      await _pump(tester, const ArtistScreen(pid: 'ar-1'), repository);

      expect(find.textContaining('1 track · '), findsOneWidget);
      expect(find.textContaining('book'), findsNothing);
      expect(find.text('Audiobooks'), findsNothing);
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

      final l10n = AppLocalizationsEn();
      expect(
        codecChipLabel(l10n, detail(codec: 'flac', rate: 44100)),
        'FLAC 44.1 kHz',
      );
      expect(
        codecChipLabel(l10n, detail(codec: 'flac', rate: 48000)),
        'FLAC 48 kHz',
      );
      expect(codecChipLabel(l10n, detail(codec: 'flac')), 'FLAC');
      // The rates that are not whole thousands keep every digit they
      // need: half of 44.1 is 22.05, not 22.1, and spoken-word files
      // are full of it.
      expect(
        codecChipLabel(l10n, detail(codec: 'mp3', rate: 22050)),
        'MP3 22.05 kHz',
      );
      // A rate with no codec is still worth saying, and saying it must
      // not leave the space the codec would have filled.
      expect(codecChipLabel(l10n, detail(rate: 44100)), '44.1 kHz');
      expect(codecChipLabel(l10n, detail(codec: '', rate: 44100)), '44.1 kHz');
      expect(codecChipLabel(l10n, detail()), isEmpty);
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
