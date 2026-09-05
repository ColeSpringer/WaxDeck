import 'dart:async';

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
/// The bell in the top app bar is the peek at the first half; this is
/// the destination, and the reason it is one is the second half: the
/// delivery targets were a row inside a settings section nobody looking
/// for "stop telling me about this" would think to open. Both halves on
/// one screen answer the whole question.
///
/// The list is the account's own inbox, which the server keeps and
/// prunes, merged with the refetch hints this session minted. So a row
/// survives a relaunch and reaches the other device, and the hints -
/// which say a surface moved and nothing more - do not, because there
/// was never anything for the server to keep.
///
/// Read is a state here rather than a disappearance: unread rows are
/// emphasized and say so, and dealing with one leaves it in place,
/// greyed. Delete is what removes one, and it is per row.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  /// The row's detail line, or null where it has none to add.
  ///
  /// Null rather than an empty string, so the subtitle is built with one
  /// join instead of a conditional at every use.
  static String? _detailOrNull(WaxNotification row, AppLocalizations l10n) {
    final detail = row.detailOf(l10n);
    return detail.isEmpty ? null : detail;
  }

  Future<void> _confirmClear(
    BuildContext context,
    NotificationsController notifier,
  ) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('notifications-clear-dialog'),
        title: Text(l10n.bellClearTitle),
        content: Text(l10n.bellClearConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          Semantics(
            identifier: SemanticsIds.notificationsClearConfirm,
            container: true,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.bellClear),
            ),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await notifier.clear();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = WaxColors.of(context);
    final view = ref.watch(notificationsViewProvider);
    final rows = view.rows;
    final notifier = ref.read(notificationsProvider.notifier);
    return WaxScaffold(
      title: l10n.bellTitle,
      largeTitle: false,
      semanticsId: SemanticsIds.notificationsScreen,
      actions: <Widget>[
        if (view.badge > 0)
          WaxIconButton(
            glyph: WaxIcons.check,
            label: l10n.bellMarkAllRead,
            semanticsId: SemanticsIds.notificationsMarkAllRead,
            onPressed: () => unawaited(notifier.markAllRead()),
          ),
        if (rows.isNotEmpty)
          WaxIconButton(
            glyph: WaxIcons.close,
            label: l10n.bellClear,
            semanticsId: SemanticsIds.notificationsClear,
            // Asked first, because this one is not a tidy-up: the inbox
            // is ninety days of history shared by every device on the
            // account, read rows included, and nothing brings it back.
            onPressed: () => unawaited(_confirmClear(context, notifier)),
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
                  // The row's own identity, not what it is about: the
                  // inbox keeps ninety days, so two nightly backups are
                  // two rows saying the same thing, and a key drawn
                  // from the event alone would be the same key twice.
                  key: ValueKey(row.semanticsId),
                  glyph: row.glyph,
                  title: row.messageOf(l10n),
                  // What happened, then whether it has been dealt with
                  // and when. The detail is the server's own wording,
                  // which is the only place the particular episode,
                  // show or playlist is named.
                  subtitle: <String>[
                    ?_detailOrNull(row, l10n),
                    l10n.bellRowWhen(
                      row.read
                          ? l10n.bellReadOverline
                          : l10n.bellUnreadOverline,
                      l10n.relativeSpaced(row.at),
                    ),
                  ].join('\n'),
                  subtitleMaxLines: 4,
                  semanticsId: row.semanticsId,
                  // Unread rows are emphasized and say so: the overline
                  // carries the state in words, because colour alone
                  // reaches neither a screen reader nor everybody
                  // looking at it.
                  active: !row.read,
                  trailing: row.fromInbox
                      ? WaxIconButton(
                          glyph: WaxIcons.close,
                          label: l10n.bellDelete,
                          semanticsId: SemanticsIds.notificationDelete(row.id!),
                          onPressed: () => unawaited(notifier.delete(row.id!)),
                        )
                      : const WaxIcon(WaxIcons.forward, size: 16),
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
