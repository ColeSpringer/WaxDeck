import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

void main() {
  testWidgets('boots to the login screen when unauthenticated', (tester) async {
    final repo = FakeRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: const WaxDeckApp(),
      ),
    );
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
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: const WaxDeckApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login-username')), findsNothing);
    expect(find.text('Prancing Pony Blues'), findsOneWidget);
  });
}
