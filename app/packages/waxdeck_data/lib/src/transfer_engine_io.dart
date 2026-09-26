import 'dart:async';
import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';

import 'transfer_engine.dart';

/// The transfer engine over `background_downloader`: everything
/// plugin-shaped lives here, from its tasks and statuses to its
/// notification placeholders and the directory files land in.
class BackgroundTransferEngine implements TransferEnginePort {
  BackgroundTransferEngine() {
    _updates = FileDownloader().updates.listen(_onUpdate);
  }

  /// Where downloaded originals go. An engine decision, not the
  /// manager's: the manager names files, this owns the directory.
  static const _directory = 'waxdeck/media';

  final _events = StreamController<TransferEvent>.broadcast();

  /// The plugin's task objects, which pause and resume need and the port
  /// never carries. A failed one is kept: the manager may resume it on a
  /// fresh URL.
  final _tasks = <String, DownloadTask>{};

  late final StreamSubscription<TaskUpdate> _updates;

  @override
  Stream<TransferEvent> get events => _events.stream;

  /// The plugin's own records, which it keeps from [recover] on. A failed
  /// one is forgotten here: nothing will come of it.
  @override
  Future<List<TrackedTransfer>> trackedTransfers() async {
    await FileDownloader().ready;
    final database = FileDownloader().database;
    final out = <TrackedTransfer>[];
    for (final record in await database.allRecords()) {
      final task = record.task;
      final placed = _placed(task);
      if (task is! DownloadTask || placed == null) continue;
      final state = switch (record.status) {
        TaskStatus.enqueued ||
        TaskStatus.running ||
        TaskStatus.waitingToRetry => null,
        TaskStatus.paused => TransferState.paused,
        TaskStatus.complete => TransferState.complete,
        TaskStatus.notFound ||
        TaskStatus.failed ||
        TaskStatus.canceled => TransferState.failed,
      };
      if (state == TransferState.failed) {
        await database.deleteRecordWithId(task.taskId);
        continue;
      }
      _tasks[task.taskId] = task;
      out.add(
        TrackedTransfer(
          taskId: task.taskId,
          pid: placed.pid,
          fileName: placed.fileName,
          state: state,
          path: state == TransferState.complete ? await task.filePath() : null,
          staleAt: placed.staleAt,
        ),
      );
    }
    return out;
  }

  /// Starts tracking, replays what the OS held for a suspended app, and
  /// reschedules what it killed. Foreground on Android, where a worker's
  /// nine-minute limit re-requests a file on a URL long expired.
  @override
  Future<void> recover() async {
    await FileDownloader().configure(
      androidConfig: [(Config.runInForeground, Config.always)],
    );
    await FileDownloader().start();
  }

  /// A notice a transfer, under its display name. A group that does not
  /// announce the end drops its notice as the transfer finishes.
  @override
  Future<void> describe(TransferGroup group) async {
    final copy = group.copy;
    FileDownloader().configureNotificationForGroup(
      group.id,
      running: TaskNotification(
        '{displayName}',
        copy.downloading('{progress}'),
      ),
      complete: group.announceDone
          ? TaskNotification('{displayName}', copy.downloaded)
          : null,
      error: TaskNotification('{displayName}', copy.failed),
      progressBar: true,
    );
  }

  @override
  Future<String> start(TransferRequest request) async {
    final task = DownloadTask(
      url: request.url,
      filename: request.fileName,
      displayName: request.displayName,
      directory: _directory,
      baseDirectory: BaseDirectory.applicationSupport,
      group: request.group,
      metaData: _metaData(request.pid, request.fileName, request.staleAt),
      updates: Updates.statusAndProgress,
      retries: 3,
      allowPause: true,
      // Never the plugin's: from 9.6.1 it means the Wi-Fi transport and
      // would hold an Ethernet device. The manager's gate holds instead.
      requiresWiFi: false,
    );
    if (!await FileDownloader().enqueue(task)) {
      throw StateError('the platform refused ${task.taskId}');
    }
    _tasks[task.taskId] = task;
    return task.taskId;
  }

  /// What places the task when the manager holds no mapping for it.
  static String _metaData(String pid, String fileName, DateTime? staleAt) =>
      jsonEncode(<String, String>{
        'pid': pid,
        'fileName': fileName,
        if (staleAt != null) 'staleAt': staleAt.toUtc().toIso8601String(),
      });

  @override
  Future<bool> pause(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return false;
    return FileDownloader().pause(task);
  }

  @override
  Future<void> resume(String taskId, {String? url, DateTime? staleAt}) async {
    var task = _tasks[taskId];
    if (task == null) throw StateError('no transfer $taskId to resume');
    final placed = _placed(task);
    if (url != null && placed != null) {
      task = task.copyWith(
        url: url,
        metaData: _metaData(placed.pid, placed.fileName, staleAt),
      );
      _tasks[taskId] = task;
    }
    if (await FileDownloader().resume(task)) return;
    // Nothing to resume from, as after a failure: it starts over, under
    // the same name.
    if (!await FileDownloader().enqueue(task)) {
      throw StateError('the platform refused $taskId');
    }
  }

  @override
  Future<void> cancel(List<String> taskIds) async {
    if (taskIds.isEmpty) return;
    await FileDownloader().cancelTasksWithIds(taskIds);
    for (final id in taskIds) {
      _tasks.remove(id);
      await FileDownloader().database.deleteRecordWithId(id);
    }
  }

  @override
  Future<NotificationPermission> notificationPermission() async {
    try {
      final permissions = FileDownloader().permissions;
      return switch (await permissions.status(PermissionType.notifications)) {
        PermissionStatus.granted ||
        PermissionStatus.partial => NotificationPermission.granted,
        PermissionStatus.undetermined => NotificationPermission.undetermined,
        PermissionStatus.denied || PermissionStatus.requestError =>
          await permissions.shouldShowRationale(PermissionType.notifications)
              ? NotificationPermission.deniedExplainable
              : NotificationPermission.denied,
      };
    } on Object {
      // Platforms with no such permission answer by throwing.
      return NotificationPermission.granted;
    }
  }

  @override
  Future<NotificationPermission> requestNotificationPermission() async {
    try {
      await FileDownloader().permissions.request(PermissionType.notifications);
    } on Object {
      // Nothing to ask for on this platform.
    }
    return notificationPermission();
  }

  Future<void> _onUpdate(TaskUpdate update) async {
    final task = update.task;
    final id = task.taskId;
    if (update is TaskProgressUpdate) {
      // Below zero is a status in progress's clothes, reported on its own.
      if (update.progress < 0) return;
      _emit(TransferEvent(taskId: id, fraction: update.progress.clamp(0, 1)));
      return;
    }
    if (update is! TaskStatusUpdate) return;
    final state = switch (update.status) {
      TaskStatus.complete => TransferState.complete,
      TaskStatus.failed || TaskStatus.notFound => TransferState.failed,
      TaskStatus.canceled => TransferState.canceled,
      TaskStatus.paused => TransferState.paused,
      TaskStatus.running => TransferState.running,
      TaskStatus.enqueued || TaskStatus.waitingToRetry => null,
    };
    if (state == null) return;
    // Resolved here because it is a platform call (the app-support
    // directory) and because the directory is this class's own.
    final path = state == TransferState.complete ? await task.filePath() : null;
    // The plugin's record stays until the next start forgets it: deleted
    // here, a crash before the manager lands the file would lose it.
    if (state == TransferState.complete || state == TransferState.canceled) {
      _tasks.remove(id);
    }
    final placed = _placed(task);
    _emit(
      TransferEvent(
        taskId: id,
        state: state,
        fraction: state == TransferState.complete ? 1 : null,
        path: path,
        pid: placed?.pid,
        fileName: placed?.fileName,
        httpStatus: switch (update) {
          TaskStatusUpdate(status: TaskStatus.notFound) => 404,
          TaskStatusUpdate(exception: final TaskHttpException e) =>
            e.httpResponseCode,
          _ => null,
        },
      ),
    );
  }

  /// The item and file a task was started for, and when its URL stops
  /// working, from its metadata.
  static ({String pid, String fileName, DateTime? staleAt})? _placed(
    Task task,
  ) {
    try {
      final meta = jsonDecode(task.metaData);
      if (meta case {'pid': final String pid, 'fileName': final String name}) {
        final staleAt = meta['staleAt'];
        return (
          pid: pid,
          fileName: name,
          staleAt: staleAt is String ? DateTime.tryParse(staleAt) : null,
        );
      }
    } on FormatException {
      // A task this engine did not start.
    }
    return null;
  }

  void _emit(TransferEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  void dispose() {
    _updates.cancel();
    _events.close();
  }
}
