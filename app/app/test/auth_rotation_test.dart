import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

const _user = WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']);

void main() {
  test(
    'a 401 during cold-start rotation drops the whole local session',
    () async {
      final repo = FakeRepository()
        ..sessionState = const SessionState(authenticated: true, user: _user)
        ..refreshError = const WaxDeckApiException(
          code: 'unauthenticated',
          message: 'session revoked',
          statusCode: 401,
        );
      final store = InMemoryCredentialStore()..token = 'stored-token';
      final container = ProviderContainer(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          credentialStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);

      // The probe itself succeeds (the token dies between probe and
      // rotation), so build reports signed in.
      final session = await container.read(authControllerProvider.future);
      expect(session.authenticated, isTrue);

      // The fire-and-forget rotation then hits the 401. The controller
      // must not leave the UI signed in over a dead credential.
      await pumpEventQueue();
      final after = container.read(authControllerProvider).value;
      expect(
        after?.authenticated,
        isFalse,
        reason: 'a revoked session must land on the login screen',
      );
      expect(store.token, isNull, reason: 'the dead token must be cleared');
      expect(repo.authToken, isNull);
    },
  );

  test('a transient rotation failure keeps the session and token', () async {
    final repo = FakeRepository()
      ..sessionState = const SessionState(authenticated: true, user: _user)
      ..refreshError = const WaxDeckApiException(
        code: 'internal',
        message: 'flaky network',
        statusCode: 500,
      );
    final store = InMemoryCredentialStore()..token = 'stored-token';
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        credentialStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);

    final session = await container.read(authControllerProvider.future);
    expect(session.authenticated, isTrue);
    await pumpEventQueue();
    expect(container.read(authControllerProvider).value?.authenticated, isTrue);
    expect(store.token, 'stored-token');
  });
}
