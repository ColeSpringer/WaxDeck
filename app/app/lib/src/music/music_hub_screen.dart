import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../home/home_shelves.dart';
import '../home/item_shelf.dart';
import '../search/search_chrome.dart';
import '../shell/account_chrome.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
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

  factory _HubTile.forDimension(MusicDimension dimension) => _HubTile(
    name: dimension.segment,
    label: dimension.label,
    glyph: dimension.glyph,
    location: WaxRoute.musicIndex(dimension),
    dimension: dimension,
  );
}

/// The ways in, in the order 6.3 lists them.
///
/// A dimension's tile takes its label, glyph, and location from the
/// dimension rather than repeating them: a renamed segment would
/// otherwise leave six tiles pointing at locations the table no longer
/// declares, and nothing here would notice.
final _tiles = <_HubTile>[
  for (final dimension in <MusicDimension>[
    MusicDimension.artists,
    MusicDimension.albums,
  ])
    _HubTile.forDimension(dimension),
  _HubTile(
    name: 'tracks',
    label: 'Tracks',
    glyph: WaxIcons.music,
    location: WaxRoute.musicTracks,
  ),
  for (final dimension in <MusicDimension>[
    MusicDimension.genres,
    MusicDimension.years,
  ])
    _HubTile.forDimension(dimension),
  _HubTile(
    name: 'playlists',
    label: 'Playlists',
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
    // Compact lays the tiles out two to a row; anything wider fits them
    // all across one, which is the chip row 6.3 asks for on desktop.
    final columns = sizeClass.isCompact ? 2 : 3;

    return WaxScaffold(
      title: 'Music',
      actions: const <Widget>[SearchAction(), AccountAction()],
      slivers: <Widget>[
        SliverPadding(
          padding: sizeClass.gutter + const EdgeInsets.only(top: WaxSpace.s8),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: WaxSpace.s12,
              crossAxisSpacing: WaxSpace.s12,
              mainAxisExtent: _IndexTile.extentFor(context),
            ),
            itemCount: _tiles.length,
            itemBuilder: (context, index) => _IndexTile(tile: _tiles[index]),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s24)),
        ItemShelf(
          shelf: 'music-recent',
          title: 'Recently added',
          overline: 'New to the collection',
          provider: musicRecentlyAddedShelfProvider,
          allLocation: WaxRoute.musicTracks,
        ),
        ItemShelf(
          shelf: 'music-most-played',
          title: 'Most played',
          overline: 'What you come back to',
          provider: musicMostPlayedShelfProvider,
        ),
        ItemShelf(
          shelf: 'music-starred',
          title: 'Starred',
          overline: 'Kept on purpose',
          provider: musicStarredShelfProvider,
        ),
        const SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s32)),
      ],
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
      label: count == null ? tile.label : '${tile.label}, ${count.label}',
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
