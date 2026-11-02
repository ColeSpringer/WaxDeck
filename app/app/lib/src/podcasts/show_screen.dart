import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/art_source_label.dart';
import '../artwork/artwork_providers.dart';
import '../l10n/l10n.dart';
import '../player/now_playing_controller.dart';
import '../player/play_progress.dart';
import '../providers.dart';
import '../search/search_chrome.dart';
import '../shell/async_sliver_face.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/server_health.dart';
import '../shell/shell_messages.dart';
import 'credits.dart';
import 'episode_actions.dart';
import 'episode_fetch.dart';
import 'episode_row.dart';
import 'podcast_shelves.dart';
import 'podcasts_controller.dart';
import 'show_actions.dart';
import 'show_notes.dart';
import 'subscription_settings_sheet.dart';

/// Which episodes the list is showing.
enum EpisodeFilterChoice {
  all('all'),
  unplayed('unplayed'),
  downloaded('downloaded');

  const EpisodeFilterChoice(this.name);

  final String name;

  String labelOf(AppLocalizations l10n) => switch (this) {
    EpisodeFilterChoice.all => l10n.podcastFilterAll,
    EpisodeFilterChoice.unplayed => l10n.podcastFilterUnplayed,
    EpisodeFilterChoice.downloaded => l10n.podcastFilterDownloaded,
  };
}

/// One podcast show: what it is, what it does automatically, and its
/// episodes.
class ShowScreen extends ConsumerStatefulWidget {
  const ShowScreen({super.key, required this.pid});

  final String pid;

  @override
  ConsumerState<ShowScreen> createState() => _ShowScreenState();
}

/// The Load more footer under the episode rows.
const _footerKey = ValueKey<String>('episodes-load-more');

class _ShowScreenState extends ConsumerState<ShowScreen> {
  var _filter = EpisodeFilterChoice.all;

  /// The chosen season, or null for every season. Only offered on a show
  /// whose feed numbers its seasons.
  int? _season;

  /// The search-within-show query, matched against the pages already
  /// loaded. Client-side on purpose: there is no per-show search on the
  /// wire, and narrowing what is on screen is what the field promises.
  var _query = '';

  /// The episodes picked for a batch action. Empty means no selection
  /// mode; the row taps go back to playing the moment it empties.
  final Set<String> _selected = <String>{};

  bool get _selecting => _selected.isNotEmpty;

  /// Whether the list on screen is narrower than the pages behind it.
  bool get _narrowed =>
      _query.trim().isNotEmpty ||
      _filter != EpisodeFilterChoice.all ||
      _season != null;

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(podcastDetailProvider(widget.pid));
    final episodes = ref.watch(episodesProvider(widget.pid));
    final loaded = episodes.value?.items ?? const <EpisodeSummary>[];
    // One read per window of loaded rows rather than one over all of
    // them: paging then costs the page it just loaded instead of every
    // page before it.
    final positions = <String, PlayProgress>{};
    for (final key in playProgressKeys(loaded)) {
      positions.addAll(
        ref.watch(playProgressProvider(key)).value ??
            const <String, PlayProgress>{},
      );
    }
    final view = PlayProgressView(positions);
    final visible = _visible(loaded, view);
    final l10n = context.l10n;
    final title = detail.value?.show.title ?? l10n.podcastShowFallbackTitle;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        // Vertical only: a horizontal scroller inside the page sits at
        // pixel zero of a short extent, which reads as "near the end".
        if (metrics.axis != Axis.vertical) return false;
        if (metrics.pixels >= metrics.maxScrollExtent - 600) {
          ref.read(episodesProvider(widget.pid).notifier).loadMore();
        }
        return false;
      },
      child: WaxScaffold(
        title: title,
        largeTitle: false,
        onBack: () => context.leave(fallback: WaxRoute.podcasts),
        actions: const <Widget>[SearchAction()],
        slivers: <Widget>[
          AsyncSliverFace<PodcastDetail>(
            state: detail,
            skeleton: SkeletonShape.detail,
            errorTitle: l10n.podcastShowLoadError,
            onRetry: () => ref.invalidate(podcastDetailProvider(widget.pid)),
            builder: (context, value) => SliverToBoxAdapter(
              child: _ShowHeader(
                pid: widget.pid,
                detail: value,
                onOpenSettings: () => _openSettings(context),
              ),
            ),
          ),
          // Gated the way the face above decides: a value carried under a
          // failure draws the failure, and an episode list under a
          // full-viewport error card would be the working half of a
          // screen that says it is broken.
          if (!detail.hasError && detail.hasValue) ...<Widget>[
            SliverToBoxAdapter(child: _toolbar(loaded)),
            _list(episodes, visible, view),
          ],
        ],
      ),
    );
  }

  /// What the filters, the season, and the query leave standing.
  List<EpisodeSummary> _visible(
    List<EpisodeSummary> loaded,
    PlayProgressView progress,
  ) {
    final needle = _query.trim().toLowerCase();
    return <EpisodeSummary>[
      for (final episode in loaded)
        if (switch (_filter) {
              EpisodeFilterChoice.all => true,
              // Never started, matching the server's shelf and the row
              // dot below: a five-minutes-in episode is in progress, not
              // unplayed.
              EpisodeFilterChoice.unplayed => switch (progress[episode.pid]) {
                final p => !p.played && p.positionMs == 0,
              },
              EpisodeFilterChoice.downloaded => episode.downloaded,
            } &&
            (_season == null || episode.season == _season) &&
            (needle.isEmpty || episode.title.toLowerCase().contains(needle)))
          episode,
    ];
  }

  Widget _toolbar(List<EpisodeSummary> loaded) {
    final sizeClass = WaxSizeClass.of(context);
    final l10n = context.l10n;
    final seasons = <int>{
      for (final episode in loaded)
        if (episode.season != null) episode.season!,
    }.toList()..sort();

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: sizeClass.gutter.horizontal / 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SearchField(
            label: l10n.podcastSearchShow,
            hint: l10n.podcastSearchShow,
            semanticsId: SemanticsIds.showEpisodeSearch,
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: WaxSpace.s12),
          FilterChipRow(
            chips: <WaxFilterChip>[
              for (final choice in EpisodeFilterChoice.values)
                WaxFilterChip(
                  name: choice.name,
                  label: choice.labelOf(l10n),
                  semanticsId: SemanticsIds.showEpisodeFilter(choice.name),
                ),
              // Seasons join the same row rather than getting a control
              // of their own: they are the same question (which of these
              // episodes), and a feed that numbers none offers none.
              for (final season in seasons)
                WaxFilterChip(
                  name: 'season-$season',
                  label: l10n.podcastSeasonChip(season),
                  semanticsId: SemanticsIds.showEpisodeFilter('season-$season'),
                ),
            ],
            selected: _season != null ? 'season-$_season' : _filter.name,
            onSelect: (name) => setState(() {
              if (name.startsWith('season-')) {
                final chosen = int.tryParse(name.substring('season-'.length));
                // Tapping the season you are in leaves it, which is what
                // a single-select row of two questions can offer without
                // a second control.
                _season = _season == chosen ? null : chosen;
                return;
              }
              _season = null;
              _filter = EpisodeFilterChoice.values.firstWhere(
                (choice) => choice.name == name,
                orElse: () => EpisodeFilterChoice.all,
              );
            }),
          ),
          if (_selecting) _selectionBar(loaded),
          const SizedBox(height: WaxSpace.s8),
        ],
      ),
    );
  }

  Widget _selectionBar(List<EpisodeSummary> loaded) {
    final chosen = <EpisodeSummary>[
      for (final episode in loaded)
        if (_selected.contains(episode.pid)) episode,
    ];
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: WaxSpace.s12),
      child: Wrap(
        spacing: WaxSpace.s8,
        runSpacing: WaxSpace.s8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text(
            l10n.podcastSelectedCount(chosen.length),
            style: WaxType.label.copyWith(
              color: WaxColors.of(context).textSecondary,
            ),
          ),
          WaxButton(
            label: l10n.podcastAddToQueue,
            kind: WaxButtonKind.tonal,
            icon: WaxIcons.addToQueue,
            semanticsId: SemanticsIds.selectionQueue,
            onPressed: chosen.isEmpty ? null : () => _queueSelected(chosen),
          ),
          WaxButton(
            label: l10n.podcastDownload,
            kind: WaxButtonKind.tonal,
            icon: WaxIcons.downloads,
            semanticsId: SemanticsIds.selectionDownload,
            onPressed: chosen.isEmpty
                ? null
                : () => unawaited(_fetchSelected(chosen)),
          ),
          WaxButton(
            label: l10n.podcastMarkPlayed,
            kind: WaxButtonKind.tonal,
            icon: WaxIcons.check,
            semanticsId: SemanticsIds.selectionMarkPlayed,
            onPressed: chosen.isEmpty
                ? null
                : () => unawaited(_markSelectedPlayed(chosen)),
          ),
          WaxButton(
            label: l10n.podcastClearSelection,
            kind: WaxButtonKind.text,
            semanticsId: SemanticsIds.selectionClear,
            onPressed: () => setState(_selected.clear),
          ),
        ],
      ),
    );
  }

  Widget _list(
    AsyncValue<EpisodeListState> episodes,
    List<EpisodeSummary> visible,
    PlayProgressView progress,
  ) {
    final loadingMore = episodes.value?.loadingMore ?? false;
    final l10n = context.l10n;
    return AsyncSliverFace<EpisodeListState>(
      state: episodes,
      errorTitle: l10n.podcastEpisodesLoadError,
      onRetry: () => ref.invalidate(episodesProvider(widget.pid)),
      isEmpty: (_) => visible.isEmpty,
      empty: (context, value) => SliverToBoxAdapter(
        // Narrowed to nothing, with more pages behind it, is its own
        // answer. The filters run over what is loaded, so a show whose
        // first page is all played has an empty Unplayed list and, this
        // being the trap, nothing to scroll, so the notification that
        // pages the next one can never fire. The way out is a control
        // rather than a gesture.
        child: value.hasMore
            ? EmptyState(
                title: l10n.podcastNothingMatchesYet,
                message: l10n.podcastNothingMatchesYetMessage(
                  value.items.length,
                ),
                glyph: WaxIcons.podcasts,
                actionLabel: l10n.podcastLoadMore,
                actionBusy: loadingMore,
                onAction: () =>
                    ref.read(episodesProvider(widget.pid).notifier).loadMore(),
              )
            : EmptyState(
                title: _narrowed
                    ? l10n.podcastNothingMatches
                    : l10n.podcastNoEpisodes,
                message: _narrowed
                    ? l10n.podcastNothingMatchesMessage
                    : l10n.podcastNoEpisodesMessage,
                glyph: WaxIcons.podcasts,
              ),
      ),
      // The same trap one step short of empty: two matches of fifty read
      // as an answer, and are too short to scroll the next page in.
      // Read off the two lists rather than off the filters, so a list
      // drawn as long as the pages behind it keeps the plain gesture.
      builder: (context, value) => _rows(
        visible,
        progress,
        loadingMore,
        loadMore: visible.length < value.items.length && value.hasMore,
      ),
    );
  }

  Widget _rows(
    List<EpisodeSummary> visible,
    PlayProgressView progress,
    bool loadingMore, {
    bool loadMore = false,
  }) {
    final sizeClass = WaxSizeClass.of(context);
    // Under the rows rather than beside the filters: a list long enough
    // to scroll has already paged by the time this is reached.
    final footer = loadingMore || loadMore;
    final rows = indexByKey(visible, episodeRowKey);
    return SliverPadding(
      padding: EdgeInsets.symmetric(
        horizontal: sizeClass.gutter.horizontal / 2,
      ),
      sliver: SliverList.builder(
        itemCount: visible.length + (footer ? 1 : 0),
        // Keyed like the rows, so a filter that moves it mid-page keeps
        // the press it holds.
        findChildIndexCallback: (key) =>
            key == _footerKey ? (footer ? visible.length : null) : rows(key),
        itemBuilder: (context, index) {
          if (index >= visible.length) {
            return LoadMoreFooter(
              key: _footerKey,
              label: context.l10n.podcastLoadMore,
              loading: loadingMore,
              onLoadMore: () =>
                  ref.read(episodesProvider(widget.pid).notifier).loadMore(),
            );
          }
          final episode = visible[index];
          return EpisodeRow(
            key: episodeRowKey(episode),
            showPid: widget.pid,
            leadingText: context.l10n.formatMonthDay(episode.publishedAt),
            viaGo: true,
            episode: episode,
            progress: progress[episode.pid],
            selecting: _selecting,
            selected: _selected.contains(episode.pid),
            onSelect: (value) => setState(() {
              if (value) {
                _selected.add(episode.pid);
              } else {
                _selected.remove(episode.pid);
              }
            }),
          );
        },
      ),
    );
  }

  void _openSettings(BuildContext context) {
    final settings =
        ref.read(podcastDetailProvider(widget.pid)).value?.settings ??
        const SubscriptionSettings();
    showWaxSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          SubscriptionSettingsSheet(pid: widget.pid, initial: settings),
    );
  }

  void _queueSelected(List<EpisodeSummary> chosen) {
    // Appended, not played. "Add to queue" is the one verb on this
    // screen that promises not to interrupt anything, and `play`
    // replaces the whole queue and starts the first entry, which on a
    // batch of six is the opposite of what was asked, and destroys
    // whatever was playing.
    final playable = <EpisodeSummary>[
      for (final episode in chosen)
        if (EpisodeActions.playable(episode)) episode,
    ];
    final refused = chosen.length - playable.length;
    if (playable.isNotEmpty) {
      ref.read(nowPlayingProvider.notifier).enqueue(playable);
    }
    final l10n = context.l10n;
    setState(_selected.clear);
    ref
        .read(shellMessengerProvider.notifier)
        .show(
          <String>[
            if (playable.isNotEmpty) l10n.podcastQueuedCount(playable.length),
            // An episode whose feed named no audio cannot play, so
            // queueing it would drop an entry that dies on arrival.
            if (refused > 0) l10n.podcastNoAudioCount(refused),
          ].join('; '),
          channel: ShellChannel.episodes,
        );
  }

  Future<void> _fetchSelected(List<EpisodeSummary> chosen) async {
    final messenger = ref.read(shellMessengerProvider.notifier);
    final l10n = context.l10n;
    final notifier = ref.read(episodesProvider(widget.pid).notifier);
    var queued = 0;
    String? failure;
    for (final episode in chosen) {
      if (episodeFetchOf(episode)
          case EpisodeFetchDone() || EpisodeFetchQueued()) {
        continue;
      }
      try {
        await notifier.fetchEpisode(episode.pid);
        queued++;
      } on WaxDeckApiException catch (e) {
        // One refusal does not abandon the rest: a batch is a list of
        // independent requests, and stopping on the first would leave
        // the selection half done with nothing said about which half.
        failure ??= explainError(l10n, e);
      }
    }
    if (!mounted) return;
    setState(_selected.clear);
    messenger.show(
      failure == null
          ? l10n.podcastQueuedForDownloadCount(queued)
          : l10n.podcastQueuedWithFailure(queued, failure),
      channel: ShellChannel.episodes,
    );
  }

  Future<void> _markSelectedPlayed(List<EpisodeSummary> chosen) async {
    final messenger = ref.read(shellMessengerProvider.notifier);
    final l10n = context.l10n;
    final repository = ref.read(repositoryProvider);
    var marked = 0;
    var skipped = 0;
    String? failure;
    for (final episode in chosen) {
      // A feed that declared no duration leaves no position that means
      // finished, so there is nothing to write for it.
      if (episode.durationMs <= 0) {
        skipped++;
        continue;
      }
      try {
        await repository.putPlayState(episode.pid, episode.durationMs);
        marked++;
      } on WaxDeckApiException catch (e) {
        failure ??= explainError(l10n, e);
      }
    }
    if (marked > 0) {
      // The family rather than one key: a selection spans windows, and
      // the hub's tile draws the backlog this just changed.
      ref.invalidate(playProgressProvider);
      ref.invalidate(subscriptionsProvider);
      ref.invalidate(upNextEpisodesProvider);
      ref.invalidate(latestEpisodesProvider);
    }
    if (!mounted) return;
    setState(_selected.clear);
    messenger.show(
      failure ??
          <String>[
            l10n.podcastMarkedPlayedCount(marked),
            if (skipped > 0) l10n.podcastNoDurationCount(skipped),
          ].join('; '),
      channel: ShellChannel.episodes,
    );
  }
}

/// The show's own actions, past follow and support.
class _ShowOverflow extends ConsumerWidget {
  const _ShowOverflow({required this.detail});

  final PodcastDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pid = detail.show.pid;
    return WaxMenuButton<ShowAction>(
      glyph: WaxIcons.more,
      label: context.l10n.podcastShowMore,
      semanticsId: SemanticsIds.showOverflow,
      items: showMenuItems(context, ref, pid, subscribed: detail.subscribed),
      onSelected: (action) => unawaited(
        runShowAction(
          context,
          ref,
          action,
          pid: pid,
          title: detail.show.title,
          hasArtwork: detail.show.artSource != null,
        ),
      ),
    );
  }
}

/// Follow and Following share one place in the header's row.
const _followSlot = #follow;

class _ShowHeader extends ConsumerWidget {
  const _ShowHeader({
    required this.pid,
    required this.detail,
    required this.onOpenSettings,
  });

  final String pid;
  final PodcastDetail detail;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = detail.show;
    final notifier = ref.read(podcastDetailProvider(pid).notifier);

    final l10n = context.l10n;

    Future<void> guarded(Future<void> Function() action) async {
      final messenger = ref.read(shellMessengerProvider.notifier);
      try {
        await action();
      } on WaxDeckApiException catch (e) {
        messenger.show(explainError(l10n, e), channel: ShellChannel.podcasts);
      }
    }

    final count = show.episodeCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        EntityHeader(
          title: show.title,
          subtitle: show.author,
          domain: WaxDomain.podcasts,
          metadata: <String>[
            if (count != null) l10n.podcastEpisodeCount(count),
            if (show.lastPublishedAt != null)
              l10n.podcastLatestPublished(
                l10n.formatDate(show.lastPublishedAt!),
              ),
            if (show.explicit) l10n.podcastExplicit,
          ].join(' · '),
          // The show detail read already carries it, so the mark costs
          // nothing here. A feed image reads as the feed's; a cover
          // somebody replaced by hand says so.
          artworkCaption: artSourceLabelWithBorrow(l10n, show.artSource),
          artwork: ref.watch(artworkStoreProvider).source(show.artUrl),
          actions: <WaxAction>[
            if (detail.subscribed)
              WaxAction(
                label: l10n.podcastFollowing,
                glyph: WaxIcons.check,
                slot: _followSlot,
                semanticsId: SemanticsIds.podcastUnsubscribe,
                onPressed: () => unawaited(_unsubscribe(context, ref, guarded)),
              )
            // A server whose podcasts are off refuses the follow.
            else if (ref.watch(podcastsOnProvider))
              WaxAction(
                label: l10n.podcastFollow,
                glyph: WaxIcons.add,
                emphasis: WaxActionEmphasis.primary,
                slot: _followSlot,
                semanticsId: SemanticsIds.podcastSubscribe,
                // A private show's address is its followers' alone, so it
                // is followed by the address the listener was given.
                onPressed: show.feedUrl == null
                    ? () => ref
                          .read(shellMessengerProvider.notifier)
                          .show(
                            l10n.podcastFollowPrivate,
                            channel: ShellChannel.podcasts,
                          )
                    : () => unawaited(guarded(notifier.subscribe)),
              ),
            if (show.funding != null)
              WaxAction(
                label: show.funding!.message?.isNotEmpty ?? false
                    ? show.funding!.message!
                    : l10n.podcastSupportShow,
                // It leaves the app, so neither the rating star nor a
                // heart.
                glyph: WaxIcons.openExternal,
                semanticsId: SemanticsIds.podcastSupport,
                onPressed: () =>
                    ref.read(urlOpenerProvider).open(show.funding!.url),
              ),
          ],
          trailing: <Widget>[
            if (detail.subscribed)
              WaxIconButton(
                glyph: WaxIcons.settings,
                label: l10n.podcastSettingsTitle,
                semanticsId: SemanticsIds.podcastSettingsOpen,
                onPressed: onOpenSettings,
              ),
          ],
          overflow: _ShowOverflow(detail: detail),
        ),
        if (show.refreshDisabled)
          Padding(
            padding: EdgeInsets.fromLTRB(
              WaxSizeClass.of(context).gutter.horizontal / 2,
              WaxSpace.s12,
              WaxSizeClass.of(context).gutter.horizontal / 2,
              0,
            ),
            child: WaxBanner(
              tone: WaxBannerTone.caution,
              message: l10n.podcastRefreshPaused,
            ),
          ),
        if (show.descriptionHtml != null && show.descriptionHtml!.isNotEmpty)
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: WaxSizeClass.of(context).gutter.horizontal / 2,
              vertical: WaxSpace.s16,
            ),
            child: CollapsibleNotes(html: show.descriptionHtml!),
          ),
        if (show.persons.isNotEmpty)
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: WaxSizeClass.of(context).gutter.horizontal / 2,
            ),
            child: PodcastCredits(
              persons: show.persons,
              onOpenLink: ref.read(urlOpenerProvider).open,
            ),
          ),
      ],
    );
  }

  // The unsubscribe itself never destroys anything, so it needs no
  // confirmation; the question only appears when server downloads are
  // at stake, and it is about the files, not the subscription.
  Future<void> _unsubscribe(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(Future<void> Function()) guarded,
  ) async {
    final episodes =
        ref.read(episodesProvider(pid)).value?.items ??
        const <EpisodeSummary>[];
    final hasDownloads = episodes.any((e) => e.downloaded);
    final notifier = ref.read(podcastDetailProvider(pid).notifier);
    if (!hasDownloads) {
      await guarded(notifier.unsubscribe);
      return;
    }
    final l10n = context.l10n;
    final removeFiles = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.podcastUnfollowTitle),
        content: WaxProse(l10n.podcastUnfollowBody),
        actions: <Widget>[
          WaxButton(
            label: l10n.podcastKeepFiles,
            kind: WaxButtonKind.text,
            semanticsId: SemanticsIds.unsubscribeKeepFiles,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          WaxButton(
            label: l10n.podcastRemoveFiles,
            kind: WaxButtonKind.destructive,
            semanticsId: SemanticsIds.unsubscribeRemoveFiles,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (removeFiles == null) return;
    await guarded(() => notifier.unsubscribe(removeDownloads: removeFiles));
  }
}

/// Show notes, clamped until asked for. A feed's description runs from
/// one line to a page, and a page of it above the episode list buries
/// the thing the screen is for.
class CollapsibleNotes extends ConsumerStatefulWidget {
  const CollapsibleNotes({
    super.key,
    required this.html,
    this.collapsedTo = 120,
  });

  final String html;

  /// How much shows while collapsed. In pixels rather than lines: the
  /// notes are arbitrary HTML, so there is no line count to clamp.
  final double collapsedTo;

  @override
  ConsumerState<CollapsibleNotes> createState() => _CollapsibleNotesState();
}

class _CollapsibleNotesState extends ConsumerState<CollapsibleNotes> {
  var _open = false;
  var _overflows = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClampedBox(
          budget: widget.collapsedTo,
          clamped: !_open,
          onOverflow: (value) {
            if (!mounted || value == _overflows) return;
            setState(() => _overflows = value);
          },
          child: ShowNotesView(
            html: widget.html,
            onOpenLink: ref.read(urlOpenerProvider).open,
          ),
        ),
        // Only where there is more to show: a one-line description used
        // to get a control that unfolded nothing.
        if (_overflows)
          WaxButton(
            label: _open
                ? context.l10n.podcastShowLessNotes
                : context.l10n.podcastShowMoreNotes,
            // Aligned with the notes it opens rather than indented a
            // pill's padding past them.
            kind: WaxButtonKind.inline,
            onPressed: () => setState(() => _open = !_open),
          ),
      ],
    );
  }
}
