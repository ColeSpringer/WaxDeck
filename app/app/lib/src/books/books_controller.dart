import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../player/play_progress.dart';
import '../providers.dart';

/// One audiobook's detail.
final bookDetailProvider = FutureProvider.autoDispose
    .family<BookDetail, String>(
      (ref, pid) => ref.watch(repositoryProvider).getBook(pid),
    );

/// How the hub orders the shelf of books.
enum BookSort {
  /// What the catalog added most recently, which is where a listener
  /// looks for the book they just imported.
  recent('Recently added'),
  title('Title'),
  author('Author');

  const BookSort(this.label);

  final String label;

  /// The enum's own `name` is the wire value the menu reports back, so a
  /// miss is a programming error rather than input.
  static BookSort byName(String name) => values.asNameMap()[name] ?? recent;
}

/// Which books the grid shows.
enum BookFilter {
  all('All'),
  unfinished('Unfinished'),
  finished('Finished');

  const BookFilter(this.label);

  final String label;

  static BookFilter byName(String name) => values.asNameMap()[name] ?? all;
}

/// What the hub is showing, and in what order.
///
/// Screen-local rather than a stored preference, the same answer the
/// podcast hub's sort gives: the settings registry that would own a
/// durable one lands with the settings phase.
class BookView {
  const BookView({
    this.sort = BookSort.recent,
    this.filter = BookFilter.all,
    this.author,
  });

  final BookSort sort;
  final BookFilter filter;

  /// The author whose books the grid is narrowed to, by display name.
  ///
  /// A name rather than an artist pid, deliberately. The facet endpoint
  /// enumerates artists across the whole library, so its buckets count
  /// music too and its keys drill to a mixed listing; the authors worth
  /// offering are the ones on the books this hub has actually loaded,
  /// which is a set the screen already holds.
  final String? author;

  BookView copyWith({
    BookSort? sort,
    BookFilter? filter,
    String? author,
    bool clearAuthor = false,
  }) => BookView(
    sort: sort ?? this.sort,
    filter: filter ?? this.filter,
    author: clearAuthor ? null : author ?? this.author,
  );
}

class BookViewController extends Notifier<BookView> {
  @override
  BookView build() => const BookView();

  void sortBy(BookSort sort) => state = state.copyWith(sort: sort);

  void filterBy(BookFilter filter) => state = state.copyWith(filter: filter);

  /// Toggles the author narrowing, as a single-select chip row does. For
  /// the chips only; a caller that means "show me this author" wants
  /// [narrowToAuthor].
  void toggleAuthor(String author) => state = state.author == author
      ? state.copyWith(clearAuthor: true)
      : state.copyWith(author: author);

  /// Narrows to [author] whether or not it was already the choice.
  void narrowToAuthor(String author) => state = state.copyWith(author: author);
}

final bookViewProvider = NotifierProvider<BookViewController, BookView>(
  BookViewController.new,
);

/// Accumulated pages of the audiobook listing.
class BooksState {
  const BooksState({
    required this.books,
    this.nextCursor,
    this.loadingMore = false,
  });

  final List<ItemSummary> books;
  final String? nextCursor;
  final bool loadingMore;

  bool get hasMore => nextCursor != null;

  BooksState copyWith({bool? loadingMore}) => BooksState(
    books: books,
    nextCursor: nextCursor,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// Pages every audiobook the caller can see.
///
/// One listing for the whole hub, sorted and filtered client-side. The
/// endpoint orders by title and offers no author or finished predicate,
/// and a library holds tens or hundreds of books rather than the tens of
/// thousands of tracks the music indexes page through — so the honest
/// shape is to load them and answer every arrangement from what is held,
/// instead of minting a cursor space per chip.
class BooksController extends AsyncNotifier<BooksState> {
  /// The queue cap, for the same reason the music listings use it:
  /// playing from the grid plays what the screen has.
  static const pageSize = 500;

  var _generation = 0;

  Future<ItemPage> _page(String? cursor) => ref
      .read(repositoryProvider)
      .listItems(
        mediaType: MediaType.audiobook,
        cursor: cursor,
        limit: pageSize,
      );

  @override
  Future<BooksState> build() async {
    _generation++;
    // Watched rather than read so a sign-in swap rebuilds the listing.
    ref.watch(repositoryProvider);
    final page = await _page(null);
    return BooksState(books: page.items, nextCursor: page.nextCursor);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final generation = _generation;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await _page(current.nextCursor);
      if (generation != _generation) return;
      state = AsyncData(
        BooksState(
          books: <ItemSummary>[...current.books, ...page.items],
          nextCursor: page.nextCursor,
        ),
      );
    } on WaxDeckApiException {
      if (generation != _generation) return;
      state = AsyncData(current.copyWith(loadingMore: false));
    } catch (_) {
      // The same split the music controllers make: release the paging
      // guard for every failure, surface the ones that are defects.
      if (generation == _generation) {
        state = AsyncData(current.copyWith(loadingMore: false));
      }
      rethrow;
    }
  }
}

final booksProvider = AsyncNotifierProvider<BooksController, BooksState>(
  BooksController.new,
);

/// The authors on [books], each with how many they wrote, biggest first
/// and alphabetical within a count.
///
/// Built from the loaded listing rather than from the facet endpoint,
/// which counts an author's music alongside their books (the bug P11
/// found from the other side: an artist bucket counting two audiobooks
/// opened to an empty music list).
List<({String name, int count})> bookAuthors(List<ItemSummary> books) {
  final counts = <String, int>{};
  for (final book in books) {
    final author = book.artist?.trim();
    if (author == null || author.isEmpty) continue;
    counts[author] = (counts[author] ?? 0) + 1;
  }
  final names = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0
          ? byCount
          : a.toLowerCase().compareTo(b.toLowerCase());
    });
  return <({String name, int count})>[
    for (final name in names) (name: name, count: counts[name]!),
  ];
}

/// [books] as [view] asks for them: narrowed, then ordered.
///
/// [progress] answers the finished filter, so a hub whose play states
/// have not landed yet shows everything rather than guessing. The
/// listing arrives in title order, which is what makes `recent` the only
/// arrangement that needs a key of its own — and the catalog gives a
/// listing no added-at, so recency reads off the pid, whose ULID prefix
/// is its mint time.
List<ItemSummary> arrangeBooks(
  List<ItemSummary> books,
  BookView view,
  PlayProgressView progress,
) {
  final author = view.author;
  final out = <ItemSummary>[
    for (final book in books)
      if (author == null || book.artist?.trim() == author)
        if (switch (view.filter) {
          BookFilter.all => true,
          BookFilter.finished => progress[book.pid].finished,
          BookFilter.unfinished => !progress[book.pid].finished,
        })
          book,
  ];
  int byTitle(ItemSummary a, ItemSummary b) =>
      a.title.toLowerCase().compareTo(b.title.toLowerCase());
  switch (view.sort) {
    case BookSort.title:
      out.sort(byTitle);
    case BookSort.author:
      out.sort((a, b) {
        final left = a.artist?.toLowerCase() ?? '';
        final right = b.artist?.toLowerCase() ?? '';
        // An unattributed book sorts last rather than first: an empty
        // string would win every comparison and lead the list.
        if (left.isEmpty != right.isEmpty) return left.isEmpty ? 1 : -1;
        final byAuthor = left.compareTo(right);
        return byAuthor != 0 ? byAuthor : byTitle(a, b);
      });
    case BookSort.recent:
      // Descending pid: a ULID sorts lexicographically by mint time, so
      // this is the order the catalog took them in without a field for
      // it. Ties are impossible (a pid is unique), so no fallback.
      out.sort((a, b) => b.pid.compareTo(a.pid));
  }
  return out;
}

/// The books a listener is part way through, most recently touched
/// first: the continue-listening shelf.
///
/// Ordered by the position write the server recorded, which is the
/// cross-device answer — a book left off on a phone leads the shelf on
/// the desktop. Books whose state carries no timestamp sort after the
/// ones that do rather than jumbling with them.
List<ItemSummary> continueListening(
  List<ItemSummary> books,
  Map<String, PlayProgress> progress, {
  int limit = 12,
}) {
  final started =
      <ItemSummary>[
        for (final book in books)
          if (progress[book.pid]?.inProgress ?? false) book,
      ]..sort((a, b) {
        final left = progress[a.pid]?.updatedAt;
        final right = progress[b.pid]?.updatedAt;
        // With no timestamps to go on, newest-added leads: a ULID sorts by
        // mint time, so this is the direction `BookSort.recent` runs and
        // the direction every other recency order in the app runs. A state
        // row for a book with a position ought to carry a stamp; this is
        // the answer for a server that gave one without.
        if (left == null && right == null) return b.pid.compareTo(a.pid);
        if (left == null) return 1;
        if (right == null) return -1;
        return right.compareTo(left);
      });
  return started.take(limit).toList();
}
