import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../providers.dart';
import '../search/search_chrome.dart';
import '../shell/account_chrome.dart';
import '../settings/client_prefs.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../uploads/file_picker_port.dart';
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

    return WaxScaffold(
      title: 'Podcasts',
      actions: <Widget>[
        WaxIconButton(
          glyph: WaxIcons.add,
          label: 'Add subscription',
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
              title: 'No shows yet',
              message:
                  'Follow a show and its new episodes turn up here as the '
                  'feed publishes them.',
              glyph: WaxIcons.podcasts,
              actionLabel: 'Add a show',
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
              title: 'Could not load your shows',
              message: error is WaxDeckApiException
                  ? error.message
                  : 'The server did not answer.',
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
    return WaxMenuButton<String>(
      glyph: WaxIcons.more,
      label: 'More',
      semanticsId: SemanticsIds.podcastOverflow,
      items: <WaxMenuItem<String>>[
        for (final choice in SubscriptionSort.values)
          WaxMenuItem<String>(
            value: 'sort:${choice.name}',
            label: 'Sort by ${choice.label.toLowerCase()}',
            selected: choice == sort,
            semanticsId: SemanticsIds.podcastSort(choice.name),
          ),
        const WaxMenuItem<String>(
          value: 'export',
          label: 'Export OPML',
          semanticsId: SemanticsIds.podcastOpmlExport,
        ),
        // Hidden without a picker, the contract every pick affordance in
        // this app follows: a platform with no file dialog would
        // otherwise offer an import that cannot open one.
        if (picker != null)
          const WaxMenuItem<String>(
            value: 'import',
            label: 'Import OPML',
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
    final String opml;
    try {
      opml = await ref.read(repositoryProvider).exportOpml();
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export OPML'),
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
            label: 'Close',
            kind: WaxButtonKind.text,
            onPressed: () => Navigator.of(context).pop(),
          ),
          WaxButton(
            label: 'Copy',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: opml));
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(content: Text('Subscriptions copied as OPML')),
                );
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
    try {
      final file = await picker.pickFile(
        extensions: _opmlExtensions,
        label: 'OPML',
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
        ..showSnackBar(const SnackBar(content: Text('Subscriptions imported')));
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } on Exception catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Could not read that file: $e')));
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
    final tiles = <MediaTileData>[
      for (final row in rows)
        MediaTileData(
          title: row.episode.title,
          subtitle: row.showTitle,
          artwork: store.source(row.episode.artUrl),
          domain: WaxDomain.podcasts,
          progress: row.progress.fractionOf(row.episode.durationMs),
          trailingText: _remaining(row),
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
        title: 'Up next',
        overline: 'Half heard',
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

  static String? _remaining(ShelfEpisode row) {
    final left = row.episode.durationMs - row.progress.positionMs;
    if (left <= 0) return null;
    return '${formatTimecode(Duration(milliseconds: left))} left';
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
              label:
                  '${widget.name}, $count '
                  '${count == 1 ? 'show' : 'shows'}',
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
            const SectionHeader(title: 'Other shows'),
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
          (final int n, _) when n > 0 => '$n unplayed',
          (_, final int n) => '$n ${n == 1 ? 'episode' : 'episodes'}',
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
    return Padding(
      padding: sizeClass.gutter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: WaxSpace.s16),
          const SectionHeader(title: 'Latest episodes', overline: 'New'),
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
                  label: 'Details for ${row.episode.title}',
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

/// URL entry plus a source-type toggle; the subscribe call surfaces
/// server errors (feed-unreachable and friends) as a SnackBar.
class SubscribeDialog extends ConsumerStatefulWidget {
  const SubscribeDialog({super.key});

  @override
  ConsumerState<SubscribeDialog> createState() => _SubscribeDialogState();
}

class _SubscribeDialogState extends ConsumerState<SubscribeDialog> {
  final _urlController = TextEditingController();
  var _sourceType = 'rss';
  var _busy = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _subscribe() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || _busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(subscriptionsProvider.notifier)
          .subscribe(url: url, sourceType: _sourceType);
      navigator.pop();
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add subscription'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // No Semantics identifier wrapper: on the web it would mint a
          // second, disabled text-field node beside the real input.
          // Tests locate the field by its label, like the login form.
          TextField(
            key: const Key('podcast-url-field'),
            controller: _urlController,
            decoration: const InputDecoration(labelText: 'Feed or channel URL'),
            keyboardType: TextInputType.url,
            autofocus: true,
          ),
          const SizedBox(height: WaxSpace.s12),
          WaxSegmented(
            label: 'Source',
            segments: const <WaxSegment>[
              WaxSegment(name: 'rss', label: 'RSS'),
              WaxSegment(name: 'youtube', label: 'YouTube'),
            ],
            selected: _sourceType,
            onSelect: (name) => setState(() => _sourceType = name),
          ),
        ],
      ),
      actions: <Widget>[
        WaxButton(
          label: 'Cancel',
          kind: WaxButtonKind.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        WaxButton(
          label: 'Subscribe',
          semanticsId: SemanticsIds.podcastSubscribeConfirm,
          onPressed: _busy ? null : _subscribe,
        ),
      ],
    );
  }
}
