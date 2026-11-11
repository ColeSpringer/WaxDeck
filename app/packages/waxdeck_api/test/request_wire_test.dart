import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'support/recording_adapter.dart';

const _noBody = Object();

/// The receive budget a call without the long-operation flag keeps.
const _ordinaryBudget = Duration(seconds: 30);

/// One call and the request it must put on the wire.
class _Row {
  _Row(
    this.name,
    this.call,
    this.method,
    this.path, {
    this.query = const {},
    this.json = _noBody,
    this.bytes,
    this.long = false,
    this.answer = const <String, Object?>{},
    this.result,
  });

  final String name;
  final Future<Object?> Function(WaxDeckClient client) call;
  final String method;
  final String path;

  /// Each key of the query to its value as text.
  final Map<String, String> query;

  /// The JSON body, or [_noBody] when none is sent.
  final Object? json;

  /// The octet-stream body, when that is what is sent.
  final List<int>? bytes;

  /// Whether the call is given the long-operation receive budget.
  final bool long;

  /// What the server answers.
  final Object? answer;

  /// What the call returns for [answer], when the row pins it.
  final Matcher? result;
}

Stream<List<int>> Function() _stream(List<int> bytes) =>
    () => Stream.value(bytes);

final _rows = <_Row>[
  // Calls whose server side does its whole job before the response line.
  _Row(
    'completeUpload',
    (c) => c.completeUpload('up-1'),
    'POST',
    '/uploads/up-1/complete',
    long: true,
  ),
  _Row(
    'completeUploadBatch',
    (c) => c.completeUploadBatch('ub-1'),
    'POST',
    '/uploads/batches/ub-1/complete',
    long: true,
  ),
  _Row(
    'decideReviewBulk',
    (c) => c.decideReviewBulk(['re-1', 're-2'], action: 'approve'),
    'POST',
    '/review/decide',
    json: {
      'entryIds': ['re-1', 're-2'],
      'action': 'approve',
    },
    long: true,
  ),
  _Row(
    'decideReviewEntry',
    (c) => c.decideReviewEntry('re-1', action: 'approve'),
    'POST',
    '/review/queue/re-1/decide',
    json: {'action': 'approve'},
    long: true,
  ),
  _Row(
    'importBackup',
    (c) => c.importBackup(sizeBytes: 3, openRead: _stream([1, 2, 3])),
    'POST',
    '/admin/backups/import',
    bytes: [1, 2, 3],
    long: true,
  ),
  _Row(
    'importPlaylistM3u',
    (c) => c.importPlaylistM3u(name: 'Mix', content: '#EXTM3U'),
    'POST',
    '/playlists/m3u',
    json: {'name': 'Mix', 'content': '#EXTM3U'},
    long: true,
  ),
  _Row(
    'probeCastEndpoint',
    (c) => c.probeCastEndpoint('ep-1'),
    'POST',
    '/player/cast/preflight/ep-1',
    long: true,
  ),
  _Row(
    'revertReviewEntry',
    (c) => c.revertReviewEntry('re-1'),
    'POST',
    '/review/queue/re-1/revert',
    long: true,
  ),
  _Row(
    'stageMigrationExport',
    (c) => c.stageMigrationExport(sizeBytes: 2, openRead: _stream([7, 8])),
    'POST',
    '/admin/migrations/exports',
    bytes: [7, 8],
    long: true,
  ),
  _Row(
    'importOpml',
    (c) => c.importOpml('<opml version="2.0"/>'),
    'POST',
    '/podcasts/opml',
    json: {'opml': '<opml version="2.0"/>'},
    long: true,
    answer: {'results': <Object>[]},
    result: isEmpty,
  ),
  _Row(
    'previewPlaylistM3u',
    (c) => c.previewPlaylistM3u('#EXTM3U'),
    'POST',
    '/playlists/m3u/preview',
    json: {'content': '#EXTM3U'},
    long: true,
  ),
  _Row(
    'getCatalogConsistency',
    (c) => c.getCatalogConsistency(),
    'GET',
    '/admin/catalog/consistency',
    long: true,
  ),
  _Row(
    'applyOrganize',
    (c) => c.applyOrganize(),
    'POST',
    '/organize/apply',
    json: <String, Object?>{},
    long: true,
  ),
  _Row(
    'undoOrganize',
    (c) => c.undoOrganize('jb-1'),
    'POST',
    '/organize/undo',
    json: {'jobPid': 'jb-1'},
    long: true,
  ),

  // A flag the server defaults to false is sent only when it is true.
  _Row(
    'exportPlaylistNsp leaves partial out when it is false',
    (c) => c.exportPlaylistNsp('pl-1', partial: false),
    'GET',
    '/playlists/pl-1/nsp',
  ),
  _Row(
    'exportPlaylistNsp sends partial when asked for',
    (c) => c.exportPlaylistNsp('pl-1', partial: true, ruleHash: 'h1'),
    'GET',
    '/playlists/pl-1/nsp',
    query: {'partial': 'true', 'ruleHash': 'h1'},
  ),
  _Row(
    'listShares leaves all out when it is false',
    (c) => c.listShares(all: false),
    'GET',
    '/shares',
  ),
  _Row(
    'listShares sends all when asked for',
    (c) => c.listShares(all: true, cursor: 'c1', limit: 10),
    'GET',
    '/shares',
    query: {'all': 'true', 'cursor': 'c1', 'limit': '10'},
  ),
  _Row(
    'unsubscribePodcast leaves removeDownloads out when it is false',
    (c) => c.unsubscribePodcast('pc-1', removeDownloads: false),
    'DELETE',
    '/podcasts/pc-1',
  ),
  _Row(
    'unsubscribePodcast sends removeDownloads when asked for',
    (c) => c.unsubscribePodcast('pc-1', removeDownloads: true),
    'DELETE',
    '/podcasts/pc-1',
    query: {'removeDownloads': 'true'},
  ),

  // A query parameter that takes the hinted default when the caller names
  // none, and the caller's value when it does.
  _Row(
    'clearEntityArtwork sends the front role by default',
    (c) => c.clearEntityArtwork('artist', 'ar-1'),
    'DELETE',
    '/entities/artist/ar-1/artwork',
    query: {'role': 'front'},
  ),
  _Row(
    'clearEntityArtwork sends the role it is given',
    (c) => c.clearEntityArtwork('artist', 'ar-1', role: 'back'),
    'DELETE',
    '/entities/artist/ar-1/artwork',
    query: {'role': 'back'},
  ),
  _Row(
    'clearItemAcquisition sends its three flags by default',
    (c) => c.clearItemAcquisition('tr-1'),
    'DELETE',
    '/items/tr-1/acquisition',
    query: {'writeBack': 'false', 'lock': 'true', 'force': 'false'},
  ),
  _Row(
    'clearItemAcquisition sends the flags it is given',
    (c) => c.clearItemAcquisition(
      'tr-1',
      writeBack: true,
      lock: false,
      force: true,
    ),
    'DELETE',
    '/items/tr-1/acquisition',
    query: {'writeBack': 'true', 'lock': 'false', 'force': 'true'},
  ),
  _Row(
    'clearItemArtwork sends the front role by default',
    (c) => c.clearItemArtwork('tr-1'),
    'DELETE',
    '/items/tr-1/artwork',
    query: {'role': 'front'},
  ),
  _Row(
    'clearItemLyrics sends writeBack false by default',
    (c) => c.clearItemLyrics('tr-1'),
    'DELETE',
    '/items/tr-1/lyrics',
    query: {'writeBack': 'false'},
  ),
  _Row(
    'clearItemLyrics sends writeBack when asked for',
    (c) => c.clearItemLyrics('tr-1', writeBack: true),
    'DELETE',
    '/items/tr-1/lyrics',
    query: {'writeBack': 'true'},
  ),
  _Row(
    'clearItemTag sends writeBack false by default',
    (c) => c.clearItemTag('tr-1', 'mood'),
    'DELETE',
    '/items/tr-1/tags/mood',
    query: {'writeBack': 'false'},
  ),
  _Row(
    'deleteUser transfers the playlists by default',
    (c) => c.deleteUser('us-1'),
    'DELETE',
    '/users/us-1',
    query: {'playlists': 'transfer'},
  ),
  _Row(
    'getEntityArtworkLock asks for the front role by default',
    (c) => c.getEntityArtworkLock('album', 'al-1'),
    'GET',
    '/entities/album/al-1/artwork/lock',
    query: {'role': 'front'},
  ),
  _Row(
    'listJobs asks for the spec default page',
    (c) => c.listJobs(),
    'GET',
    '/jobs',
    query: {'limit': '50'},
  ),
  _Row(
    'listLibraries sends counts as false by default',
    (c) => c.listLibraries(),
    'GET',
    '/libraries',
    query: {'counts': 'false'},
  ),
  _Row(
    'listLibraries asks for counts',
    (c) => c.listLibraries(counts: true),
    'GET',
    '/libraries',
    query: {'counts': 'true'},
  ),
  _Row(
    'listSubscribedEpisodes asks for the latest by default',
    (c) => c.listSubscribedEpisodes(),
    'GET',
    '/podcasts/episodes',
    query: {'filter': 'latest'},
  ),
  _Row(
    'listTrash sends includeRestored as false by default',
    (c) => c.listTrash(),
    'GET',
    '/admin/trash',
    query: {'includeRestored': 'false'},
  ),
  _Row(
    'listTrash asks for restored entries',
    (c) => c.listTrash(includeRestored: true, limit: 5),
    'GET',
    '/admin/trash',
    query: {'includeRestored': 'true', 'limit': '5'},
  ),
  _Row(
    'setEntityArtworkLock sends the front role by default',
    (c) => c.setEntityArtworkLock('album', 'al-1', locked: true),
    'PUT',
    '/entities/album/al-1/artwork/lock',
    query: {'role': 'front'},
    json: {'locked': true},
  ),

  // A binary body goes out as the octet stream, with its length.
  _Row(
    'setItemArtwork sends the front role, no write-back and the lock by '
        'default',
    (c) => c.setItemArtwork('tr-1', bytes: Uint8List.fromList([9, 8, 7])),
    'PUT',
    '/items/tr-1/artwork',
    query: {'role': 'front', 'writeBack': 'false', 'lock': 'true'},
    bytes: [9, 8, 7],
  ),
  _Row(
    'setItemArtwork sends the options it is given',
    (c) => c.setItemArtwork(
      'tr-1',
      bytes: Uint8List.fromList([1]),
      role: 'back',
      writeBack: true,
      lock: false,
    ),
    'PUT',
    '/items/tr-1/artwork',
    query: {'role': 'back', 'writeBack': 'true', 'lock': 'false'},
    bytes: [1],
  ),
  _Row(
    'setEntityArtwork sends the front role and no write-back by default',
    (c) =>
        c.setEntityArtwork('album', 'al-1', bytes: Uint8List.fromList([4, 5])),
    'PUT',
    '/entities/album/al-1/artwork',
    query: {'role': 'front', 'writeBack': 'false'},
    bytes: [4, 5],
  ),
  _Row(
    'setEntityArtwork sends the options it is given',
    (c) => c.setEntityArtwork(
      'album',
      'al-1',
      bytes: Uint8List.fromList([4]),
      role: 'back',
      writeBack: true,
    ),
    'PUT',
    '/entities/album/al-1/artwork',
    query: {'role': 'back', 'writeBack': 'true'},
    bytes: [4],
  ),

  // A body field with a default the client supplies, and a field of the
  // body that the method does not take at all.
  _Row(
    'addPlaylistItems sends the items and nothing else',
    (c) => c.addPlaylistItems('pl-1', ['tr-1']),
    'POST',
    '/playlists/pl-1/items',
    json: {
      'itemPids': ['tr-1'],
    },
  ),
  _Row(
    'createLibrary sends the model defaults for what is not given',
    (c) => c.createLibrary(name: 'Shelf', path: '/srv/shelf'),
    'POST',
    '/libraries',
    json: {
      'name': 'Shelf',
      'path': '/srv/shelf',
      'media': 'mixed',
      'managed': false,
      'allowAbsent': false,
    },
  ),
  _Row(
    'createLibrary sends what it is given',
    (c) => c.createLibrary(
      name: 'Shelf',
      path: '/srv/shelf',
      media: 'music',
      managed: true,
      allowAbsent: true,
    ),
    'POST',
    '/libraries',
    json: {
      'name': 'Shelf',
      'path': '/srv/shelf',
      'media': 'music',
      'managed': true,
      'allowAbsent': true,
    },
  ),
  _Row(
    'createPlaybackSession sends the start at the first item, playing',
    (c) => c.createPlaybackSession(endpointId: 'ep-1', itemPids: ['tr-1']),
    'POST',
    '/player/sessions',
    json: {
      'endpointId': 'ep-1',
      'itemPids': ['tr-1'],
      'index': 0,
      'positionMs': 0,
      'play': true,
    },
  ),
  _Row(
    'createPlaybackSession sends the start it is given',
    (c) => c.createPlaybackSession(
      endpointId: 'ep-1',
      itemPids: ['tr-1', 'tr-2'],
      index: 1,
      positionMs: 4000,
      play: false,
    ),
    'POST',
    '/player/sessions',
    json: {
      'endpointId': 'ep-1',
      'itemPids': ['tr-1', 'tr-2'],
      'index': 1,
      'positionMs': 4000,
      'play': false,
    },
  ),
  _Row(
    'createPlaylist leaves an empty item list out',
    (c) => c.createPlaylist(name: 'Mix', kind: 'static'),
    'POST',
    '/playlists',
    json: {'name': 'Mix', 'kind': 'static'},
  ),
  _Row(
    'createPlaylist sends the items it is given',
    (c) => c.createPlaylist(name: 'Mix', kind: 'static', itemPids: ['tr-1']),
    'POST',
    '/playlists',
    json: {
      'name': 'Mix',
      'kind': 'static',
      'itemPids': ['tr-1'],
    },
  ),
  _Row(
    'createShare sends allowDownload false by default',
    (c) => c.createShare(pid: 'tr-1'),
    'POST',
    '/shares',
    json: {'pid': 'tr-1', 'allowDownload': false},
  ),
  _Row(
    'markMyNotificationsRead sends an empty id list for all of them',
    (c) => c.markMyNotificationsRead(),
    'POST',
    '/users/me/notifications/read',
    json: {'ids': <String>[]},
  ),
  _Row(
    'markMyNotificationsRead sends the ids it is given',
    (c) => c.markMyNotificationsRead(ids: ['nf-1']),
    'POST',
    '/users/me/notifications/read',
    json: {
      'ids': ['nf-1'],
    },
  ),
  _Row(
    'previewEnrichItem sends what is wanted and no proposal',
    (c) => c.previewEnrichItem('tr-1', want: ['lyrics']),
    'POST',
    '/items/tr-1/enrich/preview',
    json: {
      'want': ['lyrics'],
    },
  ),
  _Row(
    'previewOrganizeProfile sends its templates empty and no tag write by '
        'default',
    (c) => c.previewOrganizeProfile(),
    'POST',
    '/organize/profiles/preview',
    json: {
      'musicTemplate': '',
      'audiobookTemplate': '',
      'podcastTemplate': '',
      'tagWrite': false,
    },
  ),
  _Row(
    'putOrganizeProfile sends its templates empty and no tag write by default',
    (c) => c.putOrganizeProfile('plain'),
    'PUT',
    '/organize/profiles/plain',
    json: {
      'musicTemplate': '',
      'audiobookTemplate': '',
      'podcastTemplate': '',
      'tagWrite': false,
    },
  ),
  _Row(
    'resolveUpgrade leaves empty removal lists out',
    (c) => c.resolveUpgrade(keepItemPid: 'tr-1'),
    'POST',
    '/library/upgrades/resolve',
    json: {'keepItemPid': 'tr-1'},
  ),
  _Row(
    'resolveUpgrade sends the removal lists it is given',
    (c) => c.resolveUpgrade(
      keepItemPid: 'tr-1',
      removeItemPids: ['tr-2'],
      removeFilePids: ['fi-2'],
    ),
    'POST',
    '/library/upgrades/resolve',
    json: {
      'keepItemPid': 'tr-1',
      'removeItemPids': ['tr-2'],
      'removeFilePids': ['fi-2'],
    },
  ),
  _Row(
    'runEnrichment leaves empty phase lists out',
    (c) => c.runEnrichment(),
    'POST',
    '/library/enrichment/run',
    json: {'force': false},
  ),
  _Row(
    'runEnrichment sends the phase lists it is given',
    (c) => c.runEnrichment(
      force: true,
      forcePhases: ['lyrics'],
      phases: ['art', 'lyrics'],
    ),
    'POST',
    '/library/enrichment/run',
    json: {
      'force': true,
      'forcePhases': ['lyrics'],
      'phases': ['art', 'lyrics'],
    },
  ),
  _Row(
    'setLibraryFolderFallback sends the switch alone',
    (c) => c.setLibraryFolderFallback('lb-1', true),
    'PUT',
    '/libraries/lb-1/folder-fallback',
    json: {'folderFallback': true},
  ),
  _Row(
    'setLibraryReadOnly sends the switch alone',
    (c) => c.setLibraryReadOnly('lb-1', true),
    'PUT',
    '/libraries/lb-1/read-only',
    json: {'readOnly': true},
  ),
  // Omitted, the mute and the throttle keep what the target holds.
  _Row(
    'updateMyNotificationTarget leaves out the mute and throttle it is not '
        'given',
    (c) => c.updateMyNotificationTarget(
      pid: 'nt-1',
      config: {'url': 'https://hooks.example/x'},
      enabledEvents: ['scan.finished'],
    ),
    'PUT',
    '/users/me/notification-targets/nt-1',
    json: {
      'config': {'url': 'https://hooks.example/x'},
      'enabledEvents': ['scan.finished'],
    },
  ),
  _Row(
    'updateServerNotificationTarget leaves out the mute and throttle it is '
        'not given',
    (c) => c.updateServerNotificationTarget(
      pid: 'nt-1',
      config: {'url': 'https://hooks.example/x'},
      enabledEvents: ['scan.finished'],
    ),
    'PUT',
    '/admin/notification-targets/nt-1',
    json: {
      'config': {'url': 'https://hooks.example/x'},
      'enabledEvents': ['scan.finished'],
    },
  ),
  _Row(
    'updateServerNotificationTarget sends the mute and throttle it is given',
    (c) => c.updateServerNotificationTarget(
      pid: 'nt-1',
      config: {'url': 'https://hooks.example/x'},
      enabledEvents: ['scan.finished'],
      muted: true,
      minIntervalSeconds: 60,
    ),
    'PUT',
    '/admin/notification-targets/nt-1',
    json: {
      'config': {'url': 'https://hooks.example/x'},
      'enabledEvents': ['scan.finished'],
      'muted': true,
      'minIntervalSeconds': 60,
    },
  ),

  // A model body leaves a field out at its default, or empty, and sends it
  // once it holds anything.
  _Row(
    'previewSmartRule leaves the limit, mode, seed and sorts out at their '
        'defaults',
    (c) => c.previewSmartRule(const SmartRule(root: RuleNode.all())),
    'POST',
    '/playlists/preview',
    json: {
      'root': {'type': 'all'},
    },
  ),
  _Row(
    'previewSmartRule sends the limit, mode, seed and sorts once set',
    (c) => c.previewSmartRule(
      const SmartRule(
        root: RuleNode.all(),
        sorts: [
          RuleSort(field: 'rating', desc: true),
          RuleSort(field: 'year'),
        ],
        limit: 25,
        limitMode: 'random',
        limitSeed: 7,
      ),
    ),
    'POST',
    '/playlists/preview',
    json: {
      'root': {'type': 'all'},
      'sorts': [
        {'field': 'rating', 'desc': true},
        {'field': 'year'},
      ],
      'limit': 25,
      'limitMode': 'random',
      'limitSeed': 7,
    },
  ),
  _Row(
    'commitItemMetadata leaves its empty lists, tag sets, clear flag and '
        'unset chapters out',
    (c) => c.commitItemMetadata('tr-1', const MetadataCommit()),
    'POST',
    '/items/tr-1/metadata/commit',
    json: {'writeBack': false, 'lock': true, 'force': false},
  ),
  // An empty chapter list is a value: it restores the embedded chapters.
  _Row(
    'commitItemMetadata sends an empty chapter list',
    (c) => c.commitItemMetadata('tr-1', const MetadataCommit(chapters: [])),
    'POST',
    '/items/tr-1/metadata/commit',
    json: {
      'writeBack': false,
      'lock': true,
      'force': false,
      'chapters': <Object?>[],
    },
  ),
  _Row(
    'commitItemMetadata sends its chapters',
    (c) => c.commitItemMetadata(
      'tr-1',
      const MetadataCommit(
        chapters: [ChapterMark(index: 0, startMs: 0, title: 'One')],
      ),
    ),
    'POST',
    '/items/tr-1/metadata/commit',
    json: {
      'writeBack': false,
      'lock': true,
      'force': false,
      'chapters': [
        {'index': 0, 'title': 'One', 'startMs': 0},
      ],
    },
  ),
  _Row(
    'commitItemMetadata sends its lists, tag sets and clear flag once set',
    (c) => c.commitItemMetadata(
      'tr-1',
      const MetadataCommit(
        clearLyrics: true,
        tagSets: {
          'mood': ['calm'],
        },
        tagRemoves: ['old'],
        credits: [
          CommitCredits(role: 'producer', names: ['Ada']),
        ],
      ),
    ),
    'POST',
    '/items/tr-1/metadata/commit',
    json: {
      'writeBack': false,
      'lock': true,
      'force': false,
      'clearLyrics': true,
      'tagSets': {
        'mood': ['calm'],
      },
      'tagRemoves': ['old'],
      'credits': [
        {
          'role': 'producer',
          'names': ['Ada'],
        },
      ],
    },
  ),
  _Row(
    'putSubscriptionSettings leaves an auto-download filter without terms out',
    (c) => c.putSubscriptionSettings(
      'pc-1',
      const SubscriptionSettings(autoDownloadFilter: EpisodeFilter()),
    ),
    'PUT',
    '/podcasts/pc-1/settings',
    json: {'autoDownload': false, 'private': false},
  ),
  _Row(
    'putSubscriptionSettings sends an auto-download filter with terms',
    (c) => c.putSubscriptionSettings(
      'pc-1',
      const SubscriptionSettings(
        autoDownloadFilter: EpisodeFilter(include: ['news']),
      ),
    ),
    'PUT',
    '/podcasts/pc-1/settings',
    json: {
      'autoDownload': false,
      'private': false,
      'autoDownloadFilter': {
        'include': ['news'],
      },
    },
  ),
  _Row(
    'putGenreTree leaves empty aliases out',
    (c) => c.putGenreTree(const [GenreNode(name: 'rock')]),
    'PUT',
    '/admin/genre-tree',
    json: {
      'genres': [
        {'name': 'rock'},
      ],
    },
  ),
  _Row(
    'putGenreTree sends the aliases it is given',
    (c) => c.putGenreTree(const [
      GenreNode(name: 'rock', aliases: ['rock n roll']),
    ]),
    'PUT',
    '/admin/genre-tree',
    json: {
      'genres': [
        {
          'name': 'rock',
          'aliases': ['rock n roll'],
        },
      ],
    },
  ),

  // A field whose default is the server's: it is sent when the caller
  // names it, the default itself included, and left out when not.
  _Row(
    'deleteLibraryItems leaves the mode out when none is given',
    (c) => c.deleteLibraryItems(pids: ['tr-1']),
    'POST',
    '/library/items/delete',
    json: {
      'pids': ['tr-1'],
      'dryRun': false,
    },
  ),
  _Row(
    'deleteLibraryItems sends the default mode when it is named',
    (c) => c.deleteLibraryItems(pids: ['tr-1'], mode: 'trash'),
    'POST',
    '/library/items/delete',
    json: {
      'pids': ['tr-1'],
      'mode': 'trash',
      'dryRun': false,
    },
  ),
  _Row(
    'deleteItemFiles leaves the mode out when none is given',
    (c) => c.deleteItemFiles(pid: 'tr-1', filePids: ['fi-1']),
    'POST',
    '/items/tr-1/files/delete',
    json: {
      'filePids': ['fi-1'],
      'dryRun': false,
    },
  ),
  _Row(
    'deleteItemFiles sends the default mode when it is named',
    (c) => c.deleteItemFiles(pid: 'tr-1', filePids: ['fi-1'], mode: 'trash'),
    'POST',
    '/items/tr-1/files/delete',
    json: {
      'filePids': ['fi-1'],
      'mode': 'trash',
      'dryRun': false,
    },
  ),
  _Row(
    'createInvite leaves the use count out when none is given',
    (c) => c.createInvite(),
    'POST',
    '/invites',
    json: <String, Object?>{},
  ),
  _Row(
    'createInvite sends the default use count when it is named',
    (c) => c.createInvite(maxUses: 1),
    'POST',
    '/invites',
    json: {'maxUses': 1},
  ),
  _Row(
    'createInstantMix leaves the adventurousness, size and exclusions out '
        'when none is given',
    (c) => c.createInstantMix(genre: 'blues'),
    'POST',
    '/mixes/instant',
    json: {'genre': 'blues'},
  ),
  _Row(
    'createInstantMix sends the default adventurousness and size when they '
        'are named',
    (c) => c.createInstantMix(genre: 'blues', adventurousness: 0.4, size: 50),
    'POST',
    '/mixes/instant',
    json: {'genre': 'blues', 'adventurousness': 0.4, 'size': 50},
  ),
  _Row(
    'createInstantMix sends the exclusions it is given',
    (c) => c.createInstantMix(genre: 'blues', excludePids: ['tr-9']),
    'POST',
    '/mixes/instant',
    json: {
      'genre': 'blues',
      'excludePids': ['tr-9'],
    },
  ),
];

void main() {
  group('a call puts this on the wire', () {
    for (final row in _rows) {
      test(row.name, () async {
        Object? result;
        final sent = await requestOf(
          (client) async => result = await row.call(client),
          answer: row.answer,
        );
        final expected = row.result;
        if (expected != null) expect(result, expected);
        expect(sent.method, row.method);
        expect(sent.path, row.path);
        expect(sent.query, {
          for (final MapEntry(:key, :value) in row.query.entries) key: [value],
        });
        expect(
          sent.receiveTimeout,
          row.long ? WaxDeckClient.longOperationBudget : _ordinaryBudget,
        );
        final bytes = row.bytes;
        if (bytes != null) {
          expect(sent.contentType, 'application/octet-stream');
          expect(sent.contentLength, '${bytes.length}');
          expect(sent.body, bytes);
        } else if (!identical(row.json, _noBody)) {
          expect(sent.contentType, 'application/json');
          expect(sent.json, row.json);
        } else {
          expect(sent.body, isEmpty);
        }
      });
    }
  });

  test('the long-operation budget is thirty minutes', () {
    expect(WaxDeckClient.longOperationBudget, const Duration(minutes: 30));
  });

  group('a status the method answers with null', () {
    final lost = <String, Object?>{'code': 'not-found', 'message': 'no'};
    final failed = <String, Object?>{'code': 'internal', 'message': 'boom'};

    test('getItemLyrics answers null to a 404', () async {
      final client = clientOn(RecordingAdapter(status: 404, body: lost));
      expect(await client.getItemLyrics('tr-1'), isNull);
    });

    test('getItemLyrics fails on any other status', () async {
      final client = clientOn(RecordingAdapter(status: 500, body: failed));
      await expectLater(
        client.getItemLyrics('tr-1'),
        throwsA(
          isA<WaxDeckApiException>()
              .having((e) => e.code, 'code', 'internal')
              .having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('getStagedRestore answers null to a 404', () async {
      final client = clientOn(RecordingAdapter(status: 404, body: lost));
      expect(await client.getStagedRestore(), isNull);
    });

    test('getStagedRestore fails on any other status', () async {
      final client = clientOn(RecordingAdapter(status: 500, body: failed));
      await expectLater(
        client.getStagedRestore(),
        throwsA(
          isA<WaxDeckApiException>()
              .having((e) => e.code, 'code', 'internal')
              .having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('a call that is not hinted fails on a 404', () async {
      final client = clientOn(RecordingAdapter(status: 404, body: lost));
      await expectLater(
        client.getBackup('bk-1'),
        throwsA(
          isA<WaxDeckApiException>().having(
            (e) => e.statusCode,
            'statusCode',
            404,
          ),
        ),
      );
    });
  });
}
