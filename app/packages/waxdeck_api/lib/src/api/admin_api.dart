import 'dart:async';

import '../models.dart';

/// Administration: libraries, settings, backups, migrations, trash and jobs.
abstract interface class AdminApi {
  /// `GET /libraries`: every catalog library. [counts] asks for each
  /// root's item count, which is a scan per library, so only the screen
  /// that shows the number passes it.
  Future<List<LibraryInfo>> listLibraries({bool counts = false});

  /// `POST /libraries`: registers a new library root at runtime,
  /// returning the created library. Its `streamingWarning` is set when
  /// the root exists but the streaming sidecar did not take it.
  /// [allowAbsent] registers a folder mounted later. Administrators only.
  Future<LibraryInfo> createLibrary({
    required String name,
    required String path,
    String? media,
    bool? managed,
    bool? allowAbsent,
  });

  /// `DELETE /libraries/{pid}`: takes a library out of the catalog, its
  /// files staying on disk, returning the job doing it. Administrators
  /// only.
  Future<Job> removeLibrary(String libraryPid);

  /// `POST /library/rescan`: starts a scan of every library root,
  /// returning the job tracking it. [force] re-reads files whose size
  /// and mtime are unchanged (the repair pass; curated fields stay
  /// preserved). Administrators only.
  Future<Job> rescanLibrary({bool force = false});

  /// `GET /admin/genre-tree`: the canonical genre vocabulary in force
  /// (administrators).
  Future<GenreTree> getGenreTree();

  /// `PUT /admin/genre-tree`: replaces the vocabulary, returning what is
  /// now in force. An empty list clears the override and returns the
  /// instance to the shipped default (administrators).
  Future<GenreTree> putGenreTree(List<GenreNode> genres);

  /// `POST /admin/genre-normalize`: starts a full-catalog normalization
  /// as a background task; [dryRun] reports the same numbers without
  /// writing (administrators).
  Future<ToolTask> normalizeGenres({bool dryRun = false});

  /// `PUT /libraries/{pid}/profile`: the profile a managed library is
  /// laid out by.
  Future<LibraryInfo> setLibraryProfile(String libraryPid, String profile);

  /// `GET /admin/enrichment-cache`: what the response cache holds.
  Future<EnrichmentCacheReport> getEnrichmentCache();

  /// `POST /admin/enrichment-cache/prune`: drops cached answers older
  /// than [olderThanSeconds], or down to [maxBytes].
  Future<EnrichmentCachePruneResult> pruneEnrichmentCache({
    int? olderThanSeconds,
    int? maxBytes,
  });

  /// `GET /admin/audit`: keyset-paginated audit events, newest first.
  /// [action] filters by action prefix (administrators).
  Future<AuditEventPage> listAuditEvents({
    String? cursor,
    int? limit,
    String? action,
    String? actorId,
    String? targetPid,
  });

  /// `GET /admin/settings`: the server-wide switches (administrators).
  Future<AdminSettings> getAdminSettings();

  /// `PUT /admin/settings`: writes the server-wide switches [change] names
  /// and keeps the rest as stored (administrators).
  Future<AdminSettings> putAdminSettings(AdminSettingsChange change);

  /// `GET /admin/transcoding`: the transcoding limits (administrators).
  Future<TranscodingLimits> getTranscodingLimits();

  /// `PUT /admin/transcoding`: replaces the transcoding limits
  /// (administrators).
  Future<TranscodingLimits> putTranscodingLimits(TranscodingLimits limits);

  /// `GET /admin/transcoding/activity`: the engine-backed streams in
  /// flight, for reading beside the limits (administrators).
  Future<TranscodingActivity> getTranscodingActivity();

  /// `GET /admin/scrobbling`: whether the server holds Last.fm API
  /// credentials and where they came from; the shared secret is never
  /// read back (administrators).
  Future<ScrobblingAdminConfig> getScrobblingConfig();

  /// `PUT /admin/scrobbling`: stores a Last.fm API credential pair.
  /// Both values empty clears the stored pair, falling back to
  /// environment credentials when the server has them; a half-set pair
  /// fails with `invalid-request` (administrators).
  Future<ScrobblingAdminConfig> putScrobblingConfig({
    required String apiKey,
    required String secret,
  });

  /// `GET /admin/schedules`: the three maintenance schedules
  /// (administrators).
  Future<List<Schedule>> listSchedules();

  /// `PUT /admin/schedules/{kind}`: replaces one schedule's cron and
  /// enablement; [kind] is `scan`, `backup`, or `prune`
  /// (administrators).
  Future<Schedule> putSchedule(
    String kind, {
    required String cron,
    required bool enabled,
  });

  /// `GET /admin/backups`: every backup archive, newest first
  /// (administrators).
  Future<List<Backup>> listBackups();

  /// `POST /admin/backups`: starts a backup now (administrators).
  Future<Backup> createBackup();

  /// `GET /admin/backups/{backupId}`: one archive's state
  /// (administrators).
  Future<Backup> getBackup(String backupId);

  /// `DELETE /admin/backups/{backupId}`: deletes an archive
  /// (administrators).
  Future<void> deleteBackup(String backupId);

  /// `POST /admin/backups/import`: uploads an archive produced by
  /// another instance (administrators). The zip streams from
  /// [openRead] - archives carry whole databases and easily exceed
  /// what should sit in memory, so the body is never buffered whole.
  Future<Backup> importBackup({
    required int sizeBytes,
    required Stream<List<int>> Function() openRead,
  });

  /// `POST /admin/backups/{backupId}/restore`: stages the archive for
  /// restore at the next server restart, returning the plan
  /// (administrators).
  Future<RestorePlan> stageRestore(String backupId);

  /// `GET /admin/backups/restore`: the currently staged restore, or
  /// null when none is staged (administrators).
  Future<RestorePlan?> getStagedRestore();

  /// `DELETE /admin/backups/restore`: unstages the pending restore
  /// (administrators).
  Future<void> cancelStagedRestore();

  /// `POST /admin/migrations`: starts a server-side import as a
  /// background task (administrators).
  ///
  /// [source] is one of `navidrome`, `subsonic`, `audiobookshelf`,
  /// `jellyfin`, `lastfm`, `listenbrainz`, or `spotify`. The first four
  /// read another server and need its address and a credential; the two
  /// listening services need an account name; `spotify` reads an
  /// account data export staged through [stageMigrationExport] and
  /// named by [exportId].
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
  });

  /// `POST /admin/migrations/exports`: uploads an account data export
  /// for a migration to read, answering what was recognised in it. The
  /// file is read lazily and its length declared up front, so the
  /// server can refuse one too large for its volume before reading a
  /// byte of it; on native the bytes then flow through in
  /// transport-sized pieces (administrators).
  Future<MigrationExport> stageMigrationExport({
    required int sizeBytes,
    required Stream<List<int>> Function() openRead,
  });

  /// `DELETE /admin/migrations/exports/{pid}`: discards a staged export
  /// and its file (administrators).
  Future<void> discardMigrationExport(String pid);

  /// `GET /admin/trash`: the server-side trash (administrators).
  Future<TrashList> listTrash({bool includeRestored = false, int? limit});

  /// `POST /admin/trash/{trashId}/restore`: puts one trashed file back
  /// (administrators).
  Future<void> restoreTrashEntry(String trashId);

  /// `POST /admin/trash/empty`: purges the trash for good
  /// (administrators).
  Future<TrashEmptyResult> emptyTrash();

  /// `DELETE /admin/trash/{trashId}`: purges one trashed file for good,
  /// returning the bytes reclaimed (administrators).
  Future<int> purgeTrashEntry(String trashId);

  /// `GET /admin/thumbnails`: censuses the generated artwork cache
  /// (administrators).
  Future<ThumbnailCacheReport> getThumbnailCache();

  /// `POST /admin/thumbnails/prune`: drops cached thumbnails to fit the
  /// policy (administrators).
  ///
  /// Both bounds are optional and an absent one leaves that axis
  /// unbounded, but at least one must be given - the server refuses a
  /// request with neither rather than reading it as "everything". Zero
  /// is a value here and not an absence: an age of zero drops every
  /// entry, a budget of zero empties the cache.
  Future<ThumbnailPruneResult> pruneThumbnailCache({
    int? olderThanSeconds,
    int? maxBytes,
  });

  /// `GET /admin/catalog/consistency`: checks what the catalog keeps
  /// derived from its own rows against a fresh recompute
  /// (administrators).
  Future<CatalogConsistency> getCatalogConsistency();

  /// `POST /admin/catalog/repair`: queues the catalog's repair as a
  /// `catalog-repair` tool task, refused with `conflict` while one is
  /// queued or running (administrators).
  Future<ToolTask> repairCatalog();

  /// `GET /jobs`: currently known background jobs (administrators).
  Future<List<Job>> listJobs();

  /// `POST /jobs/clear-finished`: hides the caller's ended catalog jobs
  /// from their list (administrators); answers how many it held.
  Future<int> clearFinishedJobs();

  /// `GET /jobs/{pid}`: one catalog job's state and progress.
  Future<Job> getJob(String pid);

  /// `PUT /libraries/{pid}/read-only`: sets one library's read-only
  /// flag, returning the stored value (administrators).
  Future<bool> setLibraryReadOnly(String libraryPid, bool readOnly);

  /// `PUT /libraries/{pid}/folder-fallback`: lets a scan name an in-place
  /// library's untagged files from their folders, returning the stored
  /// flag (administrators).
  Future<bool> setLibraryFolderFallback(String libraryPid, bool on);

  /// `PUT /libraries/{pid}/media`: changes what one library holds
  /// (`music`, `audiobook` or `mixed`), answering whether the scan that
  /// applies it started (administrators).
  Future<bool> setLibraryMedia(String libraryPid, String media);
}
