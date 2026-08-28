import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../sample_library.dart';

/// Every component, in the states that matter.
///
/// A component is not finished until it has been seen here in all three
/// themes with real strings in it: the long classical title, the empty
/// case, the offline case, the error case.
class ComponentsPage extends StatefulWidget {
  const ComponentsPage({required this.art, super.key});

  final SampleArt art;

  @override
  State<ComponentsPage> createState() => _ComponentsPageState();
}

class _ComponentsPageState extends State<ComponentsPage> {
  bool _starred = false;
  Duration _position = const Duration(minutes: 2, seconds: 41);
  String _destination = 'Home';
  bool _sidebarCollapsed = false;
  String _filter = 'all';
  String _letter = 'A';
  WaxVisualizerMode _visualizer = WaxVisualizerMode.waveform;

  /// Where the split-pane seam below sits. The component holds no width
  /// of its own, so somewhere has to; in the app that is a stored
  /// per-device preference.
  double _seam = 260;

  /// The same position the seek bars above draw, as the listenable the
  /// lyrics and the visualizer follow. They take one because a playhead
  /// moves several times a second and neither rebuilds for it; here the
  /// catalogue's own scrubbing is what moves it.
  late final ValueNotifier<Duration> _live = ValueNotifier(_position);

  @override
  void dispose() {
    _live.dispose();
    super.dispose();
  }

  void _seek(Duration to) {
    setState(() => _position = to);
    _live.value = to;
  }

  @override
  Widget build(BuildContext context) {
    final art = widget.art;
    final colors = WaxColors.of(context);

    return ListView(
      padding: const EdgeInsets.all(WaxSpace.s24),
      children: <Widget>[
        const SectionHeader(overline: 'Controls', title: 'Buttons'),
        Wrap(
          spacing: WaxSpace.s12,
          runSpacing: WaxSpace.s12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            WaxButton(label: 'Play', icon: WaxIcons.play, onPressed: () {}),
            WaxButton(
              label: 'Add to queue',
              kind: WaxButtonKind.tonal,
              icon: WaxIcons.addToQueue,
              onPressed: () {},
            ),
            WaxButton(
              label: 'See all',
              kind: WaxButtonKind.text,
              onPressed: () {},
            ),
            WaxButton(
              label: 'Show more',
              kind: WaxButtonKind.inline,
              onPressed: () {},
            ),
            WaxButton(
              label: 'Delete library',
              kind: WaxButtonKind.destructive,
              icon: WaxIcons.delete,
              onPressed: () {},
            ),
            const WaxButton(label: 'Scan running', onPressed: null),
            StarButton(
              starred: _starred,
              onChanged: (value) => setState(() => _starred = value),
            ),
            WaxIconButton(
              glyph: WaxIcons.sleepTimer,
              label: 'Sleep timer',
              badge: '12',
              active: true,
              onPressed: () {},
            ),
          ],
        ),
        const SizedBox(height: WaxSpace.s24),

        const SectionHeader(overline: 'Controls', title: 'Search and filters'),
        // The two shapes side by side: the field the search screen drives,
        // and the launcher the sidebar header holds.
        SizedBox(
          width: 360,
          child: SearchField(hint: 'Search your library', onChanged: (_) {}),
        ),
        const SizedBox(height: WaxSpace.s12),
        FilterChipRow(
          chips: const <WaxFilterChip>[
            WaxFilterChip(name: 'all', label: 'All'),
            WaxFilterChip(name: 'music', label: 'Music', glyph: WaxIcons.music),
            WaxFilterChip(
              name: 'podcasts',
              label: 'Podcasts',
              glyph: WaxIcons.podcasts,
            ),
            WaxFilterChip(
              name: 'books',
              label: 'Audiobooks',
              glyph: WaxIcons.audiobooks,
            ),
            WaxFilterChip(name: 'radio', label: 'Radio', glyph: WaxIcons.radio),
          ],
          selected: _filter,
          onSelect: (name) => setState(() => _filter = name),
        ),
        const SizedBox(height: WaxSpace.s24),

        const SectionHeader(overline: 'Content', title: 'Fast-scroll rail'),
        // Two heights: one with room to letter every slice, one short
        // enough that the rail decimates to dots. Both must still reach
        // every letter by drag.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              height: 320,
              child: FastScrollRail(
                letters: fastScrollLetters,
                selected: _letter,
                available: const <String>{'A', 'B', 'M', 'S', 'T', 'Z'},
                onLetter: (letter) => setState(() => _letter = letter),
              ),
            ),
            const SizedBox(width: WaxSpace.s32),
            SizedBox(
              height: 160,
              child: FastScrollRail(
                letters: fastScrollLetters,
                selected: _letter,
                onLetter: (letter) => setState(() => _letter = letter),
              ),
            ),
            const SizedBox(width: WaxSpace.s24),
            Text(
              'Jumped to $_letter',
              style: WaxType.body.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: WaxSpace.s24),

        const SectionHeader(overline: 'Controls', title: 'Seek bars'),
        WaxSeekBar(
          position: _position,
          duration: const Duration(minutes: 4, seconds: 5),
          buffered: const Duration(minutes: 3, seconds: 30),
          onSeek: _seek,
        ),
        const SizedBox(height: WaxSpace.s12),
        WaxSeekBar(
          position: _position,
          duration: const Duration(minutes: 4, seconds: 5),
          peaks: SampleLibrary.peaks(),
          onSeek: _seek,
        ),
        const SizedBox(height: WaxSpace.s24),

        // The three player extras, driven by the seek bars above: scrub
        // one and the sung line, the playhead, and the ring all follow.
        const SectionHeader(overline: 'Player', title: 'Lyrics'),
        SizedBox(
          height: 200,
          child: LyricsView(
            position: _live,
            lines: SampleLibrary.lyrics(),
            onSeek: _seek,
          ),
        ),
        const SizedBox(height: WaxSpace.s12),
        SizedBox(
          height: 140,
          child: LyricsView(
            position: _live,
            text: SampleLibrary.unsyncedLyrics,
          ),
        ),
        const SizedBox(height: WaxSpace.s24),

        const SectionHeader(overline: 'Player', title: 'Visualizer'),
        WaxSegmented(
          label: 'Visualizer mode',
          selected: _visualizer.name,
          segments: <WaxSegment>[
            for (final mode in WaxVisualizerMode.values)
              WaxSegment(name: mode.name, label: mode.label(context.waxL10n)),
          ],
          onSelect: (name) => setState(
            () => _visualizer = WaxVisualizerMode.values.byName(name),
          ),
        ),
        const SizedBox(height: WaxSpace.s12),
        SizedBox(
          height: 260,
          child: VisualizerStage(
            position: _live,
            duration: const Duration(minutes: 4, seconds: 5),
            peaks: SampleLibrary.peaks(),
            mode: _visualizer,
            playing: true,
            artwork: art.of('Salt Harbour'),
            monogram: 'Salt Harbour',
            onSeek: _seek,
          ),
        ),
        const SizedBox(height: WaxSpace.s24),

        const SectionHeader(overline: 'Player', title: 'Car mode'),
        // Boxed rather than full-screen: it imposes the OLED theme on
        // whatever it is drawn inside, and the point of showing it here
        // is that it looks the same in all three.
        SizedBox(
          height: 420,
          child: CarModeScaffold(
            now: NowPlayingData(
              title: 'Salt Harbour',
              subtitle: 'Nightjar',
              artwork: art.of('Salt Harbour'),
              position: _position,
              duration: const Duration(minutes: 4, seconds: 5),
              playing: true,
            ),
            onPlayPause: () {},
            onNext: () {},
            onPrevious: () {},
            onExit: () {},
          ),
        ),
        const SizedBox(height: WaxSpace.s24),

        const SectionHeader(overline: 'Content', title: 'Cards'),
        Wrap(
          spacing: WaxSpace.s16,
          runSpacing: WaxSpace.s16,
          children: <Widget>[
            for (final item in <MediaTileData>[
              ...SampleLibrary.continueListening(art).take(3),
              SampleLibrary.stations(art).first,
              MediaTileData(
                title: SampleLibrary.longClassicalTitle,
                subtitle: 'Wiener Philharmoniker, Karl Boehm',
                artwork: art.of('Winterreise'),
              ),
              const MediaTileData(
                title: 'No artwork yet',
                subtitle: 'Unknown artist',
              ),
            ])
              MediaCard(data: item, onTap: () {}, onPlay: () {}, onMore: () {}),
          ],
        ),
        const SizedBox(height: WaxSpace.s24),

        const SectionHeader(
          overline: 'Content',
          title: 'Cards with captions on hover',
        ),
        Text(
          'The same cards in the other caption mode. Hover one: the lines '
          'fade in without the cell changing size, which is what lets a '
          'shelf commit to a height before it lays them out.',
          style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: WaxSpace.s12),
        Wrap(
          spacing: WaxSpace.s16,
          runSpacing: WaxSpace.s16,
          children: <Widget>[
            for (final item in SampleLibrary.continueListening(art).take(3))
              MediaCard(
                data: item,
                captions: WaxCaptionMode.onHover,
                onTap: () {},
                onPlay: () {},
              ),
          ],
        ),
        const SizedBox(height: WaxSpace.s24),

        const SectionHeader(overline: 'Content', title: 'Rows'),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface1,
            borderRadius: WaxRadius.card,
          ),
          child: Column(
            children: <Widget>[
              MediaListRow(
                data: SampleLibrary.albumTracks()[1],
                leadingIndex: 2,
                playing: true,
                onTap: () {},
                onMore: () {},
              ),
              MediaListRow(
                data: MediaTileData(
                  title: 'The Quiet Part',
                  subtitle: 'Field Recordings',
                  artwork: art.of('The Quiet Part'),
                  domain: WaxDomain.podcasts,
                  trailingText: '41:12',
                ),
                onTap: () {},
                onMore: () {},
              ),
              MediaListRow(
                data: MediaTileData(
                  title: 'A History of Tides',
                  subtitle: 'Mirren Vaux',
                  artwork: art.of('A History of Tides'),
                  domain: WaxDomain.audiobooks,
                  shape: ArtworkShape.portrait,
                  trailingText: '14:02:31',
                  starred: true,
                ),
                onTap: () {},
              ),
              const MediaListRow(
                data: MediaTileData(
                  title: 'Signal to Noise',
                  subtitle: 'Not downloaded',
                  domain: WaxDomain.podcasts,
                  unavailableOffline: true,
                  trailingText: '32:00',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: WaxSpace.s24),

        const SectionHeader(overline: 'Content', title: 'Indicators and chips'),
        Wrap(
          spacing: WaxSpace.s16,
          runSpacing: WaxSpace.s16,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            // Both states, at the one size a list row draws it: moving
            // while it plays, and holding a static profile otherwise,
            // which is also what reduced motion gets.
            const PlayingIndicator(playing: true, size: 16),
            const PlayingIndicator(playing: false, size: 16),
            const ProgressRing(progress: 0.62, size: 40),
            for (final domain in WaxDomain.values) DomainBadge(domain),
            const CodecChip('FLAC 24/96', emphasis: true),
            const CodecChip('OPUS 128'),
          ],
        ),
        const SizedBox(height: WaxSpace.s24),

        const SectionHeader(
          overline: 'Content',
          title: 'How listening divides',
        ),
        // All four domains at once, and one share small enough to fall
        // to the painter's floor: a sliver thinner than the bar's own
        // rounded ends would draw as a smudge rather than as a share.
        const SizedBox(
          width: 320,
          child: MediaSplitBar(
            summary:
                'Listening by media type: music 6h 40m, podcasts 3h 20m, '
                'audiobooks 1h 40m, radio 8m.',
            segments: <MediaSplitSegment>[
              MediaSplitSegment(
                label: 'Music',
                value: 24000000,
                valueLabel: '6h 40m',
                domain: WaxDomain.music,
              ),
              MediaSplitSegment(
                label: 'Podcasts',
                value: 12000000,
                valueLabel: '3h 20m',
                domain: WaxDomain.podcasts,
              ),
              MediaSplitSegment(
                label: 'Audiobooks',
                value: 6000000,
                valueLabel: '1h 40m',
                domain: WaxDomain.audiobooks,
              ),
              MediaSplitSegment(
                label: 'Radio',
                value: 480000,
                valueLabel: '8m',
                domain: WaxDomain.radio,
              ),
            ],
          ),
        ),
        const SizedBox(height: WaxSpace.s24),

        const SectionHeader(overline: 'Content', title: 'Scrolling titles'),
        // Both cases side by side in the same slot, because the whole
        // design is that they are the same widget: the long one travels
        // and pauses at each end, the short one is a plain line with no
        // ticker behind it. Under reduced motion both draw as the short
        // one does.
        SizedBox(
          width: 220,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              WaxMarqueeText(
                'Concerto for Two Violins in D minor, BWV 1043: II. Largo',
                style: WaxType.titleItem.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: WaxSpace.s8),
              WaxMarqueeText(
                'Salt Harbour',
                style: WaxType.titleItem.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        ),
        const SizedBox(height: WaxSpace.s24),

        const SectionHeader(overline: 'Content', title: 'Artwork shapes'),
        Row(
          children: <Widget>[
            ArtworkImage(size: 96, artwork: art.of('Salt Harbour')),
            const SizedBox(width: WaxSpace.s16),
            ArtworkImage(
              size: 96,
              artwork: art.of('A History of Tides'),
              shape: ArtworkShape.portrait,
              domain: WaxDomain.audiobooks,
            ),
            const SizedBox(width: WaxSpace.s16),
            ArtworkImage(
              size: 96,
              artwork: art.of('Coastal FM'),
              shape: ArtworkShape.circle,
              domain: WaxDomain.radio,
            ),
            const SizedBox(width: WaxSpace.s16),
            const ArtworkImage(
              size: 96,
              monogram: 'Nightjar Ensemble',
              domain: WaxDomain.podcasts,
            ),
            const SizedBox(width: WaxSpace.s16),
            ArtworkImage(
              size: 96,
              artwork: art.of('Marginalia'),
              progress: 0.44,
            ),
          ],
        ),
        const SizedBox(height: WaxSpace.s24),

        const SectionHeader(overline: 'Content', title: 'Artwork captions'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // What is in the slot, which is a fact about the picture
            // that is there - one step up the ramp from the rest.
            SizedBox(
              width: 120,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ArtworkImage(size: 120, artwork: art.of('Salt Harbour')),
                  const SizedBox(height: WaxSpace.s8),
                  const ArtworkCaption('jpeg, 1400 x 1400', emphasis: true),
                  const ArtworkCaption('From the Cover Art Archive'),
                ],
              ),
            ),
            const SizedBox(width: WaxSpace.s16),
            // The two-line case a header takes, where a long provider
            // name wraps under the picture instead of widening it.
            SizedBox(
              width: 120,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const ArtworkImage(size: 120, monogram: 'Nightjar Ensemble'),
                  const SizedBox(height: WaxSpace.s8),
                  const ArtworkCaption(
                    'From the Cover Art Archive, borrowed from a track',
                    align: TextAlign.center,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: WaxSpace.s24),

        const SectionHeader(overline: 'States', title: 'Empty, error, loading'),
        SizedBox(
          height: 220,
          child: Row(
            children: <Widget>[
              Expanded(
                child: EmptyState(
                  glyph: WaxIcons.podcasts,
                  title: 'No podcasts yet',
                  message: 'Follow a show to see new episodes here.',
                  actionLabel: 'Find podcasts',
                  onAction: () {},
                ),
              ),
              Expanded(
                child: ErrorState(
                  message:
                      "Can't reach the server. Check the address and try "
                      'again.',
                  detail: 'ERR_CONNECTION_REFUSED · 10.0.0.4:4420',
                  onRetry: () {},
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: WaxSpace.s12),
        const SkeletonShapes(shape: SkeletonShape.shelf, count: 4),
        const SizedBox(height: WaxSpace.s12),
        const SkeletonShapes(shape: SkeletonShape.list, count: 3),
        const SizedBox(height: WaxSpace.s24),

        const SectionHeader(overline: 'Shell', title: 'Navigation chrome'),
        // One piece of chrome per size class, all four side by side: the
        // point of the frame is that a narrow desktop window behaves like
        // a phone, and that is only judgeable next to the others.
        SizedBox(
          height: 380,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final sizeClass in WaxSizeClass.values) ...<Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        sizeClass.name,
                        style: WaxType.overline.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                      const SizedBox(height: WaxSpace.s8),
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: WaxRadius.card,
                            border: Border.all(color: colors.hairline),
                          ),
                          child: ClipRRect(
                            borderRadius: WaxRadius.card,
                            child: WaxShellFrame(
                              sizeClass: sizeClass,
                              destinations: _catalogDestinations,
                              secondary: _catalogSecondary,
                              selected: _destination,
                              collapsed: _sidebarCollapsed,
                              onToggleCollapsed: () => setState(
                                () => _sidebarCollapsed = !_sidebarCollapsed,
                              ),
                              onSelect: (name) =>
                                  setState(() => _destination = name),
                              account: _catalogAccount,
                              // An action is not a destination, so it
                              // does not move the highlight; the app
                              // signs out here.
                              onAccountAction: (_) {},
                              sidebarHeader: const WaxWordmark(size: 18),
                              content: Center(
                                child: Text(
                                  _destination,
                                  style: WaxType.body.copyWith(
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (sizeClass != WaxSizeClass.values.last)
                  const SizedBox(width: WaxSpace.s16),
              ],
            ],
          ),
        ),
        const SizedBox(height: WaxSpace.s24),

        const SectionHeader(overline: 'Shell', title: 'Split panes'),
        // Live, because a seam is nothing but its behaviour: drag it,
        // tab to it and press an arrow, double-click it to hand the
        // width back. What it looks like standing still is one hairline.
        SizedBox(
          height: 160,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: WaxRadius.card,
              border: Border.all(color: colors.hairline),
            ),
            child: ClipRRect(
              borderRadius: WaxRadius.card,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const listMin = 180.0;
                  // Floored at the minimum, which the app's own caller
                  // does for the same reason: narrow the window enough
                  // and the detail pane's share exceeds the width, so an
                  // unguarded `clamp(180, 168)` throws and takes the
                  // whole catalogue page with it.
                  final listMax =
                      (constraints.maxWidth - WaxSplitter.hitWidth - 220).clamp(
                        listMin,
                        double.infinity,
                      );
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SizedBox(
                        width: _seam.clamp(listMin, listMax),
                        child: ColoredBox(
                          color: colors.surface2,
                          child: Center(
                            child: Text(
                              'List',
                              style: WaxType.label.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      WaxSplitter(
                        position: _seam.clamp(listMin, listMax),
                        min: listMin,
                        max: listMax,
                        onChanged: (width) => setState(() => _seam = width),
                        onReset: () => setState(() => _seam = 260),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            'Detail',
                            style: WaxType.label.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: WaxSpace.s24),

        const SectionHeader(overline: 'Shell', title: 'Command palette'),
        // Drawn in place rather than over the page: the catalogue is for
        // judging the surface, and a palette that had to be summoned with
        // a chord would be a component nobody here could see in three
        // themes at once. The app opens it in a dialog.
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: WaxCommandPalette(
            groups: _catalogPalette,
            maxHeight: 320,
            onQueryChanged: (_) {},
            onRun: (_) {},
            onClose: () {},
          ),
        ),
        const SizedBox(height: WaxSpace.s16),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: WaxShortcutSheet(
            groups: _catalogShortcuts,
            maxHeight: 300,
            onClose: () {},
          ),
        ),
        const SizedBox(height: WaxSpace.s32),
      ],
    );
  }
}

/// A palette mid-query: an action with its key, a place, and a library
/// hit, which is the mixture the app's own groups produce.
const _catalogPalette = <WaxPaletteGroup>[
  WaxPaletteGroup(
    title: 'Actions',
    entries: <WaxPaletteEntry>[
      WaxPaletteEntry(
        id: 'shuffle',
        label: 'Shuffle the queue',
        detail: 'Playback',
        glyph: WaxIcons.shuffle,
      ),
      WaxPaletteEntry(
        id: 'queue',
        label: 'Show the queue',
        detail: 'Views',
        glyph: WaxIcons.queue,
        shortcut: 'Q',
      ),
    ],
  ),
  WaxPaletteGroup(
    title: 'Go to',
    entries: <WaxPaletteEntry>[
      WaxPaletteEntry(
        id: 'go-radio',
        label: 'Radio',
        detail: 'Go to',
        glyph: WaxIcons.radio,
      ),
      WaxPaletteEntry(
        id: 'hit-1',
        label: 'Sonata for Cello and Piano in D Minor',
        detail: 'Nightjar Quartet',
        glyph: WaxIcons.albums,
      ),
    ],
  ),
];

const _catalogShortcuts = <WaxShortcutGroup>[
  WaxShortcutGroup(
    title: 'Playback',
    rows: <WaxShortcutRow>[
      WaxShortcutRow(label: 'Play or pause', keys: 'Space'),
      WaxShortcutRow(label: 'Next track', keys: 'Ctrl →'),
      WaxShortcutRow(label: 'Skip ahead 10 seconds', keys: 'Shift →'),
    ],
  ),
  WaxShortcutGroup(
    title: 'Everywhere',
    rows: <WaxShortcutRow>[
      WaxShortcutRow(label: 'Open the command palette', keys: 'Ctrl K'),
      WaxShortcutRow(label: 'Keyboard shortcuts', keys: 'Shift ?'),
    ],
  ),
];

const _catalogDestinations = <WaxDestination>[
  WaxDestination(name: 'Home', label: 'Home', glyph: WaxIcons.home),
  WaxDestination(name: 'Music', label: 'Music', glyph: WaxIcons.music),
  WaxDestination(name: 'Podcasts', label: 'Podcasts', glyph: WaxIcons.podcasts),
  WaxDestination(name: 'Radio', label: 'Radio', glyph: WaxIcons.radio),
];

// `name` is identity and `label` is what is drawn. The app mints the
// identity from an enum; modelling it as the label here would teach the
// opposite to whoever reads this as the usage example.
const _catalogAccount = WaxAccount(
  name: 'sam',
  actions: <WaxAccountAction>[
    WaxAccountAction(name: 'signOut', label: 'Sign out', glyph: WaxIcons.close),
  ],
);

const _catalogSecondary = <WaxNavEntry>[
  WaxNavLink(
    WaxDestination(
      name: 'Settings',
      label: 'Settings',
      glyph: WaxIcons.settings,
    ),
  ),
  WaxNavGroup(
    name: 'curation',
    label: 'Curation',
    glyph: WaxIcons.admin,
    children: <WaxDestination>[
      WaxDestination(
        name: 'Review queue',
        label: 'Review queue',
        glyph: WaxIcons.admin,
      ),
      WaxDestination(name: 'Users', label: 'Users', glyph: WaxIcons.admin),
    ],
  ),
];
