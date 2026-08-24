import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../l10n/l10n.dart';
import '../library/item_menu.dart';
import '../player/now_playing_controller.dart';
import '../providers.dart';
import '../queue/queue_drag.dart';
import '../queue/queue_state.dart';
import '../search/search_chrome.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'music_controllers.dart';

/// A list of tracks: everything in the library, or everything in one
/// bucket of one dimension.
///
/// One screen for both, because a bucket is the same list with a filter
/// on it - the toolbar, the row, the queue it plays, and the empty state
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
  /// arriving cold has no `extra` - a reload or a shared link drops it -
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
  /// themselves are the only thing on hand that carries the label - the
  /// first row of an artist's listing knows the artist's name.
  String _title(List<ItemSummary> items) {
    final given = widget.label;
    if (given != null && given.isNotEmpty) return given;
    final l10n = context.l10n;
    final dimension = widget.dimension;
    if (dimension == null) return l10n.musicTracksTitle;
    if (widget.segment == musicUnknownSegment) {
      return l10n.musicBucketUnknownTitle(dimension.name);
    }
    if (dimension == MusicDimension.years) return widget.segment;
    final first = items.firstOrNull;
    final derived = switch (dimension) {
      MusicDimension.artists => first?.artist,
      // A release group is named for the record, and every edition of it
      // carries that name, so the first row has it.
      MusicDimension.albums || MusicDimension.releaseGroups => first?.album,
      _ => null,
    };
    return derived ?? l10n.musicDimensionSingularTitle(dimension.name);
  }

  /// The bucket's own name, and nothing else: a source label is stored
  /// with the queue, so the title's localized fallbacks must not reach
  /// it. Empty where the bucket has no name to give.
  String _sourceName(List<ItemSummary> items) {
    final given = widget.label;
    if (given != null && given.isNotEmpty) return given;
    final dimension = widget.dimension;
    if (dimension == MusicDimension.years) return widget.segment;
    final first = items.firstOrNull;
    return switch (dimension) {
          MusicDimension.artists => first?.artist,
          MusicDimension.albums || MusicDimension.releaseGroups => first?.album,
          _ => null,
        } ??
        '';
  }

  /// What the queue this screen builds is a window over.
  ///
  /// Either listing pages at the queue's own cap, so one that fits is
  /// queued whole and one that does not is queued as far as it goes,
  /// with the listing's cursor riding along so the queue can draw the
  /// rest as it drains. A bucket names itself; the tracks index is the
  /// whole library and has no name of its own to give.
  ///
  /// [cursor] is where the listing stands at the end of what is queued,
  /// and null means it ran out. [seed] keeps a refill walking the
  /// permutation the page came from; null for a plain play.
  QueueSource _source(
    List<ItemSummary> items, {
    required String? cursor,
    int? seed,
  }) {
    final dimension = widget.dimension;
    if (dimension == null) {
      return QueueSource(
        kind: QueueSourceKind.library,
        // The kind is the whole name; the queue screen words it.
        label: '',
        rolling: cursor != null,
        cursor: cursor ?? '',
        seed: seed,
      );
    }
    return QueueSource(
      kind: switch (dimension) {
        MusicDimension.artists => QueueSourceKind.artist,
        MusicDimension.albums => QueueSourceKind.album,
        MusicDimension.releaseGroups => QueueSourceKind.releaseGroup,
        MusicDimension.genres => QueueSourceKind.genre,
        MusicDimension.years => QueueSourceKind.year,
      },
      label: _sourceName(items),
      pid: widget.segment,
      rolling: cursor != null,
      cursor: cursor ?? '',
      seed: seed,
    );
  }

  void _play(MusicItemsState state, int index) {
    final items = state.items;
    // A bucket holds whatever carried the artist or the year it counts,
    // and a book is one of those. Books resume on their own screen -
    // chapters, speed, position - so a row that is one opens it rather
    // than dropping a twelve-hour file into the queue.
    if (items[index].mediaType == MediaType.audiobook) {
      context.push(WaxRoute.book(items[index].pid));
      return;
    }
    // A listing is a list somebody asked for, so playing a row plays the
    // list from there. What is loaded is a window over the rest and the
    // cursor rides with it, which is how the tracks index plays on
    // without queueing forty thousand tracks.
    //
    // Books are left out of the sequence: a bucket counts whatever
    // carries its artist or its year, and a twelve-hour file arriving
    // between two tracks is not what the tap asked for. The tracks index
    // has none to leave out.
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
          source: _source(items, cursor: state.nextCursor),
        );
    context.push(WaxRoute.nowPlaying);
  }

  /// Shuffles what this screen lists.
  ///
  /// Draws its own page rather than shuffling what the screen happens to
  /// have scrolled into memory. Two reasons, and the second is the one
  /// that bites: a sample of a loaded list longer than the cap silently
  /// drops whatever it did not sample, because the queue cannot hold it
  /// and the cursor beside it points past all of it - so a visitor who
  /// scrolled a 5,000-track genre before pressing this would lose
  /// everything they scrolled past. A page is exactly one window's
  /// worth, and the cursor that comes with it is the frontier of that
  /// window, which is what the refill continues from.
  ///
  /// A bucket pages its own listing; the tracks index is every track in
  /// the library, which has a random order of its own to ask for, so it
  /// seeds from a random page and walks that permutation as it goes.
  Future<void> _shuffle() async {
    final dimension = widget.dimension;
    final l10n = context.l10n;
    final repository = ref.read(repositoryProvider);
    final ItemPage page;
    try {
      // A bucket shuffles through the random list scoped to itself, so
      // the window is one permutation over the whole bucket rather than
      // a shuffle of each arriving page among itself.
      page = dimension == null
          ? await repository.browse(
              DiscoveryList.random,
              mediaType: MediaType.music,
              limit: kQueueCap,
            )
          : await repository.browse(
              DiscoveryList.random,
              facet: dimension.wireName,
              facetKey: musicFacetKey(dimension, widget.segment),
              limit: kQueueCap,
            );
    } on WaxDeckApiException catch (error) {
      // A shuffle that fetched nothing has to say so: the button is
      // fire-and-forget, so an unreported failure is a control that does
      // nothing at all.
      if (mounted) _report(explainError(l10n, error));
      return;
    }
    if (!mounted) return;
    final playable = <ItemSummary>[
      for (final item in page.items)
        if (dimension == null
            ? item.mediaType == MediaType.music
            : item.mediaType != MediaType.audiobook)
          item,
    ];
    if (playable.isEmpty) {
      _report(l10n.musicShuffleNothingPlayable);
      return;
    }
    ref
        .read(nowPlayingProvider.notifier)
        .play(
          playable,
          shuffle: true,
          source: _source(playable, cursor: page.nextCursor, seed: page.seed),
        );
    context.push(WaxRoute.nowPlaying);
  }

  void _report(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
        // Pops what is beneath, which is the screen this was opened
        // from: an artist's own screen for their full track list, the
        // dimension's index for a bucket. The fallback covers a
        // location opened cold with nothing under it.
        onBack: () => context.leave(
          fallback: dimension == null
              ? WaxRoute.music
              : WaxRoute.musicIndex(dimension),
        ),
        actions: <Widget>[
          if (items.isNotEmpty)
            WaxIconButton(
              glyph: WaxIcons.shuffle,
              label: dimension == null
                  ? context.l10n.musicShuffleAllLabel
                  : context.l10n.musicShuffleLabel(_title(items)),
              onPressed: () => unawaited(_shuffle()),
              semanticsId: SemanticsIds.listingShuffle,
            ),
          const SearchAction(),
        ],
        slivers: <Widget>[
          switch (state) {
            AsyncData(:final value) => _list(value),
            AsyncError(:final error) => SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorState(
                title: context.l10n.musicListingLoadError,
                message: context.explain(error),
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
    final l10n = context.l10n;
    if (state.items.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          title: dimension == null
              ? l10n.musicEmptyTitle
              : l10n.musicListingBucketEmptyTitle(dimension.name),
          message: dimension == null
              ? l10n.musicEmptyMessage
              : l10n.musicListingBucketEmptyMessage,
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
        return QueueDraggable(
          drop: QueueDrop.item(item),
          child: MediaListRow(
            data: MediaTileData(
              title: item.title,
              subtitle: item.artist,
              artwork: ref.watch(artworkStoreProvider).source(item.artUrl),
              trailingText: formatTimecode(
                Duration(milliseconds: item.durationMs),
              ),
              // Addressed by pid rather than by position, unlike the
              // album and artist screens: this is the complete
              // enumeration a caller reaches for one known item in,
              // which is what the deleted library grid was for. Those
              // two are running orders, where the position is the point.
              semanticsId: SemanticsIds.item(item.pid),
            ),
            onTap: () => _play(state, index),
            // The item menu, keeping the pin rows this overflow used
            // to be: a track cannot be pinned itself - a kept set of
            // tracks is a playlist - so pinning here still means the
            // album or the artist it belongs to.
            onMore: () =>
                showItemMenuForSummary(context, ref, item, withPin: true),
            moreSemanticsId: SemanticsIds.listingRowMore(item.pid),
          ),
        );
      },
    );
  }
}
