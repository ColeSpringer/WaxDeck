import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../player/now_playing_controller.dart';
import '../player/play_progress.dart';
import '../providers.dart';
import '../queue/queue_state.dart';
import '../shell/routes.dart';
import 'podcasts_controller.dart';

/// The verbs an episode has, wherever it is shown.
///
/// One place rather than three: the show's list, the episode's own
/// screen, and anything that grows one later all have to agree about
/// what "play" means for an episode that is not on this server, and a
/// second copy of that rule is how the two surfaces come to disagree.
class EpisodeActions {
  const EpisodeActions({required this.ref, this.showPid});

  final WidgetRef ref;

  /// The show whose listing this is acting on, when there is one, so a
  /// fetch can refresh the rows that show its state.
  final String? showPid;

  void _report(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Whether this server can put audio on the wire for [episode] right
  /// now.
  ///
  /// `downloaded` stopped answering this when enclosure passthrough
  /// landed: an episode nobody fetched still plays, relayed from the
  /// feed's own host. What fetching adds is local bytes and the analysis
  /// that rides them (silence trim, voice boost, the skip map), so it
  /// is worth offering and is no longer the gate. The one episode that
  /// cannot play at all is undownloaded with no enclosure, which is the
  /// only case the fetch-wait path is still for.
  static bool playable(EpisodeSummary episode) =>
      episode.downloaded || episode.hasEnclosure;

  /// Plays one episode, from [positionMs] when it was started before.
  ///
  /// One episode, never the feed: an episode is a thing on its own, and
  /// a show is not an album.
  Future<void> play(
    BuildContext context,
    EpisodeSummary episode, {
    int positionMs = 0,
  }) async {
    if (!playable(episode)) {
      await fetchAndWait(context, episode);
      return;
    }
    unawaitedPlay(episode, positionMs: positionMs);
    context.push(WaxRoute.nowPlaying);
  }

  /// The queue write on its own, for a caller that is not navigating.
  void unawaitedPlay(EpisodeSummary episode, {int positionMs = 0}) {
    ref
        .read(nowPlayingProvider.notifier)
        .play(
          <ItemSummary>[episode],
          source: QueueSource(
            kind: QueueSourceKind.single,
            label: episode.title,
            pid: episode.pid,
          ),
          positionMs: positionMs > 0 ? positionMs : null,
        );
  }

  /// Appends the episode to whatever is playing.
  void enqueue(BuildContext context, EpisodeSummary episode) {
    if (!playable(episode)) {
      _report(
        context,
        'This feed named no audio for that episode, so there is nothing '
        'to queue.',
      );
      return;
    }
    ref.read(nowPlayingProvider.notifier).enqueue(<ItemSummary>[episode]);
    _report(context, 'Added to the queue');
  }

  /// Queues a server-side fetch.
  Future<void> fetch(BuildContext context, String pid) async {
    try {
      await _fetch(pid);
      if (context.mounted) _report(context, 'Fetching to server');
    } on WaxDeckApiException catch (e) {
      if (context.mounted) _report(context, e.message);
    }
  }

  /// The fallback for an episode whose feed named no enclosure: there is
  /// nothing to relay, so the server has to hold the bytes before anyone
  /// can hear it. The row flips to downloaded when the worker lands it,
  /// driven by the same invalidation every other listing follows.
  Future<void> fetchAndWait(
    BuildContext context,
    EpisodeSummary episode,
  ) async {
    try {
      await _fetch(episode.pid);
      if (context.mounted) {
        _report(
          context,
          'This feed named no audio to stream, so the server is fetching '
          'it. It plays once that lands.',
        );
      }
    } on WaxDeckApiException catch (e) {
      if (context.mounted) _report(context, e.message);
    }
  }

  Future<void> removeDownload(BuildContext context, String pid) async {
    try {
      if (showPid != null) {
        await ref
            .read(episodesProvider(showPid!).notifier)
            .removeEpisodeDownload(pid);
      } else {
        await ref.read(repositoryProvider).removeEpisodeDownload(pid);
      }
      ref.invalidate(episodeDetailProvider(pid));
      if (context.mounted) {
        _report(context, 'Removed from server; your progress is kept');
      }
    } on WaxDeckApiException catch (e) {
      if (context.mounted) _report(context, e.message);
    }
  }

  /// Records the episode as played by checkpointing at its full
  /// duration, which is the only way to say it: played is derived
  /// server-side from the position reached.
  Future<void> markPlayed(
    BuildContext context,
    EpisodeSummary episode,
    String progressKey,
  ) async {
    try {
      final done = await ref
          .read(playProgressProvider(progressKey).notifier)
          .markPlayed(episode.pid, episode.durationMs);
      if (!context.mounted) return;
      _report(
        context,
        done
            ? 'Marked as played'
            : 'This feed declared no duration, so there is no position that '
                  'means finished. Fetching the episode gives it one.',
      );
    } on WaxDeckApiException catch (e) {
      if (context.mounted) _report(context, e.message);
    }
  }

  /// Queues the fetch through the listing when this is acting inside one,
  /// so the row behind the surface on top flips to queued with it, and
  /// straight through the repository when it is not. An episode opened
  /// by a bare link has no listing to keep in step.
  Future<void> _fetch(String pid) async {
    final show = showPid;
    if (show != null) {
      await ref.read(episodesProvider(show).notifier).fetchEpisode(pid);
    } else {
      await ref.read(repositoryProvider).fetchEpisode(pid);
    }
    ref.invalidate(episodeDetailProvider(pid));
  }
}
