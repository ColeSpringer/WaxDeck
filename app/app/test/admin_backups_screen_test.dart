import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/backups_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

/// A viewport tall enough to hold archives, schedules, and retention,
/// so no test scrolls through lazily built rows.
Future<void> _pump(WidgetTester tester, FakeRepository repo) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: BackupsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Backup _backup(String id, {String state = 'done'}) => Backup(
  id: id,
  state: state,
  trigger: 'manual',
  fileName: 'waxdeck-$id.tar.zst',
  sizeBytes: 3 * 1024 * 1024,
  createdAt: DateTime.utc(2026, 7, 18, 3),
  finishedAt: state == 'done' ? DateTime.utc(2026, 7, 18, 3, 5) : null,
);

void main() {
  testWidgets('lists archives and the three schedules', (tester) async {
    final repo = FakeRepository();
    repo.backupsById['ba-1'] = _backup('ba-1');
    await _pump(tester, repo);

    final row = find.byKey(const ValueKey('backup-row-ba-1'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(
        of: row,
        matching: find.textContaining('3.0 MB, done, manual'),
      ),
      findsOneWidget,
    );
    for (final kind in const ['scan', 'backup', 'prune']) {
      expect(find.byKey(ValueKey('schedule-row-$kind')), findsOneWidget);
    }
  });

  testWidgets('staging a restore shows the plan and the banner', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.backupsById['ba-1'] = _backup('ba-1');
    repo.restorePlans['ba-1'] = RestorePlan(
      backupId: 'ba-1',
      stagedAt: DateTime.utc(2026, 7, 20, 13),
      keyfilePresent: true,
      keyfileMatches: false,
      sealedCasualties: const [
        SealedCasualty(kind: 'scrobbler', name: 'lastfm: barliman'),
      ],
      warnings: const ['listens after 2026-07-18 are lost'],
    );
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('backup-menu-ba-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stage restore...'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-restore-confirm')));
    await tester.pumpAndSettle();

    expect(repo.stageRestoreCalls, ['ba-1']);
    final dialog = find.byKey(const Key('restore-plan-dialog'));
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(
        of: dialog,
        matching: find.textContaining('applies at the next server restart'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('lastfm: barliman'), findsOneWidget);
    expect(
      find.textContaining('listens after 2026-07-18 are lost'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('restore-plan-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('restore-banner')), findsOneWidget);

    await tester.tap(find.byKey(const Key('restore-cancel')));
    await tester.pumpAndSettle();
    expect(repo.cancelStagedRestoreCalls, 1);
    expect(find.byKey(const Key('restore-banner')), findsNothing);
  });

  testWidgets('an invalid cron surfaces the server message', (tester) async {
    final repo = FakeRepository();
    await _pump(tester, repo);

    await tester.enterText(
      find.byKey(const Key('schedule-cron-scan')),
      'whenever feels right',
    );
    await tester.tap(find.byKey(const Key('schedule-save-scan')));
    await tester.pumpAndSettle();

    expect(repo.putScheduleCalls.single.kind, 'scan');
    expect(find.text('invalid cron expression'), findsOneWidget);
    // The stored schedule is untouched.
    expect(repo.schedules['scan']!.cron, '0 3 * * *');
  });

  testWidgets('a valid schedule save stores cron and enablement', (
    tester,
  ) async {
    final repo = FakeRepository();
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('schedule-enabled-backup')));
    await tester.enterText(
      find.byKey(const Key('schedule-cron-backup')),
      '30 4 * * 1',
    );
    await tester.tap(find.byKey(const Key('schedule-save-backup')));
    await tester.pumpAndSettle();

    expect(repo.schedules['backup']!.cron, '30 4 * * 1');
    expect(repo.schedules['backup']!.enabled, isTrue);
  });
}
