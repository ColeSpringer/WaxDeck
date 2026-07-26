import 'package:alchemist/alchemist.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// Renders one scenario under a theme variant, which is what makes a
/// golden a statement about the design system rather than about Material.
Widget _themed(WaxThemeVariant variant, Widget child, {WaxDensity? density}) {
  final theme = buildWaxTheme(
    variant: variant,
    density: density ?? WaxDensity.comfortable,
  );
  return Theme(
    data: theme,
    child: ColoredBox(
      color: variant.colors.canvas,
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    ),
  );
}

/// Animated components (the VU needle, the row bars, the skeletons) never
/// settle by design, so goldens pump a fixed number of frames instead of
/// waiting for stillness that will not come. The frame count is what
/// makes the captured phase deterministic.
final PumpAction _pumpAnimated = pumpNTimes(
  3,
  const Duration(milliseconds: 120),
);

const _tile = MediaTileData(
  title: 'Salt Harbour',
  subtitle: 'Nightjar',
  trailingText: '4:05',
);

const _destinations = <WaxDestination>[
  WaxDestination(name: 'home', label: 'Home', glyph: WaxIcons.home),
  WaxDestination(name: 'music', label: 'Music', glyph: WaxIcons.music),
  WaxDestination(name: 'podcasts', label: 'Podcasts', glyph: WaxIcons.podcasts),
  WaxDestination(name: 'radio', label: 'Radio', glyph: WaxIcons.radio),
];

const _secondaryEntries = <WaxNavEntry>[
  WaxNavLink(
    WaxDestination(
      name: 'settings',
      label: 'Settings',
      glyph: WaxIcons.settings,
    ),
  ),
  WaxNavGroup(
    label: 'Curation',
    glyph: WaxIcons.admin,
    children: <WaxDestination>[
      WaxDestination(
        name: 'review',
        label: 'Review queue',
        glyph: WaxIcons.admin,
      ),
    ],
  ),
];

void main() {
  group('components', () {
    goldenTest(
      'buttons render in every theme',
      fileName: 'buttons',
      builder: () => GoldenTestGroup(
        columns: 3,
        children: <Widget>[
          for (final variant in WaxThemeVariant.values)
            GoldenTestScenario(
              name: variant.name,
              child: _themed(
                variant,
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    WaxButton(
                      label: 'Play',
                      icon: WaxIcons.play,
                      onPressed: () {},
                    ),
                    const SizedBox(height: 8),
                    WaxButton(
                      label: 'Add to queue',
                      kind: WaxButtonKind.tonal,
                      onPressed: () {},
                    ),
                    const SizedBox(height: 8),
                    WaxButton(
                      label: 'Delete',
                      kind: WaxButtonKind.destructive,
                      onPressed: () {},
                    ),
                    const SizedBox(height: 8),
                    const WaxButton(label: 'Disabled', onPressed: null),
                  ],
                ),
              ),
            ),
        ],
      ),
    );

    goldenTest(
      'list rows carry state without relying on colour',
      fileName: 'list_rows',
      pumpBeforeTest: _pumpAnimated,
      builder: () => GoldenTestGroup(
        columns: 2,
        children: <Widget>[
          for (final variant in <WaxThemeVariant>[
            WaxThemeVariant.dark,
            WaxThemeVariant.light,
          ])
            for (final density in WaxDensity.values)
              GoldenTestScenario(
                name: '${variant.name} ${density.name}',
                child: _themed(
                  variant,
                  density: density,
                  SizedBox(
                    width: 420,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        MediaListRow(
                          data: _tile,
                          leadingIndex: 2,
                          playing: true,
                          onTap: () {},
                        ),
                        MediaListRow(
                          data: const MediaTileData(
                            title: 'Gullwing',
                            subtitle: 'Nightjar',
                            trailingText: '5:41',
                            starred: true,
                          ),
                          leadingIndex: 3,
                          onTap: () {},
                          onMore: () {},
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
                ),
              ),
        ],
      ),
    );

    goldenTest(
      'cards keep long titles and mixed shapes on one baseline',
      fileName: 'cards',
      builder: () => GoldenTestGroup(
        columns: 2,
        children: <Widget>[
          for (final variant in <WaxThemeVariant>[
            WaxThemeVariant.dark,
            WaxThemeVariant.light,
          ])
            GoldenTestScenario(
              name: variant.name,
              child: _themed(
                variant,
                SizedBox(
                  width: 420,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const MediaCard(
                        data: MediaTileData(
                          title: 'Salt Harbour',
                          subtitle: 'Nightjar',
                          progress: 0.62,
                          trailingText: '14 min left',
                        ),
                        width: 120,
                      ),
                      const SizedBox(width: 12),
                      const MediaCard(
                        data: MediaTileData(
                          title:
                              'Symphony No. 9 in D minor, Op. 125 "Choral": '
                              'IV. Presto',
                          subtitle: 'Wiener Philharmoniker',
                          domain: WaxDomain.audiobooks,
                          shape: ArtworkShape.portrait,
                        ),
                        width: 120,
                      ),
                      const SizedBox(width: 12),
                      const MediaCard(
                        data: MediaTileData(
                          title: 'Coastal FM',
                          subtitle: 'Ambient',
                          domain: WaxDomain.radio,
                          shape: ArtworkShape.circle,
                        ),
                        width: 120,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    goldenTest(
      'states say what happened and what to do next',
      fileName: 'states',
      builder: () => GoldenTestGroup(
        columns: 2,
        children: <Widget>[
          for (final variant in <WaxThemeVariant>[
            WaxThemeVariant.dark,
            WaxThemeVariant.light,
          ]) ...<Widget>[
            GoldenTestScenario(
              name: 'empty ${variant.name}',
              child: _themed(
                variant,
                SizedBox(
                  width: 380,
                  child: EmptyState(
                    glyph: WaxIcons.podcasts,
                    title: 'No podcasts yet',
                    message: 'Follow a show to see new episodes here.',
                    actionLabel: 'Find podcasts',
                    onAction: () {},
                  ),
                ),
              ),
            ),
            GoldenTestScenario(
              name: 'error ${variant.name}',
              child: _themed(
                variant,
                SizedBox(
                  width: 380,
                  child: ErrorState(
                    message:
                        "Can't reach the server. Check the address and try "
                        'again.',
                    detail: 'ERR_CONNECTION_REFUSED · 10.0.0.4:4420',
                    onRetry: () {},
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    goldenTest(
      'the deck bar holds every medium at two text scales',
      fileName: 'deck_bar',
      builder: () => GoldenTestGroup(
        columns: 1,
        children: <Widget>[
          for (final scale in <double>[1.0, 1.5])
            for (final now in <NowPlayingData>[
              const NowPlayingData(
                title: 'Salt Harbour',
                subtitle: 'Nightjar',
                position: Duration(minutes: 2, seconds: 41),
                duration: Duration(minutes: 4, seconds: 5),
                playing: true,
                starred: true,
              ),
              const NowPlayingData(
                title: 'What the harbour remembers',
                subtitle: 'Field Recordings',
                domain: WaxDomain.podcasts,
                position: Duration(minutes: 18, seconds: 6),
                duration: Duration(minutes: 58, seconds: 12),
                playing: true,
                speed: 1.2,
              ),
              const NowPlayingData(
                title: 'Coastal FM',
                subtitle: 'Ora Lune - Bell Tower',
                domain: WaxDomain.radio,
                shape: ArtworkShape.circle,
                position: Duration.zero,
                duration: Duration.zero,
                playing: true,
                live: true,
              ),
            ])
              GoldenTestScenario.withTextScaleFactor(
                name: '${now.domain.name} at $scale',
                textScaler: TextScaler.linear(scale),
                child: _themed(
                  WaxThemeVariant.dark,
                  SizedBox(
                    width: 420,
                    child: DeckBar(
                      now: now,
                      sizeClass: WaxSizeClass.compact,
                      actions: DeckBarActions(
                        onPlayPause: () {},
                        onNext: () {},
                        onExpand: () {},
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );

    goldenTest(
      'indicators hold a static pose when nothing is playing',
      fileName: 'indicators',
      pumpBeforeTest: _pumpAnimated,
      builder: () => GoldenTestGroup(
        columns: 3,
        children: <Widget>[
          for (final variant in WaxThemeVariant.values)
            GoldenTestScenario(
              name: variant.name,
              child: _themed(
                variant,
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const PlayingIndicator(playing: false, size: 40),
                    const SizedBox(width: 12),
                    const PlayingIndicator(
                      playing: false,
                      form: PlayingIndicatorForm.bars,
                      size: 16,
                    ),
                    const SizedBox(width: 12),
                    const ProgressRing(progress: 0.62, size: 40),
                    const SizedBox(width: 12),
                    const CodecChip('FLAC 24/96', emphasis: true),
                    const SizedBox(width: 8),
                    const DomainBadge(WaxDomain.podcasts),
                  ],
                ),
              ),
            ),
        ],
      ),
    );

    goldenTest(
      'the shell wears one piece of chrome per size class',
      fileName: 'shell_chrome',
      builder: () => GoldenTestGroup(
        columns: 2,
        children: <Widget>[
          for (final sizeClass in WaxSizeClass.values)
            GoldenTestScenario(
              name: sizeClass.name,
              child: _themed(
                WaxThemeVariant.dark,
                SizedBox(
                  width: switch (sizeClass) {
                    WaxSizeClass.compact => 400,
                    WaxSizeClass.medium => 640,
                    WaxSizeClass.expanded => 760,
                    WaxSizeClass.wide => 900,
                  },
                  height: 420,
                  child: WaxShellFrame(
                    sizeClass: sizeClass,
                    destinations: _destinations,
                    secondary: _secondaryEntries,
                    selected: 'podcasts',
                    onSelect: (_) {},
                    sidebarHeader: const WaxWordmark(size: 20),
                    onToggleCollapsed: () {},
                    content: const Center(child: Text('content pane')),
                  ),
                ),
              ),
            ),
          // Tabs at the scale where their labels give way to the glyphs
          // alone, which is reflow rather than truncation.
          for (final scale in <double>[1.0, 1.5, 2.0])
            GoldenTestScenario.withTextScaleFactor(
              name: 'tabs at $scale',
              textScaler: TextScaler.linear(scale),
              child: _themed(
                WaxThemeVariant.dark,
                SizedBox(
                  width: 400,
                  child: WaxNavBar(
                    destinations: _destinations,
                    selected: 'music',
                    onSelect: (_) {},
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    goldenTest(
      'the wordmark is drawn, not shipped as a picture',
      fileName: 'wordmark',
      builder: () => GoldenTestGroup(
        columns: 3,
        children: <Widget>[
          for (final variant in WaxThemeVariant.values)
            GoldenTestScenario(
              name: variant.name,
              child: _themed(
                variant,
                const WaxBrandBlock(
                  tagline: 'Your collection, not a storefront.',
                ),
              ),
            ),
        ],
      ),
    );
  });
}
