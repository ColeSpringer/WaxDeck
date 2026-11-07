import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';

/// The pushes on the stack, however deep the shells nest them.
int _pushes(List<RouteMatchBase> matches) => <int>[
  for (final match in matches)
    if (match is ImperativeRouteMatch)
      1
    else if (match is ShellRouteMatch)
      _pushes(match.matches),
].fold(0, (sum, n) => sum + n);

Future<GoRouter> _mount(WidgetTester tester) async {
  await pumpApp(tester, const SizedBox());
  return tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig!
      as GoRouter;
}

/// Inside the shell, where the app's own taps are: the top of the stack
/// is the deepest match, not the shell the pushes merge into.
void main() {
  for (final (what, location) in <(String, String)>[
    ('an overlay', WaxRoute.queue),
    ('a page in the shell', WaxRoute.tasks),
  ]) {
    testWidgets('$what pushed twice from inside the shell is one push', (
      tester,
    ) async {
      final router = await _mount(tester);
      router.go(WaxRoute.books);
      await tester.pumpAndSettle();

      router.pushOnce(location);
      await tester.pumpAndSettle();
      router.pushOnce(location);
      await tester.pumpAndSettle();

      final stack = router.routerDelegate.currentConfiguration;
      expect(stack.last.matchedLocation, location);
      expect(_pushes(stack.matches), 1);
    });
  }

  testWidgets('a location under the top of the stack is pushed again', (
    tester,
  ) async {
    // The review entry's Open uploads, when the entry was opened from
    // the uploads screen: uploads is beneath the entry, not on top of it.
    final router = await _mount(tester);
    router.go(WaxRoute.uploads);
    await tester.pumpAndSettle();
    router.push<void>(WaxRoute.reviewEntry('rv-9')).ignore();
    await tester.pumpAndSettle();

    router.pushOnce(WaxRoute.uploads);
    await tester.pumpAndSettle();

    final stack = router.routerDelegate.currentConfiguration;
    expect(stack.last.matchedLocation, WaxRoute.uploads);
    expect(_pushes(stack.matches), 2);
  });
}
