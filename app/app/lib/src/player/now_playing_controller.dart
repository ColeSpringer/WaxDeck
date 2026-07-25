import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

import '../connect/connect_controller.dart';
import '../connect/connect_providers.dart';
import '../providers.dart';
import '../queue/queue_controller.dart';
import '../queue/queue_state.dart';
import '../radio/radio_controller.dart';
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

  StreamSubscription<void>? _boundarySub;
  StreamSubscription<void>? _completedSub;
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
    ref.listen(radioPlaybackProvider, (previous, next) {
      if (next.station != null) _handOverToRadio();
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
        if (ref.mounted && _startToken == 0) unawaited(_start(standing));
      });
    }
    ref.onDispose(() {
      unawaited(_boundarySub?.cancel());
      _release(_session, _Farewell.stop);
      _session = null;
    });
    return NowPlaying.nothing;
  }

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
    _pendingPositionMs = positionMs;
    _pendingPaused = false;
    ref
        .read(queueControllerProvider.notifier)
        .playNow(
          [for (final item in items) item.pid],
          source: source,
          startIndex: startIndex,
          shuffle: shuffle,
          // Where the displaced queue stood, which the queue layer has
          // no way to know and this one does: it is what an Undo of the
          // replacement resumes at.
          replacedPositionMs: _session?.displayPosition.inMilliseconds ?? 0,
        );
  }

  /// Starts the current entry over after a failure. The queue never
  /// moved, so nothing else would try again: a stream that expired
  /// under a sleeping phone, or a server that was down for a moment,
  /// is one tap from playing rather than a queue that has to be
  /// rebuilt.
  void retry() {
    if (state.error == null) return;
    final entry = ref.read(queueControllerProvider).currentEntry;
    if (entry == null) return;
    _pendingPositionMs = _entryPositionMs;
    unawaited(_start(entry));
  }

  /// Puts a queue found at launch back in play, paused at its
  /// checkpoint. Accepting the offer means "put it back", not "start
  /// playing"; the transport is right there for the rest.
  void restore(QueueState queue) {
    _pendingPositionMs = null;
    _pendingPaused = true;
    ref.read(queueControllerProvider.notifier).restore(queue);
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
        unawaited(_adopt(entry, adopting.info));
      } else {
        unawaited(_start(entry));
      }
      return;
    }
    // The entry playing did not move, but what follows it may have
    // (a reorder, a removal, a repeat toggle).
    unawaited(_syncPreload());
  }

  Future<void> _start(QueueEntry entry) async {
    final token = ++_startToken;
    _sessionEntryId = entry.queueId;
    final positionMs = _pendingPositionMs;
    final paused = _pendingPaused;
    _entryPositionMs = positionMs;
    _pendingPositionMs = null;
    _pendingPaused = false;
    // Live radio bypasses sessions; loading an item takes the engine
    // back, so the radio surface must stop claiming it.
    ref.read(radioPlaybackProvider.notifier).markInterrupted();
    state = NowPlaying(entry: entry, item: _known[entry.pid]);
    try {
      final item = await _resolve(entry.pid);
      if (_superseded(token)) return;
      final session = _build(item, initialPositionMs: positionMs);
      // A load starts a fresh window, so whatever was prepared behind
      // the outgoing item is gone at the engine and gone here.
      _preload = null;
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
      _session = null;
      state = NowPlaying(entry: entry, item: _known[entry.pid], error: error);
    }
  }

  /// Takes over a stream the engine is already playing, after it crossed
  /// out of the previous item and into this one.
  Future<void> _adopt(QueueEntry entry, PlayInfo info) async {
    final token = ++_startToken;
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
      _session = null;
      state = NowPlaying(entry: entry, item: _known[entry.pid], error: error);
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
  void _handOverToRadio() {
    final session = _session;
    if (session == null) return;
    _startToken++;
    _adopting = null;
    unawaited(_dropPreload());
    _release(session, _Farewell.handOver);
    _session = null;
    state = NowPlaying(entry: state.entry, item: state.item);
  }

  /// The queue ran out from under playback: let the item go and say so.
  void _stop() {
    _startToken++;
    _adopting = null;
    _sessionEntryId = null;
    unawaited(_dropPreload());
    _release(_session, _Farewell.stop);
    _session = null;
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
      );

  /// Makes [session] the live one: the previous session lets go, Connect
  /// and the session registry are pointed here, and the feeds this layer
  /// runs on hang off it.
  void _install(PlaybackSession session, QueueEntry entry) {
    _release(_session, _Farewell.stop);
    _session = session;
    _sessionEntryId = entry.queueId;
    _registry.register(session);
    _connect.attachLocal(session, entry.pid);
    _completedSub = session.sessionCompleted.listen((_) => _onCompleted());
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

  /// Lets go of [session]: the feeds stop, Connect and the registry
  /// forget it, and it finalizes out of band so the last checkpoint and
  /// listen report still ride while the next item loads.
  void _release(PlaybackSession? session, _Farewell farewell) {
    unawaited(_completedSub?.cancel());
    unawaited(_positionFeed?.cancel());
    _completedSub = null;
    _positionFeed = null;
    if (session == null) return;
    _connect.detachLocal(session);
    _registry.unregister(session);
    unawaited(switch (farewell) {
      _Farewell.stop => session.dispose(),
      _Farewell.boundary => session.finishAtBoundary(),
      _Farewell.handOver => session.handOver(),
    });
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
      _session = null;
      _recoverFromStray();
      return;
    }
    // The outgoing item is finalized at its own end, not at the engine's
    // position, which already belongs to the item now playing.
    _release(_session, _Farewell.boundary);
    _session = null;
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
      unawaited(_adopt(crossed.entry, crossed.info));
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
        if (entry != null) unawaited(_start(entry));
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
    final item = await ref.read(repositoryProvider).getItem(pid);
    _known[pid] = item;
    return item;
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
