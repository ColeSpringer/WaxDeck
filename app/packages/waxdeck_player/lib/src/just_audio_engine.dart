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
/// rows are unmeasured too. [probedMediaFaultOf] is the second step
/// that covers the difference: where this table has no verdict, it
/// asks the network for one.
///
/// Desktop is not in this table at all: mpv through media_kit does not
/// report a failed load, it simply never finishes one, so nothing
/// reaches here to be classified. What ends that wait is the engine's
/// own load deadline, and what classifies the result is the probe
/// below - alone, rather than as a refinement of a code.
@visibleForTesting
MediaFault mediaFaultOf(Object failure) {
  if (failure is! PlayerException) return MediaFault.transport;
  // `MediaError.code`: 3 is MEDIA_ERR_DECODE and 4 is
  // MEDIA_ERR_SRC_NOT_SUPPORTED, which are the element saying it cannot
  // make sound out of these bytes. 1 (aborted) and 2 (network) are not
  // the file.
  if (kIsWeb) {
    return failure.code == 3 || failure.code == 4
        ? MediaFault.source
        : MediaFault.transport;
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

/// [mediaFaultOf], then one question the platform cannot refuse to
/// answer: when the code carried no verdict, what does the URL say
/// about itself?
///
/// On Android every load failure arrives as `TYPE_SOURCE` with a
/// constant string (measured; see [mediaFaultOf]), so the code alone
/// left a bad rip standing on the retry pane. The probe separates the
/// halves from outside the plugin. A URL that answers a ranged GET has
/// nothing wrong with its server, its network, or its token, so what
/// refused was the bytes - [MediaFault.source]. A URL that answers 415
/// says the same thing from the other side: our own endpoint would not
/// make audio out of that file either ([StreamProbe.unplayable]), which
/// is a verdict about the media and not about the way to it. WaxDeck's
/// stream URLs are HMAC-signed and replayable (`auth/mediatoken.go`),
/// so the request consumes nothing, and it is spent only on a load that
/// has already failed.
///
/// Refinement runs one way. A probe that reaches nothing proves
/// nothing new - the transport verdict it would confirm is already the
/// answer - so an unreachable URL and a probe that breaks both leave
/// [MediaFault.transport] standing, and a [MediaFault.source] from the
/// table is never second-guessed. Only a `PlayerException` is probed:
/// the player refusing for a reason it will not name is the ambiguity
/// this resolves, and a failure from anywhere else says nothing about
/// the media. The residual risk is a connection that dropped and came
/// back within the probe's window, which reads as the file and skips
/// one good track; the reverse mistake walks the queue, which is why
/// the default stays transport.
@visibleForTesting
Future<MediaFault> probedMediaFaultOf(
  Object failure,
  String url, {
  Future<StreamProbe> Function(String url) probe = probeStream,
}) async {
  final fault = mediaFaultOf(failure);
  if (fault != MediaFault.transport || failure is! PlayerException) {
    return fault;
  }
  try {
    return (await probe(url)).blamesMedia ? MediaFault.source : fault;
  } on Object {
    // The port promises MediaLoadException and nothing else; a probe
    // that broke does not get to break that.
    return fault;
  }
}

/// How long a load may take before the engine stops waiting for it.
///
/// The outer bound on a platform that can decline to answer at all: mpv
/// never reports a failed load, so without this the session sits on the
/// last face forever. Generous, because everything under it is a real
/// load that deserves to finish - a cold NAS, a large file over a slow
/// link. The cost of that generosity is at the far end: a slow but
/// legitimate load whose URL still answers is classified as the media
/// and auto-skipped rather than paned. "Answers" is a status line -
/// `probeStream` reads one and hangs up - so a host that returns
/// headers promptly and then stalls the body reads as the media every
/// time. Taken knowingly, because it is the same verdict Android
/// already gives garbage bytes on disk, and the skip surface names
/// what happened.
const Duration _defaultLoadDeadline = Duration(seconds: 15);

/// How long a `stop()` gets, both the one before a load and the one
/// that abandons a timed-out load. A player that would not finish a
/// load may not finish a stop either, so this is what keeps a hang from
/// moving one call along rather than being reported.
const Duration _defaultStopGrace = Duration(seconds: 2);

/// [AudioEnginePort] backed by just_audio.
///
/// One facade drives every platform: the bundled just_audio backends on
/// mobile and web, and mpv via the media_kit bridge on desktop (see the
/// bootstrap helper). This class is the only place just_audio types appear.
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
  /// be made to hang, a probe that answers without a network, and a
  /// deadline short enough to wait out. Nothing but a test builds an
  /// engine this way.
  @visibleForTesting
  JustAudioEngine.withPlayer(
    this._player, {
    this._loadDeadline = _defaultLoadDeadline,
    this._stopGrace = _defaultStopGrace,
    this._probe = probeStream,
  }) {
    _indexSub = _player.currentIndexStream.listen(_onIndexChanged);
    _durationSub = _player.durationStream.listen(_rememberDuration);
  }

  final AudioPlayer _player;
  final Duration _loadDeadline;
  final Duration _stopGrace;
  final Future<StreamProbe> Function(String url) _probe;
  final _boundaries = StreamController<void>.broadcast();
  final _refusals = StreamController<Object>.broadcast();
  late final StreamSubscription<int?> _indexSub;
  late final StreamSubscription<Duration?> _durationSub;

  /// Window edits run one at a time. Crossing a boundary schedules the
  /// drop of the item just consumed at the same moment the caller is
  /// preloading the one after it, and both address the same list.
  Future<void> _edits = Future<void>.value();

  /// Bumped by [load]. An edit queued against the window that load
  /// replaced is dropped rather than run against the item that replaced
  /// it.
  int _generation = 0;

  bool _disposed = false;

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
    _loadedSource = source;
    _preloadedSource = null;
    _preloadedLength = null;
    _heldDuration = _windowLength(clipStart, clipEnd);
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
      if (_player.processingState != ProcessingState.idle) {
        // Bounded like the abandonment stop below and for the same
        // reason: this runs against a player that may be mid-hang from
        // a load the deadline already gave up on, and an unbounded wait
        // here would simply move the hang one call along - no deadline,
        // no fault, no pane. A stop that will not land leaves the load
        // to fail on its own deadline, which is the honest report.
        try {
          await _player.stop().timeout(_stopGrace);
        } on TimeoutException {
          // Swallowed: the load below is what answers for this player.
        }
      }
      await _player
          .setAudioSources(
            [source],
            initialIndex: 0,
            initialPosition: initialPosition,
          )
          .timeout(_loadDeadline);
    } on Object catch (failure) {
      throw MediaLoadException(
        await _faultOf(failure, url, generation),
        failure,
      );
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
    }
  }

  /// What a failed load was, including the failure the platform never
  /// reported.
  ///
  /// A load the deadline cut short arrives as a `TimeoutException`, so
  /// [probedMediaFaultOf] would take its own early exit - the probe is
  /// spent only on a `PlayerException`, because everywhere else a
  /// failure from outside the plugin says nothing about the media.
  /// Here it says everything: a deadline is the only report the desktop
  /// gives, so the probe is the whole classification rather than a
  /// refinement of one. A URL that answers a ranged GET while the
  /// player could not finish with it is the media's fault, and so is
  /// one that answers 415 - mpv giving up on a file the server would
  /// not serve as audio is the same file twice. A URL that answers
  /// neither is the transport's.
  Future<MediaFault> _faultOf(
    Object failure,
    String url,
    int generation,
  ) async {
    if (failure is! TimeoutException) {
      return probedMediaFaultOf(failure, url, probe: _probe);
    }
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
        await _player.stop().timeout(_stopGrace);
      } on Object {
        // A player that will not stop is the same player that would not
        // load; the fault below is still the honest answer.
      }
    }
    try {
      return (await _probe(url)).blamesMedia
          ? MediaFault.source
          : MediaFault.transport;
    } on Object {
      // The port promises MediaLoadException and nothing else.
      return MediaFault.transport;
    }
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
  @override
  bool get canPreload => !kIsWeb;

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
      final source = _sourceFor(url, clipStart, clipEnd);
      await _player.addAudioSource(source);
      // A load that started while the source was going in owns the
      // window now, and the repair it queued drops what landed here.
      // Recording a preload against it would leave the engine expecting
      // a crossing that cannot come.
      if (generation != _generation) return;
      _preloadedSource = source;
      _preloadedLength = _windowLength(clipStart, clipEnd);
    });
  }

  @override
  Future<void> clearPreload() => _edit((_) => _dropPreloaded());

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
  Future<void> _dropPreloaded() async {
    final waiting = _preloadedSource;
    if (waiting == null) return;
    await _remove(waiting);
    _preloadedSource = null;
    _preloadedLength = null;
  }

  /// Removes [source] from the window if it is still in it.
  Future<void> _remove(AudioSource source) async {
    final index = _player.sequence.indexWhere((s) => identical(s, source));
    if (index < 0) return;
    await _player.removeAudioSourceRange(index, index + 1);
  }

  /// Queues a trim back to the loaded item and does not wait for it.
  ///
  /// A failure only costs an extra source in the window, which the next
  /// edit clears anyway, so it is swallowed here rather than raised into
  /// a caller that never asked for the trim. The handler also keeps a
  /// fire-and-forget edit from ever reaching the zone as an unhandled
  /// error, whatever the queue does with it.
  void _repairWindow() {
    unawaited(
      _edit((_) async {
        final keep = _loadedSource;
        if (keep == null) return;
        // Backwards, so each removal leaves the indices still to visit
        // where they were.
        for (var i = _player.sequence.length - 1; i >= 0; i--) {
          if (identical(_player.sequence[i], keep)) continue;
          await _player.removeAudioSourceRange(i, i + 1);
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
    if (_player.processingState == ProcessingState.completed) {
      await _player.pause();
      await _player.seek(Duration.zero);
      var cleared = true;
      try {
        await _player.processingStateStream
            .firstWhere((s) => s != ProcessingState.completed)
            .timeout(const Duration(milliseconds: 500));
      } on TimeoutException {
        cleared = false;
      }
      final source = _loadedSource;
      if (!cleared && source != null) {
        // A replay is a fresh single-item window, like stop-then-play:
        // the reload drops anything preloaded behind the completed
        // item, and the fields follow the list.
        _preloadedSource = null;
        _preloadedLength = null;
        await _player.setAudioSources([source], initialIndex: 0);
        _repairWindow();
      }
    }
    // just_audio's own `play()` resolves when playback *stops*, which is
    // its documented contract ("completes when the playback completes or
    // is paused or stopped") and not what this port promises. Returning
    // it directly held every caller for the length of the item: a
    // session published its transport only once the track had ended, and
    // a live stream, which never ends, never published one at all. The
    // request is raised synchronously inside that call, so issuing it
    // and letting go is what "playback is running" amounts to here.
    unawaited(_player.play().catchError(_refused));
  }

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
      await _player.pause();
    } on Object catch (failure) {
      // The flag stays raised, which is the lesser wrong: there is
      // nothing left to report it to either.
      debugPrint('could not put the playing flag back: $failure');
    }
    if (!_refusals.isClosed) _refusals.add(error);
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player.stop();
    // Stopping releases the media, and the window with it: playing again
    // resumes the item that was loaded and ends there, rather than
    // crossing into one the caller stopped before reaching.
    await clearPreload();
  }

  @override
  Future<void> dispose() async {
    // Edits already queued belong to a player that is about to go away;
    // the flag is what stops them running against it.
    _disposed = true;
    await _indexSub.cancel();
    await _durationSub.cancel();
    await _boundaries.close();
    await _refusals.close();
    await _player.dispose();
  }

  @override
  Duration get position => _player.position;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Duration? get duration => _player.duration ?? _heldDuration;

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
  EngineProcessingState get processingState => _map(_player.processingState);

  @override
  Stream<EngineProcessingState> get processingStateStream =>
      _player.processingStateStream.map(_map).distinct();

  // just_audio reports completion for the source list, not for each item
  // in it, so this is already queue-ended: an item ending into the
  // preloaded one moves the index and leaves the state ready.
  @override
  Stream<void> get completed => _player.processingStateStream.where(
    (state) => state == ProcessingState.completed,
  );

  @override
  Stream<void> get itemBoundary => _boundaries.stream;

  @override
  Stream<Object> get playbackRefused => _refusals.stream;

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  double get speed => _player.speed;

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

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
