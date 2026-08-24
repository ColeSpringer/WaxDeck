import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/art_source_label.dart';
import '../l10n/l10n.dart';
import '../music/music_controllers.dart';
import '../shell/forbidden_page.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'artwork_manager.dart';
import 'metadata_controller.dart';

/// What one editable field is called in the reader's language.
///
/// The vocabulary arrives from the server as wire keys - `album_artist`,
/// `track_no` - which were only ever an accessible name until the field
/// began drawing its label. A lookup rather than an enum because the
/// server owns the list, and the key itself is the fallback: a field a
/// later server adds draws its own name rather than nothing, and
/// translating it is one line here.
String metadataFieldLabel(AppLocalizations l10n, String name) => switch (name) {
  'title' => l10n.metadataFieldTitle,
  'artist' => l10n.metadataFieldArtist,
  'album_artist' => l10n.metadataFieldAlbumArtist,
  'album' => l10n.metadataFieldAlbum,
  'composer' => l10n.metadataFieldComposer,
  'composer_sort' => l10n.metadataFieldComposerSort,
  'comment' => l10n.metadataFieldComment,
  'genre' => l10n.metadataFieldGenre,
  'year' => l10n.metadataFieldYear,
  'track_no' => l10n.metadataFieldTrackNo,
  'disc_no' => l10n.metadataFieldDiscNo,
  'isrc' => l10n.metadataFieldIsrc,
  'mbid' => l10n.metadataFieldMbid,
  'compilation' => l10n.metadataFieldCompilation,
  'author' => l10n.metadataFieldAuthor,
  'author_sort' => l10n.metadataFieldAuthorSort,
  'narrator' => l10n.metadataFieldNarrator,
  'series' => l10n.metadataFieldSeries,
  'subtitle' => l10n.metadataFieldSubtitle,
  'asin' => l10n.metadataFieldAsin,
  'isbn' => l10n.metadataFieldIsbn,
  'publisher' => l10n.metadataFieldPublisher,
  'edition' => l10n.metadataFieldEdition,
  'description' => l10n.metadataFieldDescription,
  'pinned' => l10n.metadataFieldPinned,
  'season' => l10n.metadataFieldSeason,
  'episode_no' => l10n.metadataFieldEpisodeNo,
  'episode_type' => l10n.metadataFieldEpisodeType,
  'explicit' => l10n.metadataFieldExplicit,
  'link' => l10n.metadataFieldLink,
  _ => name,
};

/// The per-item metadata editor, deep-linkable at `/metadata/<pid>`.
/// Always pushed: a review row, a book, and the lyrics view all open it,
/// so it has three ancestries and a location may declare one.
class MetadataScreen extends ConsumerStatefulWidget {
  const MetadataScreen({super.key, required this.pid});

  final String pid;

  @override
  ConsumerState<MetadataScreen> createState() => _MetadataScreenState();
}

class _MetadataScreenState extends ConsumerState<MetadataScreen> {
  final _fieldControllers = <String, TextEditingController>{};
  final _lyricsController = TextEditingController();
  final _creditNamesController = TextEditingController();
  final _tagKeyController = TextEditingController();
  final _tagValuesController = TextEditingController();
  String? _creditRole;
  var _lyricsSeeded = false;

  var _writeBack = false;
  var _lock = true;
  var _force = false;
  var _busy = false;

  /// Write-back failures from the last save, rendered as a warning
  /// list; a partial tag write is not an error.
  List<WriteBackFailure> _writeBackFailures = const [];

  @override
  void dispose() {
    for (final controller in _fieldControllers.values) {
      controller.dispose();
    }
    _lyricsController.dispose();
    _creditNamesController.dispose();
    _tagKeyController.dispose();
    _tagValuesController.dispose();
    super.dispose();
  }

  /// What each field's controller was last seeded with from the server.
  /// A controller still holding exactly this has not been typed in
  /// since, which is what makes it safe to adopt a fresh value into.
  final _seeded = <String, String>{};

  TextEditingController _controllerFor(String field, String initial) {
    return _fieldControllers.putIfAbsent(field, () {
      _seeded[field] = initial;
      final controller = TextEditingController(text: initial);
      // Recompute dirtiness (and the Save button) as the user types.
      controller.addListener(() => setState(() {}));
      return controller;
    });
  }

  /// Takes server-side changes into the fields nobody is editing.
  /// Without it a fetched title is invisible and reads as a local edit,
  /// so Save offers to write the stale text back over it.
  void _adoptStored(MetadataEditorState state) {
    for (final field in state.kindFields.fields) {
      final controller = _fieldControllers[field.name];
      if (controller == null) continue;
      final stored = state.metadata.fields[field.name] ?? '';
      // Already in agreement - the usual case after a save, which
      // echoes back what was written. Re-seed so the next genuine
      // change is still recognised as one.
      if (controller.text == stored) {
        _seeded[field.name] = stored;
        continue;
      }
      // Typed in since it was seeded: that edit is the user's and
      // outranks a refetch.
      if (controller.text != _seeded[field.name]) continue;
      _seeded[field.name] = stored;
      controller.text = stored;
    }
  }

  Map<String, String> _changedFields(MetadataEditorState state) {
    final changed = <String, String>{};
    for (final field in state.kindFields.fields) {
      final controller = _fieldControllers[field.name];
      if (controller == null) continue;
      final stored = state.metadata.fields[field.name] ?? '';
      if (controller.text != stored) changed[field.name] = controller.text;
    }
    return changed;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      await action();
    } on WaxDeckApiException catch (e) {
      // The server's own sentence, kept: it names which field refused,
      // which is the whole of what an administrator needs when three
      // were edited and one is locked. The client adds the half the
      // server cannot know - the switch on this page that overrides it.
      messenger.show(
        e.code == 'field-locked'
            ? '${e.message}. ${l10n.metadataFieldLockedHint}'
            : explainError(l10n, e),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showResult(MetadataEditResult result) {
    if (!mounted) return;
    setState(() => _writeBackFailures = result.writeBackFailures);
    if (result.warnings.isNotEmpty) {
      ref
          .read(shellMessengerProvider.notifier)
          .show(result.warnings.join('\n'));
    }
  }

  Future<void> _save(MetadataEditorState state) => _run(() async {
    final changed = _changedFields(state);
    if (changed.isEmpty) return;
    final result = await ref
        .read(metadataControllerProvider(widget.pid).notifier)
        .saveFields(changed, writeBack: _writeBack, lock: _lock, force: _force);
    _showResult(result);
  });

  Future<void> _rematch() => _run(() async {
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    // Hoisted: the message outlives this screen, and a closure over its
    // context throws once the editor is popped.
    final router = GoRouter.maybeOf(context);
    final entryId = await ref
        .read(metadataControllerProvider(widget.pid).notifier)
        .rematch();
    messenger.show(
      l10n.metadataQueuedForIdentification,
      actionLabel: router == null ? null : l10n.commonOpenReview,
      actionSemanticsId: SemanticsIds.metadataOpenReview,
      onAction: router == null
          ? null
          : () => router.push<void>(WaxRoute.reviewEntry(entryId)),
    );
  });

  static List<String> _wantsFor(MediaType mediaType) => switch (mediaType) {
    MediaType.music => const ['cover', 'genres'],
    MediaType.audiobook => const ['cover', 'book'],
    MediaType.podcast => const ['cover'],
  };

  Future<void> _enrich(MetadataEditorState state) => _run(() async {
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    final result = await ref
        .read(metadataControllerProvider(widget.pid).notifier)
        .enrich(_wantsFor(state.metadata.mediaType));
    final parts = <String>[
      if (result.applied.isNotEmpty)
        l10n.metadataEnrichApplied(result.applied.join(', ')),
      if (result.skipped.isNotEmpty)
        l10n.metadataEnrichSkipped(result.skipped.join(', ')),
    ];
    messenger.show(
      parts.isEmpty ? l10n.metadataNothingToFetch : parts.join('. '),
    );
  });

  @override
  Widget build(BuildContext context) {
    final sizeClass = WaxSizeClass.of(context);
    final editor = ref.watch(metadataControllerProvider(widget.pid));
    ref.listen(metadataControllerProvider(widget.pid), (previous, next) {
      final value = next.value;
      if (value != null) _adoptStored(value);
    });
    // On the screen, not only on the doors that open it. The album
    // editor refuses for the same reason - this location is shareable
    // and the web build puts it in the path - but it refuses before it
    // loads, because being an administrator is something the session
    // already knows. Here the answer is a property of the item and
    // arrives with the read, so the refusal waits for it: the account
    // whose upload brought the track in may curate it, and nothing on
    // the client can work that out on its own.
    //
    // On an explicit no, never on a silence. A server too old to carry
    // the field, or one whose ownership lookup failed, says nothing -
    // and refusing on that would hand an administrator a "not yours"
    // page for an item that server would save. Unanswered, the editor
    // opens exactly as it did before this field existed and the save is
    // what refuses.
    if (editor.value case final state? when state.metadata.mayCurate == false) {
      return ForbiddenPage(
        pageTitle: context.l10n.metadataTitle,
        heading: context.l10n.metadataForbiddenTitle,
        message: context.l10n.metadataForbiddenMessage,
        glyph: WaxIcons.edit,
        semanticsId: SemanticsIds.metadataForbidden,
      );
    }
    return WaxScaffold(
      title: context.l10n.metadataTitle,
      largeTitle: false,
      semanticsId: SemanticsIds.metadataEditor,
      onBack: () => context.leave(),
      body: Padding(
        padding: sizeClass.gutter.add(
          const EdgeInsets.only(bottom: WaxSpace.s32),
        ),
        child: switch (editor) {
          AsyncData(:final value) => _body(context, value, sizeClass),
          AsyncError(:final error) => ErrorState(
            title: context.l10n.metadataLoadError,
            message: context.explain(error),
            onRetry: () =>
                ref.invalidate(metadataControllerProvider(widget.pid)),
          ),
          _ => const SkeletonShapes(shape: SkeletonShape.detail),
        },
      ),
    );
  }

  Widget _body(
    BuildContext context,
    MetadataEditorState state,
    WaxSizeClass sizeClass,
  ) {
    if (!_lyricsSeeded) {
      _lyricsSeeded = true;
      _lyricsController.text = state.metadata.lyrics?.lrc ?? '';
    }
    final left = <Widget>[
      _fieldsSection(context, state),
      _creditsSection(context, state),
      _tagsSection(context, state),
    ];
    final right = <Widget>[
      ArtworkManager(
        pid: widget.pid,
        title: state.metadata.fields['title'] ?? widget.pid,
        hasArtwork: state.metadata.hasArtwork,
      ),
      const SizedBox(height: WaxSpace.s32),
      _lyricsSection(context),
      const SizedBox(height: WaxSpace.s32),
      _releaseSection(context, state),
      const SizedBox(height: WaxSpace.s32),
      _actionsSection(context, state),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Header(state: state),
        const SizedBox(height: WaxSpace.s24),
        if (sizeClass.hasSidebar)
          // No IntrinsicHeight: each column takes the height it needs
          // and the page scrolls. The form is the wider half because
          // the fields are what somebody came to change.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: left,
                ),
              ),
              const SizedBox(width: WaxSpace.s32),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: right,
                ),
              ),
            ],
          )
        else ...<Widget>[
          ...left,
          const SizedBox(height: WaxSpace.s32),
          ...right,
        ],
      ],
    );
  }

  /// The item, its cover, and where its values came from in one line.
  Widget _fieldsSection(BuildContext context, MetadataEditorState state) {
    final changed = _changedFields(state);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: l10n.metadataFieldsTitle,
          overline: l10n.metadataFieldsOverline,
        ),
        if (_writeBackFailures.isNotEmpty) _writeBackWarning(context),
        for (final field in state.kindFields.fields) ...<Widget>[
          _FieldRow(
            field: field,
            controller: _controllerFor(
              field.name,
              state.metadata.fields[field.name] ?? '',
            ),
            locked: state.isLocked(field.name),
            provenance: state.provenanceFor(field.name),
            dirty: changed.containsKey(field.name),
            onToggleLock: () => _run(
              () => ref
                  .read(metadataControllerProvider(widget.pid).notifier)
                  .setLock(field.name, locked: !state.isLocked(field.name)),
            ),
          ),
          const SizedBox(height: WaxSpace.s12),
        ],
        _EntityDoors(metadata: state.metadata),
        const SizedBox(height: WaxSpace.s8),
        WaxSettingRow(
          title: l10n.metadataWriteBackTitle,
          help: l10n.metadataWriteBackHelp,
          control: WaxSwitch(
            label: l10n.metadataWriteBackTitle,
            value: _writeBack,
            semanticsId: SemanticsIds.metadataWriteback,
            onChanged: (v) => setState(() => _writeBack = v),
          ),
        ),
        WaxSettingRow(
          title: l10n.metadataLockTitle,
          help: l10n.metadataLockHelp,
          control: WaxSwitch(
            label: l10n.metadataLockTitle,
            value: _lock,
            semanticsId: SemanticsIds.metadataLock,
            onChanged: (v) => setState(() => _lock = v),
          ),
        ),
        WaxSettingRow(
          title: l10n.metadataForceTitle,
          help: l10n.metadataForceHelp,
          control: WaxSwitch(
            label: l10n.metadataForceTitle,
            value: _force,
            semanticsId: SemanticsIds.metadataForce,
            onChanged: (v) => setState(() => _force = v),
          ),
        ),
        const SizedBox(height: WaxSpace.s16),
        WaxButton(
          label: changed.isEmpty
              ? l10n.commonSave
              : l10n.metadataSaveChanges(changed.length),
          icon: WaxIcons.check,
          semanticsId: SemanticsIds.metadataSave,
          onPressed: changed.isEmpty || _busy ? null : () => _save(state),
        ),
        const SizedBox(height: WaxSpace.s32),
      ],
    );
  }

  /// What the server kept from a write-back. A partial tag write is not
  /// an error - the catalog holds the edit either way - so it stays on
  /// screen as a caution rather than passing as a message.
  Widget _writeBackWarning(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: WaxSpace.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          WaxBanner(
            message: l10n.metadataWriteBackWarning,
            tone: WaxBannerTone.caution,
            semanticsId: SemanticsIds.metadataWritebackWarning,
            onDismiss: () => setState(() => _writeBackFailures = const []),
          ),
          const SizedBox(height: WaxSpace.s8),
          // Which file and why is the content of the warning, so it
          // stays on screen rather than passing as a message.
          for (final failure in _writeBackFailures)
            Text(
              l10n.metadataWriteBackFailure(
                failure.path ?? failure.filePid,
                failure.reason,
              ),
              style: WaxType.monoData.copyWith(color: colors.textSecondary),
            ),
        ],
      ),
    );
  }

  Widget _creditsSection(BuildContext context, MetadataEditorState state) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final roles = state.kindFields.creditRoles;
    final role = _creditRole ?? (roles.isEmpty ? null : roles.first.name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: l10n.metadataCreditsTitle,
          overline: l10n.metadataCreditsOverline,
        ),
        for (final credit in state.metadata.credits)
          Padding(
            padding: const EdgeInsets.only(bottom: WaxSpace.s4),
            child: MonoDetailRow(
              label: credit.role,
              value: credit.names.join(', '),
            ),
          ),
        if (roles.isEmpty)
          Text(
            l10n.metadataNoCreditRoles,
            style: WaxType.bodySmall.copyWith(color: colors.textTertiary),
          )
        else ...<Widget>[
          const SizedBox(height: WaxSpace.s8),
          WaxChoice<String>(
            label: l10n.metadataCreditRole,
            value: role!,
            semanticsId: SemanticsIds.creditsRole,
            options: <String>[for (final r in roles) r.name],
            labelFor: (name) => name,
            onChanged: (v) => setState(() => _creditRole = v),
          ),
          const SizedBox(height: WaxSpace.s8),
          WaxTextField(
            label: l10n.metadataCreditNames,
            controller: _creditNamesController,
            semanticsId: SemanticsIds.creditsNames,
          ),
          const SizedBox(height: WaxSpace.s8),
          WaxButton(
            label: l10n.metadataSaveCredits,
            kind: WaxButtonKind.tonal,
            semanticsId: SemanticsIds.creditsSave,
            onPressed: _busy
                ? null
                : () => _run(() async {
                    final names = _creditNamesController.text
                        .split(',')
                        .map((n) => n.trim())
                        .where((n) => n.isNotEmpty)
                        .toList();
                    final result = await ref
                        .read(metadataControllerProvider(widget.pid).notifier)
                        .saveCredits(role, names);
                    _showResult(result);
                  }),
          ),
        ],
        const SizedBox(height: WaxSpace.s32),
      ],
    );
  }

  Widget _tagsSection(BuildContext context, MetadataEditorState state) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: l10n.metadataTagsTitle,
          overline: l10n.metadataTagsOverline,
        ),
        for (final tag in state.metadata.customTags)
          Padding(
            padding: const EdgeInsets.only(bottom: WaxSpace.s4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: MonoDetailRow(
                    label: tag.key,
                    value: tag.values.join(', '),
                  ),
                ),
                WaxIconButton(
                  glyph: WaxIcons.close,
                  label: l10n.metadataRemoveTag(tag.key),
                  size: 16,
                  semanticsId: SemanticsIds.tagRemove(tag.key),
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => ref
                              .read(
                                metadataControllerProvider(widget.pid).notifier,
                              )
                              .removeTag(tag.key),
                        ),
                ),
              ],
            ),
          ),
        const SizedBox(height: WaxSpace.s8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            SizedBox(
              width: 140,
              child: WaxTextField(
                label: l10n.metadataTagKey,
                controller: _tagKeyController,
                semanticsId: SemanticsIds.tagKey,
              ),
            ),
            const SizedBox(width: WaxSpace.s8),
            Expanded(
              child: WaxTextField(
                label: l10n.metadataTagValues,
                controller: _tagValuesController,
                semanticsId: SemanticsIds.tagValues,
              ),
            ),
          ],
        ),
        const SizedBox(height: WaxSpace.s8),
        WaxButton(
          label: l10n.metadataAddTag,
          kind: WaxButtonKind.tonal,
          icon: WaxIcons.add,
          semanticsId: SemanticsIds.tagAdd,
          onPressed: _busy
              ? null
              : () => _run(() async {
                  final key = _tagKeyController.text.trim();
                  if (key.isEmpty) return;
                  final values = _tagValuesController.text
                      .split(',')
                      .map((v) => v.trim())
                      .where((v) => v.isNotEmpty)
                      .toList();
                  await ref
                      .read(metadataControllerProvider(widget.pid).notifier)
                      .setTag(key, values);
                  _tagKeyController.clear();
                  _tagValuesController.clear();
                }),
        ),
        const SizedBox(height: WaxSpace.s32),
      ],
    );
  }

  Widget _lyricsSection(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: l10n.metadataLyricsTitle,
          overline: l10n.metadataLyricsOverline,
        ),
        WaxTextField(
          label: l10n.metadataLyricsLabel,
          hint: l10n.metadataLyricsHint,
          controller: _lyricsController,
          maxLines: 8,
          semanticsId: SemanticsIds.lyricsField,
        ),
        const SizedBox(height: WaxSpace.s8),
        _LyricsPreview(controller: _lyricsController),
        const SizedBox(height: WaxSpace.s8),
        Row(
          children: <Widget>[
            WaxButton(
              label: l10n.metadataSaveLyrics,
              kind: WaxButtonKind.tonal,
              semanticsId: SemanticsIds.lyricsSave,
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      final result = await ref
                          .read(metadataControllerProvider(widget.pid).notifier)
                          .saveLyrics(_lyricsController.text);
                      _showResult(result);
                    }),
            ),
            const SizedBox(width: WaxSpace.s8),
            WaxButton(
              label: l10n.metadataClearLyrics,
              kind: WaxButtonKind.text,
              semanticsId: SemanticsIds.lyricsClear,
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      await ref
                          .read(metadataControllerProvider(widget.pid).notifier)
                          .clearLyrics();
                      _lyricsController.clear();
                    }),
            ),
          ],
        ),
      ],
    );
  }

  Widget _releaseSection(BuildContext context, MetadataEditorState state) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: l10n.metadataReleaseTitle),
        WaxSettingRow(
          title: l10n.metadataUnofficialTitle,
          help: l10n.metadataUnofficialHelp,
          control: WaxSwitch(
            label: l10n.metadataUnofficialTitle,
            value: state.metadata.unofficial,
            semanticsId: SemanticsIds.unofficialSwitch,
            onChanged: _busy
                ? null
                : (v) => _run(
                    () => ref
                        .read(metadataControllerProvider(widget.pid).notifier)
                        .setUnofficial(unofficial: v),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _actionsSection(BuildContext context, MetadataEditorState state) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: l10n.metadataIdentificationTitle),
        Text(
          l10n.metadataIdentificationBlurb,
          style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: WaxSpace.s12),
        Wrap(
          spacing: WaxSpace.s8,
          runSpacing: WaxSpace.s8,
          children: <Widget>[
            WaxButton(
              label: l10n.metadataRematch,
              kind: WaxButtonKind.tonal,
              icon: WaxIcons.search,
              semanticsId: SemanticsIds.metadataRematch,
              onPressed: _busy ? null : _rematch,
            ),
            WaxButton(
              label: l10n.metadataFetch,
              kind: WaxButtonKind.tonal,
              icon: WaxIcons.downloads,
              semanticsId: SemanticsIds.metadataEnrich,
              onPressed: _busy ? null : () => _enrich(state),
            ),
          ],
        ),
      ],
    );
  }
}

/// The item as it stands: what it is called, and where its values came
/// from. The provenance summary is one line rather than a chip per
/// field, which the fields themselves already carry.
class _Header extends StatelessWidget {
  const _Header({required this.state});

  final MetadataEditorState state;

  /// "5 from tags, 2 from you, 1 from MusicBrainz", commonest first.
  ///
  /// Scalar rows only. The provenance list also carries an `art` and a
  /// `lyrics` row whenever the item holds one, and counting those in
  /// would shift this line on every item with a cover - which is nearly
  /// all of them - and stop "no recorded sources" meaning what it says.
  /// The artifacts get their own lines below instead, where naming the
  /// two of them is more use than adding one to a tally.
  static String provenanceSummary(
    AppLocalizations l10n,
    ItemMetadata metadata,
  ) {
    final counts = <String, int>{};
    for (final entry in metadata.provenance) {
      if (entry.isArtifact) continue;
      final source = entry.provider ?? entry.source;
      counts[source] = (counts[source] ?? 0) + 1;
    }
    if (counts.isEmpty) return l10n.metadataNoSources;
    final ordered = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ordered
        .map(
          (e) => l10n.metadataFromSource(
            e.value,
            provenanceProducerName(l10n, e.key),
          ),
        )
        .join(', ');
  }

  /// Where the item's cover and lyrics came from, one line each, worded
  /// the way the mark under a cover is.
  ///
  /// The row is not enough on its own. An `art` or `lyrics` row also
  /// appears for a field locked with nothing behind it - the way to
  /// stop a scan filling one - and the source on that row is whatever
  /// the writer that took the lock happened to stamp, which is not
  /// where anything came from. So each line is drawn only when the item
  /// actually holds the artifact the row is about.
  static List<String> artifactSources(
    AppLocalizations l10n,
    ItemMetadata metadata,
  ) {
    final out = <String>[];
    for (final row in metadata.provenance) {
      if (!row.isArtifact) continue;
      final holdsIt = row.field == 'art'
          ? metadata.hasOwnArtwork
          : metadata.lyrics != null;
      if (!holdsIt) continue;
      final label = provenanceSourceLabel(l10n, row);
      if (label == null) continue;
      out.add(
        row.field == 'art'
            ? l10n.metadataArtworkSource(label)
            : l10n.metadataLyricsSource(label),
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final metadata = state.metadata;
    final title = metadata.fields['title'] ?? l10n.metadataUntitled;
    final artist = metadata.fields['artist'];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: WaxType.titleEntity.copyWith(color: colors.textPrimary),
              ),
              if (artist != null && artist.isNotEmpty)
                Text(
                  artist,
                  style: WaxType.body.copyWith(color: colors.textSecondary),
                ),
              const SizedBox(height: WaxSpace.s8),
              Text(
                provenanceSummary(l10n, metadata),
                style: WaxType.caption.copyWith(color: colors.textTertiary),
              ),
              for (final line in artifactSources(l10n, metadata))
                Text(
                  line,
                  style: WaxType.caption.copyWith(color: colors.textTertiary),
                ),
            ],
          ),
        ),
        DomainBadge(_domain(metadata.mediaType)),
      ],
    );
  }

  static WaxDomain _domain(MediaType type) => switch (type) {
    MediaType.music => WaxDomain.music,
    MediaType.podcast => WaxDomain.podcasts,
    MediaType.audiobook => WaxDomain.audiobooks,
  };
}

/// The entities this item belongs to. Doors beside the form rather than
/// links, because the lines they name are edit fields.
class _EntityDoors extends StatelessWidget {
  const _EntityDoors({required this.metadata});

  final ItemMetadata metadata;

  @override
  Widget build(BuildContext context) {
    final artistPid = metadata.artistPid;
    final albumPid = metadata.albumPid;
    final rgPid = metadata.releaseGroupPid;
    if (artistPid == null && albumPid == null && rgPid == null) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: WaxSpace.s8),
      child: Wrap(
        spacing: WaxSpace.s8,
        runSpacing: WaxSpace.s8,
        children: <Widget>[
          if (artistPid != null)
            WaxPill(
              label: l10n.metadataOpenArtist,
              semanticsId: SemanticsIds.metadataOpenArtist,
              onPressed: () => context.push(
                WaxRoute.musicBucket(MusicDimension.artists, artistPid),
              ),
            ),
          if (albumPid != null)
            WaxPill(
              label: l10n.metadataOpenAlbum,
              semanticsId: SemanticsIds.metadataOpenAlbum,
              onPressed: () => context.push(
                WaxRoute.musicBucket(MusicDimension.albums, albumPid),
              ),
            ),
          if (rgPid != null)
            WaxPill(
              label: l10n.metadataOpenReleaseGroup,
              semanticsId: SemanticsIds.metadataOpenReleaseGroup,
              onPressed: () => context.push(
                WaxRoute.musicBucket(MusicDimension.releaseGroups, rgPid),
              ),
            ),
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.field,
    required this.controller,
    required this.locked,
    required this.provenance,
    required this.dirty,
    required this.onToggleLock,
  });

  final EditableField field;
  final TextEditingController controller;
  final bool locked;
  final FieldProvenance? provenance;

  /// Whether this field differs from what is stored. Marked on the
  /// field rather than only counted on the Save button, so a long form
  /// says which line is about to be written.
  final bool dirty;

  final VoidCallback onToggleLock;

  String _provenanceText(AppLocalizations l10n) {
    final p = provenance;
    if (p == null) return l10n.metadataSourceUnknown;
    final provider = p.provider;
    return provider == null
        ? p.source
        : l10n.metadataSourceWithProvider(p.source, provider);
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: WaxTextField(
            label: metadataFieldLabel(l10n, field.name),
            controller: controller,
            semanticsId: SemanticsIds.metadataField(field.name),
          ),
        ),
        const SizedBox(width: WaxSpace.s8),
        Padding(
          padding: const EdgeInsets.only(bottom: WaxSpace.s8),
          child: Row(
            children: <Widget>[
              CodecChip(_provenanceText(l10n), emphasis: dirty),
              WaxIconButton(
                glyph: locked ? WaxIcons.bookmark : WaxIcons.edit,
                label: locked
                    ? l10n.metadataUnlockField(field.name)
                    : l10n.metadataLockField(field.name),
                active: locked,
                size: 16,
                color: locked ? colors.accent : null,
                semanticsId: SemanticsIds.fieldLock(field.name),
                onPressed: onToggleLock,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// What the LRC will look like played back. The server takes the text as
/// typed, so this is the only warning that a stamp did not parse.
class _LyricsPreview extends StatelessWidget {
  const _LyricsPreview({required this.controller});

  final TextEditingController controller;

  static final _stamp = RegExp(r'^\s*\[(\d+):(\d+(?:\.\d+)?)\]\s*(.*)$');

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final lines = value.text
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .toList();
        if (lines.isEmpty) {
          return Text(
            l10n.metadataNothingToPreview,
            style: WaxType.caption.copyWith(color: colors.textTertiary),
          );
        }
        final synced = lines.where((line) => _stamp.hasMatch(line)).length;
        return Semantics(
          identifier: SemanticsIds.lyricsPreview,
          container: true,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(WaxSpace.s12),
            decoration: BoxDecoration(
              color: colors.surface1,
              borderRadius: WaxRadius.card,
              border: Border.all(color: colors.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  synced == lines.length
                      ? l10n.metadataLinesAllTimed(lines.length)
                      : l10n.metadataLinesSomeTimed(lines.length, synced),
                  style: WaxType.overline.copyWith(
                    color: synced == 0 ? colors.textTertiary : colors.accent,
                  ),
                ),
                const SizedBox(height: WaxSpace.s8),
                for (final line in lines.take(6)) _previewLine(colors, line),
                if (lines.length > 6)
                  Text(
                    '...',
                    style: WaxType.caption.copyWith(color: colors.textTertiary),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _previewLine(WaxColors colors, String line) {
    final match = _stamp.firstMatch(line);
    if (match == null) {
      return Text(
        line.trim(),
        style: WaxType.bodySmall.copyWith(color: colors.textTertiary),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    final seconds = double.tryParse(match.group(2)!) ?? 0;
    final stamp =
        '${match.group(1)!.padLeft(2, '0')}:'
        '${seconds.floor().toString().padLeft(2, '0')}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(stamp, style: WaxType.monoTime.copyWith(color: colors.accent)),
        const SizedBox(width: WaxSpace.s8),
        Expanded(
          child: Text(
            match.group(3)!,
            style: WaxType.bodySmall.copyWith(color: colors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
