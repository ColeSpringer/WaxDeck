import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/podcasts/podcasts_controller.dart';
import 'package:waxdeck/src/podcasts/podcasts_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

Future<void> _pump(
  WidgetTester tester,
  FakeRepository repo, {
  Size size = const Size(900, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        audioEngineProvider.overrideWithValue(FakeEngine()),
      ],
      child: routedHost(const PodcastsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the add dialog's expert path: pasting a feed URL is a
/// disclosure under the name search now, not the first thing asked.
Future<void> _openUrlPath(WidgetTester tester) async {
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.podcastAddByUrl));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists the caller subscriptions', (tester) async {
    final repo = FakeRepository()
      ..addSubscription(testShow('pc-A', title: 'Alpha Show'))
      ..addSubscription(
        testShow('pc-B', title: 'Bravo Show', author: 'Rosie Cotton'),
      );
    await _pump(tester, repo);

    expect(find.text('Alpha Show'), findsOneWidget);
    expect(find.text('Rosie Cotton'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.podcast('pc-A')),
      findsOneWidget,
    );
  });

  testWidgets('a tile says what is waiting, not what exists', (tester) async {
    // The count is the show's whole unplayed backlog, which is a number
    // only the server can answer: a client counting the page it loaded
    // would claim a window was the backlog.
    final semantics = tester.ensureSemantics();
    final repo = FakeRepository()
      ..addSubscription(testShow('pc-A', title: 'Alpha Show'))
      ..unplayedCounts['pc-A'] = 4;
    await _pump(tester, repo);

    expect(find.text('4 unplayed'), findsOneWidget);
    // And announces it: the label is built with `excludeSemantics`, so a
    // count left out of it is unreadable.
    expect(
      tester
          .getSemantics(
            find.bySemanticsIdentifier(SemanticsIds.podcast('pc-A')),
          )
          .label,
      contains('4 unplayed'),
    );
    semantics.dispose();
  });

  testWidgets('a show with nothing waiting falls back to its size', (
    tester,
  ) async {
    // Both numbers ride the same walk on the real endpoint, so a tile
    // whose backlog is cleared still knows how big the show is.
    final repo = FakeRepository()
      ..addSubscription(testShow('pc-A', title: 'Alpha Show'))
      ..episodesByShow['pc-A'] = <EpisodeSummary>[
        testEpisode('tr-a', showPid: 'pc-A'),
        testEpisode('tr-b', showPid: 'pc-A'),
      ]
      ..unplayedCounts['pc-A'] = 0;
    await _pump(tester, repo);

    expect(find.text('2 episodes'), findsOneWidget);
  });

  testWidgets('recent sort leads with the show that published last', (
    tester,
  ) async {
    // The sort is the hub's default, and it is driven by a field the
    // subscription row only carries because the listing fills it: a row
    // without it made the default order a no-op that fell through to
    // title.
    final repo = FakeRepository()
      ..addSubscription(testShow('pc-old', title: 'Aardvark Weekly'))
      ..addSubscription(testShow('pc-new', title: 'Zebra Daily'))
      ..episodesByShow['pc-old'] = <EpisodeSummary>[
        testEpisode(
          'tr-old',
          showPid: 'pc-old',
          publishedAt: DateTime.utc(2026, 1),
        ),
      ]
      ..episodesByShow['pc-new'] = <EpisodeSummary>[
        testEpisode(
          'tr-new',
          showPid: 'pc-new',
          publishedAt: DateTime.utc(2026, 7),
        ),
      ];
    await _pump(tester, repo);

    final page = await repo.listSubscriptions();
    final sorted = sortSubscriptions(page.items, SubscriptionSort.recent);
    expect(sorted.first.show.title, 'Zebra Daily');
  });

  testWidgets('the shelves ask the podcast listing, not a discovery list', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..addSubscription(testShow('pc-A', title: 'Alpha Show'))
      ..episodesByShow['pc-A'] = <EpisodeSummary>[
        testEpisode('tr-new', showPid: 'pc-A', title: 'Brand New'),
        testEpisode('tr-half', showPid: 'pc-A', title: 'Half Heard'),
      ]
      ..playPositions['tr-half'] = 60000;
    await _pump(tester, repo);

    // One read per shelf, each for its own filter: the rows carry
    // `showPid` and `hasEnclosure`, which is what a sifted discovery
    // list could not give them.
    expect(repo.subscribedEpisodeCalls, <SubscribedEpisodes>[
      SubscribedEpisodes.inProgress,
      SubscribedEpisodes.unplayed,
    ]);
    expect(find.text('Up next'), findsOneWidget);
    expect(find.text('Half Heard'), findsWidgets);
    expect(find.text('Latest episodes'), findsOneWidget);
    expect(find.text('Brand New'), findsWidgets);

    // The two shelves overlap by definition - `unplayed` is below the
    // played threshold and `in-progress` is any saved position, so an
    // episode a third of the way in is in both - so a shelf card and a
    // list row are two controls and wear two handles. One handle would
    // make a click on it a strict-mode violation rather than a tap.
    Finder byId(String id) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.identifier == id,
    );
    // This fixture is the overlap: a third of the way in is both. So the
    // same episode is on screen twice, and each control has a handle of
    // its own rather than the two sharing one.
    expect(byId(SemanticsIds.episodeContinue('tr-half')), findsOneWidget);
    expect(byId(SemanticsIds.episode('tr-half')), findsOneWidget);
  });

  testWidgets('empty state invites a first show', (tester) async {
    await _pump(tester, FakeRepository());
    expect(find.text('No shows yet'), findsOneWidget);
    expect(find.text('Add a show'), findsOneWidget);
  });

  testWidgets('the add dialog starts from a name and subscribes to a match', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..podcastDirectoryEntries = const <PodcastDirectoryEntry>[
        PodcastDirectoryEntry(
          name: 'Pipeweed Economics',
          feedUrl: 'https://pony.example/feed.xml',
          author: 'Barliman Butterbur',
        ),
      ];
    await _pump(tester, repo);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.podcastAdd));
    await tester.pumpAndSettle();

    // The name is the primary input, and the URL field is not even
    // drawn until somebody asks for it.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.podcastSearchField),
      findsOneWidget,
    );
    expect(find.byKey(const Key('podcast-url-field')), findsNothing);

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.podcastSearchField),
      'pipeweed',
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.podcastSearchRun));
    await tester.pumpAndSettle();

    expect(repo.podcastDirectoryQueries, ['pipeweed']);
    expect(find.text('Pipeweed Economics'), findsOneWidget);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.podcastSearchSubscribe(0)),
    );
    await tester.pumpAndSettle();

    // A directory match is always an RSS feed, so no kind is sent.
    expect(repo.subscribeCalls, hasLength(1));
    expect(repo.subscribeCalls.single.url, 'https://pony.example/feed.xml');
    expect(repo.subscribeCalls.single.sourceType, isNull);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.podcastSearchField),
      findsNothing,
    );
  });

  testWidgets('a directory that will not answer opens the URL path', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..podcastDirectoryError = const WaxDeckApiException(
        code: 'internal',
        message: 'the index did not answer',
        statusCode: 502,
      );
    await _pump(tester, repo);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.podcastAdd));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.podcastSearchField),
      'pipeweed',
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.podcastSearchRun));
    await tester.pumpAndSettle();

    // Said, and opened: with no directory the feed URL is the only way
    // through, so it is not left behind a disclosure nobody would think
    // to press.
    expect(find.textContaining('Subscribe with a feed URL'), findsOneWidget);
    expect(find.byKey(const Key('podcast-url-field')), findsOneWidget);
  });

  testWidgets('the subscribe dialog flow adds a tile', (tester) async {
    final repo = FakeRepository();
    await _pump(tester, repo);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.podcastAdd));
    await tester.pumpAndSettle();
    await _openUrlPath(tester);
    await tester.enterText(
      find.byKey(const Key('podcast-url-field')),
      'https://pony.example/feed.xml',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.podcastSubscribeConfirm),
    );
    await tester.pumpAndSettle();

    expect(repo.subscribeCalls, hasLength(1));
    expect(repo.subscribeCalls.single.url, 'https://pony.example/feed.xml');
    expect(repo.subscribeCalls.single.sourceType, 'rss');
    // The dialog closed and the new subscription is on screen.
    expect(find.byKey(const Key('podcast-url-field')), findsNothing);
    expect(find.text('Subscribed Show 1'), findsOneWidget);
  });

  testWidgets('the source selector carries YouTube through', (tester) async {
    final repo = FakeRepository();
    await _pump(tester, repo);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.podcastAdd));
    await tester.pumpAndSettle();
    await _openUrlPath(tester);
    await tester.enterText(
      find.byKey(const Key('podcast-url-field')),
      'https://tube.example/@pony',
    );
    await tester.tap(find.text('YouTube'));
    await tester.pump();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.podcastSubscribeConfirm),
    );
    await tester.pumpAndSettle();

    expect(repo.subscribeCalls.single.sourceType, 'youtube');
  });

  testWidgets('a failed subscribe says why and keeps the dialog', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..subscribeError = const WaxDeckApiException(
        code: 'feed-unreachable',
        message: 'feed unreachable: connection refused',
        statusCode: 502,
      );
    await _pump(tester, repo);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.podcastAdd));
    await tester.pumpAndSettle();
    await _openUrlPath(tester);
    await tester.enterText(
      find.byKey(const Key('podcast-url-field')),
      'https://dead.example/feed.xml',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.podcastSubscribeConfirm),
    );
    await tester.pumpAndSettle();

    // The code's sentence: the server's says "connection refused",
    // which names nothing the listener typed.
    expect(
      find.text(
        "The feed's own server did not answer, or did not answer with a "
        'feed.',
      ),
      findsOneWidget,
    );
    // The dialog stays open for another attempt.
    expect(find.byKey(const Key('podcast-url-field')), findsOneWidget);
  });

  testWidgets('folders group the shows that declare one', (tester) async {
    final repo = FakeRepository()
      ..addSubscription(
        testShow('pc-A', title: 'Alpha Show'),
        settings: const SubscriptionSettings(folder: 'Mornings'),
      )
      ..addSubscription(
        testShow('pc-B', title: 'Bravo Show'),
        settings: const SubscriptionSettings(folder: 'Mornings'),
      )
      ..addSubscription(testShow('pc-C', title: 'Charlie Show'));
    await _pump(tester, repo);

    expect(find.text('Mornings'), findsOneWidget);
    // The shows filed nowhere keep a group of their own rather than
    // disappearing under a folder they are not in.
    expect(find.text('Other shows'), findsOneWidget);
    expect(find.text('Charlie Show'), findsOneWidget);

    // Collapsing hides the folder's shows and leaves the rest standing.
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.podcastFolder('Mornings')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Alpha Show'), findsNothing);
    expect(find.text('Charlie Show'), findsOneWidget);
  });

  group('sortSubscriptions', () {
    Subscription sub(String title, {DateTime? published, DateTime? added}) =>
        Subscription(
          show: PodcastShow(
            pid: 'pc-$title',
            title: title,
            sourceType: 'rss',
            lastPublishedAt: published,
          ),
          settings: const SubscriptionSettings(),
          subscribedAt: added ?? DateTime.utc(2026),
        );

    test('recent leads with the newest publication', () {
      final sorted = sortSubscriptions(<Subscription>[
        sub('Older', published: DateTime.utc(2026, 1)),
        sub('Newer', published: DateTime.utc(2026, 7)),
      ], SubscriptionSort.recent);
      expect(sorted.map((s) => s.show.title), <String>['Newer', 'Older']);
    });

    test('a show that has never published sorts last, not first', () {
      // The trap a null-tolerant comparator falls into: an unpublished
      // feed compares "less" than every date and leads the list.
      final sorted = sortSubscriptions(<Subscription>[
        sub('Silent'),
        sub('Loud', published: DateTime.utc(2026, 1)),
      ], SubscriptionSort.recent);
      expect(sorted.map((s) => s.show.title), <String>['Loud', 'Silent']);
    });

    test('title sorts case-insensitively', () {
      final sorted = sortSubscriptions(<Subscription>[
        sub('zebra'),
        sub('Apple'),
      ], SubscriptionSort.title);
      expect(sorted.map((s) => s.show.title), <String>['Apple', 'zebra']);
    });
  });

  test('groupByFolder keeps a nested path whole', () {
    // Flattening to the first segment would merge two folders the user
    // made.
    final groups = groupByFolder(<Subscription>[
      Subscription(
        show: const PodcastShow(pid: 'pc-A', title: 'A', sourceType: 'rss'),
        settings: const SubscriptionSettings(folder: 'News/Daily'),
        subscribedAt: DateTime.utc(2026),
      ),
      Subscription(
        show: const PodcastShow(pid: 'pc-B', title: 'B', sourceType: 'rss'),
        settings: const SubscriptionSettings(folder: 'News/Weekly'),
        subscribedAt: DateTime.utc(2026),
      ),
    ]);
    expect(groups.keys, containsAll(<String>['News/Daily', 'News/Weekly']));
  });
}
