import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import 'refresh_in_place.dart';

/// Pacing and deferral for the live invalidation fan-out.
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
///
/// A write this client made is a run of its own, made outside the pacer
/// the moment the server answered, and [PacedRefresh.owe] is how the
/// pacer hears of it: one more run is owed once the server has caught
/// up with itself.
class PacedRefresh {
  PacedRefresh({
    required this.fanOut,
    this.retry,
    this.owed,
    this.window = const Duration(seconds: 1),
  });

  /// Runs the topic's full fan-out. True when fully applied; false when
  /// part of it was deferred and wants a retry at the window's end.
  final bool Function() fanOut;

  /// Applies only what an earlier run deferred, under the same
  /// contract. Null falls back to [fanOut], making retries full runs.
  final bool Function()? retry;

  /// The full fan-out for the run [owe] asked for, on its echo or at the
  /// window's end: that run is the first to see the server caught up
  /// with the write, and a run of hints may not end for a long while
  /// after it. Null falls back to [fanOut].
  final bool Function()? owed;

  /// How close together two runs may come.
  final Duration window;

  Timer? _cooldown;
  var _pendingHint = false;
  var _owesRetry = false;
  var _awaitsEcho = false;

  /// Whether the next full run is the one [owe] asked for.
  var _owedRun = false;
  var _disposed = false;

  /// A change hint for this topic. After [dispose] it is a no-op: a
  /// transport's async tail (a connect future resolving after stop) may
  /// still deliver one, and it must not revive a dead session's timer.
  void hint() {
    if (_disposed) return;
    if (_awaitsEcho) {
      // The echo of the write [owe] was told of: the server has caught
      // up, so the owed run is made now, whatever is left of the window.
      _awaitsEcho = false;
      _pendingHint = false;
      _cooldown?.cancel();
      _cooldown = null;
    }
    if (_cooldown != null) {
      _pendingHint = true;
      return;
    }
    _run(full: true);
  }

  /// The topic's fan-out was just run from outside, for a write this
  /// client made, and one more run is owed: what the server answers the
  /// instant a write returns can lag the write. The run is made on the
  /// next [hint], which the server sends once it has caught up, or at
  /// the window's end when none comes, as [owed] either way. The window
  /// starts over here, so the owed run never shares an instant with the
  /// one it follows, and it covers whatever was pending or deferred
  /// before.
  void owe() {
    if (_disposed) return;
    _cooldown?.cancel();
    _cooldown = Timer(window, _release);
    _pendingHint = true;
    _awaitsEcho = true;
    _owedRun = true;
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
      final run = !full
          ? retry ?? fanOut
          : _owedRun
          ? owed ?? fanOut
          : fanOut;
      final complete = run();
      _owesRetry = !complete;
      // Kept through a throw: the rerun is as owed as this one.
      _owedRun = false;
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
    _awaitsEcho = false;
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
    _awaitsEcho = false;
    _owedRun = false;
  }
}

/// How many quiet spells a run of hints that never pauses waits before
/// [QuietRefresh] runs anyway, and again after each such run.
const kQuietCeiling = 6;

/// Runs a fan-out once its hints stop coming for [quiet]: the trailing
/// edge alone, for a read worth asking again after a run of changes
/// rather than during one. A server is not always silent for that long,
/// so a run that never pauses is also answered [kQuietCeiling] quiet
/// spells after its first hint, and every as many after, for as long as
/// it lasts. What a run left owed (a first build it would not interrupt)
/// is asked again a [quiet] later, under the same contract as
/// [PacedRefresh].
class QuietRefresh {
  QuietRefresh({required this.fanOut, this.retry, required this.quiet});

  final bool Function() fanOut;
  final bool Function()? retry;
  final Duration quiet;

  /// Ends when the hints have stopped for [quiet].
  Timer? _pause;

  /// Ends when the run has gone on for as long as it may unanswered.
  Timer? _ceiling;

  Timer? _retry;

  /// Whether a hint came since the last run.
  var _heard = false;
  var _disposed = false;

  /// A change hint: the run waits for the hints to stop, or for its
  /// ceiling.
  void hint() {
    if (_disposed) return;
    _heard = true;
    _retry?.cancel();
    _retry = null;
    _pause?.cancel();
    _pause = Timer(quiet, _paused);
    _ceiling ??= Timer(quiet * kQuietCeiling, _reachedCeiling);
  }

  void _paused() {
    _pause = null;
    _ceiling?.cancel();
    _ceiling = null;
    // The ceiling's run already answered every hint before it.
    if (_heard) _run(full: true);
  }

  void _reachedCeiling() {
    _ceiling = Timer(quiet * kQuietCeiling, _reachedCeiling);
    _run(full: true);
  }

  void _run({required bool full}) {
    _retry?.cancel();
    _retry = null;
    if (_disposed) return;
    _heard = false;
    final complete = full ? fanOut() : (retry ?? fanOut)();
    if (!complete) _retry = Timer(quiet, () => _run(full: false));
  }

  /// Drops whatever is pending and ignores every later call.
  void dispose() {
    _disposed = true;
    for (final timer in [_pause, _ceiling, _retry]) {
      timer?.cancel();
    }
    _pause = null;
    _ceiling = null;
    _retry = null;
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
///
/// It keeps, the same way, which providers hold an error: a read that
/// failed and was not asked again since, which a reconnect asks again
/// whatever the server says changed.
final class FirstBuildObserver extends ProviderObserver {
  final _building = <ProviderBase<Object?>>{};
  final _errored = <ProviderBase<Object?>>{};

  /// Whether [provider]'s first build is in flight: its state is a bare
  /// loading, with no previous value to show and no error. That is
  /// exactly the skeleton condition - a refresh keeps the old data and
  /// a reload copies it forward, so neither reads as bare.
  bool inFirstBuild(ProviderBase<Object?> provider) =>
      _building.contains(provider);

  /// Whether [provider]'s state holds an error: failed, or retrying
  /// after a failure.
  bool inError(ProviderBase<Object?> provider) => _errored.contains(provider);

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
    if (state is AsyncValue<Object?> && state.hasError) {
      _errored.add(provider);
    } else {
      _errored.remove(provider);
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
    _errored.remove(context.provider);
  }

  @override
  void didUnmountProvider(ProviderObserverContext context) {
    _building.remove(context.provider);
    _errored.remove(context.provider);
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
    this.pagedProviders = const [],
    this.pagedFamilies = const [],
    this.owed,
    this.failed,
    this.firstBuilds,
    this.prelude,
  }) : assert(
         owed != null || (pagedProviders.isEmpty && pagedFamilies.isEmpty),
         'a paged listing is told its depth through the ledger',
       );

  final ProviderContainer container;

  /// The topic's plain providers, invalidated as themselves.
  final List<ProviderBase<Object?>> providers;

  /// The topic's families, applied per live instance so one instance
  /// mid-first-build defers alone rather than holding back the family.
  final List<Family> families;

  /// Those of [providers] and [families] that page and refresh in place.
  /// A sweep tells each, through [owed], the depth it owes before it
  /// invalidates it.
  final List<ProviderBase<Object?>> pagedProviders;
  final List<Family> pagedFamilies;
  final OwedDepths? owed;

  /// The paged listings whose last refresh failed, for [sweepUnhealthy].
  final FailedRefreshes? failed;

  /// The ledger of in-flight first builds. Null means no ledger is
  /// registered and everything is invalidated unconditionally, which is
  /// the pre-deferral behavior.
  final FirstBuildObserver? firstBuilds;

  /// Runs at the head of every full [sweep], for the topic's
  /// non-invalidation work (the artwork negative cache). Not run on
  /// [retry]: a retry carries no new information about the world.
  final void Function()? prelude;

  /// What a run left alone mid-first-build, owed an invalidation.
  final _deferred = <ProviderBase<Object?>>{};

  /// The full fan-out, each paged listing owed [depth]. A deferred one
  /// keeps the depth it was told for the retry that reaches it.
  bool sweep([CatalogRefresh depth = CatalogRefresh.head]) {
    prelude?.call();
    _deferred.clear();
    owed?.prune();
    for (final family in families) {
      final paged = pagedFamilies.contains(family);
      // Snapshotted: invalidation schedules work on the container, and
      // the enumeration should not be live while it happens.
      for (final reference in container.allProviders(family: family).toList()) {
        if (paged) owed?.owe(reference.provider, depth);
        _apply(reference.provider);
      }
    }
    for (final provider in providers) {
      if (pagedProviders.contains(provider)) owed?.owe(provider, depth);
      _apply(provider);
    }
    return _deferred.isEmpty;
  }

  /// Invalidates only the reads that are not current: one that holds an
  /// error, and a paged listing whose last refresh failed, owed the extent
  /// it held, as a run's quiet edge reads it, which may have failed too.
  /// With no ledger nothing can be told apart, and every read is swept.
  /// What it defers joins what a [retry] applies.
  bool sweepUnhealthy() {
    final ledger = firstBuilds;
    failed?.prune();
    bool unhealthy(ProviderBase<Object?> provider) =>
        ledger == null ||
        ledger.inError(provider) ||
        (failed?.failedLast(provider) ?? false);
    for (final family in families) {
      final paged = pagedFamilies.contains(family);
      for (final reference in container.allProviders(family: family).toList()) {
        final provider = reference.provider;
        if (!unhealthy(provider)) continue;
        if (paged) owed?.owe(provider, CatalogRefresh.loaded);
        _apply(provider);
      }
    }
    for (final provider in providers) {
      if (!unhealthy(provider)) continue;
      if (pagedProviders.contains(provider)) {
        owed?.owe(provider, CatalogRefresh.loaded);
      }
      _apply(provider);
    }
    return _deferred.isEmpty;
  }

  bool retry() {
    final deferred = _deferred.toList();
    _deferred.clear();
    deferred.forEach(_apply);
    return _deferred.isEmpty;
  }

  void _apply(ProviderBase<Object?> provider) {
    if (firstBuilds?.inFirstBuild(provider) ?? false) {
      _deferred.add(provider);
      return;
    }
    // On an instance that has since been disposed this is a no-op, and
    // on an unwatched one it only marks: the rebuild stays lazy until
    // the next reader, so deferred work never becomes invented work.
    container.invalidate(provider);
  }
}
