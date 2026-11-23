import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/books/book_screen.dart';
import 'package:waxdeck/src/books/books_screen.dart';
import 'package:waxdeck/src/books/series_controller.dart';
import 'package:waxdeck/src/books/series_merge.dart';
import 'package:waxdeck/src/l10n/l10n.dart';
import 'package:waxdeck/src/library/item_kind.dart';
import 'package:waxdeck/src/music/album_screen.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/player/now_playing_slot.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_item.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck/src/shell/adaptive_shell.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck/src/sync/sync_binder.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck/src/tools/tasks_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';
import 'player_host.dart';
import 'router_stack.dart';
import 'wax_finders.dart';

const _a = 'tr-01JZX5N8QW3F4V9T2B7KDKINDA1';
const _b = 'tr-01JZX5N8QW3F4V9T2B7KDKINDB2';
const _c = 'tr-01JZX5N8QW3F4V9T2B7KDKINDC3';
const _job = 'jb-01JZX5N8QW3F4V9T2B7KDKIND00';

const _admin = WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']);

/// A screen whose one button starts the kind change.
class _Starter extends StatelessWidget {
  const _Starter({required this.pids, required this.to});

  final List<String> pids;
  final String to;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: WaxButton(
        label: 'Start',
        onPressed: () => confirmSetKind(context, pids: pids, to: to),
      ),
    ),
  );
}

FakeRepository _repo({bool admin = true}) => FakeRepository(
  sessionState: SessionState(
    authenticated: true,
    user: admin
        ? _admin
        : const WaxDeckUser(id: 'us-2', username: 'sam', roles: ['user']),
  ),
);

Future<PlayerHarness> _pump(
  WidgetTester tester,
  FakeRepository repo, {
  required List<String> pids,
  required String to,
  FakeEngine? engine,
  SyncEngine? sync,
}) async {
  final downloads = sync == null ? null : FakeDownloads();
  if (downloads != null) addTearDown(downloads.dispose);
  final container = playbackContainer(
    repo: repo,
    engine: engine ?? FakeEngine(),
    extra: [
      if (sync != null) ...[
        mirrorDatabaseProvider.overrideWithValue(sync.db),
        downloadManagerProvider.overrideWithValue(downloads!),
        syncEngineProvider.overrideWithValue(sync),
      ],
    ],
  );
  // Signed in, as the app is wherever a kind change is offered.
  await tester.runAsync(() => container.read(authControllerProvider.future));
  await pumpApp(
    tester,
    _Starter(pids: pids, to: to),
    container: container,
  );
  return PlayerHarness(container);
}

/// Confirms the dialog and lets every poll it makes run.
Future<void> _confirm(WidgetTester tester, {int polls = 1}) async {
  await tester.tap(find.text('Start'));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.kindConfirm));
  await tester.pump();
  for (var i = 0; i < polls; i++) {
    await tester.pump(kindChangePoll);
  }
  await tester.pumpAndSettle();
}

/// The whole app at desktop width over [repo], where back and the tabs
/// walk the history.
Future<ProviderContainer> _pumpWhole(WidgetTester tester, FakeRepository repo) {
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return pumpWholeApp(
    tester,
    container: appContainer(repo: repo),
    disableAnimations: true,
  );
}

String _locationOf(ProviderContainer container) =>
    container.read(routerProvider).routerDelegate.currentConfiguration.uri.path;

Future<void> _goTo(
  WidgetTester tester,
  ProviderContainer container,
  String location,
) async {
  container.read(routerProvider).go(location);
  await tester.pumpAndSettle();
}

/// Asks for the change from the screen [on] finds, as its menu does, and
/// confirms it.
Future<void> _startFrom(
  WidgetTester tester,
  Finder on, {
  required List<String> pids,
  required String to,
}) async {
  unawaited(confirmSetKind(tester.element(on), pids: pids, to: to));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.kindConfirm));
  await tester.pump();
}

/// A choice made on the navigation chrome.
Future<void> _tapTab(WidgetTester tester, WaxNavTarget target) async {
  await tester.tap(
    find
        .byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.identifier ==
                  SemanticsIds.navDestination(target.name),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tracks that become one book open it', (tester) async {
    await _pump(tester, _repo(), pids: [_a, _b], to: 'audiobook');
    await _confirm(tester);

    expect(
      tester.widget<BookScreen>(find.byType(BookScreen)).pid,
      'bk-${_a.substring(3)}',
    );
  });

  testWidgets('a kind change recounts the kind-scoped indexes', (tester) async {
    final repo = _repo();
    final harness = await _pump(tester, repo, pids: [_a, _b], to: 'audiobook');
    final container = harness.container;
    const count = (
      dimension: MusicDimension.artists,
      domain: BrowseDomain.music,
    );
    const index = (
      dimension: MusicDimension.artists,
      sort: FacetSort.label,
      domain: BrowseDomain.books,
    );
    final held = <ProviderSubscription<Object?>>[
      container.listen(musicIndexCountProvider(count), (_, _) {}),
      container.listen(musicIndexProvider(index), (_, _) {}),
    ];
    addTearDown(() {
      for (final subscription in held) {
        subscription.close();
      }
    });
    await tester.runAsync(() async {
      await container.read(musicIndexCountProvider(count).future);
      await container.read(musicIndexProvider(index).future);
    });
    final before = repo.facetReads.length;

    await _confirm(tester);
    await tester.runAsync(() async {
      await container.read(musicIndexCountProvider(count).future);
      await container.read(musicIndexProvider(index).future);
    });

    // An item that changed kind left one scope's buckets for the other's,
    // and the books hub it lands on counts its two tiles; nothing else.
    expect(
      repo.facetReads.sublist(before),
      unorderedEquals(<Object>[
        (dimension: 'artist', sort: null, facet: 'kind', facetKey: 'track'),
        (
          dimension: 'artist',
          sort: FacetSort.label,
          facet: 'kind',
          facetKey: 'book',
        ),
        (dimension: 'artist', sort: null, facet: 'kind', facetKey: 'book'),
        (dimension: 'genre', sort: null, facet: 'kind', facetKey: 'book'),
      ]),
    );
  });

  testWidgets('a kind change re-reads the series', (tester) async {
    const series = 'bs-01JZX5N8QW3F4V9T2B7KDKINDS1';
    final repo = _repo();
    repo.bookSeries.add(
      const BookSeries(pid: series, name: 'Tidewater', bookCount: 1),
    );
    repo.bookSeriesDetails[series] = const BookSeriesDetail(
      pid: series,
      name: 'Tidewater',
      books: <BookSeriesEntry>[],
    );
    final harness = await _pump(tester, repo, pids: [_a, _b], to: 'audiobook');
    final container = harness.container;
    Future<void> readAll() => Future.wait<Object?>([
      container.read(bookSeriesCountProvider.future),
      container.read(bookSeriesShelfProvider.future),
      container.read(bookSeriesProvider.future),
      container.read(bookSeriesDetailProvider(series).future),
    ]);
    final held = <ProviderSubscription<Object?>>[
      container.listen(bookSeriesCountProvider, (_, _) {}),
      container.listen(bookSeriesShelfProvider, (_, _) {}),
      container.listen(bookSeriesProvider, (_, _) {}),
      container.listen(bookSeriesDetailProvider(series), (_, _) {}),
    ];
    addTearDown(() {
      for (final subscription in held) {
        subscription.close();
      }
    });
    await tester.runAsync(readAll);
    final listsBefore = repo.bookSeriesReads.length;
    final detailBefore = repo.bookSeriesDetailReads.length;

    await _confirm(tester);
    await tester.runAsync(readAll);

    // A book that joins or leaves a series moves its count, the hub's
    // shelf and tile, and the index: the tile, the shelf and the index
    // each read again, and so does the open series.
    expect(repo.bookSeriesReads.length - listsBefore, 3);
    expect(repo.bookSeriesDetailReads.sublist(detailBefore), [series]);
  });

  testWidgets('a change whose job was cleared meanwhile still opens the book', (
    tester,
  ) async {
    final repo = _repo();
    await _pump(tester, repo, pids: [_a, _b], to: 'audiobook');
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.kindConfirm));
    await tester.pump();
    // Another device sweeps the finished jobs before the first poll.
    await repo.clearFinishedJobs();
    await tester.pump(kindChangePoll);
    await tester.pumpAndSettle();

    expect(
      tester.widget<BookScreen>(find.byType(BookScreen)).pid,
      'bk-${_a.substring(3)}',
    );
  });

  testWidgets('a book that becomes music opens its first part\'s album', (
    tester,
  ) async {
    const album = 'al-01JZX5N8QW3F4V9T2B7KDKINDAL';
    final repo = _repo()
      ..libraryItems.add(
        const ItemSummary(
          pid: _a,
          mediaType: MediaType.music,
          title: 'First Lecture',
          albumPid: album,
          durationMs: 60000,
        ),
      );
    await _pump(tester, repo, pids: ['bk-${_a.substring(3)}'], to: 'music');
    await _confirm(tester);

    expect(find.byType(BookScreen), findsNothing);
    expect(tester.widget<AlbumScreen>(find.byType(AlbumScreen)).pid, album);
  });

  testWidgets('a refused change says why and stays put', (tester) async {
    final repo = _repo()
      ..metadataError = const WaxDeckApiException(
        code: 'invalid-request',
        message: 'a cue track cannot change kind',
        statusCode: 400,
      );
    await _pump(tester, repo, pids: [_a], to: 'audiobook');
    await _confirm(tester);

    expect(
      shellMessageText(raisedMessage(tester)),
      'a cue track cannot change kind',
    );
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('a change that failed says why', (tester) async {
    final repo = _repo()
      ..jobs = const [
        Job(
          pid: _job,
          kind: 'set-kind',
          state: 'failed',
          error: 'a file of the item is not on disk',
        ),
      ];
    await _pump(tester, repo, pids: [_a], to: 'audiobook');
    await _confirm(tester);

    expect(
      shellMessageText(raisedMessage(tester)),
      'The change could not be made: a file of the item is not on disk',
    );
    expect(find.byType(BookScreen), findsNothing);
  });

  testWidgets('an item folded into one out of sight says so and goes nowhere', (
    tester,
  ) async {
    final repo = _repo(admin: false)
      ..jobs = [
        Job(
          pid: _job,
          kind: 'set-kind',
          state: 'done',
          result: {
            'converted': const <String>[],
            'absorbed': {_a: ''},
            'created': const <String>[],
            'writeBackFailures': const <Object>[],
          },
        ),
      ];
    await _pump(tester, repo, pids: [_a], to: 'audiobook');
    await _confirm(tester);

    expect(
      shellMessageText(raisedMessage(tester)),
      'It became part of an item in a library you cannot open.',
    );
    expect(find.byType(BookScreen), findsNothing);
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('files the change could not write are owned up to', (
    tester,
  ) async {
    final repo = _repo()
      ..jobs = [
        Job(
          pid: _job,
          kind: 'set-kind',
          state: 'done',
          result: {
            'converted': ['bk-${_a.substring(3)}'],
            'absorbed': const <String, Object?>{},
            'created': const <String>[],
            'writeBackFailures': const [
              {'path': 'a.mp3', 'reason': 'permission denied'},
            ],
          },
        ),
      ];
    await _pump(tester, repo, pids: [_a], to: 'audiobook');
    await _confirm(tester);

    expect(
      shellMessageText(raisedMessage(tester)),
      'Saved, but some files kept their old tags.',
    );
    expect(find.byType(BookScreen), findsOneWidget);
  });

  testWidgets('a lost poll reads as still running, not refused', (
    tester,
  ) async {
    final repo = _repo()
      ..getJobError = const WaxDeckApiException(
        code: 'unavailable',
        message: 'the server did not answer',
        statusCode: 503,
      );
    await _pump(tester, repo, pids: [_a], to: 'audiobook');
    await _confirm(tester);

    final message = raisedMessage(tester);
    expect(shellMessageText(message), 'Still changing. Follow it in Tasks.');
    expect(message!.actionLabel, 'Tasks');
  });

  testWidgets('a change still running after the wait points at Tasks', (
    tester,
  ) async {
    final repo = _repo()
      ..jobs = const [Job(pid: _job, kind: 'set-kind', state: 'running')];
    await _pump(tester, repo, pids: [_a], to: 'audiobook');
    await _confirm(tester, polls: kindChangePolls);

    final message = raisedMessage(tester);
    expect(shellMessageText(message), 'Still changing. Follow it in Tasks.');
    expect(message!.actionLabel, 'Tasks');
  });

  testWidgets('the Tasks action of a change still running goes to Tasks', (
    tester,
  ) async {
    final repo = _repo()
      ..jobs = const [Job(pid: _job, kind: 'set-kind', state: 'running')];
    await _pump(tester, repo, pids: [_a], to: 'audiobook');
    await _confirm(tester, polls: kindChangePolls);
    final message = raisedMessage(tester);
    expect(message?.actionSemanticsId, SemanticsIds.openTasks);

    message!.onAction!();
    // By frame: a task's bar moves for as long as Tasks draws it.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final router = routerOf(tester);
    expect(find.byType(TasksScreen), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      WaxRoute.tasks,
    );
    expect(pushesOn(router), 0, reason: 'Tasks is gone to, not pushed');
  });

  testWidgets('a state the app does not know reads as still running', (
    tester,
  ) async {
    final repo = _repo(admin: false)
      ..jobs = const [Job(pid: _job, kind: 'set-kind', state: 'settling')];
    await _pump(tester, repo, pids: [_a], to: 'audiobook');
    await _confirm(tester, polls: kindChangePolls);

    expect(
      shellMessageText(raisedMessage(tester)),
      'Running in the background',
    );
  });

  testWidgets('a folded item that was playing stops, and nothing of it stays '
      'queued', (tester) async {
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final harness = await _pump(
      tester,
      _repo(),
      pids: [_a, _b, _c],
      to: 'audiobook',
      engine: engine,
    );
    harness.play([testItem(_b), testItem(_c)]);
    await tester.pumpAndSettle();
    expect(engine.playing, isTrue);

    await _confirm(tester);

    expect(engine.playing, isFalse);
    expect(
      shellMessageText(raisedMessage(tester)),
      'Now in the book; play from here',
    );
    // An item the server no longer has is nothing to persist, nor to
    // offer back at the next launch.
    final queue = harness.container.read(queueControllerProvider);
    expect(queue.entries, isEmpty);
  });

  testWidgets('what follows a folded item that was playing waits, unplayed', (
    tester,
  ) async {
    const d = 'tr-01JZX5N8QW3F4V9T2B7KDKINDD4';
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final harness = await _pump(
      tester,
      _repo(),
      pids: [_a, _b],
      to: 'audiobook',
      engine: engine,
    );
    harness.play([testItem(_b), testItem(d)]);
    await tester.pumpAndSettle();
    expect(engine.playing, isTrue);

    await _confirm(tester);

    final queue = harness.container.read(queueControllerProvider);
    expect([for (final e in queue.entries) e.pid], [d]);
    expect(queue.currentEntry?.pid, d);
    expect(engine.playing, isFalse, reason: 'it waits rather than starting');
  });

  testWidgets('a queued track that became a book starts as one', (
    tester,
  ) async {
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final repo = _repo();
    final harness = await _pump(
      tester,
      repo,
      pids: [_a],
      to: 'audiobook',
      engine: engine,
    );
    harness.play([testItem(_c), testItem(_a)]);
    await tester.pumpAndSettle();
    // A queue row naming it, from the summary the queue was built from.
    final row = harness.container.listen(queueItemProvider(_a), (_, _) {});
    addTearDown(row.close);
    await tester.pumpAndSettle();
    expect(row.read().value?.mediaType, MediaType.music);
    // The server answers the old pid with what the item is now.
    repo.libraryItems.add(testItem(_a, mediaType: MediaType.audiobook));

    await _confirm(tester);
    expect(row.read().value?.mediaType, MediaType.audiobook);
    await harness.playback.next();
    await tester.pumpAndSettle();

    final now = harness.container.read(nowPlayingProvider);
    expect(now.entry?.pid, _a);
    expect(now.session?.item.mediaType, MediaType.audiobook);
  });

  testWidgets('a change that ends after its dialog stopped watching still '
      'starts what it converted as what it is now', (tester) async {
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final repo = _repo()
      ..libraryItems.addAll([testItem(_c), testItem(_a)])
      ..jobs = const [Job(pid: _job, kind: 'set-kind', state: 'running')];
    final db = inMemoryMirrorDatabase();
    addTearDown(db.close);
    final sync = SyncEngine(
      db: db,
      repository: repo,
      channelFactory: deadChannelFactory(),
    );
    addTearDown(sync.dispose);
    final harness = await _pump(
      tester,
      repo,
      pids: [_a],
      to: 'audiobook',
      engine: engine,
      sync: sync,
    );
    // The signed-in shell holds the session's binder, which hears the
    // catalog move.
    final binder = harness.container.listen(syncBinderProvider, (_, _) {});
    harness.play([testItem(_c), testItem(_a)]);
    await tester.pumpAndSettle();
    final row = harness.container.listen(queueItemProvider(_a), (_, _) {});
    await tester.pumpAndSettle();
    expect(row.read().value?.mediaType, MediaType.music);

    // The dialog waits its whole time and leaves the change running.
    await _confirm(tester, polls: kindChangePolls);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      shellMessageText(raisedMessage(tester)),
      'Still changing. Follow it in Tasks.',
    );

    // It ends later, unwatched: the server answers the old pid with what
    // the item is now, and the catalog moves.
    repo.libraryItems
      ..removeWhere((i) => i.pid == _a)
      ..add(testItem(_a, mediaType: MediaType.audiobook));
    await sync.pullCatalog();
    await tester.pump(kCatalogRefreshWindow);
    await tester.pumpAndSettle();

    expect(row.read().value?.mediaType, MediaType.audiobook);
    await harness.playback.next();
    await tester.pumpAndSettle();
    final now = harness.container.read(nowPlayingProvider);
    expect(now.entry?.pid, _a);
    expect(now.session?.item.mediaType, MediaType.audiobook);
    row.close();
    binder.close();
  });

  testWidgets('a change that failed part way lets go of what it folded, '
      'then says why', (tester) async {
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final repo = _repo()
      ..jobs = [
        Job(
          pid: _job,
          kind: 'set-kind',
          state: 'failed',
          error: 'a file of the item is not on disk',
          result: {
            'converted': ['bk-${_a.substring(3)}'],
            'absorbed': {'tr-${_b.substring(3)}': 'bk-${_a.substring(3)}'},
            'created': const <String>[],
            'writeBackFailures': const <Object>[],
          },
        ),
      ];
    final harness = await _pump(
      tester,
      repo,
      pids: [_a, _b, _c],
      to: 'audiobook',
      engine: engine,
    );
    harness.play([testItem(_b), testItem(_c)]);
    await tester.pumpAndSettle();
    expect(engine.playing, isTrue);

    await _confirm(tester);

    expect(engine.playing, isFalse);
    final queue = harness.container.read(queueControllerProvider);
    expect([for (final e in queue.entries) e.pid], [_c]);
    expect(
      shellMessageText(raisedMessage(tester)),
      'The change could not be made: a file of the item is not on disk',
    );
    expect(find.byType(BookScreen), findsNothing);
  });

  testWidgets('a station tuned over a folded entry plays on, unremarked', (
    tester,
  ) async {
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final repo = _repo();
    final harness = await _pump(
      tester,
      repo,
      pids: [_a, _b],
      to: 'audiobook',
      engine: engine,
    );
    harness.play([testItem(_b), testItem(_c)]);
    await tester.pumpAndSettle();
    final station = RadioStation(
      pid: 'rs-01JZX5N8QW3F4V9T2B7KDSTATN1',
      name: 'Coastal FM',
      streamUrl: 'https://stream.example/coastal',
      createdAt: DateTime.utc(2026, 7, 1),
    );
    repo.radioStationsByPid[station.pid] = station;
    // The queue keeps its entry under the station.
    await harness.container.read(radioPlaybackProvider.notifier).play(station);
    await tester.pumpAndSettle();
    expect(engine.playing, isTrue);

    await _confirm(tester);

    expect(
      harness.container.read(radioPlaybackProvider).station?.pid,
      station.pid,
    );
    expect(engine.playing, isTrue);
    expect(raisedMessage(tester), isNull);
  });

  testWidgets('a folded entry a station parked goes, and nothing starts', (
    tester,
  ) async {
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final repo = _repo();
    final harness = await _pump(
      tester,
      repo,
      pids: [_a, _b],
      to: 'audiobook',
      engine: engine,
    );
    harness.play([testItem(_b), testItem(_c)]);
    await tester.pumpAndSettle();
    final station = RadioStation(
      pid: 'rs-01JZX5N8QW3F4V9T2B7KDSTATN1',
      name: 'Coastal FM',
      streamUrl: 'https://stream.example/coastal',
      createdAt: DateTime.utc(2026, 7, 1),
    );
    repo.radioStationsByPid[station.pid] = station;
    final radio = harness.container.read(radioPlaybackProvider.notifier);
    await radio.play(station);
    await tester.pumpAndSettle();
    await radio.stop();
    await tester.pumpAndSettle();
    expect(harness.container.read(nowPlayingSlotProvider), isA<ParkedSlot>());
    final loads = engine.loadedUrls.length;

    await _confirm(tester);

    // Nothing was playing, so nothing stopped and nothing is said; what
    // follows stands where the folded entry stood, still waiting.
    final slot = harness.container.read(nowPlayingSlotProvider);
    expect(slot, isA<ParkedSlot>());
    expect((slot as ParkedSlot).parked.entry.pid, _c);
    expect(engine.loadedUrls, hasLength(loads));
    expect(engine.playing, isFalse);
    expect(raisedMessage(tester), isNull);
    final queue = harness.container.read(queueControllerProvider);
    expect([for (final e in queue.entries) e.pid], [_c]);
  });

  testWidgets('a folded entry under a station is not offered back after it', (
    tester,
  ) async {
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final repo = _repo();
    final harness = await _pump(
      tester,
      repo,
      pids: [_a, _b],
      to: 'audiobook',
      engine: engine,
    );
    harness.play([testItem(_b), testItem(_c)]);
    await tester.pumpAndSettle();
    final station = RadioStation(
      pid: 'rs-01JZX5N8QW3F4V9T2B7KDSTATN1',
      name: 'Coastal FM',
      streamUrl: 'https://stream.example/coastal',
      createdAt: DateTime.utc(2026, 7, 1),
    );
    repo.radioStationsByPid[station.pid] = station;
    final radio = harness.container.read(radioPlaybackProvider.notifier);
    await radio.play(station);
    await tester.pumpAndSettle();

    await _confirm(tester);
    await radio.stop();
    await tester.pumpAndSettle();

    final slot = harness.container.read(nowPlayingSlotProvider);
    expect(slot, isA<ParkedSlot>());
    expect((slot as ParkedSlot).parked.entry.pid, _c);
    final queue = harness.container.read(queueControllerProvider);
    expect([for (final e in queue.entries) e.pid], [_c]);
    expect(engine.playing, isFalse);
  });

  testWidgets('a dialog opened over the running change is left standing', (
    tester,
  ) async {
    final repo = _repo()
      ..jobs = const [Job(pid: _job, kind: 'set-kind', state: 'running')];
    await _pump(tester, repo, pids: [_a], to: 'audiobook');
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.kindConfirm));
    await tester.pump();
    await tester.pump(kindChangePoll);

    // Something outside the dialog opens one over it meanwhile, as a
    // shared link arriving does.
    unawaited(
      showDialog<void>(
        context: tester.element(find.text('Start')),
        builder: (_) => const AlertDialog(content: Text('A shared link')),
      ),
    );
    // Bounded pumps: the change's spinner never settles while it runs.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('A shared link'), findsOneWidget);

    repo.jobs = const [
      Job(
        pid: _job,
        kind: 'set-kind',
        state: 'failed',
        error: 'a file of the item is not on disk',
      ),
    ];
    await tester.pump(kindChangePoll);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('A shared link'), findsOneWidget);
    expect(find.text('Reading the files again'), findsNothing);
    expect(
      shellMessageText(raisedMessage(tester)),
      'The change could not be made: a file of the item is not on disk',
    );
  });

  testWidgets('a change that ends after its dialog was taken down still has '
      'the open reads read again', (tester) async {
    final repo = _repo()
      ..jobs = const [Job(pid: _job, kind: 'set-kind', state: 'running')];
    final harness = await _pump(tester, repo, pids: [_a], to: 'audiobook');
    final container = harness.container;
    const count = (
      dimension: MusicDimension.artists,
      domain: BrowseDomain.music,
    );
    final held = container.listen(musicIndexCountProvider(count), (_, _) {});
    addTearDown(held.close);
    await tester.runAsync(
      () => container.read(musicIndexCountProvider(count).future),
    );
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.kindConfirm));
    await tester.pump();
    await tester.pump(kindChangePoll);

    // Its route goes from under it, as the navigator being rebuilt for
    // an ended session takes it.
    Navigator.of(
      tester.element(find.byType(AlertDialog)),
      rootNavigator: true,
    ).pop();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    final before = repo.facetReads.length;

    repo.jobs = [
      Job(
        pid: _job,
        kind: 'set-kind',
        state: 'done',
        result: {
          'converted': ['bk-${_a.substring(3)}'],
          'absorbed': const <String, String>{},
          'created': const <String>[],
          'writeBackFailures': const <Object>[],
        },
      ),
    ];
    await tester.pump(kindChangePoll);
    await tester.pumpAndSettle();

    expect(repo.facetReads.sublist(before), [
      (dimension: 'artist', sort: null, facet: 'kind', facetKey: 'track'),
    ]);
    expect(find.byType(BookScreen), findsNothing, reason: 'nobody asked');
  });

  testWidgets('a running change keeps its dialog and its buttons', (
    tester,
  ) async {
    final repo = _repo()
      ..jobs = const [Job(pid: _job, kind: 'set-kind', state: 'running')];
    await _pump(tester, repo, pids: [_a, _b], to: 'audiobook');
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(
      infoTipContaining('rebuilt catalog'),
      findsOneWidget,
      reason: 'the write-back switch explains itself in a tip',
    );
    expect(find.textContaining('rebuilt catalog'), findsNothing);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.kindConfirm));
    await tester.pump();
    await tester.pump(kindChangePoll);

    // The button pressed stays where it was, busy, so a keyboard keeps
    // its place; the way out is drawn, unavailable while it cannot be.
    final confirm = tester.widget<WaxButton>(
      waxControl<WaxButton>(SemanticsIds.kindConfirm),
    );
    expect(confirm.busy, isTrue);
    final cancel = tester.widget<WaxButton>(
      find.widgetWithText(WaxButton, 'Cancel'),
    );
    expect(cancel.onPressed, isNull);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.kindWriteBack),
      findsOneWidget,
      reason: 'the body stays',
    );
    expect(find.text('Reading the files again'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(WaxSpinner),
      ),
      findsOneWidget,
      reason: 'the one spinner is the busy button\'s glyph',
    );
    expect(
      find.ancestor(
        of: find.byType(WaxSpinner),
        matching: find.byType(WaxButton),
      ),
      findsWidgets,
    );

    repo.jobs = const [Job(pid: _job, kind: 'set-kind', state: 'failed')];
    await tester.pump(kindChangePoll);
    await tester.pumpAndSettle();
  });

  testWidgets('back while the change runs leaves the dialog to finish it', (
    tester,
  ) async {
    final repo = _repo()
      ..jobs = const [Job(pid: _job, kind: 'set-kind', state: 'running')];
    await _pump(tester, repo, pids: [_a, _b], to: 'audiobook');
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.kindConfirm));
    await tester.pump();
    await tester.pump(kindChangePoll);

    // System back, the way the platform sends it.
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      (_) {},
    );
    await tester.pump();
    expect(find.text('Reading the files again'), findsOneWidget);

    repo.jobs = [
      Job(
        pid: _job,
        kind: 'set-kind',
        state: 'done',
        result: {
          'converted': ['bk-${_a.substring(3)}'],
          'absorbed': {'tr-${_b.substring(3)}': 'bk-${_a.substring(3)}'},
          'created': const <String>[],
          'writeBackFailures': const <Object>[],
        },
      ),
    ];
    await tester.pump(kindChangePoll);
    await tester.pumpAndSettle();
    expect(
      tester.widget<BookScreen>(find.byType(BookScreen)).pid,
      'bk-${_a.substring(3)}',
    );
  });

  test('"already music" agrees with how many were named, in Spanish', () async {
    final es = await AppLocalizations.delegate.load(const Locale('es'));
    expect(es.libraryKindAlreadyMusic(1), 'Ya es música');
    expect(es.libraryKindAlreadyMusic(3), 'Ya son música');
  });

  for (final (to, pid, sentence) in [
    ('audiobook', _a, 'Already an audiobook'),
    ('music', 'bk-${_a.substring(3)}', 'Already music'),
  ]) {
    testWidgets('a change to $to that found it already says so', (
      tester,
    ) async {
      // A view drawn before another device changed it: the server skips
      // an item already of the kind rather than refusing it.
      final repo = _repo()
        ..jobs = const [
          Job(
            pid: _job,
            kind: 'set-kind',
            state: 'done',
            result: {
              'converted': <String>[],
              'absorbed': <String, Object?>{},
              'created': <String>[],
              'writeBackFailures': <Object>[],
            },
          ),
        ];
      await _pump(tester, repo, pids: [pid], to: to);
      await _confirm(tester);

      expect(shellMessageText(raisedMessage(tester)), sentence);
      expect(find.text('Start'), findsOneWidget, reason: 'nowhere to go');
    });
  }

  group('the pages of what changed kind', () {
    final bookA = 'bk-${_a.substring(3)}';
    final bookB = 'bk-${_b.substring(3)}';

    FakeRepository shelved(List<String> books) {
      final repo = _repo();
      for (final pid in books) {
        repo
          ..books[pid] = testBook(pid)
          ..libraryItems.add(testItem(pid));
      }
      return repo;
    }

    testWidgets('give way in place to what the item became, and back does '
        'not return to them', (tester) async {
      final container = await _pumpWhole(tester, shelved([bookA]));
      await _goTo(tester, container, WaxRoute.notifications);
      await _goTo(tester, container, WaxRoute.book(bookA));

      await _startFrom(
        tester,
        find.byType(BookScreen),
        pids: [bookA],
        to: 'music',
      );
      await tester.pump(kindChangePoll);
      await tester.pumpAndSettle();
      expect(_locationOf(container), WaxRoute.musicTracks);

      container.read(waxHistoryProvider)!.back();
      await tester.pumpAndSettle();
      expect(_locationOf(container), WaxRoute.notifications);
      expect(find.byType(BookScreen), findsNothing);
    });

    testWidgets('left during the change are not brought back by back or a '
        'tab, and what it became is offered', (tester) async {
      final repo = shelved([bookA])
        ..jobs = const [Job(pid: _job, kind: 'set-kind', state: 'running')];
      final container = await _pumpWhole(tester, repo);
      await _goTo(tester, container, WaxRoute.notifications);
      await _goTo(tester, container, WaxRoute.book(bookA));

      await _startFrom(
        tester,
        find.byType(BookScreen),
        pids: [bookA],
        to: 'music',
      );
      await tester.pump(kindChangePoll);
      // A link followed while the change runs.
      container.read(routerProvider).go(WaxRoute.tasks);
      // Bounded pumps: the change's spinner never settles while it runs.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // The shell's bar takes each message off as it draws it.
      final raised = <ShellMessage>[];
      container.listen<ShellMessage?>(shellMessagesProvider, (_, next) {
        if (next != null) raised.add(next);
      });
      repo.jobs = [
        Job(
          pid: _job,
          kind: 'set-kind',
          state: 'done',
          result: {
            'converted': [_a],
            'absorbed': const <String, Object?>{},
            'created': const <String>[],
            'writeBackFailures': const <Object>[],
          },
        ),
      ];
      await tester.pump(kindChangePoll);
      await tester.pumpAndSettle();

      expect(_locationOf(container), WaxRoute.tasks);
      final offer = raised.single;
      expect(shellMessageText(offer), 'Now music, ready to open');
      expect(offer.actionLabel, 'Open');

      container.read(waxHistoryProvider)!.back();
      await tester.pumpAndSettle();
      expect(_locationOf(container), WaxRoute.notifications);
      await _tapTab(tester, WaxNavTarget.books);
      expect(_locationOf(container), WaxRoute.books);
      expect(find.byType(BooksScreen), findsOneWidget);
      expect(find.byType(BookScreen), findsNothing);
    });

    /// An album of [_a] and [_b] on the shelf, open on its own page under
    /// the Music hub, with the book its tracks become.
    Future<(ProviderContainer, String)> onAlbum(
      WidgetTester tester,
      FakeRepository repo,
    ) async {
      const album = 'al-01JZX5N8QW3F4V9T2B7KDKINDAL';
      repo
        ..albums[album] = const AlbumDetail(pid: album, title: 'Lectures')
        ..facetItems['album ${album.substring(3)}'] = [
          testItem(_a, title: 'One'),
          testItem(_b, title: 'Two'),
        ]
        ..books[bookA] = testBook(bookA);
      final container = await _pumpWhole(tester, repo);
      await _goTo(tester, container, WaxRoute.music);
      final at = WaxRoute.musicBucket(MusicDimension.albums, album);
      await _goTo(tester, container, at);
      expect(find.byType(AlbumScreen), findsOneWidget);
      // The album's own row, as its overflow offers it.
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.entityOverflow));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.itemMenuKindAlbum),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.kindConfirm));
      await tester.pump();
      return (container, at);
    }

    testWidgets('an album made one book from its page is not brought back '
        'by back or the Music tab', (tester) async {
      final (container, album) = await onAlbum(tester, _repo());
      await tester.pump(kindChangePoll);
      await tester.pumpAndSettle();
      expect(_locationOf(container), WaxRoute.book(bookA));

      await _tapTab(tester, WaxNavTarget.music);
      expect(_locationOf(container), isNot(album));
      expect(find.byType(AlbumScreen), findsNothing);
      final history = container.read(waxHistoryProvider)!;
      history.back();
      await tester.pumpAndSettle();
      history.back();
      await tester.pumpAndSettle();
      expect(_locationOf(container), WaxRoute.music);
      expect(find.byType(AlbumScreen), findsNothing);
    });

    testWidgets('an album made one book while the visitor was elsewhere is '
        'not brought back by back or the Music tab', (tester) async {
      final repo = _repo()
        ..jobs = const [Job(pid: _job, kind: 'set-kind', state: 'running')];
      final (container, album) = await onAlbum(tester, repo);
      await tester.pump(kindChangePoll);
      // A link followed while the change runs.
      container.read(routerProvider).go(WaxRoute.tasks);
      // Bounded pumps: the change's spinner never settles while it runs.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      repo.jobs = [
        Job(
          pid: _job,
          kind: 'set-kind',
          state: 'done',
          result: {
            'converted': [bookA],
            'absorbed': {_b: bookA},
            'created': const <String>[],
            'writeBackFailures': const <Object>[],
          },
        ),
      ];
      await tester.pump(kindChangePoll);
      await tester.pumpAndSettle();
      expect(_locationOf(container), WaxRoute.tasks);

      await _tapTab(tester, WaxNavTarget.music);
      expect(_locationOf(container), isNot(album));
      expect(find.byType(AlbumScreen), findsNothing);
      final history = container.read(waxHistoryProvider)!;
      history.back();
      await tester.pumpAndSettle();
      history.back();
      await tester.pumpAndSettle();
      expect(_locationOf(container), WaxRoute.music);
      expect(find.byType(AlbumScreen), findsNothing);
    });

    testWidgets('converted before the change failed are not brought back by '
        'back or a tab, and an item it did not reach keeps its page', (
      tester,
    ) async {
      final bookC = 'bk-${_c.substring(3)}';
      final repo = shelved([bookA, bookC])
        ..jobs = [
          Job(
            pid: _job,
            kind: 'set-kind',
            state: 'failed',
            error: 'a file of the item is not on disk',
            result: {
              'converted': [_a],
              'absorbed': const <String, Object?>{},
              'created': const <String>[],
              'writeBackFailures': const <Object>[],
            },
          ),
        ];
      final container = await _pumpWhole(tester, repo);
      await _goTo(tester, container, WaxRoute.book(bookC));
      await _goTo(tester, container, WaxRoute.notifications);
      await _goTo(tester, container, WaxRoute.book(bookA));

      await _startFrom(
        tester,
        find.byType(BookScreen),
        pids: [bookA, bookC],
        to: 'music',
      );
      await tester.pump(kindChangePoll);
      await tester.pumpAndSettle();
      // Failed: nowhere to go, so the visitor stays where they were.
      expect(_locationOf(container), WaxRoute.book(bookA));

      final history = container.read(waxHistoryProvider)!;
      history.back();
      await tester.pumpAndSettle();
      expect(_locationOf(container), WaxRoute.notifications);
      await _tapTab(tester, WaxNavTarget.books);
      expect(_locationOf(container), WaxRoute.books);
      expect(find.byType(BookScreen), findsNothing);

      // The book the change did not reach is still somewhere back goes.
      history.back();
      await tester.pumpAndSettle();
      history.back();
      await tester.pumpAndSettle();
      expect(_locationOf(container), WaxRoute.book(bookC));
      expect(tester.widget<BookScreen>(find.byType(BookScreen)).pid, bookC);
    });

    testWidgets("of an item folded into another leave that tab's stack", (
      tester,
    ) async {
      final container = await _pumpWhole(tester, shelved([bookA, bookB]));
      await _goTo(tester, container, WaxRoute.book(bookB));
      await _goTo(tester, container, WaxRoute.tasks);

      // Two books made music: the second folds into the first.
      await _startFrom(
        tester,
        find.byType(TasksScreen),
        pids: [bookA, bookB],
        to: 'music',
      );
      await tester.pump(kindChangePoll);
      await tester.pumpAndSettle();
      expect(_locationOf(container), WaxRoute.musicTracks);

      await _tapTab(tester, WaxNavTarget.books);
      expect(_locationOf(container), WaxRoute.books);
      expect(find.byType(BookScreen), findsNothing);
    });
  });
}
