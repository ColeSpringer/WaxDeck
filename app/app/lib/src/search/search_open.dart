import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart'
    show BuildContext, WaxGlyph, WaxIcons;

import '../music/music_controllers.dart';
import '../player/now_playing_controller.dart';
import '../queue/queue_state.dart';
import '../shell/routes.dart';

/// Opens what a search hit names, for the search screen and the palette
/// alike.
///
/// Pushed, never gone to: every one of these is declared under something
/// that is not search, so `go` would rebuild that ancestry and throw away
/// the surface the visitor is standing in (ADR-0022, ADR-0032). A kind
/// this build does not know does nothing rather than being played as a
/// track.
void openSearchHit(BuildContext context, WidgetRef ref, SearchHit hit) {
  switch (hit.kind) {
    case 'artist':
      context.push(WaxRoute.musicBucket(MusicDimension.artists, hit.pid));
    case 'album':
      context.push(WaxRoute.musicBucket(MusicDimension.albums, hit.pid));
    case 'book':
      context.push(WaxRoute.book(hit.pid));
    case 'episode':
      context.push(WaxRoute.episode(hit.pid));
    case 'track':
      // One item with no list around it: the rows either side are albums
      // and shows, not a queue.
      ref.read(nowPlayingProvider.notifier).playPids(
        <String>[hit.pid],
        source: QueueSource(
          kind: QueueSourceKind.search,
          label: hit.title,
          pid: hit.pid,
        ),
      );
      context.push(WaxRoute.nowPlaying);
  }
}

WaxGlyph searchHitGlyph(String kind) => switch (kind) {
  'artist' => WaxIcons.artists,
  'album' => WaxIcons.albums,
  'book' => WaxIcons.audiobooks,
  'episode' => WaxIcons.podcasts,
  _ => WaxIcons.music,
};
