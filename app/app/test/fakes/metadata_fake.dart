import 'dart:async';
import 'dart:typed_data';

import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// In-memory [MetadataApi] for `FakeRepository`.
mixin FakeMetadata on FakeRepositoryState implements MetadataApi {
  /// Stands in for the server's own normalizers, which run on the way in
  /// so a stored value can differ from what was typed (a barcode loses
  /// its separators, a country upper-cases). Identity by default.
  String Function(String field, String value)? normalizeEntityEdit;

  /// Thrown by the metadata endpoints when set.
  WaxDeckApiException? metadataError;

  /// Editor state by item pid.
  final Map<String, Map<String, String>> itemFieldsByPid = {};
  final Map<String, Set<String>> lockedFieldsByPid = {};
  final Map<String, List<Credit>> creditsByPid = {};
  final Map<String, LyricsState> lyricsByPid = {};
  final Map<String, Map<String, List<String>>> tagsByPid = {};
  final Map<String, List<ChapterEdit>> chapterEditsByPid = {};
  final Map<String, List<ChapterMark>> chaptersByPid = {};
  final Set<String> artworkPids = {};
  final Set<String> ownArtworkPids = {};
  final Set<String> unofficialPids = {};

  /// What the metadata read answers for "may this caller edit it".
  /// True by default: the tests that mount the editor are standing in
  /// for somebody who may, and the one that checks the refusal says so.
  /// Null is a server that carries no such field - one older than it,
  /// or one whose ownership lookup failed.
  bool? mayCurateItems = true;

  /// Entity curation by `entityType/entityPid`.
  final Map<String, Map<String, String>> entityEditsByKey = {};
  final Map<String, List<EntityCuratedField>> entityCurationByKey = {};

  final List<({String pid, Map<String, String> fields, bool writeBack})>
  editItemMetadataCalls = [];

  /// Every entity edit, with the flags it carried. The map above records
  /// what an entity ends up holding; this records how each write asked
  /// for it, which is what a sparse-edit or a Force test is about.
  final List<
    ({
      String entityType,
      String entityPid,
      Map<String, String> edits,
      bool writeBack,
      bool lock,
      bool force,
    })
  >
  entityEdits = [];

  /// Every entity rename, with the flags it carried.
  final List<
    ({
      String entityType,
      String entityPid,
      Map<String, String> fields,
      bool writeBack,
      bool lock,
      bool force,
    })
  >
  renameEntityCalls = [];

  /// Every detach, in call order.
  final List<({String pid, bool writeBack})> detachCalls = [];

  /// What the next [detachItem] answers; the default reports a landing
  /// on a fresh album.
  DetachResult? detachResult;

  /// Where an `mbid` clear re-keys the entity, when a test is about
  /// the merge branch: the survivor's pid, reported the way the server
  /// reports it so a screen following the caller's pid can move.
  String? entityEditMergesInto;

  /// What the next [renameEntity] answers. A test that cares about the
  /// merge branch sets one; the default is the plain rename that keeps
  /// the pid.
  EntityRenameResult? renameEntityResult;
  final List<({String entityType, String entityPid, int byteCount})>
  entityArtworkCalls = [];
  final List<({String entityType, String entityPid})> clearEntityArtworkCalls =
      [];
  final List<String> rematchCalls = [];
  final List<({String pid, List<String> want, EnrichProposal? proposal})>
  enrichItemCalls = [];
  final List<({String pid, List<String> want})> previewEnrichItemCalls = [];
  final List<({String pid, List<String> fields, bool locked})>
  setItemLocksCalls = [];
  final List<({String pid, bool unofficial})> setReleaseStatusCalls = [];

  /// The editor vocabulary served by [getMetadataFields].
  MetadataFields metadataFields = const MetadataFields(
    kinds: [
      KindFields(
        kind: MediaType.music,
        fields: [
          EditableField(name: 'title', writeBack: true),
          EditableField(name: 'artist', writeBack: true),
          EditableField(name: 'album', writeBack: true),
          EditableField(name: 'year', writeBack: true),
          // Two of the server's snake_case keys, because the editor
          // draws a field's name and half the real vocabulary is
          // spelled this way: a form served only single words cannot
          // tell a display name from a wire key.
          EditableField(name: 'album_artist', writeBack: true),
          EditableField(name: 'track_no', writeBack: true),
        ],
        creditRoles: [EditableField(name: 'composer', writeBack: true)],
      ),
    ],
    entityTypes: [
      EntityTypeFields(
        entityType: 'artist',
        fields: [EditableField(name: 'name', writeBack: false)],
      ),
    ],
    // One reserved key, because the tag editor's refusal is about the
    // set being consulted rather than about which keys are in it.
    reservedTagKeys: ['BPM', 'MEDIATYPE', 'NARRATOR'],
  );

  void _requireUnlocked(String pid, Iterable<String> fields, bool force) {
    if (force) return;
    final locked = lockedFieldsByPid[pid] ?? const {};
    if (fields.any(locked.contains)) {
      // The code the server sends for this, not the generic conflict:
      // the editor answers this one refusal itself.
      throw const WaxDeckApiException(
        code: 'field-locked',
        message: 'field locked',
        statusCode: 409,
      );
    }
  }

  @override
  Future<MetadataFields> getMetadataFields() async => metadataFields;

  /// Entity pids the metadata read carries, per item pid.
  final Map<
    String,
    ({String? artistPid, String? albumPid, String? releaseGroupPid})
  >
  metadataEntityPids = {};

  @override
  Future<ItemPermissions> getItemPermissions(String pid) async {
    final error = metadataError;
    if (error != null) throw error;
    // The null knob means "a server that does not say" - on the wire
    // that is a server too old for this route, which answers 404, not
    // a permissions document with the field missing.
    final may = mayCurateItems;
    if (may == null) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such route',
        statusCode: 404,
      );
    }
    return ItemPermissions(mayCurate: may);
  }

  @override
  Future<ItemMetadata> getItemMetadata(String pid) async {
    final error = metadataError;
    if (error != null) throw error;
    final item = libraryItems.where((i) => i.pid == pid).firstOrNull;
    final entities = metadataEntityPids[pid];
    return ItemMetadata(
      pid: pid,
      mediaType: item?.mediaType ?? MediaType.music,
      fields: Map.of(itemFieldsByPid[pid] ?? const {}),
      lockedFields: (lockedFieldsByPid[pid] ?? const <String>{}).toList()
        ..sort(),
      provenance: itemProvenance[pid] ?? const [],
      credits: creditsByPid[pid] ?? const [],
      lyrics: lyricsByPid[pid],
      chapters: chaptersByPid[pid] ?? const [],
      customTags: [
        for (final entry in (tagsByPid[pid] ?? const {}).entries)
          CustomTag(key: entry.key, values: entry.value),
      ],
      unofficial: unofficialPids.contains(pid),
      hasArtwork: artworkPids.contains(pid) || ownArtworkPids.contains(pid),
      hasOwnArtwork: ownArtworkPids.contains(pid),
      artistPid: entities?.artistPid,
      albumPid: entities?.albumPid,
      releaseGroupPid: entities?.releaseGroupPid,
      mayCurate: mayCurateItems,
      acquisition: itemAcquisition[pid],
    );
  }

  /// Holds [editItemMetadata] until completed, with the call already
  /// recorded.
  Completer<void>? editItemMetadataGate;

  @override
  Future<MetadataEditResult> editItemMetadata(
    String pid, {
    required Map<String, String> fields,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    editItemMetadataCalls.add((
      pid: pid,
      fields: Map.of(fields),
      writeBack: writeBack,
    ));
    if (editItemMetadataGate case final gate?) await gate.future;
    _requireUnlocked(pid, fields.keys, force);
    (itemFieldsByPid[pid] ??= {}).addAll(fields);
    if (lock) (lockedFieldsByPid[pid] ??= {}).addAll(fields.keys);
    return const MetadataEditResult(applied: true);
  }

  /// When set, the compound save answers with this instead of running,
  /// so a test can stand in an older server (404, no route) or a
  /// refusal of the whole request.
  WaxDeckApiException? commitError;

  /// Every compound commit, so a test can see that one request carried
  /// what N would have.
  final List<({String pid, MetadataCommit commit})> commitCalls = [];

  @override
  Future<MetadataCommitResult> commitItemMetadata(
    String pid,
    MetadataCommit commit,
  ) async {
    // Recorded before the refusal, not after: a test that asks whether
    // the client stopped trying the route needs the attempt to be
    // observable even when it fails.
    commitCalls.add((pid: pid, commit: commit));
    final error = commitError;
    if (error != null) throw error;
    // The parts run through the same fake writes the sequential path
    // uses, in the same order, so the two paths cannot drift here in a
    // way they would not on the server.
    final parts = <MetadataCommitPart>[];
    final failures = <WriteBackFailure>[];
    final warnings = <String>[];
    var refused = false;
    Future<void> part(
      MetadataCommitPartKind kind,
      String? detail,
      Future<MetadataEditResult?> Function() run,
    ) async {
      if (refused) {
        parts.add(
          MetadataCommitPart(
            part: kind,
            detail: detail,
            status: MetadataCommitStatus.skipped,
          ),
        );
        return;
      }
      try {
        final result = await run();
        parts.add(
          MetadataCommitPart(
            part: kind,
            detail: detail,
            status: MetadataCommitStatus.committed,
          ),
        );
        if (result != null) {
          failures.addAll(result.writeBackFailures);
          warnings.addAll(result.warnings);
        }
      } on WaxDeckApiException catch (e) {
        refused = true;
        parts.add(
          MetadataCommitPart(
            part: kind,
            detail: detail,
            status: MetadataCommitStatus.refused,
            // No status code: the response itself succeeded.
            refusal: WaxDeckApiException(code: e.code, message: e.message),
          ),
        );
      }
    }

    final fields = commit.fields;
    if (fields != null && fields.isNotEmpty) {
      await part(
        MetadataCommitPartKind.fields,
        null,
        () => editItemMetadata(
          pid,
          fields: fields,
          writeBack: commit.writeBack,
          lock: commit.lock,
          force: commit.force,
        ),
      );
    }
    for (final credit in commit.credits) {
      await part(
        MetadataCommitPartKind.credit,
        credit.role,
        () => setItemCredits(
          pid,
          role: credit.role,
          names: credit.names,
          writeBack: commit.writeBack,
          lock: commit.lock,
          force: commit.force,
        ),
      );
    }
    if (commit.lyrics case final lyrics?) {
      await part(
        MetadataCommitPartKind.lyrics,
        null,
        () => setItemLyrics(
          pid,
          lrc: lyrics.lrc,
          plain: lyrics.plain,
          writeBack: commit.writeBack,
          lock: commit.lock,
          force: commit.force,
        ),
      );
    } else if (commit.clearLyrics) {
      await part(MetadataCommitPartKind.lyrics, null, () async {
        await clearItemLyrics(pid, writeBack: commit.writeBack);
        return null;
      });
    }
    if (commit.chapters case final chapters?) {
      await part(
        MetadataCommitPartKind.chapters,
        null,
        () => setBookChapters(
          pid,
          chapters: chapters,
          lock: commit.lock,
          force: commit.force,
        ),
      );
    }
    // Sorted, as the server applies them: a JSON object carries no order.
    for (final key in commit.tagSets.keys.toList()..sort()) {
      await part(MetadataCommitPartKind.tagSet, key, () async {
        final result = await setItemTag(
          pid,
          key,
          values: commit.tagSets[key]!,
          writeBack: commit.writeBack,
          lock: commit.lock,
          force: commit.force,
        );
        return MetadataEditResult(
          applied: true,
          writeBackFailures: result.writeBackFailures,
        );
      });
    }
    for (final key in commit.tagRemoves) {
      await part(MetadataCommitPartKind.tagRemove, key, () async {
        await clearItemTag(pid, key, writeBack: commit.writeBack);
        return null;
      });
    }
    if (commit.unofficial case final unofficial?) {
      await part(
        MetadataCommitPartKind.releaseStatus,
        null,
        () => setReleaseStatus(
          pid,
          unofficial: unofficial,
          writeBack: commit.writeBack,
        ),
      );
    }
    return MetadataCommitResult(
      parts: parts,
      writeBackFailures: failures,
      warnings: warnings,
    );
  }

  final List<
    ({
      List<String> itemPids,
      Map<String, String> fields,
      bool writeBack,
      bool skipLocked,
      bool force,
    })
  >
  bulkEditCalls = [];

  /// What a bulk edit of a release-keying field answers as
  /// `resultingAlbumPid` - the fake's stand-in for the regroup the real
  /// server performs. Null means the response carries none.
  String? bulkEditRegroupsTo;

  @override
  Future<BulkEditResult> bulkEditMetadata({
    required List<String> itemPids,
    required Map<String, String> fields,
    bool writeBack = false,
    bool skipLocked = false,
    bool force = false,
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    bulkEditCalls.add((
      itemPids: List.of(itemPids),
      fields: Map.of(fields),
      writeBack: writeBack,
      skipLocked: skipLocked,
      force: force,
    ));
    final edited = <String>[];
    final skipped = <String>[];
    for (final pid in itemPids) {
      final locked = lockedFieldsByPid[pid] ?? const {};
      if (!force && skipLocked && fields.keys.any(locked.contains)) {
        skipped.add(pid);
        continue;
      }
      _requireUnlocked(pid, fields.keys, force);
      (itemFieldsByPid[pid] ??= {}).addAll(fields);
      // The real endpoint always locks what it writes (Lock: LockOn);
      // the fake keeps that so a repeat edit refuses the same way.
      (lockedFieldsByPid[pid] ??= {}).addAll(fields.keys);
      edited.add(pid);
    }
    final keyed = const [
      'album',
      'album_artist',
      'year',
    ].any(fields.containsKey);
    return BulkEditResult(
      edited: edited,
      skipped: skipped,
      resultingAlbumPid: keyed && edited.isNotEmpty ? bulkEditRegroupsTo : null,
    );
  }

  @override
  Future<MetadataEditResult> setItemCredits(
    String pid, {
    required String role,
    required List<String> names,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    final credits = creditsByPid[pid] ?? const <Credit>[];
    creditsByPid[pid] = [
      for (final c in credits)
        if (c.role != role) c,
      Credit(role: role, names: List.of(names)),
    ];
    return const MetadataEditResult(applied: true);
  }

  @override
  Future<MetadataEditResult> setItemLyrics(
    String pid, {
    String? lrc,
    String? plain,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    // The lrc field carries plain text too, exactly as the server's
    // read does: unsynced lyrics fill the same box the editor edits.
    lyricsByPid[pid] = LyricsState(
      synced: lrc != null,
      source: 'user',
      lrc: lrc ?? plain,
    );
    return const MetadataEditResult(applied: true);
  }

  @override
  Future<void> clearItemLyrics(String pid, {bool writeBack = false}) async {
    partWriteBacks.add((part: 'lyrics clear', writeBack: writeBack));
    lyricsByPid.remove(pid);
  }

  /// The write switch each tag, lyrics-clear and release-status write
  /// carried, in call order, so a test can see a save forward it.
  final List<({String part, bool writeBack})> partWriteBacks = [];

  /// Files [setItemTag] answers it could not write, the edit standing.
  List<WriteBackFailure> tagWriteBackFailures = const [];

  @override
  Future<MetadataEditResult> setBookChapters(
    String pid, {
    required List<ChapterEdit> chapters,
    bool lock = true,
    bool force = false,
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    chapterEditsByPid[pid] = List.of(chapters);
    return const MetadataEditResult(applied: true);
  }

  /// The editor's provenance rows per item: the scalar fields somebody
  /// set, plus an art or lyrics row wherever the item holds one.
  final Map<String, List<FieldProvenance>> itemProvenance = {};

  /// The recorded origin per item, for the editor's read-only origin
  /// caption. Absent is the ordinary state of a plainly ripped item.
  final Map<String, ItemAcquisition> itemAcquisition = {};

  /// Every origin correction, so a test can assert what the sheet sent
  /// rather than only what it drew afterwards.
  final List<
    ({
      String pid,
      String sourceType,
      String? sourceUrl,
      String? sourceId,
      String? provider,
      bool writeBack,
    })
  >
  setItemAcquisitionCalls = [];

  /// Every origin clear, likewise.
  final List<({String pid, bool writeBack})> clearItemAcquisitionCalls = [];

  /// Entity artwork pins, by "entityType/entityPid/role". The fake
  /// keys each role separately, where the server reports an effective
  /// lock; a test that cares about that distinction drives the real one.
  final Map<String, bool> entityArtworkLocks = {};

  /// Every slot write, so a test can see which role got which bytes.
  final List<({String pid, String role, int bytes, bool writeBack})>
  setItemArtworkCalls = [];

  /// The files [setItemArtwork] reports it could not write.
  List<WriteBackFailure> setItemArtworkFailures = const [];
  final List<({String pid, String role})> clearItemArtworkCalls = [];

  @override
  Future<MetadataEditResult> setItemArtwork(
    String pid, {
    required Uint8List bytes,
    String role = 'front',
    bool writeBack = false,
    bool lock = true,
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    setItemArtworkCalls.add((
      pid: pid,
      role: role,
      bytes: bytes.length,
      writeBack: writeBack,
    ));
    artworkPids.add(pid);
    if (!artRoles.any((r) => r.role == role)) {
      artRoles.add(ArtRoleInfo(role: role, format: 'png', width: 8, height: 8));
    }
    return MetadataEditResult(
      applied: true,
      writeBackFailures: setItemArtworkFailures,
    );
  }

  @override
  Future<void> clearItemArtwork(String pid, {String role = 'front'}) async {
    clearItemArtworkCalls.add((pid: pid, role: role));
    artRoles.removeWhere((r) => r.role == role);
    if (role == 'front') artworkPids.remove(pid);
  }

  @override
  Future<MetadataEditResult> setEntityArtwork(
    String entityType,
    String entityPid, {
    required Uint8List bytes,
    String role = 'front',
    bool writeBack = false,
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    entityArtworkCalls.add((
      entityType: entityType,
      entityPid: entityPid,
      byteCount: bytes.length,
    ));
    return const MetadataEditResult(applied: true);
  }

  @override
  Future<void> clearEntityArtwork(
    String entityType,
    String entityPid, {
    String role = 'front',
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    clearEntityArtworkCalls.add((entityType: entityType, entityPid: entityPid));
  }

  @override
  Future<bool> getEntityArtworkLock(
    String entityType,
    String entityPid, {
    String role = 'front',
  }) async => entityArtworkLocks['$entityType/$entityPid/$role'] ?? false;

  @override
  Future<bool> setEntityArtworkLock(
    String entityType,
    String entityPid, {
    required bool locked,
    String role = 'front',
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    entityArtworkLocks['$entityType/$entityPid/$role'] = locked;
    return locked;
  }

  @override
  Future<MetadataEditResult> setItemAcquisition(
    String pid, {
    required String sourceType,
    String? sourceUrl,
    String? sourceId,
    String? provider,
    DateTime? acquiredAt,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    setItemAcquisitionCalls.add((
      pid: pid,
      sourceType: sourceType,
      sourceUrl: sourceUrl,
      sourceId: sourceId,
      provider: provider,
      writeBack: writeBack,
    ));
    // The server replaces every editable column as sent, so the fake
    // does too: a test asserting that an absent field cleared would
    // otherwise pass against a merge the real one does not do. The
    // address is the documented exception - absent keeps, because the
    // read redacts it and a client is never shown the stored string in
    // full - and the fake keeps it too, for the same reason in reverse.
    final standing = itemAcquisition[pid];
    itemAcquisition[pid] = ItemAcquisition(
      sourceType: sourceType,
      sourceUrl: sourceUrl ?? standing?.sourceUrl,
      sourceId: sourceId,
      provider: provider,
      acquiredAt: acquiredAt ?? standing?.acquiredAt,
      locked: lock,
    );
    return const MetadataEditResult(applied: true);
  }

  @override
  Future<void> clearItemAcquisition(
    String pid, {
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    clearItemAcquisitionCalls.add((pid: pid, writeBack: writeBack));
    itemAcquisition.remove(pid);
  }

  @override
  Future<TagEditResult> setItemTag(
    String pid,
    String key, {
    required List<String> values,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    partWriteBacks.add((part: 'tag $key', writeBack: writeBack));
    (tagsByPid[pid] ??= {})[key] = List.of(values);
    return TagEditResult(
      key: key,
      stored: values.length,
      writeBackFailures: writeBack ? tagWriteBackFailures : const [],
    );
  }

  @override
  Future<void> clearItemTag(
    String pid,
    String key, {
    bool writeBack = false,
  }) async {
    partWriteBacks.add((part: 'untag $key', writeBack: writeBack));
    tagsByPid[pid]?.remove(key);
  }

  /// Held open, a lock write waits on it: a save in flight.
  Completer<void>? setItemLocksGate;

  @override
  Future<List<String>> setItemLocks(
    String pid, {
    required List<String> fields,
    required bool locked,
  }) async {
    await setItemLocksGate?.future;
    setItemLocksCalls.add((pid: pid, fields: List.of(fields), locked: locked));
    final locks = lockedFieldsByPid[pid] ??= {};
    locked ? locks.addAll(fields) : locks.removeAll(fields);
    return locks.toList()..sort();
  }

  @override
  Future<MetadataEditResult> editEntity(
    String entityType,
    String entityPid, {
    required Map<String, String> edits,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    entityEdits.add((
      entityType: entityType,
      entityPid: entityPid,
      edits: Map<String, String>.of(edits),
      writeBack: writeBack,
      lock: lock,
      force: force,
    ));
    final normalize = normalizeEntityEdit;
    final stored = <String, String>{
      for (final entry in edits.entries)
        entry.key: normalize == null
            ? entry.value
            : normalize(entry.key, entry.value),
    };
    (entityEditsByKey['$entityType/$entityPid'] ??= {}).addAll(stored);
    // The edit lands in the album the read surface answers, so a test can
    // save and then look at what a refetch brings back.
    if (entityType == 'album') {
      final album = albums[entityPid];
      if (album != null) {
        albums[entityPid] = AlbumDetail(
          pid: album.pid,
          title: album.title,
          sortKey: album.sortKey,
          mbid: stored['mbid'] ?? album.mbid,
          year: album.year,
          releaseGroupPid: album.releaseGroupPid,
          barcode: stored['barcode'] ?? album.barcode,
          label: stored['label'] ?? album.label,
          catalogNumber: stored['catalog_number'] ?? album.catalogNumber,
          media: stored['media'] ?? album.media,
          country: stored['country'] ?? album.country,
          itemCount: album.itemCount,
          totalDurationMs: album.totalDurationMs,
        );
      }
    }
    final survivor = entityEditMergesInto;
    if (survivor != null && edits['mbid'] == '') {
      return MetadataEditResult(applied: true, mergedInto: survivor);
    }
    return const MetadataEditResult(applied: true);
  }

  final setKindCalls =
      <({List<String> pids, String mediaType, bool writeBack})>[];

  /// Starts a kind change: answers it running and lists it finished, the
  /// first item named under its new kind's prefix, unless a test put its
  /// own job in [jobs] first.
  @override
  Future<Job> setItemKind(
    List<String> pids, {
    required String mediaType,
    bool writeBack = false,
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    setKindCalls.add((pids: pids, mediaType: mediaType, writeBack: writeBack));
    const pid = 'jb-01JZX5N8QW3F4V9T2B7KDKIND00';
    final first =
        '${mediaType == 'audiobook' ? 'bk' : 'tr'}-${pids.first.substring(3)}';
    if (!jobs.any((j) => j.pid == pid)) {
      jobs = [
        ...jobs,
        Job(
          pid: pid,
          kind: 'set-kind',
          state: 'done',
          result: {
            'converted': [first],
            'absorbed': {
              for (final p in pids.skip(1))
                '${mediaType == 'audiobook' ? 'tr' : 'bk'}-${p.substring(3)}':
                    first,
            },
            'created': const <String>[],
            'writeBackFailures': const <Object>[],
          },
        ),
      ];
    }
    return const Job(pid: pid, kind: 'set-kind', state: 'running');
  }

  @override
  Future<DetachResult> detachItem(String pid, {bool writeBack = false}) async {
    final error = metadataError;
    if (error != null) throw error;
    detachCalls.add((pid: pid, writeBack: writeBack));
    return detachResult ??
        DetachResult(
          itemPid: pid,
          oldAlbumPid: 'al-01JZX5N8QW3F4V9T2B7KDALBUM',
          newAlbumPid: 'al-01JZX5N8QW3F4V9T2B7KDLOOSE',
        );
  }

  @override
  Future<EntityRenameResult> renameEntity(
    String entityType,
    String entityPid, {
    required Map<String, String> fields,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    renameEntityCalls.add((
      entityType: entityType,
      entityPid: entityPid,
      fields: Map<String, String>.of(fields),
      writeBack: writeBack,
      lock: lock,
      force: force,
    ));
    // The rename writes the keying fields onto every member and locks
    // them, exactly as the real one does, whichever branch it takes.
    for (final member
        in facetItems['$entityType ${entityPid.substring(3)}'] ??
            const <ItemSummary>[]) {
      (itemFieldsByPid[member.pid] ??= {}).addAll(fields);
      (lockedFieldsByPid[member.pid] ??= {}).addAll(fields.keys);
    }
    final canned = renameEntityResult;
    if (canned != null) return canned;
    // The default is the branch the row survives: the album read
    // answers the new title, so a test can rename and then refetch.
    if (entityType == 'album') {
      final album = albums[entityPid];
      if (album != null) {
        albums[entityPid] = AlbumDetail(
          pid: album.pid,
          title: fields['album'] ?? album.title,
          sortKey: album.sortKey,
          mbid: album.mbid,
          year: int.tryParse(fields['year'] ?? '') ?? album.year,
          releaseGroupPid: album.releaseGroupPid,
          barcode: album.barcode,
          label: album.label,
          catalogNumber: album.catalogNumber,
          media: album.media,
          country: album.country,
          itemCount: album.itemCount,
          totalDurationMs: album.totalDurationMs,
        );
      }
    }
    return EntityRenameResult(
      entityPid: entityPid,
      outcome: EntityRenameOutcome.renamed,
      members: albums[entityPid]?.itemCount ?? 0,
      credits: 0,
    );
  }

  @override
  Future<List<EntityCuratedField>> getEntityCuration(
    String entityType,
    String entityPid,
  ) async {
    final key = '$entityType/$entityPid';
    final canned = entityCurationByKey[key];
    if (canned != null) return canned;
    return [
      for (final entry in (entityEditsByKey[key] ?? const {}).entries)
        EntityCuratedField(
          field: entry.key,
          value: entry.value,
          source: 'user',
          locked: true,
        ),
    ];
  }

  @override
  Future<MetadataEditResult> setReleaseStatus(
    String pid, {
    required bool unofficial,
    bool writeBack = false,
  }) async {
    setReleaseStatusCalls.add((pid: pid, unofficial: unofficial));
    partWriteBacks.add((part: 'release status', writeBack: writeBack));
    unofficial ? unofficialPids.add(pid) : unofficialPids.remove(pid);
    return const MetadataEditResult(applied: true);
  }

  @override
  Future<String> rematchItem(String pid) async {
    final error = metadataError;
    if (error != null) throw error;
    rematchCalls.add(pid);
    final entry = ReviewEntry(
      id: 're-FAKE${reviewEntries.length}',
      kind: 'match',
      status: 'pending',
      mediaType: MediaType.music,
      origin: 'rematch',
      trackCount: 1,
      identifying: true,
      createdAt: DateTime.utc(2026, 7, 1),
    );
    reviewEntries = [...reviewEntries, entry];
    return entry.id;
  }

  /// Run as the enrichment lands, for a test that needs the stored
  /// fields to change under an open editor the way a real provider run
  /// changes them.
  void Function()? onEnrich;

  @override
  Future<EnrichItemResult> enrichItem(
    String pid, {
    required List<String> want,
    EnrichProposal? proposal,
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    enrichItemCalls.add((pid: pid, want: List.of(want), proposal: proposal));
    onEnrich?.call();
    return EnrichItemResult(applied: List.of(want));
  }

  /// Served by [previewEnrichItem]; empty by default, the way a server
  /// with no injected providers answers.
  EnrichPreview enrichPreview = const EnrichPreview(
    skipped: ['cover: no provider'],
  );

  @override
  Future<EnrichPreview> previewEnrichItem(
    String pid, {
    required List<String> want,
  }) async {
    final error = metadataError;
    if (error != null) throw error;
    previewEnrichItemCalls.add((pid: pid, want: List.of(want)));
    return enrichPreview;
  }
}
