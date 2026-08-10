import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
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
  front('front', 'Front cover', 'The cover everything else falls back to'),
  back('back', 'Back cover', 'The reverse of the sleeve'),
  disc('disc', 'Disc', 'The label printed on the disc itself'),
  booklet('booklet', 'Booklet', 'A page from the insert'),
  background(
    'background',
    'Background',
    'A wide image, and an artist portrait',
  );

  const ArtSlot(this.role, this.label, this.blurb);

  final String role;
  final String label;
  final String blurb;
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
      label: 'Image',
    );
    if (file == null) return;
    await _upload(slot, file);
  }

  /// A slot holds one image, so a multi-image drop takes the first and
  /// says so rather than dropping the rest without a word.
  Future<void> _uploadDropped(ArtSlot slot, List<PickedAudioFile> files) async {
    if (files.isEmpty) return;
    if (files.length > 1) {
      ref
          .read(shellMessengerProvider.notifier)
          .show('${slot.label} takes one image; using ${files.first.name}');
    }
    await _upload(slot, files.first);
  }

  Future<void> _upload(ArtSlot slot, PickedAudioFile file) async {
    final messenger = ref.read(shellMessengerProvider.notifier);
    if (file.size > kArtworkMaxBytes) {
      messenger.show('${file.name} is larger than the 16 MB an image may be');
      return;
    }
    final openRead = file.openRead;
    if (openRead == null) {
      messenger.show('${file.name} could not be read');
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
      messenger.show('${slot.label} replaced');
    } on WaxDeckApiException catch (e) {
      messenger.show(e.message);
    } finally {
      if (mounted) setState(() => _busyRole = null);
    }
  }

  Future<void> _clear(ArtSlot slot) async {
    final confirmed = await showTypedConfirm(
      context,
      title: 'Clear the ${slot.label.toLowerCase()}?',
      message: slot == ArtSlot.front
          ? 'The item falls back to its album or artist cover. The image '
                'itself is removed from the catalog.'
          : 'The slot becomes empty. Nothing falls back into it.',
      confirmWord: 'clear',
      confirmLabel: 'Clear',
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
      messenger.show('${slot.label} cleared');
    } on WaxDeckApiException catch (e) {
      messenger.show(e.message);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(title: 'Artwork', overline: 'One image per slot'),
        if (roles.hasError)
          const WaxBanner(
            message:
                'Could not read which slots this item holds; what is drawn '
                'below may be inherited.',
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

  String get _state {
    if (info != null) {
      final size = (info!.width ?? 0) > 0 && (info!.height ?? 0) > 0
          ? '${info!.width} x ${info!.height}'
          : null;
      return <String>[info!.format ?? 'image', ?size].join(', ');
    }
    return inherited ? 'Inherited' : 'Empty';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
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
        hint: 'Drop an image into ${slot.label.toLowerCase()}',
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
                    semanticLabel: '${slot.label}: $_state',
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
                slot.label,
                style: WaxType.label.copyWith(color: colors.textPrimary),
              ),
              Text(
                _state,
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
                        ? 'Set the ${slot.label.toLowerCase()}'
                        : 'Replace the ${slot.label.toLowerCase()}',
                    size: 16,
                    semanticsId: SemanticsIds.artSlotSet(slot.role),
                    onPressed: busy || !canPick ? null : onPick,
                  ),
                  WaxIconButton(
                    glyph: WaxIcons.delete,
                    label: 'Clear the ${slot.label.toLowerCase()}',
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
