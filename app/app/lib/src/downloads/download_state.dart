import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import '../artwork/artwork_providers.dart';
import '../sync/sync_providers.dart';
import 'wifi_only_gate.dart';

/// Where one item's download to this device stands.
sealed class DownloadState {
  const DownloadState();

  /// The device has not said yet what it holds: nothing to press, and no
  /// state to claim.
  const factory DownloadState.checking() = DownloadChecking;

  /// Nothing on disk and nothing running: the download can start.
  const factory DownloadState.idle() = DownloadIdle;

  /// Running, [DownloadTransferring.fraction] of the way, or held by the
  /// wifi-only gate.
  const factory DownloadState.transferring(double fraction, {bool held}) =
      DownloadTransferring;

  /// Every file is on disk.
  const factory DownloadState.done() = DownloadDone;

  /// The last attempt gave up; starting again is a retry.
  const factory DownloadState.failed({DownloadFailure reason, Object? cause}) =
      DownloadFailed;

  /// This build has no download manager (web).
  const factory DownloadState.unavailable() = DownloadUnavailable;
}

final class DownloadChecking extends DownloadState {
  const DownloadChecking();
}

final class DownloadIdle extends DownloadState {
  const DownloadIdle();
}

final class DownloadTransferring extends DownloadState {
  const DownloadTransferring(this.fraction, {this.held = false});

  /// From 0 to 1 across all the item's files.
  final double fraction;

  /// The wifi-only gate is shut, so nothing moves until it opens.
  final bool held;
}

final class DownloadDone extends DownloadState {
  const DownloadDone();
}

final class DownloadFailed extends DownloadState {
  const DownloadFailed({this.reason = DownloadFailure.interrupted, this.cause});

  /// Why the manager gave the item up.
  final DownloadFailure reason;

  /// What asking for the item threw, when that is how it failed; it says
  /// more than [reason] does.
  final Object? cause;
}

final class DownloadUnavailable extends DownloadState {
  const DownloadUnavailable();
}

/// One item's [DownloadState], and the verb that starts its download.
///
/// Downloading an item is a promise that it plays with the server
/// unreachable, and an offline library of grey monograms does not keep
/// it, so [start] pins the cover beside the audio. Removal is the same
/// pair from the other side, which is the downloads manager's job.
class DownloadStateController extends Notifier<DownloadState> {
  DownloadStateController(this.pid);

  final String pid;

  /// Bumped by every write that reports news, so a probe that answers
  /// after one does not overwrite it with what it read before.
  var _writes = 0;

  /// Whether the wifi-only gate holds transfers back, as last said.
  var _gateShut = false;

  @override
  DownloadState build() {
    final port = ref.watch(downloadManagerProvider);
    if (port == null) return const DownloadState.unavailable();
    final done = ref.watch(_knownDoneProvider);
    // Listened, not watched: the gate moving redraws a transfer, never
    // asks the device again.
    _gateShut =
        ref
            .listen(transfersHeldProvider, (_, next) => _gateSaid(next.value))
            .read()
            .value ??
        false;
    final sub = port.progress.where((p) => p.pid == pid).listen((p) {
      _report(switch (p) {
        DownloadProgress(complete: true) => const DownloadState.done(),
        DownloadProgress(:final failure?) => DownloadState.failed(
          reason: failure,
        ),
        DownloadProgress(stopped: true) => const DownloadState.idle(),
        // Paused reads as a fresh visit reads it: ready to go on.
        DownloadProgress(paused: true) => const DownloadState.idle(),
        _ => DownloadState.transferring(p.fraction),
      });
    });
    ref.onDispose(() => unawaited(sub.cancel()));
    unawaited(_probe(port));
    // Known done this run reads done at once; anything else waits for the
    // device, so a visit never flashes a verb it is about to take back.
    return done.contains(pid)
        ? const DownloadState.done()
        : const DownloadState.checking();
  }

  void _report(DownloadState next) {
    if (!ref.mounted) return;
    _writes++;
    _set(next);
  }

  /// Lands [next], with the gate's hold on a transfer, and remembers a
  /// finished item for the next visit.
  void _set(DownloadState next) {
    final known = ref.read(_knownDoneProvider);
    if (next is DownloadDone) {
      known.add(pid);
    } else {
      known.remove(pid);
    }
    state = switch (next) {
      DownloadTransferring(:final fraction) => DownloadState.transferring(
        fraction,
        // Drawn as transferring only for what the manager moves.
        held: heldForWifi(gateShut: _gateShut, paused: false, active: true),
      ),
      _ => next,
    };
  }

  void _gateSaid(bool? shut) {
    if (!ref.mounted) return;
    _gateShut = shut ?? false;
    if (state case DownloadTransferring(:final fraction)) {
      _set(DownloadState.transferring(fraction));
    }
  }

  /// What the device already holds: a transfer the manager is moving
  /// reads as one, so a reopened screen never offers a second start. One
  /// nothing moves (paused, parked, or rows left behind) reads ready, so
  /// a press takes it up again.
  Future<void> _probe(DownloadManagerPort port) async {
    final before = _writes;
    DownloadState held;
    Error? bug;
    StackTrace? trace;
    try {
      if (await port.isComplete(pid)) {
        held = const DownloadState.done();
      } else {
        final item = await port.storedItem(pid);
        held = item != null && !item.complete && item.active
            ? const DownloadState.transferring(0)
            : const DownloadState.idle();
      }
    } on Object catch (e, s) {
      // A device that will not say leaves the verb on offer rather than
      // a pill nobody can press; a start that fails says why.
      held = const DownloadState.idle();
      if (e is Error) (bug, trace) = (e, s);
    }
    if (ref.mounted && _writes == before) _set(held);
    // Settled first, then still loud: a bug is not the device's answer.
    if (bug != null) Zone.current.handleUncaughtError(bug, trace!);
  }

  /// Downloads the item, its cover with it once the audio is on disk, and
  /// a book's marks for listening where nothing answers.
  ///
  /// Runs to the end with the screen gone: everything it needs is read
  /// before the first wait.
  Future<void> start({String? artUrl}) async {
    final port = ref.read(downloadManagerProvider);
    if (port == null) return;
    final sync = ref.read(syncEngineProvider);
    final artwork = ref.read(artworkStoreProvider);
    _report(const DownloadState.transferring(0));
    // Listen before enqueuing so a fast completion cannot slip past, and
    // stop on any ending: a failed or canceled file never sends the
    // complete event. A manager disposed under it (a sign-out) closes the
    // stream with no ending sent, which reads as a stop.
    final ending = Completer<DownloadProgress>();
    final sub = port.progress.listen(
      (p) {
        if (p.pid == pid &&
            (p.complete || p.failed || p.stopped) &&
            !ending.isCompleted) {
          ending.complete(p);
        }
      },
      onDone: () {
        if (!ending.isCompleted) {
          ending.complete(
            DownloadProgress(
              pid: pid,
              fraction: 0,
              complete: false,
              stopped: true,
            ),
          );
        }
      },
    );
    DownloadProgress? ended;
    Object? cause;
    StackTrace? trace;
    try {
      await port.download(pid);
      if (pid.startsWith('bk-')) unawaited(_fillMarks(sync));
      // Enqueuing a paused item refreshes it and leaves it held.
      if ((await port.storedItem(pid))?.paused ?? false) {
        await port.resume(pid);
      }
      // Everything may already be on disk (a server-side retag): nothing
      // was enqueued, so no event will ever come.
      if (!await port.isComplete(pid)) ended = await ending.future;
    } on Object catch (e, s) {
      (cause, trace) = (e, s);
    } finally {
      // Not awaited: a broadcast subscription is gone at once, and the
      // future its cancel answers belongs to the root zone, which a fake
      // clock never runs.
      unawaited(sub.cancel());
    }
    // Asked again on every path: an item already on disk is downloaded
    // whatever the server said just now.
    var complete = false;
    try {
      complete = await port.isComplete(pid);
    } on Object catch (e, s) {
      if (cause == null) (cause, trace) = (e, s);
    }
    _report(switch ((complete, ended)) {
      (true, _) => const DownloadState.done(),
      _ when cause != null => DownloadState.failed(cause: cause),
      (_, DownloadProgress(stopped: true)) => const DownloadState.idle(),
      (_, DownloadProgress(:final failure?)) => DownloadState.failed(
        reason: failure,
      ),
      _ => const DownloadState.failed(),
    });
    // Settled first, then still loud: a bug is not a failed download.
    if (cause is Error) Zone.current.handleUncaughtError(cause, trace!);
    // Only once the audio is on disk: a pinned cover for an item that
    // cannot play is a promise about nothing.
    if (complete) await artwork.pinForOffline(pid, artUrl);
  }

  Future<void> _fillMarks(SyncEngine? sync) async {
    try {
      await sync?.fillBookmarks(pid);
    } on WaxDeckApiException {
      // The next remint or bookmarks event fills them instead.
    }
  }
}

/// The items this run has seen finish, per manager, so a screen that
/// opens again reads done before the device has answered.
final _knownDoneProvider = Provider<Set<String>>((ref) {
  final port = ref.watch(downloadManagerProvider);
  final known = <String>{};
  // Its own ear on the manager: a removal, cancel or free that no screen
  // was showing still takes the item out.
  final sub = port?.progress.listen((p) {
    if (p.complete) {
      known.add(p.pid);
    } else if (p.stopped || p.failed) {
      known.remove(p.pid);
    }
  });
  ref.onDispose(() => unawaited(sub?.cancel()));
  return known;
});

/// One item's download, for the screens that offer it. Nobody watching
/// means nothing to draw; a [DownloadStateController.start] in flight
/// keeps going without it.
final downloadStateProvider = NotifierProvider.autoDispose
    .family<DownloadStateController, DownloadState, String>(
      DownloadStateController.new,
    );
