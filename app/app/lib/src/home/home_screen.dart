import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../downloads/downloads_controller.dart';
import '../l10n/l10n.dart';
import '../library/item_menu.dart';
import '../media_view.dart';
import '../notifications/notifications_bell.dart';
import '../player/play_progress.dart';
import '../podcasts/episode_actions.dart';
import '../podcasts/podcast_shelves.dart';
import '../review/review_controller.dart';
import '../search/search_chrome.dart';
import '../sync/sync_providers.dart';
import '../shell/account_chrome.dart';
import '../shell/async_sliver_face.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import '../uploads/add_to_library.dart';
import '../uploads/audio_drop_area.dart';
import '../uploads/uploads_controller.dart';
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
      formats: dropFormats(ref),
      hint: l10n.uploadsDropHint,
      onDropped: (files) => uploadPickedFiles(context, ref, files),
      onSkipped: ({required unsupported, required drm, required nothingKept}) =>
          reportSkippedFiles(
            ref.read(shellMessengerProvider.notifier),
            l10n,
            unsupported: unsupported,
            drm: drm,
            nothingKept: nothingKept,
          ),
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
    // This provider rides the catalog fan-out, so every catalog event
    // rebuilds it into an AsyncLoading carrying the previous answer -
    // which a switch on the runtime type matches nowhere, and the whole
    // screen blanks to a skeleton and back. Whether the library holds
    // anything does not change on a scan tick.
    return SliverMainAxisGroup(
      slivers: <Widget>[
        // Above the has-anything gate on purpose: the person this
        // notice matters most to has just uploaded into an empty
        // library, whose home is the first-run invitation - exactly the
        // screen that otherwise says their music does not exist.
        const _ReviewPendingNotice(),
        AsyncSliverFace<bool>(
          state: ref.watch(libraryHasAnythingProvider),
          skeleton: SkeletonShape.shelf,
          errorTitle: l10n.homeLibraryLoadError,
          onRetry: () => ref.invalidate(libraryHasAnythingProvider),
          // A server with nothing in it gets the first-run state rather
          // than eight empty shelves.
          isEmpty: (hasAnything) => !hasAnything,
          empty: (context) => SliverFillRemaining(
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
          builder: (context, _) => const _Shelves(),
        ),
      ],
    );
  }
}

/// The slim door onto review while the caller's own additions wait
/// there. What was added with identification on is in the queue rather
/// than on the shelves, and without this nothing on home says so - the
/// "added music and home never refreshed" report was this silence.
/// Hidden the moment the count is zero, unknown, or the caller cannot
/// upload (their queue view is empty by construction).
class _ReviewPendingNotice extends ConsumerWidget {
  const _ReviewPendingNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The same gate as the review nav entry: the endpoint scopes rather
    // than refuses, but an account that cannot add has nothing waiting.
    if (!canAddToLibrary(ref)) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final count = ref.watch(pendingReviewCountProvider).value ?? 0;
    if (count == 0) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final l10n = context.l10n;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(bottom: WaxSpace.s16),
        // The notice tone's own info glyph, not a checkmark: a check
        // reads as done, the opposite of waiting.
        child: WaxBanner(
          tone: WaxBannerTone.notice,
          message: l10n.homeReviewPending(count),
          semanticsId: SemanticsIds.homeReviewPending,
          actionLabel: l10n.commonOpenReview,
          actionSemanticsId: SemanticsIds.homeReviewPendingOpen,
          // Gone to, not pushed: the queue is a canonical destination
          // with a nav entry of its own.
          onAction: () => context.go(WaxRoute.review),
        ),
      ),
    );
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
        provider: recentlyAddedShelfProvider,
        allLocation: WaxRoute.musicTracks,
      ),
      ItemShelf(
        shelf: 'sealed',
        title: context.l10n.homeNeverPlayedTitle,
        provider: neverPlayedShelfProvider,
      ),
      const MixShelf(),
      ItemShelf(
        shelf: 'rediscover',
        title: context.l10n.homeRediscoverTitle,
        provider: rediscoverShelfProvider,
      ),
      ItemShelf(
        shelf: 'most-played',
        title: context.l10n.homeMostPlayedTitle,
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
            items: tiles,
            actionLabel: context.l10n.homeShelfShowAll,
            actionSemanticsId: SemanticsIds.shelfAll('downloaded'),
            backSemanticsId: SemanticsIds.shelfBack('downloaded'),
            forwardSemanticsId: SemanticsIds.shelfForward('downloaded'),
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
            onPlayItem: (tile) {
              final at = tiles.indexOf(tile);
              if (at < 0) return;
              final item = shown[at].item;
              if (item == null) return;
              playHomeItem(ref, item, _resume(shown[at].progress));
            },
          ),
        ),
      ),
    );
  }
}

/// A download row's saved position, as the shelves draw one.
PlayProgress _resume(PlayState? state) =>
    state == null ? PlayProgress.none : PlayProgress.of(state);

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
          // The card clamps every line, so the full name lives on the
          // hover tooltip, as the item shelves' cards do.
          tooltip: <String?>[
            row.episode.title,
            row.showTitle,
          ].nonNulls.join('\n'),
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
            items: tiles,
            actionLabel: context.l10n.homeShelfShowAll,
            actionSemanticsId: SemanticsIds.shelfAll('episodes'),
            backSemanticsId: SemanticsIds.shelfBack('episodes'),
            forwardSemanticsId: SemanticsIds.shelfForward('episodes'),
            onAction: () => context.go(WaxRoute.podcasts),
            // A tap opens the episode's own screen, the way every other
            // shelf's tap opens what the card is about; the hover play
            // affordance is what plays it. The shelf used to play on
            // tap, which made it the one shelf whose cards could not be
            // looked at first. The canonical location, with the show in
            // the path: this shelf holds the show pid, so it does not
            // take the show-less route the generic shelves fall back to
            // - one card, one location, whichever way it is opened.
            onTapItem: (tile) {
              final at = tiles.indexOf(tile);
              if (at < 0) return;
              final row = rows[at];
              unawaited(
                context.push(
                  WaxRoute.showEpisode(row.episode.showPid, row.episode.pid),
                ),
              );
            },
            onPlayItem: (tile) {
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
            onMoreItem: (tile) {
              final at = tiles.indexOf(tile);
              if (at < 0) return;
              unawaited(_showEpisodeMenu(context, ref, rows[at]));
            },
          ),
        ),
      ),
    );
  }

  /// The episode card's overflow: play it, open it, edit it. This
  /// shelf's own sheet rather than the shared item menu, because an
  /// episode card with a show pid in hand has verbs the generic menu
  /// cannot offer.
  Future<void> _showEpisodeMenu(
    BuildContext context,
    WidgetRef ref,
    ShelfEpisode row,
  ) async {
    final episode = row.episode;
    // Captured before the sheet, which outlives what opened it; the
    // shelf's own ref stays for EpisodeActions, which needs a live one
    // and whose host - the screen, not a row - is what the modal sheet
    // holds on screen.
    final router = GoRouter.of(context);
    await showWaxOptionSheet(
      context,
      builder: (sheetContext) => Consumer(
        builder: (_, sheetRef, _) {
          final l10n = sheetContext.l10n;
          void close() => Navigator.of(sheetContext).pop();
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              WaxOptionRow(
                title: l10n.playerPlay,
                glyph: WaxIcons.play,
                semanticsId: SemanticsIds.homeEpisodePlay,
                onTap: () {
                  close();
                  unawaited(
                    EpisodeActions(
                      ref: ref,
                      showPid: episode.showPid,
                    ).play(context, episode),
                  );
                },
              ),
              WaxOptionRow(
                title: l10n.homeEpisodeInfo,
                subtitle: row.showTitle,
                glyph: WaxIcons.podcasts,
                semanticsId: SemanticsIds.homeEpisodeInfo,
                onTap: () {
                  close();
                  unawaited(
                    router.push(
                      WaxRoute.showEpisode(episode.showPid, episode.pid),
                    ),
                  );
                },
              ),
              if (mayOfferItemEdit(sheetRef))
                WaxOptionRow(
                  title: l10n.reviewEditMetadata,
                  glyph: WaxIcons.edit,
                  semanticsId: SemanticsIds.editMetadata(episode.pid),
                  onTap: () {
                    close();
                    unawaited(router.push(WaxRoute.metadata(episode.pid)));
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
