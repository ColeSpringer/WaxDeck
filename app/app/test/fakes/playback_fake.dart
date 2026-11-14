import 'dart:async';

import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// In-memory [PlaybackApi] for `FakeRepository`.
mixin FakePlayback on FakeRepositoryState implements PlaybackApi {
  /// Past the played threshold without reaching the end.
  final Set<String> playedPids = {};

  /// Star and rating state by pid.
  final Map<String, bool> starredByPid = {};
  final Map<String, int?> ratingByPid = {};

  /// Thrown by [reportListens] when set, to exercise the retry path.
  WaxDeckApiException? reportError;

  /// Thrown by [setStar] and [setRating] when set, before any state
  /// changes, to exercise the optimistic rollback path.
  WaxDeckApiException? playStateError;

  /// When set, play-info resolution fails with it.
  /// Object, not the API exception: a repository can throw anything a
  /// codec or a plugin threw, and the gateway words those two cases
  /// differently.
  Object? playInfoError;

  /// When set, [getPlayInfo] waits on it before answering, so a test can
  /// hold a resolution open and act while it is in flight.
  Completer<void>? playInfoGate;

  /// When set, position checkpoints fail with it.
  WaxDeckApiException? putPlayStateError;

  /// Skip maps by pid (single file) or 'pid#partIndex' (book parts).
  final Map<String, SkipMap> skipMaps = {};

  /// Waveforms by pid. Unseeded pids answer `pending`, which is what a
  /// server whose analyze pass has never run says about everything.
  final Map<String, Waveform> waveforms = {};

  /// Pids [getWaveform] was asked about, so a test can pin that a face
  /// with no use for peaks does not ask.
  final List<String> waveformCalls = [];

  /// The subset asked for across a whole item rather than one part: a
  /// book's bar spans the book, and asking for a part would draw one
  /// file's shape under a timeline that is not it.
  final List<String> wholeItemWaveformCalls = [];

  /// Thrown by [getWaveform] when set.
  WaxDeckApiException? waveformError;

  final List<({String pid, int positionMs})> putPlayStateCalls = [];
  final List<ListenSession> reportedSessions = [];

  final List<({String pid, int? positionMs})> playInfoCalls = [];

  /// The maxBitrateKbps each [getPlayInfo] call carried, in order.
  final List<int?> playInfoMaxBitrates = [];

  /// The hls each [getPlayInfo] call carried, in order.
  final List<bool?> playInfoHls = [];

  /// Whether a call that says it plays HLS is handed a re-encode as the
  /// item's own HLS presentation; false answers it as a server whose
  /// engine renders no HLS does.
  bool rendersHls = true;

  /// The clock a minted play-info's expiry is counted from; the wall
  /// clock when null.
  DateTime Function()? playInfoClock;

  /// How long a minted play-info's token is good for.
  Duration playInfoLifetime = const Duration(minutes: 5);

  /// Numbers each mint's token (`mt=1`, `mt=2`, ...) rather than reusing
  /// one, so a re-mint shows up as a different URL.
  bool numberMints = false;
  int _mints = 0;

  /// Failures for the next [getPlayInfo] calls, first one first; a null
  /// entry lets that call answer.
  final List<Object?> playInfoFailures = [];

  String _token() => numberMints ? '${++_mints}' : 'test-token';

  DateTime _mintExpiry() =>
      (playInfoClock?.call() ?? DateTime.now()).toUtc().add(playInfoLifetime);

  @override
  Future<PlayInfo> getPlayInfo(
    String pid, {
    int? positionMs,
    bool? voiceBoost,
    int? maxBitrateKbps,
    bool? hls,
  }) async {
    final error = playInfoError;
    if (error != null) throw error;
    playInfoCalls.add((pid: pid, positionMs: positionMs));
    playInfoMaxBitrates.add(maxBitrateKbps);
    playInfoHls.add(hls);
    await playInfoGate?.future;
    if (playInfoFailures.isNotEmpty) {
      final failure = playInfoFailures.removeAt(0);
      if (failure != null) throw failure;
    }
    // A re-encode for a caller that plays HLS is the item's own HLS
    // presentation: seekable, and never cut.
    final presents = hls == true && rendersHls;
    // What the server does with a position on a stream it cannot range:
    // cuts it there, floored to the second, and says where.
    ({String query, int offsetMs}) cutAt(int? atMs, {required bool seekable}) {
      if (seekable || atMs == null || atMs < 1000) {
        return (query: '', offsetMs: 0);
      }
      final seconds = atMs ~/ 1000;
      return (query: '&t=$seconds', offsetMs: seconds * 1000);
    }

    final episode = findEpisode(pid);
    // Enclosure passthrough: an unfetched episode still
    // resolves, relayed from the feed's own host, and the conflict is
    // now for the one episode whose feed named no audio at all.
    if (episode != null && !episode.downloaded && !episode.hasEnclosure) {
      throw const WaxDeckApiException(
        code: 'conflict',
        message: 'episode audio not fetched yet',
        statusCode: 409,
      );
    }
    final book = books[pid];
    if (book != null && book.parts.isNotEmpty) {
      final parts = book.parts;
      var part = parts.first;
      for (final p in parts) {
        if ((positionMs ?? 0) >= p.startMs) part = p;
      }
      final boostedBook = voiceBoostPids.contains(pid);
      final encodedBook = boostedBook || transcodedPids.contains(pid);
      final seekableBook = !encodedBook || presents;
      final inPart = (positionMs ?? 0) - part.startMs;
      // The server's own clamp: into the part when it has a length, and
      // never before its start.
      final bookCut = cutAt(
        part.durationMs > 0
            ? inPart.clamp(0, part.durationMs - 1)
            : (inPart < 0 ? 0 : inPart),
        seekable: seekableBook,
      );
      return PlayInfo(
        pid: pid,
        url: encodedBook && presents
            ? '/media/hls/master.m3u8?it=$pid-${part.index}&mt=${_token()}'
            : '/media/stream?pid=$pid&part=${part.index}&mt=${_token()}'
                  '${bookCut.query}',
        mimeType: encodedBook && presents
            ? 'application/vnd.apple.mpegurl'
            : 'audio/mp4',
        durationMs: part.durationMs,
        seekable: seekableBook,
        voiceBoost: boostedBook,
        expiresAt: _mintExpiry(),
        partIndex: part.index,
        partCount: parts.length,
        partStartMs: part.startMs,
        startOffsetMs: bookCut.offsetMs,
      );
    }
    final span = playInfoSpans[pid];
    final boosted = voiceBoostPids.contains(pid);
    // The server clears seekable for anything it encodes live, voice boost
    // included, so that flag is how a client that asked for no HLS tells
    // a transcode from a passthrough.
    final encoded = boosted || transcodedPids.contains(pid);
    final seekable = !encoded || presents;
    final durationMs = episode?.durationMs ?? 214000;
    // As the server does: clamped into the item when it has a length, cut
    // where asked when a feed gave it none.
    final cut = cutAt(
      durationMs > 0 ? positionMs?.clamp(0, durationMs - 1) : positionMs,
      seekable: seekable,
    );
    return PlayInfo(
      pid: pid,
      url: encoded && presents
          ? '/media/hls/master.m3u8?it=$pid&mt=${_token()}'
          : '/media/stream?pid=$pid&mt=${_token()}${cut.query}',
      mimeType: encoded && presents
          ? 'application/vnd.apple.mpegurl'
          : 'audio/flac',
      durationMs: durationMs,
      seekable: seekable,
      voiceBoost: boosted,
      expiresAt: _mintExpiry(),
      spanStartMs: span?.startMs,
      spanEndMs: span?.endMs,
      startOffsetMs: cut.offsetMs,
    );
  }

  /// Span windows served by [getPlayInfo], keyed by pid: the direct
  /// playback shape for tracks carved out of a larger file.
  final Map<String, ({int startMs, int endMs})> playInfoSpans = {};

  /// Pids the server cuts rather than passes through, so their play-info
  /// answers unseekable.
  final Set<String> transcodedPids = {};

  /// Pids served with spoken-word loudness normalization applied.
  final Set<String> voiceBoostPids = {};

  /// Pids read one at a time through [getPlayState], in order. Only the
  /// override records: the mutations below answer with the same state
  /// and would otherwise show up here as reads nobody made.
  final List<String> playStateReads = [];

  /// Thrown by [getPlayState] when set. Its own field rather than
  /// [playStateError], which the mutations use: a session start reads
  /// and writes play state, and a test about one failing has to leave
  /// the other working.
  WaxDeckApiException? getPlayStateError;

  @override
  Future<PlayState> getPlayState(String pid) async {
    playStateReads.add(pid);
    final error = getPlayStateError;
    if (error != null) throw error;
    return _playStateOf(pid);
  }

  PlayState _playStateOf(String pid) => PlayState(
    pid: pid,
    positionMs: playPositions[pid] ?? 0,
    played: finishedPids.contains(pid) || playedPids.contains(pid),
    finished: finishedPids.contains(pid),
    playCount: playCounts[pid] ?? (finishedPids.contains(pid) ? 1 : 0),
    starred: starredByPid[pid] ?? false,
    rating: ratingByPid[pid],
    lastPlayedAt: playStateLastPlayedAt[pid],
    updatedAt: playStateUpdatedAt[pid],
  );

  /// Holds every checkpoint until completed, so a test can stand a
  /// write up mid-flight and act around it.
  Completer<void>? putPlayStateGate;

  /// Holds for the next checkpoints, one per call, first one first; a
  /// null entry lets that call through. A write lands (and is recorded)
  /// when its hold completes, so a slow write can be made to land late.
  final List<Completer<void>?> putPlayStateHolds = [];

  @override
  Future<void> putPlayState(
    String pid,
    int positionMs, {
    DateTime? recordedAt,
  }) async {
    final hold = putPlayStateHolds.isEmpty
        ? null
        : putPlayStateHolds.removeAt(0);
    await hold?.future;
    await putPlayStateGate?.future;
    final error = putPlayStateError;
    if (error != null) throw error;
    putPlayStateCalls.add((pid: pid, positionMs: positionMs));
    playPositions[pid] = positionMs;
  }

  /// When set, [setStar] and [setRating] wait on it before applying,
  /// so tests can hold a mutation in flight while they race something
  /// against it (a provider invalidation, another mutation).
  Future<void>? mutationGate;

  /// Every played/finished write, in call order, so a test can see what
  /// an undo actually asked for rather than only where it landed.
  final List<
    ({String pid, bool played, bool finished, int? playCount, int? positionMs})
  >
  setPlayedCalls = [];

  /// Makes the fake behave like a server too old for `positionMs`: the
  /// field is recorded but the position is left where it was, which is
  /// what the returned state then reports.
  bool setPlayedIgnoresPosition = false;

  @override
  Future<PlayState> setPlayed(
    String pid, {
    required bool played,
    required bool finished,
    int? playCount,
    int? positionMs,
    DateTime? recordedAt,
  }) async {
    await (mutationGate ?? Future<void>.value());
    final error = playStateError;
    if (error != null) return _failLikeANetwork(error);
    setPlayedCalls.add((
      pid: pid,
      played: played,
      finished: finished,
      playCount: playCount,
      positionMs: positionMs,
    ));
    // The fake keeps one finished set behind both flags, which is what
    // every reader of it asks about; the server's three-way play count
    // is recorded above rather than modelled.
    if (finished) {
      finishedPids.add(pid);
    } else {
      finishedPids.remove(pid);
    }
    if (positionMs != null && !setPlayedIgnoresPosition) {
      playPositions[pid] = positionMs;
    }
    return _playStateOf(pid);
  }

  @override
  Future<PlayState> setStar(
    String pid,
    bool starred, {
    DateTime? recordedAt,
  }) async {
    await (mutationGate ?? Future<void>.value());
    final error = playStateError;
    if (error != null) return _failLikeANetwork(error);
    starredByPid[pid] = starred;
    return _playStateOf(pid);
  }

  @override
  Future<PlayState> setRating(
    String pid,
    int? rating, {
    DateTime? recordedAt,
  }) async {
    await (mutationGate ?? Future<void>.value());
    final error = playStateError;
    if (error != null) return _failLikeANetwork(error);
    ratingByPid[pid] = rating;
    return _playStateOf(pid);
  }

  /// The pid sets each batched play-state read covered, in call order,
  /// so a test can see what a page cost.
  final List<List<String>> playStateBatches = [];

  /// Holds every batched read until completed, with the batch recorded.
  Completer<void>? playStatesGate;

  @override
  Future<List<PlayState>> listPlayStates(List<String> pids) async {
    playStateBatches.add(List<String>.of(pids));
    await playStatesGate?.future;
    final error = playStatesError;
    if (error != null) throw error;
    return [for (final pid in pids) _playStateOf(pid)];
  }

  /// Thrown by [listPlayStates] when set, with the batch recorded.
  Object? playStatesError;

  /// Entity stars and ratings, keyed by entity pid. Their own maps, not
  /// the item ones: an entity star is independent of its members'.
  final Map<String, bool> entityStarredByPid = {};
  final Map<String, int?> entityRatingByPid = {};

  @override
  Future<EntityPlayState> getEntityPlayState(String pid) async =>
      EntityPlayState(
        pid: pid,
        starred: entityStarredByPid[pid] ?? false,
        rating: entityRatingByPid[pid],
      );

  @override
  Future<EntityPlayState> setEntityStar(
    String pid,
    bool starred, {
    DateTime? recordedAt,
  }) async {
    await (mutationGate ?? Future<void>.value());
    final error = playStateError;
    if (error != null) {
      return Future<EntityPlayState>.delayed(
        const Duration(milliseconds: 1),
        () => throw error,
      );
    }
    entityStarredByPid[pid] = starred;
    return getEntityPlayState(pid);
  }

  @override
  Future<EntityPlayState> setEntityRating(
    String pid,
    int? rating, {
    DateTime? recordedAt,
  }) async {
    await (mutationGate ?? Future<void>.value());
    final error = playStateError;
    if (error != null) {
      return Future<EntityPlayState>.delayed(
        const Duration(milliseconds: 1),
        () => throw error,
      );
    }
    entityRatingByPid[pid] = rating;
    return getEntityPlayState(pid);
  }

  @override
  Future<StarredEntities> listStarredEntities() async {
    final starred = entityStarredByPid.entries
        .where((e) => e.value)
        .map((e) => SearchHit(pid: e.key, kind: 'album', title: e.key))
        .toList();
    return StarredEntities(
      artists: starred.where((h) => h.pid.startsWith('ar-')).toList(),
      albums: starred.where((h) => h.pid.startsWith('al-')).toList(),
    );
  }

  @override
  Future<DownloadInfo> getDownloadInfo(String pid) async {
    return DownloadInfo(
      pid: pid,
      files: [
        DownloadFileInfo(
          url: '/media/download?pid=$pid&mt=test-token',
          mimeType: 'audio/flac',
          sizeBytes: 1024,
          fileName: '$pid.flac',
          essenceHash: 'essence-$pid',
          etag: '1024-1',
        ),
      ],
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );
  }

  // A beat of latency before the failure, so tests can observe the
  // optimistic frame a real network round trip would leave on screen.
  static Future<PlayState> _failLikeANetwork(WaxDeckApiException error) =>
      Future<PlayState>.delayed(
        const Duration(milliseconds: 10),
        () => throw error,
      );

  @override
  Future<ListenOutcome> reportListens(List<ListenSession> sessions) async {
    final error = reportError;
    if (error != null) throw error;
    reportedSessions.addAll(sessions);
    return ListenOutcome(accepted: sessions.length, duplicates: 0);
  }

  @override
  Future<SkipMap> getSkipMap(String pid, {int? partIndex}) async {
    final keyed = partIndex == null ? null : skipMaps['$pid#$partIndex'];
    return keyed ?? skipMaps[pid] ?? const SkipMap(state: 'unavailable');
  }

  @override
  Future<Waveform> getWaveform(String pid, {bool wholeItem = false}) async {
    waveformCalls.add(pid);
    if (wholeItem) wholeItemWaveformCalls.add(pid);
    final error = waveformError;
    if (error != null) throw error;
    // Keyed like the skip map's parts: a test that seeds the whole-item
    // answer separately can prove which span a face asked for.
    final keyed = wholeItem ? waveforms['$pid#item'] : null;
    return keyed ?? waveforms[pid] ?? const Waveform(state: 'pending');
  }
}
