import 'localized_host.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/backups_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

/// A picker resolving pickFile to one fixed archive.
class _ZipPicker implements FilePickerPort {
  _ZipPicker(this.archive);

  final PickedAudioFile? archive;

  @override
  bool get canPickFolders => false;

  @override
  Future<List<PickedAudioFile>> pickAudioFiles({
    String audioLabel = '',
    String anyLabel = '',
  }) async => const [];

  @override
  Future<List<PickedAudioFile>> pickAudioFolder() async => const [];

  @override
  Future<PickedAudioFile?> pickFile({
    required Set<String> extensions,
    required String label,
    String anyLabel = '',
  }) async => archive;
}

/// A viewport tall enough to hold the archives and the retention
/// fields, so no test scrolls through lazily built rows.
Future<void> _pump(
  WidgetTester tester,
  FakeRepository repo, {
  FilePickerPort? picker,
}) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        filePickerProvider.overrideWithValue(picker),
      ],
      child: localizedHost(const BackupsScreen()),
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
  testWidgets('lists archives', (tester) async {
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

  testWidgets('importing an archive streams it and refreshes the list', (
    tester,
  ) async {
    final repo = FakeRepository();
    final zipBytes = Uint8List.fromList(List.filled(6144, 7));
    final picker = _ZipPicker(
      PickedAudioFile(
        name: 'waxdeck-elsewhere.zip',
        size: zipBytes.length,
        openRead: ([int? start, int? end]) => Stream.value(
          Uint8List.sublistView(zipBytes, start ?? 0, end ?? zipBytes.length),
        ),
      ),
    );
    await _pump(tester, repo, picker: picker);

    await tester.tap(find.byKey(const Key('backup-import')));
    await tester.pumpAndSettle();

    expect(repo.importBackupByteCounts, [zipBytes.length]);
    // The imported archive joined the listing.
    expect(find.textContaining('imported'), findsWidgets);
  });

  testWidgets('hides the import button without a picker port', (tester) async {
    final repo = FakeRepository();
    await _pump(tester, repo);

    expect(find.byKey(const Key('backup-import')), findsNothing);
    expect(find.byKey(const Key('backup-create')), findsOneWidget);
  });
}
