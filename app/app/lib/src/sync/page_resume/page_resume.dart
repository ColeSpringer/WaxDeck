/// Platform switch for hearing that the browser thawed a page: resumed
/// from frozen, or restored from the back/forward cache.
///
/// A page stopped that way runs nothing until it comes back, so
/// what it does first on the thaw can run before it has handled anything
/// that happened meanwhile, its socket's close included. A native client
/// is never frozen this way.
library;

export 'page_resume_stub.dart'
    if (dart.library.js_interop) 'page_resume_web.dart';
