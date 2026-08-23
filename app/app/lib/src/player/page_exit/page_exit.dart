/// What playback does when the browser is taking the document away.
///
/// Native builds close a window and get a close handler; a browser tab
/// gets neither. The document dies, the audio element with it, and
/// every async call in flight is abandoned - including the checkpoint
/// and the listen report that tell the server this session ended. What
/// survives is the server's stale picture of it, which is what the
/// resume dock is fed from, so coming back offered the wrong thing at
/// the wrong position.
///
/// The fix is not "run the same code faster". Nothing ordinary
/// completes in `pagehide`: the answer is a request the browser
/// promises to deliver whether or not the page lives to see it -
/// `fetch(keepalive: true)`, which unlike `sendBeacon` can carry the
/// CSRF header a cookie-authenticated mutation needs.
///
/// Native builds get the no-op half of this switch. Their answer to the
/// same question is the desktop close handler and Android's
/// `onTaskRemoved`, both of which run ordinary code with time to spare.
library;

export 'page_exit_stub.dart' if (dart.library.js_interop) 'page_exit_web.dart';
