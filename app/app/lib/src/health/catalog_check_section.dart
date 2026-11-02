import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../providers.dart';
import '../settings/settings_registry.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import '../tools/tool_tasks_provider.dart';

/// A catalog check's counts and when they were read.
typedef CatalogCheckRead = ({CatalogConsistency counts, DateTime at});

/// The last catalog check this session asked for, null until it asks: a
/// check reads the whole catalog, so it runs on request rather than with
/// the screen.
class CatalogCheck extends Notifier<AsyncValue<CatalogCheckRead>?> {
  /// Moved by every check asked for, every repair started and every
  /// rebuild (another server), so only the latest check lands: none that
  /// read the catalog before a repair, or another server's.
  var _run = 0;

  @override
  AsyncValue<CatalogCheckRead>? build() {
    // Another server's verdict says nothing of this one's catalog, and a
    // check still out to it does not land here.
    ref.watch(repositoryProvider);
    _run++;
    return null;
  }

  Future<void> verify() async {
    final run = ++_run;
    final clock = ref.read(wallClockProvider);
    state = const AsyncLoading();
    final read = await AsyncValue.guard(() async {
      final counts = await ref.read(repositoryProvider).getCatalogConsistency();
      return (counts: counts, at: clock());
    });
    if (ref.mounted && run == _run) state = read;
  }

  /// Queues the repair. A check read before it no longer says what the
  /// catalog holds, so it is dropped, one still out included.
  Future<ToolTask> repair() async {
    final task = await ref.read(repositoryProvider).repairCatalog();
    if (ref.mounted) {
      _run++;
      state = null;
      ref.invalidate(toolTasksProvider);
    }
    return task;
  }
}

final catalogCheckProvider =
    NotifierProvider<CatalogCheck, AsyncValue<CatalogCheckRead>?>(
      CatalogCheck.new,
    );

/// What the catalog keeps beside the files, checked against a fresh
/// count, and its repair. An administrator's: nothing for anyone else.
class CatalogCheckSection extends ConsumerWidget {
  const CatalogCheckSection({super.key});

  Future<void> _repair(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    final router = GoRouter.of(context);
    final check = ref.read(catalogCheckProvider.notifier);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.healthCatalogRepairTitle),
        content: WaxProse(l10n.healthCatalogRepairBody),
        actions: <Widget>[
          WaxButton(
            label: l10n.commonCancel,
            kind: WaxButtonKind.text,
            semanticsId: SemanticsIds.confirmCancel,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          WaxButton(
            label: l10n.healthCatalogRepair,
            semanticsId: SemanticsIds.catalogCheckRepairConfirm,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    void followInTasks(String message) => messenger.show(
      message,
      actionLabel: l10n.commonOpenTasks,
      actionSemanticsId: SemanticsIds.openTasks,
      onAction: () => router.pushInShell<void>(WaxRoute.tasks),
    );
    try {
      await check.repair();
      followInTasks(l10n.healthCatalogRepairStarted);
    } on WaxDeckApiException catch (e) {
      if (e.code == 'conflict') {
        followInTasks(l10n.healthCatalogRepairRunning);
      } else {
        messenger.show(explainError(l10n, e));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isAdminProvider)) return const SizedBox.shrink();
    final l10n = context.l10n;
    final colors = WaxColors.of(context);
    final check = ref.watch(catalogCheckProvider);
    return Semantics(
      identifier: SemanticsIds.catalogCheck,
      container: true,
      explicitChildNodes: true,
      child: Padding(
        padding: const EdgeInsets.only(top: WaxSpace.s32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(
              title: l10n.healthCatalogTitle,
              overline: l10n.healthCatalogOverline,
            ),
            WaxProse(
              l10n.healthCatalogBlurb,
              style: WaxType.body.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: WaxSpace.s12),
            Wrap(
              spacing: WaxSpace.s8,
              runSpacing: WaxSpace.s8,
              children: <Widget>[
                WaxButton(
                  label: l10n.healthCatalogVerify,
                  spokenLabel: l10n.healthCatalogVerifySpoken,
                  kind: WaxButtonKind.tonal,
                  semanticsId: SemanticsIds.catalogCheckVerify,
                  busy: check?.isLoading ?? false,
                  onPressed: () =>
                      ref.read(catalogCheckProvider.notifier).verify(),
                ),
                WaxButton(
                  label: l10n.healthCatalogRepair,
                  spokenLabel: l10n.healthCatalogRepairSpoken,
                  kind: WaxButtonKind.tonal,
                  semanticsId: SemanticsIds.catalogCheckRepair,
                  onPressed: () => _repair(context, ref),
                ),
              ],
            ),
            ...switch (check) {
              AsyncData(:final value) => <Widget>[
                const SizedBox(height: WaxSpace.s16),
                _CheckResult(check: value.counts, at: value.at),
              ],
              AsyncValue(:final error?) => <Widget>[
                const SizedBox(height: WaxSpace.s16),
                Text(
                  context.explain(error),
                  style: WaxType.caption.copyWith(color: colors.error),
                ),
              ],
              _ => const <Widget>[],
            },
          ],
        ),
      ),
    );
  }
}

/// What a check found: clean, consistent with something to tidy, or out
/// of step, when it was read, and every count above zero under it.
class _CheckResult extends StatelessWidget {
  const _CheckResult({required this.check, required this.at});

  final CatalogConsistency check;
  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = WaxColors.of(context);
    final rows = <(String, int)>[
      (l10n.healthCatalogMissingFromSearch, check.itemsMissingFromSearch),
      (l10n.healthCatalogOrphanSearchRows, check.orphanSearchRows),
      (l10n.healthCatalogArtistTotals, check.artistRollupDrift),
      (l10n.healthCatalogGenreTotals, check.genreRollupDrift),
      (l10n.healthCatalogReleaseGroupTotals, check.releaseGroupRollupDrift),
      (l10n.healthCatalogSortKeys, check.sortKeyDrift),
      (l10n.healthCatalogBookLengths, check.bookDurationDrift),
      (l10n.healthCatalogBookIsbnKeys, check.bookIsbnKeyDrift),
      (l10n.healthCatalogAlbumYears, check.albumYearDrift),
      (l10n.healthCatalogReleaseYears, check.releaseYearDrift),
      (l10n.healthCatalogPlaylistNumbering, check.playlistPositionDrift),
      (l10n.healthCatalogUnusedImages, check.orphanArtSources),
      (l10n.healthCatalogUnusedThumbnails, check.orphanThumbnails),
      (l10n.healthCatalogReservedTagRecords, check.orphanTagProvenance),
      (l10n.healthCatalogRefusedTagRows, check.strandedTagRows),
    ].where((row) => row.$2 > 0).toList();
    final (verdict, tone) = !check.consistent
        ? (l10n.healthCatalogDrift, colors.error)
        : rows.isEmpty
        ? (l10n.healthCatalogClean, colors.success)
        : (l10n.healthCatalogTidy, colors.textPrimary);
    return Semantics(
      identifier: SemanticsIds.catalogCheckResult,
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(verdict, style: WaxType.titleItem.copyWith(color: tone)),
          Text(
            l10n.healthCatalogCheckedAt(l10n.formatStamp(at)),
            style: WaxType.caption.copyWith(color: colors.textSecondary),
          ),
          for (final (label, count) in rows)
            Padding(
              padding: const EdgeInsets.only(top: WaxSpace.s8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      label,
                      style: WaxType.body.copyWith(color: colors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: WaxSpace.s12),
                  Text(
                    '$count',
                    style: WaxType.monoData.copyWith(color: colors.textPrimary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
