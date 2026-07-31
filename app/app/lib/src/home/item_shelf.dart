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

/// One shelf over a discovery list.
///
/// Empty, still loading, and failed are all the same on screen, and each
/// for its own reason. A shelf that hides while it loads and appears
/// when it lands is the layout jumping under a thumb, and a skeleton per
/// shelf would draw eight ghosts on a library that has two - the
/// screen's own skeleton covers the first frame. A shelf whose read
/// *failed* hides because the screen already has one error surface, over
/// the probe that decides whether home has anything at all: a server
/// that is not answering fails that too and the screen says so once,
/// rather than eight times. What is left after that is one list failing
/// while the rest answer, which on an older server is a list it cannot
/// serve - and hiding it is the right answer to that, not a swallowed
/// error.
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
    final state = ref.watch(provider).value;
    final items = state?.items ?? const <ItemSummary>[];
    if (items.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final progress = state?.progress ?? PlayProgressView.empty;
    final store = ref.watch(artworkStoreProvider);
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
              ? _left(progress, item, short: true)
              : null,
          trailingSpoken: withProgress
              ? _left(progress, item, short: false)
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
    PlayProgressView progress,
    ItemSummary item, {
    required bool short,
  }) {
    final remaining = progress[item.pid].remainingOf(item.durationMs);
    if (remaining == null) return null;
    return '${short ? formatSpan(remaining) : spellDuration(remaining)} left';
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
