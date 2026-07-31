import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

// The credential store must be faked wherever the auth controller builds:
// the real one talks to a platform channel no test host answers.
Widget _app(FakeRepository repo) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
  ],
  child: const WaxDeckApp(),
);

void main() {
  testWidgets('boots to the login screen when unauthenticated', (tester) async {
    final repo = FakeRepository();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    expect(find.text('WaxDeck'), findsOneWidget);
    expect(find.text('Music, podcasts, and audiobooks'), findsOneWidget);
    expect(find.byKey(const Key('login-username')), findsOneWidget);
    expect(find.byKey(const Key('login-password')), findsOneWidget);
    expect(find.byKey(const Key('login-submit')), findsOneWidget);
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
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login-username')), findsNothing);
    // Landed on home, with the library on its shelves. `findsWidgets`
    // rather than `findsOneWidget`: the shelves overlap by construction,
    // so a fresh unplayed track is on Recently added and on Never played
    // at once, and counting titles would be counting shelves.
    expect(find.bySemanticsIdentifier(SemanticsIds.homeScreen), findsOneWidget);
    expect(find.text('Prancing Pony Blues'), findsWidgets);
  });
}
