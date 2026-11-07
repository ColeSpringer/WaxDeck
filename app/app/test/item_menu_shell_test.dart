import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/books/book_bucket_screen.dart';
import 'package:waxdeck/src/books/book_dimension.dart';
import 'package:waxdeck/src/books/book_screen.dart';
import 'package:waxdeck/src/library/item_menu.dart';
import 'package:waxdeck/src/metadata/metadata_screen.dart';
import 'package:waxdeck/src/music/artist_screen.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/podcasts/show_screen.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_screen.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/shell/adaptive_shell.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/side_panel.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';
import 'secondary_click.dart';

const _book = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';

const _track = 'tr-01JZX5N8QW3F4V9T2B7KDTRACK1';
const _artist = 'ar-01JZX5N8QW3F4V9T2B7KDARTIST';

const _author = 'ar-01JZX5N8QW3F4V9T2B7KDAUTHOR';

const _bookSummary = ItemSummary(
  pid: _book,
  mediaType: MediaType.audiobook,
  title: 'There And Back Again',
  artist: 'B. Baggins',
  artistPid: _author,
  durationMs: 3600000,
);

const _trackSummary = ItemSummary(
  pid: _track,
  mediaType: MediaType.music,
  title: 'Low Tide',
  artist: 'The Shore',
  artistPid: _artist,
  durationMs: 200000,
);

/// The whole app, signed in, over a library holding one book part way
/// through and one track: the item menu's doors are driven from the
/// shell's pages, its side panel and the overlays beside it, where
/// `routedHost`'s mount cannot put them.
Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  Size size = const Size(1400, 1000),
  List<String> roles = const <String>['member'],
  void Function(FakeRepository repo)? seed,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = FakeRepository(
    sessionState: SessionState(
      authenticated: true,
      user: WaxDeckUser(id: 'us-1', username: 'reader', roles: roles),
    ),
    items: const <ItemSummary>[_bookSummary, _trackSummary],
  )..playPositions[_book] = 900000;
  seed?.call(repo);
  final container = appContainer(repo: repo);
  return pumpWholeApp(tester, container: container);
}

/// Puts [item] in the deck and answers its queue row's menu handle.
Future<Finder> _queue(
  WidgetTester tester,
  ProviderContainer container,
  ItemSummary item,
) async {
  container.read(nowPlayingProvider.notifier).play(
    <ItemSummary>[item],
    source: QueueSource(
      kind: QueueSourceKind.single,
      label: item.title,
      pid: item.pid,
    ),
  );
  await tester.pumpAndSettle();
  final entry = container.read(queueControllerProvider).currentEntry!;
  return find.bySemanticsIdentifier(SemanticsIds.queueEntryMore(entry.queueId));
}

/// Raises [more]'s menu and takes the row [rowId].
Future<void> _door(WidgetTester tester, Finder more, String rowId) async {
  await tester.tap(more);
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsIdentifier(rowId));
  await tester.pumpAndSettle();
}

/// Lets the deck go, so no session outlives the test.
Future<void> _clearDeck(
  WidgetTester tester,
  ProviderContainer container,
) async {
  container.read(queueControllerProvider.notifier).clear();
  await tester.pump(const Duration(seconds: 1));
}

String _location(ProviderContainer container) => container
    .read(routerProvider)
    .routerDelegate
    .currentConfiguration
    .uri
    .toString();

Future<void> _openBook(WidgetTester tester, Finder card) async {
  await rightClick(tester, card);
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.itemMenuOpenBook));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('from the books hub, Open book goes to the book beneath it', (
    tester,
  ) async {
    final container = await _pumpApp(tester);
    container.read(routerProvider).go(WaxRoute.books);
    await tester.pumpAndSettle();

    // The grid's tap opens the book already, so its menu has no door.
    await rightClick(
      tester,
      find.bySemanticsIdentifier(SemanticsIds.book(_book)),
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.itemMenuOpenBook),
      findsNothing,
    );
    Navigator.of(
      tester.element(
        find.bySemanticsIdentifier(SemanticsIds.itemMenuSheet(_book)),
      ),
    ).pop();
    await tester.pumpAndSettle();

    // The Continue shelf's tap resumes, so its menu is the way in.
    await _openBook(
      tester,
      find.bySemanticsIdentifier(SemanticsIds.bookContinue(_book)),
    );
    expect(find.byType(BookScreen), findsOneWidget);
    // Gone to, as the hub's own tap goes: the address bar follows, and
    // back is the hub.
    expect(_location(container), WaxRoute.book(_book));
    container.read(routerProvider).pop();
    await tester.pumpAndSettle();
    expect(_location(container), WaxRoute.books);
  });

  testWidgets('raised on its show, a show-scoped Open episode goes', (
    tester,
  ) async {
    const show = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
    const episode = 'tr-01JZX5N8QW3F4V9T2B7KDEPISOD';
    final container = await _pumpApp(tester);
    final router = container.read(routerProvider);
    router.go(WaxRoute.show(show));
    await tester.pumpAndSettle();

    final page = tester.element(find.byType(ShowScreen));
    unawaited(
      showItemMenuSheet(
        page,
        page as WidgetRef,
        pid: episode,
        title: 'Second Breakfast',
        mediaType: MediaType.podcast,
        withOpen: true,
        showPid: show,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.itemMenuOpenEpisode),
    );
    await tester.pumpAndSettle();

    // Declared beneath the show two segments down: gone to, so the
    // address bar follows and back is the show.
    expect(_location(container), WaxRoute.showEpisode(show, episode));
    router.pop();
    await tester.pumpAndSettle();
    expect(_location(container), WaxRoute.show(show));
  });

  testWidgets('from home, Open book pushes over the shelves', (tester) async {
    final container = await _pumpApp(tester);
    expect(_location(container), WaxRoute.home);

    await _openBook(
      tester,
      find.bySemanticsIdentifier(SemanticsIds.shelfCard('continue', _book)),
    );
    expect(find.byType(BookScreen), findsOneWidget);
    // Pushed: home is not the book's parent, so the shelves stay beneath
    // it and the location go_router reports is still home's.
    expect(_location(container), WaxRoute.home);
    container.read(routerProvider).pop();
    await tester.pumpAndSettle();
    expect(find.byType(BookScreen), findsNothing);
    expect(_location(container), WaxRoute.home);
  });

  group('raised over the queue overlay, a door leaves it for the shell', () {
    Future<(ProviderContainer, Finder)> openQueue(
      WidgetTester tester,
      ItemSummary item, {
      List<String> roles = const <String>['member'],
    }) async {
      final container = await _pumpApp(
        tester,
        size: const Size(500, 1000),
        roles: roles,
      );
      final more = await _queue(tester, container, item);
      container.read(routerProvider).push<void>(WaxRoute.queue);
      await tester.pumpAndSettle();
      expect(find.byType(QueueScreen), findsOneWidget);
      return (container, more);
    }

    testWidgets('Open book', (tester) async {
      final (container, more) = await openQueue(tester, _bookSummary);
      await _door(tester, more, SemanticsIds.itemMenuOpenBook);
      expect(tester.takeException(), isNull);
      expect(find.byType(BookScreen), findsOneWidget);
      expect(find.byType(QueueScreen), findsNothing);
      expect(find.byType(AdaptiveShell, skipOffstage: false), findsOneWidget);
      await _clearDeck(tester, container);
    });

    testWidgets('Go to artist', (tester) async {
      final (container, more) = await openQueue(tester, _trackSummary);
      await _door(tester, more, SemanticsIds.itemMenuGoArtist);
      expect(tester.takeException(), isNull);
      expect(find.byType(ArtistScreen), findsOneWidget);
      expect(find.byType(QueueScreen), findsNothing);
      expect(find.byType(AdaptiveShell, skipOffstage: false), findsOneWidget);
      await _clearDeck(tester, container);
    });

    testWidgets('Edit metadata', (tester) async {
      final (container, more) = await openQueue(
        tester,
        _trackSummary,
        roles: const <String>['admin'],
      );
      await tester.tap(more);
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.editMetadata(_track)),
      );
      // Bounded: the editor spins while its reads are in flight.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect(find.byType(MetadataScreen), findsOneWidget);
      expect(find.byType(QueueScreen), findsNothing);
      expect(find.byType(AdaptiveShell, skipOffstage: false), findsOneWidget);
      await _clearDeck(tester, container);
    });
  });

  testWidgets('from the queue side panel, Open book pushes over the page', (
    tester,
  ) async {
    final container = await _pumpApp(tester, size: const Size(1600, 1000));
    final more = await _queue(tester, container, _bookSummary);
    container.read(routerProvider).go(WaxRoute.music);
    await tester.pumpAndSettle();
    container.read(sidePanelProvider.notifier).toggle(WaxPanel.queue);
    await tester.pumpAndSettle();

    await _door(tester, more.first, SemanticsIds.itemMenuOpenBook);
    expect(tester.takeException(), isNull);
    expect(find.byType(BookScreen), findsOneWidget);
    // Pushed: the page the panel stands beside stays beneath it.
    expect(_location(container), WaxRoute.music);
    container.read(routerProvider).pop();
    await tester.pumpAndSettle();
    expect(find.byType(BookScreen), findsNothing);
    expect(_location(container), WaxRoute.music);
    await _clearDeck(tester, container);
  });

  group('a door to the page the sheet stands on is not drawn', () {
    testWidgets('Go to author on that author\'s page', (tester) async {
      final container = await _pumpApp(
        tester,
        seed: (repo) => repo
          ..facetItems['artist ${_author.substring(3)}'] = <ItemSummary>[
            _bookSummary,
          ]
          ..facetItems['genre Fantasy'] = <ItemSummary>[_bookSummary],
      );
      final router = container.read(routerProvider);
      router.go(WaxRoute.bookBucket(BookDimension.authors, _author));
      await tester.pumpAndSettle();
      await rightClick(
        tester,
        find.bySemanticsIdentifier(SemanticsIds.book(_book)),
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.itemMenuSheet(_book)),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.itemMenuGoAuthor),
        findsNothing,
      );
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      // A genre page is not the author's, so there it leads somewhere.
      router.go(WaxRoute.bookBucket(BookDimension.genres, 'Fantasy'));
      await tester.pumpAndSettle();
      await rightClick(
        tester,
        find.bySemanticsIdentifier(SemanticsIds.book(_book)),
      );
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.itemMenuGoAuthor),
      );
      await tester.pumpAndSettle();
      final page = tester.widget<BookBucketScreen>(
        find.byType(BookBucketScreen),
      );
      expect(page.dimension, BookDimension.authors);
      expect(page.segment, _author);
    });

    testWidgets('Go to artist on that artist\'s page', (tester) async {
      final container = await _pumpApp(
        tester,
        seed: (repo) => repo
          ..facetItems['artist ${_artist.substring(3)}'] = <ItemSummary>[
            _trackSummary,
          ],
      );
      container
          .read(routerProvider)
          .go(WaxRoute.musicBucket(MusicDimension.artists, _artist));
      await tester.pumpAndSettle();
      expect(find.byType(ArtistScreen), findsOneWidget);
      await rightClick(
        tester,
        find.bySemanticsIdentifier(SemanticsIds.indexItem(0)),
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.itemMenuSheet(_track)),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.itemMenuGoArtist),
        findsNothing,
      );
    });
  });
}
