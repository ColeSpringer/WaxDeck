import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../notifications/notifications_controller.dart';
import '../providers.dart';

/// Server-wide switches (signup, read-only, backup retention). Shared by
/// the server settings section and the backups screen's retention
/// fields, so both see one stored value.
class AdminSettingsController extends AsyncNotifier<AdminSettings> {
  @override
  Future<AdminSettings> build() =>
      ref.watch(repositoryProvider).getAdminSettings();

  /// Replaces the stored settings; rethrows the structured error so
  /// callers can surface it next to the control that changed.
  Future<void> save(AdminSettings settings) async {
    final stored = await ref
        .read(repositoryProvider)
        .putAdminSettings(settings);
    state = AsyncData(stored);
  }
}

final adminSettingsProvider =
    AsyncNotifierProvider<AdminSettingsController, AdminSettings>(
      AdminSettingsController.new,
    );

/// Transcoding concurrency and bitrate ceilings.
class TranscodingLimitsController extends AsyncNotifier<TranscodingLimits> {
  @override
  Future<TranscodingLimits> build() =>
      ref.watch(repositoryProvider).getTranscodingLimits();

  Future<void> save(TranscodingLimits limits) async {
    final stored = await ref
        .read(repositoryProvider)
        .putTranscodingLimits(limits);
    state = AsyncData(stored);
  }
}

final transcodingLimitsProvider =
    AsyncNotifierProvider<TranscodingLimitsController, TranscodingLimits>(
      TranscodingLimitsController.new,
    );

/// What the transcoder is doing right now, read once when the settings
/// screen opens and again when somebody asks.
///
/// Deliberately not polled: this is a form being edited, not a monitor,
/// and a number that moved while nobody was looking is a distraction
/// under three fields somebody is typing in. The refresh affordance is
/// the whole of the freshness story.
final transcodingActivityProvider = FutureProvider<TranscodingActivity>(
  (ref) => ref.watch(repositoryProvider).getTranscodingActivity(),
);

/// The three maintenance schedules, refetched after every save so last
/// and next run times stay honest.
class SchedulesController extends AsyncNotifier<List<Schedule>> {
  @override
  Future<List<Schedule>> build() =>
      ref.watch(repositoryProvider).listSchedules();

  /// Saves one schedule; rethrows validation errors (a bad cron) for
  /// the row to show.
  Future<void> save(
    String kind, {
    required String cron,
    required bool enabled,
  }) async {
    final stored = await ref
        .read(repositoryProvider)
        .putSchedule(kind, cron: cron, enabled: enabled);
    final current = state.value;
    if (current == null) return;
    state = AsyncData([
      for (final schedule in current)
        if (schedule.kind == stored.kind) stored else schedule,
    ]);
  }
}

final schedulesProvider =
    AsyncNotifierProvider<SchedulesController, List<Schedule>>(
      SchedulesController.new,
    );

/// How often the archive list is read while one is being made.
const backupsRunningPoll = Duration(seconds: 5);

/// The backup archive list, newest first: read again every few seconds
/// while an archive is being made, and when the inbox files the news that
/// one finished or failed.
class BackupsController extends AsyncNotifier<List<Backup>> {
  @override
  Future<List<Backup>> build() async {
    // This build's own ref: [ref] answers for whichever build is newest.
    final built = ref;
    // News is a backup row this read had not seen, by id: the server's
    // clock is not this device's.
    bool isBackupRow(WaxNotification row) =>
        row.event == 'backup-completed' || row.event == 'backup-failed';
    final known = {
      for (final row in ref.read(notificationsProvider).value?.rows ?? [])
        if (isBackupRow(row)) row.id,
    };
    ref.listen(notificationsProvider, (_, next) {
      final news = next.value?.rows.any(
        (row) => isBackupRow(row) && !known.contains(row.id),
      );
      if ((news ?? false) && built.mounted) built.invalidateSelf();
    });
    final backups = await ref.watch(repositoryProvider).listBackups();
    if (backups.any((b) => b.state == 'running') && built.mounted) {
      final poll = Timer(backupsRunningPoll, () {
        if (built.mounted) built.invalidateSelf();
      });
      built.onDispose(poll.cancel);
    }
    return backups;
  }
}

final backupsProvider = AsyncNotifierProvider<BackupsController, List<Backup>>(
  BackupsController.new,
);

/// Recent catalog jobs, newest first, after any still running that newer
/// ones pushed out of the window. The dashboard counts what is running;
/// the tasks screen is where one is watched; the sync binder refetches
/// it on every job marker. An administrator's: anyone else is refused,
/// and a refusal is not retried.
final adminJobsProvider = FutureProvider<List<Job>>(
  (ref) => ref.watch(repositoryProvider).listJobs(),
  retry: retryUnlessRefused,
);

/// Whether a library scan is running, as far as the job list knows. A
/// scan covers every root, so every scan trigger reads this one.
final scanRunningProvider = Provider<bool>(
  (ref) =>
      ref
          .watch(adminJobsProvider)
          .value
          ?.any((job) => job.kind == 'scan' && job.state == 'running') ??
      false,
);

/// The catalog's libraries: names, paths, and the per-library switches.
///
/// No counts. This feeds the permission editor's grant list and the
/// review screen's matching menu as well as the libraries table, and a
/// count is a scan per library - see [libraryCountsProvider], which the
/// one screen that draws the number watches instead.
final librariesProvider = FutureProvider<List<LibraryInfo>>(
  (ref) => ref.watch(repositoryProvider).listLibraries(),
);

/// The same libraries, with what each holds. Separate because the count
/// costs a scan per root: the table that shows it asks, and nothing else
/// pays.
final libraryCountsProvider = FutureProvider<List<LibraryInfo>>(
  (ref) => ref.watch(repositoryProvider).listLibraries(counts: true),
);

/// One library's matching behavior, keyed by pid.
class LibraryMatchingController extends AsyncNotifier<LibraryMatching> {
  LibraryMatchingController(this.libraryPid);

  final String libraryPid;

  /// The write in flight, so a second tap queues behind it instead of
  /// both reading the same base and one replace erasing the other.
  Future<void>? _pending;

  @override
  Future<LibraryMatching> build() =>
      ref.watch(repositoryProvider).getLibraryMatching(libraryPid);

  Future<void> setMode(String mode) => _update((m) => m.copyWith(mode: mode));

  Future<void> setSinglesAutoApply(bool on) =>
      _update((m) => m.copyWith(singlesAutoApply: on));

  /// The PUT replaces the whole object, so every write re-reads the
  /// stored document first: this cache is one admin's, and replacing
  /// from it would silently undo what another admin stored since.
  Future<void> _update(LibraryMatching Function(LibraryMatching) change) {
    final ahead = _pending;
    final run = () async {
      if (ahead != null) {
        try {
          await ahead;
        } on Object {
          // A failure ahead in the queue is that caller's to report;
          // this write still starts from what the server holds.
        }
      }
      final repo = ref.read(repositoryProvider);
      final current = await repo.getLibraryMatching(libraryPid);
      final stored = await repo.setLibraryMatching(libraryPid, change(current));
      state = AsyncData(stored);
    }();
    _pending = run;
    return run;
  }
}

final libraryMatchingProvider =
    AsyncNotifierProvider.family<
      LibraryMatchingController,
      LibraryMatching,
      String
    >(LibraryMatchingController.new);

/// The canonical genre vocabulary, with the edits the editor applies.
class GenreTreeController extends AsyncNotifier<GenreTree> {
  @override
  Future<GenreTree> build() => ref.watch(repositoryProvider).getGenreTree();

  /// Stores a replacement vocabulary. An empty list clears the override
  /// and returns the instance to the shipped default, which is the
  /// contract's own "revert" and why this takes no separate verb.
  Future<void> save(List<GenreNode> genres) async {
    final stored = await ref.read(repositoryProvider).putGenreTree(genres);
    state = AsyncData(stored);
  }
}

final genreTreeProvider = AsyncNotifierProvider<GenreTreeController, GenreTree>(
  GenreTreeController.new,
);

/// The staged restore, or null when none is staged.
final stagedRestoreProvider = FutureProvider<RestorePlan?>(
  (ref) => ref.watch(repositoryProvider).getStagedRestore(),
);

/// Whether the trash listing includes already-restored entries.
class TrashIncludeRestoredController extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle(bool include) => state = include;
}

final trashIncludeRestoredProvider =
    NotifierProvider<TrashIncludeRestoredController, bool>(
      TrashIncludeRestoredController.new,
    );

/// The server-side trash, with restore and empty acting on it.
class TrashController extends AsyncNotifier<TrashList> {
  @override
  Future<TrashList> build() {
    final includeRestored = ref.watch(trashIncludeRestoredProvider);
    return ref
        .watch(repositoryProvider)
        .listTrash(includeRestored: includeRestored);
  }

  Future<void> restore(String trashId) async {
    await ref.read(repositoryProvider).restoreTrashEntry(trashId);
    if (!ref.mounted) return;
    ref.invalidateSelf();
  }

  Future<TrashEmptyResult> empty() async {
    final result = await ref.read(repositoryProvider).emptyTrash();
    if (ref.mounted) ref.invalidateSelf();
    return result;
  }

  Future<int> purge(String trashId) async {
    final reclaimed = await ref
        .read(repositoryProvider)
        .purgeTrashEntry(trashId);
    if (ref.mounted) ref.invalidateSelf();
    return reclaimed;
  }
}

final trashProvider = AsyncNotifierProvider<TrashController, TrashList>(
  TrashController.new,
);

/// The generated-thumbnail cache, with the prune acting on it.
///
/// Read on the dashboard tile and on the trash screen's card, which is
/// why it is a notifier rather than two reads: a prune invalidates the
/// one provider and both surfaces re-read.
class ThumbnailCacheController extends AsyncNotifier<ThumbnailCacheReport> {
  @override
  Future<ThumbnailCacheReport> build() =>
      ref.watch(repositoryProvider).getThumbnailCache();

  /// Drops every generated copy. A budget of zero is the request, not
  /// an absent bound: the server refuses a policy with neither axis
  /// set rather than reading it as "everything".
  Future<ThumbnailPruneResult> clear() async {
    final result = await ref
        .read(repositoryProvider)
        .pruneThumbnailCache(maxBytes: 0);
    if (ref.mounted) ref.invalidateSelf();
    return result;
  }
}

/// No retry, which is what makes a failure visible.
///
/// Riverpod 3 re-runs a build that threw - ten attempts over about
/// thirteen seconds - and reports `AsyncLoading` carrying the previous
/// error in between, so the error arm is never selected and both
/// surfaces draw their skeleton for the whole backoff. A census is a
/// read of something already computed: a server that predates the
/// endpoint answers 404 and will keep answering 404, and one that is
/// busy is worth telling the operator about rather than hiding from
/// them.
final thumbnailCacheProvider =
    AsyncNotifierProvider<ThumbnailCacheController, ThumbnailCacheReport>(
      ThumbnailCacheController.new,
      retry: (_, _) => null,
    );

/// Pending signup requests, oldest first.
final signupRequestsProvider = FutureProvider<List<UserAccount>>(
  (ref) async =>
      (await ref.watch(repositoryProvider).listSignupRequests()).users,
);

/// Every invite, live and spent.
final invitesProvider = FutureProvider<List<Invite>>(
  (ref) => ref.watch(repositoryProvider).listInvites(),
);

/// One library's read-only flag, keyed by pid.
class LibraryReadOnlyController extends AsyncNotifier<bool> {
  LibraryReadOnlyController(this.libraryPid);

  final String libraryPid;

  @override
  Future<bool> build() =>
      ref.watch(repositoryProvider).getLibraryReadOnly(libraryPid);

  Future<void> set(bool readOnly) async {
    final stored = await ref
        .read(repositoryProvider)
        .setLibraryReadOnly(libraryPid, readOnly);
    state = AsyncData(stored);
  }
}

final libraryReadOnlyProvider =
    AsyncNotifierProvider.family<LibraryReadOnlyController, bool, String>(
      LibraryReadOnlyController.new,
    );

/// How often a running pass is asked after: no event says it ended.
const enrichmentRunningPoll = Duration(seconds: 5);

/// Enrichment's roster, coverage, phases and last pass, with the source
/// order and a run acting on it.
class EnrichmentStatusController extends AsyncNotifier<EnrichmentStatus> {
  @override
  Future<EnrichmentStatus> build() async {
    final repository = ref.watch(repositoryProvider);
    // This build's own ref: [ref] answers for whichever build is newest.
    final built = ref;
    final status = await repository.getEnrichmentStatus();
    if (status.running && built.mounted) {
      final poll = Timer.periodic(
        enrichmentRunningPoll,
        (_) => unawaited(_follow(built, repository, status.runningJob)),
      );
      built.onDispose(poll.cancel);
    }
    return status;
  }

  /// Reads the status again once the pass has ended, asking after its
  /// job alone when the status named one; a failed job read waits a beat.
  Future<void> _follow(
    Ref built,
    WaxDeckRepository repository,
    String? job,
  ) async {
    if (job != null) {
      try {
        final state = (await repository.getJob(job)).state;
        if (!const {'done', 'failed', 'crashed', 'canceled'}.contains(state)) {
          return;
        }
      } on WaxDeckApiException catch (e) {
        if (e.statusCode == null || e.statusCode! >= 500) return;
      }
    }
    if (built.mounted) built.invalidateSelf();
  }

  /// Saves the order and switches over this server's own sources, then
  /// reads the status again: a read already out answers the old order.
  Future<EnrichmentStatus> saveSources(List<EnrichmentSource> sources) async {
    final repository = ref.read(repositoryProvider);
    try {
      final stored = await repository.putEnrichmentSources(sources);
      if (ref.mounted) state = AsyncData(stored);
      return stored;
    } finally {
      if (ref.mounted) ref.invalidateSelf();
    }
  }

  /// Starts a pass; the status and the jobs are read again either way.
  Future<String> run({
    bool force = false,
    List<String> forcePhases = const [],
  }) async {
    final repository = ref.read(repositoryProvider);
    try {
      return await repository.runEnrichment(
        force: force,
        forcePhases: forcePhases,
      );
    } finally {
      if (ref.mounted) {
        ref.invalidateSelf();
        ref.invalidate(adminJobsProvider);
      }
    }
  }
}

final enrichmentStatusProvider =
    AsyncNotifierProvider.autoDispose<
      EnrichmentStatusController,
      EnrichmentStatus
    >(EnrichmentStatusController.new, retry: retryUnlessRefused);

/// The enrichment response cache, with the prune acting on it.
class EnrichmentCacheController extends AsyncNotifier<EnrichmentCacheReport> {
  @override
  Future<EnrichmentCacheReport> build() =>
      ref.watch(repositoryProvider).getEnrichmentCache();

  Future<EnrichmentCachePruneResult> prune({
    int? olderThanSeconds,
    int? maxBytes,
  }) async {
    final result = await ref
        .read(repositoryProvider)
        .pruneEnrichmentCache(
          olderThanSeconds: olderThanSeconds,
          maxBytes: maxBytes,
        );
    if (ref.mounted) ref.invalidateSelf();
    return result;
  }
}

final enrichmentCacheProvider =
    AsyncNotifierProvider.autoDispose<
      EnrichmentCacheController,
      EnrichmentCacheReport
    >(EnrichmentCacheController.new, retry: (_, _) => null);
