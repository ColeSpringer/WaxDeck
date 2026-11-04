import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/books/book_bucket_screen.dart';
import 'package:waxdeck/src/books/book_dimension.dart';
import 'package:waxdeck/src/books/book_screen.dart';
import 'package:waxdeck/src/music/index_screen.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

const _dune = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';
const _messiah = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK02';

ItemSummary _book(String pid, String title) => ItemSummary(
  pid: pid,
  mediaType: MediaType.audiobook,
  title: title,
  artist: 'F. Herbert',
  durationMs: 3600000,
);

Future<void> _pump(
  WidgetTester tester,
  FakeRepository repository,
  BookBucketScreen screen,
) async {
  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repository),
        audioEngineProvider.overrideWithValue(FakeEngine()),
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      ],
      child: routedHost(screen),
    ),
  );
  await tester.pumpAndSettle();
}

List<String> _covers(WidgetTester tester) => <String>[
  for (final card in tester.widgetList<MediaCard>(find.byType(MediaCard)))
    card.data.title,
];

void main() {
  group('an author page', () {
    testWidgets('lists the author\'s books, named from their card', (
      tester,
    ) async {
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[
          _book(_dune, 'Dune'),
          _book(_messiah, 'Dune Messiah'),
        ]
        ..entityCards['ar-1'] = const EntityCard(
          pid: 'ar-1',
          kind: EntityCardKind.artist,
          title: 'Frank Herbert',
        );
      await _pump(
        tester,
        repository,
        const BookBucketScreen(
          dimension: BookDimension.authors,
          segment: 'ar-1',
        ),
      );

      final drill = repository.listItemsCalls.single;
      expect(drill.mediaType, MediaType.audiobook);
      expect(drill.facet, 'artist');
      expect(drill.facetKey, '1');
      // A cold link carries no label, so the author's own card names
      // the page rather than a book's credit line.
      expect(repository.resolvedEntityPids, <List<String>>[
        <String>['ar-1'],
      ]);
      expect(find.text('Frank Herbert'), findsWidgets);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.bookAuthorScreen('ar-1')),
        findsOneWidget,
      );
      expect(_covers(tester), <String>['Dune', 'Dune Messiah']);
    });

    testWidgets('takes the caller\'s label and opens a book by push', (
      tester,
    ) async {
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[_book(_dune, 'Dune')];
      await _pump(
        tester,
        repository,
        const BookBucketScreen(
          dimension: BookDimension.authors,
          segment: 'ar-1',
          label: 'F. Herbert',
        ),
      );
      expect(find.text('F. Herbert'), findsWidgets);

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.book(_dune)));
      await tester.pumpAndSettle();

      expect(find.byType(BookScreen), findsOneWidget);
      // Pushed: a book's declared parent is the hub, so going there
      // would throw the author page away beneath it.
      final router = GoRouter.of(tester.element(find.byType(BookScreen)));
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(BookBucketScreen), findsOneWidget);
    });

    testWidgets('a cold link to an author with no card reads in the singular', (
      tester,
    ) async {
      final repository = FakeRepository()
        ..facetItems['artist 1'] = <ItemSummary>[_book(_dune, 'Dune')];
      await _pump(
        tester,
        repository,
        const BookBucketScreen(
          dimension: BookDimension.authors,
          segment: 'ar-1',
        ),
      );

      // The index's plural names the list of authors, not this one.
      expect(find.text('Authors'), findsNothing);
      expect(find.text('Author'), findsWidgets);
    });

    testWidgets('an empty author page with no card says it is not found', (
      tester,
    ) async {
      final repository = FakeRepository();
      await _pump(
        tester,
        repository,
        const BookBucketScreen(
          dimension: BookDimension.authors,
          segment: 'ar-1',
        ),
      );

      expect(find.byType(MediaCard), findsNothing);
      expect(find.text('No books here'), findsNothing);
      expect(find.byType(ErrorState), findsOneWidget);
      // The page's own sentence, not the hub's.
      expect(find.text('Could not load this author'), findsOneWidget);
      expect(find.text('Could not load your books'), findsNothing);
    });

    testWidgets('the unknown bucket is titled in the reader\'s language', (
      tester,
    ) async {
      final repository = FakeRepository()
        ..facetItems['artist '] = <ItemSummary>[_book(_dune, 'Dune')];
      await _pump(
        tester,
        repository,
        const BookBucketScreen(
          dimension: BookDimension.authors,
          segment: musicUnknownSegment,
        ),
      );

      expect(repository.listItemsCalls.single.facetKey, '');
      expect(find.text('Unknown author'), findsWidgets);
      // The sentinel is no pid, so there is no card to ask for.
      expect(repository.resolvedEntityPids, isEmpty);
    });
  });

  group('a genre page', () {
    testWidgets('lists the genre\'s books under its label', (tester) async {
      final repository = FakeRepository()
        ..facetItems['genre 01JZXG'] = <ItemSummary>[_book(_dune, 'Dune')];
      await _pump(
        tester,
        repository,
        const BookBucketScreen(
          dimension: BookDimension.genres,
          segment: '01JZXG',
          label: 'Science Fiction',
        ),
      );

      final drill = repository.listItemsCalls.single;
      expect(drill.mediaType, MediaType.audiobook);
      expect(drill.facet, 'genre');
      expect(drill.facetKey, '01JZXG');
      expect(find.text('Science Fiction'), findsWidgets);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.bookGenreScreen('01JZXG')),
        findsOneWidget,
      );
      expect(_covers(tester), <String>['Dune']);
    });

    testWidgets('pages past its first 500 books, and counts them once whole', (
      tester,
    ) async {
      final books = <ItemSummary>[
        for (var i = 1; i <= 501; i++)
          _book(
            'bk-01JZX5N8QW3F4V9T2B7K${i.toString().padLeft(4, '0')}',
            'Book ${i.toString().padLeft(4, '0')}',
          ),
      ];
      final repository = FakeRepository()..facetItems['genre 01JZXG'] = books;
      await _pump(
        tester,
        repository,
        const BookBucketScreen(
          dimension: BookDimension.genres,
          segment: '01JZXG',
          label: 'Science Fiction',
        ),
      );
      expect(repository.listItemsCalls, hasLength(1));
      // No total while pages are unread: a keyset listing knows none.
      expect(find.textContaining(' books'), findsNothing);

      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(repository.listItemsCalls, hasLength(2));
      expect(repository.listItemsCalls.last.cursor, isNotNull);
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('Book 0501'), findsOneWidget);

      scroll.position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.text('501 books'), findsOneWidget);
    });

    testWidgets('an emptied genre says there is nothing here', (tester) async {
      final repository = FakeRepository()
        ..facetItems['genre 01JZXG'] = const <ItemSummary>[];
      await _pump(
        tester,
        repository,
        const BookBucketScreen(
          dimension: BookDimension.genres,
          segment: '01JZXG',
          label: 'Science Fiction',
        ),
      );
      expect(find.text('No books here'), findsOneWidget);
      expect(find.byType(MediaCard), findsNothing);
    });

    testWidgets('back from a cold link lands on its index', (tester) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final location = WaxRoute.bookBucket(BookDimension.genres, '01JZXG');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(
              FakeRepository()
                ..facetItems['genre 01JZXG'] = <ItemSummary>[
                  _book(_dune, 'Dune'),
                ],
            ),
            audioEngineProvider.overrideWithValue(FakeEngine()),
            credentialStoreProvider.overrideWithValue(
              InMemoryCredentialStore(),
            ),
          ],
          child: routedHost(
            const BookBucketScreen(
              dimension: BookDimension.genres,
              segment: '01JZXG',
              label: 'Science Fiction',
            ),
            at: location,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      final index = tester.widget<MusicIndexScreen>(
        find.byType(MusicIndexScreen),
      );
      expect(index.domain, BrowseDomain.books);
      expect(index.dimension, MusicDimension.genres);
      expect(
        GoRouter.of(
          tester.element(find.byType(MusicIndexScreen)),
        ).routerDelegate.currentConfiguration.uri.path,
        WaxRoute.bookIndex(BookDimension.genres),
      );
    });

    testWidgets('a genre that cannot be read says so in its own words', (
      tester,
    ) async {
      final repository = FakeRepository()
        ..listError = const WaxDeckApiException(
          code: 'not-found',
          message: 'no such genre',
          statusCode: 404,
        );
      await _pump(
        tester,
        repository,
        const BookBucketScreen(
          dimension: BookDimension.genres,
          segment: '01JZXG',
          label: 'Science Fiction',
        ),
      );

      expect(find.text('Could not load this genre'), findsOneWidget);
      expect(find.text('Could not load your books'), findsNothing);
    });

    testWidgets('a cold link is titled in words, never by its key', (
      tester,
    ) async {
      // A genre key is a catalog id, which names nothing to a reader.
      final repository = FakeRepository()
        ..facetItems['genre 01JZXG'] = <ItemSummary>[_book(_dune, 'Dune')];
      await _pump(
        tester,
        repository,
        const BookBucketScreen(
          dimension: BookDimension.genres,
          segment: '01JZXG',
        ),
      );

      expect(find.text('01JZXG'), findsNothing);
      expect(find.text('Genre'), findsWidgets);
    });

    testWidgets('the unknown bucket is titled in the reader\'s language', (
      tester,
    ) async {
      final repository = FakeRepository();
      await _pump(
        tester,
        repository,
        const BookBucketScreen(
          dimension: BookDimension.genres,
          segment: musicUnknownSegment,
        ),
      );

      expect(find.text('No genre'), findsWidgets);
    });
  });
}
