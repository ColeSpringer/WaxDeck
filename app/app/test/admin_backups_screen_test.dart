import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/admin_providers.dart';
import 'package:waxdeck/src/admin/backups_screen.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/notifications/notifications_controller.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'localized_host.dart';
import 'wax_finders.dart';

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

/// Records the body of every settings write.
class _RecordedWrites extends FakeRepository {
  final bodies = <AdminSettingsChange>[];

  @override
  Future<AdminSettings> putAdminSettings(AdminSettingsChange change) {
    bodies.add(change);
    return super.putAdminSettings(change);
  }
}

String _boxText(WidgetTester tester, String key) =>
    tester.widget<WaxTextField>(find.byKey(Key(key))).controller!.text;

void main() {
  testWidgets('a retention save sends only the box the admin changed', (
    tester,
  ) async {
    final repo = _RecordedWrites();
    await _pump(tester, repo);
    Future<void> save(String count) async {
      await tester.enterText(find.byKey(const Key('backup-keep-count')), count);
      await tester.tap(find.byKey(const Key('backup-retention-save')));
      await tester.pumpAndSettle();
    }

    await save('8');
    expect(repo.bodies.single.backupKeepCount, 8);
    expect(repo.bodies.single.backupKeepBytes, isNull);

    // Another administrator sets the size while this one edits the count:
    // the save must not put the stale size back.
    repo.adminSettings = repo.adminSettings.copyWith(
      backupKeepBytes: 50 * 1024 * 1024,
    );
    await save('9');
    expect(repo.bodies.last.backupKeepCount, 9);
    expect(repo.bodies.last.backupKeepBytes, isNull);
    expect(repo.adminSettings.backupKeepBytes, 50 * 1024 * 1024);

    // Back to the value the box first showed still counts as a change.
    await save('5');
    expect(repo.bodies.last.backupKeepCount, 5);
  });

  testWidgets('an untouched retention box takes what the server stored, and '
      'a typed one keeps the typing', (tester) async {
    final repo = _RecordedWrites();
    await _pump(tester, repo);

    // Another administrator changes both while this one types in the
    // count, and the settings are read again.
    repo.adminSettings = repo.adminSettings.copyWith(
      backupKeepCount: 7,
      backupKeepBytes: 50 * 1024 * 1024,
    );
    await tester.enterText(find.byKey(const Key('backup-keep-count')), '9');
    ProviderScope.containerOf(
      tester.element(find.byType(BackupsScreen)),
    ).invalidate(adminSettingsProvider);
    await tester.pumpAndSettle();

    expect(_boxText(tester, 'backup-keep-mb'), '50');
    expect(_boxText(tester, 'backup-keep-count'), '9');
  });

  testWidgets('a retention save compares each box with what is stored', (
    tester,
  ) async {
    final repo = _RecordedWrites();
    await _pump(tester, repo);
    Future<void> save({String? count, String? mb}) async {
      if (count != null) {
        await tester.enterText(
          find.byKey(const Key('backup-keep-count')),
          count,
        );
      }
      if (mb != null) {
        await tester.enterText(find.byKey(const Key('backup-keep-mb')), mb);
      }
      await tester.tap(find.byKey(const Key('backup-retention-save')));
      await tester.pumpAndSettle();
    }

    // Another administrator sets the size while this one saves the count:
    // the answer brings it, and the untouched box shows it.
    repo.adminSettings = repo.adminSettings.copyWith(
      backupKeepBytes: 50 * 1024 * 1024,
    );
    await save(count: '8');
    expect(repo.bodies.last.backupKeepBytes, isNull);
    expect(_boxText(tester, 'backup-keep-mb'), '50');

    // The stored value typed back is no change and sends nothing.
    await save(mb: '50');
    expect(repo.bodies.last.backupKeepBytes, isNull);

    // The value the box showed first is stale now, so it is sent over the
    // newer one.
    await save(mb: '0');
    expect(repo.bodies.last.backupKeepBytes, 0);
    expect(repo.adminSettings.backupKeepBytes, 0);
  });

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
    // The house notice, not a box in some kind's hue.
    expect(
      find.descendant(of: dialog, matching: find.byType(WaxBanner)),
      findsOneWidget,
    );
    expect(find.textContaining('lastfm: barliman'), findsOneWidget);
    expect(
      find.textContaining('listens after 2026-07-18 are lost'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('restore-plan-done')));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.restoreBanner),
      findsOneWidget,
    );
    expect(find.byType(WaxBanner), findsOneWidget);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.restoreCancel));
    await tester.pumpAndSettle();
    expect(repo.cancelStagedRestoreCalls, 1);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.restoreBanner),
      findsNothing,
    );
  });

  testWidgets('a backup this server cannot open says why it did not stage', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.backupsById['ba-1'] = _backup('ba-1');
    await _pump(tester, repo);
    repo.adminError = const WaxDeckApiException(
      code: 'invalid-request',
      message: 'the archive was built from a different schema baseline',
      statusCode: 400,
      params: {'reason': 'incompatible-schema'},
    );

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.backupMenu('ba-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stage restore...'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-restore-confirm')));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(BackupsScreen)),
    );
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      startsWith('This backup was made by a WaxDeck version'),
    );
    expect(find.byKey(const Key('restore-plan-dialog')), findsNothing);
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

    await tester.tap(find.byKey(const Key(SemanticsIds.backupImport)));
    await tester.pumpAndSettle();

    expect(repo.importBackupByteCounts, [zipBytes.length]);
    // The imported archive joined the listing.
    expect(find.textContaining('imported'), findsWidgets);
  });

  testWidgets('hides the import button without a picker port', (tester) async {
    final repo = FakeRepository();
    await _pump(tester, repo);

    expect(find.byKey(const Key(SemanticsIds.backupImport)), findsNothing);
    expect(find.byKey(const Key(SemanticsIds.backupCreate)), findsOneWidget);
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
      waxControl<WaxButton>(SemanticsIds.backupCreate),
    );
    expect(create.busy, isTrue);
  });

  testWidgets('delete and retention are Wax controls', (tester) async {
    final repo = FakeRepository();
    repo.backupsById['ba-1'] = _backup('ba-1');
    await _pump(tester, repo);

    expect(
      tester
          .widget<WaxButton>(find.byKey(const Key('backup-retention-save')))
          .kind,
      WaxButtonKind.tonal,
    );

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.backupMenu('ba-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete...'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<WaxButton>(find.byKey(const Key('backup-delete-confirm')))
          .kind,
      WaxButtonKind.destructive,
    );
  });

  testWidgets('the archive list and retention wait as skeletons', (
    tester,
  ) async {
    final backups = Completer<List<Backup>>();
    final settings = Completer<void>();
    addTearDown(() {
      backups.complete(const []);
      if (!settings.isCompleted) settings.complete();
    });
    final repo = FakeRepository();
    await _pumpWith(tester, repo, [
      backupsProvider.overrideWith(() => _StalledBackups(backups.future)),
      adminSettingsProvider.overrideWith(() => _HeldSettings(settings.future)),
    ]);

    expect(find.byType(SkeletonShapes), findsNWidgets(2));
    expect(find.byType(WaxSpinner), findsNothing);
    expect(find.byKey(const Key('backup-keep-count')), findsNothing);

    settings.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('backup-keep-count')), findsOneWidget);
  });

  testWidgets(
    'a failed settings load shows the error and a Retry that reloads',
    (tester) async {
      final repo = FakeRepository();
      final failing = _FailsOnce();
      await _pumpWith(tester, repo, [
        adminSettingsProvider.overrideWith(() => failing),
      ]);

      expect(find.byKey(const Key('backup-keep-count')), findsNothing);
      final retry = find.bySemanticsIdentifier(
        SemanticsIds.backupRetentionRetry,
      );
      expect(retry, findsOneWidget);
      expect(find.byType(ErrorState), findsOneWidget);
      // Final, so live: the press is what reloads it, not a retry of
      // Riverpod's own.
      expect(
        tester
            .widget<WaxButton>(
              waxControl<WaxButton>(SemanticsIds.backupRetentionRetry),
            )
            .busy,
        isFalse,
      );
      expect(failing.builds, 1);

      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(failing.builds, 2);
      expect(find.byKey(const Key('backup-keep-count')), findsOneWidget);
      expect(retry, findsNothing);
    },
  );

  testWidgets('a list refused for good says why at once and offers to ask '
      'again, which reads it', (tester) async {
    final repo = FakeRepository()
      ..listError = const WaxDeckApiException(
        code: 'forbidden',
        message: 'not an administrator',
        statusCode: 403,
      );
    await _pumpWith(tester, repo, const []);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    // A refusal is final: asked once, and the card's retry is live.
    expect(repo.backupReads, 1);
    final retry = find.widgetWithText(WaxButton, 'Try again');
    expect(retry, findsOneWidget);
    expect(tester.widget<WaxButton>(retry).busy, isFalse);

    repo.listError = null;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(repo.backupReads, 2);
    expect(find.text('No backups yet'), findsOneWidget);
  });

  // With the app's own retry on: while an attempt runs a failing read is
  // AsyncLoading carrying the last error.
  testWidgets('failed loads say so at once, while they retry', (tester) async {
    _settingsReads = 0;
    _backupsReads = 0;
    await _pumpWith(tester, FakeRepository(), [
      adminSettingsProvider.overrideWith(_AlwaysFailsSettings.new),
      backupsProvider.overrideWith(_AlwaysFailsBackups.new),
    ]);
    // Past the first retry's delay: both reads are loading again.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.backupRetentionRetry),
      findsOneWidget,
    );
    // The list's own line and the retention pane's card both explain.
    expect(
      find.text('The server ran into a problem it could not handle.'),
      findsNWidgets(2),
    );
    expect(find.byType(SkeletonShapes), findsNothing);
    // Unmounted inside the test, so no retry timer outlives it.
    await tester.pumpWidget(const SizedBox());
  });
}

Future<void> _pumpWith(
  WidgetTester tester,
  FakeRepository repo,
  List<Override> overrides, {
  Duration? Function(int, Object)? retry,
}) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: retry,
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        ...overrides,
      ],
      child: localizedHost(const BackupsScreen()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

class _StalledBackups extends BackupsController {
  _StalledBackups(this._gate);

  final Future<List<Backup>> _gate;

  @override
  Future<List<Backup>> build() => _gate;
}

class _HeldSettings extends AdminSettingsController {
  _HeldSettings(this._gate);

  final Future<void> _gate;

  @override
  Future<AdminSettings> build() async {
    await _gate;
    return ref.watch(repositoryProvider).getAdminSettings();
  }
}

class _FailsOnce extends AdminSettingsController {
  int builds = 0;

  @override
  Future<AdminSettings> build() async {
    builds++;
    if (builds == 1) {
      // A refusal, so final: Riverpod does not retry it on its own.
      throw const WaxDeckApiException(
        code: 'forbidden',
        message: 'settings are unavailable',
        statusCode: 403,
      );
    }
    return ref.watch(repositoryProvider).getAdminSettings();
  }
}

const _internal = WaxDeckApiException(
  code: 'internal',
  message: 'unavailable',
  statusCode: 500,
);

/// Fails at once the first time and waits on every retry, as a server
/// that has gone away does.
var _settingsReads = 0;

class _AlwaysFailsSettings extends AdminSettingsController {
  @override
  Future<AdminSettings> build() async {
    if (_settingsReads++ > 0) await Completer<void>().future;
    throw _internal;
  }
}

var _backupsReads = 0;

class _AlwaysFailsBackups extends BackupsController {
  @override
  Future<List<Backup>> build() async {
    if (_backupsReads++ > 0) await Completer<void>().future;
    throw _internal;
  }
}
