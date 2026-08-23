/// Reachability probe behind the engine's load-fault refinement.
///
/// The conditional export keeps `dart:io` out of web builds; the web
/// half answers false unconditionally, which leaves the web
/// classifier's own per-code verdicts standing.
library;

export 'fetchable_io.dart' if (dart.library.js_interop) 'fetchable_web.dart';
