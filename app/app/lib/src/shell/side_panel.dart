import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../queue/queue_panel.dart';

/// What the shell's right panel is showing.
///
/// One panel at a time, named rather than stacked: the panel is a place
/// to keep one thing open beside the page, and two of them would be a
/// second navigation to reason about. Lyrics and the remote session join
/// this list when those surfaces exist.
enum WaxPanel {
  queue('Queue');

  const WaxPanel(this.title);

  /// Names the panel in its header and to assistive tech.
  final String title;
}

/// Which panel is open, or none.
///
/// Shell state rather than a per-screen one: the panel outlives every
/// destination, so opening the queue and walking to another tab leaves
/// it open, which is the whole reason a wide window has one.
class SidePanelController extends Notifier<WaxPanel?> {
  @override
  WaxPanel? build() => null;

  /// Opens [panel], or closes it when it is already the one showing:
  /// the control that opened it is the control that closes it.
  void toggle(WaxPanel panel) => state = state == panel ? null : panel;

  void close() => state = null;
}

final sidePanelProvider = NotifierProvider<SidePanelController, WaxPanel?>(
  SidePanelController.new,
);

/// The shell's right panel: whichever surface is open, in the panel's
/// own chrome.
///
/// Returns null when nothing is open, which is what the frame wants:
/// there is no empty panel state, because a panel with nothing in it is
/// a stripe of surface with a close button.
Widget? shellSidePanel(WidgetRef ref) {
  final open = ref.watch(sidePanelProvider);
  return switch (open) {
    null => null,
    WaxPanel.queue => const QueuePanel(),
  };
}
