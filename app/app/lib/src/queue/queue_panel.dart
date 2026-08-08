import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../shell/semantics_ids.dart';
import '../shell/side_panel.dart';
import 'queue_controller.dart';
import 'queue_view.dart';

/// The queue, in the shell's right panel.
///
/// The panel is the frame; [queueSlivers] is the queue, and they are the
/// same slivers the full-screen route shows. Where there is room for a panel
/// the queue sits beside what you are browsing; where there is not, it
/// takes the screen.
class QueuePanel extends ConsumerWidget {
  const QueuePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queued = ref.watch(
      queueControllerProvider.select((q) => q.isNotEmpty),
    );
    return QueueCommands(
      child: WaxSidePanel(
        title: WaxPanel.queue.title,
        semanticsId: SemanticsIds.panel,
        closeSemanticsId: SemanticsIds.panelClose,
        onClose: ref.read(sidePanelProvider.notifier).close,
        actions: <Widget>[
          if (queued)
            WaxIconButton(
              glyph: WaxIcons.delete,
              label: 'Clear queue',
              size: 18,
              onPressed: ref.read(queueControllerProvider.notifier).clear,
              semanticsId: SemanticsIds.queueClear,
            ),
        ],
        child: CustomScrollView(slivers: queueSlivers(context, ref)),
      ),
    );
  }
}
