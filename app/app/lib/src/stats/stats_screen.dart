import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'listen_log_screen.dart';
import 'stats_charts.dart';
import 'stats_controller.dart';
import 'year_in_review_screen.dart';

/// The caller's listening statistics: headline totals with a range
/// selector, the bucketed listening chart, the calendar heatmap with
/// streaks, ranked top lists, and doors into the listen log and the
/// year in review.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  static String _rangeLabel(String range) =>
      range == 'all' ? 'All time' : range;

  static String _bucketLabel(String bucket) => switch (bucket) {
    'day' => 'Day',
    'week' => 'Week',
    'month' => 'Month',
    _ => bucket,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final range = ref.watch(statsRangeProvider);
    final bucket = ref.watch(statsBucketProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Listening stats')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              segments: [
                for (final r in statsRanges)
                  ButtonSegment(
                    value: r,
                    label: Semantics(
                      identifier: 'stats-range-$r',
                      child: Text(_rangeLabel(r), key: Key('stats-range-$r')),
                    ),
                  ),
              ],
              selected: {range},
              onSelectionChanged: (selection) =>
                  ref.read(statsRangeProvider.notifier).select(selection.first),
            ),
          ),
          const SizedBox(height: 16),
          const _ListeningSection(),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SegmentedButton<String>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  for (final b in statsBuckets)
                    ButtonSegment(
                      value: b,
                      label: Semantics(
                        identifier: 'stats-bucket-$b',
                        child: Text(
                          _bucketLabel(b),
                          key: Key('stats-bucket-$b'),
                        ),
                      ),
                    ),
                ],
                selected: {bucket},
                onSelectionChanged: (selection) => ref
                    .read(statsBucketProvider.notifier)
                    .select(selection.first),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('This year', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          const _HeatmapSection(),
          const SizedBox(height: 24),
          Text('Top', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          const _TopListsSection(),
          const SizedBox(height: 16),
          Semantics(
            identifier: 'open-listen-log',
            label: 'Listen log',
            button: true,
            child: ListTile(
              key: const Key('open-listen-log'),
              leading: const Icon(Icons.history),
              title: const Text('Listen log'),
              subtitle: const Text('Every recorded listen session'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ListenLogScreen(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Semantics(
            identifier: 'open-year-in-review',
            label: 'Year in review',
            button: true,
            child: Card(
              key: const Key('open-year-in-review'),
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
                leading: Icon(
                  Icons.celebration_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text('Year in review'),
                subtitle: const Text('Your listening year, wrapped up'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const YearInReviewScreen(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Headline totals plus the bucketed listening chart for the selected
/// range.
class _ListeningSection extends ConsumerWidget {
  const _ListeningSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(listeningStatsProvider);
    return switch (stats) {
      AsyncData(:final value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              StatTile(
                keyName: 'stats-total',
                value: formatListenTime(value.totalMs),
                label: 'listened',
              ),
              StatTile(
                keyName: 'stats-sessions',
                value: '${value.sessions}',
                label: 'sessions',
              ),
              StatTile(
                keyName: 'stats-saved',
                value: formatListenTime(value.timeSavedMs),
                label: 'saved by silence trimming',
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (value.buckets.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('Nothing played in this range')),
            )
          else
            ListeningBarChart(
              key: const Key('stats-chart'),
              values: [for (final b in value.buckets) b.ms],
              labels: _chartLabels(value.buckets),
            ),
        ],
      ),
      AsyncError(:final error) => _StatsError(
        error: error,
        onRetry: () => ref.invalidate(listeningStatsProvider),
      ),
      _ => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      ),
    };
  }

  static String _stamp(DateTime day) {
    final month = day.month.toString().padLeft(2, '0');
    final date = day.day.toString().padLeft(2, '0');
    return '$month-$date';
  }

  /// First and last bucket dates only; a label on every bar would just
  /// collide.
  static Map<int, String> _chartLabels(List<ListeningBucket> buckets) {
    if (buckets.isEmpty) return const {};
    if (buckets.length == 1) return {0: _stamp(buckets.first.start)};
    return {
      0: _stamp(buckets.first.start),
      buckets.length - 1: _stamp(buckets.last.start),
    };
  }
}

/// One headline number with its caption underneath.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.keyName,
    required this.value,
    required this.label,
  });

  final String keyName;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      key: Key(keyName),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: textTheme.headlineSmall),
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _HeatmapSection extends ConsumerWidget {
  const _HeatmapSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heatmap = ref.watch(listeningHeatmapProvider);
    final textTheme = Theme.of(context).textTheme;
    return switch (heatmap) {
      AsyncData(:final value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          YearHeatmap(key: const Key('stats-heatmap'), heatmap: value),
          const SizedBox(height: 8),
          Text(
            'Current streak: ${value.currentStreakDays} days | '
            'Longest: ${value.longestStreakDays} days',
            key: const Key('stats-streaks'),
            style: textTheme.bodySmall,
          ),
        ],
      ),
      AsyncError(:final error) => _StatsError(
        error: error,
        onRetry: () => ref.invalidate(listeningHeatmapProvider),
      ),
      _ => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      ),
    };
  }
}

class _TopListsSection extends ConsumerWidget {
  const _TopListsSection();

  static String _kindLabel(String kind) => switch (kind) {
    'artists' => 'Artists',
    'albums' => 'Albums',
    'genres' => 'Genres',
    'shows' => 'Shows',
    _ => kind,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = ref.watch(topKindProvider);
    final top = ref.watch(topListProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              for (final k in topListKinds)
                ButtonSegment(
                  value: k,
                  label: Semantics(
                    identifier: 'top-kind-$k',
                    child: Text(_kindLabel(k), key: Key('top-kind-$k')),
                  ),
                ),
            ],
            selected: {kind},
            onSelectionChanged: (selection) =>
                ref.read(topKindProvider.notifier).select(selection.first),
          ),
        ),
        const SizedBox(height: 8),
        switch (top) {
          AsyncData(:final value) =>
            value.entries.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('Nothing here for this range')),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < value.entries.length; i++)
                        TopEntryRow(
                          index: i,
                          entry: value.entries[i],
                          kind: value.kind,
                        ),
                    ],
                  ),
          AsyncError(:final error) => _StatsError(
            error: error,
            onRetry: () => ref.invalidate(topListProvider),
          ),
          _ => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
        },
      ],
    );
  }
}

/// One ranked top-list row: rank, artwork, name, plays, and time.
class TopEntryRow extends StatelessWidget {
  const TopEntryRow({
    super.key,
    required this.index,
    required this.entry,
    required this.kind,
  });

  final int index;
  final TopEntry entry;
  final String kind;

  static IconData _fallbackIcon(String kind) => switch (kind) {
    'artists' => Icons.person,
    'albums' => Icons.album,
    'genres' => Icons.label_outline,
    'shows' => Icons.podcasts,
    _ => Icons.music_note,
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final artUrl = entry.artUrl;
    final placeholder = ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(_fallbackIcon(kind), color: colorScheme.onSurfaceVariant),
    );
    return ListTile(
      key: Key('top-entry-$index'),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            child: Text('${index + 1}', style: textTheme.titleSmall),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 40,
              height: 40,
              child: artUrl == null
                  ? placeholder
                  : Image.network(
                      artUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => placeholder,
                    ),
            ),
          ),
        ],
      ),
      title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${entry.plays} plays'),
      trailing: Text(formatListenTime(entry.ms), style: textTheme.labelMedium),
    );
  }
}

class _StatsError extends StatelessWidget {
  const _StatsError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = error is WaxDeckApiException
        ? (error as WaxDeckApiException).message
        : 'Could not load listening stats';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
