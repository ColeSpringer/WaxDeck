/// The WaxDeck-owned audio engine contract.
library;

/// Coarse lifecycle of the loaded media.
enum EngineProcessingState {
  /// Nothing loaded, or playback was stopped.
  idle,

  /// Media is being fetched or buffered.
  loading,

  /// Media is ready; play and seek work.
  ready,

  /// Playback ran off the end of everything the engine holds: the loaded
  /// item finished with nothing preloaded behind it (queue-ended).
  ///
  /// An item finishing into an item [AudioEnginePort.preloadNext]
  /// prepared is the other case (item-ended) and never reaches here: the
  /// engine stays [ready] and fires [AudioEnginePort.itemBoundary].
  completed,
}

/// Small, honest facade over whatever audio plugin actually plays sound.
///
/// App code depends on this interface only. Community plugins (just_audio
/// and the media_kit bridge today) live behind it, so replacing or upgrading
/// them never touches feature code.
abstract interface class AudioEnginePort {
  /// Loads [url] and prepares it for playback, optionally starting at
  /// [initialPosition]. [mimeType] is a hint; engines may ignore it.
  ///
  /// [clipStart] and [clipEnd] restrict playback to a window of the
  /// source: an item carved out of a larger file plays as if the
  /// window were the whole media, with positions, duration, and
  /// completion all window-relative ([initialPosition] included). A
  /// null [clipEnd] with a set [clipStart] runs to the source's end.
  Future<void> load(
    String url, {
    String? mimeType,
    Duration? initialPosition,
    Duration? clipStart,
    Duration? clipEnd,
  });

  /// Prepares [url] to follow the loaded item with no reload between
  /// them, so a queue plays gapless where the platform allows.
  ///
  /// The preloaded item starts at the beginning of its window
  /// ([clipStart] and [clipEnd] carve it exactly as [load] does): an
  /// item that has to start anywhere else is loaded on advance instead.
  /// Calling this again replaces whatever was preloaded. Crossing into
  /// the preloaded item fires [itemBoundary], and from that moment it is
  /// the loaded item: [position], [duration], and [completed] are its
  /// own, and nothing is preloaded until the next call.
  ///
  /// Preloading is best effort. An engine that cannot do it leaves this
  /// a no-op and runs off the end normally, so a caller that advances on
  /// [completed] keeps working, with an audible gap instead of a
  /// gapless one. Preloading before the first [load] does nothing: there
  /// is no item to follow.
  Future<void> preloadNext(
    String url, {
    String? mimeType,
    Duration? clipStart,
    Duration? clipEnd,
  });

  /// Drops the preloaded item, so the loaded one ends the queue.
  ///
  /// Does nothing when nothing is preloaded. [load] and [stop] clear the
  /// preload too: a fresh load starts a fresh window, and a stop
  /// releases the whole one.
  Future<void> clearPreload();

  /// Starts or resumes playback.
  Future<void> play();

  /// Pauses playback, keeping the position.
  Future<void> pause();

  /// Moves the playback position.
  Future<void> seek(Duration position);

  /// Stops playback and releases the media, keeping the engine usable.
  /// Anything [preloadNext] prepared goes with it, so playing again
  /// resumes the loaded item and ends there.
  Future<void> stop();

  /// Releases the engine permanently. No calls are valid afterwards.
  Future<void> dispose();

  /// Current playback position.
  Duration get position;

  /// Position updates during playback and after seeks.
  Stream<Duration> get positionStream;

  /// Duration of the loaded media, when known.
  Duration? get duration;

  /// Duration updates as media loads.
  Stream<Duration?> get durationStream;

  /// Whether playback is currently running (play intent, not buffering).
  bool get playing;

  /// Play and pause transitions.
  Stream<bool> get playingStream;

  /// Current media lifecycle state.
  EngineProcessingState get processingState;

  /// Media lifecycle transitions.
  Stream<EngineProcessingState> get processingStateStream;

  /// Fires once each time playback reaches the end of the loaded media
  /// with nothing preloaded behind it: the engine has run out
  /// (queue-ended). An item ending into a preloaded one fires
  /// [itemBoundary] instead, never this.
  Stream<void> get completed;

  /// Fires once each time playback crosses out of the loaded item and
  /// into the one [preloadNext] prepared (item-ended).
  ///
  /// Playback does not stop across the boundary: the engine stays
  /// [EngineProcessingState.ready] and playing, and by the time this
  /// fires [duration] and [position] read against the new item. Callers
  /// roll their own accounting over here; the engine needs nothing.
  Stream<void> get itemBoundary;

  /// Sets the playback speed multiplier (1.0 is normal speed). The
  /// setting survives pause/play and loading new media.
  Future<void> setSpeed(double speed);

  /// Current playback speed multiplier.
  double get speed;

  /// Speed changes from [setSpeed].
  Stream<double> get speedStream;

  /// Sets the output volume, 0.0 (silent) to 1.0 (full). The setting
  /// survives pause/play and loading new media. Remote control and
  /// the sleep timer's fade both ride this.
  Future<void> setVolume(double volume);

  /// Current output volume.
  double get volume;
}
