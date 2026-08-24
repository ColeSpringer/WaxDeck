import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import '../settings/settings_registry.dart';

/// Everything the metadata editor renders for one item: the stored
/// metadata plus the field vocabulary for its media kind.
class MetadataEditorState {
  const MetadataEditorState({required this.metadata, required this.kindFields});

  final ItemMetadata metadata;
  final KindFields kindFields;

  FieldProvenance? provenanceFor(String field) =>
      metadata.provenance.where((p) => p.field == field).firstOrNull;

  bool isLocked(String field) => metadata.lockedFields.contains(field);
}

/// One item's metadata editor: loads item metadata and the vocabulary
/// together, and refetches after every mutation so lock state,
/// provenance, and values stay authoritative.
class MetadataController extends AsyncNotifier<MetadataEditorState> {
  MetadataController(this.pid);

  final String pid;

  @override
  Future<MetadataEditorState> build() async {
    final repository = ref.watch(repositoryProvider);
    final metadataFuture = repository.getItemMetadata(pid);
    final fields = await repository.getMetadataFields();
    final metadata = await metadataFuture;
    final kind =
        fields.kinds.where((k) => k.kind == metadata.mediaType).firstOrNull ??
        KindFields(kind: metadata.mediaType, fields: const []);
    return MetadataEditorState(metadata: metadata, kindFields: kind);
  }

  /// Saves the changed scalar fields only, returning the edit outcome
  /// (write-back failures ride the result, they are not errors).
  Future<MetadataEditResult> saveFields(
    Map<String, String> changed, {
    required bool writeBack,
    required bool lock,
    required bool force,
  }) async {
    final result = await ref
        .read(repositoryProvider)
        .editItemMetadata(
          pid,
          fields: changed,
          writeBack: writeBack,
          lock: lock,
          force: force,
        );
    await _refresh();
    return result;
  }

  Future<void> setLock(String field, {required bool locked}) async {
    await ref
        .read(repositoryProvider)
        .setItemLocks(pid, fields: [field], locked: locked);
    await _refresh();
  }

  Future<MetadataEditResult> saveCredits(
    String role,
    List<String> names,
  ) async {
    final result = await ref
        .read(repositoryProvider)
        .setItemCredits(pid, role: role, names: names);
    await _refresh();
    return result;
  }

  Future<void> setTag(String key, List<String> values) async {
    await ref.read(repositoryProvider).setItemTag(pid, key, values: values);
    await _refresh();
  }

  Future<void> removeTag(String key) async {
    await ref.read(repositoryProvider).clearItemTag(pid, key);
    await _refresh();
  }

  Future<MetadataEditResult> saveLyrics(String lrc) async {
    final result = await ref
        .read(repositoryProvider)
        .setItemLyrics(pid, lrc: lrc);
    await _refresh();
    return result;
  }

  Future<void> clearLyrics() async {
    await ref.read(repositoryProvider).clearItemLyrics(pid);
    await _refresh();
  }

  Future<void> setUnofficial({required bool unofficial}) async {
    await ref
        .read(repositoryProvider)
        .setReleaseStatus(pid, unofficial: unofficial);
    await _refresh();
  }

  /// Reopens identification; returns the review entry id to watch.
  Future<String> rematch() => ref.read(repositoryProvider).rematchItem(pid);

  /// Fetches the wanted artifacts now, then refetches (a new cover or
  /// genre set changes what the editor shows).
  Future<EnrichItemResult> enrich(List<String> want) async {
    final result = await ref
        .read(repositoryProvider)
        .enrichItem(pid, want: want);
    await _refresh();
    return result;
  }

  Future<void> _refresh() async {
    if (!ref.mounted) return;
    ref.invalidateSelf();
    await future;
  }
}

final metadataControllerProvider =
    AsyncNotifierProvider.family<
      MetadataController,
      MetadataEditorState,
      String
    >(MetadataController.new);

/// Whether this account may edit one item's metadata.
///
/// The server's own answer rather than a role the client re-reads:
/// administrators may, and so does whoever's upload brought the item in,
/// which is a fact about the item that nothing on the client can derive.
///
/// The permissions read, not [metadataControllerProvider], which
/// fetches the full editor document beside it - a door only needs the
/// permission. Auto-disposing and per-pid, so the player asks once
/// about the thing it is playing. Listings still do not ask per row -
/// their menus are gated on the roles the session already knows and the
/// editor refuses the rest on arrival.
final mayCurateItemProvider = FutureProvider.autoDispose.family<bool, String>(
  (ref, pid) async {
    // Half the server's own predicate is `uc.Admin`, and that half a
    // client already knows: short-circuiting it spares the fetch
    // entirely for the accounts that open this editor most. Being
    // wrong about it costs nothing - the editor refetches on arrival
    // and refuses there, which is what it is for.
    if (ref.watch(isAdminProvider)) return true;
    final permissions = await ref
        .watch(repositoryProvider)
        .getItemPermissions(pid);
    return permissions.mayCurate;
  },
  // Failure is final here: whatever the reason - offline, a server
  // too old for the route, a failed lookup - the callers read the
  // error as "withhold the door", so ten retried fetches per played
  // track would buy nothing the first answer did not.
  retry: (_, _) => null,
);
