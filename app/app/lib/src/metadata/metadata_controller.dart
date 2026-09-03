import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import '../settings/settings_registry.dart';
import 'metadata_form.dart';

/// What one unified save came back with: the write-back failures and
/// warnings the committed parts reported, and the refusal that stopped
/// the rest, when one did. Not an exception, because the failures are
/// worth showing whether or not everything landed.
class MetadataSaveOutcome {
  const MetadataSaveOutcome({
    this.writeBackFailures = const [],
    this.warnings = const [],
    this.refusal,
  });

  final List<WriteBackFailure> writeBackFailures;
  final List<String> warnings;

  /// The refusal that aborted the save partway, or null when every
  /// staged change committed.
  final WaxDeckApiException? refusal;
}

/// Whether this server has the compound save. It starts true, and goes
/// false for good the first time the route answers 404.
///
/// Keyed to the repository, which is rebuilt whenever the server
/// address moves, so a different server is asked again rather than
/// inheriting the last one's answer. One flag rather than one per item:
/// the route either exists on a server or it does not.
class CompoundSaveSupport extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(repositoryProvider);
    return true;
  }

  void unsupported() => state = false;
}

final compoundSaveProvider = NotifierProvider<CompoundSaveSupport, bool>(
  CompoundSaveSupport.new,
);

/// Everything the metadata editor renders for one item: the stored
/// metadata plus the field vocabulary for its media kind.
class MetadataEditorState {
  const MetadataEditorState({
    required this.metadata,
    required this.kindFields,
    this.reservedTagKeys = const {},
  });

  final ItemMetadata metadata;
  final KindFields kindFields;

  /// The custom-tag keys the catalog owns through a field of its own,
  /// so the tag editor refuses one before the round trip rather than
  /// after it. Canonical (uppercase) as the server states them.
  final Set<String> reservedTagKeys;

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
    // The eager read must not be left unheard while the vocabulary is
    // awaited: a server that fails both would otherwise surface the
    // metadata read's rejection as an uncaught async error before the
    // await below ever attaches.
    metadataFuture.ignore();
    final fields = await repository.getMetadataFields();
    final metadata = await metadataFuture;
    final kind =
        fields.kinds.where((k) => k.kind == metadata.mediaType).firstOrNull ??
        KindFields(kind: metadata.mediaType, fields: const []);
    return MetadataEditorState(
      metadata: metadata,
      kindFields: kind,
      reservedTagKeys: fields.reservedTagKeys.toSet(),
    );
  }

  /// Commits everything the draft staged, in one pass: the scalar
  /// fields, then credits, lyrics, chapters, tags, and the release
  /// status. The write switches ride every call that takes them.
  ///
  /// One request where the server has the compound endpoint, the same
  /// parts as sequential calls where it does not. Sequentially that is
  /// N round trips, which on a phone reaching a home server through a
  /// reverse proxy is the felt cost of a single Save, and N
  /// partial-failure windows on a flaky link. Both paths run the same
  /// parts in the same order and report the same outcome, which is what
  /// lets either stand in for the other.
  ///
  /// Never throws for a refused write. The refusal rides the outcome
  /// beside whatever the calls before it reported, because the
  /// write-back failures a committed edit accumulated are exactly what
  /// a thrown exception would discard - and the banner they feed is the
  /// reason the field exists. One refetch at the end whatever happened,
  /// so the parts that landed are adopted and only the rest stays
  /// dirty.
  Future<MetadataSaveOutcome> saveAll(
    MetadataChanges changes, {
    required bool writeBack,
    required bool lock,
    required bool force,
  }) async {
    if (ref.read(compoundSaveProvider)) {
      final outcome = await _commitAll(
        changes,
        writeBack: writeBack,
        lock: lock,
        force: force,
      );
      if (outcome != null) return outcome;
    }
    return _saveSequentially(
      changes,
      writeBack: writeBack,
      lock: lock,
      force: force,
    );
  }

  /// The compound save, or null when this server has no such route and
  /// the sequential path has to run instead.
  ///
  /// The sniff is a 404 whose body carried no `Error` envelope. The
  /// router answers an unmatched path with `404 page not found` as
  /// plain text, which the transport reports as the client-minted
  /// `transport` code, and so does a proxy's own 404 page; a genuine
  /// item-404 carries `not-found` and is a refusal of this save rather
  /// than a verdict on the server. Keying on the status code alone
  /// would let one bad pid put the whole session on the slow path.
  Future<MetadataSaveOutcome?> _commitAll(
    MetadataChanges changes, {
    required bool writeBack,
    required bool lock,
    required bool force,
  }) async {
    final repository = ref.read(repositoryProvider);
    MetadataCommitResult result;
    try {
      result = await repository.commitItemMetadata(
        pid,
        MetadataCommit(
          fields: changes.fields.isEmpty ? null : changes.fields,
          credits: <CommitCredits>[
            for (final entry in changes.credits.entries)
              CommitCredits(role: entry.key, names: entry.value),
          ],
          // Timed text is LRC; plain text must say so, because the LRC
          // parser drops unstamped lines and refuses the empty result.
          lyrics: switch (changes.lyrics) {
            final text? when metadataLyricsTimed(text) => CommitLyrics(
              lrc: text,
            ),
            final text? => CommitLyrics(plain: text),
            null => null,
          },
          clearLyrics: changes.clearLyrics,
          chapters: changes.chapters,
          tagSets: changes.tagSets,
          tagRemoves: changes.tagRemoves,
          unofficial: changes.unofficial,
          writeBack: writeBack,
          lock: lock,
          force: force,
        ),
      );
    } on WaxDeckApiException catch (e) {
      if (e.statusCode == 404 && e.code != 'not-found') {
        ref.read(compoundSaveProvider.notifier).unsupported();
        return null;
      }
      // Anything else refused the whole request, which committed
      // nothing, so there is nothing to report beside it.
      await _refreshQuietly();
      return MetadataSaveOutcome(refusal: e);
    }
    await _refreshQuietly();
    // The per-part list rides the wire for a banner richer than this
    // one; what the banner reads today is the shape the sequential path
    // produces, so the two are interchangeable.
    return MetadataSaveOutcome(
      writeBackFailures: result.writeBackFailures,
      warnings: result.warnings,
      refusal: result.refusal,
    );
  }

  /// One call per staged part, kept for servers without the compound
  /// endpoint. It is also the reference the compound path is measured
  /// against: same parts, same order, same outcome.
  Future<MetadataSaveOutcome> _saveSequentially(
    MetadataChanges changes, {
    required bool writeBack,
    required bool lock,
    required bool force,
  }) async {
    final repository = ref.read(repositoryProvider);
    final failures = <WriteBackFailure>[];
    final seen = <String>{};
    final warnings = <String>[];
    WaxDeckApiException? refusal;
    void collect(MetadataEditResult result) {
      // Deduplicated: several write paths can report the same file for
      // the same reason, and each line is for a person to read once.
      for (final failure in result.writeBackFailures) {
        if (seen.add('${failure.filePid} ${failure.path} ${failure.reason}')) {
          failures.add(failure);
        }
      }
      warnings.addAll(result.warnings);
    }

    try {
      if (changes.fields.isNotEmpty) {
        collect(
          await repository.editItemMetadata(
            pid,
            fields: changes.fields,
            writeBack: writeBack,
            lock: lock,
            force: force,
          ),
        );
      }
      for (final entry in changes.credits.entries) {
        collect(
          await repository.setItemCredits(
            pid,
            role: entry.key,
            names: entry.value,
            writeBack: writeBack,
            lock: lock,
            force: force,
          ),
        );
      }
      if (changes.lyrics case final text?) {
        // Timed text is LRC; plain text must say so, because the LRC
        // parser drops unstamped lines and refuses the empty result.
        final timed = metadataLyricsTimed(text);
        collect(
          await repository.setItemLyrics(
            pid,
            lrc: timed ? text : null,
            plain: timed ? null : text,
            writeBack: writeBack,
            lock: lock,
            force: force,
          ),
        );
      } else if (changes.clearLyrics) {
        await repository.clearItemLyrics(pid);
      }
      if (changes.chapters case final chapters?) {
        collect(
          await repository.setBookChapters(
            pid,
            chapters: chapters,
            lock: lock,
            force: force,
          ),
        );
      }
      // Sorted, which is the order the compound endpoint applies them
      // in: a JSON object carries none of its own, so the server has to
      // choose one, and the two paths only stand in for each other if
      // a refusal partway leaves the same parts committed. Dart's map
      // order is insertion order, which is a different answer.
      for (final key in changes.tagSets.keys.toList()..sort()) {
        await repository.setItemTag(
          pid,
          key,
          values: changes.tagSets[key]!,
          lock: lock,
          force: force,
        );
      }
      for (final key in changes.tagRemoves) {
        await repository.clearItemTag(pid, key);
      }
      if (changes.unofficial case final unofficial?) {
        await repository.setReleaseStatus(pid, unofficial: unofficial);
      }
    } on WaxDeckApiException catch (e) {
      refusal = e;
    } finally {
      await _refreshQuietly();
    }
    return MetadataSaveOutcome(
      writeBackFailures: failures,
      warnings: warnings,
      refusal: refusal,
    );
  }

  /// Refetch after a save, whatever happened, so the parts that landed
  /// are adopted and only the rest stays dirty. A refetch failure is
  /// swallowed: the provider holds the error, and replacing the refusal
  /// (or the failures) with a fetch problem would hide the answer that
  /// matters.
  Future<void> _refreshQuietly() async {
    try {
      await _refresh();
    } on Exception {
      // Deliberate; see above.
    }
  }

  Future<void> setLock(String field, {required bool locked}) async {
    await ref
        .read(repositoryProvider)
        .setItemLocks(pid, fields: [field], locked: locked);
    await _refresh();
  }

  /// Reopens identification; returns the review entry id to watch.
  Future<String> rematch() => ref.read(repositoryProvider).rematchItem(pid);

  /// What a fetch would change, written nowhere: the sheet the editor
  /// shows before anything lands. No refresh - nothing changed.
  Future<EnrichPreview> previewEnrich(List<String> want) =>
      ref.read(repositoryProvider).previewEnrichItem(pid, want: want);

  /// Fetches the wanted artifacts now - or, with a [proposal], commits
  /// exactly what the preview answered - then refetches (a new cover
  /// or genre set changes what the editor shows).
  Future<EnrichItemResult> enrich(
    List<String> want, {
    EnrichProposal? proposal,
  }) async {
    final result = await ref
        .read(repositoryProvider)
        .enrichItem(pid, want: want, proposal: proposal);
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
    >(
      MetadataController.new,
      // Failure is final: the error state's own Retry button is the
      // retry, and the automatic backoff would leave `.future`
      // unsettled for tens of seconds - which is a save bar stuck busy
      // with no spinner and no explanation.
      retry: (_, _) => null,
    );

/// The canonical genre vocabulary, for the editor's genre picker; empty
/// when this session cannot read one.
///
/// The tree read is administrators-only, so the fetch is not even tried
/// for anyone else - their picker takes genres as typed, which is what
/// every session may store anyway. Failure is final for the same reason
/// [mayCurateItemProvider]'s is: whatever the cause, the caller reads
/// the error as "no vocabulary", and retrying buys nothing the first
/// answer did not.
final canonicalGenresProvider = FutureProvider.autoDispose<List<GenreNode>>((
  ref,
) async {
  if (!ref.watch(isAdminProvider)) return const [];
  final tree = await ref.watch(repositoryProvider).getGenreTree();
  return tree.genres;
}, retry: (_, _) => null);

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
