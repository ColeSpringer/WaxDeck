import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Hands the browser's own context menu back everywhere the app does not
/// answer a secondary tap itself.
///
/// The web build used to switch the browser menu off once at startup,
/// because a card's right-click is its More menu and the browser's would
/// stack on top of it. That took copy, save image, and inspect away from
/// the whole page to serve the few surfaces that answer - so right-click
/// did nothing at all on text, on artwork, and on empty space.
///
/// This inverts it: the menu is on by default, and a surface that
/// answers secondary tap wraps itself in one of these to switch it off
/// while the pointer is inside. Suppression then follows exactly the
/// surfaces that have something of their own to show, and is the same on
/// every platform - off the web this is a plain pass-through, because
/// there is no browser menu to argue with.
///
/// Pointer-driven, and so mouse and stylus only: Flutter's mouse tracker
/// does not raise enter and exit for a touch. The other half of a
/// surface's suppression is [waxWithoutBrowserMenu], which the menu
/// itself holds and which covers every device - that is what a long
/// press on a touchscreen actually relies on.
class WaxSecondaryTapRegion extends StatefulWidget {
  const WaxSecondaryTapRegion({
    required this.child,
    this.enabled = true,
    super.key,
  });

  final Widget child;

  /// Whether this surface actually answers a secondary tap. False draws
  /// the child untouched, so a row without a menu leaves the browser's
  /// alone even while the pointer is over it.
  final bool enabled;

  @override
  State<WaxSecondaryTapRegion> createState() => _WaxSecondaryTapRegionState();
}

class _WaxSecondaryTapRegionState extends State<WaxSecondaryTapRegion> {
  bool _inside = false;

  @override
  void didUpdateWidget(WaxSecondaryTapRegion old) {
    super.didUpdateWidget(old);
    // A row that loses its menu while the pointer is resting on it has
    // to let go, or the browser menu stays off under a surface with
    // nothing to offer.
    if (!widget.enabled) _exit();
  }

  @override
  void dispose() {
    // Scrolling unmounts rows out from under the pointer, and an exit
    // event never arrives for one that is already gone.
    _exit();
    super.dispose();
  }

  void _enter() {
    if (_inside) return;
    _inside = true;
    _BrowserMenu.enter();
  }

  void _exit() {
    if (!_inside) return;
    _inside = false;
    _BrowserMenu.leave();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    // The web check is one layer down, on the platform call rather than
    // here: the counting is what the behaviour is, and gating the
    // annotation would leave it untestable anywhere a browser suite
    // cannot run. The region itself costs nothing off the web - both
    // widgets already annotate for hover.
    return MouseRegion(
      onEnter: (_) => _enter(),
      onExit: (_) => _exit(),
      child: widget.child,
    );
  }
}

/// The browser menu's on/off switch, counted rather than toggled.
///
/// Regions nest and abut - a card inside a shelf, one row's box touching
/// the next - so entering the second before leaving the first is
/// ordinary, and a plain boolean would be switched back on by the exit
/// that follows. The depth is what the menu's state is read from, and
/// the platform channel is asked only when the two disagree.
///
/// The calls are asynchronous, so they are drained one at a time: two
/// racing calls can land in either order, and the loser would leave the
/// menu in the state the pointer had already left behind.
abstract final class _BrowserMenu {
  static int _depth = 0;
  static bool _suppressed = false;
  static bool _draining = false;

  static void enter() {
    _depth++;
    _sync();
  }

  static void leave() {
    if (_depth > 0) _depth--;
    _sync();
  }

  static void _sync() {
    if (_draining) return;
    _draining = true;
    unawaited(_drain());
  }

  static Future<void> _drain() async {
    try {
      // Re-read the depth after every await: the pointer moves while a
      // call is in flight, and the last state asked for is the one that
      // has to win.
      while (_suppressed != (_depth > 0)) {
        final suppress = _depth > 0;
        if (kIsWeb) {
          try {
            await (suppress
                ? BrowserContextMenu.disableContextMenu()
                : BrowserContextMenu.enableContextMenu());
          } catch (_) {
            // The channel refused, so the menu is not in the state this
            // asked for and `_suppressed` must not claim otherwise.
            // Giving up on this drain rather than trying again is what
            // stops a channel that always refuses from spinning here;
            // the next enter or leave re-reads the disagreement and asks
            // once more. A browser menu is not worth an error either
            // side of it, which is why nothing is rethrown into the
            // unawaited future this runs in.
            break;
          }
        }
        _suppressed = suppress;
      }
    } finally {
      _draining = false;
    }
  }

  /// Test-only: what the switch believes, and how many regions hold it.
  @visibleForTesting
  static (int depth, bool suppressed) get debugState => (_depth, _suppressed);

  /// Test-only: forgets every held region, so one test's leftovers
  /// cannot decide the next one's assertions.
  @visibleForTesting
  static void debugReset() {
    _depth = 0;
    _suppressed = false;
    _draining = false;
  }
}

/// Holds the browser's menu off for as long as [body] is running, on top
/// of whatever the pointer is already holding.
///
/// A menu of WaxDeck's own is a route, and a route raises a modal
/// barrier - which is an opaque [MouseRegion] covering the screen. The
/// surface under the pointer is told the pointer left the instant the
/// barrier goes up, so the region that suppressed the browser menu lets
/// go while WaxDeck's menu is still on screen, and a second secondary
/// tap stacks the browser's on top of it. That is the exact pairing
/// [WaxSecondaryTapRegion] exists to prevent, so the surface raising the
/// menu holds the switch across it.
///
/// It also covers the gesture a [MouseRegion] cannot see at all: a long
/// press is a touch, and touch pointers never enter or exit one.
Future<T> waxWithoutBrowserMenu<T>(Future<T> Function() body) async {
  _BrowserMenu.enter();
  try {
    return await body();
  } finally {
    _BrowserMenu.leave();
  }
}

/// Test-only view of the browser-menu switch.
@visibleForTesting
(int depth, bool suppressed) get debugBrowserMenuState =>
    _BrowserMenu.debugState;

/// Test-only reset of the browser-menu switch.
@visibleForTesting
void debugResetBrowserMenu() => _BrowserMenu.debugReset();
