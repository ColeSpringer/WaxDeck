import 'transfer_engine.dart';

/// Web stub: the browser build keeps nothing offline, so no engine is ever
/// constructed there (the providers hand out a null download manager).
class BackgroundTransferEngine implements TransferEnginePort {
  BackgroundTransferEngine() {
    throw UnsupportedError('transfers are not supported on the web build');
  }

  @override
  Stream<TransferEvent> get events => const Stream<TransferEvent>.empty();

  @override
  Future<List<TrackedTransfer>> trackedTransfers() =>
      throw UnsupportedError('web');

  @override
  Future<void> recover() => throw UnsupportedError('web');

  @override
  Future<void> describe(TransferGroup group) => throw UnsupportedError('web');

  @override
  Future<NotificationPermission> notificationPermission() =>
      throw UnsupportedError('web');

  @override
  Future<NotificationPermission> requestNotificationPermission() =>
      throw UnsupportedError('web');

  @override
  Future<String> start(TransferRequest request) =>
      throw UnsupportedError('web');

  @override
  Future<bool> pause(String taskId) => throw UnsupportedError('web');

  @override
  Future<void> resume(String taskId, {String? url, DateTime? staleAt}) =>
      throw UnsupportedError('web');

  @override
  Future<void> cancel(List<String> taskIds) => throw UnsupportedError('web');

  @override
  void dispose() {}
}
