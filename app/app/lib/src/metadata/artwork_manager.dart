import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/art_source_label.dart';
import '../artwork/artwork_providers.dart';
import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import '../uploads/audio_drop_area.dart';
import '../uploads/file_picker_port.dart';

/// The image formats the artwork endpoints accept: the six the catalog
/// decodes, plus the two exotic containers it recognizes by their magic
/// and stores without decoding. This set decides what the picker offers
/// and what a drop is allowed to be; a file picked through "any" still
/// reaches the server, which refuses anything it cannot recognize.
const kArtworkExtensions = {
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
  'bmp',
  'tif',
  'tiff',
  'avif',
  'heic',
};

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

/// Every artwork role, what is in it, and the verbs that fill or empty
/// it. Own-versus-inherited is what the grid exists to answer: a front
/// cover drawn here may belong to the album.
class ArtworkManager extends ConsumerStatefulWidget {
  const ArtworkManager({
    super.key,
    required this.pid,
    required this.title,
    required this.hasArtwork,
    this.entityType,
    this.writeBack = false,
    this.pinnable = true,
    this.onChanged,
  });

  final String pid;

  /// What the monogram falls back to on an empty slot.
  final String title;

  /// Whether the item resolves a front cover at all, own or inherited.
  /// The read that answers this rides the metadata the editor already
  /// has; the slot listing answers only what the item holds itself.
  final bool hasArtwork;

  /// The browse-entity type (`album`, `artist`, ...) when this manages
  /// an entity's artwork rather than a catalog item's; null for an
  /// item.
  ///
  /// The reads are the same either way: both the slot listing and the
  /// art endpoint are addressed by pid, and an entity pid resolves
  /// straight to its own art level. Only the writes differ - an item's
  /// slots go through the item endpoints, an entity's through the
  /// entity ones, which additionally carry the cover pin.
  final String? entityType;

  /// Whether setting an entity's front cover also embeds it into the
  /// member files. Albums only, and ignored elsewhere by the endpoint.
  final bool writeBack;

  /// Whether the item branch offers the front-cover pin. The `art`
  /// lock only applies to tracks and books - an episode's picture is
  /// the feed's, so the store refuses the lock row - and a switch the
  /// server always refuses is worse than no switch. Ignored for
  /// entities, whose pin rides its own endpoint.
  final bool pinnable;

  /// Called after this grid changes what the entity's artwork is.
  ///
  /// The reads this widget owns are invalidated for it; a screen drawing
  /// the same cover from a read of its own - a detail read carrying the
  /// resolved source, say - has to be told, and this manager has no
  /// business knowing which provider that is.
  final VoidCallback? onChanged;

  @override
  ConsumerState<ArtworkManager> createState() => _ArtworkManagerState();
}

/// Whether a catalog entity's front cover is pinned against enrichment
/// and scan re-derives.
///
/// Its own read rather than a field on the slot listing: the pin
/// survives the cover being cleared, which is the state it exists to
/// explain, and a slot listing with nothing in it has no row to hang it
/// on. Refused for playlists by construction, so this is only ever
/// asked for a catalog entity.
final entityArtLockProvider = FutureProvider.autoDispose
    .family<bool, ({String type, String pid})>(
      (ref, key) =>
          ref.watch(repositoryProvider).getEntityArtworkLock(key.type, key.pid),
    );

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
      final bytes = builder.takeBytes();
      final repository = ref.read(repositoryProvider);
      final entity = widget.entityType;
      if (entity == null) {
        await repository.setItemArtwork(
          widget.pid,
          bytes: bytes,
          role: slot.role,
        );
      } else {
        await repository.setEntityArtwork(
          entity,
          widget.pid,
          bytes: bytes,
          role: slot.role,
          writeBack: widget.writeBack && slot == ArtSlot.front,
        );
      }
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
      final repository = ref.read(repositoryProvider);
      final entity = widget.entityType;
      if (entity == null) {
        await repository.clearItemArtwork(widget.pid, role: slot.role);
      } else {
        await repository.clearEntityArtwork(
          entity,
          widget.pid,
          role: slot.role,
        );
      }
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
    // Setting an entity's front cover pins it and clearing one leaves
    // the pin as it stood, so the switch below is stale either way.
    final entity = widget.entityType;
    if (entity != null) {
      ref.invalidate(entityArtLockProvider((type: entity, pid: widget.pid)));
    }
    widget.onChanged?.call();
  }

  /// Pins or unpins the front cover, which is the one way out of a
  /// cover cleared and left pinned: setting artwork cannot express
  /// "stop refusing", and clearing it again does nothing. An entity's
  /// pin is its own endpoint; an item's rides the field-lock surface
  /// under the `art` name. Either spelling is the whole-artwork pin,
  /// which gates the auxiliary slots' automatic fills as well.
  Future<void> _setLock(bool locked) => _writeLock(ArtSlot.front, locked);

  /// Pins or unpins one auxiliary slot's own lock. The whole-artwork
  /// pin above gates every role's automatic fill as well, so a slot can
  /// be held with nothing set here; the read says which pin holds it,
  /// and the tile captions that state rather than hiding the toggle -
  /// a slot the cover pin holds can still take a pin of its own, which
  /// outlives the cover pin coming off.
  Future<void> _setSlotLock(ArtSlot slot, bool locked) =>
      _writeLock(slot, locked);

  /// The one lock writer, keyed by slot. The front takes the
  /// whole-artwork spelling on both branches (`art`, or the entity
  /// endpoint's default role); every other slot takes its own.
  Future<void> _writeLock(ArtSlot slot, bool locked) async {
    final front = slot == ArtSlot.front;
    final entity = widget.entityType;
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    setState(() => _busyRole = slot.role);
    try {
      final repository = ref.read(repositoryProvider);
      if (entity == null) {
        await repository.setItemLocks(
          widget.pid,
          fields: <String>[front ? 'art' : 'art.${slot.role}'],
          locked: locked,
        );
      } else {
        await repository.setEntityArtworkLock(
          entity,
          widget.pid,
          role: slot.role,
          locked: locked,
        );
      }
      // Guarded like _refresh beside it: the pin may have been written
      // while this screen was being left, and invalidating through a
      // disposed ref throws. It escapes rather than surfacing, because
      // the switch takes this as a void callback and discards the
      // future.
      if (!mounted) return;
      if (entity != null) {
        ref.invalidate(entityArtLockProvider((type: entity, pid: widget.pid)));
      }
      ref.invalidate(itemArtRolesProvider(widget.pid));
      widget.onChanged?.call();
      messenger.show(switch ((front, locked)) {
        (true, true) => l10n.artworkLockPinned,
        (true, false) => l10n.artworkLockUnpinned,
        (false, true) => l10n.artworkSlotPinned(slot.labelOf(l10n)),
        (false, false) => l10n.artworkSlotUnpinned(slot.labelOf(l10n)),
      });
    } on WaxDeckApiException catch (e) {
      if (mounted) messenger.show(explainError(l10n, e));
    } finally {
      if (mounted) setState(() => _busyRole = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = ref.watch(itemArtRolesProvider(widget.pid));
    final own = <String, ArtRoleInfo>{
      for (final role in roles.value?.roles ?? const <ArtRoleInfo>[])
        role.role: role,
    };
    final picker = ref.watch(filePickerProvider);
    final l10n = context.l10n;
    // The same gate the whole-artwork switch below uses. An entity
    // always takes pins; an item takes them only where the catalog
    // curates art at all, which is tracks and books but not episodes.
    final offersPins = widget.entityType != null || widget.pinnable;
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
                // caption is what says so. A pin with nothing behind it
                // is nothing of its own: the catalog synthesizes a row
                // for it, but the read endpoint still answers the
                // album's cover, so treating that row as an image would
                // blank a tile whose picture the header is showing.
                inherited:
                    slot == ArtSlot.front &&
                    (own[ArtSlot.front.role]?.pinnedEmpty ?? true) &&
                    widget.hasArtwork,
                title: widget.title,
                // The resolved cover's provenance belongs to the front
                // tile alone: it is the only slot that inherits, and the
                // only one an inherited picture can appear in.
                resolved: slot == ArtSlot.front ? roles.value?.artSource : null,
                artUrl: _urlFor(slot),
                busy: _busyRole == slot.role,
                canPick: picker != null,
                // Null on the front, whose pin is the whole-artwork one
                // and gets its own switch under the grid; drawing it
                // twice would offer the same write in two places. Null
                // also wherever no pin is offered at all - a podcast
                // episode, where the catalog refuses an art lock
                // outright, is what `pinnable` is false for.
                //
                // The role's own pin, not the effective lock: the
                // toggle writes this slot's own lock, so drawing the
                // effective one would show a slot the cover pin holds
                // as pinned and then not move when it was released.
                locked: slot == ArtSlot.front || !offersPins
                    ? null
                    : own[slot.role]?.ownPin ?? false,
                // The same fallback the server's own lock read applies:
                // a slot with no row of its own has no pin of its own,
                // so the only thing that can hold it is the front row's
                // pin, which is the whole-artwork one. The catalog
                // synthesizes a row only for a pin that is actually set,
                // so a held-but-imageless auxiliary slot has no row at
                // all and would otherwise draw no caption.
                heldByCoverPin:
                    slot != ArtSlot.front &&
                    (own[slot.role]?.heldByCoverPin ??
                        (own[ArtSlot.front.role]?.roleLocked ?? false)),
                onTogglePin: (locked) => _setSlotLock(slot, locked),
                onPick: () => _pick(slot),
                onClear: () => _clear(slot),
                onDropped: (files) => _uploadDropped(slot, files),
              ),
          ],
        ),
        if (offersPins) ...<Widget>[
          const SizedBox(height: WaxSpace.s12),
          Builder(
            builder: (context) {
              // The pin state's read differs by branch: an entity's pin
              // survives its cover being cleared, so it has an endpoint
              // of its own, while an item's rides the front row of the
              // slot listing this grid already holds (the catalog
              // synthesizes that row for a pinned empty slot, so the
              // state this switch exists for is never rowless).
              final bool value;
              final bool known;
              if (widget.entityType case final entity?) {
                final lock = ref.watch(
                  entityArtLockProvider((type: entity, pid: widget.pid)),
                );
                value = lock.value ?? false;
                known = lock.hasValue;
              } else {
                value = own[ArtSlot.front.role]?.locked ?? false;
                known = roles.hasValue;
              }
              return WaxSettingRow(
                title: l10n.artworkLockTitle,
                help: l10n.artworkLockHelp,
                control: WaxSwitch(
                  label: l10n.artworkLockTitle,
                  value: value,
                  semanticsId: SemanticsIds.artLock,
                  // Dead until the pin is known. Off is what an unread
                  // lock draws as, so a pinned cover reads as unpinned
                  // while the read is in flight or after it failed -
                  // and a tap in that window would write the state the
                  // switch is only guessing at.
                  onChanged: _busyRole != null || !known ? null : _setLock,
                ),
              );
            },
          ),
        ],
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
    required this.resolved,
    required this.artUrl,
    required this.busy,
    required this.canPick,
    required this.locked,
    required this.heldByCoverPin,
    required this.onTogglePin,
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

  /// Where the picture this tile actually draws came from, for the
  /// front slot: the entity's own attribution where it holds one, the
  /// rung it inherits from where it does not. Null on every other slot,
  /// which never inherits and carries its own row instead.
  final ArtSource? resolved;

  final String artUrl;
  final bool busy;
  final bool canPick;

  /// Whether this slot's **own** pin is set, or null where no pin is
  /// offered on this slot at all: the front cover, whose pin is the
  /// entity's whole one and gets its own switch under the grid, and
  /// every slot on an item whose kind the catalog does not curate art
  /// for.
  ///
  /// The slot's own pin rather than the effective lock, because that is
  /// what the toggle writes - falling back to the effective lock on a
  /// server that reports no role pin, which is what that server's own
  /// reading meant and is what keeps its slots releasable. The toggle
  /// stays live either way: a slot the whole-artwork pin holds can
  /// still take a pin of its own, and disabling it there was the
  /// earlier bug - it disabled the control on exactly the
  /// cleared-and-pinned slot it exists to release.
  final bool? locked;

  /// Held by the entity's whole-artwork pin while carrying no pin of
  /// its own, which is why the tile says so: unpinning here would leave
  /// the slot just as held, and nothing else on the grid explains that.
  final bool heldByCoverPin;

  final ValueChanged<bool> onTogglePin;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final Future<void> Function(List<PickedAudioFile> files) onDropped;

  String _stateOf(AppLocalizations l10n) {
    final held = info;
    // A pin with nothing behind it is not an empty slot: it refuses
    // every later write and shows nothing, and saying "Empty" here is
    // exactly the confusion the upstream lock report exists to end.
    if (held != null && held.pinnedEmpty) return l10n.artworkStatePinned;
    if (held != null) {
      // Zero is the catalog saying it never measured this picture, not
      // that it is nothing wide. Saying so is the point: a bare "tiff"
      // reads as though nobody asked, and the two are different states -
      // one is a cover the server cannot decode, the other is one it
      // decoded and whose numbers this row simply left out.
      final size = (held.width ?? 0) > 0 && (held.height ?? 0) > 0
          ? l10n.artworkStateSize(held.width!, held.height!)
          : l10n.artworkStateSizeUnknown;
      return <String>[held.format ?? l10n.artworkStateImage, size].join(', ');
    }
    return inherited ? l10n.artworkStateInherited : l10n.artworkStateEmpty;
  }

  /// Where this tile's picture came from. A slot the entity holds
  /// carries its own attribution; the front slot showing an inherited
  /// cover reports the rung that answered instead.
  String? _sourceOf(AppLocalizations l10n) {
    final held = info;
    if (held != null && !held.pinnedEmpty) {
      return artRoleSourceLabel(l10n, held);
    }
    // The borrow note rides along here and nowhere else on this grid: a
    // slot the item owns cannot be borrowed, and the inherited case is
    // the one where the picture may be twice removed from this item.
    return inherited ? artSourceLabelWithBorrow(l10n, resolved) : null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final state = _stateOf(l10n);
    final source = _sourceOf(l10n);
    final store = ref.watch(artworkStoreProvider);
    // Whether this slot holds a picture of its own, which is the one
    // question the three controls below each used to answer for
    // themselves. A pin with nothing behind it holds nothing.
    final holdsImage = info != null && !info!.pinnedEmpty;
    // The tile draws whatever the endpoint answers for this slot, which
    // for `front` may be the album's. Every other slot 404s when it is
    // empty, and a 404 is the monogram.
    final artwork = holdsImage || inherited ? store.source(artUrl) : null;
    return Semantics(
      identifier: SemanticsIds.artSlot(slot.role),
      container: true,
      child: AudioDropArea(
        enabled: !busy,
        formats: () async => const UploadFormatSets.only(kArtworkExtensions),
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
                      source == null ? state : '$state, $source',
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
              ArtworkCaption(state, emphasis: info != null),
              if (source != null) ArtworkCaption(source),
              if (heldByCoverPin) ArtworkCaption(l10n.artworkHeldByCoverPin),
              const SizedBox(height: WaxSpace.s4),
              Row(
                children: <Widget>[
                  WaxIconButton(
                    glyph: WaxIcons.edit,
                    label: holdsImage
                        ? l10n.artworkReplaceSlot(slot.inlineOf(l10n))
                        : l10n.artworkSetSlot(slot.inlineOf(l10n)),
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
                    // screen is not where an album is edited. A pinned
                    // empty slot holds nothing either - clearing it
                    // again would do nothing at all, and the pin comes
                    // off through the field's own lock, not here.
                    onPressed: busy || !holdsImage ? null : onClear,
                  ),
                  if (locked case final pinned?)
                    WaxIconButton(
                      glyph: pinned ? WaxIcons.lock : WaxIcons.lockOpen,
                      label: pinned
                          ? l10n.artworkUnpinSlot(slot.inlineOf(l10n))
                          : l10n.artworkPinSlot(slot.inlineOf(l10n)),
                      size: 16,
                      semanticsId: SemanticsIds.artLockRole(slot.role),
                      onPressed: busy ? null : () => onTogglePin(!pinned),
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
