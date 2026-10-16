import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

import '../connect/connect_controller.dart';
import '../connect/connect_providers.dart';
import '../connectivity/connectivity_port.dart';
import '../l10n/explain_error.dart';
import '../providers.dart';
import '../settings/client_prefs.dart';
import '../settings/prefs_controller.dart';
import '../queue/queue_controller.dart';
import '../queue/queue_persistence.dart' show mediaTypeOfPid;
import '../queue/queue_state.dart';
import '../radio/radio_controller.dart';
import '../shell/lifecycle_banners.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import '../sync/sync_providers.dart';
import 'listen_outbox.dart';
import 'playback_session.dart';
import 'session_registry.dart';
import 'timeline_feeder.dart';
import 'sleep_timer.dart';
import 'stream_quality.dart';

/// How close to the end of the playing item the next one is prepared.
///
/// Long enough for the platform to have the next source ready before the
/// crossing, short enough that the stream URL the preload mints (a
/// fifteen minute media token, server side) cannot expire while the
/// current item plays out. Arming at the start of a long track would do
/// exactly that.
const Duration kPreloadLead = Duration(seconds: 30);

/// How a session lets go of the engine.
enum _Farewell {
  /// The ordinary case: checkpoint where it stands, stop the media.
  stop,

  /// The engine walked out of this item into the one prepared behind it:
  /// finalize at the item's own end and leave the stream running.
  boundary,

  /// Something else is taking the engine and will drive it directly
  /// (live radio): checkpoint where it stands, leave the media alone.
  handOver,
}

/// What the app is playing: the queue entry, the item behind it, and the
/// live session driving it.
class NowPlaying {
  const NowPlaying({
    this.entry,
    this.item,
    this.session,
    this.error,
    this.loading = false,
  });

  static const NowPlaying nothing = NowPlaying();

  /// The queue entry being played, or null when the queue is empty.
  final QueueEntry? entry;

  /// The item that entry names, once it has been resolved.
  final ItemSummary? item;

  /// The session driving playback, once it has started.
  final PlaybackSession? session;

  /// Why the entry could not start, when it could not.
  final Object? error;

  /// A start is under way: the entry is what plays next, not a stopped
  /// one, and [session] lands when it loads.
  final bool loading;

  /// What the entry is, before its item resolves too: a pid says.
  MediaType? get kind =>
      item?.mediaType ??
      switch (entry) {
        final entry? => mediaTypeOfPid(entry.pid),
        null => null,
      };
}

/// Owns playback. One [PlaybackSession] at a time, following the queue's
/// current entry: whatever puts an entry there (a tap, a skip, a
/// restored queue, an advance at the end of an item) is what starts
/// playing, and every surface that shows what is playing reads this.
///
/// Session lifecycle deliberately does not hang off a widget. A player
/// screen that owned its session could not survive being popped, which
/// is what a persistent deck bar needs; here the screens are viewers and
/// the session outlives all of them.
class NowPlayingController extends Notifier<NowPlaying> {
  // Read once and held: these are fixed for the container's life, and
  // this controller lets go of a session from its own disposal, where
  // reading a provider is not allowed.
  late final AudioEnginePort _engine;
  late final ConnectEndpointController _connect;
  late final CurrentSessionRegistry _registry;

  PlaybackSession? _session;
  String? _sessionEntryId;

  /// The start in flight, so a caller that has to answer for one can
  /// wait on it.
  Future<void>? _inFlight;

  StreamSubscription<void>? _boundarySub;
  StreamSubscription<void>? _lostSub;
  StreamSubscription<String>? _refusedSub;

  /// Keeps the queue rendered as one stream where a browser needs that
  /// to cross a boundary at all. Inert everywhere else: the flag is off
  /// and the engine plays no timelines.
  late final TimelineFeeder _feeder;

  /// The gapless rendering loaded right now, for a client that has to
  /// release it from outside this controller. Read off the notifier
  /// rather than published on [NowPlaying]: a rendering swaps at seams
  /// the listener is not told about, and every surface reading the
  /// state would rebuild for a fact none of them show.
  String? get loadedTimelinePid => _feeder.loadedPid;

  /// Every gapless rendering this session is holding, for the exit
  /// path: a queue edit mints a replacement beside the one playing, and
  /// the server counts the listener as being on both.
  List<String> get heldTimelinePids => _feeder.heldPids;
  StreamSubscription<SessionEnd>? _completedSub;
  StreamSubscription<Object>? _failedSub;
  StreamSubscription<Object>? _moveFailedSub;
  StreamSubscription<void>? _loadedSub;
  StreamSubscription<Duration>? _positionFeed;
  StreamSubscription<void>? _stopReachedSub;
  ProviderSubscription<int?>? _chapterEnd;

  /// Item summaries the callers already had in hand, so a queue built
  /// from a list on screen does not re-fetch what it just showed. Also
  /// the only way an episode keeps its show: `GET /items/{pid}` answers
  /// a plain item detail, which carries no show pid, and the per-show
  /// playback settings hang off that.
  final Map<String, ItemSummary> _known = {};

  /// How many unplayable items a single run may skip past before
  /// playback stops and says so.
  ///
  /// A queue of broken files would otherwise walk itself to the end
  /// with a toast per item, which is neither playback nor a report. The
  /// count resets on any item that does load, so a bad file in the
  /// middle of a good album costs one skip and nothing else.
  static const int _maxConsecutiveSkips = 3;

  /// Unplayable items skipped since the last item that loaded. Also
  /// what turns a stack of per-track messages into one line: the second
  /// and later skips in a run replace the first message rather than
  /// piling on top of it.
  int _skipRun = 0;

  /// The entry standing on a file that will not play, for want of
  /// anything to skip to, and whether its start meant to play: it moves on
  /// as soon as the queue has another entry (a mix the continuation
  /// appends), landing the way the start would have.
  ({String entryId, bool play})? _unplayable;

  /// The entry handed to the engine to play next, with the play-info it
  /// was minted from; null when nothing is prepared.
  ({QueueEntry entry, PlayInfo info})? _preload;

  /// Set between a crossing and the queue catching up with it, so the
  /// entry change that follows adopts the playing stream instead of
  /// loading over it.
  ({QueueEntry entry, PlayInfo info})? _adopting;

  /// The token of the start that is still running, when one is. A start
  /// occupies the state with an entry and no session for as long as it
  /// takes to resolve and load, and that window is indistinguishable
  /// from the one an engine hand-over leaves behind unless it is
  /// recorded.
  int? _starting;

  bool _arming = false;

  /// Set when the queue moves while an arm is in flight, so the arm runs
  /// again against what the queue says now.
  bool _armAgain = false;

  /// The entry the admission policy has already turned down. Its answer
  /// does not change while the entry stays next, and the last thirty
  /// seconds of a track are hundreds of position ticks: without this,
  /// every one of them re-asks the server for a play state and mints a
  /// stream token for an item that will never be prepared.
  String? _refusedNext;
  int _startToken = 0;
  int? _pendingPositionMs;
  bool _pendingPaused = false;

  /// Whether the start in flight lands playing, while one is: a press
  /// made from outside meanwhile (a lock screen, the sleep countdown, a
  /// routed command) changes it. Null with no start in flight.
  bool? _startPlays;

  /// The start in flight has installed its session, which folds a press
  /// into its own load from then on.
  bool _startInstalled = false;

  /// A seek made from outside before the start in flight installed its
  /// session, and who is waiting to hear whether it landed: the target is
  /// the incoming item's, and the session still live is the one it
  /// replaces.
  Duration? _startSeek;
  Completer<bool>? _startSeekLanded;

  /// Armed by [restore] across the one synchronous call that can consume
  /// it, so the start the queue's own notification lands on knows it is
  /// putting a listen back rather than beginning one. Every other caller
  /// says so with [_start]'s parameter; this one cannot, because the
  /// start it means happens inside `queue.restore`.
  bool _pendingUseSaved = false;

  /// Where the entry being played was asked to start, so a retry asks
  /// for the same thing rather than falling back to the checkpoint.
  int? _entryPositionMs;

  /// The failed start standing on the pane was meant to play and failed
  /// for want of the server, so the server coming back starts it.
  bool _resumeOnReconnect = false;

  /// When a failure armed [_resumeOnReconnect] while the link still read
  /// up, as it does for a moment after a stream breaks. The arm holds only
  /// if the link goes down within [_outageGrace] of it; otherwise it was
  /// no outage, and the pane waits for a press. Null once the outage is
  /// seen, or when the link already read down.
  DateTime? _armedOnline;

  static const _outageGrace = Duration(seconds: 30);

  @override
  NowPlaying build() {
    _engine = ref.read(audioEngineProvider);
    _connect = ref.read(connectControllerProvider);
    _registry = ref.read(currentSessionRegistryProvider);
    _boundarySub = _engine.itemBoundary.listen((_) => _onBoundary());
    _feeder = TimelineFeeder(
      repository: ref.read(repositoryProvider),
      engine: _engine,
      enabled: () => ref.read(webGaplessProvider),
      crossfadeSeconds: () =>
          ref.read(prefsControllerProvider).value?.crossfadeSeconds,
      maxBitrateKbps: () => ref.read(streamMaxBitrateKbpsProvider),
      resolve: (pid) async {
        try {
          return await _resolve(pid);
        } on Object {
          return null;
        }
      },
      onStatus: (reason) {
        if (ref.mounted) {
          ref.read(webGaplessStatusProvider.notifier).set(reason);
        }
      },
      onRefusal: (code, {required midStream}) {
        if (!ref.mounted || code != 'transcode-limited') return;
        ref
            .read(shellMessengerProvider.notifier)
            .showLocalized(
              (l10n) =>
                  midStream ? l10n.playerGaplessPaused : l10n.playerGaplessBusy,
              channel: ShellChannel.gapless,
            );
      },
    );
    final engine = _engine;
    if (engine is TimelineAudioEngine) {
      // A timeline that stopped being servable is the one thing that
      // reloads mid-track; a refusal met on a fetch is not, since the
      // ordinary path sits under the same server limit.
      _lostSub = engine.timelineLost.listen(_onTimelineLost);
      _refusedSub = engine.timelineRefused.listen(_feeder.onRefused);
    }
    ref.listen(queueControllerProvider, _onQueueChanged);
    // The server coming back is when a start that failed for want of it
    // is worth trying again, and when held listens can go. On the
    // container: nothing need be watching playback when it happens.
    final link = ref.container.listen<bool?>(liveConnectionProvider, (
      previous,
      next,
    ) {
      if (next == false) _outageBegan();
      if (previous == false && next == true) _onServerBack();
    });
    ref.onDispose(link.close);
    // Radio drives the engine itself, so the item playing has to let go
    // of it rather than keep counting the station's stream as its own.
    // Gated on the station transition, not on every publish: the ICY
    // poll mints a fresh state per song change carrying the same
    // station, and each of those would otherwise reach the hand-over
    // and bump the start generation - which the Connect gateway reads
    // to decide whether a routed command owns a failure, so a title
    // change mid-verb would blame a stale error on an innocent command.
    ref.listen(radioPlaybackProvider, (previous, next) {
      if (next.station != null && previous?.station != next.station) {
        _handOverToRadio();
      }
    });
    final standing = ref.read(queueControllerProvider).currentEntry;
    if (standing != null) {
      // A queue built before playback was (a restore accepted through a
      // container that had never read this): start what it points at
      // rather than waiting for its next edit. Deferred because a
      // notifier cannot publish state from inside its own build, and
      // guarded on the token rather than on the session, which is not
      // set until a start is well underway.
      Future<void>.microtask(() {
        if (ref.mounted && _startToken == 0) {
          // A queue that was already standing when playback was built is
          // one that was put back, so it comes back where it stood.
          _inFlight = _start(standing, useSavedPosition: true);
        }
      });
    }
    ref.onDispose(() {
      unawaited(_boundarySub?.cancel());
      unawaited(_lostSub?.cancel());
      unawaited(_refusedSub?.cancel());
      _feeder.dispose();
      unawaited(_release(_session, _Farewell.stop));
      // Not through _setSession: the container is going away, and there
      // is nothing left for Connect to report to.
      _session = null;
      opening.dispose();
    });
    return NowPlaying.nothing;
  }

  /// The session driving the engine, from the moment it is installed
  /// rather than from the moment it settles.
  ///
  /// [NowPlaying.session] is the one to render: it appears once the item
  /// is loaded and playing. This one is what owns the engine, which is
  /// what Connect mirrors and what a command routed here while an item
  /// is still loading belongs to.
  PlaybackSession? get liveSession => _session;

  /// A load of the app's own is opening the item and means to play it:
  /// a start in flight, or the live session reopening its stream
  /// ([PlaybackSession.reopening]). The engine reads stopped through
  /// either, so a surface outside the app (the OS media session, a
  /// Connect report, the Discord presence) reads this beside it.
  final ValueNotifier<bool> opening = ValueNotifier(false);

  /// Whether playback means to be running: the engine, or a load of the
  /// app's own that lands playing ([opening]). What every transport draws,
  /// a start in flight included, and what [togglePlayback] reverses.
  bool get meansToPlay => _engine.playing || opening.value;

  /// [meansToPlay] as it changes; one stream per controller, so a widget
  /// that reads it on every build keeps its subscription.
  late final Stream<bool> meansToPlayStream = Stream<bool>.multi((out) {
    void emit() => out.add(meansToPlay);
    final playing = _engine.playingStream.listen((_) => emit());
    opening.addListener(emit);
    // Not awaited, for the reason the session's shutdown gives.
    out.onCancel = () {
      unawaited(playing.cancel());
      opening.removeListener(emit);
    };
  }, isBroadcast: true).distinct();

  void _republishOpening() {
    // A start still unwinding as the container goes has nobody to tell.
    if (!ref.mounted) return;
    opening.value = _startPlays ?? _session?.reopening.value ?? false;
  }

  /// The summary behind [pid], when this layer already has one.
  ///
  /// Every queue built from a list on screen seeds these, and every
  /// entry that plays resolves one, so a queue surface can name most of
  /// what it shows without asking the server again. Null means nobody
  /// has needed it yet, not that it does not exist.
  ItemSummary? summaryFor(String pid) => _known[pid];

  /// Keeps a summary a caller fetched, so its entry starts named. Not an
  /// episode's: the show its settings hang off comes from the episode read.
  void noteSummary(ItemSummary item) {
    if (item.mediaType == MediaType.podcast) return;
    _known.putIfAbsent(item.pid, () => item);
  }

  /// Resolves when the start in flight has finished, or immediately when
  /// none is.
  ///
  /// A failed start is recorded on the state rather than thrown (the
  /// listener gets an error pane with a retry), so a caller that has to
  /// answer for one reads [NowPlaying.error] after awaiting this.
  Future<void> get settled => _inFlight ?? Future<void>.value();

  /// Counts the starts this controller has begun.
  ///
  /// A caller that has to answer for one reads this before and after:
  /// unchanged means nothing started (a skip at the front replays what
  /// is loaded), so an error left on the state belongs to something
  /// else. Comparing the errors themselves cannot tell those apart,
  /// because a repeated failure is often the very same object: an API
  /// exception is const-constructible, and a client that caches one
  /// hands back the same instance every time.
  int get startGeneration => _startToken;

  /// The one "play this" verb: builds the queue this gesture defines and
  /// starts the entry it lands on.
  ///
  /// [items] is the list the gesture came from, in its own order, and
  /// [startIndex] the row that was chosen. [positionMs] overrides the
  /// saved resume position of that first entry (a book resume, a chapter
  /// start). [shuffle] is the "Shuffle" entry point, which draws from
  /// anywhere in [items].
  void play(
    List<ItemSummary> items, {
    required QueueSource source,
    int startIndex = 0,
    bool shuffle = false,
    int? positionMs,
  }) {
    if (items.isEmpty) return;
    for (final item in items) {
      _known[item.pid] = item;
    }
    unawaited(
      playPids(
        [for (final item in items) item.pid],
        source: source,
        startIndex: startIndex,
        shuffle: shuffle,
        positionMs: positionMs,
      ),
    );
  }

  /// Adds [items] to the end of the queue without disturbing what is
  /// playing.
  ///
  /// Records the summaries first, the same reason [play] does: an entry
  /// added by hand is drawn from what the caller knew about it long
  /// before its own start resolves one, and a queue row reading "Loading"
  /// for something the screen was showing a title for is the seam
  /// showing.
  ///
  /// An empty queue takes them as its whole contents, which is what the
  /// queue layer already does with an insert into nothing, and playback
  /// follows the queue's current entry, so adding to nothing starts it.
  /// That is the design rather than a surprise: there is one queue and
  /// playback is a view of it.
  void enqueue(List<ItemSummary> items) {
    if (items.isEmpty) return;
    for (final item in items) {
      _known[item.pid] = item;
    }
    ref.read(queueControllerProvider.notifier).addToEnd([
      for (final item in items) item.pid,
    ]);
  }

  /// The same verb, landing at a chosen slot: what a row dropped onto
  /// the queue panel does. The summaries are seeded the same way, so
  /// the rows have titles before anything plays them.
  void enqueueAt(List<ItemSummary> items, int at) {
    if (items.isEmpty) return;
    for (final item in items) {
      _known[item.pid] = item;
    }
    ref.read(queueControllerProvider.notifier).insertAt([
      for (final item in items) item.pid,
    ], at);
  }

  /// The same verb for a queue named by pid alone, which is what
  /// arrives from outside the widget tree: a queue handed to this
  /// endpoint by another device, or a browse leaf tapped on a head
  /// unit. Summaries resolve as each entry starts.
  ///
  /// [autoplay] false loads the entry and stops there, for a queue put
  /// back at its checkpoint. Resolves once the entry it lands on has
  /// started or failed, so a caller that answers for the load can.
  ///
  /// This announces nothing. Replacing the queue is what every play verb
  /// in the app does, and the audio changing says so louder than a toast
  /// could; the displaced queue is still kept, and session history is
  /// where it is offered back.
  Future<void> playPids(
    List<String> pids, {
    required QueueSource source,
    int startIndex = 0,
    bool shuffle = false,
    int? positionMs,
    bool autoplay = true,
  }) {
    if (pids.isEmpty) return Future<void>.value();
    // A deliberate play is a fresh start, so a run of skipped files
    // left over from the last queue does not spend this one's budget:
    // three bad rips yesterday must not make the first bad file today
    // the one that stops everything.
    _skipRun = 0;
    _pendingPositionMs = positionMs;
    _pendingPaused = !autoplay;
    ref
        .read(queueControllerProvider.notifier)
        .playNow(
          pids,
          source: source,
          startIndex: startIndex,
          shuffle: shuffle,
          // Where the displaced queue stood, which the queue layer has
          // no way to know and this one does: it is what an Undo of the
          // replacement resumes at.
          replacedPositionMs: _session?.displayPosition.inMilliseconds ?? 0,
        );
    // The queue notifies its listeners as it is assigned, so the start
    // this landed on is already the one in flight.
    return settled;
  }

  /// Plays or pauses whatever this device is playing: a station stops
  /// and starts, a live session toggles, and an entry left standing by a
  /// failed start is taken back by starting it again.
  ///
  /// Here rather than beside the command that runs it, because the
  /// surfaces that need it are no longer all in the widget tree: the
  /// keyboard and the deck bar hold a `WidgetRef`, the tray menu holds a
  /// container's `Ref`, and neither is the other. The verb belongs to
  /// whatever owns playback, which is this.
  void togglePlayback() {
    if (_radioOwnsEngine) {
      unawaited(ref.read(radioPlaybackProvider.notifier).toggle());
      return;
    }
    final session = state.session;
    if (session != null) {
      unawaited(session.toggle());
      return;
    }
    // A start in flight: the press reverses what the transport shows of
    // it, which is whether it lands playing.
    if (_startPlays != null) {
      unawaited(meansToPlay ? transportPause() : transportPlay());
      return;
    }
    resume();
  }

  /// Plays, for a play raised anywhere but a session's own controls (a
  /// lock screen, a headset, a head unit, a routed command): a start in
  /// flight lands playing, a live session plays, and an entry a failed
  /// start left standing starts again. False when there is nothing to
  /// play at all.
  Future<bool> transportPlay() async {
    final session = _session;
    if (_startPlays != null) {
      _startPlays = true;
      _republishOpening();
      // Installed, the start's own session folds the press into its load.
      if (_startInstalled && session != null) await session.play();
      return true;
    }
    if (session != null) {
      await session.play();
      return true;
    }
    if (ref.read(queueControllerProvider).isEmpty) return false;
    resume();
    return true;
  }

  /// Pauses, for a pause raised anywhere but a session's own controls (the
  /// sleep countdown, a lock screen, a routed command): a start in flight
  /// lands paused, a live session pauses, folding into a load under way,
  /// and a failed start that the server's return would have started waits
  /// for a press instead.
  Future<void> transportPause() async {
    _holdForPress();
    final session = _session;
    if (session != null) {
      await session.pause();
    } else {
      await _engine.pause();
    }
  }

  /// Seeks, for a seek raised outside the app (a lock screen, a routed
  /// command), on the timeline the screens show. A seek before the start
  /// in flight has a session is held for it: the session still live is the
  /// item being replaced, and moving it would write the target as that
  /// item's place. Answers whether the seek landed.
  Future<bool> transportSeek(Duration position) async {
    if (_startPlays != null && !_startInstalled) {
      _startSeek = position;
      return (_startSeekLanded ??= Completer<bool>()).future;
    }
    final session = _session;
    if (session != null) return session.seek(position);
    await _engine.seek(position);
    return true;
  }

  /// Hands a seek held for the start in flight to its session, or answers
  /// that it did not land when no session will take it.
  void _settleStartSeek(PlaybackSession? session) {
    final held = _startSeek;
    final landed = _startSeekLanded;
    _startSeek = null;
    _startSeekLanded = null;
    if (landed == null) return;
    if (held == null || session == null) {
      landed.complete(false);
      return;
    }
    unawaited(session.seek(held).then(landed.complete));
  }

  /// Stops, for a stop raised outside the app: as [transportPause], with
  /// the live session letting its media go.
  Future<void> transportStop() async {
    _holdForPress();
    final session = _session;
    if (session != null) {
      await session.stop();
    } else {
      await _engine.stop();
    }
  }

  /// A start in flight superseded by something that is no start of an
  /// entry (the queue emptied, radio, a crossing, the app going): it lands
  /// nowhere, so from here nothing reads as opening.
  void _dropStartIntent() {
    _startPlays = null;
    _startInstalled = false;
    _settleStartSeek(null);
    _republishOpening();
  }

  /// A press that silenced playback: nothing starts again until another
  /// press says so, neither a start in flight nor the server coming back.
  void _holdForPress() {
    _resumeOnReconnect = false;
    _armedOnline = null;
    if (_startPlays != null) {
      _startPlays = false;
      _republishOpening();
    }
  }

  /// Steps to the next entry at someone's request. False when the queue
  /// has nowhere to go, so the caller can say so rather than pretend.
  ///
  /// A skip while live radio has the engine does nothing. Radio never
  /// queues, so there is nothing to step; stepping would take the
  /// engine back from the station the listener chose, which no skip
  /// button means.
  Future<bool> next() async {
    if (_radioOwnsEngine) return false;
    switch (ref.read(queueControllerProvider.notifier).skipNext()) {
      case QueueAdvance.advanced:
        await settled;
        return true;
      // A lone entry wrapping onto itself under repeat all: nothing to
      // load, so this is where it plays again.
      case QueueAdvance.repeatedCurrent:
        return _replayCurrent();
      case QueueAdvance.ended:
      case QueueAdvance.empty:
        return false;
    }
  }

  /// Steps back an entry, or starts the current one over when already
  /// at the front, which is what a second press of previous means
  /// everywhere else. False when nothing is queued, or when live radio
  /// has the engine (see [next]).
  Future<bool> previous() async {
    if (_radioOwnsEngine) return false;
    switch (ref.read(queueControllerProvider.notifier).retreat()) {
      case QueueRetreat.moved:
        await settled;
        return true;
      case QueueRetreat.atStart:
        return _replayCurrent();
      case QueueRetreat.empty:
        return false;
    }
  }

  Future<bool> _replayCurrent() async {
    final session = _session;
    if (session == null) return false;
    // A skip is not a play command: pressing previous at the front of a
    // paused queue puts it back at the start, it does not start it.
    await session.replay(play: session.meansToPlay);
    return true;
  }

  /// Starts the current entry again when nothing is driving it.
  ///
  /// Two states reach this, and the queue never moved in either, so
  /// nothing else would ever try. A start that failed leaves the entry
  /// sitting there: a stream that expired under a sleeping phone, or a
  /// server that was down for a moment, is one tap from playing rather
  /// than a queue that has to be rebuilt. And an item that let the
  /// engine go to live radio keeps its place on every surface, so the
  /// transport that is still showing it has to be able to take it back.
  ///
  /// Does nothing while a session is live: that session's own toggle is
  /// the verb for playing and pausing. Nor while one is still starting,
  /// which looks the same from the outside - the state carries an entry
  /// and no session for the whole resolve-and-load window - but is
  /// already on its way, and starting it again would supersede a load
  /// in flight, re-mint its stream token and its listen session, and
  /// drop the position it was asked to start at.
  void resume() {
    if (state.session != null || _starting != null) return;
    final entry = ref.read(queueControllerProvider).currentEntry;
    if (entry == null) return;
    // A start that failed asks again for the position it was asked for.
    // One that let go of the engine checkpointed where it stood on its
    // way out, and that checkpoint is the truthful place to come back
    // to; the original request is where it began, which is behind.
    _pendingPositionMs = state.error != null ? _entryPositionMs : null;
    // Both states this answers are resumes: a start that failed asks
    // again for where it was going, and an item that let go of the
    // engine to radio comes back to the checkpoint it wrote on its way
    // out. Neither is a fresh play.
    _inFlight = _start(entry, useSavedPosition: true);
  }

  /// Puts a queue back in play at its checkpoint, paused unless
  /// [autoplay] says to play it: a queue restored at launch waits, and
  /// the launch offer's Resume is a press of play.
  /// [offerUndo] keeps what this displaced, for the surfaces that offer
  /// to put it back. Without it the offer is a button that cannot work.
  void restore(
    QueueState queue, {
    bool offerUndo = false,
    bool autoplay = false,
  }) {
    _pendingPositionMs = null;
    _pendingPaused = !autoplay;
    // The one music case that legitimately comes back mid-track: this is
    // the listen the app was closed in the middle of. Armed only across
    // the call below, which notifies as it assigns and so may start from
    // inside it; disarmed the moment it returns, so no unrelated start
    // can pick it up.
    _pendingUseSaved = true;
    final began = _startToken;
    try {
      ref
          .read(queueControllerProvider.notifier)
          .restore(
            queue,
            displacedPositionMs: offerUndo
                ? _session?.displayPosition.inMilliseconds ?? 0
                : null,
          );
    } finally {
      _pendingUseSaved = false;
    }
    // The queue notified its listeners as it was assigned, so when the
    // restored current entry's id differs from the playing one's, the
    // entry change above already started it. When it does not - restored
    // sessions mint entry ids from zero and so does a live queue's first
    // playNow, so a collision is ordinary - nothing started: the engine
    // would keep playing the old audio under the restored queue's UI
    // forever, and the pending-paused flag would sit armed until some
    // later advance consumed it and stood silent. The start is forced,
    // not playback: it loads the restored source over the old one and
    // honors the paused contract at the checkpoint.
    if (_startToken != began) return;
    final entry = ref.read(queueControllerProvider).currentEntry;
    if (entry == null) return;
    _inFlight = _start(entry, useSavedPosition: true);
  }

  /// Takes back the replacement a tap made: the queue that was
  /// displaced, at the position it stood at, playing.
  ///
  /// The queue layer keeps what was displaced and answers where it was;
  /// resuming it there is this layer's half. Set before the queue moves,
  /// because the queue notifies its listeners as it is assigned and the
  /// start this lands on is already reading these.
  ///
  /// Playing rather than paused, unlike a restore: an undo answers an
  /// accident that happened mid-listen, and silence would be the second
  /// surprise rather than the end of the first.
  ///
  /// [only] is the replacement an offer was made for; once another has
  /// replaced the queue since, that offer takes nothing back.
  void undoReplace([QueueUndo? only]) {
    // Read before the queue moves, not from what the undo returns: the
    // queue notifies its listeners as it is assigned, so the start this
    // lands on has already read these by the time the call comes back.
    final pending = ref.read(queueControllerProvider).undo;
    if (pending == null || only != null && !identical(pending, only)) return;
    _pendingPositionMs = pending.positionMs;
    _pendingPaused = false;
    ref.read(queueControllerProvider.notifier).undoReplace();
    // The displaced queue was standing on the entry that is playing
    // (a replacement that only changed what follows), so no start is
    // coming to consume the position: seek to it here instead.
    if (ref.read(queueControllerProvider).currentEntry?.queueId ==
        _sessionEntryId) {
      _pendingPositionMs = null;
      _pendingPaused = false;
      unawaited(_session?.seek(Duration(milliseconds: pending.positionMs)));
    }
  }

  /// Takes the entry playing out of the queue, for an item that stopped
  /// existing under the listener (a kind change folded it into a book).
  /// What lands in its place waits, paused, rather than starting: the
  /// listener was just told playback stopped. The last entry going
  /// empties the queue.
  ///
  /// Armed across the one synchronous call that can consume it, as
  /// [restore] arms its flags: the queue notifies as it is assigned.
  void dropCurrent() {
    final queue = ref.read(queueControllerProvider);
    if (queue.isEmpty) return;
    _pendingPositionMs = null;
    _pendingPaused = true;
    try {
      ref.read(queueControllerProvider.notifier).removeAt(queue.currentIndex);
    } finally {
      _pendingPaused = false;
    }
  }

  void _onQueueChanged(QueueState? previous, QueueState next) {
    // Summaries accumulate as entries come and go, and a session can run
    // for days; the queue's own cap is the bound worth holding them to.
    // Guarded rather than swept every time, because a drag emits a queue
    // state per frame.
    if (_known.length > kQueueCap) _prune(next);
    final entry = next.currentEntry;
    if (entry == null) {
      _stop();
      return;
    }
    if (entry.queueId != _sessionEntryId) {
      final adopting = _adopting;
      _adopting = null;
      if (adopting != null && adopting.entry.queueId == entry.queueId) {
        _inFlight = _adopt(entry, adopting.info);
      } else {
        _inFlight = _start(entry);
      }
      return;
    }
    final unplayable = _unplayable;
    if (unplayable != null &&
        unplayable.entryId == entry.queueId &&
        _canMoveOn(next)) {
      _unplayable = null;
      _skipPast(entry, state.item, play: unplayable.play);
      return;
    }
    // The entry playing did not move, but what follows it may have
    // (a reorder, a removal, a repeat toggle).
    unawaited(_syncPreload());
  }

  /// Starts [entry].
  ///
  /// [useSavedPosition] is where the "music never resumes mid-track"
  /// policy lives, and it lives here rather than in [PlaybackSession]:
  /// the session's job is to honour the position it is handed, and six
  /// other callers rely on it reading the checkpoint when it is handed
  /// none. A parameter rather than a pending flag, deliberately -
  /// `build` defers its first start to a microtask, and a flag set
  /// before that microtask would be consumed by whatever started in
  /// between and resume the wrong item mid-track.
  ///
  /// Spoken word is untouched whatever the flag says: a book and a
  /// podcast come back to their checkpoints, which is what a checkpoint
  /// is for. Only music starts at the head.
  ///
  /// Precedence: `_pendingPositionMs` still wins over both.
  /// `undoReplace`, `playPids(positionMs:)` and resume-after-error all
  /// set it and all mean it.
  Future<void> _start(
    QueueEntry entry, {
    bool useSavedPosition = false,
    bool ordinary = false,
  }) async {
    final token = ++_startToken;
    _starting = token;
    _resumeOnReconnect = false;
    _armedOnline = null;
    _unplayable = null;
    _sessionEntryId = entry.queueId;
    var positionMs = _pendingPositionMs;
    final useSaved = useSavedPosition || _pendingUseSaved;
    // A seek held for a start this one replaces did not land there.
    _settleStartSeek(null);
    _startPlays = !_pendingPaused;
    _startInstalled = false;
    _republishOpening();
    _entryPositionMs = positionMs;
    _pendingPositionMs = null;
    _pendingPaused = false;
    state = NowPlaying(entry: entry, item: _known[entry.pid], loading: true);
    TimelineSlot? slot;
    try {
      // Live radio bypasses sessions; loading an item takes the engine
      // back, so the radio surface must stop claiming it - and stop its
      // sound. Awaited, and inside the try, because the interrupt is the
      // start's first act on the engine: a station audibly playing
      // through the round trips below is the seam showing, and a start
      // that dies before its session exists has no other teardown that
      // would ever silence it. The ordering is total from here: engine
      // idle, then resolve, then session start, then load.
      await ref.read(radioPlaybackProvider.notifier).interrupt();
      if (_superseded(token)) return;
      // A load starts a fresh window, so whatever was prepared behind
      // the outgoing item is gone at the engine and gone here. Above the
      // resolve, so a resolve that throws cannot leave a stale record
      // suppressing the next legitimate arm.
      _preload = null;
      final item = await _resolve(entry.pid);
      if (_superseded(token)) return;
      // Named as soon as it resolves rather than once it loads.
      if (state.item == null) {
        state = NowPlaying(entry: entry, item: item, loading: true);
      }
      // Music starts at the head. Skipping away from a track and back is
      // a fresh play rather than a resume, and so is tapping a track in
      // a listing you had heard half of; the exceptions all say so
      // through [useSavedPosition]. Told to the session as an explicit
      // zero rather than by leaving it null, which is what asks the
      // session to go and read the checkpoint. Spoken word passes null
      // and keeps resuming.
      if (positionMs == null &&
          !useSaved &&
          item.mediaType == MediaType.music) {
        positionMs = 0;
      }
      // The head, not "unspecified": a retry after a failed start would
      // otherwise read the checkpoint and resume music mid-track.
      _entryPositionMs = positionMs;
      // Minted here rather than inside the session: the queue is what
      // gets rendered, and the queue is this layer's. Null everywhere
      // the ordinary per-item path applies, which is everywhere but a
      // browser playing music with the switch on.
      slot = ordinary
          ? null
          : await _feeder.slotFor(
              entry,
              item,
              ref.read(queueControllerProvider),
            );
      if (_superseded(token)) return;
      final session = _build(
        item,
        initialPositionMs: positionMs,
        timeline: slot,
      );
      // The engine's owner changes as start() begins, so the outgoing
      // session flushes its final checkpoint and listen report without
      // stopping media it no longer owns. A press from outside before
      // this point changed how the start lands; one after it reaches the
      // session, which folds it into its own load.
      final starting = session.start(autoplay: _startPlays ?? true);
      _install(session, entry);
      _startInstalled = true;
      _settleStartSeek(session);
      await starting;
      if (_superseded(token)) return;
      // The stream this start asked for is loaded and fetching, which
      // is when a rendering the feeder handed off to make room for it
      // is safe to let go of.
      _feeder.started();
      _skipRun = 0;
      state = NowPlaying(entry: entry, item: item, session: session);
      await _syncPreload();
    } on Object catch (error) {
      if (_superseded(token)) return;
      // The pane stays terse; the console carries the real failure so
      // field reports and browser tests can see it.
      debugPrint('playback start failed: $error');
      // Installed before it was known to work, so that the outgoing
      // session could let go while this one loaded: it has to let go
      // too, or Connect keeps reporting an endpoint playing an item that
      // never loaded, and anything reaching for the live session finds
      // one that cannot drive the engine.
      unawaited(_release(_session, _Farewell.stop));
      _setSession(null);
      _settleStartSeek(null);
      if (slot != null) {
        // The rendering is what would not load, a stream every member of
        // the queue shares, not this item: it is let go of and the item
        // starts the ordinary way, where a skip would spend the queue and
        // a retry would be handed the same rendering back.
        _feeder.clear();
        if (error case MediaTrouble(:final refusal?)) {
          _feeder.onLoadRefused(refusal);
        }
        _pendingPositionMs = _entryPositionMs;
        _pendingPaused = !(_startPlays ?? true);
        await (_inFlight = _start(
          entry,
          useSavedPosition: true,
          ordinary: true,
        ));
        return;
      }
      _startFailed(
        entry,
        _known[entry.pid],
        error,
        meantToPlay: _startPlays ?? true,
      );
    } finally {
      // Only if it is still this start's window: a newer one that
      // superseded this has its own to close.
      if (_starting == token) {
        _starting = null;
        _startPlays = null;
        _republishOpening();
      }
    }
  }

  /// Takes over a stream the engine is already playing, after it crossed
  /// out of the previous item and into this one.
  Future<void> _adopt(QueueEntry entry, PlayInfo info) async {
    // The same bail every other start-class entry point has: radio took
    // the engine between the crossing and the queue catching up, so the
    // stream is the station's and there is nothing of this item's to
    // adopt. A session built here would run its checkpoint timer
    // against the radio stream and write this item's pid at the
    // station's position.
    if (_radioOwnsEngine) return;
    final token = ++_startToken;
    _starting = token;
    _dropStartIntent();
    _sessionEntryId = entry.queueId;
    try {
      var item = _known[entry.pid];
      if (item == null) {
        // Normally the summary is in hand, because arming the preload
        // resolved it. Without it there is a fetch between the crossing
        // and the session that owns what is playing, and the outgoing
        // session has already let go: say so rather than leave a
        // finalized session on the state for surfaces to read.
        state = NowPlaying(entry: entry, loading: true);
        item = await _resolve(entry.pid);
        if (_superseded(token)) return;
      }
      _entryPositionMs = null;
      // A replacement timeline minted while the outgoing one played is
      // swapped in here, at the seam that is happening now, before the
      // session that will own the stream exists. Nothing to do in the
      // ordinary case, where the crossing was inside the timeline
      // already loaded.
      final swapped = await _feeder.settleSwap(entry);
      if (_superseded(token)) return;
      if (!swapped) {
        // A replacement always carries a new URL, so the swap tore the
        // outgoing stream down before it failed. There is nothing left
        // to adopt: this is a start.
        await _start(entry);
        return;
      }
      final session = _build(item, timeline: _feeder.slotAt(entry));
      final adopting = session.adopt(info);
      _install(session, entry);
      // Published as soon as the session exists rather than once it
      // settles: the item is already playing and this session speaks
      // for it from here, so a crossing with the summary in hand
      // publishes exactly once, whole, with no frame in between where
      // the transport has nothing to bind to.
      _skipRun = 0;
      state = NowPlaying(entry: entry, item: item, session: session);
      await adopting;
      if (_superseded(token)) return;
      await _syncPreload();
    } on Object catch (error) {
      if (_superseded(token)) return;
      debugPrint('playback rollover failed: $error');
      unawaited(_release(_session, _Farewell.stop));
      _setSession(null);
      // A roll-over is playback already running.
      _startFailed(entry, _known[entry.pid], error, meantToPlay: true);
    } finally {
      if (_starting == token) _starting = null;
    }
  }

  /// Whether a start begun under [token] still speaks for this
  /// controller: a newer one has taken over, or the container it lives in
  /// is gone (a sign-out, a closing app) and touching state or providers
  /// from here would throw.
  bool _superseded(int token) => token != _startToken || !ref.mounted;

  /// Radio has taken the engine. The item playing lets go now, while
  /// the position is still its own: leaving it subscribed would count
  /// the station's stream as time listened to the item, checkpoint the
  /// item's pid at the station's position, and report it finished when
  /// the stream dropped. The queue keeps its entry, so what was playing
  /// is still named; nothing restarts it, because that would load over
  /// the radio the listener just chose.
  ///
  /// The token bump is unconditional, session or none: a start still
  /// resolving has no session installed yet, and guarding the bump on
  /// one let exactly that start wake up unsuperseded and load its item
  /// over the station that had just won the engine. Only the farewell
  /// is session-shaped, so only it stays behind the guard.
  void _handOverToRadio() {
    _startToken++;
    _dropStartIntent();
    // A failed start waiting for the server must not take the engine back
    // from the station when it returns.
    _resumeOnReconnect = false;
    _armedOnline = null;
    _adopting = null;
    _feeder.clear();
    unawaited(_dropPreload());
    final session = _session;
    if (session == null) return;
    unawaited(_release(session, _Farewell.handOver));
    _setSession(null);
    state = NowPlaying(entry: state.entry, item: state.item);
  }

  /// The queue ran out from under playback: let the item go and say so.
  void _stop() {
    _startToken++;
    _dropStartIntent();
    _adopting = null;
    _sessionEntryId = null;
    _feeder.clear();
    unawaited(_dropPreload());
    unawaited(_release(_session, _Farewell.stop));
    _setSession(null);
    state = NowPlaying.nothing;
  }

  /// This client is going away: stop, and wait for the state a stop
  /// finalizes to actually land.
  ///
  /// The one verb here that is worth awaiting. Everywhere else a
  /// release is fired and forgotten, because the app is still running
  /// and the writes it makes will land in their own time; here the
  /// process is about to end, and a checkpoint still in flight when it
  /// does is a listener who comes back to a book at the position it
  /// stood at the last time they closed it properly.
  ///
  /// Deliberately not what backgrounding does. Closing the window is
  /// the gesture that means "stop"; minimizing, switching apps, and
  /// losing focus all keep playing, which is what a music player is
  /// for. A remote session is left alone for the same reason - the
  /// speaker in the other room is not this window.
  Future<void> goingAway() async {
    if (_radioOwnsEngine) {
      await ref.read(radioPlaybackProvider.notifier).interrupt();
      return;
    }
    final session = _session;
    _startToken++;
    _dropStartIntent();
    _adopting = null;
    _sessionEntryId = null;
    _feeder.clear();
    unawaited(_dropPreload());
    if (session == null) return;
    // The one release that is awaited, and awaited through the release
    // itself: a second `handOver` beside it would meet the disposed
    // guard and return on the next microtask having waited for neither
    // the checkpoint nor the listen report, which is the whole of what
    // this call is for. `handOver` rather than `dispose` because it
    // finalizes without touching the engine, and the engine is going
    // with the process anyway.
    final farewell = _release(session, _Farewell.handOver);
    _setSession(null);
    state = NowPlaying(entry: state.entry, item: state.item);
    await farewell;
  }

  PlaybackSession _build(
    ItemSummary item, {
    int? initialPositionMs,
    TimelineSlot? timeline,
  }) => PlaybackSession(
    repository: ref.read(repositoryProvider),
    engine: _engine,
    item: item,
    clientId: listenClientId,
    sync: ref.read(syncEngineProvider),
    downloads: ref.read(downloadManagerProvider),
    initialPositionMs: initialPositionMs,
    // Read at build, so a default changed mid-book does not re-rate
    // what is playing. The two domains keep separate defaults
    // because they are listened to differently: 1.5x is ordinary for
    // a podcast and unusual for a novel.
    defaultSpeed: item.mediaType == MediaType.audiobook
        ? ref.read(bookSpeedProvider)
        : ref.read(podcastSpeedProvider),
    defaultTrimSilence: ref.read(trimSilenceDefaultProvider),
    defaultVoiceBoost: ref.read(voiceBoostDefaultProvider),
    smartRewind: ref.read(smartRewindProvider),
    maxBitrateKbps: ref.read(streamMaxBitrateKbpsProvider),
    timeline: timeline,
    // Only where nothing durable queues a listen that could not be sent.
    listenOutbox: ref.read(syncEngineProvider) == null
        ? ref.read(listenOutboxProvider)
        : null,
  );

  /// Makes [session] the live one: the previous session lets go, Connect
  /// and the session registry are pointed here, and the feeds this layer
  /// runs on hang off it.
  void _install(PlaybackSession session, QueueEntry entry) {
    unawaited(_release(_session, _Farewell.stop));
    _sessionEntryId = entry.queueId;
    _registry.register(session);
    _setSession(session);
    _completedSub = session.sessionCompleted.listen(_onCompleted);
    _failedSub = session.sessionFailed.listen(_onSessionFailed);
    _moveFailedSub = session.moveFailed.listen(_onMoveFailed);
    // A load of the session's own drops whatever the engine had prepared
    // behind the item: forgotten here too, and prepared again when it is
    // time to.
    _loadedSub = session.mediaLoaded.listen((_) {
      _preload = null;
      unawaited(_syncPreload());
    });
    session.reopening.addListener(_republishOpening);
    final sleepTimer = ref.read(sleepTimerProvider.notifier)
      // The chapter boundary belonged to the item that armed it: another
      // item drops it, and the same item starting again (a retry, the
      // resume when the server comes back) keeps it. A countdown is the
      // listener's and stays.
      ..clearEndOfChapter(keepFor: session.item.pid);
    // End-of-chapter sleep is the session's to carry out. On the
    // container, because nothing need be watching the timer: the player
    // that armed it can be closed long before the chapter ends.
    _chapterEnd = ref.container.listen<int?>(
      sleepTimerProvider.select((s) => s.endOfChapterEndMs),
      (_, endMs) => session.stopAt(endMs),
      fireImmediately: true,
    );
    _stopReachedSub = session.stopReached.listen(
      (_) => sleepTimer.chapterReached(),
    );
    // When to prepare the next item is a question about how much of this
    // one is left, so the preload rides the position ticks.
    _positionFeed = session.displayPositionStream.listen(
      (_) => unawaited(_syncPreload()),
    );
  }

  /// Lets go of [session]: the feeds stop, the registry forgets it, and
  /// it finalizes out of band so the last checkpoint and listen report
  /// still ride while the next item loads.
  ///
  /// The caller names the session that replaces it (or none) through
  /// [_setSession], which is the one place Connect hears about it: what
  /// the endpoint mirrors is whichever session owns the engine, and
  /// between these two calls that is nothing.
  ///
  /// Returns the farewell rather than swallowing it. Three of the four
  /// callers ignore it, which is the design; [goingAway] is the one
  /// that has to know the checkpoint and the listen report landed
  /// before the process goes, and a session finalizes once - a second
  /// `handOver` beside this one returns on the disposed guard without
  /// waiting for anything.
  ///
  /// Everything before the farewell runs synchronously, so a caller
  /// that drops the future still has the feeds cancelled and the
  /// registry cleared by the time it returns.
  Future<void> _release(PlaybackSession? session, _Farewell farewell) {
    unawaited(_completedSub?.cancel());
    unawaited(_failedSub?.cancel());
    unawaited(_moveFailedSub?.cancel());
    unawaited(_loadedSub?.cancel());
    unawaited(_positionFeed?.cancel());
    unawaited(_stopReachedSub?.cancel());
    _chapterEnd?.close();
    _completedSub = null;
    _failedSub = null;
    _moveFailedSub = null;
    _loadedSub = null;
    _positionFeed = null;
    _stopReachedSub = null;
    _chapterEnd = null;
    if (session == null) return Future<void>.value();
    session.reopening.removeListener(_republishOpening);
    _registry.unregister(session);
    return switch (farewell) {
      _Farewell.stop => session.dispose(),
      _Farewell.boundary => session.finishAtBoundary(),
      _Farewell.handOver => session.handOver(),
    };
  }

  /// Where a start that did not survive lands: skipped past when the
  /// media itself is the problem and there is somewhere to go, and left
  /// on the error pane otherwise.
  ///
  /// The split is what refused, which is why the engine types it
  /// ([MediaFault]) rather than leaving it to be guessed at from the
  /// wording. A file the platform will not decode is not going to
  /// decode on the next press, and the queue behind it has nothing
  /// wrong with it: one bad rip should cost the track rather than the
  /// listening. Everything else keeps the pane - a server that answered
  /// an error, a stream that could not be fetched, a bug in here - and
  /// the retry there is a real offer, because all three are states that
  /// change.
  ///
  /// [mayAdvance] is false for a book that failed after it was already
  /// playing. A part that will not load is still a bad file, but the
  /// queue entry it belongs to is the whole book: stepping past it
  /// leaves the book six hours in, and reports the listen ended at a
  /// part boundary. That one stops where it is.
  ///
  /// [meantToPlay] is a start, or playback, that was meant to be running:
  /// one that failed for want of the server starts when the server is
  /// back, and a skip past a bad file plays what it lands on. Anything put
  /// back to wait, or paused, waits for a press instead.
  void _startFailed(
    QueueEntry? entry,
    ItemSummary? item,
    Object error, {
    bool mayAdvance = true,
    bool meantToPlay = false,
    bool midPlay = false,
  }) {
    final unplayable =
        error is MediaTrouble && error.fault == MediaFault.source && mayAdvance;
    if (unplayable && _canMoveOn(ref.read(queueControllerProvider))) {
      if (_skipPast(entry, item, play: meantToPlay)) return;
      // The run hit its cap. Stopping is the honest answer - a queue
      // that is all bad files is a library problem, not a skip - and
      // the message says how far it got rather than repeating the last
      // filename.
      final skipped = _skipRun;
      _skipRun = 0;
      ref
          .read(shellMessengerProvider.notifier)
          .showLocalized(
            (l10n) => l10n.playerSkipsGaveUp(skipped),
            // The same channel the skips used: this is the last thing
            // that run has to say, and it belongs in place of the
            // count still standing rather than behind it.
            channel: _skipChannel,
          );
      state = NowPlaying(entry: entry, item: item, error: error);
      return;
    }
    final id = entry?.queueId;
    _unplayable = unplayable && id != null
        ? (entryId: id, play: meantToPlay)
        : null;
    _resumeOnReconnect = meantToPlay && _outOfReach(error);
    _armedOnline =
        _resumeOnReconnect && ref.read(liveConnectionProvider) != false
        ? ref.read(wallClockProvider)()
        : null;
    state = NowPlaying(entry: entry, item: item, error: error);
    _offerRetry(item, midPlay: midPlay);
  }

  /// Whether [queue] has another entry to move on to: under repeat all a
  /// lone entry can advance, but only onto itself.
  static bool _canMoveOn(QueueState queue) =>
      queue.canAdvance && queue.entries.length > 1;

  /// Steps past [item], a file that will not play, and says so; what it
  /// lands on plays only when [play] says the start meant to. False once
  /// the run of skips has reached its cap.
  bool _skipPast(QueueEntry? entry, ItemSummary? item, {required bool play}) {
    if (_skipRun >= _maxConsecutiveSkips) return false;
    _skipRun++;
    _announceSkip(item);
    if (!play) _pendingPaused = true;
    // Not awaited: a failed start calls this from a catch inside the
    // start it is replacing, and the next start has to begin after that
    // one has finished unwinding.
    Future<void>.microtask(next);
    // No error on the state: the queue is moving, and a pane that
    // appeared for a frame between two tracks is the flash this exists
    // to avoid.
    state = NowPlaying(entry: entry, item: item);
    return true;
  }

  /// Says on the shell that [item] could not start, with the pane's retry
  /// beside it: the pane is drawn only by the full player, and a listener
  /// at the deck bar would otherwise see a stopped transport and no why.
  /// Offline, a start that will resume by itself says so (see
  /// [_onServerBack]).
  /// [midPlay] is an item that had been playing, which did not fail to
  /// start and is not said to.
  void _offerRetry(ItemSummary? item, {bool midPlay = false}) {
    final title = item?.title;
    final offline =
        _resumeOnReconnect && ref.read(liveConnectionProvider) == false;
    ref
        .read(shellMessengerProvider.notifier)
        .showLocalized(
          (l10n) => offline
              ? l10n.playerOfflineStart
              : switch ((title, midPlay)) {
                  (null, false) => l10n.playerStartFailed,
                  (null, true) => l10n.playerStopped,
                  (final title?, false) => l10n.playerCouldNotStart(title),
                  (final title?, true) => l10n.playerCouldNotContinue(title),
                },
          actionLabelOf: (l10n) => l10n.commonRetry,
          onAction: resume,
          actionSemanticsId: SemanticsIds.playerStartRetry,
        );
  }

  /// Whether [error] is the server or the way to it being away, which the
  /// connection coming back can cure. Never a file, never a refusal.
  static bool _outOfReach(Object error) => switch (error) {
    WaxDeckApiException(:final unreachable) => unreachable,
    MediaTrouble(:final fault, :final refusal) =>
      fault == MediaFault.transport && refusal == null,
    _ => false,
  };

  /// The link went down. A resume a failure armed while it still read up
  /// stands when that failure was this outage's leading edge, and lapses
  /// when it was older.
  void _outageBegan() {
    final armed = _armedOnline;
    if (armed == null) return;
    _armedOnline = null;
    final since = ref.read(wallClockProvider)().difference(armed);
    if (since > _outageGrace) _resumeOnReconnect = false;
  }

  /// The live connection came back: a start that failed for want of the
  /// server starts, and listens held while it was away are sent.
  void _onServerBack() {
    unawaited(
      ref.read(listenOutboxProvider).flush(ref.read(repositoryProvider)),
    );
    if (_resumeOnReconnect && state.session == null && state.error != null) {
      _resumeOnReconnect = false;
      resume();
    }
  }

  /// Says what was skipped, as one line however many there have been.
  ///
  /// The first names the track, because that is the useful sentence
  /// when a single file in an album is bad. From the second on it is a
  /// count: three toasts naming three files nobody chose is noise, and
  /// the shell replaces the standing message rather than queueing it.
  void _announceSkip(ItemSummary? item) {
    final run = _skipRun;
    final title = item?.title;
    ref
        .read(shellMessengerProvider.notifier)
        .showLocalized(
          (l10n) => run > 1 || title == null
              ? l10n.playerSkippedUnplayableMany(run)
              : l10n.playerSkippedUnplayable(title),
          channel: _skipChannel,
        );
  }

  /// Shared by every message a skip run raises, so the shell supersedes
  /// the standing one instead of stacking a second bar over it. Not a
  /// semantics identifier: none of these has a button, and there is
  /// nothing here for a test to press.
  static const _skipChannel = ShellChannel.skippedUnplayable;

  /// Points [liveSession] at [session] and tells Connect, whose reports
  /// follow whatever owns the engine: a fresh session mirrors from here,
  /// and none at all stops the reports rather than leaving an endpoint
  /// claiming to play something it let go of.
  void _setSession(PlaybackSession? session) {
    _session = session;
    _republishOpening();
    _connect.onPlaybackChanged();
  }

  /// The live session could not do what its item needed mid-flight (a
  /// book part that would not load, a cross-part jump the server
  /// refused, media that stopped decoding): let it go the way a failed
  /// start is let go, so the same error pane and retry stand where the
  /// transport was. The release flushes the checkpoint at the position
  /// the failure left, which is where the retry resumes.
  ///
  /// A book never skips, however the failure classifies: a part is part
  /// of something already underway, and the entry a skip would step
  /// past is the whole book. A track or an episode whose file stopped
  /// decoding is the same bad file a failed start is, and skips the same.
  void _onSessionFailed(SessionFailure failure) {
    final session = _session;
    if (session == null) return;
    debugPrint('playback session failed: ${failure.error}');
    // A retry, by hand or on reconnect, picks up where this stood, not
    // where the entry first started.
    _entryPositionMs = failure.atMs;
    unawaited(_release(session, _Farewell.stop));
    _setSession(null);
    _startFailed(
      state.entry,
      state.item,
      failure.error,
      mayAdvance: session.item.mediaType != MediaType.audiobook,
      meantToPlay: failure.meantToPlay,
      midPlay: true,
    );
  }

  /// The item ended with nothing behind it in the engine: step the
  /// queue, which is what loads whatever comes next.
  void _onCompleted(SessionEnd end) {
    if (_radioOwnsEngine) return;
    final session = _session;
    switch (ref.read(queueControllerProvider.notifier).advance()) {
      // The queue moved; the entry change starts what it landed on.
      case QueueAdvance.advanced:
      case QueueAdvance.empty:
        break;
      // Nothing follows: what just finished stays on the deck bar, unless
      // a play released an end a sleep stop was holding - that press asked
      // for something, and with nothing after the item it is the item.
      case QueueAdvance.ended:
        if (end == SessionEnd.heldEndPlayed && session != null) {
          unawaited(session.replay());
        }
      case QueueAdvance.repeatedCurrent:
        if (session != null) unawaited(session.replay());
    }
  }

  /// A seek the live session could not have, with playback going on as
  /// it was: said, and nothing let go of.
  void _onMoveFailed(Object error) {
    ref
        .read(shellMessengerProvider.notifier)
        .showLocalized(
          (l10n) => l10n.playerMoveFailed(explainError(l10n, error)),
        );
  }

  /// The engine crossed out of the playing item and into the one it had
  /// prepared: the queue moves to that entry and a session for it takes
  /// over a stream that never stopped.
  void _onBoundary() {
    if (_radioOwnsEngine) return;
    final crossed = _preload;
    _preload = null;
    final notifier = ref.read(queueControllerProvider.notifier);
    if (crossed == null) {
      // The preload was dropped (the queue was edited) in the moment
      // between the engine committing to it and the crossing. The item
      // that played still reached its end, so it is finalized there
      // before the queue moves: leaving that to the next start would
      // checkpoint it at the stray item's position, which is zero.
      // Whatever the queue advances to then loads over the stray; if it
      // has nowhere to go, that item plays on and the log is the only
      // record of it.
      debugPrint('playback: crossed into an item the queue had let go');
      // Inside a timeline the stream did not stop, it ran on into the
      // member after this one - which on repeat one is the head of a
      // track the listener did not ask for, playing under the restart
      // that is about to happen.
      if (ref.read(queueControllerProvider).repeat == QueueRepeat.one) {
        _feeder.rewindMember();
      }
      unawaited(_release(_session, _Farewell.boundary));
      _setSession(null);
      _recoverFromStray();
      return;
    }
    // The outgoing item is finalized at its own end, not at the engine's
    // position, which already belongs to the item now playing.
    unawaited(_release(_session, _Farewell.boundary));
    _setSession(null);
    _adopting = crossed;
    final queue = ref.read(queueControllerProvider);
    // By identity, never by index: the queue may have been edited since
    // the preload was armed.
    final index = queue.entries.indexWhere(
      (e) => e.queueId == crossed.entry.queueId,
    );
    if (index < 0) {
      _adopting = null;
      _recoverFromStray();
    } else if (index == queue.currentIndex) {
      // Already current (the queue was edited under the crossing), so
      // no state change is coming to react to.
      _adopting = null;
      _inFlight = _adopt(crossed.entry, crossed.info);
    } else {
      notifier.jumpTo(index);
    }
  }

  /// The engine is playing an item the queue no longer points at, and the
  /// session that was playing has let go. Move the queue on, the way the
  /// end of an item does; when it has nowhere to go, nothing should be
  /// playing at all, so the stray is stopped rather than left running
  /// under a state that names a session which has already finalized.
  void _recoverFromStray() {
    _sessionEntryId = null;
    switch (ref.read(queueControllerProvider.notifier).advance()) {
      // The queue moved: the entry change loads over the stray.
      case QueueAdvance.advanced:
        return;
      // Repeat-one does not move the queue, so nothing else will load
      // over it; this does.
      case QueueAdvance.repeatedCurrent:
        final entry = ref.read(queueControllerProvider).currentEntry;
        if (entry != null) _inFlight = _start(entry);
      case QueueAdvance.ended:
      case QueueAdvance.empty:
        unawaited(_engine.stop());
        state = NowPlaying(entry: state.entry, item: state.item);
    }
  }

  /// Whether live radio has taken the engine. Radio never queues, so
  /// nothing it does to the engine is a queue event.
  bool get _radioOwnsEngine => ref.read(radioPlaybackProvider).station != null;

  /// Keeps what the engine has prepared in step with what the queue says
  /// comes next.
  ///
  /// A request that arrives while an arm is in flight is remembered and
  /// run after it, never dropped: resolving one takes three round trips,
  /// and a queue edited inside that window would otherwise leave the
  /// engine holding an item nobody wants next until the next position
  /// tick, or for good if playback is paused.
  Future<void> _syncPreload() async {
    if (_arming) {
      _armAgain = true;
      return;
    }
    _arming = true;
    try {
      do {
        _armAgain = false;
        try {
          await _reconcilePreload();
        } on Object catch (error) {
          // Preloading is best effort by contract: a failure here costs
          // the gapless crossing and nothing else, since the item loads
          // on advance the way it always did. Swallowed here rather than
          // around the loop, so a queue edit that arrived while this was
          // failing is still run: it is the edit that has no other way
          // of being noticed, since a paused queue emits no ticks.
          debugPrint('preload skipped: $error');
        }
      } while (_armAgain && ref.mounted);
    } finally {
      _arming = false;
      _armAgain = false;
    }
  }

  Future<void> _reconcilePreload() async {
    final next = ref.read(queueControllerProvider).nextEntry;
    final armed = _preload;
    if (armed != null && armed.entry.queueId == next?.queueId) return;
    if (armed != null) {
      // Cleared first, forgotten second: a clear that throws leaves the
      // engine holding the item, and the record has to say so or a
      // crossing into it arrives with nothing to identify it by.
      await _engine.clearPreload();
      _preload = null;
    }
    if (_refusedNext != null && _refusedNext != next?.queueId) {
      _refusedNext = null;
    }
    if (next == null || _refusedNext == next.queueId) return;
    final session = _session;
    // Until media reaches the engine, its position and duration are the
    // previous item's: measuring them would arm against the wrong item's
    // remaining time, and the load that follows drops the preload at the
    // engine while the record here goes on claiming it.
    if (session == null || !session.isLoaded) return;
    if (!_admitsPreload(session.item)) return;
    // A timeline holds the next member in the stream already playing,
    // so there is nothing to fetch and nothing to gate: no lead, since
    // the media is here, and no metered check, since arming spends no
    // bytes. Ahead of the window check because a timeline engine has no
    // window - crossing is the server's arrangement, not a caller's.
    if (_feeder.holds(session)) {
      _preload = await _feeder.armNext(ref.read(queueControllerProvider));
      return;
    }
    // An engine with no window drops whatever this prepares, and
    // preparing it is three round trips and a minted stream token per
    // track. It advances on `completed` instead, which is the same path
    // a queue's last item takes.
    if (!_engine.canPreload) return;
    // Too early to mint a stream URL, or no length to measure against.
    final remaining = session.mediaDuration - session.displayPosition;
    if (remaining <= Duration.zero || remaining > kPreloadLead) return;
    // Asked at the moment of arming rather than held as state, and not
    // recorded as a refusal: a listener who walks indoors mid-track gets
    // the gapless crossing, and one who walks out does not. Refusing by
    // queue id would stick to the entry for as long as it stayed next.
    if (ref.read(preloadOnWifiOnlyProvider) &&
        await ref.read(connectivityProvider).cost() == ConnectionCost.metered) {
      return;
    }
    if (!ref.mounted) return;

    final item = await _resolve(next.pid);
    if (!ref.mounted) return;
    if (!_admitsPreload(item)) {
      _refusedNext = next.queueId;
      return;
    }
    // No play-state read here any more. It refused an item with a saved
    // position, because the port prepares an item at the head of its
    // window - but both guards above have already returned for anything
    // that is not music, and music now always starts at the head. That
    // made the read a round trip per arm whose answer could not matter,
    // and it cost the gapless crossing into every track the listener had
    // once heard part of.
    final info = await ref
        .read(repositoryProvider)
        .getPlayInfo(
          next.pid,
          maxBitrateKbps: ref.read(streamMaxBitrateKbpsProvider),
        );
    if (!ref.mounted) return;
    // Only passthrough streams: a preloaded transcode opens a second
    // server-side session, which double counts against the transcode
    // limiter or is refused outright in the middle of a queue. Asked
    // without HLS, as here, the server marks a cut, capped, or
    // voice-boosted stream unseekable, so these two answers are the
    // whole test.
    if (!info.seekable || info.voiceBoost) {
      _refusedNext = next.queueId;
      return;
    }
    // The queue may have moved while all of that resolved.
    if (ref.read(queueControllerProvider).nextEntry?.queueId != next.queueId) {
      return;
    }
    await _engine.preloadNext(
      info.url,
      mimeType: info.mimeType,
      clipStart: info.spanStartMs == null
          ? null
          : Duration(milliseconds: info.spanStartMs!),
      clipEnd: info.spanEndMs == null
          ? null
          : Duration(milliseconds: info.spanEndMs!),
    );
    // Recorded even if the queue moved while that landed, because this
    // is what the engine holds, not what the queue wants: an edit inside
    // the window re-runs the reconcile, which drops it, and a crossing
    // that beats the reconcile still knows by identity which entry it
    // walked into.
    _preload = (entry: next, info: info);
  }

  /// Gapless is a music affordance, and both sides of a crossing have to
  /// be music for it.
  ///
  /// Spoken word carries per-item playback config the crossing cannot
  /// apply in time: a book or show plays at its own remembered speed, so
  /// an item crossed into would run at the previous one's rate until its
  /// session caught up, and an episode with a skip-intro setting does
  /// not start at its own head at all. Books roll their parts inside one
  /// session besides, which is not a queue boundary.
  bool _admitsPreload(ItemSummary item) => item.mediaType == MediaType.music;

  /// The loaded timeline stopped being servable: its token aged out, or
  /// the server let the render go. Re-minted and reloaded where the
  /// listener stands, keeping the listen session, which is the one
  /// mid-track reload this path allows.
  void _onTimelineLost(bool wasPlaying) {
    if (_radioOwnsEngine) return;
    _inFlight = _recoverTimeline(wasPlaying);
  }

  /// Re-mints where the listener stands, and starts the item the
  /// ordinary way when nothing could be re-minted.
  ///
  /// The fallback is the point: the stream that was playing is gone
  /// whatever happens next, so a mint that a 409, a transport failure
  /// or the server's cap turned down leaves nothing playing, no error
  /// pane, and a queue that never advances - a deck that has simply
  /// stopped, with nothing on screen to say so.
  ///
  /// A timeline lost again before playback proved itself is not minted
  /// once more ([PlaybackSession.mayRecover]): that entry starts on the
  /// ordinary path, so a rendering that keeps failing costs a mint or two
  /// rather than one per loss.
  Future<void> _recoverTimeline(bool wasPlaying) async {
    final queue = ref.read(queueControllerProvider);
    final session = _session;
    final spent = session != null && !session.mayRecover;
    if (spent) _feeder.clear();
    final recovered =
        !spent && await _feeder.onLost(session, queue, resume: wasPlaying);
    if (recovered || _radioOwnsEngine) return;
    final entry = queue.currentEntry;
    if (entry == null) return;
    await _start(entry, useSavedPosition: true, ordinary: spent);
  }

  Future<void> _dropPreload() async {
    if (_preload == null) return;
    _preload = null;
    await _engine.clearPreload();
  }

  Future<ItemSummary> _resolve(String pid) async {
    final known = _known[pid];
    if (known != null) return known;
    final repository = ref.read(repositoryProvider);
    final item = await repository.getItem(pid);
    if (item.mediaType != MediaType.podcast) {
      _known[pid] = item;
      return item;
    }
    // An episode reached by pid alone (a queue handed over by another
    // device, a browse leaf on a head unit, a restored queue the mirror
    // could not name) arrives from `GET /items/{pid}` as a plain item
    // detail, which carries no show pid, and the per-show speed, trim,
    // and skip settings all hang off that. The episode endpoint carries
    // one, so it is worth the second round trip on the rare path that
    // has no summary in hand.
    try {
      final episode = await repository.getEpisode(pid);
      _known[pid] = episode;
      return episode;
    } on WaxDeckApiException {
      // The show's settings are a refinement; the episode still plays.
      _known[pid] = item;
      return item;
    }
  }

  /// Forgets summaries no queue needs any more. The cache is a
  /// convenience for the queue in hand, not a catalog.
  void _prune(QueueState queue) {
    final keep = queue.pids.toSet();
    final playing = _session?.item.pid;
    if (playing != null) keep.add(playing);
    _known.removeWhere((pid, _) => !keep.contains(pid));
  }
}

/// The one playback owner.
final nowPlayingProvider = NotifierProvider<NowPlayingController, NowPlaying>(
  NowPlayingController.new,
);
