import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../media_view.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/side_panel.dart';
import 'queue_controller.dart';
import 'queue_item.dart';
import 'queue_state.dart';

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

/// The queue, in the shell's right panel.
///
/// What is playing stays pinned at the top and what follows is a list
/// that can be jumped into and removed from. Reordering by drag, the
/// history strip, and the compact full-screen route are the queue
/// surface's other half and land with the entity screens; this is the
/// half the deck bar's queue control needs to open onto something real.
class QueuePanel extends ConsumerWidget {
  const QueuePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    final queue = ref.watch(queueControllerProvider);
    final notifier = ref.read(queueControllerProvider.notifier);
    final provenance = queueProvenance(queue.source);
    final upNext = queue.isEmpty
        ? const <QueueEntry>[]
        : queue.entries.sublist(queue.currentIndex + 1);

    return WaxSidePanel(
      title: WaxPanel.queue.title,
      semanticsId: SemanticsIds.panel,
      closeSemanticsId: SemanticsIds.panelClose,
      onClose: ref.read(sidePanelProvider.notifier).close,
      actions: <Widget>[
        if (queue.isNotEmpty)
          WaxIconButton(
            glyph: WaxIcons.delete,
            label: 'Clear queue',
            size: 18,
            onPressed: notifier.clear,
            semanticsId: SemanticsIds.queueClear,
          ),
      ],
      child: queue.isEmpty
          ? const EmptyState(
              title: 'Nothing queued',
              message:
                  'Play an album, a show, or a playlist and it '
                  'lands here.',
              glyph: WaxIcons.queue,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
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
                          style: WaxType.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      // A rolling queue is a window over something
                      // larger, and a listener counting what is left
                      // should not read the window as the whole of it.
                      if (queue.source.rolling)
                        Text(
                          'A window over a larger shuffle',
                          style: WaxType.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      const SizedBox(height: WaxSpace.s8),
                      Row(
                        children: <Widget>[
                          WaxIconButton(
                            glyph: WaxIcons.shuffle,
                            label: queue.shuffled
                                ? 'Shuffle on'
                                : 'Shuffle off',
                            size: 18,
                            active: queue.shuffled,
                            onPressed: () =>
                                notifier.setShuffle(!queue.shuffled),
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
                            onPressed: () => notifier.setRepeat(
                              nextQueueRepeat(queue.repeat),
                            ),
                            semanticsId: SemanticsIds.queueRepeat,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _QueueRow(
                  // The queue's own accessor rather than a second place
                  // that indexes by hand: what is current is the state's
                  // to answer, and everything else in the app asks it
                  // the same way.
                  entry: queue.currentEntry!,
                  playing: true,
                  onTap: () => context.push(WaxRoute.nowPlaying),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    WaxSpace.s16,
                    WaxSpace.s16,
                    WaxSpace.s16,
                    WaxSpace.s4,
                  ),
                  child: Text(
                    upNext.isEmpty ? 'NOTHING UP NEXT' : 'UP NEXT',
                    style: WaxType.overline.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: upNext.length,
                    itemBuilder: (context, index) {
                      // The entry's place in the whole queue, which is
                      // what the controller's verbs take: `upNext` is a
                      // view of the tail, and its own indices would jump
                      // the queue to the wrong row.
                      final at = queue.currentIndex + 1 + index;
                      return _QueueRow(
                        entry: upNext[index],
                        onTap: () => notifier.jumpTo(at),
                        onRemove: () => notifier.removeAt(at),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

/// The next repeat mode in the cycle the transport walks.
QueueRepeat nextQueueRepeat(QueueRepeat repeat) => switch (repeat) {
  QueueRepeat.off => QueueRepeat.all,
  QueueRepeat.all => QueueRepeat.one,
  QueueRepeat.one => QueueRepeat.off,
};

/// One queued entry, named by whatever the app knows about its pid.
class _QueueRow extends ConsumerWidget {
  const _QueueRow({
    required this.entry,
    required this.onTap,
    this.onRemove,
    this.playing = false,
  });

  final QueueEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final bool playing;

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
      semanticsId: SemanticsIds.queueEntry(entry.queueId),
    );
    return Row(
      children: <Widget>[
        Expanded(
          child: MediaListRow(data: data, onTap: onTap, playing: playing),
        ),
        if (onRemove != null)
          Padding(
            padding: const EdgeInsets.only(right: WaxSpace.s4),
            child: WaxIconButton(
              glyph: WaxIcons.close,
              label: 'Remove from queue',
              size: 16,
              onPressed: onRemove,
              semanticsId: SemanticsIds.queueEntryRemove(entry.queueId),
            ),
          ),
      ],
    );
  }
}
