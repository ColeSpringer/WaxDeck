import '../models.dart';

/// Queue timelines, playback sessions and cast endpoints.
abstract interface class PlayerApi {
  /// `POST /player/timeline`: mints one gapless HLS stream over a whole
  /// queue, in play order. [crossfadeSeconds] shapes the seams and the
  /// returned member offsets alike; [formats] names what the caller can
  /// decode, most preferred first, and the answer says what was
  /// actually rendered.
  ///
  /// Throws `timeline-measuring` (202) while member lengths are still
  /// being measured: its `params['job']` is the job to poll, after
  /// which the same request answers immediately.
  Future<QueueTimeline> createQueueTimeline(
    List<String> pids, {
    double? crossfadeSeconds,
    List<String>? formats,
  });

  /// `DELETE /player/timeline/{pid}`: gives back the transcode slot this
  /// rendering was holding, for a player that has stopped. Best effort:
  /// the server's idle sweep releases it anyway a minute later, so a
  /// failure here is not worth surfacing or retrying.
  Future<void> releaseQueueTimeline(String pid);

  /// `GET /player/endpoints`: outputs the caller can play to.
  Future<List<PlayerEndpoint>> listPlayerEndpoints();

  /// `GET /player/sessions`: visible active playback sessions.
  Future<List<PlaybackSessionInfo>> listPlaybackSessions();

  /// `GET /player/sessions/history`: the caller's ended sessions, newest
  /// first, each carrying the whole queue it stopped on. This is the
  /// resume surface: putting one back is an ordinary
  /// [createPlaybackSession] (or a local queue) from its entries, index,
  /// and position. Short and unpaged by design - the server keeps a few
  /// per user - and never includes anything still playing.
  Future<List<PlaybackSessionHistoryEntry>> listPlaybackSessionHistory();

  /// `POST /player/sessions`: start playback on an endpoint.
  ///
  /// [rate], [repeat], and [shuffle] are the modes the queue travels
  /// with, so a handoff arrives playing the way it was playing.
  /// [handoffFrom] names a client endpoint of the caller's whose
  /// session this create replaces - what a client that never learned
  /// its own mirror session id passes instead of transferring.
  Future<PlaybackSessionInfo> createPlaybackSession({
    required String endpointId,
    required List<String> itemPids,
    int index = 0,
    int positionMs = 0,
    bool play = true,
    double? rate,
    String? repeat,
    bool? shuffle,
    String? handoffFrom,
  });

  /// `GET /player/sessions/{sessionId}`: one session snapshot.
  Future<PlaybackSessionInfo> getPlaybackSession(String sessionId);

  /// `DELETE /player/sessions/{sessionId}`: end a session.
  Future<void> deletePlaybackSession(String sessionId);

  /// `POST /player/sessions/{sessionId}/transfer`: move live playback
  /// to another endpoint, keeping queue and position.
  Future<PlaybackSessionInfo> transferPlaybackSession(
    String sessionId,
    String endpointId,
  );

  /// `GET /player/cast/preflight`: the advertise bases a cast session
  /// will offer a device, in try order, each with the server's own
  /// reachability verdict and plain-language notes. A base unreachable
  /// here reliably predicts a silent cast failure; a reachable one is
  /// not a promise, because the device's view of the network is not the
  /// server's.
  Future<List<CastPreflightBase>> getCastPreflight();

  /// `POST /player/cast/preflight/{endpointId}`: the device half of the
  /// same check. A second of silence is loaded onto a cast device or a
  /// renderer from each advertise base in turn, and each row carries
  /// what the device did with it beside the server's own verdict.
  ///
  /// It drives a physical output, so it refuses rather than interrupts:
  /// `endpoint-busy` names what is playing, on the device or in WaxDeck.
  Future<CastDeviceProbe> probeCastEndpoint(String endpointId);
}
