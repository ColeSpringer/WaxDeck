import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart'
    show HardwareKeyboard, LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../l10n/l10n.dart';
import '../media_view.dart';
import '../shell/commands.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/side_panel.dart';
import 'queue_controller.dart';
import 'queue_drag.dart';
import 'queue_item.dart';
import 'queue_state.dart';
import 'session_history.dart';

/// Where a queue came from, as a sentence. Null where naming it would
/// say nothing: one item tapped on its own is its own provenance.
String? queueProvenance(AppLocalizations l10n, QueueSource source) {
  return switch (source.kind) {
    QueueSourceKind.single || QueueSourceKind.unknown => null,
    // Worded from the kind rather than the label: the whole library has
    // no name of its own, and the label is stored with the queue, so it
    // outlives the language it was built in.
    QueueSourceKind.library => l10n.queuePlayingFromLibrary,
    // A mix seeded by one track is the same case: the seed is not what
    // the mix is, so there is no name to carry and the kind says it.
    QueueSourceKind.mix when source.label.isEmpty => l10n.queuePlayingFromMix,
    _ when source.label.isEmpty => null,
    _ => l10n.queuePlayingFrom(source.label),
  };
}

/// Opens the queue wherever this caller keeps it.
///
/// The panel where there is room for one and something to put it beside,
/// the queue's own screen otherwise. The same queue either way, and one
/// place that decides so: the deck bar, the player's action row, and the
/// up-next peek all ask for it, and three copies of the condition is
/// three places to fix when the answer changes.
///
/// [overShell] is the second half of that condition, and the player is
/// why it exists: `/now-playing` is a route pushed over the shell, so it
/// covers the panel slot. Opening the panel from there lit the control
/// and changed nothing anybody could see, on every window wide enough to
/// have a panel. The deck bar is shell chrome rather than a page over
/// it, so it keeps the panel.
void openQueue(BuildContext context, WidgetRef ref, {bool overShell = false}) {
  if (!overShell && WaxSizeClass.of(context).hasSidebar) {
    ref.read(sidePanelProvider.notifier).toggle(WaxPanel.queue);
    return;
  }
  context.push(WaxRoute.queue);
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

/// Which up-next entries are picked for a batch verb.
///
/// A provider for the same reason the disclosure above is one: the
/// surface is a list of slivers the panel and the screen each fold into
/// their own scroll view, so state held in either would be a different
/// selection on each - and the panel and the screen are the same queue.
///
/// Empty means not selecting. Keyed by queue id rather than by index,
/// because an index stops naming the same entry the moment a row moves
/// and moving rows is what this exists for.
class QueueSelection extends Notifier<Set<String>> {
  /// The last row touched, which a shift+click extends from.
  String? _anchor;

  @override
  Set<String> build() => const <String>{};

  /// Adds or drops one row, and makes it the anchor either way: the
  /// range a later shift+click covers runs from the last row the hand
  /// touched, whether that touch selected or deselected.
  void toggle(String queueId) {
    final next = <String>{...state};
    if (!next.remove(queueId)) next.add(queueId);
    // The anchor goes with the selection when un-ticking the last row
    // empties it. Leaving it set makes the two ways out of selection
    // disagree - [clear] drops the anchor, so the next shift+click would
    // start a fresh range after Clear and extend from a row nobody can
    // see any more after a final untick.
    _anchor = next.isEmpty ? null : queueId;
    state = next;
  }

  /// Selects everything between the anchor and [queueId] in [order].
  ///
  /// With no anchor - the first shift+click of a selection - the row
  /// becomes the anchor and the range is itself, which is what makes
  /// shift+click a way *into* selection rather than a gesture that only
  /// works once something is already picked.
  void selectRange(String queueId, List<String> order) {
    final to = order.indexOf(queueId);
    if (to < 0) return;
    final anchor = _anchor;
    // No anchor to extend from, or one that has since left the surface:
    // this row becomes the anchor and the range is itself. Through
    // [toggle] rather than by assignment, so the anchor is actually set
    // - without that the next shift+click has nothing to run from and
    // extends by one row at a time forever.
    final from = anchor == null ? -1 : order.indexOf(anchor);
    if (from < 0) {
      toggle(queueId);
      return;
    }
    final lo = from <= to ? from : to;
    final hi = from <= to ? to : from;
    // Added to what is held rather than replacing it: shift+click
    // extends a selection, and two ranges picked in turn are both
    // wanted. The anchor stays put so a wider drag from the same start
    // grows the range instead of walking it.
    state = <String>{...state, ...order.sublist(lo, hi + 1)};
  }

  void clear() {
    if (state.isEmpty && _anchor == null) return;
    _anchor = null;
    state = const <String>{};
  }
}

final queueSelectionProvider = NotifierProvider<QueueSelection, Set<String>>(
  QueueSelection.new,
);

/// Where a dragged block of selected rows should land, in the
/// queue-without-the-set coordinates [QueueController.moveSetTo] takes.
///
/// The reorderable list hands out an index into the up-next list without
/// the *dragged* row, which is not the same coordinate space once a
/// whole set is moving. So the drop is resolved by what it lands after
/// instead: walk back past anything travelling with the block, and the
/// first row staying put is the anchor. Nothing staying put above it
/// means the block goes to the top of up-next.
///
/// [to] is `onReorderItem`'s, so it is already one less than the raw
/// drop index whenever the drop is below the drag origin - which a drop
/// past the last row always is. That is what bounds it at one less than
/// [upNextIds]'s length and keeps the anchor inside the list; a caller
/// synthesizing a larger [to] would be outside the contract.
int queueDropTarget({
  required List<QueueEntry> entries,
  required int currentIndex,
  required List<String> upNextIds,
  required Set<String> moving,
  required int from,
  required int to,
}) {
  final without = [...upNextIds]..removeAt(from);
  var anchor = to - 1;
  while (anchor >= 0 && moving.contains(without[anchor])) {
    anchor--;
  }
  if (anchor < 0) return currentIndex + 1;
  final anchorId = without[anchor];
  final rest = <String>[
    for (final e in entries)
      if (!moving.contains(e.queueId)) e.queueId,
  ];
  return rest.indexOf(anchorId) + 1;
}

/// Escape, for a surface showing the queue.
///
/// Scoped rather than global, so the key belongs to whoever is on top:
/// `CommandScope` withdraws itself when its route stops being current,
/// which is what resolves the panel-and-player interplay - a pushed
/// player withdraws the shell-hosted panel's command, and on `/queue`
/// the screen's own scope wins. It prints in the palette and the
/// shortcut sheet for free, which a local `Shortcuts` would not.
///
/// Wrap a queue surface in this and hand it [queueSlivers].
class QueueCommands extends ConsumerWidget {
  const QueueCommands({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CommandScope(
      commands: <WaxCommand>[
        WaxCommand(
          id: 'queue-clear-selection',
          label: context.l10n.queueClearSelection,
          section: WaxCommandSection.view,
          glyph: WaxIcons.close,
          // Not on repeats, for the reason the player's Escape is not:
          // a held key repeats faster than a scope withdraws, and the
          // second firing would land on whatever is underneath.
          activators: const <ShortcutActivator>[
            SingleActivator(LogicalKeyboardKey.escape, includeRepeats: false),
          ],
          enabled: (ref) => ref.watch(queueSelectionProvider).isNotEmpty,
          run: (context, ref) =>
              ref.read(queueSelectionProvider.notifier).clear(),
        ),
      ],
      child: child,
    );
  }
}

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
  final l10n = context.l10n;
  final queue = ref.watch(queueControllerProvider);
  final notifier = ref.read(queueControllerProvider.notifier);
  final showHistory = ref.watch(queueHistoryOpenProvider);

  if (queue.isEmpty) {
    return <Widget>[
      // One sliver, not two: a filled remainder followed by anything
      // puts that anything past the bottom of the viewport, where it is
      // never laid out and never found.
      SliverFillRemaining(
        hasScrollBody: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: EmptyState(
                title: l10n.queueEmptyTitle,
                message: l10n.queueEmptyMessage,
                glyph: WaxIcons.queue,
              ),
            ),
            const SessionHistorySection(),
          ],
        ),
      ),
    ];
  }

  final upNext = queue.entries.sublist(queue.currentIndex + 1);
  final played = queue.entries.sublist(0, queue.currentIndex);
  final provenance = queueProvenance(l10n, queue.source);
  final upNextIds = <String>[for (final e in upNext) e.queueId];
  // Narrowed to what is actually drawn: the queue moves underneath a
  // selection, and a set holding ids nothing shows any more would have
  // the bar counting rows that are not there.
  //
  // Through a set rather than the list: this runs on every rebuild of a
  // surface the panel and the screen both host, and a `contains` per
  // selected id over a list is the queue's cap squared at the worst of
  // it. The ordered list stays for the range and the drop, which need
  // positions rather than membership.
  final upNextSet = upNextIds.toSet();
  final selected = <String>{
    for (final id in ref.watch(queueSelectionProvider))
      if (upNextSet.contains(id)) id,
  };
  final selecting = selected.isNotEmpty;
  final selection = ref.read(queueSelectionProvider.notifier);

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
                l10n.queueRollingWindow,
                style: WaxType.caption.copyWith(color: colors.textTertiary),
              ),
            const SizedBox(height: WaxSpace.s8),
            Row(
              children: <Widget>[
                WaxIconButton(
                  glyph: WaxIcons.shuffle,
                  label: queue.shuffled
                      ? l10n.queueShuffleOn
                      : l10n.queueShuffleOff,
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
                    QueueRepeat.off => l10n.queueRepeatOff,
                    QueueRepeat.all => l10n.queueRepeatAll,
                    QueueRepeat.one => l10n.queueRepeatOne,
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
      // The playing row answers a drop too, and it is the likeliest row
      // to aim at: without a marker here a drop on the highlighted row
      // finds nothing under the pointer and falls back to the end of
      // the queue, which is the furthest possible place from where it
      // was aimed. It does not split - nothing can be queued before
      // what is already playing - so anywhere on it means next.
      child: MetaData(
        metaData: QueueRowTarget(queue.currentEntry!.queueId, splits: false),
        behavior: HitTestBehavior.opaque,
        child: QueueRow(
          entry: queue.currentEntry!,
          playing: true,
          onTap: () => context.push(WaxRoute.nowPlaying),
        ),
      ),
    ),
    _label(
      context,
      upNext.isEmpty ? l10n.queueNothingUpNext : l10n.playerUpNext,
    ),
    if (selecting)
      SliverToBoxAdapter(
        child: _SelectionBar(
          count: selected.length,
          onRemove: () {
            notifier.removeSet(selected);
            // Cleared after a remove and kept after a move: what was
            // taken away is gone, and what was moved is still there to
            // move again.
            selection.clear();
          },
          onTop: () => notifier.moveSetTo(selected, queue.currentIndex + 1),
          onBottom: () => notifier.moveSetTo(selected, queue.length),
          onClear: selection.clear,
        ),
      ),
    // Wrapped so the drag proxy can be given a width: the proxy is built
    // into an overlay, where the cross-axis constraint is unbounded and a
    // row with an Expanded in it would stretch to infinity, and outside
    // any Material, which the row's own ink wants.
    SliverLayoutBuilder(
      builder: (context, sliverConstraints) => SliverReorderableList(
        itemCount: upNext.length,
        proxyDecorator: (child, index, animation) {
          // The lifted row says how many rows are coming with it, because
          // the others stay where they are until the drop and a block
          // that moved silently would read as a bug.
          final carrying =
              index < upNextIds.length && selected.contains(upNextIds[index])
              ? selected.length
              : 1;
          return Material(
            color: colors.surface2,
            child: SizedBox(
              width: sliverConstraints.crossAxisExtent,
              child: carrying > 1
                  ? Stack(
                      alignment: AlignmentDirectional.centerEnd,
                      children: <Widget>[
                        child,
                        Padding(
                          padding: const EdgeInsets.only(right: WaxSpace.s32),
                          child: _DragCount(count: carrying),
                        ),
                      ],
                    )
                  : child,
            ),
          );
        },
        // The offset is the played head, which this list does not
        // show: its indices start at the entry after the current one.
        onReorderItem: (from, to) {
          // Dragging any selected row moves the whole set, which is what
          // makes a selection worth having on a list whose main verb is
          // a drag.
          if (selected.contains(upNextIds[from])) {
            notifier.moveSetTo(
              selected,
              queueDropTarget(
                entries: queue.entries,
                currentIndex: queue.currentIndex,
                upNextIds: upNextIds,
                moving: selected,
                from: from,
                to: to,
              ),
            );
            return;
          }
          notifier.reorder(
            queue.currentIndex + 1 + from,
            queue.currentIndex + 1 + to,
          );
        },
        itemBuilder: (context, index) {
          final entry = upNext[index];
          final at = queue.currentIndex + 1 + index;
          return MetaData(
            // The reorderable list wants the key on the row it is
            // handed, so it rides out here with the marker rather than
            // on the dismissable inside.
            key: ValueKey<String>(entry.queueId),
            // What a drop from a listing hit-tests against, so a row
            // dragged onto the panel lands where it was released rather
            // than always at the end. Opaque so the gaps between rows
            // answer too: a drop between two of them is a drop, and a
            // pointer that fell in a one-pixel seam is not a mistake.
            metaData: QueueRowTarget(entry.queueId),
            behavior: HitTestBehavior.opaque,
            child: _Dismissable(
              entry: entry,
              // A swipe is a shortcut for removing one row, and while a
              // set is picked the row-shaped verbs belong to the bar.
              onRemove: selecting ? null : () => notifier.removeAt(at),
              // A drag is a gesture, and a gesture is not a path for
              // everyone. `SliverReorderableList` carries none of the
              // move actions `ReorderableListView` adds for itself, so
              // the row declares them: a screen reader and a switch can
              // move an entry without dragging anything.
              child: Semantics(
                customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
                  if (index > 0)
                    CustomSemanticsAction(label: l10n.queueMoveUp): () =>
                        notifier.reorder(at, at - 1),
                  if (index < upNext.length - 1)
                    CustomSemanticsAction(label: l10n.queueMoveDown): () =>
                        notifier.reorder(at, at + 1),
                },
                child: QueueRow(
                  entry: entry,
                  // While a set is picked a tap picks rather than jumps:
                  // the surface is in a mode, and a tap that started
                  // playback halfway through choosing would be the worst
                  // possible answer.
                  onTap: selecting
                      ? () => _pick(selection, entry.queueId, upNextIds)
                      : () => _pick(
                          selection,
                          entry.queueId,
                          upNextIds,
                          orJump: () => notifier.jumpTo(at),
                        ),
                  onRemove: selecting ? null : () => notifier.removeAt(at),
                  // Only while a set is picked: the checkbox takes the
                  // artwork's slot, so wiring it always would put a column
                  // of empty boxes down a queue nobody is selecting in.
                  // The long press below is the way in.
                  onSelect: selecting
                      ? (_) => selection.toggle(entry.queueId)
                      : null,
                  selected: selected.contains(entry.queueId),
                  selectSemanticsId: SemanticsIds.queueEntrySelect(
                    entry.queueId,
                  ),
                  onLongPress: () => selection.toggle(entry.queueId),
                  handle: ReorderableDragStartListener(
                    index: index,
                    child: Semantics(
                      identifier: SemanticsIds.queueEntryDrag(entry.queueId),
                      label: l10n.queueDragToReorder,
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
            label: showHistory ? l10n.queueHideHistory : l10n.queueShowHistory,
            child: InkWell(
              onTap: ref.read(queueHistoryOpenProvider.notifier).toggle,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      l10n.queuePreviously(played.length),
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

/// What a tap on an up-next row means.
///
/// Held shift extends the selection from the last row touched, which is
/// the desktop idiom for picking a run of rows and is worth having on
/// the one surface whose whole job is rearranging a long list. Without
/// it the tap is the row's ordinary verb - [orJump] where one is offered,
/// and picking the row where the surface is already selecting.
void _pick(
  QueueSelection selection,
  String queueId,
  List<String> order, {
  VoidCallback? orJump,
}) {
  if (HardwareKeyboard.instance.isShiftPressed) {
    selection.selectRange(queueId, order);
    return;
  }
  if (orJump != null) {
    orJump();
    return;
  }
  selection.toggle(queueId);
}

/// How many rows a lifted block is carrying.
///
/// Decoration and nothing else: it lives inside a drag proxy, which is
/// an overlay a screen reader never reaches, and the selection bar above
/// is where the count is announced.
class _DragCount extends StatelessWidget {
  const _DragCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.accentContainer,
          borderRadius: WaxRadius.pill,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WaxSpace.s8,
            vertical: WaxSpace.s4,
          ),
          child: Text(
            '$count',
            style: WaxType.label.copyWith(color: colors.onAccentContainer),
          ),
        ),
      ),
    );
  }
}

/// The verbs a picked set has, drawn where the up-next rows begin.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onRemove,
    required this.onTop,
    required this.onBottom,
    required this.onClear,
  });

  final int count;
  final VoidCallback onRemove;
  final VoidCallback onTop;
  final VoidCallback onBottom;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WaxSpace.s16,
        WaxSpace.s4,
        WaxSpace.s16,
        WaxSpace.s8,
      ),
      child: Wrap(
        spacing: WaxSpace.s8,
        runSpacing: WaxSpace.s8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text(
            context.l10n.queueSelectedCount(count),
            style: WaxType.label.copyWith(
              color: WaxColors.of(context).textSecondary,
            ),
          ),
          WaxButton(
            label: context.l10n.queueRemove,
            kind: WaxButtonKind.tonal,
            icon: WaxIcons.close,
            semanticsId: SemanticsIds.queueSelectionRemove,
            onPressed: onRemove,
          ),
          // Move to top subsumes play-next: the top of up-next is the
          // next thing that plays, so a second verb for it would be the
          // same button under another name.
          WaxButton(
            label: context.l10n.queueMoveToTop,
            kind: WaxButtonKind.tonal,
            icon: WaxIcons.collapse,
            semanticsId: SemanticsIds.queueSelectionTop,
            onPressed: onTop,
          ),
          WaxButton(
            label: context.l10n.queueMoveToBottom,
            kind: WaxButtonKind.tonal,
            icon: WaxIcons.expand,
            semanticsId: SemanticsIds.queueSelectionBottom,
            onPressed: onBottom,
          ),
          WaxButton(
            label: context.l10n.queueClearSelectionAction,
            kind: WaxButtonKind.text,
            semanticsId: SemanticsIds.queueSelectionClear,
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
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
  });

  final QueueEntry entry;

  /// Null while a set is picked: the shortcut for removing one row is
  /// exactly what a multi-select is not doing, and a swipe landing on a
  /// checkbox is the gesture most likely to be an accident.
  final VoidCallback? onRemove;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final onRemove = this.onRemove;
    if (onRemove == null) return child;
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
    this.onSelect,
    this.onLongPress,
    this.selectSemanticsId,
    this.selected = false,
    this.handle,
    this.playing = false,
    this.semanticsId,
    super.key,
  });

  final QueueEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  /// The multi-select plumbing, wired only on the up-next rows: the
  /// current entry and the history keep the behaviour they had, because
  /// the batch verbs are all about what has not played yet.
  final ValueChanged<bool>? onSelect;
  final VoidCallback? onLongPress;
  final String? selectSemanticsId;
  final bool selected;

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
      title: item?.title ?? context.l10n.commonLoadingTitle,
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
          child: MediaListRow(
            data: data,
            onTap: onTap,
            onSelect: onSelect,
            onLongPress: onLongPress,
            selectSemanticsId: selectSemanticsId,
            selected: selected,
            playing: playing,
          ),
        ),
        if (onRemove != null)
          WaxIconButton(
            glyph: WaxIcons.close,
            label: context.l10n.queueRemoveEntry,
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
