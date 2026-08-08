import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../auth/auth_controller.dart';
import '../home/pin_action.dart';
import '../player/entity_star_rating_row.dart';
import '../player/now_playing_controller.dart';
import '../providers.dart';
import '../queue/queue_state.dart';
import '../search/search_chrome.dart';
import '../settings/client_prefs.dart';
import '../shell/commands.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'album_detail.dart';
import 'entity_facts.dart';
import 'music_controllers.dart';

/// One album: its cover, what it is, and its tracks in the order they
/// were pressed.
///
/// The location is the album's own pid, so this screen is a link
/// somebody can send. It replaces the bucket listing that used to answer
/// here: the same items, but as a release rather than as a filtered
/// list.
class AlbumScreen extends ConsumerWidget {
  const AlbumScreen({required this.pid, this.label, super.key});

  /// The album entity's pid (`al-...`), which is also the bucket handle
  /// its listing drills by.
  final String pid;

  /// The title the caller had in hand. A hint, never a dependency: a
  /// reload or a shared link arrives without one and the screen names
  /// itself from what it loads.
  final String? label;

  MusicListing get _listing => (dimension: MusicDimension.albums, segment: pid);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(musicItemsProvider(_listing));
    final tracks = albumOrder(state.value?.items ?? const <ItemSummary>[]);
    final facts = AlbumFacts.of(tracks, fallbackTitle: label);

    return CommandScope(
      // The header's two buttons, named after this album. The runs read
      // the listing rather than closing over it: a scope keeps the
      // closure it first registered while the offer is unchanged.
      commands: <WaxCommand>[
        if (tracks.isNotEmpty) ...<WaxCommand>[
          WaxCommand(
            id: 'album-play',
            label: 'Play ${facts.title}',
            section: WaxCommandSection.playback,
            glyph: WaxIcons.play,
            run: (context, ref) => _playLive(context, ref),
          ),
          WaxCommand(
            id: 'album-shuffle',
            label: 'Shuffle ${facts.title}',
            section: WaxCommandSection.playback,
            glyph: WaxIcons.shuffle,
            run: (context, ref) => _playLive(context, ref, shuffle: true),
          ),
        ],
      ],
      child: _screen(context, ref, state, tracks, facts),
    );
  }

  void _playLive(BuildContext context, WidgetRef ref, {bool shuffle = false}) {
    final items = ref.read(musicItemsProvider(_listing)).value?.items;
    final tracks = albumOrder(items ?? const <ItemSummary>[]);
    playAlbum(
      context,
      ref,
      pid: pid,
      facts: AlbumFacts.of(tracks, fallbackTitle: label),
      tracks: tracks,
      shuffle: shuffle,
    );
  }

  Widget _screen(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<MusicItemsState> state,
    List<ItemSummary> tracks,
    AlbumFacts facts,
  ) {
    return WaxScaffold(
      title: facts.title,
      largeTitle: false,
      // Pops when something pushed this - an artist's release tile - and
      // goes to the index when nothing did, so the arrow and the system
      // gesture do the same thing from either entry point.
      onBack: () =>
          context.leave(fallback: WaxRoute.musicIndex(MusicDimension.albums)),
      actions: const <Widget>[SearchAction()],
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: _Header(pid: pid, facts: facts, tracks: tracks),
        ),
        switch (state) {
          AsyncData() when tracks.isEmpty => const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: 'Nothing in this album',
              message: 'The tracks that were here have moved or been removed.',
              glyph: WaxIcons.albums,
            ),
          ),
          AsyncData() => _TrackList(
            tracks: tracks,
            albumArtist: facts.artist,
            albumPid: pid,
            albumTitle: facts.title,
          ),
          AsyncError(:final error) => SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(
              title: 'Could not load this album',
              message: error is WaxDeckApiException
                  ? error.message
                  : 'The server did not answer.',
              onRetry: () => ref.invalidate(musicItemsProvider(_listing)),
            ),
          ),
          _ => const SliverFillRemaining(
            hasScrollBody: false,
            child: SkeletonShapes(shape: SkeletonShape.list),
          ),
        },
        if (tracks.isNotEmpty)
          SliverToBoxAdapter(child: _ReleaseDetail(track: tracks.first)),
        SliverToBoxAdapter(child: _AlbumIdentity(pid: pid)),
      ],
    );
  }
}

/// The release's own identity: barcode, label, catalog number, media,
/// country.
///
/// Deliberately not behind the technical-details switch that governs the
/// codec chip above. That switch draws the line between what the *file*
/// is and what the *release* is, and every one of these is the second: a
/// catalog number is printed on the sleeve.
///
/// Renders nothing at all when the album carries none of the five, which
/// is most of them - a header of five blank labels would be worse than
/// no block, and the absence is not something a listener can act on.
class _AlbumIdentity extends ConsumerWidget {
  const _AlbumIdentity({required this.pid});

  final String pid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Silent while loading and silent on failure, like the "Appears on"
    // shelf: identity is an extra, and the screen is complete without it.
    final album = ref.watch(albumDetailProvider(pid)).value;
    if (album == null || !album.hasIdentity) return const SizedBox.shrink();
    final colors = WaxColors.of(context);
    final sizeClass = WaxSizeClass.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        sizeClass.gutter.horizontal / 2,
        0,
        sizeClass.gutter.horizontal / 2,
        WaxSpace.s32,
      ),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        identifier: SemanticsIds.albumIdentity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SectionHeader(title: 'Release', overline: 'This edition'),
            for (final field in albumIdentityFields)
              if (albumIdentityValue(album, field.name) case final value
                  when value.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: WaxSpace.s8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: 140,
                        child: Text(
                          field.label,
                          style: WaxType.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          value,
                          style: WaxType.body.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// Plays this album and opens the player on it. The header's buttons and
/// the palette's rows both run this.
void playAlbum(
  BuildContext context,
  WidgetRef ref, {
  required String pid,
  required AlbumFacts facts,
  required List<ItemSummary> tracks,
  bool shuffle = false,
}) {
  if (tracks.isEmpty) return;
  ref
      .read(nowPlayingProvider.notifier)
      .play(
        tracks,
        shuffle: shuffle,
        source: QueueSource(
          kind: QueueSourceKind.album,
          label: facts.title,
          pid: pid,
        ),
      );
  context.push(WaxRoute.nowPlaying);
}

class _Header extends ConsumerWidget {
  const _Header({required this.pid, required this.facts, required this.tracks});

  final String pid;
  final AlbumFacts facts;
  final List<ItemSummary> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin =
        ref
            .watch(authControllerProvider)
            .value
            ?.user
            ?.roles
            .contains('admin') ??
        false;
    void play({bool shuffle = false}) => playAlbum(
      context,
      ref,
      pid: pid,
      facts: facts,
      tracks: tracks,
      shuffle: shuffle,
    );

    return EntityHeader(
      title: facts.title,
      subtitle: facts.artist,
      metadata: facts.caption,
      artwork: ref
          .watch(artworkStoreProvider)
          .source(ref.watch(repositoryProvider).artUrlFor(pid)),
      actions: <Widget>[
        WaxButton(
          label: 'Play',
          icon: WaxIcons.play,
          onPressed: tracks.isEmpty ? null : play,
          semanticsId: SemanticsIds.entityPlay,
        ),
        WaxButton(
          label: 'Shuffle',
          kind: WaxButtonKind.tonal,
          icon: WaxIcons.shuffle,
          onPressed: tracks.isEmpty ? null : () => play(shuffle: true),
          semanticsId: SemanticsIds.entityShuffle,
        ),
        EntityStarRatingRow(pid: pid, label: 'album'),
        WaxMenuButton<String>(
          semanticsId: SemanticsIds.entityOverflow,
          items: <WaxMenuItem<String>>[
            pinMenuItem<String>(
              ref,
              pid,
              value: 'pin',
              semanticsId: SemanticsIds.entityPin,
            ),
            // Administrators only, like every other editing door: the
            // entity edit endpoint answers 403 to anyone else, and a row
            // that opens a form nobody can save is worse than no row.
            if (isAdmin)
              WaxMenuItem<String>(
                value: 'edit',
                label: 'Edit album details',
                glyph: WaxIcons.edit,
                semanticsId: SemanticsIds.albumEditDetails,
              ),
          ],
          onSelected: (choice) => switch (choice) {
            'pin' => unawaited(
              togglePin(context, ref, pid, label: facts.title),
            ),
            _ => unawaited(context.push(WaxRoute.metadata(pid))),
          },
        ),
      ],
    );
  }
}

/// The tracks, numbered, with a separator where a multi-disc release
/// changes disc.
class _TrackList extends ConsumerWidget {
  const _TrackList({
    required this.tracks,
    required this.albumPid,
    required this.albumTitle,
    this.albumArtist,
  });

  final List<ItemSummary> tracks;

  /// The release this list belongs to, which is what a queue built from
  /// it is playing from - not whatever the tapped row happens to carry,
  /// which on a row with no album handle would lose the entity a refill
  /// needs and caption the queue differently from the header above it.
  final String albumPid;
  final String albumTitle;

  /// Whose release this is, so a row only names an artist where it is
  /// not that one. Null on a compilation, where every row differs and
  /// every row says so.
  final String? albumArtist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    final sizeClass = WaxSizeClass.of(context);
    // An untagged disc is disc one, the same reading the sort uses: a
    // release with disc two tagged and disc one not is the common
    // half-tagged shape, and calling its first side "disc 0" would be a
    // number that appears nowhere on the record.
    int discOf(ItemSummary track) => track.discNumber ?? 1;
    final multiDisc = tracks.any((t) => discOf(t) > 1);
    return SliverList.builder(
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        final disc = discOf(track);
        final startsDisc =
            multiDisc && (index == 0 || discOf(tracks[index - 1]) != disc);
        final row = Padding(
          padding: EdgeInsets.symmetric(
            horizontal: sizeClass.gutter.horizontal / 2,
          ),
          child: MediaListRow(
            data: MediaTileData(
              title: track.title,
              // The album's own artist is in the header; a row names its
              // own only where it differs, which is what makes a
              // compilation readable and an ordinary release quiet.
              subtitle: track.artist == albumArtist ? null : track.artist,
              trailingText: formatTimecode(
                Duration(milliseconds: track.durationMs),
              ),
              semanticsId: SemanticsIds.indexItem(index),
            ),
            leadingIndex: track.trackNumber ?? index + 1,
            onTap: () => _play(context, ref, index),
          ),
        );
        if (!startsDisc) return row;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(
                sizeClass.gutter.horizontal / 2,
                WaxSpace.s16,
                sizeClass.gutter.horizontal / 2,
                WaxSpace.s4,
              ),
              child: Text(
                'DISC $disc',
                style: WaxType.overline.copyWith(color: colors.textTertiary),
              ),
            ),
            row,
          ],
        );
      },
    );
  }

  void _play(BuildContext context, WidgetRef ref, int index) {
    ref
        .read(nowPlayingProvider.notifier)
        .play(
          tracks,
          startIndex: index,
          source: QueueSource(
            kind: QueueSourceKind.album,
            label: albumTitle,
            pid: albumPid,
          ),
        );
    context.push(WaxRoute.nowPlaying);
  }
}

/// The technical line at the end of the list: what this release is, in
/// mono, where somebody looking for it will find it and nobody else has
/// to meet it.
class _ReleaseDetail extends ConsumerWidget {
  const _ReleaseDetail({required this.track});

  final ItemSummary track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final detail = ref.watch(itemDetailProvider(track.pid)).value;
    if (detail == null) return const SizedBox(height: WaxSpace.s32);
    // Asked for rather than guarded on the codec: a release with a
    // sample rate and no codec still has something to say, and one with
    // neither answers empty and draws no chip at all.
    //
    // The codec is the only chip here the technical-details switch
    // governs. A year and a genre are what a release is about; the
    // format is what the file is, which is the distinction the switch
    // draws.
    final codec = ref.watch(technicalDetailsProvider)
        ? codecChipLabel(detail)
        : '';
    final chips = <String>[
      if (codec.isNotEmpty) codec,
      if (detail.year != null) '${detail.year}',
      ...detail.genres,
    ];
    if (chips.isEmpty) return const SizedBox(height: WaxSpace.s32);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        sizeClass.gutter.horizontal / 2,
        WaxSpace.s24,
        sizeClass.gutter.horizontal / 2,
        WaxSpace.s32,
      ),
      child: Wrap(
        spacing: WaxSpace.s8,
        runSpacing: WaxSpace.s8,
        children: <Widget>[
          for (var i = 0; i < chips.length; i++)
            CodecChip(chips[i], emphasis: i == 0),
        ],
      ),
    );
  }
}
