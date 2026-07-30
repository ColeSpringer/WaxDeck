import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../player/entity_star_rating_row.dart';
import '../player/now_playing_controller.dart';
import '../providers.dart';
import '../queue/queue_state.dart';
import '../search/search_chrome.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'music_controllers.dart';

/// What the queue an artist screen builds is a window over.
///
/// One builder for all three entry points - Play, Shuffle, and a tapped
/// row - because they queue the same scope and a source that differed
/// between them would mean the same artist refilled from one button and
/// stopped at the cap from another.
QueueSource artistSource(String pid, String name, MusicItemsState? state) =>
    QueueSource(
      kind: QueueSourceKind.artist,
      label: name,
      pid: pid,
      // An artist with more tracks than one page is a window, and the
      // listing's own cursor is where the queue draws the rest as it drains.
      rolling: state?.hasMore ?? false,
      cursor: state?.nextCursor ?? '',
    );

/// How many tracks an artist screen shows before it hands the rest to
/// the full listing. Enough to recognise the artist by, short enough
/// that the albums above it stay the point of the screen.
const int _topTracks = 5;

/// One artist: their releases and a way into everything they play on.
///
/// Addressed by the artist's own pid, which is the same handle the
/// index and search hand over, so this screen is a link.
class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({required this.pid, this.label, super.key});

  final String pid;

  /// The name the caller had. A hint: a shared link carries none and the
  /// screen names itself from the tracks it loads.
  final String? label;

  MusicListing get _listing =>
      (dimension: MusicDimension.artists, segment: pid);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(musicItemsProvider(_listing));
    // Everything the bucket holds, books included: it counted them, and
    // a screen that showed fewer than the count promised would be the
    // one thing faceted browse cannot do. An author whose whole
    // catalogue is audiobooks gets their books here rather than an empty
    // page under their own name.
    final items = state.value?.items ?? const <ItemSummary>[];
    final name = items.firstOrNull?.artist ?? label ?? 'Artist';

    return WaxScaffold(
      title: name,
      largeTitle: false,
      onBack: () =>
          context.leave(fallback: WaxRoute.musicIndex(MusicDimension.artists)),
      actions: const <Widget>[SearchAction()],
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: _Header(
            pid: pid,
            name: name,
            items: items,
            state: state.value,
          ),
        ),
        switch (state) {
          AsyncData() when items.isEmpty => const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: 'Nothing by this artist',
              message: 'The items that were here have moved or been removed.',
              glyph: WaxIcons.artists,
            ),
          ),
          AsyncData() => SliverToBoxAdapter(
            child: _Body(
              pid: pid,
              name: name,
              items: items,
              state: state.value,
            ),
          ),
          AsyncError(:final error) => SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(
              title: 'Could not load this artist',
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
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.pid,
    required this.name,
    required this.items,
    required this.state,
  });

  final String pid;
  final String name;
  final List<ItemSummary> items;
  final MusicItemsState? state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = albumsOf(items);
    final tracks = playableOf(items);
    final loaded = state;
    void play({bool shuffle = false}) {
      if (tracks.isEmpty) return;
      ref
          .read(nowPlayingProvider.notifier)
          .play(
            tracks,
            shuffle: shuffle,
            source: artistSource(pid, name, loaded),
          );
      context.push(WaxRoute.nowPlaying);
    }

    return EntityHeader(
      title: name,
      metadata: [
        '${items.length}${(loaded?.hasMore ?? false) ? '+' : ''} '
            '${items.length == 1 ? 'item' : 'items'}',
        if (albums.isNotEmpty)
          '${albums.length} ${albums.length == 1 ? 'release' : 'releases'}',
      ].join(' · '),
      shape: ArtworkShape.circle,
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
        EntityStarRatingRow(pid: pid, label: 'artist'),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.pid,
    required this.name,
    required this.items,
    required this.state,
  });

  final String pid;
  final String name;
  final List<ItemSummary> items;
  final MusicItemsState? state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final albums = albumsOf(items);
    final store = ref.watch(artworkStoreProvider);
    final repository = ref.watch(repositoryProvider);
    final top = items.take(_topTracks).toList();
    final tiles = <MediaTileData>[
      for (final album in albums)
        MediaTileData(
          title: album.title,
          subtitle:
              '${album.tracks.length} '
              '${album.tracks.length == 1 ? 'track' : 'tracks'}',
          artwork: album.pid == null
              ? null
              : store.source(repository.artUrlFor(album.pid!)),
          semanticsId: album.pid == null
              ? null
              : SemanticsIds.entityAlbum(album.pid!),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (albums.isNotEmpty) ...<Widget>[
          const SizedBox(height: WaxSpace.s16),
          ShelfRow(
            title: 'Releases',
            items: tiles,
            onTapItem: (tile) {
              // By position, never by title: two releases that share one
              // are exactly what grouping by entity keeps apart, and
              // matching on the text would open the first of them twice.
              // Tiles carry no value equality, so this is identity.
              final at = tiles.indexOf(tile);
              if (at < 0) return;
              final target = albums[at].pid;
              // An album with no entity behind it (a loose folder of
              // tracks tagged with a title) has no location to open;
              // its tracks are still in the list below.
              //
              // Pushed, not gone to: an album is declared under the
              // albums index, which is not where this is, so `go` would
              // rebuild that ancestry and throw the artist away - back
              // from a release would land on the index rather than on
              // the artist whose release it is (ADR-0022).
              if (target != null) {
                context.push(
                  WaxRoute.musicBucket(MusicDimension.albums, target),
                  extra: albums[at].title,
                );
              }
            },
          ),
        ],
        const SizedBox(height: WaxSpace.s16),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: sizeClass.gutter.horizontal / 2,
          ),
          child: SectionHeader(
            // An author's bucket holds books; naming the section for
            // tracks it does not have would be the wrong word on the one
            // screen that has to be right about what it holds.
            title: playableOf(items).isEmpty ? 'Audiobooks' : 'Tracks',
            actionLabel: items.length > top.length ? 'Show all' : null,
            // Pushed rather than gone to, like a release: `go` rebuilds
            // the artists-index ancestry, which throws away a search
            // that pushed this artist. The location stays declared, so
            // a stranger opening it still gets the list.
            onAction: items.length > top.length
                ? () => context.push(WaxRoute.artistTracks(pid), extra: name)
                : null,
            semanticsId: SemanticsIds.entityAllTracks,
          ),
        ),
        for (var i = 0; i < top.length; i++)
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: sizeClass.gutter.horizontal / 2,
            ),
            child: MediaListRow(
              data: MediaTileData(
                title: top[i].title,
                subtitle: top[i].album,
                artwork: store.source(top[i].artUrl),
                trailingText: formatTimecode(
                  Duration(milliseconds: top[i].durationMs),
                ),
                semanticsId: SemanticsIds.indexItem(i),
              ),
              onTap: () => unawaited(_play(context, ref, i)),
            ),
          ),
        const SizedBox(height: WaxSpace.s32),
      ],
    );
  }

  Future<void> _play(BuildContext context, WidgetRef ref, int index) async {
    // A book resumes on its own screen - chapters, speed, position - so
    // a row that is one opens it rather than dropping a twelve-hour file
    // into the queue between two tracks.
    if (items[index].mediaType == MediaType.audiobook) {
      context.push(WaxRoute.book(items[index].pid));
      return;
    }
    final tracks = playableOf(items);
    ref
        .read(nowPlayingProvider.notifier)
        .play(
          tracks,
          startIndex: tracks.indexOf(items[index]),
          source: artistSource(pid, name, state),
        );
    context.push(WaxRoute.nowPlaying);
  }
}

/// What in a bucket plays in sequence.
///
/// A bucket counts whatever carried its artist, books included, and the
/// list shows all of it so the count and the list agree. The queue is a
/// different question: a twelve-hour file dropped between two tracks,
/// captioned with the artist's name, is not what Play was asked for.
List<ItemSummary> playableOf(List<ItemSummary> items) => <ItemSummary>[
  for (final item in items)
    if (item.mediaType != MediaType.audiobook) item,
];

/// One release of an artist's, as the tracks on screen describe it.
class ArtistAlbum {
  const ArtistAlbum({required this.title, required this.tracks, this.pid});

  final String title;
  final String? pid;
  final List<ItemSummary> tracks;
}

/// Groups an artist's tracks into releases.
///
/// By entity pid where the rows carry one, so two albums that share a
/// title stay two albums, and by title where they do not, which is what
/// a loose folder of tagged files looks like. Order is the order the
/// releases first appear in the listing; there is no release date on a
/// summary row to sort by.
List<ArtistAlbum> albumsOf(List<ItemSummary> tracks) {
  final byKey = <String, List<ItemSummary>>{};
  final titles = <String, String>{};
  final pids = <String, String?>{};
  for (final track in playableOf(tracks)) {
    final title = track.album;
    if (title == null || title.isEmpty) continue;
    final key = track.albumPid ?? 'title:$title';
    byKey.putIfAbsent(key, () => <ItemSummary>[]).add(track);
    titles[key] = title;
    pids[key] = track.albumPid;
  }
  return <ArtistAlbum>[
    for (final entry in byKey.entries)
      ArtistAlbum(
        title: titles[entry.key]!,
        pid: pids[entry.key],
        tracks: entry.value,
      ),
  ];
}
