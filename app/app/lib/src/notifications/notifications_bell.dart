import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

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
class NotificationsBell extends ConsumerWidget {
  const NotificationsBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(notificationsProvider);
    final unseen = ref.watch(unseenNotificationsProvider);
    return WaxMenuButton<int>(
      // The vendored icon subsets carry no bell (ADR-0016: the set is
      // fixed at `make icons` time, which is network-bound and not part
      // of `generate`), so this wears the information glyph, which is
      // what the rows behind it are. Recorded rather than approximated
      // with a warning triangle, which would say something false about
      // every row.
      glyph: WaxIcons.info,
      label: unseen == 0 ? 'Notifications' : 'Notifications, $unseen unread',
      semanticsId: SemanticsIds.notificationsBell,
      badge: unseen == 0 ? null : '$unseen',
      emptyLabel: 'Nothing has happened yet.',
      onOpen: ref.read(notificationsProvider.notifier).markSeen,
      items: <WaxMenuItem<int>>[
        for (var i = 0; i < rows.length; i++)
          WaxMenuItem<int>(
            value: i,
            label: '${rows[i].kind.label}: ${rows[i].message}',
            glyph: rows[i].kind.glyph,
            semanticsId: SemanticsIds.notificationRow(i),
          ),
        if (rows.isNotEmpty)
          WaxMenuItem<int>(
            value: -1,
            label: 'Clear',
            glyph: WaxIcons.close,
            semanticsId: SemanticsIds.notificationsClear,
          ),
      ],
      onSelected: (index) {
        if (index < 0) {
          ref.read(notificationsProvider.notifier).clear();
          return;
        }
        // Re-read rather than closing over the list the menu was built
        // from: a change can land while the menu is open, and following
        // a stale index would open somebody else's surface.
        final held = ref.read(notificationsProvider);
        if (index >= held.length) return;
        context.go(held[index].kind.location);
      },
    );
  }
}
