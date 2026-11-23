part of '../playback_session.dart';

/// Loading media: minting, the display timeline, config, parts, local files.
extension _SessionMedia on PlaybackSession {
  /// Every load this session makes, so the guarantee the caller reads
  /// the failure against is made in one place rather than at five call
  /// sites: what comes out of here is a [MediaLoadException] and
  /// nothing else.
  ///
  /// The engine port promises that already. This holds the promise for
  /// an engine that broke it - a plugin exception escaping an
  /// implementation that forgot to classify one - and holds it the safe
  /// way round, as [MediaFault.transport]: a start that stops on a
  /// retryable pane costs a press, and one that walks the queue costs
  /// the listening.
  Future<void> _loadMedia(
    String url, {
    String? mimeType,
    Duration? initialPosition,
    Duration? clipStart,
    Duration? clipEnd,
  }) async {
    final standing = _standingMs();
    _loading++;
    _loadsBegun++;
    try {
      await engine.load(
        url,
        mimeType: mimeType,
        initialPosition: initialPosition,
        clipStart: clipStart,
        clipEnd: clipEnd,
      );
      _stoodBeforeFailedLoad = null;
      _announceMediaLoaded();
    } on MediaLoadException {
      _stoodBeforeFailedLoad = standing;
      rethrow;
    } on Object catch (error) {
      _stoodBeforeFailedLoad = standing;
      throw MediaLoadException(MediaFault.transport, error);
    } finally {
      _loading--;
    }
  }

  /// Loads a minted stream at display position [atMs].
  ///
  /// A refusal a fresh mint cures (an expired token, the streaming engine
  /// away) is minted once more and loaded again; a second failure is not
  /// tried a third time. Whatever the server refused comes out as its own
  /// API error, so the layer above words it and never reads it as the
  /// file.
  Future<void> _loadStream(PlayInfo info, int atMs) async {
    try {
      await _loadInfo(info, atMs);
      return;
    } on MediaLoadException catch (error) {
      if (_disposed || !_worthAnotherMint(error)) throw _surfaced(error);
    }
    final fresh = await _mint(atMs);
    if (_disposed) return;
    try {
      await _loadInfo(fresh, atMs);
    } on MediaLoadException catch (again) {
      throw _surfaced(again);
    }
  }

  /// One load of [info] at display position [atMs]. A span means the URL
  /// carries the whole backing file (direct playback of a carved track);
  /// the engine clips to the window and every position stays
  /// track-relative.
  ///
  /// A cut stream begins at [PlayInfo.startOffsetMs], at most a second
  /// before [atMs]; the rest is a seek inside media already arriving.
  Future<void> _loadInfo(PlayInfo info, int atMs) async {
    final cut = info.startOffsetMs;
    final lengthMs = info.durationMs - cut;
    var inMediaMs = atMs - (info.partStartMs ?? 0) - cut;
    // Web answers "no supported source" for a source begun at or past its
    // end: a target there plays the last second, and ends the way a seek
    // to the end of a single file does. Only where the length is the
    // audio's own, a cut's or a book part's: an episode's may be its
    // feed's word, short of the audio.
    final measured = !info.seekable || info.partIndex != null;
    if (measured && lengthMs > 0 && inMediaMs >= lengthMs) {
      inMediaMs = lengthMs > 1000 ? lengthMs - 1000 : 0;
    }
    await _loadMedia(
      info.url,
      mimeType: info.mimeType,
      initialPosition: inMediaMs > 0 ? Duration(milliseconds: inMediaMs) : null,
      clipStart: info.spanStartMs == null
          ? null
          : Duration(milliseconds: info.spanStartMs!),
      clipEnd: info.spanEndMs == null
          ? null
          : Duration(milliseconds: info.spanEndMs!),
    );
    // The timeline state moves in one step, once the media is in the
    // engine (see [_loadPartFor] for why after and not before).
    _moveTimeline(
      info: info,
      cutMs: cut,
      durationMs: info.durationMs,
      partIndex: info.partIndex,
      partCount: info.partCount,
      partStartMs: info.partStartMs ?? 0,
    );
  }

  /// Points the display timeline at what the engine now holds, in one
  /// step: the stream it was minted from ([info]; none for a timeline
  /// member, which nothing here can mint again, or a device copy),
  /// where a cut stream begins, the loaded media's length, and where a
  /// part sits in its book.
  void _moveTimeline({
    PlayInfo? info,
    int cutMs = 0,
    required int durationMs,
    int? partIndex,
    int? partCount,
    int partStartMs = 0,
  }) {
    if (info == null) {
      _info = null;
      _staleAt = null;
    } else {
      _hold(info);
    }
    _cutMs = cutMs;
    _loadedDurationMs = durationMs;
    _partIndex = partIndex;
    _partCount = partCount;
    _partStartMs = partStartMs;
    _announceTimelineMoved();
  }

  /// Makes [info] the loaded media's, its staleness read on this device's
  /// clock the way the downloads read theirs: a play that lands on an
  /// expired URL is a failure the listener hears.
  void _hold(PlayInfo info) {
    _info = info;
    _staleAt = mediaUrlStaleAt(info.expiresAt, now: _clock());
  }

  /// Mints for display position [atMs], and again for whatever arrived
  /// while that mint was out (the newest seek, a change of effects): a cut
  /// is a whole encode of the rest of the item, so the targets in between
  /// are never loaded. Answers the play-info and the target it is for.
  Future<(PlayInfo, int)> _mintNewest(int atMs) async {
    var at = atMs;
    var info = await _mint(at);
    while (!_disposed && (_pendingSeekMs != null || _remint)) {
      at = _pendingSeekMs ?? at;
      _loadTarget = at;
      _pendingSeekMs = null;
      _remint = false;
      info = await _mint(at);
    }
    return (info, at);
  }

  /// Play-info for this item at display position [atMs]: the part holding
  /// it for a book, and for a stream the server cannot range, a stream cut
  /// to begin there. The boost is the listener's choice this session where
  /// they made one, else the server's to resolve: the stored setting, else
  /// this device's default (spoken word), sent only when on.
  Future<PlayInfo> _mint(int atMs) => repository.getPlayInfo(
    item.pid,
    positionMs: _isBook ? atMs : (atMs > 0 ? atMs : null),
    voiceBoost: _boostChosen ? voiceBoost.value : null,
    voiceBoostDefault: isSpokenWord && defaultVoiceBoost ? true : null,
    maxBitrateKbps: maxBitrateKbps,
    hls: _hls,
  );

  /// Asked on every mint where the engine plays HLS: a re-encode then
  /// comes back as one presentation it seeks itself, seekable, so nothing
  /// here cuts it and trimming jumps. Unasked elsewhere.
  bool? get _hls => engine.playsHls ? true : null;

  /// The timeline half of [_loadMedia], holding the same promise. Never
  /// asks the engine to play: [start] owns the speed write and the
  /// first play, in that order, and a timeline that started itself
  /// would be audible at the wrong speed for a frame.
  Future<void> _loadTimelineMedia(TimelineSlot slot, Duration? at) async {
    final engine = this.engine;
    if (engine is! TimelineAudioEngine) {
      throw MediaLoadException(
        MediaFault.transport,
        StateError('this engine plays no timelines'),
      );
    }
    try {
      await engine.loadTimeline(
        slot.media,
        member: slot.member,
        position: at ?? Duration.zero,
      );
      _announceMediaLoaded();
    } on MediaLoadException {
      rethrow;
    } on Object catch (error) {
      throw MediaLoadException(MediaFault.transport, error);
    }
  }

  /// Fetches the per-show or per-book playback config; playback works
  /// without it, so any failure just leaves the defaults in place.
  Future<void> _loadConfig() async {
    try {
      await _readConfig();
    } on WaxDeckApiException {
      // Defaults apply; the player still plays.
    }
    // A session let go, or whose engine another took, shows nothing more.
    if (_disposed || !_ownsEngine) return;
    _applyConfig();
  }

  /// Reads the per-show or per-book playback config and holds it. Failed
  /// for want of the server, the choices waiting are kept for its return,
  /// at which a config never answered is asked again.
  Future<void> _readConfig() async {
    final first = !_configAnswered;
    try {
      final it = item;
      if (item.mediaType == MediaType.podcast && it is EpisodeSummary) {
        final detail = await repository.getPodcast(it.showPid);
        _showSettings = detail.settings;
      } else if (_isBook) {
        final detail = await repository.getBook(item.pid);
        _book ??= detail;
        _bookSettings = detail.settings;
      } else {
        return;
      }
    } on WaxDeckApiException catch (e) {
      if (first) _configFailed = e.unreachable;
      if (e.unreachable) _keepWaiting();
      rethrow;
    }
    _configAnswered = true;
    _configFailed = false;
  }

  /// Trim and boost from the item's stored settings, this device's
  /// defaults where it has none; what the listener set on this session
  /// stands over both.
  void _applyConfig() {
    // The device default is the seam behind the stored choice, spoken
    // word only: music has neither a trim chip nor a boost to open
    // with, so a default left on must not leak onto it.
    final fallbackTrim = isSpokenWord && defaultTrimSilence;
    if (!_trimChosen) {
      trimEnabled.value = _isBook
          ? (_bookSettings?.trimSilence ?? fallbackTrim)
          : (_showSettings?.trimSilence ?? fallbackTrim);
    }
    _applyBoost();
  }

  /// The boost half of [_applyConfig].
  void _applyBoost() {
    if (_boostChosen) return;
    final fallback = isSpokenWord && defaultVoiceBoost;
    voiceBoost.value = _isBook
        ? (_bookSettings?.voiceBoost ?? fallback)
        : (_showSettings?.voiceBoost ?? fallback);
  }

  /// The item's own remembered rate, and this device's default behind
  /// it.
  ///
  /// Music is 1x and nothing else. It stores no rate of its own, so a
  /// default here would be a speed a listener could set and never depart
  /// from - and the setting is Playback's "spoken word" default, which
  /// is what a show and a book are and a track is not.
  double _configuredSpeed() {
    if (item.mediaType == MediaType.music) return 1.0;
    final configured = _isBook ? _bookSettings?.speed : _showSettings?.speed;
    return configured ?? defaultSpeed;
  }

  /// Episodes with a skip-intro setting start at the intro end unless the
  /// resume point is already past it.
  int _applyIntroSkip(int resumeMs) {
    final intro = _showSettings?.skipIntroSeconds;
    if (intro == null || intro <= 0) return resumeMs;
    final introMs = intro * 1000;
    return resumeMs > introMs ? resumeMs : introMs;
  }

  /// The episode outro cutoff on the loaded file's own timeline: the
  /// show's outro seconds back from where the audio ends ([_mediaEndMs]).
  /// Null when unset, and when nothing says where the audio ends: a
  /// feed's declared length never ends the listen.
  int? get _outroCutoffMs {
    final outro = _showSettings?.skipOutroSeconds;
    final end = _isBook ? null : _mediaEndMs;
    if (outro == null || outro <= 0 || end == null) return null;
    final cutoff = end - outro * 1000;
    return cutoff > 0 ? cutoff : null;
  }

  /// Where a play from display [ms] starts: a position at or past the end
  /// the transport draws ([mediaDuration]) is not a place to start, so the
  /// top. Not in [_loadPartFor], whose rollover past the last part lands
  /// on the end.
  int _startAt(int ms) {
    final length = _knownLengthMs;
    return length > 0 && ms >= length ? 0 : ms;
  }

  /// The length [mediaDuration] draws, from what this session knows itself
  /// before its first load lands: until then the engine's length is
  /// whatever played last. Zero where nothing says.
  int get _knownLengthMs => _loaded
      ? mediaDuration.inMilliseconds
      : (_isBook ? _book?.durationMs ?? item.durationMs : _loadedDurationMs);

  /// Resolves and loads the part containing book-timeline [bookMs]
  /// (single-file items resolve to the whole file with partStartMs 0).
  /// [newest] folds in what arrives while the mint is out, for a load
  /// under way (see [_mintNewest]). Never plays: whatever runs it says
  /// how it lands. [fallback] off leaves an unreachable server to the
  /// caller.
  ///
  /// The fallback to downloaded parts is here rather than at the call
  /// sites, so every crossing gets it: a seek, a chapter tap, the deck
  /// bar's skip, replay, and the roll off a part's end.
  ///
  /// Rethrows for parts that cannot be placed on a timeline, which is
  /// [start]'s own offline branch to answer: it has the mirror position.
  Future<void> _loadPartFor(
    int bookMs, {
    bool newest = false,
    bool fallback = true,
  }) async {
    final held = _localParts;
    if (held != null) {
      await _loadLocalPartFor(held, bookMs);
      return;
    }
    final (PlayInfo, int) minted;
    try {
      minted = newest
          ? await _mintNewest(bookMs)
          : (await _mint(bookMs), bookMs);
    } on WaxDeckApiException catch (e) {
      if (!fallback) rethrow;
      final local = await _localFallback(e);
      if (_disposed) return;
      // The newest target the failed mint was folding in.
      final target = _pendingSeekMs ?? _loadTarget ?? bookMs;
      _pendingSeekMs = null;
      if (local != null && local.sequenced) {
        _localParts = local;
        await _loadLocalPartFor(local, target);
        return;
      }
      // A book that is one file plays that file wherever it stands.
      if (local != null && local.parts.length == 1) {
        await _loadLocalFile(local, target);
        return;
      }
      rethrow;
    }
    // Let go while the part was resolving: loading it now would put this
    // book over whatever took the engine.
    if (_disposed) return;
    // Until a load lands there is no map, whatever part it names (a book
    // in one file names none, which reads the same as the part before
    // it), and a downloaded copy that would not load landed none.
    final samePart = _loaded && minted.$1.partIndex == _partIndex;
    // The timeline state moves only once the part's media is in the
    // engine. Written before the load, every checkpoint fired inside it
    // - and the load's own stop publishes a pause, whose checkpoint is
    // one - added the new part's start to the old part's engine position
    // and landed part-shifted on the book timeline; and a load that
    // threw needed everything rolled back. After it, the fields and the
    // media cannot disagree whichever way the load went. The skip-map
    // state rides with them: cleared against the old part, a refused
    // load would leave trimming silently dead for a part still playing.
    await _loadStream(minted.$1, minted.$2);
    if (_disposed) return;
    // The jump cursor is per load; the map is per part, so the same part
    // loaded again (a reopen for effects, a recovery) keeps the one it has.
    _lastJumpedSpan = -1;
    if (!samePart) {
      _skipSpans = const [];
      _skipMapRetried = false;
      if (trimEnabled.value) unawaited(_loadSkipMap());
    }
    _lastPosition = engine.position;
  }

  /// The same resolution against the download store: which downloaded
  /// part holds book-timeline [bookMs], and where on the timeline it
  /// starts.
  ///
  /// The state it sets is the state play-info sets, which is what makes
  /// everything above it - the display timeline, checkpoints in book
  /// milliseconds, a seek that leaves the part, the roll into the next
  /// one - behave on the device's parts exactly as on the server's. Its
  /// skip map is the server's, asked as the stream's road asks for it.
  Future<void> _loadLocalPartFor(LocalPlayback local, int bookMs) async {
    final at = local.partAt(bookMs);
    final inPartMs = bookMs - at.startMs;
    // The map is per part, so the same part loaded again keeps the one it
    // has, as on the stream's road.
    final samePart = _loaded && at.index == _partIndex;
    // State follows the media, the same ordering as the online path and
    // for the same arithmetic: this is the one branch whose part-shifted
    // checkpoint no server write would ever correct - a downloaded part
    // pruned or corrupt would leave the final checkpoint claiming the
    // next part at the previous part's position, offline, for good.
    await _loadMedia(
      Uri.file(at.part.path).toString(),
      initialPosition: inPartMs > 0 ? Duration(milliseconds: inPartMs) : null,
    );
    if (_disposed) return;
    _moveTimeline(
      durationMs: at.part.durationMs ?? 0,
      partIndex: at.index,
      partCount: local.parts.length,
      partStartMs: at.startMs,
    );
    _lastJumpedSpan = -1;
    if (!samePart) {
      _skipSpans = const [];
      _skipMapRetried = false;
      // Wherever the stream's road would ask; out of reach, only once the
      // server has answered this session.
      if (trimEnabled.value && (_configAnswered || _socketUp)) {
        unawaited(_loadSkipMap());
      }
    }
    _lastPosition = engine.position;
  }

  /// Whether a held copy plays rather than the boosted stream: the boost
  /// off, or refused this session.
  bool get _copyPlays => !_boostOn || _boostRefused;

  /// Whether [local] can stand in for the server's stream: one file, or
  /// parts that can be placed on the item's timeline.
  bool _fits(LocalPlayback local) => local.parts.length == 1 || local.sequenced;

  /// Whether this item plays with voice boost, which only the server's
  /// minted stream carries: the listener's choice this session, else the
  /// show's or book's stored setting, else this device's default (spoken
  /// word), as the mint asks for it.
  bool get _boostOn {
    if (_boostChosen) return voiceBoost.value;
    final stored = _isBook
        ? _bookSettings?.voiceBoost
        : _showSettings?.voiceBoost;
    return stored ?? (isSpokenWord && defaultVoiceBoost);
  }

  /// Whether [copy] is laid out as the server's book is, where the server
  /// said: its positions and chapters are placed on its own parts, which a
  /// book imported again since its download no longer shares.
  bool _matchesBook(LocalPlayback copy) {
    final held = _book;
    if (!_isBook || held == null) return true;
    if (!copy.sequenced) return held.parts.length <= 1;
    final parts = <BookPart>[];
    var startMs = 0;
    for (var i = 0; i < copy.parts.length; i++) {
      final durationMs = copy.parts[i].durationMs!;
      parts.add(BookPart(index: i, startMs: startMs, durationMs: durationMs));
      startMs += durationMs;
    }
    return _sameParts(held.parts, parts);
  }

  /// Loads the device copy [local] at display position [atMs]: the part
  /// holding it for a book whose parts can be placed, the one file
  /// otherwise.
  Future<void> _loadCopy(LocalPlayback local, int atMs) async {
    if (_isBook && local.sequenced) {
      _localParts = local;
      await _loadLocalPartFor(local, atMs);
    } else {
      await _loadLocalFile(local, atMs);
    }
  }

  /// The length of [local]'s one file as the engine will play it.
  int _fileLengthMs(LocalPlayback local) {
    // A carved item's file duration is the whole rip's, and the engine
    // is about to be clipped to the window: the loaded media is the
    // item's own length.
    final span = local.spanStartMs != null && (local.spanEndMs ?? 0) > 0
        ? local.spanEndMs! - local.spanStartMs!
        : null;
    return span ?? local.parts.first.durationMs ?? item.durationMs;
  }

  /// Loads the one file of [local] at display position [atMs]: a track,
  /// an episode, a book that is one file, or the first file of a book
  /// whose stored parts cannot be placed on its timeline.
  Future<void> _loadLocalFile(LocalPlayback local, int atMs) async {
    // Downloaded originals carry the same window; clipping here is what
    // makes an offline carved track play as itself instead of the whole
    // rip.
    await _loadMedia(
      Uri.file(local.parts.first.path).toString(),
      initialPosition: atMs > 0 ? Duration(milliseconds: atMs) : null,
      clipStart: local.spanStartMs == null
          ? null
          : Duration(milliseconds: local.spanStartMs!),
      // The server closes open-ended windows now; the zero guard covers
      // download records stored before it did (an open clip end plays to
      // the file's end, which is what those meant).
      clipEnd: local.spanEndMs == null || local.spanEndMs! <= 0
          ? null
          : Duration(milliseconds: local.spanEndMs!),
    );
    if (_disposed) return;
    _moveTimeline(durationMs: _fileLengthMs(local));
  }

  /// What the sync engine says of the server's reach, for a start that may
  /// take its position from the mirror instead: its socket up; a failure
  /// behind it ([SyncStatus.retrying]: a connect that failed, a link that
  /// dropped, a session opened from memory because the server did not
  /// answer); or neither, a first connect still out. Null where the mirror
  /// is not in question: no engine to say (the server is asked as always,
  /// a copy playing all the same), no downloads, or a timeline member,
  /// whose stream the server minted for its queue.
  _Reach? get _reach {
    final engine = sync;
    if (engine == null || downloads == null || timeline != null) return null;
    final status = engine.current;
    if (engine.started && status.online) return _Reach.up;
    return status.retrying ? _Reach.out : _Reach.unknown;
  }

  /// Whether nothing says the server is out of reach: the sync engine's
  /// socket up, or no engine to say.
  bool get _socketUp {
    final reach = _reach;
    return reach == null || reach == _Reach.up;
  }

  /// The server's config, landed after a start that took the downloaded
  /// copy: taken up where the session changes it in place, the rate unless
  /// the listener chose one, and trimming, whose chip [_loadConfig] set as
  /// it landed, stored settings or none. The intro skip is a start position
  /// and voice boost a minted stream's, so the intro waits for the next
  /// start and the boost for the next load; nothing moves the listener.
  Future<void> _adoptLateConfig() async {
    if (_disposed || !_loaded || !_configAnswered || !_ownsEngine) return;
    if (!_speedChosen) await engine.setSpeed(_configuredSpeed());
    if (_disposed) return;
    if (trimEnabled.value && _skipSpans.isEmpty) unawaited(_loadSkipMap());
  }

  /// Whether the engine is still this session's to drive.
  bool get _ownsEngine =>
      identical(PlaybackSession._engineOwners[engine], this);

  /// The downloaded original, for media the server was to supply, but only
  /// for failures that smell like unreachability; a real API rejection
  /// (404, 401) propagates.
  Future<LocalPlayback?> _localFallback(WaxDeckApiException e) async {
    final port = downloads;
    if (port == null) return null;
    if (!e.unreachable) return null;
    return port.localFor(item.pid);
  }
}

/// What is known of the server's reach at a start (see `_reach`).
enum _Reach { up, unknown, out }

/// Whether another mint could make [error] go away: a refusal that says
/// so, or a failure the server never explained. Not one the load
/// deadline already waited out, which would only double the wait.
bool _worthAnotherMint(MediaLoadException error) {
  final refusal = error.refusal;
  if (refusal != null) return _curedByMint(refusal);
  return error.fault == MediaFault.transport &&
      error.cause is! TimeoutException;
}

/// Whether minting again cures [refusal]: a token that lapsed, the
/// streaming engine away.
bool _curedByMint(StreamRefusal refusal) => refusal.stale || refusal.engineDown;

/// A failure carrying the server's refusal, as the API error it is.
/// One with no envelope (a proxy's page, a bare status) reads as the
/// API client reads any such answer: the network, with its status.
Object _surfaced(MediaTrouble error) {
  final refusal = error.refusal;
  if (refusal == null) return error;
  final code = refusal.code ?? 'transport';
  return WaxDeckApiException(
    code: code,
    message: refusal.message ?? code,
    statusCode: refusal.status,
    params: refusal.params,
  );
}
