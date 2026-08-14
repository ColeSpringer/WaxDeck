import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../l10n/l10n.dart';
import '../media_view.dart';
import '../search/search_chrome.dart';
import '../settings/client_prefs.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'playlist_create.dart';
import 'playlist_import.dart';
import 'playlists_controller.dart';

/// The caller's playlists and every shared one, as covers. The section
/// headers only appear where both exist: one over the whole screen names
/// nothing.
class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playlistsProvider);
    final all = state.value ?? const <Playlist>[];
    final mine = <Playlist>[
      for (final pl in all)
        if (pl.isOwner) pl,
    ];
    final shared = <Playlist>[
      for (final pl in all)
        if (!pl.isOwner) pl,
    ];
    final split = mine.isNotEmpty && shared.isNotEmpty;
    final l10n = context.l10n;

    return WaxScaffold(
      title: l10n.playlistsTitle,
      actions: <Widget>[
        WaxIconButton(
          glyph: WaxIcons.add,
          label: l10n.playlistsNew,
          semanticsId: SemanticsIds.playlistAdd,
          onPressed: () => unawaited(showCreatePlaylistDialog(context)),
        ),
        const PlaylistImportMenu(),
        const SearchAction(),
      ],
      slivers: <Widget>[
        switch (state) {
          AsyncData() when all.isEmpty => SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: l10n.playlistsEmptyTitle,
              message: l10n.playlistsEmptyMessage,
              glyph: WaxIcons.playlists,
              actionLabel: l10n.playlistsNew,
              onAction: () => unawaited(showCreatePlaylistDialog(context)),
            ),
          ),
          AsyncData() => _Sections(mine: mine, shared: shared, split: split),
          AsyncError(:final error) => SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(
              title: l10n.playlistsLoadError,
              message: context.explain(error),
              onRetry: () => ref.invalidate(playlistsProvider),
            ),
          ),
          _ => const SliverToBoxAdapter(
            child: SkeletonShapes(shape: SkeletonShape.grid),
          ),
        },
        const SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s32)),
      ],
    );
  }
}

/// Yours, then the server's, as one sliver.
class _Sections extends StatelessWidget {
  const _Sections({
    required this.mine,
    required this.shared,
    required this.split,
  });

  final List<Playlist> mine;
  final List<Playlist> shared;

  /// Whether headers are drawn at all.
  final bool split;

  @override
  Widget build(BuildContext context) {
    final sizeClass = WaxSizeClass.of(context);
    final l10n = context.l10n;
    return SliverPadding(
      padding: sizeClass.gutter,
      sliver: SliverMainAxisGroup(
        slivers: <Widget>[
          if (split)
            SliverToBoxAdapter(
              child: SectionHeader(title: l10n.playlistsSectionYours),
            ),
          if (mine.isNotEmpty) _PlaylistGrid(playlists: mine),
          if (split)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: WaxSpace.s24),
                child: SectionHeader(title: l10n.playlistsSectionShared),
              ),
            ),
          if (shared.isNotEmpty) _PlaylistGrid(playlists: shared),
        ],
      ),
    );
  }
}

class _PlaylistGrid extends ConsumerWidget {
  const _PlaylistGrid({required this.playlists});

  final List<Playlist> playlists;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final store = ref.watch(artworkStoreProvider);
    final l10n = context.l10n;
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final grid = MediaCard.gridFor(
          constraints.crossAxisExtent,
          extent: sizeClass.gridExtent * ref.watch(gridScaleProvider),
        );
        return SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: grid.columns,
            mainAxisSpacing: WaxShellMetrics.gridGap,
            crossAxisSpacing: WaxShellMetrics.gridGap,
            mainAxisExtent: MediaCard.heightFor(context, width: grid.width),
          ),
          itemCount: playlists.length,
          itemBuilder: (context, index) {
            final playlist = playlists[index];
            return MediaCard(
              data: MediaTileData(
                title: playlist.name,
                subtitle: playlistByline(l10n, playlist),
                trailingText: playlistSize(l10n, playlist),
                artwork: waxArtwork(store, playlist.artUrl),
                badge: playlist.isSmart ? l10n.playlistSmart : null,
                semanticsId: SemanticsIds.playlist(playlist.pid),
              ),
              width: grid.width,
              // Gone to: a playlist is a link, declared under here.
              onTap: () => context.go(WaxRoute.playlist(playlist.pid)),
            );
          },
        );
      },
    );
  }
}

/// Whose playlist this is, where that is not the person looking. Null on
/// your own, where it would be a column of noise.
String? playlistByline(AppLocalizations l10n, Playlist playlist) {
  if (playlist.isOwner) {
    return playlist.isShared ? l10n.playlistSharedByYou : null;
  }
  return l10n.playlistSharedBy(playlist.ownerName);
}

/// How much is in a playlist. A smart list's count is omitted from list
/// pages, so its card carries no number rather than a wrong one.
String? playlistSize(AppLocalizations l10n, Playlist playlist) {
  final count = playlist.itemCount;
  return count == null ? null : l10n.playlistItemCount(count);
}
