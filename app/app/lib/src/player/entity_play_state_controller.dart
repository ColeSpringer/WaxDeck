import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import 'optimistic_state.dart';

/// In-flight optimistic intents by entity pid, container-scoped and kept
/// apart from the item family's: the two key on different pid spaces and
/// must never overlay each other.
final _pendingIntentsProvider =
    Provider<Map<String, List<EntityPlayState Function(EntityPlayState)>>>(
      (_) => {},
    );

/// One catalog entity's star and rating for UI that edits them.
///
/// The artist and album twin of `PlayStateController`; both ride the
/// optimistic-mutation protocol in [OptimisticStateController], which
/// carries the whole rebuild-versus-in-flight-write story.
///
/// Entity state is its own fact, not a rollup: starring an album leaves
/// its tracks' stars alone, so this never touches the item family.
class EntityPlayStateController
    extends OptimisticStateController<EntityPlayState> {
  EntityPlayStateController(super.pid);

  @override
  Map<String, List<EntityPlayState Function(EntityPlayState)>>
  get pendingIntents => ref.read(_pendingIntentsProvider);

  @override
  Future<EntityPlayState> fetch() =>
      ref.watch(repositoryProvider).getEntityPlayState(pid);

  Future<void> setStarred(bool starred) => mutate(
    optimistic: (s) => _copy(s, starred: starred),
    call: () => ref.read(repositoryProvider).setEntityStar(pid, starred),
    queue: (engine) => engine.queueEntityStar(pid, starred),
  );

  /// Rates the entity 0 to 100, or clears the rating with null.
  Future<void> rate(int? rating) => mutate(
    optimistic: (s) => _copy(s, rating: rating, setRating: true),
    call: () => ref.read(repositoryProvider).setEntityRating(pid, rating),
    queue: (engine) => engine.queueEntityRating(pid, rating),
  );

  /// A field-level copy; a nullable rating needs an explicit set flag to
  /// distinguish clear from keep.
  static EntityPlayState _copy(
    EntityPlayState s, {
    bool? starred,
    int? rating,
    bool setRating = false,
  }) {
    return EntityPlayState(
      pid: s.pid,
      starred: starred ?? s.starred,
      starredAt: s.starredAt,
      rating: setRating ? rating : s.rating,
      updatedAt: s.updatedAt,
    );
  }
}

final entityPlayStateControllerProvider = AsyncNotifierProvider.autoDispose
    .family<EntityPlayStateController, EntityPlayState, String>(
      EntityPlayStateController.new,
    );
