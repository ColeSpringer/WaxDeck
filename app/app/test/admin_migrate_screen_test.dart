import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/migrate_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart' show WaxSwitch;

import 'fakes.dart';
import 'routed_host.dart';

/// A viewport tall enough for the whole form, so no test scrolls.
Future<void> _pump(
  WidgetTester tester,
  FakeRepository repo, [
  ProviderContainer? container,
]) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final scope =
      container ??
      ProviderContainer(
        overrides: [repositoryProvider.overrideWithValue(repo)],
      );
  addTearDown(scope.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: scope,
      child: routedHost(const MigrateScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('submits a navidrome import and points at the task list', (
    tester,
  ) async {
    final repo = FakeRepository();
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
    );
    await _pump(tester, repo, container);

    await tester.enterText(
      find.byKey(const Key('migrate-server-url')),
      'https://navi.example',
    );
    await tester.enterText(
      find.byKey(const Key('migrate-username')),
      'barliman',
    );
    await tester.enterText(
      find.byKey(const Key('migrate-password')),
      'butterbur',
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('migrate-dry-run')),
        matching: find.byType(WaxSwitch),
      ),
    );
    await tester.tap(find.byKey(const Key('migrate-submit')));
    await tester.pumpAndSettle();

    final call = repo.createMigrationCalls.single;
    expect(call.source, 'navidrome');
    expect(call.serverUrl, 'https://navi.example');
    expect(call.username, 'barliman');
    expect(call.password, 'butterbur');
    expect(call.token, isNull);
    expect(call.dryRun, isTrue);
    // The message rides the shell's own channel now, like every other
    // admin screen's, so it is asserted where it is raised rather than
    // in a snackbar this screen would have to host itself.
    final raised = container.read(shellMessengerProvider);
    expect(shellMessageText(raised), 'Import started');
    // And it carries the way to watch the import, which is the whole
    // point of saying it started.
    expect(raised?.actionLabel, 'Tasks');
    expect(raised?.onAction, isNotNull);
  });

  testWidgets('audiobookshelf swaps credentials for a token field', (
    tester,
  ) async {
    final repo = FakeRepository();
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('migrate-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Audiobookshelf').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('migrate-token')), findsOneWidget);
    expect(find.byKey(const Key('migrate-username')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('migrate-server-url')),
      'https://abs.example',
    );
    await tester.enterText(find.byKey(const Key('migrate-token')), 'abs-token');
    await tester.tap(find.byKey(const Key('migrate-submit')));
    await tester.pumpAndSettle();

    final call = repo.createMigrationCalls.single;
    expect(call.source, 'audiobookshelf');
    expect(call.token, 'abs-token');
    expect(call.username, isNull);
  });
}
