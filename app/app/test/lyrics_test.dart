import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/player/lyrics.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/metadata/metadata_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_screen.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/side_panel.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'player_host.dart';
import 'routed_host.dart';

const _pid = 'tr-01JZX5N8QW3F4V9T2B7KD3M9R6';
const _nextPid = 'tr-01JZX5N8QW3F4V9T2B7KDSECOND';

const _synced = Lyrics(
  pid: _pid,
  source: 'lrc',
  synced: <SyncedLine>[
    SyncedLine(timeMs: 0, text: 'The tide comes in'),
    SyncedLine(timeMs: 12000, text: 'and the harbour lights go out'),
  ],
);

/// Wide enough for a sidebar, which is what decides panel versus sheet.
void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('the music face carries the lyrics control', (tester) async {
    _phone(tester);
    final repo = FakeRepository();
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
      item: testItem(_pid),
    );

    expect(
      find.bySemanticsIdentifier(SemanticsIds.playerLyrics),
      findsOneWidget,
    );
    // Nothing is asked for until somebody opens it: a player that
    // fetched words for every track would be a request per play for a
    // panel most listeners never open.
    expect(repo.lyricsCalls, isEmpty);
    await harness.endPlayback(tester);
  });

  testWidgets('a spoken-word face does not', (tester) async {
    _phone(tester);
    final repo = FakeRepository();
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
      item: testItem(
        'bk-01JZX5N8QW3F4V9T2B7KD3M9R6',
        mediaType: MediaType.audiobook,
      ),
    );

    expect(find.bySemanticsIdentifier(SemanticsIds.playerLyrics), findsNothing);
    await harness.endPlayback(tester);
  });

  testWidgets('the player overlays the words even where a panel would fit', (
    tester,
  ) async {
    // A wide window has a panel, and the player is a route pushed over
    // the shell that holds it: opening the panel from here would open it
    // behind this surface, so the control would light up and nothing
    // anybody could see would happen.
    _wide(tester);
    final repo = FakeRepository()..lyrics[_pid] = _synced;
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
      item: testItem(_pid),
      host: (player) => routedHost(player),
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerLyrics));
    await tester.pumpAndSettle();

    expect(harness.container.read(sidePanelProvider), isNull);
    expect(find.text('The tide comes in'), findsOneWidget);
    await harness.endPlayback(tester);
  });

  testWidgets('a phone gets the words as an overlay too', (tester) async {
    _phone(tester);
    final repo = FakeRepository()..lyrics[_pid] = _synced;
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
      item: testItem(_pid),
      host: (player) => routedHost(player),
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerLyrics));
    await tester.pumpAndSettle();

    expect(harness.container.read(sidePanelProvider), isNull);
    expect(find.text('The tide comes in'), findsOneWidget);
    expect(repo.lyricsCalls, <String>[_pid]);
    await harness.endPlayback(tester);
  });

  testWidgets('a track with no words says so, with a door for an admin', (
    tester,
  ) async {
    _phone(tester);
    final repo = FakeRepository(
      sessionState: const SessionState(
        authenticated: true,
        user: WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']),
      ),
    );
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
      item: testItem(_pid),
      container: playbackContainer(
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
        // Without a store the session never resolves in a test, and the
        // role behind the door would read as "not an admin" for a reason
        // that has nothing to do with lyrics.
        extra: [
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        ],
      ),
      host: (player) => routedHost(player),
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerLyrics));
    await tester.pumpAndSettle();

    expect(find.text('No lyrics for this track'), findsOneWidget);
    expect(find.bySemanticsIdentifier(SemanticsIds.lyricsAdd), findsOneWidget);
    await harness.endPlayback(tester);
  });

  testWidgets('and offers a member no door into a room they cannot enter', (
    tester,
  ) async {
    _phone(tester);
    final repo = FakeRepository(
      sessionState: const SessionState(
        authenticated: true,
        user: WaxDeckUser(id: 'us-2', username: 'member', roles: ['user']),
      ),
    );
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
      item: testItem(_pid),
      container: playbackContainer(
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
        // Without a store the session never resolves in a test, and the
        // role behind the door would read as "not an admin" for a reason
        // that has nothing to do with lyrics.
        extra: [
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        ],
      ),
      host: (player) => routedHost(player),
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerLyrics));
    await tester.pumpAndSettle();

    expect(find.text('No lyrics for this track'), findsOneWidget);
    expect(find.bySemanticsIdentifier(SemanticsIds.lyricsAdd), findsNothing);
    await harness.endPlayback(tester);
  });

  testWidgets('a line seeks the engine to its own moment', (tester) async {
    _phone(tester);
    final repo = FakeRepository()..lyrics[_pid] = _synced;
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(_pid),
      host: (player) => routedHost(player),
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerLyrics));
    await tester.pumpAndSettle();
    await tester.tap(find.text('and the harbour lights go out'));
    await tester.pumpAndSettle();

    expect(engine.position, const Duration(seconds: 12));
    await harness.endPlayback(tester);
  });

  testWidgets('and the queue beside it does the same', (tester) async {
    // The same defect and the same fix: both of the player's controls
    // would otherwise open a panel this surface is covering. The deck
    // bar keeps the panel, which `deck_bar_test.dart` pins.
    _wide(tester);
    final harness = await pumpPlayer(
      tester,
      repo: FakeRepository(),
      engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
      item: testItem(_pid),
      host: (player) => routedHost(player),
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerQueue));
    await tester.pumpAndSettle();

    expect(harness.container.read(sidePanelProvider), isNull);
    expect(find.byType(QueueScreen), findsOneWidget);
    await harness.endPlayback(tester);
  });

  testWidgets('a record with nothing in it says so rather than drawing '
      'an empty column', (tester) async {
    _phone(tester);
    // The contract promises one of the two is non-empty. A client that
    // took that on trust paints a blank page under a header.
    final repo = FakeRepository()
      ..lyrics[_pid] = const Lyrics(pid: _pid, source: 'lrc');
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
      item: testItem(_pid),
      host: (player) => routedHost(player),
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerLyrics));
    await tester.pumpAndSettle();
    expect(find.text('No lyrics for this track'), findsOneWidget);
    await harness.endPlayback(tester);
  });

  testWidgets('the sheet follows the queue rather than the track it was '
      'opened over', (tester) async {
    _phone(tester);
    final repo = FakeRepository()
      ..lyrics[_pid] = _synced
      ..lyrics[_nextPid] = const Lyrics(
        pid: _nextPid,
        source: 'lrc',
        synced: <SyncedLine>[SyncedLine(timeMs: 0, text: 'A different song')],
      );
    final container = playbackContainer(
      repo: repo,
      engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
    );
    final harness = PlayerHarness(container);
    harness.play([testItem(_pid), testItem(_nextPid, title: 'Second')]);
    await pumpPlayerInto(tester, harness, host: (p) => routedHost(p));

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerLyrics));
    await tester.pumpAndSettle();
    expect(find.text('The tide comes in'), findsOneWidget);

    // The queue moves on with the sheet still up. The player keeps its
    // State across the change, so a sheet handed the session it was
    // opened with would still be showing the first track's words while
    // the highlight ran off the second track's playhead - and a tap
    // would seek a session that had already let go.
    await container.read(nowPlayingProvider.notifier).next();
    await tester.pumpAndSettle();
    expect(find.text('A different song'), findsOneWidget);
    expect(find.text('The tide comes in'), findsNothing);
    await harness.endPlayback(tester);
  });

  testWidgets('the door out of the sheet takes the sheet with it', (
    tester,
  ) async {
    _phone(tester);
    final repo = FakeRepository(
      sessionState: const SessionState(
        authenticated: true,
        user: WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']),
      ),
    );
    final container = playbackContainer(
      repo: repo,
      engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
      extra: [
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      ],
    );
    final harness = PlayerHarness(container);
    harness.play([testItem(_pid)]);
    await pumpPlayerInto(tester, harness, host: (p) => routedHost(p));

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerLyrics));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.lyricsAdd));
    await tester.pumpAndSettle();

    // The editor is up and the sheet is not underneath it: left
    // standing, back from the editor lands on the words for a track the
    // listener has walked away from.
    expect(find.byType(MetadataScreen), findsOneWidget);
    expect(find.text('No lyrics for this track'), findsNothing);
    await harness.endPlayback(tester);
  });

  testWidgets('and the same door in the panel pops no screen', (tester) async {
    // The panel draws the same empty state, and there its enclosing
    // route is the page underneath rather than an overlay: popping would
    // take a screen the listener is still on.
    _wide(tester);
    final repo = FakeRepository(
      sessionState: const SessionState(
        authenticated: true,
        user: WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']),
      ),
    );
    final container = playbackContainer(
      repo: repo,
      engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
      extra: [
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      ],
    );
    final harness = PlayerHarness(container);
    harness.play([testItem(_pid)]);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(const LyricsPanel()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.lyricsAdd));
    // Bounded rather than settled: the editor spins while its own reads
    // are in flight, and a fake that answers none of them never settles.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(MetadataScreen), findsOneWidget);
    await harness.endPlayback(tester);
  });

  testWidgets('the panel draws what is playing, not what opened it', (
    tester,
  ) async {
    _wide(tester);
    final repo = FakeRepository()..lyrics[_pid] = _synced;
    final container = playbackContainer(
      repo: repo,
      engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
    );
    final harness = PlayerHarness(container);
    harness.play([testItem(_pid)]);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(const LyricsPanel()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('The tide comes in'), findsOneWidget);
    await harness.endPlayback(tester);
  });
}
