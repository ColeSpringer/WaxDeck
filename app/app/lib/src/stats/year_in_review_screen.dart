import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'share_cards.dart';
import 'stats_charts.dart';
import 'stats_controller.dart';
import 'stats_screen.dart';

/// The listening recap for one calendar year: the caller's own by
/// default, with a toggle onto the server-wide recap. Chevrons step
/// through years.
class YearInReviewScreen extends ConsumerStatefulWidget {
  const YearInReviewScreen({super.key});

  @override
  ConsumerState<YearInReviewScreen> createState() => _YearInReviewScreenState();
}

class _YearInReviewScreenState extends ConsumerState<YearInReviewScreen> {
  late int _year = DateTime.now().year;
  var _server = false;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final sizeClass = WaxSizeClass.of(context);
    final l10n = context.l10n;
    return WaxScaffold(
      title: l10n.statsDoorYearInReview,
      largeTitle: false,
      onBack: () => context.leave(fallback: WaxRoute.stats),
      slivers: <Widget>[
        SliverPadding(
          padding: sizeClass.gutter,
          // The recap reads top to bottom as one story - figures, a
          // chart, four ranked lists - so it takes the reading column
          // rather than stretching its rank rows across a desktop
          // window with the time they name a screen's width away.
          // Column-per-child rather than one column in an adapter: the
          // recap is long, and a single box child would lay the whole
          // of it out on every year step and every chip press.
          sliver: SliverList.list(
            children: <Widget>[
              ReadingColumn(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    WaxIconButton(
                      glyph: WaxIcons.back,
                      label: l10n.statsYearPrev,
                      semanticsId: SemanticsIds.yirPrevYear,
                      onPressed: () => setState(() => _year--),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: WaxSpace.s16,
                      ),
                      child: Text(
                        '$_year',
                        key: const Key('yir-year-label'),
                        style: WaxType.display.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    WaxIconButton(
                      glyph: WaxIcons.forward,
                      label: l10n.statsYearNext,
                      semanticsId: SemanticsIds.yirNextYear,
                      onPressed: () => setState(() => _year++),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: WaxSpace.s8),
              ReadingColumn(
                child: FilterChipRow(
                  padding: EdgeInsets.zero,
                  selected: _server ? 'server' : 'personal',
                  chips: <WaxFilterChip>[
                    WaxFilterChip(
                      name: 'personal',
                      label: l10n.statsYearPersonal,
                      semanticsId: SemanticsIds.yirPersonal,
                    ),
                    WaxFilterChip(
                      name: 'server',
                      label: l10n.statsYearServer,
                      semanticsId: SemanticsIds.yirServer,
                    ),
                  ],
                  onSelect: (name) =>
                      setState(() => _server = name == 'server'),
                ),
              ),
              const SizedBox(height: WaxSpace.s24),
              ReadingColumn(
                child: _server
                    ? _ServerRecap(year: _year)
                    : _PersonalRecap(
                        year: _year,
                        monthLabels: l10n.monthInitials(),
                      ),
              ),
              const SizedBox(height: WaxSpace.s32),
            ],
          ),
        ),
      ],
    );
  }
}

class _PersonalRecap extends ConsumerWidget {
  const _PersonalRecap({required this.year, required this.monthLabels});

  final int year;
  final Map<int, String> monthLabels;

  /// What the year's bar chart says out loud. A canvas announces
  /// nothing, and "your biggest month" is the one fact somebody reads a
  /// recap chart for.
  String _monthSummary(AppLocalizations l10n, List<MonthListening> months) {
    if (months.isEmpty) return l10n.statsYearChartEmpty(year);
    var peak = months.first;
    for (final month in months) {
      if (month.ms > peak.ms) peak = month;
    }
    return l10n.statsYearChartSummary(
      year,
      l10n.formatListenTime(peak.ms),
      monthLabels[peak.month - 1] ?? l10n.statsYearMonthFallback(peak.month),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recap = ref.watch(yearInReviewProvider(year));
    final l10n = context.l10n;
    return switch (recap) {
      AsyncData(:final value) =>
        value.totalMs == 0 && value.sessions == 0
            ? const _NothingPlayed()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 24,
                    runSpacing: 12,
                    children: [
                      StatFigure(
                        keyName: 'yir-total',
                        value: l10n.formatListenTime(value.totalMs),
                        label: l10n.statsListened,
                      ),
                      StatFigure(
                        keyName: 'yir-sessions',
                        value: '${value.sessions}',
                        label: l10n.statsSessions,
                      ),
                      StatFigure(
                        keyName: 'yir-distinct',
                        value: '${value.distinctItems}',
                        label: l10n.statsYearDistinct,
                      ),
                      StatFigure(
                        keyName: 'yir-new',
                        value: '${value.newInLibrary}',
                        label: l10n.statsYearNewInLibrary,
                      ),
                      StatFigure(
                        keyName: 'yir-streak',
                        value: l10n.statsYearStreakDays(
                          value.longestStreakDays,
                        ),
                        label: l10n.statsYearLongestStreak,
                      ),
                      StatFigure(
                        keyName: 'yir-saved',
                        value: l10n.formatListenTime(value.timeSavedMs),
                        label: l10n.statsTimeSaved,
                      ),
                    ],
                  ),
                  SizedBox(height: WaxLayout.of(context).sectionGap),
                  SectionHeader(title: l10n.statsYearMonthByMonth),
                  ListeningBarChart(
                    key: const Key('yir-month-chart'),
                    values: [for (final m in value.byMonth) m.ms],
                    labels: monthLabels,
                    summary: _monthSummary(l10n, value.byMonth),
                  ),
                  _TopFive(
                    title: l10n.statsYearTopArtists,
                    kind: 'artists',
                    entries: value.topArtists,
                  ),
                  _TopFive(
                    title: l10n.statsYearTopTracks,
                    kind: 'tracks',
                    entries: value.topTracks,
                  ),
                  _TopFive(
                    title: l10n.statsYearTopGenres,
                    kind: 'genres',
                    entries: value.topGenres,
                  ),
                  _TopFive(
                    title: l10n.statsYearTopShows,
                    kind: 'shows',
                    entries: value.topShows,
                  ),
                  _ShareCardsDoor(data: ShareCardData.personal(l10n, value)),
                ],
              ),
      AsyncError(:final error) => _RecapError(
        error: error,
        onRetry: () => ref.invalidate(yearInReviewProvider(year)),
      ),
      _ => const Center(
        child: Padding(
          padding: EdgeInsets.all(WaxSpace.s24),
          child: CircularProgressIndicator(),
        ),
      ),
    };
  }
}

class _ServerRecap extends ConsumerWidget {
  const _ServerRecap({required this.year});

  final int year;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recap = ref.watch(serverYearInReviewProvider(year));
    final l10n = context.l10n;
    return switch (recap) {
      AsyncData(:final value) =>
        value.totalMs == 0 && value.sessions == 0
            ? const _NothingPlayed()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 24,
                    runSpacing: 12,
                    children: [
                      StatFigure(
                        keyName: 'yir-participants',
                        value: '${value.participants}',
                        label: l10n.statsYearParticipants,
                      ),
                      StatFigure(
                        keyName: 'yir-server-total',
                        value: l10n.formatListenTime(value.totalMs),
                        label: l10n.statsYearListenedTogether,
                      ),
                      StatFigure(
                        keyName: 'yir-server-sessions',
                        value: '${value.sessions}',
                        label: l10n.statsSessions,
                      ),
                    ],
                  ),
                  _TopFive(
                    title: l10n.statsYearTopArtists,
                    kind: 'artists',
                    entries: value.topArtists,
                  ),
                  _TopFive(
                    title: l10n.statsYearTopTracks,
                    kind: 'tracks',
                    entries: value.topTracks,
                  ),
                  _TopFive(
                    title: l10n.statsYearTopGenres,
                    kind: 'genres',
                    entries: value.topGenres,
                  ),
                  _ShareCardsDoor(data: ShareCardData.server(l10n, value)),
                ],
              ),
      AsyncError(:final error) => _RecapError(
        error: error,
        onRetry: () => ref.invalidate(serverYearInReviewProvider(year)),
      ),
      _ => const Center(
        child: Padding(
          padding: EdgeInsets.all(WaxSpace.s24),
          child: CircularProgressIndicator(),
        ),
      ),
    };
  }
}

/// The first five entries of one recap top list; hidden entirely when
/// the list is empty.
class _TopFive extends StatelessWidget {
  const _TopFive({
    required this.title,
    required this.kind,
    required this.entries,
  });

  final String title;
  final String kind;
  final List<TopEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final top = entries.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: WaxLayout.of(context).sectionGap),
        SectionHeader(title: title),
        for (var i = 0; i < top.length; i++)
          TopEntryRow(index: i, entry: top[i], kind: kind),
      ],
    );
  }
}

/// The way onto a shareable card. At the end of the scroll, not in the
/// bar: it is what the story has been building to.
class _ShareCardsDoor extends StatelessWidget {
  const _ShareCardsDoor({required this.data});

  final ShareCardData data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: WaxSpace.s32),
      child: WaxButton(
        label: context.l10n.statsYearMakeCard,
        kind: WaxButtonKind.tonal,
        icon: WaxIcons.share,
        semanticsId: SemanticsIds.shareCardOpen,
        onPressed: () => showShareCardSheet(context, data),
      ),
    );
  }
}

class _NothingPlayed extends StatelessWidget {
  const _NothingPlayed();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WaxSpace.s48),
      child: Center(
        child: Text(
          context.l10n.statsYearNothingPlayed,
          key: const Key('yir-nothing-played'),
        ),
      ),
    );
  }
}

class _RecapError extends StatelessWidget {
  const _RecapError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(WaxSpace.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Titled, because `explain` answers a generic sentence for
          // anything that is not an API exception, and a panel among
          // panels has to say which one could not be drawn.
          Text(l10n.statsRecapLoadError, textAlign: TextAlign.center),
          const SizedBox(height: WaxSpace.s4),
          Text(context.explain(error), textAlign: TextAlign.center),
          const SizedBox(height: WaxSpace.s12),
          OutlinedButton(onPressed: onRetry, child: Text(l10n.commonRetry)),
        ],
      ),
    );
  }
}
