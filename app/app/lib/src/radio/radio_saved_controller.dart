import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import 'radio_controller.dart';

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

  /// Pids let go of while the list is open, so a page fetched before
  /// that cannot bring one back.
  final Set<String> _removed = <String>{};

  @override
  Future<RadioSavedState> build() async {
    _generation++;
    _removed.clear();
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
      // Released with its screen: a page that lands after the listener
      // left has nowhere to go.
      if (!ref.mounted || generation != _generation) return;
      // Onto the list as it is now: hearts kept and let go of while the
      // page was on its way have already changed it.
      final latest = state.value ?? current;
      final held = {for (final song in latest.songs) song.pid};
      state = AsyncData(
        RadioSavedState(
          songs: [
            ...latest.songs,
            for (final song in page.songs)
              if (!held.contains(song.pid) && !_removed.contains(song.pid))
                song,
          ],
          nextCursor: page.nextCursor,
        ),
      );
    } on WaxDeckApiException {
      // An expected transport or server error. Keep what we have;
      // scrolling near the end again retries.
      if (!ref.mounted || generation != _generation) return;
      _stopLoading();
    } catch (_) {
      // A defect rather than a hiccup: release the paging guard, or
      // paging wedges silently, then let the error through.
      if (ref.mounted && generation == _generation) _stopLoading();
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
    final at = current.songs.indexWhere((song) => song.pid == pid);
    // Read before the round trip: the list goes with its screen, and a
    // listener who removes a row and leaves is still owed the heart.
    final repository = ref.read(repositoryProvider);
    final playback = ref.read(radioPlaybackProvider.notifier);
    noteRemoved(pid);
    try {
      await repository.deleteRadioSavedSong(pid);
    } on Object {
      if (ref.mounted && generation == _generation && at >= 0) {
        _putBack(current.songs[at], at);
      }
      rethrow;
    }
    // The heart on air empties now if this was the song it held, rather
    // than on the poll a quarter-minute on.
    playback.noteUnsaved(pid);
  }

  /// A song kept elsewhere - the heart on a playing surface - goes to
  /// the top, which is where the newest-first list would put it.
  void noteSaved(RadioSavedSong song) {
    _removed.remove(song.pid);
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        songs: <RadioSavedSong>[
          song,
          ...current.songs.where((s) => s.pid != song.pid),
        ],
      ),
    );
  }

  /// A song let go of elsewhere, or here, leaves the list in place.
  void noteRemoved(String pid) {
    _removed.add(pid);
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        songs: current.songs.where((s) => s.pid != pid).toList(growable: false),
      ),
    );
  }

  void _stopLoading() {
    final latest = state.value;
    if (latest != null) state = AsyncData(latest.copyWith(loadingMore: false));
  }

  /// A row a failed delete owes back, where it stood, into the list as
  /// it is now rather than as it was before the round trip.
  void _putBack(RadioSavedSong song, int at) {
    _removed.remove(song.pid);
    final latest = state.value;
    if (latest == null || latest.songs.any((s) => s.pid == song.pid)) return;
    final songs = [...latest.songs]
      ..insert(math.min(at, latest.songs.length), song);
    state = AsyncData(latest.copyWith(songs: songs));
  }
}

/// Released with the screen that reads it, so opening the list again
/// reads it again: a song kept on another device otherwise showed up
/// only after a restart.
final radioSavedProvider =
    AsyncNotifierProvider.autoDispose<RadioSavedController, RadioSavedState>(
      RadioSavedController.new,
    );
