import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../discovery/discovery_actions.dart';
import '../player/now_playing_controller.dart';
import '../providers.dart';
import '../settings/client_prefs.dart';
import 'queue_controller.dart';
import 'queue_state.dart';

/// Keeps a music queue going once it has played itself out.
///
/// A sibling of `QueueRefiller` rather than a branch inside it. That one
/// is about `source.rolling` - a window over a scope that exists, drawn
/// from again as it drains. This is a different policy: the queue really
/// has ended, and what follows is invented rather than drawn, so it is
/// asked for once there is nothing left rather than ten entries before.
///
/// Its state is the queue ids it appended, which is what the queue
/// surface draws its divider above. Session-only by decision: nothing on
/// `QueueEntry`, `QueueState` or the stored queue records where an entry
/// came from, and a persisted marker would be a client-side schema
/// change for a rule of thumb. After a relaunch the divider is gone and
/// the tracks stay, which is the right way round.
class QueueContinuation extends Notifier<Set<String>> {
  /// An extension in flight. Appending notifies this listener again, so
  /// without it one continuation would set the next one going.
  bool _extending = false;

  /// The entry the queue stood on when a mix failed or came back empty.
  /// A queue that has run out does not move on its own, so this is what
  /// stops a failure becoming a loop; the next track the listener starts
  /// clears it.
  ///
  /// Keyed by the entry's pid as well as its queue id, because a queue
  /// id is only unique within one queue: a restored session re-mints
  /// them from zero and an undone replace rolls the counter back, so an
  /// id on its own would let one failure silence an unrelated queue.
  String? _blockedAt;

  /// The published set, kept here as well because the guards below run
  /// from inside `build` - where the notifier's own state is a provider
  /// that has not finished building and cannot be read.
  Set<String> _appended = const <String>{};

  @override
  Set<String> build() {
    // Immediately as well as on change, for the reason the refiller
    // gives: a one-entry queue is already as short as it will get, and
    // waiting for its next edit would mean waiting forever.
    ref.listen(
      queueControllerProvider,
      (_, next) => _onChanged(next),
      fireImmediately: true,
    );
    // A run-out queue emits nothing further, so the switch has to be its
    // own trigger: turning this on is most useful at the moment the
    // music has just stopped, which is exactly when nothing else will
    // notify. Off needs no answer - what has already been appended stays
    // appended, and the divider says where it began.
    ref.listen(keepPlayingSimilarProvider, (_, on) {
      if (on) _onChanged(ref.read(queueControllerProvider));
    });
    // The seed's own summary is what says whether a mix belongs after
    // it, and that summary arrives from a resolve the queue's
    // notification does not wait for. A queue adopted whole - a restored
    // session, a handover - knows nothing about its own last entry at
    // the moment it lands, so this is the second look that comes once it
    // does.
    ref.listen(nowPlayingProvider, (previous, next) {
      if (previous?.item?.pid == next.item?.pid) return;
      _onChanged(ref.read(queueControllerProvider));
    });
    return _appended;
  }

  void _onChanged(QueueState queue) {
    if (_extending) return;
    // The divider is drawn from these, so ids the standing queue no
    // longer holds have to go: a replaced queue re-mints ids from zero
    // and a stale one would mark a track nothing here appended.
    if (_appended.isNotEmpty) {
      final live = <String>{for (final e in queue.entries) e.queueId};
      if (_appended.any((id) => !live.contains(id))) {
        state = _appended = _appended.intersection(live);
      }
    }
    if (!ref.read(keepPlayingSimilarProvider)) return;
    if (queue.isEmpty) return;
    // A window refills itself first, and from a scope somebody chose.
    if (queue.source.rolling) return;
    // `unplayed` is `length - 1 - currentIndex`, so a queue on repeat
    // hits zero on its last track - and growing a mix behind a loop the
    // listener explicitly asked for is not continuing, it is overriding.
    if (queue.repeat != QueueRepeat.off) return;
    if (queue.unplayed > 0) return;
    final seed = queue.currentEntry;
    if (seed == null || _blockedAt == _blockKey(seed)) return;
    // Music only, and the seed decides it: the mix is built from this
    // entry, so this entry is what says whether a mix is the right thing
    // to follow it with. Reading the whole queue instead asked about
    // entries nothing has resolved - a restored session knows nothing
    // about anything it has not played yet - and let one podcast in the
    // history disable the rest of the sitting.
    final playing = ref.read(nowPlayingProvider.notifier).summaryFor(seed.pid);
    if (playing?.mediaType != MediaType.music) return;
    _extending = true;
    unawaited(_extend(queue, seed).whenComplete(_settled));
  }

  /// Runs the guards again against whatever the queue is now.
  ///
  /// The queue can be replaced while a mix builds, and the replacement
  /// is dropped on arrival because it is not what was asked for. A
  /// run-out queue emits nothing on its own, so without this second look
  /// that replacement would never be continued.
  void _settled() {
    _extending = false;
    if (!ref.mounted) return;
    _onChanged(ref.read(queueControllerProvider));
  }

  String _blockKey(QueueEntry entry) => '${entry.queueId}:${entry.pid}';

  Future<void> _extend(QueueState queue, QueueEntry seed) async {
    final InstantMix mix;
    try {
      mix = await ref
          .read(repositoryProvider)
          .createInstantMix(
            seedPid: seed.pid,
            adventurousness: ref.read(mixAdventurousnessProvider),
            size: instantMixSize,
            // The whole queue, not upcomingPids: the continuation only
            // ever runs standing on the last entry, where "current plus
            // upcoming" is one track - and the seed's nearest
            // neighbours are exactly what just played, so on a small
            // library that would re-append the album that just ended,
            // forever, with repeat off. Running dry and stopping is
            // the honest end of "keep playing similar".
            excludePids: queue.pids,
          );
    } on Object catch (error) {
      // A queue that ends where it was built to end is what happened
      // before any of this existed: worth a line in the log, not worth
      // taking anything down for.
      debugPrint('queue continuation failed: $error');
      _blockedAt = _blockKey(seed);
      return;
    }
    if (!ref.mounted) return;
    if (mix.items.isEmpty) {
      _blockedAt = _blockKey(seed);
      return;
    }
    // The queue may have been replaced or moved on while the mix built.
    final standing = ref.read(queueControllerProvider);
    final now = standing.currentEntry;
    if (now == null || _blockKey(now) != _blockKey(seed)) return;
    _blockedAt = null;
    final before = <String>{for (final e in standing.entries) e.queueId};
    // `enqueue`, not `appendWindow`: the latter sets `rolling` on the
    // source, which would turn an album queue into a window over a scope
    // that does not exist. This wraps `addToEnd`, which caps the queue
    // and seeds the summaries, so the new rows have titles at once.
    ref.read(nowPlayingProvider.notifier).enqueue(mix.items);
    state = _appended = <String>{
      ..._appended,
      for (final e in ref.read(queueControllerProvider).entries)
        if (!before.contains(e.queueId)) e.queueId,
    };
  }
}

/// Bound for the length of a session, beside the queue's persistence and
/// its refill.
final queueContinuationProvider =
    NotifierProvider.autoDispose<QueueContinuation, Set<String>>(
      QueueContinuation.new,
    );
