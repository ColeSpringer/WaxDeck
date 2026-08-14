import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../l10n/l10n.dart';
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

  /// The client's word for a range, with the wire value as the last
  /// resort: a range a newer server offers draws as itself rather than
  /// as nothing.
  static String rangeLabel(AppLocalizations l10n, String range) =>
      switch (range) {
        'all' => l10n.statsRangeAll,
        '7d' => l10n.statsRange7d,
        '30d' => l10n.statsRange30d,
        '90d' => l10n.statsRange90d,
        '365d' => l10n.statsRange365d,
        _ => range,
      };

  static String bucketLabel(AppLocalizations l10n, String bucket) =>
      switch (bucket) {
        'day' => l10n.statsBucketDay,
        'week' => l10n.statsBucketWeek,
        'month' => l10n.statsBucketMonth,
        _ => bucket,
      };

  /// The same grouping named inside a sentence. Its own keys rather
  /// than [bucketLabel] lowercased, because `toLowerCase` is not a
  /// translation - German keeps its capitals, Turkish loses its I.
  static String bucketUnit(AppLocalizations l10n, String bucket) =>
      switch (bucket) {
        'day' => l10n.statsBucketDayInline,
        'week' => l10n.statsBucketWeekInline,
        'month' => l10n.statsBucketMonthInline,
        _ => bucket,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final l10n = context.l10n;
    final range = ref.watch(statsRangeProvider);

    return WaxScaffold(
      title: l10n.statsTitle,
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: FilterChipRow(
            padding: sizeClass.gutter,
            selected: range,
            chips: <WaxFilterChip>[
              for (final value in statsRanges)
                WaxFilterChip(
                  name: value,
                  label: rangeLabel(l10n, value),
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
    final l10n = context.l10n;
    return switch (stats) {
      AsyncData(:final value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: WaxSpace.s32,
            runSpacing: WaxSpace.s12,
            children: <Widget>[
              StatFigure(
                keyName: 'stats-total',
                value: l10n.formatListenTime(value.totalMs),
                label: l10n.statsListened,
              ),
              StatFigure(
                keyName: 'stats-sessions',
                value: '${value.sessions}',
                label: l10n.statsSessions,
              ),
              // The general claim, now that it is true: the client
              // counts what playing faster saved as well as what
              // trimming skipped, so the honest word is the plain one.
              StatFigure(
                keyName: 'stats-saved',
                value: l10n.formatListenTime(value.timeSavedMs),
                label: l10n.statsTimeSaved,
              ),
            ],
          ),
          const SizedBox(height: WaxSpace.s16),
          if (value.buckets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: WaxSpace.s24),
              child: EmptyState(
                title: l10n.statsEmptyTitle,
                message: l10n.statsEmptyMessage,
                glyph: WaxIcons.stats,
              ),
            )
          else ...<Widget>[
            ListeningBarChart(
              key: const Key('stats-chart'),
              values: <int>[for (final b in value.buckets) b.ms],
              labels: _chartLabels(l10n, value.buckets),
              summary: _chartSummary(l10n, value.buckets, bucket),
            ),
            const SizedBox(height: WaxSpace.s8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: WaxChoice<String>(
                value: bucket,
                options: statsBuckets,
                labelFor: (value) => StatsScreen.bucketLabel(l10n, value),
                label: l10n.statsGroupBy,
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

  /// First and last bucket dates only; a label on every bar would just
  /// collide.
  static Map<int, String> _chartLabels(
    AppLocalizations l10n,
    List<ListeningBucket> buckets,
  ) {
    if (buckets.isEmpty) return const <int, String>{};
    if (buckets.length == 1) {
      return <int, String>{
        0: l10n.formatMonthDayNumericOnDay(buckets.first.start),
      };
    }
    return <int, String>{
      0: l10n.formatMonthDayNumericOnDay(buckets.first.start),
      buckets.length - 1: l10n.formatMonthDayNumericOnDay(buckets.last.start),
    };
  }

  /// What the chart says out loud: the span it covers, and where the
  /// most listening landed. Not a reading of every bar, which for a
  /// year of days would be 365 numbers nobody can hold.
  static String _chartSummary(
    AppLocalizations l10n,
    List<ListeningBucket> buckets,
    String bucket,
  ) {
    if (buckets.isEmpty) return l10n.statsChartEmptySummary;
    var peak = buckets.first;
    for (final b in buckets) {
      if (b.ms > peak.ms) peak = b;
    }
    return l10n.statsChartSummary(
      StatsScreen.bucketUnit(l10n, bucket),
      buckets.length,
      l10n.formatMonthDayNumericOnDay(buckets.first.start),
      l10n.formatMonthDayNumericOnDay(buckets.last.start),
      l10n.formatListenTime(peak.ms),
      l10n.formatMonthDayNumericOnDay(peak.start),
    );
  }
}

/// One headline number with its caption underneath.
///
/// Not the design system's `StatTile`, which is a bordered console card
/// with a glyph and somewhere to go; this is the bare figure a row of
/// them is built from, and the listener's stats want the row.
class StatFigure extends StatelessWidget {
  const StatFigure({
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
    final l10n = context.l10n;
    return switch (heatmap) {
      AsyncData(:final value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            title: l10n.statsHeatmapTitle,
            overline: l10n.statsHeatmapOverline,
          ),
          const SizedBox(height: WaxSpace.s12),
          YearHeatmap(
            key: const Key('stats-heatmap'),
            heatmap: value,
            summary: _summary(l10n, value),
          ),
          const SizedBox(height: WaxSpace.s8),
          Text(
            l10n.statsStreaks(value.currentStreakDays, value.longestStreakDays),
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

  static String _summary(AppLocalizations l10n, ListeningHeatmap heatmap) {
    final days = heatmap.days.where((day) => day.ms > 0).length;
    return l10n.statsHeatmapSummary(
      heatmap.year,
      days,
      heatmap.currentStreakDays,
      heatmap.longestStreakDays,
    );
  }
}

class _TopListsSection extends ConsumerWidget {
  const _TopListsSection();

  static String kindLabel(AppLocalizations l10n, String kind) => switch (kind) {
    'artists' => l10n.statsKindArtists,
    'albums' => l10n.statsKindAlbums,
    'genres' => l10n.statsKindGenres,
    'shows' => l10n.statsKindShows,
    _ => kind,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = ref.watch(topKindProvider);
    final top = ref.watch(topListProvider);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          title: l10n.statsTopTitle,
          overline: l10n.statsTopOverline,
        ),
        const SizedBox(height: WaxSpace.s8),
        FilterChipRow(
          padding: EdgeInsets.zero,
          selected: kind,
          chips: <WaxFilterChip>[
            for (final value in topListKinds)
              WaxFilterChip(
                name: value,
                label: kindLabel(l10n, value),
                semanticsId: SemanticsIds.top(value),
              ),
          ],
          onSelect: (value) => ref.read(topKindProvider.notifier).select(value),
        ),
        const SizedBox(height: WaxSpace.s8),
        switch (top) {
          AsyncData(:final value) when value.entries.isEmpty => EmptyState(
            title: l10n.statsTopEmptyTitle,
            message: l10n.statsTopEmptyMessage(kind),
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
      subtitle: context.l10n.statsPlays(entry.plays),
      artwork: waxArtwork(ref.watch(artworkStoreProvider), entry.artUrl),
      domain: _domain(kind),
      // An artist reads as a disc, the way every other artist row in the
      // app does; an album and a show are square by nature.
      shape: kind == 'artists' || kind == 'genres'
          ? ArtworkShape.circle
          : ArtworkShape.square,
      trailingText: context.l10n.formatListenTime(entry.ms),
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
        title: context.l10n.statsDoorListenLog,
        subtitle: context.l10n.statsDoorListenLogSubtitle,
        semanticsId: SemanticsIds.openListenLog,
        onTap: () => context.go(WaxRoute.listenLog),
      ),
      WaxOptionRow(
        glyph: WaxIcons.stats,
        title: context.l10n.statsDoorYearInReview,
        subtitle: context.l10n.statsDoorYearInReviewSubtitle,
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
    title: context.l10n.statsLoadError,
    message: context.explain(error),
    onRetry: onRetry,
  );
}
