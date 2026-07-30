import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_engine_port.dart';

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
  JustAudioEngine() : _player = AudioPlayer() {
    _indexSub = _player.currentIndexStream.listen(_onIndexChanged);
    _durationSub = _player.durationStream.listen(_rememberDuration);
  }

  final AudioPlayer _player;
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
    _generation++;
    _loadedSource = source;
    _preloadedSource = null;
    _preloadedLength = null;
    _heldDuration = _windowLength(clipStart, clipEnd);
    try {
      await _player.setAudioSources(
        [source],
        initialIndex: 0,
        initialPosition: initialPosition,
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

  @override
  Future<void> preloadNext(
    String url, {
    String? mimeType,
    Duration? clipStart,
    Duration? clipEnd,
  }) {
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
