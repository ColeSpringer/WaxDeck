/// The desktop shell over `window_manager` and `tray_manager`.
///
/// The only file that names either plugin. Everything here is best
/// effort by construction: a compositor may refuse any of it, and the
/// app that asked has to keep running either way.
library;

import 'dart:io';
import 'dart:ui' show Brightness, PlatformDispatcher, Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_ports.dart';

/// Sets the window plugin up before the first frame. A no-op off the
/// desktops, and called from `main` because that is where the plugin
/// wants to be told the window exists.
void ensureDesktopWindowInitialized() {
  if (!_isDesktop) return;
  // Not awaited: the channel call is what registers the plugin's own
  // observers, and nothing before the first frame depends on the answer.
  windowManager
      .ensureInitialized()
      // Set from the first frame, so leaving the mini window restores a
      // floor that was already true.
      .then((_) => windowManager.setMinimumSize(_ordinaryMinimum))
      .catchError((Object failure) {
        debugPrint('window manager unavailable: $failure');
      });
}

const Size _ordinaryMinimum = Size(kMinimumWindowWidth, kMinimumWindowHeight);

MiniWindowPort createMiniWindowPort() =>
    _isDesktop ? PluginMiniWindow() : const NoMiniWindow();

TrayPort createTrayPort() => _isDesktop ? PluginTray() : const NoTray();

bool get _isDesktop => Platform.isLinux || Platform.isWindows;

/// Whether this Linux session is Wayland.
///
/// The compositor decides framing, stacking and placement there, and it
/// mostly decides no: a client that asks to be frameless and on top gets
/// a window that is neither, sometimes after a visible flicker. Read from
/// the environment rather than attempted, because the attempt is the part
/// that looks broken.
bool get _isWayland =>
    Platform.isLinux &&
    (Platform.environment['XDG_SESSION_TYPE'] == 'wayland' ||
        (Platform.environment['WAYLAND_DISPLAY']?.isNotEmpty ?? false));

/// The mini window over `window_manager`.
class PluginMiniWindow with WindowListener implements MiniWindowPort {
  /// Where the window stood before it shrank, so leaving is a restore
  /// rather than a guess. Held rather than recomputed: a mini window
  /// that came back at a default size and position would move a window
  /// somebody had placed.
  Rect? _restore;

  bool _wasResizable = true;

  @override
  Future<MiniWindowCapabilities> probe() async {
    if (!_isDesktop) return MiniWindowCapabilities.none;
    final compositorDecides = _isWayland;
    return MiniWindowCapabilities(
      available: true,
      frameless: !compositorDecides,
      alwaysOnTop: !compositorDecides,
    );
  }

  @override
  Future<void> enter(MiniWindowCapabilities capabilities) async {
    if (!capabilities.available) return;
    try {
      _restore = await windowManager.getBounds();
      _wasResizable = await windowManager.isResizable();
      // The minimum first: a window whose minimum is larger than the
      // size being set silently keeps the larger one, and the app's own
      // minimum is a full-size shell's.
      await windowManager.setMinimumSize(
        const Size(kMiniWindowWidth, kMiniWindowHeight),
      );
      await windowManager.setSize(
        const Size(kMiniWindowWidth, kMiniWindowHeight),
      );
      // Fixed at the mini size: the player inside it is laid out for one
      // shape, and a listener who dragged it to 900 pixels wide would be
      // looking at a stripe.
      await windowManager.setResizable(false);
      if (capabilities.frameless) {
        await windowManager.setAsFrameless();
      }
      if (capabilities.alwaysOnTop) {
        await windowManager.setAlwaysOnTop(true);
      }
    } on Object catch (failure) {
      // Half applied is the state to expect here, and it is survivable:
      // the app is showing the mini player either way, and leaving puts
      // back everything it can.
      debugPrint('mini window not fully applied: $failure');
    }
  }

  @override
  Future<void> leave() async {
    try {
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      // The app's floor, not zero: entering lowered it to get under it.
      await windowManager.setMinimumSize(_ordinaryMinimum);
      await windowManager.setResizable(_wasResizable);
      final restore = _restore;
      if (restore != null) await windowManager.setBounds(restore);
      _restore = null;
    } on Object catch (failure) {
      debugPrint('window not fully restored: $failure');
    }
  }

  @override
  Future<void> show() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } on Object catch (failure) {
      debugPrint('window would not come forward: $failure');
    }
  }

  @override
  Future<void> startDragging() async {
    try {
      await windowManager.startDragging();
    } on Object catch (failure) {
      debugPrint('window would not be dragged: $failure');
    }
  }

  /// Ends the process, through whatever finalization is bound.
  ///
  /// Two routes, and which one runs is decided by whether anything is
  /// still waiting to finalize. With a close handler bound, this asks
  /// the platform to close, which is the same gesture as the window's
  /// X and lands in [onWindowClose] - so the tray's Quit and the X
  /// share one budget, one finalize and one destroy rather than each
  /// growing its own. Once that has run (or where nothing bound one),
  /// `destroy` is the end: `close` on a window that no longer prevents
  /// it is the same thing with a round trip in front.
  @override
  Future<void> quit() async {
    try {
      if (_onClose != null) {
        await windowManager.close();
        return;
      }
      await windowManager.destroy();
    } on Object catch (failure) {
      debugPrint('window would not close: $failure');
    }
  }

  /// What the close runs before the process goes. Null until bound,
  /// and null again once it has run: [onWindowClose] takes it before
  /// calling it, so the `destroy` underneath does not try to finalize a
  /// session that has already let go.
  Future<void> Function()? _onClose;

  /// Whether this port has installed itself as a window listener.
  ///
  /// `WindowManager.addListener` is a bare add on an `ObserverList` with
  /// no dedupe, and the binder that calls [bindClose] is scoped to the
  /// signed-in session: signing out and back in would otherwise leave
  /// two listeners, the second of which would reach `destroy` while the
  /// first was still finalizing.
  bool _listening = false;

  /// How long the app gets to finalize before the window closes anyway.
  ///
  /// The work behind it is a checkpoint and a listen report, both a
  /// single round trip; this is well past a slow one and well short of
  /// a window that will not shut. A close nobody can complete is a
  /// worse failure than a checkpoint that did not land, because the
  /// listener is already trying to leave.
  static const Duration _closeBudget = Duration(seconds: 3);

  @override
  Future<void> bindClose(Future<void> Function() onClose) async {
    if (!_isDesktop) return;
    // Rebinding replaces the handler and nothing else: a second sign-in
    // has a new session to finalize, and the listener that was added
    // for the first one is the one that will hear the close.
    _onClose = onClose;
    if (_listening) return;
    try {
      // Both halves: the listener is where the app is told, and
      // preventClose is what stops the platform closing the window out
      // from under it first.
      windowManager.addListener(this);
      _listening = true;
      await windowManager.setPreventClose(true);
    } on Object catch (failure) {
      // Unbound is the old behaviour - the window closes and the
      // process lives on in the tray - rather than a broken one.
      debugPrint('close handler not installed: $failure');
      _onClose = null;
      windowManager.removeListener(this);
      _listening = false;
    }
  }

  @override
  Future<void> unbindClose() async {
    _onClose = null;
  }

  @override
  Future<void> onWindowClose() async {
    final onClose = _onClose;
    // Taken rather than read: `destroy` below is the platform's close
    // again, and a `timeout` does not cancel what it gave up on, so a
    // handler that hangs is still running when the next close arrives.
    // Nulled here, this window finalizes once however many closes it is
    // asked for.
    _onClose = null;
    if (onClose != null) {
      try {
        await onClose().timeout(_closeBudget);
      } on Object catch (failure) {
        debugPrint('close handler did not finish: $failure');
      }
    }
    // Straight to `destroy`, not through `quit`: with the handler taken
    // there is nothing left to finalize, and `close` from inside a
    // close is a round trip to the same place.
    try {
      await windowManager.destroy();
    } on Object catch (failure) {
      debugPrint('window would not close: $failure');
    }
  }
}

/// The tray over `tray_manager`.
///
/// The menu is rebuilt on every update rather than mutated, because the
/// plugin has no row-level edit: the labels change with what is playing
/// ("Pause" against "Play"), and a stale row is a control that lies.
class PluginTray with TrayListener implements TrayPort {
  TrayActions? _actions;
  bool _installed = false;
  TrayFace _face = const TrayFace(playing: false);

  @override
  Future<bool> install(TrayActions actions) async {
    if (!_isDesktop) return false;
    _actions = actions;
    try {
      trayManager.addListener(this);
      await _draw(_face);
      _installed = true;
      return true;
    } on Object catch (failure) {
      // A session with no StatusNotifier host, or a desktop that refused
      // the icon. The feature is absent, which is what the plan asks
      // for: nothing else in the app depends on it.
      debugPrint('no system tray here: $failure');
      trayManager.removeListener(this);
      return false;
    }
  }

  @override
  Future<void> update(TrayFace face) async {
    _face = face;
    if (!_installed) return;
    try {
      await _draw(face);
    } on Object catch (failure) {
      debugPrint('tray not updated: $failure');
    }
  }

  @override
  Future<void> remove() async {
    if (!_installed) return;
    _installed = false;
    trayManager.removeListener(this);
    try {
      await trayManager.destroy();
    } on Object catch (failure) {
      debugPrint('tray not removed: $failure');
    }
  }

  Future<void> _draw(TrayFace face) async {
    final state = face.playing ? 'playing' : 'paused';
    await trayManager.setIcon('assets/tray/$state${_iconSuffix()}.png');
    await trayManager.setToolTip(
      face.title == null
          ? 'WaxDeck'
          : <String>[
              face.title!,
              if (face.subtitle != null) face.subtitle!,
            ].join(' - '),
    );
    await trayManager.setContextMenu(_menu(face));
  }

  /// Linux takes the mark's own colour; Windows picks neither light nor
  /// dark for the app, so the app must, and choosing wrong is a
  /// near-white mark on a near-white taskbar.
  ///
  /// Brightness is an approximation there - Windows themes apps and the
  /// taskbar separately and this reports the app's - but it agrees for
  /// anyone who has not split them, and needs no plugin.
  String _iconSuffix() {
    if (!Platform.isWindows) return '';
    // Named for the taskbar they suit: `-dark` is the light-inked mark.
    return PlatformDispatcher.instance.platformBrightness == Brightness.dark
        ? '-dark'
        : '-light';
  }

  /// English until this port learns a locale: a tray menu is drawn by
  /// the operating system from outside the element tree, so there is no
  /// `BuildContext` to read one through. Deferred with the media-session
  /// strings it belongs beside.
  Menu _menu(TrayFace face) {
    final actions = _actions;
    return Menu(
      items: <MenuItem>[
        if (face.title != null) ...<MenuItem>[
          MenuItem(key: 'now-playing', label: face.title, disabled: true),
          MenuItem.separator(),
        ],
        MenuItem(
          key: 'play-pause',
          label: face.playing ? 'Pause' : 'Play',
          onClick: (_) => actions?.onPlayPause(),
        ),
        MenuItem(
          key: 'previous',
          label: 'Previous',
          disabled: !face.canStep,
          onClick: (_) => actions?.onPrevious(),
        ),
        MenuItem(
          key: 'next',
          label: 'Next',
          disabled: !face.canStep,
          onClick: (_) => actions?.onNext(),
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'show',
          label: 'Show WaxDeck',
          onClick: (_) => actions?.onShow(),
        ),
        MenuItem(key: 'quit', label: 'Quit', onClick: (_) => actions?.onQuit()),
      ],
    );
  }

  /// A left click is "show me the app" on Windows and Linux.
  @override
  void onTrayIconMouseDown() => _actions?.onShow();

  /// A right click is the menu everywhere that does not do it for us.
  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }
}
