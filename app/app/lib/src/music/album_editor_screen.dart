import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'album_detail.dart';

/// The album-entity editor, reached from an album's overflow and served
/// at `/metadata/<al-...>`.
///
/// A screen of its own rather than a panel inside the item editor, which
/// is what the same location serves for a track. The two write through
/// different endpoints with independent failure, so one Save button over
/// both would report success for a pair of calls of which one failed;
/// and the pid already says which is meant.
class AlbumEditorScreen extends ConsumerStatefulWidget {
  const AlbumEditorScreen({super.key, required this.pid});

  final String pid;

  @override
  ConsumerState<AlbumEditorScreen> createState() => _AlbumEditorScreenState();
}

class _AlbumEditorScreenState extends ConsumerState<AlbumEditorScreen> {
  final _controllers = <String, TextEditingController>{};

  /// What each controller was last seeded with from the server. A
  /// controller still holding exactly this has not been typed in since,
  /// which is what makes it safe to adopt a fresh value into - the same
  /// rule the item editor applies for the same reason.
  final _seeded = <String, String>{};

  var _writeBack = false;
  var _lock = true;
  var _force = false;
  var _busy = false;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String field, String initial) =>
      _controllers.putIfAbsent(field, () {
        _seeded[field] = initial;
        final controller = TextEditingController(text: initial);
        controller.addListener(() => setState(() {}));
        return controller;
      });

  /// Takes server-side changes into the fields nobody is editing.
  ///
  /// Run from a `ref.listen` rather than from the build, which is how the
  /// item editor does it and is load-bearing rather than stylistic:
  /// writing a controller notifies, and the notify calls `setState`.
  /// Flutter permits that only while the element being dirtied is the one
  /// currently building - true today because the body is a method on this
  /// State, and false the moment it becomes a widget of its own, which is
  /// the obvious next refactor for a form this size.
  void _adoptStored(AlbumDetail album) {
    for (final field in AlbumIdentityField.values) {
      final controller = _controllers[field.wire];
      if (controller == null) continue;
      final stored = albumIdentityValue(album, field);
      if (controller.text == stored) {
        _seeded[field.wire] = stored;
        continue;
      }
      // Typed in since it was seeded: that edit outranks a refetch.
      if (controller.text != _seeded[field.wire]) continue;
      _seeded[field.wire] = stored;
      controller.text = stored;
    }
  }

  /// Only the fields that differ from what is stored. The endpoint takes
  /// a sparse map and locks what it is sent, so sending every field would
  /// lock five of them on a one-word change.
  Map<String, String> _changed(AlbumDetail album) {
    final changed = <String, String>{};
    for (final field in AlbumIdentityField.values) {
      final controller = _controllers[field.wire];
      if (controller == null) continue;
      final stored = albumIdentityValue(album, field);
      if (controller.text != stored) changed[field.wire] = controller.text;
    }
    return changed;
  }

  @override
  Widget build(BuildContext context) {
    // On the screen, not only on the menu row that opens it: this
    // location is shareable and the web build puts it in the path, so a
    // member following a pasted link would otherwise get a form whose
    // every Save answers 403. The entity-edit endpoint is
    // administrators-only, so this is the same rule stated where it
    // cannot be walked around.
    final isAdmin =
        ref
            .watch(authControllerProvider)
            .value
            ?.user
            ?.roles
            .contains('admin') ??
        false;
    final l10n = context.l10n;
    if (!isAdmin) {
      return WaxScaffold(
        title: l10n.musicAlbumTitle,
        largeTitle: false,
        onBack: () => context.leave(fallback: WaxRoute.music),
        slivers: <Widget>[
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: l10n.musicAlbumEditorForbiddenTitle,
              message: l10n.musicAlbumEditorForbiddenMessage,
              glyph: WaxIcons.edit,
            ),
          ),
        ],
      );
    }
    final async = ref.watch(albumDetailProvider(widget.pid));
    ref.listen(albumDetailProvider(widget.pid), (previous, next) {
      if (next.value case final album?) _adoptStored(album);
    });
    return WaxScaffold(
      title: async.value?.title ?? l10n.musicAlbumTitle,
      largeTitle: false,
      onBack: () => context.leave(fallback: WaxRoute.music),
      slivers: <Widget>[
        switch (async) {
          AsyncData(:final value) => SliverToBoxAdapter(child: _body(value)),
          AsyncError(:final error) => SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(
              title: l10n.musicAlbumLoadError,
              message: context.explain(error),
              onRetry: () => ref.invalidate(albumDetailProvider(widget.pid)),
            ),
          ),
          _ => const SliverFillRemaining(
            hasScrollBody: false,
            child: SkeletonShapes(shape: SkeletonShape.list),
          ),
        },
      ],
    );
  }

  Widget _body(AlbumDetail album) {
    final l10n = context.l10n;
    final curation = ref.watch(albumCurationProvider(widget.pid)).value ?? {};
    final changed = _changed(album);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: SemanticsIds.albumEditor,
      child: Padding(
        padding: WaxSizeClass.of(context).gutter,
        child: ReadingColumn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SectionHeader(
                title: l10n.musicAlbumEditorSectionTitle,
                overline: l10n.musicAlbumEditorSectionOverline,
              ),
              for (final field in AlbumIdentityField.values) ...<Widget>[
                _FieldRow(
                  field: field,
                  controller: _controllerFor(
                    field.wire,
                    albumIdentityValue(album, field),
                  ),
                  curated: curation[field.wire],
                  dirty: changed.containsKey(field.wire),
                ),
                const SizedBox(height: WaxSpace.s12),
              ],
              const SizedBox(height: WaxSpace.s16),
              // The item editor's own switches, down to the semantics
              // identifiers, so they read its keys. Only the write-back
              // help differs.
              WaxSettingRow(
                title: l10n.metadataWriteBackTitle,
                help: l10n.musicAlbumEditorWriteBackHelp,
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
                    : l10n.musicAlbumEditorSaveChanges(changed.length),
                icon: WaxIcons.check,
                semanticsId: SemanticsIds.metadataSave,
                onPressed: changed.isEmpty || _busy
                    ? null
                    : () => _save(changed),
              ),
              const SizedBox(height: WaxSpace.s32),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save(Map<String, String> changed) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ref.read(shellMessengerProvider.notifier);
    final l10n = context.l10n;
    try {
      await ref
          .read(repositoryProvider)
          .editEntity(
            'album',
            widget.pid,
            edits: changed,
            writeBack: _writeBack,
            lock: _lock,
            force: _force,
          );
      // What was sent stops counting as typed-in, which is what lets the
      // refetch below adopt it. Load-bearing where the server
      // normalizes: type `0-36000-29145-2` and the stored value comes
      // back `036000291452`, so text, stored, and the pre-save seed are
      // three different strings - and the adopt rule reads that as an
      // edit in flight and refuses to touch it. The field would then
      // read dirty for ever, with Save re-sending the same un-normalized
      // string on every press.
      for (final field in changed.keys) {
        _seeded[field] = changed[field]!;
      }
      ref
        ..invalidate(albumDetailProvider(widget.pid))
        ..invalidate(albumCurationProvider(widget.pid));
      messenger.show(l10n.musicAlbumEditorSaved);
    } on WaxDeckApiException catch (e) {
      // A locked field keeps the server's sentence, which names the
      // field, and gains the half the server cannot know: the switch on
      // this page that overrides it.
      messenger.show(
        e.code == 'field-locked'
            ? '${e.message}. ${l10n.metadataFieldLockedHint}'
            : explainRefusal(l10n, e),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.field,
    required this.controller,
    required this.curated,
    required this.dirty,
  });

  final AlbumIdentityField field;
  final TextEditingController controller;

  /// The curation row, when a user has already set this field. Its lock
  /// is what Force overrides.
  final EntityCuratedField? curated;

  final bool dirty;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final row = curated;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: WaxTextField(
            label: field.labelOf(l10n),
            hint: field.helpOf(l10n),
            controller: controller,
            semanticsId: SemanticsIds.metadataField(field.wire),
          ),
        ),
        const SizedBox(width: WaxSpace.s8),
        Padding(
          padding: const EdgeInsets.only(bottom: WaxSpace.s8),
          child: Row(
            children: <Widget>[
              CodecChip(
                row == null ? l10n.musicAlbumEditorFromTags : row.source,
                emphasis: dirty,
              ),
              // Read-only: the lock is set by the save below (through
              // "Lock edited fields") and cleared by Force, so a toggle
              // here would be a third way to say the same thing.
              if (row?.locked ?? false)
                Padding(
                  padding: const EdgeInsets.only(left: WaxSpace.s4),
                  child: WaxIcon(
                    WaxIcons.bookmark,
                    size: 16,
                    color: colors.accent,
                    active: true,
                    semanticLabel: l10n.musicAlbumEditorFieldLocked(
                      field.labelOf(l10n),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
