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

// The controller's sections live in the parts, as mixins over
// _NowPlayingCore, which holds the state: an extension cannot use a
// notifier's protected ref and state. A mixin reaches a member of one
// applied after it through an abstract declaration in the core.
part 'now_playing/now_playing_park.dart';
part 'now_playing/now_playing_transport.dart';
part 'now_playing/now_playing_failure.dart';
part 'now_playing/now_playing_preload.dart';
part 'now_playing/now_playing_install.dart';
part 'now_playing/now_playing_queue.dart';

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

  /// The queue entry being played, or null when nothing is: an empty
  /// queue, or one a station holds back ([parkedEntryProvider]).
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

/// [NowPlayingController]'s state, and the members its mixins share.
abstract class _NowPlayingCore extends Notifier<NowPlaying> {
  // Read once and held: these are fixed for the container's life, and
  // this controller lets go of a session from its own disposal, where
  // reading a provider is not allowed.
  late final AudioEnginePort _engine;
  late final ConnectEndpointController _connect;
  late final CurrentSessionRegistry _registry;

  PlaybackSession? _session;
  String? _sessionEntryId;

  /// Whether a session for [_sessionEntryId] has loaded since it became
  /// the entry: what a station takes from it then is displaced from
  /// playback, where one that never loaded parks fresh.
  bool _sessionEntryLoaded = false;

  /// Whether the latest start of [_sessionEntryId] meant to resume its
  /// checkpoint (a launch's queue, a queue standing when playback was
  /// built, a park taken back) rather than begin it: one a station holds
  /// back before it loaded still comes back to that place.
  bool _entryUseSaved = false;

  /// Armed across one synchronous queue call whose new current entry is
  /// parked fresh rather than started: by [NowPlayingController.dropCurrent]
  /// while parked, so what lands in the dropped one's place takes over the
  /// park, and by an add while a station plays, so an empty queue's new
  /// entry waits for it.
  bool _parkLanding = false;

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

  /// Armed by [NowPlayingController.restore] across the one synchronous
  /// call that can consume it, so the start the queue's own notification
  /// lands on knows it is putting a listen back rather than beginning one.
  /// Every other caller says so with [_start]'s parameter; this one cannot,
  /// because the start it means happens inside `queue.restore`.
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

  /// A load of the app's own is opening the item and means to play it:
  /// a start in flight, or the live session reopening its stream
  /// ([PlaybackSession.reopening]). The engine reads stopped through
  /// either, so a surface outside the app (the OS media session, a
  /// Connect report, the Discord presence) reads this beside it.
  final ValueNotifier<bool> opening = ValueNotifier(false);

  /// Whether playback means to be running: the engine, or a load of the
  /// app's own that lands playing ([opening]). What every transport draws,
  /// a start in flight included, and what
  /// [NowPlayingController.togglePlayback] reverses.
  bool get meansToPlay => _engine.playing || opening.value;

  void _republishOpening() {
    // A start still unwinding as the container goes has nobody to tell.
    if (!ref.mounted) return;
    opening.value = _startPlays ?? _session?.reopening.value ?? false;
  }

  /// Resolves when the start in flight has finished, or immediately when
  /// none is.
  ///
  /// A failed start is recorded on the state rather than thrown (the
  /// listener gets an error pane with a retry), so a caller that has to
  /// answer for one reads [NowPlaying.error] after awaiting this.
  Future<void> get settled => _inFlight ?? Future<void>.value();

  /// Whether a start begun under [token] still speaks for this
  /// controller: a newer one has taken over, or the container it lives in
  /// is gone (a sign-out, a closing app) and touching state or providers
  /// from here would throw.
  bool _superseded(int token) => token != _startToken || !ref.mounted;

  /// Whether live radio has taken the engine. Radio never queues, so
  /// nothing it does to the engine is a queue event.
  bool get _radioOwnsEngine => ref.read(radioPlaybackProvider).station != null;

  ParkedEntry? get parked;
  Future<void> _start(QueueEntry entry, {bool useSavedPosition, bool ordinary});
  Future<void> _adopt(QueueEntry entry, PlayInfo info);
  Future<void> _release(PlaybackSession? session, _Farewell farewell);
}

/// How many unplayable items a single run may skip past before
/// playback stops and says so.
///
/// A queue of broken files would otherwise walk itself to the end
/// with a toast per item, which is neither playback nor a report. The
/// count resets on any item that does load, so a bad file in the
/// middle of a good album costs one skip and nothing else.
const int _maxConsecutiveSkips = 3;

const _outageGrace = Duration(seconds: 30);

/// Owns playback. One [PlaybackSession] at a time, following the queue's
/// current entry: whatever puts an entry there (a tap, a skip, a
/// restored queue, an advance at the end of an item) is what starts
/// playing, and every surface that shows what is playing reads this.
///
/// Session lifecycle deliberately does not hang off a widget. A player
/// screen that owned its session could not survive being popped, which
/// is what a persistent deck bar needs; here the screens are viewers and
/// the session outlives all of them.
class NowPlayingController extends _NowPlayingCore
    with
        _NowPlayingPark,
        _NowPlayingTransport,
        _NowPlayingFailure,
        _NowPlayingPreload,
        _NowPlayingInstall,
        _NowPlayingQueue {
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

  /// The queue's current entry while a station holds it back: not
  /// playing, and started again only through [playEntryAt].
  @override
  ParkedEntry? get parked =>
      _parkedOf(_park, ref.read(queueControllerProvider).currentEntry);

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
    _parkFollowsKnown();
  }

  /// Forgets the summaries held for [ulids] (pids without their prefix),
  /// under either prefix: items a kind change converted in place, which
  /// start next time as what they are now.
  void forgetItems(Set<String> ulids) {
    if (ulids.isEmpty) return;
    _known.removeWhere((pid, _) => ulids.contains(ulidOf(pid)));
    _parkFollowsKnown();
  }

  /// Forgets every summary the queue does not need, for a caller that has
  /// just checked the queue's own against the server: what is left is
  /// what it checked, and what an undo would bring back.
  void forgetUnqueued() => _prune(ref.read(queueControllerProvider));

  /// Holds [item] for [pid], read again because the item changed kind:
  /// what was held under either prefix goes, and the fresh summary is kept
  /// under the pid the queue names it by, as a start would keep it.
  void refreshSummary(String pid, ItemSummary item) {
    final ulid = ulidOf(pid);
    _known.removeWhere((held, _) => ulidOf(held) == ulid);
    if (item.mediaType != MediaType.podcast) _known[pid] = item;
    _parkFollowsKnown();
  }

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
}

/// The one playback owner.
final nowPlayingProvider = NotifierProvider<NowPlayingController, NowPlaying>(
  NowPlayingController.new,
);
