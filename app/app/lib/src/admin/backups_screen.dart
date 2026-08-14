import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import '../uploads/audio_drop_area.dart';
import '../uploads/file_picker_port.dart';
import 'admin_console.dart';
import 'admin_providers.dart';

/// Backup archives with create, import, download, delete, staged
/// restore, and how many the server keeps.
///
/// The maintenance timetable moved to its own console section: only one
/// of those schedules is a backup, and a library scan buried at the
/// bottom of this page was a scan nobody found.
class BackupsScreen extends ConsumerWidget {
  const BackupsScreen({super.key});

  Future<void> _createBackup(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      await ref.read(repositoryProvider).createBackup();
      ref.invalidate(backupsProvider);
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
    }
  }

  Future<void> _pickAndImport(BuildContext context, WidgetRef ref) async {
    final picker = ref.read(filePickerProvider);
    if (picker == null) return;
    final file = await picker.pickFile(
      extensions: const {'zip'},
      label: context.l10n.adminBackupArchiveLabel,
      anyLabel: context.l10n.uploadsFileTypeAny,
    );
    if (file == null || !context.mounted) return;
    await _importArchive(context, ref, file);
  }

  /// Streams an archive up whole - never buffered in memory: archives
  /// carry both databases and a large catalog easily exceeds a hundred
  /// megabytes. Every picked reference carries a lazy reader (disk on
  /// native, the browser file handle on web).
  static Future<void> _importArchive(
    BuildContext context,
    WidgetRef ref,
    PickedAudioFile file,
  ) async {
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    final openRead = file.openRead;
    if (openRead == null) return;
    try {
      await ref
          .read(repositoryProvider)
          .importBackup(sizeBytes: file.size, openRead: () => openRead());
      ref.invalidate(backupsProvider);
      messenger.show(l10n.adminBackupImported(file.name));
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
    }
  }

  Future<void> _cancelRestore(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      await ref.read(repositoryProvider).cancelStagedRestore();
      ref.invalidate(stagedRestoreProvider);
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backups = ref.watch(backupsProvider);
    final staged = ref.watch(stagedRestoreProvider).value;
    final anyRunning = backups.value?.any((b) => b.state == 'running') ?? false;
    final picker = ref.watch(filePickerProvider);
    final sizeClass = WaxSizeClass.of(context);
    final l10n = context.l10n;
    return WaxScaffold(
      title: l10n.adminBackupsTitle,
      largeTitle: false,
      semanticsId: SemanticsIds.adminBackups,
      onBack: adminBack(context),
      // A sliver rather than a body: the drop target has to cover the
      // page to be a target at all, and the scaffold's body is an
      // adapter with no height of its own.
      slivers: <Widget>[
        SliverFillRemaining(
          child: AudioDropArea(
            extensions: const {'zip'},
            hint: l10n.adminBackupDropHint,
            onDropped: (files) async {
              for (final file in files) {
                if (!context.mounted) return;
                await _importArchive(context, ref, file);
              }
            },
            // The cap goes INSIDE the list, not around it. This page's
            // only scrollable is the ListView - the sliver above takes
            // exactly the viewport remainder, so the outer view has
            // nothing to scroll - and a 720-wide list left-aligned in a
            // wide window would leave a wheel over the right half of an
            // admin screen doing nothing at all. Full-width list, full
            // hit area, capped content; the gutter rides the list's own
            // padding, as it does on Users next door.
            child: ListView(
              padding: sizeClass.gutter.add(
                const EdgeInsets.symmetric(vertical: WaxSpace.s16),
              ),
              children: [
                ReadingColumn(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (staged != null)
                        _RestoreBanner(
                          plan: staged,
                          onCancel: () => _cancelRestore(context, ref),
                        ),
                      Row(
                        children: [
                          Semantics(
                            identifier: SemanticsIds.backupCreate,
                            child: FilledButton.icon(
                              key: const Key(SemanticsIds.backupCreate),
                              onPressed: anyRunning
                                  ? null
                                  : () => _createBackup(context, ref),
                              icon: const WaxIcon(WaxIcons.archive),
                              label: Text(
                                anyRunning
                                    ? l10n.adminBackupRunning
                                    : l10n.adminBackupNow,
                              ),
                            ),
                          ),
                          const SizedBox(width: WaxSpace.s8),
                          if (picker != null)
                            Semantics(
                              identifier: SemanticsIds.backupImport,
                              child: OutlinedButton.icon(
                                key: const Key(SemanticsIds.backupImport),
                                onPressed: () => _pickAndImport(context, ref),
                                icon: const WaxIcon(WaxIcons.upload),
                                label: Text(l10n.adminBackupImportArchive),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: WaxSpace.s8),
                      switch (backups) {
                        AsyncData(:final value) when value.isEmpty => Padding(
                          padding: const EdgeInsets.all(WaxSpace.s16),
                          child: Text(l10n.adminBackupsEmpty),
                        ),
                        AsyncData(:final value) => Column(
                          children: [
                            for (final backup in value)
                              _BackupRow(backup: backup),
                          ],
                        ),
                        AsyncError(:final error) => Padding(
                          padding: const EdgeInsets.all(WaxSpace.s16),
                          child: Text(context.explain(error)),
                        ),
                        _ => const Center(child: CircularProgressIndicator()),
                      },
                      SizedBox(height: WaxLayout.of(context).sectionGap),
                      SectionHeader(title: l10n.adminBackupsRetention),
                      const _RetentionFields(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RestoreBanner extends StatelessWidget {
  const _RestoreBanner({required this.plan, required this.onCancel});

  final RestorePlan plan;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Semantics(
      identifier: SemanticsIds.restoreBanner,
      child: Card(
        key: const Key(SemanticsIds.restoreBanner),
        color: colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(WaxSpace.s12),
          child: Row(
            children: [
              WaxIcon(WaxIcons.recent, color: colorScheme.onTertiaryContainer),
              const SizedBox(width: WaxSpace.s12),
              Expanded(
                child: Text(
                  l10n.adminRestoreStagedBanner(plan.backupId),
                  style: TextStyle(color: colorScheme.onTertiaryContainer),
                ),
              ),
              Semantics(
                identifier: SemanticsIds.restoreCancel,
                child: TextButton(
                  key: const Key(SemanticsIds.restoreCancel),
                  onPressed: onCancel,
                  child: Text(l10n.commonCancel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackupRow extends ConsumerWidget {
  const _BackupRow({required this.backup});

  final Backup backup;

  Future<void> _stageRestore(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.adminBackupRestoreTitle),
        content: Text(l10n.adminBackupRestoreBody(backup.fileName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('backup-restore-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.adminBackupStageRestore),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final plan = await ref.read(repositoryProvider).stageRestore(backup.id);
      ref.invalidate(stagedRestoreProvider);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _RestorePlanDialog(plan: plan),
      );
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.adminBackupDeleteTitle),
        content: Text(l10n.adminBackupDeleteBody(backup.fileName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('backup-delete-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.adminBackupDeleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(repositoryProvider).deleteBackup(backup.id);
      ref.invalidate(backupsProvider);
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final size = backup.sizeBytes;
    final subtitle = [
      if (size != null) l10n.formatBytes(size),
      _stateLabel(l10n, backup.state),
      _triggerLabel(l10n, backup.trigger),
      l10n.formatDate(backup.createdAt),
    ].join(', ');
    return WaxOptionRow(
      key: ValueKey(SemanticsIds.backupRow(backup.id)),
      semanticsId: SemanticsIds.backupRow(backup.id),
      glyph: backup.state == 'failed' ? WaxIcons.errorCircle : WaxIcons.archive,
      title: backup.fileName,
      subtitle: backup.error ?? subtitle,
      // The error branch is the server's own sentence, not a summary.
      subtitleMaxLines: 6,
      trailing: PopupMenuButton<String>(
        key: Key('backup-menu-${backup.id}'),
        tooltip: l10n.adminBackupActions,
        onSelected: (action) {
          switch (action) {
            case 'download':
              ref
                  .read(urlOpenerProvider)
                  .open(
                    ref.read(repositoryProvider).backupArchiveUrl(backup.id),
                  );
            case 'restore':
              _stageRestore(context, ref);
            case 'delete':
              _delete(context, ref);
          }
        },
        itemBuilder: (context) => [
          if (backup.state == 'done')
            PopupMenuItem(
              key: Key('backup-download-${backup.id}'),
              value: 'download',
              child: Text(l10n.adminBackupDownload),
            ),
          if (backup.state == 'done')
            PopupMenuItem(
              key: Key('backup-restore-${backup.id}'),
              value: 'restore',
              child: Text(l10n.adminBackupStageRestoreMenu),
            ),
          PopupMenuItem(
            key: Key('backup-delete-${backup.id}'),
            value: 'delete',
            child: Text(l10n.adminBackupDeleteMenu),
          ),
        ],
      ),
    );
  }
}

/// The three states a backup can be in, as words. The contract keeps
/// them open strings, so one this build has not heard of draws as the
/// server wrote it.
String _stateLabel(AppLocalizations l10n, String state) => switch (state) {
  'running' => l10n.adminBackupStateRunning,
  'done' => l10n.adminBackupStateDone,
  'failed' => l10n.adminBackupStateFailed,
  _ => state,
};

/// What produced a backup, as words. Open strings, same as the state.
String _triggerLabel(AppLocalizations l10n, String trigger) =>
    switch (trigger) {
      'manual' => l10n.adminBackupTriggerManual,
      'scheduled' => l10n.adminBackupTriggerScheduled,
      'imported' => l10n.adminBackupTriggerImported,
      _ => trigger,
    };

/// The staged plan: keyfile verdict, sealed casualties, and warnings.
class _RestorePlanDialog extends StatelessWidget {
  const _RestorePlanDialog({required this.plan});

  final RestorePlan plan;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final keyfileVerdict = !plan.keyfilePresent
        ? l10n.adminRestoreNoKeyfile
        : plan.keyfileMatches
        ? l10n.adminRestoreKeyfileMatches
        : l10n.adminRestoreKeyfileMismatch;
    return AlertDialog(
      key: const Key('restore-plan-dialog'),
      title: Text(l10n.adminRestoreStagedTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(WaxSpace.s8),
              color: colorScheme.tertiaryContainer,
              child: Text(
                l10n.adminRestoreAppliesAtRestart,
                style: TextStyle(color: colorScheme.onTertiaryContainer),
              ),
            ),
            const SizedBox(height: WaxSpace.s12),
            Text(keyfileVerdict),
            if (plan.sealedCasualties.isNotEmpty) ...[
              const SizedBox(height: WaxSpace.s12),
              Text(
                l10n.adminRestoreLostWithRestore,
                style: WaxType.label.copyWith(color: colors.textPrimary),
              ),
              for (final casualty in plan.sealedCasualties)
                Text(l10n.adminRestoreCasualty(casualty.kind, casualty.name)),
            ],
            if (plan.warnings.isNotEmpty) ...[
              const SizedBox(height: WaxSpace.s12),
              for (final warning in plan.warnings)
                Text(
                  warning,
                  style: WaxType.bodySmall.copyWith(color: colors.error),
                ),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          key: const Key('restore-plan-done'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonDone),
        ),
      ],
    );
  }
}

/// Backup retention (count and megabytes) bound to the admin settings.
class _RetentionFields extends ConsumerStatefulWidget {
  const _RetentionFields();

  @override
  ConsumerState<_RetentionFields> createState() => _RetentionFieldsState();
}

class _RetentionFieldsState extends ConsumerState<_RetentionFields> {
  final _keepCount = TextEditingController();
  final _keepMb = TextEditingController();
  var _seeded = false;
  var _busy = false;

  @override
  void dispose() {
    _keepCount.dispose();
    _keepMb.dispose();
    super.dispose();
  }

  void _seed(AdminSettings settings) {
    if (_seeded) return;
    _seeded = true;
    _keepCount.text = '${settings.backupKeepCount}';
    _keepMb.text = '${settings.backupKeepBytes ~/ (1024 * 1024)}';
  }

  Future<void> _save(AdminSettings settings) async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      await ref
          .read(adminSettingsProvider.notifier)
          .save(
            settings.copyWith(
              backupKeepCount:
                  int.tryParse(_keepCount.text.trim()) ??
                  settings.backupKeepCount,
              backupKeepBytes:
                  (int.tryParse(_keepMb.text.trim()) ??
                      settings.backupKeepBytes ~/ (1024 * 1024)) *
                  1024 *
                  1024,
            ),
          );
      messenger.show(l10n.adminBackupRetentionSaved);
    } on WaxDeckApiException catch (e) {
      messenger.show(explainRefusal(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(adminSettingsProvider).value;
    final l10n = context.l10n;
    if (settings == null) {
      return const Center(child: CircularProgressIndicator());
    }
    _seed(settings);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('backup-keep-count'),
          controller: _keepCount,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: l10n.adminBackupKeepCountLabel,
            helperText: l10n.adminBackupKeepAll,
          ),
        ),
        const SizedBox(height: WaxSpace.s8),
        TextField(
          key: const Key('backup-keep-mb'),
          controller: _keepMb,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: l10n.adminBackupKeepMbLabel,
            helperText: l10n.adminBackupKeepAll,
          ),
        ),
        const SizedBox(height: WaxSpace.s8),
        FilledButton.tonal(
          key: const Key('backup-retention-save'),
          onPressed: _busy ? null : () => _save(settings),
          child: Text(l10n.adminBackupSaveRetention),
        ),
      ],
    );
  }
}
