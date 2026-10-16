/// What one look at a stream URL found, behind the engine's fault
/// classification.
///
/// The conditional export keeps `dart:io` out of web builds; the web
/// half asks through a same-origin fetch, so a URL on another origin
/// reads [StreamProbe.unreachable] and the element's own verdict stands.
/// The reading and the order of requests live beside them rather than
/// here, so neither half imports the library that exports it, and each
/// half is only its transport.
library;

export 'exchange.dart' show StreamAsk;
export 'stream_probe_io.dart'
    if (dart.library.js_interop) 'stream_probe_web.dart';
export 'verdict.dart';
