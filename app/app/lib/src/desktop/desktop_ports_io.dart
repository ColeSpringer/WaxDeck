/// The desktop shell over `window_manager` and `tray_manager`.
///
/// The only file that names either plugin. Everything here is best
/// effort by construction: a compositor may refuse any of it, and the
/// app that asked has to keep running either way.
library;

import 'dart:async';
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

/// The tray over `tray_manager`, which since its 0.6 is nativeapi's
/// `TrayIcon`, `Menu` and `MenuItem` re-exported.
///
/// One native icon and menu per [install], built once and edited in
/// place: every row is permanent - the title row too, which shows the
/// app's name when nothing plays - and labels and enabled states change
/// under the platform without incident. Nothing is added or removed
/// once built, because the Linux panel keeps raw pointers to the rows
/// it was last shown and asks about them until it re-reads the menu,
/// and on Windows the open menu is a modal loop inside the platform's
/// own code that is still reading the rows. The handles go in
/// [remove] and [dispose], both of which wait for the menu to close.
class PluginTray implements TrayPort {
  TrayActions? _actions;
  TrayFace _face = const TrayFace(playing: false);
  _TrayIcon? _live;
  bool _disposed = false;

  @override
  Future<bool> install(TrayActions actions) async {
    if (!_isDesktop || _disposed) return false;
    _actions = actions;
    try {
      final live = _live ?? _TrayIcon.create(actions: () => _actions);
      _live = live;
      live.draw(_face);
      live.show();
      return true;
    } on Object catch (failure) {
      // A desktop that refused the icon, or an asset that is not in
      // the bundle. The feature is absent, which is what the plan asks
      // for: nothing else in the app depends on it.
      debugPrint('no system tray here: $failure');
      _actions = null;
      final live = _live;
      _live = null;
      unawaited(live?.release());
      return false;
    }
  }

  @override
  Future<void> update(TrayFace face) async {
    _face = face;
    final live = _live;
    if (live == null) return;
    try {
      live.draw(face);
    } on Object catch (failure) {
      debugPrint('tray not updated: $failure');
    }
  }

  /// Hides the icon now and lets the platform have it back once its
  /// menu is closed. Released rather than kept for the next sign-in:
  /// a hidden icon stays listed in Plasma's hidden area with rows that
  /// do nothing, Windows cannot hide an icon it has moved to the
  /// overflow, and an icon still held when the process ends is torn
  /// down by the platform in an order of its own choosing.
  @override
  Future<void> remove() async {
    _actions = null;
    final live = _live;
    _live = null;
    if (live != null) await live.release();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await remove();
  }
}

/// The name the tray shows for the app: the tooltip and the title row
/// when nothing plays, and on KDE the item's name in the tray settings.
const String _appName = 'WaxDeck';

/// One installed icon: the native handles, the menu, and what they
/// were last drawn with.
class _TrayIcon {
  _TrayIcon._(this._icon, this._clicks, this._menu);

  final TrayIcon _icon;
  final ListenerId _clicks;
  final _TrayMenu _menu;
  String? _asset;

  static _TrayIcon create({required TrayActions? Function() actions}) {
    final icon = TrayIcon.create();
    if (icon == null) throw StateError('the platform gave no tray icon');
    try {
      // Linux publishes the menu over D-Bus for this trigger alone, and
      // its panels open it on any click and report none. Windows opens
      // it on a right click and reports a left one, which is "show me
      // the app".
      icon.setContextMenuTrigger(
        Platform.isLinux
            ? ContextMenuTrigger.clicked
            : ContextMenuTrigger.rightClicked,
      );
      // KDE names the item by this in the tray settings and heads the
      // tooltip with it, and drops the tooltip when it is empty.
      // Windows has no title and ignores it.
      icon.setTitle(_appName);
      final clicks = icon.addListener((event) {
        if (event is TrayIconClickedEvent) actions()?.onShow();
      });
      final menu = _TrayMenu(
        actions: actions,
        // Linux panels draw from a copy of the menu and re-read it only
        // when told, and attaching it again is what tells them. Windows
        // shows the native menu itself and takes this as a no-op.
        changed: icon.setContextMenu,
      );
      icon.setContextMenu(menu.menu);
      return _TrayIcon._(icon, clicks, menu);
    } on Object {
      icon.dispose();
      rethrow;
    }
  }

  void draw(TrayFace face) {
    final state = face.playing ? 'playing' : 'paused';
    final asset = 'assets/tray/$state${_iconSuffix()}.png';
    if (asset != _asset) {
      final image = ImageAsset.fromAsset(asset);
      if (image == null) throw StateError('no tray icon at $asset');
      _icon.icon = image;
      // The platform keeps its own reference once handed one.
      image.dispose();
      _asset = asset;
    }
    // Every draw, and after the image: Windows only re-sends an icon it
    // can locate on screen, which an icon in the overflow area is not,
    // and the tooltip's update is what re-sends it regardless.
    _icon.setTooltip(
      face.title == null
          ? _appName
          : <String>[
              face.title!,
              if (face.subtitle != null) face.subtitle!,
            ].join(' - '),
    );
    _menu.show(face);
  }

  void show() => _icon.setVisible(true);

  /// Hidden now; the handles go once the menu is closed. The icon last,
  /// since it is what holds the menu.
  Future<void> release() async {
    _icon.setVisible(false);
    _icon.removeListener(_clicks);
    await _menu.dispose();
    _icon.dispose();
  }

  /// Linux takes the mark's own colour; Windows picks neither light nor
  /// dark for the app, so the app must, and choosing wrong is a
  /// near-white mark on a near-white taskbar.
  ///
  /// Brightness is an approximation there - Windows themes apps and the
  /// taskbar separately and this reports the app's - but it agrees for
  /// anyone who has not split them, and needs no plugin.
  static String _iconSuffix() {
    if (!Platform.isWindows) return '';
    // Named for the taskbar they suit: `-dark` is the light-inked mark.
    return PlatformDispatcher.instance.platformBrightness == Brightness.dark
        ? '-dark'
        : '-light';
  }
}

/// The native menu and its rows, all of them built once and edited in
/// place; see [PluginTray] for why none is ever added or removed.
///
/// English until this port learns a locale: a tray menu is drawn by the
/// operating system from outside the element tree, so there is no
/// `BuildContext` to read one through. Deferred with the media-session
/// strings it belongs beside.
///
/// The one thing that waits is [dispose]: never on the turn that asked,
/// since a row's click runs inside that row's own native callback, and
/// not while the menu is open, since on Windows that is a modal loop
/// still reading the rows. Linux never opens the menu itself.
class _TrayMenu {
  _TrayMenu({required this.actions, required this.changed})
    : menu = Menu.create() ?? (throw StateError('the platform gave no menu')) {
    _events = menu.addListener((event) {
      switch (event) {
        case MenuOpenedEvent():
          _open = true;
        case MenuClosedEvent():
          _open = false;
          _later();
        default:
          break;
      }
    });
    _title = _row(enabled: false);
    menu.addSeparator();
    _playPause = _row(onClick: () => actions()?.onPlayPause());
    _previous = _row(label: 'Previous', onClick: () => actions()?.onPrevious());
    _next = _row(label: 'Next', onClick: () => actions()?.onNext());
    menu.addSeparator();
    _row(label: 'Show WaxDeck', onClick: () => actions()?.onShow());
    _row(label: 'Quit', onClick: () => actions()?.onQuit());
  }

  final TrayActions? Function() actions;

  /// Told after every change the menu takes, with the menu to re-attach.
  final void Function(Menu) changed;

  final Menu menu;
  late final ListenerId _events;
  late final MenuItem _title;
  late final MenuItem _playPause;
  late final MenuItem _previous;
  late final MenuItem _next;
  final List<(MenuItem, ListenerId?)> _rows = <(MenuItem, ListenerId?)>[];

  TrayFace? _shown;
  bool _open = false;
  Completer<void>? _disposing;

  void show(TrayFace face) {
    final was = _shown;
    _shown = face;
    var edited = false;
    if (was == null || was.title != face.title) {
      _relabel(_title, label: face.title ?? _appName);
      edited = true;
    }
    if (was == null || was.playing != face.playing) {
      _relabel(_playPause, label: face.playing ? 'Pause' : 'Play');
      edited = true;
    }
    if (was == null || was.canStep != face.canStep) {
      _previous.isEnabled = face.canStep;
      _next.isEnabled = face.canStep;
      edited = true;
    }
    if (edited) changed(menu);
  }

  /// Releases the rows and the menu, once the menu is closed and off
  /// the turn that asked.
  Future<void> dispose() {
    final done = _disposing ??= Completer<void>();
    _later();
    return done.future;
  }

  MenuItem _row({
    String? label,
    bool enabled = true,
    void Function()? onClick,
  }) {
    final item = MenuItem.createWithLabelAndType(
      _escapeLabel(label ?? ''),
      MenuItemType.normal,
    );
    if (item == null) throw StateError('the platform gave no menu row');
    item.isEnabled = enabled;
    final listener = onClick == null
        ? null
        : item.addListener((event) {
            if (event is MenuItemClickedEvent) onClick();
          });
    _rows.add((item, listener));
    menu.addItem(item);
    return item;
  }

  void _relabel(MenuItem item, {required String label}) {
    item.label = _escapeLabel(label);
  }

  void _later() => Timer.run(_sync);

  void _sync() {
    if (_open) return;
    final done = _disposing;
    if (done == null || done.isCompleted) return;
    for (final (item, listener) in _rows) {
      if (listener != null) item.removeListener(listener);
      item.dispose();
    }
    _rows.clear();
    menu.removeListener(_events);
    menu.dispose();
    done.complete();
  }
}

/// `&` on Windows and `_` on Linux mark an access key in a menu label;
/// doubled, they show as themselves.
String _escapeLabel(String label) => Platform.isWindows
    ? label.replaceAll('&', '&&')
    : label.replaceAll('_', '__');
