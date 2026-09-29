import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
// Override lives here rather than in the root library.
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show UncontrolledProviderScope;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck/src/artwork/artwork_palette.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/l10n/l10n.dart';
import 'package:waxdeck/src/player/player_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/settings/client_prefs.dart';
import 'package:waxdeck/src/shell/commands.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'localized_host.dart';
import 'player_host.dart';
import 'routed_host.dart';

const _first = 'tr-01JZX5N8QW3F4V9T2B7KDMUSIC1';
const _second = 'tr-01JZX5N8QW3F4V9T2B7KDMUSIC2';
const _bookPid = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';

ItemSummary _track(String pid, String title) =>
    testItem(pid, title: title, artist: 'Nightjar');

const _albumPid = 'al-01JZX5N8QW3F4V9T2B7KDALBUM1';

ItemSummary _albumTrack(String pid, String title) => ItemSummary(
  pid: pid,
  mediaType: MediaType.music,
  title: title,
  artist: 'Nightjar',
  albumPid: _albumPid,
  durationMs: 214000,
  artUrl: '/api/v1/items/$pid/art',
);

/// The tracks hold no art of their own; their album holds a front, which
/// the track's own URL already resolves to, a back cover and a booklet.
FakeRepository _albumRepo(List<ItemSummary> tracks) =>
    FakeRepository(items: tracks)
      ..artSource = const ArtSource(
        source: 'enrichment',
        provider: 'coverartarchive',
        level: 'album',
      )
      ..artRolesByPid[_albumPid] = const [
        ArtRoleInfo(
          role: 'front',
          format: 'jpeg',
          source: 'enrichment',
          provider: 'coverartarchive',
        ),
        ArtRoleInfo(role: 'back', format: 'jpeg', source: 'sidecar'),
        ArtRoleInfo(role: 'booklet', format: 'png', source: 'user'),
      ];

Finder get _artwork => find.bySemanticsIdentifier(SemanticsIds.playerArtwork);

String _caption(WidgetTester tester) =>
    tester.widget<ArtworkCaption>(find.byType(ArtworkCaption)).text;

/// Plays [track] and opens the player over it with [extra] overrides.
Future<PlayerHarness> _pumpAlbumTrack(
  WidgetTester tester, {
  FakeRepository? repo,
  List<Override> extra = const <Override>[],
  bool cycle = true,
  bool reducedMotion = false,
  ValueListenable<bool>? ticking,
}) {
  final track = _albumTrack(_first, 'Salt Harbour');
  final fakes = repo ?? _albumRepo([track]);
  final container = playbackContainer(
    repo: fakes,
    engine: FakeEngine(),
    extra: extra,
  );
  if (!cycle) container.read(playerArtworkCycleProvider.notifier).set(false);
  return pumpPlayer(
    tester,
    repo: fakes,
    engine: FakeEngine(),
    item: track,
    container: container,
    host: reducedMotion || ticking != null
        ? (player) => localizedHost(
            Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reducedMotion),
                child: ticking == null
                    ? player
                    : ValueListenableBuilder<bool>(
                        valueListenable: ticking,
                        builder: (context, on, child) =>
                            TickerMode(enabled: on, child: child!),
                        child: player,
                      ),
              ),
            ),
          )
        : null,
  );
}

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
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: appSupportedLocales,
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

      // The cover leads the strip, left of the words that repeat it.
      final peek = find.bySemanticsIdentifier(SemanticsIds.playerUpNext);
      final cover = find.descendant(
        of: peek,
        matching: find.byType(ArtworkImage),
      );
      expect(cover, findsOneWidget);
      expect(
        tester.getTopLeft(cover).dx,
        lessThan(
          tester
              .getTopLeft(
                find.descendant(
                  of: peek,
                  matching: find.textContaining('Gullwing', findRichText: true),
                ),
              )
              .dx,
        ),
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

    // Narrow enough that the chips wrap: their landing is what moved a
    // press aimed at the rate chip.
    Future<void> holdsStill(WidgetTester tester, {double? rate}) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // Large type, where a wider rate is what decides the wrap.
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final first = testEpisode('tr-01JZX5N8QW3F4V9T2B7KDEP0001');
      final second = testEpisode('tr-01JZX5N8QW3F4V9T2B7KDEP0002');
      final repo = FakeRepository()
        ..addSubscription(
          testShow(first.showPid),
          settings: SubscriptionSettings(speed: rate),
        )
        ..episodesByShow[first.showPid] = [first, second];
      for (final episode in [first, second]) {
        repo.episodeDetails[episode.pid] = EpisodeDetail(
          pid: episode.pid,
          mediaType: MediaType.podcast,
          title: episode.title,
          durationMs: 1800000,
          showPid: first.showPid,
          publishedAt: DateTime.utc(2026, 7, 1),
          downloaded: true,
          descriptionHtml: '<p>Notes.</p>',
        );
      }
      final engine = FakeEngine(mediaDuration: const Duration(minutes: 30));
      final harness = PlayerHarness(
        playbackContainer(repo: repo, engine: engine),
      );
      harness.play([first, second]);
      await pumpPlayerInto(tester, harness);
      final transport = find.byType(TransportCluster);
      final row = find
          .ancestor(
            of: find.byType(SleepTimerButton),
            matching: find.byType(Wrap),
          )
          .first;
      final settledTop = tester.getTopLeft(transport).dy;
      final settledRow = tester.getSize(row).height;

      final gate = Completer<void>();
      engine.loadGate = gate;
      final advancing = harness.playback.next();
      await tester.pump();
      expect(tester.getTopLeft(transport).dy, settledTop);
      expect(tester.getSize(row).height, settledRow);

      gate.complete();
      await advancing;
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(transport).dy, settledTop);
      await harness.endPlayback(tester);
    }

    testWidgets('holds its rows still while the session resolves', (
      tester,
    ) async {
      await holdsStill(tester);
    });

    testWidgets('a stored rate keeps the chip row still too', (tester) async {
      await holdsStill(tester, rate: 1.5);
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

  group('the artwork', () {
    testWidgets('a tap turns to the next picture and the last wraps', (
      tester,
    ) async {
      final harness = await _pumpAlbumTrack(tester);

      expect(_caption(tester), 'Front cover: From Cover Art Archive');
      expect(tester.getSemantics(_artwork).label, 'Artwork 1 of 3');
      for (final (caption, label) in <(String, String)>[
        ('Back cover: From a folder image', 'Artwork 2 of 3'),
        ('Booklet: Set by hand', 'Artwork 3 of 3'),
        ('Front cover: From Cover Art Archive', 'Artwork 1 of 3'),
      ]) {
        await tester.tap(_artwork);
        await tester.pumpAndSettle();
        expect(_caption(tester), caption);
        expect(tester.getSemantics(_artwork).label, label);
      }
      // A turn is not a way out, and the accent stays the front's.
      expect(find.byType(PlayerFace), findsOneWidget);
      expect(
        tester.widget<ArtworkAccent>(find.byType(ArtworkAccent)).artUrl,
        '/api/v1/items/$_first/art',
      );
      await harness.endPlayback(tester);
    });

    testWidgets('the next picture is fetched before it is shown', (
      tester,
    ) async {
      final store = FakeArtworkStore();
      final harness = await _pumpAlbumTrack(
        tester,
        extra: [
          artworkStoreProvider.overrideWithValue(store),
          desktopProvider.overrideWithValue(true),
        ],
      );
      // At the size the hero draws, so the warm lands on its rung.
      final hero = tester.getSize(
        find.descendant(of: _artwork, matching: find.byType(ArtworkImage)),
      );
      final px = (hero.width * tester.view.devicePixelRatio).ceil();
      const back = '/api/v1/items/$_albumPid/art?role=back';
      expect(store.warmed, contains((url: back, px: px)));

      await tester.tap(_artwork);
      await tester.pumpAndSettle();
      expect(store.requested, contains(back));
      expect(store.warmed.last, (
        url: '/api/v1/items/$_albumPid/art?role=booklet',
        px: px,
      ));
      await harness.endPlayback(tester);
    });

    testWidgets('an album front beside the track\'s own is the album\'s', (
      tester,
    ) async {
      final repo = _albumRepo([_albumTrack(_first, 'Salt Harbour')])
        ..artRolesByPid[_first] = const [
          ArtRoleInfo(role: 'front', format: 'jpeg', source: 'tag'),
        ]
        ..artRolesByPid[_albumPid] = const [
          ArtRoleInfo(role: 'front', format: 'jpeg', source: 'user'),
        ];
      final harness = await _pumpAlbumTrack(tester, repo: repo);

      expect(_caption(tester), startsWith('Front cover'));
      await tester.tap(_artwork);
      await tester.pumpAndSettle();
      expect(_caption(tester), 'Album cover: Set by hand');
      await harness.endPlayback(tester);
    });

    testWidgets('an album the server refuses is asked about once', (
      tester,
    ) async {
      final repo = _albumRepo([_albumTrack(_first, 'Salt Harbour')])
        ..artRolesErrors[_albumPid] = const WaxDeckApiException(
          code: 'not-found',
          message: 'no such album',
          statusCode: 404,
        );
      final harness = await _pumpAlbumTrack(tester, repo: repo);

      await tester.pump(const Duration(seconds: 15));
      expect(repo.artRolesReads.where((pid) => pid == _albumPid), hasLength(1));
      expect(_artwork, findsNothing);
      await harness.endPlayback(tester);
    });

    testWidgets('a phone fetches the next picture only once one is turned', (
      tester,
    ) async {
      final store = FakeArtworkStore();
      final harness = await _pumpAlbumTrack(
        tester,
        extra: [artworkStoreProvider.overrideWithValue(store)],
      );
      expect(store.warmed, isEmpty);

      await tester.tap(_artwork);
      await tester.pumpAndSettle();
      expect(
        store.warmed.map((w) => w.url),
        contains('/api/v1/items/$_albumPid/art?role=booklet'),
      );
      await harness.endPlayback(tester);
    });

    testWidgets('a narrow caption keeps where the picture came from', (
      tester,
    ) async {
      final harness = await _pumpAlbumTrack(tester);
      ArtworkCaption caption() =>
          tester.widget<ArtworkCaption>(find.byType(ArtworkCaption));

      expect(caption().fallback, 'From Cover Art Archive');
      await tester.tap(_artwork);
      await tester.pumpAndSettle();
      expect(caption().fallback, 'From a folder image');
      await harness.endPlayback(tester);
    });

    testWidgets('a track with no cover opens on the picture it has', (
      tester,
    ) async {
      final repo = _albumRepo([_albumTrack(_first, 'Salt Harbour')])
        ..artSource = null
        ..artRolesByPid[_albumPid] = const [
          ArtRoleInfo(role: 'back', format: 'jpeg', source: 'user'),
        ];
      final store = FakeArtworkStore();
      final harness = await _pumpAlbumTrack(
        tester,
        repo: repo,
        extra: [artworkStoreProvider.overrideWithValue(store)],
      );

      expect(_artwork, findsNothing);
      expect(_caption(tester), 'Back cover: Set by hand');
      expect(
        store.requested,
        contains('/api/v1/items/$_albumPid/art?role=back'),
      );
      await harness.endPlayback(tester);
    });

    testWidgets('one picture is a picture, not a control', (tester) async {
      final repo = _albumRepo([_albumTrack(_first, 'Salt Harbour')])
        ..artRolesByPid[_albumPid] = const [
          ArtRoleInfo(
            role: 'front',
            format: 'jpeg',
            source: 'enrichment',
            provider: 'coverartarchive',
          ),
        ];
      final harness = await _pumpAlbumTrack(
        tester,
        repo: repo,
        extra: [desktopProvider.overrideWithValue(true)],
      );

      expect(_artwork, findsNothing);
      // The line it always drew, with no slot named.
      expect(_caption(tester), 'From Cover Art Archive');
      await tester.pump(const Duration(seconds: 30));
      expect(_caption(tester), 'From Cover Art Archive');
      await harness.endPlayback(tester);
    });

    testWidgets('a desktop turns them itself, and a tap restarts the wait', (
      tester,
    ) async {
      final harness = await _pumpAlbumTrack(
        tester,
        extra: [desktopProvider.overrideWithValue(true)],
      );

      await tester.pump(const Duration(seconds: 15));
      expect(_caption(tester), startsWith('Back cover'));

      await tester.pump(const Duration(seconds: 10));
      await tester.tap(_artwork);
      await tester.pump();
      expect(_caption(tester), startsWith('Booklet'));
      await tester.pump(const Duration(seconds: 14));
      expect(_caption(tester), startsWith('Booklet'));
      await tester.pump(const Duration(seconds: 1));
      expect(_caption(tester), startsWith('Front cover'));
      await harness.endPlayback(tester);
    });

    testWidgets('switched off, it waits for a tap', (tester) async {
      final harness = await _pumpAlbumTrack(
        tester,
        extra: [desktopProvider.overrideWithValue(true)],
        cycle: false,
      );

      await tester.pump(const Duration(seconds: 30));
      expect(_caption(tester), startsWith('Front cover'));
      await tester.tap(_artwork);
      await tester.pump();
      expect(_caption(tester), startsWith('Back cover'));
      await harness.endPlayback(tester);
    });

    testWidgets('under reduced motion, it waits for a tap', (tester) async {
      final harness = await _pumpAlbumTrack(
        tester,
        extra: [desktopProvider.overrideWithValue(true)],
        reducedMotion: true,
      );

      await tester.pump(const Duration(seconds: 30));
      expect(_caption(tester), startsWith('Front cover'));
      await tester.tap(_artwork);
      await tester.pump();
      expect(_caption(tester), startsWith('Back cover'));
      await harness.endPlayback(tester);
    });

    testWidgets('a player nobody can see holds its picture', (tester) async {
      final ticking = ValueNotifier(true);
      addTearDown(ticking.dispose);
      final harness = await _pumpAlbumTrack(
        tester,
        extra: [desktopProvider.overrideWithValue(true)],
        ticking: ticking,
      );

      // How the mini window keeps the stack behind it.
      ticking.value = false;
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      expect(_caption(tester), startsWith('Front cover'));

      ticking.value = true;
      await tester.pump();
      await tester.pump(const Duration(seconds: 15));
      expect(_caption(tester), startsWith('Back cover'));
      await harness.endPlayback(tester);
    });

    testWidgets('a phone never turns them itself', (tester) async {
      final harness = await _pumpAlbumTrack(tester);

      await tester.pump(const Duration(seconds: 30));
      expect(_caption(tester), startsWith('Front cover'));
      await harness.endPlayback(tester);
    });

    // Through the app's own navigators: the player is pushed onto the
    // signed-in one, a sheet opens over it there, and a dialog (the
    // command palette, a confirm) opens on the root above both.
    testWidgets('nothing turns under a dialog or a sheet', (tester) async {
      final track = _albumTrack(_first, 'Salt Harbour');
      final repo = _albumRepo([track])
        ..sessionState = const SessionState(
          authenticated: true,
          user: WaxDeckUser(
            id: 'us-01JZX5N8QW3F4V9T2B7KDLISTEN',
            username: 'listener',
          ),
        );
      final container = playbackContainer(
        repo: repo,
        engine: FakeEngine(),
        extra: [
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
          desktopProvider.overrideWithValue(true),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const WaxDeckApp(),
        ),
      );
      await tester.pumpAndSettle();
      final harness = PlayerHarness(container)..play([track]);
      unawaited(container.read(routerProvider).push(WaxRoute.nowPlaying));
      await tester.pumpAndSettle();
      expect(_caption(tester), startsWith('Front cover'));

      for (final open in <Future<void> Function(BuildContext)>[
        (context) => showDialog<void>(
          context: context,
          builder: (_) => const Text('over the player'),
        ),
        (context) => showWaxSheet<void>(
          context: context,
          builder: (_) => const Text('over the player'),
        ),
      ]) {
        unawaited(open(tester.element(find.byType(PlayerFace))));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 30));
        Navigator.of(tester.element(find.text('over the player'))).pop();
        await tester.pumpAndSettle();
        expect(_caption(tester), startsWith('Front cover'));
      }

      await tester.pump(const Duration(seconds: 15));
      expect(_caption(tester), startsWith('Back cover'));
      await harness.endPlayback(tester);
      // The app's own queue-save debounce, which the test outlives.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the control stays put while the next track answers', (
      tester,
    ) async {
      final first = _albumTrack(_first, 'Salt Harbour');
      final second = _albumTrack(_second, 'Gullwing');
      final repo = _albumRepo([first, second]);
      final held = Completer<void>();
      repo.artRolesGates[_second] = held;
      final harness = PlayerHarness(
        playbackContainer(repo: repo, engine: FakeEngine()),
      );
      harness.play([first, second]);
      await pumpPlayerInto(tester, harness);
      final control = find.byWidgetPredicate(
        (w) => w is WaxTappable && w.semanticsId == SemanticsIds.playerArtwork,
      );
      final before = tester.state(control);

      await harness.playback.next();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Gullwing'), findsWidgets);
      expect(tester.state(control), same(before));

      held.complete();
      await tester.pumpAndSettle();
      expect(tester.state(control), same(before));
      expect(tester.getSemantics(_artwork).label, 'Artwork 1 of 3');
      await harness.endPlayback(tester);
    });

    testWidgets('nothing turns while the next set is unknown', (tester) async {
      final first = _albumTrack(_first, 'Salt Harbour');
      final second = _albumTrack(_second, 'Gullwing');
      final repo = _albumRepo([first, second]);
      final held = Completer<void>();
      repo.artRolesGates[_second] = held;
      final harness = PlayerHarness(
        playbackContainer(
          repo: repo,
          engine: FakeEngine(),
          extra: [desktopProvider.overrideWithValue(true)],
        ),
      );
      harness.play([first, second]);
      await pumpPlayerInto(tester, harness);

      await harness.playback.next();
      await tester.pump();
      await tester.pump(const Duration(seconds: 20));
      held.complete();
      await tester.pump();
      await tester.pump();
      expect(_caption(tester), startsWith('Front cover'));
      expect(tester.getSemantics(_artwork).label, 'Artwork 1 of 3');
      await harness.endPlayback(tester);
    });

    testWidgets('a tap before the next set answers is not kept', (
      tester,
    ) async {
      final first = _albumTrack(_first, 'Salt Harbour');
      final second = _albumTrack(_second, 'Gullwing');
      final repo = _albumRepo([first, second]);
      final held = Completer<void>();
      repo.artRolesGates[_second] = held;
      final harness = PlayerHarness(
        playbackContainer(repo: repo, engine: FakeEngine()),
      );
      harness.play([first, second]);
      await pumpPlayerInto(tester, harness);

      await harness.playback.next();
      await tester.pump();
      await tester.tap(_artwork);
      await tester.pump();
      expect(tester.getSemantics(_artwork).label, 'Artwork 1 of 3');
      held.complete();
      await tester.pumpAndSettle();
      expect(_caption(tester), startsWith('Front cover'));
      expect(tester.getSemantics(_artwork).label, 'Artwork 1 of 3');
      await harness.endPlayback(tester);
    });

    testWidgets('a new album starts its pictures again at the front', (
      tester,
    ) async {
      const otherAlbum = 'al-01JZX5N8QW3F4V9T2B7KDALBUM2';
      final onFirst = _albumTrack(_first, 'Salt Harbour');
      final onOther = ItemSummary(
        pid: _first,
        mediaType: MediaType.music,
        title: 'Salt Harbour',
        artist: 'Nightjar',
        albumPid: otherAlbum,
        durationMs: 214000,
        artUrl: '/api/v1/items/$_first/art',
      );
      final repo = _albumRepo([onFirst])
        ..artRolesByPid[otherAlbum] = const [
          ArtRoleInfo(role: 'back', format: 'jpeg', source: 'user'),
          ArtRoleInfo(role: 'disc', format: 'png', source: 'user'),
        ];
      final container = playbackContainer(repo: repo, engine: FakeEngine());
      Future<void> show(ItemSummary item) async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: localizedHost(PlayerFace(session: null, item: item)),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(onFirst);
      await tester.tap(_artwork);
      await tester.pump();
      await tester.tap(_artwork);
      await tester.pumpAndSettle();
      expect(_caption(tester), startsWith('Booklet'));

      await show(onOther);
      expect(_caption(tester), startsWith('Front cover'));
    });

    testWidgets('the next track starts at its front cover', (tester) async {
      final first = _albumTrack(_first, 'Salt Harbour');
      final second = _albumTrack(_second, 'Gullwing');
      final harness = PlayerHarness(
        playbackContainer(
          repo: _albumRepo([first, second]),
          engine: FakeEngine(),
        ),
      );
      harness.play([first, second]);
      await pumpPlayerInto(tester, harness);

      await tester.tap(_artwork);
      await tester.pumpAndSettle();
      expect(_caption(tester), startsWith('Back cover'));

      await harness.playback.next();
      await tester.pumpAndSettle();
      expect(find.text('Gullwing'), findsWidgets);
      expect(_caption(tester), startsWith('Front cover'));
      expect(tester.getSemantics(_artwork).label, 'Artwork 1 of 3');
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
