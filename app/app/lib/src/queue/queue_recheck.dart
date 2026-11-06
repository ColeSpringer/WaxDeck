import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../player/now_playing_controller.dart';
import '../player/now_playing_slot.dart';
import '../providers.dart';
import '../shell/shell_messages.dart';
import 'queue_controller.dart';
import 'queue_item.dart';

/// Reads the queue's items again, for what was done to them elsewhere: a
/// kind change made on another device, or one whose dialog stopped
/// watching.
///
/// Run once a run of catalog changes goes quiet, one lookup per
/// [itemLookupCap] queued items. One that is now another kind has its
/// summary replaced, its row read again and a park naming it offered anew,
/// so it starts and reads as what it is. One the server names departed
/// (folded into a book) leaves the queue as a watched kind change lets it
/// go, but with no stop: playing, it plays on and the queue moves past it
/// at its end; parked, what follows takes over the park; standing on the
/// deck (paused, or failed), what follows waits in its place and the
/// listener is told. One archived (trashed, purged, deleted, or its
/// library removed) stays: the server cannot yet tell a removed library's
/// archive, which adding the folder again undoes, from a delete's, so it
/// answers every archived item, and one that cannot start is skipped when
/// reached. One merely out of sight stays too, since it can come back, and
/// so does every item a failed lookup asked about. Summaries the queue
/// does not hold are let go too, so none is left unchecked.
final queueRecheckProvider = Provider<QueueRecheck>(QueueRecheck.new);

class QueueRecheck {
  QueueRecheck(this._ref);

  final Ref _ref;

  bool _running = false;
  bool _again = false;

  /// One pass, or one more after the pass under way.
  Future<void> run() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await _pass();
      } while (_again && _ref.mounted);
    } finally {
      _running = false;
    }
  }

  Future<void> _pass() async {
    final container = _ref.container;
    final pids = [
      ...{...container.read(queueControllerProvider).pids},
    ];
    if (pids.isEmpty) return;
    final repository = container.read(repositoryProvider);
    final playback = container.read(nowPlayingProvider.notifier);
    // By ULID: an item a kind change converted answers under its new prefix.
    final answers = <String, ItemSummary>{};
    final departed = <String>{};
    for (var at = 0; at < pids.length; at += itemLookupCap) {
      final ItemResolution resolved;
      try {
        resolved = await repository.resolveItems(
          pids.sublist(at, min(at + itemLookupCap, pids.length)),
        );
      } on Object {
        // Says nothing of these items: they are read again next time.
        continue;
      }
      if (!_ref.mounted) return;
      for (final item in resolved.items) {
        answers[ulidOf(item.pid)] = item;
      }
      departed.addAll(resolved.departed.map(ulidOf));
    }
    if (!_ref.mounted) return;
    for (final pid in pids) {
      final now = answers[ulidOf(pid)];
      if (now == null) continue;
      final row = queueItemProvider(pid);
      final shown = container.exists(row) ? container.read(row).value : null;
      final stale = [
        playback.summaryFor(pid),
        shown,
      ].nonNulls.any((held) => held.mediaType != now.mediaType);
      if (!stale) continue;
      playback.refreshSummary(pid, now);
      if (shown != null) container.invalidate(row);
    }
    playback.forgetUnqueued();
    _letGo(departed, playback);
  }

  void _letGo(Set<String> gone, NowPlayingController playback) {
    final container = _ref.container;
    final queue = container.read(queueControllerProvider.notifier);
    if (gone.isEmpty || !queue.dropItems(gone)) return;
    final slot = container.read(nowPlayingSlotProvider);
    if (slot is ItemSlot && playback.meansToPlay) return;
    playback.dropCurrent();
    if (slot is! ItemSlot) return;
    container
        .read(shellMessengerProvider.notifier)
        .showLocalized((l10n) => l10n.queuePlayingGone);
  }
}
