import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import '../providers.dart';
import '../sync/sync_providers.dart';

/// In-flight optimistic intents by pid, container-scoped so they
/// survive controller rebuilds: server events (a playing session's own
/// checkpoints included) invalidate the play-state family, and a
/// rebuild racing an unsettled mutation would otherwise refetch the
/// pre-mutation server state and visually revert the tap. Fresh builds
/// overlay these intents onto what they fetch, so the optimistic value
/// holds across the rebuild until the write settles.
final _pendingIntentsProvider =
    Provider<Map<String, List<PlayState Function(PlayState)>>>((_) => {});

/// One item's play state (star, rating, progress) for UI that edits it.
///
/// Mutations apply optimistically so the tap feels instant, then settle
/// on the state the server returns. A failure rolls back to the
/// pre-tap state and surfaces as an error carrying that previous value,
/// so the UI keeps rendering the real state while it tells the user the
/// change did not stick.
class PlayStateController extends AsyncNotifier<PlayState> {
  PlayStateController(this.pid);

  final String pid;

  @override
  Future<PlayState> build() async {
    final fetched = await ref.watch(repositoryProvider).getPlayState(pid);
    final pending = ref.read(_pendingIntentsProvider)[pid];
    if (pending == null) return fetched;
    var overlaid = fetched;
    for (final apply in pending) {
      overlaid = apply(overlaid);
    }
    return overlaid;
  }

  Future<void> setStarred(bool starred) => _mutate(
    optimistic: (s) => _copy(s, starred: starred),
    call: () => ref.read(repositoryProvider).setStar(pid, starred),
    queue: (engine) => engine.queueStar(pid, starred),
  );

  /// Rates the item 0 to 100, or clears the rating with null.
  Future<void> rate(int? rating) => _mutate(
    optimistic: (s) => _copy(s, rating: rating, setRating: true),
    call: () => ref.read(repositoryProvider).setRating(pid, rating),
    queue: (engine) => engine.queueRating(pid, rating),
  );

  Future<void> _mutate({
    required PlayState Function(PlayState) optimistic,
    required Future<PlayState> Function() call,
    required Future<void> Function(SyncEngine engine) queue,
  }) async {
    final previous = state;
    final current = state.value;
    if (current != null) {
      state = AsyncData(optimistic(current));
    }
    // Register the intent before awaiting anything, and read what the
    // rest of the method needs through locals: a family invalidation
    // can dispose this notifier mid-flight, after which ref and state
    // are off limits (the mounted guards below).
    final intents = ref.read(_pendingIntentsProvider);
    final engine = ref.read(syncEngineProvider);
    intents.putIfAbsent(pid, () => []).add(optimistic);
    void settle() {
      final list = intents[pid];
      list?.remove(optimistic);
      if (list != null && list.isEmpty) intents.remove(pid);
    }

    // Settlement is a finally, never a per-path call: an exception
    // outside the typed catch (a repository bug throwing something
    // other than the API exception) must still remove the intent, or
    // the leaked transform would overlay every future rebuild of this
    // pid until app restart.
    try {
      final settled = await call();
      if (ref.mounted) state = AsyncData(settled);
      // Not mounted: the replacement controller built with the intent
      // overlaid, which is exactly the value the server just stored.
    } on WaxDeckApiException catch (e, st) {
      // An unreachable server is not a rejection: the change queues in
      // the outbox and the optimistic state stands (the winner comes
      // back through sync on reconnect). An offline rebuild cannot
      // fetch anything to overlay anyway, and the flushed outbox
      // announces the winner through sync.
      if (engine != null && _unreachable(e)) {
        await queue(engine);
        return;
      }
      if (!ref.mounted) {
        // Rejected after a rebuild: the rollback cannot reach the
        // replacement controller. The intent is settled, so any later
        // rebuild fetches the truth; a replacement that built during
        // the flight keeps its optimistic frame until the next
        // play-state event or screen entry (a rejection racing a
        // rebuild is the edge of an edge, and the server state is
        // correct throughout).
        return;
      }
      // Emit the failure so listeners can tell the user, then restore
      // the pre-tap state in the same turn; widgets only ever render
      // the rolled-back data.
      state = AsyncError<PlayState>(e, st);
      state = previous;
    } finally {
      settle();
    }
  }

  static bool _unreachable(WaxDeckApiException e) {
    return e.statusCode == null || e.statusCode == 503;
  }

  /// A field-level copy; PlayState has no copyWith because a nullable
  /// rating needs an explicit set flag to distinguish clear from keep.
  static PlayState _copy(
    PlayState s, {
    bool? starred,
    int? rating,
    bool setRating = false,
  }) {
    return PlayState(
      pid: s.pid,
      positionMs: s.positionMs,
      played: s.played,
      finished: s.finished,
      playCount: s.playCount,
      starred: starred ?? s.starred,
      rating: setRating ? rating : s.rating,
      updatedAt: s.updatedAt,
    );
  }
}

final playStateControllerProvider = AsyncNotifierProvider.autoDispose
    .family<PlayStateController, PlayState, String>(PlayStateController.new);
