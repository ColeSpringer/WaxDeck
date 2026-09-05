import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import 'optimistic_state.dart';

/// In-flight optimistic intents by item pid, container-scoped and kept
/// apart from the entity family's: the two key on different pid spaces
/// and must never overlay each other.
final _pendingIntentsProvider =
    Provider<Map<String, List<PlayState Function(PlayState)>>>((_) => {});

/// One item's play state (star, rating, progress) for UI that edits it.
///
/// Rides the optimistic-mutation protocol in
/// [OptimisticStateController], which carries the whole
/// rebuild-versus-in-flight-write story.
class PlayStateController extends OptimisticStateController<PlayState> {
  PlayStateController(super.pid);

  @override
  Map<String, List<PlayState Function(PlayState)>> get pendingIntents =>
      ref.read(_pendingIntentsProvider);

  @override
  Future<PlayState> fetch() => ref.watch(repositoryProvider).getPlayState(pid);

  Future<void> setStarred(bool starred) => mutate(
    optimistic: (s) => _copy(s, starred: starred),
    call: () => ref.read(repositoryProvider).setStar(pid, starred),
    queue: (engine) => engine.queueStar(pid, starred),
  );

  /// Rates the item 0 to 100, or clears the rating with null.
  Future<void> rate(int? rating) => mutate(
    optimistic: (s) => _copy(s, rating: rating, setRating: true),
    call: () => ref.read(repositoryProvider).setRating(pid, rating),
    queue: (engine) => engine.queueRating(pid, rating),
  );

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
      lastPlayedAt: s.lastPlayedAt,
      updatedAt: s.updatedAt,
    );
  }
}

final playStateControllerProvider = AsyncNotifierProvider.autoDispose
    .family<PlayStateController, PlayState, String>(PlayStateController.new);
