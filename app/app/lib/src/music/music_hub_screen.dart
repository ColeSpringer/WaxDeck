import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../auth/auth_controller.dart';
import '../home/home_shelves.dart';
import '../home/item_shelf.dart';
import '../home/mix_shelf.dart';
import '../l10n/l10n.dart';
import '../search/search_chrome.dart';
import '../shell/account_chrome.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../sync/sync_providers.dart';
import '../uploads/add_to_library.dart';
import 'music_controllers.dart';

/// One tile on the hub: somewhere to go, and how much is behind it.
class _HubTile {
  const _HubTile({
    required this.name,
    required this.label,
    required this.glyph,
    required this.location,
    this.dimension,
  });

  final String name;
  final String label;
  final WaxGlyph glyph;
  final String location;

  /// Set for the tiles whose size the facet endpoint can answer. Tracks
  /// and playlists have no bucket count to read, so they carry a label
  /// and nothing else rather than a number invented for symmetry.
  final MusicDimension? dimension;

  factory _HubTile.forDimension(
    AppLocalizations l10n,
    MusicDimension dimension,
  ) => _HubTile(
    name: dimension.segment,
    label: dimension.titleOf(l10n),
    glyph: dimension.glyph,
    location: WaxRoute.musicIndex(dimension),
    dimension: dimension,
  );
}

/// The ways in, in the order 6.3 lists them. A dimension's tile takes
/// everything from the dimension, so a renamed segment cannot leave
/// tiles pointing at locations the table no longer declares.
List<_HubTile> _tiles(AppLocalizations l10n) => <_HubTile>[
  for (final dimension in <MusicDimension>[
    MusicDimension.artists,
    MusicDimension.albums,
  ])
    _HubTile.forDimension(l10n, dimension),
  _HubTile(
    name: 'tracks',
    label: l10n.musicTracksTitle,
    glyph: WaxIcons.music,
    location: WaxRoute.musicTracks,
  ),
  for (final dimension in <MusicDimension>[
    MusicDimension.genres,
    MusicDimension.years,
  ])
    _HubTile.forDimension(l10n, dimension),
  _HubTile(
    name: 'playlists',
    label: l10n.playlistsTitle,
    glyph: WaxIcons.playlists,
    location: WaxRoute.playlists,
  ),
];

/// The music domain's front door: the ways into the collection, and what
/// is worth opening in it.
///
/// The shelves are home's, scoped to music by the browse endpoint's
/// media-type filter. The same component and the same reads: a shelf of
/// covers is a shelf of covers, and two implementations would drift on
/// which of them draws a resume ring.
class MusicHubScreen extends ConsumerWidget {
  const MusicHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final l10n = context.l10n;
    final tiles = _tiles(l10n);

    return WaxScaffold(
      title: l10n.musicTitle,
      actions: const <Widget>[SearchAction(), AccountAction()],
      slivers: <Widget>[
        // Compact browses through a tile grid, two to a row. Anything
        // wider gets the slim chip row 6.3 asks for, so the content
        // shelves lead the page instead of a wall of navigation.
        if (sizeClass.isCompact)
          SliverPadding(
            padding: sizeClass.gutter + const EdgeInsets.only(top: WaxSpace.s8),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: WaxSpace.s12,
                crossAxisSpacing: WaxSpace.s12,
                mainAxisExtent: _IndexTile.extentFor(context),
              ),
              itemCount: tiles.length,
              itemBuilder: (context, index) => _IndexTile(tile: tiles[index]),
            ),
          )
        else
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  sizeClass.gutter + const EdgeInsets.only(top: WaxSpace.s8),
              child: Wrap(
                spacing: WaxSpace.s8,
                runSpacing: WaxSpace.s8,
                children: <Widget>[
                  for (final tile in tiles) _IndexChip(tile: tile),
                ],
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s24)),
        ItemShelf(
          shelf: 'music-recent',
          title: l10n.musicShelfRecentTitle,
          overline: l10n.musicShelfRecentOverline,
          provider: musicRecentlyAddedShelfProvider,
          allLocation: WaxRoute.musicTracks,
        ),
        ItemShelf(
          shelf: 'music-most-played',
          title: l10n.musicShelfMostPlayedTitle,
          overline: l10n.musicShelfMostPlayedOverline,
          provider: musicMostPlayedShelfProvider,
        ),
        ItemShelf(
          shelf: 'music-starred',
          title: l10n.musicShelfStarredTitle,
          overline: l10n.musicShelfStarredOverline,
          provider: musicStarredShelfProvider,
        ),
        const MixShelf(),
        const _AllEmptyInvitation(),
        const SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s32)),
      ],
    );
  }
}

/// The first-run invitation, drawn only when every shelf has answered
/// and none of them has anything: a music library that is empty, not one
/// that is loading or failing, which have their own honest states now.
class _AllEmptyInvitation extends ConsumerWidget {
  const _AllEmptyInvitation();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shelves = <AsyncValue<HomeShelfItems>>[
      ref.watch(musicRecentlyAddedShelfProvider),
      ref.watch(musicMostPlayedShelfProvider),
      ref.watch(musicStarredShelfProvider),
    ];
    final mixes = ref.watch(mixCardsProvider);
    // "Answered" is hasValue, the same test for all four reads: a
    // refresh is loading WITH a value, so an isLoading test here made
    // the invitation vanish for every refetch a sync event fans out.
    // Mixes settle on an error too - they are an extra and their shelf
    // hides itself then, which must not hold the invitation hostage.
    final answered =
        shelves.every((s) => s.hasValue) && (mixes.hasValue || mixes.hasError);
    final empty =
        shelves.every((s) => (s.value?.items ?? const []).isEmpty) &&
        (mixes.value ?? const []).isEmpty;
    if (!answered || !empty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final canUpload =
        ref.watch(authControllerProvider).value?.user?.uploadEnabled ?? false;
    final offline = ref.watch(offlineProvider);
    // The same gate home's add wears: the upload right, and a server to
    // hand the files to.
    final offerAdd = canUpload && !offline;
    final l10n = context.l10n;
    return SliverFillRemaining(
      hasScrollBody: false,
      child: EmptyState(
        title: l10n.musicEmptyTitle,
        message: l10n.musicHubEmptyMessage,
        glyph: WaxIcons.music,
        actionLabel: offerAdd ? l10n.musicHubAddToLibrary : null,
        onAction: offerAdd ? () => showAddToLibrarySheet(context, ref) : null,
      ),
    );
  }
}

/// One index entry as a slim chip: glyph, label, and the count where a
/// dimension can answer one. The desktop face of [_IndexTile].
class _IndexChip extends ConsumerWidget {
  const _IndexChip({required this.tile});

  final _HubTile tile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    final dimension = tile.dimension;
    final count = dimension == null
        ? null
        : ref.watch(musicIndexCountProvider(dimension)).value;

    return WaxTappable(
      semanticsId: SemanticsIds.musicTile(tile.name),
      label: count == null
          ? tile.label
          : context.l10n.musicHubTileSpoken(tile.label, count.label),
      onPressed: () => context.go(tile.location),
      borderRadius: WaxRadius.pill,
      child: Material(
        color: colors.surface1,
        borderRadius: WaxRadius.pill,
        child: InkWell(
          onTap: () => context.go(tile.location),
          borderRadius: WaxRadius.pill,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: WaxSpace.s16,
              vertical: WaxSpace.s8,
            ),
            decoration: BoxDecoration(
              borderRadius: WaxRadius.pill,
              border: Border.all(color: colors.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                WaxIcon(tile.glyph, size: 16, color: colors.accent),
                const SizedBox(width: WaxSpace.s8),
                Text(
                  tile.label,
                  style: WaxType.label.copyWith(color: colors.textPrimary),
                ),
                if (count != null) ...<Widget>[
                  const SizedBox(width: WaxSpace.s8),
                  Text(
                    count.label,
                    style: WaxType.monoData.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IndexTile extends ConsumerWidget {
  const _IndexTile({required this.tile});

  final _HubTile tile;

  static const double _glyph = 22;

  /// How tall a tile has to be at the current text scale.
  ///
  /// A fixed number was wrong from about 1.25x: the label and the count
  /// grow with the OS setting and the glyph does not, and a grid cell
  /// that cannot fit its child overflows rather than reflowing. The same
  /// reason [MediaListRow.heightFor] exists, and asked the same way.
  static double extentFor(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    double line(TextStyle style) =>
        scaler.scale(style.height! * style.fontSize!).ceilToDouble();
    return WaxSpace.s12 * 2 +
        _glyph +
        WaxSpace.s8 +
        line(WaxType.titleItem) +
        line(WaxType.monoData);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    final dimension = tile.dimension;
    final count = dimension == null
        ? null
        : ref.watch(musicIndexCountProvider(dimension)).value;

    return WaxTappable(
      semanticsId: SemanticsIds.musicTile(tile.name),
      label: count == null
          ? tile.label
          : context.l10n.musicHubTileSpoken(tile.label, count.label),
      onPressed: () => context.go(tile.location),
      borderRadius: WaxRadius.card,
      child: Material(
        color: colors.surface1,
        borderRadius: WaxRadius.card,
        child: InkWell(
          onTap: () => context.go(tile.location),
          borderRadius: WaxRadius.card,
          child: Container(
            padding: const EdgeInsets.all(WaxSpace.s12),
            decoration: BoxDecoration(
              borderRadius: WaxRadius.card,
              border: Border.all(color: colors.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                WaxIcon(tile.glyph, size: _glyph, color: colors.accent),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      tile.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WaxType.titleItem.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    if (count != null)
                      Text(
                        count.label,
                        style: WaxType.monoData.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
