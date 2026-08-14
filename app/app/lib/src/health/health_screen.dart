import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../admin/admin_console.dart';
import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../media_view.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'health_controller.dart';
import 'health_labels.dart';

/// The library health dashboard: the score headline, the per-rule
/// failure counts with fixes, and the duplicate and quality-upgrade
/// resolution sections.
class HealthScreen extends ConsumerWidget {
  const HealthScreen({super.key});

  Future<void> _fix(BuildContext context, WidgetRef ref, String rule) async {
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      final queued = await ref.read(healthProvider.notifier).fix(rule);
      messenger.show(l10n.healthQueuedItems(queued));
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
    }
  }

  Future<void> _sweep(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      await ref.read(healthProvider.notifier).sweep();
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
      messenger.show(explainError(l10n, e));
    }
  }

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
      messenger.show(explainError(l10n, e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final l10n = context.l10n;
    final health = ref.watch(healthProvider);
    final isAdmin =
        ref
            .watch(authControllerProvider)
            .value
            ?.user
            ?.roles
            .contains('admin') ??
        false;
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
            onPressed: () => _sweep(context, ref),
          ),
      ],
      body: Padding(
        padding: sizeClass.gutter.add(
          const EdgeInsets.only(bottom: WaxSpace.s32),
        ),
        child: switch (health) {
          AsyncData(:final value) => _body(context, ref, value),
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

  Widget _body(BuildContext context, WidgetRef ref, HealthSummary summary) {
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
          onFix: (rule) => _fix(context, ref, rule),
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
            child: Text(
              l10n.healthScoreBlurb(summary.evaluatedItems),
              style: WaxType.body.copyWith(color: colors.textSecondary),
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

class _RuleTable extends StatelessWidget {
  const _RuleTable({
    required this.rules,
    required this.onFix,
    required this.onOpen,
  });

  final List<HealthRuleCount> rules;
  final void Function(String rule) onFix;
  final void Function(String rule) onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
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
          cell: (context, rule) => Text(
            healthRuleLabel(l10n, rule),
            style: WaxType.titleItem.copyWith(color: colors.textPrimary),
            overflow: TextOverflow.ellipsis,
          ),
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
      trailing: (context, rule) => rule.fixable && rule.failing > 0
          ? WaxIconButton(
              glyph: WaxIcons.success,
              label: l10n.healthFixRule(healthRuleLabel(l10n, rule)),
              semanticsId: SemanticsIds.healthFix(rule.rule),
              onPressed: () => onFix(rule.rule),
            )
          : const SizedBox.shrink(),
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
          AsyncError() => ErrorState(
            title: l10n.healthDuplicatesError,
            message: l10n.healthDuplicatesErrorBody,
          ),
          _ => const SkeletonShapes(shape: SkeletonShape.list),
        },
      ],
    );
  }
}

class _UpgradesSection extends ConsumerWidget {
  const _UpgradesSection({required this.onResolve});

  final void Function(UpgradeGroup) onResolve;

  static UpgradeMember best(UpgradeGroup group) =>
      group.members.where((m) => m.best).firstOrNull ?? group.members.first;

  static String _memberLine(AppLocalizations l10n, UpgradeMember member) {
    final parts = <String>[
      member.codec,
      if (member.bitrate != null) l10n.healthKbps(member.bitrate! ~/ 1000),
      if (member.lossless) l10n.healthLossless,
    ];
    return parts.join(', ');
  }

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
            rowId: (group) => best(group).itemPid,
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
                text: (group) => _memberLine(l10n, best(group)),
                cell: (context, group) =>
                    CodecChip(_memberLine(l10n, best(group)), emphasis: true),
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
              semanticsId: SemanticsIds.upgradeResolve(best(group).itemPid),
              onPressed: () => onResolve(group),
            ),
          ),
          AsyncError() => ErrorState(
            title: l10n.healthUpgradesError,
            message: l10n.healthUpgradesErrorBody,
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
  final keeping = _UpgradesSection.best(group).itemPid;
  return group.members
      .where((m) => m.itemPid != keeping)
      .map((m) => _UpgradesSection._memberLine(l10n, m))
      .join('; ');
}

/// The paginated failing items behind one health rule.
class HealthIssuesScreen extends ConsumerWidget {
  const HealthIssuesScreen({super.key, required this.rule});

  final String rule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final issues = ref.watch(healthIssuesProvider(rule));
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
              sliver: _list(value),
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

  Widget _list(HealthIssuesState state) {
    return SliverList.builder(
      itemCount: state.items.length + (state.loadingMore ? 1 : 0),
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
          : _IssueRow(issue: state.items[index]),
    );
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.issue});

  final HealthIssue issue;

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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
