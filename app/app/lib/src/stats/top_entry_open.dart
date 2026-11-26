import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart' show BuildContext;

import '../books/book_dimension.dart';
import '../music/genre_open.dart';
import '../music/music_controllers.dart';
import '../player/now_playing_controller.dart';
import '../queue/queue_state.dart';
import '../shell/routes.dart';

/// Whether a ranked [entry] of a [kind] list names something to open. An
/// entry whose item has left has no name, and one grouped by a name alone
/// has no pid; a genre is found by its name, so it needs none.
bool canOpenTopEntry(TopEntry entry, String kind) =>
    entry.name.isNotEmpty &&
    switch (kind) {
      'genres' => true,
      'artists' ||
      'albums' ||
      'authors' ||
      'books' ||
      'shows' ||
      'episodes' ||
      'tracks' ||
      'stations' => entry.pid != null && entry.pid!.isNotEmpty,
      _ => false,
    };

/// Opens what a ranked entry names, on the stats page and in the recaps.
///
/// The arms that navigate push, as a search hit's do: each destination is
/// declared under something that is not stats. A track plays where the
/// visitor stands, and a station goes to radio, a place of its own in the
/// chrome.
void openTopEntry(
  BuildContext context,
  WidgetRef ref,
  TopEntry entry,
  String kind,
) {
  if (!canOpenTopEntry(entry, kind)) return;
  final pid = entry.pid ?? '';
  switch (kind) {
    // The entry's name is the entity's own, the one thing the destination
    // cannot work out from the items it loads.
    case 'artists':
      context.push(
        WaxRoute.musicBucket(MusicDimension.artists, pid),
        extra: entry.name,
      );
    case 'albums':
      context.push(
        WaxRoute.musicBucket(MusicDimension.albums, pid),
        extra: entry.name,
      );
    case 'authors':
      context.push(
        WaxRoute.bookBucket(BookDimension.authors, pid),
        extra: entry.name,
      );
    case 'books':
      context.push(WaxRoute.book(pid));
    case 'shows':
      context.push(WaxRoute.show(pid));
    case 'episodes':
      context.push(WaxRoute.episode(pid));
    case 'tracks':
      unawaited(
        ref.read(nowPlayingProvider.notifier).playPids(
          <String>[pid],
          source: QueueSource(
            kind: QueueSourceKind.single,
            label: entry.name,
            pid: pid,
          ),
        ),
      );
    case 'genres':
      unawaited(openGenreByLabel(context, ref, entry.name));
    case 'stations':
      context.go(WaxRoute.radio);
  }
}
