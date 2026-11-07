import 'dart:async';

import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// In-memory [BooksApi] for `FakeRepository`.
mixin FakeBooks on FakeRepositoryState implements BooksApi {
  /// Held open, a book's detail read waits on it.
  Completer<void>? getBookGate;

  /// Stored per-book settings by pid; falls back to the book's own.
  final Map<String, BookSettings> storedBookSettings = {};

  /// Resume points by book pid; falls back to [playPositions].
  final Map<String, BookResume> bookResumes = {};

  final List<({String pid, BookSettings settings})> putBookSettingsCalls = [];

  /// Bookmarks by book pid, in the order they were made. The listing
  /// orders them by position, which is what the contract promises and
  /// what the server's own `ORDER BY position_ms` does; the controller's
  /// job is to keep that order when it places a new mark rather than
  /// refetching, which is what `spoken_face_test` presses on.
  final Map<String, List<Bookmark>> bookmarks = {};
  final List<({String pid, int positionMs, String? note, String? id})>
  createBookmarkCalls = [];
  final List<({String pid, String id})> deleteBookmarkCalls = [];

  /// What each create or delete throws instead of landing (a full book, a
  /// dropped connection).
  WaxDeckApiException? createBookmarkError;
  WaxDeckApiException? deleteBookmarkError;
  int _bookmarkCounter = 0;

  @override
  Future<BookDetail> getBook(String pid) async {
    await getBookGate?.future;
    final book = books[pid];
    if (book == null) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such book',
        statusCode: 404,
      );
    }
    final settings = storedBookSettings[pid] ?? book.settings;
    return BookDetail(
      pid: book.pid,
      title: book.title,
      subtitle: book.subtitle,
      authors: book.authors,
      narrators: book.narrators,
      series: book.series,
      seriesPid: book.seriesPid,
      seriesSequence: book.seriesSequence,
      authorPid: book.authorPid,
      publisher: book.publisher,
      asin: book.asin,
      isbn: book.isbn,
      edition: book.edition,
      abridged: book.abridged,
      descriptionHtml: book.descriptionHtml,
      durationMs: book.durationMs,
      artUrl: book.artUrl,
      chapters: book.chapters,
      parts: book.parts,
      settings: settings,
    );
  }

  @override
  Future<BookResume> getBookResume(String pid) async {
    return bookResumes[pid] ?? BookResume(positionMs: playPositions[pid] ?? 0);
  }

  @override
  Future<BookSettings> putBookSettings(
    String pid,
    BookSettings settings,
  ) async {
    putBookSettingsCalls.add((pid: pid, settings: settings));
    storedBookSettings[pid] = settings;
    return settings;
  }

  /// Holds every bookmark read until completed.
  Completer<void>? listBookmarksGate;

  /// Thrown by every bookmark read while set.
  WaxDeckApiException? listBookmarksError;

  /// How many bookmark reads were made.
  int listBookmarksCalls = 0;

  /// Holds every bookmark create until completed, when set.
  Completer<void>? createBookmarkGate;

  @override
  Future<List<Bookmark>> listBookmarks(String pid) async {
    listBookmarksCalls++;
    await listBookmarksGate?.future;
    if (listBookmarksError case final error?) throw error;
    final marks = [...?bookmarks[pid]]
      ..sort((a, b) => a.positionMs.compareTo(b.positionMs));
    return marks;
  }

  @override
  Future<Bookmark> createBookmark(
    String pid,
    int positionMs, {
    String? note,
    String? id,
  }) async {
    createBookmarkCalls.add((
      pid: pid,
      positionMs: positionMs,
      note: note,
      id: id,
    ));
    await createBookmarkGate?.future;
    final error = createBookmarkError;
    if (error != null) throw error;
    // A replay answers what is stored, as the server does.
    if (bookmarks[pid]?.where((m) => m.id == id).firstOrNull case final held?) {
      return held;
    }
    final mark = Bookmark(
      id: id ?? 'bm-${++_bookmarkCounter}',
      positionMs: positionMs,
      note: note,
      createdAt: DateTime.utc(2026, 8, 1),
    );
    (bookmarks[pid] ??= <Bookmark>[]).add(mark);
    return mark;
  }

  @override
  Future<void> deleteBookmark(String pid, String bookmarkId) async {
    deleteBookmarkCalls.add((pid: pid, id: bookmarkId));
    final error = deleteBookmarkError;
    if (error != null) throw error;
    bookmarks[pid]?.removeWhere((mark) => mark.id == bookmarkId);
  }

  /// The series the book listing answers, paged by [limit] when one is
  /// asked for.
  final List<BookSeries> bookSeries = [];

  /// Every series page read, in call order.
  final List<({String? cursor, int? limit})> bookSeriesReads = [];

  @override
  Future<BookSeriesPage> listBookSeries({String? cursor, int? limit}) async {
    bookSeriesReads.add((cursor: cursor, limit: limit));
    final start = cursor == null ? 0 : int.parse(cursor);
    final end = limit == null
        ? bookSeries.length
        : (start + limit).clamp(0, bookSeries.length);
    return BookSeriesPage(
      series: bookSeries.sublist(start.clamp(0, bookSeries.length), end),
      nextCursor: end < bookSeries.length ? '$end' : null,
    );
  }

  /// The series detail answered by pid; an unknown pid is a 404, as the
  /// server's is.
  final Map<String, BookSeriesDetail> bookSeriesDetails = {};

  /// Every series detail read, by pid, in call order.
  final List<String> bookSeriesDetailReads = [];

  @override
  Future<BookSeriesDetail> getBookSeries(String pid) async {
    bookSeriesDetailReads.add(pid);
    final detail = bookSeriesDetails[pid];
    if (detail == null) {
      throw const WaxDeckApiException(
        statusCode: 404,
        code: 'not-found',
        message: 'no series with pid',
      );
    }
    return detail;
  }
}
