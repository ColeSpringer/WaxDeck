import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../player/now_playing_controller.dart';
import '../queue/queue_state.dart';
import '../search/search_chrome.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'music_controllers.dart';

/// A list of tracks: everything in the library, or everything in one
/// bucket of one dimension.
///
/// One screen for both, because a bucket is the same list with a filter
/// on it — the toolbar, the row, the queue it plays, and the empty state
/// are all the same, and only the title and the fetch differ.
class MusicListingScreen extends ConsumerStatefulWidget {
  const MusicListingScreen({
    this.dimension,
    this.segment = '',
    this.label,
    super.key,
  });

  /// Null for the whole tracks index.
  final MusicDimension? dimension;

  /// The bucket handle from the location. Empty for the tracks index.
  final String segment;

  /// The bucket's display label, when the caller had one. A visitor
  /// arriving cold has no `extra` — a reload or a shared link drops it —
  /// so the screen names itself from what it loads instead, and the
  /// listing itself never depends on this.
  final String? label;

  @override
  ConsumerState<MusicListingScreen> createState() => _MusicListingScreenState();
}

class _MusicListingScreenState extends ConsumerState<MusicListingScreen> {
  MusicListing get _listing =>
      (dimension: widget.dimension, segment: widget.segment);

  /// What to call this list when nothing handed it a name.
  ///
  /// A year bucket names itself: its key is the year. An artist or album
  /// bucket is a pid, and a genre bucket is a catalog id, so the items
  /// themselves are the only thing on hand that carries the label — the
  /// first row of an artist's listing knows the artist's name.
  String _title(List<ItemSummary> items) {
    final given = widget.label;
    if (given != null && given.isNotEmpty) return given;
    final dimension = widget.dimension;
    if (dimension == null) return 'Tracks';
    if (widget.segment == musicUnknownSegment) {
      return 'No ${dimension.singular}';
    }
    if (dimension == MusicDimension.years) return widget.segment;
    final first = items.firstOrNull;
    final derived = switch (dimension) {
      MusicDimension.artists => first?.artist,
      MusicDimension.albums => first?.album,
      _ => null,
    };
    return derived ??
        dimension.singular[0].toUpperCase() + dimension.singular.substring(1);
  }

  void _play(List<ItemSummary> items, int index) {
    final dimension = widget.dimension;
    // A bucket holds whatever carried the artist or the year it counts,
    // and a book is one of those. Books resume on their own screen —
    // chapters, speed, position — so a row that is one opens it rather
    // than dropping a twelve-hour file into the queue.
    if (items[index].mediaType == MediaType.audiobook) {
      context.push(WaxRoute.book(items[index].pid));
      return;
    }
    // A bucket is a list somebody asked for, so playing a row plays the
    // list from there. The tracks index is not: it is every track in the
    // library in title order, and queueing 40,000 of them because
    // somebody tapped one is not what they asked for.
    if (dimension == null) {
      final item = items[index];
      ref.read(nowPlayingProvider.notifier).play(
        <ItemSummary>[item],
        source: QueueSource(
          kind: QueueSourceKind.single,
          label: item.title,
          pid: item.pid,
        ),
      );
    } else {
      // A bucket counts whatever carries its artist or its year, books
      // included, so the queue is the part of it that plays in sequence.
      // Leaving them in would drop twelve-hour files between two tracks
      // under a caption naming the artist, as though somebody had asked
      // for that.
      final playable = <ItemSummary>[];
      var start = 0;
      for (final item in items) {
        if (item.mediaType == MediaType.audiobook) continue;
        if (identical(item, items[index])) start = playable.length;
        playable.add(item);
      }
      ref
          .read(nowPlayingProvider.notifier)
          .play(
            playable,
            startIndex: start,
            source: QueueSource(
              kind: switch (dimension) {
                MusicDimension.artists => QueueSourceKind.artist,
                MusicDimension.albums => QueueSourceKind.album,
                MusicDimension.genres => QueueSourceKind.genre,
                MusicDimension.years => QueueSourceKind.year,
              },
              label: _title(items),
              pid: widget.segment,
            ),
          );
    }
    context.push(WaxRoute.nowPlaying);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(musicItemsProvider(_listing));
    final dimension = widget.dimension;
    final items = state.value?.items ?? const <ItemSummary>[];

    return NotificationListener<ScrollNotification>(
      // Paging belongs to the scroll, not to the item builder: asking a
      // notifier for another page while it is building a row mutates
      // state mid-frame.
      onNotification: (notification) {
        final metrics = notification.metrics;
        // Vertical only, for the same reason the index guards: a
        // horizontal scroller inside the page sits at pixel zero of a
        // short extent, which reads as "near the end" of the page.
        if (metrics.axis != Axis.vertical) return false;
        if (metrics.pixels >= metrics.maxScrollExtent - 600) {
          ref.read(musicItemsProvider(_listing).notifier).loadMore();
        }
        return false;
      },
      child: WaxScaffold(
        title: _title(items),
        largeTitle: false,
        onBack: () => context.go(
          dimension == null ? WaxRoute.music : WaxRoute.musicIndex(dimension),
        ),
        actions: const <Widget>[SearchAction()],
        slivers: <Widget>[
          switch (state) {
            AsyncData(:final value) => _list(value),
            AsyncError(:final error) => SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorState(
                title: 'Could not load this list',
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
      ),
    );
  }

  Widget _list(MusicItemsState state) {
    final dimension = widget.dimension;
    if (state.items.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          title: dimension == null
              ? 'No music yet'
              : 'Nothing in this ${dimension.singular}',
          message: dimension == null
              ? 'Add music to your library and it shows up here.'
              : 'The items that were here have moved or been removed.',
          glyph: WaxIcons.music,
        ),
      );
    }
    return SliverList.builder(
      itemCount: state.items.length + (state.loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= state.items.length) {
          return const Padding(
            padding: EdgeInsets.all(WaxSpace.s16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final item = state.items[index];
        return MediaListRow(
          data: MediaTileData(
            title: item.title,
            subtitle: item.artist,
            artwork: ref.watch(artworkStoreProvider).source(item.artUrl),
            trailingText: formatTimecode(
              Duration(milliseconds: item.durationMs),
            ),
            semanticsId: SemanticsIds.indexItem(index),
          ),
          onTap: () => _play(state.items, index),
        );
      },
    );
  }
}
