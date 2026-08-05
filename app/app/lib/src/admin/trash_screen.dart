import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../format_bytes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'admin_console.dart';
import 'admin_providers.dart';

/// The server-side trash: what deletions parked, restorable per entry,
/// purgeable one at a time or all at once.
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  Future<void> _restore(WidgetRef ref, TrashEntry entry) async {
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      await ref.read(trashProvider.notifier).restore(entry.id);
      messenger.show('Restored ${entry.name}');
    } on WaxDeckApiException catch (error) {
      messenger.show(error.message);
    }
  }

  /// One file, behind a plain confirmation: it is one file, its name is
  /// on screen, and the typed word is for the action that takes every
  /// one of them at once.
  Future<void> _purge(
    BuildContext context,
    WidgetRef ref,
    TrashEntry entry,
  ) async {
    final messenger = ref.read(shellMessengerProvider.notifier);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Purge this file?'),
        content: Text(
          '${entry.name} is deleted for good. This cannot be undone.',
        ),
        actions: <Widget>[
          WaxButton(
            label: 'Cancel',
            kind: WaxButtonKind.text,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          WaxButton(
            label: 'Purge',
            kind: WaxButtonKind.destructive,
            semanticsId: SemanticsIds.trashPurgeConfirm,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final reclaimed = await ref.read(trashProvider.notifier).purge(entry.id);
      messenger.show(
        'Purged ${entry.name}, reclaimed ${formatBytes(reclaimed)}',
      );
    } on WaxDeckApiException catch (error) {
      messenger.show(error.message);
    }
  }

  /// Emptying takes the typed word: it deletes files the server was
  /// holding precisely because somebody might want them back, and it is
  /// one press away from the row that restores one.
  Future<void> _empty(BuildContext context, WidgetRef ref) async {
    final messenger = ref.read(shellMessengerProvider.notifier);
    final confirmed = await showTypedConfirm(
      context,
      title: 'Empty the trash?',
      message:
          'Every trashed file is deleted for good, including the ones '
          'still restorable. This cannot be undone.',
      confirmWord: 'EMPTY',
      confirmLabel: 'Empty trash',
      fieldSemanticsId: SemanticsIds.confirmField,
      confirmSemanticsId: SemanticsIds.confirmAccept,
      cancelSemanticsId: SemanticsIds.confirmCancel,
    );
    if (!confirmed) return;
    try {
      final result = await ref.read(trashProvider.notifier).empty();
      messenger.show(
        'Purged ${result.purged} files, reclaimed '
        '${formatBytes(result.reclaimedBytes)}',
      );
    } on WaxDeckApiException catch (error) {
      messenger.show(error.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final colors = WaxColors.of(context);
    final trash = ref.watch(trashProvider);
    final includeRestored = ref.watch(trashIncludeRestoredProvider);
    return WaxScaffold(
      title: 'Trash',
      largeTitle: false,
      semanticsId: SemanticsIds.adminTrash,
      onBack: adminBack(context),
      actions: <Widget>[
        WaxButton(
          label: 'Empty trash',
          kind: WaxButtonKind.destructive,
          semanticsId: SemanticsIds.trashEmpty,
          onPressed: () => _empty(context, ref),
        ),
      ],
      body: Padding(
        padding: sizeClass.gutter.add(
          const EdgeInsets.only(bottom: WaxSpace.s32),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            WaxSettingRow(
              title: 'Show restored entries',
              help: 'Entries already put back, for the record',
              control: WaxSwitch(
                label: 'Show restored entries',
                value: includeRestored,
                semanticsId: SemanticsIds.trashIncludeRestored,
                onChanged: (value) => ref
                    .read(trashIncludeRestoredProvider.notifier)
                    .toggle(value),
              ),
            ),
            const SizedBox(height: WaxSpace.s16),
            switch (trash) {
              AsyncData(:final value) => WaxTable<TrashEntry>(
                rows: value.entries,
                rowId: (entry) => entry.id,
                rowSemanticsId: SemanticsIds.trashRow,
                rowDetailSemanticsId: SemanticsIds.trashDetail,
                empty: const EmptyState(
                  glyph: WaxIcons.delete,
                  title: 'The trash is empty',
                  message: 'Deleted files wait here before they are purged.',
                ),
                columns: <WaxColumn<TrashEntry>>[
                  WaxColumn<TrashEntry>(
                    label: 'File',
                    priority: WaxColumnPriority.primary,
                    text: (entry) => entry.name,
                    cell: (context, entry) => Text(
                      entry.name,
                      style: WaxType.titleItem.copyWith(
                        color: entry.restoredAt == null
                            ? colors.textPrimary
                            : colors.textTertiary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  WaxColumn<TrashEntry>(
                    label: 'Reason',
                    width: 140,
                    text: (entry) => entry.reason,
                    cell: (context, entry) => Text(
                      entry.restoredAt == null ? entry.reason : 'restored',
                      style: WaxType.bodySmall.copyWith(
                        color: colors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  WaxColumn<TrashEntry>(
                    label: 'Size',
                    width: 92,
                    numeric: true,
                    text: (entry) => formatBytes(entry.sizeBytes),
                    cell: (context, entry) => Text(
                      formatBytes(entry.sizeBytes),
                      style: WaxType.monoData.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  WaxColumn<TrashEntry>(
                    label: 'Trashed',
                    width: 108,
                    text: (entry) => _date(entry.trashedAt),
                    cell: (context, entry) => Text(
                      _date(entry.trashedAt),
                      style: WaxType.monoData.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
                trailing: (context, entry) => entry.restoredAt != null
                    ? const SizedBox.shrink()
                    : _RowActions(
                        entry: entry,
                        onRestore: () => _restore(ref, entry),
                        onPurge: () => _purge(context, ref, entry),
                      ),
              ),
              AsyncError(:final error) => ErrorState(
                title: 'Could not load the trash',
                message: error is WaxDeckApiException
                    ? error.message
                    : 'Something went wrong reading it.',
                onRetry: () => ref.invalidate(trashProvider),
              ),
              _ => const SkeletonShapes(shape: SkeletonShape.list),
            },
          ],
        ),
      ),
    );
  }

  static String _date(DateTime at) {
    final local = at.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }
}

class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.entry,
    required this.onRestore,
    required this.onPurge,
  });

  final TrashEntry entry;
  final VoidCallback onRestore;
  final VoidCallback onPurge;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        WaxIconButton(
          glyph: WaxIcons.refresh,
          label: 'Restore ${entry.name}',
          semanticsId: SemanticsIds.trashRestore(entry.id),
          onPressed: onRestore,
        ),
        WaxIconButton(
          glyph: WaxIcons.delete,
          label: 'Purge ${entry.name}',
          semanticsId: SemanticsIds.trashPurge(entry.id),
          onPressed: onPurge,
        ),
      ],
    );
  }
}
