/// Platform switch for where a browser keeps a sign-out its server has yet
/// to hear.
library;

export 'owed_revoke_storage_stub.dart'
    if (dart.library.js_interop) 'owed_revoke_storage_web.dart';
