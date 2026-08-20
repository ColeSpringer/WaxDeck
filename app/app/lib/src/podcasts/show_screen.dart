import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../l10n/l10n.dart';
import '../home/pin_action.dart';
import '../home/pinned_controller.dart';
import '../player/now_playing_controller.dart';
import '../player/play_progress.dart';
import '../providers.dart';
import '../search/search_chrome.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'credits.dart';
import 'episode_actions.dart';
import 'mark_older_played_dialog.dart';
import 'podcast_shelves.dart';
import 'podcasts_controller.dart';
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
        actions: <Widget>[
          if (detail.value?.subscribed ?? false)
            WaxIconButton(
              glyph: WaxIcons.settings,
              label: l10n.podcastSettingsTitle,
              semanticsId: SemanticsIds.podcastSettingsOpen,
              onPressed: () => _openSettings(context),
            ),
          _ShowOverflow(pid: widget.pid, episodes: loaded),
          const SearchAction(),
        ],
        slivers: <Widget>[
          switch (detail) {
            AsyncData(:final value) => SliverToBoxAdapter(
              child: _ShowHeader(pid: widget.pid, detail: value),
            ),
            AsyncError(:final error) => SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorState(
                title: l10n.podcastShowLoadError,
                message: context.explain(error),
                onRetry: () =>
                    ref.invalidate(podcastDetailProvider(widget.pid)),
              ),
            ),
            _ => const SliverToBoxAdapter(
              child: SkeletonShapes(shape: SkeletonShape.detail),
            ),
          },
          if (detail.hasValue) ...<Widget>[
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
    return switch (episodes) {
      AsyncError(:final error) => SliverFillRemaining(
        hasScrollBody: false,
        child: ErrorState(
          title: l10n.podcastEpisodesLoadError,
          message: context.explain(error),
          onRetry: () => ref.invalidate(episodesProvider(widget.pid)),
        ),
      ),
      // Narrowed to nothing, with more pages behind it. The filters run
      // over what is loaded, so a show whose first page is all played
      // has an empty Unplayed list and, this being the trap, nothing to
      // scroll, so the notification that pages the next one can never
      // fire. The way out is a control rather than a gesture.
      AsyncData(:final value) when visible.isEmpty && (value.hasMore) =>
        SliverToBoxAdapter(
          child: EmptyState(
            title: l10n.podcastNothingMatchesYet,
            message: l10n.podcastNothingMatchesYetMessage(value.items.length),
            glyph: WaxIcons.podcasts,
            actionLabel: loadingMore
                ? l10n.podcastLoadingMore
                : l10n.podcastLoadMore,
            onAction: loadingMore
                ? null
                : () => ref
                      .read(episodesProvider(widget.pid).notifier)
                      .loadMore(),
          ),
        ),
      AsyncData() when visible.isEmpty => SliverToBoxAdapter(
        child: EmptyState(
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
      AsyncData(:final value) => _rows(
        visible,
        progress,
        loadingMore,
        loadMore: visible.length < value.items.length && value.hasMore,
      ),
      _ => const SliverToBoxAdapter(
        child: SkeletonShapes(shape: SkeletonShape.list),
      ),
    };
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
    return SliverPadding(
      padding: EdgeInsets.symmetric(
        horizontal: sizeClass.gutter.horizontal / 2,
      ),
      sliver: SliverList.builder(
        itemCount: visible.length + (footer ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= visible.length) {
            return Padding(
              padding: const EdgeInsets.all(WaxSpace.s16),
              child: Center(
                child: loadingMore
                    ? const CircularProgressIndicator()
                    : WaxButton(
                        label: context.l10n.podcastLoadMore,
                        kind: WaxButtonKind.text,
                        onPressed: () => ref
                            .read(episodesProvider(widget.pid).notifier)
                            .loadMore(),
                      ),
              ),
            );
          }
          final episode = visible[index];
          return _EpisodeRow(
            showPid: widget.pid,
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
    showModalBottomSheet<void>(
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            <String>[
              if (playable.isNotEmpty) l10n.podcastQueuedCount(playable.length),
              // An episode whose feed named no audio cannot play, so
              // queueing it would drop an entry that dies on arrival.
              if (refused > 0) l10n.podcastNoAudioCount(refused),
            ].join('; '),
          ),
        ),
      );
  }

  Future<void> _fetchSelected(List<EpisodeSummary> chosen) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final notifier = ref.read(episodesProvider(widget.pid).notifier);
    var queued = 0;
    String? failure;
    for (final episode in chosen) {
      if (episode.downloaded || episode.fetchState == 'queued') continue;
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
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            failure == null
                ? l10n.podcastQueuedForDownloadCount(queued)
                : l10n.podcastQueuedWithFailure(queued, failure),
          ),
        ),
      );
  }

  Future<void> _markSelectedPlayed(List<EpisodeSummary> chosen) async {
    final messenger = ScaffoldMessenger.of(context);
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
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            failure ??
                <String>[
                  l10n.podcastMarkedPlayedCount(marked),
                  if (skipped > 0) l10n.podcastNoDurationCount(skipped),
                ].join('; '),
          ),
        ),
      );
  }
}

/// The show's own actions, past the ones the bar has room for.
class _ShowOverflow extends ConsumerWidget {
  const _ShowOverflow({required this.pid, required this.episodes});

  final String pid;
  final List<EpisodeSummary> episodes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(podcastDetailProvider(pid)).value;
    final subscribed = detail?.subscribed ?? false;
    final l10n = context.l10n;
    return WaxMenuButton<String>(
      glyph: WaxIcons.more,
      label: l10n.podcastShowMore,
      semanticsId: SemanticsIds.showOverflow,
      items: <WaxMenuItem<String>>[
        // Offered to a subscriber, because the resolver answers pinned
        // shows through the caller's subscriptions: pinning a show this
        // account does not follow would put a card on home that nothing
        // can draw. Offered to a non-subscriber who has it pinned
        // anyway, because unsubscribing is routine and reversible, and
        // hiding the row there would strand the pid in the document
        // holding a slot of the cap with nowhere left to remove it.
        if (subscribed || ref.watch(pinnedEntitiesProvider).contains(pid))
          pinMenuItem<String>(
            context,
            ref,
            pid,
            value: 'pin',
            semanticsId: SemanticsIds.showPin,
          ),
        WaxMenuItem<String>(
          value: 'refresh',
          label: l10n.podcastCheckForNew,
          glyph: WaxIcons.refresh,
        ),
        if (subscribed)
          WaxMenuItem<String>(
            value: 'mark-older',
            label: l10n.podcastMarkOlderPlayed,
            glyph: WaxIcons.check,
            semanticsId: SemanticsIds.markOlderPlayed,
          ),
      ],
      onSelected: (choice) {
        switch (choice) {
          case 'pin':
            // Null rather than a stand-in word: the confirmation is
            // still English, so a translated fragment would read as
            // half a sentence.
            unawaited(togglePin(context, ref, pid, label: detail?.show.title));
          case 'refresh':
            unawaited(_refresh(context, ref));
          case 'mark-older':
            unawaited(
              showDialog<void>(
                context: context,
                builder: (_) => MarkOlderPlayedDialog(pid: pid),
              ),
            );
        }
      },
    );
  }

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      final result = await ref.read(repositoryProvider).refreshPodcast(pid);
      ref.invalidate(episodesProvider(pid));
      ref.invalidate(podcastDetailProvider(pid));
      // New episodes change what the hub's tile and shelves say, and
      // the count a tile draws lives on the subscription row.
      ref.invalidate(subscriptionsProvider);
      ref.invalidate(upNextEpisodesProvider);
      ref.invalidate(latestEpisodesProvider);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              result.newEpisodes == 0
                  ? l10n.podcastNoNewEpisodes
                  : l10n.podcastNewEpisodes(result.newEpisodes),
            ),
          ),
        );
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
    }
  }
}

class _ShowHeader extends ConsumerWidget {
  const _ShowHeader({required this.pid, required this.detail});

  final String pid;
  final PodcastDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = detail.show;
    final notifier = ref.read(podcastDetailProvider(pid).notifier);

    final l10n = context.l10n;

    Future<void> guarded(Future<void> Function() action) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await action();
      } on WaxDeckApiException catch (e) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
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
          artwork: ref.watch(artworkStoreProvider).source(show.artUrl),
          actions: <Widget>[
            if (detail.subscribed)
              WaxButton(
                label: l10n.podcastFollowing,
                kind: WaxButtonKind.tonal,
                icon: WaxIcons.check,
                semanticsId: SemanticsIds.podcastUnsubscribe,
                onPressed: () => unawaited(_unsubscribe(context, ref, guarded)),
              )
            else
              WaxButton(
                label: l10n.podcastFollow,
                icon: WaxIcons.add,
                semanticsId: SemanticsIds.podcastSubscribe,
                onPressed: () => unawaited(guarded(notifier.subscribe)),
              ),
            if (show.funding != null)
              WaxButton(
                label: show.funding!.message?.isNotEmpty ?? false
                    ? show.funding!.message!
                    : l10n.podcastSupportShow,
                kind: WaxButtonKind.text,
                icon: WaxIcons.star,
                onPressed: () =>
                    ref.read(urlOpenerProvider).open(show.funding!.url),
              ),
          ],
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
        content: Text(l10n.podcastUnfollowBody),
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
        _ClampedBox(
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

/// Clamps its child to a pixel budget and reports whether there was more.
///
/// A budget cannot be answered from the widget layer: the notes are
/// arbitrary blocks, so the only thing that knows they ran past it is the
/// layout that clipped them. This lays the child out with the height it
/// asks for, keeps the answer, and takes only as much of it as the budget
/// allows - which is what lets the control above appear when there is
/// something behind it and stay away when there is not.
///
/// The report is against [budget] whether or not [clamped] is set, so an
/// opened block still knows it has something to fold back.
class _ClampedBox extends SingleChildRenderObjectWidget {
  const _ClampedBox({
    required this.budget,
    required this.clamped,
    required this.onOverflow,
    required Widget super.child,
  });

  final double budget;
  final bool clamped;
  final ValueChanged<bool> onOverflow;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderClampedBox(budget, clamped, onOverflow);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderClampedBox renderObject,
  ) {
    renderObject
      ..budget = budget
      ..clamped = clamped
      ..onOverflow = onOverflow;
  }
}

class _RenderClampedBox extends RenderProxyBox {
  _RenderClampedBox(this._budget, this._clamped, this.onOverflow);

  /// Half a pixel: a block whose height lands on the budget by rounding
  /// is not something to offer a reader more of, and reporting it would
  /// flip the control on and off as the window resized.
  static const double _epsilon = 0.5;

  double _budget;
  double get budget => _budget;
  set budget(double value) {
    if (value == _budget) return;
    _budget = value;
    markNeedsLayout();
  }

  bool _clamped;
  bool get clamped => _clamped;
  set clamped(bool value) {
    if (value == _clamped) return;
    _clamped = value;
    markNeedsLayout();
  }

  ValueChanged<bool> onOverflow;

  bool? _reported;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(
      BoxConstraints(
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
      ),
      parentUsesSize: true,
    );
    final natural = child.size.height;
    final overflows = natural - _budget > _epsilon;
    // The same test decides the clip and the control. Told apart - a
    // bare `>` here against the epsilon below - notes laid out a third
    // of a pixel over their budget are cut off while the control that
    // opens them is withheld, which is the failure this box exists to
    // end.
    size = constraints.constrain(
      Size(child.size.width, _clamped && overflows ? _budget : natural),
    );
    if (overflows == _reported) return;
    _reported = overflows;
    // After the frame rather than during it: the caller answers by
    // rebuilding, and a setState inside layout is a build reentering
    // itself.
    WidgetsBinding.instance.addPostFrameCallback((_) => onOverflow(overflows));
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _clamp(super.computeMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _clamp(super.computeMaxIntrinsicHeight(width));

  double _clamp(double height) =>
      _clamped && height > _budget ? _budget : height;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    final natural = child.getDryLayout(
      BoxConstraints(
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
      ),
    );
    return constraints.constrain(Size(natural.width, _clamp(natural.height)));
  }

  /// Whether anything of the child falls outside what this box took.
  ///
  /// Geometry rather than [_clamped]: `performLayout` hands the child
  /// unbounded height and then constrains itself, so under a height-
  /// bounding ancestor an unclamped box is still smaller than what it
  /// holds - and painting that unclipped runs the notes over whatever
  /// is drawn below them.
  bool get _clips => child != null && child!.size.height > size.height;

  /// Kept so the engine reuses one retained layer instead of taking a
  /// new one every paint, the way [RenderClipRect] does.
  final LayerHandle<ClipRectLayer> _clipLayer = LayerHandle<ClipRectLayer>();

  @override
  void dispose() {
    _clipLayer.layer = null;
    super.dispose();
  }

  /// What a reader can actually see, so the semantics tree stops where
  /// the paint does. Without it the clipped-away notes stay in the tree:
  /// a screen reader reads a whole page of description beside a control
  /// that says "Show more", and on the web their nodes keep emitting at
  /// un-clamped offsets over the rows below.
  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      _clips ? Offset.zero & size : null;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (!_clips) {
      _clipLayer.layer = null;
      context.paintChild(child, offset);
      return;
    }
    _clipLayer.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (context, offset) => context.paintChild(child, offset),
      oldLayer: _clipLayer.layer,
    );
  }
}

/// One episode in a show's list.
class _EpisodeRow extends ConsumerWidget {
  const _EpisodeRow({
    required this.showPid,
    required this.episode,
    required this.progress,
    required this.selecting,
    required this.selected,
    required this.onSelect,
  });

  final String showPid;
  final EpisodeSummary episode;
  final PlayProgress progress;
  final bool selecting;
  final bool selected;
  final ValueChanged<bool> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = EpisodeActions(ref: ref, showPid: showPid);
    final l10n = context.l10n;
    final remaining = episode.durationMs - progress.positionMs;
    final trailing = progress.inProgress && remaining > 0
        ? l10n.podcastTimeLeft(l10n.formatListenTime(remaining))
        : l10n.formatListenTime(episode.durationMs);

    final facts = <String>[
      if (episode.season != null && episode.episodeNumber != null)
        l10n.podcastSeasonEpisode(episode.season!, episode.episodeNumber!)
      else if (episode.episodeNumber != null)
        l10n.podcastEpisodeNumber(episode.episodeNumber!),
      if (episode.explicit) l10n.podcastExplicit,
      if (episode.fetchState == 'failed')
        l10n.podcastDownloadFailed
      else if (episode.fetchState != null && !episode.downloaded)
        l10n.podcastQueuedForDownload
      // Said on the row rather than left to the tap: an episode this
      // server holds no bytes for still plays, relayed from the feed's
      // own host, and the one that cannot play at all is the one whose
      // feed named no audio.
      else if (!episode.downloaded && !episode.hasEnclosure)
        l10n.podcastNoAudioInFeed,
    ];

    return MediaListRow(
      data: MediaTileData(
        title: episode.title,
        subtitle: facts.isEmpty ? null : facts.join(' · '),
        domain: WaxDomain.podcasts,
        progress: progress.fractionOf(episode.durationMs),
        trailingText: trailing,
        downloaded: episode.downloaded,
        unplayed: !progress.played && progress.positionMs == 0,
        semanticsId: SemanticsIds.episode(episode.pid),
      ),
      leadingText: l10n.formatMonthDay(episode.publishedAt),
      onSelect: selecting ? onSelect : null,
      selectSemanticsId: SemanticsIds.episodeSelect(episode.pid),
      selected: selected,
      actions: <Widget>[
        if (!episode.downloaded &&
            (episode.fetchState == null || episode.fetchState == 'failed'))
          WaxIconButton(
            glyph: WaxIcons.downloads,
            label: l10n.podcastFetchEpisode(episode.title),
            size: 18,
            semanticsId: SemanticsIds.episodeFetch(episode.pid),
            onPressed: () => unawaited(actions.fetch(context, episode.pid)),
          ),
        if (episode.downloaded)
          WaxIconButton(
            glyph: WaxIcons.offline,
            label: l10n.podcastRemoveEpisode(episode.title),
            size: 18,
            semanticsId: SemanticsIds.episodeRemove(episode.pid),
            onPressed: () =>
                unawaited(actions.removeDownload(context, episode.pid)),
          ),
        WaxIconButton(
          glyph: WaxIcons.info,
          label: l10n.podcastEpisodeDetails(episode.title),
          size: 18,
          semanticsId: SemanticsIds.episodeInfo(episode.pid),
          // Gone to, not pushed: the episode is declared beneath this
          // show, so this location is the one it says it is and leaving
          // it lands back here whether the visitor tapped in or opened
          // the link cold.
          onPressed: () =>
              context.go(WaxRoute.showEpisode(showPid, episode.pid)),
        ),
      ],
      // Long-press starts a selection, which is how a batch begins on
      // touch. Not `onMore`, which would draw an overflow button
      // announcing itself as "More for [title]" whose only action is to
      // start selecting, and which would then vanish once one was
      // running. `MediaListRow` takes the gesture without the control.
      onLongPress: selecting ? null : () => onSelect(true),
      onTap: () => selecting
          ? onSelect(!selected)
          : unawaited(
              actions.play(context, episode, positionMs: progress.positionMs),
            ),
    );
  }
}
