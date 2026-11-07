import 'package:waxdeck_api/waxdeck_api.dart';

/// Handy device-session factory for tests.
DeviceSession testSession(
  String id, {
  SessionKind kind = SessionKind.device,
  String? deviceName = 'Study desktop',
  String? client,
  bool current = false,
}) => DeviceSession(
  id: id,
  kind: kind,
  deviceName: deviceName,
  client: client,
  createdAt: DateTime.utc(2026, 7, 1, 8),
  current: current,
);

/// Handy summary factory for tests.
ItemSummary testItem(
  String pid, {
  MediaType mediaType = MediaType.music,
  String title = 'Prancing Pony Blues',
  String? artist = 'The Bree Trio',
  int durationMs = 214000,
  int? trackNumber,
  int? discNumber,
  String? sortKey,
  String? artistSort,
  String? artistSortKey,
}) => ItemSummary(
  pid: pid,
  mediaType: mediaType,
  title: title,
  artist: artist,
  durationMs: durationMs,
  trackNumber: trackNumber,
  discNumber: discNumber,
  sortKey: sortKey,
  artistSort: artistSort,
  artistSortKey: artistSortKey,
);

/// Handy show factory for tests.
PodcastShow testShow(
  String pid, {
  String title = 'The Prancing Pony Hour',
  String? author = 'Barliman Butterbur',
  String? feedUrl = 'https://pony.example/feed.xml',
  String? descriptionHtml,
  bool explicit = false,
  int? episodeCount,
  PodcastFunding? funding,
}) => PodcastShow(
  pid: pid,
  funding: funding,
  title: title,
  author: author,
  feedUrl: feedUrl,
  descriptionHtml: descriptionHtml,
  sourceType: 'rss',
  explicit: explicit,
  episodeCount: episodeCount,
);

/// Handy episode factory for tests.
///
/// [hasEnclosure] defaults true because that is the ordinary feed: an
/// episode whose feed named audio, which this server can relay whether or
/// not it has fetched it. The false case is the one episode that cannot
/// play at all, and a test about it says so.
EpisodeSummary testEpisode(
  String pid, {
  String showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01',
  String title = 'Pipeweed Economics',
  String? artist = 'Barliman Butterbur',
  int durationMs = 214000,
  DateTime? publishedAt,
  bool downloaded = true,
  String? fetchState,
  String? fetchError,
  String? sortKey,
  bool hasTranscript = false,
  bool explicit = false,
  bool hasEnclosure = true,
  int? season,
  int? episodeNumber,
}) => EpisodeSummary(
  pid: pid,
  mediaType: MediaType.podcast,
  title: title,
  artist: artist,
  durationMs: durationMs,
  sortKey: sortKey,
  showPid: showPid,
  season: season,
  episodeNumber: episodeNumber,
  publishedAt: publishedAt ?? DateTime.utc(2026, 7, 10, 6),
  downloaded: downloaded,
  fetchState: fetchState,
  fetchError: fetchError,
  hasTranscript: hasTranscript,
  explicit: explicit,
  hasEnclosure: hasEnclosure,
);

/// Handy review-entry factory for tests.
ReviewEntry testReviewEntry(
  String id, {
  String kind = 'match',
  String status = 'pending',
  MediaType mediaType = MediaType.music,
  String origin = 'scan',
  String? title = 'Neon Meridian',
  String? artist = 'The Cardinal Waves',
  int trackCount = 10,
  String? uploadedBy,
  bool identifying = false,
  CandidateSummary? best,
  int duplicateCount = 0,
}) => ReviewEntry(
  id: id,
  kind: kind,
  status: status,
  mediaType: mediaType,
  origin: origin,
  title: title,
  artist: artist,
  trackCount: trackCount,
  uploadedBy: uploadedBy,
  identifying: identifying,
  best: best,
  createdAt: DateTime.utc(2026, 7, 1),
  duplicateCount: duplicateCount,
);

/// Handy upload-session factory for tests. [idle] defaults to a day: a
/// row built by hand is an old one nobody is sending any more.
UploadSession testUpload(
  String id, {
  String fileName = 'neon-meridian.flac',
  int sizeBytes = 4194304,
  int receivedBytes = 0,
  MediaType mediaType = MediaType.music,
  String? batchId,
  String state = 'receiving',
  String? reviewEntryId,
  DuplicateWarning? duplicate,
  String? uploadedBy,
  Duration idle = const Duration(days: 1),
}) => UploadSession(
  id: id,
  fileName: fileName,
  sizeBytes: sizeBytes,
  receivedBytes: receivedBytes,
  idle: idle,
  mediaType: mediaType,
  batchId: batchId,
  state: state,
  reviewEntryId: reviewEntryId,
  duplicate: duplicate,
  uploadedBy: uploadedBy,
  createdAt: DateTime.utc(2026, 7, 1),
);

/// A signed-in session whose user holds effective upload rights, for
/// screens gating their upload affordances.
SessionState testUploaderSession({List<String> roles = const ['user']}) =>
    SessionState(
      authenticated: true,
      user: WaxDeckUser(
        id: 'us-uploader',
        username: 'uploader',
        roles: roles,
        uploadEnabled: true,
      ),
    );

/// A signed-in session whose user holds no rights: not an administrator,
/// no upload, delete or podcast-curation right. For tests that a listener
/// is refused something, since no session at all hides the same controls.
SessionState testListenerSession() => const SessionState(
  authenticated: true,
  user: WaxDeckUser(id: 'us-listener', username: 'listener', roles: ['user']),
);

/// Handy audiobook factory for tests. With [partCount] above one the
/// book splits into equal parts of [durationMs] / [partCount] each.
BookDetail testBook(
  String pid, {
  String title = 'There And Back Again',
  List<String> authors = const ['B. Baggins'],
  List<String> narrators = const ['Frodo'],
  int durationMs = 3600000,
  int partCount = 1,
  List<ChapterMark>? chapters,
  BookSettings? settings,
  String? descriptionHtml,
  String? subtitle,
  String? series,
  String? seriesPid,
  String? seriesSequence,
  String? authorPid,
  String? artUrl,
  String? publisher,
  String? isbn,
  String? asin,
  String? edition,
  bool? abridged,
}) {
  final partMs = durationMs ~/ partCount;
  return BookDetail(
    pid: pid,
    title: title,
    subtitle: subtitle,
    authors: authors,
    narrators: narrators,
    series: series,
    seriesPid: seriesPid,
    seriesSequence: seriesSequence,
    authorPid: authorPid,
    artUrl: artUrl,
    publisher: publisher,
    isbn: isbn,
    asin: asin,
    edition: edition,
    abridged: abridged,
    durationMs: durationMs,
    descriptionHtml: descriptionHtml,
    chapters: chapters ?? const [],
    parts: [
      for (var i = 0; i < partCount; i++)
        BookPart(index: i, startMs: i * partMs, durationMs: partMs),
    ],
    settings: settings,
  );
}
