import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

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

/// The backup archive list, newest first.
final backupsProvider = FutureProvider<List<Backup>>(
  (ref) => ref.watch(repositoryProvider).listBackups(),
);

/// Recent catalog jobs, newest first. The dashboard counts what is
/// running; the tasks screen is where one is watched.
final adminJobsProvider = FutureProvider<List<Job>>(
  (ref) => ref.watch(repositoryProvider).listJobs(),
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

/// One library's matching mode, keyed by pid.
class LibraryMatchingController extends AsyncNotifier<String> {
  LibraryMatchingController(this.libraryPid);

  final String libraryPid;

  @override
  Future<String> build() =>
      ref.watch(repositoryProvider).getLibraryMatching(libraryPid);

  Future<void> set(String mode) async {
    final stored = await ref
        .read(repositoryProvider)
        .setLibraryMatching(libraryPid, mode);
    state = AsyncData(stored);
  }
}

final libraryMatchingProvider =
    AsyncNotifierProvider.family<LibraryMatchingController, String, String>(
      LibraryMatchingController.new,
    );

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
