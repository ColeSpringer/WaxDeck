import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../l10n/l10n.dart';
import '../providers.dart';
import '../search/search_chrome.dart';
import '../shell/account_chrome.dart';
import '../settings/client_prefs.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../uploads/file_picker_port.dart';
import 'add_podcast.dart';
import 'episode_actions.dart';
import 'podcast_shelves.dart';
import 'podcasts_controller.dart';

/// The podcast domain's front door: what is half-listened-to, what is
/// new, and every show being followed.
class PodcastsScreen extends ConsumerWidget {
  const PodcastsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscriptions = ref.watch(subscriptionsProvider);
    final sort = ref.watch(subscriptionSortProvider);
    final l10n = context.l10n;

    return WaxScaffold(
      title: l10n.podcastsTitle,
      actions: <Widget>[
        WaxIconButton(
          glyph: WaxIcons.add,
          label: l10n.podcastAddSubscription,
          semanticsId: SemanticsIds.podcastAdd,
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const SubscribeDialog(),
          ),
        ),
        const _HubOverflow(),
        const SearchAction(),
        const AccountAction(),
      ],
      slivers: <Widget>[
        const SliverToBoxAdapter(child: _UpNextShelf()),
        switch (subscriptions) {
          AsyncData(:final value) when value.isEmpty => SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: l10n.podcastsEmptyTitle,
              message: l10n.podcastsEmptyMessage,
              glyph: WaxIcons.podcasts,
              actionLabel: l10n.podcastsEmptyAction,
              onAction: () => showDialog<void>(
                context: context,
                builder: (_) => const SubscribeDialog(),
              ),
            ),
          ),
          AsyncData(:final value) => _Subscriptions(
            subscriptions: sortSubscriptions(value, sort),
          ),
          AsyncError(:final error) => SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(
              title: l10n.podcastsLoadError,
              message: context.explain(error),
              onRetry: () => ref.invalidate(subscriptionsProvider),
            ),
          ),
          _ => const SliverToBoxAdapter(
            child: SkeletonShapes(shape: SkeletonShape.grid),
          ),
        },
        const SliverToBoxAdapter(child: _LatestEpisodes()),
      ],
    );
  }
}

/// Sort and the OPML doors. In an overflow rather than on the bar: they
/// are the things a listener reaches for twice a year, and the bar's room
/// belongs to adding a show and to search.
class _HubOverflow extends ConsumerWidget {
  const _HubOverflow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(subscriptionSortProvider);
    final picker = ref.watch(filePickerProvider);
    final l10n = context.l10n;
    return WaxMenuButton<String>(
      glyph: WaxIcons.more,
      label: l10n.podcastMore,
      semanticsId: SemanticsIds.podcastOverflow,
      items: <WaxMenuItem<String>>[
        for (final choice in SubscriptionSort.values)
          WaxMenuItem<String>(
            value: 'sort:${choice.name}',
            // The whole row rather than a lower-cased noun dropped into
            // a frame: the frame's shape is the language's business.
            label: l10n.podcastSortRow(choice.name),
            selected: choice == sort,
            semanticsId: SemanticsIds.podcastSort(choice.name),
          ),
        WaxMenuItem<String>(
          value: 'export',
          label: l10n.podcastOpmlExport,
          semanticsId: SemanticsIds.podcastOpmlExport,
        ),
        // Hidden without a picker, the contract every pick affordance in
        // this app follows: a platform with no file dialog would
        // otherwise offer an import that cannot open one.
        if (picker != null)
          WaxMenuItem<String>(
            value: 'import',
            label: l10n.podcastOpmlImport,
            semanticsId: SemanticsIds.podcastOpmlImport,
          ),
      ],
      onSelected: (choice) {
        if (choice.startsWith('sort:')) {
          final name = choice.substring('sort:'.length);
          final chosen = SubscriptionSort.values.firstWhere(
            (s) => s.name == name,
            orElse: () => SubscriptionSort.recent,
          );
          ref.read(subscriptionSortProvider.notifier).select(chosen);
          return;
        }
        switch (choice) {
          case 'export':
            unawaited(_exportOpml(context, ref));
          case 'import':
            unawaited(_importOpml(context, ref));
        }
      },
    );
  }

  /// Fetches the OPML and offers it for copying.
  ///
  /// The same answer the playlist export gives, for the same reason: the
  /// web build has no file-save surface, and an OPML document on the
  /// clipboard pastes into every other podcast client's import box.
  static Future<void> _exportOpml(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final String opml;
    try {
      opml = await ref.read(repositoryProvider).exportOpml();
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.podcastOpmlExport),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: SelectableText(
              opml,
              key: const Key('opml-export-content'),
              style: WaxType.monoData,
            ),
          ),
        ),
        actions: <Widget>[
          WaxButton(
            label: l10n.commonClose,
            kind: WaxButtonKind.text,
            onPressed: () => Navigator.of(context).pop(),
          ),
          WaxButton(
            label: l10n.podcastOpmlCopy,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: opml));
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(l10n.podcastOpmlCopied)));
            },
          ),
        ],
      ),
    );
  }

  static const _opmlExtensions = {'opml', 'xml'};

  static Future<void> _importOpml(BuildContext context, WidgetRef ref) async {
    final picker = ref.read(filePickerProvider);
    if (picker == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      final file = await picker.pickFile(
        extensions: _opmlExtensions,
        label: l10n.podcastOpmlPickerLabel,
        anyLabel: l10n.uploadsFileTypeAny,
      );
      final openRead = file?.openRead;
      if (file == null || openRead == null) return;
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in openRead()) {
        bytes.add(chunk);
      }
      await ref
          .read(subscriptionsProvider.notifier)
          .importOpml(utf8.decode(bytes.takeBytes(), allowMalformed: true));
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.podcastOpmlImported)));
    } on WaxDeckApiException catch (e) {
      // What was pasted in is what was refused, so the server's words.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(explainRefusal(l10n, e))));
    } on Exception catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(l10n.podcastFileUnreadable('$e'))),
        );
    }
  }
}

/// What the caller started and has not finished. Hidden when there is
/// nothing half-heard, so the hub leads with shows on a fresh account.
class _UpNextShelf extends ConsumerWidget {
  const _UpNextShelf();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows =
        ref.watch(upNextEpisodesProvider).value ?? const <ShelfEpisode>[];
    if (rows.isEmpty) return const SizedBox.shrink();
    final store = ref.watch(artworkStoreProvider);
    final l10n = context.l10n;
    final tiles = <MediaTileData>[
      for (final row in rows)
        MediaTileData(
          title: row.episode.title,
          subtitle: row.showTitle,
          artwork: store.source(row.episode.artUrl),
          domain: WaxDomain.podcasts,
          progress: row.progress.fractionOf(row.episode.durationMs),
          trailingText: _remaining(l10n, row),
          downloaded: row.episode.downloaded,
          // Its own handle, not the row identifier the Latest list and
          // the show's own list use. The same episode can be drawn by
          // more than one shelf on this screen, and one handle on two
          // controls makes a click a strict-mode violation rather than
          // a tap. (Unplayed and in-progress themselves are disjoint
          // now - unplayed means never started - but Latest still
          // overlaps both.)
          semanticsId: SemanticsIds.episodeContinue(row.episode.pid),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: WaxSpace.s8, bottom: WaxSpace.s16),
      child: ShelfRow(
        title: l10n.podcastUpNextTitle,
        overline: l10n.podcastUpNextOverline,
        items: tiles,
        // By position, not by title: two shows can publish an episode
        // under one name, and a tile carries no value equality, so this
        // is identity.
        onTapItem: (tile) {
          final at = tiles.indexOf(tile);
          if (at < 0) return;
          _resume(context, ref, rows[at]);
        },
      ),
    );
  }

  static String? _remaining(AppLocalizations l10n, ShelfEpisode row) {
    final left = row.episode.durationMs - row.progress.positionMs;
    if (left <= 0) return null;
    return l10n.podcastTimeLeft(formatTimecode(Duration(milliseconds: left)));
  }

  /// Resumes where the listener stopped, through the same verb every
  /// other surface plays an episode with, so an episode whose feed
  /// stopped naming audio between then and now says so rather than
  /// failing inside the player.
  static void _resume(BuildContext context, WidgetRef ref, ShelfEpisode row) {
    unawaited(
      EpisodeActions(
        ref: ref,
        showPid: row.episode.showPid,
      ).play(context, row.episode, positionMs: row.progress.positionMs),
    );
  }
}

/// The shows being followed, grouped by folder when any subscription
/// declares one.
class _Subscriptions extends ConsumerWidget {
  const _Subscriptions({required this.subscriptions});

  final List<Subscription> subscriptions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final groups = groupByFolder(subscriptions);
    final folders = groups.keys.where((name) => name.isNotEmpty).toList()
      ..sort();
    final loose = groups[''] ?? const <Subscription>[];

    // No folders: one grid, and no section header over it either. The
    // screen's own title already says what these are.
    if (folders.isEmpty) {
      return SliverPadding(
        padding: sizeClass.gutter,
        sliver: _ShowGrid(subscriptions: loose),
      );
    }
    return SliverList.list(
      children: <Widget>[
        for (final folder in folders)
          _FolderGroup(name: folder, subscriptions: groups[folder]!),
        if (loose.isNotEmpty)
          _FolderGroup(name: '', subscriptions: loose, expandable: false),
      ],
    );
  }
}

/// One folder of shows, collapsible.
class _FolderGroup extends StatefulWidget {
  const _FolderGroup({
    required this.name,
    required this.subscriptions,
    this.expandable = true,
  });

  final String name;
  final List<Subscription> subscriptions;
  final bool expandable;

  @override
  State<_FolderGroup> createState() => _FolderGroupState();
}

class _FolderGroupState extends State<_FolderGroup> {
  var _open = true;

  @override
  Widget build(BuildContext context) {
    final sizeClass = WaxSizeClass.of(context);
    final count = widget.subscriptions.length;
    return Padding(
      padding: sizeClass.gutter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.expandable)
            WaxTappable(
              semanticsId: SemanticsIds.podcastFolder(widget.name),
              label: context.l10n.podcastFolderSpoken(widget.name, count),
              selected: _open,
              onPressed: () => setState(() => _open = !_open),
              // WaxTappable adds semantics, focus, and a ring, and no
              // gesture of its own, so the row carries the tap.
              child: InkWell(
                onTap: () => setState(() => _open = !_open),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: WaxSpace.s8),
                  child: Row(
                    children: <Widget>[
                      WaxIcon(
                        _open ? WaxIcons.collapse : WaxIcons.expand,
                        size: 16,
                        color: WaxColors.of(context).textSecondary,
                      ),
                      const SizedBox(width: WaxSpace.s8),
                      Expanded(
                        child: Text(
                          widget.name,
                          style: WaxType.headline.copyWith(
                            color: WaxColors.of(context).textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        '$count',
                        style: WaxType.monoData.copyWith(
                          color: WaxColors.of(context).textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SectionHeader(title: context.l10n.podcastOtherShows),
          if (_open || !widget.expandable)
            _ShowGridBox(subscriptions: widget.subscriptions),
        ],
      ),
    );
  }
}

/// The widest a show tile is allowed to be.
const double kShowTileExtent = 180;

class _ShowGrid extends ConsumerWidget {
  const _ShowGrid({required this.subscriptions});

  final List<Subscription> subscriptions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final grid = MediaCard.gridFor(
          constraints.crossAxisExtent,
          extent: kShowTileExtent * ref.watch(gridScaleProvider),
        );
        return SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: grid.columns,
            mainAxisSpacing: WaxShellMetrics.gridGap,
            crossAxisSpacing: WaxShellMetrics.gridGap,
            mainAxisExtent: MediaCard.heightFor(context, width: grid.width),
          ),
          itemCount: subscriptions.length,
          itemBuilder: (context, index) =>
              _ShowTile(subscription: subscriptions[index], width: grid.width),
        );
      },
    );
  }
}

/// The same grid inside a box, for the folder groups, which are list
/// children rather than slivers.
class _ShowGridBox extends ConsumerWidget {
  const _ShowGridBox({required this.subscriptions});

  final List<Subscription> subscriptions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final grid = MediaCard.gridFor(
          constraints.maxWidth,
          extent: kShowTileExtent * ref.watch(gridScaleProvider),
        );
        return GridView.builder(
          shrinkWrap: true,
          // Inside the page's own scroll view: a folder holds a handful
          // of shows, so building them all costs less than a nested
          // scroller that eats the drag.
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: WaxSpace.s16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: grid.columns,
            mainAxisSpacing: WaxShellMetrics.gridGap,
            crossAxisSpacing: WaxShellMetrics.gridGap,
            mainAxisExtent: MediaCard.heightFor(context, width: grid.width),
          ),
          itemCount: subscriptions.length,
          itemBuilder: (context, index) =>
              _ShowTile(subscription: subscriptions[index], width: grid.width),
        );
      },
    );
  }
}

class _ShowTile extends ConsumerWidget {
  const _ShowTile({required this.subscription, required this.width});

  final Subscription subscription;

  /// The cell's own width, so the artwork the card draws and the height
  /// the grid reserved for it are the same measurement.
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = subscription.show;
    final unplayed = subscription.unplayedCount;
    final count = show.episodeCount;
    return MediaCard(
      data: MediaTileData(
        title: show.title,
        subtitle: show.author,
        artwork: ref.watch(artworkStoreProvider).source(show.artUrl),
        domain: WaxDomain.podcasts,
        // What is waiting, which is the number a listener opens a show
        // for. The episode count is the fallback for a server that
        // predates the field, and for a show with nothing waiting.
        trailingText: switch ((unplayed, count)) {
          (final int n, _) when n > 0 => context.l10n.podcastUnplayedCount(n),
          (_, final int n) => context.l10n.podcastEpisodeCount(n),
          _ => null,
        },
        unplayed: (unplayed ?? 0) > 0,
        semanticsId: SemanticsIds.podcast(show.pid),
      ),
      width: width,
      // A show is declared under this hub, so it is where it says it is
      // and the address bar follows.
      onTap: () => context.go(WaxRoute.show(show.pid)),
    );
  }
}

/// The newest episodes across every show being followed.
class _LatestEpisodes extends ConsumerWidget {
  const _LatestEpisodes();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest =
        ref.watch(latestEpisodesProvider).value ?? const <ShelfEpisode>[];
    if (latest.isEmpty) return const SizedBox(height: WaxSpace.s32);
    final sizeClass = WaxSizeClass.of(context);
    final store = ref.watch(artworkStoreProvider);
    final l10n = context.l10n;
    return Padding(
      padding: sizeClass.gutter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: WaxSpace.s16),
          SectionHeader(
            title: l10n.podcastLatestTitle,
            overline: l10n.podcastLatestOverline,
          ),
          for (final row in latest)
            MediaListRow(
              data: MediaTileData(
                title: row.episode.title,
                subtitle: row.showTitle,
                artwork: store.source(row.episode.artUrl),
                domain: WaxDomain.podcasts,
                trailingText: formatTimecode(
                  Duration(milliseconds: row.episode.durationMs),
                ),
                downloaded: row.episode.downloaded,
                unplayed: true,
                semanticsId: SemanticsIds.episode(row.episode.pid),
              ),
              actions: <Widget>[
                WaxIconButton(
                  glyph: WaxIcons.info,
                  label: l10n.podcastEpisodeDetails(row.episode.title),
                  size: 18,
                  semanticsId: SemanticsIds.episodeInfo(row.episode.pid),
                  // Pushed: the episode's declared parent is its show,
                  // and this is the hub, so `go` would rebuild the show
                  // beneath it and back would land there rather than
                  // here.
                  onPressed: () => context.push(
                    WaxRoute.showEpisode(row.episode.showPid, row.episode.pid),
                  ),
                ),
              ],
              // The row plays, which is what a list of new episodes is
              // for. It can: these are real episode rows, so the same
              // `hasEnclosure` rule the show's list follows applies here
              // too, and an episode with no audio in its feed falls back
              // to the fetch rather than failing in the player.
              onTap: () => unawaited(
                EpisodeActions(
                  ref: ref,
                  showPid: row.episode.showPid,
                ).play(context, row.episode),
              ),
            ),
          const SizedBox(height: WaxSpace.s32),
        ],
      ),
    );
  }
}
