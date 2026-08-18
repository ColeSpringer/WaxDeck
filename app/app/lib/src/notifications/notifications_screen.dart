import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../settings/integrations_sections.dart';
import '../shell/semantics_ids.dart';
import 'notifications_controller.dart';

/// Notifications as a topic: what happened, and how this account is told
/// about it.
///
/// The bell in the top app bar is the peek at the first half and stays
/// what it was. This is the destination, and the reason it is one is the
/// second half: the delivery targets were a row inside a settings section
/// nobody looking for "stop telling me about this" would think to open.
/// Both halves on one screen answer the whole question.
///
/// The activity list is this session's, and says so. There is no server
/// inbox behind it - `api/spec/notifications.yaml` is the event catalog
/// and the delivery targets, not a history - so a list drawn from
/// anything but what this client saw would be complete on the device that
/// was open and empty on the one that was not. A durable inbox is a
/// server feature and is recorded as deferred.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    _markSeen();
  }

  /// Marks what is on screen as read.
  ///
  /// Arriving is reading, exactly as opening the bell is: the badge
  /// counts what has landed since somebody last looked, and a full page
  /// of the same rows is looking. On arrival and on every row after it,
  /// because unlike the bell this surface stays open - a badge climbing
  /// on the page somebody is reading is the bell's own promise broken.
  ///
  /// Posted, because the first call runs inside a build and a provider
  /// cannot be written to during one. Guarded on the count rather than
  /// on a flag: marking republishes the list, which fires the listener
  /// below again, and the guard is what makes that second pass a no-op
  /// instead of a loop.
  void _markSeen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(unseenNotificationsProvider) == 0) return;
      ref.read(notificationsProvider.notifier).markSeen();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = WaxColors.of(context);
    final rows = ref.watch(notificationsProvider);
    ref.listen(notificationsProvider, (_, _) => _markSeen());
    return WaxScaffold(
      title: l10n.bellTitle,
      largeTitle: false,
      semanticsId: SemanticsIds.notificationsScreen,
      actions: <Widget>[
        if (rows.isNotEmpty)
          WaxIconButton(
            glyph: WaxIcons.close,
            label: l10n.bellClear,
            semanticsId: SemanticsIds.notificationsClear,
            onPressed: ref.read(notificationsProvider.notifier).clear,
          ),
      ],
      body: Padding(
        padding: WaxSizeClass.of(
          context,
        ).gutter.add(const EdgeInsets.only(bottom: WaxSpace.s32)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(title: l10n.bellActivityTitle),
            Text(
              l10n.bellActivityBlurb,
              style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: WaxSpace.s8),
            if (rows.isEmpty)
              EmptyState(
                glyph: WaxIcons.bell,
                title: l10n.bellEmptyTitle,
                message: l10n.bellEmpty,
              )
            else
              for (final row in rows)
                WaxOptionRow(
                  key: ValueKey(row.semanticsId),
                  glyph: row.kind.glyph,
                  title: row.kind.messageOf(l10n),
                  subtitle: l10n.bellRowWhen(
                    row.kind.labelOf(l10n),
                    l10n.relativeSpaced(row.at),
                  ),
                  semanticsId: row.semanticsId,
                  trailing: const WaxIcon(WaxIcons.forward, size: 16),
                  onTap: () => context.go(row.location),
                ),
            const SizedBox(height: WaxSpace.s24),
            const PersonalNotificationTargetsSection(),
          ],
        ),
      ),
    );
  }
}
