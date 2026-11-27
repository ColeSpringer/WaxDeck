import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../auth/auth_controller.dart';
import '../providers.dart';

/// Accumulated pages of tool tasks, newest first.
class ToolTasksState {
  const ToolTasksState({
    required this.tasks,
    this.nextCursor,
    this.loadingMore = false,
  });

  final List<ToolTask> tasks;
  final String? nextCursor;
  final bool loadingMore;

  bool get hasMore => nextCursor != null;

  ToolTasksState copyWith({bool? loadingMore}) => ToolTasksState(
    tasks: tasks,
    nextCursor: nextCursor,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// Pages the tool task list with keyset cursors.
class ToolTasksController extends AsyncNotifier<ToolTasksState> {
  static const pageSize = 50;

  var _generation = 0;

  /// The tasks whose cancel the server answered, until a read shows them
  /// finished or gone.
  final _canceled = <String>{};

  @override
  Future<ToolTasksState> build() async {
    _generation++;
    // Keyed on the account: the repository moves only with the server,
    // and the next account starts from its own first page.
    ref.watch(signedInAccountProvider);
    final page = await ref
        .watch(repositoryProvider)
        .listToolTasks(limit: pageSize);
    // Only a read to the list's end says a task is gone.
    if (page.nextCursor == null) {
      _canceled.retainWhere((id) => page.tasks.any((task) => task.id == id));
    }
    return ToolTasksState(
      tasks: _keepCancels(page.tasks),
      nextCursor: page.nextCursor,
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final generation = _generation;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref
          .read(repositoryProvider)
          .listToolTasks(cursor: current.nextCursor, limit: pageSize);
      if (generation != _generation) return;
      state = AsyncData(
        ToolTasksState(
          tasks: [...current.tasks, ..._keepCancels(page.tasks)],
          nextCursor: page.nextCursor,
        ),
      );
    } on WaxDeckApiException {
      // An expected transport or server error. Keep what we have;
      // scrolling near the end again retries.
      if (generation != _generation) return;
      state = AsyncData(current.copyWith(loadingMore: false));
    } catch (_) {
      // Anything else is a defect, not a hiccup: a decode failure,
      // a bad cast. Release the paging guard first - loadingMore is
      // what keeps two fetches from racing, so leaving it set would
      // wedge paging permanently and silently - then let the error
      // reach the app's error handler instead of vanishing here.
      if (generation == _generation) {
        state = AsyncData(current.copyWith(loadingMore: false));
      }
      rethrow;
    }
  }

  /// Removes one finished row, in place rather than by refetch, so a
  /// dismiss mid-scroll does not throw the reader back to the top.
  /// Failures propagate; the row's control answers for them.
  Future<void> dismiss(String taskId) async {
    try {
      await ref.read(repositoryProvider).deleteToolTask(taskId);
    } on WaxDeckApiException catch (e) {
      // Already gone - dismissed from another device, or swept - is
      // the outcome this tap wanted, so the splice below still runs.
      if (e.statusCode != 404) rethrow;
    }
    // Mounted before state: an unmounted notifier's state getter
    // throws, and a sign-out mid-flight lands this exactly there.
    if (!ref.mounted) return;
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      ToolTasksState(
        tasks: [
          for (final task in current.tasks)
            if (task.id != taskId) task,
        ],
        nextCursor: current.nextCursor,
        loadingMore: current.loadingMore,
      ),
    );
  }

  /// Asks one unfinished task to stop and puts the server's answer in its
  /// row, in place: `canceled` for one that had not started, still
  /// `running` with `cancelRequested` while a run winds down, or the task
  /// as it had already ended. A task the server no longer has leaves the
  /// list. Other refusals propagate; the row's control answers for them.
  /// A read begun while the cancel was out is newer than its answer, which
  /// then only keeps the cancel asked for on its row; so does every read
  /// until one shows the task finished, as one the server answered before
  /// it took the cancel does not.
  Future<void> cancel(String taskId) async {
    final generation = _generation;
    ToolTask? answered;
    try {
      answered = await ref.read(repositoryProvider).cancelToolTask(taskId);
    } on WaxDeckApiException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
    if (!ref.mounted) return;
    if (answered == null) {
      _canceled.remove(taskId);
    } else {
      _canceled.add(taskId);
    }
    final current = state.value;
    if (current == null) return;
    final tasks = generation == _generation
        ? [
            for (final task in current.tasks)
              if (task.id != taskId) task else ?answered,
          ]
        : _keepCancels(current.tasks);
    if (identical(tasks, current.tasks)) return;
    state = AsyncData(
      ToolTasksState(
        tasks: tasks,
        nextCursor: current.nextCursor,
        loadingMore: current.loadingMore,
      ),
    );
  }

  /// [tasks] with the cancel asked for on each unfinished row whose cancel
  /// the server answered; a row that shows its task finished lets it go.
  /// [tasks] itself when nothing changes.
  List<ToolTask> _keepCancels(List<ToolTask> tasks) {
    _canceled.removeAll([
      for (final task in tasks)
        if (task.finished) task.id,
    ]);
    bool owed(ToolTask task) =>
        !task.cancelRequested && _canceled.contains(task.id);
    if (!tasks.any(owed)) return tasks;
    return [
      for (final task in tasks) owed(task) ? task.withCancelRequested() : task,
    ];
  }

  /// Sweeps the caller's own finished rows, or with [all] everyone's
  /// (an administrator's choice), and answers how many went and how many
  /// stayed, for the toolbar's toast. Refetched rather than filtered
  /// locally: the server's answer is the truth about what it deleted.
  Future<ToolTasksCleared> clearFinished({bool all = false}) async {
    final cleared = await ref
        .read(repositoryProvider)
        .clearFinishedToolTasks(all: all);
    if (ref.mounted) ref.invalidateSelf();
    return cleared;
  }
}

final toolTasksProvider =
    AsyncNotifierProvider<ToolTasksController, ToolTasksState>(
      ToolTasksController.new,
      retry: retryUnlessRefused,
    );
