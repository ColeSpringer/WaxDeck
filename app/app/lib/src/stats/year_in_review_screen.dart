import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart'
    show
        FilterChipRow,
        WaxColors,
        WaxFilterChip,
        WaxIconButton,
        WaxIcons,
        WaxScaffold,
        WaxSizeClass,
        WaxSpace,
        WaxType;

import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
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

  static const _monthLabels = {
    0: 'J',
    1: 'F',
    2: 'M',
    3: 'A',
    4: 'M',
    5: 'J',
    6: 'J',
    7: 'A',
    8: 'S',
    9: 'O',
    10: 'N',
    11: 'D',
  };

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final sizeClass = WaxSizeClass.of(context);
    return WaxScaffold(
      title: 'Year in review',
      largeTitle: false,
      onBack: () => context.leave(fallback: WaxRoute.stats),
      slivers: <Widget>[
        SliverPadding(
          padding: sizeClass.gutter,
          sliver: SliverList.list(
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  WaxIconButton(
                    glyph: WaxIcons.back,
                    label: 'Previous year',
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
                    label: 'Next year',
                    semanticsId: SemanticsIds.yirNextYear,
                    onPressed: () => setState(() => _year++),
                  ),
                ],
              ),
              const SizedBox(height: WaxSpace.s8),
              FilterChipRow(
                padding: EdgeInsets.zero,
                selected: _server ? 'server' : 'personal',
                chips: const <WaxFilterChip>[
                  WaxFilterChip(
                    name: 'personal',
                    label: 'My year',
                    semanticsId: SemanticsIds.yirPersonal,
                  ),
                  WaxFilterChip(
                    name: 'server',
                    label: 'Whole server',
                    semanticsId: SemanticsIds.yirServer,
                  ),
                ],
                onSelect: (name) => setState(() => _server = name == 'server'),
              ),
              const SizedBox(height: WaxSpace.s24),
              if (_server)
                _ServerRecap(year: _year)
              else
                _PersonalRecap(year: _year, monthLabels: _monthLabels),
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
  String _monthSummary(List<MonthListening> months) {
    if (months.isEmpty) return 'No listening recorded in $year.';
    var peak = months.first;
    for (final month in months) {
      if (month.ms > peak.ms) peak = month;
    }
    return 'Listening month by month through $year. The most was '
        '${formatListenTime(peak.ms)} in '
        '${monthLabels[peak.month - 1] ?? 'month ${peak.month}'}.';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recap = ref.watch(yearInReviewProvider(year));
    final textTheme = Theme.of(context).textTheme;
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
                      StatTile(
                        keyName: 'yir-total',
                        value: formatListenTime(value.totalMs),
                        label: 'listened',
                      ),
                      StatTile(
                        keyName: 'yir-sessions',
                        value: '${value.sessions}',
                        label: 'sessions',
                      ),
                      StatTile(
                        keyName: 'yir-distinct',
                        value: '${value.distinctItems}',
                        label: 'different things played',
                      ),
                      StatTile(
                        keyName: 'yir-new',
                        value: '${value.newInLibrary}',
                        label: 'new in the library',
                      ),
                      StatTile(
                        keyName: 'yir-streak',
                        value: '${value.longestStreakDays} days',
                        label: 'longest streak',
                      ),
                      StatTile(
                        keyName: 'yir-saved',
                        value: formatListenTime(value.timeSavedMs),
                        label: 'saved by silence trimming',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text('Month by month', style: textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ListeningBarChart(
                    key: const Key('yir-month-chart'),
                    values: [for (final m in value.byMonth) m.ms],
                    labels: monthLabels,
                    summary: _monthSummary(value.byMonth),
                  ),
                  const SizedBox(height: 16),
                  _TopFive(
                    title: 'Top artists',
                    kind: 'artists',
                    entries: value.topArtists,
                  ),
                  _TopFive(
                    title: 'Top tracks',
                    kind: 'tracks',
                    entries: value.topTracks,
                  ),
                  _TopFive(
                    title: 'Top genres',
                    kind: 'genres',
                    entries: value.topGenres,
                  ),
                  _TopFive(
                    title: 'Top shows',
                    kind: 'shows',
                    entries: value.topShows,
                  ),
                ],
              ),
      AsyncError(:final error) => _RecapError(
        error: error,
        onRetry: () => ref.invalidate(yearInReviewProvider(year)),
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

class _ServerRecap extends ConsumerWidget {
  const _ServerRecap({required this.year});

  final int year;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recap = ref.watch(serverYearInReviewProvider(year));
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
                      StatTile(
                        keyName: 'yir-participants',
                        value: '${value.participants}',
                        label: 'listeners counted in',
                      ),
                      StatTile(
                        keyName: 'yir-server-total',
                        value: formatListenTime(value.totalMs),
                        label: 'listened together',
                      ),
                      StatTile(
                        keyName: 'yir-server-sessions',
                        value: '${value.sessions}',
                        label: 'sessions',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _TopFive(
                    title: 'Top artists',
                    kind: 'artists',
                    entries: value.topArtists,
                  ),
                  _TopFive(
                    title: 'Top tracks',
                    kind: 'tracks',
                    entries: value.topTracks,
                  ),
                  _TopFive(
                    title: 'Top genres',
                    kind: 'genres',
                    entries: value.topGenres,
                  ),
                ],
              ),
      AsyncError(:final error) => _RecapError(
        error: error,
        onRetry: () => ref.invalidate(serverYearInReviewProvider(year)),
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
    final textTheme = Theme.of(context).textTheme;
    final top = entries.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(title, style: textTheme.titleMedium),
        for (var i = 0; i < top.length; i++)
          TopEntryRow(index: i, entry: top[i], kind: kind),
      ],
    );
  }
}

class _NothingPlayed extends StatelessWidget {
  const _NothingPlayed();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Text('Nothing played this year', key: Key('yir-nothing-played')),
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
    final message = error is WaxDeckApiException
        ? (error as WaxDeckApiException).message
        : 'Could not load the recap';
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
