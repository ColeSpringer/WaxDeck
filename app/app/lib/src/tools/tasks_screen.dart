import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
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
import '../shell/in_flight.dart';
import '../shell/paged_scroll.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'job_rows.dart';
import 'tool_tasks_provider.dart';

/// Whether a task has reached a terminal state, a parked one included.
bool _finished(ToolTask task) => task.finished;

/// The row's key, so it moves with its task (see [indexByKey]).
Key _taskKey(ToolTask task) => ValueKey(SemanticsIds.taskRow(task.id));

/// The kinds in words. The three imports name a product rather than a
/// kind of work, so the name rides in as a placeholder and the sentence
/// around it is what gets translated; a health fix names its rule, which
/// its summary carries from the start, and a genre clean-up says when it
/// is only a preview.
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
  'genre-normalize' =>
    summary?['dryRun'] == true
        ? l10n.toolsTaskGenreNormalizePreview
        : l10n.toolsTaskGenreNormalize,
  'catalog-repair' => l10n.toolsTaskCatalogRepair,
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

/// A link without its scheme and a leading `www.`, port, path and query kept:
/// what tells one download from another when its source has not named it
/// (`v=` and `list=` are the difference between two videos). The row cuts
/// it where the line ends. A string that is no link stays as it came.
String _shortUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return url;
  final host = uri.host.replaceFirst(RegExp(r'^www\.'), '');
  final port = uri.hasPort ? ':${uri.port}' : '';
  final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  final query = uri.hasQuery ? '?${uri.query}' : '';
  return host + port + path + query;
}

/// How many entry titles a finished download lists before "and N more".
const _entryTitlesShown = 3;

/// Long-running library tool tasks (book merge and split, CUE split,
/// downloads, imports): state, progress, errors, and a way into what
/// each produced. The merge and split actions live on the media screens
/// they act on; this list is where their outcomes are followed,
/// dismissed one by one, or swept once they are done.
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

/// The sweep, the one piece of work the toolbar runs.
const _sweep = 'clear-finished';

class _TasksScreenState extends ConsumerState<TasksScreen>
    with PagedScroll, InFlight<TasksScreen, String> {
  @override
  void loadMore() => ref.read(toolTasksProvider.notifier).loadMore();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tasks = ref.watch(toolTasksProvider);
    fillViewportWhile(
      (tasks.value?.hasMore ?? false) && !(tasks.value?.loadingMore ?? true),
      at: tasks.value?.tasks,
    );
    // Catalog jobs are an administrator's: nobody else may list them.
    final jobs = ref.watch(isAdminProvider)
        ? visibleJobs(ref.watch(adminJobsProvider).value ?? const <Job>[])
        : const <Job>[];
    // Read off the value rather than the runtime type, for the same
    // reason the face below does: a refresh carries the previous value
    // under an AsyncLoading, and a toolbar control that vanished on
    // every reload would be its own bug. Two sources feed the sweep, so
    // either one being done offers it.
    final anyFinished =
        (tasks.value?.tasks.any(_finished) ?? false) ||
        jobs.any((job) => job.ended);
    // A sweep under way keeps its control, drawn busy, until it answers:
    // the refetch it starts can empty the list first.
    final sweeping = busyBy(_sweep);
    return WaxScaffold(
      title: l10n.toolsTitle,
      largeTitle: false,
      controller: pagedScroll,
      semanticsId: SemanticsIds.tasksScreen,
      onBack: () => context.back(),
      backSemanticsId: SemanticsIds.navBack,
      actions: <Widget>[
        if (anyFinished || busy)
          // An administrator's list holds everyone's tasks, so the
          // sweep asks whose. A member has the one.
          if (ref.watch(isAdminProvider) && !sweeping)
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
              onSelected: (all) => unawaited(_clearFinished(all: all)),
            )
          else
            WaxIconButton(
              glyph: WaxIcons.delete,
              label: l10n.toolsClearFinished,
              semanticsId: SemanticsIds.tasksClearFinished,
              busy: sweeping,
              onPressed: () => unawaited(_clearFinished()),
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
            findChildIndexCallback: indexByKey(jobs, jobKey),
            itemBuilder: (context, index) =>
                JobRow(key: jobKey(jobs[index]), job: jobs[index]),
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
    );
  }

  /// One sweep at a time: a second press or pick while one runs is
  /// dropped, so its count cannot replace the first's.
  Future<void> _clearFinished({bool all = false}) =>
      runAs(_sweep, () => _sweepFinished(all: all));

  Future<void> _sweepFinished({required bool all}) async {
    // Read before the dialog: this runs unawaited, so `ref` may be dead
    // by the time the answer comes back.
    final messenger = ref.read(shellMessengerProvider);
    final notifier = ref.read(toolTasksProvider.notifier);
    final container = ref.container;
    // Catalog jobs are an administrator's, and the choice of whose tasks
    // does not reach them: either one hides the caller's own.
    final repository = ref.read(isAdminProvider)
        ? ref.read(repositoryProvider)
        : null;
    final l10n = context.l10n;
    if (all) {
      final confirmed = await whileAsking(
        () => showDialog<bool>(
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
        ),
      );
      if (confirmed != true) return;
    }
    try {
      final cleared = await notifier.clearFinished(all: all);
      var jobs = 0;
      String? jobsError;
      if (repository != null) {
        // The tasks are already gone, so a refused job clear is told
        // beside what did clear rather than instead of it.
        try {
          jobs = await repository.clearFinishedJobs();
        } on WaxDeckApiException catch (e) {
          jobsError = explainError(l10n, e);
        }
        container.invalidate(adminJobsProvider);
      }
      // What stayed, and where to read why: each kept row says it.
      messenger.show(
        [
          if (cleared.deleted > 0 || (jobs == 0 && jobsError == null))
            l10n.toolsTasksCleared(cleared.deleted),
          if (jobs > 0) l10n.toolsJobsCleared(jobs),
          if (cleared.kept > 0) l10n.toolsTasksKept(cleared.kept),
          ?jobsError,
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

  /// A kind's mark, never a glyph a control draws: the row's own control
  /// is its trailing one. A check mark would read as an outcome beside a
  /// row that failed.
  WaxGlyph get _glyph => switch (task.type) {
    'book-merge' || 'book-split' => WaxIcons.audiobooks,
    'cue-split' => WaxIcons.music,
    _ => WaxIcons.library,
  };

  /// A running task that is waiting out a passing failure, to try again
  /// on its own: no work is under way, whatever its percentage says.
  bool get _waiting => task.state == 'running' && task.waitReason != null;

  /// A running task that was asked to stop and has not yet: it ends
  /// canceled, or done when it finished first.
  bool get _winding => task.state == 'running' && task.cancelRequested;

  /// Whether a cancel would keep work already opened: a download or a
  /// playlist sync that has finished an item has review entries staged,
  /// and says they stay. Progress alone says nothing while activity is
  /// reported: it counts the bytes of the item in hand.
  bool get _hasStaged =>
      (task.type == 'acquire' || task.type == 'playlist-sync') &&
      switch (task.activity) {
        final activity? => (activity.itemsDone ?? 0) > 0,
        null => (task.progressPct ?? 0) > 0,
      };

  /// The humanized state, with the running percentage when the engine
  /// reports one.
  String _statusLabel(AppLocalizations l10n) {
    final pct = task.progressPct;
    if (_winding) return l10n.toolsStateCanceling;
    if (_waiting) return l10n.toolsStateWaiting;
    return switch (task.state) {
      'queued' => l10n.toolsStateQueued,
      'running' =>
        // A bar that sweeps has no progress to put a number to.
        pct == null || _barValue == null
            ? l10n.toolsStateRunning
            : l10n.toolsStateRunningPct(pct.round()),
      'done' => l10n.toolsStateDone,
      'failed' => l10n.toolsStateFailed,
      'canceled' => l10n.toolsStateTaskCanceled,
      'parked' => l10n.toolsStateParked,
      final other => other,
    };
  }

  Color _statusColor(WaxColors colors) => switch (task.state) {
    _ when _winding || _waiting => colors.textSecondary,
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
        'source-retry' => l10n.toolsWaitSourceRetry,
        'rate-limited' => l10n.toolsWaitRateLimited,
        'stalled' => l10n.toolsWaitStalled,
        _ => l10n.toolsWaitOther,
      };

  /// The bar's fill, or null for one that sweeps: it fills from the
  /// reported percentage once the task reports anything, activity or a
  /// percentage above zero; before that nothing says how far along it is.
  double? get _barValue {
    final pct = task.progressPct;
    if (task.activity == null && (pct == null || pct <= 0)) return null;
    return ((pct ?? 0) / 100).clamp(0.0, 1.0);
  }

  /// What a running task is doing, in a line, or null for a phase this
  /// app has no words for. The byte part rides only on a download, and
  /// only when the source gave the size.
  static String? _activityCaption(
    AppLocalizations l10n,
    String type,
    Object? source,
    ToolTaskActivity activity,
  ) {
    final title = switch (activity.itemTitle) {
      final String t when t.isNotEmpty => t,
      _ => null,
    };
    final total = activity.itemsTotal;
    // itemsDone counts the finished, so the item in hand is the next one.
    final place = total != null && total > 1
        ? ((activity.itemsDone ?? 0) + 1).clamp(1, total).toInt()
        : null;
    final caption = switch (activity.phase) {
      'listing' =>
        type == 'acquire' && source == 'channel'
            ? l10n.toolsActivityListingChannel
            : l10n.toolsActivityListing,
      // A download or a sync opens review entries, an import reads from
      // elsewhere, and the file tools write into the library.
      'importing' =>
        type == 'acquire' || type == 'playlist-sync'
            ? l10n.toolsActivityImporting
            : type.startsWith('import-')
            ? l10n.toolsActivityImportingPlain
            : l10n.toolsActivityImportingLibrary,
      'processing' =>
        title == null
            ? l10n.toolsActivityProcessing
            : l10n.toolsActivityProcessingTitled(title),
      'downloading' => switch ((place, title)) {
        (final int n, final String t) =>
          l10n.toolsActivityDownloadingCountTitled(n, total!, t),
        (final int n, null) => l10n.toolsActivityDownloadingCount(n, total!),
        (null, final String t) => l10n.toolsActivityDownloadingTitled(t),
        (null, null) => l10n.toolsActivityDownloading,
      },
      _ => null,
    };
    final bytesTotal = activity.bytesTotal;
    if (caption == null || activity.phase != 'downloading') return caption;
    if (bytesTotal == null || bytesTotal <= 0) return caption;
    return l10n.toolsActivityBytes(
      caption,
      l10n.formatBytes(activity.bytesDone ?? 0),
      l10n.formatBytes(bytesTotal),
    );
  }

  /// The keys a task's summary carries from the moment it is queued, to
  /// be named and scoped by, and the ones a download adds for the entries
  /// it opened: none of them is a report.
  static const _queuedSummaryKeys = {
    'url',
    'source',
    'entries',
    'truncated',
    'target',
    'dryRun',
    'scoped',
    'rule',
  };

  /// The summary as a report, or null when it holds nothing past the keys
  /// the task was queued with.
  Map<String, Object?>? get _report {
    final summary = task.summary;
    if (summary == null || summary.keys.every(_queuedSummaryKeys.contains)) {
      return null;
    }
    return summary;
  }

  /// What a finished task produced, said as a fact; null when it
  /// produced nothing to count. The forward glyph says it opens.
  String? _resultLabel(AppLocalizations l10n) {
    if (task.state != 'done') return null;
    final results = task.resultPids;
    if (results.isEmpty) return null;
    if (task.type == 'acquire') return l10n.toolsReadyForReview(results.length);
    return l10n.toolsItemsProduced(results.length);
  }

  /// One line of the summary's headline counters, when present.
  static String? summaryLine(
    AppLocalizations l10n,
    Map<String, Object?> summary,
  ) {
    final parts = <String>[
      // A catalog repair's, once its closing check is in: what its steps
      // rewrote and deleted, then how that check read.
      if (summary['after'] case final Map<Object?, Object?> after) ...<String>[
        if (summaryCount(summary['sortKeysRewritten']) case final n? when n > 0)
          l10n.toolsCountSortKeys(n),
        if (summaryCount(summary['orphansDeleted']) case final n? when n > 0)
          l10n.toolsCountEntriesRemoved(n),
        if (_sum(summary, _reclaimedCounts) case final n when n > 0)
          l10n.toolsCountReclaimed(n),
        if (summaryCount(summary['searchRowsRebuilt']) case final n? when n > 0)
          l10n.toolsCountSearchRows(n),
        if (after['consistent'] == true)
          l10n.toolsSummaryConsistent
        else
          l10n.toolsSummaryDriftLeft(_sum(after, _driftCounts)),
      ],
      // A health fix's: what it filled of what it tried, and the rest. A
      // path fix moves its items rather than filling them, and holds some.
      if (summaryCount(summary['attempted']) case final attempted?) ...<String>[
        if (summaryCount(summary['moved']) case final moved?)
          l10n.toolsCountMovedOf(moved, attempted)
        else
          l10n.toolsCountFilledOf(
            summaryCount(summary['filled']) ?? 0,
            attempted,
          ),
        if (_skippedTotal(summary['held']) case final held?)
          l10n.toolsCountHeld(held),
        if (_skippedTotal(summary['skipped']) case final skipped?)
          l10n.toolsCountSkipped(skipped),
        if (summaryCount(summary['failed']) case final failed?)
          l10n.toolsCountFailed(failed),
      ],
      if (summary['matched'] != null)
        l10n.toolsSummaryMatched('${summary['matched']}'),
      // Part of the matched count, so beside it; present only when an
      // import took any.
      if (summary['ties'] != null) l10n.toolsSummaryTied('${summary['ties']}'),
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

  /// The link of a download its source has not named, for the subject
  /// line; null for any other task.
  String? get _untitledUrl {
    if (task.type != 'acquire' || (task.itemTitle?.isNotEmpty ?? false)) {
      return null;
    }
    return switch (task.summary?['url']) {
      final String url when url.isNotEmpty => _shortUrl(url),
      _ => null,
    };
  }

  /// What a task was queued with that its name leaves out: the account an
  /// import writes into and whether it only rehearsed, how many items a
  /// health fix was given.
  String? _queuedDetail(AppLocalizations l10n) {
    final summary = task.summary;
    if (summary == null) return null;
    if (task.type.startsWith('import-')) {
      final dryRun = summary['dryRun'] == true;
      return switch (summary['target']) {
        final String target when target.isNotEmpty =>
          dryRun
              ? l10n.toolsImportTargetDryRun(target)
              : l10n.toolsImportTarget(target),
        _ => dryRun ? l10n.toolsImportDryRun : null,
      };
    }
    if (task.type == 'health-fix') {
      final scoped = summaryCount(summary['scoped']);
      return scoped == null || scoped < 1
          ? null
          : l10n.toolsHealthScoped(scoped);
    }
    return null;
  }

  /// The titles of the review entries a download opened, in order.
  List<String> get _entryTitles =>
      switch ((task.type, task.summary?['entries'])) {
        ('acquire', final List<Object?> titles) => [
          for (final title in titles)
            if (title is String && title.isNotEmpty) title,
        ],
        _ => const <String>[],
      };

  /// Where a finished task's tap goes, and its name, which the forward
  /// glyph gives a screen reader. Null when it goes nowhere: a running
  /// task is not done being followed, and a failure with no stored report
  /// explains itself inline.
  ({VoidCallback go, String name})? _openAction(
    BuildContext context,
    WidgetRef ref,
  ) {
    final l10n = context.l10n;
    if (task.state == 'failed') {
      final summary = _report;
      if (summary == null) return null;
      return (
        go: () => _showSummary(context, summary),
        name: l10n.toolsOpenReport,
      );
    }
    if (task.state != 'done') return null;
    final results = task.resultPids;
    // An acquisition's results are review entries, so the review queue
    // is where they went; the same door serves when the entry pids are
    // in hand and when the server predates reporting them.
    if (task.type == 'acquire' || results.any((pid) => pid.startsWith('rv-'))) {
      return (
        go: () => context.go(WaxRoute.review),
        name: l10n.toolsOpenReviewQueue,
      );
    }
    final summary = _report;
    if (results.isEmpty) {
      if (summary == null) return null;
      return (
        go: () => _showSummary(context, summary),
        name: l10n.toolsOpenReport,
      );
    }
    return (
      go: results.length == 1
          ? () => unawaited(_openResult(context, ref, results.single))
          : () => unawaited(_pickResult(context, ref, results)),
      name: l10n.toolsOpenResult(results.length),
    );
  }

  /// Resolves one produced item and opens it the way a home card does:
  /// per medium, playing a track into the dock.
  Future<void> _openResult(
    BuildContext context,
    WidgetRef ref,
    String pid,
  ) async {
    final messenger = ref.read(shellMessengerProvider);
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
    final messenger = ref.read(shellMessengerProvider);
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
                WaxInkTappable(
                  label: item.title,
                  onPressed: () {
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
    final messenger = ref.read(shellMessengerProvider);
    final l10n = context.l10n;
    try {
      await ref.read(toolTasksProvider.notifier).dismiss(task.id);
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e), channel: ShellChannel.tasks);
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final messenger = ref.read(shellMessengerProvider);
    final notifier = ref.read(toolTasksProvider.notifier);
    final l10n = context.l10n;
    if (_hasStaged) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.toolsCancelTitle),
          content: WaxProse(l10n.toolsCancelBody),
          actions: <Widget>[
            WaxButton(
              label: l10n.toolsCancelKeep,
              kind: WaxButtonKind.text,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            WaxButton(
              label: l10n.toolsCancelAction,
              semanticsId: SemanticsIds.taskCancelConfirm,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      await notifier.cancel(task.id);
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
    final typeLabel = itemTitle == null || itemTitle.isEmpty
        ? _typeLabel(l10n, task.type, task.summary)
        : l10n.toolsTaskTitled(
            _typeLabel(l10n, task.type, task.summary),
            itemTitle,
          );
    final open = _openAction(context, ref);
    final error = task.error;
    // A failure's code says it in this app's words; the server's own
    // sentence stays under it as detail. Without a code the sentence is
    // all there is, and a code this app does not know falls back to it.
    // `internal` is what the server says when it has nothing more
    // specific, so its sentence, when there is one, is the better headline.
    final code =
        task.state == 'failed' &&
            !(task.errorCode == 'internal' && (error?.isNotEmpty ?? false))
        ? task.errorCode
        : null;
    final headline = code == null
        ? null
        : explainError(
            l10n,
            WaxDeckApiException(
              code: code,
              message: error ?? '',
              params: task.errorParams,
            ),
          );
    final coded = headline != null && headline.isNotEmpty;
    final activity = running && task.state == 'running' ? task.activity : null;
    final activityCaption = activity == null
        ? null
        : _activityCaption(l10n, task.type, task.summary?['source'], activity);
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
    final queuedDetail = _queuedDetail(l10n);
    final entryTitles = _entryTitles;
    final shownTitles = min(entryTitles.length, _entryTitlesShown);
    // What the task opened, less what is drawn; nothing under no titles.
    final unseenEntries = shownTitles == 0 ? 0 : results.length - shownTitles;
    final truncated =
        task.type == 'acquire' && task.summary?['truncated'] == true;
    final subject = [
      ?_untitledUrl,
      if (task.itemPid != null) task.itemPid!,
      if (produced.isNotEmpty) l10n.toolsProduced(produced.join(', ')),
    ].join(' · ');
    // A region, not one merged button: a raw InkWell on purpose, since the
    // row's dismiss and show-all controls cannot live inside a merged node.
    return Semantics(
      identifier: SemanticsIds.taskRow(task.id),
      container: true,
      explicitChildNodes: true,
      child: InkWell(
        onTap: open?.go,
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
                    if (queuedDetail != null) ...<Widget>[
                      const SizedBox(height: WaxSpace.s4),
                      Text(
                        queuedDetail,
                        style: WaxType.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                    RelativeTimeLine(
                      at: _finished(task)
                          ? task.finishedAt ?? task.createdAt
                          : task.createdAt,
                      kind: _finished(task)
                          ? RelativeTimeKind.finished
                          : RelativeTimeKind.queued,
                    ),
                    if (running) ...<Widget>[
                      const SizedBox(height: WaxSpace.s8),
                      WaxProgressBar(value: _barValue),
                    ],
                    if (activityCaption != null) ...<Widget>[
                      const SizedBox(height: WaxSpace.s4),
                      Text(
                        activityCaption,
                        style: WaxType.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                    // Only the phases whose source reports activity can go
                    // quiet: the others work without telling it.
                    if (activity != null &&
                        const {
                          'downloading',
                          'listing',
                        }.contains(activity.phase))
                      _Stall(at: activity.at),
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
                    if (coded) ...<Widget>[
                      const SizedBox(height: WaxSpace.s4),
                      _TaskAccount(
                        text: headline,
                        style: WaxType.caption.copyWith(color: colors.error),
                        onTap: open?.go,
                      ),
                      if (error != null &&
                          error.isNotEmpty &&
                          error != headline)
                        _TaskDetail(
                          taskId: task.id,
                          text: error,
                          style: WaxType.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                    ] else if (error != null) ...<Widget>[
                      const SizedBox(height: WaxSpace.s4),
                      _TaskAccount(
                        text: error,
                        style: WaxType.caption.copyWith(
                          color: waitReason != null
                              ? colors.textTertiary
                              : colors.error,
                        ),
                        onTap: open?.go,
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
                    for (final title in entryTitles.take(_entryTitlesShown))
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WaxType.caption.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    if (unseenEntries > 0)
                      Text(
                        l10n.toolsEntriesMore(unseenEntries),
                        style: WaxType.caption.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    if (truncated)
                      Text(
                        l10n.toolsAcquireTruncated,
                        style: WaxType.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
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
              if (open != null)
                Padding(
                  padding: const EdgeInsets.only(
                    top: WaxSpace.s4,
                    left: WaxSpace.s8,
                  ),
                  // Named, so the row's node says where a tap goes, as
                  // the glyph says it to a sighted reader.
                  child: WaxIcon(
                    WaxIcons.forward,
                    size: 16,
                    color: colors.textTertiary,
                    semanticLabel: open.name,
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
              ] else if (!task.cancelRequested) ...<Widget>[
                const SizedBox(width: WaxSpace.s8),
                WaxIconButton(
                  glyph: WaxIcons.stop,
                  label: l10n.toolsCancelTask(switch (_untitledUrl) {
                    final url? => l10n.toolsTaskTitled(typeLabel, url),
                    _ => typeLabel,
                  }),
                  semanticsId: SemanticsIds.taskCancel(task.id),
                  onPressed: () => unawaited(_cancel(context, ref)),
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

/// How long a running task has shown no sign of work, once that passes
/// two minutes: one timer turns the line on at the threshold and then
/// keeps its count a minute at a time, so a screen left open does not
/// read a stall that has cleared or one that has grown.
class _Stall extends StatefulWidget {
  const _Stall({required this.at});

  /// The last activity the server saw.
  final DateTime at;

  /// How old the last activity may be before the row says so.
  static const threshold = Duration(minutes: 2);

  @override
  State<_Stall> createState() => _StallState();
}

class _StallState extends State<_Stall> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(_Stall old) {
    super.didUpdateWidget(old);
    if (old.at != widget.at) _arm();
  }

  void _arm() {
    _timer?.cancel();
    final age = clock.now().difference(widget.at);
    final left = age < _Stall.threshold
        ? _Stall.threshold - age
        : Duration(milliseconds: 60000 - age.inMilliseconds % 60000);
    _timer = Timer(left, () {
      if (!mounted) return;
      setState(() {});
      _arm();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final age = clock.now().difference(widget.at);
    if (age < _Stall.threshold) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: WaxSpace.s4),
      child: Text(
        context.l10n.toolsActivityStalled(age.inMinutes),
        style: WaxType.caption.copyWith(
          color: WaxColors.of(context).textSecondary,
        ),
      ),
    );
  }
}

/// The server's own words under a failure it also gave a code for: shut
/// until asked, since the sentence above already says it.
class _TaskDetail extends StatefulWidget {
  const _TaskDetail({
    required this.taskId,
    required this.text,
    required this.style,
  });

  final String taskId;
  final String text;
  final TextStyle style;

  @override
  State<_TaskDetail> createState() => _TaskDetailState();
}

class _TaskDetailState extends State<_TaskDetail> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        WaxButton(
          label: _open ? l10n.toolsHideDetails : l10n.toolsShowDetails,
          kind: WaxButtonKind.inline,
          semanticsId: SemanticsIds.taskErrorDetails(widget.taskId),
          onPressed: () => setState(() => _open = !_open),
        ),
        if (_open) _TaskAccount(text: widget.text, style: widget.style),
      ],
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

/// Everything a fix left alone, whatever the reasons, or null when none.
int? _skippedTotal(Object? skipped) {
  if (skipped is! Map) return null;
  final total = skipped.values.fold<int>(
    0,
    (sum, n) => sum + (summaryCount(n) ?? 0),
  );
  return total == 0 ? null : total;
}

/// The named counters summed, an absent one as zero.
int _sum(Map<Object?, Object?> counts, List<String> keys) =>
    keys.fold(0, (sum, key) => sum + (summaryCount(counts[key]) ?? 0));

/// What a catalog repair deleted as unused, by its summary's counters.
const _reclaimedCounts = [
  'artSourcesReclaimed',
  'thumbnailsReclaimed',
  'tagProvenanceReclaimed',
  'strandedTagRowsReclaimed',
];

/// The counts of a catalog check that hold it back from consistent: all
/// but the playlist numbering and the unused rows.
const _driftCounts = [
  'itemsMissingFromSearch',
  'orphanSearchRows',
  'artistRollupDrift',
  'genreRollupDrift',
  'releaseGroupRollupDrift',
  'sortKeyDrift',
  'bookDurationDrift',
  'bookIsbnKeyDrift',
  'albumYearDrift',
  'releaseYearDrift',
];
