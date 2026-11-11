/// Members derived from a model's fields, kept off the model classes so each
/// class stays plain data.
library;

import 'models.dart';

extension WaxDeckUserX on WaxDeckUser {
  /// Name to show in UI chrome.
  String get label => displayName ?? username;
}

extension DeviceSessionX on DeviceSession {
  /// Name to show in UI chrome.
  String get label => deviceName ?? client ?? kind.wireName;
}

extension PrefsX on Prefs {
  /// The stored order for one dimension, or null when there is none and
  /// when this build does not know the one stored.
  FacetSort? browseSortFor(String dimension) =>
      FacetSort.fromWire(browseSorts?[dimension]);

  /// Copy with individual fields replaced. Passing null keeps the current
  /// value; clearing a stored field is not something the UI needs yet.
  Prefs copyWith({
    String? timezone,
    String? locale,
    ThemePref? theme,
    bool? sharedStatsOptOut,
    List<String>? radioFavorites,
    List<String>? radioScrobbleMutedStations,
    List<String>? pinned,
    double? crossfadeSeconds,
    bool? replayGain,
    bool? radioScrobbleOptOut,
    bool? identifyOptOut,
    bool? browseShowUnknown,
    Map<String, String>? browseSorts,
    bool? autoplay,
  }) {
    return Prefs(
      timezone: timezone ?? this.timezone,
      locale: locale ?? this.locale,
      theme: theme ?? this.theme,
      sharedStatsOptOut: sharedStatsOptOut ?? this.sharedStatsOptOut,
      radioFavorites: radioFavorites ?? this.radioFavorites,
      radioScrobbleMutedStations:
          radioScrobbleMutedStations ?? this.radioScrobbleMutedStations,
      pinned: pinned ?? this.pinned,
      crossfadeSeconds: crossfadeSeconds ?? this.crossfadeSeconds,
      replayGain: replayGain ?? this.replayGain,
      radioScrobbleOptOut: radioScrobbleOptOut ?? this.radioScrobbleOptOut,
      identifyOptOut: identifyOptOut ?? this.identifyOptOut,
      browseShowUnknown: browseShowUnknown ?? this.browseShowUnknown,
      browseSorts: browseSorts ?? this.browseSorts,
      autoplay: autoplay ?? this.autoplay,
    );
  }
}

extension ItemSummaryX on ItemSummary {
  /// What a list orders [title] by: the catalog's [sortKey], or the
  /// lowercase title for a row that carries none.
  String get titleOrderKey {
    final key = sortKey;
    return key != null && key.isNotEmpty ? key : title.toLowerCase();
  }

  /// What a list orders [artist] by: the catalog's [artistSortKey], or for
  /// a row that carries none the sort spelling where one is stated, else
  /// the name as drawn, lowercase; empty with neither.
  String get artistOrderKey {
    final key = artistSortKey;
    if (key != null && key.isNotEmpty) return key;
    final spelling = artistSort;
    if (spelling != null && spelling.isNotEmpty) return spelling.toLowerCase();
    return (artist ?? '').toLowerCase();
  }
}

extension ItemFileX on ItemFile {
  bool get isCopy => role == 'alternate';
}

extension AlbumDetailX on AlbumDetail {
  /// Whether the release carries any identity at all. Most do not, and a
  /// header with five blank labels is worse than no block.
  bool get hasIdentity =>
      (barcode ?? label ?? catalogNumber ?? media ?? country) != null;
}

extension EpisodeFilterX on EpisodeFilter {
  /// True when the filter admits every episode, which is what an unset
  /// one does.
  bool get isEmpty => include.isEmpty && exclude.isEmpty;
}

extension SkipMapX on SkipMap {
  bool get ready => state == 'ready';
}

extension WaveformX on Waveform {
  bool get ready => state == 'ready';

  /// Whether asking again could ever answer differently.
  bool get pending => state == 'pending';
}

extension LyricsX on Lyrics {
  /// Whether these words can follow playback.
  bool get isSynced => synced.isNotEmpty;
}

extension OpmlImportOutcomeX on OpmlImportOutcome {
  bool get failed => error != null || pid == null;
}

extension ServerNotificationX on ServerNotification {
  bool get read => readAt != null;
}

extension PlaybackSessionHistoryEntryX on PlaybackSessionHistoryEntry {
  PlaybackSessionEntry? get currentEntry =>
      index >= 0 && index < entries.length ? entries[index] : null;
}

extension LibraryMatchingX on LibraryMatching {
  /// Field-wise replacement, the shape every setter goes through so a
  /// third field cannot be forgotten by one of them: an omission on a
  /// full-replace PUT silently resets that field on the server.
  LibraryMatching copyWith({String? mode, bool? singlesAutoApply}) =>
      LibraryMatching(
        mode: mode ?? this.mode,
        singlesAutoApply: singlesAutoApply ?? this.singlesAutoApply,
      );
}

extension FieldProvenanceX on FieldProvenance {
  /// Whether this row pins the item's kind (music or book): an upload
  /// imported under a media type its file would not get on its own takes
  /// it, so it says nothing about who edited what.
  bool get isKind => field == 'kind';
}

extension ArtRoleInfoX on ArtRoleInfo {
  /// The pin this slot's toggle draws and writes: its own where the
  /// server reports one, else the effective lock, which is all a server
  /// predating the field can say.
  bool get ownPin => roleLocked ?? locked;

  /// Held by the whole-artwork pin alone: releasing this slot's own pin
  /// would open nothing, so the control captions the state rather than
  /// offering a toggle that does not move. False where the server does
  /// not report the role's own pin, since then the two cannot be told
  /// apart.
  bool get heldByCoverPin => locked && roleLocked == false;

  /// A pin with nothing behind it: the cover was cleared and the pin
  /// left standing, which says "do not refill this" rather than "no
  /// cover yet". It is the one artwork state nothing else surfaces.
  bool get pinnedEmpty => locked && (format ?? '').isEmpty;
}

extension MetadataCommitResultX on MetadataCommitResult {
  /// The refusal that stopped the commit, or null when every part
  /// committed.
  WaxDeckApiException? get refusal => parts
      .where((p) => p.status == MetadataCommitStatus.refused)
      .map((p) => p.refusal)
      .whereType<WaxDeckApiException>()
      .firstOrNull;
}

extension EnrichPreviewX on EnrichPreview {
  bool get isEmpty => fields.isEmpty && cover == null;

  /// The half to pass back on apply.
  EnrichProposal get proposal => EnrichProposal(fields: fields, cover: cover);
}

extension GenreNodeX on GenreNode {
  GenreNode copyWith({
    String? name,
    String? parent,
    bool clearParent = false,
    List<String>? aliases,
  }) => GenreNode(
    name: name ?? this.name,
    parent: clearParent ? null : (parent ?? this.parent),
    aliases: aliases ?? this.aliases,
  );
}

extension GenreTreeX on GenreTree {
  bool get isDefault => source == 'default';
}

extension OrganizeBatchX on OrganizeBatch {
  bool get isUndo => kind == 'organize-undo';
}

extension ToolTaskX on ToolTask {
  /// Whether the task has ended: done, failed, or parked. A finished task
  /// is dismissed and swept like any other, and a parked one holds its
  /// book or rip from another merge or split until it is.
  bool get finished =>
      state == 'done' || state == 'failed' || state == 'parked';
}

extension SignupResultX on SignupResult {
  bool get pending => state == 'pending';
}

extension InviteX on Invite {
  bool get expired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now().toUtc());
}

extension AdminSettingsX on AdminSettings {
  AdminSettings copyWith({
    bool? signupEnabled,
    bool? readOnly,
    bool? sonicAnalysis,
    int? backupKeepCount,
    int? backupKeepBytes,
    int? trashRetentionDays,
    int? taskRetentionDays,
    bool? radioExternalArt,
  }) => AdminSettings(
    signupEnabled: signupEnabled ?? this.signupEnabled,
    readOnly: readOnly ?? this.readOnly,
    sonicAnalysis: sonicAnalysis ?? this.sonicAnalysis,
    backupKeepCount: backupKeepCount ?? this.backupKeepCount,
    backupKeepBytes: backupKeepBytes ?? this.backupKeepBytes,
    trashRetentionDays: trashRetentionDays ?? this.trashRetentionDays,
    taskRetentionDays: taskRetentionDays ?? this.taskRetentionDays,
    radioExternalArt: radioExternalArt ?? this.radioExternalArt,
  );
}

extension JobX on Job {
  /// Whether the job has ended, one way or another. A state this build
  /// does not know reads as unfinished, as the contract has it.
  bool get ended => switch (state) {
    'done' || 'failed' || 'crashed' || 'canceled' => true,
    _ => false,
  };
}

extension DeleteItemsResultX on DeleteItemsResult {
  int get totalFiles => entries.fold(0, (sum, e) => sum + e.files);

  int get totalBytes => entries.fold(0, (sum, e) => sum + e.bytes);
}

extension NspReportX on NspReport {
  /// Everything worth showing, in one list: the losses that refuse and
  /// the losses that do not. A person deciding whether to accept the
  /// loss is not helped by the distinction, only by the list.
  List<NspGap> get all => <NspGap>[...gaps, ...notes];

  bool get isLossless => gaps.isEmpty && notes.isEmpty;
}
