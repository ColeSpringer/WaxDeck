import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'admin_providers.dart';
import '../format_bytes.dart';

/// The server-side trash: what deletions parked, restorable per entry,
/// purgeable as a whole.
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    TrashEntry entry,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(trashProvider.notifier).restore(entry.id);
      messenger.showSnackBar(SnackBar(content: Text('Restored ${entry.name}')));
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _empty(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Empty trash?'),
        content: const Text(
          'Every trashed file is deleted for good. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('trash-empty-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Empty trash'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final result = await ref.read(trashProvider.notifier).empty();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Purged ${result.purged} files, reclaimed '
            '${formatBytes(result.reclaimedBytes)}',
          ),
        ),
      );
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trash = ref.watch(trashProvider);
    final includeRestored = ref.watch(trashIncludeRestoredProvider);
    return Semantics(
      identifier: 'admin-trash',
      container: true,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Trash'),
          actions: [
            Semantics(
              identifier: 'trash-empty',
              child: TextButton.icon(
                key: const Key('trash-empty'),
                onPressed: () => _empty(context, ref),
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Empty trash'),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            SwitchListTile(
              key: const Key('trash-include-restored'),
              title: const Text('Show restored entries'),
              value: includeRestored,
              onChanged: (value) =>
                  ref.read(trashIncludeRestoredProvider.notifier).toggle(value),
            ),
            Expanded(
              child: switch (trash) {
                AsyncData(:final value) when value.entries.isEmpty =>
                  const Center(child: Text('The trash is empty')),
                AsyncData(:final value) => ListView(
                  children: [
                    for (final entry in value.entries)
                      _TrashRow(
                        entry: entry,
                        onRestore: () => _restore(context, ref, entry),
                      ),
                  ],
                ),
                AsyncError(:final error) => Center(
                  child: Text(
                    error is WaxDeckApiException
                        ? error.message
                        : 'Could not load the trash',
                  ),
                ),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TrashRow extends StatelessWidget {
  const _TrashRow({required this.entry, required this.onRestore});

  final TrashEntry entry;
  final VoidCallback onRestore;

  static String _date(DateTime at) {
    final local = at.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  @override
  Widget build(BuildContext context) {
    final restored = entry.restoredAt != null;
    return Semantics(
      identifier: 'trash-row-${entry.id}',
      child: ListTile(
        key: ValueKey('trash-row-${entry.id}'),
        leading: const Icon(Icons.delete_outline),
        title: Row(
          children: [
            Flexible(child: Text(entry.name, overflow: TextOverflow.ellipsis)),
            if (restored) ...[
              const SizedBox(width: 8),
              const Chip(
                label: Text('restored'),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ],
        ),
        subtitle: Text(
          '${formatBytes(entry.sizeBytes)}, ${entry.reason}, '
          '${_date(entry.trashedAt)}',
        ),
        trailing: restored
            ? null
            : Semantics(
                identifier: 'trash-restore-${entry.id}',
                child: TextButton(
                  key: Key('trash-restore-${entry.id}'),
                  onPressed: onRestore,
                  child: const Text('Restore'),
                ),
              ),
      ),
    );
  }
}
