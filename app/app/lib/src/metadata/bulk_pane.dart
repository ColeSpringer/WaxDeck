import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../music/album_detail.dart';
import '../music/music_controllers.dart';
import '../providers.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'metadata_controller.dart';
import 'metadata_form.dart';

/// What the bulk form opens on: the music field vocabulary and the
/// checked tracks' current metadata, read together so every row can say
/// whether the selection agrees on it.
typedef BulkSeed = ({KindFields kindFields, List<ItemMetadata> items});

/// Keyed by the joined pid list: a different selection is a different
/// set of common values, so it is a different seed.
final _bulkSeedProvider = FutureProvider.autoDispose.family<BulkSeed, String>((
  ref,
  key,
) async {
  final pids = key.isEmpty ? const <String>[] : key.split(' ');
  final repository = ref.watch(repositoryProvider);
  final fieldsFuture = repository.getMetadataFields();
  // The eager read must not be left unheard while the items are
  // awaited: a server failing both would surface the vocabulary read's
  // rejection as an uncaught async error before the await below ever
  // attaches - the same guard the editor controller carries.
  fieldsFuture.ignore();
  final items = await Future.wait(pids.map(repository.getItemMetadata));
  final fields = await fieldsFuture;
  final kind =
      fields.kinds.where((k) => k.kind == MediaType.music).firstOrNull ??
      const KindFields(kind: MediaType.music, fields: []);
  return (kindFields: kind, items: items);
});

/// What a bulk edit does when a target field is already locked on a
/// track. The server's three answers, offered as one choice because
/// `skipLocked` and `force` are mutually exclusive on the wire.
enum BulkLockedPolicy { fail, skip, force }

/// A boolean field's three bulk states. An enum rather than `bool?`
/// because the choice menu reports a dismissal as null, so a nullable
/// "leave as is" could never be picked back once left.
enum _BulkToggle { leave, on, off }

/// The bulk half of the release workbench: one form over the checked
/// tracks, writing through `bulkEditMetadata` in one batch. A field the
/// selection agrees on opens on that value; one it disagrees on opens
/// empty under a "Mixed" chip, and typing there sets it on every track.
/// Only the fields that were actually edited are sent.
class WorkbenchBulkPane extends ConsumerStatefulWidget {
  const WorkbenchBulkPane({
    super.key,
    required this.pids,
    required this.albumPid,
    required this.onRegrouped,
    this.onDirtyChanged,
  });

  /// The checked tracks, in list order.
  final List<String> pids;

  /// The release the workbench is open on, so a save that regrouped
  /// part of it can say where the edited tracks went.
  final String albumPid;

  /// Takes the workbench to the album the edited tracks landed on; the
  /// host owns the move because a pane in a sheet has a sheet to close.
  final void Function(String newPid) onRegrouped;

  /// Reports whether the form holds anything unsaved; the host asks
  /// before a selection change re-keys this pane and drops it.
  final ValueChanged<bool>? onDirtyChanged;

  @override
  ConsumerState<WorkbenchBulkPane> createState() => _WorkbenchBulkPaneState();
}

class _WorkbenchBulkPaneState extends ConsumerState<WorkbenchBulkPane> {
  final _controllers = <String, TextEditingController>{};
  final _seeded = <String, String>{};

  /// Fields whose text has actually been typed in, tracked apart from
  /// the value compare: on a mixed field the seed is empty, so "typed
  /// and cleared back to empty" and "never touched" hold the same
  /// string - and only the first means "wipe this on every track".
  final _touched = <String>{};
  final _lastText = <String, String>{};

  /// A staged tri-state per toggle field; [_BulkToggle.leave] - the
  /// default - keeps each track as it is, which is the third state a
  /// switch cannot say.
  final _toggles = <String, _BulkToggle>{};

  /// Staged genres; null until the person edits them. The seed is set
  /// once on first sight (and by a save), never rewritten from a
  /// build: the seed provider's refetch briefly serves pre-save items,
  /// and re-deriving from those resurrected the values a save had just
  /// retired.
  List<String>? _genres;
  String? _genresSeed;

  var _writeBack = false;
  var _policy = BulkLockedPolicy.fail;
  var _busy = false;
  List<WriteBackFailure> _writeBackFailures = const [];

  /// The dirtiness last reported, so the callback fires on the edges.
  var _reportedDirty = false;

  String get _seedKey => widget.pids.join(' ');

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// The value the selection agrees on, or null where it is mixed.
  static String? _common(List<ItemMetadata> items, String field) {
    final values = {for (final m in items) m.fields[field] ?? ''};
    return values.length == 1 ? values.first : null;
  }

  static bool _isMixed(BulkSeed seed, String field) =>
      _common(seed.items, field) == null;

  void _reportDirty() {
    final onDirty = widget.onDirtyChanged;
    if (onDirty == null) return;
    final seed = ref.read(_bulkSeedProvider(_seedKey)).value;
    final dirty = seed != null && _staged(seed).isNotEmpty;
    if (dirty != _reportedDirty) {
      _reportedDirty = dirty;
      onDirty(dirty);
    }
  }

  TextEditingController _controllerFor(String field, String seed) =>
      _controllers.putIfAbsent(field, () {
        _seeded[field] = seed;
        _lastText[field] = seed;
        final controller = TextEditingController(text: seed);
        controller.addListener(() {
          // Touched means the text changed, not that the caret moved:
          // a controller notifies for selection changes too, and a
          // click into a mixed field must not read as a wipe.
          if (controller.text != _lastText[field]) {
            _lastText[field] = controller.text;
            _touched.add(field);
          }
          setState(() {});
          _reportDirty();
        });
        return controller;
      });

  String _genreSeed(BulkSeed seed) => _genresSeed ??= joinMetadataGenres(
    splitMetadataGenres(_common(seed.items, 'genre') ?? ''),
  );

  /// Everything edited, serialized for the wire. A field is staged when
  /// its value differs from its seed - or when it was touched over a
  /// mixed seed, where the empty seed makes "cleared" and "untouched"
  /// the same string and only touching distinguishes a deliberate wipe.
  Map<String, String> _staged(BulkSeed seed) {
    final staged = <String, String>{};
    for (final field in seed.kindFields.fields) {
      switch (metadataFieldType(field.name)) {
        case MetadataFieldType.text || MetadataFieldType.count:
          final controller = _controllers[field.name];
          if (controller == null) break;
          final changed = controller.text != _seeded[field.name];
          final wiped =
              _touched.contains(field.name) && _isMixed(seed, field.name);
          if (changed || wiped) staged[field.name] = controller.text;
        case MetadataFieldType.toggle:
          switch (_toggles[field.name] ?? _BulkToggle.leave) {
            case _BulkToggle.leave:
              break;
            case _BulkToggle.on:
              staged[field.name] = 'true';
            case _BulkToggle.off:
              staged[field.name] = 'false';
          }
        case MetadataFieldType.genres:
          final genres = _genres;
          if (genres == null) break;
          final joined = joinMetadataGenres(genres);
          if (joined != _genreSeed(seed) || _isMixed(seed, field.name)) {
            staged[field.name] = joined;
          }
        // No closed-choice field exists on music; a vocabulary that
        // grows one is left to the per-item editor rather than guessed
        // at here.
        case MetadataFieldType.choice:
          break;
      }
    }
    return staged;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // A host can hold checks for tracks a regroup already moved away;
    // an empty effective selection is a state to say, not a fetch of
    // nothing to attempt.
    if (widget.pids.isEmpty) {
      return Center(
        child: EmptyState(
          glyph: WaxIcons.check,
          title: l10n.metadataWorkbenchSelectEmptyTitle,
          message: l10n.metadataWorkbenchSelectEmptyMessage,
        ),
      );
    }
    final seedAsync = ref.watch(_bulkSeedProvider(_seedKey));
    // Kept warm for the genre picker, the way the item editor keeps it.
    ref.watch(canonicalGenresProvider);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: SemanticsIds.workbenchBulkPane,
      child: switch (seedAsync) {
        AsyncValue(value: final seed?) => _form(seed),
        AsyncValue(hasError: true, error: final Object error) => Padding(
          padding: const EdgeInsets.all(WaxSpace.s16),
          child: ErrorState(
            title: l10n.metadataLoadError,
            message: context.explain(error),
            onRetry: () => ref.invalidate(_bulkSeedProvider(_seedKey)),
          ),
        ),
        _ => const SkeletonShapes(shape: SkeletonShape.list),
      },
    );
  }

  Widget _form(BulkSeed seed) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final staged = _staged(seed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(WaxSpace.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SectionHeader(
                  title: l10n.metadataBulkTitle(widget.pids.length),
                ),
                for (final field in seed.kindFields.fields) ...<Widget>[
                  _fieldRow(seed, field.name, staged),
                  const SizedBox(height: WaxSpace.s12),
                ],
                const SizedBox(height: WaxSpace.s8),
                WaxSettingRow(
                  title: l10n.metadataWriteBackTitle,
                  help: l10n.metadataWriteBackHelp,
                  control: WaxSwitch(
                    label: l10n.metadataWriteBackTitle,
                    value: _writeBack,
                    semanticsId: SemanticsIds.metadataWriteback,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _writeBack = v),
                  ),
                ),
                WaxSettingRow(
                  title: l10n.metadataBulkLockedPolicy,
                  help: l10n.metadataBulkLockedPolicyHelp,
                  control: WaxChoice<BulkLockedPolicy>(
                    label: l10n.metadataBulkLockedPolicy,
                    value: _policy,
                    semanticsId: SemanticsIds.workbenchBulkLockedPolicy,
                    options: BulkLockedPolicy.values,
                    labelFor: (policy) => switch (policy) {
                      BulkLockedPolicy.fail => l10n.metadataBulkLockedFail,
                      BulkLockedPolicy.skip => l10n.metadataBulkLockedSkip,
                      BulkLockedPolicy.force => l10n.metadataBulkLockedForce,
                    },
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _policy = v),
                  ),
                ),
                const SizedBox(height: WaxSpace.s8),
                // What the endpoint always does, said where the save is
                // decided: it locks what it writes, and one batch stops
                // at a thousand items.
                Text(
                  l10n.metadataBulkLockNote,
                  style: WaxType.caption.copyWith(color: colors.textTertiary),
                ),
                const SizedBox(height: WaxSpace.s16),
              ],
            ),
          ),
        ),
        MetadataSaveBar(
          count: staged.length,
          busy: _busy || widget.pids.length > metadataBulkEditCap,
          onSave: () => _save(staged),
          saveSemanticsId: SemanticsIds.workbenchBulkSave,
          writeBackFailures: _writeBackFailures,
          onDismissFailures: () =>
              setState(() => _writeBackFailures = const []),
        ),
      ],
    );
  }

  Widget _fieldRow(BulkSeed seed, String field, Map<String, String> staged) {
    final l10n = context.l10n;
    final common = _common(seed.items, field);
    final mixed = common == null;
    final marks = Padding(
      padding: const EdgeInsets.only(bottom: WaxSpace.s8),
      child: CodecChip(
        mixed ? l10n.metadataBulkMixedChip : l10n.musicAlbumEditorFromTags,
        emphasis: staged.containsKey(field),
      ),
    );
    final control = switch (metadataFieldType(field)) {
      MetadataFieldType.text => WaxTextField(
        label: metadataFieldLabel(l10n, field),
        controller: _controllerFor(field, common ?? ''),
        semanticsId: SemanticsIds.workbenchBulkField(field),
      ),
      MetadataFieldType.count => WaxTextField(
        label: metadataFieldLabel(l10n, field),
        controller: _controllerFor(field, common ?? ''),
        digitsOnly: true,
        semanticsId: SemanticsIds.workbenchBulkField(field),
      ),
      // Three states, not two: a switch cannot say "leave each track
      // as it is", and a bulk form that cannot say it would flatten
      // the selection on every save.
      MetadataFieldType.toggle => WaxChoice<_BulkToggle>(
        label: metadataFieldLabel(l10n, field),
        value: _toggles[field] ?? _BulkToggle.leave,
        semanticsId: SemanticsIds.workbenchBulkField(field),
        options: _BulkToggle.values,
        labelFor: (value) => switch (value) {
          _BulkToggle.leave => l10n.metadataBulkLeaveAsIs,
          _BulkToggle.on => l10n.metadataBulkOn,
          _BulkToggle.off => l10n.metadataBulkOff,
        },
        onChanged: _busy
            ? null
            : (v) {
                setState(() => _toggles[field] = v);
                _reportDirty();
              },
      ),
      MetadataFieldType.genres => _genreChips(seed, field),
      MetadataFieldType.choice => const SizedBox.shrink(),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(child: control),
        const SizedBox(width: WaxSpace.s8),
        marks,
      ],
    );
  }

  Widget _genreChips(BulkSeed seed, String field) {
    final l10n = context.l10n;
    final genres = _genres ?? splitMetadataGenres(_genreSeed(seed));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsetsDirectional.only(
            bottom: WaxSpace.s4,
            start: WaxSpace.s12,
          ),
          child: ExcludeSemantics(
            child: Text(
              metadataFieldLabel(l10n, field),
              style: WaxType.label.copyWith(
                color: WaxColors.of(context).textSecondary,
              ),
            ),
          ),
        ),
        Semantics(
          container: true,
          explicitChildNodes: true,
          identifier: SemanticsIds.workbenchBulkField(field),
          child: Wrap(
            spacing: WaxSpace.s8,
            runSpacing: WaxSpace.s8,
            children: <Widget>[
              for (final name in genres)
                RemovableChip(
                  text: name,
                  label: l10n.metadataRemoveGenre(name),
                  onRemove: _busy
                      ? null
                      : () {
                          setState(() {
                            _genres = List.of(genres)..remove(name);
                          });
                          _reportDirty();
                        },
                ),
              WaxPill(
                label: l10n.metadataAddGenre,
                onPressed: _busy ? null : () => _pickGenres(genres),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickGenres(List<String> current) async {
    final tree = ref.read(canonicalGenresProvider).value ?? const <GenreNode>[];
    final picked = await showMetadataGenrePicker(
      context,
      tree: tree,
      selected: current,
    );
    if (picked == null || !mounted) return;
    setState(() => _genres = picked);
    _reportDirty();
  }

  Future<void> _save(Map<String, String> staged) async {
    if (_busy || staged.isEmpty) return;
    setState(() => _busy = true);
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      final result = await ref
          .read(repositoryProvider)
          .bulkEditMetadata(
            itemPids: widget.pids,
            fields: staged,
            writeBack: _writeBack,
            skipLocked: _policy == BulkLockedPolicy.skip,
            force: _policy == BulkLockedPolicy.force,
          );
      if (!mounted) return;
      _markSaved(staged);
      _reportDirty();
      setState(() => _writeBackFailures = result.writeBackFailures);
      // All three parts of the answer: what took the edit, what was
      // skipped for locks, and (as the banner beside Save) which files
      // kept their old tags.
      final parts = <String>[
        l10n.metadataBulkEdited(result.edited.length),
        if (result.skipped.isNotEmpty)
          l10n.metadataBulkSkipped(result.skipped.length),
      ];
      final moved =
          result.resultingAlbumPid != null &&
          result.resultingAlbumPid != widget.albumPid;
      messenger.show(
        <String>[
          parts.join(', '),
          if (moved) l10n.metadataBulkRegrouped,
        ].join('\n'),
        actionLabel: moved ? l10n.metadataBulkOpenNewAlbum : null,
        onAction: moved
            ? () => widget.onRegrouped(result.resultingAlbumPid!)
            : null,
      );
      // The edited rows changed under every read that holds them.
      ref.invalidate(_bulkSeedProvider(_seedKey));
      ref
        ..invalidate(albumDetailProvider(widget.albumPid))
        ..invalidate(
          musicItemsProvider((
            dimension: MusicDimension.albums,
            segment: widget.albumPid,
          )),
        );
      for (final pid in result.edited) {
        ref.invalidate(metadataControllerProvider(pid));
      }
    } on WaxDeckApiException catch (e) {
      // A locked refusal gains the half the server cannot know: the
      // choice on this form that gets past it.
      messenger.show(
        e.code == 'field-locked'
            ? '${e.message}. ${l10n.metadataBulkLockedHint}'
            : explainRefusal(l10n, e),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Re-seeds what was sent, the same discipline every editor here
  /// keeps: the refetched store now echoes these values, and a field
  /// still reading dirty after its save would offer the write for ever.
  void _markSaved(Map<String, String> staged) {
    for (final entry in staged.entries) {
      switch (metadataFieldType(entry.key)) {
        case MetadataFieldType.text || MetadataFieldType.count:
          _seeded[entry.key] = entry.value;
          // Written, so touching stops meaning "wipe": the value now
          // agrees with what every selected track stores.
          _touched.remove(entry.key);
        case MetadataFieldType.toggle:
          // Sent, so "leave as is" now leaves the sent value.
          _toggles.remove(entry.key);
        case MetadataFieldType.genres:
          _genresSeed = entry.value;
          _genres = null;
        case MetadataFieldType.choice:
          break;
      }
    }
  }
}
