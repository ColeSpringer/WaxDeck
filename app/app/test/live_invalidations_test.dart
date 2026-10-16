import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/home/home_shelves.dart';
import 'package:waxdeck/src/player/entity_play_state_controller.dart';
import 'package:waxdeck/src/player/play_progress.dart';
import 'package:waxdeck/src/player/play_state_controller.dart';
import 'package:waxdeck/src/playlists/playlists_controller.dart';
import 'package:waxdeck/src/podcasts/podcast_shelves.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/prefs_controller.dart';
import 'package:waxdeck/src/sync/live_invalidations.dart';
import 'package:waxdeck/src/sync/server_event_bus.dart';
import 'package:waxdeck/src/sync/sync_binder.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

/// A channel whose connect resolves only when the test says so, which
/// is what a sign-out racing a slow handshake looks like.
class _GatedChannel extends EventsChannel {
  _GatedChannel({
    required this.gate,
    required super.onFrame,
    required super.onDone,
    required super.subscribe,
  }) : super(url: 'ws://gated', authToken: null);

  final Completer<void> gate;

  @override
  Future<void> connect() => gate.future;

  @override
  Future<void> close() async {}
}

/// Counts what the user fan-out and the entity fan-out cost.
class _CountingRepository extends FakeRepository {
  int prefsReads = 0;
  int entityReads = 0;

  @override
  Future<Prefs> getPrefs() {
    prefsReads++;
    return super.getPrefs();
  }

  @override
  Future<EntityPlayState> getEntityPlayState(String pid) {
    entityReads++;
    return super.getEntityPlayState(pid);
  }

  /// When set, a batch read answers the states as they were when it was
  /// asked, but only once this completes: a read still out while the
  /// stream reports what happened after it.
  Completer<void>? statesGate;

  @override
  Future<List<PlayState>> listPlayStates(List<String> pids) async {
    final read = await super.listPlayStates(pids);
    await statesGate?.future;
    return read;
  }
}

/// A session without a sync engine, which is the web build's: the binder
/// hears the user stream through [bus], fed by hand here rather than by
/// the walk an invalidation frame starts.
Future<
  ({ProviderContainer container, ServerEventBus bus, _CountingRepository repo})
>
_bindWeb() async {
  final repo = _CountingRepository()
    ..sessionState = const SessionState(
      authenticated: true,
      user: WaxDeckUser(id: 'us-1', username: 'admin'),
    )
    ..libraryItems.add(testItem('tr-A'))
    // Heard through once and part way through again, which is what puts
    // a track on the resume shelf.
    ..playPositions['tr-A'] = 1000
    ..playStateLastPlayedAt['tr-A'] = DateTime.utc(2026, 9, 30);
  final bus = ServerEventBus();
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      audioEngineProvider.overrideWithValue(FakeEngine()),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      artworkStoreProvider.overrideWithValue(FakeArtworkStore()),
      serverEventBusProvider.overrideWithValue(bus),
    ],
  );
  addTearDown(container.dispose);
  container
    ..listen(syncBinderProvider, (_, _) {})
    ..listen(prefsControllerProvider, (_, _) {})
    ..listen(continueListeningShelfProvider, (_, _) {});
  await container.read(prefsControllerProvider.future);
  final resume = await container.read(continueListeningShelfProvider.future);
  expect(resume.items.map((item) => item.pid), <String>['tr-A']);
  return (container: container, bus: bus, repo: repo);
}

ServerSyncEvent _report(
  int positionMs, {
  bool finished = false,
  int minute = 0,
}) => ServerSyncEvent(
  kind: 'play-state',
  pid: 'tr-A',
  playState: PlayState(
    pid: 'tr-A',
    positionMs: positionMs,
    played: finished,
    finished: finished,
    playCount: finished ? 1 : 0,
    starred: false,
    updatedAt: DateTime.utc(2026, 10, 1, 12, minute),
  ),
);

void main() {
  group('the binder over a hand-fed bus', () {
    testWidgets('a report that only moves the position refetches no shelf '
        'and moves the ring without a read', (tester) async {
      final b = await _bindWeb();
      final ring = playProgressProvider(playPidsKey(<String>['tr-A']));
      b.container.listen(ring, (_, _) {});
      await b.container.read(ring.future);
      // The first report of an item can put it on a shelf, so it hints.
      b.bus.add(_report(1000, minute: 1));
      await tester.pump(const Duration(seconds: 6));
      final (browses, batches, prefs) = (
        b.repo.browseCalls.length,
        b.repo.playStateBatches.length,
        b.repo.prefsReads,
      );

      b.bus.add(_report(90000, minute: 2));
      await tester.pump(const Duration(seconds: 6));

      expect(b.repo.browseCalls.length, browses);
      expect(b.repo.prefsReads, prefs, reason: 'no user pass at all');
      expect(b.container.read(ring).value?['tr-A']?.positionMs, 90000);
      expect(
        b.repo.playStateBatches.length,
        batches,
        reason: 'the report is the state; reading it back is a round trip',
      );
      b.container.dispose();
      await tester.pump();
    });

    testWidgets('a report that only moves the position reorders what is '
        'ordered by progress, and nothing else', (tester) async {
      // Up next is the episodes most recently progressed first. No
      // playlist rule reads a position, and an unseeded random list is
      // drawn afresh on every read, so an open one would reshuffle with
      // every checkpoint.
      final b = await _bindWeb();
      final playlist = await b.repo.createPlaylist(
        name: 'In progress',
        kind: 'smart',
      );
      final detail = playlistDetailProvider(playlist.pid);
      b.container
        ..listen(upNextEpisodesProvider, (_, _) {})
        ..listen(detail, (_, _) {});
      await b.container.read(upNextEpisodesProvider.future);
      await b.container.read(detail.future);
      int detailReads() =>
          b.repo.playlistItemPageCalls.where((p) => p == playlist.pid).length;
      b.bus.add(_report(1000, minute: 1));
      await tester.pump(const Duration(seconds: 6));
      final (upNext, details, browses, prefs) = (
        b.repo.subscribedEpisodeCalls.length,
        detailReads(),
        b.repo.browseCalls.length,
        b.repo.prefsReads,
      );

      b.bus.add(_report(90000, minute: 2));
      await tester.pump(const Duration(seconds: 6));

      expect(b.repo.subscribedEpisodeCalls.length, upNext + 1);
      expect(detailReads(), details, reason: 'no rule reads a position');
      expect(b.repo.browseCalls.length, browses, reason: 'no shelf moved');
      expect(b.repo.prefsReads, prefs, reason: 'no user pass at all');
      b.container.dispose();
      await tester.pump();
    });

    testWidgets('a report that moves more than the position moves the rings '
        'at once, not at the end of the window', (tester) async {
      final b = await _bindWeb();
      final ring = playProgressProvider(playPidsKey(<String>['tr-A']));
      b.container.listen(ring, (_, _) {});
      await b.container.read(ring.future);
      // A first sighting opens the user pacer's window.
      b.bus.add(_report(1000, minute: 1));
      await tester.pump(const Duration(seconds: 1));

      // Finished elsewhere inside that window: the pass it asks for waits
      // for the window's end, but the report already is the state.
      b.bus.add(_report(214000, finished: true, minute: 2));
      await tester.pump();

      expect(b.container.read(ring).value?['tr-A']?.finished, isTrue);
      b.container.dispose();
      await tester.pump();
    });

    testWidgets('a report that lands while a window is on its first read is '
        'in the window when the read lands', (tester) async {
      // The read was asked before the report and answers what was there
      // then; the window's echo had nothing to write into yet.
      final b = await _bindWeb();
      b.repo
        ..playPositions['tr-A'] = 30000
        ..playStateUpdatedAt['tr-A'] = DateTime.utc(2026, 10, 1, 12, 1);
      final gate = Completer<void>();
      b.repo.statesGate = gate;
      final ring = playProgressProvider(playPidsKey(<String>['tr-A']));
      b.container.listen(ring, (_, _) {});
      await tester.pump();

      b.bus.add(_report(90000, minute: 2));
      await tester.pump();
      b.repo.statesGate = null;
      gate.complete();
      await tester.pump();

      expect((await b.container.read(ring.future))['tr-A']?.positionMs, 90000);
      b.container.dispose();
      await tester.pump();
    });

    testWidgets('a report older than a window\'s own read leaves it', (
      tester,
    ) async {
      final b = await _bindWeb();
      b.repo
        ..playPositions['tr-A'] = 120000
        ..playStateUpdatedAt['tr-A'] = DateTime.utc(2026, 10, 1, 12, 5);
      final ring = playProgressProvider(playPidsKey(<String>['tr-A']));
      b.container.listen(ring, (_, _) {});
      await b.container.read(ring.future);

      // Stamped before what the read brought back: a report the stream
      // carried late.
      b.bus.add(_report(30000, minute: 2));
      await tester.pump();

      expect(b.container.read(ring).value?['tr-A']?.positionMs, 120000);
      b.container.dispose();
      await tester.pump();
    });

    testWidgets('a report reaches a window off screen without reading it '
        'back', (tester) async {
      final b = await _bindWeb();
      final ring = playProgressProvider(playPidsKey(<String>['tr-A']));
      final sub = b.container.listen(ring, (_, _) {});
      await b.container.read(ring.future);
      // Its screen is off stage, so its listener is paused, and a pass
      // marked it stale meanwhile.
      sub.pause();
      b.container.invalidate(ring);
      final batches = b.repo.playStateBatches.length;

      b.bus.add(_report(90000, minute: 2));
      await tester.pump();

      expect(
        b.repo.playStateBatches.length,
        batches,
        reason: 'nothing on screen asked for it',
      );
      b.container.dispose();
      await tester.pump();
    });

    testWidgets('another device\'s star reaches the item at once, not at the '
        'end of the window', (tester) async {
      final b = await _bindWeb();
      final item = playStateControllerProvider('tr-A');
      b.container.listen(item, (_, _) {});
      await b.container.read(item.future);
      // The client's own first report opens the user pass's window.
      b.bus.add(_report(1000, minute: 1));
      await tester.pump(const Duration(milliseconds: 500));
      final reads = b.repo.playStateReads.length;

      final starred = _report(1000, minute: 2);
      b.bus.add(
        ServerSyncEvent(
          kind: starred.kind,
          pid: starred.pid,
          playState: PlayState(
            pid: 'tr-A',
            positionMs: 1000,
            played: false,
            finished: false,
            playCount: 0,
            starred: true,
            updatedAt: DateTime.utc(2026, 10, 1, 12, 2),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(b.repo.playStateReads.length, greaterThan(reads));
      b.container.dispose();
      await tester.pump();
    });

    testWidgets('a report that finishes the item refetches the shelves', (
      tester,
    ) async {
      final b = await _bindWeb();
      b.bus.add(_report(1000, minute: 1));
      await tester.pump(const Duration(seconds: 6));
      final (browses, prefs) = (b.repo.browseCalls.length, b.repo.prefsReads);

      b.bus.add(_report(214000, finished: true, minute: 2));
      await tester.pump(const Duration(seconds: 6));

      expect(b.repo.browseCalls.length, greaterThan(browses));
      expect(b.repo.prefsReads, prefs + 1);
      b.container.dispose();
      await tester.pump();
    });

    testWidgets('a report that starts an item from the top refetches the '
        'shelves', (tester) async {
      // Only the position moved, but past zero: that is what puts an item
      // on a resume shelf.
      final b = await _bindWeb();
      b.bus.add(_report(0, minute: 1));
      await tester.pump(const Duration(seconds: 6));
      final prefs = b.repo.prefsReads;

      b.bus.add(_report(5000, minute: 2));
      await tester.pump(const Duration(seconds: 6));

      expect(b.repo.prefsReads, prefs + 1);
      b.container.dispose();
      await tester.pump();
    });

    testWidgets('an entity-state marker refreshes only the entity families', (
      tester,
    ) async {
      final b = await _bindWeb();
      final star = entityPlayStateControllerProvider('ar-1');
      b.container.listen(star, (_, _) {});
      await b.container.read(star.future);
      final (browses, prefs, entities) = (
        b.repo.browseCalls.length,
        b.repo.prefsReads,
        b.repo.entityReads,
      );

      b.bus.add(const ServerSyncEvent(kind: 'entity-state', pid: 'ar-1'));
      await tester.pump(const Duration(seconds: 6));

      expect(b.repo.entityReads, entities + 1);
      expect(b.repo.browseCalls.length, browses);
      expect(b.repo.prefsReads, prefs);
      b.container.dispose();
      await tester.pump();
    });
  });

  test('a connect that resolves after stop() reports nothing', () async {
    final gate = Completer<void>();
    var caughtUp = 0;
    var reportedConnected = 0;
    final live = LiveInvalidations(
      channelFactory:
          ({required onFrame, required onDone, required subscribe}) =>
              _GatedChannel(
                gate: gate,
                onFrame: onFrame,
                onDone: onDone,
                subscribe: subscribe,
              ),
      onCatalog: () => caughtUp++,
      onUser: () => caughtUp++,
    );
    live.onConnectionChanged = (_) => reportedConnected++;

    live.start();
    // The session ends while the handshake is still in flight; the
    // socket then comes up for nobody.
    live.stop();
    gate.complete();
    await gate.future;
    await Future<void>.delayed(Duration.zero);

    expect(caughtUp, 0, reason: 'no refresh lands on a dead session');
    expect(reportedConnected, 0, reason: 'and no banner state changes');
  });

  test('a connect that resolves while running catches up once', () async {
    final gate = Completer<void>();
    var catalog = 0;
    var user = 0;
    final live = LiveInvalidations(
      channelFactory:
          ({required onFrame, required onDone, required subscribe}) =>
              _GatedChannel(
                gate: gate,
                onFrame: onFrame,
                onDone: onDone,
                subscribe: subscribe,
              ),
      onCatalog: () => catalog++,
      onUser: () => user++,
    );
    addTearDown(live.stop);

    live.start();
    gate.complete();
    await gate.future;
    await Future<void>.delayed(Duration.zero);

    expect(catalog, 1, reason: 'the may-have-missed-changes refresh');
    expect(user, 1);
  });

  test('a throw from the connected body is not a dropped socket', () async {
    final gate = Completer<void>();
    var factoryCalls = 0;
    var wentDown = 0;
    final live = LiveInvalidations(
      channelFactory:
          ({required onFrame, required onDone, required subscribe}) {
            factoryCalls++;
            return _GatedChannel(
              gate: gate,
              onFrame: onFrame,
              onDone: onDone,
              subscribe: subscribe,
            );
          },
      // The catch-up refresh breaks, the way a fan-out bug would.
      onCatalog: () => throw StateError('fan-out bug'),
      onUser: () {},
    );
    live.onConnectionChanged = (connected) {
      if (!connected) wentDown++;
    };
    addTearDown(live.stop);

    // The connect wiring happens inside start(), so the guarded zone
    // has to hold it: an unlistened future's error reports to the zone
    // its callbacks were registered in.
    final surfaced = <Object>[];
    runZonedGuarded(live.start, (error, _) => surfaced.add(error));
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(surfaced, [isA<StateError>()], reason: 'the bug is heard as itself');
    expect(wentDown, 0, reason: 'a healthy socket is not reported down');
    expect(factoryCalls, 1, reason: 'and no reconnect is scheduled');
  });

  test('an invalidation frame routes to its topic', () {
    // The frame path is the onFrame callback the listener hands its
    // channel; capturing it is how a test speaks as the server.
    late void Function(String) deliver;
    var user = 0;
    final live = LiveInvalidations(
      channelFactory:
          ({required onFrame, required onDone, required subscribe}) {
            deliver = onFrame;
            return _GatedChannel(
              gate: Completer<void>(),
              onFrame: onFrame,
              onDone: onDone,
              subscribe: subscribe,
            );
          },
      onCatalog: () => fail('catalog was not the topic'),
      onUser: () => user++,
    );
    addTearDown(live.stop);

    live.start();
    deliver(
      jsonEncode(const <String, Object?>{
        'type': 'invalidate',
        'topic': 'user',
      }),
    );
    expect(user, 1);
  });

  test('a resync naming an unknown topic still refreshes everything', () async {
    final gate = Completer<void>()..complete();
    var catalog = 0, user = 0, radio = 0;
    late void Function(String) deliver;
    final live = LiveInvalidations(
      channelFactory:
          ({required onFrame, required onDone, required subscribe}) {
            deliver = onFrame;
            return _GatedChannel(
              gate: gate,
              onFrame: onFrame,
              onDone: onDone,
              subscribe: subscribe,
            );
          },
      onCatalog: () => catalog++,
      onUser: () => user++,
    );
    live.onRadio = () => radio++;
    live.start();
    addTearDown(live.stop);
    await gate.future;
    await Future<void>.delayed(Duration.zero);
    catalog = 0;
    user = 0;

    // Continuity recovery must not narrow as cursorless topics are added.
    deliver(jsonEncode({'type': 'resync', 'topic': 'radio'}));

    expect(catalog, 1);
    expect(user, 1);
    expect(radio, 0, reason: 'a resync is not a nudge');
  });

  test('a radio frame nudges only the radio listener', () async {
    final gate = Completer<void>()..complete();
    var catalog = 0, user = 0, player = 0, radio = 0;
    late void Function(String) deliver;
    final live = LiveInvalidations(
      channelFactory:
          ({required onFrame, required onDone, required subscribe}) {
            deliver = onFrame;
            return _GatedChannel(
              gate: gate,
              onFrame: onFrame,
              onDone: onDone,
              subscribe: subscribe,
            );
          },
      onCatalog: () => catalog++,
      onUser: () => user++,
    );
    live.onPlayer = () => player++;
    live.onRadio = () => radio++;
    live.start();
    addTearDown(live.stop);
    await gate.future;
    await Future<void>.delayed(Duration.zero);
    // The connect itself catches up once; only the frame is under test.
    catalog = 0;
    user = 0;

    deliver(jsonEncode({'type': 'invalidate', 'topic': 'radio'}));

    expect(radio, 1);
    expect(player, 0, reason: 'a radio frame is not a player frame');
    expect(catalog, 0);
    expect(user, 0, reason: 'and pulls no mirrored stream');
  });

  test(
    'a catch-up refreshes through its own callback when there is one',
    () async {
      // A user invalidation names no kind, so the web build walks the
      // stream to learn which surfaces moved; a (re)connect or a resync
      // may have lost changes the walk can no longer report.
      final gate = Completer<void>()..complete();
      var user = 0, catchUp = 0;
      late void Function(String) deliver;
      final live = LiveInvalidations(
        channelFactory:
            ({required onFrame, required onDone, required subscribe}) {
              deliver = onFrame;
              return _GatedChannel(
                gate: gate,
                onFrame: onFrame,
                onDone: onDone,
                subscribe: subscribe,
              );
            },
        onCatalog: () {},
        onUser: () => user++,
        onUserCatchUp: () => catchUp++,
      );
      live.start();
      addTearDown(live.stop);
      await gate.future;
      await Future<void>.delayed(Duration.zero);
      expect(catchUp, 1, reason: 'the connect catches up');
      expect(user, 0);

      deliver(jsonEncode({'type': 'invalidate', 'topic': 'user'}));
      deliver(jsonEncode({'type': 'resync', 'topic': 'user'}));

      expect(user, 1);
      expect(catchUp, 2);
    },
  );
}
