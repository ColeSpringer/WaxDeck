import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/books/book_screen.dart';
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
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/sync/sync_binder.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';
import 'player_host.dart';
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
}
