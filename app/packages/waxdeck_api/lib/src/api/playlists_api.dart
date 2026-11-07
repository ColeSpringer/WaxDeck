import '../models.dart';

/// Playlists, smart rules, import and export, and external sources.
abstract interface class PlaylistsApi {
  /// `GET /playlists`: the caller's playlists plus every shared one.
  /// [containsItem] restricts to static playlists holding that item.
  Future<PlaylistPage> listPlaylists({
    String? cursor,
    int? limit,
    String? containsItem,
  });

  /// `POST /playlists`: creates a static or smart playlist. A smart
  /// playlist requires [rule]; a static one may seed [itemPids].
  Future<Playlist> createPlaylist({
    required String name,
    required String kind,
    String? visibility,
    SmartRule? rule,
    List<String> itemPids,
  });

  /// `GET /playlists/{pid}`: one playlist, with a computed count for
  /// smart lists.
  Future<Playlist> getPlaylist(String pid);

  /// `PATCH /playlists/{pid}`: partial update. Replacing a smart rule
  /// applies in place under the same pid; the returned playlist carries
  /// the updated rule.
  Future<Playlist> updatePlaylist(
    String pid, {
    String? name,
    String? visibility,
    SmartRule? rule,
  });

  /// `DELETE /playlists/{pid}`: deletes an owned playlist.
  Future<void> deletePlaylist(String pid);

  /// `GET /playlists/{pid}/items`: the members in order, with stored
  /// positions for static playlists.
  Future<PlaylistItemsPage> listPlaylistItems(
    String pid, {
    String? cursor,
    int? limit,
  });

  /// `PUT /playlists/{pid}/items`: full ordered replace, which is also
  /// the reorder primitive. [baseUpdatedAt] is the lost-update guard.
  Future<void> replacePlaylistItems(
    String pid,
    List<String> itemPids, {
    DateTime? baseUpdatedAt,
  });

  /// `POST /playlists/{pid}/items`: appends members.
  Future<void> addPlaylistItems(String pid, List<String> itemPids);

  /// `DELETE /playlists/{pid}/items/{position}`: removes the member at
  /// one stored position. [itemPid] is the item the caller saw there;
  /// when the position holds another item, or none, the answer is
  /// `conflict` and nothing is removed.
  Future<void> removePlaylistItemAt(
    String pid,
    int position, {
    String? itemPid,
  });

  /// `POST /playlists/preview`: evaluates a rule without storing it.
  Future<PlaylistPreview> previewSmartRule(SmartRule rule, {int? limit});

  /// `GET /playlists/rule-fields`: the rule vocabulary for editors.
  Future<RuleFields> getRuleFields();

  /// `GET /playlists/{pid}/m3u`: the playlist as an M3U8 document.
  Future<String> exportPlaylistM3u(String pid);

  /// `POST /playlists/m3u`: imports an M3U8 document as a static
  /// playlist, reporting unmatched entries.
  Future<M3uImportResult> importPlaylistM3u({
    required String name,
    required String content,
    String? visibility,
  });

  /// `POST /playlists/m3u/preview`: how each line of an M3U8 document
  /// would import for the caller, without importing it.
  Future<M3uPreview> previewPlaylistM3u(String content);

  /// `POST /playlists/import`: imports a playlist export as a static
  /// playlist. [source] is `spotify`, `applemusic`, `ytmusic`, `csv`,
  /// `text`, or `portable`; [payload] carries the export text for the
  /// text sources, [refs] the portable refs for `portable`. The result
  /// reports unmatched entries and per-rung match confidence.
  Future<PlaylistImportResult> importPlaylist({
    required String source,
    String? name,
    String? payload,
    List<PortableRef>? refs,
  });

  /// `GET /playlists/{pid}/portable`: the playlist as portable refs,
  /// for re-importing on another WaxDeck server.
  Future<PortablePlaylist> exportPlaylistPortable(String pid);

  /// `GET /playlists/{pid}/source`: the playlist's external source
  /// binding with its sync settings and health. Owner only; a 404
  /// means the playlist has no binding, which is the normal unbound
  /// state rather than a failure.
  Future<PlaylistSource> getPlaylistSource(String pid);

  /// `PUT /playlists/{pid}/source`: bind the playlist to an external
  /// source, or re-save the settings on the binding already stored.
  ///
  /// [url] names a live source; [source] plus [payload] or [refs]
  /// records a matched export. Either form replaces any previous
  /// binding whole, so send the complete settings with it.
  /// [intervalHours] is required for a live source (1, 3, 6, 12, or 24)
  /// and absent for a matched one; selecting `mirror-trash` needs the
  /// delete right.
  ///
  /// With none of those four, the body is a settings-only re-save and
  /// needs a binding under it: the stored source, refs, identity and
  /// cover are kept and only [mode] (and [intervalHours], for a live
  /// binding) change.
  Future<PlaylistSource> setPlaylistSource(
    String pid, {
    required String mode,
    String? url,
    String? source,
    String? payload,
    List<PortableRef>? refs,
    int? intervalHours,
  });

  /// `DELETE /playlists/{pid}/source`: remove the binding. The
  /// playlist and its members stay as they are.
  Future<void> unbindPlaylistSource(String pid);

  /// `POST /playlists/{pid}/source/preview`: what a sync would do
  /// right now, computed without writing anything. With a source named
  /// it previews that prospective binding; with settings alone, the
  /// stored binding under them; with nothing, the stored binding as it
  /// stands.
  Future<PlaylistSyncPreview> previewPlaylistSync(
    String pid, {
    String? mode,
    String? url,
    String? source,
    String? payload,
    List<PortableRef>? refs,
    int? intervalHours,
  });

  /// `POST /playlists/{pid}/source/sync`: queue a sync run now,
  /// answering the tool task to follow. A run already in flight is
  /// answered with that task rather than a second one.
  Future<ToolTask> syncPlaylistSource(String pid);

  /// `GET /playlists/{pid}/nsp/report`: what exporting this smart
  /// playlist's rule as a Navidrome document would drop, without
  /// exporting it. Refuses only for a playlist with no rule.
  Future<NspReport> reportPlaylistNspExport(String pid);

  /// `POST /playlists/nsp/report`: what importing a Navidrome smart
  /// playlist [document] would drop, without importing it.
  Future<NspReport> checkNspImport(Map<String, Object?> document);

  /// `POST /playlists/nsp`: a smart playlist from [document]. [partial]
  /// drops what WaxDeck cannot read instead of refusing; [name] wins over
  /// the document's own.
  Future<Playlist> importNsp(
    Map<String, Object?> document, {
    bool partial = false,
    String? name,
  });

  /// `GET /playlists/{pid}/nsp`: the smart playlist's rule as a
  /// Navidrome document. [partial] drops what NSP cannot say instead of
  /// refusing; [ruleHash] (from the report) refuses a rule edited since.
  Future<Map<String, Object?>> exportPlaylistNsp(
    String pid, {
    bool partial = false,
    String? ruleHash,
  });
}
