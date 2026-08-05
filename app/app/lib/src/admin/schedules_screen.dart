import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

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
    final schedules = ref.watch(schedulesProvider);
    return WaxScaffold(
      title: 'Schedules',
      largeTitle: false,
      semanticsId: SemanticsIds.adminSchedules,
      onBack: adminBack(context),
      body: Padding(
        padding: sizeClass.gutter.add(
          const EdgeInsets.only(bottom: WaxSpace.s32),
        ),
        child: switch (schedules) {
          AsyncError(:final error) => ErrorState(
            title: 'Could not load the schedules',
            message: error is WaxDeckApiException
                ? error.message
                : 'Something went wrong reading them.',
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
                const EmptyState(
                  glyph: WaxIcons.recent,
                  title: 'No schedules',
                  message: 'This server runs nothing on a timetable.',
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

  static String label(String kind) => switch (kind) {
    'scan' => 'Library scan',
    'backup' => 'Backup',
    'prune' => 'Prune',
    'analyze' => 'Analyze audio',
    _ => kind,
  };

  /// What a kind costs, where that is not obvious. Only analyze has one:
  /// it is the sole pass that decodes audio, and an administrator who
  /// reads it as another scan switches it on for a large library and
  /// wonders why the machine is busy all night.
  static String blurb(String kind) => switch (kind) {
    'scan' =>
      'Finds new and changed files, reads their tags, and indexes them. '
          'Cheap: it does not decode audio.',
    'backup' => 'Writes an archive of the database and its sidecars.',
    'prune' =>
      'Clears expired staging, spent tokens, and trashed files past '
          'their retention.',
    'analyze' =>
      'Measures loudness, fingerprints, and waveforms. Decodes every '
          'audio file, so a large library takes hours. Resumable: files '
          'already analyzed are skipped.',
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
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      await ref
          .read(schedulesProvider.notifier)
          .save(
            widget.schedule.kind,
            cron: _cron.text.trim(),
            enabled: _enabled,
          );
      messenger.show('${label(widget.schedule.kind)} schedule saved');
    } on WaxDeckApiException catch (error) {
      messenger.show(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final schedule = widget.schedule;
    final kind = schedule.kind;
    final note = blurb(kind);
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
                    label(kind),
                    style: WaxType.titleItem.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                WaxSwitch(
                  label: '${label(kind)} runs on a schedule',
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: WaxTextField(
                    label: 'Cron',
                    hint: 'minute hour day month weekday',
                    controller: _cron,
                    semanticsId: SemanticsIds.scheduleCron(kind),
                  ),
                ),
                const SizedBox(width: WaxSpace.s12),
                WaxButton(
                  label: 'Save',
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

/// When it last ran, how that went, and when it runs next.
class _Status extends StatelessWidget {
  const _Status({required this.schedule});

  final Schedule schedule;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final parts = <String>[
      if (schedule.lastRunAt != null)
        'Last run ${_stamp(schedule.lastRunAt!)}'
            '${schedule.lastStatus == null ? '' : ' (${schedule.lastStatus})'}',
      // A disabled schedule has no next run, and the server sends none;
      // saying "next: never" for one somebody just switched off is noise.
      if (schedule.enabled && schedule.nextRunAt != null)
        'Next ${_stamp(schedule.nextRunAt!)}',
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

  static String _stamp(DateTime at) {
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
