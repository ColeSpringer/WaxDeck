import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/art_source_label.dart';
import '../artwork/artwork_providers.dart';
import '../l10n/l10n.dart';
import '../music/album_detail.dart' show retryUnlessRefused;
import '../music/music_controllers.dart';
import '../providers.dart';
import '../settings/settings_registry.dart';
import '../shell/forbidden_page.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'artwork_manager.dart';
import 'rename_section.dart';

/// The two catalog entities editable at their own location beside the
/// release: an artist and a release group. One screen, because their
/// forms differ only in the field list and whether a value fans out to
/// files - an artist's sort is written into member tags on request,
/// while everything on a release group is a database-only override.
enum EditableEntity {
  artist('artist', MusicDimension.artists),
  releaseGroup('release-group', MusicDimension.releaseGroups);

  const EditableEntity(this.wire, this.dimension);

  /// The entity type the edit endpoints take.
  final String wire;

  /// The browse dimension whose bucket read names this entity: an
  /// entity has no detail read, so the name comes off its own items.
  final MusicDimension dimension;

  List<String> get fields => switch (this) {
    artist => const ['sort', 'mbid'],
    releaseGroup => const ['sort', 'mbid', 'type'],
  };

  /// The keying fields the rename verb takes for this rung. They live
  /// on the member tracks rather than on the entity, which is why they
  /// are not in [fields]: moving them moves the entity's identity, and
  /// only the rename endpoint can do that without splitting it.
  List<String> get renameFields => switch (this) {
    artist => const ['name'],
    releaseGroup => const ['album', 'album_artist'],
  };
}

/// The release-group types the server accepts, plus the empty choice
/// that clears the override. Mirrored from the catalog's own list the
/// way the episode types are: the closed set is the contract.
const kReleaseGroupTypes = [
  '',
  'album',
  'ep',
  'single',
  'compilation',
  'audiobook',
];

/// The curated overrides on one entity, keyed by field name. Only
/// non-default fields have rows, so an empty map is an entity nobody
/// has curated - which is what the empty inputs honestly say.
final entityCurationProvider = FutureProvider.autoDispose
    .family<Map<String, EntityCuratedField>, ({String type, String pid})>((
      ref,
      key,
    ) async {
      final rows = await ref
          .watch(repositoryProvider)
          .getEntityCuration(key.type, key.pid);
      return <String, EntityCuratedField>{
        for (final row in rows) row.field: row,
      };
    }, retry: retryUnlessRefused);

/// The entity's display name off one member item. An entity has no
/// detail read, and the bucket listing pages at the queue cap - five
/// hundred items is a lot to hold for a title bar - so this asks for
/// exactly one.
final _entityNameProvider = FutureProvider.autoDispose
    .family<String?, ({EditableEntity entity, String pid})>((ref, key) async {
      final page = await ref
          .watch(repositoryProvider)
          .listItems(
            facet: key.entity.dimension.wireName,
            facetKey: musicFacetKey(key.entity.dimension, key.pid),
            limit: 1,
          );
      final first = page.items.firstOrNull;
      return switch (key.entity) {
        EditableEntity.artist => first?.artist,
        EditableEntity.releaseGroup => first?.album,
      };
    }, retry: retryUnlessRefused);

/// The keying values the rename inputs start from, read off one member
/// the way the album pane's rewrite section reads them. An entity has
/// no detail read, and the values agree across members by construction
/// - they are the key the entity groups on - so one member answers.
final _renameSeedProvider = FutureProvider.autoDispose
    .family<Map<String, String>, ({EditableEntity entity, String pid})>((
      ref,
      key,
    ) async {
      final repo = ref.watch(repositoryProvider);
      final page = await repo.listItems(
        facet: key.entity.dimension.wireName,
        facetKey: musicFacetKey(key.entity.dimension, key.pid),
        limit: 1,
      );
      final first = page.items.firstOrNull;
      if (first == null) return const {};
      // A release group's two keying fields are item fields, so they
      // come off the metadata read and seed the inputs directly.
      if (key.entity == EditableEntity.releaseGroup) {
        final metadata = await repo.getItemMetadata(first.pid);
        return {
          for (final field in key.entity.renameFields)
            field: metadata.fields[field] ?? '',
        };
      }
      // An artist's is not. A member's `artist` is its display credit -
      // the raw ARTIST string - which on a collaboration names several
      // people, and this entity is only one of them. Seeding the box
      // with it would offer a curator the wrong baseline to edit, and
      // the rename applies with force, so a typo fix would move the
      // whole artist onto a name that was never its own. Left empty:
      // the rename states the new name outright, and every keystroke
      // is a deliberate change rather than a diff against a guess.
      return const {'name': ''};
    }, retry: retryUnlessRefused);

/// The artist and release-group editors, deep-linkable at
/// `/metadata/<ar-...>` and `/metadata/<rg-...>`. Administrators only,
/// like every entity edit: the values are shared by everyone who can
/// see the entity.
class EntityEditorScreen extends ConsumerStatefulWidget {
  const EntityEditorScreen({
    super.key,
    required this.entity,
    required this.pid,
  });

  final EditableEntity entity;
  final String pid;

  @override
  ConsumerState<EntityEditorScreen> createState() => _EntityEditorScreenState();
}

class _EntityEditorScreenState extends ConsumerState<EntityEditorScreen> {
  final _controllers = <String, TextEditingController>{};

  /// What each controller was last seeded with from the server; a
  /// controller still holding exactly this has not been typed in since,
  /// which is what makes it safe to adopt a fresh value into.
  final _seeded = <String, String>{};

  /// The type choice, staged apart from the text fields: a closed
  /// control has no controller. Null until touched; the empty string is
  /// the explicit "not set" choice, which clears the override.
  String? _typeStaged;

  /// What the choice was last seeded with from the server; null until
  /// the first curation read lands. The control draws staged over
  /// seeded - never the possibly-stale curation map - so a save does
  /// not snap the picker back to the old value while the refetch is in
  /// flight.
  String? _typeSeeded;

  var _writeBack = false;
  var _lock = true;
  var _force = false;
  var _busy = false;

  ({String type, String pid}) get _curationKey =>
      (type: widget.entity.wire, pid: widget.pid);

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

  static String _storedOf(
    Map<String, EntityCuratedField> curation,
    String field,
  ) => curation[field]?.value ?? '';

  /// Takes server-side changes into the fields nobody is editing, on
  /// the album pane's rule: a typed edit outranks a refetch.
  void _adoptStored(Map<String, EntityCuratedField> curation) {
    for (final field in widget.entity.fields) {
      if (field == 'type') {
        final stored = _storedOf(curation, field);
        if (_typeStaged == null || _typeStaged == _typeSeeded) {
          _typeStaged = null;
        }
        _typeSeeded = stored;
        continue;
      }
      final controller = _controllers[field];
      if (controller == null) continue;
      final stored = _storedOf(curation, field);
      if (controller.text == stored) {
        _seeded[field] = stored;
        continue;
      }
      if (controller.text != _seeded[field]) continue;
      _seeded[field] = stored;
      controller.text = stored;
    }
  }

  /// Only the fields that differ from what is stored: the endpoint
  /// takes a sparse map and locks what it is sent.
  Map<String, String> _changed(Map<String, EntityCuratedField> curation) {
    final changed = <String, String>{};
    for (final field in widget.entity.fields) {
      if (field == 'type') {
        final staged = _typeStaged;
        if (staged != null && staged != _storedOf(curation, field)) {
          changed[field] = staged;
        }
        continue;
      }
      final controller = _controllers[field];
      if (controller == null) continue;
      if (controller.text != _storedOf(curation, field)) {
        changed[field] = controller.text;
      }
    }
    return changed;
  }

  Future<void> _save(Map<String, String> changed) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ref.read(shellMessengerProvider.notifier);
    final l10n = context.l10n;
    try {
      final result = await ref
          .read(repositoryProvider)
          .editEntity(
            widget.entity.wire,
            widget.pid,
            edits: changed,
            writeBack: widget.entity == EditableEntity.artist && _writeBack,
            lock: _lock,
            force: _force,
          );
      // Guarded like the artwork manager beside it: the save may land
      // while this screen is being left, and invalidating through a
      // disposed ref throws past the catch below, which only knows the
      // server's refusals.
      if (!mounted) return;
      // What was sent stops counting as typed-in, so the refetch below
      // may adopt the stored (possibly normalized) echo.
      for (final field in changed.keys) {
        if (field == 'type') {
          _typeSeeded = changed[field]!;
          _typeStaged = null;
        } else {
          _seeded[field] = changed[field]!;
        }
      }
      ref.invalidate(entityCurationProvider(_curationKey));
      messenger.show(l10n.musicAlbumEditorSaved);
      // An mbid clear is the one edit that can re-key the entity onto a
      // heuristic twin, which deletes this pid. Follow the survivor
      // rather than leaving the screen on a row that is gone.
      if (result.mergedInto case final survivor?) {
        context.replace(WaxRoute.metadata(survivor));
      }
    } on WaxDeckApiException catch (e) {
      if (mounted) {
        messenger.show(
          e.code == 'field-locked'
              ? '${e.message}. ${l10n.metadataFieldLockedHint}'
              : explainRefusal(l10n, e),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The rename section: the values that key the entity, which the
  /// edit endpoint above cannot take because they live on the members.
  Widget _renameSection() {
    final l10n = context.l10n;
    final seedKey = (entity: widget.entity, pid: widget.pid);
    final artist = widget.entity == EditableEntity.artist;
    return EntityRenameSection(
      entityType: widget.entity.wire,
      pid: widget.pid,
      fields: widget.entity.renameFields,
      seed: ref.watch(_renameSeedProvider(seedKey)),
      onRetrySeed: () => ref.invalidate(_renameSeedProvider(seedKey)),
      copy: RenameSectionCopy(
        title: l10n.musicEntityRenameTitle,
        overline: l10n.musicEntityRenameOverline,
        help: artist
            ? l10n.musicEntityRenameArtistHelp
            : l10n.musicEntityRenameGroupHelp,
        applyLabel: l10n.musicEntityRenameApply,
        confirmTitle: l10n.musicEntityRenameConfirmTitle,
        confirmBody: l10n.musicEntityRenameConfirmBody,
        merged: l10n.musicEntityRenameMerged,
        renamed: l10n.musicEntityRenameDone,
      ),
      ids: RenameSectionIds(
        field: SemanticsIds.entityRenameField,
        writeBack: SemanticsIds.entityRenameWriteBack,
        apply: SemanticsIds.entityRenameApply,
        confirm: SemanticsIds.entityRenameConfirm,
      ),
      busy: _busy,
      onBusyChanged: (busy) => setState(() => _busy = busy),
      onMerged: (survivor) => context.replace(WaxRoute.metadata(survivor)),
      onRenamed: () => ref
        ..invalidate(entityCurationProvider(_curationKey))
        ..invalidate(_entityNameProvider(seedKey)),
    );
  }

  String _labelOf(AppLocalizations l10n, String field) => switch (field) {
    'sort' => l10n.musicFieldSort,
    'mbid' =>
      widget.entity == EditableEntity.artist
          ? l10n.musicFieldArtistMbid
          : l10n.musicFieldReleaseGroupMbid,
    'type' => l10n.musicFieldReleaseGroupType,
    _ => field,
  };

  String _helpOf(AppLocalizations l10n, String field) => switch (field) {
    'sort' =>
      widget.entity == EditableEntity.artist
          ? l10n.musicFieldArtistSortHelp
          : l10n.musicFieldReleaseGroupSortHelp,
    'mbid' =>
      widget.entity == EditableEntity.artist
          ? l10n.musicFieldArtistMbidHelp
          : l10n.musicFieldReleaseGroupMbidHelp,
    'type' => l10n.musicFieldReleaseGroupTypeHelp,
    _ => '',
  };

  String _typeLabelOf(AppLocalizations l10n, String value) => switch (value) {
    'album' => l10n.musicReleaseGroupTypeAlbum,
    'ep' => l10n.musicReleaseGroupTypeEp,
    'single' => l10n.musicReleaseGroupTypeSingle,
    'compilation' => l10n.musicReleaseGroupTypeCompilation,
    'audiobook' => l10n.musicReleaseGroupTypeAudiobook,
    _ => l10n.musicReleaseGroupTypeUnset,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // On the screen, not only on the doors that open it: the location
    // is shareable, and every save behind it is administrators-only.
    if (!ref.watch(isAdminProvider)) {
      return ForbiddenPage(
        pageTitle: l10n.metadataTitle,
        heading: l10n.metadataForbiddenTitle,
        message: l10n.metadataForbiddenMessage,
        glyph: WaxIcons.edit,
        fallback: WaxRoute.music,
        semanticsId: SemanticsIds.metadataForbidden,
      );
    }
    final curation = ref.watch(entityCurationProvider(_curationKey));
    ref.listen(entityCurationProvider(_curationKey), (previous, next) {
      if (next.value case final rows?) setState(() => _adoptStored(rows));
    });
    // One member item names the entity; a read still loading names
    // the screen after the editor instead of blanking the title.
    final name = ref
        .watch(_entityNameProvider((entity: widget.entity, pid: widget.pid)))
        .value;
    return WaxScaffold(
      title: name ?? l10n.metadataTitle,
      largeTitle: false,
      semanticsId: SemanticsIds.entityEditor,
      onBack: () => context.leave(fallback: WaxRoute.music),
      body: switch (curation) {
        // Value first, like the album pane: the form holds typing
        // nobody else has a copy of, and the failure of a refetch still
        // reaches the person through the save.
        AsyncValue(value: final rows?) => SingleChildScrollView(
          padding: const EdgeInsets.all(WaxSpace.s16),
          child: _body(rows, name),
        ),
        AsyncValue(hasError: true, error: final Object error) => Padding(
          padding: const EdgeInsets.all(WaxSpace.s16),
          child: ErrorState(
            title: l10n.metadataLoadError,
            message: context.explain(error),
            onRetry: () => ref.invalidate(entityCurationProvider(_curationKey)),
          ),
        ),
        _ => const SkeletonShapes(shape: SkeletonShape.list),
      },
    );
  }

  Widget _body(Map<String, EntityCuratedField> curation, String? name) {
    final l10n = context.l10n;
    // Seeded at first sight of the curation map, the way the text
    // controllers seed at creation, so the choice never has to read
    // the possibly-stale map to draw itself.
    _typeSeeded ??= _storedOf(curation, 'type');
    final changed = _changed(curation);
    final artist = widget.entity == EditableEntity.artist;
    return ReadingColumn(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // The cover, for the one entity whose picture is its own: a
          // release group draws its releases' art and manages nothing
          // here.
          if (artist) ...<Widget>[
            ArtworkManager(
              pid: widget.pid,
              title: name ?? widget.pid,
              hasArtwork:
                  ref
                      .watch(itemArtRolesProvider(widget.pid))
                      .value
                      ?.artSource !=
                  null,
              entityType: widget.entity.wire,
            ),
            const SizedBox(height: WaxSpace.s24),
          ],
          SectionHeader(
            title: l10n.musicAlbumEditorNamesTitle,
            overline: l10n.musicAlbumEditorNamesOverline,
          ),
          for (final field in widget.entity.fields) ...<Widget>[
            if (field == 'type')
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  WaxChoice<String>(
                    label: _labelOf(l10n, field),
                    // Staged over seeded, never the curation map: after
                    // a save the seed already holds what was sent, so
                    // the picker keeps it while the refetch is in
                    // flight instead of snapping to the stale value.
                    value: _typeStaged ?? _typeSeeded ?? '',
                    semanticsId: SemanticsIds.metadataField(field),
                    options: kReleaseGroupTypes,
                    labelFor: (value) => _typeLabelOf(l10n, value),
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _typeStaged = v),
                  ),
                  const SizedBox(height: WaxSpace.s4),
                  Text(
                    _helpOf(l10n, field),
                    style: WaxType.caption.copyWith(
                      color: WaxColors.of(context).textSecondary,
                    ),
                  ),
                ],
              )
            else
              _EntityFieldRow(
                label: _labelOf(l10n, field),
                help: _helpOf(l10n, field),
                wire: field,
                controller: _controllerFor(field, _storedOf(curation, field)),
                curated: curation[field],
                dirty: changed.containsKey(field),
              ),
            const SizedBox(height: WaxSpace.s12),
          ],
          const SizedBox(height: WaxSpace.s12),
          // The item editor's own switches, down to the semantics
          // identifiers. Write-back only where a value has files to
          // reach: an artist's sort fans out to member tags, a release
          // group's fields are database-only by upstream design.
          if (artist)
            WaxSettingRow(
              title: l10n.metadataWriteBackTitle,
              help: l10n.musicFieldArtistWriteBackHelp,
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
            onPressed: changed.isEmpty || _busy ? null : () => _save(changed),
          ),
          const SizedBox(height: WaxSpace.s24),
          _renameSection(),
          const SizedBox(height: WaxSpace.s32),
        ],
      ),
    );
  }
}

/// One entity field with its curation marks: the album pane's row, for
/// the two entities that have no pane.
class _EntityFieldRow extends StatelessWidget {
  const _EntityFieldRow({
    required this.label,
    required this.help,
    required this.wire,
    required this.controller,
    required this.curated,
    required this.dirty,
  });

  final String label;
  final String help;
  final String wire;
  final TextEditingController controller;

  /// The curation row, when someone has already set this field. Its
  /// lock is what Force overrides.
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
            label: label,
            hint: help,
            controller: controller,
            semanticsId: SemanticsIds.metadataField(wire),
          ),
        ),
        const SizedBox(width: WaxSpace.s8),
        Padding(
          padding: const EdgeInsets.only(bottom: WaxSpace.s8),
          child: Row(
            children: <Widget>[
              CodecChip(
                row == null
                    ? l10n.metadataSourceUnknown
                    : provenanceProducerName(l10n, row.source),
                emphasis: dirty,
              ),
              if (row?.locked ?? false)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: WaxSpace.s4),
                  child: WaxIcon(
                    WaxIcons.lock,
                    size: 16,
                    color: colors.accent,
                    active: true,
                    semanticLabel: l10n.musicAlbumEditorFieldLocked(label),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
