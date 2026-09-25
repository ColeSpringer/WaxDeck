import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../shell/semantics_ids.dart';
import 'notifications_controller.dart';

/// The dismiss row's value. Every other row carries a location, and
/// none is empty.
const _dismissValue = '';

/// The bell: what has not been dealt with, from the account's inbox and
/// this session's hints, marked seen once its menu has been read.
/// The last row reads everything; deleting lives on the screen, which asks.
class NotificationsBell extends ConsumerWidget {
  const NotificationsBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(notificationRowsProvider);
    final unseen = ref.watch(unseenNotificationsProvider);
    final l10n = context.l10n;
    final container = ProviderScope.containerOf(context, listen: false);
    return WaxMenuButton<String>(
      glyph: WaxIcons.bell,
      label: unseen == 0 ? l10n.bellTitle : l10n.bellUnread(unseen),
      semanticsId: SemanticsIds.notificationsBell,
      badge: unseen == 0 ? null : '$unseen',
      // Says so rather than disabling: a dead bell invites a reload.
      emptyLabel: l10n.bellNothingNew,
      emptySemanticsId: SemanticsIds.notificationsEmpty,
      // This build's rows, as news may land while the menu opens; through
      // the container, as the menu can be read after a rebuild has retired
      // this element and its `ref`.
      onShown: () =>
          container.read(localNotificationsProvider.notifier).markSeen(rows),
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
