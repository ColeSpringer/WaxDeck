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
        SizedBox(width: 248, child: SearchField(onTap: () {})),
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
              WaxSegment(name: mode.name, label: mode.label),
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
            const PlayingIndicator(playing: true, size: 40),
            const PlayingIndicator(playing: false, size: 40),
            const PlayingIndicator(
              playing: true,
              form: PlayingIndicatorForm.bars,
              size: 16,
            ),
            const ProgressRing(progress: 0.62, size: 40),
            for (final domain in WaxDomain.values) DomainBadge(domain),
            const CodecChip('FLAC 24/96', emphasis: true),
            const CodecChip('OPUS 128'),
          ],
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
        const SizedBox(height: WaxSpace.s32),
      ],
    );
  }
}

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
