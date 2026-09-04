/// Platform-selected browser engine.
///
/// The conditional export keeps `package:web` and `dart:js_interop` out
/// of every native compilation unit, the way the bootstrap split keeps
/// media_kit out of web builds. Off the web there is nothing to select:
/// every native backend already crosses a boundary without a gap, so
/// [createWebGaplessEngine] hands back the engine it was given.
library;

export 'web_gapless_stub.dart'
    if (dart.library.js_interop) 'web_gapless_real.dart';
