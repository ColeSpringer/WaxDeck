import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../shell/semantics_ids.dart';
import 'notifications_controller.dart';

/// The bell: what has not been dealt with, from the account's inbox and
/// from this session's own refetch hints.
///
/// A menu rather than a panel, which is what "lightweight" in 6.19 buys:
/// the list is short by construction, every row is a link, and the whole
/// surface closes on a tap. Opening it marks this session's hints seen,
/// which is all a hint can ever be dealt with by.
///
/// Its last row reads everything, and reads rather than deletes: this
/// menu used to hold a session list where clearing cost nothing, and
/// the same gesture against a ninety-day inbox would throw away
/// somebody's history from a dropdown, on every device, with no
/// confirmation and nothing to undo it. Deleting lives on the screen,
/// where the whole list is in view and the affordance asks first.
///
/// Empty is a legitimate state and says so rather than disabling the
/// control: an account with nothing outstanding is not a broken bell,
/// and a dead control invites a reload.
/// The dismiss row's value. Every other row carries a location, and
/// none is empty.
const _dismissValue = '';

class NotificationsBell extends ConsumerWidget {
  const NotificationsBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(notificationRowsProvider);
    final unseen = ref.watch(unseenNotificationsProvider);
    final l10n = context.l10n;
    return WaxMenuButton<String>(
      glyph: WaxIcons.bell,
      label: unseen == 0 ? l10n.bellTitle : l10n.bellUnread(unseen),
      semanticsId: SemanticsIds.notificationsBell,
      badge: unseen == 0 ? null : '$unseen',
      emptyLabel: l10n.bellNothingNew,
      emptySemanticsId: SemanticsIds.notificationsEmpty,
      onOpen: ref.read(localNotificationsProvider.notifier).markSeen,
      items: <WaxMenuItem<String>>[
        for (final row in rows)
          WaxMenuItem<String>(
            // Not the index: the menu holds the list it opened with, and
            // news landing behind it shifts every index down one.
            value: row.location,
            label: l10n.bellRow(row.surfaceOf(l10n), row.messageOf(l10n)),
            glyph: row.glyph,
            semanticsId: row.semanticsId,
          ),
        if (rows.isNotEmpty)
          WaxMenuItem<String>(
            value: _dismissValue,
            label: l10n.bellMarkAllRead,
            glyph: WaxIcons.check,
            // Its own handle, not the screen's: the same identifier on
            // a menu row and an app-bar button would let a locator
            // waiting for this menu be answered by the screen behind
            // it.
            semanticsId: SemanticsIds.notificationsPeekRead,
          ),
      ],
      onSelected: (location) {
        if (location == _dismissValue) {
          unawaited(ref.read(notificationsProvider.notifier).markAllRead());
          return;
        }
        context.go(location);
      },
    );
  }
}
