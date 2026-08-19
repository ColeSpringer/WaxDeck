import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'admin_console.dart';
import 'admin_providers.dart';

/// The maintenance timetable: what runs on its own, when, and how the
/// last run went.
///
/// A screen of its own rather than a band at the bottom of the backups
/// page, which is where it lived: only one of these schedules is a
/// backup, and a scan buried under Backups is a scan nobody finds.
class SchedulesScreen extends ConsumerWidget {
  const SchedulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final l10n = context.l10n;
    final schedules = ref.watch(schedulesProvider);
    return WaxScaffold(
      title: l10n.adminSchedulesTitle,
      largeTitle: false,
      semanticsId: SemanticsIds.adminSchedules,
      onBack: adminBack(context),
      body: Padding(
        padding: sizeClass.gutter.add(
          const EdgeInsets.only(bottom: WaxSpace.s32),
        ),
        child: switch (schedules) {
          AsyncError(:final error) => ErrorState(
            title: l10n.adminSchedulesLoadError,
            message: context.explain(error),
            onRetry: () => ref.invalidate(schedulesProvider),
          ),
          AsyncData(:final value) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final schedule in value)
                Padding(
                  padding: const EdgeInsets.only(bottom: WaxSpace.s12),
                  child: _ScheduleCard(
                    key: ValueKey<String>(schedule.kind),
                    schedule: schedule,
                  ),
                ),
              if (value.isEmpty)
                EmptyState(
                  glyph: WaxIcons.recent,
                  title: l10n.adminSchedulesEmptyTitle,
                  message: l10n.adminSchedulesEmptyMessage,
                ),
            ],
          ),
          _ => const SkeletonShapes(shape: SkeletonShape.list),
        },
      ),
    );
  }
}

class _ScheduleCard extends ConsumerStatefulWidget {
  const _ScheduleCard({required this.schedule, super.key});

  final Schedule schedule;

  @override
  ConsumerState<_ScheduleCard> createState() => _ScheduleCardState();
}

class _ScheduleCardState extends ConsumerState<_ScheduleCard> {
  late final TextEditingController _cron = TextEditingController(
    text: widget.schedule.cron,
  );
  late bool _enabled = widget.schedule.enabled;
  bool _busy = false;

  /// Takes a server-side change that this card did not make.
  ///
  /// The card is keyed by kind, so its State outlives a refetch: the
  /// row above would update its last-run and next-run lines while the
  /// field kept text from before, and Save would then write that stale
  /// cron over whatever the server had. Untouched fields follow the
  /// server; a field somebody is part way through editing is left
  /// alone, because taking their typing away mid-edit is the other way
  /// to lose work.
  @override
  void didUpdateWidget(_ScheduleCard old) {
    super.didUpdateWidget(old);
    if (old.schedule.cron != widget.schedule.cron &&
        _cron.text == old.schedule.cron) {
      _cron.text = widget.schedule.cron;
    }
    if (old.schedule.enabled != widget.schedule.enabled &&
        _enabled == old.schedule.enabled) {
      _enabled = widget.schedule.enabled;
    }
  }

  static String label(AppLocalizations l10n, String kind) => switch (kind) {
    'scan' => l10n.adminScheduleScan,
    'backup' => l10n.adminScheduleBackup,
    'prune' => l10n.adminSchedulePrune,
    'analyze' => l10n.adminScheduleAnalyze,
    _ => kind,
  };

  /// What a kind costs, where that is not obvious. Only analyze has one:
  /// it is the sole pass that decodes audio, and an administrator who
  /// reads it as another scan switches it on for a large library and
  /// wonders why the machine is busy all night.
  static String blurb(AppLocalizations l10n, String kind) => switch (kind) {
    'scan' => l10n.adminScheduleScanBlurb,
    'backup' => l10n.adminScheduleBackupBlurb,
    'prune' => l10n.adminSchedulePruneBlurb,
    'analyze' => l10n.adminScheduleAnalyzeBlurb,
    _ => '',
  };

  @override
  void dispose() {
    _cron.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      await ref
          .read(schedulesProvider.notifier)
          .save(
            widget.schedule.kind,
            cron: _cron.text.trim(),
            enabled: _enabled,
          );
      messenger.show(
        l10n.adminScheduleSaved(label(l10n, widget.schedule.kind)),
      );
    } on WaxDeckApiException catch (error) {
      // The cron expression somebody just typed: the server says which
      // of its five fields it could not read.
      messenger.show(explainRefusal(l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final schedule = widget.schedule;
    final kind = schedule.kind;
    final note = blurb(l10n, kind);
    return Semantics(
      identifier: SemanticsIds.scheduleRow(kind),
      container: true,
      child: Container(
        padding: const EdgeInsets.all(WaxSpace.s16),
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: WaxRadius.card,
          border: Border.all(color: colors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label(l10n, kind),
                    style: WaxType.titleItem.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                WaxSwitch(
                  label: l10n.adminScheduleEnabledLabel(label(l10n, kind)),
                  value: _enabled,
                  semanticsId: SemanticsIds.scheduleEnabled(kind),
                  onChanged: (value) => setState(() => _enabled = value),
                ),
              ],
            ),
            if (note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: WaxSpace.s4),
                child: Text(
                  note,
                  style: WaxType.bodySmall.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            const SizedBox(height: WaxSpace.s12),
            Row(
              // Bottom-aligned now that the field carries a label above
              // it: aligned to the top, the button sits beside the word
              // rather than beside the box it acts on.
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: WaxTextField(
                    label: l10n.adminScheduleCronLabel,
                    hint: l10n.adminScheduleCronHint,
                    controller: _cron,
                    semanticsId: SemanticsIds.scheduleCron(kind),
                  ),
                ),
                const SizedBox(width: WaxSpace.s12),
                WaxButton(
                  label: l10n.commonSave,
                  kind: WaxButtonKind.tonal,
                  semanticsId: SemanticsIds.scheduleSave(kind),
                  onPressed: _busy ? null : _save,
                ),
              ],
            ),
            const SizedBox(height: WaxSpace.s8),
            _Status(schedule: schedule),
          ],
        ),
      ),
    );
  }
}

/// How a run went, as a word. The contract keeps the status an open
/// string, so one this build has not heard of draws as the server
/// wrote it.
String _statusLabel(AppLocalizations l10n, String status) => switch (status) {
  'ok' => l10n.adminScheduleStatusOk,
  'failed' => l10n.adminScheduleStatusFailed,
  _ => status,
};

/// When it last ran, how that went, and when it runs next.
class _Status extends StatelessWidget {
  const _Status({required this.schedule});

  final Schedule schedule;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final parts = <String>[
      if (schedule.lastRunAt != null)
        schedule.lastStatus == null
            ? l10n.adminScheduleLastRun(l10n.formatStamp(schedule.lastRunAt!))
            : l10n.adminScheduleLastRunStatus(
                l10n.formatStamp(schedule.lastRunAt!),
                _statusLabel(l10n, schedule.lastStatus!),
              ),
      // A disabled schedule has no next run, and the server sends none;
      // saying "next: never" for one somebody just switched off is noise.
      if (schedule.enabled && schedule.nextRunAt != null)
        l10n.adminScheduleNextRun(l10n.formatStamp(schedule.nextRunAt!)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (parts.isNotEmpty)
          Text(
            parts.join(' - '),
            style: WaxType.caption.copyWith(color: colors.textTertiary),
          ),
        if (schedule.lastError != null)
          Padding(
            padding: const EdgeInsets.only(top: WaxSpace.s4),
            child: Text(
              schedule.lastError!,
              style: WaxType.caption.copyWith(color: colors.error),
            ),
          ),
      ],
    );
  }
}
