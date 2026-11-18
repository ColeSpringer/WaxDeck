import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../player/now_playing_controller.dart';
import '../player/play_progress.dart';
import '../providers.dart';
import '../queue/queue_state.dart';
import '../shell/pending_actions.dart';
import '../shell/shell_messages.dart';
import 'podcast_shelves.dart';
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

  static void _report(ShellMessenger messenger, String message) =>
      messenger.show(message, channel: ShellChannel.episodes);

  /// What a verb that awaits reads before it does: the container, which
  /// outlives the row or screen that asked, and the messenger its answer
  /// is said through, wherever the visitor has gone by then.
  static ({ProviderContainer container, ShellMessenger messenger}) _asked(
    BuildContext context,
  ) {
    final container = ProviderScope.containerOf(context, listen: false);
    return (
      container: container,
      messenger: container.read(shellMessengerProvider),
    );
  }

  /// Whether this server can put audio on the wire for [episode] right
  /// now.
  ///
  /// `downloaded` stopped answering this when enclosure passthrough
  /// landed: an episode nobody fetched still plays, relayed from the
  /// feed's own host. What fetching adds is local bytes and the analysis
  /// that rides them (silence trim, voice boost, the skip map), so it
  /// is worth offering and is no longer the gate. The episodes that
  /// cannot play at all are undownloaded with no enclosure the server
  /// relays - none in the feed, or a YouTube show's watch page - which
  /// are the only cases the fetch-wait path is still for.
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
    playOn(
      ref.read(nowPlayingProvider.notifier),
      episode,
      positionMs: positionMs > 0 ? positionMs : null,
    );
  }

  /// [play]'s queue write, for a caller holding the controller rather
  /// than a live ref. A null [positionMs] resumes the checkpoint.
  static void playOn(
    NowPlayingController playback,
    EpisodeSummary episode, {
    int? positionMs,
  }) => playback.play(
    <ItemSummary>[episode],
    source: QueueSource(
      kind: QueueSourceKind.single,
      label: episode.title,
      pid: episode.pid,
    ),
    positionMs: positionMs,
  );

  /// Appends the episode to whatever is playing.
  void enqueue(BuildContext context, EpisodeSummary episode) {
    final messenger = ref.read(shellMessengerProvider);
    if (!playable(episode)) {
      _report(messenger, context.l10n.podcastNoAudioToQueue);
      return;
    }
    ref.read(nowPlayingProvider.notifier).enqueue(<ItemSummary>[episode]);
    _report(messenger, context.l10n.podcastAddedToQueue);
  }

  /// Queues a server-side fetch.
  Future<void> fetch(BuildContext context, EpisodeSummary episode) async {
    // Read before the await, like every other table this class needs:
    // the request outlives the frame that asked for it.
    final l10n = context.l10n;
    final (:container, :messenger) = _asked(context);
    try {
      await _fetch(container, episode);
      _report(messenger, l10n.podcastFetchingToServer);
    } on WaxDeckApiException catch (e) {
      _report(messenger, explainError(l10n, e));
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
    final l10n = context.l10n;
    final (:container, :messenger) = _asked(context);
    try {
      await _fetch(container, episode);
      _report(messenger, l10n.podcastFetchingBeforePlay);
    } on WaxDeckApiException catch (e) {
      _report(messenger, explainError(l10n, e));
    }
  }

  Future<void> removeDownload(
    BuildContext context,
    EpisodeSummary episode,
  ) async {
    final l10n = context.l10n;
    final (:container, :messenger) = _asked(context);
    final pid = episode.pid;
    try {
      if (showPid != null) {
        await container
            .read(episodesProvider(showPid!).notifier)
            .removeEpisodeDownload(pid);
      } else {
        await container.read(repositoryProvider).removeEpisodeDownload(pid);
      }
      _refreshOthers(container, episode);
      _report(messenger, l10n.podcastRemovedFromServer);
    } on WaxDeckApiException catch (e) {
      _report(messenger, explainError(l10n, e));
    }
  }

  /// Records the episode as played by checkpointing at its full
  /// duration, which is the only way to say it: played is derived
  /// server-side from the position reached.
  ///
  /// Pending under [PendingAction.markPlayed] while the write is out, so
  /// its control draws busy and a second press is dropped.
  Future<void> markPlayed(
    BuildContext context,
    EpisodeSummary episode,
    String progressKey,
  ) async {
    final l10n = context.l10n;
    final (:container, :messenger) = _asked(context);
    bool? done;
    try {
      await container.read(pendingActionsProvider.notifier).run(
        PendingAction.markPlayed(episode.pid),
        () async {
          done = await container
              .read(playProgressProvider(progressKey).notifier)
              .markPlayed(episode.pid, episode.durationMs);
        },
      );
      final marked = done;
      if (marked == null) return;
      _report(
        messenger,
        marked ? l10n.podcastMarkedAsPlayed : l10n.podcastNoDurationToFinish,
      );
    } on WaxDeckApiException catch (e) {
      _report(messenger, explainError(l10n, e));
    }
  }

  /// Queues the fetch through the listing when this is acting inside one,
  /// so the row behind the surface on top flips to queued with it, and
  /// straight through the repository when it is not. An episode opened
  /// by a bare link has no listing to keep in step.
  Future<void> _fetch(
    ProviderContainer container,
    EpisodeSummary episode,
  ) async {
    final show = showPid;
    if (show != null) {
      await container
          .read(episodesProvider(show).notifier)
          .fetchEpisode(episode.pid);
    } else {
      await container.read(repositoryProvider).fetchEpisode(episode.pid);
    }
    _refreshOthers(container, episode);
  }

  /// Re-reads the other surfaces that list the episode, since queuing a
  /// fetch sends no catalog event: the hub's shelves and the episode's
  /// detail always, and the show's listing when this acted outside it.
  /// An invalidation builds nothing that was never read.
  void _refreshOthers(ProviderContainer container, EpisodeSummary episode) {
    container
      ..invalidate(latestEpisodesProvider)
      ..invalidate(upNextEpisodesProvider)
      ..invalidate(episodeDetailProvider(episode.pid));
    if (showPid == null) {
      container.invalidate(episodesProvider(episode.showPid));
    }
  }
}
