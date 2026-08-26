import 'package:waxdeck_ui/waxdeck_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../providers.dart';
import '../home/home_shelves.dart';
import '../music/music_controllers.dart';
import '../shell/semantics_ids.dart';

/// Whether this account is offered destructive catalog verbs.
///
/// The server enforces the permission either way; this is what decides
/// whether the affordance is drawn at all, which is the house rule for
/// permission-gated actions - hidden, never disabled. The session's
/// `delete` is the server's *effective* answer (administrators always
/// hold it); the role check is the fallback for a server too old to
/// report the field, where only administrators could delete anyway.
bool canDeleteItems(WidgetRef ref) {
  final user = ref.watch(authControllerProvider).value?.user;
  if (user == null) return false;
  return user.canDelete || user.roles.contains('admin');
}

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
  // Read beside the messenger, for the same reason: both are wanted
  // after an await, and a context is not read across one.
  final l10n = context.l10n;
  // The container rather than `ref`, for the same reason the mark-older
  // dialog holds one: the deletion happens whether or not the screen
  // that offered it is still mounted when the server answers, and the
  // listings showing what just went have to be told regardless.
  final container = ProviderScope.containerOf(context, listen: false);
  final repo = container.read(repositoryProvider);
  // Permanent deletion is admin-only on the server whatever the delete
  // right says, so the radio for it is drawn only where it can succeed
  // - hidden, never disabled, and never a 403 for the option offered.
  final allowPermanent =
      container
          .read(authControllerProvider)
          .value
          ?.user
          ?.roles
          .contains('admin') ??
      false;
  try {
    final plan = await repo.deleteLibraryItems(pids: [pid], dryRun: true);
    if (!context.mounted) return;
    final mode = await showDialog<String>(
      context: context,
      builder: (_) =>
          _DeleteItemsDialog(plan: plan, allowPermanent: allowPermanent),
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
              ? l10n.libraryDeletePermanentDone(result.totalFiles)
              : l10n.libraryDeleteTrashDone(result.totalFiles),
        ),
      ),
    );
    onDeleted?.call();
  } on WaxDeckApiException catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
  }
}

/// The "Delete files..." overflow on an item screen. Rendered for
/// accounts holding the delete right; the server enforces the
/// permission either way. The dialog previews the deletion with a dry
/// run before anything moves.
class ItemDeleteAction extends ConsumerWidget {
  const ItemDeleteAction({super.key, required this.pid, this.onDeleted});

  final String pid;

  /// Called after a successful deletion, when the surrounding screen
  /// should leave (its item is gone).
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!canDeleteItems(ref)) return const SizedBox.shrink();
    final l10n = context.l10n;
    return Semantics(
      identifier: SemanticsIds.itemDelete,
      label: l10n.libraryDeleteFilesLabel,
      button: true,
      child: PopupMenuButton<String>(
        key: const Key(SemanticsIds.itemDelete),
        tooltip: l10n.libraryDeleteMore,
        onSelected: (_) =>
            confirmDeleteItem(context, pid: pid, onDeleted: onDeleted),
        itemBuilder: (context) => [
          PopupMenuItem(
            key: const Key('item-delete-open'),
            value: 'delete',
            child: Text(l10n.libraryDeleteFilesMenu),
          ),
        ],
      ),
    );
  }
}

/// Preview from the dry run plus the trash-or-permanent choice.
class _DeleteItemsDialog extends StatefulWidget {
  const _DeleteItemsDialog({required this.plan, required this.allowPermanent});

  final DeleteItemsResult plan;

  /// Whether the permanent mode is offered at all; the server refuses
  /// it to everyone but administrators.
  final bool allowPermanent;

  @override
  State<_DeleteItemsDialog> createState() => _DeleteItemsDialogState();
}

class _DeleteItemsDialogState extends State<_DeleteItemsDialog> {
  var _mode = 'trash';

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final l10n = context.l10n;
    return AlertDialog(
      key: const Key('item-delete-dialog'),
      title: Text(l10n.libraryDeleteTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.libraryDeletePreview(
              plan.totalFiles,
              l10n.formatBytes(plan.totalBytes),
            ),
            key: const Key('item-delete-preview'),
          ),
          const SizedBox(height: WaxSpace.s8),
          WaxRadioGroup<String>(
            value: _mode,
            onChanged: (value) => setState(() => _mode = value),
            options: <WaxRadioOption<String>>[
              WaxRadioOption<String>(
                value: 'trash',
                label: l10n.libraryDeleteModeTrash,
                help: l10n.libraryDeleteModeTrashHelp,
                semanticsId: SemanticsIds.itemDeleteMode('trash'),
              ),
              if (widget.allowPermanent)
                WaxRadioOption<String>(
                  value: 'permanent',
                  label: l10n.libraryDeleteModePermanent,
                  help: l10n.libraryDeleteModePermanentHelp,
                  semanticsId: SemanticsIds.itemDeleteMode('permanent'),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
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
            child: Text(l10n.libraryDeleteAction),
          ),
        ),
      ],
    );
  }
}
