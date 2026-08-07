import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/music/artist_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/search/search_controller.dart';
import 'package:waxdeck/src/search/search_screen.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

SearchResults _results({
  List<SearchHit> artists = const <SearchHit>[],
  List<SearchHit> tracks = const <SearchHit>[],
  List<SearchHit> episodes = const <SearchHit>[],
  bool truncated = false,
}) => SearchResults(
  query: 'night',
  artists: artists,
  tracks: tracks,
  episodes: episodes,
  truncated: truncated,
);

SearchHit _hit(String kind, String title, {String? pid}) =>
    SearchHit(pid: pid ?? '$kind-$title', kind: kind, title: title);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeRepository repository, {
  String initialQuery = '',

  /// Mounts the screen at the location it publishes to, so a settled query
  /// reuses this State instead of replacing the page - which is what the
  /// app does, and what a test about the filter surviving a keystroke has
  /// to reproduce.
  bool atOwnLocation = false,

  /// Riverpod retries a failed provider on a backoff of its own, which
  /// leaves a timer pending past the end of a test that is *about* the
  /// failure. Those tests turn it off so the error state holds still.
  bool retryFailures = true,
}) async {
  // Below sidebar width, which is where the screen owns a field. At and
  // above it the shell's header is the live field and the screen draws
  // none, so these cases would have nothing to type into; the pairing is
  // covered at its own width by `the sidebar's field is the only one`.
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    retry: retryFailures ? ProviderContainer.defaultRetry : (_, _) => null,
    overrides: [repositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: routedHost(
        SearchScreen(initialQuery: initialQuery),
        at: atOwnLocation ? WaxRoute.search : null,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('a chosen filter survives the next keystroke', (tester) async {
    // The address bar follows the settled query, and the screen adopts the
    // query the location arrives with - including the one it just wrote
    // itself, which reset the chips on every character typed. Picking
    // Podcasts and typing put them back to All, and picking Radio also
    // fired a library search the screen had no group left to show.
    final repository = FakeRepository()
      ..searchResults['night'] = _results(
        episodes: <SearchHit>[_hit('episode', 'Nightjar Weekly')],
      );
    final container = await _pump(tester, repository, atOwnLocation: true);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.searchFilter('podcasts')),
    );
    await tester.pumpAndSettle();
    expect(container.read(searchScopeProvider), SearchScope.podcasts);

    await tester.enterText(find.byType(TextField), 'night');
    await tester.pump(SearchQuery.debounce);
    await tester.pumpAndSettle();

    expect(container.read(searchScopeProvider), SearchScope.podcasts);
    expect(find.text('Nightjar Weekly'), findsOneWidget);
  });

  testWidgets('typing is debounced into one query', (tester) async {
    final repository = FakeRepository()
      ..searchResults['night'] = _results(
        artists: <SearchHit>[_hit('artist', 'Nightjar')],
      );
    await _pump(tester, repository);

    // Five keystrokes inside the window are one search, not five: a
    // query over a large catalog is real work, and answering prefixes
    // nobody asked about is the way to make a search field feel slow.
    for (final prefix in <String>['n', 'ni', 'nig', 'nigh', 'night']) {
      await tester.enterText(find.byType(TextField), prefix);
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pump(SearchQuery.debounce);
    await tester.pumpAndSettle();

    expect(repository.searchCalls, <String>['night']);
    expect(find.text('Nightjar'), findsOneWidget);
  });

  testWidgets('clearing empties the results without waiting', (tester) async {
    final repository = FakeRepository()
      ..searchResults['night'] = _results(
        artists: <SearchHit>[_hit('artist', 'Nightjar')],
      );
    await _pump(tester, repository, initialQuery: 'night');
    expect(find.text('Nightjar'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Clear search'));
    // No debounce wait: a quarter second of stale results after a clear
    // reads as a stuck screen.
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Nightjar'), findsNothing);
    expect(find.text('Search your library'), findsOneWidget);
  });

  testWidgets('the address bar follows the query nobody submitted', (
    tester,
  ) async {
    final repository = FakeRepository()
      ..searchResults['night'] = _results(
        artists: <SearchHit>[_hit('artist', 'Nightjar')],
      );
    await _pump(tester, repository);
    final router = GoRouter.of(tester.element(find.byType(SearchScreen)));

    await tester.enterText(find.byType(TextField), 'night');
    await tester.pump(SearchQuery.debounce);
    await tester.pumpAndSettle();

    // Results on screen and nothing in the bar is a result set that
    // cannot be shared or reloaded, which is the whole reason the query
    // is a query parameter.
    expect(find.text('Nightjar'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      WaxRoute.searchFor('night'),
    );
  });

  testWidgets('a query nobody submitted does not stack a history entry', (
    tester,
  ) async {
    final repository = FakeRepository()
      ..searchResults['nig'] = _results()
      ..searchResults['night'] = _results(
        artists: <SearchHit>[_hit('artist', 'Nightjar')],
      );
    await _pump(tester, repository);
    final router = GoRouter.of(tester.element(find.byType(SearchScreen)));
    final depth = router.routerDelegate.currentConfiguration.matches.length;

    // Two settled queries, because the typist paused in the middle. Each
    // replaces the last: back leaves search rather than walking back
    // through every prefix.
    await tester.enterText(find.byType(TextField), 'nig');
    await tester.pump(SearchQuery.debounce);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'night');
    await tester.pump(SearchQuery.debounce);
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.matches,
      hasLength(depth),
    );
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      WaxRoute.searchFor('night'),
    );
  });

  testWidgets('arriving with no query clears the one left behind', (
    tester,
  ) async {
    // The query outlives the screen, so coming back to a bare `/search`
    // after a search would otherwise show the old results under an empty
    // field.
    final repository = FakeRepository()
      ..searchResults['night'] = _results(
        artists: <SearchHit>[_hit('artist', 'Nightjar')],
      );
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    container.read(searchQueryProvider.notifier).submit('night');

    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(const SearchScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(searchQueryProvider), isEmpty);
    expect(find.text('Nightjar'), findsNothing);
  });

  testWidgets('re-entering search from itself starts over', (tester) async {
    // One click: the sidebar launcher is on screen the whole time search
    // is, and go_router keys a page by its path and path parameters, so
    // `/search` over `/search?q=night` reuses the same State and
    // initState never runs again. Left alone, the field still reads
    // "night", the results are still night's, and the bar says the
    // search is empty.
    final repository = FakeRepository()
      ..searchResults['night'] = _results(
        artists: <SearchHit>[_hit('artist', 'Nightjar')],
      );
    final container = await _pump(tester, repository, initialQuery: 'night');
    expect(find.text('Nightjar'), findsOneWidget);

    final router = GoRouter.of(tester.element(find.byType(SearchScreen)));
    router.go(WaxRoute.search);
    await tester.pumpAndSettle();

    expect(container.read(searchQueryProvider), isEmpty);
    expect(find.text('Nightjar'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('a link arrives under the filter it was shared with', (
    tester,
  ) async {
    // The scope outlives the screen the same way the query does, so
    // somebody who last picked Audiobooks would open a shared music link
    // onto "Nothing for nightjar" with a full result set behind it.
    final repository = FakeRepository()
      ..searchResults['night'] = _results(
        artists: <SearchHit>[_hit('artist', 'Nightjar')],
      );
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    container.read(searchScopeProvider.notifier).select(SearchScope.books);

    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(const SearchScreen(initialQuery: 'night')),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(searchScopeProvider), SearchScope.all);
    expect(find.text('Nightjar'), findsOneWidget);
  });

  testWidgets('a forgotten recent search does not come back', (tester) async {
    final container = await _pump(tester, FakeRepository());
    container.read(recentSearchesProvider.notifier).remember('nightjar');
    await tester.pumpAndSettle();
    expect(find.text('nightjar'), findsOneWidget);

    // Its own control beside the row, per 6.2: each recent search is
    // removable, and a menu holding one item is not the way.
    await tester.tap(find.bySemanticsLabel('Forget nightjar'));
    await tester.pumpAndSettle();

    expect(container.read(recentSearchesProvider), isEmpty);
    expect(find.text('nightjar'), findsNothing);
  });

  testWidgets('a link opens with its query already answered', (tester) async {
    final repository = FakeRepository()
      ..searchResults['night'] = _results(
        tracks: <SearchHit>[_hit('track', 'Night Drive')],
      );
    await _pump(tester, repository, initialQuery: 'night');

    // The whole reason the query is in the URL: a shared result set has
    // to answer before anybody types.
    expect(repository.searchCalls, <String>['night']);
    expect(find.text('Night Drive'), findsOneWidget);
  });

  testWidgets('a group caps its hits until it is expanded', (tester) async {
    final repository = FakeRepository()
      ..searchResults['night'] = _results(
        tracks: <SearchHit>[
          for (var i = 0; i < 8; i++) _hit('track', 'Track $i'),
        ],
      );
    await _pump(tester, repository, initialQuery: 'night');

    expect(find.byType(MediaListRow), findsNWidgets(searchGroupPreview));
    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();
    expect(find.byType(MediaListRow), findsNWidgets(8));
    expect(find.text('Show all'), findsNothing);
  });

  testWidgets('a filter chip narrows to the groups it covers', (tester) async {
    final repository = FakeRepository()
      ..searchResults['night'] = _results(
        artists: <SearchHit>[_hit('artist', 'Nightjar')],
        tracks: <SearchHit>[_hit('track', 'Night Drive')],
      );
    await _pump(tester, repository, initialQuery: 'night');
    expect(find.text('Nightjar'), findsOneWidget);

    await tester.tap(find.text('Audiobooks'));
    await tester.pumpAndSettle();

    // Not an empty screen with hits behind it: a filter that hides
    // everything says so.
    expect(find.text('Nightjar'), findsNothing);
    expect(find.textContaining('Nothing for'), findsOneWidget);
  });

  testWidgets('narrowing filters the answer rather than asking again', (
    tester,
  ) async {
    // Every library chip filters a result set already in hand. Watching the
    // whole chip re-executed the provider on each tap, refiring the
    // identical query behind a skeleton.
    final repository = FakeRepository()
      ..searchResults['night'] = _results(
        artists: <SearchHit>[_hit('artist', 'Nightjar')],
        tracks: <SearchHit>[_hit('track', 'Night Drive')],
      );
    await _pump(tester, repository, initialQuery: 'night');
    expect(repository.searchCalls, ['night']);

    for (final chip in <String>['music', 'podcasts', 'books', 'all']) {
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.searchFilter(chip)),
      );
      await tester.pumpAndSettle();
    }
    expect(repository.searchCalls, ['night']);
    expect(find.text('Nightjar'), findsOneWidget);
  });

  testWidgets('an entity hit opens its location, a track plays', (
    tester,
  ) async {
    final repository = FakeRepository()
      ..searchResults['night'] = _results(
        artists: <SearchHit>[
          _hit('artist', 'Nightjar', pid: 'ar-01JZXNIGHTJAR'),
        ],
      )
      ..facetItems['artist 01JZXNIGHTJAR'] = <ItemSummary>[
        const ItemSummary(
          pid: 'tr-1',
          mediaType: MediaType.music,
          title: 'Gullwing',
          artist: 'Nightjar',
          durationMs: 200000,
        ),
      ];
    await _pump(tester, repository, initialQuery: 'night');

    await tester.tap(find.text('Nightjar'));
    await tester.pumpAndSettle();

    // An artist is somewhere to go, and where it goes is the same
    // location the index would have sent them to: the artist's own
    // screen, which drills the same bucket behind it.
    expect(find.byType(ArtistScreen), findsOneWidget);

    // Opened over the results rather than instead of them: an artist is
    // declared under the artists index, so going there would rebuild
    // that ancestry and throw the query away. Back is the results.
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    // `contains` rather than `.last`: the artist screen also drills
    // `credit-artist` for its "appears on" shelf.
    expect(repository.facetDrills, contains(('artist', '01JZXNIGHTJAR')));
  });

  testWidgets('a capped answer says so rather than looking complete', (
    tester,
  ) async {
    final repository = FakeRepository()
      ..searchResults['night'] = _results(
        tracks: <SearchHit>[_hit('track', 'Night Drive')],
        truncated: true,
      );
    await _pump(tester, repository, initialQuery: 'night');

    expect(find.textContaining('Refine your search'), findsOneWidget);
  });

  testWidgets('an empty query offers what was searched before', (tester) async {
    final repository = FakeRepository()
      ..searchResults['night'] = _results(
        tracks: <SearchHit>[_hit('track', 'Night Drive')],
      );
    final container = await _pump(tester, repository);
    container.read(recentSearchesProvider.notifier).remember('night');
    await tester.pumpAndSettle();

    expect(find.text('night'), findsOneWidget);
    await tester.tap(find.text('night'));
    await tester.pumpAndSettle();

    expect(find.text('Night Drive'), findsOneWidget);
  });

  test('recent searches are newest first and never doubled', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final recents = container.read(recentSearchesProvider.notifier);

    recents.remember('nightjar');
    recents.remember('mogwai');
    // Case-insensitively the same query, so it moves rather than
    // appearing twice.
    recents.remember('Nightjar');
    expect(container.read(recentSearchesProvider), <String>[
      'Nightjar',
      'mogwai',
    ]);

    for (var i = 0; i < RecentSearches.limit + 5; i++) {
      recents.remember('query $i');
    }
    expect(
      container.read(recentSearchesProvider),
      hasLength(RecentSearches.limit),
    );

    recents.forget(container.read(recentSearchesProvider).first);
    expect(
      container.read(recentSearchesProvider),
      hasLength(RecentSearches.limit - 1),
    );
  });

  testWidgets('the podcasts chip lists library episodes and directory shows', (
    tester,
  ) async {
    final repository = FakeRepository()
      ..searchResults['night'] = _results(
        episodes: <SearchHit>[_hit('episode', 'Night Shift Ep. 4')],
      )
      ..podcastDirectoryEntries = <PodcastDirectoryEntry>[
        const PodcastDirectoryEntry(
          name: 'Nightjar Radio Hour',
          feedUrl: 'https://feeds.example/nightjar',
          author: 'Nightjar Media',
        ),
      ];
    await _pump(tester, repository, initialQuery: 'night');

    // The library half is not asked to make room for the directory half:
    // this chip answers from both.
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.searchFilter('podcasts')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Night Shift Ep. 4'), findsOneWidget);
    expect(find.text('Nightjar Radio Hour'), findsOneWidget);
    expect(repository.podcastDirectoryQueries, <String>['night']);

    // Subscribing takes the feed URL the match carried and asks no source
    // kind: a directory hit is always RSS.
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.podcastSearchSubscribe(0)),
    );
    await tester.pumpAndSettle();
    expect(repository.subscribeCalls, <({String url, String? sourceType})>[
      (url: 'https://feeds.example/nightjar', sourceType: null),
    ]);
  });

  testWidgets('no directory call goes out under the library chips', (
    tester,
  ) async {
    // The directory is a public service over the internet. A query typed
    // with no chip chosen must not reach it.
    final repository = FakeRepository()
      ..searchResults['night'] = _results(
        artists: <SearchHit>[_hit('artist', 'Nightjar')],
      );
    await _pump(tester, repository, initialQuery: 'night');

    for (final chip in <String>['all', 'music', 'books']) {
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.searchFilter(chip)),
      );
      await tester.pumpAndSettle();
    }
    expect(repository.podcastDirectoryQueries, isEmpty);
  });

  testWidgets('a silent podcast directory leaves the library half standing', (
    tester,
  ) async {
    // The library answered, and it holds what the listener already has.
    // Replacing that with an error page would lose the half that worked.
    final repository = FakeRepository()
      ..searchResults['night'] = _results(
        episodes: <SearchHit>[_hit('episode', 'Night Shift Ep. 4')],
      )
      ..podcastDirectoryError = WaxDeckApiException(
        statusCode: 502,
        code: 'directory-unavailable',
        message: 'the podcast directory could not be reached',
      );
    await _pump(
      tester,
      repository,
      initialQuery: 'night',
      retryFailures: false,
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.searchFilter('podcasts')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Night Shift Ep. 4'), findsOneWidget);
    expect(find.textContaining('directory did not answer'), findsOneWidget);
  });

  testWidgets('a failed library search does not take the directory with it', (
    tester,
  ) async {
    // Two servers, two questions. The directory used to be read only
    // inside the library result's data branch, so a library search that
    // failed meant the directory half was never even asked for.
    final repository = FakeRepository()
      ..searchError = const WaxDeckApiException(
        code: 'internal',
        message: 'the catalog is busy',
      )
      ..podcastDirectoryEntries = <PodcastDirectoryEntry>[
        const PodcastDirectoryEntry(
          name: 'Nightjar Radio Hour',
          feedUrl: 'https://feeds.example/nightjar',
        ),
      ];
    await _pump(
      tester,
      repository,
      initialQuery: 'night',
      retryFailures: false,
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.searchFilter('podcasts')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('the catalog is busy'), findsOneWidget);
    expect(find.text('Nightjar Radio Hour'), findsOneWidget);
    expect(repository.podcastDirectoryQueries, <String>['night']);
  });

  test('forgetting a query matches it the way remembering does', () {
    // The list holds one casing of a query because remember dedups
    // case-insensitively, so forget has to mean that one. Every caller
    // today passes a string read off the list; a screen that forgot what
    // was typed rather than what was drawn would not.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final recents = container.read(recentSearchesProvider.notifier);

    recents.remember('Nightjar');
    recents.forget('  nightjar ');
    expect(container.read(recentSearchesProvider), isEmpty);
  });
}
