import 'database.dart';

/// Web stub: the browser build runs without a local mirror for now.
MirrorDatabase openMirrorDatabase() {
  throw UnsupportedError('the local mirror is not supported on the web build');
}

/// Web stub; never constructed there.
MirrorDatabase inMemoryMirrorDatabase() {
  throw UnsupportedError('the local mirror is not supported on the web build');
}
