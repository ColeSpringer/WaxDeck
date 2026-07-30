import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// Where a screen under test is mounted. Paths of its own, so the app's
/// own routes stay exactly as the app declares them.
const _testRoot = '/screen-under-test';
const _testPushed = '$_testRoot/pushed';

/// Hosts one screen over the app's real route table.
///
/// Screens navigate through the router, so a test that taps a row needs
/// the same routes the app has, or the tap lands nowhere. The session
/// shell is deliberately left out: a widget test exercises a screen, not
/// the sync engine and share intake that wrap the signed-in app, which
/// `router_test.dart` covers by mounting the whole app instead.
///
/// Pass [pushed] for a screen that pops itself when it is done, which
/// the app only ever reaches by pushing: it puts a blank page underneath
/// so there is something to pop back to.
///
/// Pass [at] for a screen that writes its own location - search puts its
/// settled query in the address bar on every keystroke. Hosted at a path
/// of its own, such a screen is *replaced* by the app's real route when it
/// publishes, so a fresh State is built and everything the old one held
/// (a chosen filter chip) is lost to the test and to nothing else. Mounted
/// at the location it publishes, it behaves as it does in the app: go_router
/// keys a page by its path and its path parameters, a query is neither, and
/// the same State is reused. Declared ahead of the app's own routes so this
/// one wins the match.
Widget routedHost(Widget screen, {bool pushed = false, String? at}) {
  final root = at ?? _testRoot;
  final router = GoRouter(
    initialLocation: pushed ? _testPushed : root,
    routes: [
      GoRoute(
        path: root,
        builder: (context, state) => pushed ? const Scaffold() : screen,
        routes: [
          if (pushed)
            GoRoute(path: 'pushed', builder: (context, state) => screen),
        ],
      ),
      ...publicRoutes,
      ...shellRoutes(),
    ],
  );
  addTearDown(router.dispose);
  return MaterialApp.router(routerConfig: router);
}
