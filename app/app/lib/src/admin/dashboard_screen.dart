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
import '../shell/pending_actions.dart';
import '../shell/semantics_ids.dart';
import '../shell/server_health.dart';
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
                children: <Widget>[FirstRunCard(step: wizard)],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // The actions first: all below them lands late or comes
                  // and goes with a scan, and a press on a button that
                  // moved reaches whatever took its place.
                  const _QuickActions(),
                  const SizedBox(height: WaxSpace.s24),
                  const _WarmingUp(),
                  const _StatusTiles(),
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
    final schedulesRead = ref.watch(schedulesProvider);
    final similarityStatus = ref.watch(similarityStatusProvider);
    final similarity = similarityStatus.value;
    final server = ref.watch(serverHealthProvider);
    final streaming = server.value?.streaming;

    return WaxStatGrid(
      tiles: <StatTile>[
        _readTile(
          l10n,
          colors,
          ref.watch(healthProvider),
          label: l10n.adminTileHealth,
          glyph: WaxIcons.warning,
          semanticsId: SemanticsIds.adminTile('health'),
          onTap: () => context.go(WaxRoute.health),
          ready: (health) => (
            // Warming up is not a score of zero, and drawing one would
            // be the console's first lie to a new server.
            value: health.warmingUp
                ? l10n.adminTileHealthWarming
                : '${health.score.round()}',
            caption: health.warmingUp
                ? l10n.adminTileFirstSweep
                : l10n.adminTileChecked(
                    health.evaluatedItems,
                    health.totalItems,
                  ),
            tone: !health.warmingUp && health.score < 80 ? colors.error : null,
          ),
        ),
        _readTile(
          l10n,
          colors,
          ref.watch(reviewStatsProvider),
          label: l10n.adminTileReview,
          glyph: WaxIcons.check,
          semanticsId: SemanticsIds.adminTile('review'),
          onTap: () => context.go(WaxRoute.review),
          ready: (review) => (
            value: '${review.pending}',
            caption: review.identifying > 0
                ? l10n.adminTileIdentifying(review.identifying)
                : l10n.adminTileAlbumsToDecide,
            tone: null,
          ),
        ),
        _readTile(
          l10n,
          colors,
          ref.watch(adminJobsProvider),
          label: l10n.adminTileJobs,
          glyph: WaxIcons.refresh,
          semanticsId: SemanticsIds.adminTile('jobs'),
          onTap: () => context.push(WaxRoute.tasks),
          ready: (jobs) {
            final running = jobs.where((j) => j.state == 'running').length;
            return (
              value: '$running',
              caption: running == 0
                  ? l10n.adminTileNothingRunning
                  : l10n.adminTileScansAndPasses,
              tone: null,
            );
          },
        ),
        _readTile(
          l10n,
          colors,
          ref.watch(backupsProvider),
          label: l10n.adminTileLastBackup,
          glyph: WaxIcons.bookmark,
          semanticsId: SemanticsIds.adminTile('backups'),
          onTap: () => context.go(WaxRoute.backups),
          ready: (backups) {
            final last = backups.where((b) => b.state == 'done').firstOrNull;
            if (last == null) {
              return (
                value: l10n.adminTileNone,
                caption: l10n.adminTileNoArchive,
                tone: null,
              );
            }
            // When, not how big: a tile called "Last backup" is answering
            // "did one happen", and a size answers a question nobody
            // asked. The size is on the backups screen this doors into.
            final when = l10n.relativeSpaced(last.createdAt);
            final schedules = schedulesRead.value;
            if (schedules == null) {
              final wait = _unread(l10n, colors, schedulesRead);
              return (value: when, caption: wait.caption, tone: wait.tone);
            }
            return (
              value: when,
              // The backup schedule's own next run. Captioning this
              // with the soonest run of any kind put "Next scan in
              // 40 min" under the backup tile.
              caption:
                  _nextRunOf(l10n, schedules, _backupSchedule) ??
                  l10n.adminTileNotScheduled,
              tone: null,
            );
          },
        ),
        // Held while its status loads, like every other tile, so the tiles
        // after it stay put: analysis is on by default. A server with it
        // off loses the slot, and so does a status that failed for good.
        if (similarity?.enabled ?? similarityStatus is! AsyncError)
          _readTile(
            l10n,
            colors,
            similarityStatus,
            label: l10n.adminTileSimilarity,
            glyph: WaxIcons.stats,
            semanticsId: SemanticsIds.adminTile('similarity'),
            ready: (status) => (
              value: '${status.coveragePct.round()}%',
              caption: status.queueDepth > 0
                  ? l10n.adminTileTracksQueued(status.queueDepth)
                  : l10n.adminTileTracksEmbedded(status.embeddedTracks),
              tone: null,
            ),
          ),
        _readTile(
          l10n,
          colors,
          ref.watch(thumbnailCacheProvider),
          label: l10n.adminTileArtworkCache,
          glyph: WaxIcons.albums,
          semanticsId: SemanticsIds.adminTile('thumbnails'),
          onTap: () => context.go(WaxRoute.trash),
          ready: (thumbs) => (
            value: l10n.formatBytes(thumbs.bytes),
            // What the cache costs is only readable against what it was
            // derived from: 40 MB is small beside 400 MB of covers and
            // large beside 20. A cache with nothing in it has no share
            // to state, and so does one whose sources somehow measure
            // zero - which is a division, not a percentage.
            caption: thumbs.rows == 0 || thumbs.artSourceBytes <= 0
                ? l10n.adminTileArtworkCacheEmpty
                : l10n.adminTileArtworkCacheShare(
                    (thumbs.bytes * 100 / thumbs.artSourceBytes).round(),
                  ),
            tone: null,
          ),
        ),
        _readTile(
          l10n,
          colors,
          ref.watch(playbackSessionsProvider),
          label: l10n.adminTilePlayingNow,
          glyph: WaxIcons.play,
          semanticsId: SemanticsIds.adminTile('sessions'),
          ready: (sessions) => (
            value: '${sessions.length}',
            caption: l10n.adminTileSessions,
            tone: null,
          ),
        ),
        // Held while health loads, like the rest; a server too old to say
        // loses the slot.
        if (!server.hasValue || streaming != null)
          _readTile(
            l10n,
            colors,
            server,
            label: l10n.adminTileStreaming,
            glyph: WaxIcons.waveform,
            semanticsId: SemanticsIds.adminTile('streaming'),
            ready: (health) => switch (health.streaming) {
              null => _unread(l10n, colors, server),
              ServerStreaming(configured: false) => (
                value: l10n.adminStreamingNotConfigured,
                caption: null,
                tone: null,
              ),
              ServerStreaming(configured: true, connected: false) => (
                value: l10n.adminStreamingUnreachable,
                caption: l10n.adminStreamingDirect,
                tone: colors.error,
              ),
              _ => (
                value: l10n.adminStreamingConnected,
                caption: null,
                tone: null,
              ),
            },
          ),
      ],
    );
  }

  /// The schedule kind whose next run captions the backup tile. Named
  /// rather than typed inline: it is a wire token, and the sweep's copy
  /// rule reads a bare string in an argument as something to translate.
  static const _backupSchedule = 'backup';

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

/// What a status tile draws: its figure, the line under it and its tone.
typedef _Face = ({String value, String? caption, Color? tone});

/// What a tile draws before its read has a value: a dash over Loading, or
/// over Could not read in the error colour once the read failed. Neither
/// reads as a zero.
_Face _unread(
  AppLocalizations l10n,
  WaxColors colors,
  AsyncValue<Object?> read,
) => (
  value: '--',
  caption: read.hasError ? l10n.adminTileCouldNotRead : l10n.adminTileLoading,
  tone: read.hasError ? colors.error : null,
);

/// A status tile over [read]: [ready] draws it from the value, and until
/// there is one it draws what [_unread] says.
StatTile _readTile<T extends Object>(
  AppLocalizations l10n,
  WaxColors colors,
  AsyncValue<T> read, {
  required String label,
  required WaxGlyph glyph,
  required String semanticsId,
  required _Face Function(T data) ready,
  VoidCallback? onTap,
}) {
  final data = read.value;
  final face = data == null ? _unread(l10n, colors, read) : ready(data);
  return StatTile(
    label: label,
    value: face.value,
    caption: face.caption,
    glyph: glyph,
    tone: face.tone,
    semanticsId: semanticsId,
    onTap: onTap,
  );
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
          busy:
              ref.watch(pendingActionsProvider).contains(PendingAction.scan) ||
              ref.watch(scanRunningProvider),
          onPressed: () => startLibraryScan(ref),
        ),
        WaxButton(
          label: l10n.adminBackupNow,
          icon: WaxIcons.bookmark,
          kind: WaxButtonKind.tonal,
          semanticsId: SemanticsIds.adminAction('backup'),
          busy: ref
              .watch(pendingActionsProvider)
              .contains(PendingAction.backup),
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
    // The backups screen's key: one backup in flight, whichever surface
    // started it.
    await container.read(pendingActionsProvider.notifier).run(
      PendingAction.backup,
      () async {
        try {
          await container.read(repositoryProvider).createBackup();
          container.invalidate(backupsProvider);
          messenger.show(l10n.adminBackupStarted);
        } on WaxDeckApiException catch (error) {
          messenger.show(explainRefusal(l10n, error));
        }
      },
    );
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
  final router = GoRouter.maybeOf(ref.context);
  await container.read(pendingActionsProvider.notifier).run(
    PendingAction.scan,
    () async {
      try {
        await container.read(repositoryProvider).rescanLibrary();
        container.invalidate(adminJobsProvider);
        messenger.show(
          l10n.adminScanStarted,
          actionLabel: router == null ? null : l10n.commonOpenTasks,
          actionSemanticsId: SemanticsIds.openTasks,
          onAction: router == null
              ? null
              : () => router.pushInShell<void>(WaxRoute.tasks),
        );
      } on WaxDeckApiException catch (error) {
        // A job already running is the common answer, said in the app's
        // words. It also proves the job list is stale, so it is read
        // again, which lets the first-run wizard move on instead of
        // re-offering it.
        container.invalidate(adminJobsProvider);
        messenger.show(
          error.code == 'conflict'
              ? l10n.adminScanBusy
              : explainRefusal(l10n, error),
        );
      }
    },
  );
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
