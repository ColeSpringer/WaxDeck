import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../settings/integrations_sections.dart';
import '../shell/semantics_ids.dart';
import 'admin_console.dart';

/// The server's own notification destinations.
///
/// A re-parent, not new capability: the editor, its controller, and the
/// endpoints behind them all shipped with the personal targets, and this
/// section rode along at the bottom of the listener's Integrations
/// screen behind an admin check. That put a server-scope surface inside
/// a per-account one, where an administrator went looking for their own
/// targets and found everyone's underneath - and where the console,
/// which is the place this instance's switches live, did not offer it at
/// all.
class AdminNotificationsScreen extends ConsumerWidget {
  const AdminNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    return WaxScaffold(
      title: context.l10n.adminSectionNotifications,
      largeTitle: false,
      semanticsId: SemanticsIds.adminNotifications,
      onBack: adminBack(context),
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: sizeClass.gutter.add(
              const EdgeInsets.only(bottom: WaxSpace.s24),
            ),
            child: const ServerNotificationTargetsSection(),
          ),
        ),
      ],
    );
  }
}
