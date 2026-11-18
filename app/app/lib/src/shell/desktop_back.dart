import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../desktop/mini_window.dart';
import '../providers.dart';
import 'commands.dart';
import 'router.dart';
import 'shortcuts.dart';

/// Binds above the router the keys of every command flagged
/// [WaxCommand.aboveRouter], and what a desktop's mouse means by back: its
/// back button, which runs [waxBackCommand], one of those commands where
/// the keys are offered.
///
/// Above the router rather than in the shell frame, because a dialog, and
/// what is opened on the root navigator (the palette, the shortcut sheet),
/// sits above the frame: a key or a click there would never reach it, and
/// closing that thing is the first thing back does. A sheet or a menu
/// opens on its page's navigator: under the frame for a screen in the
/// shell, on the signed-in navigator beside it for an overlay (the player,
/// the queue). Where the browser or the system owns back
/// ([desktopBackProvider]) neither back's keys nor the button are bound,
/// and nothing is while the mini window shows, which keeps the app
/// mounted out of sight.
class DesktopBack extends ConsumerWidget {
  const DesktopBack({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Bound to nothing rather than unwrapped, so the app beneath keeps
    // its place in the tree whatever comes to be bound.
    final desktop = ref.watch(desktopBackProvider);
    final small =
        desktop && ref.watch(miniWindowProvider.select((s) => s.showing));
    // Back's among them only where it is offered: on a desktop.
    final commands = ref.watch(commandRegistryProvider);

    void run(WaxCommand command) {
      // A command runs from a context under the router, as the palette's
      // does; this one is above it.
      final host = ref
          .read(routerProvider)
          .routerDelegate
          .navigatorKey
          .currentContext;
      if (host == null || !command.isEnabled(ref)) return;
      command.run(host, ref);
    }

    return AppShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        if (!small)
          for (final command in commands)
            if (command.aboveRouter)
              for (final activator in command.activators)
                activator: () => run(command),
      },
      autofocus: false,
      // Hears the press on its way past, over whatever is under it, and
      // claims nothing: a button down is one event, where a drag with it
      // held is many.
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if (desktop && !small && event.buttons & kBackMouseButton != 0) {
            run(waxBackCommand);
          }
        },
        child: child,
      ),
    );
  }
}
