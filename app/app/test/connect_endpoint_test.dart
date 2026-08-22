import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/connect/connect_bus.dart';
import 'package:waxdeck/src/connect/connect_controller.dart';
import 'package:waxdeck/src/connect/connect_providers.dart';
import 'package:waxdeck/src/connect/queue_gateway.dart';
import 'package:waxdeck/src/player/autoplay_gate.dart';
import 'package:waxdeck/src/settings/prefs_controller.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

const pidA = 'tr-01JZX5N8QW3F4V9T2B7KDAAAAA1';
const pidB = 'tr-01JZX5N8QW3F4V9T2B7KDBBBBB2';
const pidC = 'tr-01JZX5N8QW3F4V9T2B7KDCCCCC3';

/// Every fake stream is this long, matching the item durations, so a
/// track runs out at a number the test can name.
const _trackMs = 214000;

const _album = QueueSource(
  kind: QueueSourceKind.album,
  label: 'Kind of Blue',
  pid: 'al-1',
);

/// The whole client wiring, as the app builds it: the endpoint
/// controller over the real gateway, over the real queue and playback.
({
  ProviderContainer container,
  ConnectEndpointController controller,
  ConnectBus bus,
  List<Map<String, Object?>> sent,
  FakeRepository repo,
  FakeEngine engine,
})
_build({Prefs? prefs}) {
  final sent = <Map<String, Object?>>[];
  final repo = FakeRepository(
    items: [testItem(pidA), testItem(pidB), testItem(pidC)],
  );
  final engine = FakeEngine(
    mediaDuration: const Duration(milliseconds: _trackMs),
  );
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      audioEngineProvider.overrideWithValue(engine),
      connectSenderProvider.overrideWithValue(
        ConnectSender()
          ..impl = (frame) {
            sent.add(Map.of(frame));
            return true;
          },
      ),
      if (prefs != null)
        prefsControllerProvider.overrideWith(() => _StubPrefs(prefs)),
    ],
  );
  addTearDown(container.dispose);
  final controller = container.read(connectControllerProvider)..wire();
  return (
    container: container,
    controller: controller,
    bus: container.read(connectBusProvider),
    sent: sent,
    repo: repo,
    engine: engine,
  );
}

/// A settled preference document. The real controller waits on a
/// session, which a bare container has none of.
class _StubPrefs extends PrefsController {
  _StubPrefs(this._prefs);

  final Prefs _prefs;

  @override
  Future<Prefs> build() async => _prefs;
}

extension on ProviderContainer {
  QueueState get queue => read(queueControllerProvider);
  NowPlayingController get playback => read(nowPlayingProvider.notifier);
}

Iterable<Map<String, Object?>> _ofType(
  List<Map<String, Object?>> sent,
  String type,
) => sent.where((f) => f['type'] == type);

/// The reports that carried the queue, which by contract is only the
/// ones where it changed.
List<Map<String, Object?>> _queued(List<Map<String, Object?>> sent) => [
  for (final frame in _ofType(sent, 'session-report'))
    if (frame['itemPids'] != null) frame,
];

/// Sends one routed endpoint command and lets it run.
Future<void> _cmd(
  ({
    ProviderContainer container,
    ConnectEndpointController controller,
    ConnectBus bus,
    List<Map<String, Object?>> sent,
    FakeRepository repo,
    FakeEngine engine,
  })
  h,
  String verb, {
  String id = 'e1',
  Map<String, Object?> args = const {},
}) async {
  h.bus.handleFrame({
    'type': 'endpoint-cmd',
    'id': id,
    'sessionId': 'ps-1',
    'verb': verb,
    ...args,
  });
  await pumpEventQueue();
}

void main() {
  test('registration acks resolve and mark the endpoint id', () async {
    final h = _build();
    final started = h.controller.start();
    final reg = _ofType(h.sent, 'register-endpoint').single;
    // Against a literal rather than against the same expression the
    // provider evaluates, which would pass even if it stopped naming
    // the device at all. The platform half varies with where the tests
    // run; that this endpoint introduces itself as a WaxDeck client
    // does not.
    expect(reg['name'], startsWith('WaxDeck '));
    h.bus.handleFrame({'type': 'ack', 'id': reg['id'], 'endpointId': 'pe-me'});
    await started;
    expect(h.controller.endpointId.value, 'pe-me');
  });

  test('a load becomes the local queue and plays it', () async {
    final h = _build();
    await _cmd(
      h,
      'load',
      args: {
        'itemPids': [pidA, pidB],
        'index': 0,
        'positionMs': 4000,
        'play': true,
      },
    );

    // The queue handed over is the one every surface reads, not one the
    // endpoint kept to itself.
    expect(h.container.queue.pids, [pidA, pidB]);
    expect(h.container.queue.currentIndex, 0);
    expect(h.engine.loadedUrl, contains(pidA));
    expect(h.engine.position, const Duration(seconds: 4));
    expect(h.engine.playing, isTrue);

    // Exactly one ok result answered the load.
    final results = _ofType(h.sent, 'cmd-result').toList();
    expect(results, hasLength(1));
    expect(results.single['id'], 'e1');
    expect(results.single['ok'], isTrue);

    // The queue rides the one report where it changed, and the load's
    // session id was adopted for later transfers from this device.
    expect(_queued(h.sent).single['itemPids'], [pidA, pidB]);
    expect(h.controller.mirrorSessionId, 'ps-1');
  });

  test('a load answers for a start that fails', () async {
    final h = _build();
    await _cmd(
      h,
      'load',
      args: {
        'itemPids': ['tr-01JZX5N8QW3F4V9T2B7KDNOSUCH'],
        'index': 0,
      },
    );
    final result = _ofType(h.sent, 'cmd-result').single;
    expect(result['ok'], isFalse);
    // Nothing plays, so nothing is reported as playing either.
    expect(_ofType(h.sent, 'session-report'), isEmpty);
  });

  test('a load with no items is refused', () async {
    final h = _build();
    await _cmd(h, 'load', args: {'itemPids': <String>[]});
    final result = _ofType(h.sent, 'cmd-result').single;
    expect(result['ok'], isFalse);
    expect(result['code'], 'invalid-request');
    expect(result['message'], contains('no items'));
  });

  test('local playback mirrors the queue it is playing from', () async {
    final h = _build();
    h.container.playback.play([
      testItem(pidA),
      testItem(pidB),
      testItem(pidC),
    ], source: _album);
    await pumpEventQueue();

    final queued = _queued(h.sent).single;
    expect(queued['itemPids'], [pidA, pidB, pidC]);
    expect(queued['index'], 0);
    expect(queued['repeat'], 'off');
    expect(queued['shuffle'], isFalse);
    expect(queued['queueVersion'], isNotNull);

    // A jump inside the same queue reports the new index without
    // re-sending a queue that did not change.
    h.container.read(queueControllerProvider.notifier).jumpTo(2);
    await pumpEventQueue();
    final second = _ofType(h.sent, 'session-report').last;
    expect(second['index'], 2);
    expect(second['itemPids'], isNull);
    expect(second['queueVersion'], isNull);

    // Repeat is the listener's, and a controller renders it from here.
    // It is queue state, so it rides a settled report like any edit,
    // and the queue itself did not change so it does not ride along.
    h.container
        .read(queueControllerProvider.notifier)
        .setRepeat(QueueRepeat.all);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final third = _ofType(h.sent, 'session-report').last;
    expect(third['repeat'], 'all');
    expect(third['itemPids'], isNull);
  });

  test('an edit to the queue is reported once it settles', () async {
    final h = _build();
    h.container.playback.play([testItem(pidA), testItem(pidB)], source: _album);
    await pumpEventQueue();
    final before = _ofType(h.sent, 'session-report').length;

    h.container.read(queueControllerProvider.notifier).addToEnd([pidC]);
    await pumpEventQueue();
    // Not on the edit itself: a drag emits a queue per frame.
    expect(_ofType(h.sent, 'session-report').length, before);

    await Future<void>.delayed(const Duration(milliseconds: 500));
    final after = _ofType(h.sent, 'session-report').last;
    expect(after['itemPids'], [pidA, pidB, pidC]);
    expect(after['queueVersion'], isNotNull);
  });

  test('seek, volume, and pause commands drive the engine', () async {
    final h = _build();
    await _cmd(
      h,
      'load',
      args: {
        'itemPids': [pidA],
        'index': 0,
      },
    );

    await _cmd(h, 'seek', id: 'e2', args: {'positionMs': 12000});
    expect(h.engine.position, const Duration(seconds: 12));

    await _cmd(h, 'set-volume', id: 'e3', args: {'volume': 0.25});
    expect(h.engine.volume, 0.25);

    await _cmd(h, 'pause', id: 'e4');
    expect(h.engine.playing, isFalse);

    final oks = _ofType(h.sent, 'cmd-result').map((f) => f['ok']).toList();
    expect(oks, everyElement(isTrue));
  });

  test('a routed seek that cannot load its part answers ok:false', () async {
    // The handler acks a command when its verb returns. A cross-part
    // seek whose load fails announces on sessionFailed rather than
    // throwing (its UI call sites are unawaited), and returning
    // normally here told the remote its seek worked while this device
    // tore the session down and stood an error pane.
    final h = _build();
    const bookPid = 'bk-01JZX5N8QW3F4V9T2B7KDBK0009';
    h.repo.libraryItems.add(
      testItem(bookPid, mediaType: MediaType.audiobook, durationMs: 120000),
    );
    h.repo.books[bookPid] = testBook(bookPid, durationMs: 120000, partCount: 2);
    await _cmd(
      h,
      'load',
      args: {
        'itemPids': [bookPid],
        'index': 0,
        'play': true,
      },
    );

    h.engine.failNextLoad = true;
    await _cmd(h, 'seek', id: 'e2', args: {'positionMs': 90000});

    final result = _ofType(h.sent, 'cmd-result').last;
    expect(result['id'], 'e2');
    expect(
      result['ok'],
      isFalse,
      reason: 'a seek that tore the session down must not ack as landed',
    );
    // The code is what the controller reads. `internal` would send the
    // listener to report a server bug, and the server never saw this;
    // `invalid-request` - what an unwhitelisted code degrades to -
    // would blame a command that was fine.
    expect(result['code'], 'endpoint-failed');
  });

  test('routed skips step the same queue the screen has', () async {
    final h = _build();
    h.container.playback.play([testItem(pidA), testItem(pidB)], source: _album);
    await pumpEventQueue();

    await _cmd(h, 'next', id: 'e1');
    expect(h.engine.loadedUrl, contains(pidB));
    expect(h.container.queue.currentIndex, 1);
    expect(_ofType(h.sent, 'session-report').last['index'], 1);

    // Past the end is a refusal the controller can render.
    await _cmd(h, 'next', id: 'e2');
    final refusal = _ofType(h.sent, 'cmd-result').last;
    expect(refusal['id'], 'e2');
    expect(refusal['ok'], isFalse);
    expect(refusal['message'], 'already at the end of the queue');

    await _cmd(h, 'previous', id: 'e3');
    expect(h.engine.loadedUrl, contains(pidA));
    expect(h.container.queue.currentIndex, 0);

    // At the front, previous starts the entry over rather than refusing.
    await _cmd(h, 'previous', id: 'e4');
    expect(h.container.queue.currentIndex, 0);
    expect(_ofType(h.sent, 'cmd-result').last['ok'], isTrue);
  });

  test('a head unit skip steps the queue through the gateway', () async {
    final h = _build();
    h.container.playback.play([testItem(pidA), testItem(pidB)], source: _album);
    await pumpEventQueue();

    // What the Android Auto media session calls, on the same seam the
    // routed commands use.
    final gateway = h.container.read(queueGatewayProvider);
    expect(await gateway.next(), isTrue);
    await pumpEventQueue();
    expect(h.engine.loadedUrl, contains(pidB));
    expect(await gateway.next(), isFalse);

    // A browse leaf plays as a queue of its own.
    await gateway.playItem(pidC);
    await pumpEventQueue();
    expect(h.container.queue.pids, [pidC]);
    expect(h.engine.loadedUrl, contains(pidC));
  });

  test('repeat and shuffle commands land on the queue', () async {
    final h = _build();
    h.container.playback.play([testItem(pidA), testItem(pidB)], source: _album);
    await pumpEventQueue();

    await _cmd(h, 'set-repeat', id: 'e1', args: {'repeat': 'one'});
    expect(h.container.queue.repeat, QueueRepeat.one);

    await _cmd(h, 'set-shuffle', id: 'e2', args: {'shuffle': true});
    expect(h.container.queue.shuffled, isTrue);
    expect(_ofType(h.sent, 'session-report').last['shuffle'], isTrue);
  });

  test('a handed-over queue plays in the order it arrived', () async {
    final h = _build();
    h.container.read(queueControllerProvider.notifier).setShuffle(true);
    await _cmd(
      h,
      'load',
      args: {
        'itemPids': [pidA, pidB, pidC],
        'index': 0,
      },
    );

    // The controlling device's order is the order, and the local toggle
    // says so rather than claiming a shuffle the queue does not show.
    expect(h.container.queue.pids, [pidA, pidB, pidC]);
    expect(h.container.queue.shuffled, isFalse);
  });

  test('a handover waits to be tapped when autoplay is off', () async {
    final h = _build(prefs: const Prefs(autoplay: false));
    // The document is read at the moment the start is claimed, so it has
    // to have landed first.
    await h.container.read(prefsControllerProvider.future);
    await _cmd(
      h,
      'load',
      args: {
        'itemPids': [pidA, pidB],
        'index': 0,
        'play': true,
      },
    );

    // The handover still lands; only the audio is declined.
    expect(h.container.queue.pids, [pidA, pidB]);
    expect(h.engine.playing, isFalse);
    // Left in the same state a browser's own refusal leaves.
    expect(h.container.read(autoplayBlockedProvider), isTrue);
  });

  test('a handover in the startup window still honours autoplay', () async {
    // The document is still loading in the seconds after a launch, which
    // is exactly when another device hands a queue over. Reading it as
    // absent there would play out loud for an account that said not to.
    final h = _build(prefs: const Prefs(autoplay: false));
    await _cmd(
      h,
      'load',
      args: {
        'itemPids': [pidA],
        'index': 0,
        'play': true,
      },
    );
    expect(h.engine.playing, isFalse);
    expect(h.container.read(autoplayBlockedProvider), isTrue);
  });

  test('stop ends the queue and the reports with it', () async {
    final h = _build();
    await _cmd(
      h,
      'load',
      args: {
        'itemPids': [pidA],
        'index': 0,
      },
    );

    await _cmd(h, 'stop', id: 'e2');
    expect(h.container.queue.isEmpty, isTrue);
    final before = _ofType(h.sent, 'session-report').length;

    // Later engine activity (another surface taking it) must not
    // produce session reports.
    await h.engine.load('http://x/other');
    await h.engine.play();
    await pumpEventQueue();
    expect(_ofType(h.sent, 'session-report').length, before);
  });

  test('a routed stop during live radio lets the station go', () async {
    // The verbs used to go straight at the engine, which silences the
    // stream but leaves the station tuned - so the face and the deck
    // bar went on naming a station nothing was playing.
    final h = _build();
    final station = RadioStation(
      pid: 'rs-1',
      name: 'Nightjar FM',
      streamUrl: 'https://stream.example/rs-1',
      createdAt: DateTime.utc(2026, 7, 1),
    );
    h.repo.radioStationsByPid['rs-1'] = station;
    await h.container.read(radioPlaybackProvider.notifier).play(station);
    await pumpEventQueue();
    expect(h.container.read(radioPlaybackProvider).station, isNotNull);

    await _cmd(h, 'stop', id: 'e2');
    await pumpEventQueue();

    expect(h.container.read(radioPlaybackProvider).station, isNull);
    expect(h.engine.playing, isFalse);
  });

  test('a routed pause during live radio lets the station go too', () async {
    // A live stream has no pause worth the name: pausing it leaves the
    // buffer to go stale, and resuming plays whatever was in it.
    final h = _build();
    final station = RadioStation(
      pid: 'rs-1',
      name: 'Nightjar FM',
      streamUrl: 'https://stream.example/rs-1',
      createdAt: DateTime.utc(2026, 7, 1),
    );
    h.repo.radioStationsByPid['rs-1'] = station;
    await h.container.read(radioPlaybackProvider.notifier).play(station);
    await pumpEventQueue();

    await _cmd(h, 'pause', id: 'e2');
    await pumpEventQueue();

    expect(h.container.read(radioPlaybackProvider).station, isNull);
  });

  test(
    'the play after that pause is refused rather than answered ok',
    () async {
      // The other half of letting the station go: there is now no station,
      // no session, and no queue, so the play has nothing to start. It
      // used to fall through every rung and answer `ok` - a head unit
      // whose pause then play left it in silence and told it that worked.
      final h = _build();
      final station = RadioStation(
        pid: 'rs-1',
        name: 'Nightjar FM',
        streamUrl: 'https://stream.example/rs-1',
        createdAt: DateTime.utc(2026, 7, 1),
      );
      h.repo.radioStationsByPid['rs-1'] = station;
      await h.container.read(radioPlaybackProvider.notifier).play(station);
      await pumpEventQueue();
      await _cmd(h, 'pause', id: 'e2');
      await pumpEventQueue();

      await _cmd(h, 'play', id: 'e3');
      await pumpEventQueue();

      final result = _ofType(h.sent, 'cmd-result').last;
      expect(result['id'], 'e3');
      expect(result['ok'], isFalse);
      expect(result['code'], 'invalid-request');
    },
  );

  test('the queue that follows a stop is reported as a new one', () async {
    final h = _build();
    await _cmd(
      h,
      'load',
      id: 'e1',
      args: {
        'itemPids': [pidA, pidB],
        'index': 0,
      },
    );
    await _cmd(h, 'stop', id: 'e2');

    // The same queue again is a different session, and a creating
    // report the server can render has to carry it.
    await _cmd(
      h,
      'load',
      id: 'e3',
      args: {
        'itemPids': [pidA, pidB],
        'index': 0,
      },
    );
    expect(_queued(h.sent), hasLength(2));
    expect(_queued(h.sent).last['itemPids'], [pidA, pidB]);
  });

  test('a command that starts nothing is not blamed for an old '
      'failure', () async {
    final h = _build();
    await _cmd(
      h,
      'load',
      id: 'e1',
      args: {
        'itemPids': ['tr-01JZX5N8QW3F4V9T2B7KDNOSUCH'],
      },
    );
    expect(_ofType(h.sent, 'cmd-result').last['ok'], isFalse);

    // The entry that failed is still the current one, so previous has
    // nowhere to step back to and starts nothing: it answers for
    // itself, not for the load before it. And it says which of the two
    // refusals this is: the queue is not empty, nothing is playing.
    await _cmd(h, 'previous', id: 'e2');
    final result = _ofType(h.sent, 'cmd-result').last;
    expect(result['id'], 'e2');
    expect(result['ok'], isFalse);
    expect(result['message'], 'nothing is playing on this device');
  });

  test('a second failure that repeats the first is still answered', () async {
    final h = _build();
    // One exception object for both attempts, which is the ordinary
    // case rather than a contrived one: the type is const-constructible
    // and a client that holds one hands back the same instance. Telling
    // the two failures apart by the error alone cannot work.
    h.repo.playInfoError = const WaxDeckApiException(
      code: 'transport',
      message: 'network unreachable',
    );
    await _cmd(
      h,
      'load',
      id: 'e1',
      args: {
        'itemPids': [pidA, pidB],
        'index': 0,
      },
    );
    expect(_ofType(h.sent, 'cmd-result').last['ok'], isFalse);

    // The queue moves, the next entry starts, and it fails the same
    // way. The controller asked for it, so it is answered for.
    await _cmd(h, 'next', id: 'e2');
    final result = _ofType(h.sent, 'cmd-result').last;
    expect(result['id'], 'e2');
    expect(result['ok'], isFalse);
    expect(result['message'], 'network unreachable');
    // This device's network, not the sender's command. Forwarding
    // `transport` would reach the controller as `invalid-request`,
    // which is the whitelist's answer for a code it does not carry, and
    // would blame a command that was fine.
    expect(result['code'], 'endpoint-failed');
  });

  test('a burst of edits reports once, where the gesture left it', () async {
    final h = _build();
    h.container.playback.play([testItem(pidA)], source: _album);
    await pumpEventQueue();
    final before = _queued(h.sent).length;

    // A run of edits longer than the settle delay, which is what a drag
    // is: a timer armed on the first would fire partway through and
    // report an order nobody stopped on, then arm again for the rest.
    final queue = h.container.read(queueControllerProvider.notifier);
    for (final pid in [pidB, pidC, pidB, pidC, pidB]) {
      queue.addToEnd([pid]);
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(_queued(h.sent).length, before + 1);
    expect(_queued(h.sent).last['itemPids'], [
      pidA,
      pidB,
      pidC,
      pidB,
      pidC,
      pidB,
    ]);
  });

  test('a load with no session id lets the old one go', () async {
    final h = _build();
    await _cmd(
      h,
      'load',
      id: 'e1',
      args: {
        'itemPids': [pidA],
        'index': 0,
      },
    );
    expect(h.controller.mirrorSessionId, 'ps-1');

    // A frame that names no session is not the session the last id
    // named; holding it would aim a transfer at playback this client
    // no longer drives.
    h.bus.handleFrame({
      'type': 'endpoint-cmd',
      'id': 'e2',
      'verb': 'load',
      'itemPids': [pidB],
      'index': 0,
    });
    await pumpEventQueue();
    expect(h.controller.mirrorSessionId, isNull);
  });

  test('a gapless crossing does not re-send the queue', () async {
    final h = _build();
    h.container.playback.play([testItem(pidA), testItem(pidB)], source: _album);
    await pumpEventQueue();
    expect(_queued(h.sent), hasLength(1));

    // Run the first item out through the prepared second one, which is
    // a crossing rather than the end of anything: the session changes
    // hands and the mirror does not.
    h.engine.advance(const Duration(milliseconds: _trackMs - 20000));
    await pumpEventQueue();
    expect(h.engine.preloadedUrl, contains(pidB));
    h.engine.advance(const Duration(milliseconds: 21000));
    await pumpEventQueue();
    expect(h.engine.loadedUrl, contains(pidB));

    // Still one queue on the wire. Re-sending it has the server
    // re-resolve every entry, rewrite the session, and fan a
    // player-topic invalidation out to every client, once per track.
    expect(_queued(h.sent), hasLength(1));
    expect(_ofType(h.sent, 'session-report').last['index'], 1);
  });

  test('a watched session elsewhere is not adopted as this one', () async {
    final h = _build();
    final started = h.controller.start();
    final reg = _ofType(h.sent, 'register-endpoint').single;
    h.bus.handleFrame({'type': 'ack', 'id': reg['id'], 'endpointId': 'pe-me'});
    await started;
    h.container.playback.play([testItem(pidA)], source: _album);
    await pumpEventQueue();
    final before = _ofType(h.sent, 'session-report').length;

    // What a controller screen watching another device receives. It is
    // not this endpoint's session: taking it would aim a later "play
    // on the kitchen speaker" at someone else's playback, and its
    // ending would stop the reports for playback still running here.
    h.bus.handleFrame({
      'type': 'session',
      'session': {
        'id': 'ps-elsewhere',
        'endpointId': 'pe-other',
        'mine': false,
        'authority': 'mirror',
        'playing': true,
        'index': 0,
        'positionMs': 0,
        'positionAt': DateTime.now().toUtc().toIso8601String(),
        'rate': 1,
        'queueVersion': 1,
        'entries': <Object?>[],
      },
    });
    await pumpEventQueue();
    expect(h.controller.mirrorSessionId, isNot('ps-elsewhere'));

    // And its ending leaves this client's own reporting alone.
    h.bus.handleFrame({
      'type': 'session',
      'session': {
        'id': 'ps-elsewhere',
        'endpointId': 'pe-other',
        'mine': false,
        'authority': 'mirror',
        'ended': true,
        'playing': false,
        'index': 0,
        'positionMs': 0,
        'positionAt': DateTime.now().toUtc().toIso8601String(),
        'rate': 1,
        'queueVersion': 1,
        'entries': <Object?>[],
      },
    });
    await pumpEventQueue();
    h.engine.advance(const Duration(seconds: 2));
    await h.engine.pause();
    await pumpEventQueue();
    expect(
      _ofType(h.sent, 'session-report').length,
      greaterThan(before),
      reason: 'local playback keeps reporting',
    );
  });

  test('an unknown verb answers ok false', () async {
    final h = _build();
    await _cmd(h, 'levitate', id: 'e9');
    final result = _ofType(h.sent, 'cmd-result').single;
    expect(result['id'], 'e9');
    expect(result['ok'], isFalse);
  });
}
