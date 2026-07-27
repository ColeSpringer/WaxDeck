import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../sample_library.dart';

/// Album detail: the entity header, the track list, and the power-user
/// channel one level down.
///
/// The header wash comes from the cover, the actions read as verbs, and
/// the technical detail (codec, bitrate, provenance) sits in mono at the
/// bottom where a family member never has to meet it.
class AlbumComposite extends StatelessWidget {
  const AlbumComposite({required this.art, this.now, super.key});

  final SampleArt art;
  final NowPlayingData? now;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final sizeClass = WaxSizeClass.of(context);
    final tracks = SampleLibrary.albumTracks();

    return WaxScaffold(
      title: SampleLibrary.albumTitle,
      largeTitle: false,
      onBack: () {},
      actions: <Widget>[
        WaxIconButton(
          glyph: WaxIcons.more,
          label: 'More for this album',
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
                // The composite shows the finished bar, so its right
                // cluster is wired: an unwired control is not drawn.
                onQueue: () {},
                onLyrics: () {},
                onCast: () {},
                onMore: () {},
              ),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          EntityHeader(
            title: SampleLibrary.albumTitle,
            subtitle: SampleLibrary.albumArtist,
            metadata: SampleLibrary.albumMeta,
            description: SampleLibrary.albumNote,
            artwork: art.of('Salt Harbour'),
            actions: <Widget>[
              WaxButton(label: 'Play', icon: WaxIcons.play, onPressed: () {}),
              WaxButton(
                label: 'Shuffle',
                kind: WaxButtonKind.tonal,
                icon: WaxIcons.shuffle,
                onPressed: () {},
              ),
              StarButton(starred: true, onChanged: (_) {}),
              WaxIconButton(
                glyph: WaxIcons.downloads,
                label: 'Download album',
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: WaxSpace.s16),
          for (var i = 0; i < tracks.length; i++)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: sizeClass.gutter.horizontal / 2,
              ),
              child: MediaListRow(
                data: tracks[i],
                leadingIndex: i + 1,
                playing: i == 1,
                onTap: () {},
                onMore: () {},
              ),
            ),
          const SizedBox(height: WaxSpace.s24),
          Padding(
            padding: sizeClass.gutter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SectionHeader(overline: 'Detail', title: 'This release'),
                Wrap(
                  spacing: WaxSpace.s8,
                  runSpacing: WaxSpace.s8,
                  children: const <Widget>[
                    CodecChip('FLAC 24/96', emphasis: true),
                    CodecChip('2.1 GB'),
                    CodecChip('MusicBrainz'),
                    CodecChip('ReplayGain -7.2 dB'),
                  ],
                ),
                const SizedBox(height: WaxSpace.s16),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface1,
                    borderRadius: WaxRadius.card,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(WaxSpace.s16),
                    child: Column(
                      children: <Widget>[
                        MonoDetailRow(
                          label: 'Album id',
                          value: 'al-01JQ8Z3K7T',
                        ),
                        MonoDetailRow(
                          label: 'Added',
                          value: '2026-02-11 21:14',
                        ),
                        MonoDetailRow(
                          label: 'Source',
                          value: '/library/nightjar/salt-harbour',
                        ),
                        MonoDetailRow(
                          label: 'Scanned',
                          value: '9 files, 0 skipped',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: WaxSpace.s32),
        ],
      ),
    );
  }
}
