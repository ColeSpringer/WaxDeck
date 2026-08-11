import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../home/item_shelf.dart';
import '../player/play_progress.dart';
import '../providers.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';

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
    );

/// Whether a task has reached a terminal state.
bool _finished(ToolTask task) => task.state == 'done' || task.state == 'failed';

String _typeLabel(String type) => switch (type) {
  'book-merge' => 'Book merge',
  'book-split' => 'Book split',
  'cue-split' => 'CUE split',
  'acquire' => 'URL download',
  'import-navidrome' => 'Import from Navidrome',
  'import-subsonic' => 'Import from Subsonic',
  'import-audiobookshelf' => 'Import from Audiobookshelf',
  _ => type,
};

/// Long-running library tool tasks (book merge and split, CUE split,
/// downloads, imports): state, progress, errors, and a way into what
/// each produced. The merge and split actions live on the media screens
/// they act on; this list is where their outcomes are followed,
/// dismissed one by one, or swept once they are done.
class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(toolTasksProvider);
    final anyFinished = switch (tasks) {
      AsyncData(:final value) => value.tasks.any(_finished),
      _ => false,
    };
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (metrics.pixels >= metrics.maxScrollExtent - 400) {
          unawaited(ref.read(toolTasksProvider.notifier).loadMore());
        }
        return false;
      },
      child: WaxScaffold(
        title: 'Tool tasks',
        actions: <Widget>[
          if (anyFinished)
            WaxIconButton(
              glyph: WaxIcons.delete,
              label: 'Clear finished',
              semanticsId: SemanticsIds.tasksClearFinished,
              onPressed: () => unawaited(_clearFinished(context, ref)),
            ),
        ],
        slivers: <Widget>[
          switch (tasks) {
            AsyncData(:final value) when value.tasks.isEmpty =>
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  title: 'No tool tasks',
                  message:
                      'Merges, splits, downloads, and imports report '
                      'their progress here while they run and land here '
                      'when they finish.',
                  glyph: WaxIcons.check,
                ),
              ),
            AsyncData(:final value) => SliverPadding(
              padding: const EdgeInsets.symmetric(vertical: WaxSpace.s8),
              sliver: SliverList.builder(
                itemCount: value.tasks.length + (value.loadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= value.tasks.length) {
                    return const SkeletonShapes(
                      shape: SkeletonShape.list,
                      count: 1,
                    );
                  }
                  return _TaskRow(task: value.tasks[index]);
                },
              ),
            ),
            AsyncError(:final error) => SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorState(
                title: 'Could not load tool tasks',
                message: error is WaxDeckApiException
                    ? error.message
                    : 'The server did not answer.',
                onRetry: () => ref.invalidate(toolTasksProvider),
              ),
            ),
            _ => const SliverToBoxAdapter(
              child: SkeletonShapes(shape: SkeletonShape.list),
            ),
          },
        ],
      ),
    );
  }

  Future<void> _clearFinished(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final deleted = await ref
          .read(toolTasksProvider.notifier)
          .clearFinished();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              deleted == 1 ? 'Cleared 1 task' : 'Cleared $deleted tasks',
            ),
          ),
        );
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _TaskRow extends ConsumerWidget {
  const _TaskRow({required this.task});

  final ToolTask task;

  WaxGlyph get _glyph => switch (task.type) {
    'book-merge' || 'book-split' => WaxIcons.audiobooks,
    'cue-split' => WaxIcons.music,
    _ => WaxIcons.downloads,
  };

  /// The humanized state, with the running percentage when the engine
  /// reports one.
  String get _statusLabel {
    final pct = task.progressPct;
    return switch (task.state) {
      'queued' => 'Queued',
      'running' => pct == null ? 'Running' : 'Running · ${pct.round()}%',
      'done' => 'Done',
      'failed' => 'Failed',
      final other => other,
    };
  }

  Color _statusColor(WaxColors colors) => switch (task.state) {
    'done' => colors.success,
    'failed' => colors.error,
    'running' => colors.accent,
    _ => colors.textTertiary,
  };

  /// What the finished task points at, said in words; null when there
  /// is nowhere to go and nothing to show.
  String? get _resultLabel {
    if (task.state == 'failed') {
      // A failure can still have written a report worth reading: an
      // import that matched half the library before dying stores what
      // landed, and the error line alone buries it.
      return task.summary == null ? null : 'Tap for the report';
    }
    if (task.state != 'done') return null;
    final results = task.resultPids;
    if (task.type == 'acquire') {
      return results.isEmpty
          ? 'Open the review queue'
          : '${results.length} ready for review';
    }
    if (results.isEmpty) {
      return task.summary == null ? null : 'Finished · tap for the report';
    }
    return results.length == 1
        ? 'Tap to open what it produced'
        : '${results.length} items produced · tap to open';
  }

  /// One line of the summary's headline counters, when present.
  static String? summaryLine(Map<String, Object?> summary) {
    final parts = [
      for (final key in const ['matched', 'unmatched', 'listens'])
        if (summary[key] != null) '$key ${summary[key]}',
    ];
    if (parts.isEmpty) return null;
    return parts.join(', ');
  }

  /// Where a finished task's tap goes. Null when it goes nowhere: a
  /// running task is not done being followed, and a failure with no
  /// stored report explains itself inline.
  VoidCallback? _openAction(BuildContext context, WidgetRef ref) {
    if (task.state == 'failed') {
      final summary = task.summary;
      if (summary == null) return null;
      return () => _showSummary(context, summary);
    }
    if (task.state != 'done') return null;
    final results = task.resultPids;
    // An acquisition's results are review entries, so the review queue
    // is where they went; the same door serves when the entry pids are
    // in hand and when the server predates reporting them.
    if (task.type == 'acquire' || results.any((pid) => pid.startsWith('rv-'))) {
      return () => context.go(WaxRoute.review);
    }
    final summary = task.summary;
    if (results.isEmpty) {
      if (summary == null) return null;
      return () => _showSummary(context, summary);
    }
    if (results.length == 1) {
      return () => unawaited(_openResult(context, ref, results.single));
    }
    return () => unawaited(_pickResult(context, ref, results));
  }

  /// Resolves one produced item and opens it the way a home card does:
  /// per medium, with the player for a track.
  Future<void> _openResult(
    BuildContext context,
    WidgetRef ref,
    String pid,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final item = await ref.read(repositoryProvider).getItem(pid);
      if (!context.mounted) return;
      openHomeItem(context, ref, item, PlayProgress.none);
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// A small sheet naming everything the task produced, one row each.
  Future<void> _pickResult(
    BuildContext context,
    WidgetRef ref,
    List<String> pids,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final List<ItemDetail> items;
    try {
      items = await Future.wait([
        for (final pid in pids) ref.read(repositoryProvider).getItem(pid),
      ]);
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final colors = WaxColors.of(sheetContext);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: WaxSpace.s8),
            children: <Widget>[
              for (final item in items)
                InkWell(
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    openHomeItem(context, ref, item, PlayProgress.none);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: WaxSpace.s16,
                      vertical: WaxSpace.s12,
                    ),
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WaxType.body.copyWith(color: colors.textPrimary),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showSummary(BuildContext context, Map<String, Object?> summary) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final colors = WaxColors.of(dialogContext);
        return AlertDialog(
          key: const Key('task-summary-dialog'),
          title: Text(_typeLabel(task.type)),
          content: SingleChildScrollView(
            child: Text(
              const JsonEncoder.withIndent('  ').convert(summary),
              style: WaxType.monoData.copyWith(color: colors.textSecondary),
            ),
          ),
          actions: <Widget>[
            WaxButton(
              label: 'Close',
              kind: WaxButtonKind.text,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    );
  }

  Future<void> _dismiss(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(toolTasksProvider.notifier).dismiss(task.id);
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    final running = task.state == 'running' || task.state == 'queued';
    final open = _openAction(context, ref);
    final error = task.error;
    final summary = task.summary;
    final summaryCounters = summary == null ? null : summaryLine(summary);
    // The pids, plainly: three queued CUE splits are three rows reading
    // "CUE split", and which failed - and what a dismiss is about to
    // remove - needs the source named. The produced list is the same
    // answer for the other end; the tap resolves titles, this line is
    // legible without one. An acquisition's results are review entries
    // rather than library items, so they are counted by the result
    // label and never listed as produced.
    final results = task.resultPids;
    final produced =
        task.type == 'acquire' || results.any((pid) => pid.startsWith('rv-'))
        ? const <String>[]
        : results;
    final subject = [
      if (task.itemPid != null) task.itemPid!,
      if (produced.isNotEmpty) 'produced ${produced.join(', ')}',
    ].join(' · ');
    // A region, not one merged button: the row carries its own dismiss
    // control, and a tappable that swallowed descendant semantics would
    // erase it (the reason the upload rows are shaped this way too).
    return Semantics(
      identifier: SemanticsIds.taskRow(task.id),
      container: true,
      explicitChildNodes: true,
      child: InkWell(
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WaxSpace.s16,
            vertical: WaxSpace.s12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: WaxSpace.s4),
                child: WaxIcon(_glyph, size: 20, color: colors.textSecondary),
              ),
              const SizedBox(width: WaxSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            _typeLabel(task.type),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WaxType.titleItem.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: WaxSpace.s8),
                        Text(
                          _statusLabel,
                          style: WaxType.overline.copyWith(
                            color: _statusColor(colors),
                          ),
                        ),
                      ],
                    ),
                    if (subject.isNotEmpty) ...<Widget>[
                      const SizedBox(height: WaxSpace.s4),
                      Text(
                        subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WaxType.monoData.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                    if (running) ...<Widget>[
                      const SizedBox(height: WaxSpace.s8),
                      LinearProgressIndicator(
                        value: task.progressPct == null
                            ? null
                            : task.progressPct! / 100,
                      ),
                    ],
                    if (error != null) ...<Widget>[
                      const SizedBox(height: WaxSpace.s4),
                      Text(
                        error,
                        style: WaxType.caption.copyWith(color: colors.error),
                      ),
                    ],
                    if (_resultLabel != null) ...<Widget>[
                      const SizedBox(height: WaxSpace.s4),
                      Text(
                        _resultLabel!,
                        style: WaxType.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                    if (summaryCounters != null) ...<Widget>[
                      const SizedBox(height: WaxSpace.s4),
                      Text(
                        summaryCounters,
                        key: Key('task-summary-${task.id}'),
                        style: WaxType.caption.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_finished(task)) ...<Widget>[
                const SizedBox(width: WaxSpace.s8),
                WaxIconButton(
                  glyph: WaxIcons.close,
                  label: 'Dismiss',
                  semanticsId: SemanticsIds.taskDismiss(task.id),
                  onPressed: () => unawaited(_dismiss(context, ref)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
