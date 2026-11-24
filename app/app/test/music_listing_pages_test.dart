import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/books/book_screen.dart';
import 'package:waxdeck/src/metadata/metadata_controller.dart';
import 'package:waxdeck/src/metadata/metadata_form.dart';
import 'package:waxdeck/src/metadata/metadata_screen.dart';
import 'package:waxdeck/src/music/index_screen.dart';
import 'package:waxdeck/src/music/listing_screen.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

const _noGenre = FacetBucket(key: '', label: '', count: 2, unknown: true);

/// A library that files a track under the genre it is given, as the
/// server does: out of the unknown bucket's listing, into the genre's
/// bucket.
class _Genres extends FakeRepository {
  _Genres({super.sessionState, super.items});

  @override
  Future<MetadataEditResult> editItemMetadata(
    String pid, {
    required Map<String, String> fields,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  }) async {
    final result = await super.editItemMetadata(
      pid,
      fields: fields,
      writeBack: writeBack,
      lock: lock,
      force: force,
    );
    final genre = fields['genre'];
    if (genre == null || genre.isEmpty) return result;
    final unfiled = facetItems['genre ']!;
    facetItems['genre '] = [
      for (final item in unfiled)
        if (item.pid != pid) item,
    ];
    facets['genre'] = [
      FacetBucket(key: '01JZX$genre', label: genre, count: 1),
      FacetBucket(
        key: '',
        label: '',
        count: facetItems['genre ']!.length,
        unknown: true,
      ),
    ];
    return result;
  }
}

/// A listing page can come back empty and still carry a cursor: the
/// server drops rows the caller may not see after it cuts the page. A
/// music listing that read one page as the whole answer said "nothing
/// here" over tracks one page further on.
void main() {
  const MusicListing tracks = (
    dimension: null,
    segment: '',
    domain: BrowseDomain.music,
  );
  const page = MusicItemsController.pageSize;

  List<ItemSummary> hidden(String tag, int count) => <ItemSummary>[
    for (var i = 0; i < count; i++) testItem('tr-$tag-$i'),
  ];

  ProviderContainer containerOver(FakeRepository repo) {
    final container = appContainer(repo: repo);
    final keep = container.listen(musicItemsProvider(tracks), (_, _) {});
    addTearDown(keep.close);
    return container;
  }

  test('a first page the listing emptied is read past', () async {
    final unseen = hidden('unseen', page);
    final repo = FakeRepository(items: [...unseen, testItem('tr-shown')])
      ..hiddenFromListings.addAll(unseen.map((i) => i.pid));
    final container = containerOver(repo);

    final first = await container.read(musicItemsProvider(tracks).future);
    expect(first.items.map((i) => i.pid), <String>['tr-shown']);
  });

  test('loading more reads past later empty pages, however many', () async {
    // Seven, past any budget a probe keeps.
    final unseen = hidden('unseen', 7 * page);
    final repo = FakeRepository(
      items: [...hidden('seen', page), ...unseen, testItem('tr-last')],
    )..hiddenFromListings.addAll(unseen.map((i) => i.pid));
    final container = containerOver(repo);

    await container.read(musicItemsProvider(tracks).future);
    await container.read(musicItemsProvider(tracks).notifier).loadMore();
    final state = container.read(musicItemsProvider(tracks)).value!;
    expect(state.items.last.pid, 'tr-last');
    expect(state.hasMore, isFalse);
  });

  test('leaving a listing while a page is loading is no error', () async {
    // Empty pages behind the one in flight, so the walk asks again after
    // the listing has gone.
    final unseen = hidden('unseen', 2 * page);
    final repo = FakeRepository(
      items: [...hidden('seen', page), ...unseen, testItem('tr-last')],
    )..hiddenFromListings.addAll(unseen.map((i) => i.pid));
    final container = appContainer(repo: repo);
    final keep = container.listen(musicItemsProvider(tracks), (_, _) {});
    await container.read(musicItemsProvider(tracks).future);
    final controller = container.read(musicItemsProvider(tracks).notifier);
    final gate = Completer<void>();
    repo.listItemsGate = gate;
    final more = controller.loadMore();

    keep.close();
    await pumpEventQueue();
    repo.listItemsGate = null;
    gate.complete();
    await expectLater(more, completes);
  });

  test('a short first page is shown as it is, its cursor kept', () async {
    // Read on to a quota, a page failing further in threw away the rows
    // in hand, and a run of short pages walked the listing. The screen
    // asks for more as it needs, a list too short to scroll included.
    final unseen = hidden('unseen', page - 1);
    final repo = FakeRepository(
      items: [testItem('tr-first'), ...unseen, testItem('tr-second')],
    )..hiddenFromListings.addAll(unseen.map((i) => i.pid));
    final container = containerOver(repo);

    final first = await container.read(musicItemsProvider(tracks).future);
    expect(first.items.map((i) => i.pid), <String>['tr-first']);
    expect(first.hasMore, isTrue);
    expect(repo.listItemsCalls, hasLength(1));
  });

  test('leaving a listing ends its first walk', () async {
    // Pages the listing emptied, one after another: a walk that outlived
    // the listing went on asking for every one of them.
    final unseen = hidden('unseen', 6 * page);
    final repo = FakeRepository(items: [...unseen, testItem('tr-last')])
      ..hiddenFromListings.addAll(unseen.map((i) => i.pid));
    final container = appContainer(repo: repo);
    final gate = Completer<void>();
    repo.listItemsGate = gate;
    final keep = container.listen(musicItemsProvider(tracks), (_, _) {});
    await pumpEventQueue();
    expect(repo.listItemsCalls, hasLength(1));

    keep.close();
    await pumpEventQueue();
    repo.listItemsGate = null;
    gate.complete();
    await pumpEventQueue();

    expect(repo.listItemsCalls, hasLength(1), reason: 'nobody is reading');
  });

  testWidgets('a track given a genre leaves the no-genre listing under its '
      'editor, and the genre index under that follows', (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const edited = 'tr-01JZX5N8QW3F4V9T2B7KDGENRE1';
    final unfiled = [
      testItem(edited, title: 'Unfiled One'),
      testItem('tr-01JZX5N8QW3F4V9T2B7KDGENRE2', title: 'Unfiled Two'),
    ];
    final repo =
        _Genres(
            sessionState: const SessionState(
              authenticated: true,
              user: WaxDeckUser(
                id: 'us-1',
                username: 'admin',
                roles: ['admin'],
              ),
            ),
            items: unfiled,
          )
          ..facets['genre'] = [_noGenre]
          ..facetItems['genre '] = unfiled;
    final container = await pumpApp(
      tester,
      const Scaffold(),
      container: appContainer(repo: repo),
    );
    final router = GoRouter.of(tester.element(find.byType(Scaffold)))
      ..go(WaxRoute.musicBucket(MusicDimension.genres, musicUnknownSegment));
    await tester.pumpAndSettle();
    expect(find.byType(MusicListingScreen), findsOneWidget);
    expect(find.byType(MusicIndexScreen, skipOffstage: false), findsOneWidget);
    expect(find.text('Unfiled One'), findsOneWidget);

    unawaited(router.push<void>(WaxRoute.metadata(edited)));
    await tester.pumpAndSettle();
    expect(find.byType(MetadataScreen), findsOneWidget);
    Iterable<ListItemsCall> listingReads() => repo.listItemsCalls.where(
      (call) => call.facet == 'genre' && call.facetKey == '' && call.limit != 1,
    );
    int indexReads() =>
        repo.facetReads.where((read) => read.dimension == 'genre').length;
    final listedBefore = listingReads().length;
    final indexedBefore = indexReads();

    final outcome = await container
        .read(metadataControllerProvider(edited).notifier)
        .saveAll(
          const MetadataChanges(fields: {'genre': 'Drone'}),
          writeBack: false,
          lock: true,
          force: false,
        );
    expect(outcome.refusal, isNull);
    await tester.pumpAndSettle();

    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(MusicListingScreen), findsOneWidget);
    expect(find.text('Unfiled One'), findsNothing);
    expect(find.text('Unfiled Two'), findsOneWidget);
    expect(listingReads(), hasLength(listedBefore + 1));

    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(MusicIndexScreen), findsOneWidget);
    expect(indexReads(), indexedBefore + 1);
    expect(find.text('Drone'), findsOneWidget);
  });

  group('a whole-library listing holding every kind', () {
    // Reached from an album's genre chip, search or a metadata pane: the
    // bucket lists whatever carries its genre, so the queue a play cuts
    // from it is what decides the kind.
    Future<ProviderContainer> pumpMixed(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = FakeRepository()
        ..facetItems['genre ge-1'] = <ItemSummary>[
          testItem('tr-alpha', title: 'Alpha'),
          testItem('bk-1', mediaType: MediaType.audiobook, title: 'A Book'),
          testItem('ep-1', mediaType: MediaType.podcast, title: 'An Episode'),
          testItem('tr-bravo', title: 'Bravo'),
        ];
      return pumpApp(
        tester,
        const MusicListingScreen(
          dimension: MusicDimension.genres,
          segment: 'ge-1',
          domain: BrowseDomain.wholeLibrary,
        ),
        container: appContainer(repo: repo),
      );
    }

    Future<void> stop(WidgetTester tester, ProviderContainer container) async {
      container.read(queueControllerProvider.notifier).clear();
      await tester.pumpAndSettle();
    }

    testWidgets('a row tap queues the tapped kind, from the tapped row', (
      tester,
    ) async {
      final container = await pumpMixed(tester);

      await tester.tap(find.text('Bravo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final queue = container.read(queueControllerProvider);
      expect(queue.pids, <String>['tr-alpha', 'tr-bravo']);
      expect(queue.currentPid, 'tr-bravo');
      // Scoped to what it plays, so a draw asks for music; the unscoped
      // cursor names another scope and is left behind.
      expect(queue.source.mediaType, MediaType.music);
      expect(queue.source.cursor, isEmpty);
      await stop(tester, container);
    });

    testWidgets('Shuffle queues music alone', (tester) async {
      final container = await pumpMixed(tester);

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.listingShuffle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final queue = container.read(queueControllerProvider);
      expect(queue.pids.toSet(), <String>{'tr-alpha', 'tr-bravo'});
      expect(queue.source.mediaType, MediaType.music);
      await stop(tester, container);
    });

    testWidgets('a book row still opens its book', (tester) async {
      final container = await pumpMixed(tester);

      await tester.tap(find.text('A Book'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(BookScreen), findsOneWidget);
      expect(container.read(queueControllerProvider).isEmpty, isTrue);
    });
  });

  test('reading a listing through does not stop at an empty page', () async {
    final unseen = hidden('unseen', page);
    final repo = FakeRepository(
      items: [...hidden('seen', page), ...unseen, testItem('tr-last')],
    )..hiddenFromListings.addAll(unseen.map((i) => i.pid));
    final container = containerOver(repo);

    await container.read(musicItemsProvider(tracks).future);
    final all = await container
        .read(musicItemsProvider(tracks).notifier)
        .readThrough(atMost: 3 * page);
    expect(all.last.pid, 'tr-last');
  });
}
