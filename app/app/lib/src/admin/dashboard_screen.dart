import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../connect/connect_providers.dart';
import '../health/health_controller.dart';
import '../providers.dart';
import '../review/review_controller.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../settings/listening_sections.dart';
import '../shell/shell_messages.dart';
import 'admin_console.dart';
import 'admin_providers.dart';

/// The console's front page: what needs attention, what is running, and
/// the two things an administrator starts by hand.
///
/// Below sidebar width it is also the console's navigation, because
/// there is no room for a section list beside the page and a phone
/// arriving at `/admin` has to be able to reach the rest.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    return WaxScaffold(
      title: 'Admin',
      semanticsId: SemanticsIds.adminDashboard,
      body: Padding(
        padding: sizeClass.gutter.add(
          const EdgeInsets.only(bottom: WaxSpace.s32),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _ReadOnlyBanner(),
            const _WarmingUp(),
            const _StatusTiles(),
            const SizedBox(height: WaxSpace.s24),
            const _QuickActions(),
            if (!sizeClass.hasSidebar) ...<Widget>[
              const SizedBox(height: WaxSpace.s32),
              const _SectionCards(),
            ],
          ],
        ),
      ),
    );
  }
}

/// Read-only mode is server-wide and silent everywhere else in the
/// console: every write refuses with the same message and no screen
/// explains why. The switch that causes it is two taps away.
class _ReadOnlyBanner extends ConsumerWidget {
  const _ReadOnlyBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readOnly = ref.watch(adminSettingsProvider).value?.readOnly ?? false;
    if (!readOnly) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: WaxSpace.s16),
      child: WaxBanner(
        message:
            'Read-only mode is on. Uploads, edits, and deletes are '
            'refused server-wide.',
        glyph: WaxIcons.warning,
        actionLabel: 'Server settings',
        onAction: () => context.go(WaxRoute.adminSettings),
      ),
    );
  }
}

/// What a new server is doing to itself, while it is doing it.
///
/// The first hour of a WaxDeck instance is the one where nothing looks
/// finished: a scan is indexing, artwork is arriving, health has not
/// swept, and matching is opening review entries. Saying so is the
/// difference between "still working" and "apparently broken".
///
/// The last clause is new and is what the discovery sweeper bought: a
/// scan used to index loose files and identify none of them, so this
/// copy would have had to say "run Identify from the review queue for
/// anything loose". It matches them itself now, so the promise is one
/// the server keeps.
class _WarmingUp extends ConsumerWidget {
  const _WarmingUp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    final health = ref.watch(healthProvider).value;
    final scanning =
        ref
            .watch(adminJobsProvider)
            .value
            ?.any((job) => job.kind == 'scan' && job.state == 'running') ??
        false;
    if (!scanning && !(health?.warmingUp ?? false)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: WaxSpace.s16),
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
                WaxIcon(WaxIcons.refresh, size: 16, color: colors.accent),
                const SizedBox(width: WaxSpace.s8),
                Text(
                  scanning ? 'Scanning your library' : 'Still warming up',
                  style: WaxType.titleItem.copyWith(color: colors.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: WaxSpace.s8),
            Text(
              'Files appear as they are indexed. Artwork, matching, and the '
              'health score fill in behind that: albums the scan finds are '
              'identified on their own, and anything the matcher is unsure '
              'of arrives in the review queue.',
              style: WaxType.body.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// The status row. Each tile doors into the area it counts, so a number
/// worth reacting to is one tap from the place to react.
class _StatusTiles extends ConsumerWidget {
  const _StatusTiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    final health = ref.watch(healthProvider).value;
    final review = ref.watch(reviewStatsProvider).value;
    final jobs = ref.watch(adminJobsProvider).value ?? const <Job>[];
    final backups = ref.watch(backupsProvider).value ?? const <Backup>[];
    final schedules = ref.watch(schedulesProvider).value ?? const <Schedule>[];
    final similarity = ref.watch(similarityStatusProvider).value;
    final sessions = ref.watch(playbackSessionsProvider).value;

    final running = jobs.where((j) => j.state == 'running').length;
    final lastBackup = backups.where((b) => b.state == 'done').firstOrNull;

    return Wrap(
      spacing: WaxSpace.s12,
      runSpacing: WaxSpace.s12,
      children: <Widget>[
        _tile(
          width: 220,
          child: StatTile(
            label: 'Library health',
            // Warming up is not a score of zero, and drawing one would
            // be the console's first lie to a new server.
            value: health == null
                ? '--'
                : health.warmingUp
                ? 'Warming up'
                : '${health.score.round()}',
            caption: health == null
                ? 'Loading'
                : health.warmingUp
                ? 'First sweep still running'
                : '${health.evaluatedItems} of ${health.totalItems} checked',
            glyph: WaxIcons.warning,
            tone: health != null && !health.warmingUp && health.score < 80
                ? colors.error
                : null,
            semanticsId: SemanticsIds.adminTile('health'),
            onTap: () => context.go(WaxRoute.health),
          ),
        ),
        _tile(
          width: 220,
          child: StatTile(
            label: 'Waiting for review',
            value: review == null ? '--' : '${review.pending}',
            caption: review == null
                ? 'Loading'
                : review.identifying > 0
                ? '${review.identifying} still identifying'
                : 'albums to decide',
            glyph: WaxIcons.check,
            semanticsId: SemanticsIds.adminTile('review'),
            onTap: () => context.go(WaxRoute.review),
          ),
        ),
        _tile(
          width: 220,
          child: StatTile(
            label: 'Jobs running',
            value: '$running',
            caption: running == 0 ? 'Nothing in flight' : 'scans and passes',
            glyph: WaxIcons.refresh,
            semanticsId: SemanticsIds.adminTile('jobs'),
            onTap: () => context.push(WaxRoute.tasks),
          ),
        ),
        _tile(
          width: 220,
          child: StatTile(
            label: 'Last backup',
            // When, not how big: a tile called "Last backup" is answering
            // "did one happen", and a size answers a question nobody
            // asked. The size is on the backups screen this doors into.
            value: lastBackup == null ? 'None' : _ago(lastBackup.createdAt),
            caption: lastBackup == null
                ? 'No archive yet'
                // The backup schedule's own next run. Captioning this
                // with the soonest run of any kind put "Next scan in
                // 40 min" under the backup tile.
                : _nextRunOf(schedules, 'backup') ?? 'Not scheduled',
            glyph: WaxIcons.bookmark,
            semanticsId: SemanticsIds.adminTile('backups'),
            onTap: () => context.go(WaxRoute.backups),
          ),
        ),
        if (similarity != null && similarity.enabled)
          _tile(
            width: 220,
            child: StatTile(
              label: 'Similarity coverage',
              value: '${similarity.coveragePct.round()}%',
              caption: similarity.queueDepth > 0
                  ? '${similarity.queueDepth} tracks queued'
                  : '${similarity.embeddedTracks} tracks embedded',
              glyph: WaxIcons.stats,
              semanticsId: SemanticsIds.adminTile('similarity'),
            ),
          ),
        _tile(
          width: 220,
          child: StatTile(
            label: 'Playing now',
            value: '${sessions?.length ?? 0}',
            caption: 'active playback sessions',
            glyph: WaxIcons.play,
            semanticsId: SemanticsIds.adminTile('sessions'),
          ),
        ),
      ],
    );
  }

  Widget _tile({required double width, required Widget child}) =>
      SizedBox(width: width, child: child);

  /// When one named schedule next runs, as a caption. A schedule that
  /// is off has no next run and answers null.
  static String? _nextRunOf(List<Schedule> schedules, String kind) {
    for (final schedule in schedules) {
      if (schedule.kind != kind) continue;
      final next = schedule.nextRunAt;
      if (!schedule.enabled || next == null) return null;
      return 'Next ${_relative(next)}';
    }
    return null;
  }

  static String _relative(DateTime at) {
    final delta = at.difference(DateTime.now());
    if (delta.isNegative) return 'due now';
    if (delta.inHours < 1) return 'in ${delta.inMinutes} min';
    if (delta.inHours < 24) return 'in ${delta.inHours} h';
    return 'in ${delta.inDays} d';
  }

  /// How long ago, in the same shape as the forward version.
  static String _ago(DateTime at) {
    final delta = DateTime.now().difference(at);
    if (delta.isNegative) return 'just now';
    if (delta.inHours < 1) return '${delta.inMinutes} min ago';
    if (delta.inHours < 24) return '${delta.inHours} h ago';
    return '${delta.inDays} d ago';
  }
}

/// The two long operations an administrator starts by hand. Both report
/// through the shell's messenger rather than by navigating: starting a
/// scan is not a reason to leave the page you started it from.
class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: WaxSpace.s12,
      runSpacing: WaxSpace.s12,
      children: <Widget>[
        WaxButton(
          label: 'Scan library',
          icon: WaxIcons.refresh,
          kind: WaxButtonKind.tonal,
          semanticsId: SemanticsIds.adminAction('scan'),
          onPressed: () => startLibraryScan(ref),
        ),
        WaxButton(
          label: 'Back up now',
          icon: WaxIcons.bookmark,
          kind: WaxButtonKind.tonal,
          semanticsId: SemanticsIds.adminAction('backup'),
          onPressed: () => _backup(ref),
        ),
      ],
    );
  }

  Future<void> _backup(WidgetRef ref) async {
    try {
      await ref.read(repositoryProvider).createBackup();
      ref.invalidate(backupsProvider);
      ref.read(shellMessengerProvider.notifier).show('Backup started');
    } on WaxDeckApiException catch (error) {
      ref.read(shellMessengerProvider.notifier).show(error.message);
    }
  }
}

/// Starts a scan of every library root, reporting through the shell.
///
/// Out here rather than inside the button because the command palette
/// runs the same verb from the same place, and two callers computing
/// their own "did it start" copy is two answers to one question.
Future<void> startLibraryScan(WidgetRef ref) async {
  final messenger = ref.read(shellMessengerProvider.notifier);
  try {
    await ref.read(repositoryProvider).rescanLibrary();
    ref.invalidate(adminJobsProvider);
    messenger.show('Scan started');
  } on WaxDeckApiException catch (error) {
    // A scan already running is the common answer, and the server's own
    // message says so better than a guess would.
    messenger.show(error.message);
  }
}

/// The section list, for the widths with no room for a sidebar.
class _SectionCards extends StatelessWidget {
  const _SectionCards();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final group in AdminGroup.values)
          if (group != AdminGroup.overview) ...<Widget>[
            SectionHeader(title: group.label),
            for (final section in AdminSection.values)
              if (section.group == group)
                WaxOptionRow(
                  title: section.title,
                  subtitle: section.blurb,
                  glyph: section.glyph,
                  trailing: const WaxIcon(WaxIcons.forward, size: 16),
                  semanticsId: section.semanticsId,
                  onTap: () => context.go(section.location),
                ),
            const SizedBox(height: WaxSpace.s16),
          ],
      ],
    );
  }
}
