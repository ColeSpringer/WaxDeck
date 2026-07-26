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
/// Pass [newShell] to mount over the adaptive shell's table instead of the
/// flat one. The two differ wherever a location's declared parent is not
/// where a screen navigates from, so a screen whose leaving depends on
/// that is worth driving against both; the shell's own wiring is covered
/// in `adaptive_shell_test.dart`.
Widget routedHost(Widget screen, {bool pushed = false, bool newShell = false}) {
  final router = GoRouter(
    initialLocation: pushed ? _testPushed : _testRoot,
    routes: [
      GoRoute(
        path: _testRoot,
        builder: (context, state) => pushed ? const Scaffold() : screen,
        routes: [
          if (pushed)
            GoRoute(path: 'pushed', builder: (context, state) => screen),
        ],
      ),
      ...publicRoutes,
      if (newShell) ...shellRoutes() else ...signedInRoutes,
    ],
  );
  addTearDown(router.dispose);
  return MaterialApp.router(routerConfig: router);
}
