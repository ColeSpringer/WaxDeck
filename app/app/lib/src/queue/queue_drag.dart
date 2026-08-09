import 'dart:async';

import 'package:flutter/gestures.dart' show HitTestResult;
import 'package:flutter/rendering.dart' show RenderMetaData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../player/now_playing_controller.dart';
import '../shell/shell_messages.dart';
import 'queue_controller.dart';

/// Dragging a row onto the queue panel.
///
/// Pointer only, by decision (ADR-0029). `LongPressDraggable` collides
/// with the long press that starts a queue selection, and touch already
/// has a path to the same outcome - pick the rows, or "Add to queue"
/// from a row's own menu - so a touch drag would be a second gesture
/// for a job that has one. The gate is hover: a row is draggable only
/// while a mouse is over it, and touch never hovers.
///
/// The panel is the only target. The `/queue` screen is the surface a
/// row would have to be dragged *from* on a narrow window, so there is
/// nothing to drop onto there.

/// What a drag carries: a name for the feedback under the cursor, and a
/// way to get the rows it stands for.
///
/// The rows are fetched rather than carried, because an index bucket is
/// a name and a count with no items in hand: an album row on the artist
/// index knows how many tracks it has and not which. A track row
/// answers instantly from what it already holds.
@immutable
class QueueDrop {
  const QueueDrop({required this.label, required this.resolve});

  /// One item, already in hand.
  factory QueueDrop.item(ItemSummary item) =>
      QueueDrop(label: item.title, resolve: () async => <ItemSummary>[item]);

  /// A bucket of an index, resolved when it lands. Bounded by the
  /// queue's own cap: dropping "Rock" is not a request to enqueue nine
  /// thousand tracks, and the queue would window it anyway.
  factory QueueDrop.bucket({
    required String label,
    required WaxDeckRepository repository,
    required String facet,
    required String facetKey,
  }) => QueueDrop(
    label: label,
    resolve: () async {
      final page = await repository.listItems(
        facet: facet,
        facetKey: facetKey,
        limit: kQueueDropCap,
      );
      return page.items;
    },
  );

  /// What the drag is of, for the feedback and for what is said after.
  final String label;

  /// The rows to append. Called once, when the drop lands.
  final Future<List<ItemSummary>> Function() resolve;
}

/// The most rows one drop adds. The queue caps itself at 500 and would
/// window anything longer; asking for more than it can hold would be a
/// page fetched to be thrown away.
const int kQueueDropCap = 500;

/// A row that can be picked up with a mouse and dropped on the queue.
///
/// The hover gate is what makes this pointer-only, and it is a gate
/// rather than a swap: the child stays in one place in the tree and
/// only `maxSimultaneousDrags` moves, so a drag already in flight is
/// not cancelled by the cursor leaving the row it started on - which is
/// the first thing that happens when a drag starts.
class QueueDraggable extends StatefulWidget {
  const QueueDraggable({required this.drop, required this.child, super.key});

  final QueueDrop drop;
  final Widget child;

  @override
  State<QueueDraggable> createState() => _QueueDraggableState();
}

class _QueueDraggableState extends State<QueueDraggable> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Draggable<QueueDrop>(
        data: widget.drop,
        maxSimultaneousDrags: _hovering ? 1 : 0,
        // Anchored to the pointer rather than to where the row was
        // grabbed, which is what makes the offset a drop target reads
        // the *cursor's* position: `DragTargetDetails.offset` is the
        // feedback's top-left, so with the default anchor the panel
        // would hit-test a point half a row up and to the left of the
        // one somebody aimed with.
        dragAnchorStrategy: pointerDragAnchorStrategy,
        // The row stays where it is while a copy travels: this adds to
        // the queue rather than moving anything out of a listing.
        feedback: _DragChip(label: widget.drop.label),
        child: widget.child,
      ),
    );
  }
}

/// What travels under the cursor: the row's name on a card, small
/// enough to see what is under it.
class _DragChip extends StatelessWidget {
  const _DragChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Material(
      color: Colors.transparent,
      child: Opacity(
        opacity: 0.9,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.symmetric(
            horizontal: WaxSpace.s12,
            vertical: WaxSpace.s8,
          ),
          decoration: BoxDecoration(
            color: colors.surface2,
            borderRadius: WaxRadius.thumb,
            border: Border.all(color: colors.accent),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              WaxIcon(WaxIcons.queue, size: 16, color: colors.accent),
              const SizedBox(width: WaxSpace.s8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WaxType.label.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Which slot of the queue one drawn row occupies, for a drop to
/// hit-test against.
///
/// A marker rather than a `DragTarget` per row: the rows are built by
/// `queueSlivers`, which the panel and the `/queue` screen share, and
/// only the panel is a drop target. So the rows say where they are and
/// the panel decides what that means.
@immutable
class QueueRowTarget {
  const QueueRowTarget(this.queueId, {this.splits = true});

  /// The entry's own id rather than its index. What a drop lands
  /// against is resolved when it lands, not when it was aimed: a
  /// bucket's rows arrive over the network, and a row removed while
  /// that is in flight shifts every index past it.
  final String queueId;

  /// Whether the half of the row the pointer is in decides above or
  /// below. The current entry does not split: nothing can be queued
  /// before what is already playing, so anywhere on that row means
  /// next.
  final bool splits;
}

/// Where a drop would land: the row it is anchored to, which side of
/// that row, and the y of the line drawn to say so, in the target's own
/// coordinates.
typedef QueueDropSlot = ({String anchorId, bool after, double y});

/// The queue panel as a place to drop a row.
///
/// A drop lands where it was released, not at the end. The rows are
/// laid out lazily inside a sliver, so the slot is resolved by hit
/// testing what is actually under the pointer rather than by arithmetic
/// on a scroll offset - and the half of the row the pointer is in
/// decides whether it goes above or below, which is the only reading
/// that lets a listener aim at a boundary.
class QueueDropTarget extends ConsumerStatefulWidget {
  const QueueDropTarget({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<QueueDropTarget> createState() => _QueueDropTargetState();
}

class _QueueDropTargetState extends ConsumerState<QueueDropTarget> {
  QueueDropSlot? _slot;

  /// The slot under [globalPosition], or null where the pointer is over
  /// the panel but not over an up-next row - the header, the history,
  /// the empty space under a short queue. Those all mean the end.
  QueueDropSlot? _slotAt(Offset globalPosition) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      globalPosition,
      View.of(context).viewId,
    );
    for (final entry in result.path) {
      final target = entry.target;
      if (target is! RenderMetaData) continue;
      final row = target.metaData;
      if (row is! QueueRowTarget) continue;
      final top = target.localToGlobal(Offset.zero).dy;
      final after =
          !row.splits || globalPosition.dy > top + target.size.height / 2;
      return (
        anchorId: row.queueId,
        after: after,
        y: box
            .globalToLocal(Offset(0, after ? top + target.size.height : top))
            .dy,
      );
    }
    return null;
  }

  /// The slot's index in the queue as it stands now, or null where the
  /// row it was anchored to has since gone - which means the end, the
  /// same answer a drop that landed on no row gets.
  static int? _indexOf(ProviderContainer container, QueueDropSlot slot) {
    final entries = container.read(queueControllerProvider).entries;
    final at = entries.indexWhere((e) => e.queueId == slot.anchorId);
    if (at < 0) return null;
    return slot.after ? at + 1 : at;
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return DragTarget<QueueDrop>(
      onMove: (details) {
        final slot = _slotAt(details.offset);
        if (slot?.anchorId != _slot?.anchorId || slot?.after != _slot?.after) {
          setState(() => _slot = slot);
        }
      },
      onLeave: (_) => setState(() => _slot = null),
      onAcceptWithDetails: (details) {
        final slot = _slot;
        setState(() => _slot = null);
        unawaited(_add(details.data, slot));
      },
      builder: (context, candidates, _) {
        final active = candidates.isNotEmpty;
        final slot = _slot;
        // One shape whether or not a drag is over the panel, and
        // constraints passed straight through, so the tree below is
        // identical either way. Returning the child bare when idle and
        // wrapped when hovering swaps the widget type at this position,
        // which inflates the whole panel fresh on every drag enter and
        // leave - a new scroll view, a new list, new state for every
        // row - at the exact moment the hit test that decides the slot
        // is walking that tree.
        return DecoratedBox(
          decoration: active
              ? BoxDecoration(
                  color: colors.accentContainer.withValues(alpha: 0.35),
                  border: Border.all(color: colors.accent),
                  borderRadius: WaxRadius.card,
                )
              : const BoxDecoration(),
          child: Stack(
            fit: StackFit.passthrough,
            children: <Widget>[
              widget.child,
              // The insertion point, because an insert nobody can see
              // coming is a drop that lands somewhere surprising.
              if (active && slot != null)
                Positioned(
                  left: 0,
                  right: 0,
                  top: slot.y - 1,
                  height: 2,
                  child: IgnorePointer(child: ColoredBox(color: colors.accent)),
                ),
            ],
          ),
        );
      },
    );
  }

  /// A null [slot] means the end: the pointer was over the panel but
  /// not over a row of the running order.
  Future<void> _add(QueueDrop drop, QueueDropSlot? slot) async {
    // The container rather than `ref`, taken before the fetch. A bucket
    // resolves over the network, and the panel can close while that is
    // in flight - the listener toggles it shut, the window narrows past
    // the breakpoint - which leaves `ref` pointing at a defunct element
    // and throws on the next read. The drop still lands: it was
    // accepted, and the queue belongs to the app rather than to this
    // panel.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = container.read(shellMessengerProvider.notifier);
    final playing = container.read(nowPlayingProvider.notifier);
    try {
      final items = await drop.resolve();
      if (items.isEmpty) {
        messenger.show('${drop.label} has nothing to play');
        return;
      }
      final at = slot == null ? null : _indexOf(container, slot);
      if (at == null) {
        playing.enqueue(items);
      } else {
        playing.enqueueAt(items, at);
      }
      messenger.show(
        items.length == 1
            ? 'Added ${items.first.title} to the queue'
            : 'Added ${items.length} tracks to the queue',
      );
    } on WaxDeckApiException catch (error) {
      // A bucket resolves over the network, so this is the one drop
      // that can fail on its way into the queue.
      messenger.show(error.message);
    }
  }
}
