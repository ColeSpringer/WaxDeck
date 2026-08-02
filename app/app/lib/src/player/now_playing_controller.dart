import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

import '../connect/connect_controller.dart';
import '../connect/connect_providers.dart';
import '../connectivity/connectivity_port.dart';
import '../providers.dart';
import '../settings/client_prefs.dart';
import '../queue/queue_controller.dart';
import '../queue/queue_state.dart';
import '../radio/radio_controller.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import '../sync/sync_providers.dart';
import 'playback_session.dart';
import 'session_registry.dart';
import 'sleep_timer.dart';

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
  const NowPlaying({this.entry, this.item, this.session, this.error});

  static const NowPlaying nothing = NowPlaying();

  /// The queue entry being played, or null when the queue is empty.
  final QueueEntry? entry;

  /// The item that entry names, once it has been resolved.
  final ItemSummary? item;

  /// The session driving playback, once it has started.
  final PlaybackSession? session;

  /// Why the entry could not start, when it could not.
  final Object? error;
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
  StreamSubscription<void>? _completedSub;
  StreamSubscription<Object>? _failedSub;
  StreamSubscription<Duration>? _positionFeed;

  /// Item summaries the callers already had in hand, so a queue built
  /// from a list on screen does not re-fetch what it just showed. Also
  /// the only way an episode keeps its show: `GET /items/{pid}` answers
  /// a plain item detail, which carries no show pid, and the per-show
  /// playback settings hang off that.
  final Map<String, ItemSummary> _known = {};

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

  /// Where the entry being played was asked to start, so a retry asks
  /// for the same thing rather than falling back to the checkpoint.
  int? _entryPositionMs;

  @override
  NowPlaying build() {
    _engine = ref.read(audioEngineProvider);
    _connect = ref.read(connectControllerProvider);
    _registry = ref.read(currentSessionRegistryProvider);
    _boundarySub = _engine.itemBoundary.listen((_) => _onBoundary());
    ref.listen(queueControllerProvider, _onQueueChanged);
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
        if (ref.mounted && _startToken == 0) _inFlight = _start(standing);
      });
    }
    ref.onDispose(() {
      unawaited(_boundarySub?.cancel());
      _release(_session, _Farewell.stop);
      // Not through _setSession: the container is going away, and there
      // is nothing left for Connect to report to.
      _session = null;
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

  /// The summary behind [pid], when this layer already has one.
  ///
  /// Every queue built from a list on screen seeds these, and every
  /// entry that plays resolves one, so a queue surface can name most of
  /// what it shows without asking the server again. Null means nobody
  /// has needed it yet, not that it does not exist.
  ItemSummary? summaryFor(String pid) => _known[pid];

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

  /// The same verb for a queue named by pid alone, which is what
  /// arrives from outside the widget tree: a queue handed to this
  /// endpoint by another device, or a browse leaf tapped on a head
  /// unit. Summaries resolve as each entry starts.
  ///
  /// [autoplay] false loads the entry and stops there, for a queue put
  /// back at its checkpoint. Resolves once the entry it lands on has
  /// started or failed, so a caller that answers for the load can.
  /// [offerUndo] false for a queue this device did not choose - a load
  /// routed from another device, a media-session command - where an
  /// offer to take it back would undo something its user never did and
  /// leave the two ends disagreeing about what plays.
  Future<void> playPids(
    List<String> pids, {
    required QueueSource source,
    int startIndex = 0,
    bool shuffle = false,
    int? positionMs,
    bool autoplay = true,
    bool offerUndo = true,
  }) {
    if (pids.isEmpty) return Future<void>.value();
    _pendingPositionMs = positionMs;
    _pendingPaused = !autoplay;
    // Read before the queue moves, and the queue layer's own guard: it
    // keeps a displaced queue only when there was one.
    final displaced = ref.read(queueControllerProvider).isNotEmpty;
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
    if (displaced && offerUndo) {
      // No expiry beyond the snackbar's own: the queue holds only the
      // most recent replacement, and the shell hides the previous toast.
      ref
          .read(shellMessengerProvider.notifier)
          .show(
            'Replaced what was playing',
            actionLabel: 'Undo',
            onAction: undoReplace,
            actionSemanticsId: SemanticsIds.queueReplaceUndo,
          );
    }
    // The queue notifies its listeners as it is assigned, so the start
    // this landed on is already the one in flight.
    return settled;
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
    await session.replay(play: _engine.playing);
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
    _inFlight = _start(entry);
  }

  /// Puts a queue found at launch back in play, paused at its
  /// checkpoint. Accepting the offer means "put it back", not "start
  /// playing"; the transport is right there for the rest.
  /// [offerUndo] keeps what this displaced, for the surfaces that offer
  /// to put it back. Without it the offer is a button that cannot work.
  void restore(QueueState queue, {bool offerUndo = false}) {
    _pendingPositionMs = null;
    _pendingPaused = true;
    final began = _startToken;
    ref
        .read(queueControllerProvider.notifier)
        .restore(
          queue,
          displacedPositionMs: offerUndo
              ? _session?.displayPosition.inMilliseconds ?? 0
              : null,
        );
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
    _inFlight = _start(entry);
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
  void undoReplace() {
    // Read before the queue moves, not from what the undo returns: the
    // queue notifies its listeners as it is assigned, so the start this
    // lands on has already read these by the time the call comes back.
    final pending = ref.read(queueControllerProvider).undo;
    if (pending == null) return;
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
    // The entry playing did not move, but what follows it may have
    // (a reorder, a removal, a repeat toggle).
    unawaited(_syncPreload());
  }

  Future<void> _start(QueueEntry entry) async {
    final token = ++_startToken;
    _starting = token;
    _sessionEntryId = entry.queueId;
    final positionMs = _pendingPositionMs;
    final paused = _pendingPaused;
    _entryPositionMs = positionMs;
    _pendingPositionMs = null;
    _pendingPaused = false;
    state = NowPlaying(entry: entry, item: _known[entry.pid]);
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
      final session = _build(item, initialPositionMs: positionMs);
      // The engine's owner changes as start() begins, so the outgoing
      // session flushes its final checkpoint and listen report without
      // stopping media it no longer owns.
      final starting = session.start(autoplay: !paused);
      _install(session, entry);
      await starting;
      if (_superseded(token)) return;
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
      _release(_session, _Farewell.stop);
      _setSession(null);
      state = NowPlaying(entry: entry, item: _known[entry.pid], error: error);
    } finally {
      // Only if it is still this start's window: a newer one that
      // superseded this has its own to close.
      if (_starting == token) _starting = null;
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
    _sessionEntryId = entry.queueId;
    try {
      var item = _known[entry.pid];
      if (item == null) {
        // Normally the summary is in hand, because arming the preload
        // resolved it. Without it there is a fetch between the crossing
        // and the session that owns what is playing, and the outgoing
        // session has already let go: say so rather than leave a
        // finalized session on the state for surfaces to read.
        state = NowPlaying(entry: entry);
        item = await _resolve(entry.pid);
        if (_superseded(token)) return;
      }
      _entryPositionMs = null;
      final session = _build(item);
      final adopting = session.adopt(info);
      _install(session, entry);
      // Published as soon as the session exists rather than once it
      // settles: the item is already playing and this session speaks
      // for it from here, so a crossing with the summary in hand
      // publishes exactly once, whole, with no frame in between where
      // the transport has nothing to bind to.
      state = NowPlaying(entry: entry, item: item, session: session);
      await adopting;
      if (_superseded(token)) return;
      await _syncPreload();
    } on Object catch (error) {
      if (_superseded(token)) return;
      debugPrint('playback rollover failed: $error');
      _release(_session, _Farewell.stop);
      _setSession(null);
      state = NowPlaying(entry: entry, item: _known[entry.pid], error: error);
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
    _adopting = null;
    unawaited(_dropPreload());
    final session = _session;
    if (session == null) return;
    _release(session, _Farewell.handOver);
    _setSession(null);
    state = NowPlaying(entry: state.entry, item: state.item);
  }

  /// The queue ran out from under playback: let the item go and say so.
  void _stop() {
    _startToken++;
    _adopting = null;
    _sessionEntryId = null;
    unawaited(_dropPreload());
    _release(_session, _Farewell.stop);
    _setSession(null);
    state = NowPlaying.nothing;
  }

  PlaybackSession _build(ItemSummary item, {int? initialPositionMs}) =>
      PlaybackSession(
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
      );

  /// Makes [session] the live one: the previous session lets go, Connect
  /// and the session registry are pointed here, and the feeds this layer
  /// runs on hang off it.
  void _install(PlaybackSession session, QueueEntry entry) {
    _release(_session, _Farewell.stop);
    _sessionEntryId = entry.queueId;
    _registry.register(session);
    _setSession(session);
    _completedSub = session.sessionCompleted.listen((_) => _onCompleted());
    _failedSub = session.sessionFailed.listen(_onSessionFailed);
    // End-of-chapter sleep mode watches the display timeline; the
    // preload rides the same ticks, since when to prepare the next item
    // is a question about how much of this one is left.
    final sleepTimer = ref.read(sleepTimerProvider.notifier)
      // The chapter boundary belonged to the item that armed it. A
      // countdown is the listener's and stays.
      ..clearEndOfChapter();
    _positionFeed = session.displayPositionStream.listen((position) {
      sleepTimer.onPosition(position);
      unawaited(_syncPreload());
    });
  }

  /// Lets go of [session]: the feeds stop, the registry forgets it, and
  /// it finalizes out of band so the last checkpoint and listen report
  /// still ride while the next item loads.
  ///
  /// The caller names the session that replaces it (or none) through
  /// [_setSession], which is the one place Connect hears about it: what
  /// the endpoint mirrors is whichever session owns the engine, and
  /// between these two calls that is nothing.
  void _release(PlaybackSession? session, _Farewell farewell) {
    unawaited(_completedSub?.cancel());
    unawaited(_failedSub?.cancel());
    unawaited(_positionFeed?.cancel());
    _completedSub = null;
    _failedSub = null;
    _positionFeed = null;
    if (session == null) return;
    _registry.unregister(session);
    unawaited(switch (farewell) {
      _Farewell.stop => session.dispose(),
      _Farewell.boundary => session.finishAtBoundary(),
      _Farewell.handOver => session.handOver(),
    });
  }

  /// Points [liveSession] at [session] and tells Connect, whose reports
  /// follow whatever owns the engine: a fresh session mirrors from here,
  /// and none at all stops the reports rather than leaving an endpoint
  /// claiming to play something it let go of.
  void _setSession(PlaybackSession? session) {
    _session = session;
    _connect.onPlaybackChanged();
  }

  /// The live session could not do what its item needed mid-flight (a
  /// book part that would not load, a cross-part jump the server
  /// refused): let it go the way a failed start is let go, so the same
  /// error pane and retry stand where the transport was. The release
  /// flushes the checkpoint at the position the failure left, which is
  /// where the retry resumes.
  void _onSessionFailed(Object error) {
    final session = _session;
    if (session == null) return;
    debugPrint('playback session failed: $error');
    _release(session, _Farewell.stop);
    _setSession(null);
    state = NowPlaying(entry: state.entry, item: state.item, error: error);
  }

  /// The item ended with nothing behind it in the engine: step the
  /// queue, which is what loads whatever comes next.
  void _onCompleted() {
    if (_radioOwnsEngine) return;
    switch (ref.read(queueControllerProvider.notifier).advance()) {
      // The queue moved; the entry change starts what it landed on.
      case QueueAdvance.advanced:
      // Nothing follows: what just finished stays on the deck bar.
      case QueueAdvance.ended:
      case QueueAdvance.empty:
        break;
      case QueueAdvance.repeatedCurrent:
        final session = _session;
        if (session != null) unawaited(session.replay());
    }
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
      _release(_session, _Farewell.boundary);
      _setSession(null);
      _recoverFromStray();
      return;
    }
    // The outgoing item is finalized at its own end, not at the engine's
    // position, which already belongs to the item now playing.
    _release(_session, _Farewell.boundary);
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
    // The port prepares an item at the head of its window, so an item
    // that would resume anywhere else has to load on advance.
    final saved = await ref.read(repositoryProvider).getPlayState(next.pid);
    if (!ref.mounted) return;
    if (saved.positionMs > 0) {
      _refusedNext = next.queueId;
      return;
    }
    final info = await ref.read(repositoryProvider).getPlayInfo(next.pid);
    if (!ref.mounted) return;
    // Only passthrough streams: a preloaded transcode opens a second
    // server-side session, which double counts against the transcode
    // limiter or is refused outright in the middle of a queue. The
    // server marks a cut or voice-boosted stream unseekable, so these
    // two answers are the whole test.
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
