import 'dart:async';

import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';

/// Runs a preference write, and says so where it fails.
///
/// The controls on these screens are drawn from the stored document and
/// hold nothing of their own, so they do not move until the server has
/// confirmed the write. A write that fails therefore looks exactly like
/// a tap that did nothing: the switch stays where it was, the menu
/// closes on the old value, and nothing anywhere says why. This is what
/// tells the two apart.
///
/// Fire-and-forget rather than awaited: a row has nothing to wait for
/// and nowhere to show a spinner, and the controller already queues one
/// write behind the last.
///
/// Everything is caught, not only the contract's own refusals. The write
/// runs the whole prefs chain - a session load, a read of the current
/// document, then the PUT - and only a Dio failure is translated on the
/// way out, so a timeout or a decode error arrives untranslated; caught
/// narrowly, those would stay the silence this exists to remove. The
/// cost is that a defect here reads as a sentence instead of reaching
/// the defect log, which is the trade `pinned_controller` already makes
/// where it catches `on Object` for the same reason.
void saveSetting(BuildContext context, Future<void> write) {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  unawaited(
    write.catchError((Object error) {
      // The messenger outlives the row but not the screen: leaving a
      // section with a write in flight must not throw on the way out.
      if (!messenger.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(explainError(l10n, error))),
      );
    }),
  );
}
