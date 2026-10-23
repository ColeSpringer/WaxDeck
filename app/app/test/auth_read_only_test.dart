import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';

import 'fakes.dart';

ProviderContainer _container(FakeRepository repo) {
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test(
    'signing in on a read-only server picks the switch up at once',
    () async {
      // The sign-in answer names the account and no more: the server's own
      // state arrives with the session, so a person who signs in while the
      // switch is on must not have to wait for the next marker to be told.
      final repo = FakeRepository()..serverReadOnly = true;
      final container = _container(repo);
      await container.read(authControllerProvider.future);
      expect(container.read(serverReadOnlyProvider), isFalse);

      await container
          .read(authControllerProvider.notifier)
          .login(username: 'admin', password: 'correct-horse');
      await pumpEventQueue();

      expect(container.read(authControllerProvider).value?.authenticated, true);
      expect(container.read(serverReadOnlyProvider), isTrue);
    },
  );

  test('a sign-in on a writable server says nothing', () async {
    final repo = FakeRepository();
    final container = _container(repo);
    await container.read(authControllerProvider.future);

    await container
        .read(authControllerProvider.notifier)
        .login(username: 'admin', password: 'correct-horse');
    await pumpEventQueue();

    expect(container.read(serverReadOnlyProvider), isFalse);
  });

  test('signing out forgets the switch', () async {
    final repo = FakeRepository()..serverReadOnly = true;
    final container = _container(repo);
    await container.read(authControllerProvider.future);
    await container
        .read(authControllerProvider.notifier)
        .login(username: 'admin', password: 'correct-horse');
    await pumpEventQueue();
    expect(container.read(serverReadOnlyProvider), isTrue);

    await container.read(authControllerProvider.notifier).logout();
    await pumpEventQueue();

    expect(container.read(serverReadOnlyProvider), isFalse);
  });
}
