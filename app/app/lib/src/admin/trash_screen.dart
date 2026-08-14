import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'admin_console.dart';
import 'admin_providers.dart';

/// The server-side trash: what deletions parked, restorable per entry,
/// purgeable one at a time or all at once.
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    TrashEntry entry,
  ) async {
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      await ref.read(trashProvider.notifier).restore(entry.id);
      messenger.show(l10n.adminTrashRestored(entry.name));
    } on WaxDeckApiException catch (error) {
      messenger.show(explainError(l10n, error));
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
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.adminTrashPurgeTitle),
        content: Text(l10n.adminTrashPurgeBody(entry.name)),
        actions: <Widget>[
          WaxButton(
            label: l10n.commonCancel,
            kind: WaxButtonKind.text,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          WaxButton(
            label: l10n.adminTrashPurgeAction,
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
        l10n.adminTrashPurged(entry.name, l10n.formatBytes(reclaimed)),
      );
    } on WaxDeckApiException catch (error) {
      messenger.show(explainError(l10n, error));
    }
  }

  /// Emptying takes the typed word: it deletes files the server was
  /// holding precisely because somebody might want them back, and it is
  /// one press away from the row that restores one.
  Future<void> _empty(BuildContext context, WidgetRef ref) async {
    final messenger = ref.read(shellMessengerProvider.notifier);
    final l10n = context.l10n;
    final confirmed = await showTypedConfirm(
      context,
      title: l10n.adminTrashEmptyTitle,
      message: l10n.adminTrashEmptyBody,
      confirmWord: l10n.adminTrashEmptyWord,
      confirmLabel: l10n.adminTrashEmptyAction,
      fieldSemanticsId: SemanticsIds.confirmField,
      confirmSemanticsId: SemanticsIds.confirmAccept,
      cancelSemanticsId: SemanticsIds.confirmCancel,
    );
    if (!confirmed) return;
    try {
      final result = await ref.read(trashProvider.notifier).empty();
      messenger.show(
        l10n.adminTrashEmptied(
          result.purged,
          l10n.formatBytes(result.reclaimedBytes),
        ),
      );
    } on WaxDeckApiException catch (error) {
      messenger.show(explainError(l10n, error));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final trash = ref.watch(trashProvider);
    final includeRestored = ref.watch(trashIncludeRestoredProvider);
    return WaxScaffold(
      title: l10n.adminTrashTitle,
      largeTitle: false,
      semanticsId: SemanticsIds.adminTrash,
      onBack: adminBack(context),
      actions: <Widget>[
        WaxButton(
          label: l10n.adminTrashEmptyAction,
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
              title: l10n.adminTrashShowRestoredTitle,
              help: l10n.adminTrashShowRestoredHelp,
              control: WaxSwitch(
                label: l10n.adminTrashShowRestoredTitle,
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
                empty: EmptyState(
                  glyph: WaxIcons.delete,
                  title: l10n.adminTrashEmptyStateTitle,
                  message: l10n.adminTrashEmptyStateMessage,
                ),
                columns: <WaxColumn<TrashEntry>>[
                  WaxColumn<TrashEntry>(
                    label: l10n.adminTrashColumnFile,
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
                    label: l10n.adminTrashColumnReason,
                    width: 140,
                    text: (entry) => _reasonLabel(l10n, entry),
                    cell: (context, entry) => Text(
                      _reasonLabel(l10n, entry),
                      style: WaxType.bodySmall.copyWith(
                        color: colors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  WaxColumn<TrashEntry>(
                    label: l10n.adminTrashColumnSize,
                    width: 92,
                    numeric: true,
                    text: (entry) => l10n.formatBytes(entry.sizeBytes),
                    cell: (context, entry) => Text(
                      l10n.formatBytes(entry.sizeBytes),
                      style: WaxType.monoData.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  WaxColumn<TrashEntry>(
                    label: l10n.adminTrashColumnTrashed,
                    width: 108,
                    text: (entry) => l10n.formatDate(entry.trashedAt),
                    cell: (context, entry) => Text(
                      l10n.formatDate(entry.trashedAt),
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
                        onRestore: () => _restore(context, ref, entry),
                        onPurge: () => _purge(context, ref, entry),
                      ),
              ),
              AsyncError(:final error) => ErrorState(
                title: l10n.adminTrashLoadError,
                message: context.explain(error),
                onRetry: () => ref.invalidate(trashProvider),
              ),
              _ => const SkeletonShapes(shape: SkeletonShape.list),
            },
          ],
        ),
      ),
    );
  }
}

/// Why a file was trashed, as words - or that it is back, which is
/// what the row says instead once it has been restored.
///
/// The contract keeps the reason an open string, so one this build has
/// not heard of draws as the server wrote it.
String _reasonLabel(AppLocalizations l10n, TrashEntry entry) {
  if (entry.restoredAt != null) return l10n.adminTrashReasonRestored;
  return switch (entry.reason) {
    'user' => l10n.adminTrashReasonUser,
    'prune' => l10n.adminTrashReasonPrune,
    'permanent' => l10n.adminTrashReasonPermanent,
    _ => entry.reason,
  };
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

  /// The API types a pid by its prefix; `TrashEntry` carries no kind
  /// field, so the prefix is the contract's way of saying "episode".
  static const _episodePidPrefix = 'ep-';

  @override
  Widget build(BuildContext context) {
    // Episodes only reach the trash from before the podcast tree owned
    // its own files, and the server refuses to restore one into it. The
    // way back is re-downloading; purge still applies, so the row keeps
    // its other action rather than drawing a button that always fails.
    final restorable = !(entry.itemPid?.startsWith(_episodePidPrefix) ?? false);
    final l10n = context.l10n;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (restorable)
          WaxIconButton(
            glyph: WaxIcons.refresh,
            label: l10n.adminTrashRestoreAction(entry.name),
            semanticsId: SemanticsIds.trashRestore(entry.id),
            onPressed: onRestore,
          ),
        WaxIconButton(
          glyph: WaxIcons.delete,
          label: l10n.adminTrashPurgeRowAction(entry.name),
          semanticsId: SemanticsIds.trashPurge(entry.id),
          onPressed: onPurge,
        ),
      ],
    );
  }
}
