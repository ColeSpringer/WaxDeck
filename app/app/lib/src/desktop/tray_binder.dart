import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/now_playing_controller.dart';
import '../providers.dart';
import '../queue/queue_controller.dart';
import '../queue/queue_persistence.dart';
import '../radio/radio_controller.dart';
import 'desktop_ports.dart';
import 'desktop_ports_io.dart'
    if (dart.library.js_interop) 'desktop_ports_stub.dart';
import 'mini_window.dart';

final trayPortProvider = Provider<TrayPort>((ref) => createTrayPort());

/// Puts WaxDeck in the system tray and keeps the icon and its menu
/// saying what is true.
///
/// The tray is the surface for an app that is not on screen, so it is
/// bound to the *container* rather than to a widget: it has to keep
/// working while the window is minimized, and it survives being on a
/// desktop that has no tray to put it in, where installing simply
/// answers false and nothing else here runs.
class TrayBinder {
  TrayBinder(this._tray);

  final TrayPort _tray;

  bool _installed = false;
  TrayFace? _drawn;

  Future<void> install(TrayActions actions) async {
    _installed = await _tray.install(actions);
    final face = _drawn;
    // Anything published while the platform was still answering is
    // applied now rather than lost.
    if (_installed && face != null) await _tray.update(face);
  }

  void show(TrayFace face) {
    if (_same(face, _drawn)) return;
    _drawn = face;
    if (_installed) unawaited(_tray.update(face));
  }

  Future<void> dispose() => _tray.remove();

  /// Everything the icon, tooltip and menu are drawn from. The subtitle
  /// counts (the tooltip uses it, so two same-titled tracks by different
  /// artists would go stale); the position does not, because a tray menu
  /// redrawn several times a second flickers shut under the pointer.
  bool _same(TrayFace a, TrayFace? b) =>
      b != null &&
      a.playing == b.playing &&
      a.title == b.title &&
      a.subtitle == b.subtitle &&
      a.canStep == b.canStep;
}

/// Binds the tray to the signed-in session.
///
/// Signed in, because everything the menu offers is playback: a tray
/// icon over a login screen would be four rows that do nothing and a
/// Quit.
final trayBinderProvider = Provider.autoDispose<TrayBinder>((ref) {
  final binder = TrayBinder(ref.watch(trayPortProvider));
  final window = ref.read(miniWindowPortProvider);

  /// Leaving for good: stop what is playing, and get the queue's last
  /// edit onto the disk before the process goes.
  ///
  /// Both, and together rather than in turn. The stop finalizes the
  /// checkpoint, the listen report and the session Connect is
  /// advertising; the flush writes the queue the next launch offers to
  /// resume. They share no state, so serializing them buys nothing but
  /// latency - and under a budget it buys worse than nothing: a server
  /// that has stopped answering would spend the whole of it on the stop
  /// and the local write would never run, which is the failure this is
  /// here to prevent.
  ///
  /// Unbounded and non-quitting on purpose. The window layer holds the
  /// budget and ends the process, because it is the one that has to
  /// answer for a close that cannot complete; this is the finalizing
  /// half alone, and every caller reaches it through that close.
  Future<void> shutdown() async {
    try {
      await Future.wait(<Future<void>>[
        ref.read(nowPlayingProvider.notifier).goingAway(),
        ref.read(queuePersistenceProvider).flush(),
      ]);
    } on Object catch (failure) {
      debugPrint('shutdown did not finish cleanly: $failure');
    }
  }

  unawaited(
    binder.install(
      TrayActions(
        // The same verb the space bar and the deck bar's button run. A
        // tray that toggled the engine directly would miss the station
        // case, where play and pause mean stop and start.
        onPlayPause: () =>
            ref.read(nowPlayingProvider.notifier).togglePlayback(),
        onNext: () => unawaited(ref.read(nowPlayingProvider.notifier).next()),
        onPrevious: () =>
            unawaited(ref.read(nowPlayingProvider.notifier).previous()),
        onShow: () => unawaited(window.show()),
        // The window's close, not a shutdown of its own: with a
        // handler bound, quitting asks the platform to close, which
        // runs the finalize under the window's budget and destroys
        // once. Two ways of saying the same thing, one path.
        onQuit: () => unawaited(window.quit()),
      ),
    ),
  );

  // The window's own close, which until now meant nothing to playback:
  // the tray keeps the process alive after the X, so the music played
  // on out of a window the listener had closed. Bound here rather than
  // in the port because the verbs are the app's - and beside the tray's
  // Quit because they are the same gesture said two ways, so they run
  // the same thing.
  unawaited(window.bindClose(shutdown));

  // This binder is scoped to the signed-in session, and the closure it
  // just bound holds a ref into it. Signing out leaves a window whose
  // close would finalize a session that no longer exists.
  ref.onDispose(() => unawaited(window.unbindClose()));

  void publish() {
    final station = ref.read(radioPlaybackProvider).station;
    final now = ref.read(nowPlayingProvider);
    final engine = ref.read(audioEngineProvider);
    binder.show(
      TrayFace(
        playing: engine.playing,
        title: station?.name ?? now.item?.title,
        subtitle: station == null ? now.item?.artist : null,
        // Radio never queues, so there is nothing to step to; an item
        // needs a queue with somewhere to go.
        canStep:
            station == null && ref.read(queueControllerProvider).length > 1,
      ),
    );
  }

  ref.listen(radioPlaybackProvider, (_, _) => publish());
  ref.listen(nowPlayingProvider, (_, _) => publish());
  ref.listen(queueControllerProvider, (_, _) => publish());
  // The engine is not a provider, so its transport is followed directly:
  // a pause has to change the glyph, and nothing above emits for one.
  final playing = ref
      .read(audioEngineProvider)
      .playingStream
      .listen((_) => publish());
  publish();
  ref.onDispose(() {
    unawaited(playing.cancel());
    unawaited(binder.dispose());
  });
  return binder;
});
