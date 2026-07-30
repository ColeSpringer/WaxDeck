import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../player/play_progress.dart';
import '../providers.dart';

/// One row of a hub shelf: an episode of a followed show with the
/// caller's position beside it.
class ShelfEpisode {
  const ShelfEpisode({required this.episode, required this.progress});

  final EpisodeSummary episode;
  final PlayProgress progress;

  /// The show, as the row names it.
  String? get showTitle => episode.artist ?? episode.album;
}

/// How many rows a shelf shows.
const int kShelfRows = 12;

/// Reads one cross-show episode listing and hangs the caller's position
/// off each row.
///
/// The listing is the podcast domain's own (`GET /podcasts/episodes`),
/// not a discovery list sifted for episodes: those are over the whole
/// library and answer generic summary rows, so a hub built on them pays
/// for a music collection it is not asking about and gets rows carrying
/// neither `showPid` nor `hasEnclosure`, the two fields that decide
/// where a row links and whether it can offer to play at all.
///
/// Both shelves are `autoDispose`: they belong to the hub, and a read
/// held past it is a stale answer nobody is looking at.
/// [withProgress] asks for the caller's positions alongside the rows. Only
/// the strip that draws a resume ring needs them; the strip of what is
/// new is unplayed by construction, so reading positions for it would be
/// a round trip spent confirming a row of zeroes.
Future<List<ShelfEpisode>> _shelf(
  Ref ref,
  SubscribedEpisodes filter, {
  bool withProgress = false,
}) async {
  final repository = ref.watch(repositoryProvider);
  final page = await repository.listSubscribedEpisodes(
    filter: filter,
    limit: kShelfRows,
  );
  if (page.items.isEmpty) return const <ShelfEpisode>[];
  if (!withProgress) {
    return <ShelfEpisode>[
      for (final episode in page.items)
        ShelfEpisode(episode: episode, progress: PlayProgress.none),
    ];
  }
  final states = await repository.listPlayStates([
    for (final episode in page.items) episode.pid,
  ]);
  final byPid = <String, PlayProgress>{
    for (final state in states)
      state.pid: PlayProgress(
        positionMs: state.positionMs,
        played: state.played,
        finished: state.finished,
      ),
  };
  return <ShelfEpisode>[
    for (final episode in page.items)
      ShelfEpisode(
        episode: episode,
        progress: byPid[episode.pid] ?? PlayProgress.none,
      ),
  ];
}

/// Episodes the caller started and has not finished, most recently
/// played first: the strip that answers "where was I".
final upNextEpisodesProvider = FutureProvider.autoDispose<List<ShelfEpisode>>(
  (ref) => _shelf(ref, SubscribedEpisodes.inProgress, withProgress: true),
);

/// The newest episodes across the caller's subscriptions that they have
/// not heard.
final latestEpisodesProvider = FutureProvider.autoDispose<List<ShelfEpisode>>(
  (ref) => _shelf(ref, SubscribedEpisodes.unplayed),
);
