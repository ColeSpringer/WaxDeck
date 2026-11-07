import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck/src/l10n/off_tree.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

void main() {
  testWidgets('boots to the login screen when unauthenticated', (tester) async {
    final repo = FakeRepository();
    await pumpWholeApp(tester, container: appContainer(repo: repo));

    expect(find.text('WaxDeck'), findsOneWidget);
    expect(find.text('Music, podcasts, and audiobooks'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.loginUsername),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.loginPassword),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.loginSubmit),
      findsOneWidget,
    );
  });

  testWidgets('skips login when the server already has a session', (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(
        authenticated: true,
        user: WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']),
      ),
      items: [testItem('tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE')],
    );
    await pumpWholeApp(tester, container: appContainer(repo: repo));

    expect(
      find.bySemanticsIdentifier(SemanticsIds.loginUsername),
      findsNothing,
    );
    // Landed on home, with the library on its shelves. `findsWidgets`
    // rather than `findsOneWidget`: the shelves overlap by construction,
    // so a fresh unplayed track is on Recently added and on Never played
    // at once, and counting titles would be counting shelves.
    expect(find.bySemanticsIdentifier(SemanticsIds.homeScreen), findsOneWidget);
    expect(find.text('Prancing Pony Blues'), findsWidgets);
  });

  testWidgets('copy drawn off the tree follows the device language', (
    tester,
  ) async {
    await pumpWholeApp(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WaxDeckApp)),
    );

    tester.platformDispatcher.localesTestValue = const [Locale('es')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpAndSettle();

    expect(container.read(offTreeL10nProvider).localeName, 'es');
  });
}
