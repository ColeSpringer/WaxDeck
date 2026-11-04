import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:go_router/go_router.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../music/music_controllers.dart';

/// One tile on a hub: somewhere to go, and how much is behind it.
class HubTile {
  const HubTile({
    required this.name,
    required this.label,
    required this.glyph,
    required this.location,
    this.count,
  });

  final String name;
  final String label;
  final WaxGlyph glyph;
  final String location;

  /// Set for the tiles whose size something can answer. Tracks and
  /// playlists have no bucket count to read, so they carry a label and
  /// nothing else rather than a number invented for symmetry.
  final ProviderListenable<AsyncValue<MusicIndexCount>>? count;
}

/// A hub's ways in, as a sliver.
///
/// Compact browses through a tile grid, two to a row. Anything wider gets
/// a slim chip row instead, so the content shelves lead the page instead
/// of a wall of navigation.
class HubTiles extends StatelessWidget {
  const HubTiles({required this.tiles, required this.semanticsIdOf, super.key});

  final List<HubTile> tiles;

  /// Each tile's handle, from its name: each hub keeps its own ids.
  final String Function(String name) semanticsIdOf;

  @override
  Widget build(BuildContext context) {
    final sizeClass = WaxSizeClass.of(context);
    final padding = sizeClass.gutter + const EdgeInsets.only(top: WaxSpace.s8);
    if (sizeClass.isCompact) {
      return SliverPadding(
        padding: padding,
        sliver: SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: WaxSpace.s12,
            crossAxisSpacing: WaxSpace.s12,
            mainAxisExtent: _IndexTile.extentFor(context),
          ),
          itemCount: tiles.length,
          itemBuilder: (context, index) => _IndexTile(
            tile: tiles[index],
            semanticsId: semanticsIdOf(tiles[index].name),
          ),
        ),
      );
    }
    return SliverToBoxAdapter(
      child: Padding(
        padding: padding,
        child: Wrap(
          spacing: WaxSpace.s8,
          runSpacing: WaxSpace.s8,
          children: <Widget>[
            for (final tile in tiles)
              _IndexChip(tile: tile, semanticsId: semanticsIdOf(tile.name)),
          ],
        ),
      ),
    );
  }
}

MusicIndexCount? _countOf(WidgetRef ref, HubTile tile) {
  final count = tile.count;
  return count == null ? null : ref.watch(count).value;
}

String _spoken(BuildContext context, HubTile tile, MusicIndexCount? count) =>
    count == null
    ? tile.label
    : context.l10n.libraryHubTileSpoken(tile.label, count.label);

/// One index entry as a slim chip: glyph, label, and the count where one
/// can be answered. The desktop face of [_IndexTile].
class _IndexChip extends ConsumerWidget {
  const _IndexChip({required this.tile, required this.semanticsId});

  final HubTile tile;
  final String semanticsId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    final count = _countOf(ref, tile);

    return WaxInkTappable(
      semanticsId: semanticsId,
      label: _spoken(context, tile, count),
      onPressed: () => context.go(tile.location),
      color: colors.surface1,
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
                style: WaxType.monoData.copyWith(color: colors.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _IndexTile extends ConsumerWidget {
  const _IndexTile({required this.tile, required this.semanticsId});

  final HubTile tile;
  final String semanticsId;

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
    final count = _countOf(ref, tile);

    return WaxInkTappable(
      semanticsId: semanticsId,
      label: _spoken(context, tile, count),
      onPressed: () => context.go(tile.location),
      color: colors.surface1,
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
                  style: WaxType.titleItem.copyWith(color: colors.textPrimary),
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
    );
  }
}
