import '../models.dart';

/// Play state, stars and ratings, listen reports and playback info.
abstract interface class PlaybackApi {
  /// `GET /items/{pid}/play-info`: short-TTL stream resolution. The returned
  /// URL is already resolved against the client base URL. [positionMs] is
  /// on the item's timeline (the book timeline for a multi-file audiobook,
  /// where it selects the part holding it); a stream that cannot be
  /// range-seeked is cut to begin there, reported as
  /// [PlayInfo.startOffsetMs], while a seekable one is left for the player
  /// to seek. [voiceBoost] requests server-side loudness normalization,
  /// overriding the caller's stored setting when present.
  /// [maxBitrateKbps] caps the stream's bitrate (32-320): a lossy source
  /// already inside the cap streams unchanged, anything else re-encodes
  /// down to it and reports the applied cap on the result. [hls] says the
  /// player plays HLS: a re-encode then comes back as the item's own HLS
  /// presentation, seekable, where the server renders one.
  Future<PlayInfo> getPlayInfo(
    String pid, {
    int? positionMs,
    bool? voiceBoost,
    int? maxBitrateKbps,
    bool? hls,
  });

  /// `GET /items/{pid}/play-state`: the caller's resume state for one item.
  Future<PlayState> getPlayState(String pid);

  /// `POST /play-states`: the caller's states for a batch of items (at
  /// most 500). Items with zero state are absent from the result.
  Future<List<PlayState>> listPlayStates(List<String> pids);

  /// `PUT /items/{pid}/play-state`: checkpoints the resume position.
  /// [recordedAt] marks an offline-queue replay; the server reconciles
  /// it per medium instead of applying it blindly.
  Future<void> putPlayState(String pid, int positionMs, {DateTime? recordedAt});

  /// `PUT /items/{pid}/played`: sets an item's played and finished flags
  /// directly, returning the updated play state. The completion rules
  /// only ever mark, so this is how a mis-tapped "mark finished" is
  /// undone. [playCount] is three-way: null keeps the stored count, 0
  /// clears it, and a positive value sets it exactly. [recordedAt] marks
  /// an offline-queue replay; an interactive un-mark leaves it null so a
  /// client clock trailing the server cannot drop the write as stale.
  ///
  /// [positionMs] restores the resume position in the same write, which
  /// is what makes an undo atomic against a completion checkpoint from
  /// another device. Null leaves the position alone. A server too old
  /// for the field ignores it and answers with the position it kept, so
  /// a caller that needs it compares the returned state and falls back
  /// to [putPlayState].
  Future<PlayState> setPlayed(
    String pid, {
    required bool played,
    required bool finished,
    int? playCount,
    int? positionMs,
    DateTime? recordedAt,
  });

  /// `PUT /items/{pid}/star`: stars or unstars one item, returning the
  /// updated play state. [recordedAt] marks an offline-queue replay.
  Future<PlayState> setStar(String pid, bool starred, {DateTime? recordedAt});

  /// `PUT /items/{pid}/rating`: rates one item, 0 to 100, or clears the
  /// rating with null. Returns the updated play state. [recordedAt]
  /// marks an offline-queue replay.
  Future<PlayState> setRating(String pid, int? rating, {DateTime? recordedAt});

  /// `GET /artists/{pid}/play-state` or `GET /albums/{pid}/play-state`:
  /// the caller's star and rating for one catalog entity, selected by
  /// the pid's own prefix. An untouched entity reads back zero.
  Future<EntityPlayState> getEntityPlayState(String pid);

  /// `PUT /artists/{pid}/star` or `PUT /albums/{pid}/star`: stars or
  /// unstars one catalog entity, returning its updated state. Entity
  /// stars are independent of item stars: starring an album does not
  /// star its tracks. [recordedAt] marks an offline-queue replay.
  Future<EntityPlayState> setEntityStar(
    String pid,
    bool starred, {
    DateTime? recordedAt,
  });

  /// `PUT /artists/{pid}/rating` or `PUT /albums/{pid}/rating`: rates
  /// one catalog entity, 0 to 100, or clears the rating with null.
  /// [recordedAt] marks an offline-queue replay.
  Future<EntityPlayState> setEntityRating(
    String pid,
    int? rating, {
    DateTime? recordedAt,
  });

  /// `GET /starred-entities`: the caller's starred artists and albums.
  Future<StarredEntities> listStarredEntities();

  /// `POST /listens`: reports listen sessions. Idempotent per session ID, so
  /// retrying a failed batch is always safe.
  Future<ListenOutcome> reportListens(List<ListenSession> sessions);

  /// `GET /items/{pid}/download-info`: resolves an offline download of
  /// the item's original bytes. URLs are resolved against the client
  /// base URL.
  Future<DownloadInfo> getDownloadInfo(String pid);

  /// `GET /items/{pid}/skip-map`: precomputed silence spans for
  /// client-side trimming; [partIndex] selects one part of a multi-file
  /// audiobook, with spans in that part's own timeline.
  Future<SkipMap> getSkipMap(String pid, {int? partIndex});

  /// `GET /items/{pid}/waveform`: the item's amplitude envelope, or the
  /// state saying there is not one to draw. A pure read of what the
  /// analyze pass stored; nothing is computed or queued by asking.
  ///
  /// [wholeItem] asks for one envelope across a multi-file audiobook's
  /// whole timeline instead of a single part's, which is what a book
  /// scrubber draws; it changes nothing for anything with one file.
  Future<Waveform> getWaveform(String pid, {bool wholeItem});
}
