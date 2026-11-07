import '../models.dart';

/// URLs and requests built locally, never sent through the generated client.
abstract interface class MediaUrlsApi {
  /// The artwork endpoint for [pid], resolved the way an [ItemSummary]'s
  /// own `artUrl` is. For callers with a pid and no row: a facet bucket
  /// carries an entity pid, which this endpoint serves too.
  ///
  /// Only the default `front` [role] walks the album/artist chain; the
  /// rest 404 unless the entity holds that slot itself.
  String artUrlFor(String pid, {String? role});

  /// The logo endpoint for the station at [pid], resolved the way
  /// [artUrlFor] resolves a cover.
  ///
  /// A station's `logoUrl` is the station host's own URL and is not what
  /// a client draws: on web it has no CORS headers to offer and an http
  /// logo is mixed content on an https UI, so the server fetches it and
  /// serves it from this origin. `logoUrl` being present is the signal
  /// there is anything to ask for.
  String radioLogoUrlFor(String pid);

  /// The origin-relative URL for the cover held under [key], the second
  /// artwork rung. [key] is [RadioPlayInfo.nowPlayingArtKey], and it is
  /// what makes this URL change when the station changes what it is
  /// playing - one URL per station would draw the first matched track's
  /// cover for the rest of the session, out of the image cache, however
  /// many songs went by. Ask only when the key is present: the endpoint
  /// 404s otherwise, and that keeps a face from asking on every poll of
  /// a station whose titles never resolve.
  String radioNowPlayingArtUrlFor(String pid, String key);

  /// The snapshot cover for the saved song at [pid], resolved the way
  /// [artUrlFor] resolves a cover. Ask only when
  /// [RadioSavedSong.hasArt]: the endpoint 404s otherwise, and a row
  /// with no cover is the ordinary case rather than a failure.
  String radioSavedArtUrlFor(String pid);

  /// URL of `GET /admin/backups/{backupId}/archive`, for opening in a
  /// browser or handing to a download manager; the bytes are never
  /// pulled through this client.
  String backupArchiveUrl(String backupId);

  /// The two requests a client that is about to stop existing has to
  /// get out, already addressed, encoded, and carrying whatever
  /// authenticates a mutation here.
  ///
  /// Built rather than sent, because the caller is a browser tab in
  /// `pagehide` and nothing this layer could await would survive the
  /// document. The web build hands these to `fetch(keepalive: true)`;
  /// every other platform has a close handler and never asks.
  ///
  /// [listen] is the session's own listen report, sent only when the
  /// client is really ending - a tab merely going hidden checkpoints
  /// and nothing else. [timelinePids] releases the gapless renderings
  /// the tab was holding, for the same reason: a closed tab is the one
  /// listener that cannot say it stopped. Plural because a queue edit
  /// mints a replacement beside the one playing and the server counts
  /// the listener as being on both - releasing one of them leaves the
  /// other holding the slot, and the release then frees nothing.
  ///
  /// Every part is optional and each stands alone. A tab can have a
  /// rendering to hand back and nothing to check point - the session
  /// already reported, or the item went away while the stream played on
  /// - and that release is the one that costs a listener their slot for
  /// a minute if it does not go out.
  List<ExitRequest> exitRequests({
    String? pid,
    int? positionMs,
    ListenSession? listen,
    List<String> timelinePids = const <String>[],
  });
}
