import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../l10n/l10n.dart';
import '../player/play_progress.dart';
import '../player/session_registry.dart';
import '../providers.dart';
import '../search/search_chrome.dart';
import '../sharing/share_dialog.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'credits.dart';
import 'episode_actions.dart';
import 'podcasts_controller.dart';
import 'show_screen.dart';

/// A cue's offset into its episode, as a readout: `4:05`, `1:02:41`.
///
/// The design system's own timecode, taking the milliseconds every cue
/// carries. Its own name because that is what the call sites read as -
/// a cue points at a moment, not at a length.
String formatCueTimestamp(int ms) => formatTimecode(Duration(milliseconds: ms));

/// What a timestamp points at. The names are `podcastCueStartsAt`'s
/// select cases, so the sentence is worded per kind rather than built
/// around the word.
enum PodcastCue { chapter, clip, cue }

/// Seeks the live player to [ms] when [pid] is the episode loaded, and
/// reports the offset otherwise: the timestamp stays useful when this
/// episode is not the one playing.
void seekLiveOrReport(
  BuildContext context,
  WidgetRef ref,
  String pid,
  int ms,
  PodcastCue kind,
) {
  final session = ref.read(currentSessionRegistryProvider).current;
  if (session != null && session.item.pid == pid) {
    session.seek(Duration(milliseconds: ms));
    return;
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.podcastCueStartsAt(kind.name, formatCueTimestamp(ms)),
        ),
      ),
    );
}

/// One episode: what it is, what can be done with it, and everything the
/// feed said about it.
class EpisodeScreen extends ConsumerWidget {
  const EpisodeScreen({super.key, required this.pid, this.showPid});

  final String pid;

  /// The show in the location, when the caller had one. Absent on the
  /// show-less location a search hit opens, where there is no ancestry
  /// to go back to and the hub is the nearest real place.
  final String? showPid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(episodeDetailProvider(pid));
    final episode = detail.value;
    final l10n = context.l10n;

    return WaxScaffold(
      title: episode?.title ?? l10n.podcastEpisodeFallbackTitle,
      largeTitle: false,
      // Pops when something pushed this and goes to the show it belongs
      // to when nothing did, so the arrow and the system gesture agree
      // from either entry point. Without a show in the location there is
      // nothing above but the hub: the detail that would name one has
      // not answered yet when the button is first there to press.
      onBack: () => context.leave(
        fallback: showPid == null ? WaxRoute.podcasts : WaxRoute.show(showPid!),
      ),
      actions: const <Widget>[SearchAction()],
      slivers: <Widget>[
        switch (detail) {
          AsyncData(:final value) => SliverToBoxAdapter(
            child: _EpisodeBody(episode: value, showPid: showPid),
          ),
          AsyncError(:final error) => SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(
              title: l10n.podcastEpisodeLoadError,
              message: context.explain(error),
              onRetry: () => ref.invalidate(episodeDetailProvider(pid)),
            ),
          ),
          _ => const SliverFillRemaining(
            hasScrollBody: false,
            child: SkeletonShapes(shape: SkeletonShape.detail),
          ),
        },
      ],
    );
  }
}

class _EpisodeBody extends ConsumerWidget {
  const _EpisodeBody({required this.episode, this.showPid});

  final EpisodeDetail episode;
  final String? showPid;

  /// This episode alone, as the progress family keys it: one row's worth
  /// of the same batch read the show's list uses, so a position written
  /// here and one written there land in the same shape of state.
  String get _progressKey => playPidsKey(<String>[episode.pid]);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final progress = PlayProgressView(
      ref.watch(playProgressProvider(_progressKey)).value ?? const {},
    )[episode.pid];
    final gutter = EdgeInsets.symmetric(
      horizontal: sizeClass.gutter.horizontal / 2,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Hero(episode: episode, showPid: showPid),
        Padding(
          padding: gutter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: WaxSpace.s16),
              _ActionBar(
                episode: episode,
                showPid: showPid,
                progress: progress,
                progressKey: _progressKey,
              ),
              if (episode.descriptionHtml?.isNotEmpty ?? false) ...<Widget>[
                const SizedBox(height: WaxSpace.s24),
                Semantics(
                  identifier: SemanticsIds.episodeSection('notes'),
                  child: SectionHeader(title: l10n.podcastSectionNotes),
                ),
                CollapsibleNotes(
                  html: episode.descriptionHtml!,
                  collapsedTo: 220,
                ),
              ],
              if (episode.chapters.isNotEmpty) ...<Widget>[
                const SizedBox(height: WaxSpace.s24),
                Semantics(
                  identifier: SemanticsIds.episodeSection('chapters'),
                  child: SectionHeader(title: l10n.podcastSectionChapters),
                ),
                for (final chapter in episode.chapters)
                  _CueRow(
                    stamp: formatCueTimestamp(chapter.startMs),
                    text:
                        chapter.title ??
                        l10n.podcastChapterFallback(chapter.index + 1),
                    onTap: () => seekLiveOrReport(
                      context,
                      ref,
                      episode.pid,
                      chapter.startMs,
                      PodcastCue.chapter,
                    ),
                  ),
              ],
              if (episode.soundbites.isNotEmpty) ...<Widget>[
                const SizedBox(height: WaxSpace.s24),
                Semantics(
                  identifier: SemanticsIds.episodeSection('soundbites'),
                  child: SectionHeader(title: l10n.podcastSectionHighlights),
                ),
                for (final (i, bite) in episode.soundbites.indexed)
                  _CueRow(
                    stamp: formatCueTimestamp(bite.startMs),
                    text: bite.title ?? l10n.podcastHighlightFallback(i + 1),
                    onTap: () => seekLiveOrReport(
                      context,
                      ref,
                      episode.pid,
                      bite.startMs,
                      PodcastCue.clip,
                    ),
                  ),
              ],
              if (episode.persons.isNotEmpty) ...<Widget>[
                const SizedBox(height: WaxSpace.s24),
                Semantics(
                  identifier: SemanticsIds.episodeSection('people'),
                  child: SectionHeader(title: l10n.podcastSectionPeople),
                ),
                PodcastCredits(
                  persons: episode.persons,
                  onOpenLink: ref.read(urlOpenerProvider).open,
                ),
              ],
              if (episode.hasTranscript) ...<Widget>[
                const SizedBox(height: WaxSpace.s24),
                _TranscriptSection(pid: episode.pid),
              ],
              if (episode.link != null) ...<Widget>[
                const SizedBox(height: WaxSpace.s24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: WaxButton(
                    label: l10n.podcastOpenEpisodePage,
                    kind: WaxButtonKind.text,
                    onPressed: () =>
                        ref.read(urlOpenerProvider).open(episode.link!),
                  ),
                ),
              ],
              const SizedBox(height: WaxSpace.s16),
              Text(
                formatEpisodeMeta(l10n, episode),
                style: WaxType.monoData.copyWith(color: colors.textTertiary),
              ),
              const SizedBox(height: WaxSpace.s32),
            ],
          ),
        ),
      ],
    );
  }
}

/// The show's art at a small size beside the episode's title: an episode
/// borrows its show's cover, so drawing it as a hero the size of an album
/// would claim the artwork is about this episode.
class _Hero extends ConsumerWidget {
  const _Hero({required this.episode, this.showPid});

  final EpisodeDetail episode;
  final String? showPid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    final sizeClass = WaxSizeClass.of(context);
    final show = showPid ?? episode.showPid;
    return WaxBackdrop(
      grain: false,
      domain: WaxDomain.podcasts,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: sizeClass.gutter.horizontal / 2,
          vertical: WaxSpace.s24,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ArtworkImage(
              size: 88,
              artwork: ref.watch(artworkStoreProvider).source(episode.artUrl),
              monogram: episode.artist ?? episode.title,
              domain: WaxDomain.podcasts,
            ),
            const SizedBox(width: WaxSpace.s16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (episode.artist != null)
                    WaxTappable(
                      label: context.l10n.podcastGoToShow(episode.artist!),
                      // The show is a real location, so its name here is
                      // the way back to it rather than a caption.
                      onPressed: () => context.go(WaxRoute.show(show)),
                      child: Text(
                        episode.artist!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WaxType.overline.copyWith(color: colors.accent),
                      ),
                    ),
                  const SizedBox(height: WaxSpace.s4),
                  Text(
                    episode.title,
                    style: WaxType.titleEntity.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: WaxSpace.s8),
                  Text(
                    formatEpisodeMeta(context.l10n, episode),
                    style: WaxType.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Everything this episode can be told to do.
class _ActionBar extends ConsumerWidget {
  const _ActionBar({
    required this.episode,
    required this.progress,
    required this.progressKey,
    this.showPid,
  });

  final EpisodeDetail episode;
  final PlayProgress progress;
  final String progressKey;
  final String? showPid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = EpisodeActions(ref: ref, showPid: showPid);
    final playable = EpisodeActions.playable(episode);
    final resuming = progress.inProgress;
    final l10n = context.l10n;

    return Wrap(
      spacing: WaxSpace.s8,
      runSpacing: WaxSpace.s8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        WaxButton(
          label: playable
              ? (resuming
                    ? l10n.podcastResume(
                        formatCueTimestamp(progress.positionMs),
                      )
                    : l10n.podcastPlay)
              : l10n.podcastFetchToPlay,
          icon: playable ? WaxIcons.play : WaxIcons.downloads,
          semanticsId: SemanticsIds.episodePlay,
          onPressed: () => unawaited(
            actions.play(context, episode, positionMs: progress.positionMs),
          ),
        ),
        WaxButton(
          label: l10n.podcastAddToQueue,
          kind: WaxButtonKind.tonal,
          icon: WaxIcons.addToQueue,
          semanticsId: SemanticsIds.episodeQueue,
          onPressed: playable ? () => actions.enqueue(context, episode) : null,
        ),
        if (episode.downloaded)
          WaxButton(
            label: l10n.podcastRemoveDownload,
            kind: WaxButtonKind.tonal,
            icon: WaxIcons.offline,
            semanticsId: SemanticsIds.episodeRemove(episode.pid),
            onPressed: () =>
                unawaited(actions.removeDownload(context, episode.pid)),
          )
        else if (episode.fetchState == null || episode.fetchState == 'failed')
          WaxButton(
            label: l10n.podcastDownload,
            kind: WaxButtonKind.tonal,
            icon: WaxIcons.downloads,
            semanticsId: SemanticsIds.episodeFetch(episode.pid),
            onPressed: () => unawaited(actions.fetch(context, episode.pid)),
          )
        else
          CodecChip(l10n.podcastQueuedForDownload),
        WaxButton(
          label: progress.played ? l10n.podcastPlayed : l10n.podcastMarkPlayed,
          kind: WaxButtonKind.tonal,
          icon: WaxIcons.check,
          semanticsId: SemanticsIds.episodeMarkPlayed,
          onPressed: progress.played
              ? null
              : () => unawaited(
                  actions.markPlayed(context, episode, progressKey),
                ),
        ),
        WaxButton(
          label: l10n.podcastShare,
          kind: WaxButtonKind.tonal,
          icon: WaxIcons.share,
          semanticsId: SemanticsIds.episodeShare,
          // The share dialog offers a start-at-timestamp when it is
          // handed one, and the position worth offering is the live
          // one: sharing "from here" means where the listener is now,
          // not where they last checkpointed.
          onPressed: () => unawaited(
            showShareLinkDialog(
              context,
              pid: episode.pid,
              positionMs: _shareablePosition(ref),
            ),
          ),
        ),
        if (episode.fetchError != null)
          CodecChip(l10n.podcastFetchFailed(episode.fetchError!)),
      ],
    );
  }

  /// The position a share should offer to start at: the live player's
  /// when it holds this episode, and the saved checkpoint otherwise.
  int? _shareablePosition(WidgetRef ref) {
    final session = ref.read(currentSessionRegistryProvider).current;
    if (session != null && session.item.pid == episode.pid) {
      return session.displayPosition.inMilliseconds;
    }
    return progress.positionMs > 0 ? progress.positionMs : null;
  }
}

/// A timestamp and a line of text that seeks to it.
class _CueRow extends StatelessWidget {
  const _CueRow({
    required this.stamp,
    required this.text,
    required this.onTap,
    this.semanticsId,
  });

  final String stamp;
  final String text;
  final VoidCallback onTap;
  final String? semanticsId;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return WaxTappable(
      semanticsId: semanticsId,
      label: context.l10n.podcastCueSpoken(text, stamp),
      onPressed: onTap,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: WaxSpace.s8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 64,
                child: Text(
                  stamp,
                  style: WaxType.monoTime.copyWith(color: colors.textTertiary),
                ),
              ),
              const SizedBox(width: WaxSpace.s8),
              Expanded(
                child: Text(
                  text,
                  style: WaxType.body.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String formatEpisodeMeta(AppLocalizations l10n, EpisodeSummary episode) {
  return <String>[
    l10n.formatDate(episode.publishedAt),
    if (episode.durationMs > 0) l10n.formatListenTime(episode.durationMs),
    if (episode.season != null && episode.episodeNumber != null)
      l10n.podcastSeasonEpisode(episode.season!, episode.episodeNumber!)
    else if (episode.episodeNumber != null)
      l10n.podcastEpisodeNumber(episode.episodeNumber!),
    // The feed's own word for what kind of episode this is (trailer,
    // bonus), drawn as it was published rather than translated.
    if (episode.episodeType != null && episode.episodeType != 'full')
      episode.episodeType!,
    if (episode.explicit) l10n.podcastExplicit,
  ].join(' · ');
}

/// Transcript cues, fetched only when the section is first expanded.
class _TranscriptSection extends ConsumerStatefulWidget {
  const _TranscriptSection({required this.pid});

  final String pid;

  @override
  ConsumerState<_TranscriptSection> createState() => _TranscriptSectionState();
}

class _TranscriptSectionState extends ConsumerState<_TranscriptSection> {
  Future<Transcript>? _loading;
  var _captured = false;

  void _onExpanded(bool expanded) {
    if (!expanded || _loading != null) return;
    setState(() {
      _loading = ref.read(repositoryProvider).getEpisodeTranscript(widget.pid);
    });
    // Opening the transcript also indexes it for search, so an episode a
    // listener streams but never downloads becomes findable by its words.
    // Best-effort: a capture failure never affects the display transcript.
    if (!_captured) {
      _captured = true;
      unawaited(
        ref
            .read(repositoryProvider)
            .captureEpisodeTranscript(widget.pid)
            .catchError((_) {}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      identifier: SemanticsIds.transcriptOpen,
      child: ExpansionTile(
        key: const Key(SemanticsIds.transcriptOpen),
        tilePadding: EdgeInsets.zero,
        title: Text(
          l10n.podcastTranscript,
          style: WaxType.headline.copyWith(
            color: WaxColors.of(context).textPrimary,
          ),
        ),
        onExpansionChanged: _onExpanded,
        children: <Widget>[
          FutureBuilder<Transcript>(
            future: _loading,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                final error = snapshot.error;
                return Padding(
                  padding: const EdgeInsets.all(WaxSpace.s8),
                  child: Text(
                    error is WaxDeckApiException
                        ? explainError(l10n, error)
                        : l10n.podcastTranscriptError,
                  ),
                );
              }
              final transcript = snapshot.data;
              if (transcript == null) {
                return const Padding(
                  padding: EdgeInsets.all(WaxSpace.s8),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return Column(
                children: <Widget>[
                  for (final (i, cue) in transcript.cues.indexed)
                    _CueRow(
                      semanticsId: SemanticsIds.transcriptCue(i),
                      stamp: formatCueTimestamp(cue.startMs),
                      text: cue.speaker == null
                          ? cue.text
                          : l10n.podcastTranscriptSpeaker(
                              cue.speaker!,
                              cue.text,
                            ),
                      onTap: () => seekLiveOrReport(
                        context,
                        ref,
                        widget.pid,
                        cue.startMs,
                        PodcastCue.cue,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
