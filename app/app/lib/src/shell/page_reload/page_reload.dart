/// Platform switch for reloading the running client.
///
/// The web build is served from the same binary as the API, so an
/// upgraded server means an upgraded bundle one reload away. A native
/// client cannot fetch itself, so it says so instead.
library;

export 'page_reload_stub.dart'
    if (dart.library.js_interop) 'page_reload_web.dart';
