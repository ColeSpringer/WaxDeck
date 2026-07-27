import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../providers.dart';
import '../search/search_chrome.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'music_controllers.dart';

/// A complete, fast enumeration of one dimension.
///
/// Artists and albums lead with an alphabet, because that is how anyone
/// looks for one; genres and years lead with the biggest buckets, because
/// an alphabet of years is just the years again and a genre with two
/// tracks in it is not where a visitor starts. Either way the toggle is
/// there.
class MusicIndexScreen extends ConsumerStatefulWidget {
  const MusicIndexScreen({required this.dimension, super.key});

  final MusicDimension dimension;

  @override
  ConsumerState<MusicIndexScreen> createState() => _MusicIndexScreenState();
}

class _MusicIndexScreenState extends ConsumerState<MusicIndexScreen> {
  final ScrollController _scroll = ScrollController();

  /// The letter the rail is showing as current: whichever one was last
  /// jumped to. Reading it back off the scroll offset would need every
  /// row's height, and the rows are not fixed-extent.
  String? _letter;

  /// A jump in flight, so a drag across the rail cannot start a second
  /// paging loop on top of the first.
  bool _jumping = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  MusicIndexKey get _key => (
    dimension: widget.dimension,
    sort: ref.read(musicIndexSortProvider(widget.dimension)),
  );

  void _onScroll(ScrollMetrics metrics) {
    // The listener wraps the whole screen, and the toolbar's sort chips
    // are a horizontal scroller inside it. A drag on those sits at pixel
    // zero of a very short extent, which satisfies any "near the end"
    // test and would fetch a 500-bucket page nobody asked for.
    if (metrics.axis != Axis.vertical) return;
    if (metrics.pixels >= metrics.maxScrollExtent - 600) {
      ref.read(musicIndexProvider(_key).notifier).loadMore();
    }
  }

  /// Scrolls to the first bucket under [letter], paging forward until one
  /// turns up or the dimension runs out.
  ///
  /// The index is keyset-paginated and the server has no seek-to-letter,
  /// so this is what a rail can do: ask for more until the letter is on
  /// the list. Pages are 500 buckets, and the server answers them from
  /// one cached enumeration, so even a long walk is cheap.
  Future<void> _jumpTo(String letter) async {
    if (_jumping) return;
    // The letter is not marked current until the list actually moves to
    // it. Every early return below is a walk that reached nothing — no
    // buckets yet, a page already in flight, the dimension exhausted —
    // and a rail showing a letter it never arrived at is the rail lying
    // about where the list is.
    var arrived = false;
    setState(() => _jumping = true);
    try {
      final key = _key;
      final notifier = ref.read(musicIndexProvider(key).notifier);
      final target = fastScrollLetters.indexOf(letter);
      // Read before the first await: the pitch is a function of the
      // density theme and the text scale, and holding the number rather
      // than the context is what keeps this off a context that may not
      // outlive the paging. Asked of the row itself rather than guessed
      // from the row height, which is only the floor — at 1.5x text a
      // title and a caption clear it, and a guess that is short by four
      // pixels a row is short by a screenful after eighty of them.
      final rowExtent = MediaListRow.heightFor(context);
      while (mounted) {
        final buckets = ref.read(musicIndexProvider(key)).value?.buckets;
        if (buckets == null) return;
        final index = buckets.indexWhere(
          (b) =>
              !b.unknown &&
              fastScrollLetters.indexOf(fastScrollLetter(b.label)) >= target,
        );
        if (index >= 0) {
          if (_scroll.hasClients) {
            // Still an estimate rather than an exact offset: a label long
            // enough to wrap makes its own row taller than the pitch, and
            // the list is lazily built, so a row that has never been on
            // screen has no measured extent to ask for. It lands on the
            // letter or a little above it, which is the direction that
            // leaves the target in view.
            _scroll.jumpTo(
              (index * rowExtent).clamp(0.0, _scroll.position.maxScrollExtent),
            );
            arrived = true;
          }
          return;
        }
        if (!await notifier.loadMore()) return;
      }
    } finally {
      if (mounted) {
        setState(() {
          _jumping = false;
          if (arrived) _letter = letter;
        });
      }
    }
  }

  void _open(FacetBucket bucket) {
    // A bucket is a place: its listing is rebuildable from the URL alone,
    // so it goes rather than pushes and the address bar follows.
    context.go(
      WaxRoute.musicBucket(
        widget.dimension,
        musicBucketSegment(widget.dimension, bucket),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dimension = widget.dimension;
    final sort = ref.watch(musicIndexSortProvider(dimension));
    final key = (dimension: dimension, sort: sort);
    final state = ref.watch(musicIndexProvider(key));

    // The rail only means anything over an alphabet. In biggest-first
    // order the letters are scattered down the list, and a rail that
    // jumped to the first S-shaped bucket in count order would be lying
    // about what it does.
    final buckets = state.value?.buckets ?? const <FacetBucket>[];
    final railed = sort == FacetSort.label && buckets.isNotEmpty;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        _onScroll(notification.metrics);
        return false;
      },
      child: Stack(
        children: <Widget>[
          WaxScaffold(
            title: dimension.label,
            onBack: () => context.go(WaxRoute.music),
            largeTitle: false,
            controller: _scroll,
            actions: const <Widget>[SearchAction()],
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: _Toolbar(
                  dimension: dimension,
                  sort: sort,
                  count: state.value?.buckets.length,
                  hasMore: state.value?.hasMore ?? false,
                  onSort: (value) => ref
                      .read(musicIndexSortProvider(dimension).notifier)
                      .select(value),
                ),
              ),
              SliverPadding(
                // Room for the rail, which floats over the list's
                // trailing edge rather than taking a column of its own:
                // a column would narrow every row on a phone to buy a
                // strip that is only useful while a finger is on it.
                padding: EdgeInsets.only(right: railed ? WaxSpace.s24 : 0),
                sliver: switch (state) {
                  AsyncData(:final value) => _list(value),
                  AsyncError(:final error) => SliverFillRemaining(
                    hasScrollBody: false,
                    child: ErrorState(
                      title: 'Could not load ${dimension.label.toLowerCase()}',
                      message: error is WaxDeckApiException
                          ? error.message
                          : 'The server did not answer.',
                      onRetry: () => ref.invalidate(musicIndexProvider(key)),
                    ),
                  ),
                  _ => const SliverFillRemaining(
                    hasScrollBody: false,
                    child: SkeletonShapes(shape: SkeletonShape.list),
                  ),
                },
              ),
            ],
          ),
          if (railed)
            Positioned(
              // Clear of the app bar, so the rail's first letter is not
              // under the title. Asked of the scaffold rather than added
              // up here: the height is the bar's own plus the window's
              // top inset, and this arithmetic has already been wrong
              // once in exactly that second term.
              top:
                  WaxScaffold.barHeight(context, largeTitle: false) +
                  WaxSpace.s8,
              bottom: WaxSpace.s8,
              right: 0,
              child: FastScrollRail(
                letters: fastScrollLetters,
                selected: _letter,
                available: <String>{
                  for (final bucket in buckets)
                    if (!bucket.unknown) fastScrollLetter(bucket.label),
                },
                semanticsId: SemanticsIds.indexRail,
                letterSemanticsId: SemanticsIds.indexRailLetter,
                onLetter: _jumpTo,
              ),
            ),
        ],
      ),
    );
  }

  Widget _list(MusicIndexState state) {
    final dimension = widget.dimension;
    if (state.buckets.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          title: 'No ${dimension.label.toLowerCase()} yet',
          message:
              'Add music to your library and its '
              '${dimension.singular}s show up here.',
          glyph: dimension.glyph,
        ),
      );
    }
    return SliverList.builder(
      itemCount: state.buckets.length + (state.loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= state.buckets.length) {
          return const Padding(
            padding: EdgeInsets.all(WaxSpace.s16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return _BucketRow(
          dimension: dimension,
          bucket: state.buckets[index],
          index: index,
          onTap: () => _open(state.buckets[index]),
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.dimension,
    required this.sort,
    required this.count,
    required this.hasMore,
    required this.onSort,
  });

  final MusicDimension dimension;
  final FacetSort sort;
  final int? count;
  final bool hasMore;
  final ValueChanged<FacetSort> onSort;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final loaded = count;
    return Padding(
      padding: WaxSizeClass.of(
        context,
      ).gutter.copyWith(top: WaxSpace.s4, bottom: WaxSpace.s8),
      child: Row(
        children: <Widget>[
          if (loaded != null)
            Semantics(
              identifier: SemanticsIds.indexCount,
              child: Text(
                // "of the ones loaded" is what a keyset list can honestly
                // say: the page after this one may hold more.
                hasMore
                    ? '$loaded+ ${dimension.label.toLowerCase()}'
                    : '$loaded ${dimension.label.toLowerCase()}',
                style: WaxType.caption.copyWith(color: colors.textTertiary),
              ),
            ),
          const Spacer(),
          // Flexible, not free-standing: the chip row is a horizontal
          // scroller and takes its full intrinsic width given the chance,
          // which on a phone is wider than what the caption leaves it.
          // Loose, so it keeps its natural width wherever there is room.
          Flexible(
            child: FilterChipRow(
              chips: <WaxFilterChip>[
                WaxFilterChip(
                  name: FacetSort.label.wireName,
                  label: 'A to Z',
                  glyph: WaxIcons.sort,
                  semanticsId: SemanticsIds.indexSort,
                ),
                const WaxFilterChip(
                  name: 'count',
                  label: 'Most items',
                  glyph: WaxIcons.stats,
                ),
              ],
              selected: sort.wireName,
              onSelect: (name) => onSort(
                name == FacetSort.label.wireName
                    ? FacetSort.label
                    : FacetSort.count,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BucketRow extends ConsumerWidget {
  const _BucketRow({
    required this.dimension,
    required this.bucket,
    required this.index,
    required this.onTap,
  });

  final MusicDimension dimension;
  final FacetBucket bucket;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entityPid = bucket.entityPid;
    // The listing hands an item its own artUrl; a bucket carries only the
    // entity behind it, and the art endpoint serves entity pids too.
    final artwork = dimension.hasArtwork && entityPid != null
        ? ref
              .watch(artworkStoreProvider)
              .source(ref.watch(repositoryProvider).artUrlFor(entityPid))
        : null;

    return MediaListRow(
      data: MediaTileData(
        title: bucket.label,
        subtitle: bucket.count == 1 ? '1 track' : '${bucket.count} tracks',
        artwork: artwork,
        shape: dimension.shape,
        semanticsId: SemanticsIds.indexBucket(index),
      ),
      onTap: onTap,
    );
  }
}
