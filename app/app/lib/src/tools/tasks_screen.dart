import 'dart:convert';

import 'package:flutter/material.dart';
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
      // a bad cast. Release the paging guard first — loadingMore is
      // what keeps two fetches from racing, so leaving it set would
      // wedge paging permanently and silently — then let the error
      // reach the zone's handler instead of vanishing here.
      if (generation == _generation) {
        state = AsyncData(current.copyWith(loadingMore: false));
      }
      rethrow;
    }
  }
}

final toolTasksProvider =
    AsyncNotifierProvider<ToolTasksController, ToolTasksState>(
      ToolTasksController.new,
    );

/// Long-running library tool tasks (book merge and split, CUE split):
/// state, progress, errors, and produced items. Read-only on purpose;
/// the merge and split actions live on the media screens they act on,
/// and the repository methods stay reachable from tests meanwhile.
class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(toolTasksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Tool tasks')),
      body: switch (tasks) {
        AsyncData(:final value) => _list(context, ref, value),
        AsyncError(:final error) => _errorView(context, ref, error),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _errorView(BuildContext context, WidgetRef ref, Object error) {
    final message = error is WaxDeckApiException
        ? error.message
        : 'Could not load tool tasks';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => ref.invalidate(toolTasksProvider),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, WidgetRef ref, ToolTasksState state) {
    if (state.tasks.isEmpty) {
      return const Center(child: Text('No tool tasks yet'));
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (metrics.pixels >= metrics.maxScrollExtent - 400) {
          ref.read(toolTasksProvider.notifier).loadMore();
        }
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: state.tasks.length + (state.loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.tasks.length) {
            return const Center(child: CircularProgressIndicator());
          }
          return _TaskRow(task: state.tasks[index]);
        },
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task});

  final ToolTask task;

  static String _typeLabel(String type) => switch (type) {
    'book-merge' => 'Book merge',
    'book-split' => 'Book split',
    'cue-split' => 'CUE split',
    'acquire' => 'URL download',
    'import-navidrome' => 'Import from Navidrome',
    'import-subsonic' => 'Import from Subsonic',
    'import-audiobookshelf' => 'Import from Audiobookshelf',
    _ => type,
  };

  /// One line of the summary's headline counters, when present.
  static String? summaryLine(Map<String, Object?> summary) {
    final parts = [
      for (final key in const ['matched', 'unmatched', 'listens'])
        if (summary[key] != null) '$key ${summary[key]}',
    ];
    if (parts.isEmpty) {
      return summary.isEmpty ? null : 'Finished; tap for detail';
    }
    return parts.join(', ');
  }

  void _showSummary(BuildContext context, Map<String, Object?> summary) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('task-summary-dialog'),
        title: Text(_typeLabel(task.type)),
        content: SingleChildScrollView(
          child: Text(
            const JsonEncoder.withIndent('  ').convert(summary),
            style: Theme.of(
              dialogContext,
            ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final progress = task.progressPct;
    final error = task.error;
    final running = task.state == 'running' || task.state == 'queued';
    final summary = task.finishedAt == null ? null : task.summary;
    return Semantics(
      identifier: 'task-row-${task.id}',
      label: _typeLabel(task.type),
      child: Card(
        key: ValueKey('task-row-${task.id}'),
        child: InkWell(
          onTap: summary == null ? null : () => _showSummary(context, summary),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        task.itemPid == null
                            ? _typeLabel(task.type)
                            : '${_typeLabel(task.type)}: ${task.itemPid}',
                        style: textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Chip(
                      label: Text(task.state),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: task.state == 'failed'
                          ? colorScheme.errorContainer
                          : null,
                      labelStyle: task.state == 'failed'
                          ? TextStyle(color: colorScheme.onErrorContainer)
                          : null,
                    ),
                  ],
                ),
                if (running) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress == null ? null : progress / 100,
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    error,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.error,
                    ),
                  ),
                ],
                if (task.resultPids.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    // Acquire tasks produce review-queue entries, not library
                    // items, so their result ids are not navigable items to list.
                    task.type == 'acquire'
                        ? '${task.resultPids.length} ready for review'
                        : 'Produced: ${task.resultPids.join(', ')}',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (summary != null && summaryLine(summary) != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    summaryLine(summary)!,
                    key: Key('task-summary-${task.id}'),
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
