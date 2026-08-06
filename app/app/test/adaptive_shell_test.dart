import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/books/book_screen.dart';
import 'package:waxdeck/src/music/listing_screen.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/home/home_screen.dart';
import 'package:waxdeck/src/player/deck_bar_host.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/player/player_screen.dart';
import 'package:waxdeck/src/podcasts/podcasts_screen.dart';
import 'package:waxdeck/src/podcasts/show_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/radio/radio_screen.dart';
import 'package:waxdeck/src/search/search_controller.dart';
import 'package:waxdeck/src/settings/settings_screen.dart';
import 'package:waxdeck/src/tools/tasks_screen.dart';
import 'package:waxdeck/src/shell/adaptive_shell.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/side_panel.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';

const _showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
const _episodePid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';
const _bookPid = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';

const _admin = WaxDeckUser(
  id: 'us-1',
  username: 'admin',
  roles: ['admin'],
  uploadEnabled: true,
);
const _listener = WaxDeckUser(id: 'us-2', username: 'sam', roles: ['user']);

/// Mounts the whole app at [size], which is what picks the chrome.
Future<ProviderContainer> _pumpShell(
  WidgetTester tester, {
  Size size = const Size(1000, 900),
  WaxDeckUser user = _admin,
  bool hasBooks = true,
  bool hasDownloads = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(
        FakeRepository(
            sessionState: SessionState(authenticated: true, user: user),
          )
          ..addSubscription(testShow(_showPid))
          // The show's episodes, so the drill-in assertions render a
          // screen rather than a not-found: a chrome test is about what
          // the chrome highlights, not about a failed fetch.
          ..episodesByShow[_showPid] = <EpisodeSummary>[
            testEpisode(_episodePid),
          ]
          // A library with a book in it, because the Audiobooks tab hides
          // where there are none; the false case is its own test.
          ..libraryItems.addAll(<ItemSummary>[
            if (hasBooks)
              testItem(
                _bookPid,
                mediaType: MediaType.audiobook,
                title: 'There And Back Again',
              ),
          ])
          ..books[_bookPid] = testBook(_bookPid),
      ),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      // The shell hosts the deck bar, so mounting it builds playback:
      // the real engine wants platform channels no widget test has.
      audioEngineProvider.overrideWithValue(FakeEngine()),
      // Downloads is a native destination, and a widget test has no
      // manager unless it is given one.
      if (hasDownloads)
        downloadManagerProvider.overrideWithValue(FakeDownloads()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      // Animations off: the deck bar's indicators run for as long as
      // something is playing, which is the point of them and the end of
      // `pumpAndSettle`. Built from the view, so the size class every
      // one of these tests keys off is still the window's own.
      child: MediaQuery(
        data: MediaQueryData.fromView(
          tester.view,
        ).copyWith(disableAnimations: true),
        child: const WaxDeckApp(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Presses system back the way the platform does.
///
/// Through the navigation channel rather than `routerDelegate.popRoute()`:
/// the router's back-button dispatcher is consulted first, and the shell's
/// handler lives there, so calling the delegate directly would skip the
/// thing under test.
Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
    (_) {},
  );
  await tester.pumpAndSettle();
}

String _location(ProviderContainer container) => container
    .read(routerProvider)
    .routerDelegate
    .currentConfiguration
    .uri
    .toString();

Finder _nav(String name) => find
    .byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.identifier == SemanticsIds.navDestination(name),
    )
    .first;

/// The destination the chrome is showing as active.
String? _selected(WidgetTester tester) =>
    tester.widget<WaxShellFrame>(find.byType(WaxShellFrame)).selected;

Future<void> _tapNav(WidgetTester tester, String name) async {
  await tester.tap(_nav(name));
  await tester.pumpAndSettle();
}

void main() {
  // Each width mounts the whole app, so they run as their own tests: two
  // apps in one body would tear the first down with its timers pending.
  for (final entry in <String, (Size, Type)>{
    'compact': (Size(400, 800), WaxNavBar),
    'medium': (Size(700, 900), WaxNavRail),
    'expanded': (Size(1000, 900), WaxSidebar),
    'wide': (Size(1400, 900), WaxSidebar),
  }.entries) {
    final (size, chrome) = entry.value;
    testWidgets('${entry.key} wears $chrome around the same screen', (
      tester,
    ) async {
      await _pumpShell(tester, size: size);
      expect(find.byType(chrome), findsOneWidget);
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  }

  testWidgets('a destination puts itself in the address bar', (tester) async {
    // The deferred item this phase closes: tapping into a screen used to
    // leave the bar wherever the last `go` had left it.
    final container = await _pumpShell(tester);

    await _tapNav(tester, WaxNavTarget.podcasts.name);
    expect(_location(container), WaxRoute.podcasts);
    expect(find.byType(PodcastsScreen), findsOneWidget);

    await _tapNav(tester, WaxNavTarget.radio.name);
    expect(_location(container), WaxRoute.radio);
    expect(find.byType(RadioScreen), findsOneWidget);
  });

  testWidgets('an entity detail is its own location, under its index', (
    tester,
  ) async {
    final container = await _pumpShell(tester);
    final router = container.read(routerProvider);

    router.go(WaxRoute.show(_showPid));
    await tester.pumpAndSettle();

    expect(_location(container), WaxRoute.show(_showPid));
    expect(find.byType(ShowScreen), findsOneWidget);
    // The hub is built underneath, so back lands where a push would have.
    expect(router.canPop(), isTrue);
  });

  group('a domain with nothing behind it', () {
    Finder navFor(WaxNavTarget target) => find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.identifier ==
              SemanticsIds.navDestination(target.name),
    );

    testWidgets('loses its tab, and home absorbs the gap', (tester) async {
      // The layout system's rule, and the answer to the tab count a fifth
      // domain forces: a library with no audiobooks is not offered a
      // books tab. The routes stay declared either way, so a shared link
      // into one still resolves.
      await _pumpShell(tester, hasBooks: false);
      expect(navFor(WaxNavTarget.books), findsNothing);
      expect(navFor(WaxNavTarget.podcasts), findsWidgets);
      expect(navFor(WaxNavTarget.home), findsWidgets);
    });

    testWidgets('keeps its tab where the library has one', (tester) async {
      await _pumpShell(tester);
      expect(navFor(WaxNavTarget.books), findsWidgets);
    });

    testWidgets('a book is still reachable by location without the tab', (
      tester,
    ) async {
      final container = await _pumpShell(tester, hasBooks: false);
      container.read(routerProvider).go(WaxRoute.book(_bookPid));
      await tester.pumpAndSettle();

      expect(find.byType(BookScreen), findsOneWidget);
      // And the chrome lights nothing rather than lying about where the
      // visitor is. The branch on screen still names its domain - that is
      // what keeps a drill-in from lighting Home - but the chrome is not
      // drawing that destination, so no row is selected.
      final frame = tester.widget<WaxShellFrame>(find.byType(WaxShellFrame));
      expect(frame.selected, WaxNavTarget.books.name);
      expect(
        frame.destinations.map((d) => d.name),
        isNot(contains(WaxNavTarget.books.name)),
      );
    });

    // Two mounts in one body would tear the first app down with its
    // timers pending, which is why every width above is its own test.
    testWidgets('downloads is absent where this build keeps none', (
      tester,
    ) async {
      await _pumpShell(tester, hasDownloads: false);
      expect(navFor(WaxNavTarget.downloads), findsNothing);
    });

    testWidgets('downloads is offered where this build keeps some', (
      tester,
    ) async {
      await _pumpShell(tester);
      expect(navFor(WaxNavTarget.downloads), findsWidgets);
    });
  });

  testWidgets('every destination is exposed to assistive tech and the suite', (
    tester,
  ) async {
    // Not a formality. A routed content pane carries a ModalBarrier per
    // route, and a barrier blocks the semantics of everything painted
    // before it in its container, so the sidebar rendered and announced
    // nothing until the frame gave the pane a boundary of its own. The
    // chrome is where the suite steers from after the flip, so this is
    // the shape that has to hold.
    final semantics = tester.ensureSemantics();
    // Tall enough that the whole list is built: the sidebar scrolls, and
    // a lazily-built row that is off screen is not the thing under test.
    final container = await _pumpShell(tester, size: const Size(1000, 1400));
    // Both sections start closed away from what they hold, so their
    // children are not built until they are opened; every one of them has
    // to carry a handle once they are.
    await tester.tap(find.text('Curation'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Expand Music'));
    await tester.pumpAndSettle();

    for (final target in WaxNavTarget.values) {
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.identifier ==
                  SemanticsIds.navDestination(target.name),
        ),
        findsWidgets,
        reason: '${target.name} has no handle',
      );
    }
    expect(find.bySemanticsLabel('Main navigation'), findsOneWidget);
    expect(
      tester.getSemantics(
        find.descendant(
          of: find.byType(WaxSidebar),
          matching: find.bySemanticsLabel('Podcasts'),
        ),
      ),
      matchesSemantics(
        label: 'Podcasts',
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        hasSelectedState: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );

    container.read(routerProvider).go(WaxRoute.podcasts);
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(
            find.descendant(
              of: find.byType(WaxSidebar),
              matching: find.bySemanticsLabel('Podcasts'),
            ),
          )
          .getSemanticsData()
          .toString(),
      contains('isSelected'),
    );
    semantics.dispose();
  });

  testWidgets('a drilled-in screen keeps its domain highlighted', (
    tester,
  ) async {
    // The chrome reads the matched location, so it stays truthful when
    // navigation happens somewhere other than the chrome itself.
    final container = await _pumpShell(tester);

    container.read(routerProvider).go(WaxRoute.show(_showPid));
    await tester.pumpAndSettle();
    expect(_selected(tester), WaxNavTarget.podcasts.name);

    container.read(routerProvider).go(WaxRoute.book(_bookPid));
    await tester.pumpAndSettle();
    expect(_selected(tester), WaxNavTarget.books.name);

    // A console section lights the console's own row: the chrome has one
    // entry for the whole of it, and the section list inside it says
    // which one is open.
    container.read(routerProvider).go(WaxRoute.trash);
    await tester.pumpAndSettle();
    expect(_selected(tester), WaxNavTarget.admin.name);

    // The show-less episode location, which a search hit opens because a
    // hit carries no show, cannot sit under `/podcasts`, so nothing but
    // home claims it by prefix. The branch on screen is what settles it;
    // lighting Home here would have the chrome contradict the router.
    // (The canonical location has the show in the path and is claimed by
    // prefix like any other drill-in.)
    container.read(routerProvider).go(WaxRoute.episode(_episodePid));
    await tester.pumpAndSettle();
    expect(_selected(tester), WaxNavTarget.podcasts.name);
  });

  testWidgets('a domain keeps the stack it had while another is showing', (
    tester,
  ) async {
    // The whole point of a branch per domain: leaving podcasts mid-drill
    // and coming back lands on the show again, not on the hub.
    final container = await _pumpShell(tester);
    final router = container.read(routerProvider);

    router.go(WaxRoute.show(_showPid));
    await tester.pumpAndSettle();
    await _tapNav(tester, WaxNavTarget.home.name);
    expect(find.byType(HomeScreen), findsOneWidget);

    await _tapNav(tester, WaxNavTarget.podcasts.name);
    expect(find.byType(ShowScreen), findsOneWidget);
    expect(_location(container), WaxRoute.show(_showPid));
  });

  testWidgets('tapping the domain you are on returns to its root', (
    tester,
  ) async {
    final container = await _pumpShell(tester);
    container.read(routerProvider).go(WaxRoute.show(_showPid));
    await tester.pumpAndSettle();

    await _tapNav(tester, WaxNavTarget.podcasts.name);

    expect(find.byType(PodcastsScreen), findsOneWidget);
    expect(_location(container), WaxRoute.podcasts);
  });

  testWidgets('settings never becomes what the home tab restores', (
    tester,
  ) async {
    // Everything that is not a domain shares one branch for exactly this
    // reason: a secondary destination must not be pinned to a tab.
    final container = await _pumpShell(tester);

    await _tapNav(tester, WaxNavTarget.settings.name);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(_location(container), WaxRoute.settings);

    await _tapNav(tester, WaxNavTarget.home.name);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
  });

  testWidgets('a pushed excursion keeps the stack it came from', (
    tester,
  ) async {
    // A book is declared under the audiobooks hub, so `go` from anywhere
    // else rebuilds that ancestry and takes the stack with it - here, a
    // drilled genre three levels into the music branch. Pushing is what
    // makes the excursion an excursion.
    final container = await _pumpShell(tester);
    final router = container.read(routerProvider);

    router.go(WaxRoute.musicBucket(MusicDimension.genres, 'jazz'));
    await tester.pumpAndSettle();
    expect(find.byType(MusicListingScreen), findsOneWidget);

    router.push<void>(WaxRoute.book(_bookPid));
    await tester.pumpAndSettle();
    expect(find.byType(BookScreen), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(
      find.byType(MusicListingScreen),
      findsOneWidget,
      reason: 'the excursion has to come back where it started',
    );
  });

  testWidgets('a snackbar excursion returns where it started', (tester) async {
    // `/tasks` lives in the shared branch and is reached from a snackbar
    // anywhere, so it is pushed: `go` would unmount whatever started the
    // task with no route back to it.
    final container = await _pumpShell(tester);
    final router = container.read(routerProvider);

    router.go(WaxRoute.podcasts);
    await tester.pumpAndSettle();
    router.push<void>(WaxRoute.tasks);
    await tester.pumpAndSettle();
    expect(find.byType(TasksScreen), findsOneWidget);

    await _systemBack(tester);
    expect(find.byType(PodcastsScreen), findsOneWidget);
    expect(_location(container), WaxRoute.podcasts);
  });

  testWidgets('compact reaches settings through the account menu', (
    tester,
  ) async {
    // A phone's tab bar holds the domains and nothing else, and the
    // screens' own navigation rows are gone, so this is the whole route
    // to the secondary destinations there.
    final container = await _pumpShell(tester, size: const Size(400, 800));

    await tester.tap(find.bySemanticsLabel('Account'));
    await tester.pumpAndSettle();
    expect(find.text('admin'), findsOneWidget, reason: 'who is signed in');

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(_location(container), WaxRoute.settings);
  });

  testWidgets('the account menu signs out', (tester) async {
    final container = await _pumpShell(tester, size: const Size(400, 800));

    await tester.tap(find.bySemanticsLabel('Account'));
    await tester.pumpAndSettle();
    // An administrator's menu is longer than a phone, so the last row is
    // scrolled to rather than tapped where it is not.
    await tester.ensureVisible(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(
      container.read(authControllerProvider).value?.authenticated,
      isFalse,
    );
    // Nothing unwinds the stack by hand: dropping the session moves the
    // redirect, and the whole signed-in shell goes with it.
    expect(_location(container), WaxRoute.login);
  });

  testWidgets('the curation group is hidden from an account without it', (
    tester,
  ) async {
    await _pumpShell(tester, user: _listener);

    expect(find.text('Curation'), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('the curation group opens on the area a visitor is in', (
    tester,
  ) async {
    final container = await _pumpShell(tester, size: const Size(1000, 1400));
    container.read(routerProvider).go(WaxRoute.trash);
    await tester.pumpAndSettle();

    // Arriving by URL must never hide where you are: the group opens on
    // the console entry that claims the location.
    expect(
      find.descendant(
        of: find.byType(WaxSidebar),
        matching: find.text('Admin console'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the player covers the chrome and back closes it', (
    tester,
  ) async {
    final container = await _pumpShell(tester);
    final router = container.read(routerProvider);

    router.push<void>(WaxRoute.nowPlaying);
    await tester.pumpAndSettle();

    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(find.byType(WaxSidebar), findsNothing, reason: 'it is an overlay');

    await router.routerDelegate.popRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PlayerScreen), findsNothing);
    expect(find.byType(WaxSidebar), findsOneWidget);
  });

  testWidgets('playback keeps its slot across every destination', (
    tester,
  ) async {
    // The deck bar is the shell's, not a screen's: it sits outside the
    // branch navigators, so walking between domains never unmounts it
    // and playback never loses its one home.
    final container = await _pumpShell(tester);
    container.read(nowPlayingProvider.notifier).play(
      [testItem('tr-A', title: 'Salt Harbour')],
      source: const QueueSource(
        kind: QueueSourceKind.single,
        label: 'Salt Harbour',
      ),
    );
    await tester.pump();
    await tester.pump();

    final frame = tester.widget<WaxShellFrame>(find.byType(WaxShellFrame));
    expect(frame.bottom, isA<DeckBarHost>());
    expect(find.text('Salt Harbour'), findsOneWidget);

    await _tapNav(tester, WaxNavTarget.radio.name);
    expect(find.text('Salt Harbour'), findsOneWidget);

    container.read(queueControllerProvider.notifier).clear();
    // Long enough for the queue's own save debounce and Connect's report
    // settle to fire: both are the app's, and the test outlives them.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a replacing play verb offers to take it back', (tester) async {
    // The offer only ever existed on the queue surface's EARLIER rows;
    // every other play verb replaced silently.
    final container = await _pumpShell(tester);
    final playback = container.read(nowPlayingProvider.notifier);
    const source = QueueSource(
      kind: QueueSourceKind.single,
      label: 'Salt Harbour',
    );

    // The first play displaced nothing, so it offers nothing.
    playback.play([testItem('tr-A', title: 'Salt Harbour')], source: source);
    await tester.pump();
    await tester.pump();
    expect(find.text('Replaced what was playing'), findsNothing);

    playback.play([testItem('tr-B', title: 'Kelp Line')], source: source);
    await tester.pump();
    await tester.pump();
    // An affordance still off screen has no semantics node to tap.
    await tester.pump(const Duration(milliseconds: 750));
    expect(find.text('Replaced what was playing'), findsOneWidget);
    expect(container.read(queueControllerProvider).currentPid, 'tr-B');

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.queueReplaceUndo));
    await tester.pump();
    await tester.pump();

    // Undo puts the displaced queue back, entry and all.
    expect(container.read(queueControllerProvider).currentPid, 'tr-A');

    container.read(queueControllerProvider.notifier).clear();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a second replacement replaces the toast rather than stacking', (
    tester,
  ) async {
    // The queue holds only the most recent replacement, so a stale
    // toast would offer to undo a queue already gone.
    final container = await _pumpShell(tester);
    final playback = container.read(nowPlayingProvider.notifier);
    const source = QueueSource(
      kind: QueueSourceKind.single,
      label: 'Salt Harbour',
    );

    playback.play([testItem('tr-A', title: 'Salt Harbour')], source: source);
    await tester.pump();
    await tester.pump();
    playback.play([testItem('tr-B', title: 'Kelp Line')], source: source);
    await tester.pump();
    await tester.pump();
    playback.play([testItem('tr-C', title: 'Tide Bell')], source: source);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    // One bar on screen, and it must be the live one: a queued bar would
    // read as one toast while offering to undo a queue already gone.
    expect(find.text('Replaced what was playing'), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.queueReplaceUndo));
    await tester.pump();
    await tester.pump();
    expect(container.read(queueControllerProvider).currentPid, 'tr-B');

    // And nothing is queued behind it offering to undo again.
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Replaced what was playing'), findsNothing);

    container.read(queueControllerProvider.notifier).clear();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a replacing play verb does not eat another surface\'s toast', (
    tester,
  ) async {
    // One ScaffoldMessenger serves the whole app, so hiding
    // unconditionally would take down an error nobody has read.
    final container = await _pumpShell(tester);
    final messenger = ScaffoldMessenger.of(
      tester.element(find.byType(WaxShellFrame)),
    );
    messenger.showSnackBar(const SnackBar(content: Text('Could not save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    final playback = container.read(nowPlayingProvider.notifier);
    const source = QueueSource(
      kind: QueueSourceKind.single,
      label: 'Salt Harbour',
    );
    playback.play([testItem('tr-A', title: 'Salt Harbour')], source: source);
    await tester.pump();
    await tester.pump();
    playback.play([testItem('tr-B', title: 'Kelp Line')], source: source);
    await tester.pump();
    await tester.pump();

    expect(find.text('Could not save'), findsOneWidget);

    container.read(queueControllerProvider.notifier).clear();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a queue handed over by another device offers no undo', (
    tester,
  ) async {
    // The offer would undo something this device's user never did, and
    // leave the two ends disagreeing about what plays.
    final container = await _pumpShell(tester);
    final playback = container.read(nowPlayingProvider.notifier);
    const source = QueueSource(
      kind: QueueSourceKind.single,
      label: 'Salt Harbour',
    );

    playback.play([testItem('tr-A', title: 'Salt Harbour')], source: source);
    await tester.pump();
    await tester.pump();
    await playback.playPids(
      ['tr-B'],
      source: QueueSource.none,
      offerUndo: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.text('Replaced what was playing'), findsNothing);

    container.read(queueControllerProvider.notifier).clear();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the panel takes its slot only once something opens it', (
    tester,
  ) async {
    final container = await _pumpShell(tester, size: const Size(1400, 900));
    expect(
      tester.widget<WaxShellFrame>(find.byType(WaxShellFrame)).panel,
      isNull,
      reason: 'an empty panel is a stripe of surface with a close button',
    );

    container.read(sidePanelProvider.notifier).toggle(WaxPanel.queue);
    await tester.pumpAndSettle();

    expect(find.byType(WaxSidePanel), findsOneWidget);
    // Shell state, so it survives the destination that was showing when
    // it opened.
    await _tapNav(tester, WaxNavTarget.radio.name);
    expect(find.byType(WaxSidePanel), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Close panel'));
    await tester.pumpAndSettle();
    expect(find.byType(WaxSidePanel), findsNothing);
  });

  testWidgets('back steps from a domain to home once, then leaves', (
    tester,
  ) async {
    final container = await _pumpShell(tester, size: const Size(400, 800));

    await _tapNav(tester, WaxNavTarget.radio.name);
    await _systemBack(tester);
    expect(find.byType(HomeScreen), findsOneWidget);

    // Home's own root has nothing behind it, so the press falls through to
    // the platform and the app closes.
    expect(
      await container.read(routerProvider).routerDelegate.popRoute(),
      isFalse,
    );
  });

  testWidgets('back inside a domain pops the drill-in first', (tester) async {
    final container = await _pumpShell(tester);

    container.read(routerProvider).go(WaxRoute.show(_showPid));
    await tester.pumpAndSettle();

    await _systemBack(tester);
    expect(find.byType(PodcastsScreen), findsOneWidget);
    expect(_location(container), WaxRoute.podcasts);
  });

  testWidgets('back steps to home from a domain that had been drilled into', (
    tester,
  ) async {
    // The state a `PopScope` on the shell page never sees: once a branch
    // has held two pages and stepped back to one, `popRoute`'s walk halts
    // before reaching that scope, so the press used to leave the app from
    // a domain root instead of stepping to Home.
    final container = await _pumpShell(tester, size: const Size(400, 800));
    final router = container.read(routerProvider);

    await _tapNav(tester, WaxNavTarget.podcasts.name);
    router.go(WaxRoute.show(_showPid));
    await tester.pumpAndSettle();
    await _tapNav(tester, WaxNavTarget.podcasts.name);
    expect(_location(container), WaxRoute.podcasts);
    expect(router.canPop(), isFalse, reason: 'the branch is back at its root');

    await _systemBack(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(_location(container), WaxRoute.home);
  });

  group('the sidebar search field', () {
    testWidgets('is live, and the only field on the search screen', (
      tester,
    ) async {
      final container = await _pumpShell(tester, size: const Size(1000, 900));

      // One field, in the chrome, before anything has been searched: the
      // header used to be a launcher that opened a screen with a second
      // field in it, so the click landed somewhere the typing did not.
      final field = find.bySemanticsIdentifier(SemanticsIds.searchField);
      expect(field, findsOne);
      expect(_location(container), WaxRoute.home);

      // Focusing it is what opens the screen, and the caret stays put
      // because the field is in the shell frame rather than in the route.
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(_location(container), startsWith(WaxRoute.search));
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
        isTrue,
      );

      await tester.enterText(field, 'night');
      await tester.pump(SearchQuery.debounce);
      await tester.pumpAndSettle();

      // Still one field: the screen brings none of its own.
      expect(find.bySemanticsIdentifier(SemanticsIds.searchField), findsOne);
      expect(container.read(searchQueryProvider), 'night');
    });

    testWidgets('navigates once, however many characters are typed', (
      tester,
    ) async {
      final container = await _pumpShell(tester, size: const Size(1000, 900));
      final router = container.read(routerProvider);
      final field = find.bySemanticsIdentifier(SemanticsIds.searchField);
      await tester.tap(field);
      await tester.pumpAndSettle();
      final depth = router.routerDelegate.currentConfiguration.matches.length;

      // On web every `go` mints a history entry, so routing per keystroke
      // would make one word several back presses. The one navigation this
      // feature makes is the focus one, already spent above.
      for (final prefix in <String>['n', 'ni', 'nig', 'nigh', 'night']) {
        await tester.enterText(field, prefix);
        await tester.pump(SearchQuery.debounce);
      }
      await tester.pumpAndSettle();

      expect(_location(container), startsWith(WaxRoute.search));
      expect(
        router.routerDelegate.currentConfiguration.matches,
        hasLength(depth),
      );
    });

    testWidgets('takes its text with it when focus opens the screen', (
      tester,
    ) async {
      final container = await _pumpShell(tester, size: const Size(1000, 900));
      final field = find.bySemanticsIdentifier(SemanticsIds.searchField);

      // Typed here, then carried away and back: the search screen adopts
      // the location's query as the one being answered, so opening it
      // with a bare `/search` would submit an empty query and the shell
      // would write that emptiness straight back into the field - the
      // same class of failure as the launcher this replaced.
      await tester.enterText(field, 'nightjar');
      await tester.pump(SearchQuery.debounce);
      await tester.pumpAndSettle();
      container.read(routerProvider).go(WaxRoute.music);
      await tester.pumpAndSettle();

      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(_location(container), startsWith(WaxRoute.search));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'nightjar',
      );
      expect(container.read(searchQueryProvider), 'nightjar');
    });

    testWidgets(
      'remembers what was submitted, like the screen own field does',
      (tester) async {
        final container = await _pumpShell(tester, size: const Size(1000, 900));
        final field = find.bySemanticsIdentifier(SemanticsIds.searchField);

        // At sidebar width the screen draws no field, so this is the only
        // one there is: without the second step a desktop session never
        // accumulates a recent search and the surface offering them back
        // stays empty for good.
        await tester.enterText(field, 'nightjar');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();

        expect(container.read(recentSearchesProvider), contains('nightjar'));
      },
    );

    testWidgets('keeps its text when the branch under it swaps', (
      tester,
    ) async {
      final container = await _pumpShell(tester, size: const Size(1000, 900));
      final field = find.bySemanticsIdentifier(SemanticsIds.searchField);
      await tester.enterText(field, 'night');
      await tester.pump(SearchQuery.debounce);
      await tester.pumpAndSettle();

      // The controller lives in the shell frame, above the routed
      // navigator, which is the whole reason this shape works: results
      // swap in underneath and the field keeps what was typed in it.
      container.read(routerProvider).go(WaxRoute.music);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'night',
      );
    });

    testWidgets('is absent below sidebar width, where the screen owns one', (
      tester,
    ) async {
      final container = await _pumpShell(tester, size: const Size(400, 800));
      expect(
        find.bySemanticsIdentifier(SemanticsIds.searchField),
        findsNothing,
      );

      container.read(routerProvider).go(WaxRoute.search);
      await tester.pumpAndSettle();
      // Exactly one, and it is the screen's: two would be the
      // synchronisation problem the launcher used to avoid by being dead.
      expect(find.bySemanticsIdentifier(SemanticsIds.searchField), findsOne);
    });
  });

  group('active destination', () {
    test('is the longest declared location a screen sits under', () {
      const targets = WaxNavTarget.values;
      expect(activeNavTarget(WaxRoute.home, targets), WaxNavTarget.home);
      expect(
        activeNavTarget(WaxRoute.book('bk-1'), targets),
        WaxNavTarget.books,
      );
      expect(
        activeNavTarget(WaxRoute.show(_showPid), targets),
        WaxNavTarget.podcasts,
      );
      expect(
        activeNavTarget(WaxRoute.playlist('pl-1'), targets),
        WaxNavTarget.playlists,
      );
      expect(activeNavTarget(WaxRoute.listenLog, targets), WaxNavTarget.stats);
      // A curation area lights its own row, not the branch's tab.
      expect(
        activeNavTarget(WaxRoute.reviewEntry('re-1'), targets),
        WaxNavTarget.review,
      );
      expect(activeNavTarget(WaxRoute.tasks, targets), WaxNavTarget.tasks);
    });

    test('falls to the branch on screen when only home would claim it', () {
      const targets = WaxNavTarget.values;
      final podcasts = waxShellBranches.indexOf(WaxNavTarget.podcasts);
      expect(
        activeNavTarget(
          WaxRoute.episode('ep-1'),
          targets,
          branchIndex: podcasts,
        ),
        WaxNavTarget.podcasts,
      );
      // A prefix match is the stronger signal and outranks the branch.
      expect(
        activeNavTarget(WaxRoute.show('pc-1'), targets, branchIndex: 0),
        WaxNavTarget.podcasts,
      );
      // Home's own branch still answers home, for a location only home
      // claims - every domain's own drill-ins are claimed by prefix now
      // that the last of them has a hub.
      expect(
        activeNavTarget(WaxRoute.home, targets, branchIndex: 0),
        WaxNavTarget.home,
      );
      // And the shared branch names no destination, so a location nothing
      // there claims lights nothing rather than lighting Home.
      expect(
        activeNavTarget(
          WaxRoute.metadata('tr-1'),
          targets,
          branchIndex: waxShellBranches.length,
        ),
        isNull,
      );
    });
  });
}
