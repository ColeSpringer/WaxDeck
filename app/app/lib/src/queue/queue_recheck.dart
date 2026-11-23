import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../books/book_summary.dart';
import '../player/now_playing_controller.dart';
import '../player/now_playing_slot.dart';
import '../providers.dart';
import '../shell/shell_messages.dart';
import 'queue_controller.dart';
import 'queue_item.dart';

/// Reads the queue's items again, for what was done to them elsewhere or
/// by an editor here: a rename, a new credit, a move to another album, a
/// kind change.
///
/// Run once a run of catalog changes goes quiet, and in part when a
/// write lands here ([QueueRecheck.redraw]), one lookup per
/// [itemLookupCap] queued items. One whose row now draws differently has
/// its summary replaced (a book played from its screen composed again from
/// a fresh read of its detail, as its play composed it) and its row read
/// again, and the entry playing is named anew where it stands: its session, its stream and its place are
/// not touched. One that is now another kind has its summary replaced, its
/// row read again and a park naming it offered anew, so it starts and
/// reads as what it is. One the server names departed
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

  /// The server's last row for each queued item held as a
  /// [ComposedSummary], by ULID: what the next lookup is compared with.
  final _said = <String, ItemSummary>{};

  bool _running = false;
  bool _again = false;
  bool _redrawAgain = false;

  /// Whether a lookup of the last whole pass failed: the items it asked
  /// about are owed another.
  bool get missedLast => _missed;
  bool _missed = false;

  /// Whether a pass is under way.
  bool get running => _running;

  /// One pass, or one more after the pass under way.
  Future<void> run() => _ask(whole: true);

  /// One lookup for a write made here, ahead of the pass its hint
  /// brings: summaries whose rows draw differently are replaced, and
  /// nothing else is done. A kind change and what it folded away are the
  /// write's own to settle with the queue, and that pass's to check.
  /// Where nothing has played there is nothing held, and none is asked.
  Future<void> redraw() async {
    if (!_ref.container.exists(nowPlayingProvider)) return;
    await _ask(whole: false);
  }

  Future<void> _ask({required bool whole}) async {
    if (_running) {
      if (whole) {
        _again = true;
      } else {
        _redrawAgain = true;
      }
      return;
    }
    _running = true;
    try {
      var next = whole;
      while (true) {
        await _pass(whole: next);
        if (!_ref.mounted || !(_again || _redrawAgain)) break;
        // A whole pass redraws too.
        next = _again;
        _again = _redrawAgain = false;
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _pass({required bool whole}) async {
    final container = _ref.container;
    final pids = [
      ...{...container.read(queueControllerProvider).pids},
    ];
    if (pids.isEmpty) {
      if (whole) _missed = false;
      return;
    }
    final repository = container.read(repositoryProvider);
    final playback = container.read(nowPlayingProvider.notifier);
    // By ULID: an item a kind change converted answers under its new prefix.
    final answers = <String, ItemSummary>{};
    final departed = <String>{};
    var missed = false;
    for (var at = 0; at < pids.length; at += itemLookupCap) {
      final ItemResolution resolved;
      try {
        resolved = await repository.resolveItems(
          pids.sublist(at, min(at + itemLookupCap, pids.length)),
        );
      } on Object {
        // Says nothing of these items: they are read again next time.
        missed = true;
        continue;
      }
      if (!_ref.mounted) return;
      for (final item in resolved.items) {
        answers[ulidOf(item.pid)] = item;
      }
      departed.addAll(resolved.departed.map(ulidOf));
    }
    if (!_ref.mounted) return;
    final queued = {for (final pid in pids) ulidOf(pid)};
    _said.removeWhere((ulid, _) => !queued.contains(ulid));
    for (final pid in pids) {
      final ulid = ulidOf(pid);
      final now = answers[ulid];
      if (now == null) continue;
      final row = queueItemProvider(pid);
      final shown = container.exists(row) ? container.read(row).value : null;
      final held = [playback.summaryFor(pid), shown].nonNulls;
      final said = _said[ulid];
      bool changed(ItemSummary was) => switch (was) {
        ComposedSummary() when said != null => !_drawsAs(said, now),
        // No row of the server's yet: only what both reads mean alike.
        ComposedSummary() => was.title != now.title,
        _ => !_drawsAs(was, now),
      };
      final composed = held.any((was) => was is ComposedSummary);
      if (held.any((was) => was.mediaType != now.mediaType)) {
        if (!whole) continue;
        playback.refreshSummary(pid, now);
      } else if (held.any(changed)) {
        if (composed) {
          // Composed again as its play composed it: the server's row is
          // not the line it plays under.
          final BookDetail book;
          try {
            book = await repository.getBook(pid);
          } on Object {
            // Still owed: the next pass finds the same change.
            missed = true;
            continue;
          }
          if (!_ref.mounted) return;
          playback.redrawSummary(pid, bookItemSummary(book));
          _said[ulid] = now;
          if (shown != null) container.invalidate(row);
          continue;
        }
        playback.redrawSummary(pid, now);
      } else {
        if (composed) _said[ulid] = now;
        continue;
      }
      // Held as the server's row from here.
      _said.remove(ulid);
      if (shown != null) container.invalidate(row);
    }
    if (whole) _missed = missed;
    // A playing book's chapter marks, which no lookup row carries.
    await playback.rereadBook();
    if (!_ref.mounted || !whole) return;
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
        .read(shellMessengerProvider)
        .showLocalized((l10n) => l10n.queuePlayingGone);
  }
}

/// Whether [held] draws as [now] does: everything of a row that a surface
/// shows or follows. Not what only a fuller read carries, which the
/// lookup's rows lack.
bool _drawsAs(ItemSummary held, ItemSummary now) =>
    held.title == now.title &&
    held.artist == now.artist &&
    held.album == now.album &&
    held.artistPid == now.artistPid &&
    held.albumPid == now.albumPid &&
    held.trackNumber == now.trackNumber &&
    held.discNumber == now.discNumber &&
    held.durationMs == now.durationMs &&
    held.artUrl == now.artUrl;
