import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/art_source_label.dart';
import '../l10n/l10n.dart';
import '../music/album_detail.dart';
import '../music/entity_facts.dart';
import '../music/music_controllers.dart';
import '../providers.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'artwork_manager.dart';
import 'rename_section.dart';

/// The fields whose values key a release. Editing any of them moves the
/// members to a new release identity, and where they land depends on
/// coverage: this section edits every member at once, which renames the
/// album in place and keeps its pid, while a partial batch would fork
/// the edited members onto a fresh one - the server's own behavior,
/// pinned by `TestBulkEditAlbumFieldsRenamesInPlaceOnFullCoverage` and
/// `...RegroupsOnPartialCoverage`. The rewrite section still warns
/// before it writes, because a rename onto a name another release owns
/// merges the two, and the workbench still follows the pid the response
/// reports.
const albumRewriteFields = ['album', 'album_artist', 'year'];

/// The release-keying fields as the first member's tags carry them,
/// which is what the rewrite section seeds its inputs with. The three
/// agree across members by construction - they are the key the release
/// groups on - so one read answers for the album without walking it.
final _rewriteSeedProvider = FutureProvider.autoDispose
    .family<Map<String, String>, String>((ref, albumPid) async {
      final members = await ref.watch(
        musicItemsProvider((
          dimension: MusicDimension.albums,
          segment: albumPid,
        )).future,
      );
      final first = albumOrder(members.items).firstOrNull;
      if (first == null) return const {};
      final metadata = await ref
          .watch(repositoryProvider)
          .getItemMetadata(first.pid);
      return {
        for (final field in albumRewriteFields)
          field: metadata.fields[field] ?? '',
      };
    });

/// The album half of the release workbench: what the album editor
/// screen used to be, as a pane. The release before the form - the
/// cover, the title, and what is on it - then the entity's own fields,
/// and last the rewrite section for the three values that live on the
/// tracks.
///
/// The entity fields and the track rewrite keep separate Save buttons
/// deliberately: they write through different endpoints with
/// independent failure, and one button over both would report success
/// for a pair of calls of which one failed.
class AlbumPane extends ConsumerStatefulWidget {
  const AlbumPane({
    super.key,
    required this.pid,
    required this.onRegrouped,
    this.onDirtyChanged,
  });

  final String pid;

  /// Where the host takes the workbench once a rewrite regroups the
  /// members: the album pid they landed on. The host owns the move
  /// because a pane in a sheet has a sheet to close first.
  final void Function(String newPid) onRegrouped;

  /// Reports whether either form on this pane holds anything unsaved,
  /// so a host that replaces the pane can ask before it discards
  /// typing. Fired on the edges only.
  final ValueChanged<bool>? onDirtyChanged;

  @override
  ConsumerState<AlbumPane> createState() => _AlbumPaneState();
}

class _AlbumPaneState extends ConsumerState<AlbumPane> {
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

  /// Whether the rename section below holds anything unsaved. It owns
  /// its own inputs; this is the half of the pane's dirtiness it
  /// reports up.
  var _rewriteDirty = false;

  /// Every editable entity field, as the two things the form's
  /// bookkeeping needs: the name the endpoint takes it under, and what
  /// the album currently holds there.
  Iterable<({String wire, String Function(AlbumDetail) stored})>
  get _fields sync* {
    for (final field in AlbumNameField.values) {
      yield (wire: field.wire, stored: (a) => albumNameValue(a, field));
    }
    for (final field in AlbumIdentityField.values) {
      yield (wire: field.wire, stored: (a) => albumIdentityValue(a, field));
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// The dirtiness last reported, so [AlbumPane.onDirtyChanged] fires
  /// on the edges rather than on every keystroke.
  var _reportedDirty = false;

  void _reportDirty() {
    final onDirty = widget.onDirtyChanged;
    if (onDirty == null) return;
    final album = ref.read(albumDetailProvider(widget.pid)).value;
    final dirty =
        (album != null && _changed(album).isNotEmpty) || _rewriteDirty;
    if (dirty != _reportedDirty) {
      _reportedDirty = dirty;
      onDirty(dirty);
    }
  }

  TextEditingController _controllerFor(String field, String initial) =>
      _controllers.putIfAbsent(field, () {
        _seeded[field] = initial;
        final controller = TextEditingController(text: initial);
        controller.addListener(() {
          setState(() {});
          _reportDirty();
        });
        return controller;
      });

  /// Takes server-side changes into the fields nobody is editing.
  ///
  /// Run from a `ref.listen` rather than from the build, which is how the
  /// item editor does it and is load-bearing rather than stylistic:
  /// writing a controller notifies, and the notify calls `setState`.
  /// Flutter permits that only while the element being dirtied is the one
  /// currently building, which a `listen` callback is not building at all.
  void _adoptStored(AlbumDetail album) {
    for (final field in _fields) {
      final controller = _controllers[field.wire];
      if (controller == null) continue;
      final stored = field.stored(album);
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
  /// lock seven of them on a one-word change.
  Map<String, String> _changed(AlbumDetail album) {
    final changed = <String, String>{};
    for (final field in _fields) {
      final controller = _controllers[field.wire];
      if (controller == null) continue;
      final stored = field.stored(album);
      if (controller.text != stored) changed[field.wire] = controller.text;
    }
    return changed;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final async = ref.watch(albumDetailProvider(widget.pid));
    ref.listen(albumDetailProvider(widget.pid), (previous, next) {
      if (next.value case final album?) _adoptStored(album);
    });
    return switch (async) {
      // Value first here, which is the opposite of the order the hubs
      // use behind AsyncSliverFace, and deliberately: this form holds
      // typing nobody else has a copy of, and replacing it with an
      // error card over a refetch that failed would throw that away.
      // The failure still reaches the person through the save.
      AsyncValue(value: final album?) => SingleChildScrollView(
        padding: const EdgeInsets.all(WaxSpace.s16),
        child: _body(album),
      ),
      AsyncValue(hasError: true, error: final Object error) => Padding(
        padding: const EdgeInsets.all(WaxSpace.s16),
        child: ErrorState(
          title: l10n.musicAlbumLoadError,
          message: context.explain(error),
          onRetry: () => ref.invalidate(albumDetailProvider(widget.pid)),
        ),
      ),
      _ => const SkeletonShapes(shape: SkeletonShape.list),
    };
  }

  Widget _body(AlbumDetail album) {
    final l10n = context.l10n;
    final curation = ref.watch(albumCurationProvider(widget.pid)).value ?? {};
    final changed = _changed(album);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: SemanticsIds.albumEditor,
      child: ReadingColumn(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _AlbumSummary(pid: widget.pid, album: album),
            // The release group's own editor, one hop up: sort, MBID,
            // and type live on the group rather than this edition, and
            // this pane is already administrators-only.
            if (album.releaseGroupPid case final rgPid?) ...<Widget>[
              const SizedBox(height: WaxSpace.s8),
              WaxPill(
                label: context.l10n.musicAlbumEditReleaseGroup,
                semanticsId: SemanticsIds.albumEditReleaseGroup,
                onPressed: () {
                  // On the compact workbench this pane is a bottom
                  // sheet; it closes before the push, or Back from the
                  // editor lands on the still-open sheet. The router is
                  // taken first because the pop unmounts this context.
                  final router = GoRouter.of(context);
                  if (ModalRoute.of(context) is PopupRoute) {
                    Navigator.of(context).pop();
                  }
                  unawaited(router.push<void>(WaxRoute.metadata(rgPid)));
                },
              ),
            ],
            const SizedBox(height: WaxSpace.s24),
            // The cover, through the same grid the item editor uses -
            // set, clear, the provenance mark, and the pin that
            // explains a release refusing every cover it is offered.
            // Write-back rides the switch below, so embedding a cover
            // into the member files is the same decision as embedding
            // a barcode.
            ArtworkManager(
              pid: widget.pid,
              title: album.title,
              // Read off the identity the pane already has: a release
              // resolves a cover whenever anything answered for it, its
              // own or a member track's.
              hasArtwork: album.artSource != null,
              entityType: 'album',
              writeBack: _writeBack,
              // The summary above draws this album's resolved cover
              // and its source mark from the detail read, which the
              // grid knows nothing about: without this, clearing a
              // cover leaves the mark describing a picture that is
              // gone until the pane is left and re-entered.
              onChanged: () => ref.invalidate(albumDetailProvider(widget.pid)),
            ),
            const SizedBox(height: WaxSpace.s24),
            _FieldSection(
              title: l10n.musicAlbumEditorNamesTitle,
              overline: l10n.musicAlbumEditorNamesOverline,
              semanticsId: SemanticsIds.albumEditorNames,
              children: <Widget>[
                for (final field in AlbumNameField.values)
                  _FieldRow(
                    label: field.labelOf(l10n),
                    help: field.helpOf(l10n),
                    wire: field.wire,
                    controller: _controllerFor(
                      field.wire,
                      albumNameValue(album, field),
                    ),
                    curated: curation[field.wire],
                    dirty: changed.containsKey(field.wire),
                  ),
              ],
            ),
            const SizedBox(height: WaxSpace.s24),
            _FieldSection(
              title: l10n.musicAlbumEditorSectionTitle,
              overline: l10n.musicAlbumEditorSectionOverline,
              children: <Widget>[
                for (final field in AlbumIdentityField.values)
                  _FieldRow(
                    label: field.labelOf(l10n),
                    help: field.helpOf(l10n),
                    wire: field.wire,
                    controller: _controllerFor(
                      field.wire,
                      albumIdentityValue(album, field),
                    ),
                    curated: curation[field.wire],
                    dirty: changed.containsKey(field.wire),
                  ),
                _DerivedTotalTracks(pid: widget.pid, album: album),
              ],
            ),
            const SizedBox(height: WaxSpace.s24),
            SectionHeader(
              title: l10n.musicAlbumEditorWriteTitle,
              overline: l10n.musicAlbumEditorWriteOverline,
            ),
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
              onPressed: changed.isEmpty || _busy ? null : () => _save(changed),
            ),
            const SizedBox(height: WaxSpace.s32),
            _rewriteSection(),
            const SizedBox(height: WaxSpace.s32),
          ],
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
      final result = await ref
          .read(repositoryProvider)
          .editEntity(
            'album',
            widget.pid,
            edits: changed,
            writeBack: _writeBack,
            lock: _lock,
            force: _force,
          );
      // The save may land while this pane is being left - a merge below
      // replaces the route, and the workbench can be popped under it.
      // Reading through a disposed ref throws past the catch, which
      // only knows the server's refusals.
      if (!mounted) return;
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
      _reportDirty();
      // An mbid clear is the one entity edit that can re-key the album
      // onto a heuristic twin, which deletes this pid: refetching it
      // would put an error state under a "Saved" toast. The host moves
      // the workbench instead, exactly as a merging rename does.
      if (result.mergedInto case final survivor?) {
        messenger.show(l10n.musicAlbumRewriteMerged);
        widget.onRegrouped(survivor);
        return;
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

  /// The three fields the album bug asked for and the entity edit
  /// endpoint cannot take: they live on the member tracks. The rename
  /// verb moves them on every member in one transaction, so the release
  /// keeps its row - a name another release owns is the one case that
  /// moves the page, and the confirm says so before it writes.
  Widget _rewriteSection() {
    final l10n = context.l10n;
    // The count the button shows is the release's own, not the loaded
    // page's: the rename covers every member whether or not the list
    // scrolled that far.
    final members =
        ref.watch(albumDetailProvider(widget.pid)).value?.itemCount ?? 0;
    final listing = (dimension: MusicDimension.albums, segment: widget.pid);
    return EntityRenameSection(
      entityType: 'album',
      pid: widget.pid,
      fields: albumRewriteFields,
      seed: ref.watch(_rewriteSeedProvider(widget.pid)),
      onRetrySeed: () => ref.invalidate(_rewriteSeedProvider(widget.pid)),
      copy: RenameSectionCopy(
        title: l10n.musicAlbumRewriteTitle,
        overline: l10n.musicAlbumRewriteOverline,
        help: l10n.musicAlbumRewriteHelp,
        applyLabel: l10n.musicAlbumRewriteApply(members),
        confirmTitle: l10n.musicAlbumRewriteConfirmTitle,
        confirmBody: l10n.musicAlbumRewriteConfirmBody,
        merged: l10n.musicAlbumRewriteMerged,
        renamed: l10n.musicAlbumRewriteRenamed,
      ),
      ids: RenameSectionIds(
        section: SemanticsIds.albumRewrite,
        field: SemanticsIds.albumRewriteField,
        writeBack: SemanticsIds.albumRewriteWriteBack,
        apply: SemanticsIds.albumRewriteApply,
        confirm: SemanticsIds.albumRewriteConfirm,
      ),
      busy: _busy,
      onBusyChanged: (busy) => setState(() => _busy = busy),
      canApply: members > 0,
      onDirtyChanged: (dirty) {
        _rewriteDirty = dirty;
        _reportDirty();
      },
      onMerged: widget.onRegrouped,
      onRenamed: () => ref
        ..invalidate(albumDetailProvider(widget.pid))
        ..invalidate(musicItemsProvider(listing)),
    );
  }
}

/// What is being edited: the title, what the catalog knows about the
/// release, and the tracks a write-back would reach.
///
/// The tracks are the point rather than decoration. "Also rewrite the
/// matching tags in every track on this release" is a sentence about
/// files nobody can see from here, and the count is what makes it a
/// decision instead of a leap.
class _AlbumSummary extends ConsumerWidget {
  const _AlbumSummary({required this.pid, required this.album});

  static const _maxTracks = 6;

  final String pid;
  final AlbumDetail album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final wax = context.waxL10n;
    final tracks = albumOrder(
      ref
              .watch(
                musicItemsProvider((
                  dimension: MusicDimension.albums,
                  segment: pid,
                )),
              )
              .value
              ?.items ??
          const <ItemSummary>[],
    );
    final duration = album.totalDurationMs;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: SemanticsIds.albumEditorTracks,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            album.title,
            style: WaxType.titleEntity.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: WaxSpace.s4),
          Text(
            // Joined here rather than in one ICU string, the way the
            // album header's own caption is: a release with no year and
            // no stored running time should read as a track count, not
            // as two empty separators.
            <String>[
              if (album.year != null) '${album.year}',
              l10n.musicTrackCount(album.itemCount ?? tracks.length),
              if (duration != null && duration > 0)
                formatRunningTime(wax, Duration(milliseconds: duration)),
            ].join(' · '),
            style: WaxType.caption.copyWith(color: colors.textSecondary),
          ),
          // The mark under the cover the release actually resolves. The
          // grid below reports each slot's own; this is the one the
          // album shows, borrow note included.
          if (artSourceLabelWithBorrow(l10n, album.artSource)
              case final source?) ...<Widget>[
            const SizedBox(height: WaxSpace.s4),
            Text(
              source,
              style: WaxType.caption.copyWith(color: colors.textTertiary),
            ),
          ],
          if (tracks.isNotEmpty) ...<Widget>[
            const SizedBox(height: WaxSpace.s16),
            SectionHeader(
              title: l10n.musicAlbumEditorTracksTitle,
              overline: l10n.musicAlbumEditorTracksOverline,
            ),
            for (final track in tracks.take(_maxTracks))
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WaxType.caption.copyWith(color: colors.textSecondary),
              ),
            if (tracks.length > _maxTracks)
              Text(
                l10n.musicAlbumEditorTracksMore(tracks.length - _maxTracks),
                style: WaxType.caption.copyWith(color: colors.textTertiary),
              ),
          ],
        ],
      ),
    );
  }
}

/// The one number the album bug asked to edit that is not a field:
/// total tracks is the release's membership counted, nothing stores
/// it, so the row says the number and why there is no input. Editing
/// the tracks is what changes it.
class _DerivedTotalTracks extends ConsumerWidget {
  const _DerivedTotalTracks({required this.pid, required this.album});

  final String pid;
  final AlbumDetail album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // The same fallback the summary above uses: the detail's own count
    // where the server sent one, the loaded member list otherwise.
    final count =
        album.itemCount ??
        ref
            .watch(
              musicItemsProvider((
                dimension: MusicDimension.albums,
                segment: pid,
              )),
            )
            .value
            ?.items
            .length ??
        0;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: SemanticsIds.albumEditorTotalTracks,
      child: WaxSettingRow(
        title: l10n.musicAlbumEditorTotalTracks,
        help: l10n.musicAlbumEditorTotalTracksHelp,
        control: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '$count',
              style: WaxType.monoData.copyWith(
                color: WaxColors.of(context).textPrimary,
              ),
            ),
            const SizedBox(width: WaxSpace.s8),
            CodecChip(l10n.metadataDerivedChip),
          ],
        ),
      ),
    );
  }
}

/// A titled run of fields. One wrapper, so the two groups sit at the
/// same rhythm as the artwork grid and the switches around them.
class _FieldSection extends StatelessWidget {
  const _FieldSection({
    required this.title,
    required this.overline,
    required this.children,
    this.semanticsId,
  });

  final String title;
  final String overline;
  final List<Widget> children;
  final String? semanticsId;

  @override
  Widget build(BuildContext context) {
    final section = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: title, overline: overline),
        for (final child in children) ...<Widget>[
          child,
          const SizedBox(height: WaxSpace.s12),
        ],
      ],
    );
    if (semanticsId == null) return section;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: semanticsId,
      child: section,
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.help,
    required this.wire,
    required this.controller,
    required this.curated,
    required this.dirty,
  });

  final String label;
  final String help;

  /// The endpoint's own name for the field, which is also the handle
  /// its input carries and the key its curation row is filed under.
  final String wire;

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
                row == null ? l10n.musicAlbumEditorFromTags : row.source,
                emphasis: dirty,
              ),
              // Read-only: the lock is set by the save below (through
              // "Lock edited fields") and cleared by Force, so a toggle
              // here would be a third way to say the same thing.
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
