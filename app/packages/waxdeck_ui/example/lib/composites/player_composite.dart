import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../sample_library.dart';

/// The full player, in each of its faces.
///
/// One scaffold, four configurations: music gets a waveform and a
/// queue peek, podcasts get interval seeks and a speed chip, books put
/// the chapter first, radio drops the seek bar entirely because there is
/// nothing to seek on a live stream.
class PlayerComposite extends StatelessWidget {
  const PlayerComposite({
    required this.art,
    this.face = WaxDomain.music,
    super.key,
  });

  final SampleArt art;
  final WaxDomain face;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final now = switch (face) {
      WaxDomain.music => SampleLibrary.nowPlayingMusic(art),
      WaxDomain.podcasts => SampleLibrary.nowPlayingPodcast(art),
      WaxDomain.audiobooks => SampleLibrary.nowPlayingBook(art),
      WaxDomain.radio => SampleLibrary.nowPlayingRadio(art),
    };

    return PlayerScaffold(
      now: now,
      onCollapse: () {},
      trailingHeaderActions: <Widget>[
        WaxIconButton(
          glyph: WaxIcons.cast,
          label: 'Play on another device',
          onPressed: () {},
        ),
        WaxIconButton(glyph: WaxIcons.more, label: 'More', onPressed: () {}),
      ],
      titleTrailing: face == WaxDomain.radio
          ? null
          : StarButton(starred: now.starred, onChanged: (_) {}),
      seek: SeekCluster(
        now: now,
        onSeek: (_) {},
        peaks: face == WaxDomain.music ? SampleLibrary.peaks() : null,
        remainingLabel: face == WaxDomain.audiobooks
            ? '42 percent · 6 hr 12 min left'
            : null,
      ),
      transport: TransportCluster(
        playing: now.playing,
        live: now.live,
        onPlayPause: () {},
        onPrevious: face == WaxDomain.music ? () {} : null,
        onNext: face == WaxDomain.music ? () {} : null,
        onSkipBack: face == WaxDomain.podcasts || face == WaxDomain.audiobooks
            ? () {}
            : null,
        onSkipForward:
            face == WaxDomain.podcasts || face == WaxDomain.audiobooks
            ? () {}
            : null,
        onShuffle: face == WaxDomain.music ? () {} : null,
        onRepeat: face == WaxDomain.music ? () {} : null,
        skipBackSeconds: face == WaxDomain.audiobooks ? 30 : 15,
      ),
      actionRow: _actionRow(colors),
      bottomRegion: face == WaxDomain.radio ? null : _bottomRegion(colors),
    );
  }

  Widget _actionRow(WaxColors colors) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: <Widget>[
      if (face == WaxDomain.music) ...<Widget>[
        WaxIconButton(
          glyph: WaxIcons.lyrics,
          label: 'Lyrics',
          onPressed: () {},
        ),
        WaxIconButton(glyph: WaxIcons.queue, label: 'Queue', onPressed: () {}),
        WaxIconButton(
          glyph: WaxIcons.waveform,
          label: 'More like this',
          onPressed: () {},
        ),
      ],
      if (face == WaxDomain.podcasts ||
          face == WaxDomain.audiobooks) ...<Widget>[
        _speedChip(colors),
        WaxIconButton(
          glyph: WaxIcons.sleepTimer,
          label: 'Sleep timer',
          onPressed: () {},
        ),
        if (face == WaxDomain.audiobooks)
          WaxIconButton(
            glyph: WaxIcons.bookmark,
            label: 'Bookmarks',
            onPressed: () {},
          )
        else
          WaxIconButton(
            glyph: WaxIcons.downloads,
            label: 'Download episode',
            onPressed: () {},
          ),
      ],
      if (face == WaxDomain.radio) ...<Widget>[
        WaxIconButton(
          glyph: WaxIcons.search,
          label: 'Find this song in your library',
          onPressed: () {},
        ),
        WaxIconButton(
          glyph: WaxIcons.info,
          label: 'Station info',
          onPressed: () {},
        ),
      ],
    ],
  );

  Widget _speedChip(WaxColors colors) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s8),
    child: Semantics(
      button: true,
      label: 'Playback speed',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: WaxSpace.s12,
            vertical: WaxSpace.s8,
          ),
          decoration: BoxDecoration(
            color: colors.surface2,
            borderRadius: WaxRadius.pill,
            border: Border.all(color: colors.hairline),
          ),
          child: Text(
            face == WaxDomain.audiobooks ? '1.35x' : '1.2x',
            style: WaxType.monoData.copyWith(color: colors.textPrimary),
          ),
        ),
      ),
    ),
  );

  /// Up next for music, chapters for spoken word: the drag-up region the
  /// scaffold reserves.
  Widget _bottomRegion(WaxColors colors) => Container(
    decoration: BoxDecoration(
      color: colors.surface1.withValues(alpha: 0.92),
      borderRadius: WaxRadius.sheetTop,
      border: Border(top: BorderSide(color: colors.hairline)),
    ),
    padding: const EdgeInsets.fromLTRB(
      WaxSpace.s16,
      WaxSpace.s8,
      WaxSpace.s16,
      WaxSpace.s16,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(bottom: WaxSpace.s8),
          decoration: BoxDecoration(
            color: colors.textTertiary,
            borderRadius: WaxRadius.pill,
          ),
        ),
        Row(
          children: <Widget>[
            Text(
              face == WaxDomain.music ? 'UP NEXT' : 'CHAPTERS',
              style: WaxType.overline.copyWith(color: colors.textTertiary),
            ),
            const Spacer(),
            Text(
              face == WaxDomain.music ? 'Salt Harbour · 7 left' : '18 chapters',
              style: WaxType.caption.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: WaxSpace.s4),
        MediaListRow(
          data: face == WaxDomain.music
              ? const MediaTileData(
                  title: 'Gullwing',
                  subtitle: 'Nightjar',
                  trailingText: '5:41',
                )
              : const MediaTileData(
                  title: 'Chapter 15: Spring Range',
                  subtitle: 'A History of Tides',
                  trailingText: '31:08',
                  domain: WaxDomain.audiobooks,
                ),
          leadingIndex: face == WaxDomain.music ? 3 : 15,
          onTap: () {},
        ),
      ],
    ),
  );
}
