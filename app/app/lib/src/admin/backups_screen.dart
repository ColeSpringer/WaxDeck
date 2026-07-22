import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import '../uploads/audio_drop_area.dart';
import '../uploads/file_picker_port.dart';
import 'admin_providers.dart';
import '../format_bytes.dart';

/// Backup archives with create, import, download, delete, and staged
/// restore, plus the maintenance schedules and backup retention knobs.
/// One screen because they are one story: when and what the server
/// keeps.
class BackupsScreen extends ConsumerWidget {
  const BackupsScreen({super.key});

  Future<void> _createBackup(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(repositoryProvider).createBackup();
      ref.invalidate(backupsProvider);
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
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

  /// Streams an archive up whole — never buffered in memory: archives
  /// carry both databases and a large catalog easily exceeds a hundred
  /// megabytes. Every picked reference carries a lazy reader (disk on
  /// native, the browser file handle on web).
  static Future<void> _importArchive(
    BuildContext context,
    WidgetRef ref,
    PickedAudioFile file,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final openRead = file.openRead;
    if (openRead == null) return;
    try {
      await ref
          .read(repositoryProvider)
          .importBackup(sizeBytes: file.size, openRead: () => openRead());
      ref.invalidate(backupsProvider);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('${file.name} imported; stage its restore')),
        );
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _cancelRestore(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(repositoryProvider).cancelStagedRestore();
      ref.invalidate(stagedRestoreProvider);
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backups = ref.watch(backupsProvider);
    final staged = ref.watch(stagedRestoreProvider).value;
    final anyRunning = backups.value?.any((b) => b.state == 'running') ?? false;
    final picker = ref.watch(filePickerProvider);
    return Semantics(
      identifier: 'admin-backups',
      container: true,
      child: Scaffold(
        appBar: AppBar(title: const Text('Backups')),
        body: AudioDropArea(
          extensions: const {'zip'},
          hint: 'Drop a backup archive to import',
          onDropped: (files) async {
            for (final file in files) {
              if (!context.mounted) return;
              await _importArchive(context, ref, file);
            }
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (staged != null)
                _RestoreBanner(
                  plan: staged,
                  onCancel: () => _cancelRestore(context, ref),
                ),
              Row(
                children: [
                  Semantics(
                    identifier: 'backup-create',
                    child: FilledButton.icon(
                      key: const Key('backup-create'),
                      onPressed: anyRunning
                          ? null
                          : () => _createBackup(context, ref),
                      icon: const Icon(Icons.archive_outlined),
                      label: Text(anyRunning ? 'Backing up...' : 'Back up now'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (picker != null)
                    Semantics(
                      identifier: 'backup-import',
                      child: OutlinedButton.icon(
                        key: const Key('backup-import'),
                        onPressed: () => _pickAndImport(context, ref),
                        icon: const Icon(Icons.unarchive_outlined),
                        label: const Text('Import archive'),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              switch (backups) {
                AsyncData(:final value) when value.isEmpty => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No backups yet'),
                ),
                AsyncData(:final value) => Column(
                  children: [
                    for (final backup in value) _BackupRow(backup: backup),
                  ],
                ),
                AsyncError(:final error) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    error is WaxDeckApiException
                        ? error.message
                        : 'Could not load backups',
                  ),
                ),
                _ => const Center(child: CircularProgressIndicator()),
              },
              const SizedBox(height: 16),
              Text('Schedules', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              switch (ref.watch(schedulesProvider)) {
                AsyncData(:final value) => Column(
                  children: [
                    for (final schedule in value)
                      _ScheduleRow(
                        key: ValueKey('schedule-${schedule.kind}'),
                        schedule: schedule,
                      ),
                  ],
                ),
                AsyncError() => const Text('Could not load schedules'),
                _ => const Center(child: CircularProgressIndicator()),
              },
              const SizedBox(height: 16),
              Text('Retention', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const _RetentionFields(),
            ],
          ),
        ),
      ),
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
      identifier: 'restore-banner',
      child: Card(
        key: const Key('restore-banner'),
        color: colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.restore, color: colorScheme.onTertiaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'A restore of ${plan.backupId} is staged; it applies at '
                  'the next server restart.',
                  style: TextStyle(color: colorScheme.onTertiaryContainer),
                ),
              ),
              Semantics(
                identifier: 'restore-cancel',
                child: TextButton(
                  key: const Key('restore-cancel'),
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

  static String _date(DateTime at) {
    final local = at.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  Future<void> _stageRestore(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
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
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
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
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = backup.sizeBytes;
    final subtitle = [
      if (size != null) formatBytes(size),
      backup.state,
      backup.trigger,
      _date(backup.createdAt),
    ].join(', ');
    return Semantics(
      identifier: 'backup-row-${backup.id}',
      child: ListTile(
        key: ValueKey('backup-row-${backup.id}'),
        leading: Icon(
          backup.state == 'failed'
              ? Icons.error_outline
              : Icons.archive_outlined,
          color: backup.state == 'failed' ? colorScheme.error : null,
        ),
        title: Text(backup.fileName, overflow: TextOverflow.ellipsis),
        subtitle: Text(backup.error == null ? subtitle : backup.error!),
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
    final textTheme = Theme.of(context).textTheme;
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
              padding: const EdgeInsets.all(8),
              color: colorScheme.tertiaryContainer,
              child: Text(
                'The restore applies at the next server restart.',
                style: TextStyle(color: colorScheme.onTertiaryContainer),
              ),
            ),
            const SizedBox(height: 12),
            Text(keyfileVerdict),
            if (plan.sealedCasualties.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Lost with the restore', style: textTheme.titleSmall),
              for (final casualty in plan.sealedCasualties)
                Text('• ${casualty.kind}: ${casualty.name}'),
            ],
            if (plan.warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final warning in plan.warnings)
                Text(
                  warning,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                  ),
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

class _ScheduleRow extends ConsumerStatefulWidget {
  const _ScheduleRow({super.key, required this.schedule});

  final Schedule schedule;

  @override
  ConsumerState<_ScheduleRow> createState() => _ScheduleRowState();
}

class _ScheduleRowState extends ConsumerState<_ScheduleRow> {
  late final TextEditingController _cron = TextEditingController(
    text: widget.schedule.cron,
  );
  late bool _enabled = widget.schedule.enabled;
  var _busy = false;

  static String _label(String kind) => switch (kind) {
    'scan' => 'Library scan',
    'backup' => 'Backup',
    'prune' => 'Prune',
    _ => kind,
  };

  @override
  void dispose() {
    _cron.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(schedulesProvider.notifier)
          .save(
            widget.schedule.kind,
            cron: _cron.text.trim(),
            enabled: _enabled,
          );
      messenger.showSnackBar(
        SnackBar(content: Text('${_label(widget.schedule.kind)} saved')),
      );
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final schedule = widget.schedule;
    final kind = schedule.kind;
    final status = StringBuffer();
    if (schedule.lastRunAt != null) {
      status.write('Last run ${schedule.lastStatus ?? 'unknown'}');
    }
    if (schedule.nextRunAt != null) {
      if (status.isNotEmpty) status.write(', ');
      status.write('next ${schedule.nextRunAt!.toLocal()}');
    }
    return Semantics(
      identifier: 'schedule-row-$kind',
      container: true,
      child: Card(
        key: ValueKey('schedule-row-$kind'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(_label(kind), style: textTheme.titleSmall),
                  ),
                  Semantics(
                    identifier: 'schedule-enabled-$kind',
                    child: Switch(
                      key: Key('schedule-enabled-$kind'),
                      value: _enabled,
                      onChanged: (value) => setState(() => _enabled = value),
                    ),
                  ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Semantics(
                      identifier: 'schedule-cron-$kind',
                      child: TextField(
                        key: Key('schedule-cron-$kind'),
                        controller: _cron,
                        decoration: const InputDecoration(
                          labelText: 'Cron',
                          helperText: 'minute hour day month weekday',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    identifier: 'schedule-save-$kind',
                    child: FilledButton.tonal(
                      key: Key('schedule-save-$kind'),
                      onPressed: _busy ? null : _save,
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
              if (status.isNotEmpty)
                Text(status.toString(), style: textTheme.bodySmall),
              if (schedule.lastError != null)
                Text(
                  schedule.lastError!,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                  ),
                ),
            ],
          ),
        ),
      ),
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
    final messenger = ScaffoldMessenger.of(context);
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
      messenger.showSnackBar(const SnackBar(content: Text('Retention saved')));
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
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
        const SizedBox(height: 8),
        TextField(
          key: const Key('backup-keep-mb'),
          controller: _keepMb,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Backup space (MB)',
            helperText: '0 keeps all',
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          key: const Key('backup-retention-save'),
          onPressed: _busy ? null : () => _save(settings),
          child: const Text('Save retention'),
        ),
      ],
    );
  }
}
