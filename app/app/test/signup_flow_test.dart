import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/login_screen.dart';
import 'package:waxdeck/src/providers.dart';

import 'fakes.dart';
import 'routed_host.dart';

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: routedHost(const LoginScreen()),
);

void main() {
  testWidgets('open signup queues the request and says so', (tester) async {
    final repo = FakeRepository();
    repo.adminSettings = repo.adminSettings.copyWith(signupEnabled: true);
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    // Open signup gets the louder label.
    expect(find.text('Request an account'), findsOneWidget);
    await tester.tap(find.byKey(const Key('signup-open')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('signup-username')), 'pippin');
    await tester.enterText(
      find.byKey(const Key('signup-password')),
      'second-breakfast',
    );
    await tester.tap(find.byKey(const Key('signup-submit')));
    await tester.pumpAndSettle();

    final call = repo.signupCalls.single;
    expect(call.username, 'pippin');
    expect(call.inviteToken, isNull);
    expect(find.byKey(const Key('signup-result')), findsOneWidget);
    expect(find.textContaining('approve'), findsOneWidget);
  });

  testWidgets('an invite signup lands back on login prefilled', (tester) async {
    final repo = FakeRepository();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    // Without open signup the link still serves invite holders.
    expect(find.text('Have an invite?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('signup-open')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('signup-username')), 'sam');
    await tester.enterText(
      find.byKey(const Key('signup-password')),
      'po-ta-toes',
    );
    await tester.enterText(
      find.byKey(const Key('signup-invite-token')),
      'invite-token-0',
    );
    await tester.tap(find.byKey(const Key('signup-submit')));
    await tester.pumpAndSettle();

    expect(repo.signupCalls.single.inviteToken, 'invite-token-0');
    // Back on the login form with the fresh username filled in.
    expect(find.byKey(const Key('login-submit')), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'sam'), findsOneWidget);
  });
}
