/// Where the browser's document lifecycle reaches playback.
///
/// What it carries is the repository's own [ExitRequest], not a shape
/// of this port's: that is already a whole request built while the page
/// was alive - path, method, headers, encoded body - because there is
/// no "later" in `pagehide` to shape one in. A copy here would be a
/// second spelling of the same four fields, remapped at the binder and
/// free to drift from what the client actually sends.
library;

import 'package:waxdeck_api/waxdeck_api.dart';

// Re-exported: this port's whole vocabulary is the request, and a
// consumer of the conditional export should not have to know which
// package it came from.
export 'package:waxdeck_api/waxdeck_api.dart' show ExitRequest;

/// Where the document's own lifecycle reaches playback.
abstract interface class PageExitPort {
  /// Registers what to send as the page goes.
  ///
  /// [onExit] is asked at `pagehide`, which is the browser's own "this
  /// document is done" - a close, a navigation away, a reload. What it
  /// returns is the end of the session.
  ///
  /// [onHidden] is asked at `visibilitychange` to hidden, which is not
  /// an ending: a tab switch, a phone locking. It exists because a
  /// mobile browser may discard a backgrounded tab without ever firing
  /// `pagehide`, so this is the last chance to say where the listener
  /// had got to. It reports a position and never stops anything, and it
  /// is throttled, because switching tabs is something people do
  /// constantly.
  ///
  /// Both are called synchronously and must not await: the document may
  /// be gone before a microtask would run.
  void bind({
    required List<ExitRequest> Function() onExit,
    required List<ExitRequest> Function() onHidden,
  });

  /// Stops listening. Native builds have nothing to stop.
  void dispose();
}
