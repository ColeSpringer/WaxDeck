import '../l10n/l10n.dart';
import '../music/music_controllers.dart';

/// A way the books hub browses its shelf: the music index's dimension
/// over the books' own scope, under a segment of its own beneath
/// `/books`.
enum BookDimension {
  authors(segment: 'authors', dimension: MusicDimension.artists),
  genres(segment: 'genres', dimension: MusicDimension.genres);

  const BookDimension({required this.segment, required this.dimension});

  /// The path segment under `/books`. Never `series`, which is taken, and
  /// never a book pid's `bk-` shape, so `:pid` cannot claim it.
  final String segment;

  /// The dimension the server enumerates. An author is the artist
  /// dimension's bucket for a book: its primary author.
  final MusicDimension dimension;

  /// What this way of browsing is called: the hub tile and the index it
  /// opens. Selected on `name`, as [MusicDimension.titleOf] is.
  String titleOf(AppLocalizations l10n) => l10n.booksDimensionTitle(name);

  static BookDimension? bySegment(String segment) =>
      values.where((d) => d.segment == segment).firstOrNull;

  static BookDimension? byDimension(MusicDimension dimension) =>
      values.where((d) => d.dimension == dimension).firstOrNull;
}
