import 'dart:async';

import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// In-memory [AdminApi] for `FakeRepository`.
mixin FakeAdmin on FakeRepositoryState implements AdminApi {
  /// Server-level Last.fm credential state served and replaced by the
  /// admin scrobbling endpoints.
  ScrobblingAdminConfig scrobblingConfig = const ScrobblingAdminConfig(
    lastfmConfigured: false,
    lastfmSource: 'none',
    lastfmSecretSet: false,
  );

  @override
  Future<ScrobblingAdminConfig> getScrobblingConfig() async => scrobblingConfig;

  @override
  Future<ScrobblingAdminConfig> putScrobblingConfig({
    required String apiKey,
    required String secret,
  }) async {
    final error = adminError;
    if (error != null) throw error;
    // The server refuses a half-set pair, like it does.
    if (apiKey.isEmpty != secret.isEmpty) {
      throw const WaxDeckApiException(
        code: 'invalid-request',
        message: 'set both the API key and the secret, or neither',
        statusCode: 400,
      );
    }
    scrobblingConfig = apiKey.isEmpty
        ? const ScrobblingAdminConfig(
            lastfmConfigured: false,
            lastfmSource: 'none',
            lastfmSecretSet: false,
          )
        : ScrobblingAdminConfig(
            lastfmConfigured: true,
            lastfmSource: 'settings',
            lastfmApiKey: apiKey,
            lastfmSecretSet: true,
          );
    // The Last.fm slot's availability follows the credential state.
    scrobblers = [
      for (final s in scrobblers)
        if (s.service == 'lastfm')
          Scrobbler(
            service: s.service,
            available: scrobblingConfig.lastfmConfigured,
            connected: s.connected,
            username: s.username,
            apiUrl: s.apiUrl,
            lastSuccessAt: s.lastSuccessAt,
            lastError: s.lastError,
            lastErrorAt: s.lastErrorAt,
          )
        else
          s,
    ];
    return scrobblingConfig;
  }

  /// Catalog libraries the fake reports.
  final List<LibraryInfo> libraries = [];

  @override
  Future<List<LibraryInfo>> listLibraries({bool counts = false}) async {
    listLibrariesCalls.add(counts);
    return List.unmodifiable(libraries);
  }

  /// Whether each library listing asked for the per-root counts, so a
  /// test can pin that the cheap callers stay cheap.
  final List<bool> listLibrariesCalls = <bool>[];

  @override
  Future<LibraryInfo> createLibrary({
    required String name,
    required String path,
    String? media,
    bool? managed,
    bool? allowAbsent,
  }) async {
    createLibraryCalls.add((name: name, path: path, allowAbsent: allowAbsent));
    final error = createLibraryError;
    if (error != null) throw error;
    final info = LibraryInfo(
      pid: 'lb-${libraries.length + 1}',
      name: name,
      media: media ?? 'mixed',
      path: path,
    );
    libraries.add(info);
    return LibraryInfo(
      pid: info.pid,
      name: info.name,
      media: info.media,
      path: info.path,
      streamingWarning: createLibraryWarning,
      scanStarted: createLibraryScanStarted,
    );
  }

  /// Whether the next [createLibrary] reports its scan started.
  bool createLibraryScanStarted = true;

  /// What the next [createLibrary] reports about streaming, so a test
  /// can drive the degraded answer.
  String? createLibraryWarning;

  /// Each [createLibrary] call, refused or not.
  final List<({String name, String path, bool? allowAbsent})>
  createLibraryCalls = [];

  /// Thrown by [createLibrary] instead of creating, as a server refusing
  /// the path would.
  WaxDeckApiException? createLibraryError;

  /// The library pids [removeLibrary] was asked to remove.
  final List<String> removeLibraryCalls = [];

  /// Thrown by [removeLibrary] instead of starting the removal.
  WaxDeckApiException? removeLibraryError;

  /// Starts the removal: the fake drops the library at once, as the
  /// listing reads once the job has ended.
  @override
  Future<Job> removeLibrary(String libraryPid) async {
    removeLibraryCalls.add(libraryPid);
    final error = removeLibraryError;
    if (error != null) throw error;
    libraries.removeWhere((l) => l.pid == libraryPid);
    return Job(
      pid: 'jb-remove-${removeLibraryCalls.length}',
      kind: 'remove-root',
      state: 'running',
      target: JobTarget(type: 'library', pid: libraryPid),
    );
  }

  /// Scans this fake has been asked to start.
  int rescans = 0;

  /// The force flag each [rescanLibrary] call carried, in order.
  final List<bool> rescanForces = [];

  /// Thrown by [rescanLibrary] instead of starting one. The real server
  /// refuses while a catalog job is running, which is the answer a
  /// client that thinks nothing is running has to handle.
  WaxDeckApiException? rescanError;

  @override
  Future<Job> rescanLibrary({bool force = false}) async {
    rescans++;
    rescanForces.add(force);
    final error = rescanError;
    if (error != null) throw error;
    return Job(pid: 'jb-scan-$rescans', kind: 'scan', state: 'running');
  }

  /// The stored vocabulary; empty means the shipped default is in force.
  List<GenreNode> genreTree = <GenreNode>[];

  /// Normalizations started, and whether each was a dry run.
  final List<bool> genreNormalizations = <bool>[];

  @override
  Future<GenreTree> getGenreTree() async => GenreTree(
    source: genreTree.isEmpty ? 'default' : 'custom',
    genres: List.unmodifiable(genreTree),
  );

  @override
  Future<GenreTree> putGenreTree(List<GenreNode> genres) async {
    genreTree = List.of(genres);
    return getGenreTree();
  }

  @override
  Future<ToolTask> normalizeGenres({bool dryRun = false}) async {
    genreNormalizations.add(dryRun);
    return ToolTask(
      id: 'tt-genre-${genreNormalizations.length}',
      type: 'genre-normalize',
      state: 'running',
      createdAt: DateTime.utc(2026),
    );
  }

  final List<({String libraryPid, String profile})> setLibraryProfileCalls = [];

  /// Names the profile on the listed library, as the catalog would.
  @override
  Future<LibraryInfo> setLibraryProfile(
    String libraryPid,
    String profile,
  ) async {
    await libraryWriteGate?.future;
    setLibraryProfileCalls.add((libraryPid: libraryPid, profile: profile));
    final i = libraries.indexWhere((l) => l.pid == libraryPid);
    final l = libraries[i];
    return libraries[i] = LibraryInfo(
      pid: l.pid,
      name: l.name,
      media: l.media,
      mediaDeclared: l.mediaDeclared,
      path: l.path,
      itemCount: l.itemCount,
      readOnly: l.readOnly,
      folderFallback: l.folderFallback,
      managed: l.managed,
      profile: profile,
    );
  }

  /// The response cache served by [getEnrichmentCache], and each prune.
  EnrichmentCacheReport enrichmentCache = const EnrichmentCacheReport(
    rows: 0,
    bytes: 0,
  );
  final List<({int? olderThanSeconds, int? maxBytes})>
  pruneEnrichmentCacheCalls = [];
  EnrichmentCachePruneResult pruneEnrichmentCacheResult =
      const EnrichmentCachePruneResult(removed: 2, freedBytes: 2048);

  @override
  Future<EnrichmentCacheReport> getEnrichmentCache() async {
    enrichmentCacheReads++;
    return enrichmentCache;
  }

  int enrichmentCacheReads = 0;

  @override
  Future<EnrichmentCachePruneResult> pruneEnrichmentCache({
    int? olderThanSeconds,
    int? maxBytes,
  }) async {
    pruneEnrichmentCacheCalls.add((
      olderThanSeconds: olderThanSeconds,
      maxBytes: maxBytes,
    ));
    return pruneEnrichmentCacheResult;
  }

  /// Audit events, newest first, served by [listAuditEvents].
  List<AuditEvent> auditEvents = [];

  @override
  Future<AuditEventPage> listAuditEvents({
    String? cursor,
    int? limit,
    String? action,
    String? actorId,
    String? targetPid,
  }) async {
    final error = listError;
    if (error != null) throw error;
    final filtered = auditEvents
        .where((e) => action == null || e.action.startsWith(action))
        .where((e) => actorId == null || e.actorId == actorId)
        .where((e) => targetPid == null || e.targetPid == targetPid)
        .toList();
    final start = cursor == null ? 0 : int.parse(cursor);
    final pageSize = limit ?? 100;
    final end = (start + pageSize).clamp(0, filtered.length);
    return AuditEventPage(
      events: filtered.sublist(start.clamp(0, filtered.length), end),
      nextCursor: end < filtered.length ? '$end' : null,
    );
  }

  /// Thrown by the admin mutation endpoints when set.
  WaxDeckApiException? adminError;

  /// How many times the settings were read.
  int adminSettingsReads = 0;

  @override
  Future<AdminSettings> getAdminSettings() async {
    adminSettingsReads++;
    return adminSettings;
  }

  @override
  Future<AdminSettings> putAdminSettings(AdminSettingsChange change) async {
    final error = adminError;
    if (error != null) throw error;
    return adminSettings = adminSettings.copyWith(
      signupEnabled: change.signupEnabled,
      readOnly: change.readOnly,
      sonicAnalysis: change.sonicAnalysis,
      backupKeepCount: change.backupKeepCount,
      backupKeepBytes: change.backupKeepBytes,
      trashRetentionDays: change.trashRetentionDays,
      taskRetentionDays: change.taskRetentionDays,
      radioExternalArt: change.radioExternalArt,
    );
  }

  TranscodingLimits transcodingLimits = const TranscodingLimits(
    maxConcurrent: 2,
    maxConcurrentPerUser: 1,
    defaultMaxBitrateKbps: 0,
  );

  @override
  Future<TranscodingLimits> getTranscodingLimits() async => transcodingLimits;

  @override
  Future<TranscodingLimits> putTranscodingLimits(
    TranscodingLimits limits,
  ) async {
    final error = adminError;
    if (error != null) throw error;
    transcodingLimits = limits;
    return limits;
  }

  /// Engine-backed sessions the server reports in flight, how many of
  /// them are gapless queues, and how many times it has been asked (the
  /// screen reads once and again on demand, never on a timer).
  int activeTranscodeSessions = 0;
  int? activeTranscodeTimelines = 0;
  int transcodingActivityReads = 0;

  @override
  Future<TranscodingActivity> getTranscodingActivity() async {
    transcodingActivityReads++;
    final error = adminError;
    if (error != null) throw error;
    return TranscodingActivity(
      activeSessions: activeTranscodeSessions,
      activeTimelines: activeTranscodeTimelines,
    );
  }

  /// Maintenance schedules by kind.
  final Map<String, Schedule> schedules = {
    for (final kind in const ['scan', 'backup', 'prune', 'analyze', 'enrich'])
      kind: Schedule(kind: kind, cron: '0 3 * * *', enabled: false),
  };

  final List<({String kind, String cron, bool enabled})> putScheduleCalls = [];

  @override
  Future<List<Schedule>> listSchedules() async => schedules.values.toList();

  @override
  Future<Schedule> putSchedule(
    String kind, {
    required String cron,
    required bool enabled,
  }) async {
    putScheduleCalls.add((kind: kind, cron: cron, enabled: enabled));
    final error = adminError;
    if (error != null) throw error;
    // The server validates the cron expression; five fields, like it does.
    if (cron.trim().split(RegExp(r'\s+')).length != 5) {
      throw const WaxDeckApiException(
        code: 'validation',
        message: 'invalid cron expression',
        statusCode: 400,
      );
    }
    final current = schedules[kind]!;
    final stored = Schedule(
      kind: kind,
      cron: cron,
      enabled: enabled,
      lastRunAt: current.lastRunAt,
      lastStatus: current.lastStatus,
      lastError: current.lastError,
      nextRunAt: enabled ? DateTime.utc(2026, 7, 22, 3) : null,
    );
    schedules[kind] = stored;
    return stored;
  }

  /// Backup archives by id, newest last.
  final Map<String, Backup> backupsById = {};
  int _backupSeq = 0;
  int createBackupCalls = 0;

  @override
  Future<List<Backup>> listBackups() async {
    backupReads++;
    final error = listError;
    if (error != null) throw error;
    return backupsById.values.toList().reversed.toList();
  }

  /// How many times the archive list was read.
  int backupReads = 0;

  @override
  Future<Backup> createBackup() async {
    final error = adminError;
    if (error != null) throw error;
    createBackupCalls++;
    final backup = Backup(
      id: 'ba-FAKE${_backupSeq++}',
      state: 'running',
      trigger: 'manual',
      fileName: 'waxdeck-2026-07-20-$_backupSeq.tar.zst',
      createdAt: DateTime.utc(2026, 7, 20, 12),
    );
    backupsById[backup.id] = backup;
    return backup;
  }

  @override
  Future<Backup> getBackup(String backupId) async {
    final backup = backupsById[backupId];
    if (backup == null) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such backup',
        statusCode: 404,
      );
    }
    return backup;
  }

  /// Ids deleted, in order.
  final List<String> deleteBackupCalls = [];

  @override
  Future<void> deleteBackup(String backupId) async {
    final error = adminError;
    if (error != null) throw error;
    deleteBackupCalls.add(backupId);
    backupsById.remove(backupId);
  }

  /// Byte counts of each imported archive, drained from its stream.
  final List<int> importBackupByteCounts = [];

  @override
  Future<Backup> importBackup({
    required int sizeBytes,
    required Stream<List<int>> Function() openRead,
  }) async {
    final error = adminError;
    if (error != null) throw error;
    var received = 0;
    await for (final chunk in openRead()) {
      received += chunk.length;
    }
    importBackupByteCounts.add(received);
    final backup = Backup(
      id: 'ba-FAKE${_backupSeq++}',
      state: 'done',
      trigger: 'imported',
      fileName: 'imported-$_backupSeq.zip',
      sizeBytes: received,
      createdAt: DateTime.utc(2026, 7, 20, 12),
    );
    backupsById[backup.id] = backup;
    return backup;
  }

  /// Preset restore plans by backup id; [stageRestore] falls back to a
  /// clean plan.
  final Map<String, RestorePlan> restorePlans = {};

  /// The staged restore served by [getStagedRestore].
  RestorePlan? stagedRestore;

  /// Ids staged, in order.
  final List<String> stageRestoreCalls = [];
  int cancelStagedRestoreCalls = 0;

  @override
  Future<RestorePlan> stageRestore(String backupId) async {
    final error = adminError;
    if (error != null) throw error;
    stageRestoreCalls.add(backupId);
    final plan =
        restorePlans[backupId] ??
        RestorePlan(
          backupId: backupId,
          stagedAt: DateTime.utc(2026, 7, 20, 13),
          keyfilePresent: true,
          keyfileMatches: true,
        );
    stagedRestore = plan;
    return plan;
  }

  @override
  Future<RestorePlan?> getStagedRestore() async => stagedRestore;

  @override
  Future<void> cancelStagedRestore() async {
    cancelStagedRestoreCalls++;
    stagedRestore = null;
  }

  final List<
    ({
      String source,
      String? serverUrl,
      String? username,
      String? password,
      String? token,
      String? accountId,
      String? exportId,
      MigrationOptions? options,
      bool dryRun,
    })
  >
  createMigrationCalls = [];

  /// Holds [createMigration] until completed, with the call recorded.
  Completer<void>? createMigrationGate;

  @override
  Future<ToolTask> createMigration({
    required String source,
    String? serverUrl,
    String? username,
    String? password,
    String? token,
    String? accountId,
    String? exportId,
    MigrationOptions? options,
    bool dryRun = false,
  }) async {
    final error = adminError;
    if (error != null) throw error;
    createMigrationCalls.add((
      source: source,
      serverUrl: serverUrl,
      username: username,
      password: password,
      token: token,
      accountId: accountId,
      exportId: exportId,
      options: options,
      dryRun: dryRun,
    ));
    if (createMigrationGate case final gate?) await gate.future;
    final task = ToolTask(
      id: 'tt-FAKE${toolTaskSeq++}',
      type: 'import-$source',
      state: 'queued',
      createdAt: DateTime.utc(2026, 7, 20, 14),
    );
    toolTasksById[task.id] = task;
    return task;
  }

  /// Exports staged by [stageMigrationExport], newest last.
  final List<MigrationExport> stagedExports = [];

  /// Thrown by [stageMigrationExport] when set.
  Object? stageExportError;

  /// Holds [stageMigrationExport] until completed.
  Completer<void>? stageExportGate;

  @override
  Future<MigrationExport> stageMigrationExport({
    required int sizeBytes,
    required Stream<List<int>> Function() openRead,
  }) async {
    if (stageExportGate case final gate?) await gate.future;
    final error = stageExportError;
    if (error != null) throw error;
    final export = MigrationExport(
      pid: 'mx-FAKE${stagedExports.length}',
      source: 'spotify',
      files: const ['Streaming_History_Audio_2026_1.json'],
      sizeBytes: sizeBytes,
      expiresAt: DateTime.utc(2026, 7, 21, 14),
    );
    stagedExports.add(export);
    return export;
  }

  /// Export pids discarded, in order.
  final List<String> discardedExports = [];

  @override
  Future<void> discardMigrationExport(String pid) async {
    discardedExports.add(pid);
  }

  /// Trash entries served by [listTrash].
  final List<TrashEntry> trashEntries = [];

  @override
  Future<TrashList> listTrash({
    bool includeRestored = false,
    int? limit,
  }) async {
    final error = listError;
    if (error != null) throw error;
    final entries = trashEntries
        .where((e) => includeRestored || e.restoredAt == null)
        .take(limit ?? 200)
        .toList();
    return TrashList(entries: entries);
  }

  /// Ids restored, in order.
  final List<String> restoreTrashCalls = [];
  int emptyTrashCalls = 0;

  @override
  Future<void> restoreTrashEntry(String trashId) async {
    final error = adminError;
    if (error != null) throw error;
    restoreTrashCalls.add(trashId);
    final index = trashEntries.indexWhere((e) => e.id == trashId);
    if (index < 0) return;
    final entry = trashEntries[index];
    trashEntries[index] = TrashEntry(
      id: entry.id,
      itemPid: entry.itemPid,
      name: entry.name,
      reason: entry.reason,
      sizeBytes: entry.sizeBytes,
      trashedAt: entry.trashedAt,
      restoredAt: DateTime.utc(2026, 7, 20, 15),
    );
  }

  /// Holds an empty's answer until completed, for the in-flight state.
  Completer<void>? emptyTrashGate;

  @override
  Future<TrashEmptyResult> emptyTrash() async {
    final error = adminError;
    if (error != null) throw error;
    emptyTrashCalls++;
    await emptyTrashGate?.future;
    bool kept(TrashEntry e) => readOnlyTrashLibraries.contains(e.libraryPid);
    final active = trashEntries.where((e) => e.restoredAt == null).toList();
    final purgeable = active.where((e) => !kept(e)).toList();
    trashEntries.removeWhere((e) => e.restoredAt == null && !kept(e));
    return TrashEmptyResult(
      purged: purgeable.length,
      errored: 0,
      reclaimedBytes: purgeable.fold(0, (sum, e) => sum + e.sizeBytes),
      skippedReadOnly: active.length - purgeable.length,
    );
  }

  /// Libraries whose trash entries an empty leaves, as read-only ones.
  final Set<String> readOnlyTrashLibraries = {};

  final List<String> purgeTrashCalls = [];

  @override
  Future<int> purgeTrashEntry(String trashId) async {
    final error = adminError;
    if (error != null) throw error;
    purgeTrashCalls.add(trashId);
    final index = trashEntries.indexWhere((e) => e.id == trashId);
    if (index < 0) return 0;
    final entry = trashEntries.removeAt(index);
    return entry.sizeBytes;
  }

  /// The generated-thumbnail census served by [getThumbnailCache], and
  /// the prunes asked for against it.
  ThumbnailCacheReport thumbnailCache = const ThumbnailCacheReport(
    rows: 0,
    bytes: 0,
    sources: 0,
    artSources: 0,
    artSourceBytes: 0,
    rungs: <ThumbnailRung>[],
  );

  /// Each prune as (olderThanSeconds, maxBytes), absences included: the
  /// difference between an unset bound and a zero is the thing the
  /// server refuses on, so a test asserting the call has to see it.
  final List<(int?, int?)> thumbnailPrunes = [];

  @override
  Future<ThumbnailCacheReport> getThumbnailCache() async {
    final error = adminError;
    if (error != null) throw error;
    return thumbnailCache;
  }

  @override
  Future<ThumbnailPruneResult> pruneThumbnailCache({
    int? olderThanSeconds,
    int? maxBytes,
  }) async {
    final error = adminError;
    if (error != null) throw error;
    thumbnailPrunes.add((olderThanSeconds, maxBytes));
    final dropped = thumbnailCache;
    thumbnailCache = ThumbnailCacheReport(
      rows: 0,
      bytes: 0,
      sources: 0,
      artSources: dropped.artSources,
      artSourceBytes: dropped.artSourceBytes,
      rungs: const <ThumbnailRung>[],
    );
    return ThumbnailPruneResult(
      removed: dropped.rows,
      freedBytes: dropped.bytes,
    );
  }

  /// The catalog check served by [getCatalogConsistency]: clean unless a
  /// test plants drift.
  CatalogConsistency catalogConsistency = const CatalogConsistency(
    itemsMissingFromSearch: 0,
    orphanSearchRows: 0,
    artistRollupDrift: 0,
    genreRollupDrift: 0,
    releaseGroupRollupDrift: 0,
    sortKeyDrift: 0,
    bookDurationDrift: 0,
    bookIsbnKeyDrift: 0,
    albumYearDrift: 0,
    releaseYearDrift: 0,
    playlistPositionDrift: 0,
    orphanArtSources: 0,
    orphanThumbnails: 0,
    orphanTagProvenance: 0,
    strandedTagRows: 0,
    consistent: true,
    reclaimable: false,
  );

  /// How many checks were read, and the repairs started, each queued as
  /// a task. A repair refused as the server refuses one throws
  /// [catalogRepairError] when set; a check waits on [catalogCheckGate]
  /// when set, and answers what [catalogConsistency] holds by then.
  int catalogChecks = 0;
  final List<ToolTask> catalogRepairs = [];
  WaxDeckApiException? catalogRepairError;
  Completer<void>? catalogCheckGate;

  @override
  Future<CatalogConsistency> getCatalogConsistency() async {
    final error = adminError;
    if (error != null) throw error;
    catalogChecks++;
    await catalogCheckGate?.future;
    return catalogConsistency;
  }

  @override
  Future<ToolTask> repairCatalog() async {
    final error = adminError ?? catalogRepairError;
    if (error != null) throw error;
    final task = ToolTask(
      id: 'tt-repair-${catalogRepairs.length}',
      type: 'catalog-repair',
      state: 'queued',
      createdAt: DateTime.utc(2026, 10, 1),
    );
    catalogRepairs.add(task);
    toolTasksById[task.id] = task;
    return task;
  }

  /// How many times the job list has been read, for the cases about
  /// whether a client noticed its copy had gone stale.
  int jobReads = 0;

  /// How many times [clearFinishedJobs] was called.
  int clearFinishedJobCalls = 0;

  /// Thrown by [clearFinishedJobs] when set.
  Object? clearFinishedJobsError;

  /// The finished jobs each account has cleared from its own list, by
  /// account id. Still read by pid, as the server keeps them.
  final Map<String?, Set<String>> clearedJobPids = {};

  @override
  Future<int> clearFinishedJobs() async {
    clearFinishedJobCalls++;
    if (clearFinishedJobsError case final error?) throw error;
    // The server's clear: what the caller's list shows finished leaves
    // that list, and only that is counted.
    final cleared = [
      for (final job in _listedJobs())
        if (job.ended) job.pid,
    ];
    (clearedJobPids[sessionState.user?.id] ??= {}).addAll(cleared);
    return cleared.length;
  }

  @override
  Future<List<Job>> listJobs() async {
    jobReads++;
    return _listedJobs();
  }

  /// The server's listing: a finished targeted job is left out, so a
  /// burst of one-item runs does not bury the passes, except a kind
  /// change, an organize undo or a library removal, which someone asked
  /// for and is told the result of; and so is whatever this account
  /// cleared.
  List<Job> _listedJobs() {
    final cleared = clearedJobPids[sessionState.user?.id] ?? const {};
    return [
      for (final job in jobs)
        if (!cleared.contains(job.pid) &&
            (job.target == null ||
                job.state == 'running' ||
                job.kind == 'set-kind' ||
                job.kind == 'organize-undo' ||
                job.kind == 'remove-root'))
          job,
    ];
  }

  /// How many single-job reads were made.
  int jobByPidReads = 0;

  /// Thrown by [getJob] when set.
  WaxDeckApiException? getJobError;

  @override
  Future<Job> getJob(String pid) async {
    jobByPidReads++;
    final error = getJobError;
    if (error != null) throw error;
    for (final job in jobs) {
      if (job.pid == pid) return job;
    }
    throw WaxDeckApiException(
      code: 'not-found',
      message: 'no job $pid',
      statusCode: 404,
    );
  }

  final List<({String libraryPid, bool readOnly})> setLibraryReadOnlyCalls = [];

  /// Holds a library's flag or profile write in flight.
  Completer<void>? libraryWriteGate;

  /// Flips the flag on the listed library, as the catalog would.
  @override
  Future<bool> setLibraryReadOnly(String libraryPid, bool readOnly) async {
    await libraryWriteGate?.future;
    final error = adminError;
    if (error != null) throw error;
    setLibraryReadOnlyCalls.add((libraryPid: libraryPid, readOnly: readOnly));
    final i = libraries.indexWhere((l) => l.pid == libraryPid);
    if (i >= 0) {
      final l = libraries[i];
      libraries[i] = LibraryInfo(
        pid: l.pid,
        name: l.name,
        media: l.media,
        mediaDeclared: l.mediaDeclared,
        path: l.path,
        itemCount: l.itemCount,
        readOnly: readOnly,
        folderFallback: l.folderFallback,
        managed: l.managed,
        profile: l.profile,
      );
    }
    return readOnly;
  }

  final List<({String libraryPid, bool on})> setLibraryFolderFallbackCalls = [];

  final List<({String libraryPid, String media})> setLibraryMediaCalls = [];

  /// Whether [setLibraryMedia] reports the scan that applies it started.
  bool libraryMediaScanStarts = true;

  /// Changes what the listed library holds, as the catalog would.
  @override
  Future<bool> setLibraryMedia(String libraryPid, String media) async {
    await libraryWriteGate?.future;
    final error = adminError;
    if (error != null) throw error;
    setLibraryMediaCalls.add((libraryPid: libraryPid, media: media));
    final i = libraries.indexWhere((l) => l.pid == libraryPid);
    if (i >= 0) {
      final l = libraries[i];
      libraries[i] = LibraryInfo(
        pid: l.pid,
        name: l.name,
        media: media,
        mediaDeclared: l.mediaDeclared,
        path: l.path,
        itemCount: l.itemCount,
        readOnly: l.readOnly,
        folderFallback: l.folderFallback,
        managed: l.managed,
        profile: l.profile,
      );
    }
    return libraryMediaScanStarts;
  }

  /// Flips the folder fallback on the listed library, as the catalog
  /// would.
  @override
  Future<bool> setLibraryFolderFallback(String libraryPid, bool on) async {
    await libraryWriteGate?.future;
    final error = adminError;
    if (error != null) throw error;
    setLibraryFolderFallbackCalls.add((libraryPid: libraryPid, on: on));
    final i = libraries.indexWhere((l) => l.pid == libraryPid);
    if (i >= 0) {
      final l = libraries[i];
      libraries[i] = LibraryInfo(
        pid: l.pid,
        name: l.name,
        media: l.media,
        mediaDeclared: l.mediaDeclared,
        path: l.path,
        itemCount: l.itemCount,
        readOnly: l.readOnly,
        folderFallback: on,
        managed: l.managed,
        profile: l.profile,
      );
    }
    return on;
  }
}
