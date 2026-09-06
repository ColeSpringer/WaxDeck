import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'now_playing_controller.dart';
import 'page_exit/page_exit.dart';

final pageExitPortProvider = Provider<PageExitPort>(
  (ref) => createPageExitPort(),
);

/// Tells the server this client is going away, on the one platform that
/// gets no chance to say so.
///
/// A closing window and a swiped-away task both run ordinary code with
/// time to finish; a closing browser tab runs none. The document dies
/// with the checkpoint and the listen report still in flight, so the
/// server kept believing the session was live - and the resume dock,
/// which is fed from exactly that, offered the wrong item at the wrong
/// position on the next visit.
///
/// Bound to the container rather than to a widget, for the same reason
/// the tray is: the tab can be closed from any screen, including none.
final pageExitBinderProvider = Provider.autoDispose<void>((ref) {
  final port = ref.watch(pageExitPortProvider);
  final repository = ref.read(repositoryProvider);

  /// The requests to send, read synchronously off whatever is playing.
  ///
  /// [ending] is what separates a closing document from a tab going
  /// hidden: the first ends the session and reports the listen, the
  /// second says where the listener stood and nothing more. A tab
  /// switch is not a stop, and treating it as one would end a listen
  /// every time somebody checked their mail.
  List<ExitRequest> beacons({required bool ending}) {
    final now = ref.read(nowPlayingProvider);
    // Read first and sent on its own if it has to be. A tab can hold a
    // rendering with nothing to check point beside it - the session
    // already reported, or the item went away while the stream played
    // on - and that release is the one thing here nothing else can do
    // later: the server counts this listener as listening until it
    // hears otherwise.
    //
    // Only on the way out, though. A tab going hidden is still
    // listening, and handing its rendering back would take the slot
    // from a listener who is about to switch straight back to it.
    final timelinePids = ending
        ? ref.read(nowPlayingProvider.notifier).heldTimelinePids
        : const <String>[];
    final session = now.session;
    final item = now.item;
    final report = session?.exitReport(ending: ending);
    if (item == null || report == null) {
      return repository.exitRequests(timelinePids: timelinePids);
    }
    return repository.exitRequests(
      pid: item.pid,
      positionMs: report.positionMs,
      listen: report.listen,
      timelinePids: timelinePids,
    );
  }

  port.bind(
    onExit: () => beacons(ending: true),
    onHidden: () => beacons(ending: false),
  );
  ref.onDispose(port.dispose);
});
