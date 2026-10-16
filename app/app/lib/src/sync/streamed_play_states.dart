import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../auth/auth_controller.dart';
import '../player/play_progress.dart';
import '../recency_map.dart';

/// The newest play state the user stream reported for each item this
/// session.
///
/// The sync binder records every report here and asks whether it moved
/// more than the position: a player checkpoints every few seconds, and
/// refetching every user surface for each one is what kept an open home
/// busy. The shelves that read positions with their rows draw a newer
/// one from here, which is how a ring moves without its shelf being
/// read again.
class StreamedPlayStates extends Notifier<Map<String, PlayState>> {
  /// How many items it holds. Past this the oldest goes, and its next
  /// report reads as a first sighting.
  static const capacity = 500;

  @override
  Map<String, PlayState> build() {
    // One account's positions are not another's.
    ref.watch(signedInAccountProvider);
    return const <String, PlayState>{};
  }

  /// Records [next] and answers whether it moved more than the position.
  bool record(PlayState next) {
    final before = state[next.pid];
    // In the order of the latest reports, so the oldest is first to go.
    state = <String, PlayState>{...state}
      ..putNewest(next.pid, next, capacity: capacity);
    return movesMoreThanPosition(before, next);
  }
}

final streamedPlayStatesProvider =
    NotifierProvider.autoDispose<StreamedPlayStates, Map<String, PlayState>>(
      StreamedPlayStates.new,
    );

/// Whether [after] moved anything a list is chosen by, against [before]
/// as the stream last reported it.
///
/// A first sighting does: it can put the item on a shelf. So does a
/// position that starts an item or takes it back to the top, which puts
/// it on a resume shelf or takes it off. A position that only moves on
/// moves rings, and the rings take it without a read.
bool movesMoreThanPosition(PlayState? before, PlayState after) =>
    before == null ||
    before.finished != after.finished ||
    before.played != after.played ||
    before.playCount != after.playCount ||
    before.starred != after.starred ||
    before.rating != after.rating ||
    before.lastPlayedAt != after.lastPlayedAt ||
    (before.positionMs > 0) != (after.positionMs > 0);

/// [held] unless the stream has reported a newer state for the item.
///
/// Newer by the server's own stamp, so a shelf read after the report
/// keeps what it read. A held position with no stamp is one the server
/// never stored, which any report supersedes.
PlayProgress newerProgress(PlayProgress held, PlayState? streamed) {
  if (streamed == null) return held;
  final heldAt = held.updatedAt;
  final streamedAt = streamed.updatedAt;
  if (heldAt != null && (streamedAt == null || !streamedAt.isAfter(heldAt))) {
    return held;
  }
  return PlayProgress.of(streamed);
}
