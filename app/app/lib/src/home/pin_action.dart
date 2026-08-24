import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
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
}) => togglePinCaptured(
  messenger: ScaffoldMessenger.of(context),
  l10n: context.l10n,
  pinned: ref.read(pinnedEntitiesProvider.notifier),
  pid: pid,
  label: label,
);

/// [togglePin] for a caller that captured its dependencies before
/// raising a sheet. A sheet outlives the row that opened it - a queue
/// entry scrolls into collapsed history, a sync delta rewrites a
/// playlist - and reaching back through that row's context or ref after
/// the pop lands on an element that is no longer in the tree. The
/// messenger, the copy table, and the controller all outlive the row,
/// so what was tapped still happens.
Future<void> togglePinCaptured({
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
  required PinnedEntities pinned,
  required String pid,
  String? label,
}) async {
  final wasPinned = pinned.contains(pid);
  final refusal = await pinned.toggle(pid);
  if (refusal != null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(pinRefusalMessage(l10n, refusal))));
    return;
  }
  // Confirmed only on the way off, and only where the caller named what
  // it was: unpinning from the shelf makes a card vanish, which is a
  // change worth a word, while pinning puts one there and speaks for
  // itself.
  if (!wasPinned || label == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(l10n.homeUnpinned(label))));
}

/// The menu row every entity surface offers, labelled for what the tap
/// will do.
WaxMenuItem<T> pinMenuItem<T>(
  BuildContext context,
  WidgetRef ref,
  String pid, {
  required T value,
  String? semanticsId,
}) {
  final pinned = ref.watch(pinnedEntitiesProvider).contains(pid);
  final l10n = context.l10n;
  return WaxMenuItem<T>(
    value: value,
    label: pinned ? l10n.homeUnpinAction : l10n.homePinAction,
    glyph: WaxIcons.home,
    semanticsId: semanticsId,
  );
}

/// One target the pin sheet offers: the pid, and what to say about it.
/// [what] is a token, not a word - the row is a whole sentence about
/// the kind. [name] is the thing's own name on the row under it.
typedef PinTarget = ({String pid, String what, String name});

/// The pin row as every sheet draws it: the live pin state read through
/// the sheet's own ref, the sentence for the kind, and the target's
/// stable handle. One body for the pin sheet and both item menus, so
/// the row cannot drift between them.
Widget pinSheetRow(
  BuildContext sheetContext,
  WidgetRef sheetRef,
  PinTarget target, {
  required VoidCallback onTap,
}) {
  final pinned = sheetRef.watch(pinnedEntitiesProvider).contains(target.pid);
  return WaxOptionRow(
    title: pinned
        ? sheetContext.l10n.homePinSheetUnpin(target.what)
        : sheetContext.l10n.homePinSheetPin(target.what),
    subtitle: target.name,
    glyph: WaxIcons.home,
    semanticsId: SemanticsIds.pinSheetTarget(target.pid),
    onTap: onTap,
  );
}

/// The pin affordance for rows and tiles whose menu holds nothing else:
/// artist and book search hits, the artist index buckets. A listing
/// row's overflow may hold more than one target - a track row pins its
/// album or its artist, never itself - and each wants a line naming
/// what it is.
Future<void> showPinSheet(
  BuildContext context,
  WidgetRef ref, {
  required List<PinTarget> targets,
}) async {
  // Captured before the sheet: it outlives the row that opened it.
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final pinned = ref.read(pinnedEntitiesProvider.notifier);
  await showWaxOptionSheet(
    context,
    builder: (sheetContext) => Consumer(
      // Its own Consumer: the pin state has to flip live under a tap.
      builder: (_, sheetRef, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final target in targets)
            pinSheetRow(
              sheetContext,
              sheetRef,
              target,
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(
                  togglePinCaptured(
                    messenger: messenger,
                    l10n: l10n,
                    pinned: pinned,
                    pid: target.pid,
                    label: target.name,
                  ),
                );
              },
            ),
        ],
      ),
    ),
  );
}
