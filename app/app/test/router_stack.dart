/// What the router's stack holds, for the tests that assert a door went to
/// its location rather than pushing it over the page it was on.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// The router the app [tester] mounted navigates with.
GoRouter routerOf(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(Navigator).first));

/// The pushes on [router]'s stack, however deep the shells nest them.
int pushesOn(GoRouter router) =>
    _pushes(router.routerDelegate.currentConfiguration.matches);

int _pushes(List<RouteMatchBase> matches) => <int>[
  for (final match in matches)
    if (match is ImperativeRouteMatch)
      1
    else if (match is ShellRouteMatch)
      _pushes(match.matches),
].fold(0, (sum, n) => sum + n);
