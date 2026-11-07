import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// In-memory [PlayerApi] for `FakeRepository`.
mixin FakePlayer on FakeRepositoryState implements PlayerApi {
  final List<
    ({
      String endpointId,
      List<String> itemPids,
      int index,
      int positionMs,
      double? rate,
      String? repeat,
      bool? shuffle,
      String? handoffFrom,
    })
  >
  createPlaybackSessionCalls = [];
  final List<({String sessionId, String endpointId})>
  transferPlaybackSessionCalls = [];
  final List<String> deletePlaybackSessionCalls = [];
  List<PlayerEndpoint> playerEndpoints = [];
  List<PlaybackSessionInfo> playbackSessions = [];

  @override
  Future<QueueTimeline> createQueueTimeline(
    List<String> pids, {
    double? crossfadeSeconds,
    List<String>? formats,
  }) async {
    timelineCalls.add((
      pids: pids,
      crossfadeSeconds: crossfadeSeconds,
      formats: formats,
    ));
    final error = timelineError;
    if (error != null) throw error;
    final made = timelines?.call(pids);
    if (made != null) return made;
    // One member per pid, tiling exactly at 48 kHz: the shape a queue of
    // whole tracks mints, so a test that only cares that a timeline
    // exists does not have to build one.
    var offset = 0;
    final members = <QueueTimelineMember>[];
    for (final pid in pids) {
      final ms = libraryItems
          .where((i) => i.pid == pid)
          .map((i) => i.durationMs)
          .firstOrNull;
      final samples = ((ms ?? 214000) * 48000) ~/ 1000;
      members.add(
        QueueTimelineMember(
          pid: pid,
          offsetSamples: offset,
          durationSamples: samples,
        ),
      );
      offset += samples;
    }
    return QueueTimeline(
      // One pid per rendering, so a test can tell which mint a release
      // was for.
      pid: 'tl-fake${timelineCalls.length}',
      // A fresh token per mint, the way the real one signs one: a
      // re-mint that answered the same URL byte for byte let every
      // engine take its "already loaded, just seek" path, so the reload
      // a lost timeline actually performs went untested.
      url:
          '/media/hls/master.m3u8?tl=${pids.join('.')}'
          '&rk=${formats?.firstOrNull ?? 'aac'}&mt=test-token-${timelineCalls.length}',
      mimeType: 'application/vnd.apple.mpegurl',
      durationMs: offset * 1000 ~/ 48000,
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 30)),
      envelopeRate: 48000,
      crossfadeSeconds: crossfadeSeconds,
      format: formats?.firstOrNull ?? 'aac',
      members: members,
    );
  }

  /// Every timeline mint, in order.
  final List<
    ({List<String> pids, double? crossfadeSeconds, List<String>? formats})
  >
  timelineCalls = [];

  /// Every timeline release, in order.
  final List<String> timelineReleases = [];

  @override
  Future<void> releaseQueueTimeline(String pid) async {
    timelineReleases.add(pid);
  }

  /// Thrown by [createQueueTimeline] when set; a
  /// `WaxDeckApiException(code: 'feature-unavailable', statusCode: 501)`
  /// is the server with no streaming engine.
  Object? timelineError;

  /// Overrides what [createQueueTimeline] answers, for a test that needs
  /// particular seams. Null falls back to one member per pid.
  QueueTimeline? Function(List<String> pids)? timelines;

  @override
  Future<List<PlayerEndpoint>> listPlayerEndpoints() async {
    return List.of(playerEndpoints);
  }

  @override
  Future<List<PlaybackSessionInfo>> listPlaybackSessions() async {
    return List.of(playbackSessions);
  }

  /// The caller's ended sessions, newest first. Empty by default, which
  /// is what a launch with nothing to resume looks like.
  List<PlaybackSessionHistoryEntry> sessionHistory = [];

  /// Thrown by [listPlaybackSessionHistory] when set: a launch offline,
  /// or against a server too old to serve the surface at all.
  Object? sessionHistoryError;

  @override
  Future<List<PlaybackSessionHistoryEntry>> listPlaybackSessionHistory() async {
    final error = sessionHistoryError;
    if (error != null) throw error;
    return List.of(sessionHistory);
  }

  /// Thrown by [createPlaybackSession] when set, for the refusals a
  /// picker has to explain (a windowed track sent to a cast device).
  WaxDeckApiException? createSessionError;

  @override
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
  }) async {
    final error = createSessionError;
    if (error != null) throw error;
    createPlaybackSessionCalls.add((
      endpointId: endpointId,
      itemPids: itemPids,
      index: index,
      positionMs: positionMs,
      rate: rate,
      repeat: repeat,
      shuffle: shuffle,
      handoffFrom: handoffFrom,
    ));
    return PlaybackSessionInfo(
      id: 'ps-created',
      endpointId: endpointId,
      mine: true,
      authority: 'remote',
      playing: play,
      index: index,
      positionMs: positionMs,
      positionAt: DateTime.now().toUtc(),
      rate: rate ?? 1,
      repeat: repeat,
      shuffle: shuffle ?? false,
      queueVersion: 1,
      entries: [
        for (final pid in itemPids) PlaybackSessionEntry(pid: pid, title: pid),
      ],
    );
  }

  @override
  Future<PlaybackSessionInfo> getPlaybackSession(String sessionId) async {
    final match = playbackSessions.where((s) => s.id == sessionId);
    if (match.isEmpty) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such session',
        statusCode: 404,
      );
    }
    return match.first;
  }

  @override
  Future<void> deletePlaybackSession(String sessionId) async {
    deletePlaybackSessionCalls.add(sessionId);
  }

  /// Thrown by [transferPlaybackSession] when set. `not-found` is the
  /// one the picker treats as "start a fresh session instead".
  WaxDeckApiException? transferSessionError;

  @override
  Future<PlaybackSessionInfo> transferPlaybackSession(
    String sessionId,
    String endpointId,
  ) async {
    transferPlaybackSessionCalls.add((
      sessionId: sessionId,
      endpointId: endpointId,
    ));
    final error = transferSessionError;
    if (error != null) throw error;
    return PlaybackSessionInfo(
      id: sessionId,
      endpointId: endpointId,
      mine: true,
      authority: 'remote',
      playing: true,
      index: 0,
      positionMs: 0,
      positionAt: DateTime.now().toUtc(),
      rate: 1,
      queueVersion: 1,
      entries: const [],
    );
  }

  /// What [getCastPreflight] answers; the surface renders whatever is
  /// here, including the empty list a server with no candidate base has.
  List<CastPreflightBase> preflightBases = const <CastPreflightBase>[];

  /// Thrown by [getCastPreflight] when set.
  WaxDeckApiException? preflightError;

  @override
  Future<List<CastPreflightBase>> getCastPreflight() async {
    final error = preflightError;
    if (error != null) throw error;
    return preflightBases;
  }

  /// What [probeCastEndpoint] answers, keyed by endpoint id.
  Map<String, CastDeviceProbe> deviceProbes = const <String, CastDeviceProbe>{};

  /// Thrown by [probeCastEndpoint] when set, for the refusals a probe
  /// answers with rather than a verdict.
  WaxDeckApiException? deviceProbeError;

  /// The endpoints [probeCastEndpoint] was asked about, in order.
  final List<String> probedEndpoints = <String>[];

  @override
  Future<CastDeviceProbe> probeCastEndpoint(String endpointId) async {
    probedEndpoints.add(endpointId);
    final error = deviceProbeError;
    if (error != null) throw error;
    final probe = deviceProbes[endpointId];
    if (probe == null) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such endpoint',
        statusCode: 404,
      );
    }
    return probe;
  }
}
