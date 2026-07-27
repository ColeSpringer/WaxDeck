import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/books/book_screen.dart';
import 'package:waxdeck/src/library/browse_controller.dart';
import 'package:waxdeck/src/library/browse_screen.dart';
import 'package:waxdeck/src/library/library_screen.dart';
import 'package:waxdeck/src/player/deck_bar_host.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/player/player_screen.dart';
import 'package:waxdeck/src/podcasts/podcasts_screen.dart';
import 'package:waxdeck/src/podcasts/show_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/radio/radio_screen.dart';
import 'package:waxdeck/src/settings/settings_screen.dart';
import 'package:waxdeck/src/tools/tasks_screen.dart';
import 'package:waxdeck/src/shell/adaptive_shell.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/side_panel.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';

const _showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';

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
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(
        FakeRepository(
          sessionState: SessionState(authenticated: true, user: user),
        )..addSubscription(testShow(_showPid)),
      ),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      // The shell hosts the deck bar, so mounting it builds playback:
      // the real engine wants platform channels no widget test has.
      audioEngineProvider.overrideWithValue(FakeEngine()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      // Animations off: the deck bar's VU needle repeats for as long as
      // something is playing, which is the point of it and the end of
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
      expect(find.byType(LibraryScreen), findsOneWidget);
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
    // The group starts closed, so its children are not built until it is
    // opened; every one of them has to carry a handle once it is.
    await tester.tap(find.text('Curation'));
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

    container.read(routerProvider).go(WaxRoute.book('bk-1'));
    await tester.pumpAndSettle();
    expect(_selected(tester), WaxNavTarget.home.name);

    container.read(routerProvider).go(WaxRoute.trash);
    await tester.pumpAndSettle();
    expect(_selected(tester), WaxNavTarget.trash.name);

    // An episode is a podcasts location whose path cannot sit under
    // `/podcasts`, so nothing but home claims it by prefix. The branch on
    // screen is what settles it; lighting Home here would have the chrome
    // contradict the router.
    container.read(routerProvider).go(WaxRoute.episode('ep-1'));
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
    expect(find.byType(LibraryScreen), findsOneWidget);

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
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
  });

  testWidgets('a pushed excursion keeps the stack it came from', (
    tester,
  ) async {
    // A book is declared under home, so `go` from anywhere else rebuilds
    // that ancestry and takes the stack with it — including a bucket whose
    // contents live in memory and cannot be rebuilt from a URL. Pushing is
    // what makes the excursion an excursion.
    final container = await _pumpShell(tester);
    final router = container.read(routerProvider);

    router.go(WaxRoute.browse);
    await tester.pumpAndSettle();
    router.push<void>(
      WaxRoute.browseItems,
      extra: const BrowseBucketArgs(
        dimension: BrowseDimension.genre,
        bucket: FacetBucket(key: 'jazz', label: 'Jazz', count: 3),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BrowseItemsScreen), findsOneWidget);

    router.push<void>(WaxRoute.book('bk-1'));
    await tester.pumpAndSettle();
    expect(find.byType(BookScreen), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(
      find.byType(BrowseItemsScreen),
      findsOneWidget,
      reason: 'the bucket cannot be rebuilt, so it has to survive',
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

    // Arriving by URL must never hide where you are.
    expect(
      find.descendant(
        of: find.byType(WaxSidebar),
        matching: find.text('Trash'),
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
    expect(find.byType(LibraryScreen), findsOneWidget);

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

    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(_location(container), WaxRoute.home);
  });

  group('active destination', () {
    test('is the longest declared location a screen sits under', () {
      const targets = WaxNavTarget.values;
      expect(activeNavTarget(WaxRoute.home, targets), WaxNavTarget.home);
      expect(
        activeNavTarget(WaxRoute.book('bk-1'), targets),
        WaxNavTarget.home,
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
      // Home's own branch still answers home.
      expect(
        activeNavTarget(WaxRoute.book('bk-1'), targets, branchIndex: 0),
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
