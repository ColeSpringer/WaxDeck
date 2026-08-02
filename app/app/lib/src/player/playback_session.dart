import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

import 'smart_rewind.dart';

/// Drives one item's playback through the engine port and owns the server
/// bookkeeping around it: resume on open, position checkpoints, and listen
/// session accounting.
///
/// Listen accounting counts media time actually heard, not wall clock:
/// position deltas are accumulated only while playing and only when small
/// enough to be normal playback progress, so pauses contribute nothing and
/// a seek's jump is never counted as listening.
///
/// Spoken-word items add item-scoped playback config on top: per-show and
/// per-book speed memory, silence trimming from server skip maps, episode
/// intro/outro skipping, and multi-part audiobooks. For books every
/// position this class reports to the server is a book-timeline
/// millisecond (part start plus the in-part engine position).
class PlaybackSession {
  PlaybackSession({
    required this.repository,
    required this.engine,
    required this.item,
    required this.clientId,
    this.sync,
    this.downloads,
    this.checkpointInterval = const Duration(seconds: 5),
    this.initialPositionMs,
    this.skipMapRetryDelay = const Duration(seconds: 30),
    this.defaultSpeed = 1.0,
    this.defaultTrimSilence = false,
    this.defaultVoiceBoost = false,
    this.smartRewind = SmartRewind.off,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final WaxDeckRepository repository;
  final AudioEnginePort engine;
  final ItemSummary item;
  final String clientId;

  /// The sync engine, when this platform runs one: offline mutations
  /// queue through it instead of being dropped.
  final SyncEngine? sync;

  /// Downloaded originals, for playback when the server is unreachable.
  final DownloadManagerPort? downloads;
  final Duration checkpointInterval;

  /// Overrides the saved resume position (book resume, chapter start).
  /// For books this is a book-timeline millisecond.
  final int? initialPositionMs;

  /// How long to wait before the single retry of a pending skip map.
  final Duration skipMapRetryDelay;

  /// The rate a show or a book plays at when it has none stored of its
  /// own: this device's Playback default. Never applied to music, which
  /// has no per-item rate to fall back from.
  ///
  /// Supplied by the caller rather than read here, because a session
  /// outlives the frame it was built in: a value read once at start is
  /// exactly the semantics wanted, since changing the default must not
  /// re-rate a book somebody is listening to.
  final double defaultSpeed;

  /// What the spoken-word effects do when the show or book has no
  /// stored choice of its own: this device's Playback defaults, read
  /// once at build for the same reason [defaultSpeed] is. Never applied
  /// to music, which has neither effect to default.
  final bool defaultTrimSilence;
  final bool defaultVoiceBoost;

  /// How far a resume steps back for context, per this device's
  /// Playback setting. Read once at build for the same reason
  /// [defaultSpeed] is: a session outlives the frame it was made in.
  final SmartRewind smartRewind;

  /// Wall clock behind the rewind's "how long ago", injectable so tests
  /// can put a pause in the past without waiting one out.
  final DateTime Function() _clock;

  /// When playback last stopped under this session, for the rewind on
  /// the next play. Null while playing, and while nothing has played
  /// yet: a session that has never started has no pause to measure.
  DateTime? _pausedAt;

  /// When the listener last left this item, for a session that loaded
  /// without playing (a queue put back at launch). Spent by the first
  /// play and null from then on, so the step is never applied twice and
  /// never applied to a checkpoint nobody listened past.
  DateTime? _restedSince;

  /// Position deltas above this are treated as seeks, not listening.
  static const maxCountedStep = Duration(seconds: 2);

  /// How early before a silence span the trim jump may fire, absorbing
  /// position-stream granularity.
  static const trimWindowMs = 250;

  /// Which session currently owns each (shared) engine. A disposed
  /// session must not stop an engine a newer session has taken over.
  static final Expando<PlaybackSession> _engineOwners = Expando('engine owner');

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<void>? _completedSub;
  Timer? _checkpointTimer;
  Timer? _skipMapRetry;

  Duration _lastPosition = Duration.zero;
  String? _sessionId;
  DateTime? _startedAt;
  int _msPlayed = 0;

  // The trimmed-milliseconds counter's value when the open listen
  // session began, so each session reports only its own.
  int _skippedAtSessionStart = 0;

  /// The other half of the time-saved sum: milliseconds of content this
  /// session heard but did not sit through, because it was playing
  /// faster than the recording.
  ///
  /// Accumulated per counted position delta at the rate that delta was
  /// heard at, so a rate changed mid-episode is priced from where it
  /// changed, and a rate below 1x adds nothing rather than owing time
  /// back.
  int _speedSavedMs = 0;

  /// The counter when the open listen session began, the same baseline
  /// [_skippedAtSessionStart] is.
  int _speedSavedAtSessionStart = 0;
  bool _finished = false;
  ListenSession? _pendingRetry;
  bool _disposed = false;

  // Item-scoped playback config, fetched on start and tolerated missing.
  SubscriptionSettings? _showSettings;
  BookDetail? _book;
  BookSettings? _bookSettings;

  // Multi-part book state. _partStartMs stays 0 for single-file items so
  // display arithmetic is uniform.
  int? _partIndex;
  int? _partCount;
  int _partStartMs = 0;

  /// The loaded media's own duration: one part's for a multi-part book,
  /// the whole item's otherwise.
  ///
  /// Filled by both load paths, so the part arithmetic below - where a
  /// seek leaves the loaded part, and where the next part starts - never
  /// has to know whether the server or the download store resolved it.
  /// Reading play-info for it was what made every one of those sums zero
  /// on the offline path.
  int _loadedDurationMs = 0;

  /// The downloaded parts this book is playing from, set only where the
  /// offline branch took over an item whose parts can be placed on its
  /// timeline. Non-null means part resolution runs against the download
  /// store rather than against play-info.
  LocalPlayback? _localParts;

  /// Whether media ever reached the engine under this session. A start
  /// that failed before loading has no position of its own: the engine's
  /// is the previous item's, or zero.
  bool _loaded = false;

  /// Where this item ended, when it ended on its own terms (an outro
  /// cutoff). The final checkpoint uses it instead of the engine's
  /// position, which stopped short of it by design.
  Duration? _endedAt;

  // Silence trimming. Spans are in the loaded file's own timeline.
  List<SkipSpan> _skipSpans = const [];
  int _lastJumpedSpan = -1;
  bool _skipMapRetried = false;

  // Episode outro cutoff, in the file timeline; null when unset.
  int? _outroCutoffMs;
  bool _outroFired = false;

  /// Whether silence trimming is currently on, for the player chip.
  final ValueNotifier<bool> trimEnabled = ValueNotifier(false);

  /// Whether spoken-word loudness normalization is on, for its chip.
  ///
  /// Unlike trimming, this one is the server's to apply: the stream is
  /// minted with it, so the chip persists the setting and reopens the
  /// stream rather than changing anything locally.
  final ValueNotifier<bool> voiceBoost = ValueNotifier(false);

  /// Milliseconds of silence skipped so far, for the trim chip's badge.
  ///
  /// Trimming only, which is what the control it feeds is about. The
  /// listen report adds what playing faster saved on top; a chip that
  /// counted both would credit the trim toggle with the speed chip's
  /// work.
  final ValueNotifier<int> hoursSavedMs = ValueNotifier(0);

  /// Prices [heard] milliseconds of content against the rate they were
  /// heard at.
  ///
  /// Content heard at 2x took half as long to sit through as the
  /// recording lasts, so half of it is time the listener got back. Rates
  /// at or below 1x save nothing: a listener slowing a lecture down is
  /// spending time, not saving it, and the counter this feeds only
  /// counts one direction.
  void _countSpeedSaving(int heard) {
    final rate = engine.speed;
    if (rate <= 1) return;
    _speedSavedMs += (heard * (1 - 1 / rate)).round();
  }

  final StreamController<void> _sessionCompleted =
      StreamController<void>.broadcast();

  /// Fires once when this item is truly over: the last part of a book
  /// ran out, or an episode reached its outro cutoff. Rolling from one
  /// part of a book to the next is internal and never fires here, so the
  /// queue above cannot mistake a part boundary for the end of an item.
  Stream<void> get sessionCompleted => _sessionCompleted.stream;

  final StreamController<Object> _sessionFailed =
      StreamController<Object>.broadcast();

  /// Fires when the session cannot do what its item needs mid-flight: a
  /// book part that would not load, a cross-part jump the server
  /// refused. The verbs that get here are unawaited at every call site
  /// (a chapter row, a bookmark, the roll off a part's end), so a
  /// rethrow would be an unhandled async error and a dead tap; this is
  /// where those failures land instead, for the layer above to surface
  /// the way it surfaces a failed start.
  Stream<Object> get sessionFailed => _sessionFailed.stream;

  /// The book detail behind an audiobook session (chapters, parts), when
  /// it could be fetched.
  BookDetail? get book => _book;

  bool get _isBook => item.mediaType == MediaType.audiobook;

  /// Whether this item carries spoken-word playback affordances.
  bool get isSpokenWord => item.mediaType != MediaType.music;

  /// Whether media has actually reached the engine under this session.
  /// Until it has, the engine's position and duration belong to whatever
  /// played before it, so nothing here reads as this item's.
  bool get isLoaded => _loaded;

  /// Current playback speed multiplier.
  double get speed => engine.speed;

  /// Duration to render the seek bar against: the whole book timeline
  /// for audiobooks, the loaded media otherwise.
  Duration get mediaDuration {
    if (_isBook) {
      final total = _book?.durationMs ?? item.durationMs;
      if (total > 0) return Duration(milliseconds: total);
    }
    return engine.duration ?? Duration(milliseconds: _loadedDurationMs);
  }

  /// Current position on the display timeline (book timeline for books).
  Duration get displayPosition => _display(engine.position);

  /// Position updates on the display timeline.
  Stream<Duration> get displayPositionStream =>
      engine.positionStream.map(_display);

  Duration _display(Duration enginePosition) =>
      Duration(milliseconds: _partStartMs + enginePosition.inMilliseconds);

  /// Fetches item config, play-info, and saved state, loads the stream at
  /// the resume position, and starts playing. When the server is
  /// unreachable and the item's original is downloaded, playback runs
  /// from the local file with the mirrored resume position instead.
  ///
  /// [autoplay] false loads and stops there, for a queue put back at
  /// launch: the item stands at its checkpoint until someone presses
  /// play.
  Future<void> start({bool autoplay = true}) async {
    _engineOwners[engine] = this;
    await _loadConfig();
    if (_disposed) return;
    try {
      var resumeMs = initialPositionMs;
      if (resumeMs == null) {
        final saved = await repository.getPlayState(item.pid);
        // A finished item has no resume point: its checkpoint sits at
        // its own end, and playing it again means playing it. Loading
        // media at the position it ends at also fails outright on web,
        // where the element answers "no supported source" for a source
        // it is asked to begin past, so this is the difference between
        // starting over and an error pane.
        resumeMs = saved.finished ? 0 : saved.positionMs;
        if (autoplay) {
          // Applied to the load rather than as a seek after it, so the
          // ordinary case has no stutter at the seam.
          resumeMs = _rewound(resumeMs, since: saved.updatedAt);
        } else {
          // A queue put back at launch stands at its checkpoint and may
          // never be played at all. Rewinding it here would move the
          // position this session goes on to write back, so ten cold
          // starts nobody listened to would walk a book backwards; the
          // step is owed to the first play and spent there.
          _restedSince = saved.updatedAt;
        }
      }
      // Let go while this was resolving: a tap on something else, or the
      // queue emptying. Loading here would put this item's media over
      // whatever took the engine, under a session nothing can reach.
      if (_disposed) return;
      if (_isBook) {
        await _loadPartFor(resumeMs, autoplay: false);
      } else {
        final info = await repository.getPlayInfo(item.pid);
        if (_disposed) return;
        _loadedDurationMs = info.durationMs;
        _applyOutroCutoff(info.durationMs);
        // The same guard against a checkpoint the media outgrew: a
        // position at or past the end is not a place to start, however
        // it got there (a re-imported file, a listen that rounded up,
        // a finished flag that never landed).
        if (info.durationMs > 0 && resumeMs >= info.durationMs) resumeMs = 0;
        resumeMs = _applyIntroSkip(resumeMs);
        final resumeAt = resumeMs > 0 ? Duration(milliseconds: resumeMs) : null;
        // A span means the URL carries the whole backing file (direct
        // playback of a carved track); the engine clips to the window
        // and every position stays track-relative.
        await engine.load(
          info.url,
          mimeType: info.mimeType,
          initialPosition: resumeAt,
          clipStart: info.spanStartMs == null
              ? null
              : Duration(milliseconds: info.spanStartMs!),
          clipEnd: info.spanEndMs == null
              ? null
              : Duration(milliseconds: info.spanEndMs!),
        );
        if (trimEnabled.value) unawaited(_loadSkipMap());
      }
    } on WaxDeckApiException catch (e) {
      final local = await _localFallback(e);
      if (local == null) rethrow;
      final saved = await sync?.localPlayState(item.pid);
      // The offline branch loads below; this is what keeps a session
      // already let go from doing so.
      if (_disposed) return;
      // A finished item starts over here too: the mirror keeps the same
      // checkpoint the server does, so a downloaded track listened to
      // the end would load at its own end with no network to correct
      // it.
      var resumeMs = initialPositionMs ?? 0;
      if (initialPositionMs == null && saved != null && !saved.finished) {
        resumeMs = saved.positionMs;
        if (autoplay) {
          resumeMs = _rewound(resumeMs, since: saved.updatedAt);
        } else {
          _restedSince = saved.updatedAt;
        }
      }
      // A downloaded book whose parts can be placed on its own timeline
      // resolves the part the resume position falls in, exactly as
      // play-info would have. Anything else - a track, a single-file
      // book, a book whose stored parts carry no durations - is the one
      // file this always loaded.
      if (_isBook && local.sequenced) {
        _localParts = local;
        await _loadPartFor(resumeMs, autoplay: false);
      } else {
        if (!_isBook) resumeMs = _applyIntroSkip(resumeMs);
        final resumeAt = resumeMs > 0 ? Duration(milliseconds: resumeMs) : null;
        // A carved item's file duration is the whole rip's, and the engine
        // is about to be clipped to the window: the loaded media is the
        // item's own length.
        final span = local.spanStartMs != null && (local.spanEndMs ?? 0) > 0
            ? local.spanEndMs! - local.spanStartMs!
            : null;
        _loadedDurationMs =
            span ?? local.parts.first.durationMs ?? item.durationMs;
        // Downloaded originals carry the same window; clipping here is
        // what makes an offline carved track play as itself instead of
        // the whole rip.
        await engine.load(
          Uri.file(local.parts.first.path).toString(),
          initialPosition: resumeAt,
          clipStart: local.spanStartMs == null
              ? null
              : Duration(milliseconds: local.spanStartMs!),
          // The server closes open-ended windows now; the zero guard
          // covers download records stored before it did (an open clip
          // end plays to the file's end, which is what those meant).
          clipEnd: local.spanEndMs == null || local.spanEndMs! <= 0
              ? null
              : Duration(milliseconds: local.spanEndMs!),
        );
      }
    }
    if (_disposed) return;
    // After whichever load branch ran, never before: the engine's rate
    // is player-level state that outlives sources, so a write up where
    // the config landed sat two round trips ahead of the load and
    // audibly re-rated the outgoing media - a 1.5x podcast dropping to
    // 1x while a tapped track resolved, and the reverse. Here the rate
    // only ever lands on media this session owns, loaded but not yet
    // audible.
    await engine.setSpeed(_configuredSpeed());
    if (_disposed) return;
    _lastPosition = engine.position;
    _loaded = true;
    _watchEngine();
    if (autoplay) {
      await engine.play();
    } else if (engine.playing) {
      // A load-paused start can land over live playback (a session
      // restored while something plays): the source swap alone does not
      // stop the transport, and put-it-back-paused means exactly that.
      await engine.pause();
    }
  }

  /// Takes over media the engine is already playing: this item was
  /// preloaded behind the previous one and the engine has crossed into
  /// it. [info] is the play-info that preload was minted from, so
  /// nothing is resolved, loaded, or seeked here: the stream never
  /// stopped, and this session picks up accounting where it stands.
  ///
  /// Only ever called for an item the preload admission policy let
  /// through, which is why the book and offline branches of [start] have
  /// no counterpart: neither is ever preloaded.
  Future<void> adopt(PlayInfo info) async {
    _engineOwners[engine] = this;
    await _loadConfig();
    if (_disposed) return;
    await engine.setSpeed(_configuredSpeed());
    if (_disposed) return;
    _loadedDurationMs = info.durationMs;
    _applyOutroCutoff(info.durationMs);
    _lastPosition = engine.position;
    _loaded = true;
    _watchEngine();
    if (trimEnabled.value) unawaited(_loadSkipMap());
    // Nothing here starts playback, but the checkpoint timer hangs off a
    // play transition that already happened under the previous session,
    // so this one is told what it walked into.
    if (engine.playing) _onPlayingChanged(true);
  }

  void _watchEngine() {
    _positionSub = engine.positionStream.listen(_onPosition);
    _playingSub = engine.playingStream.listen(_onPlayingChanged);
    _completedSub = engine.completed.listen((_) => _onCompleted());
  }

  /// Fetches the per-show or per-book playback config; playback works
  /// without it, so any failure just leaves the defaults in place.
  Future<void> _loadConfig() async {
    try {
      final it = item;
      if (item.mediaType == MediaType.podcast && it is EpisodeSummary) {
        final detail = await repository.getPodcast(it.showPid);
        _showSettings = detail.settings;
      } else if (_isBook) {
        final detail = await repository.getBook(item.pid);
        _book = detail;
        _bookSettings = detail.settings;
      }
    } on WaxDeckApiException {
      // Defaults apply; the player still plays.
    }
    // The device default is the seam behind the stored choice, spoken
    // word only: music has neither a trim chip nor a boost to open
    // with, so a default left on must not leak onto it.
    final fallbackTrim = isSpokenWord && defaultTrimSilence;
    final fallbackBoost = isSpokenWord && defaultVoiceBoost;
    trimEnabled.value = _isBook
        ? (_bookSettings?.trimSilence ?? fallbackTrim)
        : (_showSettings?.trimSilence ?? fallbackTrim);
    voiceBoost.value = _isBook
        ? (_bookSettings?.voiceBoost ?? fallbackBoost)
        : (_showSettings?.voiceBoost ?? fallbackBoost);
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

  void _applyOutroCutoff(int durationMs) {
    final outro = _showSettings?.skipOutroSeconds;
    if (outro == null || outro <= 0 || durationMs <= 0) return;
    final cutoff = durationMs - outro * 1000;
    if (cutoff > 0) _outroCutoffMs = cutoff;
  }

  /// Resolves and loads the part containing book-timeline [bookMs]
  /// (single-file items resolve to the whole file with partStartMs 0).
  ///
  /// The fallback to downloaded parts is here rather than at the call
  /// sites, so every crossing gets it: a seek, a chapter tap, the deck
  /// bar's skip, replay, and the roll off a part's end. Three of those do
  /// not await, so an escape would be an unhandled async error.
  ///
  /// Rethrows for parts that cannot be placed on a timeline, which is
  /// [start]'s own offline branch to answer: it has the mirror position.
  Future<void> _loadPartFor(int bookMs, {required bool autoplay}) async {
    final held = _localParts;
    if (held != null) {
      await _loadLocalPartFor(held, bookMs, autoplay: autoplay);
      return;
    }
    final PlayInfo info;
    try {
      info = await repository.getPlayInfo(item.pid, positionMs: bookMs);
    } on WaxDeckApiException catch (e) {
      final local = await _localFallback(e);
      if (_disposed) return;
      if (local == null || !local.sequenced) rethrow;
      _localParts = local;
      await _loadLocalPartFor(local, bookMs, autoplay: autoplay);
      return;
    }
    // Let go while the part was resolving: loading it now would put this
    // book over whatever took the engine.
    if (_disposed) return;
    // The timeline state moves only once the part's media is in the
    // engine. Written before the load, every checkpoint fired inside it
    // - and the load's own stop publishes a pause, whose checkpoint is
    // one - added the new part's start to the old part's engine position
    // and landed part-shifted on the book timeline; and a load that
    // threw needed everything rolled back. After it, the fields and the
    // media cannot disagree whichever way the load went. The skip-map
    // state rides with them: cleared against the old part, a refused
    // load would leave trimming silently dead for a part still playing.
    final partStartMs = info.partStartMs ?? 0;
    final inPartMs = bookMs - partStartMs;
    await engine.load(
      info.url,
      mimeType: info.mimeType,
      initialPosition: inPartMs > 0 ? Duration(milliseconds: inPartMs) : null,
    );
    // Let go while the part was loading: the play below would start the
    // engine on whatever a newer session has since loaded into it.
    if (_disposed) return;
    _loadedDurationMs = info.durationMs;
    _partIndex = info.partIndex;
    _partCount = info.partCount;
    _partStartMs = partStartMs;
    _skipSpans = const [];
    _lastJumpedSpan = -1;
    _skipMapRetried = false;
    _lastPosition = engine.position;
    if (trimEnabled.value) unawaited(_loadSkipMap());
    if (autoplay) await engine.play();
  }

  /// The same resolution against the download store: which downloaded
  /// part holds book-timeline [bookMs], and where on the timeline it
  /// starts.
  ///
  /// The state it sets is the state play-info sets, which is what makes
  /// everything above it - the display timeline, checkpoints in book
  /// milliseconds, a seek that leaves the part, the roll into the next
  /// one - behave offline exactly as it does online. No skip map is
  /// fetched: trimming needs a server, and this branch is the one that
  /// has none.
  Future<void> _loadLocalPartFor(
    LocalPlayback local,
    int bookMs, {
    required bool autoplay,
  }) async {
    final at = local.partAt(bookMs);
    final inPartMs = bookMs - at.startMs;
    // State follows the media, the same ordering as the online path and
    // for the same arithmetic: this is the one branch whose part-shifted
    // checkpoint no server write would ever correct - a downloaded part
    // pruned or corrupt would leave the final checkpoint claiming the
    // next part at the previous part's position, offline, for good.
    await engine.load(
      Uri.file(at.part.path).toString(),
      initialPosition: inPartMs > 0 ? Duration(milliseconds: inPartMs) : null,
    );
    if (_disposed) return;
    _loadedDurationMs = at.part.durationMs ?? 0;
    _partIndex = at.index;
    _partCount = local.parts.length;
    _partStartMs = at.startMs;
    _skipSpans = const [];
    _lastJumpedSpan = -1;
    _lastPosition = engine.position;
    if (autoplay) await engine.play();
  }

  /// The downloaded original, but only for failures that smell like
  /// unreachability; a real API rejection (404, 401) propagates.
  Future<LocalPlayback?> _localFallback(WaxDeckApiException e) async {
    final port = downloads;
    if (port == null) return null;
    if (e.statusCode != null && e.statusCode != 503) return null;
    return port.localFor(item.pid);
  }

  Future<void> toggle() async {
    if (engine.playing) {
      await engine.pause();
    } else {
      await engine.play();
    }
  }

  /// Steps back a little when the play that just started followed a
  /// break long enough to have lost the thread.
  ///
  /// Hung off the engine's own play transition rather than off a
  /// control, for the reason the pause is: a play arrives from the lock
  /// screen, a headset button, a media key, and a routed Connect
  /// command as well as from a button on a WaxDeck screen, and the
  /// overnight resume this exists for is most often one of those. A
  /// control-side step would have covered the one path that is hardest
  /// to reach and none of the ones a phone in a pocket actually uses.
  ///
  /// The cost is a seek just after the sound starts rather than just
  /// before, which is the same shape the silence-trim jump already has.
  void _rewindForBreak() {
    final since = _pausedAt ?? _restedSince;
    _pausedAt = null;
    _restedSince = null;
    if (!isSpokenWord || since == null) return;
    final back = smartRewind.rewindFor(_clock().difference(since));
    if (back <= Duration.zero) return;
    final target = displayPosition - back;
    unawaited(seek(target < Duration.zero ? Duration.zero : target));
  }

  /// The same for a resume that is a fresh start rather than a play:
  /// [positionMs] is the stored checkpoint and [since] is when it was
  /// written, which is when this listener stopped.
  ///
  /// Never past the head of the item, and never applied to an explicit
  /// position - a chapter tap or a shared timestamp is a request for a
  /// place, not a resume, and moving it would put the listener before
  /// the thing they asked for. That guard is the caller's: this only
  /// runs on the branch that read a checkpoint.
  int _rewound(int positionMs, {DateTime? since}) {
    if (!isSpokenWord || positionMs <= 0 || since == null) return positionMs;
    final back = smartRewind.rewindFor(_clock().difference(since));
    final rewound = positionMs - back.inMilliseconds;
    return rewound > 0 ? rewound : 0;
  }

  /// Seeks to a display-timeline position: the book timeline for books
  /// (crossing into another part re-resolves play-info), the media
  /// timeline otherwise.
  ///
  /// Answers whether the seek landed. A cross-part jump that fails is
  /// announced on [sessionFailed] rather than thrown - the UI call
  /// sites are unawaited (a chapter row, a bookmark, a transcript
  /// cue), so a rethrow would be an unhandled async error and a dead
  /// tap. The answer is for the caller that speaks for someone else (a
  /// routed Connect command): a session being torn down must not be
  /// acked to the remote as a seek that worked.
  Future<bool> seek(Duration position) async {
    // A session that has let go must not move an engine a newer one is
    // driving. The same rule the shutdown follows for `stop`, and it
    // belongs here too: a surface built with this session can outlive
    // it - a sheet holding the track it was opened over, a routed
    // command in flight - and the answer for those is that the seek did
    // not land, not that somebody else's item jumped.
    if (_disposed) return false;
    final targetMs = position.inMilliseconds;
    final withinPart =
        _partIndex == null ||
        (targetMs >= _partStartMs &&
            targetMs <= _partStartMs + _loadedDurationMs);
    if (withinPart) {
      await engine.seek(Duration(milliseconds: targetMs - _partStartMs));
      return true;
    }
    try {
      await _loadPartFor(targetMs, autoplay: engine.playing);
      return true;
    } on Object catch (error) {
      // The failure lands on the error surface: the layer above lets
      // the session go and stands the same pane a failed start gets,
      // with the checkpoint at the position the jump left.
      _announceFailed(error);
      return false;
    }
  }

  /// Sets the playback speed now and, for episodes and books, persists it
  /// as the item's remembered speed. Music never persists.
  Future<void> setSpeed(double speed, {bool persist = true}) async {
    await engine.setSpeed(speed);
    if (!persist) return;
    try {
      final it = item;
      if (item.mediaType == MediaType.podcast && it is EpisodeSummary) {
        final current = _showSettings;
        if (current == null) return;
        final updated = SubscriptionSettings(
          retentionKeep: current.retentionKeep,
          autoDownload: current.autoDownload,
          folder: current.folder,
          private: current.private,
          speed: speed,
          trimSilence: current.trimSilence,
          voiceBoost: current.voiceBoost,
          skipIntroSeconds: current.skipIntroSeconds,
          skipOutroSeconds: current.skipOutroSeconds,
        );
        _showSettings = updated;
        await repository.putSubscriptionSettings(it.showPid, updated);
      } else if (_isBook) {
        final current = _bookSettings ?? const BookSettings();
        final updated = BookSettings(
          speed: speed,
          voiceBoost: current.voiceBoost,
          trimSilence: current.trimSilence,
        );
        _bookSettings = updated;
        await repository.putBookSettings(item.pid, updated);
      }
    } on WaxDeckApiException {
      // The runtime speed stands; remembering it is best effort.
    }
  }

  /// Turns silence trimming on or off for this session.
  void setTrimEnabled(bool on) {
    trimEnabled.value = on;
    if (on && _skipSpans.isEmpty) {
      unawaited(_loadSkipMap());
    }
  }

  /// Turns spoken-word loudness normalization on or off for this show or
  /// book, and reopens the stream where it stands so the change is
  /// audible now rather than next time.
  ///
  /// The reopen is the part that makes the control honest: the boost is
  /// applied when the server mints the stream, so persisting alone would
  /// be a toggle that does nothing until the item is loaded again. A
  /// downloaded original carries no boost at all and cannot be given
  /// one, which is why the offline branch is left alone: the setting is
  /// stored for the next online play and the local file keeps playing.
  /// Answers whether the change took: false when there was nothing to
  /// store it on, which is a show whose settings this session could not
  /// fetch. The chip puts itself back for that, rather than reporting a
  /// state nothing holds and a reload that changed nothing.
  Future<bool> setVoiceBoost(bool on) async {
    voiceBoost.value = on;
    if (!await _persistVoiceBoost(on)) {
      voiceBoost.value = !on;
      return false;
    }
    if (_disposed || _localParts != null) return true;
    try {
      await _reopenForEffects();
    } on Object {
      // Best effort, and broader than an API failure on purpose: the
      // reopen crosses the engine too, and a platform that refuses the
      // media must not take playback down with it. The stored setting
      // stands and the next load applies it.
    }
    return true;
  }

  Future<bool> _persistVoiceBoost(bool on) async {
    try {
      final it = item;
      if (item.mediaType == MediaType.podcast && it is EpisodeSummary) {
        final current = _showSettings;
        if (current == null) return false;
        final updated = SubscriptionSettings(
          retentionKeep: current.retentionKeep,
          autoDownload: current.autoDownload,
          folder: current.folder,
          private: current.private,
          speed: current.speed,
          trimSilence: current.trimSilence,
          voiceBoost: on,
          skipIntroSeconds: current.skipIntroSeconds,
          skipOutroSeconds: current.skipOutroSeconds,
        );
        _showSettings = updated;
        await repository.putSubscriptionSettings(it.showPid, updated);
      } else if (_isBook) {
        final current = _bookSettings ?? const BookSettings();
        final updated = BookSettings(
          speed: current.speed,
          voiceBoost: on,
          trimSilence: current.trimSilence,
        );
        _bookSettings = updated;
        await repository.putBookSettings(item.pid, updated);
      }
      return true;
    } on WaxDeckApiException {
      // Best effort, like the speed memory beside it. Reported rather
      // than swallowed, because unlike a rate this one changes nothing
      // audible on its own: the server applies it when it mints the
      // stream, so a write that did not land is a control with no
      // effect at all.
      return false;
    }
  }

  /// Reopens the loaded media where it stands, for a change only a
  /// freshly minted stream can carry.
  Future<void> _reopenForEffects() async {
    var at = displayPosition.inMilliseconds;
    final playing = engine.playing;
    if (_isBook) {
      await _loadPartFor(at, autoplay: playing);
      return;
    }
    final info = await repository.getPlayInfo(item.pid);
    if (_disposed) return;
    // The same guard the first load carries: web answers "no supported
    // source" for a source it is asked to begin at or past the end, and
    // an episode toggled at its own end is exactly where this lands.
    if (info.durationMs > 0 && at >= info.durationMs) at = 0;
    await engine.load(
      info.url,
      mimeType: info.mimeType,
      initialPosition: at > 0 ? Duration(milliseconds: at) : null,
      clipStart: info.spanStartMs == null
          ? null
          : Duration(milliseconds: info.spanStartMs!),
      clipEnd: info.spanEndMs == null
          ? null
          : Duration(milliseconds: info.spanEndMs!),
    );
    if (_disposed) return;
    // After the load, like the part paths: a reopen that threw keeps
    // the state of the media the engine still describes.
    _loadedDurationMs = info.durationMs;
    _lastPosition = engine.position;
    if (playing) await engine.play();
  }

  /// Fetches the skip map for the loaded file. Pending maps get exactly
  /// one retry after [skipMapRetryDelay]; anything else leaves trimming
  /// inert for this load.
  Future<void> _loadSkipMap() async {
    _skipMapRetry?.cancel();
    final requestedPart = _partIndex;
    try {
      final map = await repository.getSkipMap(
        item.pid,
        partIndex: requestedPart,
      );
      if (_disposed || requestedPart != _partIndex) return;
      if (map.ready) {
        _skipSpans = map.spans;
        _lastJumpedSpan = -1;
      } else if (map.state == 'pending' && !_skipMapRetried) {
        _skipMapRetried = true;
        _skipMapRetry = Timer(skipMapRetryDelay, () {
          unawaited(_loadSkipMap());
        });
      }
    } on WaxDeckApiException {
      // Unavailable or unreachable: trimming stays off for this load.
    }
  }

  /// Plays this item again from the top: repeat-one, or a transport
  /// asking for the start of what is already loaded. The finished
  /// session was reported when it completed, so the next counted
  /// position mints a fresh listen session id and the second play is
  /// accounted as its own rather than extending the first.
  ///
  /// [play] false leaves it where a paused listener put it. Repeat-one
  /// passes true, because the engine stopped at the end of the item and
  /// nothing else would start it; a press of previous passes whether
  /// the item was playing, since a skip is not a play command.
  Future<void> replay({bool play = true}) async {
    _outroFired = false;
    _lastJumpedSpan = -1;
    _finished = false;
    // The end an outro cutoff recorded belonged to that play. Left
    // standing, the next checkpoint would write the item's end rather
    // than where this play actually stopped.
    _endedAt = null;
    // Through the display timeline, so a book on repeat-one goes back to
    // its first part rather than to the top of the part it ended on.
    await seek(Duration.zero);
    if (play) await engine.play();
  }

  /// Stops playback, flushing a final checkpoint and the listen report.
  ///
  /// The position is read here, synchronously: the engine is shared, and
  /// by the time the shutdown's awaits run a newer session may have
  /// loaded different media into it. The checkpoint must record where
  /// THIS item was, and stop() must not cut off the newer session.
  Future<void> dispose() => _shutdown(
    at: _endedAt ?? engine.position,
    finished: _finished,
    stopEngine: true,
  );

  /// Lets go of the engine without stopping it, for a hand-over to
  /// something that drives it directly (live radio). The item is
  /// checkpointed where it stands and its listen reported as unfinished;
  /// what plays next is the caller's business.
  Future<void> handOver() => _shutdown(
    at: _endedAt ?? engine.position,
    finished: _finished,
    stopEngine: false,
  );

  /// Finalizes this item because the engine walked out of it and into
  /// the item preloaded behind it. The checkpoint lands at this item's
  /// own end rather than at the engine's position, which already belongs
  /// to the next item, and the listen report says finished. The stream
  /// is left running: the next item's session adopts it.
  Future<void> finishAtBoundary() => _shutdown(
    at: Duration(
      milliseconds: _loadedDurationMs > 0 ? _loadedDurationMs : item.durationMs,
    ),
    finished: true,
    stopEngine: false,
  );

  Future<void> _shutdown({
    required Duration at,
    required bool finished,
    required bool stopEngine,
  }) async {
    if (_disposed) return;
    _disposed = true;
    _checkpointTimer?.cancel();
    _skipMapRetry?.cancel();
    // Cancellations are not awaited: an idle subscription's cancel future is
    // the root-zone null future, which never resumes inside the fake-async
    // zone widget tests run in. Cancelling takes effect synchronously.
    unawaited(_positionSub?.cancel());
    unawaited(_playingSub?.cancel());
    unawaited(_completedSub?.cancel());
    unawaited(_sessionCompleted.close());
    unawaited(_sessionFailed.close());
    // A start that never got as far as loading has nothing to record,
    // and the engine's position belongs to whatever played before it:
    // writing that as this item's resume point would lose the
    // listener's place on a failure they can retry.
    if (_loaded) await _checkpoint(at: at);
    await _reportSession(finished: finished);
    await _flushRetry();
    trimEnabled.dispose();
    voiceBoost.dispose();
    hoursSavedMs.dispose();
    if (identical(_engineOwners[engine], this)) {
      _engineOwners[engine] = null;
      if (stopEngine) await engine.stop();
    }
  }

  void _onPosition(Duration position) {
    if (_disposed) return;
    final delta = position - _lastPosition;
    _lastPosition = position;
    if (!engine.playing) return;
    if (delta > Duration.zero && delta <= maxCountedStep) {
      _ensureSession();
      _msPlayed += delta.inMilliseconds;
      _countSpeedSaving(delta.inMilliseconds);
    }
    _maybeTrimJump(position);
    _maybeOutroStop(position);
  }

  /// Entering a mapped silence span jumps forward to its end. Jumps only
  /// ever go forward and each span fires at most once per load, so a
  /// stubborn backend that lands short of the target cannot loop.
  void _maybeTrimJump(Duration position) {
    if (!trimEnabled.value || _skipSpans.isEmpty) return;
    final ms = position.inMilliseconds;
    for (var i = _lastJumpedSpan + 1; i < _skipSpans.length; i++) {
      final span = _skipSpans[i];
      if (ms >= span.startMs - trimWindowMs && ms < span.endMs) {
        _lastJumpedSpan = i;
        hoursSavedMs.value += span.endMs - ms;
        unawaited(engine.seek(Duration(milliseconds: span.endMs)));
        return;
      }
    }
  }

  /// Crossing the outro cutoff ends the episode as completed: the tail
  /// is credits the caller asked to skip.
  void _maybeOutroStop(Duration position) {
    final cutoff = _outroCutoffMs;
    if (cutoff == null || _outroFired) return;
    if (position.inMilliseconds < cutoff) return;
    _outroFired = true;
    _finished = true;
    unawaited(engine.pause());
    // The checkpoint records the real end so resume lands past the outro.
    // Held as well as written: the engine is paused at the cutoff, so a
    // final checkpoint taken from it would put the resume point back
    // before the outro and fire this again on the next play.
    final endMs = _loadedDurationMs > 0
        ? _loadedDurationMs
        : position.inMilliseconds;
    _endedAt = Duration(milliseconds: endMs);
    unawaited(_checkpoint(at: _endedAt!));
    unawaited(_reportSession(finished: true));
    _announceCompleted();
  }

  void _onPlayingChanged(bool playing) {
    if (_disposed) return;
    if (playing) {
      _rewindForBreak();
      _ensureSession();
      _checkpointTimer?.cancel();
      _checkpointTimer = Timer.periodic(
        checkpointInterval,
        (_) => _checkpoint(),
      );
    } else {
      // Stamped from the engine's own transition rather than from the
      // control that caused it: a pause arrives from the lock screen,
      // a headset button, a routed Connect command, and an interruption
      // the platform made on its own, and all of them are a listener
      // who stopped listening.
      _pausedAt ??= _clock();
      _checkpointTimer?.cancel();
      _checkpointTimer = null;
      unawaited(_checkpoint());
    }
  }

  void _onCompleted() {
    if (_disposed) return;
    final index = _partIndex;
    final count = _partCount;
    if (index != null && count != null && index < count - 1) {
      // The book has more parts: roll into the next one seamlessly.
      unawaited(_advanceToNextPart());
      return;
    }
    _finished = true;
    unawaited(_checkpoint());
    unawaited(_reportSession(finished: true));
    _announceCompleted();
  }

  Future<void> _advanceToNextPart() async {
    try {
      // Falls back to the downloaded parts itself where there are any:
      // a server that went away mid-book does not end a book somebody
      // downloaded, which is the whole point of downloading one.
      await _loadPartFor(_partStartMs + _loadedDurationMs, autoplay: true);
    } on Object catch (error) {
      // Nothing to carry on from: the server refused the next part with
      // nothing local behind it, or the part's media would not open.
      // Broader than the API type on purpose - an engine failure used
      // to escape this unawaited zone as an unhandled async error, and
      // the book stopped dead with no error state and the session still
      // installed. The failure lands on the error surface instead; the
      // release that answers it flushes the checkpoint at the boundary
      // this play actually reached and reports the listen unfinished,
      // which is what it is.
      _announceFailed(error);
    }
  }

  /// Tells the layer above that this item is over. Reported after the
  /// checkpoint and the listen report are on their way, so whatever
  /// advances the queue cannot outrun this item's own accounting.
  void _announceCompleted() {
    if (!_sessionCompleted.isClosed) _sessionCompleted.add(null);
  }

  /// Tells the layer above this session could not do what its item
  /// needed and should be let go, with [error] as the reason to show.
  void _announceFailed(Object error) {
    if (!_sessionFailed.isClosed) _sessionFailed.add(error);
  }

  /// Mints the idempotency ID the first time playback makes progress and
  /// whenever a new run starts after the previous session was reported.
  void _ensureSession() {
    if (_sessionId != null) return;
    _sessionId = newListenSessionId();
    _startedAt = DateTime.now().toUtc();
    _msPlayed = 0;
    _skippedAtSessionStart = hoursSavedMs.value;
    _speedSavedAtSessionStart = _speedSavedMs;
  }

  /// Checkpoints [at] (engine timeline; defaults to the live position),
  /// reported to the server on the display timeline: books checkpoint
  /// book-timeline positions.
  Future<void> _checkpoint({Duration? at}) async {
    final position = _display(at ?? engine.position);
    try {
      await repository.putPlayState(item.pid, position.inMilliseconds);
    } on WaxDeckApiException {
      // ANY failure queues, deliberately broader than the reachability
      // gate elsewhere: queued checkpoints replay with recordedAt and
      // reconcile server-side, flushOutbox drops permanent rejections,
      // and a transient auth failure would otherwise silently lose the
      // position. Without an engine (web), best effort stands and the
      // next checkpoint catches up.
      await sync?.queueCheckpoint(item.pid, position.inMilliseconds);
    }
  }

  /// Milliseconds of content this listen session did not sit through,
  /// for the server's time-saved counter.
  ///
  /// The two things the field is defined as, added: what trimming jumped
  /// over, and what playing faster than the recording gave back. Both
  /// are accumulated where they happen - the jump that skipped a span
  /// adds its own length, and every counted delta is priced at the rate
  /// it was heard at - so this is a sum rather than a measurement.
  ///
  /// It is deliberately *not* content minus wall clock, which is the
  /// obvious formulation and is wrong twice over. A trim jump and a hand
  /// on the seek bar look identical as a position delta, so content read
  /// off raw movement counts a scrub through an hour as an hour saved.
  /// And wall clock counts every second that passed, including the ones
  /// that saved nobody anything: a rebuffer, a phone that slept, a
  /// browser tab throttled in the background. Subtracting those would
  /// let a stalled stream eat a real saving and report zero beside a
  /// trim chip saying thirty seconds.
  int _timeSavedMs() {
    final trimmed = hoursSavedMs.value - _skippedAtSessionStart;
    final faster = _speedSavedMs - _speedSavedAtSessionStart;
    return (trimmed > 0 ? trimmed : 0) + (faster > 0 ? faster : 0);
  }

  /// Reports the open session once. On network failure the session is kept
  /// and retried on dispose; the server deduplicates on the session ID, so
  /// the retry can never double-count.
  Future<void> _reportSession({required bool finished}) async {
    final sessionId = _sessionId;
    final startedAt = _startedAt;
    _sessionId = null;
    _startedAt = null;
    if (sessionId == null || startedAt == null || _msPlayed <= 0) return;
    final skipped = _timeSavedMs();
    final session = ListenSession(
      sessionId: sessionId,
      pid: item.pid,
      startedAt: startedAt,
      msPlayed: _msPlayed,
      skippedMs: skipped > 0 ? skipped : null,
      finished: finished,
      client: clientId,
    );
    _msPlayed = 0;
    _finished = false;
    try {
      await repository.reportListens([session]);
    } on WaxDeckApiException {
      final engine = sync;
      if (engine != null) {
        await engine.queueListen(session);
      } else {
        _pendingRetry = session;
      }
    }
  }

  Future<void> _flushRetry() async {
    final retry = _pendingRetry;
    if (retry == null) return;
    _pendingRetry = null;
    try {
      await repository.reportListens([retry]);
    } on WaxDeckApiException {
      // Web only (native queues instead of retrying): gone for good
      // once the session ends.
    }
  }
}
