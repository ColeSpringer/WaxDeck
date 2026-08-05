/// Goldens for the components that landed after the design system's own
/// phase: the player's transport and seek clusters, settings rows, the
/// console table, the entity header, the palette and its shortcut sheet,
/// the station dial, the mini player, and the controls the later phases
/// added (the volume slider, segmented, pills).
///
/// **CI goldens only, deliberately.** The readable platform goldens are
/// baselined on Linux and skipped elsewhere, so a run on any other host
/// cannot produce one - and the readable pass exists to catch a wrong
/// font weight or a lost variable axis, which is a statement about
/// `WaxType` rather than about any one component. That statement is
/// already locked by `components_golden_test.dart` and the composites,
/// which render the whole type ramp; every component here draws from the
/// same styles. What is left to catch is layout, spacing, and colour,
/// which is exactly what the tolerant CI comparison gates, on every
/// host. `docs/deferred-work.md` carries the readable half.
library;

import 'package:alchemist/alchemist.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

Widget _themed(WaxThemeVariant variant, Widget child) {
  final theme = buildWaxTheme(variant: variant);
  return Theme(
    data: theme,
    child: ColoredBox(
      color: variant.colors.canvas,
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    ),
  );
}

/// The needle, the bars, and the dial's settle never come to rest, so
/// goldens pump a fixed number of frames instead of waiting for a
/// stillness that will not come.
final PumpAction _pumpAnimated = pumpNTimes(
  3,
  const Duration(milliseconds: 120),
);

const _lightAndDark = <WaxThemeVariant>[
  WaxThemeVariant.dark,
  WaxThemeVariant.light,
];

const _music = NowPlayingData(
  title: 'Salt Harbour',
  subtitle: 'Nightjar',
  position: Duration(minutes: 2, seconds: 41),
  duration: Duration(minutes: 4, seconds: 5),
  playing: true,
);

const _book = NowPlayingData(
  title: 'Chapter 9: The long way round',
  subtitle: 'A Bright Shore',
  domain: WaxDomain.audiobooks,
  shape: ArtworkShape.portrait,
  position: Duration(hours: 4, minutes: 12),
  duration: Duration(hours: 11, minutes: 3),
  playing: false,
  speed: 1.4,
);

class _Job {
  const _Job(this.name, this.state, this.items);

  final String name;
  final String state;
  final int items;
}

const _jobs = <_Job>[
  _Job('Scan library', 'running', 12480),
  _Job('Analyze audio', 'queued', 312),
  _Job('Rebuild covers', 'failed', 4),
];

void main() {
  // The whole file is CI-only; see the library comment for why.
  final ciOnly = AlchemistConfig.current().copyWith(
    platformGoldensConfig: const PlatformGoldensConfig(
      platforms: <HostPlatform>{},
    ),
  );

  AlchemistConfig.runWithConfig(
    config: ciOnly,
    run: () {
      group('later components', () {
        goldenTest(
          'the transport holds every medium it drives',
          fileName: 'player_transport',
          pumpBeforeTest: _pumpAnimated,
          builder: () => GoldenTestGroup(
            columns: 1,
            children: <Widget>[
              for (final scale in <double>[1.0, 1.5])
                GoldenTestScenario.withTextScaleFactor(
                  name: 'music at $scale',
                  textScaler: TextScaler.linear(scale),
                  child: _themed(
                    WaxThemeVariant.dark,
                    SizedBox(
                      width: 460,
                      height: scale > 1 ? 200 : 170,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          SeekCluster(now: _music, onSeek: (_) {}),
                          const SizedBox(height: WaxSpace.s16),
                          TransportCluster(
                            playing: true,
                            onPlayPause: () {},
                            onPrevious: () {},
                            onNext: () {},
                            onShuffle: () {},
                            onRepeat: () {},
                            shuffled: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Spoken word: skip arrows in place of track steps, the
              // remaining-time line under the bar, and a paused face.
              GoldenTestScenario(
                name: 'spoken word',
                child: _themed(
                  WaxThemeVariant.dark,
                  SizedBox(
                    width: 460,
                    height: 190,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        SeekCluster(
                          now: _book,
                          onSeek: (_) {},
                          remainingLabel: '38 percent, 6 hr 51 min left',
                        ),
                        const SizedBox(height: WaxSpace.s16),
                        TransportCluster(
                          playing: false,
                          onPlayPause: () {},
                          onSkipBack: () {},
                          onSkipForward: () {},
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Live: no scrubbing, no steps, and the transport says so
              // by drawing neither.
              GoldenTestScenario(
                name: 'live',
                child: _themed(
                  WaxThemeVariant.dark,
                  SizedBox(
                    width: 460,
                    height: 96,
                    child: TransportCluster(
                      playing: true,
                      live: true,
                      onPlayPause: () {},
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

        goldenTest(
          'a settings section reads as rows of one decision each',
          fileName: 'settings_rows',
          builder: () => GoldenTestGroup(
            columns: 2,
            children: <Widget>[
              for (final variant in _lightAndDark)
                for (final scale in <double>[1, 1.5])
                  GoldenTestScenario(
                    name: '${variant.name} ${scale}x',
                    child: MediaQuery(
                      data: MediaQueryData(
                        textScaler: TextScaler.linear(scale),
                      ),
                      child: _themed(
                        variant,
                        SizedBox(
                          width: 520,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              WaxSettingRow(
                                title: 'Prepare the next track',
                                help:
                                    'Only on wifi, so mobile data is '
                                    'spent on what you asked for',
                                glyph: WaxIcons.downloads,
                                control: WaxSwitch(
                                  value: true,
                                  label: 'Prepare the next track on wifi only',
                                  onChanged: (_) {},
                                ),
                              ),
                              WaxSettingRow(
                                title: 'Skip back by',
                                help:
                                    'How far the back arrow moves in '
                                    'podcasts and audiobooks',
                                control: WaxChoice<int>(
                                  value: 15,
                                  options: const <int>[10, 15, 30],
                                  labelFor: (value) => '$value seconds',
                                  label: 'Skip back by',
                                  onChanged: (_) {},
                                ),
                              ),
                              // A control with nothing loaded behind it
                              // yet: disabled, and reported as such.
                              const WaxSettingRow(
                                title: 'Crossfade',
                                help:
                                    'Overlap the end of one track with '
                                    'the start of the next',
                                control: WaxSwitch(
                                  value: false,
                                  label: 'Crossfade',
                                  onChanged: null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        );

        goldenTest(
          'the console table keeps its columns and its row controls',
          fileName: 'console_table',
          builder: () => GoldenTestGroup(
            columns: 1,
            children: <Widget>[
              // A table is columns on a desktop and a card per row below
              // sidebar width, and it reads the window rather than its own
              // box to decide - so the size class is declared here, and
              // both shapes are locked.
              for (final (name, width) in const <(String, double)>[
                ('tabular', 1000),
                ('cards', 560),
              ])
                for (final variant in _lightAndDark)
                  GoldenTestScenario(
                    name: '$name ${variant.name}',
                    child: MediaQuery(
                      data: MediaQueryData(size: Size(width, 900)),
                      child: _themed(
                        variant,
                        SizedBox(
                          width: width,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  const Expanded(
                                    child: StatTile(
                                      label: 'Items',
                                      value: '104,812',
                                      glyph: WaxIcons.albums,
                                    ),
                                  ),
                                  const SizedBox(width: WaxSpace.s12),
                                  Expanded(
                                    child: StatTile(
                                      label: 'Health',
                                      value: '82',
                                      caption: '311 items want attention',
                                      tone: variant.colors.error,
                                      onTap: () {},
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: WaxSpace.s16),
                              WaxTable<_Job>(
                                rows: _jobs,
                                rowId: (job) => job.name,
                                onRowTap: (_) {},
                                caption: 'Background work on this server',
                                columns: <WaxColumn<_Job>>[
                                  WaxColumn<_Job>(
                                    label: 'Job',
                                    text: (job) => job.name,
                                    cell: (context, job) => Text(job.name),
                                    priority: WaxColumnPriority.primary,
                                  ),
                                  WaxColumn<_Job>(
                                    label: 'State',
                                    text: (job) => job.state,
                                    cell: (context, job) =>
                                        CodecChip(job.state),
                                  ),
                                  WaxColumn<_Job>(
                                    label: 'Items',
                                    numeric: true,
                                    text: (job) => '${job.items}',
                                    cell: (context, job) =>
                                        Text('${job.items}'),
                                  ),
                                  // A control in the row: the one shape
                                  // an over-eager row semantics wrapper
                                  // eats.
                                  WaxColumn<_Job>(
                                    label: '',
                                    cell: (context, job) => WaxIconButton(
                                      glyph: WaxIcons.close,
                                      label: 'Cancel ${job.name}',
                                      size: 18,
                                      onPressed: () {},
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        );

        goldenTest(
          'an entity wears its own header',
          fileName: 'entity_header',
          builder: () => GoldenTestGroup(
            columns: 1,
            children: <Widget>[
              for (final variant in _lightAndDark)
                GoldenTestScenario(
                  name: variant.name,
                  child: _themed(
                    variant,
                    SizedBox(
                      width: 640,
                      child: EntityHeader(
                        title: 'The Harbour Tapes',
                        subtitle: 'Nightjar',
                        metadata: '1975 · 9 tracks · 41 min',
                        description:
                            'Recorded over four winter nights in a '
                            'converted boathouse, and mixed the following '
                            'spring.',
                        actions: <Widget>[
                          WaxButton(
                            label: 'Play',
                            icon: WaxIcons.play,
                            onPressed: () {},
                          ),
                          WaxButton(
                            label: 'Shuffle',
                            kind: WaxButtonKind.tonal,
                            icon: WaxIcons.shuffle,
                            onPressed: () {},
                          ),
                          StarButton(starred: true, onChanged: (_) {}),
                        ],
                      ),
                    ),
                  ),
                ),
              // A book: portrait art on a matte, which is the shape rule
              // the header has to honour rather than crop.
              GoldenTestScenario(
                name: 'portrait',
                child: _themed(
                  WaxThemeVariant.dark,
                  SizedBox(
                    width: 640,
                    child: EntityHeader(
                      title: 'A Bright Shore',
                      subtitle: 'Read by Ines Marchetti',
                      metadata: '11 hr 3 min · 24 chapters',
                      shape: ArtworkShape.portrait,
                      domain: WaxDomain.audiobooks,
                      actions: <Widget>[
                        WaxButton(
                          label: 'Resume',
                          icon: WaxIcons.play,
                          onPressed: () {},
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
          'the palette and the reference sheet share one voice',
          fileName: 'palette_and_shortcuts',
          builder: () => GoldenTestGroup(
            columns: 1,
            children: <Widget>[
              GoldenTestScenario(
                name: 'palette',
                child: _themed(
                  WaxThemeVariant.dark,
                  SizedBox(
                    width: 560,
                    height: 340,
                    child: WaxCommandPalette(
                      onQueryChanged: (_) {},
                      onRun: (_) {},
                      onClose: () {},
                      groups: const <WaxPaletteGroup>[
                        WaxPaletteGroup(
                          title: 'Commands',
                          entries: <WaxPaletteEntry>[
                            WaxPaletteEntry(
                              id: 'play',
                              label: 'Play or pause',
                              glyph: WaxIcons.play,
                              shortcut: 'Space',
                            ),
                            WaxPaletteEntry(
                              id: 'queue',
                              label: 'Show the queue',
                              detail: 'Opens beside the page on a desktop',
                              glyph: WaxIcons.queue,
                              shortcut: 'Ctrl Q',
                            ),
                          ],
                        ),
                        WaxPaletteGroup(
                          title: 'Library',
                          entries: <WaxPaletteEntry>[
                            WaxPaletteEntry(
                              id: 'al-1',
                              label: 'The Harbour Tapes',
                              detail: 'Album · Nightjar',
                              glyph: WaxIcons.albums,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              GoldenTestScenario(
                name: 'shortcut sheet',
                child: _themed(
                  WaxThemeVariant.dark,
                  SizedBox(
                    width: 520,
                    height: 400,
                    child: WaxShortcutSheet(
                      onClose: () {},
                      groups: const <WaxShortcutGroup>[
                        WaxShortcutGroup(
                          title: 'Playback',
                          rows: <WaxShortcutRow>[
                            WaxShortcutRow(
                              label: 'Play or pause',
                              keys: 'Space',
                            ),
                            WaxShortcutRow(label: 'Next track', keys: 'Ctrl →'),
                            WaxShortcutRow(label: 'Volume up', keys: 'Ctrl ↑'),
                          ],
                        ),
                        WaxShortcutGroup(
                          title: 'Getting around',
                          rows: <WaxShortcutRow>[
                            WaxShortcutRow(
                              label: 'Command palette',
                              keys: 'Ctrl K',
                            ),
                            WaxShortcutRow(label: 'Search', keys: '/'),
                          ],
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
          'the dial and the mini window are their own surfaces',
          fileName: 'dial_and_mini_player',
          pumpBeforeTest: _pumpAnimated,
          builder: () => GoldenTestGroup(
            columns: 1,
            children: <Widget>[
              for (final variant in _lightAndDark)
                GoldenTestScenario(
                  name: 'dial ${variant.name}',
                  child: _themed(
                    variant,
                    SizedBox(
                      width: 460,
                      height: 260,
                      child: StationDial(
                        onTune: (_) {},
                        onStop: () {},
                        initialIndex: 1,
                        stations: const <DialStation>[
                          DialStation(name: 'Coastal FM'),
                          DialStation(
                            name: 'Ora Lune',
                            nowPlaying: 'Bell Tower',
                            playing: true,
                          ),
                          DialStation(name: 'Night Bus Radio'),
                          DialStation(name: 'Harbour Jazz'),
                        ],
                      ),
                    ),
                  ),
                ),
              // The mini window is a fixed 320 by 96 by contract, so the
              // golden is the whole window rather than a slice of one.
              GoldenTestScenario(
                name: 'mini player',
                child: _themed(
                  WaxThemeVariant.dark,
                  SizedBox(
                    width: 320,
                    height: 96,
                    child: MiniPlayer(
                      now: _music,
                      onRestore: () {},
                      actions: DeckBarActions(
                        onPlayPause: () {},
                        onNext: () {},
                        onPrevious: () {},
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

        goldenTest(
          'the controls the later phases added',
          fileName: 'late_controls',
          builder: () => GoldenTestGroup(
            columns: 3,
            children: <Widget>[
              for (final variant in WaxThemeVariant.values)
                GoldenTestScenario(
                  name: variant.name,
                  child: _themed(
                    variant,
                    SizedBox(
                      width: 300,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          // The volume row: slider plus its mute glyph,
                          // which is one control over one piece of state.
                          WaxSlider(
                            value: 0.62,
                            label: 'Volume',
                            glyph: WaxIcons.volume,
                            mutedGlyph: WaxIcons.volumeMuted,
                            onMute: () {},
                            onChanged: (_) {},
                          ),
                          const SizedBox(height: WaxSpace.s12),
                          WaxSlider(
                            value: 0,
                            muted: true,
                            label: 'Volume',
                            glyph: WaxIcons.volume,
                            mutedGlyph: WaxIcons.volumeMuted,
                            onMute: () {},
                            onChanged: (_) {},
                          ),
                          const SizedBox(height: WaxSpace.s12),
                          WaxSegmented(
                            label: 'Order',
                            selected: 'added',
                            onSelect: (_) {},
                            segments: const <WaxSegment>[
                              WaxSegment(name: 'az', label: 'A-Z'),
                              WaxSegment(name: 'added', label: 'Added'),
                            ],
                          ),
                          const SizedBox(height: WaxSpace.s12),
                          Row(
                            children: <Widget>[
                              WaxPill(
                                label: 'Speed 1.4 times',
                                text: '1.4x',
                                mono: true,
                                selected: true,
                                onPressed: () {},
                              ),
                              const SizedBox(width: WaxSpace.s8),
                              WaxPill(
                                label: 'Sleep timer',
                                text: 'Sleep',
                                onPressed: () {},
                              ),
                              const SizedBox(width: WaxSpace.s8),
                              StarButton(starred: false, onChanged: (_) {}),
                            ],
                          ),
                          const SizedBox(height: WaxSpace.s12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: WaxFab(
                              label: 'Play everything',
                              glyph: WaxIcons.play,
                              onPressed: () {},
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
      });
    },
  );
}
