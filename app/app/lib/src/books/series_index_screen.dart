import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../settings/client_prefs.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'books_screen.dart';
import 'series_merge.dart';

/// Every series the shelf's books belong to.
///
/// Cards without artwork, drawn as monograms: the listing carries counts
/// and library pids but no member pids, so a cover would cost one
/// members read per row on a page of up to five hundred. An artless
/// artist card is the same answer to the same question.
class BookSeriesIndexScreen extends ConsumerWidget {
  const BookSeriesIndexScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final series = ref.watch(bookSeriesProvider);
    final l10n = context.l10n;
    return WaxScaffold(
      title: l10n.bookSeriesTitle,
      largeTitle: false,
      semanticsId: SemanticsIds.bookSeriesIndex,
      onBack: () => context.leave(fallback: WaxRoute.books),
      slivers: <Widget>[
        switch (series) {
          AsyncData(:final value) when value.isEmpty => SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: l10n.bookSeriesEmpty,
              message: l10n.bookSeriesEmptyMessage,
              glyph: WaxIcons.audiobooks,
            ),
          ),
          AsyncData(:final value) => _SeriesGrid(series: value),
          AsyncError(:final error) => SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(
              title: l10n.bookSeriesIndexLoadError,
              message: context.explain(error),
              onRetry: () => ref.invalidate(bookSeriesProvider),
            ),
          ),
          _ => const SliverToBoxAdapter(
            child: SkeletonShapes(shape: SkeletonShape.grid),
          ),
        },
        const SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s32)),
      ],
    );
  }
}

class _SeriesGrid extends ConsumerWidget {
  const _SeriesGrid({required this.series});

  final List<BookSeries> series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final l10n = context.l10n;
    return SliverPadding(
      padding: sizeClass.gutter,
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final grid = MediaCard.gridFor(
            constraints.crossAxisExtent,
            extent: kBookTileExtent * ref.watch(gridScaleProvider),
          );
          return SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: grid.columns,
              mainAxisSpacing: WaxShellMetrics.gridGap,
              crossAxisSpacing: WaxShellMetrics.gridGap,
              mainAxisExtent: MediaCard.heightFor(context, width: grid.width),
            ),
            itemCount: series.length,
            itemBuilder: (context, index) {
              final row = series[index];
              return MediaCard(
                data: MediaTileData(
                  title: row.name,
                  // Zero is what a restricted account reads, and a "0
                  // books" caption on a series it can open is a lie the
                  // count is not allowed to tell.
                  subtitle: row.bookCount > 0
                      ? l10n.bookSeriesBookCount(row.bookCount)
                      : null,
                  domain: WaxDomain.audiobooks,
                  semanticsId: SemanticsIds.bookSeriesCard(row.pid),
                ),
                width: grid.width,
                // `go`: a series is a location a stranger can open, and
                // its declared parent is this index.
                onTap: () => context.go(WaxRoute.bookSeries(row.pid)),
              );
            },
          );
        },
      ),
    );
  }
}
