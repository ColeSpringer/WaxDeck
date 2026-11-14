/// Platform switch for hearing that the network came back.
///
/// A browser says so (its `online` event), and a socket waiting out its
/// backoff should try at once rather than up to a minute later. A native
/// client is told nothing; its sockets find out on their own.
library;

export 'network_back_stub.dart'
    if (dart.library.js_interop) 'network_back_web.dart';
