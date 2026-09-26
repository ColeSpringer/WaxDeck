import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../l10n/l10n.dart';
import '../player/now_playing_controller.dart';
import '../providers.dart';
import '../queue/queue_drag.dart';
import '../queue/queue_state.dart';
import '../shell/shell_messages.dart';
import 'entity_facts.dart';
import 'music_controllers.dart';

/// Plays an album's [tracks] into the dock, as the album. The album
/// screen's buttons and a release card's play affordance both end here.
void playAlbum(
  WidgetRef ref, {
  required String pid,
  required String title,
  required List<ItemSummary> tracks,
  bool shuffle = false,
}) => _playAlbum(
  ref.read(nowPlayingProvider.notifier),
  pid: pid,
  title: title,
  tracks: tracks,
  shuffle: shuffle,
);

/// Plays album [pid] from its cover alone: the tracks are read the way a
/// queue drop reads a bucket, then put in pressing order. [label] is the
/// name the card showed, which the queue carries; the first tag stands in.
Future<void> playAlbumPid(
  WidgetRef ref,
  String pid, {
  String? label,
  bool shuffle = false,
}) async {
  // Read before the await: the card may be gone when the tracks land,
  // and the play is honoured anyway.
  final repository = ref.read(repositoryProvider);
  final playback = ref.read(nowPlayingProvider.notifier);
  final messenger = ref.read(shellMessengerProvider.notifier);
  try {
    final tracks = albumOrder(
      await bucketItems(
        repository,
        facet: MusicDimension.albums.wireName,
        facetKey: musicFacetKey(MusicDimension.albums, pid),
      ),
    );
    _playAlbum(
      playback,
      pid: pid,
      title: label ?? tracks.firstOrNull?.album ?? '',
      tracks: tracks,
      shuffle: shuffle,
    );
  } on WaxDeckApiException catch (error) {
    messenger.showLocalized((l10n) => explainError(l10n, error));
  }
}

void _playAlbum(
  NowPlayingController playback, {
  required String pid,
  required String title,
  required List<ItemSummary> tracks,
  required bool shuffle,
}) {
  if (tracks.isEmpty) return;
  playback.play(
    tracks,
    shuffle: shuffle,
    source: QueueSource(kind: QueueSourceKind.album, label: title, pid: pid),
  );
}
