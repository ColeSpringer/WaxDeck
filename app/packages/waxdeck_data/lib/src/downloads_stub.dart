import 'dart:async';

import 'package:waxdeck_api/waxdeck_api.dart';

import 'database.dart';
import 'downloads_port.dart';

/// Web stub: the browser build keeps no offline downloads yet, so the
/// manager is never constructed there (providers hand out null).
class BackgroundDownloadManager implements DownloadManagerPort {
  BackgroundDownloadManager({
    required MirrorDatabase db,
    required WaxDeckRepository repository,
    required String baseUrl,
  }) {
    throw UnsupportedError('downloads are not supported on the web build');
  }

  void dispose() {}

  @override
  Future<void> download(String pid) => throw UnsupportedError('web');

  @override
  Future<void> remove(String pid) => throw UnsupportedError('web');

  @override
  Future<LocalPlayback?> localFor(String pid) => throw UnsupportedError('web');

  @override
  Future<bool> isComplete(String pid) => throw UnsupportedError('web');

  @override
  Stream<DownloadProgress> get progress => const Stream.empty();
}
