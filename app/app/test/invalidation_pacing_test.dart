import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/playlists/playlist_screen.dart';
import 'package:waxdeck/src/playlists/playlists_controller.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/sync/refresh_pacing.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';
import 'routed_host.dart';

// The starvation ADR-0036 closes: a live invalidation used to rebuild
// every controller its topic touched, and a rebuild landing on a
// provider still doing its *first* build abandons work it cannot
// cancel, so hints arriving faster than a build completes held the
// screen on its skeleton for as long as they kept coming. The pacer
// bounds how often the fan-out runs; the ledger and the fan-out below
// keep a run from touching an in-flight first build at all, so even a
// build slower than the pacer's window finishes and renders.

const _track = ItemSummary(
  pid: 'tr-01JZX5N8QW3F4V9T2B7KD3M9R6',
  mediaType: MediaType.music,
  title: 'Prancing Pony Blues',
  artist: 'The Bree Trio',
  durationMs: 214000,
);

/// Holds one playlist's `getPlaylist` behind [gate], so a test can keep
/// that detail's first build in flight for exactly as long as it needs
/// while every other playlist stays readable. Completed detail builds
/// are visible through the base fake's `playlistItemPageCalls`.
class _GatedRepository extends FakeRepository {
  _GatedRepository({super.items});

  Completer<void>? gate;
  String? gatedPid;
  var listingReads = 0;

  @override
  Future<Playlist> getPlaylist(String pid) async {
    final g = gate;
    if (g != null && pid == gatedPid) await g.future;
    return super.getPlaylist(pid);
  }

  @override
  Future<PlaylistPage> listPlaylists({
    String? cursor,
    int? limit,
    String? containsItem,
  }) async {
    listingReads++;
    return super.listPlaylists(
      cursor: cursor,
      limit: limit,
      containsItem: containsItem,
    );
  }
}

/// Reads slow enough that a detail's first build outlasts the pacer's
/// window, which is the case pacing alone could not save.
class _SlowRepository extends FakeRepository {
  _SlowRepository({super.items});

  static const latency = Duration(milliseconds: 700);

  @override
  Future<Playlist> getPlaylist(String pid) async {
    await Future<void>.delayed(latency);
    return super.getPlaylist(pid);
  }

  @override
  Future<PlaylistItemsPage> listPlaylistItems(
    String pid, {
    String? cursor,
    int? limit,
  }) async {
    await Future<void>.delayed(latency);
    return super.listPlaylistItems(pid, cursor: cursor, limit: limit);
  }
}

void main() {
  group('PacedRefresh', () {
    testWidgets('the first hint after a quiet spell fans out at once', (
      tester,
    ) async {
      var runs = 0;
      final paced = PacedRefresh(
        fanOut: () {
          runs++;
          return true;
        },
      );

      paced.hint();
      expect(runs, 1, reason: 'a lone change still lands immediately');
      paced.dispose();
    });

    testWidgets('hints inside the window collapse into one at its end', (
      tester,
    ) async {
      var runs = 0;
      final paced = PacedRefresh(
        fanOut: () {
          runs++;
          return true;
        },
      );

      paced.hint();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        paced.hint();
      }
      expect(runs, 1, reason: 'the window is still open');

      await tester.pump(const Duration(seconds: 1));
      expect(runs, 2, reason: 'the ones that arrived during it, as one');

      // And nothing more: the collapsed fan-out already covered them.
      await tester.pump(const Duration(seconds: 5));
      expect(runs, 2);
      paced.dispose();
    });

    testWidgets('a sustained stream costs one fan-out per window', (
      tester,
    ) async {
      var runs = 0;
      final paced = PacedRefresh(
        fanOut: () {
          runs++;
          return true;
        },
      );

      // The server's own ceiling: a hint per topic per 250 ms, and both
      // topics reach the same controllers.
      for (var tick = 0; tick < 40; tick++) {
        paced.hint();
        await tester.pump(const Duration(milliseconds: 125));
      }
      expect(runs, 6, reason: '5 seconds of hints, one fan-out per second');
      paced.dispose();
    });

    testWidgets('an incomplete run retries at the window, not before', (
      tester,
    ) async {
      var sweeps = 0;
      var retries = 0;
      var complete = false;
      final paced = PacedRefresh(
        fanOut: () {
          sweeps++;
          return complete;
        },
        retry: () {
          retries++;
          return complete;
        },
      );

      paced.hint();
      expect(sweeps, 1);
      expect(retries, 0);

      // Still owed at the first window's end, applied at the second.
      await tester.pump(const Duration(seconds: 1));
      expect(retries, 1, reason: 'the deferred part is re-attempted');
      complete = true;
      await tester.pump(const Duration(seconds: 1));
      expect(retries, 2, reason: 'retries continue until one completes');
      await tester.pump(const Duration(seconds: 5));
      expect(retries, 2, reason: 'a complete retry ends the loop');
      expect(sweeps, 1, reason: 'no hint arrived, so no full run');
      paced.dispose();
    });

    testWidgets('a hint during the cooldown outranks the owed retry', (
      tester,
    ) async {
      var sweeps = 0;
      var retries = 0;
      final paced = PacedRefresh(
        fanOut: () {
          sweeps++;
          return sweeps > 1;
        },
        retry: () {
          retries++;
          return true;
        },
      );

      paced.hint();
      paced.hint();
      await tester.pump(const Duration(seconds: 1));
      expect(sweeps, 2, reason: 'the full run covers what the retry would');
      expect(retries, 0);
      await tester.pump(const Duration(seconds: 5));
      expect(retries, 0, reason: 'the full run recomputed what was owed');
      paced.dispose();
    });

    testWidgets('disposal drops the pending retry and hint alike', (
      tester,
    ) async {
      var runs = 0;
      final paced = PacedRefresh(
        fanOut: () {
          runs++;
          return false;
        },
      );

      paced.hint();
      paced.hint();
      paced.dispose();
      await tester.pump(const Duration(seconds: 5));
      expect(runs, 1, reason: 'the trailing work belonged to a live session');
    });

    testWidgets('a hint after disposal is a no-op', (tester) async {
      var runs = 0;
      final paced = PacedRefresh(
        fanOut: () {
          runs++;
          return true;
        },
      );

      paced.dispose();
      // The web transport's connect future can resolve after stop() and
      // deliver a hint to a pacer whose session is already gone.
      paced.hint();
      expect(runs, 0, reason: 'a dead pacer runs nothing');
      await tester.pump(const Duration(seconds: 5));
      expect(runs, 0, reason: 'and schedules nothing either');
    });

    testWidgets('a throwing run keeps the window and the hint', (tester) async {
      var runs = 0;
      var explode = true;
      final paced = PacedRefresh(
        fanOut: () {
          runs++;
          if (explode) throw StateError('fan-out bug');
          return true;
        },
      );

      expect(paced.hint, throwsStateError);
      expect(runs, 1, reason: 'the exception surfaces to the caller');

      // No second hint: the thrown one was not consumed, so it re-runs
      // on its own at the window's end - a throw partway leaves an
      // unknown remainder, and a lost hint would stay lost until the
      // next unrelated change.
      explode = false;
      await tester.pump(const Duration(seconds: 1));
      expect(runs, 2, reason: 'the broken run did not consume the hint');
      await tester.pump(const Duration(seconds: 5));
      expect(runs, 2, reason: 'and the clean re-run did');
      paced.dispose();
    });

    testWidgets('a throwing retry escalates to a full run', (tester) async {
      var sweeps = 0;
      var retries = 0;
      final paced = PacedRefresh(
        fanOut: () {
          sweeps++;
          return sweeps > 1;
        },
        retry: () {
          retries++;
          throw StateError('retry bug');
        },
      );

      // The timers fire in the zone the first hint created them in, so
      // guarding the hint is what catches the retry's timer-fired throw.
      final surfaced = <Object>[];
      runZonedGuarded(paced.hint, (error, _) => surfaced.add(error));
      expect(sweeps, 1, reason: 'the first sweep defers something');
      await tester.pump(const Duration(seconds: 1));
      expect(surfaced, [isA<StateError>()]);
      expect(retries, 1, reason: 'the retry ran and broke');
      // A broken retry's coverage is unknown, so the next window runs
      // the full sweep, which recomputes what is owed from scratch.
      await tester.pump(const Duration(seconds: 1));
      expect(sweeps, 2, reason: 'escalated to the full sweep');
      await tester.pump(const Duration(seconds: 5));
      expect(retries, 1);
      expect(sweeps, 2);
      paced.dispose();
    });
  });

  group('FirstBuildObserver', () {
    test('tracks a first build from birth to landing', () async {
      final observer = FirstBuildObserver();
      final repository = _GatedRepository(items: const [_track]);
      final created = await repository.createPlaylist(
        name: 'By Hand',
        kind: 'static',
      );
      final container = ProviderContainer(
        overrides: [repositoryProvider.overrideWithValue(repository)],
        observers: [observer],
      );
      addTearDown(container.dispose);

      repository.gatedPid = created.pid;
      final gate = repository.gate = Completer<void>();
      final instance = playlistDetailProvider(created.pid);
      final sub = container.listen(instance, (_, _) {});
      addTearDown(sub.close);
      expect(observer.inFirstBuild(instance), isTrue);

      gate.complete();
      repository.gate = null;
      await container.read(instance.future);
      expect(observer.inFirstBuild(instance), isFalse);

      // A refresh is not a first build: the previous value rides along,
      // so the screen never shows a skeleton and the ledger stays out.
      container.invalidate(instance);
      expect(observer.inFirstBuild(instance), isFalse);
      await container.read(instance.future);
      expect(observer.inFirstBuild(instance), isFalse);
    });

    test(
      'an invalidation that cancels a first build prunes its entry',
      () async {
        final observer = FirstBuildObserver();
        final repository = _GatedRepository(items: const [_track]);
        final created = await repository.createPlaylist(
          name: 'By Hand',
          kind: 'static',
        );
        final container = ProviderContainer(
          overrides: [repositoryProvider.overrideWithValue(repository)],
          observers: [observer],
        );
        addTearDown(container.dispose);
        final fanOut = InvalidationFanOut(
          container: container,
          firstBuilds: observer,
          families: [playlistDetailProvider],
        );

        repository.gatedPid = created.pid;
        final gate = repository.gate = Completer<void>();
        final instance = playlistDetailProvider(created.pid);
        final sub = container.listen(instance, (_, _) {});
        expect(observer.inFirstBuild(instance), isTrue);

        // The screen leaves mid-build; the keep-alive element stays,
        // still building. A mutation then invalidates it from outside
        // the fan-out (appendTo on an unopened playlist has exactly this
        // shape), which cancels the build: the landing this entry was
        // waiting for will never notify.
        sub.close();
        container.invalidate(instance);
        expect(
          observer.inFirstBuild(instance),
          isFalse,
          reason: 'a cancelled build is pruned, not deferred forever',
        );
        expect(
          fanOut.sweep(),
          isTrue,
          reason: 'nothing is owed for it, so no retry timer re-arms',
        );
        gate.complete();
      },
    );
  });

  group('InvalidationFanOut', () {
    test(
      'defers the building instance and invalidates the loaded one',
      () async {
        final observer = FirstBuildObserver();
        final repository = _GatedRepository(items: const [_track]);
        final loaded = await repository.createPlaylist(
          name: 'Loaded',
          kind: 'static',
        );
        final opening = await repository.createPlaylist(
          name: 'Opening',
          kind: 'static',
        );
        final container = ProviderContainer(
          overrides: [repositoryProvider.overrideWithValue(repository)],
          observers: [observer],
        );
        addTearDown(container.dispose);
        final fanOut = InvalidationFanOut(
          container: container,
          firstBuilds: observer,
          families: [playlistDetailProvider],
        );
        int builds(String pid) =>
            repository.playlistItemPageCalls.where((p) => p == pid).length;

        final loadedSub = container.listen(
          playlistDetailProvider(loaded.pid),
          (_, _) {},
        );
        addTearDown(loadedSub.close);
        await container.read(playlistDetailProvider(loaded.pid).future);
        expect(builds(loaded.pid), 1);

        repository.gatedPid = opening.pid;
        final gate = repository.gate = Completer<void>();
        final openingSub = container.listen(
          playlistDetailProvider(opening.pid),
          (_, _) {},
        );
        addTearDown(openingSub.close);

        expect(fanOut.sweep(), isFalse, reason: 'one instance was deferred');
        await container.read(playlistDetailProvider(loaded.pid).future);
        expect(builds(loaded.pid), 2, reason: 'the loaded instance refetched');
        expect(
          builds(opening.pid),
          0,
          reason: 'the building one was left alone',
        );

        // Still in flight at the retry: still deferred, still untouched.
        expect(fanOut.retry(), isFalse);

        gate.complete();
        repository.gate = null;
        await container.read(playlistDetailProvider(opening.pid).future);
        expect(
          builds(opening.pid),
          1,
          reason: 'exactly one build: the first was never restarted',
        );

        expect(fanOut.retry(), isTrue, reason: 'the landing releases the debt');
        await container.read(playlistDetailProvider(opening.pid).future);
        expect(
          builds(opening.pid),
          2,
          reason: 'the deferred invalidation applied once the build landed',
        );
      },
    );

    test('without the ledger everything invalidates at once', () async {
      final repository = _GatedRepository(items: const [_track]);
      final created = await repository.createPlaylist(
        name: 'By Hand',
        kind: 'static',
      );
      final container = ProviderContainer(
        overrides: [repositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final fanOut = InvalidationFanOut(
        container: container,
        families: [playlistDetailProvider],
      );

      repository.gatedPid = created.pid;
      final gate = repository.gate = Completer<void>();
      final sub = container.listen(
        playlistDetailProvider(created.pid),
        (_, _) {},
      );
      addTearDown(sub.close);

      expect(
        fanOut.sweep(),
        isTrue,
        reason: 'no ledger means nothing defers: the pre-deferral behavior',
      );
      gate.complete();
      repository.gate = null;
    });

    test(
      'an unwatched invalidation stays lazy: no build is triggered',
      () async {
        final observer = FirstBuildObserver();
        final repository = _GatedRepository(items: const [_track]);
        await repository.createPlaylist(name: 'By Hand', kind: 'static');
        final container = ProviderContainer(
          overrides: [repositoryProvider.overrideWithValue(repository)],
          observers: [observer],
        );
        addTearDown(container.dispose);
        final fanOut = InvalidationFanOut(
          container: container,
          firstBuilds: observer,
          providers: [playlistsProvider],
        );

        // Built once, then left: the keep-alive element persists with no
        // listener, which is every screen the user has visited and left.
        final sub = container.listen(playlistsProvider, (_, _) {});
        await container.read(playlistsProvider.future);
        sub.close();
        expect(repository.listingReads, 1);

        for (var i = 0; i < 3; i++) {
          expect(fanOut.sweep(), isTrue);
          await container.pump();
        }
        expect(
          repository.listingReads,
          1,
          reason: 'marking an unwatched element dirty must not rebuild it',
        );

        // The mark was real: the next watcher rebuilds from it.
        final again = container.listen(playlistsProvider, (_, _) {});
        addTearDown(again.close);
        await container.read(playlistsProvider.future);
        expect(repository.listingReads, 2);
      },
    );

    test('a provider outside the targets is untouched', () async {
      final observer = FirstBuildObserver();
      final repository = _GatedRepository(items: const [_track]);
      final created = await repository.createPlaylist(
        name: 'By Hand',
        kind: 'static',
      );
      final container = ProviderContainer(
        overrides: [repositoryProvider.overrideWithValue(repository)],
        observers: [observer],
      );
      addTearDown(container.dispose);
      final fanOut = InvalidationFanOut(
        container: container,
        firstBuilds: observer,
        providers: [playlistsProvider],
      );

      final sub = container.listen(
        playlistDetailProvider(created.pid),
        (_, _) {},
      );
      addTearDown(sub.close);
      await container.read(playlistDetailProvider(created.pid).future);
      final builds = repository.playlistItemPageCalls.length;

      expect(fanOut.sweep(), isTrue);
      await container.pump();
      await container.read(playlistDetailProvider(created.pid).future);
      expect(repository.playlistItemPageCalls.length, builds);
    });
  });

  testWidgets('a first build slower than the window still lands', (
    tester,
  ) async {
    final observer = FirstBuildObserver();
    final repository = _SlowRepository(items: const [_track]);
    final created = await repository.createPlaylist(
      name: 'By Hand',
      kind: 'static',
    );
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repository),
        filePickerProvider.overrideWithValue(null),
      ],
      observers: [observer],
    );
    addTearDown(container.dispose);
    final fanOut = InvalidationFanOut(
      container: container,
      firstBuilds: observer,
      families: [playlistDetailProvider],
    );
    final paced = PacedRefresh(fanOut: fanOut.sweep, retry: fanOut.retry);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(PlaylistScreen(pid: created.pid), pushed: true),
      ),
    );

    // Five seconds of an unrelenting server. The build takes 1.4 s
    // against a 1 s window, so pacing alone restarts it forever; the
    // deferral is what lets it land.
    var settled = false;
    for (var tick = 0; tick < 40; tick++) {
      paced.hint();
      await tester.pump(const Duration(milliseconds: 125));
      if (_showsAddField()) settled = true;
    }
    paced.dispose();
    expect(
      settled,
      isTrue,
      reason: 'the first build finished while the hints kept coming',
    );
    // Lets the deferred invalidation's own refetch land.
    for (var i = 0; i < 6; i++) {
      await tester.pump(_SlowRepository.latency * 2);
    }
    expect(_showsAddField(), isTrue);
  });

  testWidgets('without the ledger the same storm starves the build', (
    tester,
  ) async {
    final repository = _SlowRepository(items: const [_track]);
    final created = await repository.createPlaylist(
      name: 'By Hand',
      kind: 'static',
    );
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repository),
        filePickerProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);
    // No FirstBuildObserver: this is the pre-deferral wiring, kept
    // failing on purpose so the mechanism above cannot quietly rot.
    final fanOut = InvalidationFanOut(
      container: container,
      families: [playlistDetailProvider],
    );
    final paced = PacedRefresh(fanOut: fanOut.sweep, retry: fanOut.retry);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(PlaylistScreen(pid: created.pid), pushed: true),
      ),
    );

    var settled = false;
    for (var tick = 0; tick < 40; tick++) {
      paced.hint();
      await tester.pump(const Duration(milliseconds: 125));
      if (_showsAddField()) settled = true;
    }
    paced.dispose();
    expect(
      settled,
      isFalse,
      reason: 'a 1.4 s build never survives 1 s restart windows',
    );
    // The storm over, the last restart completes.
    for (var i = 0; i < 6; i++) {
      await tester.pump(_SlowRepository.latency * 2);
    }
    expect(_showsAddField(), isTrue);
  });
}

bool _showsAddField() => find
    .bySemanticsIdentifier(SemanticsIds.playlistAddField)
    .evaluate()
    .isNotEmpty;
