import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/connect_server_screen.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/auth/server_address.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';
import 'routed_host.dart';

void main() {
  const health = ServerHealth(status: 'ok', version: 'test', apiVersion: 1);

  Widget host({
    required CredentialStorePort store,
    required Future<ServerHealth> Function(String) probe,
  }) => ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(FakeRepository()),
      credentialStoreProvider.overrideWithValue(store),
      bootServerAddressProvider.overrideWithValue(null),
      serverProbeProvider.overrideWithValue(probe),
    ],
    child: routedHost(const ConnectServerScreen()),
  );

  testWidgets('a reachable address is adopted and the token dropped', (
    tester,
  ) async {
    final store = InMemoryCredentialStore()..token = 'stale-token';
    final probed = <String>[];
    await tester.pumpWidget(
      host(
        store: store,
        probe: (base) async {
          probed.add(base);
          if (base == 'http://wax.example.com') return health;
          throw const WaxDeckApiException(
            code: 'transport',
            message: 'no route',
          );
        },
      ),
    );
    await tester.enterText(
      find.byKey(const Key(SemanticsIds.connectServerAddress)),
      'wax.example.com',
    );
    await tester.tap(find.byKey(const Key(SemanticsIds.connectServerSubmit)));
    await tester.pumpAndSettle();

    // https was tried first and refused; http answered and won.
    expect(probed, ['https://wax.example.com', 'http://wax.example.com']);
    expect(store.serverAddress, 'http://wax.example.com');
    expect(
      store.token,
      isNull,
      reason: 'a token minted elsewhere is never presented to this server',
    );
  });

  testWidgets('an unreachable address reports and adopts nothing', (
    tester,
  ) async {
    final store = InMemoryCredentialStore();
    await tester.pumpWidget(
      host(
        store: store,
        probe: (_) async => throw const WaxDeckApiException(
          code: 'transport-timeout',
          message: 'timed out',
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key(SemanticsIds.connectServerAddress)),
      'wax.example.com',
    );
    await tester.tap(find.byKey(const Key(SemanticsIds.connectServerSubmit)));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key(SemanticsIds.connectServerError)),
      findsOneWidget,
    );
    expect(store.serverAddress, isNull);
  });

  testWidgets('junk is refused before any probe fires', (tester) async {
    var probes = 0;
    await tester.pumpWidget(
      host(
        store: InMemoryCredentialStore(),
        probe: (_) async {
          probes++;
          return health;
        },
      ),
    );
    await tester.enterText(
      find.byKey(const Key(SemanticsIds.connectServerAddress)),
      'not an address',
    );
    await tester.tap(find.byKey(const Key(SemanticsIds.connectServerSubmit)));
    await tester.pumpAndSettle();

    expect(probes, 0);
    expect(
      find.byKey(const Key(SemanticsIds.connectServerError)),
      findsOneWidget,
    );
  });
}
