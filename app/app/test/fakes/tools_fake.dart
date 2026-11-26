import 'dart:async';

import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// In-memory [ToolsApi] for `FakeRepository`.
mixin FakeTools on FakeRepositoryState implements ToolsApi {
  /// Held open, the uploads and tool-task listings wait on theirs, for
  /// the same reason `listItemsGate` exists.
  Completer<void>? listToolTasksGate;

  /// Thrown by the tool endpoints when set.
  WaxDeckApiException? toolError;

  final List<({String pid, List<String>? titles, bool keepOriginals})>
  mergeBookCalls = [];
  final List<({String pid, bool keepOriginals})> splitBookCalls = [];
  final List<({String pid, bool keepOriginals})> splitCueCalls = [];

  ToolTask _startToolTask(String type, String pid) {
    final task = ToolTask(
      id: 'tt-FAKE${toolTaskSeq++}',
      type: type,
      state: 'queued',
      itemPid: pid,
      createdAt: DateTime.utc(2026, 7, 1),
    );
    toolTasksById[task.id] = task;
    return task;
  }

  @override
  Future<ToolTask> mergeBook(
    String pid, {
    List<String>? titles,
    bool keepOriginals = false,
  }) async {
    final error = toolError;
    if (error != null) throw error;
    mergeBookCalls.add((
      pid: pid,
      titles: titles,
      keepOriginals: keepOriginals,
    ));
    return _startToolTask('book-merge', pid);
  }

  @override
  Future<ToolTask> splitBook(String pid, {bool keepOriginals = false}) async {
    final error = toolError;
    if (error != null) throw error;
    splitBookCalls.add((pid: pid, keepOriginals: keepOriginals));
    return _startToolTask('book-split', pid);
  }

  @override
  Future<ToolTask> splitCueRip(String pid, {bool keepOriginals = false}) async {
    final error = toolError;
    if (error != null) throw error;
    splitCueCalls.add((pid: pid, keepOriginals: keepOriginals));
    return _startToolTask('cue-split', pid);
  }

  /// How many times the task list was read.
  int listToolTasksCalls = 0;

  @override
  Future<ToolTaskPage> listToolTasks({String? cursor, int? limit}) async {
    listToolTasksCalls++;
    final error = toolError;
    if (error != null) throw error;
    await listToolTasksGate?.future;
    return ToolTaskPage(tasks: toolTasksById.values.toList());
  }

  @override
  Future<ToolTask> getToolTask(String taskId) async {
    final task = toolTasksById[taskId];
    if (task == null) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such task',
        statusCode: 404,
      );
    }
    return task;
  }

  /// Every id [cancelToolTask] was asked to stop, refusals included.
  final List<String> cancelToolTaskCalls = [];

  /// Thrown by [cancelToolTask] when set.
  WaxDeckApiException? cancelToolTaskError;

  /// What a cancel does to a running task: a wind-down by default
  /// (`cancelRequested`), or with this false the stop is at once.
  bool cancelWindsDown = true;

  @override
  Future<ToolTask> cancelToolTask(String taskId) async {
    cancelToolTaskCalls.add(taskId);
    final error = cancelToolTaskError;
    if (error != null) throw error;
    final task = await getToolTask(taskId);
    if (task.finished) return task;
    final windsDown = task.state == 'running' && cancelWindsDown;
    final answered = ToolTask(
      id: task.id,
      type: task.type,
      state: windsDown ? 'running' : 'canceled',
      cancelRequested: windsDown,
      itemPid: task.itemPid,
      itemTitle: task.itemTitle,
      progressPct: task.progressPct,
      activity: task.activity,
      createdAt: task.createdAt,
      finishedAt: windsDown ? null : task.createdAt,
    );
    toolTasksById[taskId] = answered;
    return answered;
  }

  /// Every id [deleteToolTask] was asked to remove, refusals included.
  final List<String> deleteToolTaskCalls = [];

  /// How many times the bulk clear ran.
  int clearFinishedToolTaskCalls = 0;

  /// Whether each bulk clear asked for everyone's tasks, in order.
  final List<bool> clearFinishedToolTaskScopes = [];

  /// How many finished tasks [clearFinishedToolTasks] answers it kept.
  int clearFinishedKept = 0;

  /// Thrown by [deleteToolTask] and [clearFinishedToolTasks] when set.
  WaxDeckApiException? deleteToolTaskError;

  @override
  Future<void> deleteToolTask(String taskId) async {
    deleteToolTaskCalls.add(taskId);
    final refusal = deleteToolTaskError;
    if (refusal != null) throw refusal;
    final task = toolTasksById[taskId];
    if (task == null) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such task',
        statusCode: 404,
      );
    }
    if (!task.finished) {
      throw const WaxDeckApiException(
        code: 'conflict',
        message: 'the task has not finished',
        statusCode: 409,
      );
    }
    toolTasksById.remove(taskId);
  }

  @override
  Future<ToolTasksCleared> clearFinishedToolTasks({bool all = false}) async {
    clearFinishedToolTaskCalls++;
    clearFinishedToolTaskScopes.add(all);
    final refusal = deleteToolTaskError;
    if (refusal != null) throw refusal;
    final finished = [
      for (final task in toolTasksById.values)
        if (task.finished) task.id,
    ];
    finished.forEach(toolTasksById.remove);
    return ToolTasksCleared(deleted: finished.length, kept: clearFinishedKept);
  }
}
