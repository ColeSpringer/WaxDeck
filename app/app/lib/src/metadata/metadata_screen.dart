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
import 'metadata_form.dart';

/// The per-item metadata editor, deep-linkable at `/metadata/<pid>`.
/// Always pushed: a review row, a book, and the lyrics view all open it,
/// so it has three ancestries and a location may declare one.
class MetadataScreen extends ConsumerWidget {
  const MetadataScreen({super.key, required this.pid});

  final String pid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editor = ref.watch(metadataControllerProvider(pid));
    // On the screen, not only on the doors that open it. The workbench
    // refuses for the same reason - this location is shareable and the
    // web build puts it in the path - but it refuses before it loads,
    // because being an administrator is something the session already
    // knows. Here the answer is a property of the item and arrives with
    // the read, so the refusal waits for it: the account whose upload
    // brought the track in may curate it, and nothing on the client can
    // work that out on its own.
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
      // A filling sliver rather than a body, so the pane can keep its
      // save bar under its own scroll the same way it does when it is
      // mounted beside the workbench's list.
      slivers: <Widget>[
        SliverFillRemaining(hasScrollBody: true, child: MetadataPane(pid: pid)),
      ],
    );
  }
}

/// The editor itself, without a page around it: the header, the typed
/// sections, and the sticky save bar that is the only thing that
/// writes. [MetadataScreen] mounts it as the whole page; the release
/// workbench mounts it beside its track list for whichever member is
/// selected.
///
/// Everything on it stages into one [MetadataDraft]. It replaced a form
/// where fields, credits, tags, and lyrics each carried a save of their
/// own, which meant four buttons and no one answer to "is anything
/// unsaved".
class MetadataPane extends ConsumerStatefulWidget {
  const MetadataPane({
    super.key,
    required this.pid,
    this.embedded = false,
    this.onSaved,
    this.onDirtyChanged,
  });

  /// The narrowest the pane works at before its field rows start
  /// wrapping badly. Stated here, where the form lives, so a host
  /// splitting a screen derives its floor from what the pane needs
  /// rather than guessing one.
  static const double minWidth = 360;

  final String pid;

  /// Whether the pane sits beside something else rather than being the
  /// page. Embedded it keeps one column whatever its width - the room
  /// belongs to the list beside it - and takes pane gutters rather than
  /// the page's.
  final bool embedded;

  /// Fired after a save committed, for a host whose other panes read
  /// the same item: the controller refetches only itself, so a list
  /// beside this pane would keep the old title without it.
  final VoidCallback? onSaved;

  /// Reports whether the draft holds anything unsaved, so a host that
  /// replaces this pane on a selection change can ask before it
  /// discards typing. Fired on the edges only.
  final ValueChanged<bool>? onDirtyChanged;

  @override
  ConsumerState<MetadataPane> createState() => _MetadataPaneState();
}

class _MetadataPaneState extends ConsumerState<MetadataPane> {
  final _draft = MetadataDraft();

  var _writeBack = false;
  var _lock = true;
  var _force = false;
  var _busy = false;

  /// Write-back failures from the last save, rendered as a warning
  /// list beside the save bar; a partial tag write is not an error.
  List<WriteBackFailure> _writeBackFailures = const [];

  @override
  void initState() {
    super.initState();
    // Redraws dirty marks and the save bar as the user types.
    _draft.addListener(_onDraftChanged);
  }

  /// The dirtiness last reported, so [MetadataPane.onDirtyChanged]
  /// fires on the edges rather than on every keystroke.
  var _reportedDirty = false;

  void _onDraftChanged() {
    if (!mounted) return;
    setState(() {});
    _reportDirty();
  }

  void _reportDirty() {
    final onDirty = widget.onDirtyChanged;
    if (onDirty == null) return;
    final state = ref.read(metadataControllerProvider(widget.pid)).value;
    final dirty = state != null && !_draft.changes(state).isEmpty;
    if (dirty != _reportedDirty) {
      _reportedDirty = dirty;
      onDirty(dirty);
    }
  }

  @override
  void dispose() {
    _draft
      ..removeListener(_onDraftChanged)
      ..dispose();
    super.dispose();
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

  /// Whether write-back is offered at all: episodes never write back to
  /// files by upstream design, and a switch the server refuses wholesale
  /// is worse than no switch.
  static bool _canWriteBack(MetadataEditorState state) =>
      state.metadata.mediaType != MediaType.podcast;

  Future<void> _save(MetadataEditorState state) => _run(() async {
    final l10n = context.l10n;
    final changes = _draft.changes(state);
    if (changes.isEmpty) return;
    final outcome = await ref
        .read(metadataControllerProvider(widget.pid).notifier)
        .saveAll(
          changes,
          writeBack: _canWriteBack(state) && _writeBack,
          lock: _lock,
          force: _force,
        );
    if (!mounted) return;
    // Re-seed to what was sent only when everything landed: after a
    // refusal the parts that did not land must stay the user's edits.
    if (outcome.refusal == null) _draft.markSaved(changes);
    setState(() => _writeBackFailures = outcome.writeBackFailures);
    _reportDirty();
    // Even a refused save committed the calls before the refusal, so
    // the host's other readers of this item are stale either way.
    widget.onSaved?.call();
    final messages = <String>[
      ...outcome.warnings,
      // A locked field keeps the server's sentence, which names the
      // field, and gains the half the server cannot know: the switch on
      // this page that overrides it.
      if (outcome.refusal case final e?)
        e.code == 'field-locked'
            ? '${e.message}. ${l10n.metadataFieldLockedHint}'
            : explainRefusal(l10n, e),
    ];
    if (messages.isNotEmpty) {
      ref.read(shellMessengerProvider.notifier).show(messages.join('\n'));
    }
  });

  Future<void> _pickGenres(MetadataEditorState state) async {
    final tree = ref.read(canonicalGenresProvider).value ?? const <GenreNode>[];
    final picked = await showMetadataGenrePicker(
      context,
      tree: tree,
      selected: _draft.genresValue(state.metadata.fields['genre']),
    );
    if (picked != null) _draft.setGenres(picked);
  }

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
    // Kept warm for the picker: read at tap time, fetched once here.
    ref.watch(canonicalGenresProvider);
    ref.listen(metadataControllerProvider(widget.pid), (previous, next) {
      final value = next.value;
      if (value != null) _draft.adopt(value);
    });
    // The screen answers this with a full [ForbiddenPage] before the
    // pane ever builds; this inline refusal is for a host that mounted
    // the pane beside something else.
    if (editor.value case final state? when state.metadata.mayCurate == false) {
      return Center(
        child: EmptyState(
          glyph: WaxIcons.edit,
          title: context.l10n.metadataForbiddenTitle,
          message: context.l10n.metadataForbiddenMessage,
        ),
      );
    }
    // One walk of the draft per frame: the bar's count, the dirty
    // marks, and the section rows all read this same summary.
    final changes = switch (editor) {
      AsyncData(:final value) => _draft.changes(value),
      _ => null,
    };
    final padding = widget.embedded
        ? const EdgeInsets.all(WaxSpace.s16)
        : sizeClass.gutter.add(const EdgeInsets.only(bottom: WaxSpace.s32));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: switch (editor) {
            AsyncData(:final value) => SingleChildScrollView(
              padding: padding,
              child: _body(context, value, changes!, sizeClass),
            ),
            AsyncError(:final error) => Padding(
              padding: padding,
              child: ErrorState(
                title: context.l10n.metadataLoadError,
                message: context.explain(error),
                onRetry: () =>
                    ref.invalidate(metadataControllerProvider(widget.pid)),
              ),
            ),
            _ => const SkeletonShapes(shape: SkeletonShape.detail),
          },
        ),
        // Gated on the same pattern as the body: a bar offering Save
        // over an error state (or a skeleton) would be saving against a
        // state the pane is not showing.
        if (editor case AsyncData(:final value))
          MetadataSaveBar(
            count: changes!.count,
            busy: _busy,
            onSave: () => _save(value),
            writeBackFailures: _writeBackFailures,
            onDismissFailures: () =>
                setState(() => _writeBackFailures = const []),
          ),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    MetadataEditorState state,
    MetadataChanges changes,
    WaxSizeClass sizeClass,
  ) {
    final left = <Widget>[
      _fieldsSection(context, state, changes),
      MetadataCreditsSection(state: state, draft: _draft, busy: _busy),
      MetadataTagsSection(state: state, draft: _draft, busy: _busy),
    ];
    final right = <Widget>[
      ArtworkManager(
        pid: widget.pid,
        title: state.metadata.fields['title'] ?? widget.pid,
        hasArtwork: state.metadata.hasArtwork,
      ),
      const SizedBox(height: WaxSpace.s32),
      _lyricsSection(context, state),
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
        // Embedded keeps one column whatever the window says: the pane
        // is the narrow half of a split, and the size class describes
        // the window around it.
        if (!widget.embedded && sizeClass.hasSidebar)
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

  /// The fields, one typed row each, and the switches that shape the
  /// save. No button: the save bar is the button.
  Widget _fieldsSection(
    BuildContext context,
    MetadataEditorState state,
    MetadataChanges changes,
  ) {
    final changed = changes.fields;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: l10n.metadataFieldsTitle,
          overline: l10n.metadataFieldsOverline,
        ),
        for (final field in state.kindFields.fields) ...<Widget>[
          MetadataFieldRow(
            field: field,
            state: state,
            draft: _draft,
            dirty: changed.containsKey(field.name),
            busy: _busy,
            onToggleLock: () => _run(
              () => ref
                  .read(metadataControllerProvider(widget.pid).notifier)
                  .setLock(field.name, locked: !state.isLocked(field.name)),
            ),
            onAddGenre: () => _pickGenres(state),
          ),
          const SizedBox(height: WaxSpace.s12),
        ],
        _EntityDoors(metadata: state.metadata),
        const SizedBox(height: WaxSpace.s8),
        // Absent for episodes rather than refused: they never write
        // back by upstream design, and the server answers the whole
        // save with that refusal when asked.
        if (_canWriteBack(state))
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
        const SizedBox(height: WaxSpace.s32),
      ],
    );
  }

  Widget _lyricsSection(BuildContext context, MetadataEditorState state) {
    final l10n = context.l10n;
    _draft.lyricsValue(state.metadata.lyrics?.lrc ?? '');
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
          helperText: l10n.metadataLyricsEmptyClears,
          controller: _draft.lyrics,
          maxLines: 8,
          semanticsId: SemanticsIds.lyricsField,
        ),
        const SizedBox(height: WaxSpace.s8),
        _LyricsPreview(controller: _draft.lyrics),
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
            value: _draft.unofficialValue(stored: state.metadata.unofficial),
            semanticsId: SemanticsIds.unofficialSwitch,
            // Disabled while a save is in flight: a flip back to the
            // seeded value mid-save reads as untouched once the refetch
            // lands, and the second decision would be discarded.
            onChanged: _busy ? null : (v) => _draft.setUnofficial(value: v),
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
