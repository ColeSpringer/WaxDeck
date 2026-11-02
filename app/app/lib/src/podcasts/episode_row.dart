import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../library/item_menu.dart';
import '../player/play_progress.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'episode_actions.dart';
import 'episode_fetch.dart';

/// A row's key, so the row moves with its episode (see [indexByKey]).
Key episodeRowKey(EpisodeSummary episode) =>
    ValueKey(SemanticsIds.episode(episode.pid));

/// What the row says about [episode] under its title: its number, and
/// where its audio stands.
String episodeFacts(AppLocalizations l10n, EpisodeSummary episode) {
  final facts = <String>[
    if (episode.season != null && episode.episodeNumber != null)
      l10n.podcastSeasonEpisode(episode.season!, episode.episodeNumber!)
    else if (episode.episodeNumber != null)
      l10n.podcastEpisodeNumber(episode.episodeNumber!),
    if (episode.explicit) l10n.podcastExplicit,
    ?_audioFact(l10n, episode),
  ];
  return facts.join(' · ');
}

String? _audioFact(AppLocalizations l10n, EpisodeSummary episode) {
  final fetch = episodeFetchOf(episode);
  if (episodeFetchFact(l10n, fetch) case final fact?) return fact;
  // Said on the row rather than left to the tap: an episode this server
  // holds no bytes for still plays, relayed from the feed's own host,
  // unless the listing says there is no audio to relay. It does not say
  // why (no enclosure, a playlist, a YouTube watch page), so the words
  // hold for every cause.
  if (!episode.downloaded && !episode.hasEnclosure) {
    return l10n.podcastNoAudioToStream;
  }
  return null;
}

/// One episode in a list: the show's own, or the hub's latest.
class EpisodeRow extends ConsumerWidget {
  const EpisodeRow({
    super.key,
    required this.episode,
    this.progress = PlayProgress.none,
    this.showPid,
    this.subtitle,
    this.leadingText,
    this.artwork,
    this.selecting = false,
    this.selected = false,
    this.onSelect,
    this.viaGo = false,
  });

  final EpisodeSummary episode;
  final PlayProgress progress;

  /// The show whose listing a fetch refreshes. Null where no listing is
  /// open (the hub), so acting never builds one.
  final String? showPid;

  /// Replaces the number and explicit facts (empty says none); where the
  /// audio stands is still said after it.
  final String? subtitle;
  final String? leadingText;
  final WaxArtwork? artwork;
  final bool selecting;
  final bool selected;

  /// Null where rows cannot be selected: no checkbox, no long press.
  final ValueChanged<bool>? onSelect;

  /// Whether info `go`es to the episode (its declared parent is this
  /// screen) rather than pushing it over the screen.
  final bool viaGo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = EpisodeActions(ref: ref, showPid: showPid);
    final l10n = context.l10n;
    final select = onSelect;
    final remaining = episode.durationMs - progress.positionMs;
    final trailing = progress.inProgress && remaining > 0
        ? l10n.podcastTimeLeft(l10n.formatListenTime(remaining))
        : l10n.formatListenTime(episode.durationMs);
    final facts = subtitle == null
        ? episodeFacts(l10n, episode)
        : [
            subtitle,
            _audioFact(l10n, episode),
          ].nonNulls.where((fact) => fact.isNotEmpty).join(' · ');

    return MediaListRow(
      data: MediaTileData(
        title: episode.title,
        subtitle: facts.isEmpty ? null : facts,
        artwork: artwork,
        domain: WaxDomain.podcasts,
        progress: progress.fractionOf(episode.durationMs),
        trailingText: trailing,
        downloaded: episode.downloaded,
        unplayed: !progress.played && progress.positionMs == 0,
        semanticsId: SemanticsIds.episode(episode.pid),
      ),
      leadingText: leadingText,
      onSelect: selecting ? select : null,
      selectSemanticsId: SemanticsIds.episodeSelect(episode.pid),
      selected: selected,
      actions: <Widget>[
        ?switch (episodeFetchOf(episode)) {
          EpisodeFetchReady() || EpisodeFetchFailed() => WaxIconButton(
            glyph: WaxIcons.downloads,
            label: l10n.podcastFetchEpisode(episode.title),
            size: 18,
            semanticsId: SemanticsIds.episodeFetch(episode.pid),
            onPressed: () => unawaited(actions.fetch(context, episode.pid)),
          ),
          EpisodeFetchDone() => WaxIconButton(
            glyph: WaxIcons.offline,
            label: l10n.podcastRemoveEpisode(episode.title),
            size: 18,
            semanticsId: SemanticsIds.episodeRemove(episode.pid),
            onPressed: () =>
                unawaited(actions.removeDownload(context, episode.pid)),
          ),
          EpisodeFetchQueued() => null,
        },
        WaxIconButton(
          glyph: WaxIcons.info,
          label: l10n.podcastEpisodeDetails(episode.title),
          size: 18,
          semanticsId: SemanticsIds.episodeInfo(episode.pid),
          // The show page goes to the episode, which is declared beneath
          // it, so leaving lands back there whether the visitor tapped in
          // or opened the link cold. Anywhere else pushes: `go` would
          // rebuild the show beneath this screen and back would land
          // there rather than here.
          onPressed: () {
            final location = WaxRoute.showEpisode(episode.showPid, episode.pid);
            if (viaGo) {
              context.go(location);
            } else {
              unawaited(context.push<void>(location));
            }
          },
        ),
      ],
      // A long press selects, in a selection too, so the menu the kebab
      // and a right click open never takes it.
      onLongPress: select == null
          ? null
          : () => select(selecting ? !selected : true),
      onMore: () => unawaited(
        showItemMenuSheet(
          context,
          ref,
          pid: episode.pid,
          title: episode.title,
          mediaType: MediaType.podcast,
        ),
      ),
      moreSemanticsId: SemanticsIds.episodeMore(episode.pid),
      // The row plays, which is what a list of episodes is for. An
      // episode with no audio in its feed falls back to the fetch rather
      // than failing in the player.
      onTap: () => selecting && select != null
          ? select(!selected)
          : unawaited(
              actions.play(context, episode, positionMs: progress.positionMs),
            ),
    );
  }
}
