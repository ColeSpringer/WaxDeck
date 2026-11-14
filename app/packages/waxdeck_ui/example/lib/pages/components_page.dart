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
  bool _notesOpen = false;
  bool _notesOverflow = false;

  /// The demo footer's page, asked for and never landing until the link
  /// under it lands it.
  bool _paging = false;

  /// Where the split-pane seam below sits. The component holds no width
  /// of its own, so somewhere has to; in the app that is a stored
  /// per-device preference.
  double _seam = 260;

  /// The same position the seek bars above draw, as the listenable the
  /// lyrics and the visualizer follow. They take one because a playhead
  /// moves several times a second and neither rebuilds for it; here the
  /// catalogue's own scrubbing is what moves it.
  late final ValueNotifier<Duration> _live = ValueNotifier(_position);

  /// Holds a value the validator below refuses, so its line shows.
  final TextEditingController _address = TextEditingController(
    text: 'waxdeck.local',
  );

  @override
  void dispose() {
    _live.dispose();
    _address.dispose();
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
            const WaxButton(
              label: 'Downloading',
              kind: WaxButtonKind.tonal,
              icon: WaxIcons.downloads,
              progress: 0.42,
              onPressed: null,
            ),
            const WaxButton(
              label: 'Queued for download',
              icon: WaxIcons.downloads,
              status: true,
              onPressed: null,
            ),
            SizedBox(
              width: 200,
              child: WaxButton(
                label: 'Download every episode of this show',
                kind: WaxButtonKind.tonal,
                icon: WaxIcons.downloads,
                onPressed: () {},
              ),
            ),
            // States to read: lit, never the disabled tint.
            const WaxIconButton(
              glyph: WaxIcons.success,
              label: 'Downloaded',
              active: true,
              status: true,
              onPressed: null,
            ),
            const WaxIconButton(
              glyph: WaxIcons.downloads,
              label: 'Waiting for wifi',
              status: true,
              onPressed: null,
            ),
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
            // What the glyph leaves out, on hover, focus or long press.
            WaxIconButton(
              glyph: WaxIcons.downloads,
              label: 'Retry download',
              detail: 'Not enough space on this device',
              color: colors.error,
              onPressed: () {},
            ),
          ],
        ),
        const SizedBox(height: WaxSpace.s12),
        // Pills: selected, plain, busy while its work runs, and disabled.
        Wrap(
          spacing: WaxSpace.s8,
          runSpacing: WaxSpace.s8,
          children: <Widget>[
            WaxPill(
              label: 'Speed 1.4 times',
              text: '1.4x',
              mono: true,
              selected: true,
              onPressed: () {},
            ),
            WaxPill(label: 'Sleep timer', text: 'Sleep', onPressed: () {}),
            WaxPill(label: 'Voice boost', busy: true, onPressed: () {}),
            const WaxPill(label: 'Trim silence', onPressed: null),
          ],
        ),
        const SizedBox(height: WaxSpace.s24),

        // An entity's row: one primary, the download in each of its
        // states, the star cluster, and the overflow last.
        const SectionHeader(overline: 'Controls', title: 'Action bar'),
        WaxActionBar(
          actions: <WaxAction>[
            WaxAction(
              label: 'Play',
              semanticsId: 'play',
              glyph: WaxIcons.play,
              emphasis: WaxActionEmphasis.primary,
              onPressed: () {},
            ),
            WaxAction(
              label: 'Download',
              semanticsId: 'ready',
              glyph: WaxIcons.downloads,
              onPressed: () {},
            ),
            WaxAction(
              label: 'Download',
              semanticsId: 'busy',
              glyph: WaxIcons.downloads,
              state: const WaxActionState.busy(),
              onPressed: () {},
            ),
            const WaxAction(
              label: 'Downloading',
              semanticsId: 'progress',
              glyph: WaxIcons.downloads,
              state: WaxActionState.progress(0.42),
            ),
            const WaxAction(
              label: 'Downloaded',
              semanticsId: 'done',
              glyph: WaxIcons.downloads,
              state: WaxActionState.done(),
            ),
            const WaxAction(
              label: 'Queued for download',
              semanticsId: 'status',
              glyph: WaxIcons.downloads,
              state: WaxActionState.status(),
              detail: 'Waits for Wi-Fi',
            ),
            WaxAction(
              label: 'Retry download',
              semanticsId: 'failed',
              glyph: WaxIcons.downloads,
              state: const WaxActionState.failed(),
              detail: 'Not enough space on this device',
              onPressed: () {},
            ),
          ],
          trailing: <Widget>[
            StarButton(
              starred: _starred,
              onChanged: (value) => setState(() => _starred = value),
            ),
          ],
          overflow: WaxMenuButton<String>(
            items: const <WaxMenuItem<String>>[
              WaxMenuItem<String>(value: 'share', label: 'Share'),
              WaxMenuItem<String>(value: 'edit', label: 'Edit details'),
            ],
            onSelected: (_) {},
          ),
        ),
        const SizedBox(height: WaxSpace.s24),

        const SectionHeader(overline: 'Controls', title: 'Tooltips'),
        // Three in a row, which is the case the component exists for:
        // rest on one and its label appears after the wait; slide along
        // and each of the others waits the same, rather than opening
        // the instant the pointer arrives because a neighbour is still
        // fading out.
        Wrap(
          spacing: WaxSpace.s12,
          children: <Widget>[
            for (final (glyph, label) in const <(WaxGlyph, String)>[
              (WaxIcons.shuffle, 'Shuffle'),
              (WaxIcons.repeatAll, 'Repeat'),
              (WaxIcons.queue, 'Queue'),
            ])
              WaxIconButton(glyph: glyph, label: label, onPressed: () {}),
          ],
        ),
        const SizedBox(height: WaxSpace.s12),
        // The explanation a label does not carry: hover or focus shows it,
        // a tap opens it, and Escape or a tap elsewhere closes it again.
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Play count'),
            WaxInfoTip(message: 'Counts only the plays you listened through'),
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
        // A field a form checks, holding a value it refuses, and one that
        // only applies while another control is on.
        SizedBox(
          width: 360,
          child: Form(
            autovalidateMode: AutovalidateMode.always,
            child: WaxTextField(
              label: 'Server address',
              controller: _address,
              autocorrect: false,
              validator: (value) =>
                  (value ?? '').startsWith(RegExp('https?://'))
                  ? null
                  : 'Start with http:// or https://',
            ),
          ),
        ),
        const SizedBox(height: WaxSpace.s12),
        const SizedBox(
          width: 360,
          child: WaxTextField(
            label: 'Only these words',
            hint: 'Download episodes whose title has',
            enabled: false,
          ),
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

        const SectionHeader(overline: 'Controls', title: 'Settings rows'),
        // A settings section as the app draws one: its own header, holding
        // the sentence it does not print behind the glyph after its title,
        // then rows of one decision each.
        ReadingColumn(
          child: Column(
            children: <Widget>[
              const SectionHeader(
                title: 'Playback',
                info: 'Applies on this device only',
              ),
              // A label that says it all: no help line.
              WaxSettingRow(
                title: 'Show lyrics',
                control: WaxSwitch(
                  value: true,
                  label: 'Show lyrics',
                  onChanged: (_) {},
                ),
              ),
              WaxSettingRow(
                title: 'Prepare the next track',
                help:
                    'Only on wifi, so mobile data is spent on what you asked for',
                glyph: WaxIcons.downloads,
                control: WaxSwitch(
                  value: true,
                  label: 'Prepare the next track on wifi only',
                  onChanged: (_) {},
                ),
              ),
              WaxSettingRow(
                title: 'Gapless playback',
                info: 'Joins the tracks an album was mastered to run together',
                control: WaxSwitch(
                  value: false,
                  label: 'Gapless playback',
                  onChanged: (_) {},
                ),
              ),
            ],
          ),
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
        // The bar in its place: a book's header, where the author and the
        // series are links in the text block and a long one wraps in line.
        EntityHeader(
          title: 'A History of Tides',
          subtitle: 'An Almanac of Coasts',
          metadata: 'Audiobook, 11h 42m',
          artwork: art.of('A History of Tides'),
          shape: ArtworkShape.portrait,
          domain: WaxDomain.audiobooks,
          links: <EntityHeaderLink>[
            EntityHeaderLink(
              label: 'By Mirren Vaux',
              semanticsId: 'author-link',
              onPressed: () {},
            ),
            EntityHeaderLink(
              label: 'Book 3 of The Long Chronicle of the Harbour and the Sea',
              semanticsId: 'series-link',
              onPressed: () {},
            ),
          ],
          actions: <WaxAction>[
            WaxAction(
              label: 'Resume',
              semanticsId: 'resume',
              glyph: WaxIcons.play,
              emphasis: WaxActionEmphasis.primary,
              onPressed: () {},
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
        // The same choice while nothing is playing: drawn, not pressable.
        WaxSegmented(
          label: 'Visualizer mode',
          selected: _visualizer.name,
          segments: <WaxSegment>[
            for (final mode in WaxVisualizerMode.values)
              WaxSegment(name: mode.name, label: mode.label(context.waxL10n)),
          ],
          onSelect: null,
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
              // A play count before the duration: a glyph and a number
              // drawn, a sentence on hover and read aloud.
              MediaListRow(
                data: const MediaTileData(
                  title: 'Harbour Lights',
                  subtitle: 'Nightjar',
                  trailingText: '4:18',
                  playCount: 12,
                  playCountLabel: 'played 12 times',
                ),
                leadingIndex: 5,
                onTap: () {},
                onMore: () {},
              ),
            ],
          ),
        ),
        const SizedBox(height: WaxSpace.s12),
        // A custom row is one control, its ink and its name on one press.
        // Hairlines rule them off; a disclosure holds its section shut
        // until it is opened.
        for (final (i, (title, detail)) in const <(String, String)>[
          ('Kitchen', 'Speaker on this network'),
          ('Study', 'Last seen yesterday'),
        ].indexed) ...<Widget>[
          if (i > 0) const WaxHairline(),
          WaxInkTappable(
            label: '$title, $detail',
            onPressed: () {},
            child: Padding(
              padding: const EdgeInsets.all(WaxSpace.s12),
              child: Row(
                children: <Widget>[
                  WaxIcon(WaxIcons.cast, size: 20, color: colors.textSecondary),
                  const SizedBox(width: WaxSpace.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: WaxType.body.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          detail,
                          style: WaxType.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const WaxHairline(extent: WaxSpace.s16),
        const WaxDisclosure(
          title: 'Edition',
          children: <Widget>[
            MonoDetailRow(label: 'Publisher', value: 'Harbour Press'),
            MonoDetailRow(label: 'Narrator', value: 'Ora Lune'),
          ],
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
        const SizedBox(height: WaxSpace.s12),
        // Empty, part-way and full, then one of unknown length.
        const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            WaxProgressBar(value: 0),
            SizedBox(height: WaxSpace.s12),
            WaxProgressBar(value: 0.42),
            SizedBox(height: WaxSpace.s12),
            WaxProgressBar(value: 1),
            SizedBox(height: WaxSpace.s12),
            WaxProgressBar(),
          ],
        ),
        const SizedBox(height: WaxSpace.s12),
        // A quota at its cap, drawn in the verdict's colour.
        WaxProgressBar(value: 1, tone: colors.error),
        const SizedBox(height: WaxSpace.s24),

        const SectionHeader(overline: 'Content', title: 'Stats'),
        // The stats screen's headline figures, in its own spacing.
        const Wrap(
          spacing: WaxSpace.s32,
          runSpacing: WaxSpace.s12,
          children: <Widget>[
            StatFigure(value: '2h 6m', caption: 'listened'),
            StatFigure(value: '10', caption: 'sessions'),
            StatFigure(value: '1h 4m', caption: 'time saved'),
          ],
        ),
        const SizedBox(height: WaxSpace.s16),
        // The console's tiles, one height in a row: one bare, one with a
        // caption, one whose caption is cut and one whose value is, each
        // whole in a tooltip and in what the tile says aloud.
        WaxStatGrid(
          tiles: <StatTile>[
            const StatTile(
              label: 'Items',
              value: '104,812',
              glyph: WaxIcons.albums,
            ),
            StatTile(
              label: 'Health',
              value: '82',
              caption: '311 items want attention',
              tone: colors.error,
              onTap: () {},
            ),
            const StatTile(
              label: 'Pending',
              value: '12',
              caption:
                  'Elementos pendientes de revision por el equipo de catalogo',
            ),
            const StatTile(
              label: 'Streaming',
              value: 'Waiting for its first scan',
            ),
          ],
        ),
        const SizedBox(height: WaxSpace.s16),
        // How listening divides: all four domains at once.
        // One share is small enough to fall to the painter's floor: a
        // sliver thinner than the bar's own rounded ends would draw as a
        // smudge rather than as a share.
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

        const SectionHeader(overline: 'Content', title: 'Clamped text'),
        // The control follows the box's report, so a short note gets none.
        SizedBox(
          width: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClampedBox(
                budget: 64,
                clamped: !_notesOpen,
                onOverflow: (value) {
                  if (mounted && value != _notesOverflow) {
                    setState(() => _notesOverflow = value);
                  }
                },
                child: Text(
                  'A weekly hour of field recordings from harbours, markets '
                  'and train yards, stitched into one long walk. This week '
                  'the tide comes in over the mud flats at dawn, a ferry '
                  'horn answers from across the estuary, and the fish '
                  'market opens its shutters.',
                  style: WaxType.body.copyWith(color: colors.textSecondary),
                ),
              ),
              if (_notesOverflow)
                WaxButton(
                  label: _notesOpen ? 'Show less' : 'Show more',
                  kind: WaxButtonKind.inline,
                  onPressed: () => setState(() => _notesOpen = !_notesOpen),
                ),
            ],
          ),
        ),
        const SizedBox(height: WaxSpace.s24),

        const SectionHeader(overline: 'Content', title: 'Artwork shapes'),
        Wrap(
          spacing: WaxSpace.s16,
          runSpacing: WaxSpace.s16,
          children: <Widget>[
            ArtworkImage(size: 96, artwork: art.of('Salt Harbour')),
            ArtworkImage(
              size: 96,
              artwork: art.of('A History of Tides'),
              shape: ArtworkShape.portrait,
              domain: WaxDomain.audiobooks,
            ),
            ArtworkImage(
              size: 96,
              artwork: art.of('Coastal FM'),
              shape: ArtworkShape.circle,
              domain: WaxDomain.radio,
            ),
            const ArtworkImage(
              size: 96,
              monogram: 'Nightjar Ensemble',
              domain: WaxDomain.podcasts,
            ),
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
        // Each at the height its words take, side by side where there is
        // room: a fixed box cut them off at large text and on a phone.
        Wrap(
          spacing: WaxSpace.s16,
          runSpacing: WaxSpace.s16,
          children: <Widget>[
            SizedBox(
              width: 320,
              child: EmptyState(
                glyph: WaxIcons.podcasts,
                title: 'No podcasts yet',
                message: 'Follow a show to see new episodes here.',
                actionLabel: 'Find podcasts',
                onAction: () {},
              ),
            ),
            // The message is optional: the title and the way out say it.
            SizedBox(
              width: 320,
              child: EmptyState(
                glyph: WaxIcons.playlists,
                title: 'No playlists yet',
                actionLabel: 'New playlist',
                onAction: () {},
              ),
            ),
            SizedBox(
              width: 320,
              child: ErrorState(
                message:
                    "Can't reach the server. Check the address and try "
                    'again.',
                detail: 'ERR_CONNECTION_REFUSED - 10.0.0.4:4420',
                onRetry: () {},
              ),
            ),
          ],
        ),
        const SizedBox(height: WaxSpace.s12),
        const SkeletonShapes(shape: SkeletonShape.shelf, count: 4),
        const SizedBox(height: WaxSpace.s12),
        const SkeletonShapes(shape: SkeletonShape.list, count: 3),
        const SizedBox(height: WaxSpace.s12),
        // The foot of a list paged by hand: pressed, the button stays busy
        // over the next page's ghost; a page a scroll asked for is the
        // ghost alone, as the second one draws.
        Wrap(
          spacing: WaxSpace.s16,
          runSpacing: WaxSpace.s16,
          children: <Widget>[
            SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  LoadMoreFooter(
                    label: 'Load more episodes',
                    loading: _paging,
                    onLoadMore: () => setState(() => _paging = true),
                  ),
                  WaxButton(
                    label: 'Land the page',
                    kind: WaxButtonKind.inline,
                    onPressed: _paging
                        ? () => setState(() => _paging = false)
                        : null,
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 320,
              child: LoadMoreFooter(
                label: 'Load more episodes',
                loading: true,
                onLoadMore: () {},
              ),
            ),
          ],
        ),
        const SizedBox(height: WaxSpace.s12),
        // The same three in a box shorter than they are, as a short tab or
        // a phone on its side gives them: the panes scroll within, the
        // ghost is cut off at the edge, and none of them overflows.
        Wrap(
          spacing: WaxSpace.s16,
          runSpacing: WaxSpace.s16,
          children: <Widget>[
            SizedBox(
              width: 320,
              height: 140,
              child: EmptyState(
                glyph: WaxIcons.podcasts,
                title: 'No podcasts yet, and nothing followed to fetch',
                actionLabel: 'Find podcasts',
                onAction: () {},
              ),
            ),
            SizedBox(
              width: 320,
              height: 140,
              child: ErrorState(
                message:
                    "Can't reach the server. Check the address and try "
                    'again.',
                onRetry: () {},
              ),
            ),
            const SizedBox(
              width: 320,
              height: 140,
              child: SkeletonShapes(shape: SkeletonShape.list, count: 6),
            ),
          ],
        ),
        const SizedBox(height: WaxSpace.s24),

        const SectionHeader(overline: 'Shell', title: 'Navigation chrome'),
        // One piece of chrome per size class, side by side where the page
        // is wide enough: the point of the frame is that a narrow desktop
        // window behaves like a phone, and that is only judgeable next to
        // the others. Each keeps a width its chrome fits and grows with
        // the text, so a phone stacks them rather than crushing four
        // sidebars into it.
        Wrap(
          spacing: WaxSpace.s16,
          runSpacing: WaxSpace.s16,
          children: <Widget>[
            for (final sizeClass in WaxSizeClass.values)
              SizedBox(
                width: 320,
                height: MediaQuery.textScalerOf(context).scale(380),
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
                            // A logo does not wrap: at large text it
                            // scales down to the sidebar instead.
                            sidebarHeader: const FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: AlignmentDirectional.centerStart,
                              child: WaxWordmark(size: 18),
                            ),
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
          ],
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
