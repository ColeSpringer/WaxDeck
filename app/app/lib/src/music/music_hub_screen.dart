import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../home/home_shelves.dart';
import '../home/item_shelf.dart';
import '../home/mix_shelf.dart';
import '../l10n/l10n.dart';
import '../library/hub_tiles.dart';
import '../search/search_chrome.dart';
import '../shell/account_chrome.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../uploads/add_to_library.dart';
import 'music_controllers.dart';

HubTile _forDimension(AppLocalizations l10n, MusicDimension dimension) =>
    HubTile(
      name: dimension.segment,
      label: dimension.titleOf(l10n),
      glyph: dimension.glyph,
      location: WaxRoute.musicIndex(dimension),
      count: musicIndexCountProvider((
        dimension: dimension,
        domain: BrowseDomain.music,
      )),
    );

/// The ways in, in the order the hub offers them. A dimension's tile takes
/// everything from the dimension, so a renamed segment cannot leave
/// tiles pointing at locations the table no longer declares.
List<HubTile> _tiles(AppLocalizations l10n) => <HubTile>[
  for (final dimension in <MusicDimension>[
    MusicDimension.artists,
    MusicDimension.albums,
  ])
    _forDimension(l10n, dimension),
  HubTile(
    name: 'tracks',
    label: l10n.musicTracksTitle,
    glyph: WaxIcons.music,
    location: WaxRoute.musicTracks,
  ),
  for (final dimension in <MusicDimension>[
    MusicDimension.genres,
    MusicDimension.years,
  ])
    _forDimension(l10n, dimension),
  HubTile(
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
    final l10n = context.l10n;
    final tiles = _tiles(l10n);

    return WaxScaffold(
      title: l10n.musicTitle,
      actions: <Widget>[
        // The add every other hub has. It was only in the first-run
        // invitation, which disappears the moment a library has anything
        // in it - so the one section people add to most had no door
        // after the first album. Same gate as home's, same sheet, with
        // this section's type already chosen.
        if (canAddToLibrary(ref))
          WaxIconButton(
            glyph: WaxIcons.add,
            label: l10n.musicHubAddToLibrary,
            semanticsId: SemanticsIds.musicAdd,
            onPressed: () =>
                showAddToLibrarySheet(context, ref, fixed: MediaType.music),
          ),
        const SearchAction(),
        const AccountAction(),
      ],
      slivers: <Widget>[
        HubTiles(tiles: tiles, semanticsIdOf: SemanticsIds.musicTile),
        const SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s24)),
        ItemShelf(
          shelf: 'music-recent',
          title: l10n.musicShelfRecentTitle,
          provider: musicRecentlyAddedShelfProvider,
          allLocation: WaxRoute.musicTracks,
        ),
        ItemShelf(
          shelf: 'music-most-played',
          title: l10n.musicShelfMostPlayedTitle,
          provider: musicMostPlayedShelfProvider,
        ),
        ItemShelf(
          shelf: 'music-starred',
          title: l10n.musicShelfStarredTitle,
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
    final offerAdd = canAddToLibrary(ref);
    final l10n = context.l10n;
    return SliverFillRemaining(
      hasScrollBody: false,
      child: EmptyState(
        title: l10n.musicEmptyTitle,
        message: l10n.musicHubEmptyMessage,
        glyph: WaxIcons.music,
        actionLabel: offerAdd ? l10n.musicHubAddToLibrary : null,
        onAction: offerAdd
            ? () => showAddToLibrarySheet(context, ref, fixed: MediaType.music)
            : null,
      ),
    );
  }
}
