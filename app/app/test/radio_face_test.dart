import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/player/player_screen.dart';
import 'package:waxdeck/src/player/radio_face.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck/src/settings/client_settings_providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

const _stationPid = 'rs-01JZX5N8QW3F4V9T2B7KDSTATN1';

RadioStation _station() => RadioStation(
  pid: _stationPid,
  name: 'Coastal FM',
  streamUrl: 'https://stream.example/coastal',
  homepageUrl: 'https://coastal.example',
  createdAt: DateTime.utc(2026, 7, 1),
);

/// Animations off: the platter ring turns forever, which is the point of
/// it and the end of `pumpAndSettle`.
Widget _stilled(Widget child) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: child,
  ),
);

Future<ProviderContainer> _pumpTuned(
  WidgetTester tester, {
  required FakeRepository repo,
  required FakeEngine engine,
}) async {
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      audioEngineProvider.overrideWithValue(engine),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      clientSettingsStoreProvider.overrideWithValue(
        MemoryClientSettingsStore(),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(radioPlaybackProvider.notifier).play(_station());
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: routedHost(_stilled(const PlayerScreen())),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Lets the station go. The ICY poll is a live timer, and a test that
/// left one running fails on the pending timer rather than on what it
/// was checking.
Future<void> _stop(ProviderContainer container) =>
    container.read(radioPlaybackProvider.notifier).stop();

/// The shape the face's own artwork is drawn in. Scoped to the hero,
/// which is the one piece of artwork the scaffold draws.
ArtworkShape _heroShape(WidgetTester tester) => tester
    .widget<ArtworkImage>(
      find.descendant(
        of: find.byType(Hero),
        matching: find.byType(ArtworkImage),
      ),
    )
    .shape;

void main() {
  testWidgets('the player draws the station when radio has the engine', (
    tester,
  ) async {
    final repo = FakeRepository()..radioStationsByPid[_stationPid] = _station();
    final engine = FakeEngine();
    final container = await _pumpTuned(tester, repo: repo, engine: engine);

    // Twice: the title row, and the station mark standing in for a logo
    // this station does not have. Real station logos are their name set
    // in type, so a mark that reads as one is the point rather than a
    // duplication - and the artwork is `ExcludeSemantics`, so a screen
    // reader still hears the name once.
    expect(find.text('Coastal FM'), findsNWidgets(2));
    // Live, so there is no seek bar to lie with and no next to press.
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.bySemanticsIdentifier(SemanticsIds.playerSeek), findsNothing);
    expect(find.bySemanticsIdentifier(SemanticsIds.playerNext), findsNothing);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playerShuffle),
      findsNothing,
    );
    // The sleep timer is on every face: it is about the device rather
    // than the medium.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.sleepTimerOpen),
      findsOneWidget,
    );
    await _stop(container);
  });

  testWidgets('the one transport control stops the station', (tester) async {
    final repo = FakeRepository()..radioStationsByPid[_stationPid] = _station();
    final engine = FakeEngine();
    final container = await _pumpTuned(tester, repo: repo, engine: engine);

    expect(engine.playing, isTrue);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerToggle));
    await tester.pumpAndSettle();

    // Stop, not pause: a paused live stream resumes at the live edge
    // anyway, so the station is let go of entirely.
    expect(engine.playing, isFalse);
    expect(container.read(radioPlaybackProvider).station, isNull);
  });

  testWidgets('a stopped station leaves the player rather than emptying it', (
    tester,
  ) async {
    // The reason the surface was open has gone, and the deck bar goes
    // in the same frame, so there is nothing to minimize to either.
    final repo = FakeRepository()..radioStationsByPid[_stationPid] = _station();
    final container = await _pumpTuned(
      tester,
      repo: repo,
      engine: FakeEngine(),
    );

    expect(find.byType(PlayerScaffold), findsOneWidget);
    await container.read(radioPlaybackProvider.notifier).stop();
    await tester.pumpAndSettle();

    expect(find.byType(PlayerScaffold), findsNothing);
    expect(find.byKey(const Key('player-idle')), findsNothing);
  });

  testWidgets('a stop under an open dialog leaves the dialog alone', (
    tester,
  ) async {
    // The state can empty from anywhere and does not wait for a dialog.
    // Popping then takes the dialog and leaves the player behind.
    final repo = FakeRepository()..radioStationsByPid[_stationPid] = _station();
    final container = await _pumpTuned(
      tester,
      repo: repo,
      engine: FakeEngine(),
    );

    unawaited(
      showDialog<void>(
        context: tester.element(find.byType(PlayerScreen)),
        builder: (_) => const AlertDialog(content: Text('half-typed edit')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('half-typed edit'), findsOneWidget);

    await container.read(radioPlaybackProvider.notifier).stop();
    await tester.pumpAndSettle();

    expect(find.text('half-typed edit'), findsOneWidget);
  });

  testWidgets('a matched cover squares the artwork and takes the ring off', (
    tester,
  ) async {
    // A sleeve cropped to a circle loses its corners, and the ring
    // reads as a hoop thrown over it.
    final repo = FakeRepository()
      ..radioStationsByPid[_stationPid] = _station()
      ..radioNowPlaying[_stationPid] = 'Salt Harbour - The Bree Trio'
      ..radioNowPlayingItemPid[_stationPid] = 'tr-01JZX5N8QW3F4V9T2B7KDMATCH1';
    final container = await _pumpTuned(
      tester,
      repo: repo,
      engine: FakeEngine(),
    );

    expect(_heroShape(tester), ArtworkShape.square);
    expect(find.byType(PlatterRing), findsNothing);
    await _stop(container);
  });

  testWidgets('a station with only its logo keeps the circle and the ring', (
    tester,
  ) async {
    final repo = FakeRepository()..radioStationsByPid[_stationPid] = _station();
    final container = await _pumpTuned(
      tester,
      repo: repo,
      engine: FakeEngine(),
    );

    expect(_heroShape(tester), ArtworkShape.circle);
    expect(find.byType(PlatterRing), findsOneWidget);
    await _stop(container);
  });

  testWidgets('a named track offers a way into the library', (tester) async {
    final repo = FakeRepository()
      ..radioStationsByPid[_stationPid] = _station()
      ..radioNowPlaying[_stationPid] = 'Salt Harbour - The Bree Trio';
    final engine = FakeEngine();
    final container = await _pumpTuned(tester, repo: repo, engine: engine);

    expect(find.text('Salt Harbour - The Bree Trio'), findsOneWidget);
    final shortcut = find.bySemanticsIdentifier(
      SemanticsIds.playerFindInLibrary,
    );
    expect(shortcut, findsOneWidget);
    expect(tester.getSemantics(shortcut).label, contains('Salt Harbour'));
    await _stop(container);
  });

  testWidgets('a station nobody has named offers no search shortcut', (
    tester,
  ) async {
    final repo = FakeRepository()..radioStationsByPid[_stationPid] = _station();
    final container = await _pumpTuned(
      tester,
      repo: repo,
      engine: FakeEngine(),
    );

    expect(
      find.bySemanticsIdentifier(SemanticsIds.playerFindInLibrary),
      findsNothing,
    );
    await _stop(container);
  });

  testWidgets('the heart keeps the song the station named', (tester) async {
    final repo = FakeRepository()
      ..radioStationsByPid[_stationPid] = _station()
      ..radioNowPlaying[_stationPid] = 'Salt Harbour - The Bree Trio';
    final container = await _pumpTuned(
      tester,
      repo: repo,
      engine: FakeEngine(),
    );

    final heart = find.bySemanticsIdentifier(SemanticsIds.playerSaveSong);
    expect(heart, findsOneWidget);
    // The wording says song, never favourite: the star two rows up means
    // "pin this station", and two affordances that both read as
    // favouriting would blur into each other.
    expect(tester.getSemantics(heart).label, 'Save this song');

    await tester.tap(heart);
    await tester.pumpAndSettle();

    // The line the listener saw, sent as they saw it: a station rolls
    // over between polls, so resolving it server-side would sometimes
    // keep the next song.
    expect(repo.savedSongRequests, hasLength(1));
    expect(
      repo.savedSongRequests.single.nowPlaying,
      'Salt Harbour - The Bree Trio',
    );
    expect(container.read(radioPlaybackProvider).nowPlayingSaved, isTrue);
    expect(tester.getSemantics(heart).label, 'Forget this song');

    // And the same tap takes it back off.
    await tester.tap(heart);
    await tester.pumpAndSettle();
    expect(container.read(radioPlaybackProvider).nowPlayingSaved, isFalse);
    expect(
      await repo.listRadioSavedSongs(),
      isA<RadioSavedSongPage>().having((p) => p.songs, 'songs', isEmpty),
    );
    await _stop(container);
  });

  testWidgets('a poll that answers nothing leaves the song standing', (
    tester,
  ) async {
    // The server drops a title when it stops hearing from the station,
    // and a track can outlast that. Adopting the blank emptied the face
    // mid-song, artwork included.
    final repo = FakeRepository()
      ..radioStationsByPid[_stationPid] = _station()
      ..radioNowPlaying[_stationPid] = 'Salt Harbour - The Bree Trio'
      ..radioNowPlayingItemPid[_stationPid] = 'tr-01JZX5N8QW3F4V9T2B7KDMATCH1';
    final container = await _pumpTuned(
      tester,
      repo: repo,
      engine: FakeEngine(),
    );
    expect(
      container.read(radioPlaybackProvider).nowPlaying,
      'Salt Harbour - The Bree Trio',
    );

    repo.radioNowPlaying.remove(_stationPid);
    repo.radioNowPlayingItemPid.remove(_stationPid);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    final held = container.read(radioPlaybackProvider);
    expect(held.nowPlaying, 'Salt Harbour - The Bree Trio');
    expect(held.nowPlayingItemPid, 'tr-01JZX5N8QW3F4V9T2B7KDMATCH1');

    // And a real answer still lands: this holds a blank, not the state.
    repo.radioNowPlaying[_stationPid] = 'Nightjar - Long Way Down';
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(
      container.read(radioPlaybackProvider).nowPlaying,
      'Nightjar - Long Way Down',
    );
    await _stop(container);
  });

  testWidgets('a blank that keeps coming is eventually believed', (
    tester,
  ) async {
    // The server lets a title go when nobody has renewed it for long
    // enough, and that is a decision rather than a gap. Riding a blank
    // out forever would put the client's memory above the server's
    // answer and leave a song on the face for the rest of the session.
    final repo = FakeRepository()
      ..radioStationsByPid[_stationPid] = _station()
      ..radioNowPlaying[_stationPid] = 'Salt Harbour - The Bree Trio';
    final container = await _pumpTuned(
      tester,
      repo: repo,
      engine: FakeEngine(),
    );

    repo.radioNowPlaying.remove(_stationPid);
    // Well past the grace: the poll runs every fifteen seconds.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
    }

    expect(container.read(radioPlaybackProvider).nowPlaying, isNull);
    await _stop(container);
  });

  testWidgets('the grace does not carry over to the next station', (
    tester,
  ) async {
    // A station that had gone quiet must not spend the next one's grace:
    // tuning publishes a title directly, so a carried count empties it on
    // the first blank poll.
    const otherPid = 'rs-01JZX5N8QW3F4V9T2B7KDSTATN2';
    final other = RadioStation(
      pid: otherPid,
      name: 'Inland FM',
      streamUrl: 'https://stream.example/inland',
      createdAt: DateTime.utc(2026, 7, 1),
    );
    final repo = FakeRepository()
      ..radioStationsByPid[_stationPid] = _station()
      ..radioStationsByPid[otherPid] = other
      ..radioNowPlaying[_stationPid] = 'Salt Harbour - The Bree Trio';
    final container = await _pumpTuned(
      tester,
      repo: repo,
      engine: FakeEngine(),
    );

    // Spend some of the first station's grace, staying inside it.
    repo.radioNowPlaying.remove(_stationPid);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
    }
    expect(
      container.read(radioPlaybackProvider).nowPlaying,
      'Salt Harbour - The Bree Trio',
    );

    // The new station names a song at tune time, and the relay has not
    // seen a block yet - so its first poll answers blank.
    repo.radioNowPlaying[otherPid] = 'Nightjar - Long Way Down';
    await container.read(radioPlaybackProvider.notifier).play(other);
    await tester.pumpAndSettle();
    repo.radioNowPlaying.remove(otherPid);
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();

    expect(
      container.read(radioPlaybackProvider).nowPlaying,
      'Nightjar - Long Way Down',
    );
    await _stop(container);
  });

  testWidgets('an untap that crosses its own save takes the row back', (
    tester,
  ) async {
    // The double tap: the second one lands while the first one's save is
    // still in flight, so it has no pid to remove. Leaving the row would
    // put it on the server with nothing pointing at it, and the next
    // poll would fill the heart back in against what the last tap asked
    // for.
    final gate = Completer<void>();
    final repo = FakeRepository()
      ..radioStationsByPid[_stationPid] = _station()
      ..radioNowPlaying[_stationPid] = 'Salt Harbour - The Bree Trio'
      ..saveSongGate = gate.future;
    final container = await _pumpTuned(
      tester,
      repo: repo,
      engine: FakeEngine(),
    );
    final notifier = container.read(radioPlaybackProvider.notifier);

    final first = notifier.toggleSaveNowPlaying();
    await tester.pump();
    expect(container.read(radioPlaybackProvider).nowPlayingSaved, isTrue);
    expect(container.read(radioPlaybackProvider).nowPlayingSavedPid, isNull);

    // Untapped before the save answers.
    final second = notifier.toggleSaveNowPlaying();
    await tester.pump();
    expect(container.read(radioPlaybackProvider).nowPlayingSaved, isFalse);

    gate.complete();
    await first;
    await second;
    await tester.pumpAndSettle();

    // The row the first tap created is gone, so the poll has nothing to
    // fill the heart back in with.
    expect(container.read(radioPlaybackProvider).nowPlayingSaved, isFalse);
    expect((await repo.listRadioSavedSongs()).songs, isEmpty);
    await _stop(container);
  });

  testWidgets('a save in flight does not freeze what is playing', (
    tester,
  ) async {
    // The heart is the poll's to leave alone while a tap is in flight;
    // the title, the match and the art key are not. Holding the whole
    // answer back stopped now-playing dead for as long as a save took.
    final gate = Completer<void>();
    final repo = FakeRepository()
      ..radioStationsByPid[_stationPid] = _station()
      ..radioNowPlaying[_stationPid] = 'Salt Harbour - The Bree Trio'
      ..saveSongGate = gate.future;
    final container = await _pumpTuned(
      tester,
      repo: repo,
      engine: FakeEngine(),
    );
    final notifier = container.read(radioPlaybackProvider.notifier);

    final tap = notifier.toggleSaveNowPlaying();
    await tester.pump();
    expect(container.read(radioPlaybackProvider).nowPlayingSaved, isTrue);

    // The station rolls over while the save is still out, and the poll's
    // own first tick - four seconds after a tune - brings it.
    repo.radioNowPlaying[_stationPid] = 'Nightjar - Long Way Down';
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(
      container.read(radioPlaybackProvider).nowPlaying,
      'Nightjar - Long Way Down',
    );
    // And the heart belongs to the new song, not to the tap that was
    // about the old one.
    expect(container.read(radioPlaybackProvider).nowPlayingSaved, isFalse);

    gate.complete();
    await tap;
    await _stop(container);
  });

  testWidgets('a refused save puts the heart back and says why', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..radioStationsByPid[_stationPid] = _station()
      ..radioNowPlaying[_stationPid] = 'Salt Harbour - The Bree Trio'
      ..saveSongError = const WaxDeckApiException(
        code: 'conflict',
        message: 'the saved songs list is full; remove something first',
      );
    final container = await _pumpTuned(
      tester,
      repo: repo,
      engine: FakeEngine(),
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerSaveSong));
    await tester.pumpAndSettle();

    expect(container.read(radioPlaybackProvider).nowPlayingSaved, isFalse);
    expect(
      find.text('the saved songs list is full; remove something first'),
      findsOneWidget,
    );
    await _stop(container);
  });

  testWidgets('a station nobody has named offers no heart', (tester) async {
    final repo = FakeRepository()..radioStationsByPid[_stationPid] = _station();
    final container = await _pumpTuned(
      tester,
      repo: repo,
      engine: FakeEngine(),
    );

    expect(
      find.bySemanticsIdentifier(SemanticsIds.playerSaveSong),
      findsNothing,
    );
    await _stop(container);
  });

  testWidgets('the station can be pinned from the player', (tester) async {
    final repo = FakeRepository(
      sessionState: const SessionState(
        authenticated: true,
        user: WaxDeckUser(
          id: 'us-1',
          username: 'admin',
          roles: <String>['admin'],
        ),
      ),
    )..radioStationsByPid[_stationPid] = _station();
    final container = await _pumpTuned(
      tester,
      repo: repo,
      engine: FakeEngine(),
    );

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.radioFavorite(_stationPid)),
    );
    await tester.pumpAndSettle();
    expect(container.read(radioFavoritesProvider), contains(_stationPid));
    await _stop(container);
  });

  testWidgets('a radio wakeup collects a cover without waiting a poll', (
    tester,
  ) async {
    final repo = FakeRepository()..radioStationsByPid[_stationPid] = _station();
    repo.radioNowPlaying[_stationPid] = 'Charlie Parker - Ornithology';
    final container = await _pumpTuned(
      tester,
      repo: repo,
      engine: FakeEngine(),
    );
    expect(
      container.read(radioPlaybackProvider).nowPlayingArtKey,
      isNull,
      reason: 'the lookup has not landed yet',
    );

    // The server's detached lookup lands, and it wakes the client rather
    // than leaving the key for the next fifteen-second poll.
    repo.radioNowPlayingArtKey[_stationPid] = 'artkey-1';
    container.read(radioPlaybackProvider.notifier).refreshNowPlaying();
    await tester.pumpAndSettle();

    expect(
      container.read(radioPlaybackProvider).nowPlayingArtKey,
      'artkey-1',
      reason: 'the nudge re-read play-info off the poll schedule',
    );
    await _stop(container);
  });

  testWidgets('a radio wakeup mid-tune leaves the station buffering', (
    tester,
  ) async {
    final repo = FakeRepository()..radioStationsByPid[_stationPid] = _station();
    repo.radioPlayInfoGates[_stationPid] = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        audioEngineProvider.overrideWithValue(FakeEngine()),
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        clientSettingsStoreProvider.overrideWithValue(
          MemoryClientSettingsStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final tune = container
        .read(radioPlaybackProvider.notifier)
        .play(_station());
    await tester.pump();
    expect(container.read(radioPlaybackProvider).starting, isTrue);

    // A cover landing for somebody else's station reaches every client,
    // so this arrives mid-tune. It must not answer for the tune.
    container.read(radioPlaybackProvider.notifier).refreshNowPlaying();
    await tester.pump();

    expect(
      container.read(radioPlaybackProvider).starting,
      isTrue,
      reason: 'the transport control flipped to play over a buffering stream',
    );
    expect(repo.radioPlayInfoReads, 1, reason: 'only the tune asked');
    repo.radioPlayInfoGates[_stationPid]!.complete();
    await tune;
    await _stop(container);
  });

  testWidgets('radio wakeups do not spend the blank-title grace', (
    tester,
  ) async {
    final repo = FakeRepository()..radioStationsByPid[_stationPid] = _station();
    repo.radioNowPlaying[_stationPid] = 'Charlie Parker - Ornithology';
    final container = await _pumpTuned(
      tester,
      repo: repo,
      engine: FakeEngine(),
    );

    // The server restarted and lost the title. The grace rides that out
    // for two minutes of polling, and a burst of wakeups - which is what
    // a busy server sends - must not spend it in a few frames.
    repo.radioNowPlaying.remove(_stationPid);
    for (var i = 0; i < 12; i++) {
      container.read(radioPlaybackProvider.notifier).refreshNowPlaying();
      await tester.pumpAndSettle();
    }

    expect(
      container.read(radioPlaybackProvider).nowPlaying,
      'Charlie Parker - Ornithology',
      reason: 'the wakeups counted against a grace measured in polls',
    );
    await _stop(container);
  });

  testWidgets('a radio wakeup with no station tuned does nothing', (
    tester,
  ) async {
    final repo = FakeRepository();
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        audioEngineProvider.overrideWithValue(FakeEngine()),
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        clientSettingsStoreProvider.overrideWithValue(
          MemoryClientSettingsStore(),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(radioPlaybackProvider.notifier).refreshNowPlaying();
    await tester.pump();

    expect(
      repo.radioPlayInfoReads,
      0,
      reason: 'a wakeup with nothing tuned asks the server nothing',
    );
    expect(container.read(radioPlaybackProvider).station, isNull);
  });
}
