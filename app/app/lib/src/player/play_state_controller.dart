import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';

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
  Future<PlayState> build() => ref.watch(repositoryProvider).getPlayState(pid);

  Future<void> setStarred(bool starred) => _mutate(
    optimistic: (s) => _copy(s, starred: starred),
    call: () => ref.read(repositoryProvider).setStar(pid, starred),
  );

  /// Rates the item 0 to 100, or clears the rating with null.
  Future<void> rate(int? rating) => _mutate(
    optimistic: (s) => _copy(s, rating: rating, setRating: true),
    call: () => ref.read(repositoryProvider).setRating(pid, rating),
  );

  Future<void> _mutate({
    required PlayState Function(PlayState) optimistic,
    required Future<PlayState> Function() call,
  }) async {
    final previous = state;
    final current = state.value;
    if (current != null) {
      state = AsyncData(optimistic(current));
    }
    try {
      state = AsyncData(await call());
    } on WaxDeckApiException catch (e, st) {
      // Emit the failure so listeners can tell the user, then restore
      // the pre-tap state in the same turn; widgets only ever render
      // the rolled-back data.
      state = AsyncError<PlayState>(e, st);
      state = previous;
    }
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

final playStateControllerProvider =
    AsyncNotifierProvider.family<PlayStateController, PlayState, String>(
      PlayStateController.new,
    );
