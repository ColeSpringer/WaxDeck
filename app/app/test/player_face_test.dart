import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/l10n/l10n.dart';
import 'package:waxdeck/src/player/player_screen.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/shell/commands.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart' show ArtworkCaption;

import 'fakes.dart';
import 'player_host.dart';
import 'routed_host.dart';

const _first = 'tr-01JZX5N8QW3F4V9T2B7KDMUSIC1';
const _second = 'tr-01JZX5N8QW3F4V9T2B7KDMUSIC2';
const _bookPid = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';

ItemSummary _track(String pid, String title) =>
    testItem(pid, title: title, artist: 'Nightjar');

/// The player over a router arranged the way the app arranges it, which
/// the plain [routedHost] cannot be: the key map has to sit *inside* the
/// router, or a command that navigates finds no `GoRouter` from the
/// context it is run with, and *above* the navigator the player is
/// pushed onto, or the key never reaches the map from the focused route.
/// A shell route is where the app satisfies both, so it is where this
/// does too.
Widget _keyboardHost(Widget player) {
  final router = GoRouter(
    initialLocation: '/under-test/player',
    routes: <RouteBase>[
      ShellRoute(
        builder: (context, state, child) => CommandShortcuts(child: child),
        routes: <RouteBase>[
          GoRoute(
            path: '/under-test',
            // Something to go back to, so popping is what the app does
            // rather than the fallback to home.
            builder: (context, state) => const Scaffold(),
            routes: <RouteBase>[
              GoRoute(path: 'player', builder: (context, state) => player),
            ],
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  return MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: waxLocalizationsDelegates,
    supportedLocales: waxSupportedLocales,
  );
}

void main() {
  group('the music face', () {
    testWidgets('carries the transport the old screen never had', (
      tester,
    ) async {
      final repo = FakeRepository(items: [_track(_first, 'Salt Harbour')]);
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
        item: _track(_first, 'Salt Harbour'),
      );

      for (final id in <String>[
        SemanticsIds.playerPrevious,
        SemanticsIds.playerNext,
        SemanticsIds.playerShuffle,
        SemanticsIds.playerRepeat,
        SemanticsIds.playerQueue,
      ]) {
        expect(find.bySemanticsIdentifier(id), findsOneWidget, reason: id);
      }
      await harness.endPlayback(tester);
    });

    testWidgets('shuffle and repeat drive the queue, not the engine', (
      tester,
    ) async {
      final repo = FakeRepository(items: [_track(_first, 'Salt Harbour')]);
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
        item: _track(_first, 'Salt Harbour'),
      );

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerShuffle));
      await tester.pumpAndSettle();
      expect(harness.container.read(queueControllerProvider).shuffled, isTrue);

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerRepeat));
      await tester.pumpAndSettle();
      expect(
        harness.container.read(queueControllerProvider).repeat,
        QueueRepeat.all,
      );
      await harness.endPlayback(tester);
    });

    testWidgets('an advance keeps the same face rather than flashing one', (
      tester,
    ) async {
      // A start publishes the entry first and the session only once the
      // load lands. Reading that window as "not playing yet" put a
      // spinner shell on screen for every track change - a different
      // widget type, so the face and everything it was holding (the
      // hero, the position ticker, the artwork) were torn down and
      // rebuilt. Web hit it on every advance, having no preload.
      final repo = FakeRepository(
        items: [_track(_first, 'Salt Harbour'), _track(_second, 'Gullwing')],
      );
      final engine = FakeEngine();
      final harness = PlayerHarness(
        playbackContainer(repo: repo, engine: engine),
      );
      harness.play([
        _track(_first, 'Salt Harbour'),
        _track(_second, 'Gullwing'),
      ]);
      await pumpPlayerInto(tester, harness);

      final face = find.byType(PlayerFace);
      expect(face, findsOneWidget);
      // The element, not the widget: a rebuild is fine and expected,
      // and a *replacement* is the bug. Identity of the State survives
      // the first and not the second.
      final before = tester.state(face);
      expect(find.text('Salt Harbour'), findsWidgets);

      // The window this is about is the one where the entry is
      // published and the session is not, and against fakes that
      // resolve in a microtask it does not survive to a frame. Held
      // open on purpose, which is also what it is on web: no preload,
      // so every advance loads across the network.
      final gate = Completer<void>();
      engine.loadGate = gate;
      final advancing = harness.playback.next();
      await tester.pump();

      expect(
        face,
        findsOneWidget,
        reason: 'the face stands through the load window',
      );
      expect(tester.state(face), same(before));
      // And it is the outgoing track it stands as, rather than a
      // spinner: the summary is in hand well before the session is.
      expect(find.text('Gullwing'), findsWidgets);

      gate.complete();
      await advancing;
      await tester.pumpAndSettle();

      expect(tester.state(face), same(before));
      expect(find.text('Gullwing'), findsWidgets);
      await harness.endPlayback(tester);
    });

    testWidgets('the up-next peek names what plays next', (tester) async {
      final repo = FakeRepository(
        items: [_track(_first, 'Salt Harbour'), _track(_second, 'Gullwing')],
      );
      final harness = PlayerHarness(
        playbackContainer(repo: repo, engine: FakeEngine()),
      );
      harness.play([
        _track(_first, 'Salt Harbour'),
        _track(_second, 'Gullwing'),
      ]);
      await pumpPlayerInto(tester, harness);

      // The peek draws the title and the artist as one paragraph, so
      // the title is a span rather than a Text of its own.
      expect(
        find.textContaining('Gullwing', findRichText: true),
        findsOneWidget,
      );
      expect(
        tester
            .getSemantics(find.bySemanticsIdentifier(SemanticsIds.playerUpNext))
            .label,
        contains('Gullwing'),
      );
      await harness.endPlayback(tester);
    });

    testWidgets('a queue of one greys next here too, not just on the bar', (
      tester,
    ) async {
      // A row tapped off a shelf queues itself alone, and this face is
      // what the tap opens: gating only the bar behind it left the lit
      // button on the surface the listener is actually looking at.
      final repo = FakeRepository(items: [_track(_first, 'Salt Harbour')]);
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
        item: _track(_first, 'Salt Harbour'),
      );

      final next = find.bySemanticsIdentifier(SemanticsIds.playerNext);
      // A dead control is one that takes no tap, which is what a screen
      // reader and the e2e suite both drive it by.
      bool live() => tester
          .getSemantics(next)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap);

      expect(next, findsOneWidget, reason: 'greyed, not gone');
      expect(live(), isFalse);

      harness.play([
        _track(_first, 'Salt Harbour'),
        _track(_second, 'Gullwing'),
      ]);
      await tester.pumpAndSettle();
      expect(live(), isTrue);
      await harness.endPlayback(tester);
    });

    testWidgets('repeat-one has no next, and the peek says so', (tester) async {
      // The item plays again; the track after it is not what comes next,
      // and naming it is what deriving "next" from the index did.
      final repo = FakeRepository(
        items: [_track(_first, 'Salt Harbour'), _track(_second, 'Gullwing')],
      );
      final harness = PlayerHarness(
        playbackContainer(repo: repo, engine: FakeEngine()),
      );
      harness.play([
        _track(_first, 'Salt Harbour'),
        _track(_second, 'Gullwing'),
      ]);
      harness.container
          .read(queueControllerProvider.notifier)
          .setRepeat(QueueRepeat.one);
      await pumpPlayerInto(tester, harness);

      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerUpNext),
        findsNothing,
      );
      await harness.endPlayback(tester);
    });

    testWidgets('repeat-all wraps, and the peek names the wrap', (
      tester,
    ) async {
      // Standing on the last entry with repeat-all, playback goes back to
      // the first - so there is a next, and a peek that vanished here was
      // telling the listener the queue was about to end.
      final repo = FakeRepository(
        items: [_track(_first, 'Salt Harbour'), _track(_second, 'Gullwing')],
      );
      final harness = PlayerHarness(
        playbackContainer(repo: repo, engine: FakeEngine()),
      );
      harness.play([
        _track(_first, 'Salt Harbour'),
        _track(_second, 'Gullwing'),
      ], startIndex: 1);
      harness.container
          .read(queueControllerProvider.notifier)
          .setRepeat(QueueRepeat.all);
      await pumpPlayerInto(tester, harness);

      expect(
        tester
            .getSemantics(find.bySemanticsIdentifier(SemanticsIds.playerUpNext))
            .label,
        contains('Salt Harbour'),
      );
      // And no count beside it: nothing is left unplayed, which is not
      // the same as nothing being next.
      expect(find.textContaining('left'), findsNothing);
      await harness.endPlayback(tester);
    });

    testWidgets('nothing next means no peek at all', (tester) async {
      final repo = FakeRepository(items: [_track(_first, 'Salt Harbour')]);
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(),
        item: _track(_first, 'Salt Harbour'),
      );

      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerUpNext),
        findsNothing,
      );
      await harness.endPlayback(tester);
    });

    testWidgets('the provenance line says where the queue came from', (
      tester,
    ) async {
      final repo = FakeRepository(items: [_track(_first, 'Salt Harbour')]);
      final harness = PlayerHarness(
        playbackContainer(repo: repo, engine: FakeEngine()),
      );
      harness.play(
        [_track(_first, 'Salt Harbour')],
        source: const QueueSource(
          kind: QueueSourceKind.album,
          label: 'Salt Harbour',
          pid: 'al-01JZX5N8QW3F4V9T2B7KDALBUM1',
        ),
      );
      await pumpPlayerInto(tester, harness);

      expect(find.text('Playing from Salt Harbour'), findsOneWidget);
      await harness.endPlayback(tester);
    });

    testWidgets('a fetched cover names its provider under the hero', (
      tester,
    ) async {
      final repo = FakeRepository(items: [_track(_first, 'Salt Harbour')])
        ..artSource = const ArtSource(
          source: 'enrichment',
          provider: 'coverartarchive',
        );
      final harness = PlayerHarness(
        playbackContainer(repo: repo, engine: FakeEngine()),
      );
      harness.play([_track(_first, 'Salt Harbour')]);
      await pumpPlayerInto(tester, harness);
      // The read is a future, so the mark arrives a frame after the face.
      await tester.pumpAndSettle();

      expect(find.text('From Cover Art Archive'), findsOneWidget);
      await harness.endPlayback(tester);
    });

    testWidgets('a cover the tags carried draws no borrowed note', (
      tester,
    ) async {
      // The other half of the mark: an unattributed cover says nothing
      // at all rather than falling back to a sentence about a person.
      final repo = FakeRepository(items: [_track(_first, 'Salt Harbour')]);
      final harness = PlayerHarness(
        playbackContainer(repo: repo, engine: FakeEngine()),
      );
      harness.play([_track(_first, 'Salt Harbour')]);
      await pumpPlayerInto(tester, harness);
      await tester.pumpAndSettle();

      // The line itself stays - it is held for the session so that a
      // mark arriving later does not resize the cover under it - so what
      // is asserted is that it says nothing rather than that it is gone.
      final caption = tester.widget<ArtworkCaption>(
        find.byType(ArtworkCaption),
      );
      expect(caption.text, isNot(matches(RegExp(r'\p{L}', unicode: true))));
      await harness.endPlayback(tester);
    });
  });

  group('the spoken-word face', () {
    testWidgets('stands through a load window like the music one', (
      tester,
    ) async {
      // Every other half of this face is guarded against the window
      // where the entry is published and the session is not - the
      // chapter seek, the bottom region, the sleep timer. The chip row
      // was not, and each of its four chips drives a live session, so
      // an advance in a podcast queue replaced the whole player with a
      // red box for the length of the resolve. On web that is every
      // advance.
      final first = testItem(
        'tr-01JZX5N8QW3F4V9T2B7KDEP0001',
        mediaType: MediaType.podcast,
      );
      final second = testItem(
        'tr-01JZX5N8QW3F4V9T2B7KDEP0002',
        mediaType: MediaType.podcast,
      );
      final repo = FakeRepository(items: [first, second])
        ..addSubscription(testShow('pc-1'));
      final engine = FakeEngine(mediaDuration: const Duration(minutes: 30));
      final harness = PlayerHarness(
        playbackContainer(repo: repo, engine: engine),
      );
      harness.play([first, second]);
      await pumpPlayerInto(tester, harness);
      expect(find.byType(PlayerFace), findsOneWidget);

      final gate = Completer<void>();
      engine.loadGate = gate;
      final advancing = harness.playback.next();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(PlayerFace), findsOneWidget);

      gate.complete();
      await advancing;
      await tester.pumpAndSettle();
      await harness.endPlayback(tester);
    });

    testWidgets('swaps the transport for interval seeks', (tester) async {
      final repo = FakeRepository()..addSubscription(testShow('pc-1'));
      final episode = testItem(
        'tr-01JZX5N8QW3F4V9T2B7KDEP0001',
        mediaType: MediaType.podcast,
      );
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(minutes: 30)),
        item: episode,
      );

      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerSkipBack),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerSkipForward),
        findsOneWidget,
      );
      // Nothing to skip to and nothing to shuffle: an episode plays on
      // its own, and the controls that would say otherwise are absent
      // rather than disabled.
      expect(find.bySemanticsIdentifier(SemanticsIds.playerNext), findsNothing);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerShuffle),
        findsNothing,
      );
      // And it keeps the controls it had before the rebuild.
      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerSpeed),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerTrim),
        findsOneWidget,
      );
      await harness.endPlayback(tester);
    });

    testWidgets('an episode names its show once, not twice', (tester) async {
      // The overline above the title is the show, and it is a link. An
      // episode's `artist` is the same string, so passing it through as
      // the subtitle drew the show's name again one line down.
      const showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
      final repo = FakeRepository()..addSubscription(testShow(showPid));
      final episode = testEpisode(
        'tr-01JZX5N8QW3F4V9T2B7KDEP0001',
        showPid: showPid,
        // What a feed actually carries: an episode's artist line is the
        // show it came from.
        artist: 'The Prancing Pony Hour',
      );
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(minutes: 30)),
        item: episode,
      );

      expect(find.text('The Prancing Pony Hour'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerShow),
        findsOneWidget,
        reason: 'the one that survives is the tappable one',
      );
      await harness.endPlayback(tester);
    });

    testWidgets('a track still names its artist under the title', (
      tester,
    ) async {
      // The other half of the same rule: a track's maker is named
      // nowhere else on the face, so the subtitle is where it lives.
      final repo = FakeRepository(items: [_track(_first, 'Salt Harbour')]);
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(minutes: 4)),
        item: _track(_first, 'Salt Harbour'),
      );

      expect(find.text('Nightjar'), findsOneWidget);
      await harness.endPlayback(tester);
    });

    testWidgets('a book reaches its chapters', (tester) async {
      final repo = FakeRepository()
        ..books[_bookPid] = testBook(
          _bookPid,
          durationMs: 120000,
          chapters: const [
            ChapterMark(index: 0, title: 'An Unexpected Party', startMs: 0),
            ChapterMark(index: 1, title: 'Roast Mutton', startMs: 60000),
          ],
        );
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(minutes: 2)),
        item: testItem(_bookPid, mediaType: MediaType.audiobook),
      );

      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerChapters),
        findsOneWidget,
      );
      await harness.endPlayback(tester);
    });
  });

  group('the sleep timer', () {
    testWidgets('is offered on music as well as on spoken word', (
      tester,
    ) async {
      final repo = FakeRepository(items: [_track(_first, 'Salt Harbour')]);
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(),
        item: _track(_first, 'Salt Harbour'),
      );

      expect(
        find.bySemanticsIdentifier(SemanticsIds.sleepTimerOpen),
        findsOneWidget,
      );
      await harness.endPlayback(tester);
    });
  });

  // Three ways down, for three ways of arriving: the collapse button,
  // the pull-down, and -- since a mouse has neither a thumb nor a
  // reliable aim for a 40 px button -- Escape and a click off the
  // content.
  group('leaving the player', () {
    testWidgets('offers the keyboard a way down', (tester) async {
      final repo = FakeRepository(items: [_track(_first, 'Salt Harbour')]);
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(),
        item: _track(_first, 'Salt Harbour'),
      );

      // Scoped to the screen, so it is in the registry while the player
      // is up and gone with it -- which is also what puts it in the
      // palette and the shortcut sheet for free.
      harness.container.listen(commandRegistryProvider, (_, _) {});
      await tester.pumpAndSettle();
      expect(
        harness.container.read(commandRegistryProvider).map((c) => c.id),
        contains('player-collapse'),
      );
      await harness.endPlayback(tester);
    });

    testWidgets('Escape takes it back down', (tester) async {
      final repo = FakeRepository(items: [_track(_first, 'Salt Harbour')]);
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(),
        item: _track(_first, 'Salt Harbour'),
        host: _keyboardHost,
      );
      expect(find.byType(PlayerScreen), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsNothing);
      await harness.endPlayback(tester);
    });

    testWidgets('a click leaves the states that have no scaffold', (
      tester,
    ) async {
      // The idle, error, and loading shells are not the scaffold and do
      // not get its islands: they are a glyph and two lines over
      // backdrop, so anything that is not their one button is a way out.
      final harness = PlayerHarness(
        playbackContainer(repo: FakeRepository(), engine: FakeEngine()),
      );
      await pumpPlayerInto(
        tester,
        harness,
        host: (player) => routedHost(player, pushed: true),
      );
      expect(find.byKey(const Key('player-idle')), findsOneWidget);

      await tester.tapAt(const Offset(24, 420));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player-idle')), findsNothing);
    });
  });
}
