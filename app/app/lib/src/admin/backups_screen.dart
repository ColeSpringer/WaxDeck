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
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      await ref.read(repositoryProvider).createBackup();
      ref.invalidate(backupsProvider);
    } on WaxDeckApiException catch (e) {
      messenger.show(e.message);
    }
  }

  Future<void> _pickAndImport(BuildContext context, WidgetRef ref) async {
    final picker = ref.read(filePickerProvider);
    if (picker == null) return;
    final file = await picker.pickFile(
      extensions: const {'zip'},
      label: 'Backup archive',
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
    final messenger = ref.read(shellMessengerProvider.notifier);
    final openRead = file.openRead;
    if (openRead == null) return;
    try {
      await ref
          .read(repositoryProvider)
          .importBackup(sizeBytes: file.size, openRead: () => openRead());
      ref.invalidate(backupsProvider);
      messenger.show('${file.name} imported; stage its restore');
    } on WaxDeckApiException catch (e) {
      messenger.show(e.message);
    }
  }

  Future<void> _cancelRestore(BuildContext context, WidgetRef ref) async {
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      await ref.read(repositoryProvider).cancelStagedRestore();
      ref.invalidate(stagedRestoreProvider);
    } on WaxDeckApiException catch (e) {
      messenger.show(e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backups = ref.watch(backupsProvider);
    final staged = ref.watch(stagedRestoreProvider).value;
    final anyRunning = backups.value?.any((b) => b.state == 'running') ?? false;
    final picker = ref.watch(filePickerProvider);
    final sizeClass = WaxSizeClass.of(context);
    return WaxScaffold(
      title: 'Backups',
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
            hint: 'Drop a backup archive to import',
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
                                anyRunning ? 'Backing up...' : 'Back up now',
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
                                label: const Text('Import archive'),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: WaxSpace.s8),
                      switch (backups) {
                        AsyncData(:final value) when value.isEmpty =>
                          const Padding(
                            padding: EdgeInsets.all(WaxSpace.s16),
                            child: Text('No backups yet'),
                          ),
                        AsyncData(:final value) => Column(
                          children: [
                            for (final backup in value)
                              _BackupRow(backup: backup),
                          ],
                        ),
                        AsyncError(:final error) => Padding(
                          padding: const EdgeInsets.all(WaxSpace.s16),
                          child: Text(
                            error is WaxDeckApiException
                                ? error.message
                                : 'Could not load backups',
                          ),
                        ),
                        _ => const Center(child: CircularProgressIndicator()),
                      },
                      SizedBox(height: WaxLayout.of(context).sectionGap),
                      const SectionHeader(title: 'Retention'),
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
                  'A restore of ${plan.backupId} is staged; it applies at '
                  'the next server restart.',
                  style: TextStyle(color: colorScheme.onTertiaryContainer),
                ),
              ),
              Semantics(
                identifier: SemanticsIds.restoreCancel,
                child: TextButton(
                  key: const Key(SemanticsIds.restoreCancel),
                  onPressed: onCancel,
                  child: const Text('Cancel'),
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
    final messenger = ref.read(shellMessengerProvider.notifier);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Text(
          'The server replaces its database with ${backup.fileName} at '
          'the next restart. Changes made since the backup are lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('backup-restore-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Stage restore'),
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
      messenger.show(e.message);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final messenger = ref.read(shellMessengerProvider.notifier);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete backup?'),
        content: Text('${backup.fileName} is removed for good.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('backup-delete-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(repositoryProvider).deleteBackup(backup.id);
      ref.invalidate(backupsProvider);
    } on WaxDeckApiException catch (e) {
      messenger.show(e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final size = backup.sizeBytes;
    final subtitle = [
      if (size != null) l10n.formatBytes(size),
      backup.state,
      backup.trigger,
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
        tooltip: 'Backup actions',
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
              child: const Text('Download'),
            ),
          if (backup.state == 'done')
            PopupMenuItem(
              key: Key('backup-restore-${backup.id}'),
              value: 'restore',
              child: const Text('Stage restore...'),
            ),
          PopupMenuItem(
            key: Key('backup-delete-${backup.id}'),
            value: 'delete',
            child: const Text('Delete...'),
          ),
        ],
      ),
    );
  }
}

/// The staged plan: keyfile verdict, sealed casualties, and warnings.
class _RestorePlanDialog extends StatelessWidget {
  const _RestorePlanDialog({required this.plan});

  final RestorePlan plan;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final keyfileVerdict = !plan.keyfilePresent
        ? 'The archive has no secrets keyfile; sealed secrets are lost.'
        : plan.keyfileMatches
        ? 'The secrets keyfile matches; sealed secrets survive.'
        : 'The secrets keyfile does not match this server; the sealed '
              'secrets below are lost.';
    return AlertDialog(
      key: const Key('restore-plan-dialog'),
      title: const Text('Restore staged'),
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
                'The restore applies at the next server restart.',
                style: TextStyle(color: colorScheme.onTertiaryContainer),
              ),
            ),
            const SizedBox(height: WaxSpace.s12),
            Text(keyfileVerdict),
            if (plan.sealedCasualties.isNotEmpty) ...[
              const SizedBox(height: WaxSpace.s12),
              Text(
                'Lost with the restore',
                style: WaxType.label.copyWith(color: colors.textPrimary),
              ),
              for (final casualty in plan.sealedCasualties)
                Text('• ${casualty.kind}: ${casualty.name}'),
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
          child: const Text('Done'),
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
      messenger.show('Retention saved');
    } on WaxDeckApiException catch (e) {
      messenger.show(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(adminSettingsProvider).value;
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
          decoration: const InputDecoration(
            labelText: 'Backups to keep',
            helperText: '0 keeps all',
          ),
        ),
        const SizedBox(height: WaxSpace.s8),
        TextField(
          key: const Key('backup-keep-mb'),
          controller: _keepMb,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Backup space (MB)',
            helperText: '0 keeps all',
          ),
        ),
        const SizedBox(height: WaxSpace.s8),
        FilledButton.tonal(
          key: const Key('backup-retention-save'),
          onPressed: _busy ? null : () => _save(settings),
          child: const Text('Save retention'),
        ),
      ],
    );
  }
}
