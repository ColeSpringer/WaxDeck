/// Platform switch for where the web listener keeps its catalog cursor.
library;

export 'cursor_storage_stub.dart'
    if (dart.library.js_interop) 'cursor_storage_web.dart';
