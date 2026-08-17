import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/books/books_controller.dart';
import 'package:waxdeck/src/books/books_screen.dart';
import 'package:waxdeck/src/player/play_progress.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

/// Pids sort by ULID, which is what "recently added" reads off, so these
/// are ordered oldest to newest deliberately.
const _hobbit = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';
const _dune = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK02';
const _foundation = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK03';

ItemSummary _book(
  String pid, {
  required String title,
  String? author,
  int durationMs = 3600000,
}) => ItemSummary(
  pid: pid,
  mediaType: MediaType.audiobook,
  title: title,
  artist: author,
  durationMs: durationMs,
);

FakeRepository _repo() => FakeRepository(
  items: <ItemSummary>[
    _book(_hobbit, title: 'There And Back Again', author: 'B. Baggins'),
    _book(_dune, title: 'Arrakis', author: 'F. Herbert'),
    _book(_foundation, title: 'Trantor', author: 'B. Baggins'),
    // A track, to prove the hub asks for audiobooks and not for
    // everything: a library is mostly music.
    testItem('tr-01JZX5N8QW3F4V9T2B7KDTRACK1'),
  ],
);

String _volume(int i) =>
    'bk-01JZX5N8QW3F4V9T2B7KDV${i.toString().padLeft(5, '0')}';

/// One book past a page, so the listing hands back a cursor.
FakeRepository _paged() => FakeRepository(
  items: <ItemSummary>[
    for (var i = 0; i <= BooksController.pageSize; i++)
      _book(_volume(i), title: 'Volume ${i.toString().padLeft(3, '0')}'),
  ],
);

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    audioEngineProvider.overrideWithValue(FakeEngine()),
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
  ],
  child: routedHost(const BooksScreen()),
);

Finder _byId(String id) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.identifier == id,
);

Future<void> _tap(WidgetTester tester, String id) async {
  final finder = _byId(id).first;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// The titles in the order the grid draws them.
List<String> _order(WidgetTester tester) => <String>[
  for (final card in tester.widgetList<MediaCard>(find.byType(MediaCard)))
    card.data.title,
];

void main() {
  testWidgets('the grid holds the audiobooks and nothing else', (tester) async {
    await tester.pumpWidget(_host(_repo()));
    await tester.pumpAndSettle();

    expect(_byId(SemanticsIds.book(_hobbit)), findsOneWidget);
    expect(_byId(SemanticsIds.book(_dune)), findsOneWidget);
    expect(
      find.text('Prancing Pony Blues'),
      findsNothing,
      reason: 'the music in the library is not on the books hub',
    );
  });

  testWidgets('an empty library says how books arrive', (tester) async {
    await tester.pumpWidget(_host(FakeRepository()));
    await tester.pumpAndSettle();
    expect(find.text('No audiobooks yet'), findsOneWidget);
  });

  testWidgets('a server that will not answer offers a retry', (tester) async {
    final repo = FakeRepository()
      ..listError = const WaxDeckApiException(
        code: 'transport',
        message: 'network unreachable',
      );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();
    expect(find.text('Could not load your books'), findsOneWidget);
    // The code's sentence rather than the transport's diagnostic.
    expect(
      find.text(
        'Could not reach the server. Check the connection and try '
        'again.',
      ),
      findsOneWidget,
    );
  });

  group('order', () {
    testWidgets('leads with what the catalog took most recently', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_repo()));
      await tester.pumpAndSettle();
      // Descending pid, which is descending mint time.
      expect(_order(tester), ['Trantor', 'Arrakis', 'There And Back Again']);
    });

    testWidgets('sorts by title and by author', (tester) async {
      await tester.pumpWidget(_host(_repo()));
      await tester.pumpAndSettle();

      await _tap(tester, SemanticsIds.booksHubOverflow);
      await _tap(tester, SemanticsIds.bookSort(BookSort.title.name));
      expect(_order(tester), ['Arrakis', 'There And Back Again', 'Trantor']);

      await _tap(tester, SemanticsIds.booksHubOverflow);
      await _tap(tester, SemanticsIds.bookSort(BookSort.author.name));
      expect(_order(tester), [
        // Both Baggins books, alphabetical within the author.
        'There And Back Again',
        'Trantor',
        'Arrakis',
      ]);
    });
  });

  group('filters', () {
    testWidgets('an author chip narrows the shelf and clears again', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_repo()));
      await tester.pumpAndSettle();

      await _tap(tester, SemanticsIds.bookAuthorFilter('B. Baggins'));
      expect(_order(tester), ['Trantor', 'There And Back Again']);

      // The same chip again clears it: the row is single-select, so this
      // is the only way back to everything.
      await _tap(tester, SemanticsIds.bookAuthorFilter('B. Baggins'));
      expect(_order(tester), hasLength(3));
    });

    test('narrowing to an author is not a toggle', () {
      // Following a series from a book whose author the hub already held
      // must narrow, not clear.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final view = container.read(bookViewProvider.notifier);

      view.narrowToAuthor('B. Baggins');
      expect(container.read(bookViewProvider).author, 'B. Baggins');
      view.narrowToAuthor('B. Baggins');
      expect(container.read(bookViewProvider).author, 'B. Baggins');
      // The chip row still toggles.
      view.toggleAuthor('B. Baggins');
      expect(container.read(bookViewProvider).author, isNull);
    });

    testWidgets('finished and unfinished read the play states', (tester) async {
      final repo = _repo()..finishedPids.add(_dune);
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      await _tap(
        tester,
        SemanticsIds.bookFinishedFilter(BookFilter.finished.name),
      );
      expect(_order(tester), ['Arrakis']);

      await _tap(
        tester,
        SemanticsIds.bookFinishedFilter(BookFilter.unfinished.name),
      );
      expect(_order(tester), ['Trantor', 'There And Back Again']);
    });

    testWidgets('a filter that matches nothing offers the way out', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_repo()));
      await tester.pumpAndSettle();

      await _tap(
        tester,
        SemanticsIds.bookFinishedFilter(BookFilter.finished.name),
      );
      // Not the empty-library state: the way out is the chips, not a scan.
      expect(find.text('Nothing matches'), findsOneWidget);
      await tester.tap(find.text('Show all books'));
      await tester.pumpAndSettle();
      expect(_order(tester), hasLength(3));
    });

    testWidgets('a short filtered shelf offers the pages behind it', (
      tester,
    ) async {
      // The chips narrow the loaded pages, so one match of five hundred
      // is too short to scroll and the scroll listener never pages.
      final repo = _paged()..finishedPids.add(_volume(0));
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      await _tap(
        tester,
        SemanticsIds.bookFinishedFilter(BookFilter.finished.name),
      );
      expect(_order(tester), ['Volume 000']);

      await tester.tap(find.text('Load more books'));
      await tester.pumpAndSettle();

      // The last page landed, so there is nothing left to offer.
      expect(find.text('Load more books'), findsNothing);
      expect(_order(tester), ['Volume 000']);
    });

    testWidgets('an empty filtered shelf offers a fetch before a reset', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_paged()));
      await tester.pumpAndSettle();

      await _tap(
        tester,
        SemanticsIds.bookFinishedFilter(BookFilter.finished.name),
      );
      expect(find.text('Nothing matches yet'), findsOneWidget);

      await tester.tap(find.text('Load more books'));
      await tester.pumpAndSettle();

      // Out of pages: now it really is an answer, and the way out is the
      // chips again.
      expect(find.text('Nothing matches'), findsOneWidget);
      expect(find.text('Show all books'), findsOneWidget);
    });

    testWidgets('one author gets no chip row at all', (tester) async {
      final repo = FakeRepository(
        items: <ItemSummary>[
          _book(_hobbit, title: 'There And Back Again', author: 'B. Baggins'),
        ],
      );
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();
      expect(_byId(SemanticsIds.bookAuthorFilter('B. Baggins')), findsNothing);
    });
  });

  group('continue listening', () {
    testWidgets('holds what is part way through, most recent first', (
      tester,
    ) async {
      final repo = _repo()
        ..playPositions[_hobbit] = 1800000
        ..playPositions[_dune] = 900000
        ..playStateUpdatedAt[_hobbit] = DateTime.utc(2026, 7, 1)
        ..playStateUpdatedAt[_dune] = DateTime.utc(2026, 7, 20);
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      expect(find.text('Continue listening'), findsOneWidget);
      // The shelf and the grid both draw cards, so the shelf's are the
      // ones inside it.
      final shelf = find.descendant(
        of: find.byType(ShelfRow),
        matching: find.byType(MediaCard),
      );
      expect(
        <String>[
          for (final card in tester.widgetList<MediaCard>(shelf))
            card.data.title,
        ],
        ['Arrakis', 'There And Back Again'],
      );
    });

    testWidgets('says what is left of a book, not where it is', (tester) async {
      final repo = _repo()..playPositions[_hobbit] = 900000;
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      // 45 minutes of an hour-long book, abbreviated to what a cell has
      // room for. The spelled form is what a screen reader hears.
      expect(find.text('45 min left'), findsWidgets);
      final card = tester.widget<MediaCard>(
        find
            .descendant(
              of: find.byType(ShelfRow),
              matching: find.byType(MediaCard),
            )
            .first,
      );
      expect(card.data.trailingSpoken, '45 minutes left');
    });

    testWidgets('is absent until something has been started', (tester) async {
      await tester.pumpWidget(_host(_repo()));
      await tester.pumpAndSettle();
      expect(find.text('Continue listening'), findsNothing);
    });

    testWidgets('a finished book is not part way through', (tester) async {
      final repo = _repo()
        ..playPositions[_hobbit] = 3600000
        ..finishedPids.add(_hobbit);
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();
      expect(find.text('Continue listening'), findsNothing);
      // It says so on the cover instead. Asserted on the card rather than
      // on the text, because the filter chip wears the same word.
      final card = tester
          .widgetList<MediaCard>(find.byType(MediaCard))
          .firstWhere((c) => c.data.title == 'There And Back Again');
      expect(card.data.trailingText, 'Finished');
    });
  });

  group('arrangement', () {
    test('an unattributed book sorts last by author, not first', () {
      final books = <ItemSummary>[
        _book('bk-1', title: 'Anon'),
        _book('bk-2', title: 'Arrakis', author: 'F. Herbert'),
      ];
      final sorted = arrangeBooks(
        books,
        const BookView(sort: BookSort.author),
        PlayProgressView.empty,
      );
      expect(sorted.map((b) => b.title), ['Arrakis', 'Anon']);
    });

    test('authors come biggest first, alphabetical within a count', () {
      final authors = bookAuthors(<ItemSummary>[
        _book('bk-1', title: 'One', author: 'Zed'),
        _book('bk-2', title: 'Two', author: 'Ann'),
        _book('bk-3', title: 'Three', author: 'Ann'),
        _book('bk-4', title: 'Four', author: 'Mo'),
        _book('bk-5', title: 'Five'),
      ]);
      expect(authors.map((a) => a.name), ['Ann', 'Mo', 'Zed']);
      expect(authors.first.count, 2);
    });
  });
}
