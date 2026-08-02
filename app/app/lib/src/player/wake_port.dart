import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// Whether the screen is allowed to sleep.
///
/// The wrapping rule (`wakelock_plus` never appears above this line).
/// Two surfaces need it and both need it for the same reason: a screen
/// that dims mid-drive or mid-record is a control nobody can reach and a
/// picture nobody is watching.
///
/// Deliberately not a claim count: counting is the caller's problem and
/// [WakeLock] solves it once, so a platform implementation stays the one
/// call it is.
abstract interface class WakePort {
  /// Holds the screen awake, or lets it go. Best effort: a platform that
  /// refuses is a screen that dims, not an error anybody can act on.
  Future<void> keepAwake(bool on);
}

/// The port over `wakelock_plus`.
class PluginWake implements WakePort {
  const PluginWake();

  @override
  Future<void> keepAwake(bool on) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } on Object {
      // Every platform this ships on can refuse: a browser wants a user
      // gesture and revokes the lock when the tab is hidden, a Linux
      // session may have no inhibitor to talk to. The surface is worth
      // showing either way, so a refusal costs the screen staying on and
      // nothing else.
    }
  }
}

/// The port where nothing can hold the screen.
///
/// Not a platform today, and here so a test can drive the surfaces that
/// ask without a plugin channel underneath them.
class NoWake implements WakePort {
  const NoWake();

  @override
  Future<void> keepAwake(bool on) async {}
}

final wakePortProvider = Provider<WakePort>((ref) => const PluginWake());

/// Who has taken the screen.
///
/// A count, because the two surfaces that ask can stand at once - the
/// visualizer opened over car mode - and the first one to leave must not
/// turn the screen off under the other.
///
/// [held] is read as well as written. Holding the screen awake and
/// having taken over the screen are the same fact here, and the idle
/// watcher reads it to decide it has nothing to do: a machine already
/// showing the visualizer is not a machine to open the visualizer on.
/// Anything new that takes this lock is saying it owns the screen, which
/// is the contract to keep rather than a coincidence to work around.
///
/// A plain object behind a `Provider` rather than a notifier holding
/// Riverpod state, and that is not a style choice: the claims are taken
/// and released from `initState` and `dispose`, where moving a
/// provider's state is forbidden outright. What changes here is one
/// widget-tree-free counter and a [ValueNotifier] beside it.
class WakeLock {
  WakeLock(this._port);

  final WakePort _port;

  final ValueNotifier<bool> held = ValueNotifier(false);

  int _claims = 0;

  void hold() {
    _claims++;
    if (_claims == 1) _apply(true);
  }

  void letGo() {
    if (_claims == 0) return;
    _claims--;
    if (_claims == 0) _apply(false);
  }

  /// Lets the screen go whatever is still holding it, for a container
  /// being torn down: a surface disposed with the app around it would
  /// otherwise leave the screen pinned awake for the rest of the
  /// process.
  void dispose() {
    if (_claims > 0) {
      _claims = 0;
      _apply(false);
    }
    held.dispose();
  }

  void _apply(bool on) {
    held.value = on;
    unawaited(_port.keepAwake(on));
  }
}

final wakeLockProvider = Provider<WakeLock>((ref) {
  final lock = WakeLock(ref.watch(wakePortProvider));
  ref.onDispose(lock.dispose);
  return lock;
});

/// Holds the screen awake for as long as it is mounted.
///
/// A widget rather than a call pair, so the release is owned by the same
/// thing that owns the acquire: every way out of car mode - the exit
/// button, the system back gesture, a route the sleep timer took - is a
/// dispose, and none of them has to remember.
class KeepAwake extends ConsumerStatefulWidget {
  const KeepAwake({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<KeepAwake> createState() => _KeepAwakeState();
}

class _KeepAwakeState extends ConsumerState<KeepAwake> {
  /// Held in a field rather than read where it is used: `ref` is unsafe
  /// from `dispose`, and letting go is exactly what has to happen there.
  /// The lock outlives this widget, which is the point of the count.
  late final WakeLock _lock = ref.read(wakeLockProvider);

  @override
  void initState() {
    super.initState();
    _lock.hold();
  }

  @override
  void dispose() {
    _lock.letGo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
