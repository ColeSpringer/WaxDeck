import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../admin/admin_console.dart';
import '../auth/auth_controller.dart';
import '../media_view.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'health_controller.dart';

/// The library health dashboard: the score headline, the per-rule
/// failure counts with fixes, and the duplicate and quality-upgrade
/// resolution sections.
class HealthScreen extends ConsumerWidget {
  const HealthScreen({super.key});

  Future<void> _fix(WidgetRef ref, String rule) async {
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      final queued = await ref.read(healthProvider.notifier).fix(rule);
      messenger.show('Queued $queued items');
    } on WaxDeckApiException catch (e) {
      messenger.show(e.message);
    }
  }

  Future<void> _sweep(WidgetRef ref) async {
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      await ref.read(healthProvider.notifier).sweep();
      messenger.show('Sweep queued');
    } on WaxDeckApiException catch (e) {
      messenger.show(e.message);
    }
  }

  Future<void> _merge(
    BuildContext context,
    WidgetRef ref,
    DuplicateGroup group,
  ) async {
    final losers = group.losers.map((l) => '"${l.name}"').join(', ');
    final confirmed = await showTypedConfirm(
      context,
      title: 'Merge duplicates?',
      message:
          '$losers will merge into "${group.survivor.name}". Their items '
          'move under the survivor, and the merge cannot be undone.',
      confirmWord: 'merge',
      confirmLabel: 'Merge',
      fieldSemanticsId: SemanticsIds.confirmField,
      confirmSemanticsId: SemanticsIds.confirmAccept,
      cancelSemanticsId: SemanticsIds.confirmCancel,
    );
    if (!confirmed) return;
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      final outcome = await ref.read(duplicatesProvider.notifier).merge(group);
      messenger.show('Merged ${outcome.merged} entries');
    } on WaxDeckApiException catch (e) {
      messenger.show(e.message);
    }
  }

  Future<void> _resolve(
    BuildContext context,
    WidgetRef ref,
    UpgradeGroup group,
  ) async {
    final confirmed = await showTypedConfirm(
      context,
      title: 'Keep the best version?',
      message:
          'The other versions move to the server trash and can be restored '
          'until the trash window closes.',
      confirmWord: 'resolve',
      confirmLabel: 'Resolve',
      fieldSemanticsId: SemanticsIds.confirmField,
      confirmSemanticsId: SemanticsIds.confirmAccept,
      cancelSemanticsId: SemanticsIds.confirmCancel,
    );
    if (!confirmed) return;
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      final trashed = await ref.read(upgradesProvider.notifier).resolve(group);
      messenger.show('Trashed $trashed files');
    } on WaxDeckApiException catch (e) {
      messenger.show(e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
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
      title: 'Library health',
      largeTitle: false,
      semanticsId: SemanticsIds.adminHealth,
      onBack: adminBack(context),
      actions: <Widget>[
        if (isAdmin)
          WaxIconButton(
            glyph: WaxIcons.refresh,
            label: 'Sweep now',
            semanticsId: SemanticsIds.healthSweep,
            onPressed: () => _sweep(ref),
          ),
      ],
      body: Padding(
        padding: sizeClass.gutter.add(
          const EdgeInsets.only(bottom: WaxSpace.s32),
        ),
        child: switch (health) {
          AsyncData(:final value) => _body(context, ref, value),
          AsyncError(:final error) => ErrorState(
            title: 'Could not load library health',
            message: error is WaxDeckApiException
                ? error.message
                : 'Something went wrong reading it.',
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
        const SectionHeader(
          title: 'Rules',
          overline: 'What the sweeper checks',
        ),
        _RuleTable(
          rules: summary.rules,
          onFix: (rule) => _fix(ref, rule),
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
                      'Still warming up',
                      style: WaxType.headline.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: WaxSpace.s4),
                    Text(
                      'Evaluated ${summary.evaluatedItems} of '
                      '${summary.totalItems} items',
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
            label: 'Health score $score',
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
              'Library health across ${summary.evaluatedItems} evaluated '
              'items',
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
    return WaxTable<HealthRuleCount>(
      rows: rules,
      rowId: (rule) => rule.rule,
      rowSemanticsId: SemanticsIds.health,
      onRowTap: (rule) => onOpen(rule.rule),
      empty: const EmptyState(
        glyph: WaxIcons.success,
        title: 'Nothing to check yet',
        message: 'Rules appear once the sweeper has evaluated the library.',
      ),
      columns: <WaxColumn<HealthRuleCount>>[
        WaxColumn<HealthRuleCount>(
          label: 'Rule',
          priority: WaxColumnPriority.primary,
          text: (rule) => rule.label ?? rule.rule,
          cell: (context, rule) => Text(
            rule.label ?? rule.rule,
            style: WaxType.titleItem.copyWith(color: colors.textPrimary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        WaxColumn<HealthRuleCount>(
          label: 'Failing',
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
              label: 'Fix ${rule.label ?? rule.rule}',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(
          title: 'Duplicates',
          overline: 'One thing under two names',
        ),
        switch (duplicates) {
          AsyncData(:final value) when value.isEmpty => const EmptyState(
            glyph: WaxIcons.success,
            title: 'No duplicates detected',
            message: 'Artists, albums, and shows each appear once.',
          ),
          AsyncData(:final value) => WaxTable<DuplicateGroup>(
            rows: value,
            rowId: (group) => group.survivor.pid,
            rowSemanticsId: SemanticsIds.duplicateGroup,
            rowDetailSemanticsId: SemanticsIds.duplicateDetail,
            columns: <WaxColumn<DuplicateGroup>>[
              WaxColumn<DuplicateGroup>(
                label: 'Survivor',
                priority: WaxColumnPriority.primary,
                text: (group) => group.survivor.name,
                cell: (context, group) => Text(
                  group.survivor.name,
                  style: WaxType.titleItem.copyWith(color: colors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              WaxColumn<DuplicateGroup>(
                label: 'Absorbs',
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
                label: 'Kind',
                width: 96,
                text: (group) => group.entityType,
                cell: (context, group) => CodecChip(group.entityType),
              ),
              WaxColumn<DuplicateGroup>(
                label: 'Why',
                priority: WaxColumnPriority.detail,
                text: (group) => group.detail ?? 'Names match',
                cell: (context, group) => Text(
                  group.detail ?? 'Names match',
                  style: WaxType.caption.copyWith(color: colors.textTertiary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            trailing: (context, group) => WaxIconButton(
              glyph: WaxIcons.check,
              label: 'Merge into ${group.survivor.name}',
              semanticsId: SemanticsIds.duplicateMerge(group.survivor.pid),
              onPressed: () => onMerge(group),
            ),
          ),
          AsyncError() => const ErrorState(
            title: 'Could not load duplicates',
            message: 'The clustering pass did not answer.',
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

  static String _memberLine(UpgradeMember member) {
    final parts = [
      member.codec,
      if (member.bitrate != null) '${member.bitrate! ~/ 1000} kbps',
      if (member.lossless) 'lossless',
    ];
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upgrades = ref.watch(upgradesProvider);
    final colors = WaxColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(
          title: 'Quality upgrades',
          overline: 'The same recording twice',
        ),
        switch (upgrades) {
          AsyncData(:final value) when value.isEmpty => const EmptyState(
            glyph: WaxIcons.success,
            title: 'No duplicate qualities detected',
            message: 'Every recording is held once.',
          ),
          AsyncData(:final value) => WaxTable<UpgradeGroup>(
            rows: value,
            rowId: (group) => best(group).itemPid,
            rowSemanticsId: SemanticsIds.upgradeGroup,
            rowDetailSemanticsId: SemanticsIds.upgradeDetail,
            columns: <WaxColumn<UpgradeGroup>>[
              WaxColumn<UpgradeGroup>(
                label: 'Recording',
                priority: WaxColumnPriority.primary,
                text: (group) => best(group).artist == null
                    ? best(group).title
                    : '${best(group).title} by ${best(group).artist}',
                cell: (context, group) => Text(
                  best(group).artist == null
                      ? best(group).title
                      : '${best(group).title} by ${best(group).artist}',
                  style: WaxType.titleItem.copyWith(color: colors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              WaxColumn<UpgradeGroup>(
                label: 'Keeping',
                width: 180,
                text: (group) => _memberLine(best(group)),
                cell: (context, group) =>
                    CodecChip(_memberLine(best(group)), emphasis: true),
              ),
              WaxColumn<UpgradeGroup>(
                label: 'Trashing',
                priority: WaxColumnPriority.detail,
                text: (group) => group.members
                    .where((m) => m.itemPid != best(group).itemPid)
                    .map(_memberLine)
                    .join('; '),
                cell: (context, group) => Text(
                  group.members
                      .where((m) => m.itemPid != best(group).itemPid)
                      .map(_memberLine)
                      .join('; '),
                  style: WaxType.caption.copyWith(color: colors.textTertiary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            trailing: (context, group) => WaxIconButton(
              glyph: WaxIcons.check,
              label: 'Keep the best version',
              semanticsId: SemanticsIds.upgradeResolve(best(group).itemPid),
              onPressed: () => onResolve(group),
            ),
          ),
          AsyncError() => const ErrorState(
            title: 'Could not load upgrades',
            message: 'The quality comparison did not answer.',
          ),
          _ => const SkeletonShapes(shape: SkeletonShape.list),
        },
      ],
    );
  }
}

/// The paginated failing items behind one health rule.
class HealthIssuesScreen extends ConsumerWidget {
  const HealthIssuesScreen({super.key, required this.rule});

  final String rule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final issues = ref.watch(healthIssuesProvider(rule));
    // A failed "load more" keeps the list intact, so surface it on the
    // flag's rising edge; scrolling again retries.
    ref.listen(healthIssuesProvider(rule), (prev, next) {
      final failedNow = next.value?.loadError ?? false;
      final failedBefore = prev?.value?.loadError ?? false;
      if (failedNow && !failedBefore) {
        ref
            .read(shellMessengerProvider.notifier)
            .show('Could not load more; scroll to retry');
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
        title: rule,
        largeTitle: false,
        semanticsId: SemanticsIds.adminHealthRule,
        onBack: () => context.leave(fallback: WaxRoute.health),
        slivers: <Widget>[
          switch (issues) {
            AsyncData(:final value) when value.items.isEmpty =>
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  glyph: WaxIcons.success,
                  title: 'Nothing failing this rule',
                  message: 'Every item the sweeper has seen passes it.',
                ),
              ),
            AsyncData(:final value) => SliverPadding(
              padding: sizeClass.gutter,
              sliver: _list(value),
            ),
            AsyncError(:final error) => SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorState(
                title: 'Could not load issues',
                message: error is WaxDeckApiException
                    ? error.message
                    : 'The server did not answer.',
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
    final title = issue.artist == null
        ? issue.title
        : '${issue.title} by ${issue.artist}';
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
                    issue.rules.join(', '),
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
