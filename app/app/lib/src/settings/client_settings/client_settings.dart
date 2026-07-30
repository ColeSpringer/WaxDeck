/// Platform switch for where per-device preferences persist.
///
/// Native builds already have a durable local store, so they use it. The
/// web build has no mirror at all - drift does not run there - and the
/// alternative was the no-op store the queue uses on web, which would
/// leave a collapsed sidebar unpersisted on exactly the surface that
/// wants it. So the browser gets a real implementation over
/// `localStorage`, and it lives here rather than in `waxdeck_data`:
/// a browser-storage backend inside the drift package is the coupling
/// ADR-0025 avoided for artwork. See ADR-0027.
library;

export 'client_settings_native.dart'
    if (dart.library.js_interop) 'client_settings_web.dart';
