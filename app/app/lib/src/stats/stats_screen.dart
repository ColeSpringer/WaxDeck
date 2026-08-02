import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../media_view.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'stats_charts.dart';
import 'stats_controller.dart';

/// The caller's listening statistics: headline totals with a range
/// selector, the bucketed listening chart, the calendar heatmap with
/// streaks, ranked top lists, and doors into the listen log and the
/// year in review.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  static String rangeLabel(String range) => switch (range) {
    'all' => 'All time',
    '7d' => '7 days',
    '30d' => '30 days',
    '90d' => '90 days',
    '365d' => 'A year',
    _ => range,
  };

  static String bucketLabel(String bucket) => switch (bucket) {
    'day' => 'Day',
    'week' => 'Week',
    'month' => 'Month',
    _ => bucket,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final range = ref.watch(statsRangeProvider);

    return WaxScaffold(
      title: 'Listening stats',
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: FilterChipRow(
            padding: sizeClass.gutter,
            selected: range,
            chips: <WaxFilterChip>[
              for (final value in statsRanges)
                WaxFilterChip(
                  name: value,
                  label: rangeLabel(value),
                  semanticsId: SemanticsIds.statsRange(value),
                ),
            ],
            onSelect: (value) =>
                ref.read(statsRangeProvider.notifier).select(value),
          ),
        ),
        SliverPadding(
          padding: sizeClass.gutter,
          sliver: const SliverMainAxisGroup(
            slivers: <Widget>[
              SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s16)),
              SliverToBoxAdapter(child: _ListeningSection()),
              SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s32)),
              SliverToBoxAdapter(child: _HeatmapSection()),
              SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s32)),
              SliverToBoxAdapter(child: _TopListsSection()),
              SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s24)),
              SliverToBoxAdapter(child: _Doors()),
              SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s32)),
            ],
          ),
        ),
      ],
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
    final bucket = ref.watch(statsBucketProvider);
    return switch (stats) {
      AsyncData(:final value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: WaxSpace.s32,
            runSpacing: WaxSpace.s12,
            children: <Widget>[
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
              // The general claim, now that it is true: the client
              // counts what playing faster saved as well as what
              // trimming skipped, so the honest word is the plain one.
              StatTile(
                keyName: 'stats-saved',
                value: formatListenTime(value.timeSavedMs),
                label: 'time saved',
              ),
            ],
          ),
          const SizedBox(height: WaxSpace.s16),
          if (value.buckets.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: WaxSpace.s24),
              child: EmptyState(
                title: 'Nothing played in this range',
                message: 'Pick a longer range, or go and play something.',
                glyph: WaxIcons.stats,
              ),
            )
          else ...<Widget>[
            ListeningBarChart(
              key: const Key('stats-chart'),
              values: <int>[for (final b in value.buckets) b.ms],
              labels: _chartLabels(value.buckets),
              summary: _chartSummary(value.buckets, bucket),
            ),
            const SizedBox(height: WaxSpace.s8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: WaxChoice<String>(
                value: bucket,
                options: statsBuckets,
                labelFor: StatsScreen.bucketLabel,
                label: 'Group by',
                semanticsId: SemanticsIds.statsBucket,
                onChanged: (value) =>
                    ref.read(statsBucketProvider.notifier).select(value),
              ),
            ),
          ],
        ],
      ),
      AsyncError(:final error) => _StatsError(
        error: error,
        onRetry: () => ref.invalidate(listeningStatsProvider),
      ),
      _ => const SkeletonShapes(shape: SkeletonShape.detail),
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
    if (buckets.isEmpty) return const <int, String>{};
    if (buckets.length == 1) {
      return <int, String>{0: _stamp(buckets.first.start)};
    }
    return <int, String>{
      0: _stamp(buckets.first.start),
      buckets.length - 1: _stamp(buckets.last.start),
    };
  }

  /// What the chart says out loud: the span it covers, and where the
  /// most listening landed. Not a reading of every bar, which for a
  /// year of days would be 365 numbers nobody can hold.
  static String _chartSummary(List<ListeningBucket> buckets, String bucket) {
    if (buckets.isEmpty) return 'No listening in this range.';
    var peak = buckets.first;
    for (final b in buckets) {
      if (b.ms > peak.ms) peak = b;
    }
    final unit = StatsScreen.bucketLabel(bucket).toLowerCase();
    return 'Listening by $unit, ${buckets.length} bars from '
        '${_stamp(buckets.first.start)} to ${_stamp(buckets.last.start)}. '
        'The most was ${formatListenTime(peak.ms)} '
        'on ${_stamp(peak.start)}.';
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
    final colors = WaxColors.of(context);
    // Merged, so the tile announces "2h 6m listened" as one thing. Left
    // unmerged, three tiles side by side merge by geometry instead -
    // every value on one line and every caption on the next, which reads
    // as "2h 6m 10 1m listened sessions time saved" and is three
    // numbers nobody can attach to anything.
    return MergeSemantics(
      child: Column(
        key: Key(keyName),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Mono, which is what 6.12 asks for and what keeps a row of
          // figures from shifting sideways as they tick over.
          Text(
            value,
            style: WaxType.titleEntity.copyWith(
              color: colors.textPrimary,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          Text(
            label,
            style: WaxType.caption.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _HeatmapSection extends ConsumerWidget {
  const _HeatmapSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heatmap = ref.watch(listeningHeatmapProvider);
    final colors = WaxColors.of(context);
    return switch (heatmap) {
      AsyncData(:final value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeader(title: 'This year', overline: 'Every day'),
          const SizedBox(height: WaxSpace.s12),
          YearHeatmap(
            key: const Key('stats-heatmap'),
            heatmap: value,
            summary: _summary(value),
          ),
          const SizedBox(height: WaxSpace.s8),
          Text(
            'Current streak: ${value.currentStreakDays} days · '
            'Longest: ${value.longestStreakDays} days',
            key: const Key('stats-streaks'),
            style: WaxType.caption.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
      AsyncError(:final error) => _StatsError(
        error: error,
        onRetry: () => ref.invalidate(listeningHeatmapProvider),
      ),
      _ => const SkeletonShapes(shape: SkeletonShape.detail),
    };
  }

  static String _summary(ListeningHeatmap heatmap) {
    final days = heatmap.days.where((day) => day.ms > 0).length;
    return 'A calendar of ${heatmap.year}: listening on $days days. '
        'Current streak ${heatmap.currentStreakDays} days, '
        'longest ${heatmap.longestStreakDays}.';
  }
}

class _TopListsSection extends ConsumerWidget {
  const _TopListsSection();

  static String kindLabel(String kind) => switch (kind) {
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
      children: <Widget>[
        const SectionHeader(title: 'Top', overline: 'In this range'),
        const SizedBox(height: WaxSpace.s8),
        FilterChipRow(
          padding: EdgeInsets.zero,
          selected: kind,
          chips: <WaxFilterChip>[
            for (final value in topListKinds)
              WaxFilterChip(
                name: value,
                label: kindLabel(value),
                semanticsId: SemanticsIds.top(value),
              ),
          ],
          onSelect: (value) => ref.read(topKindProvider.notifier).select(value),
        ),
        const SizedBox(height: WaxSpace.s8),
        switch (top) {
          AsyncData(:final value) when value.entries.isEmpty => EmptyState(
            title: 'Nothing here for this range',
            message:
                'A longer range, or a ${kindLabel(kind).toLowerCase()} '
                'you have actually played.',
            glyph: WaxIcons.stats,
          ),
          AsyncData(:final value) => Column(
            children: <Widget>[
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
          _ => const SkeletonShapes(shape: SkeletonShape.list),
        },
      ],
    );
  }
}

/// One ranked top-list row: rank, artwork, name, plays, and time.
class TopEntryRow extends ConsumerWidget {
  const TopEntryRow({
    super.key,
    required this.index,
    required this.entry,
    required this.kind,
  });

  final int index;
  final TopEntry entry;
  final String kind;

  static WaxDomain _domain(String kind) =>
      kind == 'shows' ? WaxDomain.podcasts : WaxDomain.music;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MediaListRow(
    data: MediaTileData(
      title: entry.name,
      subtitle: entry.plays == 1 ? '1 play' : '${entry.plays} plays',
      artwork: waxArtwork(ref.watch(artworkStoreProvider), entry.artUrl),
      domain: _domain(kind),
      // An artist reads as a disc, the way every other artist row in the
      // app does; an album and a show are square by nature.
      shape: kind == 'artists' || kind == 'genres'
          ? ArtworkShape.circle
          : ArtworkShape.square,
      trailingText: formatListenTime(entry.ms),
      semanticsId: SemanticsIds.topEntry(index),
    ),
    // The rank, in the slot the row already has for one, so it lines up
    // in mono without this reimplementing the row's leading column.
    leadingIndex: index + 1,
  );
}

/// The two surfaces stats is a door to.
class _Doors extends StatelessWidget {
  const _Doors();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      WaxOptionRow(
        glyph: WaxIcons.recent,
        title: 'Listen log',
        subtitle: 'Every recorded listen session',
        semanticsId: SemanticsIds.openListenLog,
        onTap: () => context.go(WaxRoute.listenLog),
      ),
      WaxOptionRow(
        glyph: WaxIcons.stats,
        title: 'Year in review',
        subtitle: 'Your listening year, wrapped up',
        semanticsId: SemanticsIds.openYearInReview,
        onTap: () => context.go(WaxRoute.yearInReview),
      ),
    ],
  );
}

class _StatsError extends StatelessWidget {
  const _StatsError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ErrorState(
    title: 'Could not load your listening stats',
    message: error is WaxDeckApiException
        ? (error as WaxDeckApiException).message
        : 'The server did not answer.',
    onRetry: onRetry,
  );
}
