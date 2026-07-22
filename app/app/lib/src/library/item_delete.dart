import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../auth/auth_controller.dart';
import '../providers.dart';
import 'library_controller.dart';
import '../format_bytes.dart';

/// The "Delete files..." overflow on an item screen. Rendered for
/// administrators; the server enforces the permission either way. The
/// dialog previews the deletion with a dry run before anything moves.
class ItemDeleteAction extends ConsumerWidget {
  const ItemDeleteAction({super.key, required this.pid, this.onDeleted});

  final String pid;

  /// Called after a successful deletion, when the surrounding screen
  /// should leave (its item is gone).
  final VoidCallback? onDeleted;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(repositoryProvider);
    try {
      final plan = await repo.deleteLibraryItems(pids: [pid], dryRun: true);
      if (!context.mounted) return;
      final mode = await showDialog<String>(
        context: context,
        builder: (_) => _DeleteItemsDialog(plan: plan),
      );
      if (mode == null) return;
      final result = await repo.deleteLibraryItems(pids: [pid], mode: mode);
      ref.invalidate(libraryControllerProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.mode == 'permanent'
                ? 'Deleted ${result.totalFiles} files for good'
                : 'Moved ${result.totalFiles} files to the trash',
          ),
        ),
      );
      onDeleted?.call();
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin =
        ref
            .watch(authControllerProvider)
            .value
            ?.user
            ?.roles
            .contains('admin') ??
        false;
    if (!isAdmin) return const SizedBox.shrink();
    return Semantics(
      identifier: 'item-delete',
      label: 'Delete files',
      button: true,
      child: PopupMenuButton<String>(
        key: const Key('item-delete'),
        tooltip: 'More',
        onSelected: (_) => _delete(context, ref),
        itemBuilder: (context) => [
          const PopupMenuItem(
            key: Key('item-delete-open'),
            value: 'delete',
            child: Text('Delete files...'),
          ),
        ],
      ),
    );
  }
}

/// Preview from the dry run plus the trash-or-permanent choice.
class _DeleteItemsDialog extends StatefulWidget {
  const _DeleteItemsDialog({required this.plan});

  final DeleteItemsResult plan;

  @override
  State<_DeleteItemsDialog> createState() => _DeleteItemsDialogState();
}

class _DeleteItemsDialogState extends State<_DeleteItemsDialog> {
  var _mode = 'trash';

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    return AlertDialog(
      key: const Key('item-delete-dialog'),
      title: const Text('Delete files?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This removes ${plan.totalFiles} files, '
            '${formatBytes(plan.totalBytes)}.',
            key: const Key('item-delete-preview'),
          ),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: _mode,
            onChanged: (value) => setState(() => _mode = value ?? 'trash'),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String>(
                  key: Key('item-delete-mode-trash'),
                  title: Text('Move to trash'),
                  subtitle: Text('Restorable from the trash screen'),
                  value: 'trash',
                ),
                RadioListTile<String>(
                  key: Key('item-delete-mode-permanent'),
                  title: Text('Delete permanently'),
                  subtitle: Text('Gone for good'),
                  value: 'permanent',
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        Semantics(
          identifier: 'item-delete-confirm',
          child: FilledButton(
            key: const Key('item-delete-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(_mode),
            child: const Text('Delete'),
          ),
        ),
      ],
    );
  }
}
