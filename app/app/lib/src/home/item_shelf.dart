import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../l10n/l10n.dart';
import '../library/item_menu.dart';
import '../media_view.dart';
import '../player/now_playing_controller.dart';
import '../player/play_progress.dart';
import '../queue/queue_state.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../sync/streamed_play_states.dart';
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
    required this.provider,
    this.withProgress = false,
    this.orderedByProgress = false,
    this.allLocation,
  });

  /// The handle stem, and what a spec calls this shelf. Not the title: a
  /// caption is copy and a handle is a contract.
  final String shelf;

  final String title;
  final FutureProvider<HomeShelfItems> provider;

  /// Whether cards draw a progress ring and a remaining-time readout.
  final bool withProgress;

  /// Whether the list is ordered by progress, most recent first, so a
  /// position the stream reports reorders it as well as moving a ring.
  /// Only with [withProgress], whose reports it reads.
  final bool orderedByProgress;

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
                actionLabel: context.l10n.homeShelfRetry,
                onAction: () => ref.invalidate(provider),
              ),
            ),
          ),
        );
      }
      return SliverToBoxAdapter(child: DelayedShelfSkeleton(title: title));
    }
    final state = async.value;
    final read = state?.items ?? const <ItemSummary>[];
    if (read.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final progress = state?.progress ?? PlayProgressView.empty;
    // A position the stream reported after the shelf was read: a
    // checkpoint moves the ring without the shelf being read again. This
    // shelf's own items only, since the reports are replaced whole on
    // every report, for any item.
    final streamed = <String, PlayState>{
      if (withProgress)
        for (final item in read)
          item.pid: ?ref.watch(
            streamedPlayStatesProvider.select((all) => all[item.pid]),
          ),
    };
    PlayProgress positionOf(String pid) =>
        newerProgress(progress[pid], streamed[pid]);
    final items = orderedByProgress
        ? _reportedFirst(read, progress, streamed)
        : read;
    final store = ref.watch(artworkStoreProvider);
    final l10n = context.l10n;
    final wax = context.waxL10n;
    final tiles = <MediaTileData>[
      for (final item in items)
        MediaTileData(
          title: item.title,
          // The album joins the artist on the caption line: a shelf of
          // singles from one artist is otherwise a row of identical
          // captions saying nothing about which release each came from.
          // Deduplicated, because an episode's artist and album are
          // both the show's title, and empty stays null rather than
          // becoming an empty caption line with a comma in the spoken
          // label.
          subtitle: _caption(item),
          // The card clamps every line, so the full name lives on the
          // hover tooltip.
          tooltip: <String?>[item.title, _caption(item)].nonNulls.join('\n'),
          artwork: waxArtwork(store, item.artUrl),
          domain: waxDomainOf(item.mediaType),
          shape: waxShapeOf(item.mediaType),
          progress: withProgress
              ? positionOf(item.pid).fractionOf(item.durationMs)
              : null,
          trailingText: withProgress
              ? _left(l10n, wax, positionOf(item.pid), item, short: true)
              : null,
          trailingSpoken: withProgress
              ? _left(l10n, wax, positionOf(item.pid), item, short: false)
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
            items: tiles,
            actionLabel: allLocation == null ? null : l10n.homeShelfShowAll,
            actionSemanticsId: SemanticsIds.shelfAll(shelf),
            backSemanticsId: SemanticsIds.shelfBack(shelf),
            forwardSemanticsId: SemanticsIds.shelfForward(shelf),
            onAction: allLocation == null
                ? null
                : () => context.go(allLocation!),
            // By position rather than by title: a tile carries no value
            // equality, and two editions of one album share a name.
            onTapItem: (tile) {
              final at = tiles.indexOf(tile);
              if (at < 0) return;
              openHomeItem(context, ref, items[at], positionOf(items[at].pid));
            },
            // The cover is the thing that plays here, so it says so
            // under a pointer. Nothing appears for a finger: the
            // affordance is a hover, and a touch device reports none.
            onPlayItem: (tile) {
              final at = tiles.indexOf(tile);
              if (at < 0) return;
              playHomeItem(ref, items[at], positionOf(items[at].pid));
            },
            onMoreItem: (tile) {
              final at = tiles.indexOf(tile);
              if (at < 0) return;
              // Home is where the pinned shelf lives, so its cards pin
              // from here the way a listing row does.
              unawaited(
                showItemMenuForSummary(context, ref, items[at], withPin: true),
              );
            },
          ),
        ),
      ),
    );
  }

  /// [items] with the cards whose position the stream moved since [read]
  /// in front, newest report first, and the rest in the order read.
  ///
  /// For a list ordered by progress: a report newer than its card's read
  /// is progress made after the read, so newer than anything the read
  /// ordered by. A finished one keeps its place until the read that
  /// takes it off, and a report that moved no position (a star) leaves
  /// the order alone.
  static List<ItemSummary> _reportedFirst(
    List<ItemSummary> items,
    PlayProgressView read,
    Map<String, PlayState> streamed,
  ) {
    DateTime? movedAt(ItemSummary item) {
      final report = streamed[item.pid];
      final held = read[item.pid];
      if (report == null || report.finished) return null;
      if (report.positionMs == held.positionMs) return null;
      if (identical(newerProgress(held, report), held)) return null;
      return report.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    }

    final moved = <(ItemSummary, DateTime)>[
      for (final item in items)
        if (movedAt(item) case final at?) (item, at),
    ];
    if (moved.isEmpty) return items;
    moved.sort((a, b) => b.$2.compareTo(a.$2));
    final ahead = <String>{for (final (item, _) in moved) item.pid};
    return <ItemSummary>[
      for (final (item, _) in moved) item,
      for (final item in items)
        if (!ahead.contains(item.pid)) item,
    ];
  }

  /// The caption under a card: the artist, and the album where it says
  /// something the artist line does not. Null rather than empty when
  /// the item carries neither.
  static String? _caption(ItemSummary item) {
    final parts = <String>[
      ?item.artist,
      if (item.album case final album? when album != item.artist) album,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// "12 min left", and the spelled form a screen reader hears. Two
  /// tables: the design system spells the duration, as every read-out
  /// span does, and the frame around it is this screen's own.
  static String? _left(
    AppLocalizations l10n,
    WaxLocalizations wax,
    PlayProgress progress,
    ItemSummary item, {
    required bool short,
  }) {
    final remaining = progress.remainingOf(item.durationMs);
    if (remaining == null) return null;
    final span = short
        ? wax.formatSpan(remaining)
        : wax.spellDuration(remaining);
    return l10n.homeShelfRemaining(span);
  }
}

/// A shelf's ghost - its heading and a row of blank cards - shown only
/// once [kShelfSkeletonDelay] has passed, so a warm cache never flashes
/// it. Until then it takes no height, exactly like the hidden shelf it
/// stands in for.
class DelayedShelfSkeleton extends StatefulWidget {
  const DelayedShelfSkeleton({super.key, required this.title});

  final String title;

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
            child: SectionHeader(title: widget.title),
          ),
          const SkeletonShapes(shape: SkeletonShape.shelf),
        ],
      ),
    );
  }
}

/// Plays one shelf item where it stands, going nowhere.
///
/// The verb behind a card's hover play affordance, and behind
/// [openHomeItem]'s track arm. Playback lands in the dock whatever
/// raised it; the deck bar is the way into the full player.
///
/// One item, and it says so: a shelf is a dozen unrelated covers
/// rather than a running order, and queueing the shelf would fill the
/// queue with a view. A book
/// names itself as the source instead, because its parts roll inside the
/// session and there is nothing else in the queue for them to be.
void playHomeItem(WidgetRef ref, ItemSummary item, PlayProgress progress) {
  ref
      .read(nowPlayingProvider.notifier)
      .play(
        <ItemSummary>[item],
        source: QueueSource(
          kind: item.mediaType == MediaType.audiobook
              ? QueueSourceKind.book
              : QueueSourceKind.single,
          label: item.title,
          pid: item.pid,
        ),
        // The caller's own where it holds one (the Downloaded shelf's
        // comes off the mirror), none where it holds none so the session
        // reads its checkpoint, and the head of a finished item.
        positionMs: progress.finished
            ? 0
            : (progress.positionMs > 0 ? progress.positionMs : null),
      );
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
      playHomeItem(ref, item, progress);
  }
}
