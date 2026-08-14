import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/connect/connect_bus.dart';
import 'package:waxdeck/src/connect/connect_providers.dart';
import 'package:waxdeck/src/connect/remote_session.dart';
import 'package:waxdeck/src/player/autoplay_gate.dart';
import 'package:waxdeck/src/player/deck_bar_host.dart';
import 'package:waxdeck/src/player/output_volume.dart';
import 'package:waxdeck/src/playlists/add_to_playlist_sheet.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_panel.dart';
import 'package:waxdeck/src/queue/queue_persistence.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/side_panel.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'localized_host.dart';
import 'player_host.dart';
import 'queue_persistence_test.dart' show RecordingQueueStore;
import 'routed_host.dart';

/// The widget carrying one semantics handle. By widget rather than by
/// semantics node, because these tests do not enable the semantics tree.
Finder _byId(String id) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.identifier == id,
);

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
          : localizedHost(_reducedMotion(slot), theme: buildWaxTheme()),
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

    testWidgets('opens the words beside the page, for a track that has any', (
      tester,
    ) async {
      final repo = FakeRepository(items: [testItem('tr-A')]);
      final harness = await _pumpDeck(
        tester,
        repo: repo,
        engine: FakeEngine(),
        routed: true,
      );
      harness.play([testItem('tr-A')]);
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.deckLyrics));
      await tester.pumpAndSettle();
      expect(harness.container.read(sidePanelProvider), WaxPanel.lyrics);

      // A book's words are not a thing to follow, so the bar offers no
      // control for them.
      harness.play([
        testItem('bk-1', mediaType: MediaType.audiobook, title: 'A Book'),
      ]);
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier(SemanticsIds.deckLyrics), findsNothing);
      await harness.endPlayback(tester);
    });

    testWidgets('and drops the control on a bar with no cluster', (
      tester,
    ) async {
      final repo = FakeRepository(items: [testItem('tr-A')]);
      final harness = await _pumpDeck(
        tester,
        repo: repo,
        engine: FakeEngine(),
        size: const Size(420, 900),
      );
      harness.play([testItem('tr-A')]);
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier(SemanticsIds.deckLyrics), findsNothing);
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

    testWidgets('offers the heart for a named song, at sidebar width only', (
      tester,
    ) async {
      final repo = FakeRepository(items: [testItem('tr-A')]);
      final station = RadioStation(
        pid: 'ra-1',
        name: 'Coastal FM',
        streamUrl: 'https://radio.example/stream',
        createdAt: DateTime.utc(2026, 7, 1),
      );
      repo.radioStationsByPid[station.pid] = station;
      repo.radioNowPlaying[station.pid] = 'Salt Harbour - The Bree Trio';
      final engine = FakeEngine();
      final harness = await _pumpDeck(tester, repo: repo, engine: engine);
      await harness.container
          .read(radioPlaybackProvider.notifier)
          .play(station);
      await tester.pumpAndSettle();

      final heart = _byId(SemanticsIds.deckSaveSong);
      expect(heart, findsOneWidget);
      await tester.tap(heart);
      await tester.pumpAndSettle();
      expect(repo.savedSongRequests, hasLength(1));
      expect(
        harness.container.read(radioPlaybackProvider).nowPlayingSaved,
        isTrue,
      );

      // The compact bar has no right cluster to put it in, and the full
      // face's own heart is one tap away through expand - the same
      // bargain the star and the level already make here.
      tester.view.physicalSize = const Size(600, 900);
      await tester.pumpAndSettle();
      expect(heart, findsNothing);

      await harness.container.read(radioPlaybackProvider.notifier).stop();
      await tester.pumpAndSettle();
      await harness.endPlayback(tester);
    });

    testWidgets('follows live radio onto the station', (tester) async {
      final repo = FakeRepository(items: [testItem('tr-A')]);
      final station = RadioStation(
        pid: 'ra-1',
        name: 'Coastal FM',
        streamUrl: 'https://radio.example/stream',
        logoUrl: 'https://coastal.example/logo.png',
        createdAt: DateTime.utc(2026, 7, 1),
      );
      repo.radioStationsByPid[station.pid] = station;
      final engine = FakeEngine();
      final artwork = FakeArtworkStore();
      final harness = await _pumpDeck(
        tester,
        repo: repo,
        engine: engine,
        container: playbackContainer(
          repo: repo,
          engine: engine,
          extra: [artworkStoreProvider.overrideWithValue(artwork)],
        ),
      );
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

      // Through the proxy here too. The hub was converted and this face was
      // missed, so the station drawn on every screen was fetched from the
      // station host.
      expect(artwork.requested, contains(repo.radioLogoUrlFor('ra-1')));
      expect(
        artwork.requested.any((url) => url.startsWith('https://coastal')),
        isFalse,
      );

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

  group('the volume slider', () {
    testWidgets('drives local output and follows it back', (tester) async {
      // The condition 5.2 gives desktop and web, which P7 built in
      // neither of the faces it belongs to. The level has to *follow* the
      // engine rather than store its own copy: a routed set-volume from
      // another device and the sleep timer's fade both write there
      // without asking any widget.
      // The gate is the platform, and flutter_test pins that to Android so
      // tests are deterministic - which is exactly the half of 5.2 that
      // gets no slider. Overridden through the provider rather than the
      // foundation global, which the harness checks nobody has moved.
      final repo = FakeRepository(items: [testItem('tr-A')]);
      final engine = FakeEngine();
      final harness = await _pumpDeck(
        tester,
        repo: repo,
        engine: engine,
        container: playbackContainer(
          repo: repo,
          engine: engine,
          extra: [localVolumeAvailableProvider.overrideWithValue(true)],
        ),
      );
      harness.play([testItem('tr-A')]);
      await tester.pumpAndSettle();

      final slider = find.bySemanticsIdentifier(SemanticsIds.deckVolume);
      expect(slider, findsOneWidget);
      expect(tester.getSemantics(slider).value, '100%');

      // A screen reader can set it, which is the contract a semantic
      // slider makes and the reason this is not a bare gesture detector.
      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: SemanticsAction.decrease,
          nodeId: tester.getSemantics(slider).id,
          viewId: tester.view.viewId,
        ),
      );
      await tester.pumpAndSettle();
      expect(engine.volume, closeTo(0.95, 0.001));

      // Somebody else turns this device down: the slider says so, because
      // it reads the engine rather than remembering what it last sent.
      await engine.setVolume(0.25);
      await tester.pumpAndSettle();
      expect(tester.getSemantics(slider).value, '25%');

      // Mute remembers where it was, so it can be undone.
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.deckMute));
      await tester.pumpAndSettle();
      expect(engine.volume, 0);
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.deckMute));
      await tester.pumpAndSettle();
      expect(engine.volume, closeTo(0.25, 0.001));

      await harness.endPlayback(tester);
    });

    testWidgets('the level moves under the finger, not on release', (
      tester,
    ) async {
      // The filed bug: the gain only changed when the finger let go.
      final repo = FakeRepository(items: [testItem('tr-A')]);
      final engine = FakeEngine();
      final harness = await _pumpDeck(
        tester,
        repo: repo,
        engine: engine,
        container: playbackContainer(
          repo: repo,
          engine: engine,
          extra: [localVolumeAvailableProvider.overrideWithValue(true)],
        ),
      );
      harness.play([testItem('tr-A')]);
      await tester.pumpAndSettle();

      final slider = find.bySemanticsIdentifier(SemanticsIds.deckVolume);
      final before = engine.volume;
      final gesture = await tester.startGesture(tester.getCenter(slider));
      await gesture.moveBy(Offset(-tester.getSize(slider).width / 2 + 4, 0));
      await tester.pump();
      expect(
        engine.volume,
        lessThan(before),
        reason: 'the gain must follow the drag, not wait for release',
      );

      await gesture.up();
      await tester.pumpAndSettle();

      await harness.endPlayback(tester);
    });

    testWidgets('a level set from elsewhere becomes the one to come back to', (
      tester,
    ) async {
      // What mute promises is "put it back where it was", and where it was
      // is whatever the engine last reported - not whatever this device set.
      // Another device raising the volume while muted clears the remembered
      // level through the stream, so the next mute records the new one.
      final repo = FakeRepository(items: [testItem('tr-A')]);
      final engine = FakeEngine();
      final container = playbackContainer(
        repo: repo,
        engine: engine,
        extra: [localVolumeAvailableProvider.overrideWithValue(true)],
      );
      final harness = await _pumpDeck(
        tester,
        repo: repo,
        engine: engine,
        container: container,
      );
      harness.play([testItem('tr-A')]);
      await tester.pumpAndSettle();

      final volume = container.read(outputVolumeProvider.notifier);
      await volume.set(0.8);
      await volume.toggleMute();
      expect(engine.volume, 0);

      // Another device turns this one up while it is silenced. That is the
      // level now, so muting again records it and unmuting restores it -
      // 0.8 is gone, and putting it back would be this device overruling
      // the one the listener just used.
      await engine.setVolume(0.4);
      await tester.pumpAndSettle();
      expect(container.read(outputVolumeProvider), closeTo(0.4, 0.001));

      await volume.toggleMute();
      expect(engine.volume, 0);
      await volume.toggleMute();
      expect(engine.volume, closeTo(0.4, 0.001));

      // And with nothing ever recorded, unmuting goes to full rather than
      // staying silent: a control whose only effect is to do nothing is
      // worse than one that guesses.
      final fresh = playbackContainer(
        repo: repo,
        engine: FakeEngine(),
        extra: [localVolumeAvailableProvider.overrideWithValue(true)],
      );
      await fresh.read(audioEngineProvider).setVolume(0);
      await fresh.read(outputVolumeProvider.notifier).toggleMute();
      expect(fresh.read(audioEngineProvider).volume, 1.0);

      await harness.endPlayback(tester);
    });

    testWidgets('is on the radio face too, over the same engine gain', (
      tester,
    ) async {
      // The reported bug: the bar carried a level on every face but the
      // one live radio was on. A station is the engine's output like an
      // item is, and the two faces share the gain, so a level set while a
      // station plays is still there when an item takes the engine back.
      final repo = FakeRepository(items: [testItem('tr-A')]);
      final station = RadioStation(
        pid: 'ra-1',
        name: 'Coastal FM',
        streamUrl: 'https://radio.example/stream',
        createdAt: DateTime.utc(2026, 7, 1),
      );
      repo.radioStationsByPid[station.pid] = station;
      final engine = FakeEngine();
      final harness = await _pumpDeck(
        tester,
        repo: repo,
        engine: engine,
        container: playbackContainer(
          repo: repo,
          engine: engine,
          extra: [localVolumeAvailableProvider.overrideWithValue(true)],
        ),
      );

      await harness.container
          .read(radioPlaybackProvider.notifier)
          .play(station);
      await tester.pumpAndSettle();
      expect(find.text('Coastal FM'), findsOneWidget);

      final slider = find.bySemanticsIdentifier(SemanticsIds.deckVolume);
      expect(slider, findsOneWidget);
      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: SemanticsAction.decrease,
          nodeId: tester.getSemantics(slider).id,
          viewId: tester.view.viewId,
        ),
      );
      await tester.pumpAndSettle();
      expect(engine.volume, closeTo(0.95, 0.001));

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.deckMute));
      await tester.pumpAndSettle();
      expect(engine.volume, 0);

      // One gain, whichever face is drawing it: the level the station was
      // set to is what the item plays at.
      await harness.container.read(radioPlaybackProvider.notifier).stop();
      harness.play([testItem('tr-A')]);
      await tester.pumpAndSettle();
      expect(engine.volume, 0);
      expect(tester.getSemantics(slider).value, '0%');

      await harness.endPlayback(tester);
    });

    testWidgets('is absent on the compact bar, which has no cluster', (
      tester,
    ) async {
      final repo = FakeRepository(items: [testItem('tr-A')]);
      final engine = FakeEngine();
      final harness = await _pumpDeck(
        tester,
        repo: repo,
        engine: engine,
        size: const Size(400, 900),
        // Desktop, so the only thing keeping the slider away is the width.
        container: playbackContainer(
          repo: repo,
          engine: engine,
          extra: [localVolumeAvailableProvider.overrideWithValue(true)],
        ),
      );
      harness.play([testItem('tr-A')]);
      await tester.pumpAndSettle();

      expect(find.byType(DeckBar), findsOneWidget);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.deckVolume),
        findsNothing,
        reason: 'a 64 px bar has no right cluster to hold a track',
      );

      await harness.endPlayback(tester);
    });
  });

  group('the remote face', () {
    testWidgets('says where playback went, and drives it there', (
      tester,
    ) async {
      // The entry this closes: handing a session away used to leave the
      // bar with nothing at all, because the bar read local playback and
      // the remote control was a pushed screen holding its own state.
      final repo = FakeRepository(items: [testItem('tr-A')])
        ..playerEndpoints = const [
          PlayerEndpoint(
            id: 'pe-kitchen',
            kind: 'cast',
            name: 'Kitchen speaker',
            online: true,
            shared: true,
            mine: false,
            volumeControl: true,
            rateControl: false,
          ),
        ];
      final engine = FakeEngine();
      final sent = <Map<String, Object?>>[];
      final container = playbackContainer(
        repo: repo,
        engine: engine,
        extra: [
          connectBusProvider.overrideWith((ref) {
            final bus = ConnectBus(
              send: (frame) {
                sent.add(Map.of(frame));
                return true;
              },
            );
            ref.onDispose(bus.dispose);
            return bus;
          }),
        ],
      );
      final harness = await _pumpDeck(
        tester,
        repo: repo,
        engine: engine,
        container: container,
        routed: true,
      );
      expect(find.byType(DeckBar), findsNothing);

      harness.container
          .read(remoteSessionProvider.notifier)
          .adopt(
            PlaybackSessionInfo(
              id: 'ps-kitchen',
              endpointId: 'pe-kitchen',
              endpointName: 'Kitchen speaker',
              mine: true,
              authority: 'remote',
              playing: true,
              index: 0,
              positionMs: 0,
              positionAt: DateTime.now().toUtc(),
              rate: 1,
              volume: 0.5,
              queueVersion: 1,
              entries: const [
                PlaybackSessionEntry(
                  pid: 'tr-A',
                  title: 'Prancing Pony Blues',
                  artist: 'The Ponies',
                  durationMs: 200000,
                ),
              ],
            ),
          );
      await tester.pumpAndSettle();

      // The caption 5.2 asks for, so a silent device does not read as
      // broken.
      expect(find.byType(DeckBar), findsOneWidget);
      expect(find.textContaining('on Kitchen speaker'), findsOneWidget);

      // The transport is routed rather than local: the engine here is
      // untouched and the verb goes over the bus.
      await tester.tap(find.bySemanticsLabel('Pause'));
      await tester.pump();
      final cmd = sent.lastWhere((f) => f['type'] == 'cmd');
      expect(cmd['verb'], 'pause');
      expect(cmd['sessionId'], 'ps-kitchen');
      expect(engine.playing, isFalse, reason: 'nothing local was playing');
      // Answer the ack: a routed command waits ten seconds for one, and an
      // unanswered wait is a timer outliving the test.
      harness.container.read(connectBusProvider).handleFrame({
        'type': 'ack',
        'id': cmd['id'],
      });
      await tester.pump();

      // The endpoint reports volume control, so the bar draws its level -
      // the second of 5.2's two conditions, and the endpoint's own level
      // rather than this device's.
      final slider = find.bySemanticsIdentifier(SemanticsIds.deckVolume);
      expect(slider, findsOneWidget);
      expect(tester.getSemantics(slider).value, '50%');

      harness.container.read(remoteSessionProvider.notifier).release();
      await tester.pumpAndSettle();
      expect(find.byType(DeckBar), findsNothing);
    });

    testWidgets('offers no seek over an entry with no length', (tester) async {
      // A frame may carry no duration per entry, and every position the
      // seek bar computes is a fraction of it: at zero a scrub would seek
      // the room back to the start.
      final repo = FakeRepository(items: [testItem('tr-A')]);
      final engine = FakeEngine();
      final harness = await _pumpDeck(tester, repo: repo, engine: engine);

      harness.container
          .read(remoteSessionProvider.notifier)
          .adopt(
            PlaybackSessionInfo(
              id: 'ps-kitchen',
              endpointId: 'pe-kitchen',
              endpointName: 'Kitchen speaker',
              mine: true,
              authority: 'remote',
              // Paused, so no position feed outlives the test.
              playing: false,
              index: 0,
              positionMs: 0,
              positionAt: DateTime.now().toUtc(),
              rate: 1,
              queueVersion: 1,
              entries: const [
                PlaybackSessionEntry(pid: 'tr-Z', title: 'Somewhere Else'),
              ],
            ),
          );
      await tester.pumpAndSettle();

      expect(find.text('Somewhere Else'), findsOneWidget);
      final seek = find.bySemanticsIdentifier(SemanticsIds.deckSeek);
      expect(seek, findsOneWidget);
      expect(
        tester
            .getSemantics(seek)
            .getSemanticsData()
            .hasAction(SemanticsAction.increase),
        isFalse,
        reason: 'a zero-length entry has nowhere to seek to',
      );

      harness.container.read(remoteSessionProvider.notifier).release();
      await tester.pumpAndSettle();
    });

    testWidgets('yields to what is playing on this device', (tester) async {
      // The bar's promise is "this is what you are listening to", and
      // local playback is what is coming out of this device. Opening
      // another device's session to skip a track must not take the bar
      // away from the album playing here.
      final repo = FakeRepository(items: [testItem('tr-A')]);
      final engine = FakeEngine();
      final harness = await _pumpDeck(tester, repo: repo, engine: engine);
      harness.play([testItem('tr-A')]);
      await tester.pumpAndSettle();

      harness.container
          .read(remoteSessionProvider.notifier)
          .adopt(
            PlaybackSessionInfo(
              id: 'ps-kitchen',
              endpointId: 'pe-kitchen',
              endpointName: 'Kitchen speaker',
              mine: true,
              authority: 'remote',
              // Paused, so no position feed outlives the test.
              playing: false,
              index: 0,
              positionMs: 0,
              positionAt: DateTime.now().toUtc(),
              rate: 1,
              queueVersion: 1,
              entries: const [
                PlaybackSessionEntry(pid: 'tr-Z', title: 'Somewhere Else'),
              ],
            ),
          );
      await tester.pumpAndSettle();

      expect(find.text('Prancing Pony Blues'), findsOneWidget);
      expect(find.text('Somewhere Else'), findsNothing);

      harness.container.read(remoteSessionProvider.notifier).release();
      await harness.endPlayback(tester);
    });
  });

  group('opening the player', () {
    testWidgets('is one push however many times the bar is clicked', (
      tester,
    ) async {
      // The expand is one onTap, so a double click fires it twice. That
      // is correct behaviour and it has to be idempotent: without the
      // guard the second click stacks a second player over the first, and
      // backing out once looks like nothing happened. A double-tap
      // recogniser would be the wrong fix - it costs the disambiguation
      // delay and swallows the first tap.
      final repo = FakeRepository(items: [testItem('tr-A')]);
      final harness = await _pumpDeck(
        tester,
        repo: repo,
        engine: FakeEngine(),
        routed: true,
      );
      harness.play([testItem('tr-A')]);
      await tester.pumpAndSettle();

      final router = GoRouter.of(tester.element(find.byType(DeckBar)));
      final before = router.routerDelegate.currentConfiguration.matches.length;

      final expand = _byId(SemanticsIds.deckExpand);
      expect(expand, findsOne, reason: 'the bar says how to open the player');
      await tester.tap(expand);
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.matches,
        hasLength(before + 1),
      );

      // And again on a stack that already has it, which is what the
      // second half of a double click is. `pushOnce` is what makes it a
      // no-op; the bar itself is gone from this host once the player is
      // up, so the guard is exercised through the router.
      router.pushOnce(WaxRoute.nowPlaying);
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.matches,
        hasLength(before + 1),
        reason: 'a second click must not stack a second player',
      );

      await harness.endPlayback(tester);
    });

    testWidgets('takes a click on the padding, not only on what is drawn', (
      tester,
    ) async {
      // deferToChild left the horizontal padding, the gutter between the
      // artwork and the title, and the slack around a shrink-wrapped
      // title block all falling through, which is the half of the bug
      // that reads as "sometimes works and sometimes does not".
      final repo = FakeRepository(items: [testItem('tr-A')]);
      final harness = await _pumpDeck(
        tester,
        repo: repo,
        engine: FakeEngine(),
        size: const Size(500, 900),
        routed: true,
      );
      harness.play([testItem('tr-A')]);
      await tester.pumpAndSettle();

      final router = GoRouter.of(tester.element(find.byType(DeckBar)));
      final before = router.routerDelegate.currentConfiguration.matches.length;

      // The bar's left edge, inside its padding and over nothing drawn.
      final bar = tester.getRect(find.byType(DeckBar));
      await tester.tapAt(Offset(bar.left + 3, bar.center.dy));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.matches,
        hasLength(before + 1),
      );

      await harness.endPlayback(tester);
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
      expect(find.byType(AddToPlaylistSheet), findsOneWidget);
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
          child: localizedHost(
            _reducedMotion(const Scaffold(body: QueuePanel())),
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
          child: localizedHost(
            _reducedMotion(const Scaffold(body: QueuePanel())),
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
