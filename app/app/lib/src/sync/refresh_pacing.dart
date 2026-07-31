import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

/// Pacing and deferral for the live invalidation fan-out (ADR-0036).
///
/// The server already coalesces change hints into a 250 ms window per
/// topic, which bounds what arrives but not what it costs: each hint
/// invalidates every controller the topic touches, and both the catalog
/// and the user topic reach a dozen of them, so a busy server had this
/// client refetching whole screens several times a second.
///
/// The refetch itself is harmless where a provider already holds a
/// value - riverpod keeps the old data through a refresh and the screen
/// never blinks. What it is not harmless for is a provider whose
/// *first* build is still in flight: the rebuild abandons that work and
/// starts over, so a screen opened while another device is busy can be
/// held on its skeleton for as long as the hints keep coming. A
/// playlist detail is the worst of them (a read plus a page walk,
/// restarted from the top each time), and it is what first surfaced
/// this, as an e2e timeout waiting for a screen that never left its
/// skeleton.
///
/// Two mechanisms close it, split across the classes below:
///
/// [PacedRefresh] paces each topic. The first hint after a quiet spell
/// runs the fan-out at once - a lone change still lands immediately,
/// which the live-update surfaces are about - and hints arriving inside
/// the window collapse into one at its end. A stream of them costs one
/// fan-out per window instead of one per hint.
///
/// [InvalidationFanOut] makes the run itself skip any provider whose
/// first build is in flight, so the build is never interrupted at all:
/// the skipped instance is owed an invalidation, and the pacer retries
/// at the next window's end until the build has landed and the
/// invalidation can be applied. A build slower than the window is not
/// restarted; it finishes, and the data it fetched before the change is
/// replaced one window later.
class PacedRefresh {
  PacedRefresh({
    required this.fanOut,
    this.retry,
    this.window = const Duration(seconds: 1),
  });

  /// Runs the topic's full fan-out. True when fully applied; false when
  /// part of it was deferred and wants a retry at the window's end.
  final bool Function() fanOut;

  /// Applies only what an earlier run deferred, under the same
  /// contract. Null falls back to [fanOut], making retries full runs.
  final bool Function()? retry;

  /// How close together two runs may come.
  final Duration window;

  Timer? _cooldown;
  var _pendingHint = false;
  var _owesRetry = false;
  var _disposed = false;

  /// A change hint for this topic. After [dispose] it is a no-op: a
  /// transport's async tail (a connect future resolving after stop) may
  /// still deliver one, and it must not revive a dead session's timer.
  void hint() {
    if (_disposed) return;
    if (_cooldown != null) {
      _pendingHint = true;
      return;
    }
    _run(full: true);
  }

  void _run({required bool full}) {
    if (_disposed) return;
    // The window stands even when the run throws: an exception surfaces
    // (it is a bug in the fan-out, worth hearing about), but it must
    // not turn the pacer into a per-hint pass-through. And a hint is
    // only consumed by a run that finished - a throw partway leaves an
    // unknown remainder untouched, so the hint stays pending and the
    // next window re-runs in full, which also supersedes whatever
    // partial debt the broken run left behind.
    try {
      final complete = full ? fanOut() : (retry ?? fanOut)();
      _owesRetry = !complete;
    } catch (_) {
      _pendingHint = true;
      rethrow;
    } finally {
      _cooldown = Timer(window, _release);
    }
  }

  void _release() {
    if (_disposed) return;
    _cooldown = null;
    // A hint outranks a retry: the full run covers everything a partial
    // one would have, and recomputes what is owed from scratch.
    if (_pendingHint) {
      _pendingHint = false;
      _run(full: true);
    } else if (_owesRetry) {
      _owesRetry = false;
      _run(full: false);
    }
  }

  /// Drops whatever is pending and ignores every later call. For a
  /// signed-out session: the providers a run would invalidate are going
  /// away with it.
  void dispose() {
    _disposed = true;
    _cooldown?.cancel();
    _cooldown = null;
    _pendingHint = false;
    _owesRetry = false;
  }
}

/// Which providers are mid-first-build right now, kept from the
/// observer hooks. Registered on the app's root container in main.dart;
/// [InvalidationFanOut] reads it to know what not to interrupt.
///
/// An observer because it is the one way to know a provider's state
/// without touching it: every read path riverpod exposes flushes a
/// dirty element as a side effect, and the fan-out deliberately leaves
/// unwatched elements dirty (an invalidation only marks them; the
/// rebuild waits for the next reader). Probing by read would have
/// turned that mark into a fetch nobody asked for, on every sweep, for
/// every once-opened screen. The hooks carry the states passively:
/// birth and every change, with disposal pruning the set.
final class FirstBuildObserver extends ProviderObserver {
  final _building = <ProviderBase<Object?>>{};

  /// Whether [provider]'s first build is in flight: its state is a bare
  /// loading, with no previous value to show and no error. That is
  /// exactly the skeleton condition - a refresh keeps the old data and
  /// a reload copies it forward, so neither reads as bare.
  bool inFirstBuild(ProviderBase<Object?> provider) =>
      _building.contains(provider);

  static bool _isBareLoading(Object? state) =>
      state is AsyncValue<Object?> &&
      state.isLoading &&
      !state.hasValue &&
      !state.hasError;

  void _track(ProviderBase<Object?> provider, Object? state) {
    if (_isBareLoading(state)) {
      _building.add(provider);
    } else {
      _building.remove(provider);
    }
  }

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    _track(context.provider, value);
  }

  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    _track(context.provider, newValue);
  }

  /// Fires when a provider's `onDispose` listeners run, which happens
  /// on every invalidation - and an invalidation *cancels* the build in
  /// flight (`runOnDispose` stops listening to the async operation), so
  /// the landing this entry was waiting for will never notify. Without
  /// this prune, a keep-alive instance invalidated mid-first-build from
  /// outside the fan-out (`appendTo` invalidating an unwatched detail,
  /// a delete invalidating the grid) stayed in the ledger for the life
  /// of the session, deferred forever, re-arming its topic's retry
  /// timer forever. There is no build left to protect; the entry goes
  /// with it. The narrow cost: a *watched* instance invalidated
  /// mid-first-build rebuilds into a bare loading equal to its old one,
  /// which notifies nobody, so until a differing state lands that one
  /// instance is invisible to the ledger and rides plain pacing - the
  /// pre-deferral behavior, not a new failure.
  @override
  void didDisposeProvider(ProviderObserverContext context) {
    _building.remove(context.provider);
  }

  @override
  void didUnmountProvider(ProviderObserverContext context) {
    _building.remove(context.provider);
  }
}

/// One topic's invalidation set, applied without interrupting first
/// builds. [sweep] is the full fan-out for a fresh hint; [retry]
/// re-attempts only what a previous run deferred. Both answer whether
/// everything was applied, which is what [PacedRefresh] schedules on.
class InvalidationFanOut {
  InvalidationFanOut({
    required this.container,
    this.providers = const [],
    this.families = const [],
    this.firstBuilds,
    this.prelude,
  });

  final ProviderContainer container;

  /// The topic's plain providers, invalidated as themselves.
  final List<ProviderBase<Object?>> providers;

  /// The topic's families, applied per live instance so one instance
  /// mid-first-build defers alone rather than holding back the family.
  final List<Family> families;

  /// The ledger of in-flight first builds. Null means no ledger is
  /// registered and everything is invalidated unconditionally, which is
  /// the pre-deferral behavior.
  final FirstBuildObserver? firstBuilds;

  /// Runs at the head of every full [sweep], for the topic's
  /// non-invalidation work (the artwork negative cache). Not run on
  /// [retry]: a retry carries no new information about the world.
  final void Function()? prelude;

  /// What a run left alone mid-first-build, owed an invalidation.
  final _owed = <ProviderBase<Object?>>{};

  bool sweep() {
    prelude?.call();
    _owed.clear();
    for (final family in families) {
      // Snapshotted: invalidation schedules work on the container, and
      // the enumeration should not be live while it happens.
      for (final reference in container.allProviders(family: family).toList()) {
        _apply(reference.provider);
      }
    }
    providers.forEach(_apply);
    return _owed.isEmpty;
  }

  bool retry() {
    final owed = _owed.toList();
    _owed.clear();
    owed.forEach(_apply);
    return _owed.isEmpty;
  }

  void _apply(ProviderBase<Object?> provider) {
    if (firstBuilds?.inFirstBuild(provider) ?? false) {
      _owed.add(provider);
      return;
    }
    // On an instance that has since been disposed this is a no-op, and
    // on an unwatched one it only marks: the rebuild stays lazy until
    // the next reader, so deferred work never becomes invented work.
    container.invalidate(provider);
  }
}
