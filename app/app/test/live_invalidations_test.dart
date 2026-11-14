import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/connect/connect_bus.dart';
import 'package:waxdeck/src/home/home_shelves.dart';
import 'package:waxdeck/src/player/entity_play_state_controller.dart';
import 'package:waxdeck/src/player/play_progress.dart';
import 'package:waxdeck/src/player/play_state_controller.dart';
import 'package:waxdeck/src/playlists/playlists_controller.dart';
import 'package:waxdeck/src/podcasts/podcast_shelves.dart';
import 'package:waxdeck/src/settings/prefs_controller.dart';
import 'package:waxdeck/src/sync/live_invalidations.dart';
import 'package:waxdeck/src/sync/server_event_bus.dart';
import 'package:waxdeck/src/sync/sync_binder.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import 'app_host.dart';
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

  /// Whether the socket is open: connected and not closed since.
  bool up = false;

  @override
  Future<void> connect() => gate.future.then((_) => up = true);

  @override
  Future<void> close() async => up = false;
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
  final container = appContainer(
    repo: repo,
    extra: [serverEventBusProvider.overrideWithValue(bus)],
  );
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
    late _GatedChannel channel;
    final live = LiveInvalidations(
      channelFactory:
          ({required onFrame, required onDone, required subscribe}) =>
              channel = _GatedChannel(
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
    expect(channel.up, isFalse, reason: 'the socket that came up is closed');
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

  group('the session the socket rides', () {
    testWidgets('a socket the server closes as ended asks for the session '
        'at once', (tester) async {
      final link = FakeLink();
      var doubts = 0;
      final live = LiveInvalidations(
        channelFactory: link.factory,
        onCatalog: () {},
        onUser: () {},
      )..onSessionInDoubt = () async => ++doubts > 0;
      live.start();
      await tester.pump();
      expect(doubts, 0, reason: 'a first connect rides the session just read');

      link.reachable = false;
      link.attempts.last.drop(sessionEndedCloseCode);

      expect(doubts, 1, reason: 'the server said the session ended');
      live.stop();
    });

    testWidgets('a drop asks for nothing; each failed attempt asks once, and '
        'the return once', (tester) async {
      final link = FakeLink();
      var doubts = 0;
      final live = LiveInvalidations(
        channelFactory: link.factory,
        onCatalog: () {},
        onUser: () {},
      )..onSessionInDoubt = () async => ++doubts > 0;
      live.start();
      await tester.pump();

      // The network goes, as the browser reports it, and the attempts to
      // come back fail with it.
      link.reachable = false;
      link.attempts.last.drop(1006);
      await tester.pump();
      expect(doubts, 0, reason: 'a drop says nothing about the session');

      await tester.pump(const Duration(seconds: 1));
      expect(link.attempts, hasLength(2));
      expect(
        doubts,
        1,
        reason: 'an upgrade refused for want of a session fails like this',
      );
      await tester.pump(const Duration(seconds: 2));
      expect(link.attempts, hasLength(3));
      expect(doubts, 2, reason: 'once per attempt, as the backoff spaces them');

      link.reachable = true;
      await tester.pump(const Duration(seconds: 4));
      expect(link.attempts, hasLength(4));
      expect(doubts, 3, reason: 'another account may own the cookie now');

      await tester.pump(const Duration(minutes: 1));
      expect(doubts, 3, reason: 'a socket that is up asks no more');
      live.stop();
    });

    testWidgets('the network back while it waits to reconnect connects now, '
        'and starts the backoff over', (tester) async {
      final link = FakeLink();
      final live = LiveInvalidations(
        channelFactory: link.factory,
        onCatalog: () {},
        onUser: () {},
      );
      live.start();
      await tester.pump();

      // Down a while: the next attempt is four seconds off.
      link.reachable = false;
      link.attempts.last.drop(1006);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 2));
      expect(link.attempts, hasLength(3));

      live.networkBack();
      await tester.pump();
      expect(link.attempts, hasLength(4), reason: 'at once');
      await tester.pump(const Duration(seconds: 1));
      expect(link.attempts, hasLength(5), reason: 'a second after, not eight');

      link.reachable = true;
      await tester.pump(const Duration(seconds: 2));
      expect(link.attempts, hasLength(6));
      live.networkBack();
      await tester.pump(const Duration(minutes: 1));
      expect(link.attempts, hasLength(6), reason: 'a socket that is up stays');
      live.stop();
    });

    testWidgets('started again after a stop, its first failed connect waits '
        'a second, not the delay the outage had grown to', (tester) async {
      final link = FakeLink()..reachable = false;
      final live = LiveInvalidations(
        channelFactory: link.factory,
        onCatalog: () {},
        onUser: () {},
      );
      live.start();
      await tester.pump();
      // Down a while: the waits between attempts grow to four seconds, and
      // the one after the third failure would be eight.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 2));
      expect(link.attempts, hasLength(3));

      live.stop();
      live.start();
      await tester.pump();
      expect(link.attempts, hasLength(4));

      await tester.pump(const Duration(seconds: 1));
      expect(link.attempts, hasLength(5), reason: 'a second after, not eight');
      live.stop();
    });

    group('a return', () {
      late FakeLink link;
      late Completer<bool> answer;
      late LiveInvalidations live;

      /// What the listener did, in order.
      late List<String> heard;

      setUp(() {
        link = FakeLink();
        heard = [];
        live =
            LiveInvalidations(
                channelFactory: link.factory,
                onCatalog: () => heard.add('catalog'),
                onUser: () => heard.add('user'),
              )
              ..onSessionInDoubt = (() => answer.future)
              ..onConnected = (() => heard.add('connected'))
              ..onPlayer = (() => heard.add('player'))
              ..onRadio = (() => heard.add('radio'))
              ..onControlFrame = (frame) => heard.add('${frame['type']}');
      });

      tearDown(() => live.stop());

      const caughtUp = ['connected', 'catalog', 'user'];

      void say(Map<String, Object?> frame) =>
          link.attempts.last.onFrame(jsonEncode(frame));

      /// What the socket says while its session is read: something of
      /// every kind a catch-up does not read again, and one it does.
      void sayMeanwhile() {
        say(const {'type': 'invalidate', 'topic': 'player'});
        say(const {'type': 'invalidate', 'topic': 'radio'});
        say(const {'type': 'session', 'session': <String, Object?>{}});
        say(const {'type': 'invalidate', 'topic': 'catalog'});
      }

      const saidMeanwhile = ['player', 'radio', 'session', 'catalog'];

      /// Up and caught up, then dropped and back a second later with the
      /// session read out.
      Future<void> back(WidgetTester tester) async {
        // Made in the test's own zone, so its answer lands on the clock
        // the test pumps.
        answer = Completer<bool>();
        live.start();
        await tester.pump();
        expect(heard, caughtUp);
        heard.clear();
        link.attempts.last.drop(1006);
        await tester.pump(const Duration(seconds: 1));
        expect(link.attempts, hasLength(2));
      }

      testWidgets('as the same account catches up once it answers, then '
          'hands on what the socket said meanwhile, in order', (tester) async {
        await back(tester);
        sayMeanwhile();
        await tester.pump();
        expect(heard, isEmpty, reason: 'nothing before the session answers');

        answer.complete(true);
        await tester.pump();
        expect(heard, [...caughtUp, ...saidMeanwhile]);

        heard.clear();
        say(const {'type': 'invalidate', 'topic': 'user'});
        expect(heard, ['user'], reason: 'and hears the socket as it speaks');
      });

      testWidgets('a read that fails hands it on too', (tester) async {
        await back(tester);
        sayMeanwhile();
        await tester.pump();

        answer.completeError(StateError('the read broke'));
        await tester.pump();

        expect(heard, [...caughtUp, ...saidMeanwhile]);
      });

      testWidgets('as an account that left catches nothing up and hands on '
          'nothing', (tester) async {
        await back(tester);
        sayMeanwhile();
        await tester.pump();

        answer.complete(false);
        await tester.pump();
        say(const {'type': 'invalidate', 'topic': 'user'});
        await tester.pump();

        expect(heard, isEmpty);
      });

      testWidgets('closed as ended while its session is read, hands on '
          'nothing it said', (tester) async {
        await back(tester);
        sayMeanwhile();
        link.reachable = false;
        link.attempts.last.drop(sessionEndedCloseCode);

        answer.complete(true);
        await tester.pump();

        expect(heard, isEmpty);
        live.stop();
      });

      testWidgets('the reply to a command sent while its session is read '
          'reaches the command', (tester) async {
        final bus = ConnectBus(send: live.sendControl);
        live.onControlFrame = bus.handleFrame;
        await back(tester);

        String? registered;
        bus
            .registerEndpoint(name: 'desk')
            .then((id) => registered = id, onError: (Object _) {})
            .ignore();
        final sent = link.attempts.last.sent;
        expect(sent, hasLength(1), reason: 'the socket takes frames at once');
        final id = (jsonDecode(sent.single) as Map<String, Object?>)['id'];
        say({'type': 'ack', 'id': id, 'endpointId': 'ep-desk'});
        await tester.pump();

        answer.complete(true);
        await tester.pump();

        expect(registered, 'ep-desk');
      });

      testWidgets('past ${LiveInvalidations.mostHeld} frames lets them go, '
          'and catches up every topic instead', (tester) async {
        await back(tester);
        for (var i = 0; i <= LiveInvalidations.mostHeld; i++) {
          say(const {'type': 'invalidate', 'topic': 'player'});
        }
        sayMeanwhile();
        await tester.pump();

        answer.complete(true);
        await tester.pump();

        expect(heard, [...caughtUp, 'player', 'radio']);
      });

      testWidgets('a pong said while its session is read is not paired with '
          'the ping the catch-up sends', (tester) async {
        var clock = DateTime.utc(2026, 7, 21, 12);
        final bus = ConnectBus(send: live.sendControl, now: () => clock);
        live
          ..onControlFrame = ((frame) {
            heard.add('${frame['type']}');
            bus.handleFrame(frame);
          })
          ..onConnected = (() {
            heard.add('connected');
            bus.ping();
          });
        Object? lastPingT() =>
            (jsonDecode(link.attempts.last.sent.last)
                as Map<String, Object?>)['t'];
        await back(tester);

        // The ping timer fires while the read is out, and the server
        // answers on the new socket, its clock five seconds ahead.
        clock = clock.add(const Duration(minutes: 1));
        bus.ping();
        final mid = lastPingT();
        say({
          'type': 'pong',
          't': mid,
          'at': clock.add(const Duration(seconds: 5)).millisecondsSinceEpoch,
        });

        clock = clock.add(const Duration(seconds: 3));
        answer.complete(true);
        await tester.pump();
        expect(heard, [...caughtUp, 'pong'], reason: 'the pong is heard');
        final ping = lastPingT();
        expect(ping, isNot(mid), reason: 'the catch-up pinged again');
        expect(
          bus.serverClockOffset,
          Duration.zero,
          reason: 'it answered the ping from before, not the one just sent',
        );

        say({
          'type': 'pong',
          't': ping,
          'at': clock.add(const Duration(seconds: 5)).millisecondsSinceEpoch,
        });
        expect(bus.serverClockOffset, const Duration(seconds: 5));
      });

      testWidgets('stopped while its session is read and started again, '
          'hears the socket', (tester) async {
        await back(tester);
        sayMeanwhile();
        live.stop();

        live.start();
        await tester.pump();
        expect(link.attempts, hasLength(3));
        expect(heard, caughtUp, reason: 'a start is a first connect');
        heard.clear();

        answer.complete(true);
        await tester.pump();
        expect(heard, isEmpty, reason: 'the old read touches nothing now');

        say(const {'type': 'invalidate', 'topic': 'user'});
        expect(heard, ['user']);
      });

      testWidgets('stopped while down and started again, connects as a '
          'first connect', (tester) async {
        answer = Completer<bool>();
        live.start();
        await tester.pump();
        heard.clear();
        link.attempts.last.drop(1006);
        live.stop();

        live.start();
        await tester.pump();

        expect(link.attempts, hasLength(2));
        expect(heard, caughtUp, reason: 'no session to read before it');
        say(const {'type': 'invalidate', 'topic': 'user'});
        expect(heard, [...caughtUp, 'user']);
      });
    });
  });
}
