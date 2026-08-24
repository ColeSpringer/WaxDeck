import 'dart:async';

import 'package:waxdeck_api/waxdeck_api.dart';

import 'database.dart';
import 'downloads_port.dart';
import 'transfer_engine.dart';

/// Web stub: the browser build keeps no offline downloads yet, so the
/// manager is never constructed there (providers hand out null).
class BackgroundDownloadManager implements DownloadManagerPort {
  BackgroundDownloadManager({
    required MirrorDatabase db,
    required WaxDeckRepository Function() repository,
    TransferEnginePort? engine,
    bool Function()? wifiOnly,
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
  Future<List<DownloadedItem>> stored() => throw UnsupportedError('web');

  @override
  Future<void> cancel(String pid) => throw UnsupportedError('web');

  @override
  Future<bool> pause(String pid) => throw UnsupportedError('web');

  @override
  Future<void> resume(String pid) => throw UnsupportedError('web');

  @override
  Stream<DownloadProgress> get progress => const Stream.empty();
}
