import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/login_screen.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

Future<void> _mount(WidgetTester tester, FakeRepository repo) => mountApp(
  tester,
  const LoginScreen(),
  container: appContainer(repo: repo),
  routed: false,
);

void main() {
  testWidgets('empty form fails validation without calling the API', (
    tester,
  ) async {
    final repo = FakeRepository();
    await _mount(tester, repo);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.loginSubmit));
    await tester.pump();

    expect(find.text('Enter a username'), findsOneWidget);
    expect(find.text('Enter a password'), findsOneWidget);
    expect(repo.loginCalls, isEmpty);
  });

  testWidgets('only the missing field is flagged', (tester) async {
    final repo = FakeRepository();
    await _mount(tester, repo);

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.loginUsername),
      'admin',
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.loginSubmit));
    await tester.pump();

    expect(find.text('Enter a username'), findsNothing);
    expect(find.text('Enter a password'), findsOneWidget);
    expect(repo.loginCalls, isEmpty);
  });

  testWidgets('a rejected login says so in the reader\'s language', (
    tester,
  ) async {
    // The server answers `unauthenticated` with a log line, not copy,
    // and the table's sentence for that code tells a reader to sign in
    // again - which is what just failed. So the screen words it.
    final repo = FakeRepository()
      ..loginError = const WaxDeckApiException(
        code: 'unauthenticated',
        message: 'invalid credentials',
        statusCode: 401,
      );
    await _mount(tester, repo);

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.loginUsername),
      'admin',
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.loginPassword),
      'nope',
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.loginSubmit));
    await tester.pumpAndSettle();

    expect(repo.loginCalls, hasLength(1));
    expect(find.byKey(const Key(SemanticsIds.loginError)), findsOneWidget);
    expect(
      find.text('That username and password do not go together.'),
      findsOneWidget,
    );
    expect(find.text('invalid credentials'), findsNothing);
  });
}
