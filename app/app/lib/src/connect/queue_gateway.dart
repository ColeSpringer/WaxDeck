import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../player/now_playing_controller.dart';
import '../player/playback_session.dart';
import '../queue/queue_controller.dart';
import '../queue/queue_state.dart';

/// The queue as the mirror contract reports it: the ordered pids, where
/// the listener stands in them, and the toggles a controller renders.
class QueueSnapshot {
  const QueueSnapshot({
    required this.pids,
    required this.index,
    required this.positionMs,
    required this.repeat,
    required this.shuffled,
  });

  final List<String> pids;
  final int index;

  /// Position within the current entry, on its display timeline (the
  /// book timeline for audiobooks).
  final int positionMs;

  final QueueRepeat repeat;
  final bool shuffled;
}

/// The local queue and the playback following it, for the surfaces that
/// live outside the widget tree: the Connect endpoint, which executes
/// commands routed here from another device, and the media session,
/// which drives playback from a head unit or a lock screen.
///
/// One seam, so those two and the UI cannot disagree about what is
/// queued. Before it existed the endpoint kept a queue of its own for
/// remotely loaded ones: a queue handed over from another device played
/// through something no screen could see, and a skip on the head unit
/// stepped that queue rather than the one on screen.
abstract class QueueGateway {
  /// What is queued and where it stands, or null when nothing local is
  /// playing: an empty queue, or an engine live radio has taken.
  QueueSnapshot? snapshot();

  /// Whether anything is queued at all.
  ///
  /// What tells the end of a session from the gap inside one: at a
  /// gapless crossing the live session is briefly nobody's while the
  /// queue stands, and a mirror that treated that as the end would
  /// re-introduce itself, whole queue and all, at every track.
  bool get hasQueue;

  /// The session driving playback, for the verbs that have to go
  /// through it rather than at the engine: seek reads the book
  /// timeline, and a rate is remembered per show and per book.
  PlaybackSession? get session;

  /// Replaces the queue with [pids] and plays the entry at [index] from
  /// [positionMs]. Throws when that entry cannot start, so a routed
  /// command answers for it.
  Future<void> load(
    List<String> pids, {
    required int index,
    required int positionMs,
    required bool play,
  });

  /// Plays one item by itself, for a browse-tree leaf tapped on a head
  /// unit. Throws when it cannot start.
  Future<void> playItem(String pid);

  /// Steps to the next entry. False when the queue has nowhere to go.
  Future<bool> next();

  /// Steps back an entry, or starts the current one over when already
  /// at the front. False when nothing is queued.
  Future<bool> previous();

  /// Ends playback and the queue with it: a controller's `stop` ends
  /// the session, and the local queue is what that session is.
  void stop();

  void setRepeat(QueueRepeat repeat);

  void setShuffle(bool shuffle);
}

/// [QueueGateway] over the two controllers that actually hold this: the
/// queue, and the playback that follows its current entry.
///
/// Providers are read per call rather than held, because playback is
/// built on top of Connect (the endpoint controller is one of its
/// dependencies) and reading it back at construction would close the
/// loop.
class LocalQueueGateway implements QueueGateway {
  LocalQueueGateway(this._ref);

  final Ref _ref;

  QueueController get _queue => _ref.read(queueControllerProvider.notifier);

  NowPlayingController get _playback => _ref.read(nowPlayingProvider.notifier);

  @override
  PlaybackSession? get session => _playback.liveSession;

  @override
  bool get hasQueue => _ref.read(queueControllerProvider).isNotEmpty;

  @override
  QueueSnapshot? snapshot() {
    final session = _playback.liveSession;
    if (session == null) return null;
    final queue = _ref.read(queueControllerProvider);
    if (queue.isEmpty) return null;
    return QueueSnapshot(
      pids: queue.pids,
      index: queue.currentIndex,
      // Until media reaches the engine the position it reports is the
      // outgoing item's, and a session is installed before its start
      // resolves. Skipping from four minutes into one track to a
      // shorter one would otherwise publish the new index at the old
      // position, which reads on a controller as a scrubber past the
      // end of what it names.
      positionMs: session.isLoaded ? session.displayPosition.inMilliseconds : 0,
      repeat: queue.repeat,
      shuffled: queue.shuffled,
    );
  }

  @override
  Future<void> load(
    List<String> pids, {
    required int index,
    required int positionMs,
    required bool play,
  }) async {
    if (pids.isEmpty) {
      throw const WaxDeckApiException(
        code: 'invalid-request',
        message: 'the load carried no items',
      );
    }
    final began = _playback.startGeneration;
    // The order in the frame is the order the controlling device is
    // showing, and shuffle is its own verb: a standing local preference
    // must not reorder what was handed over, or the two ends disagree
    // about what plays next.
    _queue.setShuffle(false);
    await _playback.playPids(
      pids,
      // Pids and nothing else arrive with a load; the entity they came
      // from stayed on the device that sent it.
      source: QueueSource.none,
      startIndex: index.clamp(0, pids.length - 1),
      positionMs: positionMs > 0 ? positionMs : null,
      autoplay: play,
    );
    _throwOnFailedStart(began);
  }

  @override
  Future<void> playItem(String pid) async {
    final began = _playback.startGeneration;
    await _playback.playPids([
      pid,
    ], source: const QueueSource(kind: QueueSourceKind.single, label: ''));
    _throwOnFailedStart(began);
  }

  @override
  Future<bool> next() async {
    final began = _playback.startGeneration;
    final moved = await _playback.next();
    _throwOnFailedStart(began);
    return moved;
  }

  @override
  Future<bool> previous() async {
    final began = _playback.startGeneration;
    final moved = await _playback.previous();
    _throwOnFailedStart(began);
    return moved;
  }

  @override
  void stop() => _queue.clear();

  @override
  void setRepeat(QueueRepeat repeat) => _queue.setRepeat(repeat);

  @override
  void setShuffle(bool shuffle) => _queue.setShuffle(shuffle);

  /// Playback records a failed start on its state rather than throwing
  /// (the error pane and its retry are what a listener gets), so a
  /// caller that has to answer for the start reads it back here.
  ///
  /// [began] is the start generation when the call began. Not every
  /// verb starts something (a skip at the front replays what is
  /// loaded), and answering one of those with a failure left there by
  /// something else would blame this command for it.
  void _throwOnFailedStart(int began) {
    if (_playback.startGeneration == began) return;
    final error = _ref.read(nowPlayingProvider).error;
    if (error == null) return;
    if (error is WaxDeckApiException) throw error;
    throw WaxDeckApiException(code: 'internal', message: error.toString());
  }
}

/// The one gateway onto local playback.
final queueGatewayProvider = Provider<QueueGateway>(LocalQueueGateway.new);
