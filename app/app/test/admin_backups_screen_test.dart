import 'localized_host.dart';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/backups_screen.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/notifications/notifications_controller.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

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
    UploadFormatSets formats = const UploadFormatSets(),
  }) async => const [];

  @override
  Future<FolderPick> pickAudioFolder({
    UploadFormatSets formats = const UploadFormatSets(),
  }) async => const FolderPick();

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
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      ],
      child: localizedHost(const BackupsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// The same host, with motion off: a running archive holds the create
/// button busy, and a busy ring only settles with motion off.
Future<void> _pumpStill(WidgetTester tester, FakeRepository repo) async {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await _pump(tester, repo);
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

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.backupMenu('ba-1')),
    );
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

  testWidgets('a running archive is read again until it is done', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.backupsById['ba-1'] = _backup('ba-1', state: 'running');
    await _pumpStill(tester, repo);
    final reads = repo.backupReads;

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(repo.backupReads, reads + 1);

    repo.backupsById['ba-1'] = _backup('ba-1');
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(repo.backupReads, reads + 2);

    await tester.pump(const Duration(seconds: 15));
    expect(repo.backupReads, reads + 2, reason: 'nothing running, no poll');
  });

  testWidgets("a finished archive's inbox row reads the list again", (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(
        authenticated: true,
        user: WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']),
      ),
    );
    repo.backupsById['ba-1'] = _backup('ba-1');
    await _pump(tester, repo);
    final reads = repo.backupReads;
    final container = ProviderScope.containerOf(
      tester.element(find.byType(BackupsScreen)),
    );

    repo.inbox.add(
      ServerNotification(
        id: 'nf-1',
        event: 'backup-completed',
        title: 'Backup finished',
        body: 'waxdeck-ba-2.tar.zst',
        createdAt: DateTime.now().add(const Duration(seconds: 1)),
      ),
    );
    container.invalidate(notificationsProvider);
    await tester.pumpAndSettle();

    expect(repo.backupReads, reads + 1);
  });

  testWidgets("an archive's row is news whatever the server's clock says", (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(
        authenticated: true,
        user: WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']),
      ),
    );
    // A row from before this read, which is not news.
    repo.inbox.add(
      ServerNotification(
        id: 'nf-old',
        event: 'backup-completed',
        title: 'Backup finished',
        body: 'waxdeck-ba-1.tar.zst',
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      ),
    );
    repo.backupsById['ba-1'] = _backup('ba-1');
    await _pump(tester, repo);
    final reads = repo.backupReads;
    final container = ProviderScope.containerOf(
      tester.element(find.byType(BackupsScreen)),
    );
    container.invalidate(notificationsProvider);
    await tester.pumpAndSettle();
    expect(repo.backupReads, reads, reason: 'a row it already had');

    // The server's clock an hour behind this device's.
    repo.inbox.add(
      ServerNotification(
        id: 'nf-2',
        event: 'backup-completed',
        title: 'Backup finished',
        body: 'waxdeck-ba-2.tar.zst',
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    );
    container.invalidate(notificationsProvider);
    await tester.pumpAndSettle();
    expect(repo.backupReads, reads + 1);
  });

  testWidgets('back up now is busy while an archive is being made', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.backupsById['ba-1'] = _backup('ba-1', state: 'running');
    await _pumpStill(tester, repo);

    final create = tester.widget<WaxButton>(
      find.byWidgetPredicate(
        (w) => w is WaxButton && w.semanticsId == SemanticsIds.backupCreate,
      ),
    );
    expect(create.busy, isTrue);
  });
}
