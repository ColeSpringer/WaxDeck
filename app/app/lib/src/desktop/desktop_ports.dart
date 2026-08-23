/// The two desktop shell surfaces WaxDeck owns: the mini window and the
/// tray.
///
/// Both are wrapped rather than called (`window_manager` and
/// `tray_manager` never appear above this line), and both are allowed to
/// do less than they were asked. That is not defensive coding: a Wayland
/// compositor decides for itself whether a window may be frameless, sit
/// above others, or be put where the app wants it, and a Linux session
/// with no StatusNotifier host has nowhere to put a tray icon at all. The
/// ports say what they can do first and the app asks for that, so the
/// failure mode is a plain small window rather than one that misbehaves.
library;

/// How small the mini player gets, in logical pixels. The design's own
/// figure: artwork, a title block, three transports and a progress
/// hairline, and nothing else.
const double kMiniWindowWidth = 320;
const double kMiniWindowHeight = 96;

/// How small the ordinary window may be dragged.
///
/// A number of its own because the mini window lowers the floor to get
/// under it and `window_manager` has no getter to restore from. Under
/// the compact breakpoint, so the phone-shaped layout is what draws.
const double kMinimumWindowWidth = 480;
const double kMinimumWindowHeight = 520;

/// What this session's window layer will actually do.
class MiniWindowCapabilities {
  const MiniWindowCapabilities({
    this.available = false,
    this.frameless = false,
    this.alwaysOnTop = false,
  });

  /// Nowhere to put a mini window: not a desktop, or the window layer
  /// would not answer.
  static const MiniWindowCapabilities none = MiniWindowCapabilities();

  /// Whether the app may shrink its window at all.
  final bool available;

  /// Whether the frame and title bar can be taken off. Refused under
  /// Wayland, where a client does not draw its own decorations by
  /// asking.
  final bool frameless;

  /// Whether the window can be kept above others. A compositor's call,
  /// and under Wayland the answer is no.
  final bool alwaysOnTop;
}

/// The app's window, for the one thing it does with it.
abstract interface class MiniWindowPort {
  /// What this platform will allow. Asked once and answered from the
  /// environment, not attempted and rolled back: a window that flickered
  /// frameless and back is worse than one that never tried.
  Future<MiniWindowCapabilities> probe();

  /// Shrinks the window to the mini player, within [capabilities].
  /// Remembers where the window was, so leaving puts it back.
  Future<void> enter(MiniWindowCapabilities capabilities);

  /// Restores the window the way it was found.
  Future<void> leave();

  /// Brings the window forward: the tray's "Show WaxDeck", and what a
  /// second launch of a single-instance app would want.
  Future<void> show();

  /// Hands the window to the system's own move loop, for a drag begun on
  /// the mini player's background. A frameless window has no title bar to
  /// grab, so without this it cannot be moved at all.
  Future<void> startDragging();

  /// Ends the app. The tray's Quit, which has to work from a menu that
  /// is not part of any window.
  Future<void> quit();

  /// Runs [onClose] when the window's own close is asked for, then ends
  /// the app.
  ///
  /// The window is what a listener presses to leave, and until this it
  /// meant nothing to playback: the tray plugin keeps the process alive
  /// after the X, so the music played on out of a window that was gone.
  /// A close is a stop, and a stop has state to finalize - the
  /// checkpoint, the listen report, the session Connect is advertising -
  /// so the app is given a chance to write it before the process goes.
  ///
  /// Bounded by the implementation rather than by the callback: a
  /// server that has stopped answering must not be able to hold a
  /// window open. Minimizing and losing focus are not this; only the
  /// close.
  Future<void> bindClose(Future<void> Function() onClose);

  /// Forgets whatever [bindClose] bound, for a binder going out of
  /// scope: the app signing out has no session to finalize, and a
  /// closure still holding a torn-down one is worse than no handler at
  /// all. The window keeps listening - what it heard is what stops
  /// meaning anything.
  Future<void> unbindClose();
}

/// What the tray icon says and what its menu offers.
class TrayFace {
  const TrayFace({
    required this.playing,
    this.title,
    this.subtitle,
    this.canStep = false,
  });

  /// Which glyph: the needle swings up while the music plays.
  final bool playing;

  /// What the tooltip says, and the disabled first row of the menu. Null
  /// when nothing is playing.
  final String? title;
  final String? subtitle;

  /// Whether next and previous mean anything. A station has nothing to
  /// step to, and an empty queue has nowhere to go.
  final bool canStep;
}

/// What the tray menu's rows do.
class TrayActions {
  const TrayActions({
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onShow,
    required this.onQuit,
  });

  final void Function() onPlayPause;
  final void Function() onNext;
  final void Function() onPrevious;
  final void Function() onShow;
  final void Function() onQuit;
}

/// The system tray, where the session has one.
abstract interface class TrayPort {
  /// Puts the icon in the tray. False where there is no tray to put it
  /// in, which is a session without a StatusNotifier host as much as it
  /// is a phone - and which is a feature that is absent rather than
  /// broken.
  Future<bool> install(TrayActions actions);

  /// Redraws the icon and its menu for [face].
  Future<void> update(TrayFace face);

  /// Takes the icon away.
  Future<void> remove();
}

/// The ports where there is no desktop shell: web, and both mobiles.
class NoMiniWindow implements MiniWindowPort {
  const NoMiniWindow();

  @override
  Future<MiniWindowCapabilities> probe() async => MiniWindowCapabilities.none;

  @override
  Future<void> enter(MiniWindowCapabilities capabilities) async {}

  @override
  Future<void> leave() async {}

  @override
  Future<void> show() async {}

  @override
  Future<void> startDragging() async {}

  @override
  Future<void> quit() async {}

  @override
  Future<void> bindClose(Future<void> Function() onClose) async {}

  @override
  Future<void> unbindClose() async {}
}

class NoTray implements TrayPort {
  const NoTray();

  @override
  Future<bool> install(TrayActions actions) async => false;

  @override
  Future<void> update(TrayFace face) async {}

  @override
  Future<void> remove() async {}
}
