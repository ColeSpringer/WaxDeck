import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../downloads/downloads_controller.dart';
import '../l10n/l10n.dart';
import '../media_view.dart';
import '../notifications/notifications_bell.dart';
import '../player/play_progress.dart';
import '../podcasts/episode_actions.dart';
import '../podcasts/podcast_shelves.dart';
import '../search/search_chrome.dart';
import '../sync/sync_providers.dart';
import '../shell/account_chrome.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../uploads/add_to_library.dart';
import '../uploads/audio_drop_area.dart';
import 'home_shelves.dart';
import 'item_shelf.dart';
import 'mix_shelf.dart';
import 'pinned_shelf.dart';

/// The landing surface: what you were listening to, what is new, and what
/// is yours and still sealed.
///
/// Shelves rather than a grid. The grid this replaces was every medium in
/// one wall of covers with a filter over it, which is a listing; each
/// medium has a hub of its own now, and what home owes a listener is the
/// handful of answers none of those hubs can give - where they left off
/// across all of them, and what in their own collection is worth opening.
///
/// Every shelf hides when it is empty, so a young library shows two
/// shelves and a full one shows eight, and neither reads as broken.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The shelves are server-backed reads, so offline they have nothing
    // to say and the screen says that instead of drawing eight error
    // states.
    final offline = ref.watch(offlineProvider);
    final canAdd = canAddToLibrary(ref);
    final l10n = context.l10n;

    return AudioDropArea(
      enabled: canAdd,
      hint: l10n.uploadsDropHint,
      onDropped: (files) => uploadPickedFiles(context, ref, files),
      child: WaxScaffold(
        title: l10n.homeTitle,
        semanticsId: SemanticsIds.homeScreen,
        actions: <Widget>[
          const SearchAction(),
          const NotificationsBell(),
          // Adding audio is a primary action and home is where it
          // belongs: every other surface is about one medium, and what
          // a listener drops in may be any of them. Top-right, because
          // that is where every hub keeps its own add - home had the
          // one floating button in the app, which read as a different
          // app's convention. Hidden without the upload right, which
          // every path behind it needs, and offline, where there is no
          // server to hand it to.
          if (canAdd)
            WaxIconButton(
              glyph: WaxIcons.add,
              label: l10n.homeAddAction,
              semanticsId: SemanticsIds.homeAdd,
              onPressed: () => showAddToLibrarySheet(context, ref),
            ),
          const AccountAction(),
        ],
        onRefresh: () => refreshHome(ref),
        slivers: <Widget>[
          if (offline) ...<Widget>[
            SliverToBoxAdapter(
              child: WaxBanner(
                message: l10n.homeOfflineMessage,
                glyph: WaxIcons.offline,
                semanticsId: SemanticsIds.offlineBanner,
              ),
            ),
            const _DownloadedShelf(),
          ],
          if (!offline) const _OnlineHome(),
          const SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s32)),
        ],
      ),
    );
  }
}

/// Home with a server to ask.
///
/// Its own widget so the probe below is read only where it is used: read
/// from the screen it would run offline too, where every request fails
/// by construction and nothing looks at the answer.
class _OnlineHome extends ConsumerWidget {
  const _OnlineHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The same gate as the app bar's add, read through the same helper:
    // this widget only mounts online, so the offline half it also asks
    // is already decided.
    final canUpload = canAddToLibrary(ref);
    final l10n = context.l10n;
    return switch (ref.watch(libraryHasAnythingProvider)) {
      // A server with nothing in it gets the first-run state rather
      // than eight empty shelves.
      AsyncData(value: false) => SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          title: l10n.homeEmptyTitle,
          message: l10n.homeEmptyMessage,
          glyph: WaxIcons.home,
          actionLabel: canUpload ? l10n.homeAddAction : null,
          onAction: canUpload
              ? () => showAddToLibrarySheet(context, ref)
              : null,
        ),
      ),
      AsyncData() => const _Shelves(),
      AsyncError(:final error) => SliverFillRemaining(
        hasScrollBody: false,
        child: ErrorState(
          title: l10n.homeLibraryLoadError,
          message: context.explain(error),
          onRetry: () => ref.invalidate(libraryHasAnythingProvider),
        ),
      ),
      _ => const SliverToBoxAdapter(
        child: SkeletonShapes(shape: SkeletonShape.shelf),
      ),
    };
  }
}

/// The shelves, in the order 6.1 lists them.
class _Shelves extends StatelessWidget {
  const _Shelves();

  @override
  Widget build(BuildContext context) => SliverMainAxisGroup(
    slivers: <Widget>[
      ItemShelf(
        shelf: 'continue',
        title: context.l10n.homeContinueTitle,
        overline: context.l10n.homeContinueOverline,
        provider: continueListeningShelfProvider,
        withProgress: true,
      ),
      // Second, under what is half-finished: a pin is the strongest
      // statement a listener makes about the library, and everything
      // below is the server's opinion rather than theirs.
      const PinnedShelf(),
      const _NewEpisodesShelf(),
      ItemShelf(
        shelf: 'recent',
        title: context.l10n.homeRecentTitle,
        overline: context.l10n.homeRecentOverline,
        provider: recentlyAddedShelfProvider,
        allLocation: WaxRoute.musicTracks,
      ),
      ItemShelf(
        shelf: 'sealed',
        title: context.l10n.homeNeverPlayedTitle,
        overline: context.l10n.homeNeverPlayedOverline,
        provider: neverPlayedShelfProvider,
      ),
      const MixShelf(),
      ItemShelf(
        shelf: 'rediscover',
        title: context.l10n.homeRediscoverTitle,
        overline: context.l10n.homeRediscoverOverline,
        provider: rediscoverShelfProvider,
      ),
      ItemShelf(
        shelf: 'most-played',
        title: context.l10n.homeMostPlayedTitle,
        overline: context.l10n.homeMostPlayedOverline,
        provider: mostPlayedShelfProvider,
      ),
    ],
  );
}

/// What this device holds, when there is no server to ask.
///
/// The one shelf that is not a server read, and the only honest thing
/// home can offer with the network gone: the grid this screen replaced
/// served the whole mirrored catalog offline, which listed mostly things
/// that had no local audio and failed on the tap. What plays offline is
/// what was downloaded, so that is what is drawn, with the manager behind
/// it. Native only, because the web build downloads nothing.
class _DownloadedShelf extends ConsumerWidget {
  const _DownloadedShelf();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries =
        ref.watch(downloadsProvider).value?.stored.toList() ??
        const <DownloadEntry>[];
    if (entries.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final store = ref.watch(artworkStoreProvider);
    final shown = entries.take(kHomeShelfCards).toList();
    final tiles = <MediaTileData>[
      for (final entry in shown)
        MediaTileData(
          title: entry.title,
          subtitle: entry.subtitle,
          artwork: waxArtwork(store, entry.item?.artUrl),
          domain: waxDomainOf(entry.mediaType),
          shape: waxShapeOf(entry.mediaType),
          downloaded: true,
          semanticsId: SemanticsIds.shelfCard('downloaded', entry.pid),
        ),
    ];
    return SliverToBoxAdapter(
      child: Semantics(
        // A region rather than a node that swallows its subtree; see
        // `ItemShelf` for why.
        container: true,
        explicitChildNodes: true,
        identifier: SemanticsIds.shelf('downloaded'),
        child: Padding(
          padding: const EdgeInsets.only(
            top: WaxSpace.s8,
            bottom: WaxSpace.s24,
          ),
          child: ShelfRow(
            title: context.l10n.homeDownloadedTitle,
            overline: context.l10n.homeDownloadedOverline,
            items: tiles,
            actionLabel: context.l10n.homeShelfShowAll,
            actionSemanticsId: SemanticsIds.shelfAll('downloaded'),
            onAction: () => context.go(WaxRoute.downloads),
            onTapItem: (tile) {
              final at = tiles.indexOf(tile);
              if (at < 0) return;
              final entry = shown[at];
              final item = entry.item;
              // A row whose catalog entry has gone is still on disk and
              // still worth listing (the manager is where it is
              // reclaimed), but there is nothing to open it as.
              if (item == null) return;
              // The position comes off the mirror rather than the
              // server, which is the whole reason the download row
              // carries one: this is the shelf most likely to be tapped
              // with no network, and resuming at zero there is the
              // failure it exists to avoid.
              openHomeItem(context, ref, item, _resume(entry.progress));
            },
          ),
        ),
      ),
    );
  }
}

/// A download row's saved position, as the shelves draw one.
PlayProgress _resume(PlayState? state) => state == null
    ? PlayProgress.none
    : PlayProgress(
        positionMs: state.positionMs,
        played: state.played,
        finished: state.finished,
      );

/// The newest episodes across the shows the caller follows.
///
/// Its own shelf rather than a discovery list scoped to podcasts: the
/// podcast domain's listing is subscription-scoped, and a cross-library
/// list is not - a fresh episode of a show nobody follows is not news.
class _NewEpisodesShelf extends ConsumerWidget {
  const _NewEpisodesShelf();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows =
        ref.watch(latestEpisodesProvider).value ?? const <ShelfEpisode>[];
    if (rows.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final store = ref.watch(artworkStoreProvider);
    final tiles = <MediaTileData>[
      for (final row in rows)
        MediaTileData(
          title: row.episode.title,
          subtitle: row.showTitle,
          artwork: waxArtwork(store, row.episode.artUrl),
          domain: WaxDomain.podcasts,
          unplayed: true,
          downloaded: row.episode.downloaded,
          semanticsId: SemanticsIds.shelfCard('episodes', row.episode.pid),
        ),
    ];
    return SliverToBoxAdapter(
      child: Semantics(
        // A region rather than a node that swallows its subtree; see
        // `ItemShelf` for why.
        container: true,
        explicitChildNodes: true,
        identifier: SemanticsIds.shelf('episodes'),
        child: Padding(
          padding: const EdgeInsets.only(bottom: WaxSpace.s24),
          child: ShelfRow(
            title: context.l10n.homeEpisodesTitle,
            overline: context.l10n.homeEpisodesOverline,
            items: tiles,
            actionLabel: context.l10n.homeShelfShowAll,
            actionSemanticsId: SemanticsIds.shelfAll('episodes'),
            onAction: () => context.go(WaxRoute.podcasts),
            onTapItem: (tile) {
              final at = tiles.indexOf(tile);
              if (at < 0) return;
              final row = rows[at];
              unawaited(
                EpisodeActions(
                  ref: ref,
                  showPid: row.episode.showPid,
                ).play(context, row.episode),
              );
            },
          ),
        ),
      ),
    );
  }
}
