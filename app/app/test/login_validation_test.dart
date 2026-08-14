import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/login_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';
import 'localized_host.dart';

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: localizedHost(const LoginScreen()),
);

void main() {
  testWidgets('empty form fails validation without calling the API', (
    tester,
  ) async {
    final repo = FakeRepository();
    await tester.pumpWidget(_host(repo));

    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();

    expect(find.text('Enter a username'), findsOneWidget);
    expect(find.text('Enter a password'), findsOneWidget);
    expect(repo.loginCalls, isEmpty);
  });

  testWidgets('only the missing field is flagged', (tester) async {
    final repo = FakeRepository();
    await tester.pumpWidget(_host(repo));

    await tester.enterText(find.byKey(const Key('login-username')), 'admin');
    await tester.tap(find.byKey(const Key('login-submit')));
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
    await tester.pumpWidget(_host(repo));

    await tester.enterText(find.byKey(const Key('login-username')), 'admin');
    await tester.enterText(find.byKey(const Key('login-password')), 'nope');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(repo.loginCalls, hasLength(1));
    expect(find.byKey(const Key('login-error')), findsOneWidget);
    expect(
      find.text('That username and password do not go together.'),
      findsOneWidget,
    );
    expect(find.text('invalid credentials'), findsNothing);
  });
}
