import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/adaptive_shell.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'localized_host.dart';

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

List<Override> _signedIn() => [
  repositoryProvider.overrideWithValue(
    FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _user),
      items: [testItem('tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE')],
    ),
  ),
  credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
];

ProviderContainer _signedInContainer() =>
    ProviderContainer(overrides: _signedIn());

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

  testWidgets('a message is drawn over a lone overlay', (tester) async {
    // A typed overlay location builds no shell beneath it.
    final container = _signedInContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const WaxDeckApp(),
      ),
    );
    await tester.pumpAndSettle();
    container.read(routerProvider).go(WaxRoute.queue);
    await tester.pumpAndSettle();
    expect(find.byType(AdaptiveShell), findsNothing);

    container.read(shellMessengerProvider.notifier).show('Could not restore');
    await tester.pumpAndSettle();

    expect(find.text('Could not restore'), findsOneWidget);
  });

  testWidgets('a bar up as the player opens over two visited tabs', (
    tester,
  ) async {
    // Each tab's top screen is a Scaffold of its own and draws the bar, so
    // a hidden tab would put a second copy of the bar's hero in flight.
    final container = _signedInContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const WaxDeckApp(),
      ),
    );
    await tester.pumpAndSettle();
    final router = container.read(routerProvider)..go(WaxRoute.health);
    await tester.pumpAndSettle();
    container.read(shellMessengerProvider.notifier).show('Scan started');
    await tester.pumpAndSettle();

    router.push<void>(WaxRoute.nowPlaying);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Scan started'), findsOneWidget);
  });

  testWidgets('an offer opens its shell screen from over the player', (
    tester,
  ) async {
    // The offer outlives the screen that raised it, so the player can be
    // over the shell by the time it is pressed, and a plain push from
    // under an overlay builds a second shell.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _user),
    );
    repo
      ..healthSummary = const HealthSummary(
        score: 90,
        totalItems: 4,
        evaluatedItems: 4,
        rules: [
          HealthRuleCount(
            rule: 'missing-art',
            label: 'Missing artwork',
            failing: 1,
            fixable: true,
          ),
        ],
      )
      ..fixHealthStart = const HealthFixStart(queued: 1, taskId: 'tk-fix');
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const WaxDeckApp(),
      ),
    );
    await tester.pumpAndSettle();
    final router = container.read(routerProvider)..go(WaxRoute.health);
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.healthFix('missing-art')),
    );
    await tester.pumpAndSettle();

    router.push<void>(WaxRoute.nowPlaying);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.openTasks));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.tasksScreen),
      findsOneWidget,
    );
    expect(find.byType(AdaptiveShell), findsOneWidget);
  });

  group('a run of messages', () {
    Future<ShellMessenger> pumpApp(WidgetTester tester) async {
      final container = _signedInContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const WaxDeckApp(),
        ),
      );
      await tester.pumpAndSettle();
      return container.read(shellMessengerProvider.notifier);
    }

    Future<void> outlast(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    }

    testWidgets('replaces its own bar on screen', (tester) async {
      final messenger = await pumpApp(tester);

      messenger.show('Unpinned Blue Train', channel: ShellChannel.pins);
      await tester.pumpAndSettle();
      messenger.show('Unpinned Kind of Blue', channel: ShellChannel.pins);
      await tester.pumpAndSettle();

      expect(find.text('Unpinned Blue Train'), findsNothing);
      expect(find.text('Unpinned Kind of Blue'), findsOneWidget);
    });

    testWidgets('waits behind another bar as its newest word', (tester) async {
      final messenger = await pumpApp(tester);

      messenger.show('Could not save');
      await tester.pumpAndSettle();
      messenger.show('Unpinned Blue Train', channel: ShellChannel.pins);
      await tester.pump();
      messenger.show('Unpinned Kind of Blue', channel: ShellChannel.pins);
      await tester.pumpAndSettle();

      expect(find.text('Could not save'), findsOneWidget);
      await outlast(tester);
      expect(find.text('Could not save'), findsNothing);
      expect(find.text('Unpinned Kind of Blue'), findsOneWidget);
      await outlast(tester);
      expect(find.text('Unpinned Blue Train'), findsNothing);
    });

    testWidgets('an offer made to wait stays until it is answered', (
      tester,
    ) async {
      final messenger = await pumpApp(tester);

      messenger.show(
        'Marked finished',
        actionLabel: 'Undo',
        onAction: () {},
        persist: true,
      );
      await tester.pumpAndSettle();
      await outlast(tester);
      expect(find.text('Marked finished'), findsOneWidget);

      // The next message takes its place rather than waiting behind it.
      messenger.show('Scan started');
      await tester.pumpAndSettle();
      expect(find.text('Marked finished'), findsNothing);
      expect(find.text('Scan started'), findsOneWidget);
    });

    testWidgets('under accessible navigation every offer stays', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final messenger = await pumpApp(tester);

      messenger.show(
        'Added 2 tracks to the queue',
        actionLabel: 'Open',
        onAction: () {},
      );
      await tester.pumpAndSettle();
      await outlast(tester);
      expect(find.text('Added 2 tracks to the queue'), findsOneWidget);
    });

    testWidgets('an offer made to wait yields only after its time', (
      tester,
    ) async {
      final messenger = await pumpApp(tester);

      messenger.show(
        'Identifying 2 files',
        actionLabel: 'Open review',
        onAction: () {},
        persist: true,
      );
      await tester.pump();
      messenger.show('Skipped 1 Audible file');
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Identifying 2 files'), findsOneWidget);

      await outlast(tester);
      expect(find.text('Identifying 2 files'), findsNothing);
      expect(find.text('Skipped 1 Audible file'), findsOneWidget);
    });

    testWidgets('an answered offer lets the next message on', (tester) async {
      final messenger = await pumpApp(tester);
      var undone = false;

      messenger.show(
        'Restored Kind of Blue',
        actionLabel: 'Undo',
        onAction: () => undone = true,
      );
      await tester.pump();
      messenger.show('Scan started');
      await tester.pumpAndSettle();
      expect(find.text('Scan started'), findsNothing);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(undone, isTrue);
      expect(find.text('Scan started'), findsOneWidget);
    });

    testWidgets('an offer that waited its turn yields to the next', (
      tester,
    ) async {
      final messenger = await pumpApp(tester);

      messenger.show('Saved');
      await tester.pump();
      messenger.show(
        'Marked finished',
        actionLabel: 'Undo',
        onAction: () {},
        persist: true,
      );
      await tester.pump();
      messenger.show('Could not sync');
      await tester.pumpAndSettle();

      await outlast(tester);
      expect(find.text('Marked finished'), findsOneWidget);
      await outlast(tester);
      expect(find.text('Marked finished'), findsNothing);
      expect(find.text('Could not sync'), findsOneWidget);
    });

    testWidgets('an offer answers one press', (tester) async {
      final messenger = await pumpApp(tester);
      var undone = 0;

      messenger.show(
        'Restored Kind of Blue',
        actionLabel: 'Undo',
        onAction: () => undone++,
        persist: true,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo'));
      await tester.pump();
      await tester.tap(find.text('Undo'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(undone, 1);
    });

    testWidgets('a waiting offer leaves with the session', (tester) async {
      final container = _signedInContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const WaxDeckApp(),
        ),
      );
      await tester.pumpAndSettle();

      container
          .read(shellMessengerProvider.notifier)
          .show(
            'Marked finished',
            actionLabel: 'Undo',
            onAction: () {},
            persist: true,
          );
      await tester.pumpAndSettle();
      expect(find.text('Marked finished'), findsOneWidget);

      await container.read(authControllerProvider.notifier).signOutLocally();
      await tester.pumpAndSettle();
      expect(find.byType(AdaptiveShell), findsNothing);
      expect(find.text('Marked finished'), findsNothing);
    });

    testWidgets('a message with nowhere to be drawn holds up nothing', (
      tester,
    ) async {
      // Car mode's playing face has no Scaffold, which a debug build
      // asserts on. A ProviderScope reports what a listener throws
      // rather than failing the test.
      final scaffold = ValueNotifier(false);
      addTearDown(scaffold.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: localizedHost(
            ShellMessageHost(
              child: ValueListenableBuilder<bool>(
                valueListenable: scaffold,
                builder: (context, on, _) => on
                    ? const Scaffold(body: SizedBox.expand())
                    : const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      final messenger = ProviderScope.containerOf(
        tester.element(find.byType(ShellMessageHost)),
      ).read(shellMessengerProvider.notifier);

      messenger.show('Skipped 1 unplayable track');
      await tester.pump();
      expect(tester.takeException(), isAssertionError);

      scaffold.value = true;
      await tester.pumpAndSettle();
      messenger.show('Scan started');
      await tester.pumpAndSettle();
      expect(find.text('Scan started'), findsOneWidget);
    });

    testWidgets('leaves other messages to take their turns', (tester) async {
      final messenger = await pumpApp(tester);

      messenger.show('Scan started');
      await tester.pump();
      messenger.show('Link copied');
      await tester.pumpAndSettle();

      expect(find.text('Scan started'), findsOneWidget);
      await outlast(tester);
      expect(find.text('Link copied'), findsOneWidget);
    });
  });
}
