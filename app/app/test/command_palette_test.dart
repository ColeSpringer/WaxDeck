import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/l10n/l10n.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/player/output_volume.dart';
import 'package:waxdeck/src/player/player_screen.dart';
import 'package:waxdeck/src/player/waveform.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck/src/search/search_controller.dart';
import 'package:waxdeck/src/settings/settings_registry.dart';
import 'package:waxdeck/src/shell/command_palette.dart';
import 'package:waxdeck/src/shell/commands.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/side_panel.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';

const _albumPid = 'al-01JZX5N8QW3F4V9T2B7KDALBUM1';
const _trackPid = 'tr-01JZX5N8QW3F4V9T2B7KDTRACK1';
const _showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
const _episodePid = 'tr-01JZX5N8QW3F4V9T2B7KDEPS001';

const _admin = WaxDeckUser(
  id: 'us-1',
  username: 'admin',
  roles: ['admin'],
  uploadEnabled: true,
);

/// What a test holds on to: the container playback lives in, and the
/// engine underneath it.
class _Shell {
  _Shell(this.container, this.repo, this.engine);

  final ProviderContainer container;
  final FakeRepository repo;
  final FakeEngine engine;

  String get location => container
      .read(routerProvider)
      .routerDelegate
      .currentConfiguration
      .uri
      .toString();
}

/// Mounts the whole app, which is what puts the keyboard map on the tree:
/// the bindings live in the shell, so a screen hosted on its own would
/// prove nothing about them.
Future<_Shell> _pumpShell(
  WidgetTester tester, {
  Size size = const Size(1200, 900),
  bool localVolume = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = FakeRepository(
    sessionState: const SessionState(authenticated: true, user: _admin),
    items: <ItemSummary>[testItem(_trackPid)],
  );
  final engine = FakeEngine();
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      audioEngineProvider.overrideWithValue(engine),
      // The platform gate on the volume keys. flutter_test pins the
      // target platform to Android, which is the half that deliberately
      // has no software level, so a test about the keys says which
      // machine it is standing on.
      localVolumeAvailableProvider.overrideWithValue(localVolume),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MediaQuery(
        data: MediaQueryData.fromView(
          tester.view,
        ).copyWith(disableAnimations: true),
        child: const WaxDeckApp(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Shell(container, repo, engine);
}

/// Plays one track, the way a row tap does.
Future<void> _play(WidgetTester tester, _Shell shell) async {
  final item = testItem(_trackPid);
  shell.container.read(nowPlayingProvider.notifier).play(
    <ItemSummary>[item, testItem('tr-second', title: 'Second')],
    source: const QueueSource(
      kind: QueueSourceKind.album,
      label: 'An album',
      pid: _albumPid,
    ),
  );
  await tester.pumpAndSettle();
}

/// Ends playback the way "Clear queue" does, so no session is left
/// checkpointing into a torn-down test. The second beat is long enough
/// for the queue's save debounce and Connect's report settle, both of
/// which outlive the widget tree otherwise.
Future<void> _stop(WidgetTester tester, _Shell shell) async {
  shell.container.read(queueControllerProvider.notifier).clear();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _chord(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

Future<void> _openPalette(WidgetTester tester) =>
    _chord(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyK);

/// Enter, as the field receives it: a physical return key reaches a text
/// field through the input connection rather than through the key
/// dispatcher, so this is what a submit is in a widget test.
Future<void> _submit(WidgetTester tester) async {
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(
    find.bySemanticsIdentifier(SemanticsIds.commandPaletteField),
    text,
  );
  // Past the palette's debounce, so the library half has been asked.
  await tester.pump(PaletteQueryController.debounce);
  await tester.pumpAndSettle();
}

Finder _row(String id) =>
    find.bySemanticsIdentifier(SemanticsIds.commandPaletteEntry(id));

void main() {
  test('every standing command is named in both languages', () async {
    // The standing list is declared above every BuildContext, so its
    // names live in a table keyed on the id, and nothing in Dart ties
    // the two. A command added to one and not the other draws its id.
    for (final locale in <String>['en', 'es']) {
      final l10n = await AppLocalizations.delegate.load(Locale(locale));
      for (final command in waxStandingCommands) {
        final label = commandLabel(l10n, command);
        expect(
          label,
          isNot(command.id),
          reason: '$locale: ${command.id} falls back to its own id',
        );
        expect(label.trim(), isNotEmpty);
      }
    }
  });

  testWidgets('space plays and pauses what is on the deck bar', (tester) async {
    final shell = await _pumpShell(tester);
    await _play(tester, shell);
    expect(shell.engine.playing, isTrue);

    await _press(tester, LogicalKeyboardKey.space);
    expect(shell.engine.playing, isFalse);

    await _press(tester, LogicalKeyboardKey.space);
    expect(shell.engine.playing, isTrue);

    await _stop(tester, shell);
  });

  testWidgets('space belongs to the control that has focus', (tester) async {
    final shell = await _pumpShell(tester);
    await _play(tester, shell);

    // Tab into the chrome. Whatever it lands on is one of the design
    // system's tappables, and a space is how a keyboard presses those:
    // the transport must not take it out of their hands (WCAG 2.1.1).
    await _press(tester, LogicalKeyboardKey.tab);
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(
      focused != null && Actions.maybeFind<ActivateIntent>(focused) != null,
      isTrue,
      reason: 'tab landed on nothing pressable, so this proves nothing',
    );

    await _press(tester, LogicalKeyboardKey.space);
    expect(shell.engine.playing, isTrue);

    await _stop(tester, shell);
  });

  testWidgets('the keyboard is live on the overlays too', (tester) async {
    // The player, the queue and the rest are pushed onto the signed-in
    // navigator rather than into the shell, so a map mounted inside the
    // shell would be their sibling and dead on all of them.
    final shell = await _pumpShell(tester);
    await _play(tester, shell);
    shell.container.read(routerProvider).push<void>(WaxRoute.nowPlaying);
    await tester.pumpAndSettle();
    expect(find.byType(PlayerScreen), findsOne);

    await _press(tester, LogicalKeyboardKey.space);
    expect(shell.engine.playing, isFalse);

    await _openPalette(tester);
    expect(find.bySemanticsIdentifier(SemanticsIds.commandPalette), findsOne);
    await _press(tester, LogicalKeyboardKey.escape);

    await _stop(tester, shell);
  });

  testWidgets('the keyboard drives the transport', (tester) async {
    final shell = await _pumpShell(tester, localVolume: true);
    await _play(tester, shell);
    final queue = shell.container.read(queueControllerProvider);
    expect(queue.currentIndex, 0);

    await _chord(
      tester,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.arrowRight,
    );
    expect(shell.container.read(queueControllerProvider).currentIndex, 1);

    await _chord(
      tester,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.arrowLeft,
    );
    expect(shell.container.read(queueControllerProvider).currentIndex, 0);

    // The keyboard's own ten seconds, which is neither of the spoken-word
    // skip intervals the deck bar's buttons use.
    await _chord(
      tester,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.arrowRight,
    );
    expect(shell.engine.position, kKeyboardSeek);

    await _chord(
      tester,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.arrowLeft,
    );
    expect(shell.engine.position, Duration.zero);

    final level = shell.engine.volume;
    await _chord(
      tester,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.arrowDown,
    );
    expect(shell.engine.volume, closeTo(level - kVolumeStep, 0.001));

    await _press(tester, LogicalKeyboardKey.keyM);
    expect(shell.engine.volume, 0);
    await _press(tester, LogicalKeyboardKey.keyM);
    expect(shell.engine.volume, greaterThan(0));

    await _stop(tester, shell);
  });

  testWidgets('q opens the queue where the window keeps it', (tester) async {
    final shell = await _pumpShell(tester);
    await _play(tester, shell);
    expect(shell.container.read(sidePanelProvider), isNull);

    await _press(tester, LogicalKeyboardKey.keyQ);
    expect(shell.container.read(sidePanelProvider), WaxPanel.queue);

    await _press(tester, LogicalKeyboardKey.keyQ);
    expect(shell.container.read(sidePanelProvider), isNull);

    await _stop(tester, shell);
  });

  testWidgets('a bound letter typed into a field is a letter', (tester) async {
    final shell = await _pumpShell(tester);
    shell.container.read(routerProvider).go(WaxRoute.search);
    await tester.pumpAndSettle();

    // The search screen autofocuses its own field, which is the state
    // the guard exists for.
    await _press(tester, LogicalKeyboardKey.keyQ);
    expect(shell.container.read(sidePanelProvider), isNull);

    // The palette is the exception: no field can receive Ctrl+K as text,
    // and being reachable from the caret is the whole point of it.
    await _openPalette(tester);
    expect(find.bySemanticsIdentifier(SemanticsIds.commandPalette), findsOne);
  });

  testWidgets('the palette opens, runs a command, and closes', (tester) async {
    final shell = await _pumpShell(tester);
    await _play(tester, shell);

    await _openPalette(tester);
    expect(find.bySemanticsIdentifier(SemanticsIds.commandPalette), findsOne);

    // Esc closes it, which is the other half of the contract.
    await _press(tester, LogicalKeyboardKey.escape);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.commandPalette),
      findsNothing,
    );

    await _openPalette(tester);
    await _type(tester, 'show the queue');
    // Enter runs the first result, with nothing touched.
    await _submit(tester);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.commandPalette),
      findsNothing,
    );
    expect(shell.container.read(sidePanelProvider), WaxPanel.queue);

    await _stop(tester, shell);
  });

  testWidgets('a queue a station parked is not up for the keys or the '
      'palette', (tester) async {
    final shell = await _pumpShell(tester);
    await _play(tester, shell);
    const commands = <(String, String)>[
      ('play or pause', 'cmd-play-pause'),
      ('next track', 'cmd-next'),
      ('previous track', 'cmd-previous'),
    ];
    Future<void> expectRows(Matcher matcher) async {
      await _openPalette(tester);
      for (final (query, row) in commands) {
        await _type(tester, query);
        expect(_row(row), matcher, reason: row);
      }
      await _press(tester, LogicalKeyboardKey.escape);
    }

    // Offered while the item is up, so their absence below is the park's.
    await expectRows(findsOne);

    final station = RadioStation(
      pid: 'rs-1',
      name: 'Coastal FM',
      streamUrl: 'https://radio.example/stream',
      createdAt: DateTime.utc(2026, 7, 1),
    );
    shell.repo.radioStationsByPid['rs-1'] = station;
    final radio = shell.container.read(radioPlaybackProvider.notifier);
    await radio.play(station);
    await tester.pumpAndSettle();
    await radio.stop();
    await tester.pumpAndSettle();
    final loads = shell.engine.loadedUrls.length;

    await expectRows(findsNothing);
    await _press(tester, LogicalKeyboardKey.space);
    expect(shell.engine.loadedUrls, hasLength(loads));
    expect(shell.engine.playing, isFalse);

    await _stop(tester, shell);
  });

  testWidgets('the palette names the key a command answers to', (tester) async {
    final shell = await _pumpShell(tester);
    await _play(tester, shell);

    await _openPalette(tester);
    await _type(tester, 'next track');
    expect(_row('cmd-next'), findsOne);
    // The chord, spelled for the platform under the test.
    expect(find.text('Ctrl →'), findsOne);

    await _stop(tester, shell);
  });

  testWidgets('the palette offers places, the library, and settings', (
    tester,
  ) async {
    final shell = await _pumpShell(tester);
    shell.repo.searchResults['night'] = SearchResults(
      query: 'night',
      albums: <SearchHit>[
        SearchHit(
          pid: _albumPid,
          kind: 'album',
          title: 'Night Music',
          subtitle: 'The Bree Trio',
        ),
      ],
    );

    await _openPalette(tester);
    await _type(tester, 'night');
    expect(_row('hit-$_albumPid'), findsOne);
    // The cap is not silent: the last row hands the rest to the screen
    // that can show them all.
    expect(_row('search-all'), findsOne);

    await _type(tester, 'podcasts');
    expect(_row('go-podcasts'), findsOne);

    // Running a settings row lands on the section, carrying the setting
    // id so the row is marked and scrolled to - the same deep link the
    // settings screen's own results mint.
    await _type(tester, 'theme');
    expect(_row('set-theme'), findsOne);
    await tester.tap(_row('set-theme'));
    await tester.pumpAndSettle();
    expect(
      shell.location,
      WaxRoute.settingsSection(SettingsSection.appearance, setting: 'theme'),
    );
  });

  testWidgets('the palette lists Books on a library with no books', (
    tester,
  ) async {
    await _pumpShell(tester);

    await _openPalette(tester);
    await _type(tester, 'books');
    expect(_row('go-books'), findsOne);
  });

  testWidgets('two indexes of one name say which hub they are under', (
    tester,
  ) async {
    await _pumpShell(tester);

    await _openPalette(tester);
    await _type(tester, 'gen');
    expect(
      find.descendant(of: _row('go-genres'), matching: find.text('In Music')),
      findsOne,
    );
    expect(
      find.descendant(
        of: _row('go-bookGenres'),
        matching: find.text('In Books'),
      ),
      findsOne,
    );
    // A destination with no hub above it keeps its plain detail.
    await _type(tester, 'books');
    expect(
      find.descendant(of: _row('go-books'), matching: find.text('Go to')),
      findsOne,
    );
  });

  testWidgets('the palette leads with the album named as the query', (
    tester,
  ) async {
    // The groups come in turn, artists first, so an artist merely
    // starting with the query would sit above the album that is the query.
    // What the server marks as the name asked for goes first, and goes
    // once.
    final shell = await _pumpShell(tester);
    const artistPid = 'ar-01JZX5N8QW3F4V9T2B7KDARTST1';
    shell.repo.searchResults['heroes'] = SearchResults(
      query: 'heroes',
      artists: <SearchHit>[
        SearchHit(pid: artistPid, kind: 'artist', title: 'Heroes del Silencio'),
      ],
      albums: <SearchHit>[
        SearchHit(pid: _albumPid, kind: 'album', title: 'Heroes', exact: true),
      ],
      tracks: <SearchHit>[
        SearchHit(pid: _trackPid, kind: 'track', title: 'Heroes Medley'),
      ],
    );

    await _openPalette(tester);
    await _type(tester, 'heroes');

    double at(String id) => tester.getTopLeft(_row(id)).dy;
    expect(_row('hit-$_albumPid'), findsOne);
    expect(at('hit-$_albumPid'), lessThan(at('hit-$artistPid')));
    expect(at('hit-$artistPid'), lessThan(at('hit-$_trackPid')));
  });

  testWidgets('an exact album past the cut still leads the palette', (
    tester,
  ) async {
    // Three hits of every kind, and the round-robin takes eight, two deep,
    // so it never reached the third album. The one the server names exact
    // leads, and the rest is what the round-robin took, short by the last
    // row, which the lead made room for.
    final shell = await _pumpShell(tester);
    List<SearchHit> hits(String prefix, String kind, {int exact = -1}) => [
      for (var i = 0; i < 3; i++)
        SearchHit(
          pid: '$prefix-0$i',
          kind: kind,
          title: '$kind $i',
          exact: i == exact,
        ),
    ];
    shell.repo.searchResults['moon'] = SearchResults(
      query: 'moon',
      artists: hits('ar', 'artist'),
      albums: hits('al', 'album', exact: 2),
      tracks: hits('tr', 'track'),
      books: hits('bk', 'book'),
      episodes: hits('ep', 'episode'),
    );

    await _openPalette(tester);
    await _type(tester, 'moon');

    // Read off the palette's own groups: a row past the dialog's height is
    // not built, and what is being pinned is what it was handed.
    final palette = tester.widget<WaxCommandPalette>(
      find.byType(WaxCommandPalette),
    );
    expect(
      [
        for (final group in palette.groups)
          for (final entry in group.entries)
            if (entry.id.startsWith('hit-')) entry.id,
      ],
      [
        'hit-al-02',
        'hit-ar-00',
        'hit-al-00',
        'hit-tr-00',
        'hit-bk-00',
        'hit-ep-00',
        'hit-ar-01',
        'hit-al-01',
      ],
    );
  });

  testWidgets('an exact artist leads an exact album', (tester) async {
    final shell = await _pumpShell(tester);
    shell.repo.searchResults['heroes'] = SearchResults(
      query: 'heroes',
      artists: <SearchHit>[
        SearchHit(pid: 'ar-01', kind: 'artist', title: 'Heroes del Silencio'),
        SearchHit(pid: 'ar-02', kind: 'artist', title: 'Heroes', exact: true),
      ],
      albums: <SearchHit>[
        SearchHit(pid: 'al-01', kind: 'album', title: 'Heroes', exact: true),
      ],
    );

    await _openPalette(tester);
    await _type(tester, 'heroes');

    double at(String pid) => tester.getTopLeft(_row('hit-$pid')).dy;
    expect(at('ar-02'), lessThan(at('ar-01')));
    expect(at('ar-02'), lessThan(at('al-01')));
    // Taken once: the exact artist is not listed again among the artists.
    expect(_row('hit-ar-02'), findsOne);
  });

  testWidgets('a hit opens over what the palette was opened from', (
    tester,
  ) async {
    // Every hit is pushed, the episode included. It is the show-less
    // `/episodes/:pid`, declared beside the podcasts hub rather than
    // beneath it, so going to it would put the visitor in that branch
    // with nothing under the screen - and would throw away whatever the
    // palette was opened over.
    final shell = await _pumpShell(tester);
    // A real episode behind the hit, so the screen that opens is the one
    // it names rather than an error pane.
    shell.repo
      ..addSubscription(testShow(_showPid))
      ..episodesByShow[_showPid] = <EpisodeSummary>[
        testEpisode(_episodePid, showPid: _showPid, title: 'Nightjar Weekly'),
      ]
      ..searchResults['nightjar'] = SearchResults(
        query: 'nightjar',
        episodes: <SearchHit>[
          SearchHit(
            pid: _episodePid,
            kind: 'episode',
            title: 'Nightjar Weekly',
            subtitle: 'The Prancing Pony Hour',
          ),
        ],
      );
    shell.container.read(routerProvider).go(WaxRoute.radio);
    await tester.pumpAndSettle();

    await _openPalette(tester);
    await _type(tester, 'nightjar');
    await tester.tap(_row('hit-$_episodePid'));
    await tester.pumpAndSettle();

    // Pushed: there is something underneath to come back to, and the
    // address bar still names the surface that is under it.
    expect(shell.container.read(routerProvider).canPop(), isTrue);
    expect(shell.location, WaxRoute.radio);
  });

  testWidgets('the palette tunes a station the library search cannot find', (
    tester,
  ) async {
    // Stations are their own list rather than search hits, and tuning one
    // is what reaching it means: there is no per-station location to go
    // to, and the hub's dial plays what it is pointed at.
    final shell = await _pumpShell(tester);
    shell.repo.radioStationsByPid['rs-1'] = RadioStation(
      pid: 'rs-1',
      name: 'Nightjar FM',
      streamUrl: 'https://stream.example/rs-1',
      createdAt: DateTime.utc(2026, 7, 1),
    );

    await _openPalette(tester);
    await _type(tester, 'nightjar');
    expect(_row('station-rs-1'), findsOne);

    await tester.tap(_row('station-rs-1'));
    await tester.pumpAndSettle();
    expect(shell.container.read(radioPlaybackProvider).station?.pid, 'rs-1');

    await shell.container.read(radioPlaybackProvider.notifier).stop();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the palette hands a library search to the search screen', (
    tester,
  ) async {
    final shell = await _pumpShell(tester);
    await _openPalette(tester);
    await _type(tester, 'night');

    await tester.tap(_row('search-all'));
    await tester.pumpAndSettle();
    expect(shell.location, WaxRoute.searchFor('night'));
    expect(shell.container.read(searchQueryProvider), 'night');
  });

  testWidgets('a screen lends the palette its own commands', (tester) async {
    final shell = await _pumpShell(tester);
    // The release behind the album screen, keyed the way the fake's facet
    // listing answers.
    shell.repo.facetItems['album 1'] = <ItemSummary>[
      ItemSummary(
        pid: _trackPid,
        mediaType: MediaType.music,
        title: 'Opening',
        artist: 'The Bree Trio',
        album: 'Gullwing',
        albumPid: 'al-1',
        trackNumber: 1,
        durationMs: 214000,
      ),
    ];
    shell.container
        .read(routerProvider)
        .go(WaxRoute.musicBucket(MusicDimension.albums, 'al-1'));
    await tester.pumpAndSettle();

    await _openPalette(tester);
    await _type(tester, 'shuffle');
    expect(_row('cmd-album-shuffle'), findsOne);
    await _press(tester, LogicalKeyboardKey.escape);

    // The commands leave with the screen: a palette that still offered to
    // shuffle an album nobody is looking at would be offering a stale
    // closure over a list that has been thrown away.
    shell.container.read(routerProvider).go(WaxRoute.home);
    await tester.pumpAndSettle();
    await _openPalette(tester);
    await _type(tester, 'shuffle');
    expect(_row('cmd-album-shuffle'), findsNothing);
  });

  testWidgets('the reference sheet lists what is bound', (tester) async {
    final shell = await _pumpShell(tester);

    // Shift and the slash key, which is the spelling the desktop
    // embedders report and the only one a simulated keyboard can send:
    // there is no physical key behind a bare question mark. The web's
    // spelling is bound beside it.
    await _chord(
      tester,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.slash,
    );
    expect(find.bySemanticsIdentifier(SemanticsIds.shortcutSheet), findsOne);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.shortcutSheetRow('play-pause')),
      findsOne,
    );
    // The last section, which is below the fold on this window: the sheet
    // is a list, and the rows past the bottom of it are reached the way
    // any list's are.
    await tester.scrollUntilVisible(
      find.bySemanticsIdentifier(SemanticsIds.shortcutSheetRow('palette')),
      120,
      // The sheet's own list, named because the page behind the dialog
      // scrolls too.
      scrollable: find
          .descendant(
            of: find.bySemanticsIdentifier(SemanticsIds.shortcutSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.shortcutSheetRow('palette')),
      findsOne,
    );
    // A command with no keystroke teaches nothing here, so it is absent
    // rather than listed with an empty column.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.shortcutSheetRow('cast')),
      findsNothing,
    );

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.shortcutSheetClose),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.shortcutSheet),
      findsNothing,
    );
    expect(shell.location, WaxRoute.home);
  });

  testWidgets('the visualizer is offered only where there is a shape', (
    tester,
  ) async {
    // The palette is the third door onto the visualizer, and it used to
    // be gated on anything playing at all - so it could carry a listener
    // to an empty state during a podcast, or during a track no analyze
    // pass has measured. Same gate as the player's own row now.
    final shell = await _pumpShell(tester);
    await _play(tester, shell);

    await _openPalette(tester);
    await _type(tester, 'visual');
    expect(_row('cmd-visualizer'), findsNothing);
    await _press(tester, LogicalKeyboardKey.escape);

    // Measured, so it comes back. `refresh` because the face already
    // read the pending answer for this track.
    shell.repo.waveforms[_trackPid] = Waveform(
      state: 'ready',
      peaks: <int>[for (var i = 0; i < 1000; i++) (i % 200) + 20],
      resolution: 1000,
    );
    shell.container.invalidate(trackWaveformProvider(_trackPid));
    await tester.pumpAndSettle();

    await _openPalette(tester);
    await _type(tester, 'visual');
    expect(_row('cmd-visualizer'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.escape);

    await _stop(tester, shell);
  });

  testWidgets('reopening the palette does not re-read the same peaks', (
    tester,
  ) async {
    // The visualizer gate reads the envelope and the palette is a
    // `showDialog`, so with the player face unmounted each open was the
    // only listener and paid for a fresh read of the same peaks -
    // nothing revalidates them. The playing track's envelope is held
    // for as long as it is playing.
    final shell = await _pumpShell(tester);
    await _play(tester, shell);

    await _openPalette(tester);
    await _type(tester, 'visual');
    await _press(tester, LogicalKeyboardKey.escape);
    expect(shell.repo.waveformCalls, <String>[_trackPid]);

    await _openPalette(tester);
    await _type(tester, 'visual');
    await _press(tester, LogicalKeyboardKey.escape);
    expect(shell.repo.waveformCalls, <String>[_trackPid]);

    await _stop(tester, shell);
  });

  test('every standing command is unique, and every key is spelled', () {
    final ids = <String>{};
    for (final command in waxStandingCommands) {
      expect(ids.add(command.id), isTrue, reason: 'duplicate id ${command.id}');
      for (final activator in command.activators) {
        // The sheet drops what it cannot spell, so a binding of another
        // shape would work while being taught nowhere.
        expect(
          activator,
          isA<SingleActivator>(),
          reason: '${command.id} binds a chord the sheet cannot print',
        );
      }
      if (command.activators.isEmpty) continue;
      expect(command.keys, isNotNull, reason: '${command.id} prints no key');
    }
  });

  test('a chord is spelled the way the platform writes it', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(
      describeActivator(const <ShortcutActivator>[
        SingleActivator(LogicalKeyboardKey.keyK, control: true),
        SingleActivator(LogicalKeyboardKey.keyK, meta: true),
      ]),
      '⌘ K',
    );

    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(
      describeActivator(const <ShortcutActivator>[
        SingleActivator(LogicalKeyboardKey.keyK, control: true),
        SingleActivator(LogicalKeyboardKey.keyK, meta: true),
      ]),
      'Ctrl K',
    );
    expect(
      describeActivator(const <ShortcutActivator>[
        SingleActivator(LogicalKeyboardKey.arrowUp, control: true),
      ]),
      'Ctrl ↑',
    );
  });
}
