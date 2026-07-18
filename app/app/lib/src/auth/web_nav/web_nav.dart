/// Platform switch for same-tab browser navigation: web builds assign
/// the page location directly, everything else refuses (native flows
/// open an external browser instead).
library;

export 'web_nav_stub.dart' if (dart.library.js_interop) 'web_nav_web.dart';
