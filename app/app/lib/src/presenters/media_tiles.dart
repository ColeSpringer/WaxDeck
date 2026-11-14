/// Turning models into the design system's tile data, one function per
/// surface that draws one.
///
/// `waxdeck_ui` never imports the API package, so every list row, shelf
/// card and grid tile is mapped here from the model it shows. A presenter
/// takes plain values - the model, the localization tables, the artwork
/// store, whatever state the model does not carry - and never a
/// `BuildContext` or a `WidgetRef`: the caller reads `context.l10n` and
/// passes the result. The e2e handle is always the caller's to pass,
/// because the same item is drawn on more than one surface.
library;

import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_store.dart';
import '../downloads/downloads_controller.dart';
import '../home/home_shelves.dart';
import '../l10n/l10n.dart';
import '../media_view.dart';
import '../player/play_progress.dart';
import '../podcasts/episode_fetch.dart';
import '../podcasts/podcast_shelves.dart';
import '../search/search_controller.dart';

/// The length on the right of a row, or none where there is none to say: a
/// feed that declares no length produces zero, and "0:00" would claim one.
String? _length(int durationMs) =>
    durationMs > 0 ? formatTimecode(Duration(milliseconds: durationMs)) : null;

// Tracks.

/// A music track's play count as its row carries it: the number, and the
/// words its tooltip and its node say. Zero on a counted list's unplayed
/// track, so the row keeps its shape when the first play lands; nothing
/// where the list counts nothing ([count] null) or on any other medium, so
/// a playlist's episode or a book part draws no count beside the tracks
/// that do.
typedef _Plays = ({int count, String? label, String? semanticsId});

_Plays? _plays(
  MediaType mediaType,
  int? count,
  AppLocalizations l10n,
  String? semanticsId,
) => count == null || mediaType != MediaType.music
    ? null
    : count > 0
    ? (
        count: count,
        label: l10n.musicTrackPlaysSpoken(count),
        semanticsId: semanticsId,
      )
    : (count: 0, label: null, semanticsId: null);

/// What every row that draws an item has in common: the title, the length,
/// and the hue and shape of the item's medium. A row never assumes music: an
/// artist's whole library holds books, a playlist holds any medium, and a
/// smart rule matches by it. A [store] draws the cover; null leaves the
/// monogram or the row's own index.
MediaTileData _itemRow(
  ItemSummary item, {
  String? subtitle,
  ArtworkStore? store,
  String? semanticsId,
  _Plays? plays,
}) => MediaTileData(
  title: item.title,
  subtitle: subtitle,
  artwork: store == null ? null : waxArtwork(store, item.artUrl),
  domain: waxDomainOf(item.mediaType),
  shape: waxShapeOf(item.mediaType),
  trailingText: _length(item.durationMs),
  playCount: plays?.count,
  playCountLabel: plays?.label,
  playCountSemanticsId: plays?.semanticsId,
  semanticsId: semanticsId,
);

/// An item of any medium in a row: the artist under the title, the cover
/// and the length, and a track's [playCount] on a list that counts them.
/// What a listing, a playlist's members and a mix's answers are drawn as.
MediaTileData itemRowTile(
  ItemSummary item, {
  required AppLocalizations l10n,
  required ArtworkStore store,
  required String semanticsId,
  int? playCount,
}) => _itemRow(
  item,
  subtitle: item.artist,
  store: store,
  semanticsId: semanticsId,
  plays: _plays(item.mediaType, playCount, l10n, null),
);

/// A track on its album's own screen.
///
/// The album's artist is in the header; a row names its own only where it
/// differs, which is what makes a compilation readable and an ordinary
/// release quiet.
MediaTileData trackRowTile(
  ItemSummary track, {
  required AppLocalizations l10n,
  required String? albumArtist,
  required String semanticsId,
  int? playCount,
  String? playCountSemanticsId,
}) => _itemRow(
  track,
  subtitle: track.artist == albumArtist ? null : track.artist,
  semanticsId: semanticsId,
  plays: _plays(track.mediaType, playCount, l10n, playCountSemanticsId),
);

/// A track in an artist's top list, captioned with the album it is on.
MediaTileData topTrackRowTile(
  ItemSummary track, {
  required AppLocalizations l10n,
  required ArtworkStore store,
  required String semanticsId,
  int? playCount,
  String? playCountSemanticsId,
}) => _itemRow(
  track,
  subtitle: track.album,
  store: store,
  semanticsId: semanticsId,
  plays: _plays(track.mediaType, playCount, l10n, playCountSemanticsId),
);

/// One queued entry, named by whatever the app knows about its pid. No
/// play count: a queue is what is about to play, not a list to choose
/// from.
///
/// An unresolved row still says where it sits and still answers a tap: a
/// queue that cannot be driven until every title has landed is worse than
/// one with a placeholder in it.
MediaTileData queueRowTile(
  ItemSummary? item, {
  required AppLocalizations l10n,
  required ArtworkStore store,
  required String semanticsId,
}) => item == null
    ? MediaTileData(title: l10n.commonLoadingTitle, semanticsId: semanticsId)
    : itemRowTile(item, l10n: l10n, store: store, semanticsId: semanticsId);

/// A match in a rule's preview: no cover and no handle, a list to read.
MediaTileData rulePreviewTile(ItemSummary item) =>
    _itemRow(item, subtitle: item.artist);

/// A track of the release the metadata workbench is open on.
MediaTileData workbenchTrackTile(
  ItemSummary track, {
  required String semanticsId,
}) => _itemRow(track, semanticsId: semanticsId);

/// The release itself, as the workbench list's first row. [album] is null
/// until it has been read; [trackCount] stands in for its count then.
MediaTileData workbenchAlbumTile(
  AlbumDetail? album, {
  required int trackCount,
  required AppLocalizations l10n,
  required String semanticsId,
}) => MediaTileData(
  title: album?.title ?? l10n.musicAlbumTitle,
  subtitle: <String>[
    if (album?.year case final year?) '$year',
    l10n.musicTrackCount(album?.itemCount ?? trackCount),
  ].join(' · '),
  semanticsId: semanticsId,
);

// Library items on home shelves.

/// The caption under a card: the artist, and the album where it says
/// something the artist line does not. Null rather than empty when the
/// item carries neither.
String? _itemCaption(ItemSummary item) {
  final parts = <String>[
    ?item.artist,
    if (item.album case final album? when album != item.artist) album,
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// "12 min left", and the spelled form a screen reader hears. Two tables:
/// the design system spells the duration, as every read-out span does, and
/// the frame around it is the app's own.
String? _shelfRemaining(
  AppLocalizations l10n,
  WaxLocalizations wax,
  PlayProgress progress,
  ItemSummary item, {
  required bool short,
}) {
  final remaining = progress.remainingOf(item.durationMs);
  if (remaining == null) return null;
  final span = short ? wax.formatSpan(remaining) : wax.spellDuration(remaining);
  return l10n.homeShelfRemaining(span);
}

/// A card on an item shelf. A [progress] draws the resume ring and the
/// time left; null is a shelf with no positions to show.
MediaTileData itemCardTile(
  ItemSummary item, {
  required AppLocalizations l10n,
  required WaxLocalizations wax,
  required ArtworkStore store,
  required String semanticsId,
  PlayProgress? progress,
}) {
  // The album joins the artist on the caption line: a shelf of singles
  // from one artist is otherwise a row of identical captions saying
  // nothing about which release each came from. Deduplicated, because an
  // episode's artist and album are both the show's title, and empty stays
  // null rather than becoming an empty caption line with a comma in the
  // spoken label.
  final caption = _itemCaption(item);
  return MediaTileData(
    title: item.title,
    subtitle: caption,
    // The card clamps every line, so the full name lives on the hover
    // tooltip.
    tooltip: <String?>[item.title, caption].nonNulls.join('\n'),
    artwork: waxArtwork(store, item.artUrl),
    domain: waxDomainOf(item.mediaType),
    shape: waxShapeOf(item.mediaType),
    progress: progress?.fractionOf(item.durationMs),
    trailingText: progress == null
        ? null
        : _shelfRemaining(l10n, wax, progress, item, short: true),
    trailingSpoken: progress == null
        ? null
        : _shelfRemaining(l10n, wax, progress, item, short: false),
    semanticsId: semanticsId,
  );
}

// Books.

/// What every book tile draws: the cover on the audiobook hue, portrait,
/// with the author under the title unless [byline] is off. A [progress]
/// draws the resume ring; the readout is the surface's own.
MediaTileData _bookTile(
  ItemSummary book, {
  required ArtworkStore store,
  required String semanticsId,
  bool byline = true,
  PlayProgress? progress,
  String? trailingText,
  String? trailingSpoken,
}) => MediaTileData(
  title: book.title,
  subtitle: byline ? book.artist : null,
  artwork: waxArtwork(store, book.artUrl),
  domain: WaxDomain.audiobooks,
  shape: ArtworkShape.portrait,
  progress: progress?.fractionOf(book.durationMs),
  trailingText: trailingText,
  trailingSpoken: trailingSpoken,
  semanticsId: semanticsId,
);

/// A book in a series, its whole length on the right when it has one.
MediaTileData seriesBookRowTile(
  ItemSummary book, {
  required WaxLocalizations wax,
  required ArtworkStore store,
  required PlayProgress progress,
  required String semanticsId,
}) {
  final length = book.durationMs > 0
      ? Duration(milliseconds: book.durationMs)
      : null;
  return _bookTile(
    book,
    store: store,
    progress: progress,
    trailingText: length == null ? null : wax.formatSpan(length),
    trailingSpoken: length == null ? null : wax.spellDuration(length),
    semanticsId: semanticsId,
  );
}

/// "6 hr left". A span rather than a timecode, which would read as a
/// clock time. [short] draws it; the long form is what a screen reader
/// hears.
String? _bookLeft(
  AppLocalizations l10n,
  WaxLocalizations wax,
  PlayProgress progress,
  int durationMs, {
  required bool short,
}) {
  final remaining = progress.remainingOf(durationMs);
  if (remaining == null) return null;
  return l10n.booksTimeLeft(
    short ? wax.formatSpan(remaining) : wax.spellDuration(remaining),
  );
}

/// A half-heard book on the continue shelf, with how much is left.
MediaTileData bookContinueTile(
  ItemSummary book, {
  required AppLocalizations l10n,
  required WaxLocalizations wax,
  required ArtworkStore store,
  required PlayProgress progress,
  required String semanticsId,
}) => _bookTile(
  book,
  store: store,
  progress: progress,
  trailingText: _bookLeft(l10n, wax, progress, book.durationMs, short: true),
  trailingSpoken: _bookLeft(l10n, wax, progress, book.durationMs, short: false),
  semanticsId: semanticsId,
);

/// What the cover says under the author: how much is left of a book in
/// progress, that it is finished, or how long it is.
///
/// [short] draws it, abbreviated to what a cell has room for; the long
/// form is what a screen reader hears.
String? _bookCaption(
  AppLocalizations l10n,
  WaxLocalizations wax,
  PlayProgress state,
  int durationMs, {
  required bool short,
}) {
  String span(Duration d) => short ? wax.formatSpan(d) : wax.spellDuration(d);
  if (state.finished) return l10n.booksFinished;
  final remaining = state.remainingOf(durationMs);
  if (state.inProgress && remaining != null) {
    return l10n.booksTimeLeft(span(remaining));
  }
  return durationMs > 0 ? span(Duration(milliseconds: durationMs)) : null;
}

/// A book in the hub's grid.
MediaTileData bookCardTile(
  ItemSummary book, {
  required AppLocalizations l10n,
  required WaxLocalizations wax,
  required ArtworkStore store,
  required PlayProgress progress,
  required String semanticsId,
}) => _bookTile(
  book,
  store: store,
  progress: progress,
  trailingText: _bookCaption(l10n, wax, progress, book.durationMs, short: true),
  trailingSpoken: _bookCaption(
    l10n,
    wax,
    progress,
    book.durationMs,
    short: false,
  ),
  semanticsId: semanticsId,
);

/// A bare portrait cover, for a shelf of an author's books.
MediaTileData bookShelfTile(
  ItemSummary book, {
  required ArtworkStore store,
  required String semanticsId,
}) => _bookTile(book, store: store, byline: false, semanticsId: semanticsId);

/// A series, without artwork: the listing carries counts but no member
/// pids, so a cover would cost a members read per row.
MediaTileData seriesCardTile(
  BookSeries series, {
  required AppLocalizations l10n,
  required String semanticsId,
}) => MediaTileData(
  title: series.name,
  // Zero is what a restricted account reads, and a "0 books" caption on a
  // series it can open is a lie the count is not allowed to tell.
  subtitle: series.bookCount > 0
      ? l10n.bookSeriesBookCount(series.bookCount)
      : null,
  domain: WaxDomain.audiobooks,
  semanticsId: semanticsId,
);

/// How long chapter [at] runs: to the next chapter's start, or to the end
/// of the book for the last one.
String? _chapterLength(BookDetail book, int at) {
  final chapter = book.chapters[at];
  final endMs =
      chapter.endMs ??
      (at + 1 < book.chapters.length
          ? book.chapters[at + 1].startMs
          : book.durationMs);
  final length = endMs - chapter.startMs;
  return _length(length);
}

/// Chapter [index] of [book], numbered when its tags name none.
MediaTileData chapterRowTile(
  BookDetail book,
  int index, {
  required AppLocalizations l10n,
  required String semanticsId,
}) => MediaTileData(
  title:
      book.chapters[index].title ??
      l10n.bookChapterFallback(book.chapters[index].index + 1),
  trailingText: _chapterLength(book, index),
  semanticsId: semanticsId,
);

// Music entities.

/// One bucket of an index. [artwork] is the caller's, since only some
/// dimensions have any; the unknown bucket is named in the reader's
/// language by [unknownTitle] rather than by the server's sentinel.
MediaTileData bucketTile(
  FacetBucket bucket, {
  required String unknownTitle,
  required String caption,
  required ArtworkShape shape,
  required String semanticsId,
  WaxArtwork? artwork,
}) => MediaTileData(
  title: bucket.unknown ? unknownTitle : bucket.label,
  subtitle: caption,
  artwork: artwork,
  shape: shape,
  semanticsId: semanticsId,
);

/// One release on an artist's page, whether they head it or are only
/// credited on it. A loose folder of tagged files has no entity [pid], so it
/// draws the monogram and carries no handle.
MediaTileData releaseTile(
  String title, {
  required int trackCount,
  required AppLocalizations l10n,
  required ArtworkStore store,
  required MediaUrlsApi repository,
  String? pid,
  String? semanticsId,
}) => MediaTileData(
  title: title,
  subtitle: l10n.musicTrackCount(trackCount),
  artwork: pid == null ? null : waxArtwork(store, repository.artUrlFor(pid)),
  semanticsId: semanticsId,
);

/// A "Made for you" mix card.
MediaTileData mixCardTile(
  MixCard card, {
  required AppLocalizations l10n,
  required ArtworkStore store,
  required String semanticsId,
}) => MediaTileData(
  title: card.titleOf(l10n),
  subtitle: l10n.discoveryInstantMixTitle,
  // The card clamps every line, so the full name lives on the hover
  // tooltip, as on every other home shelf.
  tooltip: card.titleOf(l10n),
  artwork: waxArtwork(store, card.artUrl),
  domain: WaxDomain.music,
  semanticsId: semanticsId,
);

/// The line under a pinned card's title: what the thing is, plus whose it
/// is where that is not the title itself.
String pinnedCardCaption(AppLocalizations l10n, EntityCard card) {
  final kind = switch (card.kind) {
    EntityCardKind.album => l10n.homePinnedKindAlbum,
    EntityCardKind.artist => l10n.homePinnedKindArtist,
    EntityCardKind.releaseGroup => l10n.homePinnedKindReleaseGroup,
    EntityCardKind.playlist => l10n.homePinnedKindPlaylist,
    EntityCardKind.podcast => l10n.homePinnedKindPodcast,
    EntityCardKind.book => l10n.homePinnedKindBook,
  };
  final artist = card.artist;
  return artist == null || artist.isEmpty
      ? kind
      : l10n.homePinnedCaption(kind, artist);
}

WaxDomain _pinnedDomain(EntityCardKind kind) => switch (kind) {
  EntityCardKind.podcast => WaxDomain.podcasts,
  EntityCardKind.book => WaxDomain.audiobooks,
  _ => WaxDomain.music,
};

/// A pinned entity on the home shelf.
MediaTileData pinnedCardTile(
  EntityCard card, {
  required AppLocalizations l10n,
  required ArtworkStore store,
  required MediaUrlsApi repository,
  required String semanticsId,
}) {
  final caption = pinnedCardCaption(l10n, card);
  return MediaTileData(
    title: card.title,
    subtitle: caption,
    // The card clamps every line, so the full name lives on the hover
    // tooltip, as on every other home shelf.
    tooltip: '${card.title}\n$caption',
    // A release group statically holds no artwork of its own, so it draws
    // a monogram rather than asking for a cover that 404s.
    artwork: card.kind == EntityCardKind.releaseGroup
        ? null
        : waxArtwork(store, repository.artUrlFor(card.pid)),
    domain: _pinnedDomain(card.kind),
    shape: card.kind == EntityCardKind.artist
        ? ArtworkShape.circle
        : ArtworkShape.square,
    semanticsId: semanticsId,
  );
}

// Playlists.

/// Whose playlist this is, where that is not the person looking. Null on
/// your own, where it would be a column of noise.
String? _playlistByline(AppLocalizations l10n, Playlist playlist) {
  if (playlist.isOwner) {
    return playlist.isShared ? l10n.playlistSharedByYou : null;
  }
  return l10n.playlistSharedBy(playlist.ownerName);
}

/// How much is in a playlist. A smart list's count is omitted from list
/// pages, so its card carries no number rather than a wrong one.
String? _playlistSize(AppLocalizations l10n, Playlist playlist) {
  final count = playlist.itemCount;
  return count == null ? null : l10n.playlistItemCount(count);
}

/// A playlist card; a smart list is badged, since it evaluates itself.
MediaTileData playlistTile(
  Playlist playlist, {
  required AppLocalizations l10n,
  required ArtworkStore store,
  required String semanticsId,
}) => MediaTileData(
  title: playlist.name,
  subtitle: _playlistByline(l10n, playlist),
  trailingText: _playlistSize(l10n, playlist),
  artwork: waxArtwork(store, playlist.artUrl),
  badge: playlist.isSmart ? l10n.playlistSmart : null,
  semanticsId: semanticsId,
);

// Podcasts.

/// What the row says about [episode] under its title: its number, and
/// where its audio stands.
String _episodeFacts(AppLocalizations l10n, EpisodeSummary episode) {
  final facts = <String>[
    if (episode.season != null && episode.episodeNumber != null)
      l10n.podcastSeasonEpisode(episode.season!, episode.episodeNumber!)
    else if (episode.episodeNumber != null)
      l10n.podcastEpisodeNumber(episode.episodeNumber!),
    if (episode.explicit) l10n.podcastExplicit,
    ?_audioFact(l10n, episode),
  ];
  return facts.join(' · ');
}

String? _audioFact(AppLocalizations l10n, EpisodeSummary episode) {
  final fetch = episodeFetchOf(episode);
  if (episodeFetchFact(l10n, fetch) case final fact?) return fact;
  // Said on the row rather than left to the tap: an episode this server
  // holds no bytes for still plays, relayed from the feed's own host,
  // unless the listing says there is no audio to relay. It does not say
  // why (no enclosure, a playlist, a YouTube watch page), so the words
  // hold for every cause.
  if (!episode.downloaded && !episode.hasEnclosure) {
    return l10n.podcastNoAudioToStream;
  }
  return null;
}

/// "42m left", in the span every episode surface spells a duration with.
String _episodeTimeLeft(AppLocalizations l10n, int leftMs) =>
    l10n.podcastTimeLeft(l10n.formatListenTime(leftMs));

/// One episode in a list: the show's own, or the hub's latest. A
/// [subtitle] replaces the number and explicit facts (empty says none);
/// where the audio stands is still said after it.
MediaTileData episodeRowTile(
  EpisodeSummary episode, {
  required AppLocalizations l10n,
  required PlayProgress progress,
  required String semanticsId,
  String? subtitle,
  WaxArtwork? artwork,
}) {
  final remaining = episode.durationMs - progress.positionMs;
  final trailing = progress.inProgress && remaining > 0
      ? _episodeTimeLeft(l10n, remaining)
      : episode.durationMs > 0
      ? l10n.formatListenTime(episode.durationMs)
      : null;
  final facts = subtitle == null
      ? _episodeFacts(l10n, episode)
      : [
          subtitle,
          _audioFact(l10n, episode),
        ].nonNulls.where((fact) => fact.isNotEmpty).join(' · ');
  return MediaTileData(
    title: episode.title,
    subtitle: facts.isEmpty ? null : facts,
    artwork: artwork,
    domain: WaxDomain.podcasts,
    progress: progress.fractionOf(episode.durationMs),
    trailingText: trailing,
    downloaded: episode.downloaded,
    unplayed: !progress.played && progress.positionMs == 0,
    semanticsId: semanticsId,
  );
}

/// What every shelf episode draws: its title, its show, its cover and its
/// stored mark.
MediaTileData _shelfEpisodeTile(
  ShelfEpisode row, {
  required ArtworkStore store,
  required String semanticsId,
  String? tooltip,
  bool unplayed = false,
  double? progress,
  String? trailingText,
}) => MediaTileData(
  title: row.episode.title,
  subtitle: row.showTitle,
  tooltip: tooltip,
  artwork: waxArtwork(store, row.episode.artUrl),
  domain: WaxDomain.podcasts,
  progress: progress,
  trailingText: trailingText,
  downloaded: row.episode.downloaded,
  unplayed: unplayed,
  semanticsId: semanticsId,
);

/// A fresh episode on the new-episodes shelf: unplayed by construction.
MediaTileData episodeShelfTile(
  ShelfEpisode row, {
  required ArtworkStore store,
  required String semanticsId,
}) => _shelfEpisodeTile(
  row,
  store: store,
  semanticsId: semanticsId,
  // The card clamps every line, so the full name lives on the hover
  // tooltip, as the item shelves' cards do.
  tooltip: <String?>[row.episode.title, row.showTitle].nonNulls.join('\n'),
  unplayed: true,
);

String? _episodeRemaining(AppLocalizations l10n, ShelfEpisode row) {
  final left = row.episode.durationMs - row.progress.positionMs;
  if (left <= 0) return null;
  return _episodeTimeLeft(l10n, left);
}

/// A half-heard episode on the up-next shelf, with the time left.
MediaTileData episodeContinueTile(
  ShelfEpisode row, {
  required AppLocalizations l10n,
  required ArtworkStore store,
  required String semanticsId,
}) => _shelfEpisodeTile(
  row,
  store: store,
  semanticsId: semanticsId,
  progress: row.progress.fractionOf(row.episode.durationMs),
  trailingText: _episodeRemaining(l10n, row),
);

/// A followed show.
MediaTileData showTile(
  Subscription subscription, {
  required AppLocalizations l10n,
  required ArtworkStore store,
  required String semanticsId,
}) {
  final show = subscription.show;
  final unplayed = subscription.unplayedCount;
  final count = show.episodeCount;
  return MediaTileData(
    title: show.title,
    subtitle: show.author,
    artwork: waxArtwork(store, show.artUrl),
    domain: WaxDomain.podcasts,
    // What is waiting, which is the number a listener opens a show for.
    // The episode count is the fallback for a server that predates the
    // field, and for a show with nothing waiting.
    trailingText: switch ((unplayed, count)) {
      (final int n, _) when n > 0 => l10n.podcastUnplayedCount(n),
      (_, final int n) => l10n.podcastEpisodeCount(n),
      _ => null,
    },
    unplayed: (unplayed ?? 0) > 0,
    semanticsId: semanticsId,
  );
}

// Downloads.

/// What every stored item draws: its title, its artist and its cover on
/// the hue of its medium. A row the catalog no longer knows reads its pid
/// and draws a monogram.
MediaTileData _downloadTile(
  DownloadEntry entry, {
  required ArtworkStore store,
  required String semanticsId,
  String? tooltip,
  bool downloaded = false,
  bool unplayed = false,
  double? progress,
  String? trailingText,
  String? trailingDetail,
  String? trailingDetailSpoken,
}) => MediaTileData(
  title: entry.title,
  subtitle: entry.subtitle,
  tooltip: tooltip,
  artwork: waxArtwork(store, entry.item?.artUrl),
  domain: waxDomainOf(entry.mediaType),
  shape: waxShapeOf(entry.mediaType),
  progress: progress,
  trailingText: trailingText,
  trailingDetail: trailingDetail,
  trailingDetailSpoken: trailingDetailSpoken,
  downloaded: downloaded,
  unplayed: unplayed,
  semanticsId: semanticsId,
);

/// An entry on home's downloaded shelf.
MediaTileData downloadShelfTile(
  DownloadEntry entry, {
  required ArtworkStore store,
  required String semanticsId,
}) => _downloadTile(
  entry,
  store: store,
  // The card clamps every line, so the full name lives on the hover
  // tooltip, as on every other home shelf.
  tooltip: <String?>[entry.title, entry.subtitle].nonNulls.join('\n'),
  downloaded: true,
  semanticsId: semanticsId,
);

/// A transfer in flight. [progress] is the live fraction of the file, and
/// the detail column is the caller's: it says why a transfer is held.
MediaTileData downloadTransferTile(
  DownloadEntry entry, {
  required AppLocalizations l10n,
  required ArtworkStore store,
  required double? progress,
  required String semanticsId,
  String? trailingDetail,
  String? trailingDetailSpoken,
}) => _downloadTile(
  entry,
  store: store,
  // The progress bar under the row, which is the sliver MediaListRow
  // already draws for a resume position.
  progress: progress,
  trailingText: l10n.formatBytes(entry.record.sizeBytes),
  trailingDetail: trailingDetail,
  trailingDetailSpoken: trailingDetailSpoken,
  semanticsId: semanticsId,
);

double? _playedFraction(PlayState? progress, int? durationMs) {
  final position = progress?.positionMs ?? 0;
  if (position <= 0 || durationMs == null || durationMs <= 0) return null;
  return (position / durationMs).clamp(0.0, 1.0);
}

/// A stored item in the downloads manager's groups.
MediaTileData downloadRowTile(
  DownloadEntry entry, {
  required AppLocalizations l10n,
  required ArtworkStore store,
  required String semanticsId,
}) => _downloadTile(
  entry,
  store: store,
  downloaded: true,
  // Played state as the row already draws it: a dot for never-heard, a
  // sliver for part way through.
  unplayed: (entry.progress?.positionMs ?? 0) == 0,
  progress: entry.finished
      ? null
      : _playedFraction(entry.progress, entry.item?.durationMs),
  trailingText: l10n.formatBytes(entry.record.sizeBytes),
  semanticsId: semanticsId,
);

// Radio.

/// What a saved-song row says under its title: who it is by where the line
/// split, where it was heard, and whether the hunt is over. In the
/// subtitle rather than the trailing slot, which is unclipped and reserved
/// for a timecode - a caption of this length there pushes the row's own
/// controls off the end of it.
String _savedSongCaption(AppLocalizations l10n, RadioSavedSong song) =>
    <String>[
      if (song.artist != null) song.artist!,
      song.stationName,
      if (song.inLibraryPid != null) l10n.radioSavedInLibrary,
    ].join(' · ');

/// A song saved off a station.
MediaTileData savedSongTile(
  RadioSavedSong song, {
  required AppLocalizations l10n,
  required ArtworkStore store,
  required MediaUrlsApi repository,
  required String semanticsId,
}) => MediaTileData(
  // The announced line is what the listener saw, so it is what the row
  // leads with when nothing parsed out of it.
  title: song.title ?? song.nowPlaying,
  subtitle: _savedSongCaption(l10n, song),
  // The snapshot taken when the heart was tapped, or the monogram - which
  // is the ordinary state rather than a loading one, since most
  // announcements have no cover on any rung.
  artwork: song.hasArt
      ? waxArtwork(store, repository.radioSavedArtUrlFor(song.pid))
      : null,
  domain: WaxDomain.radio,
  semanticsId: semanticsId,
);

/// A station card. The caller owns the line under the name, because the
/// pinned row beside it draws the same line from a different shape.
MediaTileData stationTile(
  RadioStation station, {
  required String? subtitle,
  required WaxArtwork? artwork,
  required String semanticsId,
}) => MediaTileData(
  title: station.name,
  subtitle: subtitle,
  artwork: artwork,
  domain: WaxDomain.radio,
  shape: ArtworkShape.circle,
  semanticsId: semanticsId,
);

// Search.

/// A recent query, drawn as a row that runs it again.
MediaTileData recentSearchTile(String query, {required String semanticsId}) =>
    MediaTileData(title: query, semanticsId: semanticsId);

/// A hit in the group [kind]; an artist reads as a disc, and a track
/// carries its [playCount].
MediaTileData searchHitTile(
  SearchHit hit,
  SearchHitKind kind, {
  required AppLocalizations l10n,
  required String semanticsId,
  int? playCount,
}) {
  final plays = kind == SearchHitKind.tracks
      ? _plays(MediaType.music, playCount, l10n, null)
      : null;
  return MediaTileData(
    title: hit.title,
    subtitle: hit.subtitle,
    shape: kind == SearchHitKind.artists
        ? ArtworkShape.circle
        : ArtworkShape.square,
    domain: switch (kind) {
      SearchHitKind.episodes => WaxDomain.podcasts,
      SearchHitKind.books => WaxDomain.audiobooks,
      _ => WaxDomain.music,
    },
    playCount: plays?.count,
    playCountLabel: plays?.label,
    semanticsId: semanticsId,
  );
}

// Stats.

/// One recorded listen.
MediaTileData listenLogTile(
  ListenLogEntry entry, {
  required AppLocalizations l10n,
}) {
  final played = l10n.formatListenTime(entry.msPlayed);
  final details = <String>[
    ?entry.artist,
    // Skipped when empty, the way the filter above skips it: a radio row
    // is measured by the server and names no client, and joining an empty
    // string in leads the subtitle with a bare separator.
    if (entry.client.isNotEmpty) entry.client,
    l10n.formatStamp(entry.startedAt),
  ];
  return MediaTileData(
    // A session outlives the item it was about: a track deleted since is
    // still a listen that happened.
    title: entry.title ?? l10n.statsLogRemovedItem,
    subtitle: details.join(' · '),
    domain: waxDomainOfStats(entry.mediaType),
    shape: waxShapeOfStats(entry.mediaType),
    trailingText: played,
    // The tick is the whole of what "finished" means here, and the row
    // reads it out rather than leaving it to a glyph.
    trailingSpoken: entry.finished
        ? l10n.statsLogFinishedSpoken(played)
        : played,
    badge: entry.finished ? l10n.statsLogFinished : null,
  );
}

WaxDomain _topDomain(String kind) => switch (kind) {
  'shows' => WaxDomain.podcasts,
  'stations' => WaxDomain.radio,
  _ => WaxDomain.music,
};

/// A ranked row of a top list of [kind].
MediaTileData topEntryTile(
  TopEntry entry,
  String kind, {
  required AppLocalizations l10n,
  required ArtworkStore store,
  required String semanticsId,
}) => MediaTileData(
  // An entry outlives the thing it counted: a track deleted since, a
  // station taken out of the library. The time it holds is real and stays
  // in the ranking, so it needs a name to stand under - the same one the
  // listen log gives a row in the same state, rather than a blank line
  // where a title goes.
  title: entry.name.isEmpty ? l10n.statsLogRemovedItem : entry.name,
  subtitle: l10n.statsPlays(entry.plays),
  artwork: waxArtwork(store, entry.artUrl),
  domain: _topDomain(kind),
  // An artist reads as a disc, the way every other artist row in the app
  // does; an album and a show are square by nature.
  shape: kind == 'artists' || kind == 'genres'
      ? ArtworkShape.circle
      : ArtworkShape.square,
  trailingText: l10n.formatListenTime(entry.ms),
  semanticsId: semanticsId,
);
