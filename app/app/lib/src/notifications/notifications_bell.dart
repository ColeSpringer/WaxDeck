import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../shell/semantics_ids.dart';
import 'notifications_controller.dart';

/// The bell: what this client saw happen while it was running.
///
/// A menu rather than a panel, which is what "lightweight" in 6.19 buys:
/// the list is short by construction, every row is a link, and the whole
/// surface closes on a tap. Opening it is what marks the rows seen, so
/// the badge counts what has arrived since somebody last looked.
///
/// Empty is a legitimate state and says so rather than disabling the
/// control: a session that has been quiet is not a broken bell, and a
/// dead control invites a reload.
/// Clear's value. Every other row carries a location, and none is empty.
const _clearValue = '';

class NotificationsBell extends ConsumerWidget {
  const NotificationsBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(notificationsProvider);
    final unseen = ref.watch(unseenNotificationsProvider);
    final l10n = context.l10n;
    return WaxMenuButton<String>(
      glyph: WaxIcons.bell,
      label: unseen == 0 ? l10n.bellTitle : l10n.bellUnread(unseen),
      semanticsId: SemanticsIds.notificationsBell,
      badge: unseen == 0 ? null : '$unseen',
      emptyLabel: l10n.bellEmpty,
      emptySemanticsId: SemanticsIds.notificationsEmpty,
      onOpen: ref.read(notificationsProvider.notifier).markSeen,
      items: <WaxMenuItem<String>>[
        for (final row in rows)
          WaxMenuItem<String>(
            // Not the index: the menu holds the list it opened with, and
            // news landing behind it shifts every index down one.
            value: row.location,
            label: l10n.bellRow(
              row.kind.labelOf(l10n),
              row.kind.messageOf(l10n),
            ),
            glyph: row.kind.glyph,
            semanticsId: row.semanticsId,
          ),
        if (rows.isNotEmpty)
          WaxMenuItem<String>(
            value: _clearValue,
            label: l10n.bellClear,
            glyph: WaxIcons.close,
            semanticsId: SemanticsIds.notificationsClear,
          ),
      ],
      onSelected: (location) {
        if (location == _clearValue) {
          ref.read(notificationsProvider.notifier).clear();
          return;
        }
        context.go(location);
      },
    );
  }
}
