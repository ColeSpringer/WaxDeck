import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../admin/admin_console.dart';
import '../l10n/l10n.dart';
import '../media_view.dart';
import '../organize/organize_labels.dart';
import '../providers.dart';
import '../settings/settings_registry.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'health_controller.dart';
import 'health_labels.dart';

/// The rule whose fix moves files: the whole library's is an organize
/// pass, and a fix of named items moves them as organize jobs.
const _pathRule = 'path-mismatch';

/// Starts one rule's fix, over [itemPids] or every failing item, and says
/// where it runs or why it was refused.
Future<void> _startFix(
  BuildContext context,
  WidgetRef ref,
  String rule,
  String name, {
  List<String>? itemPids,
}) async {
  final l10n = context.l10n;
  final messenger = ref.read(shellMessengerProvider.notifier);
  final router = GoRouter.of(context);
  try {
    await ref
        .read(healthFixesProvider.notifier)
        .start(rule, itemPids: itemPids);
    messenger.show(
      l10n.healthFixStarted(name),
      actionLabel: l10n.commonOpenTasks,
      actionSemanticsId: SemanticsIds.openTasks,
      onAction: () => router.pushInShell<void>(WaxRoute.tasks),
    );
  } on WaxDeckApiException catch (e) {
    if (e.code != 'conflict') {
      messenger.show(explainError(l10n, e));
      return;
    }
    // Refused while a pass holds the enrichment, or while the rule is
    // being fixed already: the summary the refusal re-read says which.
    final fixing =
        context.mounted &&
        (ref
                .read(healthProvider)
                .value
                ?.rules
                .any((r) => r.rule == rule && r.fixing) ??
            false);
    messenger.show(fixing ? l10n.healthFixRunning(name) : l10n.healthFixBusy);
  }
}

/// The library health dashboard: the score headline, the per-rule
/// failure counts with fixes, and the duplicate and quality-upgrade
/// resolution sections.
class HealthScreen extends ConsumerWidget {
  const HealthScreen({super.key});

  Future<void> _fix(
    BuildContext context,
    WidgetRef ref,
    HealthRuleCount rule,
  ) => _startFix(context, ref, rule.rule, healthRuleLabel(context.l10n, rule));

  Future<void> _sweep(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      await ref.read(healthSweepRequestProvider.notifier).send();
      messenger.show(l10n.healthSweepQueued);
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
    }
  }

  Future<void> _merge(
    BuildContext context,
    WidgetRef ref,
    DuplicateGroup group,
  ) async {
    final l10n = context.l10n;
    final losers = group.losers.map((l) => '"${l.name}"').join(', ');
    final confirmed = await showTypedConfirm(
      context,
      title: l10n.healthMergeTitle,
      message: l10n.healthMergeBody(losers, group.survivor.name),
      confirmWord: l10n.healthMergeWord,
      confirmLabel: l10n.healthMergeAction,
      fieldSemanticsId: SemanticsIds.confirmField,
      confirmSemanticsId: SemanticsIds.confirmAccept,
      cancelSemanticsId: SemanticsIds.confirmCancel,
    );
    if (!confirmed) return;
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      final outcome = await ref.read(duplicatesProvider.notifier).merge(group);
      messenger.show(l10n.healthMerged(outcome.merged));
    } on WaxDeckApiException catch (e) {
      messenger.show(_refused(l10n, e));
    }
  }

  /// A `conflict` here says what stood in the way - for a resolve, how
  /// many moves the trash could not make and why - which the table's
  /// "something changed first" cannot.
  static String _refused(AppLocalizations l10n, WaxDeckApiException e) =>
      e.code == 'conflict' ? explainRefusal(l10n, e) : explainError(l10n, e);

  Future<void> _resolve(
    BuildContext context,
    WidgetRef ref,
    UpgradeGroup group,
  ) async {
    final l10n = context.l10n;
    final confirmed = await showTypedConfirm(
      context,
      title: l10n.healthResolveTitle,
      message: l10n.healthResolveBody,
      confirmWord: l10n.healthResolveWord,
      confirmLabel: l10n.healthResolveAction,
      fieldSemanticsId: SemanticsIds.confirmField,
      confirmSemanticsId: SemanticsIds.confirmAccept,
      cancelSemanticsId: SemanticsIds.confirmCancel,
    );
    if (!confirmed) return;
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      final trashed = await ref.read(upgradesProvider.notifier).resolve(group);
      messenger.show(l10n.healthTrashedFiles(trashed));
    } on WaxDeckApiException catch (e) {
      messenger.show(_refused(l10n, e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final l10n = context.l10n;
    final health = ref.watch(healthProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final sweeping =
        ref.watch(healthSweepRequestProvider) ||
        (health.value?.sweeping ?? false);
    return WaxScaffold(
      title: l10n.adminTileHealth,
      largeTitle: false,
      semanticsId: SemanticsIds.adminHealth,
      onBack: adminBack(context),
      actions: <Widget>[
        if (isAdmin)
          WaxIconButton(
            glyph: WaxIcons.refresh,
            label: l10n.healthSweepNow,
            semanticsId: SemanticsIds.healthSweep,
            busy: sweeping,
            onPressed: () => _sweep(context, ref),
          ),
      ],
      body: Padding(
        padding: sizeClass.gutter.add(
          const EdgeInsets.only(bottom: WaxSpace.s32),
        ),
        child: switch (health) {
          AsyncData(:final value) => _body(context, ref, value, isAdmin),
          AsyncError(:final error) => ErrorState(
            title: l10n.healthLoadError,
            message: context.explain(error),
            onRetry: () => ref.invalidate(healthProvider),
          ),
          _ => const SkeletonShapes(shape: SkeletonShape.list),
        },
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    HealthSummary summary,
    bool isAdmin,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ScoreHeadline(summary: summary),
        const SizedBox(height: WaxSpace.s32),
        SectionHeader(
          title: context.l10n.healthRulesTitle,
          overline: context.l10n.healthRulesOverline,
        ),
        _RuleTable(
          rules: summary.rules,
          // The fixes are an administrator's; everyone reads the standing.
          onFix: isAdmin ? (rule) => _fix(context, ref, rule) : null,
          onOpen: (rule) => context.go(WaxRoute.healthRule(rule)),
        ),
        const SizedBox(height: WaxSpace.s32),
        _DuplicatesSection(onMerge: (group) => _merge(context, ref, group)),
        const SizedBox(height: WaxSpace.s32),
        _UpgradesSection(onResolve: (group) => _resolve(context, ref, group)),
      ],
    );
  }
}

/// The score, or the arc filling toward it. An unevaluated library has
/// no score rather than a zero, so warming up replaces the number.
class _ScoreHeadline extends StatelessWidget {
  const _ScoreHeadline({required this.summary});

  final HealthSummary summary;

  /// Green above 90, amber in the middle, red below 60: the number is a
  /// verdict, and one drawn in the text colour reads as a statistic.
  static Color _tone(WaxColors colors, double score) {
    if (score >= 90) return colors.success;
    if (score >= 60) return colors.accent;
    return colors.error;
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    if (summary.warmingUp) {
      final progress = summary.totalItems == 0
          ? 0.0
          : summary.evaluatedItems / summary.totalItems;
      return Semantics(
        identifier: SemanticsIds.healthWarmingUp,
        container: true,
        child: _Card(
          child: Row(
            children: <Widget>[
              ProgressRing(
                progress: progress,
                size: 72,
                thickness: 5,
                child: Center(
                  child: Text(
                    '${(progress * 100).round()}%',
                    style: WaxType.monoData.copyWith(color: colors.textPrimary),
                  ),
                ),
              ),
              const SizedBox(width: WaxSpace.s20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.adminWarmingUp,
                      style: WaxType.headline.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: WaxSpace.s4),
                    Text(
                      l10n.healthEvaluatedOf(
                        summary.evaluatedItems,
                        summary.totalItems,
                      ),
                      style: WaxType.body.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    final score = summary.score.round();
    return _Card(
      child: Row(
        children: <Widget>[
          Semantics(
            identifier: SemanticsIds.healthScore,
            label: l10n.healthScoreSpoken(score),
            excludeSemantics: true,
            child: Text(
              '$score',
              style: WaxType.display.copyWith(
                color: _tone(colors, summary.score),
              ),
            ),
          ),
          const SizedBox(width: WaxSpace.s20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  l10n.healthScoreBlurb(summary.evaluatedItems),
                  style: WaxType.body.copyWith(color: colors.textSecondary),
                ),
                if (summary.sweepFailed) ...<Widget>[
                  const SizedBox(height: WaxSpace.s4),
                  Text(
                    l10n.healthSweepFailed,
                    style: WaxType.caption.copyWith(color: colors.error),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Container(
      padding: const EdgeInsets.all(WaxSpace.s20),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: WaxRadius.card,
        border: Border.all(color: colors.hairline),
      ),
      child: child,
    );
  }
}

class _RuleTable extends ConsumerWidget {
  const _RuleTable({
    required this.rules,
    required this.onFix,
    required this.onOpen,
  });

  final List<HealthRuleCount> rules;

  /// Null for a session that may not fix, which draws neither the fixes
  /// nor what blocks them.
  final void Function(HealthRuleCount rule)? onFix;
  final void Function(String rule) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final fix = onFix;
    return WaxTable<HealthRuleCount>(
      rows: rules,
      rowId: (rule) => rule.rule,
      rowSemanticsId: SemanticsIds.health,
      onRowTap: (rule) => onOpen(rule.rule),
      empty: EmptyState(
        glyph: WaxIcons.success,
        title: l10n.healthRulesEmptyTitle,
        message: l10n.healthRulesEmptyMessage,
      ),
      columns: <WaxColumn<HealthRuleCount>>[
        WaxColumn<HealthRuleCount>(
          label: l10n.healthColumnRule,
          priority: WaxColumnPriority.primary,
          text: (rule) => healthRuleLabel(l10n, rule),
          cell: (context, rule) {
            final blocked = rule.fixBlocked;
            final name = Text(
              healthRuleLabel(l10n, rule),
              style: WaxType.titleItem.copyWith(color: colors.textPrimary),
              overflow: TextOverflow.ellipsis,
            );
            if (fix == null || blocked == null || rule.failing == 0) {
              return name;
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                name,
                const SizedBox(height: WaxSpace.s4),
                Text(
                  healthFixBlockedReason(l10n, blocked),
                  style: WaxType.caption.copyWith(color: colors.textTertiary),
                ),
              ],
            );
          },
        ),
        WaxColumn<HealthRuleCount>(
          label: l10n.healthColumnFailing,
          width: 96,
          numeric: true,
          text: (rule) => '${rule.failing}',
          cell: (context, rule) => Text(
            '${rule.failing}',
            style: WaxType.monoData.copyWith(
              color: rule.failing == 0 ? colors.textTertiary : colors.error,
            ),
          ),
        ),
      ],
      trailing: (context, rule) {
        if (fix == null || rule.failing == 0) return const SizedBox.shrink();
        // Every misplaced file at once is an organize pass, previewed
        // before anything moves and undoable after.
        if (rule.fixable && rule.rule == _pathRule) {
          return WaxIconButton(
            glyph: WaxIcons.sort,
            label: l10n.healthFixPreviewMoves,
            semanticsId: SemanticsIds.healthFixPreview(rule.rule),
            onPressed: () => context.go(WaxRoute.organizePreviewOwn),
          );
        }
        if (rule.fixable) {
          return Consumer(
            builder: (context, ref, _) => WaxIconButton(
              glyph: WaxIcons.success,
              label: l10n.healthFixRule(healthRuleLabel(l10n, rule)),
              semanticsId: SemanticsIds.healthFix(rule.rule),
              busy: ref.watch(healthFixingProvider(rule.rule)),
              onPressed: () => fix(rule),
            ),
          );
        }
        final blocked = rule.fixBlocked;
        if (blocked == null) return const SizedBox.shrink();
        // The row reads as one button and excludes its cells, so what
        // blocks the fix is said here too, where it has a handle.
        final reason = healthFixBlockedReason(l10n, blocked);
        return Semantics(
          identifier: SemanticsIds.healthFixBlocked(rule.rule),
          container: true,
          label: reason,
          excludeSemantics: true,
          child: Tooltip(
            message: reason,
            child: Center(
              child: WaxIcon(
                WaxIcons.info,
                size: 20,
                color: colors.textTertiary,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DuplicatesSection extends ConsumerWidget {
  const _DuplicatesSection({required this.onMerge});

  final void Function(DuplicateGroup) onMerge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final duplicates = ref.watch(duplicatesProvider);
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: l10n.healthDuplicatesTitle,
          overline: l10n.healthDuplicatesOverline,
        ),
        switch (duplicates) {
          AsyncData(:final value) when value.isEmpty => EmptyState(
            glyph: WaxIcons.success,
            title: l10n.healthDuplicatesEmptyTitle,
            message: l10n.healthDuplicatesEmptyMessage,
          ),
          AsyncData(:final value) => WaxTable<DuplicateGroup>(
            rows: value,
            rowId: (group) => group.survivor.pid,
            rowSemanticsId: SemanticsIds.duplicateGroup,
            rowDetailSemanticsId: SemanticsIds.duplicateDetail,
            columns: <WaxColumn<DuplicateGroup>>[
              WaxColumn<DuplicateGroup>(
                label: l10n.healthColumnSurvivor,
                priority: WaxColumnPriority.primary,
                text: (group) => group.survivor.name,
                cell: (context, group) => Text(
                  group.survivor.name,
                  style: WaxType.titleItem.copyWith(color: colors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              WaxColumn<DuplicateGroup>(
                label: l10n.healthColumnAbsorbs,
                text: (group) => group.losers.map((l) => l.name).join(', '),
                cell: (context, group) => Text(
                  group.losers.map((l) => l.name).join(', '),
                  style: WaxType.bodySmall.copyWith(
                    color: colors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              WaxColumn<DuplicateGroup>(
                label: l10n.healthColumnKind,
                width: 96,
                text: (group) => healthEntityKind(l10n, group.entityType),
                cell: (context, group) =>
                    CodecChip(healthEntityKind(l10n, group.entityType)),
              ),
              WaxColumn<DuplicateGroup>(
                label: l10n.healthColumnWhy,
                priority: WaxColumnPriority.detail,
                text: (group) => group.detail ?? l10n.healthNamesMatch,
                cell: (context, group) => Text(
                  group.detail ?? l10n.healthNamesMatch,
                  style: WaxType.caption.copyWith(color: colors.textTertiary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            trailing: (context, group) => WaxIconButton(
              glyph: WaxIcons.check,
              label: l10n.healthMergeInto(group.survivor.name),
              semanticsId: SemanticsIds.duplicateMerge(group.survivor.pid),
              onPressed: () => onMerge(group),
            ),
          ),
          AsyncError(:final error) => ErrorState(
            title: l10n.healthDuplicatesError,
            message: context.explain(error),
            onRetry: () => ref.invalidate(duplicatesProvider),
            retrySemanticsId: SemanticsIds.duplicatesRetry,
          ),
          _ => const SkeletonShapes(shape: SkeletonShape.list),
        },
      ],
    );
  }
}

/// What names an upgrade group in its row's identifiers: its files, as
/// one file can head two groups (its item's own encodings, and the items
/// its recording ties).
String upgradeGroupKey(UpgradeGroup group) =>
    [for (final m in group.members) m.filePid].join('+');

class _UpgradesSection extends ConsumerWidget {
  const _UpgradesSection({required this.onResolve});

  final void Function(UpgradeGroup) onResolve;

  static UpgradeMember best(UpgradeGroup group) =>
      group.members.where((m) => m.best).firstOrNull ?? group.members.first;

  /// What one encoding is: codec, kilobits, and for a lossless one how
  /// fine its samples are. Two members of a group that read alike are
  /// told apart by their files' names.
  static String _memberLine(
    AppLocalizations l10n,
    UpgradeMember member,
    UpgradeGroup group,
  ) {
    final quality = _quality(l10n, member);
    final alike = group.members.where((m) => _quality(l10n, m) == quality);
    if (alike.length < 2) return quality;
    final name = member.path?.split(RegExp(r'[\\/]')).last ?? member.filePid;
    return l10n.healthMemberInFile(quality, name);
  }

  static String _quality(AppLocalizations l10n, UpgradeMember member) => [
    member.codec,
    if (member.bitrate != null) l10n.unitKbps(member.bitrate!),
    if (member.lossless) l10n.healthLossless,
    if (member.lossless && member.sampleRate != null)
      l10n.formatSampleRate(member.sampleRate!),
  ].join(', ');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upgrades = ref.watch(upgradesProvider);
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: l10n.healthUpgradesTitle,
          overline: l10n.healthUpgradesOverline,
        ),
        switch (upgrades) {
          AsyncData(:final value) when value.isEmpty => EmptyState(
            glyph: WaxIcons.success,
            title: l10n.healthUpgradesEmptyTitle,
            message: l10n.healthUpgradesEmptyMessage,
          ),
          AsyncData(:final value) => WaxTable<UpgradeGroup>(
            rows: value,
            rowId: upgradeGroupKey,
            rowSemanticsId: SemanticsIds.upgradeGroup,
            rowDetailSemanticsId: SemanticsIds.upgradeDetail,
            columns: <WaxColumn<UpgradeGroup>>[
              WaxColumn<UpgradeGroup>(
                label: l10n.healthColumnRecording,
                priority: WaxColumnPriority.primary,
                text: (group) => _recording(l10n, best(group)),
                cell: (context, group) => Text(
                  _recording(l10n, best(group)),
                  style: WaxType.titleItem.copyWith(color: colors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              WaxColumn<UpgradeGroup>(
                label: l10n.healthColumnKeeping,
                width: 180,
                text: (group) => _memberLine(l10n, best(group), group),
                cell: (context, group) => CodecChip(
                  _memberLine(l10n, best(group), group),
                  emphasis: true,
                ),
              ),
              WaxColumn<UpgradeGroup>(
                label: l10n.healthColumnTrashing,
                priority: WaxColumnPriority.detail,
                text: (group) => _trashing(l10n, group),
                cell: (context, group) => Text(
                  _trashing(l10n, group),
                  style: WaxType.caption.copyWith(color: colors.textTertiary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            trailing: (context, group) => WaxIconButton(
              glyph: WaxIcons.check,
              label: l10n.healthKeepBest,
              semanticsId: SemanticsIds.upgradeResolve(upgradeGroupKey(group)),
              onPressed: () => onResolve(group),
            ),
          ),
          AsyncError(:final error) => ErrorState(
            title: l10n.healthUpgradesError,
            message: context.explain(error),
            onRetry: () => ref.invalidate(upgradesProvider),
            retrySemanticsId: SemanticsIds.upgradesRetry,
          ),
          _ => const SkeletonShapes(shape: SkeletonShape.list),
        },
      ],
    );
  }
}

/// One recording named the way both health tables name it.
String _recording(AppLocalizations l10n, UpgradeMember member) {
  final artist = member.artist;
  return artist == null
      ? member.title
      : l10n.healthTitleByArtist(member.title, artist);
}

/// The copies a resolution would trash, worded one per copy.
String _trashing(AppLocalizations l10n, UpgradeGroup group) {
  // The kept copy once, not once per member: the predicate runs for
  // every row and `best` walks the group each time it is asked.
  final keeping = _UpgradesSection.best(group).filePid;
  return group.members
      .where((m) => m.filePid != keeping)
      .map((m) => _UpgradesSection._memberLine(l10n, m, group))
      .join('; ');
}

/// The paginated failing items behind one health rule.
class HealthIssuesScreen extends ConsumerWidget {
  const HealthIssuesScreen({super.key, required this.rule});

  final String rule;

  /// Moves one misplaced item where its library's profile puts it, once
  /// a dry run of it says where and the administrator agrees.
  Future<void> _moveIntoPlace(
    BuildContext context,
    WidgetRef ref,
    HealthIssue issue,
  ) async {
    // Held from the press until the fix starts or is declined, so a second
    // tap meanwhile starts nothing.
    final moving = ref.read(movingIssuesProvider.notifier);
    if (!moving.start(issue.pid)) return;
    try {
      await _confirmMove(context, ref, issue);
    } finally {
      moving.end(issue.pid);
    }
  }

  Future<void> _confirmMove(
    BuildContext context,
    WidgetRef ref,
    HealthIssue issue,
  ) async {
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    final OrganizePlan plan;
    try {
      plan = await ref
          .read(repositoryProvider)
          .previewOrganize(itemPids: [issue.pid]);
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
      return;
    }
    if (!context.mounted) return;
    if (plan.actions.isEmpty) {
      // A library gone read-only since the sweep leaves the file out of
      // the plan, out of place all the same.
      final hold = plan.holds.firstOrNull;
      messenger.show(switch (hold) {
        OrganizeHold(:final code) => l10n.healthIssueFixHeld(
          organizeHoldLabel(l10n, code, planned: true),
        ),
        null when plan.readOnlyLibraries > 0 => l10n.healthIssueFixHeld(
          l10n.organizeHoldReadOnly,
        ),
        null => l10n.healthIssueFixInPlace,
      });
      return;
    }
    final colors = WaxColors.of(context);
    // A book moves as all its parts, so each is named.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.healthIssueFixTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final move in plan.actions) ...<Widget>[
                Text(
                  l10n.organizeColumnFrom,
                  style: WaxType.caption.copyWith(color: colors.textTertiary),
                ),
                Text(
                  move.from,
                  style: WaxType.monoData.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: WaxSpace.s8),
                Text(
                  l10n.organizeColumnTo,
                  style: WaxType.caption.copyWith(color: colors.textTertiary),
                ),
                Text(
                  move.to,
                  style: WaxType.monoData.copyWith(color: colors.accent),
                ),
                const SizedBox(height: WaxSpace.s12),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          WaxButton(
            label: l10n.commonCancel,
            kind: WaxButtonKind.text,
            semanticsId: SemanticsIds.confirmCancel,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          WaxButton(
            label: l10n.healthIssueFixAction,
            semanticsId: SemanticsIds.healthIssueFixConfirm,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _startFix(
      context,
      ref,
      rule,
      healthRuleName(l10n, rule) ?? rule,
      itemPids: [issue.pid],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final issues = ref.watch(healthIssuesProvider(rule));
    final moving = ref.watch(movingIssuesProvider);
    // An administrator moves a misplaced file from its own row, while the
    // install can fix the rule at all.
    final movable =
        rule == _pathRule &&
        ref.watch(isAdminProvider) &&
        (ref
                .watch(healthProvider)
                .value
                ?.rules
                .any((r) => r.rule == rule && r.fixable) ??
            false);
    // The rule arrives as its own path segment, so the title is the
    // client's word for it rather than the wire token the table it was
    // opened from already stopped drawing.
    final title = healthRuleName(context.l10n, rule) ?? rule;
    // A failed "load more" keeps the list intact, so surface it on the
    // flag's rising edge; scrolling again retries.
    final l10n = context.l10n;
    ref.listen(healthIssuesProvider(rule), (prev, next) {
      final failedNow = next.value?.loadError ?? false;
      final failedBefore = prev?.value?.loadError ?? false;
      if (failedNow && !failedBefore) {
        ref
            .read(shellMessengerProvider.notifier)
            .show(l10n.healthLoadMoreFailed);
      }
    });
    // Paged off the scroll rather than from the builder: a `loadMore`
    // called while the list is building mutates provider state mid-build
    // and re-fires on every rebuild of the sentinel.
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (metrics.pixels >= metrics.maxScrollExtent - 400) {
          ref.read(healthIssuesProvider(rule).notifier).loadMore();
        }
        return false;
      },
      child: WaxScaffold(
        title: title,
        largeTitle: false,
        semanticsId: SemanticsIds.adminHealthRule,
        onBack: () => context.leave(fallback: WaxRoute.health),
        slivers: <Widget>[
          switch (issues) {
            AsyncData(:final value) when value.items.isEmpty =>
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  glyph: WaxIcons.success,
                  title: context.l10n.healthIssuesEmptyTitle,
                  message: context.l10n.healthIssuesEmptyMessage,
                ),
              ),
            AsyncData(:final value) => SliverPadding(
              padding: sizeClass.gutter,
              sliver: _list(
                value,
                movable ? (issue) => _moveIntoPlace(context, ref, issue) : null,
                moving,
              ),
            ),
            AsyncError(:final error) => SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorState(
                title: context.l10n.healthIssuesError,
                message: context.explain(error),
                onRetry: () => ref.invalidate(healthIssuesProvider(rule)),
              ),
            ),
            _ => const SliverFillRemaining(
              hasScrollBody: false,
              child: SkeletonShapes(shape: SkeletonShape.list),
            ),
          },
        ],
      ),
    );
  }

  Widget _list(
    HealthIssuesState state,
    void Function(HealthIssue issue)? onMove,
    Set<String> moving,
  ) {
    return SliverList.builder(
      itemCount: state.items.length + (state.loadingMore ? 1 : 0),
      // Keyed by item, so a row moves with its issue, node and identifiers
      // with it, when a fixed one drops out above it.
      findChildIndexCallback: indexByKey(state.items, _issueKey),
      itemBuilder: (context, index) => index >= state.items.length
          ? const Padding(
              padding: EdgeInsets.all(WaxSpace.s16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : _IssueRow(
              key: _issueKey(state.items[index]),
              issue: state.items[index],
              onMove: onMove,
              moving: moving.contains(state.items[index].pid),
            ),
    );
  }
}

/// Both lengths, saying whose they are when not the item's own file.
String _durationDetail(AppLocalizations l10n, HealthIssueDetail detail) {
  final header = formatTimecode(Duration(milliseconds: detail.headerMs!));
  final audio = formatTimecode(Duration(milliseconds: detail.decodedMs!));
  if (detail.partIndex case final int part) {
    return l10n.healthDurationDetailPart(part + 1, header, audio);
  }
  if (detail.wholeFile) return l10n.healthDurationDetailFile(header, audio);
  return l10n.healthDurationDetail(header, audio);
}

Key _issueKey(HealthIssue issue) => ValueKey(issue.pid);

class _IssueRow extends StatelessWidget {
  const _IssueRow({
    super.key,
    required this.issue,
    this.onMove,
    this.moving = false,
  });

  final HealthIssue issue;

  /// Null where the row's file is not the administrator's to move.
  final void Function(HealthIssue issue)? onMove;

  /// A move of this row's file is under way.
  final bool moving;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final artist = issue.artist;
    final title = artist == null
        ? issue.title
        : l10n.healthTitleByArtist(issue.title, artist);
    return Semantics(
      identifier: SemanticsIds.healthIssue(issue.pid),
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: WaxSpace.s8),
        child: Row(
          children: <Widget>[
            DomainBadge(waxDomainOf(issue.mediaType), compact: true),
            const SizedBox(width: WaxSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: WaxType.titleItem.copyWith(
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    issue.rules
                        .map((r) => healthRuleName(l10n, r) ?? r)
                        .join(', '),
                    style: WaxType.caption.copyWith(color: colors.textTertiary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (issue.detail case final HealthIssueDetail detail?
                      when detail.headerMs != null && detail.decodedMs != null)
                    Text(
                      _durationDetail(l10n, detail),
                      style: WaxType.caption.copyWith(
                        color: colors.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (onMove case final move?)
              WaxIconButton(
                glyph: WaxIcons.sort,
                label: l10n.healthIssueFix,
                semanticsId: SemanticsIds.healthIssueFix(issue.pid),
                busy: moving,
                onPressed: moving ? null : () => move(issue),
              ),
          ],
        ),
      ),
    );
  }
}
