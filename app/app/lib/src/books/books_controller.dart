import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../library/page_walk.dart';
import '../player/play_progress.dart';
import '../providers.dart';

/// One audiobook's detail. A refusal is final: a pid that is no longer
/// a book (turned into tracks) answers 404, and retrying that would hold
/// the screen on its skeleton for the whole backoff.
final bookDetailProvider = FutureProvider.autoDispose
    .family<BookDetail, String>(
      (ref, pid) => ref.watch(repositoryProvider).getBook(pid),
      retry: retryUnlessRefused,
    );

/// How the hub orders the shelf of books.
enum BookSort {
  /// What the catalog added most recently, which is where a listener
  /// looks for the book they just imported.
  recent,
  title,
  author;

  /// The enum's own `name` is the wire value the menu reports back, so a
  /// miss is a programming error rather than input. What each order is
  /// called is copy, and lives in the row that draws it.
  static BookSort byName(String name) => values.asNameMap()[name] ?? recent;
}

/// Which books the grid shows.
enum BookFilter {
  all,
  unfinished,
  finished;

  static BookFilter byName(String name) => values.asNameMap()[name] ?? all;

  String labelOf(AppLocalizations l10n) => switch (this) {
    BookFilter.all => l10n.booksFilterAll,
    BookFilter.unfinished => l10n.booksFilterUnfinished,
    BookFilter.finished => l10n.booksFilterFinished,
  };
}

/// What the hub is showing, and in what order.
///
/// Screen-local rather than a stored preference, the same answer the
/// podcast hub's sort gives: the settings registry that would own a
/// durable one lands with the settings phase.
class BookView {
  const BookView({this.sort = BookSort.recent, this.filter = BookFilter.all});

  final BookSort sort;
  final BookFilter filter;

  BookView copyWith({BookSort? sort, BookFilter? filter}) =>
      BookView(sort: sort ?? this.sort, filter: filter ?? this.filter);
}

class BookViewController extends Notifier<BookView> {
  @override
  BookView build() => const BookView();

  void sortBy(BookSort sort) => state = state.copyWith(sort: sort);

  void filterBy(BookFilter filter) => state = state.copyWith(filter: filter);
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
/// thousands of tracks the music indexes page through - so the honest
/// shape is to load them and answer every arrangement from what is held,
/// instead of minting a cursor space per chip.
class BooksController extends AsyncNotifier<BooksState> {
  /// The queue cap, for the same reason the music listings use it:
  /// playing from the grid plays what the screen has.
  static const pageSize = 500;

  var _generation = 0;

  /// Whether the walk [generation] started has lost its reader: the hub
  /// was rebuilt under it, or is gone.
  bool _gone(int generation) => !ref.mounted || generation != _generation;

  /// A page reader over the repository as it is now, so a walk reads its
  /// pages through one repository rather than through the ref each time.
  Future<ItemPage> Function(String? cursor) _pages() {
    final repository = ref.read(repositoryProvider);
    return (cursor) => repository.listItems(
      mediaType: MediaType.audiobook,
      cursor: cursor,
      limit: pageSize,
    );
  }

  @override
  Future<BooksState> build() async {
    final generation = ++_generation;
    // Watched rather than read so a sign-in swap rebuilds the listing.
    ref.watch(repositoryProvider);
    ref.watch(signedInAccountProvider);
    // To the first page with books on it, past pages the listing emptied,
    // which the contract allows with books behind them: never "no
    // audiobooks" over books a page further on. No further, so a later
    // page that fails takes nothing this read showed and a run of short
    // pages is not walked to fill a quota; the hub asks for more as it
    // needs it, a grid too short to scroll included.
    final walk = await readPages(
      _pages(),
      want: 1,
      stop: () => _gone(generation),
    );
    return BooksState(books: walk.items, nextCursor: walk.nextCursor);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final generation = _generation;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      // To the next page with books on it, past pages the listing
      // emptied: one that adds nothing to the grid gives the hub nothing
      // to ask again from.
      final walk = await readPages(
        _pages(),
        from: current.nextCursor,
        want: 1,
        stop: () => _gone(generation),
      );
      if (_gone(generation)) return;
      state = AsyncData(
        BooksState(
          books: <ItemSummary>[...current.books, ...walk.items],
          nextCursor: walk.nextCursor,
        ),
      );
    } on WaxDeckApiException {
      if (_gone(generation)) return;
      state = AsyncData(current.copyWith(loadingMore: false));
    } catch (_) {
      // The same split the music controllers make: release the paging
      // guard for every failure, surface the ones that are defects.
      if (!_gone(generation)) {
        state = AsyncData(current.copyWith(loadingMore: false));
      }
      rethrow;
    }
  }
}

final booksProvider = AsyncNotifierProvider<BooksController, BooksState>(
  BooksController.new,
  retry: retryUnlessRefused,
);

/// [books] as [view] asks for them: narrowed, then ordered.
///
/// [progress] answers the finished filter, so a hub whose play states
/// have not landed yet shows everything rather than guessing. The
/// listing arrives in title order, which is what makes `recent` the only
/// arrangement that needs a key of its own - and the catalog gives a
/// listing no added-at, so recency reads off the pid, whose ULID prefix
/// is its mint time.
List<ItemSummary> arrangeBooks(
  List<ItemSummary> books,
  BookView view,
  PlayProgressView progress,
) {
  final out = <ItemSummary>[
    for (final book in books)
      if (switch (view.filter) {
        BookFilter.all => true,
        BookFilter.finished => progress[book.pid].finished,
        BookFilter.unfinished => !progress[book.pid].finished,
      })
        book,
  ];
  // The pid last, so books the catalog files under one key (it folds "The
  // Hobbit" and "Hobbit" together) keep one order however pages arrived.
  int byTitle(ItemSummary a, ItemSummary b) {
    final byKey = a.titleOrderKey.compareTo(b.titleOrderKey);
    return byKey != 0 ? byKey : a.pid.compareTo(b.pid);
  }

  switch (view.sort) {
    case BookSort.title:
      out.sort(byTitle);
    case BookSort.author:
      out.sort((a, b) {
        final left = a.artistOrderKey;
        final right = b.artistOrderKey;
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
/// cross-device answer - a book left off on a phone leads the shelf on
/// the desktop. Books whose state carries no timestamp sort after the
/// ones that do rather than jumbling with them.
List<ItemSummary> continueListening(
  List<ItemSummary> books,
  PlayProgressView progress, {
  int limit = 12,
}) {
  final started =
      <ItemSummary>[
        for (final book in books)
          if (progress[book.pid].inProgress) book,
      ]..sort((a, b) {
        final left = progress[a.pid].updatedAt;
        final right = progress[b.pid].updatedAt;
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
