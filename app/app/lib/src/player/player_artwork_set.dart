import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../artwork/artwork_providers.dart';
import '../metadata/artwork_manager.dart' show ArtSlot;

/// One picture the full-screen player can turn to: a slot the item or its
/// album holds.
class PlayerArtwork {
  const PlayerArtwork({required this.pid, required this.slot, this.info});

  /// The item's pid or its album's.
  final String pid;
  final ArtSlot slot;

  /// The slot's own row; null for a cover the item shows without holding.
  final ArtRoleInfo? info;
}

/// The item a set is built for, and the album whose slots follow its own.
typedef PlayerArtworkKey = ({String pid, String? albumPid});

/// What the full-screen player turns through, the item's cover first.
///
/// Null until both reads have answered, so the set arrives whole.
final playerArtworkSetProvider = Provider.autoDispose
    .family<List<PlayerArtwork>?, PlayerArtworkKey>((ref, key) {
      final own = ref.watch(itemArtRolesProvider(key.pid));
      final albumPid = key.albumPid;
      final album = albumPid == null
          ? null
          : ref.watch(itemArtRolesProvider(albumPid));
      bool answered(AsyncValue<ArtRoles>? read) =>
          read == null || read.hasValue || read.hasError;
      if (!answered(own) || !answered(album)) return null;
      return playerArtworkSet(
        pid: key.pid,
        own: own.value,
        albumPid: albumPid,
        album: album?.value,
      );
    });

/// The item's own slots, front first whether or not it holds one, then
/// its album's, less the album front the item already shows. An item
/// that shows no cover at all starts at the first picture it has.
List<PlayerArtwork> playerArtworkSet({
  required String pid,
  ArtRoles? own,
  String? albumPid,
  ArtRoles? album,
}) {
  final held = _held(own);
  final entries = <PlayerArtwork>[
    PlayerArtwork(pid: pid, slot: ArtSlot.front, info: held[ArtSlot.front]),
    for (final slot in ArtSlot.values.where((s) => s != ArtSlot.front))
      if (held[slot] case final info?)
        PlayerArtwork(pid: pid, slot: slot, info: info),
  ];
  if (albumPid != null) {
    final albums = _held(album);
    for (final slot in ArtSlot.values) {
      // Without a front of its own the item's cover is this one.
      if (slot == ArtSlot.front && held[ArtSlot.front] == null) continue;
      if (albums[slot] case final info?) {
        entries.add(PlayerArtwork(pid: albumPid, slot: slot, info: info));
      }
    }
  }
  // Nothing attributed resolves nothing: every stored picture has a source.
  final coverless =
      own != null && own.artSource == null && held[ArtSlot.front] == null;
  return coverless && entries.length > 1 ? entries.sublist(1) : entries;
}

/// The slots [roles] holds an image in. A pin left on a cleared slot
/// holds none, and a role this build does not name is not drawn.
Map<ArtSlot, ArtRoleInfo> _held(ArtRoles? roles) => <ArtSlot, ArtRoleInfo>{
  for (final info in roles?.roles ?? const <ArtRoleInfo>[])
    if (!info.pinnedEmpty)
      for (final slot in ArtSlot.values)
        if (slot.role == info.role) slot: info,
};
