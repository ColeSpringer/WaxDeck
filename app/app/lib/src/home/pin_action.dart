import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../shell/semantics_ids.dart';
import 'pinned_controller.dart';

/// Pins or unpins, saying so when the write did not land.
///
/// One helper rather than five copies, because the affordance is a menu
/// row on five different screens plus the shelf's own cards, and every
/// one of them has the same two outcomes: the shelf changes, or a full
/// list and a refused write need somewhere to be reported. A menu row
/// has no room to report anything, so the message goes where a screen's
/// others go.
Future<void> togglePin(
  BuildContext context,
  WidgetRef ref,
  String pid, {
  String? label,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final pinned = ref.read(pinnedEntitiesProvider.notifier);
  final wasPinned = pinned.contains(pid);
  final refusal = await pinned.toggle(pid);
  if (refusal != null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(refusal)));
    return;
  }
  // Confirmed only on the way off, and only where the caller named what
  // it was: unpinning from the shelf makes a card vanish, which is a
  // change worth a word, while pinning puts one there and speaks for
  // itself.
  if (!wasPinned || label == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('Unpinned $label')));
}

/// The menu row every entity surface offers, labelled for what the tap
/// will do.
WaxMenuItem<T> pinMenuItem<T>(
  WidgetRef ref,
  String pid, {
  required T value,
  String? semanticsId,
}) {
  final pinned = ref.watch(pinnedEntitiesProvider).contains(pid);
  return WaxMenuItem<T>(
    value: value,
    label: pinned ? 'Unpin from Home' : 'Pin to Home',
    glyph: WaxIcons.home,
    semanticsId: semanticsId,
  );
}

/// One target the pin sheet offers: the pid, and the words for it.
/// [what] is the kind said out loud ("album", "artist"), and [name] is
/// the thing's own name on the row under it.
typedef PinTarget = ({String pid, String what, String name});

/// The pin affordance for rows and tiles with no menu of their own: the
/// music listings, the index buckets, the search hits. A sheet rather
/// than a `WaxMenuButton`, because a
/// listing row's overflow may hold more than one target - a track row
/// pins its album or its artist, never itself - and each wants a line
/// naming what it is.
Future<void> showPinSheet(
  BuildContext context,
  WidgetRef ref, {
  required List<PinTarget> targets,
}) async {
  final colors = WaxColors.of(context);
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.surface2,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          WaxSpace.s16,
          0,
          WaxSpace.s16,
          WaxSpace.s24,
        ),
        child: Consumer(
          // Its own Consumer: the sheet outlives the row that opened it,
          // and the pin state has to flip live under a tap. The caller's
          // context stays unshadowed on purpose - the toggle reports
          // into the screen's messenger, which must outlive the pop.
          builder: (_, sheetRef, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final target in targets)
                WaxOptionRow(
                  title:
                      sheetRef
                          .watch(pinnedEntitiesProvider)
                          .contains(target.pid)
                      ? 'Unpin ${target.what} from Home'
                      : 'Pin ${target.what} to Home',
                  subtitle: target.name,
                  glyph: WaxIcons.home,
                  semanticsId: SemanticsIds.pinSheetTarget(target.pid),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(
                      togglePin(context, ref, target.pid, label: target.name),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
