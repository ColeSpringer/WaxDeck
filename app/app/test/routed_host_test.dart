import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/books/book_screen.dart';
import 'package:waxdeck/src/books/books_screen.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';

/// The harness has to route as the app does, or a door a screen takes
/// under it walks a path the app never walks.
void main() {
  testWidgets('a door taken inside the shell pushes over the page', (
    tester,
  ) async {
    await pumpApp(tester, const SizedBox());
    final router =
        tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig!
            as GoRouter;
    router.go(WaxRoute.books);
    await tester.pumpAndSettle();
    expect(find.byType(BooksScreen), findsOneWidget);

    // What every menu door takes: in the shell it is a plain push, so
    // nothing under the page is popped or replaced on the way.
    unawaited(
      router.pushInShell<void>(WaxRoute.book('bk-01JZX5N8QW3F4V9T2B7KDBOOK1')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BookScreen), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(BooksScreen), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.uri.path, WaxRoute.books);
  });
}
