import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../music/music_controllers.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'artwork_manager.dart';
import 'metadata_controller.dart';

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
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      await action();
    } on WaxDeckApiException catch (e) {
      final hint = e.statusCode == 409
          ? ' Check "Force" to overwrite locked fields.'
          : '';
      messenger.show('${e.message}.$hint');
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
    final messenger = ref.read(shellMessengerProvider.notifier);
    // Hoisted: the message outlives this screen, and a closure over its
    // context throws once the editor is popped.
    final router = GoRouter.maybeOf(context);
    final entryId = await ref
        .read(metadataControllerProvider(widget.pid).notifier)
        .rematch();
    messenger.show(
      'Queued for identification',
      actionLabel: router == null ? null : 'Open review',
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
    final messenger = ref.read(shellMessengerProvider.notifier);
    final result = await ref
        .read(metadataControllerProvider(widget.pid).notifier)
        .enrich(_wantsFor(state.metadata.mediaType));
    final parts = [
      if (result.applied.isNotEmpty) 'Applied: ${result.applied.join(', ')}',
      if (result.skipped.isNotEmpty) 'Skipped: ${result.skipped.join(', ')}',
    ];
    messenger.show(parts.isEmpty ? 'Nothing to fetch' : parts.join('. '));
  });

  @override
  Widget build(BuildContext context) {
    final sizeClass = WaxSizeClass.of(context);
    final editor = ref.watch(metadataControllerProvider(widget.pid));
    ref.listen(metadataControllerProvider(widget.pid), (previous, next) {
      final value = next.value;
      if (value != null) _adoptStored(value);
    });
    return WaxScaffold(
      title: 'Edit metadata',
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
            title: 'Could not load the metadata',
            message: error is WaxDeckApiException
                ? error.message
                : 'Something went wrong reading it.',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(
          title: 'Fields',
          overline: 'What this item claims to be',
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
          title: 'Write tags to files',
          help: 'Also rewrite the tags embedded in the backing files',
          control: WaxSwitch(
            label: 'Write tags to files',
            value: _writeBack,
            semanticsId: SemanticsIds.metadataWriteback,
            onChanged: (v) => setState(() => _writeBack = v),
          ),
        ),
        WaxSettingRow(
          title: 'Lock edited fields',
          help: 'Keep scans and enrichment from overwriting what you type',
          control: WaxSwitch(
            label: 'Lock edited fields',
            value: _lock,
            semanticsId: SemanticsIds.metadataLock,
            onChanged: (v) => setState(() => _lock = v),
          ),
        ),
        WaxSettingRow(
          title: 'Force',
          help: 'Overwrite fields that are already locked',
          control: WaxSwitch(
            label: 'Force',
            value: _force,
            semanticsId: SemanticsIds.metadataForce,
            onChanged: (v) => setState(() => _force = v),
          ),
        ),
        const SizedBox(height: WaxSpace.s16),
        WaxButton(
          label: changed.isEmpty
              ? 'Save'
              : 'Save ${changed.length} '
                    '${changed.length == 1 ? 'change' : 'changes'}',
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
    return Padding(
      padding: const EdgeInsets.only(bottom: WaxSpace.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          WaxBanner(
            message: 'Saved, but some files kept their old tags.',
            tone: WaxBannerTone.caution,
            semanticsId: SemanticsIds.metadataWritebackWarning,
            onDismiss: () => setState(() => _writeBackFailures = const []),
          ),
          const SizedBox(height: WaxSpace.s8),
          // Which file and why is the content of the warning, so it
          // stays on screen rather than passing as a message.
          for (final failure in _writeBackFailures)
            Text(
              '${failure.path ?? failure.filePid}: ${failure.reason}',
              style: WaxType.monoData.copyWith(color: colors.textSecondary),
            ),
        ],
      ),
    );
  }

  Widget _creditsSection(BuildContext context, MetadataEditorState state) {
    final colors = WaxColors.of(context);
    final roles = state.kindFields.creditRoles;
    final role = _creditRole ?? (roles.isEmpty ? null : roles.first.name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(title: 'Credits', overline: 'Who else is on it'),
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
            'No credit roles for this kind',
            style: WaxType.bodySmall.copyWith(color: colors.textTertiary),
          )
        else ...<Widget>[
          const SizedBox(height: WaxSpace.s8),
          WaxChoice<String>(
            label: 'Credit role',
            value: role!,
            semanticsId: SemanticsIds.creditsRole,
            options: <String>[for (final r in roles) r.name],
            labelFor: (name) => name,
            onChanged: (v) => setState(() => _creditRole = v),
          ),
          const SizedBox(height: WaxSpace.s8),
          WaxTextField(
            label: 'Names, comma separated',
            controller: _creditNamesController,
            semanticsId: SemanticsIds.creditsNames,
          ),
          const SizedBox(height: WaxSpace.s8),
          WaxButton(
            label: 'Save credits',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(
          title: 'Custom tags',
          overline: 'Anything the vocabulary has no field for',
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
                  label: 'Remove tag ${tag.key}',
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
                label: 'Key',
                controller: _tagKeyController,
                semanticsId: SemanticsIds.tagKey,
              ),
            ),
            const SizedBox(width: WaxSpace.s8),
            Expanded(
              child: WaxTextField(
                label: 'Values, comma separated',
                controller: _tagValuesController,
                semanticsId: SemanticsIds.tagValues,
              ),
            ),
          ],
        ),
        const SizedBox(height: WaxSpace.s8),
        WaxButton(
          label: 'Add tag',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(
          title: 'Lyrics',
          overline: 'Timed LRC, or plain lines',
        ),
        WaxTextField(
          label: 'LRC',
          hint: '[00:12.00] First line',
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
              label: 'Save lyrics',
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
              label: 'Clear',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(title: 'Release status'),
        WaxSettingRow(
          title: 'Unofficial release',
          help: 'A bootleg, a promo, or another unofficial issue',
          control: WaxSwitch(
            label: 'Unofficial release',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(title: 'Identification'),
        Text(
          'Rematch reopens identification and puts the result in the review '
          'queue. Fetching metadata applies what the providers already agree '
          'on, without asking.',
          style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: WaxSpace.s12),
        Wrap(
          spacing: WaxSpace.s8,
          runSpacing: WaxSpace.s8,
          children: <Widget>[
            WaxButton(
              label: 'Rematch',
              kind: WaxButtonKind.tonal,
              icon: WaxIcons.search,
              semanticsId: SemanticsIds.metadataRematch,
              onPressed: _busy ? null : _rematch,
            ),
            WaxButton(
              label: 'Fetch metadata',
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
  static String provenanceSummary(ItemMetadata metadata) {
    if (metadata.provenance.isEmpty) return 'No recorded sources';
    final counts = <String, int>{};
    for (final entry in metadata.provenance) {
      final source = entry.provider ?? entry.source;
      counts[source] = (counts[source] ?? 0) + 1;
    }
    final ordered = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ordered.map((e) => '${e.value} from ${e.key}').join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final metadata = state.metadata;
    final title = metadata.fields['title'] ?? 'Untitled';
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
                provenanceSummary(metadata),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: WaxSpace.s8),
      child: Wrap(
        spacing: WaxSpace.s8,
        runSpacing: WaxSpace.s8,
        children: <Widget>[
          if (artistPid != null)
            WaxPill(
              label: 'Open artist',
              semanticsId: SemanticsIds.metadataOpenArtist,
              onPressed: () => context.push(
                WaxRoute.musicBucket(MusicDimension.artists, artistPid),
              ),
            ),
          if (albumPid != null)
            WaxPill(
              label: 'Open album',
              semanticsId: SemanticsIds.metadataOpenAlbum,
              onPressed: () => context.push(
                WaxRoute.musicBucket(MusicDimension.albums, albumPid),
              ),
            ),
          if (rgPid != null)
            WaxPill(
              label: 'Open release group',
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

  String get _provenanceText {
    final p = provenance;
    if (p == null) return 'Source unknown';
    final provider = p.provider;
    return provider == null ? p.source : '${p.source} ($provider)';
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: WaxTextField(
            label: field.name,
            controller: controller,
            semanticsId: SemanticsIds.metadataField(field.name),
          ),
        ),
        const SizedBox(width: WaxSpace.s8),
        Padding(
          padding: const EdgeInsets.only(bottom: WaxSpace.s8),
          child: Row(
            children: <Widget>[
              CodecChip(_provenanceText, emphasis: dirty),
              WaxIconButton(
                glyph: locked ? WaxIcons.bookmark : WaxIcons.edit,
                label: locked ? 'Unlock ${field.name}' : 'Lock ${field.name}',
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
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final lines = value.text
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .toList();
        if (lines.isEmpty) {
          return Text(
            'Nothing to preview',
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
                      ? '${lines.length} lines, all timed'
                      : '${lines.length} lines, $synced timed',
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
