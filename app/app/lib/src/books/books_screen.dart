import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../l10n/l10n.dart';
import '../library/hub_tiles.dart';
import '../library/item_play.dart';
import '../music/music_controllers.dart';
import '../player/play_progress.dart';
import '../presenters/media_tiles.dart';
import '../search/search_chrome.dart';
import '../shell/account_chrome.dart';
import '../settings/client_prefs.dart';
import '../shell/async_sliver_face.dart';
import '../shell/paged_scroll.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../uploads/add_to_library.dart';
import 'book_dimension.dart';
import 'books_controller.dart';
import 'series_merge.dart';

/// The ways into the shelf, ahead of the shelves. Counted over the books
/// alone, as the indexes they open are.
List<HubTile> _tiles(AppLocalizations l10n) => <HubTile>[
  for (final dimension in BookDimension.values)
    HubTile(
      name: dimension.segment,
      label: dimension.titleOf(l10n),
      glyph: dimension.dimension.glyph,
      location: WaxRoute.bookIndex(dimension),
      count: musicIndexCountProvider((
        dimension: dimension.dimension,
        domain: BrowseDomain.books,
      )),
    ),
  HubTile(
    name: 'series',
    label: l10n.bookSeriesTitle,
    glyph: WaxIcons.library,
    location: WaxRoute.bookSeriesIndex,
    count: bookSeriesCountProvider,
  ),
];

/// The audiobook domain's front door: what is being read, and everything
/// there is to read.
class BooksScreen extends ConsumerStatefulWidget {
  const BooksScreen({super.key});

  @override
  ConsumerState<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends ConsumerState<BooksScreen> with PagedScroll {
  @override
  double get pageAhead => 600;

  @override
  void loadMore() => ref.read(booksProvider.notifier).loadMore();

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(booksProvider);
    final view = ref.watch(bookViewProvider);
    final loaded = state.value?.books ?? const <ItemSummary>[];
    final progress = watchPlayProgress(ref, loaded);
    final shown = arrangeBooks(loaded, view, progress);
    final l10n = context.l10n;
    final canUpload = canAddToLibrary(ref);
    // The chips narrow the loaded pages, so a shelf drawn shorter than
    // what it pages leaves nothing to scroll and the scroll listener
    // never fires. Read off the two lists rather than off the chips, so
    // a filter added later is covered without being remembered here.
    final narrowed = shown.length < loaded.length;
    final more = state.value?.hasMore ?? false;
    final loadingMore = state.value?.loadingMore ?? false;
    // Not while the chips narrow it, where a filter that matches little
    // would page the whole listing in; that view keeps its own button.
    fillViewportWhile(
      more && !loadingMore && !narrowed,
      at: state.value?.books,
    );

    return WaxScaffold(
      title: l10n.booksTitle,
      semanticsId: SemanticsIds.booksHub,
      controller: pagedScroll,
      actions: <Widget>[
        // The hub add the music hub was also missing: same gate, same
        // sheet, this section's type already chosen.
        if (canUpload)
          WaxIconButton(
            glyph: WaxIcons.add,
            label: l10n.booksAddToLibrary,
            semanticsId: SemanticsIds.booksAdd,
            onPressed: () =>
                showAddToLibrarySheet(context, ref, fixed: MediaType.audiobook),
          ),
        const _HubOverflow(),
        const SearchAction(),
        const AccountAction(),
      ],
      slivers: <Widget>[
        HubTiles(tiles: _tiles(l10n), semanticsIdOf: SemanticsIds.bookTile),
        const SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s16)),
        SliverToBoxAdapter(
          child: _ContinueShelf(books: loaded, progress: progress),
        ),
        const SliverToBoxAdapter(child: _SeriesShelf()),
        if (loaded.isNotEmpty) const SliverToBoxAdapter(child: _AllHeader()),
        AsyncSliverFace<BooksState>(
          state: state,
          skeleton: SkeletonShape.grid,
          errorTitle: l10n.booksLoadError,
          onRetry: () => ref.invalidate(booksProvider),
          isEmpty: (_) => shown.isEmpty,
          // Three empties, told apart by why nothing is showing: no
          // books at all, every book filtered out with pages still
          // unread, or every book filtered out with nothing left to
          // fetch. The way out differs each time: the upload where the
          // account may, a fetch, or the chips above.
          empty: (context, _) => switch (loaded.isEmpty) {
            true => SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                title: l10n.booksEmptyTitle,
                glyph: WaxIcons.audiobooks,
                actionLabel: canUpload ? l10n.booksEmptyAdd : null,
                onAction: canUpload
                    ? () => showAddToLibrarySheet(
                        context,
                        ref,
                        fixed: MediaType.audiobook,
                      )
                    : null,
              ),
            ),
            false when more => SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                title: l10n.booksNothingMatchesYet,
                message: l10n.booksNothingMatchesYetEmptyMessage(loaded.length),
                glyph: WaxIcons.filter,
                actionLabel: l10n.booksLoadMore,
                actionBusy: loadingMore,
                onAction: () => ref.read(booksProvider.notifier).loadMore(),
              ),
            ),
            false => SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                title: l10n.booksNothingMatches,
                // The whole sentence per chip rather than the chip's own
                // word lower-cased into a frame: the casing was an
                // English rule, and the frame is the language's business.
                message: l10n.booksFilterEmptyMessage(view.filter.name),
                glyph: WaxIcons.filter,
                actionLabel: l10n.booksShowAll,
                onAction: () => ref
                    .read(bookViewProvider.notifier)
                    .filterBy(BookFilter.all),
              ),
            ),
          },
          // The footer rides with the grid rather than sitting beside
          // the face: a load state that keeps its previous value would
          // otherwise draw a live control under a skeleton.
          builder: (context, _) => SliverMainAxisGroup(
            slivers: <Widget>[
              BookGrid(
                books: shown,
                progress: progress,
                onOpen: (book) => context.go(WaxRoute.book(book.pid)),
              ),
              // Under the grid, so a shelf long enough to scroll has
              // already paged by the time this is reached.
              if (narrowed && more)
                SliverToBoxAdapter(
                  child: LoadMoreFooter(
                    label: l10n.booksLoadMore,
                    loading: loadingMore,
                    padding: const EdgeInsets.only(top: WaxSpace.s16),
                    onLoadMore: () =>
                        ref.read(booksProvider.notifier).loadMore(),
                  ),
                ),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s32)),
      ],
    );
  }
}

/// Sort, in an overflow rather than on the bar: the bar's room belongs to
/// search, and an order is something a listener sets once.
class _HubOverflow extends ConsumerWidget {
  const _HubOverflow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(bookViewProvider);
    final l10n = context.l10n;
    return WaxMenuButton<String>(
      glyph: WaxIcons.more,
      label: l10n.booksMore,
      semanticsId: SemanticsIds.booksHubOverflow,
      items: <WaxMenuItem<String>>[
        for (final sort in BookSort.values)
          WaxMenuItem<String>(
            value: sort.name,
            label: l10n.booksSortRow(sort.name),
            selected: sort == view.sort,
            semanticsId: SemanticsIds.bookSort(sort.name),
          ),
      ],
      onSelected: (name) =>
          ref.read(bookViewProvider.notifier).sortBy(BookSort.byName(name)),
    );
  }
}

/// The grid's heading, and the finished/unfinished chips under it.
class _AllHeader extends ConsumerWidget {
  const _AllHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(bookViewProvider);
    final sizeClass = WaxSizeClass.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: sizeClass.gutter,
          child: SectionHeader(title: l10n.booksAllTitle),
        ),
        FilterChipRow(
          padding: sizeClass.gutter,
          selected: view.filter.name,
          chips: <WaxFilterChip>[
            for (final filter in BookFilter.values)
              WaxFilterChip(
                name: filter.name,
                label: filter.labelOf(l10n),
                semanticsId: SemanticsIds.bookFinishedFilter(filter.name),
              ),
          ],
          onSelect: (name) => ref
              .read(bookViewProvider.notifier)
              .filterBy(BookFilter.byName(name)),
        ),
        const SizedBox(height: WaxSpace.s12),
      ],
    );
  }
}

/// What is part way through, with how much is left.
class _ContinueShelf extends ConsumerWidget {
  const _ContinueShelf({required this.books, required this.progress});

  final List<ItemSummary> books;
  final PlayProgressView progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reading = continueListening(books, progress);
    if (reading.isEmpty) return const SizedBox.shrink();
    final store = ref.watch(artworkStoreProvider);
    final l10n = context.l10n;
    final wax = context.waxL10n;
    // By position rather than by title: a tile carries no value equality,
    // and two editions of one book share a name.
    void resume(WidgetRef ref, int at) {
      if (at < 0) return;
      final book = reading[at];
      playOrResumeItem(ref, book, progress[book.pid]);
    }

    final tiles = <MediaTileData>[
      for (final book in reading)
        bookContinueTile(
          book,
          l10n: l10n,
          wax: wax,
          store: store,
          progress: progress[book.pid],
          // Its own handle, not the grid card's. A half-heard book is on
          // this shelf *and* in the grid below, so one handle would name
          // two controls and leave a spec picking by document order
          // rather than by intent - which is what the search field and
          // the search action were split over.
          semanticsId: SemanticsIds.bookContinue(book.pid),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: WaxSpace.s8, bottom: WaxSpace.s16),
      child: ShelfRow(
        title: l10n.booksContinueTitle,
        items: tiles,
        // The shelf exists to carry on, so the card and its cover both
        // do; the book's own screen is in the card's menu.
        onTapItem: (tile) => resume(ref, tiles.indexOf(tile)),
        onPlayItem: (tile) => resume(ref, tiles.indexOf(tile)),
        playSemanticsIdAt: (at) =>
            SemanticsIds.bookContinuePlay(reading[at].pid),
        playLabelAt: (at) =>
            resumeLabel(l10n, reading[at], progress[reading[at].pid]),
        onMoreItem: (tile) {
          final at = tiles.indexOf(tile);
          if (at < 0) return;
          unawaited(
            showItemCardMenu(
              context,
              ref,
              reading[at],
              progress[reading[at].pid],
              withOpen: true,
            ),
          );
        },
      ),
    );
  }
}

/// The series the shelf's books belong to, and the way into the index.
///
/// Cards without artwork: the listing carries counts and library pids
/// but no member pids, so a cover would cost a members read per row.
/// Hidden when the library has none, which is the ordinary state for a
/// shelf whose tags name no series.
class _SeriesShelf extends ConsumerWidget {
  const _SeriesShelf();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The shelf's own read, which stops as soon as it has enough tiles;
    // the drained list is the index's and the merge picker's.
    final series =
        ref.watch(bookSeriesShelfProvider).value ?? const <BookSeries>[];
    if (series.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;
    final shown = series.take(kBookSeriesShelf).toList(growable: false);
    final tiles = <MediaTileData>[
      for (final row in shown)
        seriesCardTile(
          row,
          l10n: l10n,
          semanticsId: SemanticsIds.bookSeriesCard(row.pid),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: WaxSpace.s16),
      child: ShelfRow(
        title: l10n.bookSeriesTitle,
        items: tiles,
        actionLabel: l10n.bookSeriesShowAll,
        actionSemanticsId: SemanticsIds.bookSeriesSeeAll,
        onAction: () => context.go(WaxRoute.bookSeriesIndex),
        // By position rather than by title: a tile carries no value
        // equality, and two spellings of one series share a name. Pushed:
        // a series' declared parent is the index, so back should still
        // find the hub.
        onTapItem: (tile) {
          final at = tiles.indexOf(tile);
          if (at < 0) return;
          unawaited(context.push(WaxRoute.bookSeries(shown[at].pid)));
        },
      ),
    );
  }
}

/// A card's key, so the card moves with its book (see [indexByKey]).
Key _bookKey(ItemSummary book) => ValueKey(SemanticsIds.book(book.pid));

/// Books as covers: the hub's whole shelf, or one author's or genre's.
class BookGrid extends ConsumerWidget {
  const BookGrid({
    required this.books,
    required this.progress,
    required this.onOpen,
    super.key,
  });

  final List<ItemSummary> books;
  final PlayProgressView progress;

  /// Gone to from the hub, which is a book's declared parent, and pushed
  /// from anywhere else.
  final ValueChanged<ItemSummary> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final store = ref.watch(artworkStoreProvider);
    final l10n = context.l10n;
    final wax = context.waxL10n;
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
            itemCount: books.length,
            findChildIndexCallback: indexByKey(books, _bookKey),
            itemBuilder: (context, index) {
              final book = books[index];
              final state = progress[book.pid];
              return MediaCard(
                key: _bookKey(book),
                data: bookCardTile(
                  book,
                  l10n: l10n,
                  wax: wax,
                  store: store,
                  progress: state,
                  semanticsId: SemanticsIds.book(book.pid),
                ),
                width: grid.width,
                onTap: () => onOpen(book),
                onPlay: () => playOrResumeItem(ref, book, state),
                playSemanticsId: SemanticsIds.bookPlay(book.pid),
                playLabel: resumeLabel(l10n, book, state),
                onMore: () =>
                    unawaited(showItemCardMenu(context, ref, book, state)),
              );
            },
          );
        },
      ),
    );
  }
}

/// The widest a book cover is allowed to be. Narrower than a show tile:
/// book covers are portrait as often as square, so a cell sized for a
/// square cover makes a portrait one very tall.
const double kBookTileExtent = 156;
