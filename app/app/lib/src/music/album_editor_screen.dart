import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/art_source_mark.dart';
import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../metadata/artwork_manager.dart';
import '../providers.dart';
import '../shell/forbidden_page.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'album_detail.dart';
import 'entity_facts.dart';
import 'music_controllers.dart';

/// The album-entity editor, reached from an album's overflow and served
/// at `/metadata/<al-...>`.
///
/// A screen of its own rather than a panel inside the item editor, which
/// is what the same location serves for a track. The two write through
/// different endpoints with independent failure, so one Save button over
/// both would report success for a pair of calls of which one failed;
/// and the pid already says which is meant.
///
/// It shows the release before it offers to change it: the cover, the
/// title, and what is on it. An editor whose only content is seven text
/// fields makes the person using it hold the album in their head, and
/// the fields here are exactly the ones nobody remembers the value of.
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

  /// Every editable field, as the two things the form's bookkeeping
  /// needs: the name the endpoint takes it under, and what the album
  /// currently holds there. The labels live on the enums, which is
  /// where the rows that draw them read them from.
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
      return ForbiddenPage(
        pageTitle: l10n.musicAlbumTitle,
        heading: l10n.musicAlbumEditorForbiddenTitle,
        message: l10n.musicAlbumEditorForbiddenMessage,
        glyph: WaxIcons.edit,
        fallback: WaxRoute.music,
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
          // Value first here, which is the opposite of the order the
          // hubs use behind AsyncSliverFace, and deliberately: a hub
          // showing rows that failed to reload may be showing something
          // wrong, so it says so - but this form holds typing nobody
          // else has a copy of, and replacing it with an error card
          // over a refetch that failed would throw that away. The
          // failure still reaches the person through the save.
          AsyncValue(value: final album?) => SliverToBoxAdapter(
            child: _body(album),
          ),
          AsyncValue(hasError: true, error: final Object error) =>
            SliverFillRemaining(
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
              _AlbumSummary(pid: widget.pid, album: album),
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
                // Read off the identity the screen already has: a
                // release resolves a cover whenever anything answered
                // for it, its own or a member track's, and that is
                // exactly what makes the front tile draw a picture
                // rather than a monogram.
                hasArtwork: album.artSource != null,
                entityType: 'album',
                writeBack: _writeBack,
                // The summary above draws this album's resolved cover
                // and its source mark from the detail read, which the
                // grid knows nothing about: without this, clearing a
                // cover leaves the mark describing a picture that is
                // gone until the screen is left and re-entered.
                onChanged: () =>
                    ref.invalidate(albumDetailProvider(widget.pid)),
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
                  padding: const EdgeInsets.only(left: WaxSpace.s4),
                  child: WaxIcon(
                    WaxIcons.bookmark,
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
