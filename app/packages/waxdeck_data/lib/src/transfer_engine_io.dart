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

  @override
  Stream<TransferEvent> get events => _events.stream;

  @override
  Future<String> start(TransferRequest request) async {
    final task = DownloadTask(
      url: request.url,
      filename: request.fileName,
      directory: _directory,
      baseDirectory: BaseDirectory.applicationSupport,
      updates: Updates.statusAndProgress,
      retries: 3,
      allowPause: true,
    );
    _tasks[task.taskId] = task;
    await FileDownloader().enqueue(task);
    return task.taskId;
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
