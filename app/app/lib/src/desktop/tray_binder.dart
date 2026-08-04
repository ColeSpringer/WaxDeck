import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/now_playing_controller.dart';
import '../providers.dart';
import '../queue/queue_controller.dart';
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
        onQuit: () => unawaited(window.quit()),
      ),
    ),
  );

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
