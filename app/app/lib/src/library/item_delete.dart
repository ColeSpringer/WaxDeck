import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../auth/auth_controller.dart';
import '../providers.dart';
import '../format_bytes.dart';
import '../home/home_shelves.dart';
import '../music/music_controllers.dart';
import '../shell/semantics_ids.dart';

/// Whether this account is offered destructive catalog verbs.
///
/// The server enforces the permission either way; this is what decides
/// whether the affordance is drawn at all, which is the house rule for
/// permission-gated actions - hidden, never disabled.
bool canDeleteItems(WidgetRef ref) =>
    ref.watch(authControllerProvider).value?.user?.roles.contains('admin') ??
    false;

/// Previews a deletion with a dry run, then performs the mode the
/// listener picked.
///
/// A function rather than only a button, because two surfaces offer this
/// verb in two shapes: an item screen's own overflow row, and the
/// player's single overflow menu, where a second three-dot control
/// beside the first would be two menus wearing one glyph.
/// Takes no `ref` on purpose: the work outlives the widget that asked
/// for it, so it goes through the container rather than through a
/// caller's provider dependencies - which is the whole point of the
/// capture below.
Future<void> confirmDeleteItem(
  BuildContext context, {
  required String pid,
  VoidCallback? onDeleted,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  // The container rather than `ref`, for the same reason the mark-older
  // dialog holds one: the deletion happens whether or not the screen
  // that offered it is still mounted when the server answers, and the
  // listings showing what just went have to be told regardless.
  final container = ProviderScope.containerOf(context, listen: false);
  final repo = container.read(repositoryProvider);
  try {
    final plan = await repo.deleteLibraryItems(pids: [pid], dryRun: true);
    if (!context.mounted) return;
    final mode = await showDialog<String>(
      context: context,
      builder: (_) => _DeleteItemsDialog(plan: plan),
    );
    if (mode == null) return;
    final result = await repo.deleteLibraryItems(pids: [pid], mode: mode);
    // The listings that could be showing what just went: the music
    // listing this was opened from, and the home shelves, which draw
    // the same items from the other side. The catalog invalidation is
    // on its way too, and arrives whenever the socket does; this is
    // what makes the row leave now rather than shortly.
    container.invalidate(musicItemsProvider);
    for (final provider in homeShelfProviders) {
      container.invalidate(provider);
    }
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

/// The "Delete files..." overflow on an item screen. Rendered for
/// administrators; the server enforces the permission either way. The
/// dialog previews the deletion with a dry run before anything moves.
class ItemDeleteAction extends ConsumerWidget {
  const ItemDeleteAction({super.key, required this.pid, this.onDeleted});

  final String pid;

  /// Called after a successful deletion, when the surrounding screen
  /// should leave (its item is gone).
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!canDeleteItems(ref)) return const SizedBox.shrink();
    return Semantics(
      identifier: SemanticsIds.itemDelete,
      label: 'Delete files',
      button: true,
      child: PopupMenuButton<String>(
        key: const Key(SemanticsIds.itemDelete),
        tooltip: 'More',
        onSelected: (_) =>
            confirmDeleteItem(context, pid: pid, onDeleted: onDeleted),
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
          identifier: SemanticsIds.itemDeleteConfirm,
          child: FilledButton(
            key: const Key(SemanticsIds.itemDeleteConfirm),
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
