import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

import 'listen_outbox.dart';
import 'smart_rewind.dart';

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

  /// [start]'s reads and its load, which [_underway] lands as asked.
  Future<void> _open({required bool autoplay}) async {
    // The three reads are independent and go out together. Config feeds
    // the rate, trim, and intro/outro, all applied after the load; play
    // state feeds only the resume point; play-info needs neither. Run in
    // turn they were three round trips of silence before the first byte
    // of an episode was even asked for, which is what made a
    // not-yet-fetched podcast slow to start.
    //
    // What that costs is the dispose gates that used to sit between
    // them: a session let go while the first read was in flight now
    // spends all three, so skipping fast through a queue mints a
    // play-info per tap. Bounded on the server rather than here - the
    // background chain resolve those mint has a ceiling of its own -
    // because a gate here would have to be a gate before the reads,
    // which is the serialization this removes.
    _configLoad = _loadConfig();
    PlayState? saved;
    PlayInfo? playInfo;
    Object? stateFailure;
    Object? infoFailure;
    try {
      // Joined rather than awaited one after another: a failure has to
      // leave no sibling read unwaited, or its own failure arrives as
      // an unhandled async error rather than in the catch below.
      //
      // Each read holds its own failure instead of letting the join
      // report one. `Future.wait` answers with whichever error landed
      // first, and the offline fallback below branches on the status
      // code it is handed - so a server mid-restart, answering 503 to
      // one read and 404 to the other, would decide between playing a
      // downloaded copy and rethrowing by whichever socket won the
      // race. Re-raised in a fixed order instead, which is the order
      // the serialized version had.
      await Future.wait<void>(<Future<void>>[
        _configLoad!,
        if (initialPositionMs == null)
          repository
              .getPlayState(item.pid)
              .then<void>((v) {
                saved = v;
              })
              .catchError((Object e) {
                stateFailure = e;
              }),
        if (!_isBook && timeline == null)
          _mint(0)
              .then<void>((v) {
                playInfo = v;
              })
              .catchError((Object e) {
                infoFailure = e;
              }),
      ]);
      if (stateFailure != null) throw stateFailure!;
      if (infoFailure != null) throw infoFailure!;
      // Let go while those were resolving: a tap on something else, or
      // the queue emptying. Loading here would put this item's media
      // over whatever took the engine, under a session nothing can
      // reach. One check for all three, because nothing between here
      // and the load awaits again.
      if (_disposed) return;
      var resumeMs = initialPositionMs;
      if (resumeMs == null) {
        final state = saved!;
        // A finished item has no resume point: its checkpoint sits at
        // its own end, and playing it again means playing it. Loading
        // media at the position it ends at also fails outright on web,
        // where the element answers "no supported source" for a source
        // it is asked to begin past, so this is the difference between
        // starting over and an error pane.
        resumeMs = state.finished ? 0 : state.positionMs;
        if (autoplay) {
          // Applied to the load rather than as a seek after it, so the
          // ordinary case has no stutter at the seam.
          resumeMs = _rewound(resumeMs, since: state.updatedAt);
        } else {
          // A queue put back at launch stands at its checkpoint and may
          // never be played at all. Rewinding it here would move the
          // position this session goes on to write back, so ten cold
          // starts nobody listened to would walk a book backwards; the
          // step is owed to the first play and spent there.
          _restedSince = state.updatedAt;
        }
      }
      if (_isBook) {
        final at = _startAt(resumeMs);
        _loadTarget = at;
        await _loadPartFor(at);
      } else {
        // A timeline member needs nothing resolved: the URL is minted,
        // the duration is the member's own, and the stream is
        // passthrough by construction. Synthesized into the same
        // PlayInfo the ordinary path builds so everything below - the
        // end-of-media guard, the outro cutoff, the reported duration -
        // reads one shape.
        final slot = timeline;
        final info =
            playInfo ??
            (slot == null
                ? null
                : PlayInfo(
                    pid: item.pid,
                    url: slot.media.url,
                    mimeType: slot.media.mimeType,
                    durationMs: slot.durationMs,
                    seekable: true,
                    expiresAt: slot.media.expiresAt,
                  ))!;
        _applyOutroCutoff(info.durationMs);
        // The same guard against a checkpoint the media outgrew: a
        // position at or past the end is not a place to start, however
        // it got there (a re-imported file, a listen that rounded up,
        // a finished flag that never landed).
        if (info.durationMs > 0 && resumeMs >= info.durationMs) resumeMs = 0;
        resumeMs = _applyIntroSkip(resumeMs);
        _loadTarget = resumeMs;
        if (slot != null) {
          await _loadTimelineMedia(
            slot,
            resumeMs > 0 ? Duration(milliseconds: resumeMs) : null,
          );
          if (_disposed) return;
          _moveTimeline(durationMs: slot.durationMs);
        } else {
          final at = resumeMs;
          // The mint above could not know the resume point (it went out
          // beside the play-state read), and a stream that answers no
          // ranges cannot be seeked to it: minted again, cut there.
          final minted = !info.seekable && at > 0 ? await _mint(at) : info;
          if (_disposed) return;
          await _loadStream(minted, at);
        }
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
        final at = _startAt(resumeMs);
        _loadTarget = at;
        await _loadPartFor(at);
      } else {
        if (!_isBook) resumeMs = _applyIntroSkip(resumeMs);
        _loadTarget = resumeMs;
        await _loadLocalFile(local, resumeMs);
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
    _failureSub = engine.mediaFailed.listen(_onMediaFailed);
  }

  /// The in-flight (or finished) config load, so a write that arrives
  /// before it does can wait for it rather than run without it.
  Future<void>? _configLoad;

  /// The show's stored settings, waited for rather than given up on.
  ///
  /// A persist sends the whole object back, so it needs what is stored
  /// now. Reading the field alone meant a tap that beat the load - or
  /// one whose load had failed - dropped the choice with the engine
  /// already at the new rate and the sheet's own footer promising the
  /// show would remember it. Re-fetched here when the load left nothing
  /// behind, so the write either lands or throws to the caller's catch.
  Future<SubscriptionSettings> _storedShowSettings(String showPid) async {
    await _configLoad;
    final loaded = _showSettings;
    if (loaded != null) return loaded;
    final detail = await repository.getPodcast(showPid);
    // Defaults where the show carries none, the way the book branch
    // already reads its own: a show nobody is subscribed to refuses the
    // write server-side, which is the caller's catch to report.
    final fetched = detail.settings ?? const SubscriptionSettings();
    _showSettings = fetched;
    return fetched;
  }

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
  /// member or a downloaded file, which nothing here can mint again),
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
  /// to begin there.
  Future<PlayInfo> _mint(int atMs) => repository.getPlayInfo(
    item.pid,
    positionMs: _isBook ? atMs : (atMs > 0 ? atMs : null),
    maxBitrateKbps: maxBitrateKbps,
    hls: _hls,
  );

  /// Asked on every mint where the engine plays HLS: a re-encode then
  /// comes back as one presentation it seeks itself, seekable, so nothing
  /// here cuts it and trimming jumps. Unasked elsewhere.
  bool? get _hls => engine.playsHls ? true : null;

  /// Whether another mint could make [error] go away: a refusal that says
  /// so, or a failure the server never explained. Not one the load
  /// deadline already waited out, which would only double the wait.
  static bool _worthAnotherMint(MediaLoadException error) {
    final refusal = error.refusal;
    if (refusal != null) return _curedByMint(refusal);
    return error.fault == MediaFault.transport &&
        error.cause is! TimeoutException;
  }

  /// Whether minting again cures [refusal]: a token that lapsed, the
  /// streaming engine away.
  static bool _curedByMint(StreamRefusal refusal) =>
      refusal.stale || refusal.engineDown;

  /// A failure carrying the server's refusal, as the API error it is.
  /// One with no envelope (a proxy's page, a bare status) reads as the
  /// API client reads any such answer: the network, with its status.
  static Object _surfaced(MediaTrouble error) {
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
        await _loadTimelineMedia(slot, at);
        if (_disposed) return;
        _moveTimeline(durationMs: slot.durationMs);
      },
    );
  }

  /// Whether a stream lost again may be reloaded again: not once reloads
  /// have kept failing before playback proved itself.
  bool get mayRecover => _recoveries < _recoveryBudget;

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
  /// how it lands.
  ///
  /// The fallback to downloaded parts is here rather than at the call
  /// sites, so every crossing gets it: a seek, a chapter tap, the deck
  /// bar's skip, replay, and the roll off a part's end.
  ///
  /// Rethrows for parts that cannot be placed on a timeline, which is
  /// [start]'s own offline branch to answer: it has the mirror position.
  Future<void> _loadPartFor(int bookMs, {bool newest = false}) async {
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
    // The first load has no map yet, whatever part it names (a book in
    // one file names none, which reads the same as the part before it).
    final samePart = _loadsBegun > 0 && minted.$1.partIndex == _partIndex;
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
  /// one - behave offline exactly as it does online. No skip map is
  /// fetched: trimming needs a server, and this branch is the one that
  /// has none.
  Future<void> _loadLocalPartFor(LocalPlayback local, int bookMs) async {
    final at = local.partAt(bookMs);
    final inPartMs = bookMs - at.startMs;
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
    _skipSpans = const [];
    _lastJumpedSpan = -1;
    _lastPosition = engine.position;
  }

  /// Loads the one file of [local] at display position [atMs]: a track,
  /// an episode, a book that is one file, or the first file of a book
  /// whose stored parts cannot be placed on its timeline.
  Future<void> _loadLocalFile(LocalPlayback local, int atMs) async {
    // A carved item's file duration is the whole rip's, and the engine
    // is about to be clipped to the window: the loaded media is the
    // item's own length.
    final span = local.spanStartMs != null && (local.spanEndMs ?? 0) > 0
        ? local.spanEndMs! - local.spanStartMs!
        : null;
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
    _moveTimeline(
      durationMs: span ?? local.parts.first.durationMs ?? item.durationMs,
    );
  }

  /// The downloaded original, but only for failures that smell like
  /// unreachability; a real API rejection (404, 401) propagates.
  Future<LocalPlayback?> _localFallback(WaxDeckApiException e) async {
    final port = downloads;
    if (port == null) return null;
    if (!e.unreachable) return null;
    return port.localFor(item.pid);
  }

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

  /// Runs [load] as this session's load under way (see [_busy]), meaning
  /// to land at display position [atMs] and to end playing when [resume]
  /// says so. A press made meanwhile changes what it ends with, and a seek
  /// made meanwhile lands as soon as it does. Throws what [load] threw,
  /// leaving nothing folded into it behind.
  Future<void> _underway(
    int atMs, {
    required bool resume,
    required Future<void> Function() load,
  }) async {
    final landed = Completer<bool>();
    _landed = landed;
    _busy = true;
    _resumeWanted = resume;
    _loadTarget = atMs;
    _markReopening();
    try {
      await load();
    } on Object {
      // A seek folded into a load that failed did not land, and the next
      // load must not carry it.
      _pendingSeekMs = null;
      _remint = false;
      landed.complete(false);
      rethrow;
    } finally {
      _busy = false;
      _loadTarget = null;
      _markReopening();
    }
    var arrived = false;
    try {
      if (_disposed) return;
      _lastPosition = engine.position;
      if (_resumeWanted) {
        await play();
      } else if (engine.playing) {
        // Landed over live playback that was asked to stay paused (a
        // queue put back while something plays): the source swap alone
        // does not stop the transport.
        await engine.pause();
      }
      // A seek that arrived after the last mint lands now; effects
      // changed meanwhile reopen it once more (a seek that reloads has
      // minted them already).
      final pending = _pendingSeekMs;
      _pendingSeekMs = null;
      arrived = pending == null || await seek(Duration(milliseconds: pending));
    } finally {
      landed.complete(arrived);
    }
    if (_remint && !_disposed) await _reopenForEffects();
  }

  /// Mints this item again and loads it at display position [atMs], as a
  /// load under way. Keeps the listen session and its accounting: the
  /// item never changed, only the stream it plays from.
  ///
  /// Throws what the load threw, the server's refusals as API errors.
  Future<void> _reload({required int atMs, required bool resume}) => _underway(
    atMs,
    resume: resume,
    load: () async {
      var at = atMs;
      do {
        _remint = false;
        await _loadAt(at);
        if (_disposed) return;
        // Effects changed while the media loaded: minted again where
        // it now stands.
        at = _display(engine.position).inMilliseconds;
        _loadTarget = at;
      } while (_remint);
    },
  );

  /// One mint and load inside a load under way, at display position
  /// [atMs] or the newest target a seek made meanwhile: the part holding
  /// it for a book; the item otherwise, or the copy downloaded to this
  /// device when the server is out of reach.
  Future<void> _loadAt(int atMs) async {
    if (_isBook) {
      await _loadPartFor(atMs, newest: true);
      return;
    }
    final (PlayInfo, int) minted;
    try {
      minted = await _mintNewest(atMs);
    } on WaxDeckApiException catch (e) {
      final local = await _localFallback(e);
      if (_disposed) return;
      if (local == null) rethrow;
      final target = _pendingSeekMs ?? _loadTarget ?? atMs;
      _pendingSeekMs = null;
      await _loadLocalFile(local, target);
      return;
    }
    if (_disposed) return;
    await _loadStream(minted.$1, minted.$2);
  }

  /// A load of its own the listener asked for (a move, an effect). One
  /// whose mint failed before any load began left the media it was
  /// replacing as it was, so that is kept, set as the presses made
  /// meanwhile ask, and it answers false, said on [moveFailed] when [say]
  /// asks; one that failed after a load began has nothing left to keep
  /// and is said on [sessionFailed].
  Future<bool> _reloadKeeping({
    required int atMs,
    required bool resume,
    bool say = false,
  }) async {
    final loadsBefore = _loadsBegun;
    try {
      await _reload(atMs: atMs, resume: resume);
      return !_disposed;
    } on Object catch (error) {
      if (_disposed) return false;
      if (_loadsBegun != loadsBefore) {
        _announceFailed(error, meantToPlay: _resumeWanted);
        return false;
      }
      if (_resumeWanted &&
          !engine.playing &&
          engine.processingState != EngineProcessingState.completed) {
        await engine.play();
      } else if (!_resumeWanted && engine.playing) {
        await engine.pause();
      }
      if (say && !_moveFailed.isClosed) _moveFailed.add(error);
      return false;
    }
  }

  /// Media that had loaded failed afterwards (a token that lapsed before
  /// the next range request, a dropped connection, the engine away).
  ///
  /// Recovered by minting again and reloading where the listener stood,
  /// when another mint can help: a stale or engine-down refusal, or a
  /// failure nobody explained. The server's other refusals (the transcode
  /// cap) and the file itself failing are said instead, never retried.
  /// A timeline member and a downloaded file have nothing to mint.
  void _onMediaFailed(MediaFailure failure) {
    if (_disposed || !_loaded || _busy) return;
    if (!identical(_engineOwners[engine], this)) return;
    // The engine may have dropped its position with the media; the last
    // one it reported is the floor, for a reload and for a failure said.
    final now = _display(engine.position).inMilliseconds;
    final last = _display(_lastPosition).inMilliseconds;
    final at = now > last ? now : last;
    final refusal = failure.refusal;
    final curable = refusal != null
        ? _curedByMint(refusal)
        : failure.fault == MediaFault.transport || _streamStale;
    if (_info == null || !curable || _recoveries >= _recoveryBudget) {
      _announceFailed(
        _surfaced(failure),
        meantToPlay: failure.wasPlaying,
        atMs: at,
      );
      return;
    }
    _recoveries++;
    _recoveredAtMs = at;
    unawaited(_recover(at, resume: failure.wasPlaying));
  }

  /// Reloads at [atMs], where the listener stood, for a failure or a
  /// token that lapsed, and says the failure from there when that does
  /// not work. Answers whether it landed.
  Future<bool> _recover(int atMs, {required bool resume}) async {
    try {
      await _reload(atMs: atMs, resume: resume);
      return !_disposed;
    } on Object catch (error) {
      _announceFailed(error, meantToPlay: _resumeWanted, atMs: atMs);
      return false;
    }
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

  /// Where this item stands for a final checkpoint, read synchronously:
  /// where it stood when it said it failed, else the target of a load
  /// under way (the engine reads the media being replaced, or the new
  /// media against the old timeline), else [_standingMs].
  int _exitMs() {
    final failed = _failedAtMs;
    if (failed != null) return failed;
    final target = _pendingSeekMs ?? _loadTarget;
    if (_busy && target != null) return target;
    return _standingMs();
  }

  /// Where the item stands with no load under way: where it stood before
  /// a load that failed (the engine reads the incoming media's start
  /// then), else the end an outro recorded, else the engine.
  int _standingMs() =>
      _stoodBeforeFailedLoad ??
      _display(_endedAt ?? engine.position).inMilliseconds;

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

  Future<void> _shutdown({
    required int atMs,
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
    unawaited(_failureSub?.cancel());
    unawaited(_stopReached.close());
    unawaited(_timelineMoved.close());
    unawaited(_mediaLoaded.close());
    unawaited(_sessionCompleted.close());
    unawaited(_sessionFailed.close());
    unawaited(_moveFailed.close());
    // Silenced before the writes below, which can wait out a dead
    // network: a cleared queue or an app swiped away goes quiet now, not
    // once the server answers. Ownership is read before any await, for
    // the reason [dispose] gives.
    final owned = identical(_engineOwners[engine], this);
    if (owned) _engineOwners[engine] = null;
    Object? stopFailure;
    StackTrace? stopStack;
    if (owned && stopEngine) {
      try {
        await engine.stop();
      } on Object catch (error, stack) {
        stopFailure = error;
        stopStack = stack;
      }
    }
    // A start that never got as far as loading has nothing to record,
    // and the engine's position belongs to whatever played before it:
    // writing that as this item's resume point would lose the
    // listener's place on a failure they can retry.
    if (_loaded) await _checkpointMs(atMs);
    await _reportSession(finished: finished);
    trimEnabled.dispose();
    voiceBoost.dispose();
    hoursSavedMs.dispose();
    reopening.dispose();
    // The writes still landed; the stop that failed is the caller's to hear.
    if (stopFailure != null) Error.throwWithStackTrace(stopFailure, stopStack!);
  }

  void _onPosition(Duration position) {
    if (_disposed) return;
    final delta = position - _lastPosition;
    _lastPosition = position;
    if (_reachedStop(position, delta)) return;
    if (!engine.playing) return;
    if (delta > Duration.zero && delta <= maxCountedStep) {
      _ensureSession();
      _msPlayed += delta.inMilliseconds;
      _countSpeedSaving(delta.inMilliseconds);
    }
    final recoveredAt = _recoveredAtMs;
    if (recoveredAt != null &&
        _display(position).inMilliseconds - recoveredAt >= _provenMs) {
      _recoveries = 0;
      _recoveredAtMs = null;
    }
    _maybeTrimJump(position);
    _maybeOutroStop(position);
  }

  /// Entering a mapped silence span jumps forward to its end. Jumps only
  /// ever go forward and each span fires at most once per load, so a
  /// stubborn backend that lands short of the target cannot loop.
  ///
  /// Spans are in the file's own time; a cut stream's clock starts at the
  /// cut, so both sides are read in file time.
  void _maybeTrimJump(Duration position) {
    if (!trimEnabled.value || _skipSpans.isEmpty) return;
    // A jump would restart such a stream at its head, and a cut per
    // silence is a fresh encode of the rest each time.
    if (_cantSeekHere) return;
    final ms = _cutMs + position.inMilliseconds;
    for (var i = _lastJumpedSpan + 1; i < _skipSpans.length; i++) {
      final span = _skipSpans[i];
      if (ms >= span.startMs - trimWindowMs && ms < span.endMs) {
        _lastJumpedSpan = i;
        hoursSavedMs.value += span.endMs - ms;
        unawaited(engine.seek(Duration(milliseconds: span.endMs - _cutMs)));
        return;
      }
    }
  }

  /// Crossing the outro cutoff ends the episode as completed: the tail
  /// is credits the caller asked to skip.
  void _maybeOutroStop(Duration position) {
    final cutoff = _outroCutoffMs;
    if (cutoff == null || _outroFired) return;
    final fileMs = _cutMs + position.inMilliseconds;
    if (fileMs < cutoff) return;
    _outroFired = true;
    _finished = true;
    unawaited(engine.pause());
    // The checkpoint records the real end so resume lands past the outro.
    // Held as well as written: the engine is paused at the cutoff, so a
    // final checkpoint taken from it would put the resume point back
    // before the outro and fire this again on the next play.
    final endMs = _loadedDurationMs > 0 ? _loadedDurationMs : fileMs;
    // On the engine's clock, which [_display] reads back through the cut.
    _endedAt = Duration(milliseconds: endMs - _cutMs);
    unawaited(_checkpoint(at: _endedAt!));
    unawaited(_reportSession(finished: true));
    _announceCompleted(SessionEnd.played);
  }

  void _onPlayingChanged(bool playing) {
    if (_disposed) return;
    if (playing) {
      _rewindForBreak();
      _ensureSession();
      _checkpointTimer?.cancel();
      _checkpointTimer = Timer.periodic(checkpointInterval, (_) {
        if (_loading == 0) unawaited(_checkpoint());
      });
    } else {
      // Stamped from the engine's own transition rather than from the
      // control that caused it: a pause arrives from the lock screen,
      // a headset button, a routed Connect command, and an interruption
      // the platform made on its own, and all of them are a listener
      // who stopped listening.
      _pausedAt ??= _clock();
      _checkpointTimer?.cancel();
      _checkpointTimer = null;
      // Paused from outside while a load under way waits on its mint (an
      // interruption the platform made): it must not start it again. Only
      // media still standing ready stops that way. The stop that comes
      // with an end or a failure arrives after it, when the end has
      // already begun a load (the roll into a book's next part), and is
      // no listener stopping.
      if (_busy &&
          _loading == 0 &&
          engine.processingState == EngineProcessingState.ready) {
        _resumeWanted = false;
        _markReopening();
      }
      // The stop a load starts with is not the listener stopping: the
      // engine already reads the new media while the state is the old.
      if (_loading == 0) unawaited(_checkpoint());
    }
  }

  void _onCompleted() {
    if (_disposed) return;
    // About media no longer loaded: a newer load took the engine first.
    if (engine.processingState != EngineProcessingState.completed) return;
    // Already somebody's: a stop at the end under way, a load replacing
    // the media, an end held for the next play or rested on.
    if (_stopping || _busy || _atEnd != _AtEnd.none) return;
    final stop = _stopAtMs;
    if (stop != null &&
        (stop <= _partStartMs + _loadedDurationMs + _stopSlackMs ||
            !_hasNextPart)) {
      // The boundary is this media's end, and the end arrived before any
      // position crossed it: the end is the boundary. On the last part a
      // boundary still armed is the end too, since a chapter can be
      // marked past where the audio stops.
      _stopAtMs = null;
      unawaited(_stopHere(stop));
      return;
    }
    if (_hasNextPart) {
      // The book has more parts: roll into the next one seamlessly.
      unawaited(_advanceToNextPart());
      return;
    }
    _finished = true;
    unawaited(_checkpoint());
    unawaited(_reportSession(finished: true));
    _announceCompleted(SessionEnd.played);
  }

  Future<void> _advanceToNextPart() async {
    // Falls back to the downloaded parts itself where there are any: a
    // server that went away mid-book does not end a book somebody
    // downloaded, which is the whole point of downloading one. A part
    // that cannot be had lands on the error surface instead, from the
    // boundary this play actually reached, and the release that answers
    // it reports the listen unfinished, which is what it is.
    final partEnd = _partStartMs + _loadedDurationMs;
    if (await _recover(partEnd, resume: true)) {
      // The load's own pause wrote nothing; this is where the book is.
      unawaited(_checkpoint());
    }
  }

  /// Whether [position] reached the armed stop by moving forward into it:
  /// playing at any speed, or a trim jump over the silence a chapter ends
  /// in. A listener's jump past it never arrives here, since [seek]
  /// disarms it first; a move backwards across it only spends it.
  ///
  /// Read off the step, not off `playing`: the tick that crosses a
  /// boundary at the end of the media arrives as the media ends, when the
  /// engine already reads stopped.
  bool _reachedStop(Duration position, Duration delta) {
    final stop = _stopAtMs;
    // A load in flight reports the new media's position against the old
    // media's timeline, which can read as anywhere; and while a load of
    // the session's own is under way the media still playing is the one
    // being replaced, whose crossing says nothing of where the new one
    // lands.
    if (stop == null || _loading > 0 || _busy) return false;
    if (_display(position).inMilliseconds < stop) return false;
    _stopAtMs = null;
    // Reached only by a step that began short of it. One already behind
    // where the step began (a move backwards, a boundary armed after
    // playback passed it) is spent where it stands.
    final crossed = _display(position - delta).inMilliseconds < stop;
    if (crossed) {
      unawaited(_stopHere(stop));
    } else {
      _announceStopReached();
    }
    return crossed;
  }

  /// Rests at [stopMs]: pauses and parks on the boundary, so a resume
  /// starts what follows at its head. A boundary at the end of the loaded
  /// media is that end: a book's next part is loaded paused, and the last
  /// part finishes without the queue moving on under a sleeper. A load
  /// under way while it does, so a press made meanwhile is how it ends.
  Future<void> _stopHere(int stopMs) async {
    _stopping = true;
    final mediaEnd = _partStartMs + _loadedDurationMs;
    final at = stopMs < mediaEnd ? stopMs : mediaEnd;
    try {
      await _underway(
        at,
        resume: false,
        load: () async {
          await engine.pause();
          if (_disposed) return;
          if (stopMs < mediaEnd - _stopSlackMs) {
            // The pause lands up to a tick late; parked back where the
            // engine can seek, left there where it would restart the
            // stream.
            if (!_cantSeekHere) await engine.seek(_inMedia(stopMs));
          } else if (_hasNextPart) {
            await _loadAt(mediaEnd);
          } else {
            _finished = true;
            _atEnd = _AtEnd.held;
            unawaited(_reportSession(finished: true));
          }
        },
      );
      if (!_disposed) unawaited(_checkpoint());
    } on Object catch (error) {
      _announceFailed(error, meantToPlay: _resumeWanted, atMs: at);
    } finally {
      _stopping = false;
      _announceStopReached();
    }
  }

  void _announceStopReached() {
    if (!_stopReached.isClosed) _stopReached.add(null);
  }

  /// Tells the layer above that this item is over. Reported after the
  /// checkpoint and the listen report are on their way, so whatever
  /// advances the queue cannot outrun this item's own accounting.
  void _announceCompleted(SessionEnd end) {
    if (!_sessionCompleted.isClosed) _sessionCompleted.add(end);
  }

  /// Tells the layer above this session could not do what its item
  /// needed and should be let go, with [error] as the reason to show and
  /// whether playback [meantToPlay] when it struck.
  /// [atMs] is where the item stood, when the caller knows better than
  /// the engine does by now.
  void _announceFailed(Object error, {required bool meantToPlay, int? atMs}) {
    if (_sessionFailed.isClosed) return;
    final at = atMs ?? _exitMs();
    _failedAtMs = at;
    _sessionFailed.add((error: error, meantToPlay: meantToPlay, atMs: at));
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

  /// The position waiting behind the checkpoint write in flight, and who
  /// is waiting on it. One write at a time, so a slow write of an older
  /// position can never land after a newer one and leave the server
  /// behind the listener; one waiting, the newest, since a stalled
  /// network would otherwise queue a write per tick and hold every exit
  /// behind all of them.
  int? _queuedCheckpointMs;
  Completer<void>? _queuedCheckpoint;
  bool _writingCheckpoint = false;

  /// Checkpoints [at] (engine timeline; defaults to the live position),
  /// reported to the server on the display timeline: books checkpoint
  /// book-timeline positions. The position is read now, the write waits
  /// its turn.
  Future<void> _checkpoint({Duration? at}) =>
      _checkpointMs(_display(at ?? engine.position).inMilliseconds);

  /// [_checkpoint] at a display-timeline position already read. Settles
  /// once that position, or a newer one queued behind it, is written.
  Future<void> _checkpointMs(int positionMs) {
    final waiting = _queuedCheckpoint ??= Completer<void>()..future.ignore();
    _queuedCheckpointMs = positionMs;
    if (!_writingCheckpoint) unawaited(_drainCheckpoints());
    return waiting.future;
  }

  Future<void> _drainCheckpoints() async {
    _writingCheckpoint = true;
    try {
      while (true) {
        final positionMs = _queuedCheckpointMs;
        final waiting = _queuedCheckpoint;
        if (positionMs == null || waiting == null) return;
        _queuedCheckpointMs = null;
        _queuedCheckpoint = null;
        try {
          await _writeCheckpoint(positionMs);
          waiting.complete();
        } on Object catch (error, stack) {
          debugPrint('checkpoint failed: $error');
          waiting.completeError(error, stack);
        }
      }
    } finally {
      _writingCheckpoint = false;
    }
  }

  Future<void> _writeCheckpoint(int positionMs) async {
    try {
      await repository.putPlayState(item.pid, positionMs);
    } on WaxDeckApiException {
      // ANY failure queues, deliberately broader than the reachability
      // gate elsewhere: queued checkpoints replay with recordedAt and
      // reconcile server-side, flushOutbox drops permanent rejections,
      // and a transient auth failure would otherwise silently lose the
      // position. Without an engine (web), best effort stands and the
      // next checkpoint catches up.
      await sync?.queueCheckpoint(item.pid, positionMs);
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

  /// Reports the open session once. One that does not reach the server
  /// waits in the sync engine's queue, or where there is none in the
  /// listen outbox, until it does; the server deduplicates on the session
  /// ID, so a report sent twice never counts twice.
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
      // The server is answering: whatever an earlier report left behind
      // goes now.
      unawaited(listenOutbox?.flush(repository));
    } on WaxDeckApiException catch (error) {
      final engine = sync;
      if (engine != null) {
        await engine.queueListen(session);
      } else if (!error.isRefusal) {
        // A refusal is the server's answer (a session signed out mid-flight
        // answers 401), not a report waiting for the server to come back.
        listenOutbox?.keep(session);
      }
    }
  }
}
