/// Offline-first data layer: the drift catalog mirror, the delta-sync
/// engine over the /sync endpoints and the WebSocket event channel,
/// the offline mutation outbox, and downloads of original files.
library;

export 'package:drift/drift.dart' show Value;

export 'src/artwork_pin_store.dart';
export 'src/database.dart';
export 'src/downloads_io.dart'
    if (dart.library.js_interop) 'src/downloads_stub.dart';
export 'src/downloads_port.dart';
export 'src/events_channel.dart';
export 'src/mirror_pages.dart';
export 'src/open_io.dart' if (dart.library.js_interop) 'src/open_stub.dart';
export 'src/queue_store.dart';
export 'src/sync_engine.dart';
