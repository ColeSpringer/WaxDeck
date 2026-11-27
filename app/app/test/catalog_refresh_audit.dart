import 'package:flutter_test/flutter_test.dart';

import 'analysis_host.dart';
import 'catalog_refresh_scan.dart';

/// A catalog write refreshes what every screen shows of the catalog only
/// while two things hold, and nothing in the compiler says either: every
/// read of the catalog is in a sweep, and every catalog write calls
/// `CatalogWrites.landed`. These read `lib/` for both.
///
/// A read is in a sweep when a provider holds it and that provider is in
/// the registry every pass sweeps, or among the reads asked once a run of
/// changes goes quiet (both in `sync/catalog_reads.dart`; `landed` sweeps
/// both at once). Every other read of the catalog is named here, where
/// it sits, with why it cannot go stale on screen or how long it can.
///
/// What a catalog operation is comes from the generated client. In the
/// tag interfaces [catalogRule] names as the catalog's, a read is a GET
/// and a write is anything else, so an operation the spec adds to one of
/// them is under the rule the day it is generated. Every operation of
/// every other tag is filed by name, as a catalog operation or with why
/// it is not one, so an operation or a tag the spec adds there fails
/// until someone has answered for it. An entry that excuses nothing
/// fails too.
///
/// What a green run does not cover: a filing is a judgment of what an
/// operation answers or changes, made when it was filed, and the scans'
/// own limits, which `catalog_refresh_scan.dart` states.
void catalogRefreshAudit(AnalysisHost Function() host) {
  group('the catalog refresh guards', () {
    test('every operation of the client is held by a guard or filed with '
        'why not, and every exception names an operation it excepts', () async {
      final operations = await Operations.of(host());
      expect(
        catalogRule.rot(operations),
        isEmpty,
        reason:
            'An operation of a tag that is not the catalog\'s is named in '
            'catalogRule: in readsElsewhere or writesElsewhere when it '
            'answers with or changes catalog rows, else under its tag in '
            'otherReads or otherWrites with why not.',
      );
    });

    test('every read of the catalog is in a sweep or says why not', () async {
      final breaches = await unregisteredReadsIn(
        host(),
        libFiles(host()),
        catalogRule,
        allowed: _sharedWithSwept,
        allowedSites: _unswept,
      );
      expect(
        breaches,
        isEmpty,
        reason:
            'A provider that reads the catalog joins catalogReadProviders '
            'or catalogReadFamilies in lib/src/sync/catalog_reads.dart, so '
            'a catalog change reaches it (catalogQuietReads or '
            'catalogQuietFamilies when a pass of a scan should not ask '
            'it). A read no sweep reaches moves behind such a provider, '
            'or is named in _unswept with why it cannot go stale. A read '
            'that answers with no catalog row is excepted by operation, '
            'in catalogRule.noRowRead.\n\n${breaches.join('\n')}',
      );
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('every catalog write lands or says why not', () async {
      final breaches = [
        ...await unlandedWritesIn(
          host(),
          libFiles(host()),
          catalogRule,
          allowed: _landsElsewhere,
        ),
        ...await notLandingIn(host(), _landsForAnother.keys, catalogRule),
      ];
      expect(
        breaches,
        isEmpty,
        reason:
            'A function that makes a catalog write reads '
            'catalogWritesProvider before its await and calls landed() on '
            'it once the server answers. A write that has changed no '
            'catalog row when it answers is excepted by operation, in '
            'catalogRule.noRowWritten; a site whose landing is somewhere '
            'the scan cannot follow is named in _landsElsewhere with '
            'where.\n\n${breaches.join('\n')}',
      );
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('every exception has a reason', () {
      expect(
        [
          ..._sharedWithSwept.entries,
          ..._unswept.entries,
          ..._landsElsewhere.entries,
          ..._landsForAnother.entries,
        ].where((entry) => entry.value.trim().isEmpty),
        isEmpty,
      );
    });
  });
}

/// [operations], each under the reason true of every one of them.
Map<String, String> _each(String why, Set<String> operations) => {
  for (final operation in operations) operation: why,
};

/// The catalog's operations. Reads: the tags that answer with items,
/// entities, shows and episodes, or with what an audit of them found,
/// and the reads of other tags that answer with their rows or names.
/// Writes: the tags that edit, delete, merge, file and follow them, and
/// the writes of other tags that move their rows or files.
final catalogRule = CatalogRule(
  readTags: const {
    'LibraryApi',
    'MetadataApi',
    'BooksApi',
    'PodcastsApi',
    'HealthApi',
  },
  writeTags: const {
    'LibraryApi',
    'MetadataApi',
    'HealthApi',
    'ReviewApi',
    'PodcastsApi',
  },
  readsByAnotherVerb: const {
    'resolveEntities': _batchRead,
    'resolveItems': _batchRead,
    'createInstantMix':
        'computes a mix and answers its tracks: POST for the seed it '
        'takes, and nothing is written',
    'previewSmartRule':
        'answers the items a rule would hold: POST for the rule in the '
        'body, and nothing is written',
  },
  noRowRead: const {
    'getItemPermissions': 'what the caller may do to the item, not the item',
    'getMetadataFields':
        'the server\'s vocabulary of fields, the same for every item',
    'listBookmarks':
        'the caller\'s own marks in a book, each a place and a note of '
        'theirs: no catalog change moves one',
    'searchPodcastDirectory':
        'a public directory search: no row of this library is in it',
    'getLibraryHealth': _sweptHealth,
    'listHealthIssues': _sweptHealth,
    'listFileDiagnostics': _fileLog,
    'getDiagnosticSummary': _fileLog,
  },
  readsElsewhere: const {
    'listTrash':
        'the items a delete moved out of every listing, which a restore '
        'puts back',
    'getPlaylist':
        'a playlist with its count and cover, which for a smart playlist '
        'are evaluated over the catalog',
    'listPlaylistItems': 'a playlist\'s members, each an item row',
    'previewSmartRule': 'the item rows a rule matches',
    'getTopList': _rankedByName,
    'getYearInReview': _rankedByName,
    'getServerYearInReview': _rankedByName,
    'listListenLog':
        'what played, each row under its item\'s title and artist as the '
        'catalog has them when the page is read',
    'listShares':
        'share links, each under its target\'s title as the catalog has '
        'it when the page is read',
    'listStarredEntities':
        'the caller\'s starred artists and albums, by the names the '
        'catalog gives them',
    'listRadioSavedSongs':
        'saved songs, each matched against the library when the page is '
        'read: which item, if any, it is here',
    'getSimilarTracks': _mixRows,
    'getSonicPath': _mixRows,
    'createInstantMix': _mixRows,
    'listPlaybackSessions': _sessionRows,
    'getPlaybackSession': _sessionRows,
    'listPlaybackSessionHistory': _sessionRows,
    'getReviewEntry':
        'a review entry, each file that duplicates the library naming the '
        'item it duplicates as the catalog has it when read',
    'listUploads': _duplicates,
    'getUpload': _duplicates,
  },
  otherReads: {
    'AdminApi': {
      'listLibraries':
          'the libraries, and with counts how many items each holds: the '
          'libraries topic reads both again, and the counts once more '
          'when a run of catalog changes goes quiet',
      ..._each('a job\'s own state, which the job topic reports', {
        'getJob',
        'listJobs',
      }),
      'listAuditEvents':
          'the log of administrative actions: a row names its target as '
          'it was when the action was taken',
      ..._each(_serverSetting, {
        'getAdminSettings',
        'getTranscodingLimits',
        'getScrobblingConfig',
        'listSchedules',
      }),
      'getGenreTree':
          'the genre vocabulary, a setting only its editor writes: no '
          'item or entity row is in it',
      'getTranscodingActivity': 'what the transcoder is doing this moment',
      ..._each('backup archives and the restore staged from one', {
        'listBackups',
        'getBackup',
        'getStagedRestore',
      }),
      ..._each('a census of a cache, counted when asked', {
        'getThumbnailCache',
        'getEnrichmentCache',
      }),
      'getCatalogConsistency':
          'counts from a check of the catalog\'s derived data, run when '
          'asked for and drawn by the section that asked',
    },
    'AuthApi': _each('sessions, sign-in and first-run state', {
      'getSession',
      'bootstrapStatus',
      'listSessions',
      'oidcProviders',
    }),
    'EnrichmentApi': const {
      'getEnrichmentStatus':
          'the enrichment sources, the state of a run and coverage '
          'counts: its console asks again while a run goes on',
    },
    'NotificationsApi': _each(
      'the notification targets, registrations and inbox, and the '
      'vocabulary of events: an inbox row carries the text it was sent '
      'with',
      {
        'listNotificationEvents',
        'listMyNotificationTargets',
        'listPushRegistrations',
        'listServerNotificationTargets',
        'listMyNotifications',
      },
    ),
    'OrganizeApi': const {
      'listOrganizeProfiles': 'layout profiles, a setting',
      'listOrganizeHistory':
          'the runs of organize, each a state and counts: no item row',
    },
    'PlaybackApi': {
      ..._each('a stream or a download minted for now, not a row', {
        'getPlayInfo',
        'getDownloadInfo',
      }),
      ..._each(
        'the caller\'s own position, stars and ratings, which the user '
        'topic reports',
        {'getPlayState', 'getEntityPlayState'},
      ),
      ..._each(
        'derived from the audio itself: no edit of a catalog row changes '
        'it',
        {'getSkipMap', 'getWaveform'},
      ),
    },
    'PlayerApi': const {
      'listPlayerEndpoints': 'the endpoints playback can go to',
      'getCastPreflight': 'a reachability check of this moment',
    },
    'PlaylistsApi': {
      'listPlaylists':
          'the playlists by name, rows of the caller\'s own on the user '
          'topic: the hub draws no count, and a cover is behind a URL '
          'that does not change',
      'getRuleFields':
          'the vocabulary a rule editor offers when it opens: its tag '
          'keys and their counts are a hint to the author, as of then',
      ..._each('a document made when asked for, to be saved or copied', {
        'exportPlaylistM3u',
        'exportPlaylistNsp',
        'exportPlaylistPortable',
        'reportPlaylistNspExport',
      }),
      'getPlaylistSource':
          'a playlist\'s binding to an outside source, the caller\'s own',
    },
    'RadioApi': {
      'listRadioStations': 'stations: rows of their own',
      'getRadioPlayInfo':
          'a station\'s stream and the title it plays this moment, with '
          'the item of the library that title matches when asked: asked '
          'again at each poll and each title the station announces',
      'searchRadioDirectory':
          'a public directory search: no row of this library is in it',
    },
    'ReviewApi': {
      ..._each(
        'the review queue and its counts, on the user topic: a queue row '
        'names what was identified in the files under review, not a '
        'catalog row',
        {'listReviewQueue', 'getReviewStats'},
      ),
      'getLibraryMatching': 'a setting of one library\'s matching',
    },
    'ScrobblingApi': const {
      'listScrobblers': 'the caller\'s scrobbling connections',
    },
    'SimilarityApi': const {
      'getSimilarityStatus': 'how far the analysis has got',
    },
    'StatsApi': _each('the caller\'s listening time, in numbers alone', {
      'getListeningStats',
      'getListeningHeatmap',
    }),
    'SyncApi': _each('the feed the mirror itself is built from', {
      'syncCatalog',
      'syncServer',
    }),
    'SystemApi': const {'health': 'liveness and the server\'s version'},
    'ToolsApi': _each(
      'tool tasks, on the user topic: a task names its item as it was '
      'when the task was made',
      {'listToolTasks', 'getToolTask'},
    ),
    'UploadsApi': const {
      'listUploadTargets': 'the libraries an upload may name',
    },
    'UsersApi': _each(_accounts, {
      'listUsers',
      'getUser',
      'listSignupRequests',
      'listInvites',
      'getPrefs',
      'listAppPasswords',
    }),
  },
  noRowWritten: const {
    'previewEnrichItem': 'answers what a fetch would change, written nowhere',
    'rematchItem':
        'reopens identification: the catalog moves when the review entry '
        'it opens is decided, and a decision lands',
    'reidentifyReviewEntry':
        'changes a review entry\'s candidates: the catalog moves when the '
        'entry is decided, and a decision lands',
    'setLibraryMatching': 'a setting of the library\'s matching, no row',
    'sweepLibraryHealth': _startsAJob,
    'fixHealthIssues': _startsAJob,
    'fetchEpisode':
        'queues a fetch the server runs after it answers: the episode '
        'turns present when that ends, which the server\'s catalog hint '
        'reports, and the sites mark the row queued in place meanwhile',
    'putSubscriptionSettings':
        'the caller\'s own settings for a show: no row of the show or its '
        'episodes moves, and a retention sweep it prompts runs after',
    'captureEpisodeTranscript':
        'indexes an episode\'s transcript, which no listing draws; a '
        'search held from before answers without the episode until it is '
        'asked again, taken over a registry sweep each time a transcript '
        'section opens',
  },
  writesElsewhere: const {
    'putGenreTree': 'the genre index groups by the vocabulary this replaces',
    'restoreTrashEntry': 'puts items back into every listing',
    'emptyTrash': _leavesTrash,
    'purgeTrashEntry': _leavesTrash,
    'applyOrganize': _movesFiles,
    'undoOrganize': _movesFiles,
  },
  otherWrites: {
    'AdminApi': {
      'createLibrary':
          'adds a library and starts its scan: the libraries topic '
          'reports the library, and the catalog hints what the scan finds',
      ..._each(_startsAJob, {'rescanLibrary', 'removeLibrary'}),
      ..._each(
        'a setting of one library: where it changes what the library\'s '
        'rows are, it does so through the scan it starts, a job',
        {
          'setLibraryProfile',
          'setLibraryMedia',
          'setLibraryReadOnly',
          'setLibraryFolderFallback',
        },
      ),
      'clearFinishedJobs': 'clears finished jobs from the caller\'s list',
      'cancelJob':
          'stops a scan, an analysis or an enrichment between files: what '
          'it wrote before it stopped reaches the client through the '
          'server\'s catalog hints, as a finished one\'s does',
      ..._each(_serverSetting, {
        'putAdminSettings',
        'putTranscodingLimits',
        'putScrobblingConfig',
        'putSchedule',
      }),
      ..._each(_startsATask, {
        'normalizeGenres',
        'repairCatalog',
        'createMigration',
      }),
      ..._each(
        'backup archives and the restore staged from one, which replaces '
        'the catalog only at the next start',
        {
          'createBackup',
          'importBackup',
          'deleteBackup',
          'stageRestore',
          'cancelStagedRestore',
        },
      ),
      ..._each('prunes a cache: no row moves', {
        'pruneThumbnailCache',
        'pruneEnrichmentCache',
      }),
      ..._each('an export file staged for a migration, or let go', {
        'stageMigrationExport',
        'discardMigrationExport',
      }),
    },
    'AuthApi': _each('sessions and sign-in', {
      'login',
      'logout',
      'bootstrap',
      'signup',
      'refreshToken',
      'renameSession',
      'revokeSession',
      'oidcExchange',
    }),
    'BooksApi': _each(
      'the caller\'s own playback settings and bookmarks for a book',
      {'putBookSettings', 'createBookmark', 'deleteBookmark'},
    ),
    'EnrichmentApi': const {
      'putEnrichmentSources': 'the order of the sources, a setting',
      'runEnrichment': _startsAJob,
    },
    'NotificationsApi':
        _each('notification targets, registrations and the inbox', {
          'createMyNotificationTarget',
          'updateMyNotificationTarget',
          'deleteMyNotificationTarget',
          'testMyNotificationTarget',
          'createPushRegistration',
          'deletePushRegistration',
          'createServerNotificationTarget',
          'updateServerNotificationTarget',
          'deleteServerNotificationTarget',
          'testServerNotificationTarget',
          'clearMyNotifications',
          'markMyNotificationsRead',
          'deleteMyNotification',
        }),
    'OrganizeApi': {
      ..._each('a layout profile, a setting', {
        'putOrganizeProfile',
        'deleteOrganizeProfile',
      }),
      ..._each('a dry run, asked by POST: nothing is moved', {
        'previewOrganizeProfile',
        'previewOrganize',
      }),
    },
    'PlaybackApi': {
      ..._each(
        'the caller\'s own play state and listens, which the user topic '
        'reports',
        {
          'putPlayState',
          'setPlayed',
          'setStar',
          'setRating',
          'setEntityStar',
          'setEntityRating',
          'reportListens',
        },
      ),
      'listPlayStates':
          'reads the caller\'s play state for many items, by POST for '
          'the size of the question',
    },
    'PlayerApi': _each('playback sessions, endpoints and renderings', {
      'createPlaybackSession',
      'deletePlaybackSession',
      'transferPlaybackSession',
      'createQueueTimeline',
      'releaseQueueTimeline',
      'probeCastEndpoint',
    }),
    'PlaylistsApi': {
      ..._each(
        'the caller\'s own playlists and their members: no item or '
        'entity row moves, and the user topic reports the playlist',
        {
          'createPlaylist',
          'importPlaylistM3u',
          'importNsp',
          'importPlaylist',
          'updatePlaylist',
          'deletePlaylist',
          'replacePlaylistItems',
          'addPlaylistItems',
          'removePlaylistItemAt',
          'setPlaylistSource',
          'unbindPlaylistSource',
        },
      ),
      ..._each(
        'a preview of an import or a sync, asked by POST: nothing is '
        'written',
        {'previewPlaylistM3u', 'checkNspImport', 'previewPlaylistSync'},
      ),
      'syncPlaylistSource': _startsATask,
    },
    'RadioApi': _each('stations and saved songs: rows of their own', {
      'createRadioStation',
      'updateRadioStation',
      'deleteRadioStation',
      'saveRadioSong',
      'deleteRadioSavedSong',
    }),
    'ScrobblingApi': _each('the caller\'s scrobbling connections', {
      'connectListenBrainz',
      'disconnectListenBrainz',
      'disconnectLastfm',
      'startLastfmConnect',
    }),
    'SharesApi': _each('share links: rows of their own', {
      'createShare',
      'revokeShare',
    }),
    'SyncApi': const {'syncCatalogRemoved': 'asks the feed a question by POST'},
    'ToolsApi': {
      ..._each(_startsATask, {'mergeBook', 'splitBook', 'splitCueRip'}),
      ..._each('clears finished tasks from the list', {
        'clearFinishedToolTasks',
        'deleteToolTask',
      }),
      'cancelToolTask':
          'stops a task: what its runs wrote, and what its settle files of '
          'what they staged (a declined download imported, a repair\'s owed '
          'reset), reaches the client through the server\'s catalog hints; '
          'its settle otherwise removes only outputs never filed',
    },
    'UploadsApi': {
      ..._each('staging: bytes received, nothing filed yet', {
        'createUpload',
        'deleteUpload',
        'putUploadData',
        'createUploadBatch',
      }),
      ..._each(
        'opens a review entry: the catalog moves when it is decided, and '
        'a decision lands',
        {'completeUpload', 'completeUploadBatch'},
      ),
      'createAcquisition': _startsATask,
    },
    'UsersApi': _each(_accounts, {
      'createUser',
      'updateUser',
      'deleteUser',
      'setUserPassword',
      'revokeUserSessions',
      'approveSignupRequest',
      'rejectSignupRequest',
      'createInvite',
      'revokeInvite',
      'putPrefs',
      'createAppPassword',
      'revokeAppPassword',
    }),
  },
);

const _batchRead =
    'a read of many pids at once, which go in the body: POST for the size '
    'of the question';
const _sweptHealth =
    'computed by the server\'s background sweep, not read off the catalog '
    'when asked: an edit moves it only once a sweep has, and the health '
    'topic says so';
const _fileLog =
    'the log of what jobs said about files, not rows of the catalog; the '
    'diagnostics screen reads it again when asked to';
const _rankedByName =
    'ranks the caller\'s listening under the names and covers the catalog '
    'gives its artists, albums, tracks and shows now';
const _mixRows = 'a mix computed over the catalog: its tracks, as item rows';
const _duplicates =
    'uploads being staged, each that duplicates the library naming the '
    'item it duplicates as the catalog has it when read';
const _sessionRows =
    'a playback session\'s queue, each entry named from the catalog when '
    'the session is read';
const _startsAJob =
    'answers with a job or a task just started: what it rewrites comes '
    'after, and reaches the client by the server\'s catalog hints';
const _startsATask =
    'starts a tool task: what the task rewrites comes after, and reaches '
    'the client by the server\'s catalog hints';
const _leavesTrash =
    'what the trash lists, a read of the catalog, is gone from it when '
    'this answers';
const _movesFiles =
    'answers once its job has ended: the files of the items it names '
    'have moved by then';
const _serverSetting = 'a setting of the server';
const _accounts = 'accounts, invites, preferences and app passwords';

/// Providers in no sweep that read the catalog through a body a swept
/// provider also runs, as `provider: operation`, each with why no sweep
/// has to reach that provider.
const Map<String, String> _sharedWithSwept = {};

/// Catalog reads no sweep reaches, as `path: Type.member: operation`,
/// each with why what it answers cannot go stale on screen, or for how
/// long it can.
const Map<String, String> _unswept = {
  // Swept by a write and by the session's passes, on terms of its own.
  'lib/src/home/home_shelves.dart: libraryHasAnythingProvider: listItems':
      'home\'s probe, swept through probeFanOutProvider: a registry pass '
      'on every hint of a scan is more than one bit is worth',

  // A form opens on these; what is being typed outranks a refetch.
  'lib/src/metadata/bulk_pane.dart: _bulkSeedProvider: getItemMetadata':
      _formSeed,
  'lib/src/metadata/entity_editor_screen.dart: _renameSeedProvider: '
          'listItems':
      _formSeed,
  'lib/src/metadata/entity_editor_screen.dart: _renameSeedProvider: '
          'getItemMetadata':
      _formSeed,
  'lib/src/metadata/album_pane.dart: _rewriteSeedProvider: getItemMetadata':
      'what the album rewrite opens on, read off the first row of the '
      'album\'s listing: it watches that listing, which is registered, so '
      'a sweep reaches it through it',
  'lib/src/metadata/entity_editor_screen.dart: _entityNameProvider: '
          'listItems':
      'the entity editor\'s own title, read off one member: its rename '
      'reads it again, and it lives no longer than the editor',
  'lib/src/metadata/artwork_manager.dart: entityArtLockProvider: '
          'getEntityArtworkLock':
      'the cover editor\'s own pin, alive only under that editor, whose '
      'writes each read it again',
  'lib/src/playlists/rule_editor_screen.dart: '
          '_RuleEditorScreenState._schedulePreview: previewSmartRule':
      'the rule editor\'s sample of what its rule matches, alive only '
      'under that form and asked again each time the rule is edited',

  // Read afresh each time their surface shows, and gone with it.
  'lib/src/health/health_controller.dart: FoldsController.build: '
          'listEntityFolds':
      _folds,
  'lib/src/health/health_controller.dart: FoldsController.loadMore: '
          'listEntityFolds':
      _folds,
  'lib/src/radio/radio_saved_controller.dart: RadioSavedController.build: '
          'listRadioSavedSongs':
      _savedSongs,
  'lib/src/radio/radio_saved_controller.dart: '
          'RadioSavedController.loadMore: listRadioSavedSongs':
      _savedSongs,
  'lib/src/queue/session_history.dart: sessionHistoryProvider: '
          'listPlaybackSessionHistory':
      'the ended sessions offered under the queue, alive only while '
      'that offer shows and read each time it does',
  'lib/src/shell/command_palette.dart: paletteHitsProvider: search':
      'the command palette\'s matches, alive while it is open over the '
      'app and asked again with each query',

  // A read made once, on a tap, and used at once to choose where to go.
  'lib/src/health/folds_section.dart: _FoldGroups._openArtist: '
          'resolveEntities':
      'the artist card a tapped fold row opens on, read to choose which '
      'page to open and acted on as it answers; nothing holds it',

  // Playback reads an item to play it, and keeps what it queued current
  // itself.
  'lib/src/player/now_playing/now_playing_preload.dart: '
          '_NowPlayingPreload._resolve: getItem':
      _playback,
  'lib/src/player/now_playing/now_playing_preload.dart: '
          '_NowPlayingPreload._resolve: getEpisode':
      _playback,
  'lib/src/queue/queue_item.dart: queueItemProvider: getItem': _playback,
  'lib/src/queue/queue_recheck.dart: QueueRecheck._pass: resolveItems':
      'the lookup that keeps playback\'s summaries current: it is the '
      'read made again, by the session once a run of catalog hints goes '
      'quiet, when a write lands here and with the pass it is owed',
  'lib/src/queue/queue_recheck.dart: QueueRecheck._pass: getBook':
      'a queued book\'s detail, read again by that lookup when the server\'s '
      'row for a book held as composed from it changed, and composed again '
      'at once: used, never held',
  'lib/src/player/session/session_media.dart: _SessionMedia._readConfig: '
          'getPodcast':
      'what a session plays an episode by, and read again before each '
      'write of its settings: of the show, only the caller\'s own '
      'settings for it, which no catalog write moves',
  'lib/src/player/session/session_media.dart: _SessionMedia._readConfig: '
          'getBook':
      'what a session plays a book by, read as it loads and again before '
      'each write of its settings: its parts, which are the stream, and '
      'the caller\'s settings; its chapter marks are read again with every '
      'lookup of the queue',
  'lib/src/books/book_screen.dart: _BookSettingsSheetState._save: getBook':
      'the book\'s settings read at a save, for the sheet to write back '
      'with only its own changes over them: used at once, and never shown',
  'lib/src/podcasts/subscription_settings_sheet.dart: '
          '_SubscriptionSettingsSheetState._save: getPodcast':
      'the caller\'s settings for the show, read at a save for the sheet to '
      'write back with only its own changes over them: used at once, and '
      'never shown',
  'lib/src/books/book_screen.dart: _BookSettingsSheetState._readStored: '
          'getBook':
      _sheetOpens,
  'lib/src/podcasts/subscription_settings_sheet.dart: '
          '_SubscriptionSettingsSheetState._readStored: getPodcast':
      _sheetOpens,
  'lib/src/player/playback_session.dart: PlaybackSession.rereadBook: '
          'getBook':
      'a playing book\'s chapter marks, read again with every lookup of '
      'the queue (QueueRecheck) and held while the parts it plays stand',
  'lib/src/queue/queue_source_pager.dart: '
          'RepositoryQueueSourcePager._listing: browse':
      _refill,
  'lib/src/queue/queue_source_pager.dart: '
          'RepositoryQueueSourcePager._listing: listItems':
      _refill,
  'lib/src/queue/queue_source_pager.dart: '
          'RepositoryQueueSourcePager._listing: listPlaylistItems':
      _refill,
  'lib/src/queue/queue_continuation.dart: QueueContinuation._extend: '
          'createInstantMix':
      'keeps playing when the queue ends: a mix appended to the queue '
      'and held by nothing else, where QueueRecheck reads it again',
  'lib/src/queue/queue_persistence.dart: '
          'QueueRestoreController._sessionHistory: '
          'listPlaybackSessionHistory':
      _restoreOffer,
  'lib/src/queue/queue_persistence.dart: '
          'QueueRestoreController._offeredItem: getItem':
      _restoreOffer,
  'lib/src/desktop/discord_binder.dart: discordCoversProvider: getAlbum':
      'a resolver Discord presence asks for an album\'s cover: nothing '
      'on screen draws it',

  // Read to act on at once, or handed on to what reads it again.
  'lib/src/discovery/discovery_actions.dart: openSimilarTracks: '
          'getSimilarTracks':
      _handedOn,
  'lib/src/music/genre_open.dart: openGenreByLabel: listFacets': _verbsLookup,
  'lib/src/home/mix_shelf.dart: playMixCard: createInstantMix': _handedOn,
  'lib/src/discovery/discovery_actions.dart: _InstantMixSheetState._mix: '
          'createInstantMix':
      _handedOn,
  'lib/src/library/item_kind.dart: _destination: getItem': _verbsLookup,
  'lib/src/music/listing_screen.dart: _MusicListingScreenState._shuffle: '
          'browse':
      _verbsLookup,
  'lib/src/playlists/playlist_play.dart: playPlaylistPid: getPlaylist':
      _verbsLookup,
  'lib/src/playlists/playlist_play.dart: playPlaylistPid: listPlaylistItems':
      _verbsLookup,
  'lib/src/podcasts/show_actions.dart: playShowLatest: listEpisodes':
      _verbsLookup,
  'lib/src/queue/queue_drag.dart: bucketItems: listItems': _verbsLookup,
  'lib/src/tools/tasks_screen.dart: _TaskRow._openResult: getItem':
      _verbsLookup,

  // Read once for a surface that shows it as it was asked.
  'lib/src/podcasts/podcasts_screen.dart: _HubOverflow._exportOpml: '
          'exportOpml':
      'a document of the caller\'s subscriptions, shown once in a '
      'dialog to be copied, over the app',
  'lib/src/tools/tasks_screen.dart: _TaskRow._pickResult: getItem':
      'one read for a sheet naming what a task produced, shown over the '
      'app and gone when one is picked',
  'lib/src/podcasts/mark_older_played_dialog.dart: '
          '_MarkOlderPlayedDialogState._backlog: listEpisodes':
      'one walk of a show\'s episodes when the dialog runs, to mark them: '
      'the dialog draws none of them',
  'lib/src/playlists/playlist_screen.dart: _AddRowState._onChanged: search':
      'the matches under the add row for the text typed in it, asked '
      'again with each keystroke and gone when the row closes',

  // The publisher's words, which nothing here writes.
  'lib/src/player/spoken_face.dart: _TranscriptRegionState._loading: '
          'getEpisodeTranscript':
      _transcript,
  'lib/src/podcasts/episode_screen.dart: '
          '_TranscriptSectionState._onExpanded: getEpisodeTranscript':
      _transcript,
};

const _formSeed =
    'what an editor\'s form opens on, alive only under that form, where a '
    'refetch would replace what is being typed';
const _folds =
    'the folded names, read afresh on each visit to the health screen '
    'and dropped with it: a sweep under it would start its pages over';
const _savedSongs =
    'the saved songs, read afresh on each visit to their list and '
    'dropped with it: which of them the library holds is as of that '
    'visit, and a sweep under the list would start its pages over';
const _sheetOpens =
    'a settings sheet\'s stored settings, read once as it opens to fill the '
    'fields nobody has changed yet; a change made while it stands is taken '
    'up by its save, which reads them again';

const _playback =
    'playback\'s own: it reads an item when it is about to play or list '
    'it and holds the summary, which QueueRecheck reads again once a run '
    'of catalog hints goes quiet and when a write lands here, replacing '
    'it wherever its row draws differently';
const _refill =
    'pages the queue\'s source when the queue runs low: it holds no '
    'rows, and what it appends goes to playback, where QueueRecheck '
    'reads it again';
const _restoreOffer =
    'the offer to resume the last session, made once at launch and '
    'gone when taken or dismissed';
const _handedOn =
    'a computed answer, handed on as it arrives: what is played or queued '
    'is playback\'s, which QueueRecheck reads again, and the list pushed '
    'for it draws its rows from trackListRowsProvider, which a sweep '
    'reads again';
const _verbsLookup =
    'a verb\'s lookup: read when the verb runs, acted on at once (played, '
    'queued, gone to), and held by nothing';
const _transcript =
    'an episode\'s transcript as its publisher serves it, fetched for '
    'the region that shows it: no write made here and no catalog change '
    'rewrites it';

/// Catalog writes whose landing the scan cannot follow from the
/// declaration that makes them, as `path: Type.member: operation`, each
/// with where it lands.
const Map<String, String> _landsElsewhere = {};

/// Declarations that land a write another declaration makes, each with
/// which: the scan holds them to calling `landed` as well.
const Map<String, String> _landsForAnother = {
  'lib/src/library/item_kind.dart: confirmSetKind':
      'the kind change _SetKindDialogState._run starts: with the dialog '
      'still there the outcome is handed back and lands here, after the '
      'destination is read; _run lands it itself only once the dialog '
      'has gone',
};
