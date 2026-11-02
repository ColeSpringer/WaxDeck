import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../shell/semantics_ids.dart';

/// Where the server stands on fetching an episode's audio.
///
/// A server fetch has a queue and no fraction, so it is its own small
/// state rather than the device's download state.
sealed class EpisodeFetch {
  const EpisodeFetch();

  /// Not held and not asked for.
  const factory EpisodeFetch.ready() = EpisodeFetchReady;

  /// Asked for and not landed yet.
  const factory EpisodeFetch.queued() = EpisodeFetchQueued;

  /// The last attempt gave up, for [EpisodeFetchFailed.reason] when the
  /// server said.
  const factory EpisodeFetch.failed(String? reason) = EpisodeFetchFailed;

  /// The server holds the audio.
  const factory EpisodeFetch.done() = EpisodeFetchDone;
}

final class EpisodeFetchReady extends EpisodeFetch {
  const EpisodeFetchReady();
}

final class EpisodeFetchQueued extends EpisodeFetch {
  const EpisodeFetchQueued();
}

final class EpisodeFetchFailed extends EpisodeFetch {
  const EpisodeFetchFailed(this.reason);

  final String? reason;
}

final class EpisodeFetchDone extends EpisodeFetch {
  const EpisodeFetchDone();
}

/// [episode]'s fetch. The server's states are an open set, so any value
/// but `failed` is a fetch in the queue.
EpisodeFetch episodeFetchOf(EpisodeSummary episode) {
  if (episode.downloaded) return const EpisodeFetch.done();
  return switch (episode.fetchState) {
    null => const EpisodeFetch.ready(),
    'failed' => EpisodeFetch.failed(episode.fetchError),
    _ => const EpisodeFetch.queued(),
  };
}

/// [fetch] as the one pill of an entity's action bar. The four states
/// share a slot, so the pill keeps its place through each flip.
WaxAction episodeFetchWaxAction(
  AppLocalizations l10n,
  String pid,
  EpisodeFetch fetch, {
  required VoidCallback onFetch,
  required VoidCallback onRemove,
}) {
  final fetchId = SemanticsIds.episodeFetch(pid);
  return switch (fetch) {
    EpisodeFetchReady() => WaxAction(
      label: l10n.podcastDownload,
      semanticsId: fetchId,
      slot: pid,
      glyph: WaxIcons.downloads,
      onPressed: onFetch,
    ),
    EpisodeFetchQueued() => WaxAction(
      label: l10n.podcastQueuedForDownload,
      semanticsId: fetchId,
      slot: pid,
      glyph: WaxIcons.clock,
      state: const WaxActionState.status(),
    ),
    EpisodeFetchFailed(:final reason) => WaxAction(
      label: l10n.downloadsActionRetry,
      semanticsId: fetchId,
      slot: pid,
      glyph: WaxIcons.downloads,
      state: const WaxActionState.failed(),
      detail: reason == null ? null : l10n.podcastFetchFailed(reason),
      onPressed: onFetch,
    ),
    EpisodeFetchDone() => WaxAction(
      label: l10n.podcastRemoveDownload,
      semanticsId: SemanticsIds.episodeRemove(pid),
      slot: pid,
      glyph: WaxIcons.offline,
      state: const WaxActionState.done(),
      onPressed: onRemove,
    ),
  };
}

/// What a row says about [fetch] beside the episode's facts, if anything.
String? episodeFetchFact(AppLocalizations l10n, EpisodeFetch fetch) =>
    switch (fetch) {
      EpisodeFetchFailed() => l10n.podcastDownloadFailed,
      EpisodeFetchQueued() => l10n.podcastQueuedForDownload,
      EpisodeFetchReady() || EpisodeFetchDone() => null,
    };
