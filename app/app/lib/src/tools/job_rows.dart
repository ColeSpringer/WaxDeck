import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../admin/admin_providers.dart';
import '../l10n/l10n.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';

/// A summary counter as a whole number, or null when absent.
int? summaryCount(Object? value) => value is num ? value.toInt() : null;

/// How many entries a result's list or map holds, zero for anything else.
int _length(Object? value) => switch (value) {
  final List<Object?> list => list.length,
  final Map<Object?, Object?> map => map.length,
  _ => 0,
};

/// How many finished jobs the section keeps.
const _finishedJobsShown = 20;

/// The jobs worth a row: every running one first, then the finished
/// ones newest first. Which finished jobs list at all is the server's
/// to say: it leaves out targeted ones and the per-item kinds (an
/// upload's imports, a delete, a restore, one purge).
List<Job> visibleJobs(List<Job> jobs) {
  DateTime at(Job j) =>
      j.finishedAt ?? j.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final finished = [
    for (final job in jobs)
      if (job.state != 'running') job,
  ]..sort((a, b) => at(b).compareTo(at(a)));
  return [
    for (final job in jobs)
      if (job.state == 'running') job,
    ...finished.take(_finishedJobsShown),
  ];
}

/// The row's key, so it moves with its job (see [indexByKey]).
Key jobKey(Job job) => ValueKey(SemanticsIds.jobRow(job.pid));

/// Which sentence a [RelativeTimeLine] puts its time in.
enum RelativeTimeKind { queued, started, finished }

/// When something happened, as "queued 5 min ago", kept current: one timer
/// turns the line over when its phrase would change, so a screen left open
/// does not read a time behind it.
class RelativeTimeLine extends StatefulWidget {
  const RelativeTimeLine({super.key, required this.at, required this.kind});

  final DateTime at;
  final RelativeTimeKind kind;

  @override
  State<RelativeTimeLine> createState() => _RelativeTimeLineState();
}

class _RelativeTimeLineState extends State<RelativeTimeLine> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(RelativeTimeLine old) {
    super.didUpdateWidget(old);
    if (old.at != widget.at) _arm();
  }

  /// Sleeps to the next moment the phrase changes: a minute's step to the
  /// hour, an hour's to the day, a day's after.
  void _arm() {
    _timer?.cancel();
    final age = clock.now().difference(widget.at);
    final unit = switch (age) {
      < const Duration(hours: 1) => const Duration(minutes: 1),
      < const Duration(days: 1) => const Duration(hours: 1),
      _ => const Duration(days: 1),
    };
    // A time ahead of this clock reads as just now until it is a minute old.
    final left = age.isNegative
        ? const Duration(minutes: 1) - age
        : Duration(
            microseconds:
                unit.inMicroseconds - age.inMicroseconds % unit.inMicroseconds,
          );
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
    final l10n = context.l10n;
    final now = clock.now();
    final when = l10n.relativeSpaced(widget.at, now: now);
    return Padding(
      padding: const EdgeInsets.only(top: WaxSpace.s4),
      child: Text(
        switch (widget.kind) {
          RelativeTimeKind.queued => l10n.toolsTimeQueued(when),
          RelativeTimeKind.started => l10n.toolsTimeStarted(when),
          RelativeTimeKind.finished => l10n.toolsTimeFinished(when),
        },
        style: WaxType.caption.copyWith(
          color: WaxColors.of(context).textTertiary,
        ),
      ),
    );
  }
}

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
/// finished what it did. A running one the server can stop has a cancel.
class JobRow extends ConsumerWidget {
  const JobRow({super.key, required this.job});

  final Job job;

  /// A running job that was asked to stop and has not yet: it ends
  /// stopped, or done when it finished first.
  bool get _winding => job.state == 'running' && job.cancelRequested;

  /// A kind's mark, never a glyph a control draws: nothing presses a row.
  WaxGlyph get _glyph => switch (job.kind) {
    'scan' ||
    'empty-trash' ||
    'purge-trash' ||
    'delete' ||
    'remove-root' ||
    'import' => WaxIcons.library,
    'enrich' => WaxIcons.fingerprint,
    'analyze' => WaxIcons.waveform,
    'organize' || 'organize-undo' || 'restore' => WaxIcons.archive,
    'set-kind' => WaxIcons.audiobooks,
    _ => WaxIcons.hourglass,
  };

  String _stateLabel(AppLocalizations l10n) {
    final progress = job.progress;
    if (_winding) return l10n.toolsStateCanceling;
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
    _ when _winding => colors.textSecondary,
    'done' => colors.success,
    'failed' || 'crashed' => colors.error,
    'running' => colors.accent,
    _ => colors.textTertiary,
  };

  /// The finished job's headline counters, by kind.
  String? _resultLine(AppLocalizations l10n) {
    final r = job.result;
    if (r == null) return null;
    int? n(String key) => summaryCount(r[key]);
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
                  summaryCount(run['audioFiles']) ?? 0,
                  summaryCount(run['copies']) ?? 0,
                ),
    ];
  }

  /// Asks first, saying what a cancel keeps: a scan, an analysis or an
  /// enrichment keeps what it did, and its next run carries on unless it
  /// was forced.
  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final messenger = ref.read(shellMessengerProvider);
    final jobs = ref.read(adminJobsProvider.notifier);
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.toolsJobCancelTitle),
        content: WaxProse(l10n.toolsJobCancelBody),
        actions: <Widget>[
          WaxButton(
            label: l10n.toolsCancelKeep,
            kind: WaxButtonKind.text,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          WaxButton(
            label: l10n.toolsJobCancelAction,
            semanticsId: SemanticsIds.jobCancelConfirm,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await jobs.cancel(job.pid);
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e), channel: ShellChannel.tasks);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final message = job.message;
    // A stopped job's state says it; the catalog's sentence for it is
    // English in every locale.
    final error = job.state == 'canceled' ? null : job.error;
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
                  if (job.ended
                          ? job.finishedAt ?? job.startedAt
                          : job.startedAt
                      case final at?)
                    RelativeTimeLine(
                      at: at,
                      kind: job.ended
                          ? RelativeTimeKind.finished
                          : RelativeTimeKind.started,
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
                    WaxProgressBar(value: job.progress),
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
            if (job.cancelable && !_winding) ...<Widget>[
              const SizedBox(width: WaxSpace.s8),
              WaxIconButton(
                glyph: WaxIcons.stop,
                label: l10n.toolsCancelTask(_jobTitle(l10n, job)),
                semanticsId: SemanticsIds.jobCancel(job.pid),
                onPressed: () => unawaited(_cancel(context, ref)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
