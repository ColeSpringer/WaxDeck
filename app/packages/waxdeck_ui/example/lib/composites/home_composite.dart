import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../sample_library.dart';

/// Home, as a family member sees it.
///
/// The question this screen answers in one glance is "what was I
/// listening to". Continue listening comes first and crosses domains;
/// everything under it is an invitation rather than a storefront.
class HomeComposite extends StatelessWidget {
  const HomeComposite({required this.art, this.now, super.key});

  final SampleArt art;

  /// The deck bar is the shell's, not the screen's; the composite carries
  /// one so the page can be judged with playback present, which is how it
  /// is always seen.
  final NowPlayingData? now;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final sizeClass = WaxSizeClass.of(context);

    return WaxScaffold(
      title: 'Home',
      actions: <Widget>[
        WaxIconButton(
          glyph: WaxIcons.search,
          label: 'Search',
          onPressed: () {},
        ),
        WaxIconButton(
          glyph: WaxIcons.settings,
          label: 'Settings',
          onPressed: () {},
        ),
      ],
      bottom: now == null
          ? null
          : DeckBar(
              now: now!,
              actions: DeckBarActions(
                onPlayPause: () {},
                onNext: () {},
                onPrevious: () {},
                onExpand: () {},
                onSeek: (_) {},
                onStar: (_) {},
              ),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ShelfRow(
            overline: 'Pick up where you left off',
            title: 'Continue listening',
            items: SampleLibrary.continueListening(art),
            onTapItem: (_) {},
            onPlayItem: (_) {},
          ),
          SizedBox(height: WaxLayout.of(context).sectionGap),
          ShelfRow(
            overline: 'From your subscriptions',
            title: 'New episodes',
            actionLabel: 'See all',
            onAction: () {},
            items: SampleLibrary.newEpisodes(art),
            onTapItem: (_) {},
            onPlayItem: (_) {},
          ),
          SizedBox(height: WaxLayout.of(context).sectionGap),
          ShelfRow(
            overline: 'Added this month',
            title: 'Recently added',
            actionLabel: 'See all',
            onAction: () {},
            items: SampleLibrary.recentlyAdded(art),
            onTapItem: (_) {},
            onPlayItem: (_) {},
          ),
          SizedBox(height: WaxLayout.of(context).sectionGap),
          Padding(
            padding: sizeClass.gutter,
            child: const SectionHeader(
              overline: 'Live',
              title: 'Stations you pinned',
            ),
          ),
          SizedBox(
            height: MediaCard.heightFor(context, width: 116),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: sizeClass.gutter,
              children: <Widget>[
                for (final station in SampleLibrary.stations(art))
                  Padding(
                    padding: const EdgeInsets.only(right: WaxSpace.s16),
                    child: MediaCard(
                      data: station,
                      width: 116,
                      onTap: () {},
                      onPlay: () {},
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: WaxLayout.of(context).sectionGap),
          Padding(
            padding: sizeClass.gutter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface1,
                borderRadius: WaxRadius.card,
                border: Border.all(color: colors.hairline),
              ),
              child: const Padding(
                padding: EdgeInsets.all(WaxSpace.s8),
                child: EmptyState(
                  glyph: WaxIcons.audiobooks,
                  title: 'No audiobooks yet',
                  message:
                      'Point a library at a folder of books and they show '
                      'up here, chapters and all.',
                  actionLabel: 'Add a library',
                ),
              ),
            ),
          ),
          const SizedBox(height: WaxSpace.s32),
        ],
      ),
    );
  }
}
