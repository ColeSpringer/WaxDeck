import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import '../uploads/audio_drop_area.dart';
import '../uploads/file_picker_port.dart';

/// The image formats the artwork endpoints accept. The server sniffs
/// the bytes rather than trusting the name, so this only decides what
/// the picker offers and what a drop is allowed to be.
const kArtworkExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif'};

/// The endpoint's own ceiling. Checked here so a picked 40 MB scan is
/// refused with a sentence rather than with a 400 after the upload.
const kArtworkMaxBytes = 16 * 1024 * 1024;

/// One artwork slot an item can hold. Only `front` walks the album and
/// artist chain; the rest resolve at the item's own level.
enum ArtSlot {
  front('front'),
  back('back'),
  disc('disc'),
  booklet('booklet'),
  background('background');

  const ArtSlot(this.role);

  final String role;

  /// The slot's name where it stands on its own, over its tile.
  String labelOf(AppLocalizations l10n) => switch (this) {
    front => l10n.artSlotFront,
    back => l10n.artSlotBack,
    disc => l10n.artSlotDisc,
    booklet => l10n.artSlotBooklet,
    background => l10n.artSlotBackground,
  };

  /// The same name inside a sentence, which English lower-cases and
  /// other languages may need an article for. A key of its own rather
  /// than a fold applied to the label: lower-casing is an English rule
  /// wearing a formatting disguise, and the sentences around it cannot
  /// know the gender of the words in this list.
  String inlineOf(AppLocalizations l10n) => switch (this) {
    front => l10n.artSlotFrontInline,
    back => l10n.artSlotBackInline,
    disc => l10n.artSlotDiscInline,
    booklet => l10n.artSlotBookletInline,
    background => l10n.artSlotBackgroundInline,
  };
}

/// The slots an entity holds at its own level.
final itemArtRolesProvider = FutureProvider.autoDispose
    .family<List<ArtRoleInfo>, String>(
      (ref, pid) => ref.watch(repositoryProvider).getItemArtRoles(pid),
    );

/// Every artwork role, what is in it, and the verbs that fill or empty
/// it. Own-versus-inherited is what the grid exists to answer: a front
/// cover drawn here may belong to the album.
class ArtworkManager extends ConsumerStatefulWidget {
  const ArtworkManager({
    super.key,
    required this.pid,
    required this.title,
    required this.hasArtwork,
  });

  final String pid;

  /// What the monogram falls back to on an empty slot.
  final String title;

  /// Whether the item resolves a front cover at all, own or inherited.
  /// The read that answers this rides the metadata the editor already
  /// has; the slot listing answers only what the item holds itself.
  final bool hasArtwork;

  @override
  ConsumerState<ArtworkManager> createState() => _ArtworkManagerState();
}

class _ArtworkManagerState extends ConsumerState<ArtworkManager> {
  /// The slot with a request in flight, so its own controls disable
  /// rather than the whole grid going dead.
  String? _busyRole;

  String _urlFor(ArtSlot slot) =>
      ref.read(repositoryProvider).artUrlFor(widget.pid, role: slot.role);

  Future<void> _pick(ArtSlot slot) async {
    final picker = ref.read(filePickerProvider);
    if (picker == null) return;
    final file = await picker.pickFile(
      extensions: kArtworkExtensions,
      label: context.l10n.artworkPickLabel,
      anyLabel: context.l10n.uploadsFileTypeAny,
    );
    if (file == null) return;
    await _upload(slot, file);
  }

  /// A slot holds one image, so a multi-image drop takes the first and
  /// says so rather than dropping the rest without a word.
  Future<void> _uploadDropped(ArtSlot slot, List<PickedAudioFile> files) async {
    if (files.isEmpty) return;
    final l10n = context.l10n;
    if (files.length > 1) {
      ref
          .read(shellMessengerProvider.notifier)
          .show(l10n.artworkOneImageOnly(slot.labelOf(l10n), files.first.name));
    }
    await _upload(slot, files.first);
  }

  Future<void> _upload(ArtSlot slot, PickedAudioFile file) async {
    // Reached from `_pick` after the OS file picker has been awaited,
    // so the screen may be gone: reading an ancestor through a dead
    // element throws rather than doing nothing.
    if (!mounted) return;
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    if (file.size > kArtworkMaxBytes) {
      messenger.show(l10n.artworkTooLarge(file.name));
      return;
    }
    final openRead = file.openRead;
    if (openRead == null) {
      messenger.show(l10n.artworkUnreadable(file.name));
      return;
    }
    setState(() => _busyRole = slot.role);
    try {
      // Whole in memory, unlike an upload: the endpoint takes one body.
      final builder = BytesBuilder(copy: false);
      await for (final chunk in openRead()) {
        builder.add(chunk);
      }
      await ref
          .read(repositoryProvider)
          .setItemArtwork(
            widget.pid,
            bytes: builder.takeBytes(),
            role: slot.role,
          );
      await _refresh(slot);
      messenger.show(l10n.artworkReplaced(slot.labelOf(l10n)));
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
    } finally {
      if (mounted) setState(() => _busyRole = null);
    }
  }

  Future<void> _clear(ArtSlot slot) async {
    final l10n = context.l10n;
    final confirmed = await showTypedConfirm(
      context,
      title: l10n.artworkClearTitle(slot.inlineOf(l10n)),
      message: slot == ArtSlot.front
          ? l10n.artworkClearFrontBody
          : l10n.artworkClearBody,
      confirmWord: l10n.artworkClearWord,
      confirmLabel: l10n.artworkClearAction,
      fieldSemanticsId: SemanticsIds.confirmField,
      confirmSemanticsId: SemanticsIds.confirmAccept,
      cancelSemanticsId: SemanticsIds.confirmCancel,
    );
    if (!confirmed) return;
    final messenger = ref.read(shellMessengerProvider.notifier);
    setState(() => _busyRole = slot.role);
    try {
      await ref
          .read(repositoryProvider)
          .clearItemArtwork(widget.pid, role: slot.role);
      await _refresh(slot);
      messenger.show(l10n.artworkCleared(slot.labelOf(l10n)));
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
    } finally {
      if (mounted) setState(() => _busyRole = null);
    }
  }

  /// The store's own eviction is the cache bust: it notes the URL as
  /// replaced and asks for it under a new `v` everywhere. A counter
  /// here would bust a URL only this screen draws.
  Future<void> _refresh(ArtSlot slot) async {
    await ref.read(artworkStoreProvider).evict(_urlFor(slot));
    if (!mounted) return;
    setState(() {});
    ref.invalidate(itemArtRolesProvider(widget.pid));
  }

  @override
  Widget build(BuildContext context) {
    final roles = ref.watch(itemArtRolesProvider(widget.pid));
    final own = <String, ArtRoleInfo>{
      for (final role in roles.value ?? const <ArtRoleInfo>[]) role.role: role,
    };
    final picker = ref.watch(filePickerProvider);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: l10n.artworkTitle, overline: l10n.artworkOverline),
        if (roles.hasError)
          WaxBanner(
            message: l10n.artworkSlotsUnreadable,
            tone: WaxBannerTone.caution,
          ),
        Wrap(
          spacing: WaxSpace.s12,
          runSpacing: WaxSpace.s12,
          children: <Widget>[
            for (final slot in ArtSlot.values)
              _SlotTile(
                slot: slot,
                info: own[slot.role],
                // A front cover with nothing of its own still draws:
                // what appears is the album's or the artist's, and the
                // caption is what says so.
                inherited:
                    slot == ArtSlot.front &&
                    own[ArtSlot.front.role] == null &&
                    widget.hasArtwork,
                title: widget.title,
                artUrl: _urlFor(slot),
                busy: _busyRole == slot.role,
                canPick: picker != null,
                onPick: () => _pick(slot),
                onClear: () => _clear(slot),
                onDropped: (files) => _uploadDropped(slot, files),
              ),
          ],
        ),
      ],
    );
  }
}

class _SlotTile extends ConsumerWidget {
  const _SlotTile({
    required this.slot,
    required this.info,
    required this.inherited,
    required this.title,
    required this.artUrl,
    required this.busy,
    required this.canPick,
    required this.onPick,
    required this.onClear,
    required this.onDropped,
  });

  static const _size = 132.0;

  final ArtSlot slot;

  /// What the entity holds in this slot itself; null when it holds
  /// nothing.
  final ArtRoleInfo? info;

  final bool inherited;
  final String title;
  final String artUrl;
  final bool busy;
  final bool canPick;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final Future<void> Function(List<PickedAudioFile> files) onDropped;

  String _stateOf(AppLocalizations l10n) {
    final held = info;
    if (held != null) {
      final size = (held.width ?? 0) > 0 && (held.height ?? 0) > 0
          ? l10n.artworkStateSize(held.width!, held.height!)
          : null;
      return <String>[held.format ?? l10n.artworkStateImage, ?size].join(', ');
    }
    return inherited ? l10n.artworkStateInherited : l10n.artworkStateEmpty;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final state = _stateOf(l10n);
    final store = ref.watch(artworkStoreProvider);
    // The tile draws whatever the endpoint answers for this slot, which
    // for `front` may be the album's. Every other slot 404s when it is
    // empty, and a 404 is the monogram.
    final artwork = info != null || inherited ? store.source(artUrl) : null;
    return Semantics(
      identifier: SemanticsIds.artSlot(slot.role),
      container: true,
      child: AudioDropArea(
        enabled: !busy,
        extensions: kArtworkExtensions,
        hint: l10n.artworkDropHint(slot.inlineOf(l10n)),
        semanticsId: SemanticsIds.artSlotDrop(slot.role),
        onDropped: onDropped,
        child: SizedBox(
          width: _size,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Stack(
                children: <Widget>[
                  ArtworkImage(
                    size: _size,
                    artwork: artwork,
                    monogram: title,
                    semanticLabel: l10n.artworkSlotSpoken(
                      slot.labelOf(l10n),
                      state,
                    ),
                  ),
                  if (busy)
                    Positioned.fill(
                      child: ColoredBox(
                        color: colors.scrim.withValues(alpha: 0.6),
                        child: const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: WaxSpace.s8),
              Text(
                slot.labelOf(l10n),
                style: WaxType.label.copyWith(color: colors.textPrimary),
              ),
              Text(
                state,
                style: WaxType.caption.copyWith(
                  color: info != null
                      ? colors.textSecondary
                      : colors.textTertiary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: WaxSpace.s4),
              Row(
                children: <Widget>[
                  WaxIconButton(
                    glyph: WaxIcons.edit,
                    label: info == null
                        ? l10n.artworkSetSlot(slot.inlineOf(l10n))
                        : l10n.artworkReplaceSlot(slot.inlineOf(l10n)),
                    size: 16,
                    semanticsId: SemanticsIds.artSlotSet(slot.role),
                    onPressed: busy || !canPick ? null : onPick,
                  ),
                  WaxIconButton(
                    glyph: WaxIcons.delete,
                    label: l10n.artworkClearSlot(slot.inlineOf(l10n)),
                    size: 16,
                    semanticsId: SemanticsIds.artSlotClear(slot.role),
                    // Nothing of its own is nothing to clear: an
                    // inherited cover belongs to the album, and this
                    // screen is not where an album is edited.
                    onPressed: busy || info == null ? null : onClear,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
