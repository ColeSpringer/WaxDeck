import 'dart:async';

import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// In-memory [PlaylistsApi] for `FakeRepository`.
mixin FakePlaylists on FakeRepositoryState implements PlaylistsApi {
  /// Playlists by pid, with static members alongside.
  final Map<String, Playlist> playlistsByPid = {};
  final Map<String, List<String>> playlistMembers = {};

  /// Preview served by [previewSmartRule]; tests seed it.
  PlaylistPreview previewResult = const PlaylistPreview(items: [], total: 0);

  /// Rule vocabulary served by [getRuleFields].
  RuleFields ruleFields = const RuleFields(
    fields: [
      RuleField(
        name: 'title',
        kind: 'text',
        ops: [
          'is',
          'isNot',
          'contains',
          'startsWith',
          'endsWith',
          'isPresent',
          'isMissing',
        ],
        userState: false,
        sortable: true,
      ),
      RuleField(
        name: 'rating',
        kind: 'number',
        ops: [
          'is',
          'isNot',
          'gt',
          'lt',
          'gte',
          'lte',
          'inTheRange',
          'isPresent',
          'isMissing',
        ],
        userState: true,
        sortable: true,
      ),
      RuleField(
        name: 'starred',
        kind: 'boolean',
        ops: ['is'],
        userState: true,
        sortable: true,
      ),
      RuleField(
        name: 'mediaType',
        kind: 'mediaType',
        ops: ['is', 'isNot'],
        userState: false,
        sortable: false,
      ),
      RuleField(
        name: 'addedAt',
        kind: 'date',
        ops: [
          'before',
          'after',
          'inTheRange',
          'inTheLast',
          'notInTheLast',
          'isPresent',
          'isMissing',
        ],
        userState: false,
        sortable: true,
      ),
      RuleField(
        name: 'playlist',
        kind: 'playlist',
        ops: ['is', 'isNot'],
        userState: false,
        sortable: false,
      ),
    ],
    tagKeys: [RuleTagKey(key: 'MOOD', itemCount: 3)],
  );

  int _playlistSeq = 0;

  ItemSummary _itemByPid(String pid) {
    return libraryItems.firstWhere(
      (i) => i.pid == pid,
      orElse: () => throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such item',
        statusCode: 404,
      ),
    );
  }

  /// Held open, the playlist listing waits on it: a reload in flight is
  /// what a screen's refresh test is about.
  Completer<void>? listPlaylistsGate;

  @override
  Future<PlaylistPage> listPlaylists({
    String? cursor,
    int? limit,
    String? containsItem,
  }) async {
    await listPlaylistsGate?.future;
    var rows = playlistsByPid.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (containsItem != null) {
      rows = rows
          .where(
            (p) =>
                !p.isSmart &&
                (playlistMembers[p.pid] ?? const []).contains(containsItem),
          )
          .toList();
    }
    return PlaylistPage(playlists: rows);
  }

  /// Holds [createPlaylist] until completed.
  Completer<void>? createPlaylistGate;

  @override
  Future<Playlist> createPlaylist({
    required String name,
    required String kind,
    String? visibility,
    SmartRule? rule,
    List<String> itemPids = const [],
  }) async {
    if (createPlaylistGate case final gate?) await gate.future;
    final pid = 'pl-FAKE${_playlistSeq++}';
    final pl = Playlist(
      pid: pid,
      name: name,
      kind: kind,
      visibility: visibility ?? 'private',
      ownerName: 'me',
      isOwner: true,
      itemCount: kind == 'static' ? itemPids.length : null,
      rule: rule,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    playlistsByPid[pid] = pl;
    playlistMembers[pid] = List.of(itemPids);
    return pl;
  }

  /// Held open, a playlist's own read waits on it, for the detail
  /// screen's refresh test.
  Completer<void>? getPlaylistGate;

  /// When set, a playlist's own read fails with it.
  WaxDeckApiException? getPlaylistError;

  /// When set, a playlist delete fails with it.
  WaxDeckApiException? deletePlaylistError;

  @override
  Future<Playlist> getPlaylist(String pid) async {
    await getPlaylistGate?.future;
    final error = getPlaylistError;
    if (error != null) throw error;
    final pl = playlistsByPid[pid];
    if (pl == null) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such playlist',
        statusCode: 404,
      );
    }
    return pl;
  }

  @override
  Future<Playlist> updatePlaylist(
    String pid, {
    String? name,
    String? visibility,
    SmartRule? rule,
  }) async {
    final pl = await getPlaylist(pid);
    // Name, visibility, and rule all apply in place under a stable pid,
    // like the real server since the reissue seam was retired.
    final next = Playlist(
      pid: pl.pid,
      name: name ?? pl.name,
      kind: pl.kind,
      visibility: visibility ?? pl.visibility,
      ownerName: pl.ownerName,
      isOwner: pl.isOwner,
      itemCount: pl.itemCount,
      rule: rule ?? pl.rule,
      createdAt: pl.createdAt,
      updatedAt: DateTime.utc(2026, 2),
    );
    playlistsByPid[next.pid] = next;
    return next;
  }

  @override
  Future<void> deletePlaylist(String pid) async {
    final error = deletePlaylistError;
    if (error != null) throw error;
    playlistsByPid.remove(pid);
    playlistMembers.remove(pid);
  }

  /// Every pid a member page was asked for, so a test can see which
  /// playlists were opened rather than only written to.
  final List<String> playlistItemPageCalls = [];

  @override
  Future<PlaylistItemsPage> listPlaylistItems(
    String pid, {
    String? cursor,
    int? limit,
  }) async {
    playlistItemPageCalls.add(pid);
    final pl = await getPlaylist(pid);
    if (pl.isSmart) {
      return PlaylistItemsPage(
        entries: [
          for (final it in previewResult.items) PlaylistEntry(item: it),
        ],
      );
    }
    final members = playlistMembers[pid] ?? const [];
    final start = cursor == null ? 0 : int.parse(cursor);
    final end = limit == null
        ? members.length
        : (start + limit).clamp(0, members.length);
    return PlaylistItemsPage(
      entries: [
        for (var i = start; i < end; i++)
          PlaylistEntry(position: i, item: _itemByPid(members[i])),
      ],
      nextCursor: end < members.length ? '$end' : null,
    );
  }

  /// Makes the next replace answer `conflict`, the way the server does
  /// when another device edited the list first.
  var playlistReplaceConflict = false;

  /// The member orders [replacePlaylistItems] was asked for, oldest
  /// first, refusals included.
  final List<List<String>> replacedPlaylistOrders = [];

  @override
  Future<void> replacePlaylistItems(
    String pid,
    List<String> itemPids, {
    DateTime? baseUpdatedAt,
  }) async {
    await getPlaylist(pid);
    replacedPlaylistOrders.add(List.of(itemPids));
    if (playlistReplaceConflict) {
      throw const WaxDeckApiException(
        code: 'conflict',
        message:
            'the playlist changed since this member list was built; '
            'refetch and retry',
        statusCode: 409,
      );
    }
    playlistMembers[pid] = List.of(itemPids);
  }

  @override
  Future<void> addPlaylistItems(String pid, List<String> itemPids) async {
    await getPlaylist(pid);
    (playlistMembers[pid] ??= []).addAll(itemPids);
  }

  /// What [removePlaylistItemAt] was asked, in order.
  final List<({int position, String? itemPid})> removedPlaylistEntries = [];

  /// Holds [removePlaylistItemAt] until completed.
  Completer<void>? removePlaylistItemGate;

  @override
  Future<void> removePlaylistItemAt(
    String pid,
    int position, {
    String? itemPid,
  }) async {
    await removePlaylistItemGate?.future;
    await getPlaylist(pid);
    removedPlaylistEntries.add((position: position, itemPid: itemPid));
    final members = playlistMembers[pid];
    // The server's guard: the slot still holds the item the caller saw.
    final held = members != null && position >= 0 && position < members.length
        ? members[position]
        : null;
    if (itemPid != null && held != itemPid) {
      throw const WaxDeckApiException(
        code: 'conflict',
        message:
            'the playlist changed since its members were read; refetch '
            'and retry',
        statusCode: 409,
      );
    }
    if (held != null) members!.removeAt(position);
  }

  /// Rules passed to [previewSmartRule], newest last.
  final List<SmartRule> previewedRules = [];

  @override
  Future<PlaylistPreview> previewSmartRule(SmartRule rule, {int? limit}) async {
    previewedRules.add(rule);
    return previewResult;
  }

  @override
  Future<RuleFields> getRuleFields() async => ruleFields;

  /// What [exportPlaylistM3u] serves, and the pids it was asked for.
  String exportM3uResult = '#EXTM3U\n';
  final List<String> exportedM3uPids = [];

  /// The documents [importPlaylistM3u] received, and the counts its
  /// result reports.
  final List<String> importedM3uContents = [];
  int importMatched = 0;
  int importUnmatched = 0;

  /// What [importPlaylistM3u] raises, and a gate it waits on until
  /// completed, so a test can act mid-import.
  WaxDeckApiException? importM3uError;
  Completer<void>? importM3uGate;

  @override
  Future<String> exportPlaylistM3u(String pid) async {
    exportedM3uPids.add(pid);
    return exportM3uResult;
  }

  @override
  Future<M3uImportResult> importPlaylistM3u({
    required String name,
    required String content,
    String? visibility,
  }) async {
    importedM3uContents.add(content);
    await importM3uGate?.future;
    final error = importM3uError;
    if (error != null) throw error;
    final pl = await createPlaylist(
      name: name,
      kind: 'static',
      visibility: visibility,
    );
    return M3uImportResult(
      playlist: pl,
      matched: importMatched,
      unmatched: importUnmatched,
    );
  }

  /// What [previewPlaylistM3u] answers or raises, and the documents it
  /// was asked about.
  M3uPreview m3uPreview = const M3uPreview(matched: 0, merged: 0, unmatched: 0);
  WaxDeckApiException? m3uPreviewError;
  final List<String> previewedM3uContents = [];

  /// Held open until completed, so a test can act mid-check.
  Completer<void>? m3uPreviewGate;

  @override
  Future<M3uPreview> previewPlaylistM3u(String content) async {
    previewedM3uContents.add(content);
    await m3uPreviewGate?.future;
    final error = m3uPreviewError;
    if (error != null) throw error;
    return m3uPreview;
  }

  /// The canned import report; null derives an empty one from the
  /// request.
  PlaylistImportResult? playlistImportResult;

  final List<
    ({String source, String? name, String? payload, List<PortableRef>? refs})
  >
  importPlaylistCalls = [];

  @override
  Future<PlaylistImportResult> importPlaylist({
    required String source,
    String? name,
    String? payload,
    List<PortableRef>? refs,
  }) async {
    importPlaylistCalls.add((
      source: source,
      name: name,
      payload: payload,
      refs: refs == null ? null : List.of(refs),
    ));
    return playlistImportResult ??
        PlaylistImportResult(
          name: name ?? 'Imported playlist',
          requested: 0,
          resolved: 0,
          rungs: const ResolveRungCounts(
            essence: 0,
            strongId: 0,
            fingerprint: 0,
            descriptive: 0,
          ),
        );
  }

  /// The portable export served by [exportPlaylistPortable], and the
  /// pids it was asked for.
  PortablePlaylist portableExport = const PortablePlaylist(
    name: 'Portable playlist',
  );
  final List<String> exportedPortablePids = [];

  @override
  Future<PortablePlaylist> exportPlaylistPortable(String pid) async {
    exportedPortablePids.add(pid);
    return portableExport;
  }

  /// Holds [getPlaylistSource] until completed.
  Completer<void>? playlistSourceGate;

  /// Stored source bindings by playlist pid; absent means unbound, the
  /// 404 the real endpoint answers.
  final Map<String, PlaylistSource> playlistSources = {};

  /// What [previewPlaylistSync] answers.
  PlaylistSyncPreview playlistSyncPreview = const PlaylistSyncPreview(
    entries: 0,
    wouldAdd: 0,
    wouldDownload: 0,
    wouldRemove: 0,
    wouldTrash: 0,
    pending: 0,
    unavailable: 0,
    missing: 0,
  );

  /// What [syncPlaylistSource] answers.
  ToolTask playlistSyncTask = ToolTask(
    id: 'tk-sync',
    type: 'playlist-sync',
    state: 'queued',
    createdAt: DateTime.utc(2026),
  );

  final List<
    ({
      String pid,
      String mode,
      String? url,
      String? source,
      String? payload,
      List<PortableRef>? refs,
      int? intervalHours,
    })
  >
  setPlaylistSourceCalls = [];
  final List<String> unbindPlaylistSourceCalls = [];
  final List<
    ({
      String pid,
      String? mode,
      String? url,
      String? source,
      String? payload,
      List<PortableRef>? refs,
      int? intervalHours,
    })
  >
  previewPlaylistSyncCalls = [];
  final List<String> syncPlaylistSourceCalls = [];

  /// Raised by [setPlaylistSource] when set, for the refusal path.
  WaxDeckApiException? playlistSourceError;

  /// Raised by [getPlaylistSource] when set, for the read-failed path.
  /// Distinct from an absent binding, which is the ordinary 404.
  WaxDeckApiException? playlistSourceReadError;

  @override
  Future<PlaylistSource> getPlaylistSource(String pid) async {
    await playlistSourceGate?.future;
    final readError = playlistSourceReadError;
    if (readError != null) throw readError;
    final src = playlistSources[pid];
    if (src == null) {
      throw WaxDeckApiException(
        statusCode: 404,
        code: 'not-found',
        message: 'the playlist has no source binding',
      );
    }
    return src;
  }

  @override
  Future<PlaylistSource> setPlaylistSource(
    String pid, {
    required String mode,
    String? url,
    String? source,
    String? payload,
    List<PortableRef>? refs,
    int? intervalHours,
  }) async {
    setPlaylistSourceCalls.add((
      pid: pid,
      mode: mode,
      url: url,
      source: source,
      payload: payload,
      refs: refs == null ? null : List.of(refs),
      intervalHours: intervalHours,
    ));
    final err = playlistSourceError;
    if (err != null) {
      throw err;
    }
    // The server's own shape checks, so a widget test that saves an
    // empty form sees the refusal production shows rather than a bound
    // state the real endpoint would never answer.
    final live = url != null && url.trim().isNotEmpty;
    final held = playlistSources[pid];
    // Presence, as the server reads it: `url: ''` names a source badly
    // and is a bind, not a re-save.
    if (url == null && source == null && payload == null && refs == null) {
      // The settings-only re-save: it needs a binding under it, and it
      // keeps everything about that binding but the settings.
      if (held == null) {
        throw WaxDeckApiException(
          statusCode: 400,
          code: 'invalid-request',
          message: 'bind a url or a source export',
        );
      }
      // The server's own shape rules, read off the stored row: without
      // them a body the real endpoint refuses passes here, which is
      // exactly the regression a widget test is for.
      if (!held.live && mode == 'mirror-trash') {
        throw const WaxDeckApiException(
          statusCode: 400,
          code: 'invalid-request',
          message:
              'a matched source downloads nothing and never removes files; '
              'append or mirror only',
        );
      }
      if (held.live && ![1, 3, 6, 12, 24].contains(intervalHours)) {
        throw const WaxDeckApiException(
          statusCode: 400,
          code: 'invalid-request',
          message: 'intervalHours must be 1, 3, 6, 12, or 24',
        );
      }
      if (!held.live && intervalHours != null) {
        throw const WaxDeckApiException(
          statusCode: 400,
          code: 'invalid-request',
          message: 'a matched source syncs on demand only; no interval',
        );
      }
      return playlistSources[pid] = PlaylistSource(
        source: held.source,
        url: held.url,
        title: held.title,
        refCount: held.refCount,
        live: held.live,
        mode: mode,
        intervalHours: held.live ? intervalHours : null,
        disabled: held.disabled,
        consecutiveFailures: held.consecutiveFailures,
        lastError: held.lastError,
        lastAttemptAt: held.lastAttemptAt,
        lastSyncedAt: held.lastSyncedAt,
        lastRun: held.lastRun,
      );
    }
    if (!live && source == null) {
      throw WaxDeckApiException(
        statusCode: 400,
        code: 'invalid-request',
        message: 'bind a url or a source export',
      );
    }
    final stored = PlaylistSource(
      source: live ? 'youtube' : (source ?? 'portable'),
      url: url,
      title: live ? 'Source Playlist' : null,
      live: live,
      mode: mode,
      intervalHours: live ? intervalHours : null,
      refCount: live ? null : (refs?.length ?? 1),
      disabled: false,
      consecutiveFailures: 0,
    );
    playlistSources[pid] = stored;
    return stored;
  }

  @override
  Future<void> unbindPlaylistSource(String pid) async {
    unbindPlaylistSourceCalls.add(pid);
    playlistSources.remove(pid);
  }

  /// Holds [previewPlaylistSync] until completed, with the call
  /// already recorded.
  Completer<void>? previewPlaylistSyncGate;

  @override
  Future<PlaylistSyncPreview> previewPlaylistSync(
    String pid, {
    String? mode,
    String? url,
    String? source,
    String? payload,
    List<PortableRef>? refs,
    int? intervalHours,
  }) async {
    previewPlaylistSyncCalls.add((
      pid: pid,
      mode: mode,
      url: url,
      source: source,
      payload: payload,
      refs: refs == null ? null : List.of(refs),
      intervalHours: intervalHours,
    ));
    await previewPlaylistSyncGate?.future;
    return playlistSyncPreview;
  }

  /// Raised by [syncPlaylistSource] when set, for the refusal paths
  /// (no binding, no bridge, read-only server).
  WaxDeckApiException? playlistSyncError;

  @override
  Future<ToolTask> syncPlaylistSource(String pid) async {
    syncPlaylistSourceCalls.add(pid);
    final err = playlistSyncError;
    if (err != null) {
      throw err;
    }
    return playlistSyncTask;
  }

  /// What [reportPlaylistNspExport] answers, and the NSP document
  /// [exportPlaylistNsp] hands back.
  NspReport nspReport = const NspReport(direction: 'export');
  Map<String, Object?> nspExport = const <String, Object?>{
    'name': 'Smart playlist',
    'all': <Object?>[],
  };

  /// Every NSP report and export, and for the export whether it asked
  /// for the lossy one and which report's rule it was pinned to.
  final List<String> nspReports = [];
  final List<({String pid, bool partial, String? ruleHash})> nspExports = [];

  /// Answered in turn ahead of [nspReport], so a rule can change between
  /// two reads.
  final List<NspReport> nspReportQueue = [];

  /// Raised by the report and by the export respectively. Two hooks and
  /// not one: the reachable refusal is the export's, after a report that
  /// answered, and a single hook cannot express that.
  WaxDeckApiException? nspReportError;
  WaxDeckApiException? nspExportError;

  /// Raised in turn by the export ahead of [nspExportError].
  final List<WaxDeckApiException> nspExportFailures = [];

  @override
  Future<NspReport> reportPlaylistNspExport(String pid) async {
    nspReports.add(pid);
    final error = nspReportError;
    if (error != null) throw error;
    if (nspReportQueue.isNotEmpty) return nspReportQueue.removeAt(0);
    return nspReport;
  }

  @override
  Future<Map<String, Object?>> exportPlaylistNsp(
    String pid, {
    bool partial = false,
    String? ruleHash,
  }) async {
    nspExports.add((pid: pid, partial: partial, ruleHash: ruleHash));
    if (nspExportFailures.isNotEmpty) throw nspExportFailures.removeAt(0);
    final error = nspExportError;
    if (error != null) throw error;
    return nspExport;
  }

  /// What [checkNspImport] answers, and what [importNsp] raises.
  NspReport nspImportReport = const NspReport(direction: 'import');
  WaxDeckApiException? nspImportError;

  /// Every NSP document checked, and every import with its choices.
  final List<Map<String, Object?>> nspImportChecks = [];
  final List<({Map<String, Object?> document, bool partial, String? name})>
  nspImports = [];

  /// Held open until completed, so a test can act mid-check.
  Completer<void>? nspImportCheckGate;

  /// Holds [importNsp] until completed, with the call recorded.
  Completer<void>? nspImportGate;

  @override
  Future<NspReport> checkNspImport(Map<String, Object?> document) async {
    nspImportChecks.add(document);
    await nspImportCheckGate?.future;
    return nspImportReport;
  }

  @override
  Future<Playlist> importNsp(
    Map<String, Object?> document, {
    bool partial = false,
    String? name,
  }) async {
    nspImports.add((document: document, partial: partial, name: name));
    if (nspImportGate case final gate?) await gate.future;
    final error = nspImportError;
    if (error != null) throw error;
    final named = document['name'];
    return createPlaylist(
      name: name ?? (named is String ? named : 'Imported'),
      kind: 'smart',
      rule: const SmartRule(root: RuleNode.all([])),
    );
  }
}
