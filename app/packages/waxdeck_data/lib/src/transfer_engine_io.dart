import 'dart:async';

import 'package:background_downloader/background_downloader.dart';

import 'transfer_engine.dart';

/// The transfer engine over `background_downloader`.
///
/// Everything plugin-shaped lives here: its task objects, its status
/// vocabulary, the directory files land in, and the resume-or-re-enqueue
/// dance. The manager above sees ids and four states.
class BackgroundTransferEngine implements TransferEnginePort {
  BackgroundTransferEngine() {
    _updates = FileDownloader().updates.listen(_onUpdate);
    // A background download with no notification is a download the
    // listener cannot see, stop, or explain - on Android it is also the
    // only thing keeping the work visible to the OS. Configured once
    // for every task; a no-op on the desktops, which have no such
    // notification to post.
    FileDownloader().configureNotification(
      running: const TaskNotification(
        '{displayName}',
        'Downloading {progress}',
      ),
      complete: const TaskNotification('{displayName}', 'Downloaded'),
      error: const TaskNotification('{displayName}', 'Download failed'),
      progressBar: true,
      // Deliberately per task rather than grouped. A group notification
      // collapses a multi-part book into one row, which is the better
      // answer for a book - but it also replaces the file name with a
      // count, and one file is what most downloads are. Getting both
      // means a notification group per item, which needs a group on the
      // request; deferred rather than traded away here.
    );
  }

  /// Where downloaded originals go. An engine decision, not the
  /// manager's: the manager names files, this owns the directory.
  static const _directory = 'waxdeck/media';

  final _events = StreamController<TransferEvent>.broadcast();

  /// The plugin's task objects, by id. Held here so they never cross the
  /// port, and because pause and resume both need the object rather than
  /// the id the plugin reports.
  final _tasks = <String, DownloadTask>{};

  late final StreamSubscription<TaskUpdate> _updates;

  /// Whether the notification permission has been asked for this run.
  bool _askedForNotifications = false;

  @override
  Stream<TransferEvent> get events => _events.stream;

  @override
  Future<String> start(TransferRequest request) async {
    await _ensureNotificationPermission();
    final task = DownloadTask(
      url: request.url,
      filename: request.fileName,
      displayName: request.displayName,
      directory: _directory,
      baseDirectory: BaseDirectory.applicationSupport,
      updates: Updates.statusAndProgress,
      retries: 3,
      allowPause: true,
      requiresWiFi: request.wifiOnly,
    );
    _tasks[task.taskId] = task;
    await FileDownloader().enqueue(task);
    return task.taskId;
  }

  /// Asks for the notification permission at the first download rather
  /// than at launch, where it would be a dialog about a feature the
  /// listener has not reached yet. Once per process: [PermissionStatus]
  /// is the platform's answer and asking again does not change it.
  ///
  /// A refusal is not an error. The download runs either way - the
  /// permission buys the progress notification, not the transfer - so
  /// this neither blocks nor reports.
  Future<void> _ensureNotificationPermission() async {
    if (_askedForNotifications) return;
    _askedForNotifications = true;
    try {
      final permissions = FileDownloader().permissions;
      if (await permissions.status(PermissionType.notifications) ==
          PermissionStatus.undetermined) {
        await permissions.request(PermissionType.notifications);
      }
    } on Object {
      // Platforms with no such permission answer by throwing; the
      // download is unaffected either way.
    }
  }

  @override
  Future<bool> pause(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return false;
    return FileDownloader().pause(task);
  }

  @override
  Future<void> resume(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return;
    // A task the plugin has forgotten how to resume starts over rather
    // than staying stopped; the bytes land under the same name either way,
    // because the caller names files by essence hash.
    if (!await FileDownloader().resume(task)) {
      await FileDownloader().enqueue(task);
    }
  }

  @override
  Future<void> cancel(List<String> taskIds) async {
    if (taskIds.isEmpty) return;
    await FileDownloader().cancelTasksWithIds(taskIds);
    for (final id in taskIds) {
      _tasks.remove(id);
    }
  }

  Future<void> _onUpdate(TaskUpdate update) async {
    final id = update.task.taskId;
    if (update is TaskProgressUpdate) {
      _emit(TransferEvent(taskId: id, fraction: update.progress.clamp(0, 1)));
      return;
    }
    if (update is! TaskStatusUpdate) return;
    switch (update.status) {
      case TaskStatus.complete:
        // Resolved here because it is a platform call (the app-support
        // directory) and because the directory is this class's own.
        final path = await update.task.filePath();
        _tasks.remove(id);
        _emit(
          TransferEvent(
            taskId: id,
            state: TransferState.complete,
            fraction: 1,
            path: path,
          ),
        );
      case TaskStatus.failed:
        _tasks.remove(id);
        _emit(TransferEvent(taskId: id, state: TransferState.failed));
      case TaskStatus.canceled:
        _tasks.remove(id);
        _emit(TransferEvent(taskId: id, state: TransferState.canceled));
      case TaskStatus.paused:
        // The task stays: it resumes under this same id.
        _emit(TransferEvent(taskId: id, state: TransferState.paused));
      case TaskStatus.enqueued:
      case TaskStatus.running:
      case TaskStatus.notFound:
      case TaskStatus.waitingToRetry:
        break;
    }
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
