import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

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
