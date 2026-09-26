import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../l10n/l10n.dart';
import '../player/now_playing_controller.dart';
import '../providers.dart';
import '../queue/queue_state.dart';
import '../shell/shell_messages.dart';
import 'playlists_controller.dart';

/// Plays a playlist's members into the dock, as the playlist. The
/// playlist screen's buttons and a card's play affordance both end here.
void playPlaylist(WidgetRef ref, PlaylistView view, {bool shuffle = false}) =>
    _playPlaylist(ref.read(nowPlayingProvider.notifier), view, shuffle);

/// Plays playlist [pid] from its card alone, through the read its own
/// screen makes. Straight from the repository: the provider's backoff
/// would hold a failure for seconds with nothing said.
Future<void> playPlaylistPid(
  WidgetRef ref,
  String pid, {
  bool shuffle = false,
}) async {
  // Read before the await, for the reason [playAlbumPid] does.
  final repository = ref.read(repositoryProvider);
  final playback = ref.read(nowPlayingProvider.notifier);
  final messenger = ref.read(shellMessengerProvider.notifier);
  try {
    // In order the queue keeps only its first [kQueueCap], so one page
    // starts it; a shuffle draws from the whole list.
    final view = shuffle
        ? await fetchPlaylistView(repository, pid)
        : PlaylistView(
            playlist: await repository.getPlaylist(pid),
            entries: (await repository.listPlaylistItems(
              pid,
              limit: kQueueCap,
            )).entries,
          );
    _playPlaylist(playback, view, shuffle);
  } on WaxDeckApiException catch (error) {
    messenger.showLocalized((l10n) => explainError(l10n, error));
  }
}

void _playPlaylist(
  NowPlayingController playback,
  PlaylistView view,
  bool shuffle,
) {
  if (view.entries.isEmpty) return;
  playback.play(
    <ItemSummary>[for (final entry in view.entries) entry.item],
    shuffle: shuffle,
    source: QueueSource(
      kind: QueueSourceKind.playlist,
      label: view.playlist.name,
      pid: view.playlist.pid,
    ),
  );
}
