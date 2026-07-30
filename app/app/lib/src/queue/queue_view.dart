import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../media_view.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'queue_controller.dart';
import 'queue_item.dart';
import 'queue_state.dart';
import 'session_history.dart';

/// Where a queue came from, as a sentence.
///
/// Null where naming the source would say nothing: one item tapped on
/// its own is its own provenance, and a queue that predates the field
/// has none to give.
String? queueProvenance(QueueSource source) {
  if (source.label.isEmpty) return null;
  return switch (source.kind) {
    QueueSourceKind.single || QueueSourceKind.unknown => null,
    _ => 'Playing from ${source.label}',
  };
}

/// The next repeat mode in the cycle the transport walks.
QueueRepeat nextQueueRepeat(QueueRepeat repeat) => switch (repeat) {
  QueueRepeat.off => QueueRepeat.all,
  QueueRepeat.all => QueueRepeat.one,
  QueueRepeat.one => QueueRepeat.off,
};

/// Whether the queue surface is showing what has already played.
///
/// A provider rather than widget state because the surface is a list of
/// slivers rather than a widget of its own: the scaffold and the panel
/// each concatenate them into their own scroll view, and a disclosure
/// that lived in one of those would be a different disclosure on each.
class QueueHistoryOpen extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

/// Collapsed by default: the queue is about what happens next, and the
/// history is there for the moment somebody wants that track again.
final queueHistoryOpenProvider = NotifierProvider<QueueHistoryOpen, bool>(
  QueueHistoryOpen.new,
);

/// The queue itself: what is playing, what follows it, and what came
/// before, as slivers.
///
/// One body for both surfaces. The desktop panel and the compact screen
/// are the same list at two widths - the same order, the same drag, the
/// same verbs - so a listener who learns one has learned the other, and
/// a fix to either is a fix to both. Slivers rather than a widget so
/// each surface owns its own scroll view: a scaffold builds one for its
/// large title, and a panel has no title to scroll under.
List<Widget> queueSlivers(BuildContext context, WidgetRef ref) {
  final colors = WaxColors.of(context);
  final queue = ref.watch(queueControllerProvider);
  final notifier = ref.read(queueControllerProvider.notifier);
  final showHistory = ref.watch(queueHistoryOpenProvider);

  if (queue.isEmpty) {
    return <Widget>[
      // One sliver, not two: a filled remainder followed by anything
      // puts that anything past the bottom of the viewport, where it is
      // never laid out and never found.
      const SliverFillRemaining(
        hasScrollBody: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: EmptyState(
                title: 'Nothing queued',
                message:
                    'Play an album, a show, or a playlist and it lands here.',
                glyph: WaxIcons.queue,
              ),
            ),
            SessionHistorySection(),
          ],
        ),
      ),
    ];
  }

  final upNext = queue.entries.sublist(queue.currentIndex + 1);
  final played = queue.entries.sublist(0, queue.currentIndex);
  final provenance = queueProvenance(queue.source);

  return <Widget>[
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          WaxSpace.s16,
          WaxSpace.s12,
          WaxSpace.s16,
          WaxSpace.s8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (provenance != null)
              Text(
                provenance,
                style: WaxType.caption.copyWith(color: colors.textSecondary),
              ),
            // A rolling queue is a window over something larger, and
            // a listener counting what is left should not read the
            // window as the whole of it. Deliberately silent about the
            // refill: the window is over more than it holds in every
            // case, and whether the scope can be drawn from again is
            // the pager's answer, which this line is drawn before.
            if (queue.source.rolling)
              Text(
                'A window over a larger scope',
                style: WaxType.caption.copyWith(color: colors.textTertiary),
              ),
            const SizedBox(height: WaxSpace.s8),
            Row(
              children: <Widget>[
                WaxIconButton(
                  glyph: WaxIcons.shuffle,
                  label: queue.shuffled ? 'Shuffle on' : 'Shuffle off',
                  size: 18,
                  active: queue.shuffled,
                  onPressed: () => notifier.setShuffle(!queue.shuffled),
                  semanticsId: SemanticsIds.queueShuffle,
                ),
                WaxIconButton(
                  glyph: queue.repeat == QueueRepeat.one
                      ? WaxIcons.repeatOne
                      : WaxIcons.repeatAll,
                  label: switch (queue.repeat) {
                    QueueRepeat.off => 'Repeat off',
                    QueueRepeat.all => 'Repeat all',
                    QueueRepeat.one => 'Repeat one',
                  },
                  size: 18,
                  active: queue.repeat != QueueRepeat.off,
                  onPressed: () =>
                      notifier.setRepeat(nextQueueRepeat(queue.repeat)),
                  semanticsId: SemanticsIds.queueRepeat,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    SliverToBoxAdapter(
      child: QueueRow(
        entry: queue.currentEntry!,
        playing: true,
        onTap: () => context.push(WaxRoute.nowPlaying),
      ),
    ),
    _label(context, upNext.isEmpty ? 'NOTHING UP NEXT' : 'UP NEXT'),
    // Wrapped so the drag proxy can be given a width: the proxy is built
    // into an overlay, where the cross-axis constraint is unbounded and a
    // row with an Expanded in it would stretch to infinity, and outside
    // any Material, which the row's own ink wants.
    SliverLayoutBuilder(
      builder: (context, sliverConstraints) => SliverReorderableList(
        itemCount: upNext.length,
        proxyDecorator: (child, index, animation) => Material(
          color: colors.surface2,
          child: SizedBox(
            width: sliverConstraints.crossAxisExtent,
            child: child,
          ),
        ),
        // The offset is the played head, which this list does not
        // show: its indices start at the entry after the current one.
        onReorderItem: (from, to) => notifier.reorder(
          queue.currentIndex + 1 + from,
          queue.currentIndex + 1 + to,
        ),
        itemBuilder: (context, index) {
          final entry = upNext[index];
          final at = queue.currentIndex + 1 + index;
          return _Dismissable(
            key: ValueKey<String>(entry.queueId),
            entry: entry,
            onRemove: () => notifier.removeAt(at),
            // A drag is a gesture, and a gesture is not a path for
            // everyone. `SliverReorderableList` carries none of the
            // move actions `ReorderableListView` adds for itself, so
            // the row declares them: a screen reader and a switch can
            // move an entry without dragging anything.
            child: Semantics(
              customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
                if (index > 0)
                  const CustomSemanticsAction(label: 'Move up'): () =>
                      notifier.reorder(at, at - 1),
                if (index < upNext.length - 1)
                  const CustomSemanticsAction(label: 'Move down'): () =>
                      notifier.reorder(at, at + 1),
              },
              child: QueueRow(
                entry: entry,
                onTap: () => notifier.jumpTo(at),
                onRemove: () => notifier.removeAt(at),
                handle: ReorderableDragStartListener(
                  index: index,
                  child: Semantics(
                    identifier: SemanticsIds.queueEntryDrag(entry.queueId),
                    label: 'Drag to reorder',
                    child: Padding(
                      padding: const EdgeInsets.all(WaxSpace.s8),
                      child: WaxIcon(
                        WaxIcons.sort,
                        size: 16,
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
    if (played.isNotEmpty) ...<Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            WaxSpace.s16,
            WaxSpace.s16,
            WaxSpace.s8,
            WaxSpace.s4,
          ),
          child: WaxTappable(
            onPressed: ref.read(queueHistoryOpenProvider.notifier).toggle,
            semanticsId: SemanticsIds.queueHistory,
            selected: showHistory,
            label: showHistory
                ? 'Hide what has played'
                : 'Show what has played',
            child: InkWell(
              onTap: ref.read(queueHistoryOpenProvider.notifier).toggle,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'PREVIOUSLY (${played.length})',
                      style: WaxType.overline.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                  WaxIcon(
                    showHistory ? WaxIcons.collapse : WaxIcons.expand,
                    size: 16,
                    color: colors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      if (showHistory)
        SliverList.builder(
          itemCount: played.length,
          itemBuilder: (context, index) => QueueRow(
            entry: played[index],
            onTap: () => notifier.jumpTo(index),
            onRemove: () => notifier.removeAt(index),
            semanticsId: SemanticsIds.queueHistoryEntry(played[index].queueId),
          ),
        ),
    ],
    const SliverToBoxAdapter(child: SessionHistorySection()),
    const SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s24)),
  ];
}

Widget _label(BuildContext context, String text) => SliverToBoxAdapter(
  child: Padding(
    padding: const EdgeInsets.fromLTRB(
      WaxSpace.s16,
      WaxSpace.s16,
      WaxSpace.s16,
      WaxSpace.s4,
    ),
    child: Text(
      text,
      style: WaxType.overline.copyWith(
        color: WaxColors.of(context).textTertiary,
      ),
    ),
  ),
);

/// Swipe to drop an entry. The row's own remove button does the same
/// thing, so this is a shortcut rather than the only way out - which is
/// what keeps the queue usable by keyboard and by screen reader.
class _Dismissable extends StatelessWidget {
  const _Dismissable({
    required this.entry,
    required this.onRemove,
    required this.child,
    super.key,
  });

  final QueueEntry entry;
  final VoidCallback onRemove;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Dismissible(
      key: ValueKey<String>('dismiss-${entry.queueId}'),
      onDismissed: (_) => onRemove(),
      background: ColoredBox(
        color: colors.surface2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s16),
          child: Row(
            children: <Widget>[
              WaxIcon(WaxIcons.close, size: 16, color: colors.textTertiary),
              const Spacer(),
              WaxIcon(WaxIcons.close, size: 16, color: colors.textTertiary),
            ],
          ),
        ),
      ),
      child: child,
    );
  }
}

/// One queued entry, named by whatever the app knows about its pid.
class QueueRow extends ConsumerWidget {
  const QueueRow({
    required this.entry,
    required this.onTap,
    this.onRemove,
    this.handle,
    this.playing = false,
    this.semanticsId,
    super.key,
  });

  final QueueEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  /// The drag affordance, for the rows that can be moved.
  final Widget? handle;

  final bool playing;
  final String? semanticsId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(queueItemProvider(entry.pid)).value;
    // An unresolved row still says where it sits and still answers a
    // tap: a queue that cannot be driven until every title has landed
    // is worse than one with a placeholder in it.
    final data = MediaTileData(
      title: item?.title ?? 'Loading…',
      subtitle: item?.artist,
      artwork: waxArtwork(ref.watch(artworkStoreProvider), item?.artUrl),
      domain: waxDomainOf(item?.mediaType ?? MediaType.music),
      shape: waxShapeOf(item?.mediaType ?? MediaType.music),
      trailingText: item == null
          ? null
          : formatTimecode(Duration(milliseconds: item.durationMs)),
      semanticsId: semanticsId ?? SemanticsIds.queueEntry(entry.queueId),
    );
    return Row(
      children: <Widget>[
        Expanded(
          child: MediaListRow(data: data, onTap: onTap, playing: playing),
        ),
        if (onRemove != null)
          WaxIconButton(
            glyph: WaxIcons.close,
            label: 'Remove from queue',
            size: 16,
            onPressed: onRemove,
            semanticsId: SemanticsIds.queueEntryRemove(entry.queueId),
          ),
        if (handle != null)
          Padding(
            padding: const EdgeInsets.only(right: WaxSpace.s4),
            child: handle,
          ),
      ],
    );
  }
}
