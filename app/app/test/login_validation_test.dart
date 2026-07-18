import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/login_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: const MaterialApp(home: LoginScreen()),
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

  testWidgets('a rejected login shows the structured API message', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..loginError = const WaxDeckApiException(
        code: 'unauthenticated',
        message: 'wrong username or password',
        statusCode: 401,
      );
    await tester.pumpWidget(_host(repo));

    await tester.enterText(find.byKey(const Key('login-username')), 'admin');
    await tester.enterText(find.byKey(const Key('login-password')), 'nope');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(repo.loginCalls, hasLength(1));
    expect(find.byKey(const Key('login-error')), findsOneWidget);
    expect(find.text('wrong username or password'), findsOneWidget);
  });
}
