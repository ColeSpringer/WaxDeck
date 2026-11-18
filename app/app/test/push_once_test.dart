import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'router_stack.dart';

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
      expect(pushesOn(router), 1);
    });
  }

  testWidgets('a location under the top of the stack is pushed again', (
    tester,
  ) async {
    // Uploads is beneath the entry, not on top of it, so asking for it
    // again is a new push.
    final router = await _mount(tester);
    router.go(WaxRoute.uploads);
    await tester.pumpAndSettle();
    router.push<void>(WaxRoute.reviewEntry('rv-9')).ignore();
    await tester.pumpAndSettle();

    router.pushOnce(WaxRoute.uploads);
    await tester.pumpAndSettle();

    final stack = router.routerDelegate.currentConfiguration;
    expect(stack.last.matchedLocation, WaxRoute.uploads);
    expect(pushesOn(router), 2);
  });
}
