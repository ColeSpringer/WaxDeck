import 'dart:async';

import 'package:flutter/services.dart' show HardwareKeyboard, KeyEvent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../providers.dart';
import '../settings/client_prefs.dart';
import '../shell/routes.dart';
import 'now_playing_controller.dart';
import 'wake_port.dart';

/// Opens the visualizer on a desktop left alone with the music playing.
///
/// Off unless somebody asked for it, and desktop only: this is about a
/// machine on a shelf across a room, which a phone that locks its own
/// screen and a browser tab are not. Wrapped around the signed-in app so
/// every screen counts as somewhere to be left alone; the timer restarts
/// on any input at all, which is what makes "idle" mean idle rather than
/// "has not clicked a WaxDeck button".
///
/// The push is what opens it, so leaving the visualizer lands back where
/// the listener was rather than on a home screen they never asked for.
class IdleVisualizer extends ConsumerStatefulWidget {
  const IdleVisualizer({required this.child, super.key});

  final Widget child;

  /// How long a machine has to be left alone. Long enough that it never
  /// happens to somebody reading their own library, short enough to be
  /// the reason they turned it on.
  static const Duration after = Duration(minutes: 5);

  @override
  ConsumerState<IdleVisualizer> createState() => _IdleVisualizerState();
}

class _IdleVisualizerState extends ConsumerState<IdleVisualizer> {
  Timer? _idle;

  /// Whether the surface this opened is still standing. The push's own
  /// future says so exactly: it completes when the route is popped,
  /// however it was popped.
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _arm();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _idle?.cancel();
    super.dispose();
  }

  /// Never handles anything: this listens to the keyboard to know
  /// somebody is there, and every key belongs to whatever has focus.
  bool _onKey(KeyEvent event) {
    _arm();
    return false;
  }

  void _arm() {
    _idle?.cancel();
    _idle = Timer(IdleVisualizer.after, _fire);
  }

  Future<void> _fire() async {
    if (!mounted) return;
    // Re-armed rather than left stopped: the conditions below are about
    // this moment, and a machine that was paused when the timer fired is
    // one to check again after the next stretch of quiet.
    _arm();
    if (_opened) return;
    if (!ref.read(visualizerWhenIdleProvider)) return;
    if (!ref.read(desktopProvider)) return;
    // Already showing something that owns the screen: the visualizer
    // itself, or car mode. Nothing to open.
    if (ref.read(wakeLockProvider).held.value) return;
    // Playing, not merely queued. A machine left paused is a machine
    // somebody walked away from, and filling its screen with a still
    // waveform is a screensaver nobody asked for.
    final session = ref.read(nowPlayingProvider).session;
    if (session == null || !session.engine.playing) return;

    final router = GoRouter.of(context);
    _opened = true;
    try {
      await router.push<void>(WaxRoute.visualizer);
    } finally {
      _opened = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Behaviour left alone on purpose: this observes what reaches the
      // app rather than claiming it, so every control underneath keeps
      // its own gestures and this hears the pointer on the way past.
      onPointerDown: (_) => _arm(),
      onPointerMove: (_) => _arm(),
      onPointerHover: (_) => _arm(),
      onPointerSignal: (_) => _arm(),
      child: widget.child,
    );
  }
}
