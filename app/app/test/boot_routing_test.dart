import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';

import 'fakes.dart';

Widget _app(FakeRepository repo, {InMemoryCredentialStore? store}) =>
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        credentialStoreProvider.overrideWithValue(
          store ?? InMemoryCredentialStore(),
        ),
      ],
      child: const WaxDeckApp(),
    );

void main() {
  testWidgets('routes to setup while the server has no accounts', (
    tester,
  ) async {
    final repo = FakeRepository(bootstrapNeeded: true);
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('setup-username')), findsOneWidget);
    expect(find.byKey(const Key('setup-submit')), findsOneWidget);
    expect(find.byKey(const Key('login-username')), findsNothing);
  });

  testWidgets('routes to login once accounts exist', (tester) async {
    final repo = FakeRepository();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login-username')), findsOneWidget);
    expect(find.byKey(const Key('setup-username')), findsNothing);
  });

  testWidgets('setup submits and lands signed in', (tester) async {
    final repo = FakeRepository(
      bootstrapNeeded: true,
      items: [testItem('tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE')],
    );
    final store = InMemoryCredentialStore();
    await tester.pumpWidget(_app(repo, store: store));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('setup-username')), 'admin');
    await tester.enterText(
      find.byKey(const Key('setup-password')),
      'wax-setup-pass',
    );
    await tester.enterText(
      find.byKey(const Key('setup-confirm')),
      'wax-setup-pass',
    );
    await tester.tap(find.byKey(const Key('setup-submit')));
    await tester.pumpAndSettle();

    expect(repo.bootstrapCalls, hasLength(1));
    expect(repo.bootstrapCalls.single.username, 'admin');
    expect(repo.bootstrapCalls.single.password, 'wax-setup-pass');
    expect(find.byKey(const Key('setup-username')), findsNothing);
    // Landed on home, with the library on its shelves. `findsWidgets`
    // rather than `findsOneWidget`: the shelves overlap by construction,
    // so a fresh unplayed track is on Recently added and on Never played
    // at once, and counting titles would be counting shelves.
    expect(find.bySemanticsIdentifier(SemanticsIds.homeScreen), findsOneWidget);
    expect(find.text('Prancing Pony Blues'), findsWidgets);
    // Native path: the bearer token is persisted for the next launch.
    expect(store.token, 'test-token');
  });

  testWidgets('a short password never reaches the API', (tester) async {
    final repo = FakeRepository(bootstrapNeeded: true);
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('setup-username')), 'admin');
    await tester.enterText(find.byKey(const Key('setup-password')), 'short');
    await tester.enterText(find.byKey(const Key('setup-confirm')), 'short');
    await tester.tap(find.byKey(const Key('setup-submit')));
    await tester.pump();

    expect(find.text('Use at least 8 characters'), findsOneWidget);
    expect(repo.bootstrapCalls, isEmpty);
  });

  testWidgets('a mismatched confirmation never reaches the API', (
    tester,
  ) async {
    final repo = FakeRepository(bootstrapNeeded: true);
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('setup-username')), 'admin');
    await tester.enterText(
      find.byKey(const Key('setup-password')),
      'wax-setup-pass',
    );
    await tester.enterText(
      find.byKey(const Key('setup-confirm')),
      'wax-other-pass',
    );
    await tester.tap(find.byKey(const Key('setup-submit')));
    await tester.pump();

    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(repo.bootstrapCalls, isEmpty);
  });
}
