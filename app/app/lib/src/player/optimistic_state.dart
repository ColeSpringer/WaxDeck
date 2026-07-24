import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import '../sync/sync_providers.dart';

/// The optimistic-mutation protocol shared by the play-state controllers
/// (items, and their artist/album twin).
///
/// It is one protocol with several subtleties, so it lives in one place:
/// a second copy would drift the moment either side is fixed.
///
///  - The tap applies immediately, then settles on what the server
///    returns, so the control never lags the finger.
///  - Each in-flight intent is registered in a container-scoped map
///    before anything is awaited. Server events invalidate the family,
///    and a rebuild racing an unsettled write would otherwise refetch
///    the pre-mutation state and visually revert the tap; fresh builds
///    overlay the pending intents onto what they fetch.
///  - An unreachable server is not a rejection: the change queues in
///    the outbox and the optimistic value stands until the flush
///    announces the winner through sync.
///  - A rejection emits the failure and then restores the pre-tap value
///    in the same turn, so widgets only ever render real state.
///  - Settlement is a `finally`, never a per-path call: a throw outside
///    the typed catch must still remove the intent, or the leaked
///    transform overlays every later rebuild of that key until restart.
abstract class OptimisticStateController<T> extends AsyncNotifier<T> {
  OptimisticStateController(this.pid);

  /// The entity or item this controller's state belongs to, and the key
  /// its pending intents register under.
  final String pid;

  /// Reads the current server state.
  Future<T> fetch();

  /// The in-flight intents shared across rebuilds of this controller's
  /// family. Implementations hold one container-scoped map per family
  /// so two families never collide on a pid.
  Map<String, List<T Function(T)>> get pendingIntents;

  @override
  Future<T> build() async {
    final fetched = await fetch();
    final pending = pendingIntents[pid];
    if (pending == null) return fetched;
    var overlaid = fetched;
    for (final apply in pending) {
      overlaid = apply(overlaid);
    }
    return overlaid;
  }

  /// Applies [optimistic] at once, runs [call], and settles on its
  /// result; [queue] takes over when the server is unreachable.
  Future<void> mutate({
    required T Function(T) optimistic,
    required Future<T> Function() call,
    required Future<void> Function(SyncEngine engine) queue,
  }) async {
    final previous = state;
    final current = state.value;
    if (current != null) {
      state = AsyncData(optimistic(current));
    }
    // Register the intent and read what the rest of the method needs
    // through locals before awaiting: a family invalidation can dispose
    // this notifier mid-flight, after which ref and state are off
    // limits (the mounted guards below).
    final intents = pendingIntents;
    final engine = ref.read(syncEngineProvider);
    intents.putIfAbsent(pid, () => []).add(optimistic);
    void settle() {
      final list = intents[pid];
      list?.remove(optimistic);
      if (list != null && list.isEmpty) intents.remove(pid);
    }

    try {
      final settled = await call();
      if (ref.mounted) state = AsyncData(settled);
      // Not mounted: the replacement controller built with the intent
      // overlaid, which is exactly the value the server just stored.
    } on WaxDeckApiException catch (e, st) {
      if (engine != null && _unreachable(e)) {
        await queue(engine);
        return;
      }
      if (!ref.mounted) {
        // Rejected after a rebuild: the rollback cannot reach the
        // replacement controller. The intent is settled, so any later
        // rebuild fetches the truth; a replacement that built during
        // the flight keeps its optimistic frame until the next event or
        // screen entry (a rejection racing a rebuild is the edge of an
        // edge, and the server state is correct throughout).
        return;
      }
      state = AsyncError<T>(e, st);
      state = previous;
    } finally {
      settle();
    }
  }

  static bool _unreachable(WaxDeckApiException e) {
    return e.statusCode == null || e.statusCode == 503;
  }
}
