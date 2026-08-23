import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

/// Where a shell message ends up on screen.
///
/// The channel itself is asserted a dozen times across the suite by
/// reading the notifier, which is the half that has always worked. What
/// nothing covered is the other half: the shell is what renders these,
/// and the surfaces that raise the ones with an action - an instant mix,
/// a queue edit - raise them from over the player, which is a route of
/// its own above the shell. Whether the button survives that trip is the
/// question, and it is answered here rather than only in the e2e suite.
///
/// Mounted as the whole app, deliberately: `routed_host.dart` builds its
/// own `MaterialApp.router` with no shell in it, so the listener that
/// draws these would not be there at all.

const _user = WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']);

ProviderContainer _signedInContainer() => ProviderContainer(
  overrides: [
    repositoryProvider.overrideWithValue(
      FakeRepository(
        sessionState: const SessionState(authenticated: true, user: _user),
        items: [testItem('tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE')],
      ),
    ),
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
  ],
);

void main() {
  testWidgets('a message with an action is reachable from over the player', (
    tester,
  ) async {
    final container = _signedInContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const WaxDeckApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The player over the shell, which is where the mix sheet raises its
    // message from.
    container.read(routerProvider).push(WaxRoute.nowPlaying);
    await tester.pumpAndSettle();

    var opened = false;
    container
        .read(shellMessengerProvider.notifier)
        .show(
          'Added 2 tracks to the queue',
          actionLabel: 'Open',
          onAction: () => opened = true,
          actionSemanticsId: SemanticsIds.queueOpen,
        );
    await tester.pumpAndSettle();

    final action = find.bySemanticsIdentifier(SemanticsIds.queueOpen);
    expect(
      action,
      findsOneWidget,
      reason: 'the only affordance a mix leaves is drawn where it can be used',
    );
    expect(find.text('Added 2 tracks to the queue'), findsOneWidget);

    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });

  testWidgets('a message is drawn on an ordinary screen as well', (
    tester,
  ) async {
    // The other position, so the one above is a comparison rather than
    // an isolated fact: no route pushed, the shell's own branch showing.
    final container = _signedInContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const WaxDeckApp(),
      ),
    );
    await tester.pumpAndSettle();

    container.read(shellMessengerProvider.notifier).show('Scan started');
    await tester.pumpAndSettle();

    expect(find.text('Scan started'), findsOneWidget);
  });
}
