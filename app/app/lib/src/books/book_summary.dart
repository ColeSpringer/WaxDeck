import 'package:waxdeck_api/waxdeck_api.dart';

/// A row built here from a fuller read of the item (a book's, from its
/// detail), not the server's row for it: its fields mean what that read
/// means, so the queue's recheck compares the server's rows for it with
/// each other, not with it.
class ComposedSummary extends ItemSummary {
  const ComposedSummary({
    required super.pid,
    required super.mediaType,
    required super.title,
    required super.durationMs,
    super.artist,
    super.album,
    super.artistPid,
    super.albumPid,
    super.trackNumber,
    super.discNumber,
    super.sortKey,
    super.artistSort,
    super.artistSortKey,
    super.artUrl,
  });
}

/// Builds the summary the player needs from the book detail: authors
/// joined and the series as album, which the server's row for the book
/// is not, so it is held as a row composed here.
ItemSummary bookItemSummary(BookDetail book) => ComposedSummary(
  pid: book.pid,
  mediaType: MediaType.audiobook,
  title: book.title,
  artist: book.authors.isEmpty ? null : book.authors.join(', '),
  album: book.series,
  durationMs: book.durationMs,
  artUrl: book.artUrl,
);
