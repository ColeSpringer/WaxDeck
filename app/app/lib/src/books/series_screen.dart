import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../l10n/l10n.dart';
import '../library/item_menu.dart';
import '../player/play_progress.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'series_controller.dart';

/// One series: its books, in the order the tags put them.
class BookSeriesScreen extends ConsumerWidget {
  const BookSeriesScreen({required this.pid, super.key});

  final String pid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(bookSeriesDetailProvider(pid));
    final l10n = context.l10n;
    return WaxScaffold(
      title: detail.value?.name ?? l10n.bookSeriesTitle,
      largeTitle: false,
      semanticsId: SemanticsIds.bookSeriesScreen(pid),
      onBack: () => context.leave(fallback: WaxRoute.bookSeriesIndex),
      slivers: <Widget>[
        switch (detail) {
          // A series whose every book this account cannot open reads
          // as one with none: the read answers 404 only when the whole
          // series is out of reach, so an empty list here is a grant or
          // a tag rule rather than a mistake.
          AsyncData(:final value) when value.books.isEmpty =>
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                title: l10n.bookSeriesNoBooks,
                message: l10n.bookSeriesNoBooksMessage,
                glyph: WaxIcons.audiobooks,
              ),
            ),
          AsyncData(:final value) => SliverMainAxisGroup(
            slivers: <Widget>[
              SliverToBoxAdapter(child: _Header(series: value)),
              _Books(books: value.books),
            ],
          ),
          AsyncError(:final error) => SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(
              title: l10n.bookSeriesLoadError,
              message: context.explain(error),
              onRetry: () => ref.invalidate(bookSeriesDetailProvider(pid)),
            ),
          ),
          _ => const SliverToBoxAdapter(
            child: SkeletonShapes(shape: SkeletonShape.list),
          ),
        },
        const SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s32)),
      ],
    );
  }
}

/// The series' name, and what it adds up to.
class _Header extends StatelessWidget {
  const _Header({required this.series});

  final BookSeriesDetail series;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final wax = context.waxL10n;
    // The catalog-wide count where it was answered, the visible one
    // otherwise: a restricted account is told what it can open rather
    // than a zero the server withheld.
    final count = series.bookCount > 0 ? series.bookCount : series.books.length;
    final lines = <String>[
      l10n.bookSeriesBookCount(count),
      if (series.totalDurationMs > 0)
        wax.spellDuration(Duration(milliseconds: series.totalDurationMs)),
    ];
    return Padding(
      padding: WaxSizeClass.of(context).gutter.add(
        const EdgeInsets.only(top: WaxSpace.s8, bottom: WaxSpace.s16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(series.name, style: WaxType.titleScreen),
          const SizedBox(height: WaxSpace.s4),
          Text(
            lines.join(' · '),
            style: WaxType.caption.copyWith(
              color: WaxColors.of(context).textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Books extends ConsumerWidget {
  const _Books({required this.books});

  final List<BookSeriesEntry> books;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final store = ref.watch(artworkStoreProvider);
    final l10n = context.l10n;
    final wax = context.waxL10n;
    final rows = <ItemSummary>[for (final entry in books) entry.book];
    final states = <String, PlayProgress>{};
    for (final key in playProgressKeys(rows)) {
      states.addAll(ref.watch(playProgressProvider(key)).value ?? const {});
    }
    return SliverPadding(
      padding: sizeClass.gutter,
      sliver: SliverList.builder(
        itemCount: books.length,
        itemBuilder: (context, index) {
          final entry = books[index];
          final book = entry.book;
          return MediaListRow(
            data: MediaTileData(
              title: book.title,
              subtitle: book.artist,
              artwork: store.source(book.artUrl),
              domain: WaxDomain.audiobooks,
              shape: ArtworkShape.portrait,
              progress: states[book.pid]?.fractionOf(book.durationMs),
              trailingText: wax.formatSpan(
                Duration(milliseconds: book.durationMs),
              ),
              trailingSpoken: wax.spellDuration(
                Duration(milliseconds: book.durationMs),
              ),
              semanticsId: SemanticsIds.bookSeriesRow(index),
            ),
            // The number the tags spell, not the row's position: a
            // series can start at book two on a shelf that holds two of
            // five, and a dash where the tags name no number keeps the
            // column a column.
            leadingText: entry.sequence ?? l10n.bookSeriesUnknownSequence,
            // Pushed, not gone to: a book is declared under the hub,
            // so `go` would rebuild that ancestry and throw the series
            // away - and walking a series book by book would mean
            // re-navigating hub, index, series for every one of them.
            onTap: () => context.push(WaxRoute.book(book.pid)),
            onMore: () => showItemMenuForSummary(context, ref, book),
          );
        },
      ),
    );
  }
}
