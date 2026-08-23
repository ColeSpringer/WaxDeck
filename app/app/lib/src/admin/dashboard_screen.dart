import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../connect/connect_providers.dart';
import '../health/health_controller.dart';
import '../l10n/l10n.dart';
import '../providers.dart';
import '../review/review_controller.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../settings/listening_sections.dart';
import '../shell/shell_messages.dart';
import 'admin_console.dart';
import 'admin_providers.dart';
import 'first_run_wizard.dart';

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
    // The guided first run takes the page rather than sitting on it: a
    // server with nothing in it has no status worth reading, and a card
    // competing with six empty tiles is what made the console feel like
    // a dashboard for somebody else's server.
    final wizard = ref.watch(firstRunWizardProvider);
    return WaxScaffold(
      title: context.l10n.adminDashboardTitle,
      semanticsId: SemanticsIds.adminDashboard,
      body: Padding(
        padding: sizeClass.gutter.add(
          const EdgeInsets.only(bottom: WaxSpace.s32),
        ),
        child: wizard != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const _ReadOnlyBanner(),
                  FirstRunCard(step: wizard),
                ],
              )
            : Column(
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
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: WaxSpace.s16),
      child: WaxBanner(
        message: l10n.adminReadOnlyBanner,
        glyph: WaxIcons.warning,
        actionLabel: l10n.adminServerTitle,
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
    final l10n = context.l10n;
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
                  scanning ? l10n.adminWarmingScanning : l10n.adminWarmingUp,
                  style: WaxType.titleItem.copyWith(color: colors.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: WaxSpace.s8),
            Text(
              l10n.adminWarmingBlurb,
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
    final l10n = context.l10n;
    final health = ref.watch(healthProvider).value;
    final review = ref.watch(reviewStatsProvider).value;
    final jobs = ref.watch(adminJobsProvider).value ?? const <Job>[];
    final backups = ref.watch(backupsProvider).value ?? const <Backup>[];
    final schedules = ref.watch(schedulesProvider).value ?? const <Schedule>[];
    final similarity = ref.watch(similarityStatusProvider).value;
    final sessions = ref.watch(playbackSessionsProvider).value;
    final thumbs = ref.watch(thumbnailCacheProvider).value;

    final running = jobs.where((j) => j.state == 'running').length;
    final lastBackup = backups.where((b) => b.state == 'done').firstOrNull;

    return Wrap(
      spacing: WaxSpace.s12,
      runSpacing: WaxSpace.s12,
      children: <Widget>[
        _tile(
          width: 220,
          child: StatTile(
            label: l10n.adminTileHealth,
            // Warming up is not a score of zero, and drawing one would
            // be the console's first lie to a new server.
            value: health == null
                ? '--'
                : health.warmingUp
                ? l10n.adminTileHealthWarming
                : '${health.score.round()}',
            caption: health == null
                ? l10n.adminTileLoading
                : health.warmingUp
                ? l10n.adminTileFirstSweep
                : l10n.adminTileChecked(
                    health.evaluatedItems,
                    health.totalItems,
                  ),
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
            label: l10n.adminTileReview,
            value: review == null ? '--' : '${review.pending}',
            caption: review == null
                ? l10n.adminTileLoading
                : review.identifying > 0
                ? l10n.adminTileIdentifying(review.identifying)
                : l10n.adminTileAlbumsToDecide,
            glyph: WaxIcons.check,
            semanticsId: SemanticsIds.adminTile('review'),
            onTap: () => context.go(WaxRoute.review),
          ),
        ),
        _tile(
          width: 220,
          child: StatTile(
            label: l10n.adminTileJobs,
            value: '$running',
            caption: running == 0
                ? l10n.adminTileNothingRunning
                : l10n.adminTileScansAndPasses,
            glyph: WaxIcons.refresh,
            semanticsId: SemanticsIds.adminTile('jobs'),
            onTap: () => context.push(WaxRoute.tasks),
          ),
        ),
        _tile(
          width: 220,
          child: StatTile(
            label: l10n.adminTileLastBackup,
            // When, not how big: a tile called "Last backup" is answering
            // "did one happen", and a size answers a question nobody
            // asked. The size is on the backups screen this doors into.
            value: lastBackup == null
                ? l10n.adminTileNone
                : l10n.relativeSpaced(lastBackup.createdAt),
            caption: lastBackup == null
                ? l10n.adminTileNoArchive
                // The backup schedule's own next run. Captioning this
                // with the soonest run of any kind put "Next scan in
                // 40 min" under the backup tile.
                : _nextRunOf(l10n, schedules, _backupSchedule) ??
                      l10n.adminTileNotScheduled,
            glyph: WaxIcons.bookmark,
            semanticsId: SemanticsIds.adminTile('backups'),
            onTap: () => context.go(WaxRoute.backups),
          ),
        ),
        if (similarity != null && similarity.enabled)
          _tile(
            width: 220,
            child: StatTile(
              label: l10n.adminTileSimilarity,
              value: '${similarity.coveragePct.round()}%',
              caption: similarity.queueDepth > 0
                  ? l10n.adminTileTracksQueued(similarity.queueDepth)
                  : l10n.adminTileTracksEmbedded(similarity.embeddedTracks),
              glyph: WaxIcons.stats,
              semanticsId: SemanticsIds.adminTile('similarity'),
            ),
          ),
        _tile(
          width: 220,
          child: StatTile(
            label: l10n.adminTileArtworkCache,
            value: thumbs == null ? '--' : l10n.formatBytes(thumbs.bytes),
            // What the cache costs is only readable against what it was
            // derived from: 40 MB is small beside 400 MB of covers and
            // large beside 20. A cache with nothing in it has no share
            // to state, and so does one whose sources somehow measure
            // zero - which is a division, not a percentage.
            caption: thumbs == null
                ? l10n.adminTileLoading
                : thumbs.rows == 0 || thumbs.artSourceBytes <= 0
                ? l10n.adminTileArtworkCacheEmpty
                : l10n.adminTileArtworkCacheShare(
                    (thumbs.bytes * 100 / thumbs.artSourceBytes).round(),
                  ),
            glyph: WaxIcons.albums,
            semanticsId: SemanticsIds.adminTile('thumbnails'),
            onTap: () => context.go(WaxRoute.trash),
          ),
        ),
        _tile(
          width: 220,
          child: StatTile(
            label: l10n.adminTilePlayingNow,
            value: '${sessions?.length ?? 0}',
            caption: l10n.adminTileSessions,
            glyph: WaxIcons.play,
            semanticsId: SemanticsIds.adminTile('sessions'),
          ),
        ),
      ],
    );
  }

  /// The schedule kind whose next run captions the backup tile. Named
  /// rather than typed inline: it is a wire token, and the sweep's copy
  /// rule reads a bare string in an argument as something to translate.
  static const _backupSchedule = 'backup';

  Widget _tile({required double width, required Widget child}) =>
      SizedBox(width: width, child: child);

  /// When one named schedule next runs, as a caption. A schedule that
  /// is off has no next run and answers null.
  static String? _nextRunOf(
    AppLocalizations l10n,
    List<Schedule> schedules,
    String kind,
  ) {
    for (final schedule in schedules) {
      if (schedule.kind != kind) continue;
      final next = schedule.nextRunAt;
      if (!schedule.enabled || next == null) return null;
      return l10n.adminTileNextRun(l10n.relativeUntil(next));
    }
    return null;
  }
}

/// The two long operations an administrator starts by hand. Both report
/// through the shell's messenger rather than by navigating: starting a
/// scan is not a reason to leave the page you started it from.
class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Wrap(
      spacing: WaxSpace.s12,
      runSpacing: WaxSpace.s12,
      children: <Widget>[
        WaxButton(
          label: l10n.adminScanLibrary,
          icon: WaxIcons.refresh,
          kind: WaxButtonKind.tonal,
          semanticsId: SemanticsIds.adminAction('scan'),
          onPressed: () => startLibraryScan(ref),
        ),
        WaxButton(
          label: l10n.adminBackupNow,
          icon: WaxIcons.bookmark,
          kind: WaxButtonKind.tonal,
          semanticsId: SemanticsIds.adminAction('backup'),
          onPressed: () => _backup(ref),
        ),
      ],
    );
  }

  Future<void> _backup(WidgetRef ref) async {
    // The container rather than `ref`, the reason the delete flow holds
    // one: the console can be left while the request is out, and a
    // `ref` past its widget throws rather than doing nothing. The
    // backup is started either way, so the list that shows it has to be
    // told either way.
    final container = ProviderScope.containerOf(ref.context, listen: false);
    final messenger = container.read(shellMessengerProvider.notifier);
    final l10n = ref.context.l10n;
    try {
      await container.read(repositoryProvider).createBackup();
      container.invalidate(backupsProvider);
      messenger.show(l10n.adminBackupStarted);
    } on WaxDeckApiException catch (error) {
      messenger.show(explainRefusal(l10n, error));
    }
  }
}

/// Starts a scan of every library root, reporting through the shell.
///
/// Out here rather than inside the button because the command palette
/// runs the same verb from the same place, and two callers computing
/// their own "did it start" copy is two answers to one question.
Future<void> startLibraryScan(WidgetRef ref) async {
  // Through the container, because the caller may not outlive the
  // request: the wizard's own step-two card is replaced the moment a
  // running scan lands, and the palette runs this from wherever it was
  // opened. The scan starts regardless, so the job list is refreshed
  // regardless.
  final container = ProviderScope.containerOf(ref.context, listen: false);
  final messenger = container.read(shellMessengerProvider.notifier);
  final l10n = ref.context.l10n;
  try {
    await container.read(repositoryProvider).rescanLibrary();
    container.invalidate(adminJobsProvider);
    messenger.show(l10n.adminScanStarted);
  } on WaxDeckApiException catch (error) {
    // A scan already running is the common answer, and the server's own
    // message says so better than a guess would. It is also proof the
    // job list this client holds is stale - it shows nothing running -
    // so the refusal refreshes it too, which is what lets a caller
    // watching that list (the first-run wizard) move on instead of
    // offering the same scan again.
    container.invalidate(adminJobsProvider);
    messenger.show(explainRefusal(l10n, error));
  }
}

/// The section list, for the widths with no room for a sidebar.
class _SectionCards extends StatelessWidget {
  const _SectionCards();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final group in AdminGroup.values)
          if (group != AdminGroup.overview) ...<Widget>[
            SectionHeader(title: group.labelOf(l10n)),
            for (final section in AdminSection.values)
              if (section.group == group)
                WaxOptionRow(
                  title: section.titleOf(l10n),
                  subtitle: section.blurbOf(l10n),
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
