import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'page_exit_port.dart';

export 'page_exit_port.dart';

PageExitPort createPageExitPort() => BrowserPageExit();

/// The browser half: `pagehide` for the ending, `visibilitychange` for
/// the tab that may not live to see one.
class BrowserPageExit implements PageExitPort {
  /// How often a hidden tab reports its position.
  ///
  /// Switching tabs is not an event, it is a habit, and a request per
  /// switch would be a checkpoint every few seconds from somebody
  /// working with the music on. The window is short enough that a tab
  /// the phone discards has said something recent and long enough that
  /// normal use costs nothing.
  static const Duration _hiddenThrottle = Duration(seconds: 20);

  DateTime? _lastHidden;
  JSFunction? _pagehide;
  JSFunction? _visibility;

  @override
  void bind({
    required List<ExitRequest> Function() onExit,
    required List<ExitRequest> Function() onHidden,
  }) {
    dispose();
    // `pagehide` rather than `beforeunload` or `unload`: the older two
    // are unreliable on mobile and, on iOS, may never fire at all. This
    // one is the event the platform actually promises, and it covers
    // the bfcache case a close does not.
    _pagehide = ((web.Event _) => _send(onExit())).toJS;
    web.window.addEventListener('pagehide', _pagehide);
    _visibility = ((web.Event _) {
      if (web.document.visibilityState != 'hidden') return;
      final now = DateTime.now();
      final last = _lastHidden;
      if (last != null && now.difference(last) < _hiddenThrottle) return;
      _lastHidden = now;
      _send(onHidden());
    }).toJS;
    web.document.addEventListener('visibilitychange', _visibility);
  }

  @override
  void dispose() {
    if (_pagehide case final handler?) {
      web.window.removeEventListener('pagehide', handler);
      _pagehide = null;
    }
    if (_visibility case final handler?) {
      web.document.removeEventListener('visibilitychange', handler);
      _visibility = null;
    }
  }

  /// Hands the requests to the browser and returns.
  ///
  /// `keepalive` is the whole mechanism: the request outlives the
  /// document that made it, which an ordinary `fetch` does not. The
  /// returned promise is deliberately dropped - there is nobody left to
  /// tell - and errors are swallowed for the same reason: a page that
  /// is closing has no way to report one and no way to retry.
  void _send(List<ExitRequest> requests) {
    for (final request in requests) {
      try {
        final headers = web.Headers();
        headers.set('Content-Type', 'application/json');
        for (final entry in request.headers.entries) {
          headers.set(entry.key, entry.value);
        }
        web.window.fetch(
          request.path.toJS,
          web.RequestInit(
            method: request.method,
            headers: headers,
            body: request.body.toJS,
            keepalive: true,
            // The session cookie is the credential on web, and a
            // same-origin fetch does not send one unless asked.
            credentials: 'include',
          ),
        );
      } on Object catch (failure) {
        // A browser that refuses keepalive (a body past its 64 KB
        // budget, an extension in the way) loses this report and
        // nothing else: the server still has the last periodic
        // checkpoint.
        debugPrint('exit beacon not sent: $failure');
      }
    }
  }
}
