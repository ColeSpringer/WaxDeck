import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../l10n/l10n.dart';
import '../music/music_controllers.dart';
import '../player/play_progress.dart';
import '../providers.dart';
import '../search/search_chrome.dart';
import '../shell/async_sliver_face.dart';
import '../shell/paged_scroll.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'book_dimension.dart';
import 'books_screen.dart';

/// One author's books, or one genre's, as covers.
///
/// Drilled under the books' media type, the scope the index counted the
/// bucket over, so the count on the row that opened it and the shelf
/// here agree.
class BookBucketScreen extends ConsumerStatefulWidget {
  const BookBucketScreen({
    required this.dimension,
    required this.segment,
    this.label,
    super.key,
  });

  final BookDimension dimension;

  /// The handle from the location: an author's `ar-` pid, a genre key,
  /// or [musicUnknownSegment].
  final String segment;

  /// The bucket's name, when the caller had one. A cold link has none.
  final String? label;

  @override
  ConsumerState<BookBucketScreen> createState() => _BookBucketScreenState();
}

class _BookBucketScreenState extends ConsumerState<BookBucketScreen>
    with PagedScroll {
  MusicListing get _listing => (
    dimension: widget.dimension.dimension,
    segment: widget.segment,
    domain: BrowseDomain.books,
  );

  bool get _unknown => widget.segment == musicUnknownSegment;

  /// An author bucket's pid, which names the person and their artwork.
  String? get _authorPid =>
      widget.dimension == BookDimension.authors && !_unknown
      ? widget.segment
      : null;

  @override
  double get pageAhead => 600;

  @override
  void loadMore() => ref.read(musicItemsProvider(_listing).notifier).loadMore();

  String _title(AppLocalizations l10n) {
    if (_unknown) {
      return switch (widget.dimension) {
        BookDimension.authors => l10n.bookAuthorUnknown,
        BookDimension.genres => l10n.bookGenreUnknown,
      };
    }
    final given = widget.label;
    if (given != null && given.isNotEmpty) return given;
    final pid = _authorPid;
    // Never from a book: its artist line is a credit, not the author.
    // A genre key is a catalog id, which names nothing to a reader.
    final card = pid == null
        ? null
        : ref.watch(entityCardProvider(pid)).value?.title;
    return card ?? l10n.bookBucketFallbackTitle(widget.dimension.name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(musicItemsProvider(_listing));
    final books = state.value?.items ?? const <ItemSummary>[];
    final states = <String, PlayProgress>{};
    for (final key in playProgressKeys(books)) {
      states.addAll(ref.watch(playProgressProvider(key)).value ?? const {});
    }
    final progress = PlayProgressView(states);
    fillViewportWhile(
      (state.value?.hasMore ?? false) && !(state.value?.loadingMore ?? true),
      at: state.value?.items,
    );
    final title = _title(l10n);
    final loadError = l10n.bookBucketLoadError(widget.dimension.name);
    final pid = _authorPid;
    final store = ref.watch(artworkStoreProvider);
    // The listing answers an empty page for any key, so an empty author
    // page waits on the author's card to say whether they are there.
    final unproven =
        pid != null && state.hasValue && !state.hasError && books.isEmpty
        ? unprovenEntityFace(
            context,
            ref.watch(entityCardProvider(pid)),
            errorTitle: loadError,
            onRetry: () => ref.invalidate(entityCardProvider(pid)),
          )
        : null;

    return WaxScaffold(
      title: title,
      largeTitle: false,
      controller: pagedScroll,
      semanticsId: switch (widget.dimension) {
        BookDimension.authors => SemanticsIds.bookAuthorScreen(widget.segment),
        BookDimension.genres => SemanticsIds.bookGenreScreen(widget.segment),
      },
      onBack: () =>
          context.leave(fallback: WaxRoute.bookIndex(widget.dimension)),
      actions: const <Widget>[SearchAction()],
      slivers: <Widget>[
        if (unproven != null)
          unproven
        else
          AsyncSliverFace<MusicItemsState>(
            state: state,
            skeleton: SkeletonShape.grid,
            errorTitle: loadError,
            onRetry: () => ref.invalidate(musicItemsProvider(_listing)),
            isEmpty: (value) => value.items.isEmpty,
            empty: (context, _) => SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                title: l10n.bookBucketEmptyTitle,
                glyph: WaxIcons.audiobooks,
              ),
            ),
            builder: (context, value) => SliverMainAxisGroup(
              slivers: <Widget>[
                SliverToBoxAdapter(
                  child: EntityHeader(
                    title: title,
                    // Only once the shelf is whole: a keyset listing knows
                    // no total before its last page.
                    metadata: value.hasMore
                        ? null
                        : l10n.bookCount(value.items.length),
                    domain: WaxDomain.audiobooks,
                    shape: pid == null
                        ? ArtworkShape.portrait
                        : ArtworkShape.circle,
                    // The author's own portrait; a genre borrows its first
                    // cover, as a series does.
                    artwork: store.source(
                      pid == null
                          ? books.firstOrNull?.artUrl
                          : ref.watch(repositoryProvider).artUrlFor(pid),
                    ),
                  ),
                ),
                BookGrid(
                  books: value.items,
                  progress: progress,
                  // Pushed: a book's declared parent is the hub, so going
                  // there would throw this page away beneath it.
                  onOpen: (book) => context.push(WaxRoute.book(book.pid)),
                ),
                if (value.loadingMore)
                  const SliverToBoxAdapter(
                    child: SkeletonShapes(shape: SkeletonShape.grid, count: 1),
                  ),
              ],
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s32)),
      ],
    );
  }
}
