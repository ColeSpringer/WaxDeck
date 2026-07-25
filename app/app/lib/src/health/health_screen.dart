import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../auth/auth_controller.dart';
import '../media_icons.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'health_controller.dart';

/// The library health dashboard: the score headline, the per-rule
/// failure counts with fixes, and the duplicate and quality-upgrade
/// resolution sections.
class HealthScreen extends ConsumerWidget {
  const HealthScreen({super.key});

  Future<void> _fix(BuildContext context, WidgetRef ref, String rule) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final queued = await ref.read(healthProvider.notifier).fix(rule);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Queued $queued items')));
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _sweep(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(healthProvider.notifier).sweep();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Sweep queued')));
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _merge(
    BuildContext context,
    WidgetRef ref,
    DuplicateGroup group,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final losers = group.losers.map((l) => '"${l.name}"').join(', ');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Merge duplicates?'),
        content: Text(
          '$losers will merge into "${group.survivor.name}". '
          'Their items move under the survivor.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('duplicate-merge-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Merge'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final outcome = await ref.read(duplicatesProvider.notifier).merge(group);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Merged ${outcome.merged} entries')),
        );
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _resolve(
    BuildContext context,
    WidgetRef ref,
    UpgradeGroup group,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keep the best version?'),
        content: const Text(
          'The other versions move to the server trash and can be '
          'restored until the trash window closes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('upgrade-resolve-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final trashed = await ref.read(upgradesProvider.notifier).resolve(group);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Trashed $trashed files')));
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthProvider);
    final isAdmin =
        ref
            .watch(authControllerProvider)
            .value
            ?.user
            ?.roles
            .contains('admin') ??
        false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library health'),
        actions: [
          if (isAdmin)
            Semantics(
              identifier: SemanticsIds.healthSweep,
              label: 'Sweep now',
              button: true,
              child: IconButton(
                key: const Key(SemanticsIds.healthSweep),
                tooltip: 'Sweep now',
                icon: const Icon(Icons.autorenew),
                onPressed: () => _sweep(context, ref),
              ),
            ),
        ],
      ),
      body: switch (health) {
        AsyncData(:final value) => _body(context, ref, value),
        AsyncError(:final error) => _errorView(context, ref, error),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _errorView(BuildContext context, WidgetRef ref, Object error) {
    final message = error is WaxDeckApiException
        ? error.message
        : 'Could not load library health';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => ref.invalidate(healthProvider),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, HealthSummary summary) {
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _scoreCard(context, summary),
          const SizedBox(height: 16),
          Text('Rules', style: textTheme.titleMedium),
          for (final rule in summary.rules)
            _RuleRow(
              rule: rule,
              onFix: () => _fix(context, ref, rule.rule),
              onOpen: () => context.push(WaxRoute.healthRule(rule.rule)),
            ),
          const SizedBox(height: 16),
          _DuplicatesSection(onMerge: (group) => _merge(context, ref, group)),
          const SizedBox(height: 16),
          _UpgradesSection(onResolve: (group) => _resolve(context, ref, group)),
        ],
      ),
    );
  }

  Widget _scoreCard(BuildContext context, HealthSummary summary) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    if (summary.warmingUp) {
      final progress = summary.totalItems == 0
          ? null
          : summary.evaluatedItems / summary.totalItems;
      return Card(
        key: const Key(SemanticsIds.healthWarmingUp),
        child: Semantics(
          identifier: SemanticsIds.healthWarmingUp,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Still warming up', style: textTheme.titleMedium),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 4),
                Text(
                  'Evaluated ${summary.evaluatedItems} of '
                  '${summary.totalItems} items',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Semantics(
              identifier: SemanticsIds.healthScore,
              label: 'Health score ${summary.score.round()}',
              child: Text(
                '${summary.score.round()}',
                key: const Key(SemanticsIds.healthScore),
                style: textTheme.displayLarge?.copyWith(
                  color: colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'Library health across ${summary.evaluatedItems} '
                'evaluated items',
                style: textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.rule,
    required this.onFix,
    required this.onOpen,
  });

  final HealthRuleCount rule;
  final VoidCallback onFix;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: SemanticsIds.health(rule.rule),
      label: rule.label ?? rule.rule,
      button: true,
      child: ListTile(
        key: ValueKey(SemanticsIds.health(rule.rule)),
        contentPadding: EdgeInsets.zero,
        title: Text(rule.label ?? rule.rule),
        subtitle: Text('${rule.failing} failing'),
        onTap: onOpen,
        trailing: rule.fixable && rule.failing > 0
            ? Semantics(
                identifier: SemanticsIds.healthFix(rule.rule),
                label: 'Fix ${rule.label ?? rule.rule}',
                button: true,
                child: FilledButton.tonal(
                  key: ValueKey(SemanticsIds.healthFix(rule.rule)),
                  onPressed: onFix,
                  child: const Text('Fix'),
                ),
              )
            : null,
      ),
    );
  }
}

class _DuplicatesSection extends ConsumerWidget {
  const _DuplicatesSection({required this.onMerge});

  final void Function(DuplicateGroup) onMerge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final duplicates = ref.watch(duplicatesProvider);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Duplicates', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        switch (duplicates) {
          AsyncData(:final value) when value.isEmpty => const Text(
            'No duplicates detected',
          ),
          AsyncData(:final value) => Column(
            children: [
              for (final group in value)
                _DuplicateCard(group: group, onMerge: () => onMerge(group)),
            ],
          ),
          AsyncError() => const Text('Could not load duplicates'),
          _ => const Padding(
            padding: EdgeInsets.all(8),
            child: LinearProgressIndicator(),
          ),
        },
      ],
    );
  }
}

class _DuplicateCard extends StatelessWidget {
  const _DuplicateCard({required this.group, required this.onMerge});

  final DuplicateGroup group;
  final VoidCallback onMerge;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      identifier: SemanticsIds.duplicateGroup(group.survivor.pid),
      child: Card(
        key: ValueKey(SemanticsIds.duplicateGroup(group.survivor.pid)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.survivor.name, style: textTheme.titleSmall),
                    Text(
                      '${group.entityType}; absorbs '
                      '${group.losers.map((l) => l.name).join(', ')}',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (group.detail != null)
                      Text(group.detail!, style: textTheme.bodySmall),
                  ],
                ),
              ),
              Semantics(
                identifier: SemanticsIds.duplicateMerge(group.survivor.pid),
                label: 'Merge into ${group.survivor.name}',
                button: true,
                child: FilledButton.tonal(
                  key: ValueKey(
                    SemanticsIds.duplicateMerge(group.survivor.pid),
                  ),
                  onPressed: onMerge,
                  child: const Text('Merge'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpgradesSection extends ConsumerWidget {
  const _UpgradesSection({required this.onResolve});

  final void Function(UpgradeGroup) onResolve;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upgrades = ref.watch(upgradesProvider);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quality upgrades', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        switch (upgrades) {
          AsyncData(:final value) when value.isEmpty => const Text(
            'No duplicate qualities detected',
          ),
          AsyncData(:final value) => Column(
            children: [
              for (final group in value)
                _UpgradeCard(group: group, onResolve: () => onResolve(group)),
            ],
          ),
          AsyncError() => const Text('Could not load upgrades'),
          _ => const Padding(
            padding: EdgeInsets.all(8),
            child: LinearProgressIndicator(),
          ),
        },
      ],
    );
  }
}

class _UpgradeCard extends StatelessWidget {
  const _UpgradeCard({required this.group, required this.onResolve});

  final UpgradeGroup group;
  final VoidCallback onResolve;

  static String _memberLine(UpgradeMember member) {
    final parts = [
      member.codec,
      if (member.bitrate != null) '${member.bitrate! ~/ 1000} kbps',
      if (member.lossless) 'lossless',
    ];
    return parts.join(', ');
  }

  UpgradeMember get _best =>
      group.members.where((m) => m.best).firstOrNull ?? group.members.first;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final best = _best;
    return Semantics(
      identifier: SemanticsIds.upgradeGroup(best.itemPid),
      child: Card(
        key: ValueKey(SemanticsIds.upgradeGroup(best.itemPid)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                best.artist == null
                    ? best.title
                    : '${best.title} by ${best.artist}',
                style: textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              for (final member in group.members)
                Row(
                  children: [
                    Icon(
                      member.best ? Icons.star : Icons.audio_file_outlined,
                      size: 16,
                      color: member.best
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(_memberLine(member), style: textTheme.bodySmall),
                    if (member.best) ...[
                      const SizedBox(width: 8),
                      Text(
                        'Best',
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              Align(
                alignment: Alignment.centerRight,
                child: Semantics(
                  identifier: SemanticsIds.upgradeResolve(best.itemPid),
                  label: 'Keep the best version',
                  button: true,
                  child: FilledButton.tonal(
                    key: ValueKey(SemanticsIds.upgradeResolve(best.itemPid)),
                    onPressed: onResolve,
                    child: const Text('Resolve'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The paginated failing items behind one health rule.
class HealthIssuesScreen extends ConsumerWidget {
  const HealthIssuesScreen({super.key, required this.rule});

  final String rule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issues = ref.watch(healthIssuesProvider(rule));
    // A failed "load more" keeps the list intact, so surface it on the flag's
    // rising edge; scrolling again retries.
    ref.listen(healthIssuesProvider(rule), (prev, next) {
      final failedNow = next.value?.loadError ?? false;
      final failedBefore = prev?.value?.loadError ?? false;
      if (failedNow && !failedBefore) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Could not load more; scroll to retry'),
            ),
          );
      }
    });
    return Scaffold(
      appBar: AppBar(title: Text(rule)),
      body: switch (issues) {
        AsyncData(:final value) => _list(context, ref, value),
        AsyncError(:final error) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error is WaxDeckApiException
                    ? error.message
                    : 'Could not load issues',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(healthIssuesProvider(rule)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _list(BuildContext context, WidgetRef ref, HealthIssuesState state) {
    if (state.items.isEmpty) {
      return const Center(child: Text('Nothing failing this rule'));
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (metrics.pixels >= metrics.maxScrollExtent - 400) {
          ref.read(healthIssuesProvider(rule).notifier).loadMore();
        }
        return false;
      },
      child: ListView.builder(
        itemCount: state.items.length + (state.loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.items.length) {
            return const Center(child: CircularProgressIndicator());
          }
          final issue = state.items[index];
          return Semantics(
            identifier: SemanticsIds.healthIssue(issue.pid),
            label: issue.title,
            child: ListTile(
              key: ValueKey(SemanticsIds.healthIssue(issue.pid)),
              leading: Icon(mediaFallbackIcon(issue.mediaType)),
              title: Text(
                issue.artist == null
                    ? issue.title
                    : '${issue.title} by ${issue.artist}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Wrap(
                spacing: 4,
                children: [
                  for (final failing in issue.rules)
                    Chip(
                      label: Text(failing),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
