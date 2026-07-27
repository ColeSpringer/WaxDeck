import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/autoplay_gate.dart';
import 'package:waxdeck/src/player/deck_bar_host.dart';
import 'package:waxdeck/src/playlists/add_to_playlist_dialog.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_panel.dart';
import 'package:waxdeck/src/queue/queue_persistence.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck/src/shell/side_panel.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'player_host.dart';
import 'routed_host.dart';
import 'queue_persistence_test.dart' show RecordingQueueStore;

const _album = QueueSource(
  kind: QueueSourceKind.album,
  label: 'Kind of Blue',
  pid: 'al-1',
);

/// The window's own metrics with animations off, so a bar with a VU
/// needle in it settles: the needle repeats forever while something is
/// playing, which is the point of it and the end of `pumpAndSettle`.
/// Replacing the whole [MediaQueryData] instead would wipe the size the
/// size class is read from, and every bar would draw compact.
Widget _reducedMotion(Widget child) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: child,
  ),
);

/// Mounts the deck bar the way the shell does: in a slot at the bottom
/// of the window, over the container that owns playback.
///
/// [size] picks which bar is drawn: the three-zone one needs a
/// sidebar's worth of width, and the compact one is everything below it.
Future<PlayerHarness> _pumpDeck(
  WidgetTester tester, {
  required FakeRepository repo,
  required FakeEngine engine,
  Size size = const Size(1400, 900),
  ProviderContainer? container,
  bool routed = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = PlayerHarness(
    container ?? playbackContainer(repo: repo, engine: engine),
  );
  // The gate lives with the session in the app, so it is listening
  // before the refusal it exists to catch; here the container is the
  // session.
  harness.container.read(autoplayBlockedProvider.notifier);
  const slot = Scaffold(
    body: Align(alignment: Alignment.bottomCenter, child: DeckBarHost()),
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      // Over the app's own route table where a test needs one: the bar's
      // menu reaches the router, and the player it opens is a real route.
      child: routed
          ? routedHost(_reducedMotion(slot))
          : MaterialApp(theme: buildWaxTheme(), home: _reducedMotion(slot)),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

StoredQueue _storedAlbum() => StoredQueue(
  entries: const <StoredQueueEntry>[
    StoredQueueEntry(queueId: 'q0', pid: 'tr-A', sourceRank: 0),
    StoredQueueEntry(queueId: 'q1', pid: 'tr-B', sourceRank: 1),
  ],
  currentIndex: 0,
  shuffled: false,
  repeat: 'off',
  sourceKind: 'album',
  sourceLabel: 'Kind of Blue',
  sourcePid: 'al-1',
  nextQueueId: 2,
  updatedAt: DateTime.utc(2026, 7, 26),
);

void main() {
  group('the bar', () {
    testWidgets('names what is playing and drives the transport', (
      tester,
    ) async {
      final repo = FakeRepository(items: [testItem('tr-A')]);
      final engine = FakeEngine();
      final harness = await _pumpDeck(tester, repo: repo, engine: engine);

      expect(find.byType(DeckBar), findsNothing, reason: 'nothing has played');

      harness.play([testItem('tr-A')]);
      await tester.pumpAndSettle();

      expect(find.text('Prancing Pony Blues'), findsOneWidget);
      expect(engine.playing, isTrue);

      await tester.tap(find.bySemanticsLabel('Pause'));
      await tester.pumpAndSettle();
      expect(engine.playing, isFalse);

      await harness.endPlayback(tester);
      expect(find.byType(DeckBar), findsNothing);
    });

    testWidgets('shows the modes its own controls cycle', (tester) async {
      // A toggle that never changes when pressed is indistinguishable
      // from a dead one, in greyscale and to a screen reader alike.
      final repo = FakeRepository(items: [testItem('tr-A'), testItem('tr-B')]);
      final engine = FakeEngine();
      final harness = await _pumpDeck(tester, repo: repo, engine: engine);
      harness.play([testItem('tr-A'), testItem('tr-B')], source: _album);
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Shuffle off'), findsOneWidget);
      expect(find.bySemanticsLabel('Repeat off'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Shuffle off'));
      await tester.tap(find.bySemanticsLabel('Repeat off'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Shuffle on'), findsOneWidget);
      expect(find.bySemanticsLabel('Repeat all'), findsOneWidget);
      expect(harness.container.read(queueControllerProvider).shuffled, isTrue);

      await tester.tap(find.bySemanticsLabel('Repeat all'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Repeat one'), findsOneWidget);

      await harness.endPlayback(tester);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('steps the queue from the bar', (tester) async {
      final repo = FakeRepository(items: [testItem('tr-A'), testItem('tr-B')]);
      final engine = FakeEngine();
      final harness = await _pumpDeck(tester, repo: repo, engine: engine);

      harness.play([
        testItem('tr-A', title: 'First'),
        testItem('tr-B', title: 'Second'),
      ], source: _album);
      await tester.pumpAndSettle();
      expect(find.text('First'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Second'), findsOneWidget);
      expect(harness.container.read(queueControllerProvider).currentIndex, 1);
      await harness.endPlayback(tester);
    });

    testWidgets('ticks its progress without rebuilding the bar', (
      tester,
    ) async {
      // The bar is on screen for the whole session, so a rebuild per
      // position tick is the app's most repeated frame work. Only the
      // leaf that draws the position may rebuild.
      final repo = FakeRepository(items: [testItem('tr-A')]);
      final engine = FakeEngine(mediaDuration: const Duration(minutes: 4));
      final harness = await _pumpDeck(
        tester,
        repo: repo,
        engine: engine,
        size: const Size(400, 800),
      );
      harness.play([testItem('tr-A')]);
      await tester.pumpAndSettle();

      final before = tester.widget<DeckBar>(find.byType(DeckBar));
      double progress() => tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value!;
      final wasAt = progress();

      engine.advance(const Duration(minutes: 1));
      // Twice: the position rides a stream into the notifier, and the
      // leaf listening to it rebuilds on the frame after that.
      await tester.pump();
      await tester.pump();

      expect(progress(), greaterThan(wasAt), reason: 'the hairline moved');
      expect(
        identical(tester.widget<DeckBar>(find.byType(DeckBar)), before),
        isTrue,
        reason: 'the bar itself did not rebuild',
      );
      await harness.endPlayback(tester);
    });

    testWidgets('says so when the browser refuses to resume', (tester) async {
      final repo = FakeRepository(items: [testItem('tr-A')]);
      final engine = FakeEngine()..refuseNextPlay = true;
      final harness = await _pumpDeck(tester, repo: repo, engine: engine);

      harness.play([testItem('tr-A')]);
      await tester.pumpAndSettle();

      expect(engine.playing, isFalse);
      expect(find.bySemanticsLabel('Tap to resume'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Tap to resume'));
      await tester.pumpAndSettle();

      expect(engine.playing, isTrue, reason: 'the tap is the gesture');
      expect(find.bySemanticsLabel('Pause'), findsOneWidget);
      await harness.endPlayback(tester);
    });

    testWidgets('does not restart a start that is still loading', (
      tester,
    ) async {
      // The bar's play button is live while an entry is loading, because
      // an entry with no session is also what an engine hand-over leaves
      // behind. Pressing it there used to begin a second start: the
      // first was superseded mid-load, its stream token and listen
      // session re-minted, and the position it was asked for dropped.
      final repo = FakeRepository(items: [testItem('tr-A')]);
      final engine = FakeEngine(mediaDuration: const Duration(minutes: 5));
      final harness = await _pumpDeck(tester, repo: repo, engine: engine);
      final gate = repo.playInfoGate = Completer<void>();

      harness.playback.play(
        [testItem('tr-A')],
        source: playedAlone(testItem('tr-A')),
        positionMs: 90000,
      );
      await tester.pump();
      final generation = harness.playback.startGeneration;

      await tester.tap(find.bySemanticsLabel('Play'));
      await tester.pumpAndSettle();
      expect(
        harness.playback.startGeneration,
        generation,
        reason: 'the load in flight is the one that finishes',
      );

      gate.complete();
      await tester.pumpAndSettle();
      expect(engine.position, const Duration(seconds: 90));
      await harness.endPlayback(tester);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('follows live radio onto the station', (tester) async {
      final repo = FakeRepository(items: [testItem('tr-A')]);
      final station = RadioStation(
        pid: 'ra-1',
        name: 'Coastal FM',
        streamUrl: 'https://radio.example/stream',
        createdAt: DateTime.utc(2026, 7, 1),
      );
      repo.radioStationsByPid[station.pid] = station;
      final engine = FakeEngine();
      final harness = await _pumpDeck(tester, repo: repo, engine: engine);
      harness.play([testItem('tr-A')]);
      await tester.pumpAndSettle();

      await harness.container
          .read(radioPlaybackProvider.notifier)
          .play(station);
      await tester.pumpAndSettle();

      expect(find.text('Coastal FM'), findsOneWidget);
      // A live stream has no pause that means anything, and no seek bar
      // to pretend it has a position.
      expect(find.bySemanticsLabel('Stop'), findsOneWidget);
      expect(find.byType(WaxSeekBar), findsNothing);

      // Stopping the station puts the item back on the bar, where it
      // has been standing all along with nothing driving it: the play
      // button is what takes the engine back.
      await harness.container.read(radioPlaybackProvider.notifier).stop();
      await tester.pumpAndSettle();
      expect(find.text('Prancing Pony Blues'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Play'));
      await tester.pumpAndSettle();
      expect(engine.playing, isTrue);
      expect(engine.loadedUrl, contains('tr-A'));

      await harness.endPlayback(tester);
    });

    testWidgets('a refused station says so instead of offering to stop', (
      tester,
    ) async {
      // The gate is the engine's and a station rides the same engine, so
      // this bar is the only surface that could report a refusal. Left
      // unwired it drew "Play" over a silent stream and stopped the
      // station when that was pressed.
      final repo = FakeRepository(items: [testItem('tr-A')]);
      final station = RadioStation(
        pid: 'ra-1',
        name: 'Coastal FM',
        streamUrl: 'https://radio.example/stream',
        createdAt: DateTime.utc(2026, 7, 1),
      );
      repo.radioStationsByPid[station.pid] = station;
      final engine = FakeEngine()..refuseNextPlay = true;
      final harness = await _pumpDeck(tester, repo: repo, engine: engine);

      await harness.container
          .read(radioPlaybackProvider.notifier)
          .play(station);
      await tester.pumpAndSettle();

      expect(find.text('Coastal FM'), findsOneWidget);
      expect(find.bySemanticsLabel('Tap to resume'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Tap to resume'));
      await tester.pumpAndSettle();

      expect(engine.playing, isTrue, reason: 'the tap is the gesture');
      expect(
        harness.container.read(radioPlaybackProvider).station,
        isNotNull,
        reason: 'the station is still tuned',
      );
      await harness.container.read(radioPlaybackProvider.notifier).stop();
      await tester.pumpAndSettle();
    });
  });

  group('the item menu', () {
    testWidgets('outlives the bar that opened it', (tester) async {
      // A sheet outlives the surface that opened it, and this one is
      // opened from a bar that comes and goes on its own: a routed
      // Connect command clearing the queue replaces it while the menu is
      // still up. Reaching back through the bar's own context then lands
      // on an element no longer in the tree.
      final repo = FakeRepository(items: [testItem('tr-A')]);
      final engine = FakeEngine();
      final harness = await _pumpDeck(
        tester,
        repo: repo,
        engine: engine,
        routed: true,
      );
      harness.play([testItem('tr-A')]);
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('More'));
      await tester.pumpAndSettle();
      expect(find.text('Add to playlist'), findsOneWidget);

      harness.container.read(queueControllerProvider.notifier).clear();
      await tester.pumpAndSettle();
      expect(find.byType(DeckBar), findsNothing, reason: 'the bar is gone');

      await tester.tap(find.text('Add to playlist'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AddToPlaylistDialog), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('the launch offer', () {
    testWidgets('names the queue it found and puts it back', (tester) async {
      final repo = FakeRepository(items: [testItem('tr-A'), testItem('tr-B')]);
      final engine = FakeEngine();
      final store = RecordingQueueStore()..saved = _storedAlbum();
      final container = ProviderContainer(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          audioEngineProvider.overrideWithValue(engine),
          queueStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      final harness = await _pumpDeck(
        tester,
        repo: repo,
        engine: engine,
        container: container,
      );

      expect(find.byType(DeckBarOffer), findsOneWidget);
      expect(find.text('2 queued items'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Resume'));
      await tester.pumpAndSettle();

      final queue = container.read(queueControllerProvider);
      expect(queue.length, 2);
      expect(queue.currentPid, 'tr-A');
      // Putting a queue back is not pressing play: it comes back where
      // it stood, and the transport is right there.
      expect(engine.playing, isFalse);
      expect(find.byType(DeckBarOffer), findsNothing);
      expect(find.byType(DeckBar), findsOneWidget);
      await harness.endPlayback(tester);
    });

    testWidgets('can be turned down, and is forgotten when it is', (
      tester,
    ) async {
      final repo = FakeRepository(items: [testItem('tr-A')]);
      final engine = FakeEngine();
      final store = RecordingQueueStore()..saved = _storedAlbum();
      final container = ProviderContainer(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          audioEngineProvider.overrideWithValue(engine),
          queueStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      await _pumpDeck(tester, repo: repo, engine: engine, container: container);

      await tester.tap(find.bySemanticsLabel('Not now'));
      await tester.pumpAndSettle();

      expect(find.byType(DeckBarOffer), findsNothing);
      expect(store.saved, isNull, reason: 'a declined offer does not return');
    });
  });

  group('the queue panel', () {
    testWidgets('lists what is next, jumps into it, and drops rows', (
      tester,
    ) async {
      final repo = FakeRepository(
        items: [testItem('tr-A'), testItem('tr-B'), testItem('tr-C')],
      );
      final engine = FakeEngine();
      final harness = await _pumpDeck(tester, repo: repo, engine: engine);
      harness.play([
        testItem('tr-A', title: 'First'),
        testItem('tr-B', title: 'Second'),
        testItem('tr-C', title: 'Third'),
      ], source: _album);
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Queue'));
      await tester.pumpAndSettle();
      expect(
        harness.container.read(sidePanelProvider),
        WaxPanel.queue,
        reason: 'the bar opens the panel it names',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: harness.container,
          child: MaterialApp(
            home: _reducedMotion(const Scaffold(body: QueuePanel())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Playing from Kind of Blue'), findsOneWidget);
      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);

      await tester.tap(find.text('Third'));
      await tester.pumpAndSettle();
      expect(
        harness.container.read(queueControllerProvider).currentPid,
        'tr-C',
      );

      await tester.tap(find.bySemanticsLabel('Clear queue'));
      await tester.pumpAndSettle();
      expect(harness.container.read(queueControllerProvider).isEmpty, isTrue);
      expect(find.text('Nothing queued'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('removes the row it is asked to, not the one beside it', (
      tester,
    ) async {
      // The panel renders the tail of the queue, so a row's own index in
      // that view is not the index the controller's verbs take.
      final repo = FakeRepository(
        items: [testItem('tr-A'), testItem('tr-B'), testItem('tr-C')],
      );
      final engine = FakeEngine();
      final harness = await _pumpDeck(tester, repo: repo, engine: engine);
      harness.play([
        testItem('tr-A', title: 'First'),
        testItem('tr-B', title: 'Second'),
        testItem('tr-C', title: 'Third'),
      ], source: _album);
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: harness.container,
          child: MaterialApp(
            home: _reducedMotion(const Scaffold(body: QueuePanel())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Remove from queue').last);
      await tester.pumpAndSettle();

      expect(harness.container.read(queueControllerProvider).pids, <String>[
        'tr-A',
        'tr-B',
      ]);
      await harness.endPlayback(tester);
      // A queue edit is reported to Connect once it settles, four
      // hundred milliseconds later; the test outlives its own timer.
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
