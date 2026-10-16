import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_engine_port.dart';
import 'stream_probe/stream_probe.dart';

/// Which half of a failed load a just_audio failure describes.
///
/// `PlayerException.code` is a different number on every platform - a
/// `MediaError.code` on web, an `ExoPlaybackException.type` on Android,
/// an `NSError.code` on Apple - so there is no one reading of it, and
/// this is a table per platform rather than a clever one for all of
/// them.
///
/// Only positive evidence answers [MediaFault.source]. Every code
/// nothing here recognizes, and every failure that is not a
/// `PlayerException` at all, is [MediaFault.transport], because the two
/// mistakes do not cost the same: reading a dropped connection as a bad
/// file walks a listener's queue one track at a time on a server
/// restart, and reading a bad file as a dropped connection costs one
/// retry press.
///
/// Which leaves platforms that classify less than they could, and this
/// is measured rather than assumed - `integration_test/load_fault_test.dart`
/// is what measured it. On Android every failure there is, from garbage
/// bytes to a DNS failure, arrives as `PlayerException(0, "Source
/// error")`: one `TYPE_SOURCE` and one constant string, with the cause
/// that would separate them left on the far side of the plugin's
/// channel. The `TYPE_RENDERER` row below is from ExoPlayer's contract
/// rather than from that run, which produced no such code. The Apple
/// rows are unmeasured too. [probedMediaFailureOf] is the second step
/// that covers the difference: where this table has no verdict, it
/// asks the network for one.
///
/// Desktop has no row. mpv through media_kit does not fail a load, it
/// simply never finishes one, so the engine's own load deadline ends
/// that wait and the probe below classifies it alone. What mpv does
/// report is media that had loaded failing afterwards, which reads as
/// transport like any code without a row.
@visibleForTesting
MediaFault mediaFaultOf(Object failure, {bool isWeb = kIsWeb}) {
  if (failure is! PlayerException) return MediaFault.transport;
  // `MediaError.code`: 3 is MEDIA_ERR_DECODE, the element saying it cannot
  // make sound out of these bytes. 4 (MEDIA_ERR_SRC_NOT_SUPPORTED) is no
  // such evidence: the HTML spec raises it for any first fetch that
  // produced no media, a 401 or a 429 as much as a codec, so the probe
  // decides it. 1 (aborted) and 2 (network) are not the file.
  if (isWeb) {
    return failure.code == 3 ? MediaFault.source : MediaFault.transport;
  }
  return switch (defaultTargetPlatform) {
    // `ExoPlaybackException.type`: 1 is TYPE_RENDERER, a decoder that
    // would not take the stream it was handed.
    TargetPlatform.android when failure.code == 1 => MediaFault.source,
    // `NSError.code` in AVFoundationErrorDomain: the file the framework
    // could not make sense of. Everything else there - -1009 for
    // offline, -11800 for unknown - is not the file.
    TargetPlatform.iOS || TargetPlatform.macOS =>
      _appleFormatErrors.contains(failure.code)
          ? MediaFault.source
          : MediaFault.transport,
    _ => MediaFault.transport,
  };
}

/// `AVErrorFileFormatNotRecognized` and `AVErrorFailedToParse`.
const Set<int> _appleFormatErrors = <int>{-11828, -11829};

/// A failure of [url], weighed against one question the platform cannot
/// refuse to answer: what does the URL say about itself?
///
/// The one place a failure is blamed, whenever it struck. At [midPlay],
/// media that had loaded failed afterwards; [abandoned] is a load the
/// deadline gave up on, which the platform never reported; neither is a
/// load the platform failed itself.
///
/// A load the platform failed is first read by [mediaFaultOf]: its source
/// verdict stands unasked, and a failure that is not the player's own
/// says nothing about the media and is the transport. Otherwise the probe
/// decides. On Android every load failure arrives as `TYPE_SOURCE` with a
/// constant string (measured; see [mediaFaultOf]), so the code alone left
/// a bad rip standing on the retry pane; the probe separates the halves
/// from outside the plugin. WaxDeck's stream URLs are HMAC-signed and
/// replayable (`auth/mediatoken.go`), so asking consumes nothing, and it
/// is spent only on media that has already failed.
///
/// The server's refusal (an expired token, the transcode cap, the engine
/// away) is never the file: the server answered and said why, and that
/// reason is what the caller acts on. A server calling the file unplayable
/// is the file wherever it struck. Between them, a URL that answers is
/// the file only where an answer is evidence: a load that failed on bytes
/// the player was handed. It is not where the element itself said network
/// (the web's codes 1 and 2), where the web's load ran out of time (the
/// element names a file it cannot decode), for an HLS presentation (its
/// segments are where it fails, and the server's verdicts are read off the
/// segment the player needed at [at]), or mid-play: what fails partway
/// through is far
/// more often the way to a file than a file that decoded until then,
/// whatever code the platform gave - save a file on disk, where no way
/// stands between the player and the bytes. The residual risk is a
/// connection that dropped and came back within the probe's window,
/// which reads as the file and skips one good track; the reverse mistake
/// walks the queue, which is why the default stays transport.
@visibleForTesting
Future<({MediaFault fault, StreamRefusal? refusal})> probedMediaFailureOf(
  Object failure,
  String url, {
  StreamAsk ask = askStream,
  bool isWeb = kIsWeb,
  bool midPlay = false,
  bool abandoned = false,
  bool presentation = false,
  Duration at = Duration.zero,
}) async {
  if (!midPlay && !abandoned) {
    if (failure is! PlayerException) {
      return (fault: MediaFault.transport, refusal: null);
    }
    final fault = mediaFaultOf(failure, isWeb: isWeb);
    if (fault == MediaFault.source) return (fault: fault, refusal: null);
  }
  ProbeAnswer answer;
  try {
    answer = await ask(
      url,
      segmentAt: presentation ? at + _segmentLookAhead : null,
    );
  } on Object {
    // The port promises MediaLoadException and nothing else; a probe
    // that broke does not get to break that.
    answer = ProbeAnswer.unreachable;
  }
  final refusal = answer.refusal;
  if (refusal != null) return (fault: MediaFault.transport, refusal: refusal);
  final local = Uri.tryParse(url)?.isScheme('file') ?? false;
  final strict =
      presentation ||
      (midPlay ? !local : isWeb && (abandoned || _saidNetwork(failure)));
  return (
    fault: answer.verdict.blames(strict: strict)
        ? MediaFault.source
        : MediaFault.transport,
    refusal: null,
  );
}

/// How far past [probedMediaFailureOf]'s position the segment a
/// presentation needed is looked for. Where playback stopped is where the
/// segment it could not fetch begins, give or take a frame, so the one
/// holding a moment later is that segment rather than the one before.
const Duration _segmentLookAhead = Duration(milliseconds: 250);

/// `MediaError.code` 1 (aborted) and 2 (network): the element saying the
/// fetch failed, not the file.
bool _saidNetwork(Object failure) =>
    failure is PlayerException && (failure.code == 1 || failure.code == 2);

/// How long a load may take before the engine stops waiting for it.
///
/// The outer bound on a platform that can decline to answer at all: mpv
/// never reports a failed load, so without this the session sits on the
/// last face forever. Generous, because everything under it is a real
/// load that deserves to finish - a cold NAS, a large file over a slow
/// link. The cost of that generosity is at the far end: off the web, a
/// slow but legitimate load whose URL still answers is classified as the
/// media and auto-skipped rather than paned (the web, where the element
/// names an undecodable file itself, keeps it on the pane, and so does
/// an HLS presentation, which only the server calling it unplayable puts
/// on the file). "Answers" is a status line - `askStream` reads one and
/// hangs up - so a host that returns headers promptly and then stalls the
/// body reads as the media every time. Taken knowingly, because it is the
/// same verdict Android already gives garbage bytes on disk, and the skip
/// surface names what happened.
///
/// Window edits and a replay's seek and reload are held to it too.
const Duration _defaultLoadDeadline = Duration(seconds: 15);

/// How long a `stop()` gets, both the one before a load and the one
/// that abandons a timed-out load, and the pause a replay starts with.
/// A player that would not finish a load may not finish a stop either,
/// so this is what keeps a hang from moving one call along rather than
/// being reported.
const Duration _defaultStopGrace = Duration(seconds: 2);

/// [AudioEnginePort] backed by just_audio.
///
/// One facade drives every platform: the bundled just_audio backends on
/// mobile and web, and mpv via the media_kit bridge on desktop (see the
/// bootstrap helper). This class is the only place just_audio types appear,
/// save the platform bound the web bootstrap installs.
///
/// Gapless playback is a sliding two-item window over just_audio's audio
/// source list: the item playing, plus the one [preloadNext] put behind
/// it. The engine crossing between them is what the platform makes
/// gapless (ExoPlayer's playlist, mpv's `prefetch-playlist`). The window
/// never grows past two: the consumed item is dropped the moment the
/// engine walks out of it.
class JustAudioEngine implements AudioEnginePort {
  JustAudioEngine() : this.withPlayer(AudioPlayer());

  /// The seams the load deadline is tested through: a player that can
  /// be made to hang, a probe that answers without a network, a deadline
  /// short enough to wait out, and whether it behaves as the web's.
  /// Nothing but a test builds an engine this way.
  @visibleForTesting
  JustAudioEngine.withPlayer(
    this._player, {
    this._loadDeadline = _defaultLoadDeadline,
    this._stopGrace = _defaultStopGrace,
    this._ask = askStream,
    this._isWeb = kIsWeb,
  }) {
    _indexSub = _player.currentIndexStream.listen(_onIndexChanged);
    _durationSub = _player.durationStream.listen(_rememberDuration);
    _eventSub = _player.playbackEventStream.listen(
      _onPlaybackEvent,
      onError: (Object _) {},
    );
  }

  final AudioPlayer _player;
  final bool _isWeb;
  final Duration _loadDeadline;
  final Duration _stopGrace;
  final StreamAsk _ask;
  final _boundaries = StreamController<void>.broadcast();
  final _refusals = StreamController<Object>.broadcast();
  final _failures = StreamController<MediaFailure>.broadcast();
  final _completions = StreamController<void>.broadcast();

  /// What the port reports the state as, each time it may have moved: the
  /// platform's events, and the engine's own turns the platform never
  /// sees (a load answering, a failure announced). See [_emitState].
  final _states = StreamController<EngineProcessingState>.broadcast();
  late final StreamSubscription<int?> _indexSub;
  late final StreamSubscription<Duration?> _durationSub;
  late final StreamSubscription<PlaybackEvent> _eventSub;

  /// The platform's last playback event, read when the next one says the
  /// item ended or failed: see [_onPlaybackEvent].
  PlaybackEvent? _lastEvent;

  /// Where an HLS presentation had got to when the platform called it
  /// over well short of its playlist length, which is a failure and not
  /// an end, and where it resumes from; null otherwise. Cleared by
  /// whatever moves the item on.
  Duration? _endedShort;

  /// A failure of the loaded media that is still being probed before it
  /// is announced; null when none is. Let go with the media, so a stop, a
  /// load or disposal drops the announcement (see [_announce]).
  _PendingFailure? _pending;

  /// An end the platform raised while a load or a replay had not
  /// answered: the loaded media's only if that attempt leaves media
  /// loaded and the platform still reads ended (see [_settled]).
  ({PlaybackEvent previous, PlaybackEvent event})? _heldEnd;

  /// Window edits run one at a time. Crossing a boundary schedules the
  /// drop of the item just consumed at the same moment the caller is
  /// preloading the one after it, and both address the same list.
  Future<void> _edits = Future<void>.value();

  /// Bumped by [load]. An edit queued against the window that load
  /// replaced is dropped rather than run against the item that replaced
  /// it.
  int _generation = 0;

  bool _disposed = false;

  /// Every just_audio call runs here (see [_run]): an error never reaches a
  /// listener in another error zone, so one zone for all of them.
  final Zone _zone = Zone.current.fork(
    specification: const ZoneSpecification(handleUncaughtError: _dropEcho),
  );

  /// A load or a replay was issued and has not succeeded. Its start may
  /// still hold the platform, so the next load stops first even while the
  /// player reads idle; and what the platform reports meanwhile is either
  /// the attempt's to report by throwing, or about media that never
  /// loaded.
  bool _unsettled = false;

  /// Bumped by every attempt to put media on the platform: a load, and a
  /// replay, which is a load in all but name.
  int _attempt = 0;

  /// The attempt that has not answered yet, or null. The stop a load
  /// starts with takes the platform through idle, and audio_service reads
  /// a move into idle as the service stopping (on the web it clears the
  /// browser's media session), so an attempt reads as loading from its
  /// stop to its answer. Only the newest attempt counts: one a newer
  /// attempt superseded no longer speaks for the platform.
  int? _settling;

  /// Platform calls the engine stopped waiting for that have not answered
  /// yet: window edits, loads, a replay's calls, stops. See [_stillOut].
  int _unanswered = 0;

  /// Bumped by everything that decides what is preloaded, so a preload
  /// that lands after its deadline is adopted only while nothing has
  /// changed that since.
  int _preloadEpoch = 0;

  /// The two sources the window can hold, by identity.
  ///
  /// Every index the engine acts on is derived from these, never from
  /// the platform's own index: that arrives by event and so lags a
  /// crossing, and arithmetic on a stale one addresses the item that is
  /// playing right now. The sequence just_audio reports holds these
  /// exact objects, so finding one in it is honest at any moment.
  AudioSource? _loadedSource;
  AudioSource? _preloadedSource;

  /// Length of the item playing, as far as the engine knows it. See
  /// [_rememberDuration].
  Duration? _heldDuration;

  /// Length of the preloaded item, held until the crossing makes it the
  /// playing one.
  Duration? _preloadedLength;

  @override
  Future<void> load(
    String url, {
    String? mimeType,
    Duration? initialPosition,
    Duration? clipStart,
    Duration? clipEnd,
  }) async {
    // A fresh load starts a fresh window, preload included. Load stays
    // off the edit queue: a slow one has to stay interruptible by the
    // next load, which is just_audio's own contract.
    final source = _sourceFor(url, clipStart, clipEnd);
    final generation = ++_generation;
    final attempt = _attempting();
    _loadedSource = source;
    _preloadedSource = null;
    _preloadedLength = null;
    _heldDuration = _windowLength(clipStart, clipEnd);
    final at = _presentationAt(source, initialPosition ?? Duration.zero);
    try {
      // A hard stop before every replacement, and not an optimisation:
      // just_audio funnels setAudioSources through one internal playlist
      // whose id never changes, and its web platform caches source
      // players by that id - so a second load on a live player finds
      // the stale cached player, keeps the old element's src, applies
      // the new initial position as a bare seek, and reports success.
      // The audible result was the old item playing on under the new
      // item's face while the new session checkpointed against it.
      // Stopping first deactivates the platform player, so the load
      // that follows builds a fresh one with an empty cache. Nothing
      // gapless is lost: crossings ride the preload window and never
      // pass through here.
      final replacing =
          _player.processingState != ProcessingState.idle || _unsettled;
      _unsettled = true;
      if (replacing) {
        // Bounded like the abandonment stop below and for the same
        // reason: this runs against a player that may be mid-hang from
        // a load the deadline already gave up on, and an unbounded wait
        // here would simply move the hang one call along - no deadline,
        // no fault, no pane. A stop that will not land leaves the load
        // to fail on its own deadline, which is the honest report.
        try {
          await _within(_run(_player.stop), _stopGrace);
        } on TimeoutException {
          // Swallowed: the load below is what answers for this player.
        }
      }
      final answer = _run(
        () => _player.setAudioSources(
          [source],
          initialIndex: 0,
          initialPosition: initialPosition,
        ),
      );
      try {
        await answer.timeout(_loadDeadline);
      } on TimeoutException catch (timeout) {
        // Read before this load is counted, and before the stop that
        // abandons it can shake an earlier call loose.
        final behind = _unanswered > 0;
        _stillOut(answer);
        throw _Abandoned(timeout, behindAnother: behind);
      }
      if (attempt == _attempt) _unsettled = false;
    } on _Abandoned catch (abandoned) {
      final read = await _abandonedFault(abandoned, source, generation, at);
      throw MediaLoadException(
        read.fault,
        abandoned.timeout,
        refusal: read.refusal,
      );
    } on Object catch (failure) {
      final read = await probedMediaFailureOf(
        failure,
        url,
        ask: _ask,
        isWeb: _isWeb,
        presentation: _isPresentation(source),
        at: at,
      );
      throw MediaLoadException(read.fault, failure, refusal: read.refusal);
    } finally {
      // An edit already in flight when this load started can put its
      // source into the list the load just built: both go through the
      // same playlist, so an add that had not reached it yet appends to
      // the new one instead of the replaced one. Left there it would
      // play after this item, gaplessly, as a track nobody queued. Edits
      // are ordered, so a trim queued here runs after that straggler.
      // A load that threw owns the window just as much as one that did
      // not, so the trim rides the failure path too.
      _repairWindow();
      _settled(attempt);
    }
  }

  /// Starts an attempt to put media on the platform, a load or a replay:
  /// whatever the media before it was doing - failing, ending - is no
  /// longer anyone's to report.
  int _attempting() {
    final attempt = ++_attempt;
    _settling = attempt;
    _pending = null;
    _heldEnd = null;
    _endedShort = null;
    _emitState();
    return attempt;
  }

  /// [attempt] has answered, either way. An end the platform raised while
  /// it was out is the loaded media's only if the attempt left media
  /// loaded and the platform still reads ended; one superseded by a newer
  /// attempt leaves that attempt to answer.
  void _settled(int attempt) {
    if (_settling != attempt) return;
    _settling = null;
    final held = _heldEnd;
    _heldEnd = null;
    if (held != null &&
        !_unsettled &&
        _player.processingState == ProcessingState.completed) {
      _ended(held.previous, held.event);
    }
    _emitState();
  }

  /// What a load the deadline cut short was: the failure the platform
  /// never reported.
  ///
  /// The probe is the whole classification here rather than a refinement
  /// of one: a deadline is the only report the desktop gives. A URL that
  /// answers while the player could not finish with it is the media's
  /// fault, and so is one the server will not serve as audio - mpv giving
  /// up on a file the server would not decode is the same file twice. A
  /// load that waited behind a call the platform never answered is the
  /// transport unasked: it never reached the platform, and a probe that
  /// answers would blame a file nobody tried. See [probedMediaFailureOf]
  /// for where an answering URL says nothing.
  Future<({MediaFault fault, StreamRefusal? refusal})> _abandonedFault(
    _Abandoned abandoned,
    AudioSource source,
    int generation,
    Duration at,
  ) async {
    // Abandoned, not cancelled: just_audio has no cancel, so the source
    // stays attached until something replaces it, and on the mpv bridge
    // that leaves the file open. Best-effort and time-bounded, and its
    // failure is nothing to act on - the window repair already fences
    // whatever the abandoned load left behind.
    //
    // Fenced on the generation, because a load is deliberately
    // interruptible: fifteen seconds is long enough for the listener to
    // have tapped something else, and that item is playing on this same
    // player. Stopping it here would silence a track nobody reported a
    // fault for. The classification below still runs - the caller of
    // the load that timed out is owed an answer either way.
    if (generation == _generation) {
      try {
        await _within(_run(_player.stop), _stopGrace);
      } on Object {
        // A player that will not stop is the same player that would not
        // load; the fault below is still the honest answer.
      }
    }
    if (abandoned.behindAnother) {
      return (fault: MediaFault.transport, refusal: null);
    }
    return probedMediaFailureOf(
      abandoned.timeout,
      _urlOf(source),
      ask: _ask,
      isWeb: _isWeb,
      abandoned: true,
      presentation: _isPresentation(source),
      at: at,
    );
  }

  /// No window on the web, where one was never worth having.
  ///
  /// just_audio's web platform is a single `HTMLAudioElement` whose
  /// `src` is re-pointed at every boundary, so a crossing there is a
  /// load and a gap however the window is arranged - there is no
  /// gapless to lose by declining. What the window did cost was real:
  /// its insert reloads the *playing* source unconditionally
  /// (`concatenatingInsertAll` awaits `_currentAudioSourcePlayer.load()`
  /// even when the insert lands past the current index), which resets
  /// that item to zero, never fetches the appended one, and leaves a
  /// player that can no longer end - no `completed`, no index change,
  /// position pinned at the duration with `playing` still true. The
  /// queue stopped dead on the track it was on and the listen went
  /// unreported. Same defect [load] stops first for, one call on. Every
  /// other engine here keeps its window and its gapless crossing.
  ///
  /// The browser gets its gapless crossing another way, and not through
  /// this window: `WebGaplessEngine` puts a whole queue on one
  /// server-rendered stream and crosses members inside it, where a
  /// boundary is a position passing a number rather than a media swap.
  ///
  /// Nor behind an HLS presentation on the desktops: mpv steps over a
  /// segment it cannot fetch into the entry behind, which reads as a
  /// crossing and never as the early end it is. ExoPlayer fails such a
  /// segment instead, so Android keeps its gapless crossing.
  @override
  bool get canPreload =>
      !_isWeb &&
      (defaultTargetPlatform == TargetPlatform.android || !_holdsPresentation);

  bool get _holdsPresentation {
    final source = _loadedSource;
    return source != null && _isPresentation(source);
  }

  @override
  Future<void> preloadNext(
    String url, {
    String? mimeType,
    Duration? clipStart,
    Duration? clipEnd,
  }) {
    if (!canPreload) return Future<void>.value();
    return _edit((generation) async {
      // Nothing loaded means nothing to follow: appending here would
      // make the preloaded item the one that plays.
      if (_player.sequence.isEmpty) return;
      await _dropPreloaded();
      final epoch = ++_preloadEpoch;
      // Behind a call the platform has not answered the add would only
      // wait out a deadline in turn, holding up every edit after it.
      // Best effort: the item runs off its end and loads on advance.
      if (_unanswered > 0) return;
      final source = _sourceFor(url, clipStart, clipEnd);
      final length = _windowLength(clipStart, clipEnd);
      final added = await _bounded(
        () => _player.addAudioSource(source),
        // Landed late, and nothing has been prepared, dropped, or loaded
        // since: it is the preload the caller has recorded, and the
        // crossing into it stays gapless.
        onLateAnswer: () {
          if (generation != _generation ||
              epoch != _preloadEpoch ||
              _preloadedSource != null) {
            return;
          }
          _preloadedSource = source;
          _preloadedLength = length;
        },
      );
      // A load that started while the source was going in owns the
      // window now, and the repair it queued drops what landed here.
      // Recording a preload against it would leave the engine expecting
      // a crossing that cannot come.
      if (!added || generation != _generation) return;
      _preloadedSource = source;
      _preloadedLength = length;
    });
  }

  @override
  Future<void> clearPreload() => _edit((_) {
    _preloadEpoch++;
    return _dropPreloaded();
  });

  /// Runs a window edit after the ones already queued, against the list
  /// as it stands by then, and only while it still describes the window
  /// the caller asked about.
  ///
  /// The body is handed the generation it belongs to: anything it
  /// decides after an await has to check that a load has not replaced
  /// the window in the meantime.
  Future<void> _edit(Future<void> Function(int generation) body) {
    final generation = _generation;
    final edit = _edits.then((_) async {
      if (_disposed || generation != _generation) return;
      await body(generation);
    });
    // A failed edit must not wedge the ones queued behind it, while the
    // caller still sees its own failure.
    _edits = edit.catchError((_) {});
    return edit;
  }

  /// Drops the source waiting behind the item playing.
  ///
  /// Nothing is waiting once the engine has crossed into it: the
  /// crossing clears the field, so this stops being able to remove an
  /// item that is playing. The residue is the round trip an index event
  /// takes to arrive, during which a crossing has happened that the
  /// engine cannot yet know about; a drop landing inside it stops
  /// playback of an item the caller had just asked to drop, and the load
  /// that follows the caller's own queue change puts it right.
  ///
  /// One the platform will not let go stays on record and throws: it is
  /// still in the platform's list, so a crossing into it has to be
  /// announced rather than played under the item before it, and the
  /// caller keeps its own record for the same reason.
  Future<void> _dropPreloaded() async {
    final waiting = _preloadedSource;
    if (waiting == null) return;
    final dropped = await _remove(
      waiting,
      // The removal landed after all: it no longer follows anything.
      onLateAnswer: () {
        if (identical(_preloadedSource, waiting) &&
            !_player.sequence.any((s) => identical(s, waiting))) {
          _preloadedSource = null;
          _preloadedLength = null;
        }
      },
    );
    if (!dropped) {
      throw TimeoutException(
        'the platform did not let the preloaded item go',
        _loadDeadline,
      );
    }
    _preloadedSource = null;
    _preloadedLength = null;
  }

  /// Removes [source] from the window if it is still in it. False when it
  /// was not taken out: the platform did not answer in time, or a call it
  /// has not answered is ahead, which this would only wait behind.
  Future<bool> _remove(
    AudioSource source, {
    void Function()? onLateAnswer,
  }) async {
    final index = _player.sequence.indexWhere((s) => identical(s, source));
    if (index < 0) return true;
    if (_unanswered > 0) return false;
    return _bounded(
      () => _player.removeAudioSourceRange(index, index + 1),
      onLateAnswer: onLateAnswer,
    );
  }

  /// Runs one window call under the load deadline, answering whether the
  /// platform finished it in time.
  ///
  /// A call that runs out is let go, not cancelled (just_audio has no
  /// cancel), so it can still land and leave the window holding what the
  /// engine never recorded. Once the last such call is answered the
  /// window is trimmed back to what the engine holds.
  Future<bool> _bounded(
    Future<Object?> Function() call, {
    void Function()? onLateAnswer,
  }) async {
    final answer = _run(call);
    try {
      await answer.timeout(_loadDeadline);
      return true;
    } on TimeoutException {
      debugPrint('audio engine: gave up waiting on a window edit');
      _stillOut(answer, onLateAnswer: onLateAnswer);
      return false;
    }
  }

  /// Waits for [answer] up to [limit], counting one that runs out as
  /// still out (see [_stillOut]) and throwing the timeout.
  Future<void> _within(Future<void> answer, Duration limit) async {
    try {
      await answer.timeout(limit);
    } on TimeoutException {
      _stillOut(answer);
      rethrow;
    }
  }

  /// Counts [answer] as out until the platform gets to it, running
  /// [onLateAnswer] if it lands after all, and trims the window once the
  /// last such call is answered.
  ///
  /// Only let go, never cancelled - just_audio has none - and the
  /// platform takes its calls in turn, so every call after this one
  /// waits behind it: while any is out a call made now only spends a
  /// deadline, and a load that runs out never reached the platform.
  void _stillOut(Future<void> answer, {void Function()? onLateAnswer}) {
    _unanswered++;
    unawaited(
      answer
          .then<void>((_) => onLateAnswer?.call(), onError: (Object _) {})
          .whenComplete(() {
            if (--_unanswered == 0) _repairWindow();
          }),
    );
  }

  /// Queues a trim back to the loaded item and the one preloaded behind
  /// it, and does not wait for it.
  ///
  /// A failure only costs an extra source in the window until the next
  /// trim, so it is swallowed here rather than raised into a caller
  /// that never asked for the trim. The handler also keeps a
  /// fire-and-forget edit from ever reaching the zone as an unhandled
  /// error, whatever the queue does with it.
  void _repairWindow() {
    unawaited(
      _edit((generation) async {
        // Backwards, so each removal leaves the indices still to visit
        // where they were.
        for (var i = _player.sequence.length - 1; i >= 0; i--) {
          final sequence = _player.sequence;
          // Only the list the engine describes: just_audio runs playlist
          // calls in turn, so a load made while a call is held leaves the
          // old list standing, and indices counted in it would land on
          // the new item after the reset.
          if (generation != _generation ||
              _unanswered > 0 ||
              !sequence.any((s) => identical(s, _loadedSource))) {
            return;
          }
          final source = sequence[i];
          if (identical(source, _loadedSource) ||
              identical(source, _preloadedSource)) {
            continue;
          }
          await _bounded(() => _player.removeAudioSourceRange(i, i + 1));
        }
      }).catchError((_) {}),
    );
  }

  void _onIndexChanged(int? index) {
    final waiting = _preloadedSource;
    if (waiting == null || index == null) return;
    final sequence = _player.sequence;
    if (index < 0 || index >= sequence.length) return;
    // A crossing is the reported index landing on the source preloadNext
    // put behind the item, which no renumbering can imitate.
    if (!identical(sequence[index], waiting)) return;
    final consumed = _loadedSource;
    _loadedSource = waiting;
    _preloadedSource = null;
    // The item that just finished must not stand in for the new one, so
    // the length carried over is the new one's own or nothing.
    _heldDuration = _preloadedLength;
    _preloadedLength = null;
    if (!_boundaries.isClosed) _boundaries.add(null);
    // Dropping the consumed item renumbers the window, and on the mpv
    // bridge a renumbering republishes position zero. Here that is the
    // truth (the new item has just started), which is why the drop
    // happens at the crossing rather than whenever the next preload
    // arrives, mid-item.
    if (consumed != null) {
      unawaited(_edit((_) => _remove(consumed)).catchError((_) {}));
    }
  }

  /// Keeps the length of the item playing across a window edit.
  ///
  /// The mpv bridge republishes its playback event with a null duration
  /// on every source-list change (adding the preloaded item counts, and
  /// so does dropping the consumed one), and it re-reports a length only
  /// when the underlying file's own length changes. A length that drops
  /// to null while the same item keeps playing is the window sliding,
  /// not the length becoming unknown, so the engine answers with what
  /// the item already reported. Streams that never had a length (live
  /// radio) keep nothing and keep reporting null.
  ///
  /// One subscription writes this, made when the engine is built, so
  /// what the getters below read never depends on who is listening.
  void _rememberDuration(Duration? reported) {
    if (reported != null) _heldDuration = reported;
  }

  /// Length of a clip window, when the engine can compute it.
  ///
  /// Two windows carved from one album rip are the same file to the
  /// platform, so the mpv bridge never re-reports a length when playback
  /// moves between them and would leave the new window with none. The
  /// engine built the window and knows the answer, whether or not the
  /// window names its start (an absent start is the head of the file).
  /// A window with an open end runs to the file's end, which only the
  /// platform knows.
  Duration? _windowLength(Duration? clipStart, Duration? clipEnd) {
    if (clipEnd == null) return null;
    final length = clipEnd - (clipStart ?? Duration.zero);
    // Floor at zero: a window past the media's end plays nothing, never
    // a negative length.
    return length > Duration.zero ? length : Duration.zero;
  }

  AudioSource _sourceFor(String url, Duration? clipStart, Duration? clipEnd) {
    // The MIME hint is unused: just_audio sniffs the container itself on
    // every backend this engine targets.
    final source = AudioSource.uri(Uri.parse(url));
    if (clipStart == null && clipEnd == null) return source;
    // The clip window makes positions, duration, and completion
    // window-relative, which is exactly the port's contract.
    return ClippingAudioSource(child: source, start: clipStart, end: clipEnd);
  }

  @override
  Future<void> play() async {
    final pending = _pending;
    if (pending != null) {
      // Media whose failure is still being worked out is not started
      // again under its announcement: the play is the intent the
      // announcement carries, and whoever recovers the media starts it.
      pending.wantsPlay = true;
      return;
    }
    // A play that follows the end of the item starts it again, which is
    // the port's contract and what every play button on every surface
    // means once `playing` has gone false.
    //
    // Two steps, both load-bearing. just_audio's own `playing` stays
    // true through completion, so the pause is what clears it - without
    // that, the play() below returns at its own `if (playing) return`
    // guard and the request is dropped in silence. The seek is what
    // leaves the completed state. Relying on the seek alone would work
    // only where the backend happens to resume from a still-set
    // play-when-ready: on web it does not, because seeking to the index
    // already loaded just moves currentTime and never issues a play.
    //
    // The mpv bridge never leaves the completed state on its own: its
    // one exit is a buffering flicker, media_kit emits one only when a
    // file loads, and neither a bare seek nor a same-index jump loads
    // anything (libmpv 0.36+ ignores a playlist-pos write that does not
    // change the value). `playing`, gated on leaving completed, would
    // then report false over a replay that is audibly running. So: the
    // seek first, a short grace for the backends that clear on it, and
    // past the grace the held source is reloaded outright - the load
    // walk fires on every backend, and the refetch it costs is paid
    // only where the state machine offered no other door.
    //
    // That makes the replay a load on the platform that declines to
    // finish them, so it is bounded, attempted like one (a failure that
    // lands after it threw is its own, and an end raised before it
    // answered is held), and fails like one. Its fault is read off the
    // failure alone, with no probe: the item played to its end a moment
    // ago, so only a platform naming the file moves the verdict off
    // transport.
    if (_player.processingState == ProcessingState.completed) {
      // An item that ended short failed rather than ended: it resumes
      // where it had got to.
      final from = _endedShort ?? Duration.zero;
      final attempt = _attempting();
      _unsettled = true;
      final bool ours;
      try {
        ours = await _replay(from);
        if (ours && attempt == _attempt) _unsettled = false;
      } on Object catch (failure) {
        throw MediaLoadException(mediaFaultOf(failure, isWeb: _isWeb), failure);
      } finally {
        _settled(attempt);
      }
      // A load took the player over mid-replay: whether its item starts
      // is its caller's to say.
      if (!ours) return;
    }
    // just_audio's own `play()` resolves when playback *stops*, which is
    // its documented contract ("completes when the playback completes or
    // is paused or stopped") and not what this port promises. Returning
    // it directly held every caller for the length of the item: a
    // session published its transport only once the track had ended, and
    // a live stream, which never ends, never published one at all. The
    // request is raised synchronously inside that call, so issuing it
    // and letting go is what "playback is running" amounts to here.
    unawaited(_run(_player.play).catchError(_refused));
  }

  /// Takes a completed item back to [from], its top unless it ended
  /// short, reloading it where the platform will not leave the completed
  /// state otherwise (see [play]).
  ///
  /// False when a load took the player over meanwhile. Checked after every
  /// wait, since past one the seek would move the new item and the reload
  /// would interrupt its load.
  Future<bool> _replay(Duration from) async {
    final generation = _generation;
    await _within(_run(_player.pause), _stopGrace);
    if (generation != _generation) return false;
    // The load deadline, not the stop grace: Android answers a seek only
    // once the player is ready again, so the seek carries the buffering.
    await _within(_run(() => _player.seek(from)), _loadDeadline);
    var cleared = true;
    try {
      await _player.processingStateStream
          .firstWhere((s) => s != ProcessingState.completed)
          .timeout(const Duration(milliseconds: 500));
    } on TimeoutException {
      cleared = false;
    }
    if (generation != _generation) return false;
    final source = _loadedSource;
    if (cleared || source == null) return true;
    // A replay is a fresh single-item window, like stop-then-play: the
    // reload drops anything preloaded behind the completed item, and the
    // fields follow the list.
    _preloadedSource = null;
    _preloadedLength = null;
    _preloadEpoch++;
    await _within(
      _run(
        () => _player.setAudioSources(
          [source],
          initialIndex: 0,
          initialPosition: from,
        ),
      ),
      _loadDeadline,
    );
    _repairWindow();
    return generation == _generation;
  }

  /// Runs a just_audio call in [_zone], its outcome carried out as a value,
  /// since an error cannot leave an error zone.
  Future<void> _run(Future<Object?> Function() call) async {
    final failure = await _zone.run(
      () => call().then<(Object, StackTrace)?>(
        (_) => null,
        onError: (Object error, StackTrace stack) => (error, stack),
      ),
    );
    if (failure != null) Error.throwWithStackTrace(failure.$1, failure.$2);
  }

  /// just_audio 0.10.6 also leaves a failed start's error uncaught, on a
  /// completer nothing listens to yet (on web, a page error). The call has
  /// already reported it, so the player's own types are dropped here.
  static void _dropEcho(
    Zone self,
    ZoneDelegate parent,
    Zone zone,
    Object error,
    StackTrace stack,
  ) {
    if (error is PlayerException || error is PlayerInterruptedException) {
      return;
    }
    parent.handleUncaughtError(zone, error, stack);
  }

  /// Everything the platform reports, read in one place and in order: a
  /// failure or an end is weighed before the state it leaves is shown, so
  /// no reader is told idle or completed about media that failed.
  ///
  /// just_audio derives its error stream from these same events, so the
  /// error is read off the event that carries it, as that stream would
  /// (a repeat of the error the last event carried is the same error).
  void _onPlaybackEvent(PlaybackEvent event) {
    final previous = _lastEvent;
    _lastEvent = event;
    if (_disposed) return;
    final code = event.errorCode;
    if (code != null &&
        (previous?.errorCode != code ||
            previous?.errorMessage != event.errorMessage ||
            previous?.currentIndex != event.currentIndex)) {
      _onFailed(
        PlayerException(code, event.errorMessage, event.currentIndex),
        _failedAt(previous, event),
      );
    } else if (event.processingState == ProcessingState.completed) {
      if (previous != null &&
          previous.processingState != ProcessingState.completed) {
        _onEnded(previous, event);
      }
    } else if (event.processingState != ProcessingState.idle) {
      // Moving again, so an early end no longer stands for the position.
      _endedShort = null;
    }
    _emitState();
  }

  /// Media that had loaded failing afterwards, as the platform reports it.
  ///
  /// Ignored while a load or a replay is unsettled: those report their own
  /// failure by throwing, and the platform's echo of the same failure can
  /// land on either side of the throw. A failed attempt leaves
  /// [_unsettled] set until the next one succeeds, which is exactly the
  /// window in which nothing is loaded to fail afterwards. One failure of
  /// the same media is enough.
  ///
  /// An error arrives with the platform idle, and just_audio releases the
  /// platform player on any move into idle, so the media has stopped
  /// whatever the error was (the mpv bridge reports a frame it could not
  /// decode the same way): it is a failure to recover from every time.
  void _onFailed(PlayerException error, Duration at) {
    if (_unsettled || _pending != null) return;
    final source = _loadedSource;
    if (source == null) return;
    final pending = _pending = _PendingFailure(wantsPlay: playing);
    // just_audio keeps its playing flag raised over a failed element, as it
    // does over a refused start, so the flag is put back first.
    unawaited(_run(_player.pause).catchError((Object _) {}));
    unawaited(_announce(pending, error, source, at));
  }

  /// Where playback stood when it failed: as far as the platform had
  /// played or read, the latter being where a fetch it could not make
  /// stopped it.
  static Duration _failedAt(PlaybackEvent? previous, PlaybackEvent event) {
    var at = Duration.zero;
    for (final position in [
      event.updatePosition,
      event.bufferedPosition,
      ?previous?.updatePosition,
      ?previous?.bufferedPosition,
    ]) {
      if (position > at) at = position;
    }
    return at;
  }

  /// The platform calling the loaded item over. Held while a load or a
  /// replay has not answered (see [_settled]), and nobody's once one failed
  /// or a failure is being worked out.
  void _onEnded(PlaybackEvent previous, PlaybackEvent event) {
    if (_settling != null) {
      _heldEnd = (previous: previous, event: event);
      return;
    }
    if (_unsettled || _pending != null) return;
    _ended(previous, event);
  }

  /// An end of the loaded media: the queue-ended the port announces, or,
  /// for an HLS presentation the platform calls over well short of its
  /// length, a failure. mpv hands HLS to libavformat, which steps over a
  /// segment it cannot fetch (a refused one, an engine with no slot free)
  /// rather than failing, plays what it had and ends, so a refusal
  /// mid-listen reads as the item ending early: reported finished, a book
  /// rolled into its next part. A presentation's length is its playlist's,
  /// exact, so ending well short of it is a failure; a progressive
  /// stream's length is an estimate and is left alone.
  ///
  /// Where it got to is the end's own position where the platform keeps
  /// one (ExoPlayer), else the last one reported, run on to the end (the
  /// mpv bridge zeroes it as it completes).
  void _ended(PlaybackEvent previous, PlaybackEvent event) {
    final source = _loadedSource;
    final length = duration;
    if (source != null && length != null && _isPresentation(source)) {
      var reached = previous.updatePosition;
      if (previous.processingState == ProcessingState.ready &&
          _player.playing) {
        reached +=
            event.updateTime.difference(previous.updateTime) * _player.speed;
      }
      // What it had read, not only what was heard: mpv ends as its decoder
      // runs dry, while the output still drains, so its last position is
      // behind the end by the speed times the output's delay. Its buffered
      // position is where reading stopped, the end after a whole read and
      // short of it after stepped-over segments.
      for (final at in [event.updatePosition, previous.bufferedPosition]) {
        if (at > reached) reached = at;
      }
      if (length - reached > _presentationEndSlack) {
        _endedShort = reached;
        final pending = _pending = _PendingFailure(wantsPlay: true);
        // Paused, as a failed element is, so a seek made before the
        // recovery moves where it resumes rather than starting it.
        unawaited(_run(_player.pause).catchError((Object _) {}));
        unawaited(
          _announce(pending, _EndedShort(reached, length), source, reached),
        );
        return;
      }
    }
    if (!_completions.isClosed) _completions.add(null);
  }

  /// Announces the failure [pending] stands for, once the probe has said
  /// what it can, at [at] into [source].
  ///
  /// The probe can take its whole deadline, and the listener can act
  /// meanwhile. A stop, a load or disposal lets the media go, and with it
  /// the announcement: nothing is said about media the engine no longer
  /// holds. A pause or a play changes only the intent it carries. A seek
  /// leaves it standing - the media is still failed (just_audio's seek on
  /// a released player moves its idle position and fetches nothing) - and
  /// moves where the recovery picks up, which reads the position then.
  Future<void> _announce(
    _PendingFailure pending,
    Object cause,
    AudioSource source,
    Duration at,
  ) async {
    final read = await probedMediaFailureOf(
      cause,
      _urlOf(source),
      ask: _ask,
      isWeb: _isWeb,
      midPlay: true,
      presentation: _isPresentation(source),
      at: _presentationAt(source, at),
    );
    if (!identical(_pending, pending) || _failures.isClosed) return;
    _pending = null;
    // The failure before the idle it leaves: whoever recovers the media
    // hears of it before anything reads nothing as loaded.
    _failures.add(
      MediaFailure(
        read.fault,
        cause,
        wasPlaying: pending.wantsPlay,
        refusal: read.refusal,
      ),
    );
    _emitState();
  }

  /// Tells the state's listeners what it reads now; repeats are theirs to
  /// drop (see [processingStateStream]).
  void _emitState() {
    if (!_states.isClosed) _states.add(processingState);
  }

  /// Whether [source] is an HLS presentation: what just_audio built from
  /// the URL, which is how the platform was asked to read it.
  static bool _isPresentation(AudioSource source) => switch (source) {
    ClippingAudioSource(:final child) => child is HlsAudioSource,
    _ => source is HlsAudioSource,
  };

  /// [at] into [source] as a position in the media it was carved from,
  /// which is what a presentation's playlist counts in.
  static Duration _presentationAt(AudioSource source, Duration at) =>
      switch (source) {
        ClippingAudioSource(:final start?) => at + start,
        _ => at,
      };

  static String _urlOf(AudioSource source) => switch (source) {
    ClippingAudioSource(:final child) => child.uri.toString(),
    UriAudioSource(:final uri) => uri.toString(),
    _ => '',
  };

  /// The platform turned the request down (a browser's autoplay policy).
  ///
  /// just_audio raises its playing flag before it asks the platform and
  /// leaves it raised when the answer is no, so the engine would report
  /// itself playing over silence. The flag is put back first, so every
  /// surface reads the truth, and the refusal is announced after.
  /// Nothing here may throw: it is reached through `catchError` on a
  /// request nobody awaits, so an error escaping it has no handler and
  /// surfaces as an unhandled zone error. Disposal is the way to get
  /// one - the flag is raised several awaits before the player is
  /// actually released, and a pause issued into that window is talking
  /// to a platform that is tearing down.
  Future<void> _refused(Object error) async {
    if (_disposed) return;
    try {
      await _run(_player.pause);
    } on Object catch (failure) {
      // The flag stays raised, which is the lesser wrong: there is
      // nothing left to report it to either.
      debugPrint('could not put the playing flag back: $failure');
    }
    if (!_refusals.isClosed) _refusals.add(error);
  }

  @override
  Future<void> pause() {
    _pending?.wantsPlay = false;
    return _run(_player.pause);
  }

  @override
  Future<void> seek(Duration position) {
    // An item that ended short stays failed rather than ended, and the
    // seek moves where it resumes.
    if (_endedShort != null) _endedShort = position;
    return _run(() => _player.seek(position));
  }

  @override
  Future<void> stop() async {
    // What was failing, or had ended short, is let go with the media.
    _pending = null;
    _heldEnd = null;
    _endedShort = null;
    _emitState();
    await _run(_player.stop);
    // Stopping releases the media, and the window with it: playing again
    // resumes the item that was loaded and ends there, rather than
    // crossing into one the caller stopped before reaching.
    try {
      await clearPreload();
    } on TimeoutException {
      // The media is stopped. A preload the platform would not let go
      // stays on record, so a play that crosses into it is announced.
    }
  }

  @override
  Future<void> dispose() async {
    // Edits already queued belong to a player that is about to go away;
    // the flag is what stops them running against it.
    _disposed = true;
    _pending = null;
    await _indexSub.cancel();
    await _durationSub.cancel();
    await _eventSub.cancel();
    await _boundaries.close();
    await _refusals.close();
    await _failures.close();
    await _completions.close();
    await _states.close();
    await _run(_player.dispose);
  }

  @override
  Duration get position => _endedShort ?? _player.position;

  @override
  Stream<Duration> get positionStream =>
      _player.positionStream.map((position) => _endedShort ?? position);

  @override
  Duration? get duration => _player.duration ?? _heldDuration;

  /// Measured on the web only: ExoPlayer's progressive source restarts an
  /// unseekable stream at its head, and mpv is unmeasured.
  @override
  bool get seeksWithinUnrangedStream => _isWeb;

  /// ExoPlayer and mpv both play HLS; just_audio_web's element does not.
  @override
  bool get playsHls => !_isWeb;

  @override
  Duration get bufferedPosition {
    final buffered = _player.bufferedPosition;
    final length = duration;
    return length != null && buffered > length ? length : buffered;
  }

  @override
  Stream<Duration?> get durationStream => _player.durationStream
      .map((reported) => reported ?? _heldDuration)
      .distinct();

  // just_audio keeps its playing flag raised after playback runs off the
  // end of the media; the port contract (and the fake) drop it. Normalize
  // here so every engine reports completion the same way.
  @override
  bool get playing =>
      _player.playing && _player.processingState != ProcessingState.completed;

  @override
  Stream<bool> get playingStream => _player.playerStateStream
      .map((s) => s.playing && s.processingState != ProcessingState.completed)
      .distinct();

  @override
  EngineProcessingState get processingState => _shown(_player.processingState);

  /// Built once, like every stream here: a getter that merged afresh would
  /// resubscribe for every reader on every rebuild. One instance, listened
  /// to as often as anyone likes (a composite keeps the one it picked);
  /// each listener holds its own subscription, is told the state it
  /// starts in as the platform's own stream tells it, and is done when
  /// the engine is.
  @override
  late final Stream<EngineProcessingState> processingStateStream =
      Stream<EngineProcessingState>.multi((listener) {
        listener.add(processingState);
        final states = _states.stream.listen(
          listener.add,
          onError: listener.addError,
          onDone: listener.close,
        );
        listener.onCancel = states.cancel;
      }, isBroadcast: true).distinct();

  /// The platform's state as the port reports it: loading while a failure
  /// is still being worked out (audio_service reads idle as the service
  /// stopping, and the media is not let go until it is announced) and for
  /// the whole of an attempt that has not answered, whose end is held
  /// until it does (see [_settling]); idle after one that failed, and for
  /// an item that ended short, where nothing is loaded whatever the
  /// platform last said.
  EngineProcessingState _shown(ProcessingState state) {
    if (_pending != null) return EngineProcessingState.loading;
    if (_settling != null) {
      return state == ProcessingState.idle || state == ProcessingState.completed
          ? EngineProcessingState.loading
          : _map(state);
    }
    if (_unsettled) return EngineProcessingState.idle;
    if (state == ProcessingState.completed && _endedShort != null) {
      return EngineProcessingState.idle;
    }
    return _map(state);
  }

  // just_audio reports completion for the source list, not for each item
  // in it, so this is already queue-ended: an item ending into the
  // preloaded one moves the index and leaves the state ready.
  @override
  Stream<void> get completed => _completions.stream;

  @override
  Stream<void> get itemBoundary => _boundaries.stream;

  @override
  Stream<Object> get playbackRefused => _refusals.stream;

  @override
  Stream<MediaFailure> get mediaFailed => _failures.stream;

  @override
  Future<void> setSpeed(double speed) => _run(() => _player.setSpeed(speed));

  @override
  double get speed => _player.speed;

  @override
  Future<void> setVolume(double volume) =>
      _run(() => _player.setVolume(volume));

  @override
  double get volume => _player.volume;

  @override
  Stream<double> get speedStream => _player.speedStream;

  @override
  Stream<double> get volumeStream => _player.volumeStream;

  EngineProcessingState _map(ProcessingState state) {
    return switch (state) {
      ProcessingState.idle => EngineProcessingState.idle,
      ProcessingState.loading ||
      ProcessingState.buffering => EngineProcessingState.loading,
      ProcessingState.ready => EngineProcessingState.ready,
      ProcessingState.completed => EngineProcessingState.completed,
    };
  }
}

/// How far short of its playlist length an HLS presentation may end and
/// still have ended. Its length is exact and what a natural end had read
/// lands within a frame of it; the least a stepped-over refusal loses is a
/// segment, four seconds at the engine's default.
const Duration _presentationEndSlack = Duration(seconds: 2);

/// A failure of the loaded media waiting on its probe to be announced.
class _PendingFailure {
  _PendingFailure({required this.wantsPlay});

  /// The play intent the announcement carries: whether it was playing
  /// when it failed, moved by a pause or a play made since.
  bool wantsPlay;
}

/// An HLS presentation the platform called over at [reached] of [length].
class _EndedShort implements Exception {
  const _EndedShort(this.reached, this.length);

  final Duration reached;
  final Duration length;

  @override
  String toString() => 'presentation ended at $reached of $length';
}

/// A load the deadline gave up on, and whether a call the engine had
/// already stopped waiting for was ahead of it.
class _Abandoned implements Exception {
  const _Abandoned(this.timeout, {required this.behindAnother});

  final TimeoutException timeout;
  final bool behindAnother;
}
