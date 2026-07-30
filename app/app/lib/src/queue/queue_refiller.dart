import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'queue_controller.dart';
import 'queue_source_pager.dart';
import 'queue_state.dart';

/// How few unplayed entries a rolling window falls to before it draws
/// again.
///
/// Far enough ahead that the draw lands before the gap does - a draw is
/// a round trip, and the entry after the current one is the one the
/// engine prepares - and short enough that a listener who stops after
/// two tracks has not pulled a hundred more down behind them.
const int kQueueRefillLead = 10;

/// How many draws in a row one drain will make.
///
/// A page can legitimately land empty: a bucket page of nothing but
/// audiobooks, a listing page whose every item is outside the caller's
/// libraries. The cursor still moves, so trying again is right, but a
/// scope with a long run of them should not be walked to its end in one
/// go while somebody waits for the next track.
const int _maxDrawsPerDrain = 5;

/// Keeps a rolling queue from running out of the scope it is a window
/// over.
///
/// The queue is a pure state machine and the pager is I/O; this is the
/// piece between them. It watches the queue drain, draws more of the
/// source when it gets short, and seals the window when the source has
/// no more to give - which is what turns the "window over a larger
/// scope" caption off, so nothing claims there is more once there is
/// not.
class QueueRefiller {
  QueueRefiller(this._ref);

  final Ref _ref;

  /// A draw in flight. Appending to the queue notifies this listener
  /// again, so without it a draw would set the next one going.
  bool _drawing = false;

  /// The entry the queue stood on when a draw failed. A failure is
  /// usually the network, and the next queue edit is often the same
  /// second; retrying then would hammer a server that is already down.
  /// Waiting for the current entry to move means the retry comes with
  /// the next track, which is when it can matter again.
  String? _blockedAt;

  void onChanged(QueueState state) {
    if (_drawing || state.isEmpty) return;
    if (!state.source.rolling) return;
    if (state.unplayed >= kQueueRefillLead) return;
    if (_blockedAt != null && _blockedAt == state.currentEntry?.queueId) return;
    _drawing = true;
    unawaited(_drain().whenComplete(() => _drawing = false));
  }

  Future<void> _drain() async {
    final pager = _ref.read(queueSourcePagerProvider);
    for (var draws = 0; draws < _maxDrawsPerDrain; draws++) {
      final state = _ref.read(queueControllerProvider);
      // Re-read every time round: the queue can be cleared or replaced
      // while a draw is in flight, and what arrives then belongs to a
      // window that no longer exists.
      if (state.isEmpty || !state.source.rolling) return;
      final QueueDraw? draw;
      try {
        draw = await pager.draw(state.source, afterPid: state.frontierPid);
      } on Object catch (error) {
        // A window that cannot be refilled is a queue that ends early,
        // which is what it did before any of this existed: worth a line
        // in the log, not worth taking anything down for.
        debugPrint('queue refill failed: $error');
        _blockedAt = state.currentEntry?.queueId;
        return;
      }
      if (!_ref.mounted) return;
      _blockedAt = null;
      final queue = _ref.read(queueControllerProvider.notifier);
      // Nothing here can page this source, or can find where in it the
      // queue stands. Either way there is no more to draw.
      if (draw == null) {
        queue.sealWindow();
        return;
      }
      queue.appendWindow(
        draw.pids,
        cursor: draw.cursor,
        more: draw.more,
        seed: draw.seed,
      );
      if (draw.pids.isNotEmpty || !draw.more) return;
    }
  }
}

/// Binds the refill to the session, alongside the queue's persistence:
/// both are things the queue needs doing for it while somebody is
/// signed in, and neither should outlive that.
final queueRefillProvider = Provider.autoDispose<QueueRefiller>((ref) {
  final refiller = QueueRefiller(ref);
  // Immediately as well as on change: a queue restored at launch is
  // already as short as it is going to get, and waiting for its next
  // edit would mean waiting for it to run out.
  ref.listen(
    queueControllerProvider,
    (_, next) => refiller.onChanged(next),
    fireImmediately: true,
  );
  return refiller;
});
