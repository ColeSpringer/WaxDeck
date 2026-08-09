import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../auth/auth_controller.dart';
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
    for (final field in albumIdentityFields) {
      final controller = _controllers[field.name];
      if (controller == null) continue;
      final stored = albumIdentityValue(album, field.name);
      if (controller.text == stored) {
        _seeded[field.name] = stored;
        continue;
      }
      // Typed in since it was seeded: that edit outranks a refetch.
      if (controller.text != _seeded[field.name]) continue;
      _seeded[field.name] = stored;
      controller.text = stored;
    }
  }

  /// Only the fields that differ from what is stored. The endpoint takes
  /// a sparse map and locks what it is sent, so sending every field would
  /// lock five of them on a one-word change.
  Map<String, String> _changed(AlbumDetail album) {
    final changed = <String, String>{};
    for (final field in albumIdentityFields) {
      final controller = _controllers[field.name];
      if (controller == null) continue;
      final stored = albumIdentityValue(album, field.name);
      if (controller.text != stored) changed[field.name] = controller.text;
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
    if (!isAdmin) {
      return WaxScaffold(
        title: 'Album',
        largeTitle: false,
        onBack: () => context.leave(fallback: WaxRoute.music),
        slivers: <Widget>[
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: 'Only administrators can edit a release',
              message:
                  'Barcodes, labels, and catalog numbers are shared by '
                  'everyone who can see this album, so the server keeps '
                  'them to administrators.',
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
      title: async.value?.title ?? 'Album',
      largeTitle: false,
      onBack: () => context.leave(fallback: WaxRoute.music),
      slivers: <Widget>[
        switch (async) {
          AsyncData(:final value) => SliverToBoxAdapter(child: _body(value)),
          AsyncError(:final error) => SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(
              title: 'Could not load this album',
              message: error is WaxDeckApiException
                  ? error.message
                  : 'The server did not answer.',
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
              const SectionHeader(
                title: 'Release identity',
                overline: 'What this edition is',
              ),
              for (final field in albumIdentityFields) ...<Widget>[
                _FieldRow(
                  field: field,
                  controller: _controllerFor(
                    field.name,
                    albumIdentityValue(album, field.name),
                  ),
                  curated: curation[field.name],
                  dirty: changed.containsKey(field.name),
                ),
                const SizedBox(height: WaxSpace.s12),
              ],
              const SizedBox(height: WaxSpace.s16),
              WaxSettingRow(
                title: 'Write tags to files',
                help:
                    'Also rewrite the matching tags in every track on this '
                    'release. Media has no tag form and stays here.',
                control: WaxSwitch(
                  label: 'Write tags to files',
                  value: _writeBack,
                  semanticsId: SemanticsIds.metadataWriteback,
                  onChanged: (v) => setState(() => _writeBack = v),
                ),
              ),
              WaxSettingRow(
                title: 'Lock edited fields',
                help:
                    'Keep scans and enrichment from overwriting what you type',
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
      messenger.show('Saved');
    } on WaxDeckApiException catch (e) {
      // The two refusals worth naming: a locked field wants Force, and a
      // barcode or country the normalizer would not take says so itself,
      // because a scan can store a value this endpoint refuses.
      final hint = e.statusCode == 409
          ? ' Check "Force" to overwrite locked fields.'
          : '';
      messenger.show('${e.message}.$hint');
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

  final ({String name, String label, String help}) field;
  final TextEditingController controller;

  /// The curation row, when a user has already set this field. Its lock
  /// is what Force overrides.
  final EntityCuratedField? curated;

  final bool dirty;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final row = curated;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: WaxTextField(
            label: field.label,
            hint: field.help,
            controller: controller,
            semanticsId: SemanticsIds.metadataField(field.name),
          ),
        ),
        const SizedBox(width: WaxSpace.s8),
        Padding(
          padding: const EdgeInsets.only(bottom: WaxSpace.s8),
          child: Row(
            children: <Widget>[
              CodecChip(
                row == null ? 'From tags' : row.source,
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
                    semanticLabel: '${field.label} is locked',
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
