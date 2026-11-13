part of '../now_playing_controller.dart';

/// The queue entry a station holds back, standing where it was without
/// being what is playing: the way back to it is an explicit choice.
class ParkedEntry {
  const ParkedEntry({required this.entry, this.item, this.fresh = false});

  final QueueEntry entry;

  /// Null while no summary is held for it, as when radio overtook its
  /// start before the item resolved; one that arrives later is offered.
  final ItemSummary? item;

  /// Never played and holding no place to come back to, neither a
  /// checkpoint to resume nor a position its start was given: parked by an
  /// add or a landing under a station, or a tap's start held back before it
  /// had loaded. It is offered as queued and taken back as an ordinary
  /// start.
  final bool fresh;

  @override
  bool operator ==(Object other) =>
      other is ParkedEntry &&
      other.entry.queueId == entry.queueId &&
      other.item == item &&
      other.fresh == fresh;

  @override
  int get hashCode => Object.hash(entry.queueId, item, fresh);
}

/// The park: the entry a station holds back, set and followed.
mixin _NowPlayingPark on _NowPlayingCore {
  /// The entry a station holds back, until a start or an emptied queue
  /// retires it: one piece of state, which [parkedEntryProvider] watches
  /// and this controller reads. See [parked].
  _Park? get _park => ref.read(_parkProvider);
  String? get _parkedEntryId => _park?.id;

  void _setPark(String? id, {bool fresh = false, int? positionMs}) {
    _Park? park;
    if (id != null) {
      final pid = ref
          .read(queueControllerProvider)
          .entries
          .where((e) => e.queueId == id)
          .firstOrNull
          ?.pid;
      park = (
        id: id,
        pid: pid,
        item: pid == null ? null : _known[pid],
        fresh: fresh,
        positionMs: positionMs,
      );
    }
    if (park == _park) return;
    ref.read(_parkProvider.notifier).set(park);
  }

  /// Republishes the park once the summary held for its pid changed, so
  /// the offer names what the entry is now.
  void _parkFollowsKnown() {
    final park = _park;
    final pid = park?.pid;
    if (park == null || pid == null) return;
    final item = _known[pid];
    if (identical(item, park.item)) return;
    ref.read(_parkProvider.notifier).set((
      id: park.id,
      pid: pid,
      item: item,
      fresh: park.fresh,
      positionMs: park.positionMs,
    ));
  }
}

/// A park: the entry's queue id and pid, the summary held for that pid,
/// whether it is [ParkedEntry.fresh], and where a start that never loaded
/// was asked to begin.
typedef _Park = ({
  String id,
  String? pid,
  ItemSummary? item,
  bool fresh,
  int? positionMs,
});

/// [NowPlayingController]'s park, the one place it is held.
final _parkProvider = NotifierProvider<_ParkState, _Park?>(_ParkState.new);

class _ParkState extends Notifier<_Park?> {
  @override
  _Park? build() => null;

  void set(_Park? park) => state = park;
}

/// The parked entry [park] makes of the queue's current [entry]: none once
/// the queue moved off it.
ParkedEntry? _parkedOf(_Park? park, QueueEntry? entry) =>
    park == null || entry == null || entry.queueId != park.id
    ? null
    : ParkedEntry(entry: entry, item: park.item, fresh: park.fresh);

/// [NowPlayingController.parked], followed: it changes when a park is set
/// or retired, when the summary it names changes, and when the queue moves
/// off the parked entry.
final parkedEntryProvider = Provider<ParkedEntry?>(
  (ref) => _parkedOf(
    ref.watch(_parkProvider),
    ref.watch(queueControllerProvider.select((queue) => queue.currentEntry)),
  ),
);
