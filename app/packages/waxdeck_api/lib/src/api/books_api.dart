import '../models.dart';

/// Audiobook detail, series, resume points and bookmarks.
abstract interface class BooksApi {
  /// `GET /books/{pid}`: full audiobook detail with chapters, parts, and
  /// the caller's per-book settings.
  Future<BookDetail> getBook(String pid);

  /// `GET /books/series`: one keyset page of the series the visible
  /// audiobooks belong to.
  Future<BookSeriesPage> listBookSeries({String? cursor, int? limit});

  /// `GET /series/{pid}`: one series and the books in it, in sequence
  /// order.
  Future<BookSeriesDetail> getBookSeries(String pid);

  /// `GET /books/{pid}/resume`: the caller's cross-device resume point
  /// on the book timeline.
  Future<BookResume> getBookResume(String pid);

  /// `PUT /books/{pid}/settings`: full replace of the caller's per-book
  /// playback settings.
  Future<BookSettings> putBookSettings(String pid, BookSettings settings);

  /// `GET /books/{pid}/bookmarks`: the caller's marks in one book, in
  /// timeline order.
  Future<List<Bookmark>> listBookmarks(String pid);

  /// `POST /books/{pid}/bookmarks`: mark a place on the book timeline,
  /// under [id] when the client minted one (a replay answers the mark).
  Future<Bookmark> createBookmark(
    String pid,
    int positionMs, {
    String? note,
    String? id,
  });

  /// `DELETE /books/{pid}/bookmarks/{bookmarkId}`: remove one mark.
  Future<void> deleteBookmark(String pid, String bookmarkId);
}
