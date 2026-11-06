import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/art_source_label.dart';
import '../artwork/artwork_providers.dart';
import '../books/book_dimension.dart';
import '../home/pin_action.dart';
import '../l10n/l10n.dart';
import '../library/item_menu.dart';
import '../library/item_play.dart';
import '../player/entity_star_rating_row.dart';
import '../player/now_playing_controller.dart';
import '../player/play_progress.dart';
import '../providers.dart';
import '../queue/queue_drag.dart';
import '../queue/queue_state.dart';
import '../search/search_chrome.dart';
import '../settings/settings_registry.dart';
import '../shell/async_sliver_face.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'album_play.dart';
import 'music_controllers.dart';

/// What the queue an artist screen builds is a window over. One builder
/// for the three entry points, and [name] is the artist's own name or
/// empty - a stored label, never the screen's localized fallback.
QueueSource artistSource(String pid, String name, MusicItemsState? state) =>
    QueueSource(
      kind: QueueSourceKind.artist,
      label: name,
      pid: pid,
      // An artist with more tracks than one page is a window, and the
      // listing's own cursor is where the queue draws the rest as it drains.
      rolling: state?.hasMore ?? false,
      cursor: state?.nextCursor ?? '',
      // Unscoped, as the page's own read is, which is what the cursor
      // names.
      mediaType: null,
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

  MusicListing get _listing => (
    dimension: MusicDimension.artists,
    segment: pid,
    domain: BrowseDomain.wholeLibrary,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(musicItemsProvider(_listing));
    final l10n = context.l10n;
    // Everything under the artist, books included: search, mixes and the
    // editor reach this page with the medium unknown, and an author whose
    // whole catalogue is audiobooks gets their books here rather than an
    // empty page under their own name.
    final items = state.value?.items ?? const <ItemSummary>[];
    // Never from an item. A track's artist field is its *credit* - "Dom
    // Kennedy feat. Ty Dolla $ign" - and the first row of a catalogue
    // is no more this artist's name than any other row is. The caller's
    // label where there is one; the entity's own card where a link
    // arrived without it.
    final artist = label ?? ref.watch(entityCardProvider(pid)).value?.title;
    final name = artist ?? l10n.musicArtistUnknownName;
    // The listing answers an empty page for any key, so an empty one says
    // nothing about whether the artist is there; their card does, and the
    // page waits for it rather than drawing an empty artist.
    final unproven = state.hasValue && !state.hasError && items.isEmpty
        ? unprovenEntityFace(
            context,
            ref.watch(entityCardProvider(pid)),
            errorTitle: l10n.musicArtistLoadError,
            onRetry: () => ref.invalidate(entityCardProvider(pid)),
          )
        : null;

    return WaxScaffold(
      title: name,
      largeTitle: false,
      onBack: () =>
          context.leave(fallback: WaxRoute.musicIndex(MusicDimension.artists)),
      actions: const <Widget>[SearchAction()],
      slivers: <Widget>[
        if (unproven != null)
          unproven
        else ...<Widget>[
          SliverToBoxAdapter(
            child: _Header(
              pid: pid,
              name: name,
              sourceName: artist ?? '',
              items: items,
              state: state.value,
            ),
          ),
          AsyncSliverFace<MusicItemsState>(
            state: state,
            skeletonFills: true,
            errorTitle: l10n.musicArtistLoadError,
            onRetry: () => ref.invalidate(musicItemsProvider(_listing)),
            isEmpty: (_) => items.isEmpty,
            empty: (context, _) => SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                title: l10n.musicArtistEmptyTitle,
                glyph: WaxIcons.artists,
              ),
            ),
            builder: (context, _) => SliverToBoxAdapter(
              child: _Body(
                pid: pid,
                name: name,
                sourceName: artist ?? '',
                items: items,
                state: state.value,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.pid,
    required this.name,
    required this.sourceName,
    required this.items,
    required this.state,
  });

  final String pid;
  final String name;

  /// The artist's own name, or empty. What the queue records.
  final String sourceName;

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
            source: artistSource(pid, sourceName, loaded),
          );
    }

    final l10n = context.l10n;
    final books = booksOf(items);
    // Each medium counted as itself, so "3 tracks" here is the music
    // index's "3 tracks"; a floor while the read runs past its page.
    final more = loaded?.hasMore ?? false;
    return EntityHeader(
      title: name,
      metadata: [
        if (tracks.isNotEmpty)
          more
              ? l10n.musicArtistTrackCountAtLeast(tracks.length)
              : l10n.musicTrackCount(tracks.length),
        if (books.isNotEmpty)
          more
              ? l10n.musicArtistBookCountAtLeast(books.length)
              : l10n.bookCount(books.length),
        if (albums.isNotEmpty) l10n.musicArtistReleaseCount(albums.length),
      ].join(' · '),
      shape: ArtworkShape.circle,
      // An artist has no detail read to ride, so the mark comes off the
      // art-roles read, which answers for every entity type and carries
      // the resolved cover's provenance beside the slots.
      artworkCaption: artSourceLabelWithBorrow(
        l10n,
        ref.watch(itemArtRolesProvider(pid)).value?.artSource,
      ),
      artwork: ref
          .watch(artworkStoreProvider)
          .source(ref.watch(repositoryProvider).artUrlFor(pid)),
      actions: <WaxAction>[
        WaxAction(
          label: l10n.musicPlay,
          glyph: WaxIcons.play,
          emphasis: WaxActionEmphasis.primary,
          onPressed: tracks.isEmpty ? null : play,
          semanticsId: SemanticsIds.entityPlay,
        ),
        WaxAction(
          label: l10n.musicShuffle,
          glyph: WaxIcons.shuffle,
          onPressed: tracks.isEmpty ? null : () => play(shuffle: true),
          semanticsId: SemanticsIds.entityShuffle,
        ),
      ],
      trailing: <Widget>[
        EntityStarRatingRow(pid: pid, label: l10n.libraryKindArtist),
      ],
      overflow: WaxMenuButton<String>(
        semanticsId: SemanticsIds.entityOverflow,
        items: <WaxMenuItem<String>>[
          pinMenuItem<String>(
            context,
            ref,
            pid,
            value: 'pin',
            semanticsId: SemanticsIds.entityPin,
          ),
          // The entity editor's door, only for who its every save
          // answers: sort, identifier, and picture are shared by
          // everyone who can see the artist.
          if (ref.watch(isAdminProvider))
            WaxMenuItem<String>(
              value: 'edit',
              label: l10n.musicArtistEditMetadata,
              glyph: WaxIcons.edit,
              semanticsId: SemanticsIds.entityEditMetadata,
            ),
        ],
        onSelected: (value) => switch (value) {
          'edit' => context.push(WaxRoute.metadata(pid)),
          _ => unawaited(togglePin(context, ref, pid, label: name)),
        },
      ),
    );
  }
}

/// The "Appears on" shelf: releases this artist is credited on without
/// heading them.
///
/// Silent about its own absence in every direction. A library whose
/// tracks name one artist each has nothing here, which is the common
/// case and is not worth a heading over an empty row; and a lookup that
/// fails leaves the shelf out rather than putting an error under the
/// artist's own releases, because a credit shelf is an extra and the
/// screen is complete without it.
class _AppearsOn extends ConsumerWidget {
  const _AppearsOn({required this.pid});

  final String pid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(appearsOnProvider(pid)).value;
    if (albums == null || albums.isEmpty) return const SizedBox.shrink();

    final store = ref.watch(artworkStoreProvider);
    final repository = ref.watch(repositoryProvider);
    final l10n = context.l10n;
    final tiles = <MediaTileData>[
      for (final album in albums)
        MediaTileData(
          title: album.label,
          subtitle: l10n.musicTrackCount(album.count),
          artwork: store.source(repository.artUrlFor(album.entityPid!)),
          semanticsId: SemanticsIds.entityAlbum(album.entityPid!),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: WaxSpace.s16),
        ShelfRow(
          title: l10n.musicArtistAppearsOn,
          items: tiles,
          onTapItem: (tile) {
            // Positional, for the reason the Releases shelf above is:
            // two releases can share a title and tiles carry no value
            // equality, so matching on the text would open the first of
            // them twice.
            final at = tiles.indexOf(tile);
            if (at < 0) return;
            // Pushed, not gone to: an album is declared under the albums
            // index, so `go` would rebuild that ancestry and throw this
            // artist away.
            unawaited(
              context.push(
                WaxRoute.musicBucket(
                  MusicDimension.albums,
                  albums[at].entityPid!,
                ),
                extra: albums[at].label,
              ),
            );
          },
          onPlayItem: (tile) {
            final at = tiles.indexOf(tile);
            if (at < 0) return;
            unawaited(
              playAlbumPid(ref, albums[at].entityPid!, label: albums[at].label),
            );
          },
          onMoreItem: (tile) {
            final at = tiles.indexOf(tile);
            if (at < 0) return;
            unawaited(
              showAlbumMenuSheet(
                context,
                ref,
                pid: albums[at].entityPid!,
                title: albums[at].label,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.pid,
    required this.name,
    required this.sourceName,
    required this.items,
    required this.state,
  });

  final String pid;
  final String name;

  /// The artist's own name, or empty. What the queue records.
  final String sourceName;

  final List<ItemSummary> items;
  final MusicItemsState? state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final albums = albumsOf(items);
    final store = ref.watch(artworkStoreProvider);
    final repository = ref.watch(repositoryProvider);
    final l10n = context.l10n;
    final tracks = playableOf(items);
    final books = booksOf(items);
    final top = tracks.take(_topTracks).toList();
    // Past the page read, the rest may hold tracks too.
    final moreTracks = tracks.length > top.length || (state?.hasMore ?? false);
    final tiles = <MediaTileData>[
      for (final album in albums)
        MediaTileData(
          title: album.title,
          subtitle: l10n.musicTrackCount(album.tracks.length),
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
            title: l10n.musicArtistReleases,
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
              // the artist whose release it is.
              if (target != null) {
                context.push(
                  WaxRoute.musicBucket(MusicDimension.albums, target),
                  extra: albums[at].title,
                );
              }
            },
            // A loose folder has no entity to play or to hold a menu.
            itemHasActions: (tile) {
              final at = tiles.indexOf(tile);
              return at >= 0 && albums[at].pid != null;
            },
            onPlayItem: (tile) {
              final at = tiles.indexOf(tile);
              if (at < 0) return;
              if (albums[at].pid case final pid?) {
                unawaited(playAlbumPid(ref, pid, label: albums[at].title));
              }
            },
            onMoreItem: (tile) {
              final at = tiles.indexOf(tile);
              if (at < 0) return;
              if (albums[at].pid case final pid?) {
                unawaited(
                  showAlbumMenuSheet(
                    context,
                    ref,
                    pid: pid,
                    title: albums[at].title,
                  ),
                );
              }
            },
          ),
        ],
        _AppearsOn(pid: pid),
        if (top.isNotEmpty) ...<Widget>[
          const SizedBox(height: WaxSpace.s16),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: sizeClass.gutter.horizontal / 2,
            ),
            child: SectionHeader(
              title: l10n.musicArtistTracksSection,
              actionLabel: moreTracks ? l10n.musicArtistShowAll : null,
              // Pushed rather than gone to, like a release: `go` rebuilds
              // the artists-index ancestry, which throws away a search
              // that pushed this artist. The location stays declared, so
              // a stranger opening it still gets the list.
              onAction: moreTracks
                  // The artist's own name, never the localized fallback:
                  // the listing stores what it is given as the queue's
                  // source label.
                  ? () => context.push(
                      WaxRoute.artistTracks(pid),
                      extra: sourceName.isEmpty ? null : sourceName,
                    )
                  : null,
              semanticsId: SemanticsIds.entityAllTracks,
            ),
          ),
          for (var i = 0; i < top.length; i++)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: sizeClass.gutter.horizontal / 2,
              ),
              child: QueueDraggable(
                drop: QueueDrop.item(top[i]),
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
                  onTap: () => _play(ref, tracks, i),
                  onMore: () =>
                      unawaited(showItemMenuForSummary(context, ref, top[i])),
                ),
              ),
            ),
        ],
        if (books.isNotEmpty) ...<Widget>[
          const SizedBox(height: WaxSpace.s16),
          _Books(pid: pid, books: books),
        ],
        const SizedBox(height: WaxSpace.s32),
      ],
    );
  }

  void _play(WidgetRef ref, List<ItemSummary> tracks, int index) {
    ref
        .read(nowPlayingProvider.notifier)
        .play(
          tracks,
          startIndex: index,
          source: artistSource(pid, sourceName, state),
        );
  }
}

/// An artist's books, as the shelf an author's own page under Books is
/// the whole of. Its covers open each book, and play or resume it in
/// place as the Books hub's do; Show all goes there.
class _Books extends ConsumerWidget {
  const _Books({required this.pid, required this.books});

  final String pid;
  final List<ItemSummary> books;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(artworkStoreProvider);
    final l10n = context.l10n;
    final progress = watchPlayProgress(ref, books);
    final tiles = <MediaTileData>[
      for (final book in books)
        MediaTileData(
          title: book.title,
          artwork: store.source(book.artUrl),
          domain: WaxDomain.audiobooks,
          shape: ArtworkShape.portrait,
          semanticsId: SemanticsIds.book(book.pid),
        ),
    ];
    return ShelfRow(
      title: l10n.musicArtistAudiobooksSection,
      items: tiles,
      actionLabel: l10n.musicArtistShowAll,
      actionSemanticsId: SemanticsIds.entityAllBooks,
      // Pushed, as a release is: the author's page is declared under the
      // authors index, and `go` would throw this artist away.
      onAction: () => unawaited(
        context.push(WaxRoute.bookBucket(BookDimension.authors, pid)),
      ),
      onTapItem: (tile) {
        final at = tiles.indexOf(tile);
        if (at < 0) return;
        unawaited(context.push(WaxRoute.book(books[at].pid)));
      },
      onPlayItem: (tile) {
        final at = tiles.indexOf(tile);
        if (at < 0) return;
        playOrResumeItem(ref, books[at], progress[books[at].pid]);
      },
      playSemanticsIdAt: (at) => SemanticsIds.bookPlay(books[at].pid),
      playLabelAt: (at) =>
          resumeLabel(l10n, books[at], progress[books[at].pid]),
      onMoreItem: (tile) {
        final at = tiles.indexOf(tile);
        if (at < 0) return;
        final book = books[at];
        unawaited(showItemCardMenu(context, ref, book, progress[book.pid]));
      },
    );
  }
}

/// What in a bucket plays in sequence: its tracks.
///
/// A bucket counts whatever carried its artist, books included. The
/// page lists each medium as itself, and the queue takes the tracks: a
/// twelve-hour file dropped between two tracks, captioned with the
/// artist's name, is not what Play was asked for.
List<ItemSummary> playableOf(List<ItemSummary> items) => <ItemSummary>[
  for (final item in items)
    if (item.mediaType != MediaType.audiobook) item,
];

/// The books in a bucket, which the page shelves apart from the tracks.
List<ItemSummary> booksOf(List<ItemSummary> items) => <ItemSummary>[
  for (final item in items)
    if (item.mediaType == MediaType.audiobook) item,
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

/// How many credited releases the shelf will consider. A glance, not a
/// listing: past this the shelf truncates silently, which is the same
/// bargain every other shelf makes with its card cap.
const _appearsOnLimit = 100;

/// The dimension that buckets a track under every artist its credit
/// names. Not a [MusicDimension]: the hub offers no index over it, and
/// this shelf is its only reader.
const _creditArtistDimension = 'credit-artist';

/// The releases an artist is credited on but does not head, as album
/// buckets.
///
/// The artist screen above reads the `artist` dimension, which buckets a
/// track once under its primary artist, so a feature is invisible there.
/// `credit-artist` buckets it under every artist the credit names, which
/// is the same track counted a second way rather than a second listing:
/// the two overlap by construction, and the overlap is what the section
/// has to remove before it draws anything.
///
/// One read, and it answers albums directly. This used to page the
/// *items* endpoint - the only scoped read that existed - and collapse
/// track rows into albums client-side, bounded at four pages because the
/// dimension buckets an artist's own tracks too and a prolific artist's
/// first page could be entirely self-releases. The facet endpoint takes a
/// scope now, so the question is asked the way it was always meant to
/// be: album buckets, counted over this artist's credits, bounded by
/// construction.
///
/// Buckets come back count-ordered, so the shelf leads with the release
/// this artist plays most on rather than with whichever sorted first.
///
/// Two reads, because the exclusion has to be exact. The albums the
/// artist *heads* come from the same facet space rather than from the
/// rows the screen happens to have loaded: the listing above pages at
/// five hundred tracks and the credited side is now a complete
/// enumeration, so a prolific artist's own release whose tracks sort past
/// the loaded window would be missing from the exclusion set and drawn
/// here - the duplication this shelf exists to prevent, appearing exactly
/// where a big catalogue makes it hardest to notice.
///
/// Concurrent: they are the same shape against the same index and neither
/// needs the other's answer.
///
/// Auto-disposed and per-artist, like the bucket listing it sits beside.
final appearsOnProvider = FutureProvider.autoDispose
    .family<List<FacetBucket>, String>((ref, pid) async {
      final repository = ref.watch(repositoryProvider);
      final key = musicFacetKey(MusicDimension.artists, pid);
      final pages = await Future.wait(<Future<FacetPage>>[
        repository.listFacets(
          MusicDimension.albums.wireName,
          facet: _creditArtistDimension,
          facetKey: key,
          limit: _appearsOnLimit,
        ),
        repository.listFacets(
          MusicDimension.albums.wireName,
          facet: MusicDimension.artists.wireName,
          facetKey: key,
          limit: _appearsOnLimit,
        ),
      ]);
      return appearsOnBuckets(pages[0].buckets, <String>{
        for (final bucket in pages[1].buckets) ?bucket.entityPid,
      });
    });

/// The album buckets worth drawing: the ones that name a real release
/// this artist does not already head.
///
/// Two drops. The unknown bucket ([Non-Album]) is a real bucket the
/// enumeration returns and carries no entity behind it, so there is
/// nothing for a card to open. And a release the artist heads is already
/// drawn above under Releases, so leaving it here would make the screen
/// repeat itself - a self-titled record appearing twice reads as a
/// duplicate in the library rather than as two ways of counting.
///
/// By entity pid rather than by title: two releases can share a title,
/// and dropping both because one matched is the same mistake the
/// Releases shelf avoids by opening tiles positionally. Every real album
/// bucket carries one, so there is no title fallback to keep.
List<FacetBucket> appearsOnBuckets(
  List<FacetBucket> buckets,
  Set<String> ownPids,
) => <FacetBucket>[
  for (final bucket in buckets)
    if (bucket.entityPid case final pid?)
      if (!ownPids.contains(pid)) bucket,
];
