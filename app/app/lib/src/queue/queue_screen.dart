import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../shell/routes.dart';
import '../shell/side_panel.dart';
import '../shell/semantics_ids.dart';
import 'queue_controller.dart';
import 'queue_view.dart';

/// The queue, full screen.
///
/// What the side panel shows where there is room for one, and the only
/// place it can be shown where there is not. Pushed rather than gone to,
/// like the player: it is a view of live state with nothing of its own
/// to address, and back closes it onto whatever was underneath.
class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queued = ref.watch(
      queueControllerProvider.select((q) => q.isNotEmpty),
    );
    return QueueCommands(
      child: WaxScaffold(
        title: WaxPanel.queue.title,
        largeTitle: false,
        onBack: () => context.leave(),
        semanticsId: SemanticsIds.queueScreen,
        actions: <Widget>[
          if (queued)
            WaxIconButton(
              glyph: WaxIcons.delete,
              label: 'Clear queue',
              onPressed: ref.read(queueControllerProvider.notifier).clear,
              semanticsId: SemanticsIds.queueClear,
            ),
        ],
        slivers: queueSlivers(context, ref),
      ),
    );
  }
}
