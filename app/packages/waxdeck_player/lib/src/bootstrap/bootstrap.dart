/// Platform-selected engine bootstrap.
///
/// Call `ensureAudioEngineInitialized()` once before creating an engine. The
/// conditional export keeps the media_kit dependency (and its ffi imports)
/// entirely out of web builds; on native it is a no-op everywhere except
/// desktop, where it points just_audio at mpv.
library;

export 'bootstrap_io.dart' if (dart.library.js_interop) 'bootstrap_web.dart';
