/// What one look at a stream URL found, behind the engine's load-fault
/// refinement.
///
/// The conditional export keeps `dart:io` out of web builds; the web
/// half answers [StreamProbe.unreachable] unconditionally, which leaves
/// the web classifier's own per-code verdicts standing. The verdict
/// itself lives beside them rather than here, so neither half imports
/// the library that exports it.
library;

export 'stream_probe_io.dart'
    if (dart.library.js_interop) 'stream_probe_web.dart';
export 'verdict.dart';
