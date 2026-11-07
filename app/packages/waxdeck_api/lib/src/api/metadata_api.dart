import 'dart:typed_data';

import '../models.dart';

/// Reading and editing item and entity metadata.
abstract interface class MetadataApi {
  /// `GET /metadata/fields`: the metadata editor vocabulary.
  Future<MetadataFields> getMetadataFields();

  /// `GET /items/{pid}/metadata`: everything the metadata editor
  /// shows for one item.
  Future<ItemMetadata> getItemMetadata(String pid);

  /// `GET /items/{pid}/permissions`: whether this account may edit
  /// the item, without the cost of the full editor document.
  Future<ItemPermissions> getItemPermissions(String pid);

  /// `PATCH /items/{pid}/metadata`: edits item fields. [lock] pins
  /// the edited fields against later automatic updates; [force]
  /// overwrites locked fields; [writeBack] also rewrites file tags.
  Future<MetadataEditResult> editItemMetadata(
    String pid, {
    required Map<String, String> fields,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  });

  /// `POST /items/{pid}/metadata/commit`: runs a whole staged editor
  /// draft in one request, in the same order the per-part calls would.
  ///
  /// It exists for latency: the sequential save is one round trip per
  /// part. Parts run until one is refused; that part reports its own
  /// error and the later ones report skipped, which is exactly what the
  /// sequential path produces, so the two are interchangeable. A
  /// refusal therefore does not throw - read
  /// [MetadataCommitResult.parts], or its `refusal` shorthand.
  ///
  /// A server too old for the route answers 404, which is a thrown
  /// `WaxDeckApiException` a caller can fall back on.
  Future<MetadataCommitResult> commitItemMetadata(
    String pid,
    MetadataCommit commit,
  );

  /// `POST /items/bulk-edit`: applies one field edit to many items.
  /// [skipLocked] passes over locked fields instead of failing.
  Future<BulkEditResult> bulkEditMetadata({
    required List<String> itemPids,
    required Map<String, String> fields,
    bool writeBack = false,
    bool skipLocked = false,
    bool force = false,
  });

  /// `PUT /items/{pid}/credits`: replaces one credited [role]'s
  /// [names], in order.
  Future<MetadataEditResult> setItemCredits(
    String pid, {
    required String role,
    required List<String> names,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  });

  /// `PUT /items/{pid}/lyrics`: stores synced ([lrc]) and/or [plain]
  /// lyrics for a track.
  Future<MetadataEditResult> setItemLyrics(
    String pid, {
    String? lrc,
    String? plain,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  });

  /// `DELETE /items/{pid}/lyrics`: removes the stored lyrics. With
  /// [writeBack] the `.lrc` sidecar beside the item's file goes too;
  /// lyrics embedded in the audio's own tags stay.
  Future<void> clearItemLyrics(String pid, {bool writeBack = false});

  /// `PUT /books/{pid}/chapters`: replaces an audiobook's chapter
  /// marks.
  Future<MetadataEditResult> setBookChapters(
    String pid, {
    required List<ChapterEdit> chapters,
    bool lock = true,
    bool force = false,
  });

  /// `PUT /items/{pid}/artwork`: replaces an item's artwork in one slot
  /// ([role], default `front`) with the uploaded image [bytes].
  Future<MetadataEditResult> setItemArtwork(
    String pid, {
    required Uint8List bytes,
    String role = 'front',
    bool writeBack = false,
    bool lock = true,
  });

  /// `DELETE /items/{pid}/artwork`: removes the curated artwork in one
  /// slot ([role], default `front`).
  Future<void> clearItemArtwork(String pid, {String role = 'front'});

  /// `PUT /entities/{entityType}/{entityPid}/artwork`: replaces a
  /// browse entity's artwork in one slot ([role], default `front`) with
  /// the uploaded image [bytes]. `playlist` is an owner-edited entity
  /// type here rather than an administrators-only catalog one.
  Future<MetadataEditResult> setEntityArtwork(
    String entityType,
    String entityPid, {
    required Uint8List bytes,
    String role = 'front',
    bool writeBack = false,
  });

  /// `DELETE /entities/{entityType}/{entityPid}/artwork`: removes a
  /// browse entity's artwork in one slot ([role], default `front`).
  /// Clearing a playlist's uploaded cover restores the one the server
  /// generates from the members.
  Future<void> clearEntityArtwork(
    String entityType,
    String entityPid, {
    String role = 'front',
  });

  /// `GET /entities/{entityType}/{entityPid}/artwork/lock`: whether one
  /// of a catalog entity's artwork slots is pinned against enrichment
  /// and scan re-derives. An auxiliary role reads the effective pin -
  /// the whole-artwork one or its own. Refuses `playlist`.
  Future<bool> getEntityArtworkLock(
    String entityType,
    String entityPid, {
    String role = 'front',
  });

  /// `PUT /entities/{entityType}/{entityPid}/artwork/lock`: pins or
  /// unpins one of a catalog entity's artwork slots without touching the
  /// image. Unpinning is the way out of a cover cleared and left pinned,
  /// which setting artwork cannot express. The default `front` writes
  /// the whole-artwork pin, which also gates enrichment's fills in every
  /// other role; a named auxiliary role writes that slot alone. Refuses
  /// `playlist`.
  Future<bool> setEntityArtworkLock(
    String entityType,
    String entityPid, {
    required bool locked,
    String role = 'front',
  });

  /// `PUT /items/{pid}/acquisition`: replaces the item's recorded
  /// origin. [sourceType], [sourceId] and [provider] are written as
  /// sent - a null one is **cleared** - because the automatic recorder
  /// is merge-wise and never lowers a field, so this is the only way a
  /// wrong value comes off. An absent [acquiredAt] keeps the stamp the
  /// row already carries.
  ///
  /// [sourceUrl] is the exception and works the other way: null keeps
  /// the stored address and `''` clears it. It is the one column the
  /// read redacts, so a caller is never shown the stored string in full
  /// and cannot faithfully resend it.
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
  });

  /// `DELETE /items/{pid}/acquisition`: takes the origin row off, so
  /// the item reads the source it has without one. Idempotent. [lock]
  /// defaults true because the row came from evidence still in the
  /// file; [writeBack] strips those tags, which is the durable half.
  Future<void> clearItemAcquisition(
    String pid, {
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  });

  /// `PUT /items/{pid}/tags/{key}`: replaces one custom tag's values,
  /// written into the item's files too with [writeBack].
  Future<TagEditResult> setItemTag(
    String pid,
    String key, {
    required List<String> values,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  });

  /// `DELETE /items/{pid}/tags/{key}`: removes one custom tag, stripped
  /// from the item's files too with [writeBack].
  Future<void> clearItemTag(String pid, String key, {bool writeBack = false});

  /// `PUT /items/{pid}/locks`: locks or unlocks [fields], returning
  /// the item's full locked-field list.
  Future<List<String>> setItemLocks(
    String pid, {
    required List<String> fields,
    required bool locked,
  });

  /// `PATCH /entities/{entityType}/{entityPid}`: edits a browse
  /// entity's curated fields.
  Future<MetadataEditResult> editEntity(
    String entityType,
    String entityPid, {
    required Map<String, String> edits,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  });

  /// `POST /items/{pid}/detach`: pulls one track off the release a
  /// MusicBrainz id pins it to.
  Future<DetachResult> detachItem(String pid, {bool writeBack = false});

  /// `POST /items/kind`: starts the job turning [pids] into `music`
  /// tracks or one `audiobook`, answering it at once; the finished job's
  /// result names the items' pids in their new form.
  Future<Job> setItemKind(
    List<String> pids, {
    required String mediaType,
    bool writeBack = false,
  });

  /// `POST /entities/{entityType}/{entityPid}/rename`: moves a whole
  /// album, release group, or artist onto new keying values, keeping
  /// the row.
  Future<EntityRenameResult> renameEntity(
    String entityType,
    String entityPid, {
    required Map<String, String> fields,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  });

  /// `GET /entities/{entityType}/{entityPid}/curation`: the entity's
  /// curated field overrides.
  Future<List<EntityCuratedField>> getEntityCuration(
    String entityType,
    String entityPid,
  );

  /// `PUT /items/{pid}/release-status`: marks an item's release
  /// official or unofficial, written into its files too with
  /// [writeBack].
  Future<MetadataEditResult> setReleaseStatus(
    String pid, {
    required bool unofficial,
    bool writeBack = false,
  });

  /// `POST /items/{pid}/rematch`: reopens identification for the
  /// item's release, returning the review entry id to watch.
  Future<String> rematchItem(String pid);

  /// `POST /items/{pid}/enrich`: fetches the wanted artifacts
  /// (`cover`, `lyrics`, `genres`, `book`, `fields`) for one item now.
  /// `fields` is a track's scalar metadata and `book` an audiobook's;
  /// the server refuses either for the wrong kind. With a
  /// [proposal] nothing is fetched: the server commits exactly what
  /// the preview answered, so what was approved is what lands (the
  /// catalog's un-previewable built-ins still backfill after it).
  Future<EnrichItemResult> enrichItem(
    String pid, {
    required List<String> want,
    EnrichProposal? proposal,
  });

  /// `POST /items/{pid}/enrich/preview`: what the providers would
  /// change for the wanted artifacts, without writing anything.
  Future<EnrichPreview> previewEnrichItem(
    String pid, {
    required List<String> want,
  });
}
