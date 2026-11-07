import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/books/book_dimension.dart';
import 'package:waxdeck/src/books/book_screen.dart';
import 'package:waxdeck/src/books/books_controller.dart';
import 'package:waxdeck/src/books/books_screen.dart';
import 'package:waxdeck/src/books/series_index_screen.dart';
import 'package:waxdeck/src/books/series_screen.dart';
import 'package:waxdeck/src/l10n/l10n.dart';
import 'package:waxdeck/src/music/index_screen.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/player/play_progress.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck/src/shell/async_sliver_face.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck/src/uploads/add_to_library.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'player_host.dart';
import 'routed_host.dart';
import 'secondary_click.dart';
import 'wax_finders.dart';

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

Widget _host(FakeRepository repo, {bool offline = false}) => ProviderScope(
  overrides: [
    if (offline) offlineProvider.overrideWithValue(true),
    repositoryProvider.overrideWithValue(repo),
    audioEngineProvider.overrideWithValue(FakeEngine()),
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
  ],
  child: routedHost(const BooksScreen()),
);

Finder _byId(String id) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.identifier == id,
);

/// The empty hub's action buttons.
final _emptyActions = find.descendant(
  of: find.byType(EmptyState),
  matching: find.byType(WaxButton),
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

/// The hub at its own location over a playback container, for the tests
/// that ask where a press left the listener and what it started.
Future<ProviderContainer> _pumpPlaying(
  WidgetTester tester,
  FakeRepository repo, {
  FakeEngine? engine,
}) async {
  final container = playbackContainer(
    repo: repo,
    engine: engine ?? FakeEngine(),
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: routedHost(const BooksScreen(), at: WaxRoute.books),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Where the app's router stands, whichever screen it shows.
String _routerPath(WidgetTester tester) =>
    (tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig!
            as GoRouter)
        .routerDelegate
        .currentConfiguration
        .uri
        .path;

/// [book] started the way its cover starts it.
void _start(ProviderContainer container, ItemSummary book) =>
    PlayerHarness(container).play(
      [book],
      source: QueueSource(
        kind: QueueSourceKind.book,
        label: book.title,
        pid: book.pid,
      ),
    );

void main() {
  testWidgets('a refresh redraws the books it already has', (tester) async {
    // Through the shared face, which decides from the value rather than
    // from the state's runtime type: a reload carries what it had, and
    // the three empty arms are told apart inside the empty face.
    final repo = _repo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();
    expect(find.byType(AsyncSliverFace<BooksState>), findsOneWidget);
    final before = _order(tester);
    expect(before, isNotEmpty);

    final gate = Completer<void>();
    repo.listItemsGate = gate;
    ProviderScope.containerOf(
      tester.element(find.byType(WaxScaffold).first),
    ).invalidate(booksProvider);
    await tester.pump();
    await tester.pump();

    expect(_order(tester), before);
    gate.complete();
    repo.listItemsGate = null;
    await tester.pumpAndSettle();
  });

  testWidgets('an uploader gets the add every other hub has', (tester) async {
    final repo = _repo()
      ..sessionState = const SessionState(
        authenticated: true,
        user: WaxDeckUser(
          id: 'us-01JZX5N8QW3F4V9T2B7KDUPLOAD',
          username: 'uploader',
          roles: <String>['member'],
          uploadEnabled: true,
        ),
      );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(_byId(SemanticsIds.booksAdd), findsOneWidget);
    await _tap(tester, SemanticsIds.booksAdd);
    expect(_byId(SemanticsIds.addFromUrl), findsOneWidget);
  });

  testWidgets('a listener without the upload right gets no add', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_repo()..sessionState = testListenerSession()),
    );
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.booksAdd), findsNothing);
  });

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

  group('the ways in', () {
    FakeRepository seeded() => _repo()
      ..facets['artist|kind|book'] = const <FacetBucket>[
        FacetBucket(
          key: 'k-baggins',
          label: 'B. Baggins',
          count: 2,
          entityPid: 'ar-1',
        ),
        FacetBucket(
          key: 'k-herbert',
          label: 'F. Herbert',
          count: 1,
          entityPid: 'ar-2',
        ),
      ]
      ..facets['genre|kind|book'] = const <FacetBucket>[
        FacetBucket(key: 'g-fantasy', label: 'Fantasy', count: 3),
      ]
      ..bookSeries.addAll(const <BookSeries>[
        BookSeries(pid: 'sr-1', name: 'Harbour'),
        BookSeries(pid: 'sr-2', name: 'Tide'),
        BookSeries(pid: 'sr-3', name: 'Shore'),
      ]);

    Finder tileText(String name, String text) => find.descendant(
      of: _byId(SemanticsIds.bookTile(name)),
      matching: find.text(text),
    );

    testWidgets('Authors, Genres and Series lead the hub, counted', (
      tester,
    ) async {
      final repo = seeded();
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      expect(tileText('authors', 'Authors'), findsOneWidget);
      expect(tileText('authors', '2'), findsOneWidget);
      expect(tileText('genres', 'Genres'), findsOneWidget);
      expect(tileText('genres', '1'), findsOneWidget);
      expect(tileText('series', 'Series'), findsOneWidget);
      expect(tileText('series', '3'), findsOneWidget);
      // Counted over the books alone: an author's music is not theirs here.
      expect(repo.facetScopes, contains(('artist', 'kind', 'book')));
      expect(repo.facetScopes, contains(('genre', 'kind', 'book')));
      expect(
        tester.getTopLeft(_byId(SemanticsIds.bookTile('authors'))).dy,
        lessThan(
          tester.getTopLeft(_byId(SemanticsIds.bookSeriesCard('sr-1'))).dy,
        ),
        reason: 'over the shelves',
      );
      expect(
        tester.getTopLeft(find.text('All books')).dy,
        lessThan(tester.getTopLeft(_byId(SemanticsIds.book(_hobbit))).dy),
        reason: 'the grid is headed as the whole shelf',
      );
    });

    test('a dimension is titled by its name in every language', () {
      for (final locale in const <Locale>[Locale('en'), Locale('es')]) {
        final l10n = lookupAppLocalizations(locale);
        final fallback = l10n.booksDimensionTitle('');
        for (final dimension in BookDimension.values) {
          expect(
            dimension.titleOf(l10n),
            isNot(fallback),
            reason: '$locale ${dimension.name}',
          );
        }
      }
    });

    testWidgets('a tile and the index it opens share one title', (
      tester,
    ) async {
      for (final dimension in BookDimension.values) {
        await tester.pumpWidget(_host(seeded()));
        await tester.pumpAndSettle();
        final label = tester
            .widgetList<Text>(
              find.descendant(
                of: _byId(SemanticsIds.bookTile(dimension.segment)),
                matching: find.byType(Text),
              ),
            )
            .first
            .data!;

        await _tap(tester, SemanticsIds.bookTile(dimension.segment));
        expect(find.byType(MusicIndexScreen), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(MusicIndexScreen),
            matching: find.text(label),
          ),
          findsWidgets,
          reason: dimension.name,
        );
      }
    });

    testWidgets('a series on the hub\'s shelf opens over the hub', (
      tester,
    ) async {
      await tester.pumpWidget(_host(seeded()));
      await tester.pumpAndSettle();

      await _tap(tester, SemanticsIds.bookSeriesCard('sr-1'));
      expect(find.byType(BookSeriesScreen), findsOneWidget);
      // Pushed: the series page's declared parent is the series index, so
      // going there would put the index under it and lose the hub.
      GoRouter.of(tester.element(find.byType(BookSeriesScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(BooksScreen), findsOneWidget);
      expect(find.byType(BookSeriesIndexScreen), findsNothing);
    });

    testWidgets('the series count is one page, never the whole list', (
      tester,
    ) async {
      final repo = _repo()
        ..bookSeries.addAll(<BookSeries>[
          for (var i = 0; i < 501; i++)
            BookSeries(pid: 'sr-$i', name: 'Series $i'),
        ]);
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      // A page that reports more reads as a floor, as the music tiles do.
      expect(tileText('series', '500+'), findsOneWidget);
      // The shelf's first page and the count's: nothing follows a cursor.
      expect(repo.bookSeriesReads, hasLength(2));
      expect(repo.bookSeriesReads.map((r) => r.cursor), everyElement(isNull));
    });

    for (final (name, location, screen, row)
        in <(String, String, Type, String)>[
          (
            'authors',
            WaxRoute.bookIndex(BookDimension.authors),
            MusicIndexScreen,
            'B. Baggins',
          ),
          (
            'genres',
            WaxRoute.bookIndex(BookDimension.genres),
            MusicIndexScreen,
            'Fantasy',
          ),
          (
            'series',
            WaxRoute.bookSeriesIndex,
            BookSeriesIndexScreen,
            'Harbour',
          ),
        ]) {
      testWidgets('the $name tile goes to its index', (tester) async {
        await tester.pumpWidget(_host(seeded()));
        await tester.pumpAndSettle();

        await _tap(tester, SemanticsIds.bookTile(name));
        expect(find.byType(screen), findsOneWidget);
        expect(_routerPath(tester), location);
        // The index's own rows, read under the books scope the seed sits in.
        expect(find.text(row), findsOneWidget);
      });
    }

    testWidgets('a compact hub draws them as tiles too', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(seeded()));
      await tester.pumpAndSettle();

      expect(tileText('authors', '2'), findsOneWidget);
      await _tap(tester, SemanticsIds.bookTile('genres'));
      expect(_routerPath(tester), WaxRoute.bookIndex(BookDimension.genres));
    });
  });

  testWidgets('reads past a first page the listing emptied', (tester) async {
    // Rows dropped after the page is cut, which the listing contract
    // allows: a whole first page of them reads as no books at all.
    final hidden = <ItemSummary>[
      for (var i = 0; i < BooksController.pageSize; i++)
        _book(_volume(i), title: 'Volume $i'),
    ];
    final repo = FakeRepository(
      items: <ItemSummary>[
        ...hidden,
        _book(_hobbit, title: 'There And Back Again', author: 'B. Baggins'),
      ],
    )..hiddenFromListings.addAll(hidden.map((book) => book.pid));
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(find.text('No audiobooks yet'), findsNothing);
    expect(_byId(SemanticsIds.book(_hobbit)), findsOneWidget);
  });

  testWidgets('reads on past more hidden pages than a probe would', (
    tester,
  ) async {
    // Six pages of rows this caller is not shown are no proof the hub is
    // empty: the listing goes on, so the hub reads on rather than say
    // there are no audiobooks.
    final hidden = <ItemSummary>[
      for (var i = 0; i < 6 * BooksController.pageSize; i++)
        _book(_volume(i), title: 'Volume $i'),
    ];
    final repo = FakeRepository(
      items: <ItemSummary>[
        ...hidden,
        _book(_hobbit, title: 'There And Back Again', author: 'B. Baggins'),
      ],
    )..hiddenFromListings.addAll(hidden.map((book) => book.pid));
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(find.text('No audiobooks yet'), findsNothing);
    expect(_byId(SemanticsIds.book(_hobbit)), findsOneWidget);
  });

  test('loading more reads past later pages the listing emptied, however '
      'many', () async {
    // The grid asks for more as it scrolls; a page that came back empty
    // adds nothing to scroll, so nothing would ever ask again. Seven
    // empty pages, past any budget a probe keeps.
    final shown = <ItemSummary>[
      for (var i = 0; i < BooksController.pageSize; i++)
        _book(_volume(i), title: 'Volume $i'),
    ];
    final hidden = <ItemSummary>[
      for (var i = 0; i < 7 * BooksController.pageSize; i++)
        _book(_volume(BooksController.pageSize + i), title: 'Hidden $i'),
    ];
    final repo = FakeRepository(
      items: <ItemSummary>[
        ...shown,
        ...hidden,
        _book(_hobbit, title: 'There And Back Again'),
      ],
    )..hiddenFromListings.addAll(hidden.map((book) => book.pid));
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final opened = await container.read(booksProvider.future);
    expect(opened.books, hasLength(BooksController.pageSize));
    expect(opened.hasMore, isTrue);

    await container.read(booksProvider.notifier).loadMore();
    final more = container.read(booksProvider).value!;
    expect(more.books.last.pid, _hobbit);
    expect(more.hasMore, isFalse);
  });

  test('a short first page is shown as it is, its cursor kept', () {
    // Read on to a quota, a page failing further in threw away the books
    // in hand, and a run of short pages walked the listing. The hub asks
    // for more as it needs, a grid too short to scroll included.
    const first = 'bk-01JZX5N8QW3F4V9T2B7KDFIRST1';
    final hidden = <ItemSummary>[
      for (var i = 0; i < BooksController.pageSize - 1; i++)
        _book(_volume(i), title: 'Volume $i'),
    ];
    final repo = FakeRepository(
      items: <ItemSummary>[
        _book(first, title: 'Another Book'),
        ...hidden,
        _book(_hobbit, title: 'There And Back Again'),
      ],
    )..hiddenFromListings.addAll(hidden.map((book) => book.pid));
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    return container.read(booksProvider.future).then((opened) {
      expect(opened.books.map((b) => b.pid), <String>[first]);
      expect(opened.hasMore, isTrue);
      expect(repo.listItemsCalls, hasLength(1));
    });
  });

  testWidgets('a hub too short to scroll pages on by itself', (tester) async {
    final hidden = <ItemSummary>[
      for (var i = 0; i < BooksController.pageSize - 1; i++)
        _book(_volume(i), title: 'Volume $i'),
    ];
    final repo = FakeRepository(
      items: <ItemSummary>[
        _book('bk-01JZX5N8QW3F4V9T2B7KDFIRST1', title: 'Another Book'),
        ...hidden,
        _book(_hobbit, title: 'There And Back Again'),
      ],
    )..hiddenFromListings.addAll(hidden.map((book) => book.pid));
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(_byId(SemanticsIds.book(_hobbit)), findsOneWidget);
  });

  test('a rebuilt hub ends the walk its old build started', () async {
    // Pages the listing emptied, one after another: the build a sign-in
    // swap or a refresh replaced went on asking for every one of them.
    final hidden = <ItemSummary>[
      for (var i = 0; i < 6 * BooksController.pageSize; i++)
        _book(_volume(i), title: 'Volume $i'),
    ];
    final repo = FakeRepository(
      items: <ItemSummary>[
        ...hidden,
        _book(_hobbit, title: 'There And Back Again'),
      ],
    )..hiddenFromListings.addAll(hidden.map((book) => book.pid));
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final gate = Completer<void>();
    repo.listItemsGate = gate;
    final keep = container.listen(booksProvider, (_, _) {});
    addTearDown(keep.close);
    await pumpEventQueue();
    expect(repo.listItemsCalls, hasLength(1));

    // The rebuild's own walk reads past the hidden pages too, so only the
    // count of reads that started from the head says which walk asked.
    container.invalidate(booksProvider);
    await pumpEventQueue();
    repo.listItemsGate = null;
    gate.complete();
    await container.read(booksProvider.future);

    final fromHead = repo.listItemsCalls.where((c) => c.cursor == null);
    expect(fromHead, hasLength(2));
    expect(
      repo.listItemsCalls,
      hasLength(1 + 7),
      reason: 'the replaced walk stops; the new one reads to the end',
    );
  });

  testWidgets('an empty hub offers the upload to an uploader', (tester) async {
    final repo = FakeRepository()
      ..sessionState = const SessionState(
        authenticated: true,
        user: WaxDeckUser(
          id: 'us-01JZX5N8QW3F4V9T2B7KDUPLOAD',
          username: 'uploader',
          roles: <String>['member'],
          uploadEnabled: true,
        ),
      );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();
    expect(find.text('No audiobooks yet'), findsOneWidget);
    expect(_emptyActions, findsOneWidget);

    await tester.tap(find.text('Add audiobooks'));
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.addFromUrl), findsOneWidget);
    await _tap(tester, SemanticsIds.addFromUrl);
    final dialog = tester.widget<AcquireDialog>(find.byType(AcquireDialog));
    expect(dialog.initial, MediaType.audiobook);
    expect(dialog.kindFixed, isTrue);
  });

  testWidgets('an empty hub offers nothing to a listener', (tester) async {
    await tester.pumpWidget(
      _host(FakeRepository(sessionState: testListenerSession())),
    );
    await tester.pumpAndSettle();
    expect(find.text('No audiobooks yet'), findsOneWidget);
    expect(_emptyActions, findsNothing);
  });

  testWidgets('an administrator who can upload is offered the upload', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        FakeRepository(
          sessionState: const SessionState(
            authenticated: true,
            user: WaxDeckUser(
              id: 'us-1',
              username: 'admin',
              roles: ['admin'],
              uploadEnabled: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add audiobooks'), findsOneWidget);
    expect(_emptyActions, findsOneWidget);
  });

  testWidgets('offline, an empty hub offers nothing', (tester) async {
    // An administrator holds the right, but there is no server to hand
    // files to, and the libraries screen would need one too.
    await tester.pumpWidget(
      _host(
        FakeRepository(
          sessionState: const SessionState(
            authenticated: true,
            user: WaxDeckUser(
              id: 'us-1',
              username: 'admin',
              roles: ['admin'],
              uploadEnabled: true,
            ),
          ),
        ),
        offline: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No audiobooks yet'), findsOneWidget);
    expect(_emptyActions, findsNothing);
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

    testWidgets('a pressed Load more stays, busy, over the ghost row', (
      tester,
    ) async {
      final repo = _paged()..finishedPids.add(_volume(0));
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();
      await _tap(
        tester,
        SemanticsIds.bookFinishedFilter(BookFilter.finished.name),
      );

      repo.listItemsGate = Completer<void>();
      final button = find.widgetWithText(WaxButton, 'Load more books');
      final pressed = await pressWithKeyboard(tester, button);
      await tester.pump(const Duration(milliseconds: 400));

      // The button pressed stays, busy and with the keyboard on it, and
      // the ghost of the page stands under it.
      expect(tester.widget<WaxButton>(button).busy, isTrue);
      expect(pressed.hasFocus, isTrue);
      expect(find.byType(SkeletonShapes), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(SkeletonShapes)).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(button).dy),
      );
      // The only spinner is the busy button's own.
      expect(
        find.descendant(of: button, matching: find.byType(WaxSpinner)),
        findsOneWidget,
      );
      expect(find.byType(WaxSpinner), findsOneWidget);
      repo.listItemsGate!.complete();
      repo.listItemsGate = null;
      await tester.pumpAndSettle();
      expect(find.byType(SkeletonShapes), findsNothing);
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

    testWidgets('the fetch an empty filtered shelf offers stays, busy, while '
        'it pages', (tester) async {
      final repo = _paged();
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();
      await _tap(
        tester,
        SemanticsIds.bookFinishedFilter(BookFilter.finished.name),
      );

      repo.listItemsGate = Completer<void>();
      final button = find.widgetWithText(WaxButton, 'Load more books');
      final pressed = await pressWithKeyboard(tester, button);
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.widget<WaxButton>(button).busy, isTrue);
      expect(pressed.hasFocus, isTrue);
      repo.listItemsGate!.complete();
      repo.listItemsGate = null;
      await tester.pumpAndSettle();
    });
  });

  testWidgets('a book cover opens the item menu, which pins the book', (
    tester,
  ) async {
    final repo = _repo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await rightClick(tester, _byId(SemanticsIds.book(_hobbit)).first);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.itemMenuSheet(_hobbit)),
      findsOneWidget,
    );
    await tester.tap(find.text('Pin book to Home'));
    await tester.pumpAndSettle();
    expect(repo.prefs.pinned, <String>[_hobbit]);
  });

  testWidgets('a book cover plays the book where it was left', (tester) async {
    final repo = _repo()..playPositions[_hobbit] = 900000;
    final container = playbackContainer(repo: repo, engine: FakeEngine());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(const BooksScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // A book part way through says the cover carries on.
    await semanticsPlay(
      tester,
      _byId(SemanticsIds.book(_hobbit)),
      playId: SemanticsIds.bookPlay(_hobbit),
      label: 'Resume There And Back Again',
    );
    final queue = container.read(queueControllerProvider);
    expect(<String>[for (final e in queue.entries) e.pid], <String>[_hobbit]);
    expect(queue.source.kind, QueueSourceKind.book);
    await PlayerHarness(container).endPlayback(tester);
  });

  testWidgets('a finished book plays from its start, not its end', (
    tester,
  ) async {
    final repo = _repo()
      ..playPositions[_hobbit] = 3600000
      ..finishedPids.add(_hobbit);
    final engine = FakeEngine();
    final container = playbackContainer(repo: repo, engine: engine);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(const BooksScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await semanticsPlay(
      tester,
      _byId(SemanticsIds.book(_hobbit)),
      playId: SemanticsIds.bookPlay(_hobbit),
      label: 'Play There And Back Again',
    );
    expect(engine.loadedUrl, isNotNull);
    expect(engine.position, Duration.zero);
    await PlayerHarness(container).endPlayback(tester);
  });

  testWidgets('a book cover\'s tap still opens the book', (tester) async {
    await tester.pumpWidget(_host(_repo()));
    await tester.pumpAndSettle();

    await _tap(tester, SemanticsIds.book(_hobbit));
    expect(find.byType(BookScreen), findsOneWidget);
  });

  testWidgets('a paused current book resumes rather than restarts', (
    tester,
  ) async {
    final repo = _repo()..playPositions[_hobbit] = 900000;
    final engine = FakeEngine();
    final container = await _pumpPlaying(tester, repo, engine: engine);
    final book = repo.libraryItems.firstWhere((item) => item.pid == _hobbit);
    _start(container, book);
    await tester.pumpAndSettle();
    final playback = container.read(nowPlayingProvider.notifier);
    await playback.transportPause();
    await tester.pumpAndSettle();
    expect(engine.playing, isFalse);
    final starts = playback.startGeneration;

    await semanticsPlay(
      tester,
      _byId(SemanticsIds.book(_hobbit)),
      playId: SemanticsIds.bookPlay(_hobbit),
    );
    expect(playback.startGeneration, starts, reason: 'no new start');
    expect(engine.playing, isTrue);
    expect(_routerPath(tester), WaxRoute.books);
    await PlayerHarness(container).endPlayback(tester);
  });

  testWidgets('a finished current book starts again from its head', (
    tester,
  ) async {
    final repo = _repo()
      ..playPositions[_hobbit] = 3600000
      ..finishedPids.add(_hobbit);
    final engine = FakeEngine(mediaDuration: const Duration(hours: 1));
    final container = await _pumpPlaying(tester, repo, engine: engine);
    final book = repo.libraryItems.firstWhere((item) => item.pid == _hobbit);
    _start(container, book);
    await tester.pumpAndSettle();
    final playback = container.read(nowPlayingProvider.notifier);
    await playback.liveSession!.seek(const Duration(minutes: 5));
    await playback.transportPause();
    await tester.pumpAndSettle();
    final starts = playback.startGeneration;

    // Carried on, it would play from where its session stands.
    await semanticsPlay(
      tester,
      _byId(SemanticsIds.book(_hobbit)),
      playId: SemanticsIds.bookPlay(_hobbit),
      label: 'Play There And Back Again',
    );
    await tester.pumpAndSettle();
    expect(playback.startGeneration, starts + 1);
    expect(engine.position, Duration.zero);
    await PlayerHarness(container).endPlayback(tester);
  });

  testWidgets('a second press while the book loads does not start it again', (
    tester,
  ) async {
    final repo = _repo()..playPositions[_hobbit] = 900000;
    final gate = Completer<void>();
    repo.playInfoGate = gate;
    final engine = FakeEngine();
    final container = await _pumpPlaying(tester, repo, engine: engine);
    final playback = container.read(nowPlayingProvider.notifier);

    await semanticsPlay(
      tester,
      _byId(SemanticsIds.book(_hobbit)),
      playId: SemanticsIds.bookPlay(_hobbit),
    );
    expect(container.read(nowPlayingProvider).loading, isTrue);
    final starts = playback.startGeneration;
    await semanticsPlay(
      tester,
      _byId(SemanticsIds.book(_hobbit)),
      playId: SemanticsIds.bookPlay(_hobbit),
    );
    expect(playback.startGeneration, starts, reason: 'folded into the load');

    gate.complete();
    await tester.pumpAndSettle();
    expect(engine.loadedUrl, contains(_hobbit));
    expect(engine.playing, isTrue);
    await PlayerHarness(container).endPlayback(tester);
  });

  group('continue listening', () {
    testWidgets('the hub\'s continue card resumes in place', (tester) async {
      final repo = _repo()..playPositions[_hobbit] = 900000;
      final container = await _pumpPlaying(tester, repo);

      await _tap(tester, SemanticsIds.bookContinue(_hobbit));
      final queue = container.read(queueControllerProvider);
      expect(<String>[for (final e in queue.entries) e.pid], <String>[_hobbit]);
      expect(queue.source.kind, QueueSourceKind.book);
      expect(find.byType(BookScreen), findsNothing);
      expect(_routerPath(tester), WaxRoute.books);
      await PlayerHarness(container).endPlayback(tester);
    });

    testWidgets('its cover play carries on too', (tester) async {
      final repo = _repo()..playPositions[_hobbit] = 900000;
      final container = await _pumpPlaying(tester, repo);

      await semanticsPlay(
        tester,
        _byId(SemanticsIds.bookContinue(_hobbit)),
        playId: SemanticsIds.bookContinuePlay(_hobbit),
        label: 'Resume There And Back Again',
      );
      final queue = container.read(queueControllerProvider);
      expect(<String>[for (final e in queue.entries) e.pid], <String>[_hobbit]);
      expect(_routerPath(tester), WaxRoute.books);
      await PlayerHarness(container).endPlayback(tester);
    });

    testWidgets('a fresh resume reads the checkpoint, not the shelf\'s copy', (
      tester,
    ) async {
      final repo = _repo()..playPositions[_hobbit] = 900000;
      final engine = FakeEngine();
      final container = await _pumpPlaying(tester, repo, engine: engine);
      // Another device listened on after the shelf read its window.
      repo.playPositions[_hobbit] = 1500000;

      await _tap(tester, SemanticsIds.bookContinue(_hobbit));
      expect(repo.playStateReads, contains(_hobbit));
      expect(engine.position, const Duration(milliseconds: 1500000));
      await PlayerHarness(container).endPlayback(tester);
    });

    testWidgets('and rewinds it by the break, as the deck\'s Resume does', (
      tester,
    ) async {
      final repo = _repo()
        ..playPositions[_hobbit] = 900000
        ..playStateUpdatedAt[_hobbit] = DateTime.now().subtract(
          const Duration(days: 3),
        );
      final engine = FakeEngine();
      final container = await _pumpPlaying(tester, repo, engine: engine);

      await semanticsPlay(
        tester,
        _byId(SemanticsIds.bookContinue(_hobbit)),
        playId: SemanticsIds.bookContinuePlay(_hobbit),
      );
      await tester.pumpAndSettle();
      expect(engine.position, lessThan(const Duration(milliseconds: 900000)));
      await PlayerHarness(container).endPlayback(tester);
    });

    testWidgets('a book a station parked resumes through the park', (
      tester,
    ) async {
      final repo = _repo()..playPositions[_hobbit] = 900000;
      final engine = FakeEngine();
      final container = await _pumpPlaying(tester, repo, engine: engine);
      final book = repo.libraryItems.firstWhere((item) => item.pid == _hobbit);
      _start(container, book);
      await tester.pumpAndSettle();
      await container
          .read(radioPlaybackProvider.notifier)
          .play(
            RadioStation(
              pid: 'st-1',
              name: 'Prancing Pony FM',
              streamUrl: 'https://pony.example/stream',
              createdAt: DateTime.utc(2026, 7, 25),
            ),
          );
      await tester.pumpAndSettle();
      expect(container.read(parkedEntryProvider)?.entry.pid, _hobbit);
      final queued = <String>[
        for (final e in container.read(queueControllerProvider).entries)
          e.queueId,
      ];
      final starts = container
          .read(nowPlayingProvider.notifier)
          .startGeneration;

      await _tap(tester, SemanticsIds.bookContinue(_hobbit));
      // The park's own entry, not a fresh queue: a play would mint new
      // entries for the same book.
      expect(<String>[
        for (final e in container.read(queueControllerProvider).entries)
          e.queueId,
      ], queued);
      expect(
        container.read(nowPlayingProvider.notifier).startGeneration,
        starts + 1,
      );
      expect(container.read(radioPlaybackProvider).station, isNull);
      expect(engine.loadedUrl, contains(_hobbit));
      await PlayerHarness(container).endPlayback(tester);
    });

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

    testWidgets('a card on it opens the item menu, which opens the book', (
      tester,
    ) async {
      final repo = _repo()..playPositions[_hobbit] = 900000;
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      await rightClick(tester, _byId(SemanticsIds.bookContinue(_hobbit)).first);
      expect(find.text('Pin book to Home'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.itemMenuOpenBook),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BookScreen), findsOneWidget);
    });

    testWidgets('a grid card\'s menu has no Open book: its tap is that', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_repo()));
      await tester.pumpAndSettle();

      await rightClick(tester, _byId(SemanticsIds.book(_hobbit)).first);
      expect(_byId(SemanticsIds.itemMenuSheet(_hobbit)), findsOneWidget);
      expect(_byId(SemanticsIds.itemMenuOpenBook), findsNothing);
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
  });
}
