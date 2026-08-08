import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';

/// Accumulated pages of songs kept off the air.
class RadioSavedState {
  const RadioSavedState({
    required this.songs,
    this.nextCursor,
    this.loadingMore = false,
  });

  final List<RadioSavedSong> songs;
  final String? nextCursor;
  final bool loadingMore;

  bool get hasMore => nextCursor != null;

  RadioSavedState copyWith({List<RadioSavedSong>? songs, bool? loadingMore}) =>
      RadioSavedState(
        songs: songs ?? this.songs,
        nextCursor: nextCursor,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

/// Pages the caller's saved songs, newest first, and drops them.
class RadioSavedController extends AsyncNotifier<RadioSavedState> {
  static const pageSize = 50;

  var _generation = 0;

  @override
  Future<RadioSavedState> build() async {
    _generation++;
    final page = await ref
        .watch(repositoryProvider)
        .listRadioSavedSongs(limit: pageSize);
    return RadioSavedState(songs: page.songs, nextCursor: page.nextCursor);
  }

  /// Fetches the next page and appends it. No-op while a fetch is
  /// running or once the last page was reached.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final generation = _generation;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref
          .read(repositoryProvider)
          .listRadioSavedSongs(cursor: current.nextCursor, limit: pageSize);
      if (generation != _generation) return;
      state = AsyncData(
        RadioSavedState(
          songs: [...current.songs, ...page.songs],
          nextCursor: page.nextCursor,
        ),
      );
    } on WaxDeckApiException {
      // An expected transport or server error. Keep what we have;
      // scrolling near the end again retries.
      if (generation != _generation) return;
      state = AsyncData(current.copyWith(loadingMore: false));
    } catch (_) {
      // Anything else is a defect rather than a hiccup. Release the
      // paging guard first, or leaving it set wedges paging silently,
      // then let the error reach the zone's handler.
      if (generation == _generation) {
        state = AsyncData(current.copyWith(loadingMore: false));
      }
      rethrow;
    }
  }

  /// Drops one song. The row leaves the list first: removing a row is
  /// the one thing on this screen a listener is certain about, and a
  /// list that waited a round trip to agree reads as a dead tap. A
  /// failure puts it back and the caller surfaces the message.
  Future<void> remove(String pid) async {
    final current = state.value;
    if (current == null) return;
    final generation = _generation;
    state = AsyncData(
      current.copyWith(
        songs: current.songs.where((s) => s.pid != pid).toList(growable: false),
      ),
    );
    try {
      await ref.read(repositoryProvider).deleteRadioSavedSong(pid);
    } on Object {
      if (generation == _generation) state = AsyncData(current);
      rethrow;
    }
  }
}

final radioSavedProvider =
    AsyncNotifierProvider<RadioSavedController, RadioSavedState>(
      RadioSavedController.new,
    );
