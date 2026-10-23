import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../admin/admin_providers.dart';
import '../health/health_labels.dart';
import '../home/item_shelf.dart';
import '../l10n/l10n.dart';
import '../player/play_progress.dart';
import '../providers.dart';
import '../settings/settings_registry.dart';
import '../shell/async_sliver_face.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'tool_tasks_provider.dart';

/// Whether a task has reached a terminal state, a parked one included.
bool _finished(ToolTask task) => task.finished;

/// The kinds in words. The three imports name a product rather than a
/// kind of work, so the name rides in as a placeholder and the sentence
/// around it is what gets translated; a health fix names its rule, which
/// its summary carries from the start.
String _typeLabel(
  AppLocalizations l10n,
  String type, [
  Map<String, Object?>? summary,
]) => switch (type) {
  'book-merge' => l10n.toolsTaskBookMerge,
  'book-split' => l10n.toolsTaskBookSplit,
  'cue-split' => l10n.toolsTaskCueSplit,
  'acquire' => l10n.toolsTaskAcquire,
  'playlist-sync' => l10n.toolsTaskPlaylistSync,
  'genre-normalize' => l10n.toolsTaskGenreNormalize,
  'health-fix' => switch (summary?['rule']) {
    final String rule => l10n.toolsTaskHealthFix(
      healthRuleName(l10n, rule) ?? rule,
    ),
    _ => l10n.toolsTaskHealthFix(type),
  },
  'import-navidrome' => l10n.toolsTaskImportFrom('Navidrome'),
  'import-subsonic' => l10n.toolsTaskImportFrom('Subsonic'),
  'import-audiobookshelf' => l10n.toolsTaskImportFrom('Audiobookshelf'),
  'import-jellyfin' => l10n.toolsTaskImportFrom('Jellyfin'),
  'import-lastfm' => l10n.toolsTaskImportFrom('Last.fm'),
  'import-listenbrainz' => l10n.toolsTaskImportFrom('ListenBrainz'),
  'import-spotify' => l10n.toolsTaskImportFrom('Spotify'),
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
    final l10n = context.l10n;
    final tasks = ref.watch(toolTasksProvider);
    // Catalog jobs are an administrator's: nobody else may list them.
    final jobs = ref.watch(isAdminProvider)
        ? _visibleJobs(ref.watch(adminJobsProvider).value ?? const <Job>[])
        : const <Job>[];
    // Read off the value rather than the runtime type, for the same
    // reason the face below does: a refresh carries the previous value
    // under an AsyncLoading, and a toolbar control that vanished on
    // every reload would be its own bug.
    final anyFinished = tasks.value?.tasks.any(_finished) ?? false;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (metrics.pixels >= metrics.maxScrollExtent - 400) {
          unawaited(ref.read(toolTasksProvider.notifier).loadMore());
        }
        return false;
      },
      child: WaxScaffold(
        title: l10n.toolsTitle,
        semanticsId: SemanticsIds.tasksScreen,
        actions: <Widget>[
          if (anyFinished)
            // An administrator's list holds everyone's tasks, so the
            // sweep asks whose. A member has the one.
            if (ref.watch(isAdminProvider))
              WaxMenuButton<bool>(
                glyph: WaxIcons.delete,
                label: l10n.toolsClearFinished,
                semanticsId: SemanticsIds.tasksClearFinished,
                items: <WaxMenuItem<bool>>[
                  WaxMenuItem<bool>(
                    value: false,
                    label: l10n.toolsClearFinishedMine,
                    semanticsId: SemanticsIds.tasksClearFinishedMine,
                  ),
                  WaxMenuItem<bool>(
                    value: true,
                    label: l10n.toolsClearFinishedAll,
                    semanticsId: SemanticsIds.tasksClearFinishedAll,
                  ),
                ],
                onSelected: (all) =>
                    unawaited(_clearFinished(context, ref, all: all)),
              )
            else
              WaxIconButton(
                glyph: WaxIcons.delete,
                label: l10n.toolsClearFinished,
                semanticsId: SemanticsIds.tasksClearFinished,
                onPressed: () => unawaited(_clearFinished(context, ref)),
              ),
        ],
        slivers: <Widget>[
          if (jobs.isNotEmpty) ...<Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s16),
                child: SectionHeader(title: l10n.toolsJobsTitle),
              ),
            ),
            SliverList.builder(
              itemCount: jobs.length,
              findChildIndexCallback: indexByKey(jobs, _jobKey),
              itemBuilder: (context, index) =>
                  _JobRow(key: _jobKey(jobs[index]), job: jobs[index]),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s16),
                child: SectionHeader(title: l10n.toolsTasksSection),
              ),
            ),
          ],
          AsyncSliverFace<ToolTasksState>(
            state: tasks,
            errorTitle: l10n.toolsLoadError,
            onRetry: () => ref.invalidate(toolTasksProvider),
            isEmpty: (value) => value.tasks.isEmpty,
            // Under the jobs it keeps its own height; alone, it centres in
            // the screen.
            empty: (context, _) {
              final empty = EmptyState(
                title: l10n.toolsEmptyTitle,
                message: l10n.toolsEmptyMessage,
                glyph: WaxIcons.check,
              );
              return jobs.isEmpty
                  ? SliverFillRemaining(hasScrollBody: false, child: empty)
                  : SliverToBoxAdapter(child: empty);
            },
            builder: (context, value) => SliverPadding(
              padding: const EdgeInsets.symmetric(vertical: WaxSpace.s8),
              sliver: SliverList.builder(
                itemCount: value.tasks.length + (value.loadingMore ? 1 : 0),
                findChildIndexCallback: indexByKey(value.tasks, _taskKey),
                itemBuilder: (context, index) {
                  if (index >= value.tasks.length) {
                    return const SkeletonShapes(
                      shape: SkeletonShape.list,
                      count: 1,
                    );
                  }
                  final task = value.tasks[index];
                  return _TaskRow(key: _taskKey(task), task: task);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _clearFinished(
    BuildContext context,
    WidgetRef ref, {
    bool all = false,
  }) async {
    // Read before the dialog: this runs unawaited, so `ref` may be dead
    // by the time the answer comes back.
    final messenger = ref.read(shellMessengerProvider.notifier);
    final notifier = ref.read(toolTasksProvider.notifier);
    final l10n = context.l10n;
    if (all) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.toolsClearAllTitle),
          content: WaxProse(l10n.toolsClearAllBody),
          actions: <Widget>[
            WaxButton(
              label: l10n.commonCancel,
              kind: WaxButtonKind.text,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            WaxButton(
              label: l10n.toolsClearAllAction,
              semanticsId: SemanticsIds.tasksClearFinishedConfirm,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      final cleared = await notifier.clearFinished(all: all);
      // What stayed, and where to read why: each kept row says it.
      messenger.show(
        [
          l10n.toolsTasksCleared(cleared.deleted),
          if (cleared.kept > 0) l10n.toolsTasksKept(cleared.kept),
        ].join('\n'),
        channel: ShellChannel.tasks,
      );
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e), channel: ShellChannel.tasks);
    }
  }
}

class _TaskRow extends ConsumerWidget {
  const _TaskRow({super.key, required this.task});

  final ToolTask task;

  WaxGlyph get _glyph => switch (task.type) {
    'book-merge' || 'book-split' => WaxIcons.audiobooks,
    'cue-split' => WaxIcons.music,
    'playlist-sync' => WaxIcons.refresh,
    _ => WaxIcons.downloads,
  };

  /// A running task that is waiting out a passing failure, to try again
  /// on its own: no work is under way, whatever its percentage says.
  bool get _waiting => task.state == 'running' && task.waitReason != null;

  /// The humanized state, with the running percentage when the engine
  /// reports one.
  String _statusLabel(AppLocalizations l10n) {
    final pct = task.progressPct;
    if (_waiting) return l10n.toolsStateWaiting;
    return switch (task.state) {
      'queued' => l10n.toolsStateQueued,
      'running' =>
        pct == null
            ? l10n.toolsStateRunning
            : l10n.toolsStateRunningPct(pct.round()),
      'done' => l10n.toolsStateDone,
      'failed' => l10n.toolsStateFailed,
      'parked' => l10n.toolsStateParked,
      final other => other,
    };
  }

  Color _statusColor(WaxColors colors) => switch (task.state) {
    _ when _waiting => colors.textSecondary,
    'done' => colors.success,
    'failed' || 'parked' => colors.error,
    'running' => colors.accent,
    _ => colors.textTertiary,
  };

  /// Why a waiting task waits, and what would end it where that takes
  /// somebody; a cause this app has no sentence for reads as passing,
  /// with the server's words under it.
  static String _waitSentence(AppLocalizations l10n, String reason) =>
      switch (reason) {
        'catalog-busy' => l10n.toolsWaitCatalogBusy,
        'catalog-maintenance' => l10n.toolsWaitCatalogMaintenance,
        'read-only' => l10n.toolsWaitReadOnly,
        'storage-unwritable' => l10n.toolsWaitStorageUnwritable,
        'engine-unavailable' => l10n.toolsWaitEngineUnavailable,
        'part-missing' => l10n.toolsWaitPartMissing,
        'put-back-blocked' => l10n.toolsWaitPutBackBlocked,
        'stopped' => l10n.toolsWaitStopped,
        _ => l10n.toolsWaitOther,
      };

  /// The summary as a report, or null when there is none: a health fix
  /// carries its rule from the start, to be named by, and its counts only
  /// once it has some.
  Map<String, Object?>? get _report {
    final summary = task.summary;
    if (task.type == 'health-fix' &&
        !(summary?.containsKey('attempted') ?? false)) {
      return null;
    }
    return summary;
  }

  /// What the finished task points at, said in words; null when there
  /// is nowhere to go and nothing to show.
  String? _resultLabel(AppLocalizations l10n) {
    if (task.state == 'failed') {
      // A failure can still have written a report worth reading: an
      // import that matched half the library before dying stores what
      // landed, and the error line alone buries it.
      return _report == null ? null : l10n.toolsTapForReport;
    }
    if (task.state != 'done') return null;
    final results = task.resultPids;
    if (task.type == 'acquire') {
      return results.isEmpty
          ? l10n.toolsOpenReviewQueue
          : l10n.toolsReadyForReview(results.length);
    }
    if (results.isEmpty) {
      return _report == null ? null : l10n.toolsFinishedTapForReport;
    }
    return results.length == 1
        ? l10n.toolsTapToOpenResult
        : l10n.toolsItemsProduced(results.length);
  }

  /// One line of the summary's headline counters, when present.
  static String? summaryLine(
    AppLocalizations l10n,
    Map<String, Object?> summary,
  ) {
    final parts = <String>[
      // A health fix's: what it filled of what it tried, and the rest. A
      // path fix moves its items rather than filling them, and holds some.
      if (_count(summary['attempted']) case final attempted?) ...<String>[
        if (_count(summary['moved']) case final moved?)
          l10n.toolsCountMovedOf(moved, attempted)
        else
          l10n.toolsCountFilledOf(_count(summary['filled']) ?? 0, attempted),
        if (_skippedTotal(summary['held']) case final held?)
          l10n.toolsCountHeld(held),
        if (_skippedTotal(summary['skipped']) case final skipped?)
          l10n.toolsCountSkipped(skipped),
        if (_count(summary['failed']) case final failed?)
          l10n.toolsCountFailed(failed),
      ],
      if (summary['matched'] != null)
        l10n.toolsSummaryMatched('${summary['matched']}'),
      if (summary['unmatched'] != null)
        l10n.toolsSummaryUnmatched('${summary['unmatched']}'),
      if (summary['listens'] != null)
        l10n.toolsSummaryListens('${summary['listens']}'),
      // Only when there were any. An import onto a household member the
      // administrator has restricted matches thousands and writes none
      // of them, and without this the report says so with a zero and no
      // reason.
      if (summary['refused'] != null)
        l10n.toolsSummaryRefused('${summary['refused']}'),
      // Only when it is true: a history that fit says nothing, and a
      // count beside it would read as a number of anything.
      if (summary['historyTruncated'] == true) l10n.toolsSummaryTruncated,
    ];
    if (parts.isEmpty) return null;
    return parts.join(', ');
  }

  /// Where a finished task's tap goes. Null when it goes nowhere: a
  /// running task is not done being followed, and a failure with no
  /// stored report explains itself inline.
  VoidCallback? _openAction(BuildContext context, WidgetRef ref) {
    if (task.state == 'failed') {
      final summary = _report;
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
    final summary = _report;
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
  /// per medium, playing a track into the dock.
  Future<void> _openResult(
    BuildContext context,
    WidgetRef ref,
    String pid,
  ) async {
    final messenger = ref.read(shellMessengerProvider.notifier);
    final l10n = context.l10n;
    try {
      final item = await ref.read(repositoryProvider).getItem(pid);
      if (!context.mounted) return;
      openHomeItem(context, ref, item, PlayProgress.none);
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e), channel: ShellChannel.tasks);
    }
  }

  /// A small sheet naming everything the task produced, one row each.
  Future<void> _pickResult(
    BuildContext context,
    WidgetRef ref,
    List<String> pids,
  ) async {
    final messenger = ref.read(shellMessengerProvider.notifier);
    final l10n = context.l10n;
    final List<ItemDetail> items;
    try {
      items = await Future.wait([
        for (final pid in pids) ref.read(repositoryProvider).getItem(pid),
      ]);
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e), channel: ShellChannel.tasks);
      return;
    }
    if (!context.mounted) return;
    await showWaxSheet<void>(
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
    final l10n = context.l10n;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final colors = WaxColors.of(dialogContext);
        return AlertDialog(
          key: const Key('task-summary-dialog'),
          title: Text(_typeLabel(l10n, task.type, task.summary)),
          content: SingleChildScrollView(
            child: WaxProse(
              const JsonEncoder.withIndent('  ').convert(summary),
              style: WaxType.monoData.copyWith(color: colors.textSecondary),
            ),
          ),
          actions: <Widget>[
            WaxButton(
              label: l10n.commonClose,
              kind: WaxButtonKind.text,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    );
  }

  Future<void> _dismiss(BuildContext context, WidgetRef ref) async {
    final messenger = ref.read(shellMessengerProvider.notifier);
    final l10n = context.l10n;
    try {
      await ref.read(toolTasksProvider.notifier).dismiss(task.id);
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e), channel: ShellChannel.tasks);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    // A bar for work under way: over a task that waits, a finished one
    // reads as done.
    final running =
        (task.state == 'running' && !_waiting) || task.state == 'queued';
    final waitReason = _waiting ? task.waitReason : null;
    final retryAt = task.retryAt;
    final itemTitle = task.itemTitle;
    final typeLabel = itemTitle == null
        ? _typeLabel(l10n, task.type, task.summary)
        : l10n.toolsTaskTitled(
            _typeLabel(l10n, task.type, task.summary),
            itemTitle,
          );
    final open = _openAction(context, ref);
    final error = task.error;
    final summary = task.summary;
    final summaryCounters = summary == null ? null : summaryLine(l10n, summary);
    final result = _resultLabel(l10n);
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
      if (produced.isNotEmpty) l10n.toolsProduced(produced.join(', ')),
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
                    _TaskHeading(
                      title: typeLabel,
                      status: _statusLabel(l10n),
                      statusColor: _statusColor(colors),
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
                    if (waitReason != null) ...<Widget>[
                      const SizedBox(height: WaxSpace.s4),
                      Text(
                        _waitSentence(l10n, waitReason),
                        style: WaxType.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      if (retryAt != null) _NextTry(at: retryAt),
                    ],
                    // Until a merge or split ends, its sources are in the
                    // trash and the book is missing for everyone.
                    if (task.bookInTrash &&
                        task.state == 'running') ...<Widget>[
                      const SizedBox(height: WaxSpace.s4),
                      Text(
                        l10n.toolsBookInTrash,
                        style: WaxType.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                    // A wait's error is the server's account of what it
                    // waits out: detail under the sentence, not a failure.
                    if (error != null) ...<Widget>[
                      const SizedBox(height: WaxSpace.s4),
                      _TaskAccount(
                        text: error,
                        style: WaxType.caption.copyWith(
                          color: waitReason != null
                              ? colors.textTertiary
                              : colors.error,
                        ),
                        onTap: open,
                      ),
                    ],
                    if (result != null) ...<Widget>[
                      const SizedBox(height: WaxSpace.s4),
                      Text(
                        result,
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
                  label: l10n.toolsDismiss,
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

/// When a waiting task tries next, as a time of day, and from that time
/// on that it is trying now: one timer turns the row over when the time
/// comes, so a screen left open does not read a next try behind it.
class _NextTry extends StatefulWidget {
  const _NextTry({required this.at});

  final DateTime at;

  @override
  State<_NextTry> createState() => _NextTryState();
}

class _NextTryState extends State<_NextTry> {
  Timer? _timer;
  var _due = false;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(_NextTry old) {
    super.didUpdateWidget(old);
    if (old.at != widget.at) _arm();
  }

  void _arm() {
    _timer?.cancel();
    final left = widget.at.difference(DateTime.now());
    _due = left <= Duration.zero;
    if (!_due) {
      _timer = Timer(left, () {
        if (mounted) setState(() => _due = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Text(
      _due
          ? l10n.toolsWaitTryingNow
          : l10n.toolsWaitNextTry(l10n.formatTimeOfDay(widget.at)),
      style: WaxType.caption.copyWith(
        color: WaxColors.of(context).textTertiary,
      ),
    );
  }
}

/// A row's title and its state: side by side while the state takes no
/// more than half the line, the state under the title once large type or
/// a long word would push it past the row's edge.
class _TaskHeading extends StatelessWidget {
  const _TaskHeading({
    required this.title,
    required this.status,
    required this.statusColor,
  });

  final String title;
  final String status;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final heading = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: WaxType.titleItem.copyWith(color: colors.textPrimary),
    );
    final style = WaxType.overline.copyWith(color: statusColor);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: status, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final width = painter.width;
        painter.dispose();
        if (width + WaxSpace.s8 <= constraints.maxWidth / 2) {
          return Row(
            children: <Widget>[
              Expanded(child: heading),
              const SizedBox(width: WaxSpace.s8),
              Text(status, style: style),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            heading,
            Text(status, style: style),
          ],
        );
      },
    );
  }
}

/// A task's own account, folded to its first lines when it runs longer
/// (a merge of sixty files names sixty), and selectable: it says where
/// the files are, which is what whoever puts them right copies out.
class _TaskAccount extends StatefulWidget {
  const _TaskAccount({required this.text, required this.style, this.onTap});

  final String text;
  final TextStyle style;
  final VoidCallback? onTap;

  @override
  State<_TaskAccount> createState() => _TaskAccountState();
}

class _TaskAccountState extends State<_TaskAccount> {
  /// How many lines show while folded.
  static const _lines = 4;

  var _open = false;
  var _overflows = false;

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final line = MediaQuery.textScalerOf(
      context,
    ).scale(style.fontSize! * (style.height ?? 1)).ceilToDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClampedBox(
          budget: line * _lines,
          clamped: !_open,
          onOverflow: (value) {
            if (!mounted || value == _overflows) return;
            setState(() => _overflows = value);
          },
          child: WaxProse(widget.text, style: style, onTap: widget.onTap),
        ),
        // Only where there is more: a short account gets no control that
        // opens nothing.
        if (_overflows)
          WaxButton(
            label: _open
                ? context.l10n.toolsShowLess
                : context.l10n.toolsShowAll,
            kind: WaxButtonKind.inline,
            onPressed: () => setState(() => _open = !_open),
          ),
      ],
    );
  }
}

/// A summary counter as a whole number, or null when absent.
int? _count(Object? value) => value is num ? value.toInt() : null;

/// How many entries a result's list or map holds, zero for anything else.
int _length(Object? value) => switch (value) {
  final List<Object?> list => list.length,
  final Map<Object?, Object?> map => map.length,
  _ => 0,
};

/// Everything a fix left alone, whatever the reasons, or null when none.
int? _skippedTotal(Object? skipped) {
  if (skipped is! Map) return null;
  final total = skipped.values.fold<int>(0, (sum, n) => sum + (_count(n) ?? 0));
  return total == 0 ? null : total;
}

/// Kinds a job runs per item: an upload's imports, a delete, a restore,
/// one purge. Finished, they would bury a scan.
const _perItemJobKinds = {'import', 'delete', 'restore', 'purge-trash'};

/// How many finished jobs the section keeps.
const _finishedJobsShown = 20;

/// The jobs worth a row: every running one first, then the finished
/// ones newest first, per-item kinds left out. The server already leaves
/// finished targeted jobs out of the list.
List<Job> _visibleJobs(List<Job> jobs) {
  DateTime at(Job j) =>
      j.finishedAt ?? j.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final finished = [
    for (final job in jobs)
      if (job.state != 'running' && !_perItemJobKinds.contains(job.kind)) job,
  ]..sort((a, b) => at(b).compareTo(at(a)));
  return [
    for (final job in jobs)
      if (job.state == 'running') job,
    ...finished.take(_finishedJobsShown),
  ];
}

/// The rows' keys, so a row moves with its job or task (see [indexByKey]).
Key _jobKey(Job job) => ValueKey(SemanticsIds.jobRow(job.pid));

Key _taskKey(ToolTask task) => ValueKey(SemanticsIds.taskRow(task.id));

/// A job's name, and what it ran on when that is known.
String _jobTitle(AppLocalizations l10n, Job job) {
  final label = _jobLabel(l10n, job.kind);
  final name = job.target?.name;
  return name == null || name.isEmpty
      ? label
      : l10n.toolsJobTargeted(label, name);
}

String _jobLabel(AppLocalizations l10n, String kind) => switch (kind) {
  'scan' => l10n.toolsJobScan,
  'enrich' => l10n.toolsJobEnrich,
  'analyze' => l10n.toolsJobAnalyze,
  'organize' => l10n.toolsJobOrganize,
  'organize-undo' => l10n.toolsJobOrganizeUndo,
  'empty-trash' => l10n.toolsJobEmptyTrash,
  'purge-trash' => l10n.toolsJobPurgeTrash,
  'import' => l10n.toolsJobImport,
  'delete' => l10n.toolsJobDelete,
  'restore' => l10n.toolsJobRestore,
  'remove-root' => l10n.toolsJobRemoveRoot,
  'set-kind' => l10n.toolsJobSetKind,
  _ => kind,
};

/// One catalog job: what it is, how far along, what it said, and once
/// finished what it did.
class _JobRow extends StatelessWidget {
  const _JobRow({super.key, required this.job});

  final Job job;

  WaxGlyph get _glyph => switch (job.kind) {
    'scan' => WaxIcons.refresh,
    'enrich' => WaxIcons.search,
    'analyze' => WaxIcons.waveform,
    'organize' || 'organize-undo' || 'restore' => WaxIcons.archive,
    'empty-trash' || 'purge-trash' || 'delete' => WaxIcons.delete,
    'remove-root' => WaxIcons.delete,
    'import' => WaxIcons.upload,
    'set-kind' => WaxIcons.audiobooks,
    _ => WaxIcons.hourglass,
  };

  String _stateLabel(AppLocalizations l10n) {
    final progress = job.progress;
    return switch (job.state) {
      'running' =>
        progress == null
            ? l10n.toolsStateRunning
            : l10n.toolsStateRunningPct((progress * 100).round()),
      'done' => l10n.toolsStateDone,
      'failed' => l10n.toolsStateFailed,
      'crashed' => l10n.toolsStateCrashed,
      'canceled' => l10n.toolsStateCanceled,
      final other => other,
    };
  }

  Color _stateColor(WaxColors colors) => switch (job.state) {
    'done' => colors.success,
    'failed' || 'crashed' => colors.error,
    'running' => colors.accent,
    _ => colors.textTertiary,
  };

  /// The finished job's headline counters, by kind.
  String? _resultLine(AppLocalizations l10n) {
    final r = job.result;
    if (r == null) return null;
    int? n(String key) => _count(r[key]);
    final parts = <String>[
      ...switch (job.kind) {
        'scan' => <String>[
          if (n('created') case final v?) l10n.toolsCountAdded(v),
          if (n('updated') case final v?) l10n.toolsCountUpdated(v),
          if (n('copies') case final v?) l10n.toolsCountCopies(v),
          if (n('missing') case final v?) l10n.toolsCountMissing(v),
          if (n('errored') case final v?) l10n.toolsCountErrored(v),
          // Entries the walk could not read are no file count's, and an
          // unreachable folder is none at all: the counts alone read clean.
          if (n('walkErrors') case final v? when v > 0)
            l10n.toolsCountUnreadable(v),
          if (r['rootUnreachable'] == true) l10n.toolsRootUnreachable,
        ],
        'enrich' => <String>[
          if (n('lyricsMatched') case final v?) l10n.toolsCountLyrics(v),
          if (n('artFetched') case final v?) l10n.toolsCountCovers(v),
          if (n('auxArtFetched') case final v?) l10n.toolsCountPictures(v),
        ],
        'analyze' => <String>[
          if (n('analyzed') case final v?) l10n.toolsCountAnalyzed(v),
          if (n('errored') case final v?) l10n.toolsCountErrored(v),
          if (n('fingerprintFallbacks') case final v? when v > 0)
            l10n.toolsCountFallbacks(v),
        ],
        // An undo reads like the run it takes back: what moved, and what
        // stayed where it was. The job's skipped counts every file that did
        // not move, the held ones among them: said apart, as Organize says
        // them.
        'organize' || 'organize-undo' => <String>[
          if (n('moved') case final v?) l10n.toolsCountMoved(v),
          if (n('skipped') case final v?)
            l10n.toolsCountSkipped(max(0, v - (n('held') ?? 0))),
          if (n('held') case final v? when v > 0) l10n.toolsCountHeld(v),
          if (n('errored') case final v?) l10n.toolsCountErrored(v),
          if (n('dirsPruned') case final v? when v > 0)
            l10n.toolsCountFoldersRemoved(v),
        ],
        // What the catalog let go of, as the removal's notice says it;
        // trash entries only when the library had any.
        'remove-root' => <String>[
          if (n('filesDetached') case final v?) l10n.toolsCountDetached(v),
          if (n('itemsArchived') case final v?) l10n.toolsCountArchived(v),
          if (n('trashRowsDropped') case final v? when v > 0)
            l10n.toolsCountTrashEntriesDropped(v),
        ],
        // Lists and a map rather than counts: the pids are what a client
        // follows to the items' new forms, and the line is their size.
        'set-kind' => <String>[
          l10n.toolsCountChanged(
            _length(r['converted']) + _length(r['created']),
          ),
          l10n.toolsCountFolded(_length(r['absorbed'])),
          if (_length(r['writeBackFailures']) case final v when v > 0)
            l10n.toolsCountNotWritten(v),
        ],
        _ => const <String>[],
      },
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// A scan of several libraries says what it found in each, the
  /// administrator's breakdown of the line above; one library's run is
  /// that line.
  List<String> _runLines(AppLocalizations l10n) {
    final runs = job.result?['runs'];
    if (job.kind != 'scan' || runs is! List || runs.length < 2) {
      return const [];
    }
    return [
      for (final run in runs.whereType<Map<Object?, Object?>>())
        if (run['library'] ?? run['libraryPid'] case final String name)
          run['rootUnreachable'] == true
              ? l10n.toolsScanRunUnreachable(name)
              : l10n.toolsScanRun(
                  name,
                  _count(run['audioFiles']) ?? 0,
                  _count(run['copies']) ?? 0,
                ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final message = job.message;
    final error = job.error;
    final result = _resultLine(l10n);
    final runs = _runLines(l10n);
    // Its lines stay nodes of their own, as a task row's do, rather than
    // merging into one label that changes shape as the job moves.
    return Semantics(
      identifier: SemanticsIds.jobRow(job.pid),
      container: true,
      explicitChildNodes: true,
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
                          _jobTitle(l10n, job),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WaxType.titleItem.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: WaxSpace.s8),
                      Text(
                        _stateLabel(l10n),
                        style: WaxType.overline.copyWith(
                          color: _stateColor(colors),
                        ),
                      ),
                    ],
                  ),
                  if (message != null && message.isNotEmpty) ...<Widget>[
                    const SizedBox(height: WaxSpace.s4),
                    Text(
                      message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WaxType.monoData.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                  if (job.state == 'running') ...<Widget>[
                    const SizedBox(height: WaxSpace.s8),
                    LinearProgressIndicator(value: job.progress),
                  ],
                  if (error != null) ...<Widget>[
                    const SizedBox(height: WaxSpace.s4),
                    Text(
                      error,
                      style: WaxType.caption.copyWith(color: colors.error),
                    ),
                  ],
                  if (result != null) ...<Widget>[
                    const SizedBox(height: WaxSpace.s4),
                    Text(
                      result,
                      style: WaxType.caption.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                  for (final line in runs)
                    Text(
                      line,
                      style: WaxType.caption.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
