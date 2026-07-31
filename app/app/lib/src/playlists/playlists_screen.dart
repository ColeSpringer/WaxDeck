import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
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

    return WaxScaffold(
      title: 'Playlists',
      actions: <Widget>[
        WaxIconButton(
          glyph: WaxIcons.add,
          label: 'New playlist',
          semanticsId: SemanticsIds.playlistAdd,
          onPressed: () => unawaited(showCreatePlaylistDialog(context)),
        ),
        const PlaylistImportMenu(),
        const SearchAction(),
      ],
      slivers: <Widget>[
        switch (state) {
          AsyncData() when all.isEmpty => const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: 'No playlists yet',
              message:
                  'Make one from the plus above, or add a track to a new '
                  'list from anywhere it is playing. A smart playlist '
                  'writes itself from rules and keeps up as the library '
                  'grows.',
              glyph: WaxIcons.playlists,
            ),
          ),
          AsyncData() => _Sections(mine: mine, shared: shared, split: split),
          AsyncError(:final error) => SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(
              title: 'Could not load your playlists',
              message: error is WaxDeckApiException
                  ? error.message
                  : 'The server did not answer.',
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
    return SliverPadding(
      padding: sizeClass.gutter,
      sliver: SliverMainAxisGroup(
        slivers: <Widget>[
          if (split)
            const SliverToBoxAdapter(child: SectionHeader(title: 'Yours')),
          if (mine.isNotEmpty) _PlaylistGrid(playlists: mine),
          if (split)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: WaxSpace.s24),
                child: SectionHeader(title: 'Shared with the server'),
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
                subtitle: playlistByline(playlist),
                trailingText: playlistSize(playlist),
                artwork: waxArtwork(store, playlist.artUrl),
                badge: playlist.isSmart ? 'Smart' : null,
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
String? playlistByline(Playlist playlist) {
  if (playlist.isOwner) return playlist.isShared ? 'Shared by you' : null;
  return 'Shared by ${playlist.ownerName}';
}

/// How much is in a playlist. A smart list's count is omitted from list
/// pages, so its card carries no number rather than a wrong one.
String? playlistSize(Playlist playlist) {
  final count = playlist.itemCount;
  if (count == null) return null;
  return count == 1 ? '1 item' : '$count items';
}
