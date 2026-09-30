import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

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

  @override
  Future<ToolTasksState> build() async {
    _generation++;
    final page = await ref
        .watch(repositoryProvider)
        .listToolTasks(limit: pageSize);
    return ToolTasksState(tasks: page.tasks, nextCursor: page.nextCursor);
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
          tasks: [...current.tasks, ...page.tasks],
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

  /// Sweeps the finished rows the caller can see (everyone's for an
  /// administrator, whose list shows everyone's) and answers how many
  /// went, for the toolbar's toast. Refetched rather than filtered
  /// locally: the server's answer is the truth about what it deleted.
  Future<int> clearFinished() async {
    final deleted = await ref.read(repositoryProvider).clearFinishedToolTasks();
    if (ref.mounted) ref.invalidateSelf();
    return deleted;
  }
}

final toolTasksProvider =
    AsyncNotifierProvider<ToolTasksController, ToolTasksState>(
      ToolTasksController.new,
      retry: retryUnlessRefused,
    );
