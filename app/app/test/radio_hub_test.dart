import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// Override lives here rather than in the root library.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/player/output_volume.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck/src/radio/radio_screen.dart';
import 'package:waxdeck/src/search/search_controller.dart';
import 'package:waxdeck/src/search/search_screen.dart';
import 'package:waxdeck/src/settings/client_settings_providers.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

RadioStation _station(
  String pid, {
  required String name,
  String? logoUrl,
  String? homepageUrl,
}) => RadioStation(
  pid: pid,
  name: name,
  streamUrl: 'https://stream.example/$pid',
  logoUrl: logoUrl,
  homepageUrl: homepageUrl,
  createdAt: DateTime.utc(2026, 7, 1),
);

FakeRepository _repo() {
  // Signed in, because the preference document the dial reads is only
  // fetched for an authenticated session - which is the point of moving
  // favourites onto the account.
  final repo = FakeRepository(
    items: <ItemSummary>[],
    sessionState: const SessionState(
      authenticated: true,
      user: WaxDeckUser(
        id: 'us-1',
        username: 'admin',
        roles: <String>['admin'],
      ),
    ),
  );
  for (final station in <RadioStation>[
    _station('rs-1', name: 'Coastal FM', logoUrl: 'https://coastal/logo.png'),
    _station('rs-2', name: 'Deck Radio'),
    _station('rs-3', name: 'Night Jazz', homepageUrl: 'https://jazz.example'),
  ]) {
    repo.radioStationsByPid[station.pid] = station;
  }
  return repo;
}

ProviderContainer _container(
  FakeRepository repo, {
  FakeEngine? engine,
  FakeArtworkStore? artwork,
  List<Override> extra = const <Override>[],
}) {
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      audioEngineProvider.overrideWithValue(engine ?? FakeEngine()),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      clientSettingsStoreProvider.overrideWithValue(
        MemoryClientSettingsStore(),
      ),
      if (artwork != null) artworkStoreProvider.overrideWithValue(artwork),
      ...extra,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// A repository whose account has [pids] pinned, and which is signed in -
/// the prefs document is only fetched for an authenticated session.
FakeRepository _repoWithFavorites(List<String> pids) {
  final repo = _repo();
  repo.prefs = Prefs(radioFavorites: pids);
  return repo;
}

/// The window's own metrics with animations off.
///
/// A station tile drawn as playing carries the VU needle, which repeats
/// forever - that is the point of it and the end of `pumpAndSettle`.
/// Replacing the whole [MediaQueryData] instead would wipe the size the
/// size class reads, and every grid would draw one column.
Widget _reducedMotion(Widget child) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: child,
  ),
);

Future<void> _pumpHub(
  WidgetTester tester,
  ProviderContainer container, {
  Size size = const Size(1200, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: routedHost(_reducedMotion(const RadioScreen())),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _byId(String id) => find.bySemanticsIdentifier(id);

void main() {
  testWidgets('the grid lists every station and the dial only the pinned', (
    tester,
  ) async {
    final container = _container(_repoWithFavorites(<String>['rs-2']));
    await _pumpHub(tester, container);

    // Every station is a row in the grid, which is the primary surface and
    // the one carrying the semantics.
    expect(find.text('Coastal FM'), findsOneWidget);
    expect(find.text('Deck Radio'), findsWidgets);
    expect(find.text('Night Jazz'), findsOneWidget);

    // The dial holds the one pinned station.
    expect(_byId(SemanticsIds.radioDial), findsOneWidget);
    expect(container.read(radioDialProvider).map((s) => s.pid), ['rs-2']);

    // The logo band is decoration: the grid below has a row per station, so
    // twelve circular logos in the traversal order buy nothing and cost the
    // way out of them. The one tune control is not excluded, because it is
    // one control rather than twelve.
    expect(_byId(SemanticsIds.radioTune), findsOneWidget);
  });

  testWidgets('a station logo is asked for through the proxy, never the '
      'station host', (tester) async {
    final repo = _repo();
    final artwork = FakeArtworkStore();
    await _pumpHub(tester, _container(repo, artwork: artwork));

    final cards = tester.widgetList<MediaCard>(find.byType(MediaCard)).toList();
    final coastal = cards.firstWhere((c) => c.data.title == 'Coastal FM');
    // Asked for at all, and asked for through the proxy: the station's own
    // URL is what an edit form shows and what the server fetches from, and
    // drawing it directly fails browser CORS, is mixed content on an https
    // page, and hands the listener's IP to a stranger's host.
    expect(coastal.data.artwork, isNotNull);
    expect(
      artwork.requested,
      contains(repo.radioLogoUrlFor('rs-1')),
      reason: 'the logo is fetched from this origin, not from the station',
    );
    expect(
      artwork.requested.any((url) => url.startsWith('https://coastal')),
      isFalse,
    );

    // A station with no logo asks for nothing at all, rather than spending
    // a 404 per paint to learn what the row already knows.
    final deck = cards.firstWhere((c) => c.data.title == 'Deck Radio');
    expect(deck.data.artwork, isNull);
  });

  testWidgets('pinning puts a station on the dial and unpinning takes it '
      'off', (tester) async {
    final repo = _repo();
    final container = _container(repo);
    await _pumpHub(tester, container);

    expect(container.read(radioDialProvider), isEmpty);
    expect(_byId(SemanticsIds.radioDial), findsNothing);

    await tester.tap(_byId(SemanticsIds.radioFavorite('rs-1')));
    await tester.pumpAndSettle();
    expect(container.read(radioDialProvider).map((s) => s.pid), ['rs-1']);
    expect(_byId(SemanticsIds.radioDial), findsOneWidget);
    // Per account, so the pin is on the phone too and signing out takes it
    // with the account rather than leaving it on a shared machine.
    expect(repo.prefs.radioFavorites, ['rs-1']);

    await tester.tap(_byId(SemanticsIds.radioFavorite('rs-1')));
    await tester.pumpAndSettle();
    expect(container.read(radioDialProvider), isEmpty);
    // An empty list is a value, not a "keep": copyWith treats only null
    // that way, so the last unpin carries through.
    expect(repo.prefs.radioFavorites, isEmpty);
  });

  // The dial's cap is a display bound. Presenting the stored list through
  // it and writing that back deletes another client's thirteenth pin.
  testWidgets('a stored list longer than the dial survives a write', (
    tester,
  ) async {
    final beyond = <String>[
      for (var i = 0; i < RadioFavorites.limit + 3; i++) 'rs-far-$i',
      'rs-1',
    ];
    final repo = _repoWithFavorites(beyond);
    final container = _container(repo);
    await _pumpHub(tester, container);

    // Held whole, drawn capped.
    expect(
      container.read(radioFavoritesProvider).length,
      beyond.length,
      reason: 'the stored list is held whole',
    );
    expect(
      container.read(radioDialProvider).length,
      lessThanOrEqualTo(RadioFavorites.limit),
    );

    // Unpinning one writes the rest back, all of them.
    await tester.tap(_byId(SemanticsIds.radioFavorite('rs-1')));
    await tester.pumpAndSettle();
    expect(repo.prefs.radioFavorites, beyond.sublist(0, beyond.length - 1));
  });

  testWidgets('a pin past the dial says so rather than vanishing', (
    tester,
  ) async {
    final full = <String>[
      for (var i = 0; i < RadioFavorites.limit; i++) 'rs-far-$i',
    ];
    final repo = _repoWithFavorites(full);
    await _pumpHub(tester, _container(repo));

    await tester.tap(_byId(SemanticsIds.radioFavorite('rs-1')));
    await tester.pumpAndSettle();

    // Said, and not written: a silent drop is a tap that reports success
    // and does nothing.
    expect(find.textContaining('Unpin one to make room'), findsOneWidget);
    expect(repo.prefs.radioFavorites, full);
  });

  testWidgets('a refused pin springs back and says why', (tester) async {
    final repo = _repo()
      ..putPrefsError = const WaxDeckApiException(
        code: 'invalid-request',
        message: 'not a station pid',
      );
    final container = _container(repo);
    await _pumpHub(tester, container);

    await tester.tap(_byId(SemanticsIds.radioFavorite('rs-1')));
    await tester.pumpAndSettle();

    // The star goes back, and says why: the discarded future turned a
    // refused write into a zone error with nothing shown.
    expect(container.read(radioFavoritesProvider), isEmpty);
    expect(find.text('not a station pid'), findsOneWidget);
  });

  // PUT replaces the whole document and the server takes the last writer,
  // so two pins in flight would each build from the same loaded value.
  testWidgets('pins tapped in a run all reach the document', (tester) async {
    final repo = _repo();
    await _pumpHub(tester, _container(repo));

    await tester.tap(_byId(SemanticsIds.radioFavorite('rs-1')));
    await tester.tap(_byId(SemanticsIds.radioFavorite('rs-2')));
    await tester.tap(_byId(SemanticsIds.radioFavorite('rs-3')));
    await tester.pumpAndSettle();

    expect(repo.prefs.radioFavorites, ['rs-1', 'rs-2', 'rs-3']);
  });

  testWidgets('tuning a station in plays it, and tapping it again stops', (
    tester,
  ) async {
    final engine = FakeEngine();
    final container = _container(_repo(), engine: engine);
    await _pumpHub(tester, container);

    await tester.tap(_byId(SemanticsIds.radio('rs-1')));
    await tester.pumpAndSettle();
    expect(engine.playing, isTrue);
    expect(container.read(radioPlaybackProvider).station?.pid, 'rs-1');

    await tester.tap(_byId(SemanticsIds.radio('rs-1')));
    await tester.pumpAndSettle();
    expect(container.read(radioPlaybackProvider).station, isNull);
  });

  testWidgets('tuning to a station that will not open stops the one that was', (
    tester,
  ) async {
    // The reported bug: with the second station down, the hub and the bar
    // both moved onto it while the first one kept playing. Two faults met
    // there - a stream that will not open throws from the engine rather
    // than as an API error, which the catch did not cover, and nothing
    // released the engine on the way in, so the old stream stayed up.
    final engine = FakeEngine();
    final container = _container(_repo(), engine: engine);
    await _pumpHub(tester, container);

    await tester.tap(_byId(SemanticsIds.radio('rs-1')));
    await tester.pumpAndSettle();
    expect(engine.playing, isTrue);
    expect(engine.loadedUrl, contains('rs-1'));

    engine.failNextLoad = true;
    await tester.tap(_byId(SemanticsIds.radio('rs-2')));
    await tester.pumpAndSettle();

    // Nothing is on: the station that was playing was let go as the dial
    // turned, and the one that would not open never started.
    expect(engine.playing, isFalse);
    expect(
      container.read(radioPlaybackProvider).station,
      isNull,
      reason: 'the hub must not name a station making no sound',
    );
    // And the tap says so rather than reading as one that was dropped.
    expect(find.text('Could not tune Deck Radio'), findsOneWidget);
  });

  testWidgets('a tune overtaken before it opens leaves the newer one alone', (
    tester,
  ) async {
    // Two taps in flight at once: the slow one must not open its stream
    // over the station that replaced it, nor publish itself as what is on
    // when it finally comes back.
    final repo = _repo();
    final engine = FakeEngine();
    final gate = Completer<void>();
    repo.radioPlayInfoGates['rs-1'] = gate;
    final container = _container(repo, engine: engine);
    await _pumpHub(tester, container);

    await tester.tap(_byId(SemanticsIds.radio('rs-1')));
    await tester.pump();
    expect(container.read(radioPlaybackProvider).starting, isTrue);

    await tester.tap(_byId(SemanticsIds.radio('rs-2')));
    await tester.pumpAndSettle();
    expect(container.read(radioPlaybackProvider).station?.pid, 'rs-2');
    expect(engine.loadedUrl, contains('rs-2'));

    gate.complete();
    await tester.pumpAndSettle();

    expect(container.read(radioPlaybackProvider).station?.pid, 'rs-2');
    expect(engine.loadedUrl, contains('rs-2'));
    expect(engine.playing, isTrue);

    // The title poll outlives the widget tree, like every other thing
    // playback owns: a station left on is a timer still firing.
    await container.read(radioPlaybackProvider.notifier).stop();
    await tester.pumpAndSettle();
  });

  testWidgets('a stop that fails is not reported as a failed tune', (
    tester,
  ) async {
    // Tapping the station that is on stops it. Naming every failure after
    // tuning told a listener their station could not be tuned while it
    // carried on playing.
    final engine = FakeEngine();
    final container = _container(_repo(), engine: engine);
    await _pumpHub(tester, container);

    await tester.tap(_byId(SemanticsIds.radio('rs-1')));
    await tester.pumpAndSettle();
    expect(container.read(radioPlaybackProvider).station?.pid, 'rs-1');

    engine.failNextStop = true;
    await tester.tap(_byId(SemanticsIds.radio('rs-1')));
    await tester.pumpAndSettle();

    expect(find.text('Could not stop Coastal FM'), findsOneWidget);
    expect(find.textContaining('Could not tune'), findsNothing);
  });

  testWidgets('an overtaken tune that then fails says nothing', (tester) async {
    // The failure belongs to a station the listener has already moved off,
    // and the one they moved to is tuning fine: reporting the old one puts
    // "could not tune" on screen over a station that is about to play.
    final repo = _repo();
    final engine = FakeEngine();
    final gate = Completer<void>();
    repo.radioPlayInfoGates['rs-1'] = gate;
    final container = _container(repo, engine: engine);
    await _pumpHub(tester, container);

    await tester.tap(_byId(SemanticsIds.radio('rs-1')));
    await tester.pump();

    await tester.tap(_byId(SemanticsIds.radio('rs-2')));
    await tester.pumpAndSettle();
    expect(container.read(radioPlaybackProvider).station?.pid, 'rs-2');

    // The overtaken tune comes back to a stream that will not open.
    engine.failNextLoad = true;
    gate.complete();
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not tune'), findsNothing);
    expect(
      container.read(radioPlaybackProvider).station?.pid,
      'rs-2',
      reason: 'a failure it no longer owns must not clear the newer station',
    );

    await container.read(radioPlaybackProvider.notifier).stop();
    await tester.pumpAndSettle();
  });

  testWidgets('the hub carries the level while a station is on', (
    tester,
  ) async {
    // The compact deck bar has no right cluster to hold a track, so the
    // level lives on the surfaces that have the room: this hub and the
    // player's radio face. Without one here, a listener on the hub
    // below sidebar width had no way to set a station's loudness.
    final engine = FakeEngine();
    final container = _container(
      _repo(),
      engine: engine,
      extra: [localVolumeAvailableProvider.overrideWithValue(true)],
    );
    await _pumpHub(tester, container, size: const Size(700, 900));

    expect(
      _byId(SemanticsIds.radioVolume),
      findsNothing,
      reason: 'nothing is playing, so there is no output to set',
    );

    await tester.tap(_byId(SemanticsIds.radio('rs-1')));
    await tester.pumpAndSettle();

    final slider = _byId(SemanticsIds.radioVolume);
    expect(slider, findsOneWidget);
    // Straight onto the engine, and the control follows it back rather
    // than keeping a copy: the sleep timer's fade writes the same gain.
    await tester.tapAt(tester.getTopRight(slider) - const Offset(1, 0));
    await tester.pumpAndSettle();
    expect(engine.volume, closeTo(1.0, 0.02));

    await tester.tap(_byId(SemanticsIds.radioMute));
    await tester.pumpAndSettle();
    expect(engine.volume, 0);

    await container.read(radioPlaybackProvider.notifier).stop();
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.radioVolume), findsNothing);
  });

  testWidgets('removing a station drops the pin that named it', (tester) async {
    final repo = _repoWithFavorites(<String>['rs-1', 'rs-2']);
    final container = _container(repo);
    await _pumpHub(tester, container);
    expect(container.read(radioDialProvider), hasLength(2));

    await tester.tap(_byId(SemanticsIds.radioMenu('rs-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove station').last);
    await tester.pumpAndSettle();

    expect(repo.radioStationsByPid.containsKey('rs-1'), isFalse);
    expect(container.read(radioDialProvider).map((s) => s.pid), ['rs-2']);
    // Not just resolved away: a pid left in storage would hold a slot of
    // the dial's cap for a station nobody can tune.
    expect(container.read(radioFavoritesProvider), ['rs-2']);
  });

  testWidgets('an empty library says how to fill it', (tester) async {
    final container = _container(FakeRepository(items: <ItemSummary>[]));
    await _pumpHub(tester, container);
    expect(find.text('No stations yet'), findsOneWidget);
  });

  testWidgets('the add dialog searches the directory and adds a match', (
    tester,
  ) async {
    final repo = _repo()
      ..directoryEntries = const [
        RadioDirectoryEntry(
          name: 'Jazz24',
          streamUrl: 'https://jazz24.example/stream',
          country: 'United States',
          codec: 'MP3',
          bitrateKbps: 192,
          tags: 'jazz,smooth',
        ),
      ];
    final container = _container(repo);
    await _pumpHub(tester, container);

    await tester.tap(_byId(SemanticsIds.radioAdd));
    await tester.pumpAndSettle();
    await tester.enterText(_byId(SemanticsIds.radioSearchField), 'jazz');
    await tester.tap(_byId(SemanticsIds.radioSearchRun));
    await tester.pumpAndSettle();

    expect(find.text('Jazz24'), findsOneWidget);
    // What a listener picks between six results called "Jazz FM" with.
    expect(find.textContaining('United States · MP3 192 kbps'), findsOneWidget);

    await tester.tap(_byId(SemanticsIds.radioAddDirectory(0)));
    await tester.pumpAndSettle();

    expect(
      repo.radioStationsByPid.values.map((s) => s.name),
      contains('Jazz24'),
    );
  });

  testWidgets('an unreachable directory names the way round it', (
    tester,
  ) async {
    final repo = _repo()
      ..directoryError = const WaxDeckApiException(
        code: 'directory-unavailable',
        message: 'The station directory could not be reached.',
      );
    await _pumpHub(tester, _container(repo));

    await tester.tap(_byId(SemanticsIds.radioAdd));
    await tester.pumpAndSettle();
    await tester.enterText(_byId(SemanticsIds.radioSearchField), 'jazz');
    await tester.tap(_byId(SemanticsIds.radioSearchRun));
    await tester.pumpAndSettle();

    // The mapped message plus the door manual entry leaves open: adding a
    // station by URL needs no directory at all.
    expect(find.textContaining('Paste a stream URL instead'), findsOneWidget);
  });

  testWidgets('a refused save is readable inside the dialog', (tester) async {
    // The dialog stays open on a refusal, so a snackbar would render on the
    // scaffold behind it - and a duplicate stream URL is the refusal a
    // listener hits most, since the library rejects one outright.
    final repo = _repo()
      ..createStationError = const WaxDeckApiException(
        code: 'conflict',
        message: 'a station with this stream URL already exists',
      );
    await _pumpHub(tester, _container(repo));

    await tester.tap(_byId(SemanticsIds.radioAdd));
    await tester.pumpAndSettle();
    await tester.tap(find.text('By URL'));
    await tester.pumpAndSettle();
    await tester.enterText(_byId(SemanticsIds.radioNameField), 'Dupe FM');
    await tester.enterText(
      _byId(SemanticsIds.radioUrlField),
      'https://stream.example/rs-1',
    );
    await tester.tap(_byId(SemanticsIds.radioAddConfirm));
    await tester.pumpAndSettle();

    // Still open, with the reason on it.
    expect(_byId(SemanticsIds.radioAddConfirm), findsOneWidget);
    expect(
      find.text('a station with this stream URL already exists'),
      findsOneWidget,
    );
  });

  testWidgets('editing a station keeps its pid and re-points its logo', (
    tester,
  ) async {
    final repo = _repo();
    final artwork = FakeArtworkStore();
    await _pumpHub(tester, _container(repo, artwork: artwork));

    await tester.tap(_byId(SemanticsIds.radioMenu('rs-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit station').last);
    await tester.pumpAndSettle();

    // The form opens on the station rather than on a directory search:
    // there is nothing to look up about a station that already exists.
    expect(find.text('Edit station'), findsWidgets);
    await tester.enterText(
      _byId(SemanticsIds.radioNameField),
      'Deck Radio One',
    );
    await tester.tap(_byId(SemanticsIds.radioAddConfirm));
    await tester.pumpAndSettle();

    expect(repo.radioStationsByPid['rs-2']?.name, 'Deck Radio One');
    // The proxy URL is keyed by pid, which an edit does not change, so
    // without this the fix to a broken logo changes nothing visible.
    expect(artwork.evicted, contains(repo.radioLogoUrlFor('rs-2')));
  });

  group("search's radio chip", () {
    Future<void> pumpSearch(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          // At the location it publishes to, so typing keeps the chip:
          // hosted anywhere else, the settled query replaces the page and
          // a fresh screen resets the filter.
          child: routedHost(
            _reducedMotion(const SearchScreen()),
            at: WaxRoute.search,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('searches the directory and offers to add each result', (
      tester,
    ) async {
      final repo = _repo()
        ..directoryEntries = const [
          RadioDirectoryEntry(
            name: 'Jazz24',
            streamUrl: 'https://jazz24.example/stream',
            country: 'United States',
          ),
        ];
      final container = _container(repo);
      await pumpSearch(tester, container);

      await tester.tap(_byId(SemanticsIds.searchFilter('radio')));
      await tester.pumpAndSettle();
      await tester.enterText(_byId(SemanticsIds.searchField), 'jazz');
      await tester.pump(SearchQuery.debounce);
      await tester.pumpAndSettle();

      expect(find.text('Jazz24'), findsOneWidget);
      await tester.tap(_byId(SemanticsIds.radioSearchAdd(0)));
      await tester.pumpAndSettle();

      expect(
        repo.radioStationsByPid.values.map((s) => s.name),
        contains('Jazz24'),
      );
    });

    testWidgets('with nothing typed it says what typing will do', (
      tester,
    ) async {
      // The recent searches are queries put to the *library*, so offering
      // them under a chip that searches the station directory would put a
      // shortcut to the wrong surface behind them.
      final repo = _repo();
      final container = _container(repo);
      container.read(recentSearchesProvider.notifier).remember('nightjar');
      await pumpSearch(tester, container);

      await tester.tap(_byId(SemanticsIds.searchFilter('radio')));
      await tester.pumpAndSettle();

      expect(find.text('Search the station directory'), findsOneWidget);
      expect(find.text('nightjar'), findsNothing);
    });

    testWidgets('a directory query is not kept as a library recent', (
      tester,
    ) async {
      // An entry stored under this chip would sit among the library's
      // recents and, tapped, search the library for a station name.
      final repo = _repo();
      final container = _container(repo);
      await pumpSearch(tester, container);

      await tester.tap(_byId(SemanticsIds.searchFilter('radio')));
      await tester.pumpAndSettle();
      await tester.enterText(_byId(SemanticsIds.searchField), 'jazz24');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(container.read(recentSearchesProvider), isEmpty);

      // A library query still is: the guard is the chip, not the submit.
      await tester.tap(_byId(SemanticsIds.searchFilter('all')));
      await tester.pumpAndSettle();
      await tester.enterText(_byId(SemanticsIds.searchField), 'nightjar');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(container.read(recentSearchesProvider), ['nightjar']);
    });

    testWidgets('does not spend a library search it cannot show', (
      tester,
    ) async {
      // The chip asks a different surface a different question, so it is
      // deliberately not part of "All": a keystroke under it must not fire
      // a library search whose every group is hidden.
      final repo = _repo();
      final container = _container(repo);
      await pumpSearch(tester, container);

      await tester.tap(_byId(SemanticsIds.searchFilter('radio')));
      await tester.pumpAndSettle();
      await tester.enterText(_byId(SemanticsIds.searchField), 'jazz');
      await tester.pump(SearchQuery.debounce);
      await tester.pumpAndSettle();

      expect(repo.searchCalls, isEmpty);
      expect(repo.directoryQueries, ['jazz']);
    });
  });
}
