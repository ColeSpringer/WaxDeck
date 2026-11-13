import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

import 'listen_outbox.dart';
import 'smart_rewind.dart';

// Most of the session's private machinery lives in the parts, as extensions
// on it. A method handed to addListener or removeListener stays in the class:
// an extension tear-off is never equal to another tear-off of the same member.
part 'session/session_events.dart';
part 'session/session_lifecycle.dart';
part 'session/session_listen.dart';
part 'session/session_media.dart';
part 'session/session_recovery.dart';

/// One member of a minted timeline: the stream and which item of it
/// this session is.
///
/// A session handed one of these skips play-info resolution entirely -
/// the URL is already minted, and the member's own duration is already
/// known - and loads through the timeline engine, which crosses into
/// the next member without stopping.
class TimelineSlot {
  const TimelineSlot(this.media, this.member);

  final TimelineMedia media;
  final int member;

  /// The member's own duration, which is what this item reports and
  /// what a finished listen is credited with.
  int get durationMs => media.memberDurationMs(member);
}

/// How an item came to be over, for the layer that moves the queue.
enum SessionEnd {
  /// It played out, or reached its outro cutoff.
  played,

  /// A play pressed on an end an armed stop was holding: whatever follows
  /// it plays, and with nothing following, the item again.
  heldEndPlayed,
}

/// How the item rests at its end, when it does.
enum _AtEnd {
  /// It does not.
  none,

  /// At its end, the engine perhaps a few milliseconds short of it: a play
  /// starts it over, as one after its own end does.
  rests,

  /// The last part ended at an armed stop: the item is over, and the end
  /// that would have moved the queue on is held for the next play.
  held,
}

/// How a move reached its target.
enum _Moved {
  /// A seek inside the loaded media.
  seeked,

  /// A load of the session's own, which ended playing or paused as asked.
  reloaded,

  /// It did not get there.
  not,
}

/// A failure a session could not get past, whether playback meant to be
/// running when it struck (what decides whether it may start again by
/// itself once the server is back), and where on the display timeline the
/// item stood, which a retry picks up from.
typedef SessionFailure = ({Object error, bool meantToPlay, int atMs});

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
    this.maxBitrateKbps,
    this.timeline,
    this.listenOutbox,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final WaxDeckRepository repository;
  final AudioEnginePort engine;
  final ItemSummary item;

  /// The timeline member this item is, when a whole queue is playing as
  /// one stream. Null is the ordinary path: one item, one stream URL.
  final TimelineSlot? timeline;
  final String clientId;

  /// The sync engine, when this platform runs one: offline mutations
  /// queue through it instead of being dropped.
  final SyncEngine? sync;

  /// Downloaded originals, for playback when the server is unreachable.
  final DownloadManagerPort? downloads;

  /// Where a listen that could not be reported waits, when this platform
  /// runs no [sync] engine to queue it in.
  final ListenOutbox? listenOutbox;
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

  /// The bitrate cap every play-info this session mints asks for; null
  /// streams the original. Read once at build for the same reason
  /// [defaultSpeed] is: a changed quality setting applies from the next
  /// track, never mid-stream.
  final int? maxBitrateKbps;

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
  StreamSubscription<MediaFailure>? _failureSub;
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

  /// The play-info the loaded media was minted from. Null for a timeline
  /// member and a downloaded file, which nothing here can mint again.
  PlayInfo? _info;

  /// When the loaded stream reads stale on this device's clock, fixed as
  /// it loads (see [_hold]).
  DateTime? _staleAt;

  /// Whether the loaded stream's token has lapsed (or is about to), so a
  /// play from here would meet a refusal.
  bool get _streamStale {
    final staleAt = _staleAt;
    return _info != null && staleAt != null && !_clock().isBefore(staleAt);
  }

  /// A load of this session's own is under way: the first one, a reload
  /// where it stands, a move into another part, the stop at a part's end.
  /// A press made meanwhile changes what it ends with ([_resumeWanted])
  /// and a seek where it lands ([_pendingSeekMs]), so nothing starts a
  /// second load beside it: the engine fails an overtaken load, and a
  /// session that minted again for that failure fought itself.
  bool _busy = false;

  /// Whether the load under way ends playing.
  bool _resumeWanted = false;

  /// Effects only a fresh mint carries changed while a load was under
  /// way: it mints once more before it lets go.
  bool _remint = false;

  /// Settles with whether the load under way landed, which is what a seek
  /// folded into it answers.
  Completer<bool>? _landed;

  /// How the item rests at its end, when it does.
  _AtEnd _atEnd = _AtEnd.none;

  /// The newest seek made while a load was under way, applied once it
  /// lands. Only the newest: a cut is a whole encode of the rest of the
  /// item, so the targets in between are never worth loading.
  int? _pendingSeekMs;

  /// Where the served audio begins on the loaded media's own timeline,
  /// when the server cut a stream that answers no ranges; zero otherwise.
  /// The engine's clock starts at the cut, so this is added back to every
  /// position it reports.
  int _cutMs = 0;

  /// How far past what a cut stream has buffered a seek may still go
  /// without a reload: the media keeps arriving while the seek waits.
  static const _bufferSlackMs = 2000;

  /// Display-timeline position where playback rests on its own (the
  /// sleep timer's end of chapter); null when nothing is armed.
  int? _stopAtMs;

  /// A stop at the end of the loaded media is under way: the media's own
  /// end, arriving meanwhile, belongs to that stop and is no roll-over.
  bool _stopping = false;

  /// How near the end of the loaded media a boundary counts as that end.
  static const _stopSlackMs = 250;

  /// How near the end of the audio a checkpoint counts as that end: a
  /// listen heard through rather than a place to resume.
  static const _resumeSlackMs = 5000;

  /// Engine loads in flight. A load stops the outgoing media first, and
  /// the pause that publishes must not checkpoint: the engine's position
  /// is already the new media's while the timeline state is still the old.
  int _loading = 0;

  /// Loads begun under this session, ever: whether a failure came before
  /// the outgoing media was stopped or after.
  int _loadsBegun = 0;

  /// Where on the display timeline the load under way lands, which is the
  /// place to show and to record for a session let go meanwhile.
  int? _loadTarget;

  /// Where the item stood before a load that failed: the engine stopped
  /// the outgoing media first and now reads the incoming media's start,
  /// against a timeline that never moved. Cleared by a load that works.
  int? _stoodBeforeFailedLoad;

  /// Where the item stood when this session said it failed: what its
  /// release records, whatever the engine reads by then.
  int? _failedAtMs;

  /// Recoveries since playback last proved itself, and where the last one
  /// reloaded. A stream that fails again before it has played on for
  /// [_provenMs] spends the budget; one that keeps failing is said.
  int _recoveries = 0;
  int? _recoveredAtMs;
  static const _recoveryBudget = 2;
  static const _provenMs = 5000;

  /// Where this item ended, when it ended on its own terms (an outro
  /// cutoff). The final checkpoint uses it instead of the engine's
  /// position, which stopped short of it by design.
  Duration? _endedAt;

  // Silence trimming. Spans are in the loaded file's own timeline.
  List<SkipSpan> _skipSpans = const [];
  int _lastJumpedSpan = -1;
  bool _skipMapRetried = false;

  // Whether the episode outro cutoff ([_outroCutoffMs]) has fired.
  bool _outroFired = false;

  /// Whether silence trimming is currently on, for the player chip.
  final ValueNotifier<bool> trimEnabled = ValueNotifier(false);

  /// Whether spoken-word loudness normalization is on, for its chip.
  ///
  /// Unlike trimming, this one is the server's to apply: the stream is
  /// minted with it, so the chip persists the setting and reopens the
  /// stream rather than changing anything locally.
  final ValueNotifier<bool> voiceBoost = ValueNotifier(false);

  /// A load of this session's own is opening the item to play it: the
  /// engine stands stopped for the load, and the transport still means to
  /// play.
  final ValueNotifier<bool> reopening = ValueNotifier(false);

  void _markReopening() {
    if (!_disposed) reopening.value = _busy && _resumeWanted;
  }

  /// Whether a play/pause control reads as playing: the engine, or a load
  /// under way that means to play ([reopening]). What every transport
  /// draws and what [toggle] reverses, so a press means what it shows.
  bool get meansToPlay => engine.playing || reopening.value;

  /// [meansToPlay] as it changes; one stream per session, so a widget
  /// that reads it on every build keeps its subscription.
  late final Stream<bool> meansToPlayStream = Stream<bool>.multi((out) {
    void emit() => out.add(meansToPlay);
    final playing = engine.playingStream.listen((_) => emit());
    final listening = !_disposed;
    if (listening) reopening.addListener(emit);
    // Not awaited, for the reason [_shutdown] gives.
    out.onCancel = () {
      unawaited(playing.cancel());
      if (listening) reopening.removeListener(emit);
    };
  }, isBroadcast: true).distinct();

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

  final StreamController<SessionEnd> _sessionCompleted =
      StreamController<SessionEnd>.broadcast();

  /// Fires once when this item is truly over: the last part of a book
  /// ran out, or an episode reached its outro cutoff, or a play released
  /// an end an armed stop held. Rolling from one part of a book to the
  /// next is internal and never fires here, so the queue above cannot
  /// mistake a part boundary for the end of an item.
  Stream<SessionEnd> get sessionCompleted => _sessionCompleted.stream;

  final StreamController<void> _stopReached =
      StreamController<void>.broadcast();

  /// Fires when the stop [stopAt] armed is spent: playback reached it and
  /// rests there, or a seek moved past it.
  Stream<void> get stopReached => _stopReached.stream;

  /// Arms a stop at [displayMs] on the display timeline, or disarms it
  /// with null. Playback pauses there and parks on it, so a resume starts
  /// what follows at its head. Owned here rather than by whoever armed it,
  /// because a boundary at the end of a file races the file's own end,
  /// and only the session sees both.
  void stopAt(int? displayMs) {
    _stopAtMs = displayMs;
    // Armed after playback passed it (a sheet left open across a chapter
    // end): spent now rather than parked on behind the listener.
    if (displayMs != null &&
        _loaded &&
        !_busy &&
        displayMs < displayPosition.inMilliseconds) {
      _stopAtMs = null;
      _announceStopReached();
    }
  }

  /// A [stopAt] position past any the media can reach, so only its own
  /// end does: a stop there rests wherever the loaded media ends, for
  /// audio whose length nothing reports.
  static const mediaEndStopMs = 1 << 40;

  /// Where the loaded media ends on the display timeline as far as
  /// anything to be trusted says (see [_mediaEndMs]); null when nothing
  /// does.
  int? get knownEndMs => _mediaEndMs;

  final StreamController<SessionFailure> _sessionFailed =
      StreamController<SessionFailure>.broadcast();

  /// Fires when the session cannot do what its item needs mid-flight: a
  /// book part that would not load, a cross-part jump the server
  /// refused. The verbs that get here are unawaited at every call site
  /// (a chapter row, a bookmark, the roll off a part's end), so a
  /// rethrow would be an unhandled async error and a dead tap; this is
  /// where those failures land instead, for the layer above to surface
  /// the way it surfaces a failed start.
  Stream<SessionFailure> get sessionFailed => _sessionFailed.stream;

  final StreamController<Object> _moveFailed =
      StreamController<Object>.broadcast();

  /// Fires when a seek could not be had and playback went on as it was:
  /// nothing to let go of, only something to say. An effect that could
  /// not reopen the stream says nothing, since its stored setting is
  /// applied by the next load anyway.
  Stream<Object> get moveFailed => _moveFailed.stream;

  /// The book detail behind an audiobook session (chapters, parts), when
  /// it could be fetched.
  BookDetail? get book => _book;

  bool get _isBook => item.mediaType == MediaType.audiobook;

  /// Whether play-info's length can be a feed's word rather than the
  /// audio's: an episode not known to be downloaded, which the server
  /// streams from its feed with the length the feed declares.
  bool get _lengthMayBeDeclared {
    final it = item;
    return it.mediaType == MediaType.podcast &&
        !(it is EpisodeSummary && it.downloaded);
  }

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
    // A cut stream's own clock covers only what is left of the item.
    if (_cutMs > 0) return Duration(milliseconds: _loadedDurationMs);
    return engine.duration ?? Duration(milliseconds: _loadedDurationMs);
  }

  /// Current position on the display timeline (book timeline for books),
  /// or, while a load of this session's own is under way, where it is
  /// taking the listener: the engine reads the media being replaced, or
  /// already the new media against the old timeline.
  Duration get displayPosition => _shown(engine.position);

  Duration _shown(Duration enginePosition) {
    final target = _pendingSeekMs ?? _loadTarget;
    if (_busy && target != null) return Duration(milliseconds: target);
    return _display(enginePosition);
  }

  /// Position updates on the display timeline, and one more each time the
  /// timeline itself moves under the engine (another part, another cut):
  /// the element reports the new media's position before its load
  /// answers, read against the old timeline, and a paused one says
  /// nothing after.
  Stream<Duration> get displayPositionStream => Stream<Duration>.multi((out) {
    final positions = engine.positionStream.listen(
      (position) => out.add(_shown(position)),
      onError: out.addError,
    );
    final moves = _timelineMoved.stream.listen((_) => out.add(displayPosition));
    // Not awaited, for the reason [_shutdown] gives.
    out.onCancel = () {
      unawaited(positions.cancel());
      unawaited(moves.cancel());
    };
  });

  final StreamController<void> _timelineMoved =
      StreamController<void>.broadcast();

  void _announceTimelineMoved() {
    if (!_timelineMoved.isClosed) _timelineMoved.add(null);
  }

  final StreamController<void> _mediaLoaded =
      StreamController<void>.broadcast();

  /// Fires each time this session puts media into the engine, the first
  /// load and every one after it: whatever the engine had prepared to
  /// follow the item went with what was replaced.
  Stream<void> get mediaLoaded => _mediaLoaded.stream;

  void _announceMediaLoaded() {
    if (!_mediaLoaded.isClosed) _mediaLoaded.add(null);
  }

  Duration _display(Duration enginePosition) => Duration(
    milliseconds: _partStartMs + _cutMs + enginePosition.inMilliseconds,
  );

  /// Fetches item config, play-info, and saved state, loads the stream at
  /// the resume position, and starts playing. When the server is
  /// unreachable and the item's original is downloaded, playback runs
  /// from the local file with the mirrored resume position instead.
  ///
  /// [autoplay] false loads and stops there, for a queue put back at
  /// launch: the item stands at its checkpoint until someone presses
  /// play.
  Future<void> start({bool autoplay = true}) {
    _engineOwners[engine] = this;
    // The first load is one under way like any other: a press made while
    // it resolves decides how it lands, and a seek waits for it.
    return _underway(
      initialPositionMs ?? 0,
      resume: autoplay,
      load: () => _open(autoplay: autoplay),
    );
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
    await (_configLoad = _loadConfig());
    if (_disposed) return;
    await engine.setSpeed(_configuredSpeed());
    if (_disposed) return;
    // A timeline member's info is the rendering's, which the feeder keeps
    // and nothing here can mint again.
    _moveTimeline(
      info: timeline == null ? info : null,
      cutMs: info.startOffsetMs,
      durationMs: info.durationMs,
    );
    _lastPosition = engine.position;
    _loaded = true;
    _watchEngine();
    if (trimEnabled.value) unawaited(_loadSkipMap());
    // Nothing here starts playback, but the checkpoint timer hangs off a
    // play transition that already happened under the previous session,
    // so this one is told what it walked into.
    if (engine.playing) _onPlayingChanged(true);
  }

  /// The in-flight (or finished) config load, so a write that arrives
  /// before it does can wait for it rather than run without it.
  Future<void>? _configLoad;

  /// Re-opens the same item on a freshly minted timeline, at the
  /// position it stands at.
  ///
  /// The one mid-track reload a timeline listener can hear, and only
  /// for a stream that stopped being servable underneath them. Modelled
  /// on the effects re-open: same listen session, same accounting, same
  /// resume, and the transport left as it was found.
  /// [resume] rather than the engine's own `playing`, which by this
  /// point always reads false: silencing the stream is part of losing
  /// it, so what the listener had asked for only survives in the loss
  /// itself.
  ///
  /// Spends the same budget a stream's recoveries do: a timeline lost
  /// again before playback proved itself is not re-minted for ever
  /// ([mayRecover]).
  Future<void> reloadTimeline(TimelineSlot slot, {required bool resume}) {
    final at = displayPosition;
    _recoveries++;
    _recoveredAtMs = at.inMilliseconds;
    return _underway(
      at.inMilliseconds,
      resume: resume,
      load: () async {
        // Let go while the mint was out: loading now would put this item
        // over whatever took the engine.
        if (_disposed) return;
        await _loadTimelineMedia(slot, at);
        if (_disposed) return;
        _moveTimeline(durationMs: slot.durationMs);
      },
    );
  }

  /// Whether a stream lost again may be reloaded again: not once reloads
  /// have kept failing before playback proved itself.
  bool get mayRecover => _recoveries < _recoveryBudget;

  /// Starts playback, whoever asked.
  ///
  /// Every play that reaches this session goes through here rather than
  /// at the engine, because a play after the item ended is a replay and
  /// [replay] is the only place the per-play bookkeeping resets. Left to
  /// `engine.play`, the item would restart while `_finished` still said
  /// the last play finished it, so the next report would call this play
  /// finished too, and `_lastJumpedSpan` would still be at the end of
  /// the list, suppressing the intro skip the replay should make again.
  /// It also rewinds a book to its first part rather than to the top of
  /// the part it ended on, which the engine alone cannot do.
  ///
  /// A pause is stamped from the engine's own transition, in
  /// [_onPlayingChanged], so that an interruption the platform made counts
  /// the same as a press; a press still comes through [pause], which is
  /// what folds it into a load under way.
  ///
  /// A stream whose token has lapsed (a long pause outlives one) is minted
  /// again and reloaded where the listener stands, rather than handed to
  /// an engine that would only meet the refusal.
  Future<void> play() async {
    if (_busy) {
      _resumeWanted = true;
      _markReopening();
      return;
    }
    if (engine.playing) return;
    if (_atEnd == _AtEnd.held) {
      // The end that would have moved the queue on under a sleeper.
      _atEnd = _AtEnd.rests;
      _announceCompleted(SessionEnd.heldEndPlayed);
      return;
    }
    if (_atEnd == _AtEnd.rests ||
        engine.processingState == EngineProcessingState.completed) {
      await replay();
      return;
    }
    if (_streamStale) {
      // The rewind a long break earns is applied to the reload, so the
      // play that follows it does not seek a second time.
      final since = _pausedAt ?? _restedSince;
      _pausedAt = null;
      _restedSince = null;
      final at = _startAt(
        _rewound(displayPosition.inMilliseconds, since: since),
      );
      await _recover(at, resume: true);
      return;
    }
    await engine.play();
  }

  /// A press of the one play/pause control: it reverses what the control
  /// shows ([meansToPlay]), a load under way included.
  Future<void> toggle() => meansToPlay ? pause() : play();

  /// Pauses, folding into a load under way so it does not start what the
  /// listener stopped.
  Future<void> pause() async {
    if (_busy) {
      _resumeWanted = false;
      _markReopening();
    }
    await engine.pause();
  }

  /// Stops for a stop raised outside the app (a lock screen, a routed
  /// command): the media is let go and the item stays where it stood. A
  /// load under way lands paused instead, since stopping the engine under
  /// it would only fail the load.
  Future<void> stop() async {
    if (_busy) {
      _resumeWanted = false;
      _markReopening();
      if (_loading > 0) return;
    }
    await engine.stop();
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
  ///
  /// A stream the server cuts (it answers no ranges) is seeked only
  /// inside what it has buffered; anywhere else is minted again, cut at
  /// the target. Seeks made while a reload is in flight fold into it.
  /// Every seek that lands is checkpointed, so a paused scrub followed by
  /// a closed tab keeps the place it chose.
  Future<bool> seek(Duration position) async {
    // A session that has let go must not move an engine a newer one is
    // driving. The same rule the shutdown follows for `stop`, and it
    // belongs here too: a surface built with this session can outlive
    // it - a sheet holding the track it was opened over, a routed
    // command in flight - and the answer for those is that the seek did
    // not land, not that somebody else's item jumped. Nor one that was
    // never started: there is no load for it to wait on. One made while
    // the first load is under way waits for it, below: the engine still
    // holds the item before it, and is no place to move.
    if (_disposed || !_loaded && !_busy) return false;
    _atEnd = _AtEnd.none;
    // The end an outro cutoff recorded belonged to the play that reached
    // it; one moved back from there is listening again.
    _endedAt = null;
    var targetMs = position.inMilliseconds < 0 ? 0 : position.inMilliseconds;
    final cutoff = _outroCutoffMs;
    if (cutoff != null && targetMs - _partStartMs < cutoff) _outroFired = false;
    // Past the end is the end (a skip near it, from here or the lock
    // screen): a part loaded beyond its own end fails on web. The end the
    // transport draws, which for an uncut stream is the audio's own: a
    // feed's declared length can fall short of it.
    final length = _knownLengthMs;
    if (length > 0 && targetMs > length) targetMs = length;
    final stop = _stopAtMs;
    if (stop != null && targetMs >= stop) {
      // Jumping past the boundary is not reaching it: spent, no pause.
      _stopAtMs = null;
      _announceStopReached();
    }
    if (_busy) {
      _pendingSeekMs = targetMs;
      return _landed!.future;
    }
    return await _moveTo(targetMs, resume: engine.playing) != _Moved.not;
  }

  /// Moves to [targetMs] on the display timeline: a seek inside the
  /// loaded media, or a load of its own where a seek cannot reach
  /// (another part, a cut stream past what it holds), ending as [resume]
  /// says. A move that lands is checkpointed, so a paused scrub followed
  /// by a closed tab keeps the place it chose.
  ///
  /// [keep] is a move away from media still worth hearing (see
  /// [_reloadKeeping]); a replay's is from an end, with nothing to keep,
  /// so a failure there is said.
  Future<_Moved> _moveTo(
    int targetMs, {
    required bool resume,
    bool keep = true,
  }) async {
    if (_withinPart(targetMs) && !_needsCut(targetMs)) {
      await engine.seek(_inMedia(targetMs));
      if (_disposed) return _Moved.not;
      unawaited(_checkpoint());
      return _Moved.seeked;
    }
    final landed = keep
        ? await _reloadKeeping(atMs: targetMs, resume: resume, say: true)
        : await _recover(targetMs, resume: resume);
    if (!landed) return _Moved.not;
    unawaited(_checkpoint());
    return _Moved.reloaded;
  }

  /// Whether [targetMs] lies in the loaded part. Half-open, as the server
  /// resolves parts: the first millisecond of the next part belongs to
  /// it, except at the very end of the book.
  bool _withinPart(int targetMs) {
    if (_partIndex == null) return true;
    final partEnd = _partStartMs + _loadedDurationMs;
    return targetMs >= _partStartMs &&
        (targetMs < partEnd || !_hasNextPart && targetMs <= partEnd);
  }

  /// Whether the loaded part has another after it.
  bool get _hasNextPart {
    final index = _partIndex;
    final count = _partCount;
    return index != null && count != null && index < count - 1;
  }

  /// Display position [displayMs] on the loaded media's own clock.
  Duration _inMedia(int displayMs) =>
      Duration(milliseconds: displayMs - _partStartMs - _cutMs);

  /// Whether the loaded stream answers no ranges on an engine that
  /// restarts such a stream at any seek.
  bool get _cantSeekHere =>
      _info?.seekable == false && !engine.seeksWithinUnrangedStream;

  /// Whether [targetMs] (display timeline) is out of the loaded media's
  /// reach by seeking: a cut stream answers no ranges, so it reaches only
  /// what it has buffered, and never back before where it was cut.
  bool _needsCut(int targetMs) {
    final info = _info;
    if (info == null || info.seekable) return false;
    if (!engine.seeksWithinUnrangedStream) return true;
    final inMedia = _inMedia(targetMs).inMilliseconds;
    return inMedia < 0 ||
        inMedia > engine.bufferedPosition.inMilliseconds + _bufferSlackMs;
  }

  /// Sets the playback speed now and, for episodes and books, persists it
  /// as the item's remembered speed. Music never persists.
  Future<void> setSpeed(double speed, {bool persist = true}) async {
    await engine.setSpeed(speed);
    if (!persist) return;
    try {
      final it = item;
      if (item.mediaType == MediaType.podcast && it is EpisodeSummary) {
        final current = await _storedShowSettings(it.showPid);
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
    // A mint that fails leaves the old media playing, and the stored
    // setting is applied by the next load; a load that began and failed
    // has stopped the old media, so that is said, as a seek's is.
    if (!_disposed) await _reopenForEffects();
    return true;
  }

  Future<bool> _persistVoiceBoost(bool on) async {
    try {
      final it = item;
      if (item.mediaType == MediaType.podcast && it is EpisodeSummary) {
        final current = await _storedShowSettings(it.showPid);
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
  /// freshly minted stream can carry. A downloaded file or a timeline
  /// member has nothing to mint, so the stored setting waits for the next
  /// online play. A load under way mints once more instead, so its target
  /// and its intent to play stand.
  Future<void> _reopenForEffects() async {
    if (_busy) {
      _remint = true;
      return;
    }
    if (_info == null) return;
    await _reloadKeeping(
      atMs: _startAt(displayPosition.inMilliseconds),
      resume: engine.playing,
    );
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
  ///
  /// A play from the end of the item can be a reload (the port's
  /// [AudioEnginePort.play]), and one that fails is announced on
  /// [sessionFailed] rather than thrown, for the reason [seek] gives:
  /// the transport's toggle and repeat-one both reach here unawaited.
  Future<void> replay({bool play = true}) async {
    _atEnd = _AtEnd.none;
    _outroFired = false;
    _lastJumpedSpan = -1;
    _finished = false;
    // The end an outro cutoff recorded belonged to that play. Left
    // standing, the next checkpoint would write the item's end rather
    // than where this play actually stopped.
    _endedAt = null;
    if (_disposed || !_loaded) return;
    if (_busy) {
      // Joins the load under way: it lands at the top, as asked.
      _pendingSeekMs = 0;
      _resumeWanted = play;
      _markReopening();
      return;
    }
    // A stream whose token lapsed while the item sat at its end (a long
    // episode played out, repeat-one for a quarter hour) is minted again:
    // opening the held URL once more would only meet the refusal.
    if (_streamStale) {
      await _recover(0, resume: play);
      return;
    }
    // Through the display timeline, so a book on repeat-one goes back to
    // its first part rather than to the top of the part it ended on. A
    // move that failed is already on [sessionFailed], and one that loaded
    // ended playing or paused as asked.
    if (await _moveTo(0, resume: play, keep: false) != _Moved.seeked || !play) {
      return;
    }
    try {
      await engine.play();
    } on MediaLoadException catch (error) {
      _announceFailed(error, meantToPlay: true);
    }
  }

  /// Stops playback, flushing a final checkpoint and the listen report.
  ///
  /// The position is read here, synchronously: the engine is shared, and
  /// by the time the shutdown's awaits run a newer session may have
  /// loaded different media into it. The checkpoint must record where
  /// THIS item was, and stop() must not cut off the newer session.
  Future<void> dispose() =>
      _shutdown(atMs: _exitMs(), finished: _finished, stopEngine: true);

  /// Lets go of the engine without stopping it, for a hand-over to
  /// something that drives it directly (live radio). The item is
  /// checkpointed where it stands and its listen reported as unfinished;
  /// what plays next is the caller's business.
  Future<void> handOver() =>
      _shutdown(atMs: _exitMs(), finished: _finished, stopEngine: false);

  /// Finalizes this item because the engine walked out of it and into
  /// the item preloaded behind it. The checkpoint lands at this item's
  /// own end rather than at the engine's position, which already belongs
  /// to the next item, and the listen report says finished. The stream
  /// is left running: the next item's session adopts it.
  Future<void> finishAtBoundary() => _shutdown(
    atMs:
        _partStartMs +
        (_loadedDurationMs > 0 ? _loadedDurationMs : item.durationMs),
    finished: true,
    stopEngine: false,
  );

  /// What has to reach the server if this client vanishes right now,
  /// built without awaiting anything.
  ///
  /// The web build's answer to a closing tab. Every path that ends a
  /// session ordinarily - [dispose], [handOver], [finishAtBoundary] -
  /// is a sequence of awaited round trips, and there are none of those
  /// left once `pagehide` has fired. So the two facts a stop records
  /// are read off here synchronously and sent as they are.
  ///
  /// [ending] separates the two callers. A closing document is the end
  /// of the session and reports the listen; a tab merely going hidden
  /// is not, and reports only where the listener had got to - a tab
  /// switch that closed the session would end a listen the moment
  /// somebody checked their mail.
  ///
  /// Null when there is nothing to say: a session that never loaded has
  /// no position of its own, and the engine's belongs to whatever
  /// played before it.
  ({int positionMs, ListenSession? listen})? exitReport({
    required bool ending,
  }) {
    if (_disposed || !_loaded) return null;
    // `_endedAt` first, exactly as `dispose` and `handOver` read it: an
    // outro cutoff pauses the engine before the credits and records the
    // real end, so reading the engine here would put the resume point
    // back before the cutoff and fire it again next time - the loop the
    // held end exists to break.
    final positionMs = _exitMs();
    if (!ending) return (positionMs: positionMs, listen: null);
    final sessionId = _sessionId;
    final startedAt = _startedAt;
    if (sessionId == null || startedAt == null || _msPlayed <= 0) {
      return (positionMs: positionMs, listen: null);
    }
    final skipped = _timeSavedMs();
    return (
      positionMs: positionMs,
      listen: ListenSession(
        sessionId: sessionId,
        pid: item.pid,
        startedAt: startedAt,
        msPlayed: _msPlayed,
        skippedMs: skipped > 0 ? skipped : null,
        // A tab that closed mid-track did not finish it. The server
        // deduplicates on the session id, so a later report from a
        // path that knows better wins rather than double-counting.
        finished: _finished,
        client: clientId,
      ),
    );
  }

  /// The position waiting behind the checkpoint write in flight, and who
  /// is waiting on it. One write at a time, so a slow write of an older
  /// position can never land after a newer one and leave the server
  /// behind the listener; one waiting, the newest, since a stalled
  /// network would otherwise queue a write per tick and hold every exit
  /// behind all of them.
  int? _queuedCheckpointMs;
  Completer<void>? _queuedCheckpoint;
  bool _writingCheckpoint = false;
}
