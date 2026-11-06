import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart' show RadioStation;

import '../connect/remote_session.dart';
import '../queue/queue_persistence.dart';
import '../radio/radio_controller.dart';
import 'now_playing_controller.dart';

/// What this app is playing, decided once: every surface that names it
/// (the deck, the player, the OS media surfaces, the tray, Discord, the
/// mini window, the transports) switches on this rather than ranking the
/// sources itself.
sealed class NowPlayingSlot {
  const NowPlayingSlot();
}

/// Live radio has the engine.
final class StationSlot extends NowPlayingSlot {
  const StationSlot(this.playback);

  final RadioPlayback playback;

  /// Never null here: a station on air is what makes this slot.
  RadioStation get station => playback.station!;

  @override
  bool operator ==(Object other) =>
      other is StationSlot && other.playback == playback;

  @override
  int get hashCode => playback.hashCode;
}

/// The queue's current entry: playing, loading, or where a failed start
/// left it.
final class ItemSlot extends NowPlayingSlot {
  const ItemSlot(this.now);

  final NowPlaying now;

  @override
  bool operator ==(Object other) => other is ItemSlot && other.now == now;

  @override
  int get hashCode => now.hashCode;
}

/// The entry a station holds back (displaced, or queued under it) and
/// nothing has taken back. Not playing: the deck offers it, the queue
/// and a cover play take it back, and the transport surfaces read it as
/// nothing.
final class ParkedSlot extends NowPlayingSlot {
  const ParkedSlot(this.parked);

  final ParkedEntry parked;

  @override
  bool operator ==(Object other) =>
      other is ParkedSlot && other.parked == parked;

  @override
  int get hashCode => parked.hashCode;
}

/// A session this client drives on another endpoint.
final class RemoteSlot extends NowPlayingSlot {
  const RemoteSlot(this.remote);

  final RemoteSession remote;

  @override
  bool operator ==(Object other) =>
      other is RemoteSlot && other.remote == remote;

  @override
  int get hashCode => remote.hashCode;
}

/// The queue a launch found, offered back.
final class OfferSlot extends NowPlayingSlot {
  const OfferSlot(this.offer);

  final RestorableQueue offer;

  @override
  bool operator ==(Object other) => other is OfferSlot && other.offer == offer;

  @override
  int get hashCode => offer.hashCode;
}

final class EmptySlot extends NowPlayingSlot {
  const EmptySlot();
}

/// The deck's order: a station, an item with an entry, a parked entry, a
/// remote session, the launch offer, nothing. Each source is watched only
/// once the ones above it are empty, so a station on air depends on
/// nothing else.
final nowPlayingSlotProvider = Provider<NowPlayingSlot>((ref) {
  final radio = ref.watch(radioPlaybackProvider);
  if (radio.station != null) return StationSlot(radio);
  final now = ref.watch(nowPlayingProvider);
  if (now.entry != null) return ItemSlot(now);
  final parked = ref.watch(parkedEntryProvider);
  if (parked != null) return ParkedSlot(parked);
  final remote = ref.watch(remoteSessionProvider);
  if (remote != null) return RemoteSlot(remote);
  final offer = ref.watch(queueRestoreProvider).value;
  if (offer != null) return OfferSlot(offer);
  return const EmptySlot();
});
