import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/migrate_screen.dart';
import 'package:waxdeck/src/providers.dart';

import 'fakes.dart';

/// A viewport tall enough for the whole form, so no test scrolls.
Future<void> _pump(WidgetTester tester, FakeRepository repo) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: MigrateScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('submits a navidrome import and points at the task list', (
    tester,
  ) async {
    final repo = FakeRepository();
    await _pump(tester, repo);

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
    await tester.tap(find.byKey(const Key('migrate-dry-run')));
    await tester.tap(find.byKey(const Key('migrate-submit')));
    await tester.pumpAndSettle();

    final call = repo.createMigrationCalls.single;
    expect(call.source, 'navidrome');
    expect(call.serverUrl, 'https://navi.example');
    expect(call.username, 'barliman');
    expect(call.password, 'butterbur');
    expect(call.token, isNull);
    expect(call.dryRun, isTrue);
    expect(find.text('Import started'), findsOneWidget);
    expect(find.text('Tasks'), findsOneWidget);
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
