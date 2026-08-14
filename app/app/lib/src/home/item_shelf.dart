import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../media_view.dart';
import '../player/now_playing_controller.dart';
import '../player/play_progress.dart';
import '../queue/queue_state.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'home_shelves.dart';

/// How long a shelf loads before its skeleton appears.
///
/// The delay is the difference between honesty and jank: a warm cache
/// answers in a frame or two, and a skeleton that flashes for 80 ms
/// reads as the layout stuttering rather than as loading. One knob, so
/// home and the music hub ghost at the same moment.
const Duration kShelfSkeletonDelay = Duration(milliseconds: 200);

/// One shelf over a discovery list.
///
/// A shelf that is *empty* hides: nothing enumerates "never
/// played" but the shelf itself, and an empty row with a heading is a
/// reproach. Loading and failed used to hide the same way, and a
/// library without stars or plays degraded the hub to bare navigation
/// with nothing saying why - so they stopped masquerading as empty:
/// loading shows the shelf's ghost once [kShelfSkeletonDelay] passes,
/// and a failed read keeps the shelf's name on screen with a quiet
/// retry, which is the honest answer for one list failing while the
/// rest of the screen works. A server that is down entirely never gets
/// this far - the screen-level probe fails first and says so once.
class ItemShelf extends ConsumerWidget {
  const ItemShelf({
    super.key,
    required this.shelf,
    required this.title,
    required this.overline,
    required this.provider,
    this.withProgress = false,
    this.allLocation,
  });

  /// The handle stem, and what a spec calls this shelf. Not the title: a
  /// caption is copy and a handle is a contract.
  final String shelf;

  final String title;
  final String overline;
  final FutureProvider<HomeShelfItems> provider;

  /// Whether cards draw a progress ring and a remaining-time readout.
  final bool withProgress;

  /// Where "Show all" goes, on the shelves that have a surface behind
  /// them. The collection shelves do not: nothing enumerates "never
  /// played" but the shelf itself, and a door onto a screen that does not
  /// exist is worse than no door.
  final String? allLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);
    if (!async.hasValue) {
      if (async.hasError) {
        return SliverToBoxAdapter(
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            identifier: SemanticsIds.shelf(shelf),
            child: Padding(
              padding:
                  WaxSizeClass.of(context).gutter +
                  const EdgeInsets.only(bottom: WaxSpace.s24),
              child: SectionHeader(
                title: title,
                overline: overline,
                actionLabel: 'Try again',
                onAction: () => ref.invalidate(provider),
              ),
            ),
          ),
        );
      }
      return SliverToBoxAdapter(
        child: DelayedShelfSkeleton(title: title, overline: overline),
      );
    }
    final state = async.value;
    final items = state?.items ?? const <ItemSummary>[];
    if (items.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final progress = state?.progress ?? PlayProgressView.empty;
    final store = ref.watch(artworkStoreProvider);
    final l10n = context.waxL10n;
    final tiles = <MediaTileData>[
      for (final item in items)
        MediaTileData(
          title: item.title,
          subtitle: item.artist,
          artwork: waxArtwork(store, item.artUrl),
          domain: waxDomainOf(item.mediaType),
          shape: waxShapeOf(item.mediaType),
          progress: withProgress
              ? progress[item.pid].fractionOf(item.durationMs)
              : null,
          trailingText: withProgress
              ? _left(l10n, progress, item, short: true)
              : null,
          trailingSpoken: withProgress
              ? _left(l10n, progress, item, short: false)
              : null,
          // Scoped by shelf, because the shelves overlap by construction:
          // a fresh unplayed track is on Recently added and on Never
          // played at once, and one handle on two cards makes a click a
          // strict-mode violation rather than a tap.
          semanticsId: SemanticsIds.shelfCard(shelf, item.pid),
        ),
    ];
    return SliverToBoxAdapter(
      child: Semantics(
        // A region, not a node that swallows what is under it: a plain
        // `Semantics` merges with its descendants, which turned a whole
        // shelf - header, "Show all", and every card - into one node
        // announcing itself as a button. `container` gives the handle a
        // node of its own and `explicitChildNodes` leaves the controls
        // theirs.
        container: true,
        explicitChildNodes: true,
        identifier: SemanticsIds.shelf(shelf),
        child: Padding(
          padding: const EdgeInsets.only(bottom: WaxSpace.s24),
          child: ShelfRow(
            title: title,
            overline: overline,
            items: tiles,
            actionLabel: allLocation == null ? null : 'Show all',
            actionSemanticsId: SemanticsIds.shelfAll(shelf),
            onAction: allLocation == null
                ? null
                : () => context.go(allLocation!),
            // By position rather than by title: a tile carries no value
            // equality, and two editions of one album share a name.
            onTapItem: (tile) {
              final at = tiles.indexOf(tile);
              if (at < 0) return;
              openHomeItem(context, ref, items[at], progress[items[at].pid]);
            },
          ),
        ),
      ),
    );
  }

  /// "12 min left", and the spelled form a screen reader hears.
  static String? _left(
    WaxLocalizations l10n,
    PlayProgressView progress,
    ItemSummary item, {
    required bool short,
  }) {
    final remaining = progress[item.pid].remainingOf(item.durationMs);
    if (remaining == null) return null;
    final span = short
        ? l10n.formatSpan(remaining)
        : l10n.spellDuration(remaining);
    return '$span left';
  }
}

/// A shelf's ghost - its heading and a row of blank cards - shown only
/// once [kShelfSkeletonDelay] has passed, so a warm cache never flashes
/// it. Until then it takes no height, exactly like the hidden shelf it
/// stands in for.
class DelayedShelfSkeleton extends StatefulWidget {
  const DelayedShelfSkeleton({
    super.key,
    required this.title,
    required this.overline,
  });

  final String title;
  final String overline;

  @override
  State<DelayedShelfSkeleton> createState() => _DelayedShelfSkeletonState();
}

class _DelayedShelfSkeletonState extends State<DelayedShelfSkeleton> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(kShelfSkeletonDelay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: WaxSpace.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: WaxSizeClass.of(context).gutter,
            child: SectionHeader(
              title: widget.title,
              overline: widget.overline,
            ),
          ),
          const SkeletonShapes(shape: SkeletonShape.shelf),
        ],
      ),
    );
  }
}

/// Opens or resumes whatever a home card is about.
///
/// One verb for every medium, because home is the one screen that mixes
/// them: a book and an episode go to their own screens, where the
/// chapters, the speed, the show notes, and a resume that means something
/// are; a track plays, because there is nothing else a track's card
/// could be offering.
///
/// Pushed, not gone to, wherever a detail screen is involved: a book and
/// an episode are declared under their own domains, so `go` would rebuild
/// that ancestry and discard the shelves underneath (8.3, the entry-point
/// half P11 found).
void openHomeItem(
  BuildContext context,
  WidgetRef ref,
  ItemSummary item,
  PlayProgress progress,
) {
  switch (item.mediaType) {
    case MediaType.audiobook:
      unawaited(context.push(WaxRoute.book(item.pid)));
    case MediaType.podcast:
      // The show-less episode location, because home has no show to name
      // - the same position a search hit is in, and the same route it
      // opens. The episode screen is where a listener decides whether to
      // play it, which is the honest answer for a card that says nothing
      // about whether its feed still holds audio.
      unawaited(context.push(WaxRoute.episode(item.pid)));
    case MediaType.music:
      // One item, and it says so. A shelf is a dozen unrelated covers
      // rather than a running order, so queueing the shelf would fill the
      // queue with a view.
      ref
          .read(nowPlayingProvider.notifier)
          .play(
            <ItemSummary>[item],
            source: QueueSource(
              kind: QueueSourceKind.single,
              label: item.title,
              pid: item.pid,
            ),
            positionMs: progress.positionMs,
          );
      unawaited(context.push(WaxRoute.nowPlaying));
  }
}
