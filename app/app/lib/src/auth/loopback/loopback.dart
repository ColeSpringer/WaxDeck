/// Platform switch for the loopback code receiver: dart:io platforms get
/// the real localhost listener, web gets none (web uses cookie mode).
library;

export 'loopback_stub.dart' if (dart.library.io) 'loopback_io.dart';
