import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/account_binder.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/settings_registry.dart';
import 'package:waxdeck/src/sync/server_event_bus.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

const _plain = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  username: 'listener',
  roles: ['user'],
);
const _admin = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  username: 'listener',
  roles: ['user', 'admin'],
);

void main() {
  late FakeRepository repo;
  late ServerEventBus bus;
  late ProviderContainer container;

  setUp(() async {
    repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _plain),
    );
    bus = ServerEventBus();
    container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        serverEventBusProvider.overrideWith((ref) => bus),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(bus.dispose);
    await container.read(authControllerProvider.future);
  });

  test('an account marker re-reads the session and the gates follow', () async {
    final alive = container.listen(accountBinderProvider, (_, _) {});
    addTearDown(alive.close);
    expect(container.read(isAdminProvider), isFalse);

    repo.sessionState = const SessionState(authenticated: true, user: _admin);
    bus.add(const ServerSyncEvent(kind: 'account'));
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(isAdminProvider),
      isTrue,
      reason: 'a role granted mid-session has to reach the gates that read it',
    );
    expect(
      container.read(authControllerProvider).hasValue,
      isTrue,
      reason:
          'the redirect reads the value, so the refresh never shows loading',
    );
  });

  test('markers about other things are ignored', () async {
    final alive = container.listen(accountBinderProvider, (_, _) {});
    addTearDown(alive.close);

    repo.sessionState = const SessionState(authenticated: true, user: _admin);
    bus.add(const ServerSyncEvent(kind: 'review', pid: 'rv-1'));
    await Future<void>.delayed(Duration.zero);

    expect(container.read(isAdminProvider), isFalse);
  });
}
