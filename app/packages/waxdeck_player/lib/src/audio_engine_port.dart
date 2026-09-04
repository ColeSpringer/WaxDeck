/// The WaxDeck-owned audio engine contract.
library;

import 'timeline/timeline_media.dart';

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

/// Which half of a failed [AudioEnginePort.load] is at fault.
///
/// The split is the only one a caller can act differently on: one of
/// these says the queue behind this item is fine and the next press
/// will fail the same way, and the other says the opposite.
enum MediaFault {
  /// The media itself: a container nothing here decodes, a truncated
  /// rip, a codec the platform does not carry. Trying again gets the
  /// same answer, so the useful response is to move past it.
  source,

  /// Fetching the media: the server, the network, the token. Nothing is
  /// wrong with the file, so the useful response is to offer a retry -
  /// and never to walk the queue, which would spend a listener's
  /// library one track at a time on a dropped connection.
  transport,
}

/// A [AudioEnginePort.load] that did not produce playable media.
///
/// The type an engine throws out of `load`, and the only one: an engine
/// that cannot classify a failure says [MediaFault.transport], because
/// the cost of reading a bad file as a bad connection is one retry and
/// the cost of the reverse is a queue skipped past on a flaky network.
class MediaLoadException implements Exception {
  const MediaLoadException(this.fault, this.cause);

  final MediaFault fault;

  /// What the plugin threw, kept for the log. Never matched on above
  /// this line - that is what [fault] is for.
  final Object cause;

  @override
  String toString() => 'MediaLoadException(${fault.name}): $cause';
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
  ///
  /// Throws [MediaLoadException] and nothing else: classifying the
  /// plugin's own exception is the engine's job, because the plugin is
  /// the thing an engine exists to know about.
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
  /// gapless one - and says so through [canPreload], so a caller can
  /// skip the work of preparing an item nothing will take. Preloading
  /// before the first [load] does nothing: there is no item to follow.
  Future<void> preloadNext(
    String url, {
    String? mimeType,
    Duration? clipStart,
    Duration? clipEnd,
  });

  /// Whether [preloadNext] does anything here.
  ///
  /// False is not a failure and needs no handling: the engine runs off
  /// the end and answers [completed], which is the path an advance
  /// takes anyway. It is here so a caller does not pay to resolve,
  /// authorize, and mint a stream for an item that will be dropped -
  /// per track, for as long as a queue plays.
  bool get canPreload;

  /// Drops the preloaded item, so the loaded one ends the queue.
  ///
  /// Does nothing when nothing is preloaded. [load] and [stop] clear the
  /// preload too: a fresh load starts a fresh window, and a stop
  /// releases the whole one.
  Future<void> clearPreload();

  /// Starts or resumes playback.
  ///
  /// Resolves once the engine has taken the request and playback is
  /// running, never when the item ends: a caller waits on this before
  /// showing a transport, and an engine that answered at the end of the
  /// track would leave a live stream's caller waiting for good.
  ///
  /// A platform that turns the request down answers on
  /// [playbackRefused] rather than here: the refusal arrives after the
  /// request has been dispatched, and waiting for one would mean
  /// waiting on every start that is going to succeed.
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

  /// Fires when the platform refused to start playback, carrying
  /// whatever reason it gave.
  ///
  /// Browsers refuse a programmatic resume that no gesture led to (a
  /// Connect handoff, a restored queue put back into play, a sleep timer
  /// cancelled from a notification). The media stays loaded and where it
  /// belongs; only the start was turned down, and [playing] reads false
  /// by the time this fires, so a surface can offer the tap that would
  /// be allowed rather than reporting a failure.
  Stream<Object> get playbackRefused;

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

  /// Volume changes, wherever they came from.
  ///
  /// A surface drawing the level cannot own it, which is the whole reason
  /// this exists: a routed `set-volume` from another device and the sleep
  /// timer's fade both write here without asking any widget, so a slider
  /// holding its own copy of the number would show a loudness the output
  /// no longer has.
  ///
  /// Replays the current level to a new listener. A surface built after the
  /// level moved would otherwise draw full until somebody changed it.
  Stream<double> get volumeStream;
}

/// An engine that can also play a whole queue as one continuous stream.
///
/// The ordinary port loads one item at a time and crosses into a
/// preloaded next; a timeline engine is handed the queue already
/// rendered, so the crossing happens inside media that never stops.
/// Everything on [AudioEnginePort] keeps its meaning while a timeline
/// is loaded, read against the member playing: [position] and
/// [duration] are that member's own, [itemBoundary] fires as playback
/// crosses a seam, and [completed] fires only when the last member
/// ends.
///
/// The two are not exclusive. An engine implementing this still loads
/// single items through [load] - a podcast, a book, a station - and
/// says so by answering false to [canPreload] while a timeline is what
/// it holds, since the seams are the server's to arrange and there is
/// no window for a caller to fill.
abstract interface class TimelineAudioEngine implements AudioEnginePort {
  /// Loads [media] and positions at [position] into [member].
  ///
  /// The same URL already loaded is not reloaded: it pauses and seeks,
  /// which is what a skip inside a loaded timeline is. [play] is for
  /// the one case that must not pause first - swapping to a freshly
  /// minted timeline at the seam that is happening now.
  ///
  /// Throws [MediaLoadException] and nothing else, like [load].
  Future<void> loadTimeline(
    TimelineMedia media, {
    int member = 0,
    Duration? position,
    bool play = false,
  });

  /// Moves to [position] into [member] of the loaded timeline.
  ///
  /// A seek, not a crossing: [duration] and [position] republish for
  /// the member landed on and [itemBoundary] does not fire, because
  /// nothing played its way over. The caller moved the queue and
  /// already knows.
  Future<void> seekToMember(int member, Duration position);

  /// Formats this engine can actually decode, most preferred first, as
  /// the mint names them. What comes back is asked for by name because
  /// a rendering the engine cannot decode is silence with nothing to
  /// explain it: better to say so before the queue is rendered.
  List<String> get supportedTimelineFormats;

  /// Whether this engine can play a timeline at all, having done
  /// whatever one-time preparation the answer needs - fetching a
  /// player library, probing the media source.
  ///
  /// Asked before a queue is rendered, because a render costs the
  /// server real work and a transcode slot: an engine that answers
  /// false here has cost the listener nothing but the ordinary path.
  /// [supportedTimelineFormats] answers about codecs and can be read
  /// at any time; this answers about the machinery around them.
  Future<bool> prepareTimelines();

  /// The timeline currently loaded, or null when [load] holds the
  /// engine instead.
  TimelineMedia? get loadedTimeline;

  /// Which member of [loadedTimeline] is playing.
  int get currentMember;

  /// Fires when the loaded timeline stops being servable: its token
  /// expired, the server aged it out, or the files moved underneath it.
  /// Nothing is playing by then; the caller mints another and reloads.
  ///
  /// Carries whether it was playing when it was lost, which is the one
  /// thing the reload cannot read back off the engine: silencing the
  /// stream is part of losing it, so by the time anybody hears about
  /// it [playing] is false whatever the listener had asked for.
  Stream<bool> get timelineLost;

  /// Fires with a refusal code met mid-stream (`transcode-limited` when
  /// the server's session cap is reached on a fetch). Distinct from
  /// [timelineLost] because re-minting does not help: the answer is to
  /// tell the listener what the server said.
  Stream<String> get timelineRefused;
}
