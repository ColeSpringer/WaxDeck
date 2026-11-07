import '../models.dart';

/// Long-running maintenance tasks.
abstract interface class ToolsApi {
  /// `POST /books/{pid}/merge`: joins a multi-file audiobook into one
  /// file, returning the queued task. [titles] overrides the derived
  /// chapter titles.
  Future<ToolTask> mergeBook(
    String pid, {
    List<String>? titles,
    bool keepOriginals = false,
  });

  /// `POST /books/{pid}/split`: splits a single-file audiobook at its
  /// chapter marks, returning the queued task.
  Future<ToolTask> splitBook(String pid, {bool keepOriginals = false});

  /// `POST /items/{pid}/split-cue`: carves a CUE-backed rip into real
  /// per-track files, returning the queued task.
  Future<ToolTask> splitCueRip(String pid, {bool keepOriginals = false});

  /// `GET /tools/tasks`: keyset-paginated tool tasks, newest first.
  Future<ToolTaskPage> listToolTasks({String? cursor, int? limit});

  /// `GET /tools/tasks/{taskId}`: one task's progress and outcome.
  Future<ToolTask> getToolTask(String taskId);

  /// `DELETE /tools/tasks/{taskId}`: removes one finished task; a task
  /// still queued or running answers `conflict`.
  Future<void> deleteToolTask(String taskId);

  /// `POST /tools/tasks/clear-finished`: deletes the caller's finished
  /// tasks, or with [all] every account's (administrators only, else
  /// `forbidden`), and answers how many went, and how many stayed for
  /// files they left that could not be moved.
  Future<ToolTasksCleared> clearFinishedToolTasks({bool all = false});
}
