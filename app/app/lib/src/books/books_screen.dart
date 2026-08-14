import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../player/play_progress.dart';
import '../search/search_chrome.dart';
import '../shell/account_chrome.dart';
import '../settings/client_prefs.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'books_controller.dart';

/// The audiobook domain's front door: what is being read, and everything
/// there is to read.
class BooksScreen extends ConsumerStatefulWidget {
  const BooksScreen({super.key});

  @override
  ConsumerState<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends ConsumerState<BooksScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels < position.maxScrollExtent - 600) return;
    ref.read(booksProvider.notifier).loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(booksProvider);
    final view = ref.watch(bookViewProvider);
    final loaded = state.value?.books ?? const <ItemSummary>[];
    // Windowed, like every other listing that reads play states: one key
    // per page of rows, so paging never re-reads the pages before it.
    final states = <String, PlayProgress>{};
    for (final key in playProgressKeys(loaded)) {
      states.addAll(ref.watch(playProgressProvider(key)).value ?? const {});
    }
    final progress = PlayProgressView(states);
    final shown = arrangeBooks(loaded, view, progress);

    return WaxScaffold(
      title: 'Audiobooks',
      semanticsId: SemanticsIds.booksHub,
      controller: _scroll,
      actions: <Widget>[
        const _HubOverflow(),
        const SearchAction(),
        const AccountAction(),
      ],
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: _ContinueShelf(books: loaded, states: states),
        ),
        if (loaded.isNotEmpty)
          SliverToBoxAdapter(child: _Filters(books: loaded)),
        switch (state) {
          AsyncData() when loaded.isEmpty => const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: 'No audiobooks yet',
              message:
                  'Books turn up here as the library scans them. Point a '
                  'library at your audiobook folder and they arrive with '
                  'their chapters.',
              glyph: WaxIcons.audiobooks,
            ),
          ),
          // Loaded, but every book is filtered out. Distinct from an
          // empty library and answered differently: the way out is the
          // chips above, not a scan.
          AsyncData() when shown.isEmpty => SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: 'Nothing matches',
              message: 'No book here is ${view.filter.label.toLowerCase()}.',
              glyph: WaxIcons.filter,
              actionLabel: 'Show all books',
              onAction: () =>
                  ref.read(bookViewProvider.notifier).filterBy(BookFilter.all),
            ),
          ),
          AsyncData() => _BookGrid(books: shown, progress: progress),
          AsyncError(:final error) => SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(
              title: 'Could not load your books',
              message: error is WaxDeckApiException
                  ? error.message
                  : 'The server did not answer.',
              onRetry: () => ref.invalidate(booksProvider),
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

/// Sort, in an overflow rather than on the bar: the bar's room belongs to
/// search, and an order is something a listener sets once.
class _HubOverflow extends ConsumerWidget {
  const _HubOverflow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(bookViewProvider);
    return WaxMenuButton<String>(
      glyph: WaxIcons.more,
      label: 'More',
      semanticsId: SemanticsIds.booksHubOverflow,
      items: <WaxMenuItem<String>>[
        for (final sort in BookSort.values)
          WaxMenuItem<String>(
            value: sort.name,
            label: 'Sort by ${sort.label.toLowerCase()}',
            selected: sort == view.sort,
            semanticsId: SemanticsIds.bookSort(sort.name),
          ),
      ],
      onSelected: (name) =>
          ref.read(bookViewProvider.notifier).sortBy(BookSort.byName(name)),
    );
  }
}

/// The finished/unfinished chips, and the authors on the shelf.
///
/// Two rows rather than one: they are different questions, and a single
/// row would let an author scroll the finished filter out of reach.
class _Filters extends ConsumerWidget {
  const _Filters({required this.books});

  final List<ItemSummary> books;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(bookViewProvider);
    final sizeClass = WaxSizeClass.of(context);
    final authors = bookAuthors(books);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FilterChipRow(
          padding: sizeClass.gutter,
          selected: view.filter.name,
          chips: <WaxFilterChip>[
            for (final filter in BookFilter.values)
              WaxFilterChip(
                name: filter.name,
                label: filter.label,
                semanticsId: SemanticsIds.bookFinishedFilter(filter.name),
              ),
          ],
          onSelect: (name) => ref
              .read(bookViewProvider.notifier)
              .filterBy(BookFilter.byName(name)),
        ),
        // Only where there is a choice to make: one author is the whole
        // shelf, and a chip that narrows to everything is a control that
        // does nothing.
        if (authors.length > 1) ...<Widget>[
          const SizedBox(height: WaxSpace.s8),
          FilterChipRow(
            padding: sizeClass.gutter,
            // The row is single-select and this one clears rather than
            // switches, so "no author" needs a name of its own: an empty
            // string is the selection when nothing is narrowed.
            selected: view.author ?? '',
            chips: <WaxFilterChip>[
              for (final author in authors)
                WaxFilterChip(
                  name: author.name,
                  label: '${author.name} (${author.count})',
                  semanticsId: SemanticsIds.bookAuthorFilter(author.name),
                ),
            ],
            onSelect: ref.read(bookViewProvider.notifier).toggleAuthor,
          ),
        ],
        const SizedBox(height: WaxSpace.s12),
      ],
    );
  }
}

/// What is part way through, with how much is left.
class _ContinueShelf extends ConsumerWidget {
  const _ContinueShelf({required this.books, required this.states});

  final List<ItemSummary> books;
  final Map<String, PlayProgress> states;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reading = continueListening(books, states);
    if (reading.isEmpty) return const SizedBox.shrink();
    final store = ref.watch(artworkStoreProvider);
    final l10n = context.waxL10n;
    final tiles = <MediaTileData>[
      for (final book in reading)
        MediaTileData(
          title: book.title,
          subtitle: book.artist,
          artwork: store.source(book.artUrl),
          domain: WaxDomain.audiobooks,
          shape: ArtworkShape.portrait,
          progress: states[book.pid]?.fractionOf(book.durationMs),
          trailingText: _left(l10n, states[book.pid], book.durationMs),
          trailingSpoken: _leftSpoken(l10n, states[book.pid], book.durationMs),
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
        title: 'Continue listening',
        overline: 'Part way through',
        items: tiles,
        // By position rather than by title: a tile carries no value
        // equality, and two editions of one book share a name.
        onTapItem: (tile) {
          final at = tiles.indexOf(tile);
          if (at < 0) return;
          // Gone to, not pushed: a book is declared under this hub, so
          // back lands here and the address bar follows.
          context.go(WaxRoute.book(reading[at].pid));
        },
      ),
    );
  }

  /// "6 hr left", the readout the layout asks the shelf for. A span
  /// rather than a timecode: a book with "7:50:12" left is being told a
  /// clock time.
  static String? _left(
    WaxLocalizations l10n,
    PlayProgress? progress,
    int durationMs,
  ) {
    final remaining = progress?.remainingOf(durationMs);
    return remaining == null ? null : '${l10n.formatSpan(remaining)} left';
  }

  /// The same, for the ear: "6 hours left" rather than "6 hr left".
  static String? _leftSpoken(
    WaxLocalizations l10n,
    PlayProgress? progress,
    int durationMs,
  ) {
    final remaining = progress?.remainingOf(durationMs);
    return remaining == null ? null : '${l10n.spellDuration(remaining)} left';
  }
}

/// Every book, as covers.
class _BookGrid extends ConsumerWidget {
  const _BookGrid({required this.books, required this.progress});

  final List<ItemSummary> books;
  final PlayProgressView progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final store = ref.watch(artworkStoreProvider);
    final l10n = context.waxL10n;
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
            itemBuilder: (context, index) {
              final book = books[index];
              final state = progress[book.pid];
              return MediaCard(
                data: MediaTileData(
                  title: book.title,
                  subtitle: book.artist,
                  artwork: store.source(book.artUrl),
                  domain: WaxDomain.audiobooks,
                  shape: ArtworkShape.portrait,
                  progress: state.fractionOf(book.durationMs),
                  trailingText: _caption(
                    l10n,
                    state,
                    book.durationMs,
                    short: true,
                  ),
                  trailingSpoken: _caption(
                    l10n,
                    state,
                    book.durationMs,
                    short: false,
                  ),
                  semanticsId: SemanticsIds.book(book.pid),
                ),
                width: grid.width,
                onTap: () => context.go(WaxRoute.book(book.pid)),
              );
            },
          );
        },
      ),
    );
  }

  /// What the cover says under the author: how much is left of a book in
  /// progress, that it is finished, or how long it is.
  ///
  /// [short] draws it, abbreviated to what a cell has room for; the long
  /// form is what a screen reader hears.
  static String? _caption(
    WaxLocalizations l10n,
    PlayProgress state,
    int durationMs, {
    required bool short,
  }) {
    String span(Duration d) =>
        short ? l10n.formatSpan(d) : l10n.spellDuration(d);
    if (state.finished) return 'Finished';
    final remaining = state.remainingOf(durationMs);
    if (state.inProgress && remaining != null) {
      return '${span(remaining)} left';
    }
    return durationMs > 0 ? span(Duration(milliseconds: durationMs)) : null;
  }
}

/// The widest a book cover is allowed to be. Narrower than a show tile:
/// book covers are portrait as often as square, so a cell sized for a
/// square cover makes a portrait one very tall.
const double kBookTileExtent = 156;
