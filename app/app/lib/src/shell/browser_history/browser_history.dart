/// Platform switch for the browser's own session history.
///
/// On web the browser keeps a list of where the visitor went, and its
/// buttons walk it, so back in the app walks the same list rather than
/// adding to it. A native client has no such list: its history is the
/// app's own.
library;

export 'browser_history_stub.dart'
    if (dart.library.js_interop) 'browser_history_web.dart';
