import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Override lives here rather than in the root library.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/connect/connect_bus.dart';
import 'package:waxdeck/src/connect/connect_providers.dart';
import 'package:waxdeck/src/connect/device_picker.dart';
import 'package:waxdeck/src/connect/remote_screen.dart';
import 'package:waxdeck/src/connect/remote_session.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'player_host.dart';
import 'routed_host.dart';

const _endpoint = PlayerEndpoint(
  id: 'pe-speaker',
  kind: 'cast',
  name: 'Kitchen speaker',
  online: true,
  shared: true,
  mine: false,
  volumeControl: true,
  rateControl: false,
);

const _offline = PlayerEndpoint(
  id: 'pe-porch',
  kind: 'dlna',
  name: 'Porch radio',
  online: false,
  shared: true,
  mine: false,
  volumeControl: false,
  rateControl: false,
);

PlaybackSessionInfo _session({bool playing = true}) => PlaybackSessionInfo(
  id: 'ps-remote',
  endpointId: 'pe-speaker',
  endpointName: 'Kitchen speaker',
  mine: true,
  authority: 'remote',
  playing: playing,
  index: 0,
  positionMs: 1000,
  positionAt: DateTime.now().toUtc(),
  rate: 1,
  volume: 0.8,
  queueVersion: 1,
  entries: const [
    PlaybackSessionEntry(pid: 'tr-x', title: 'Alpha', durationMs: 30000),
  ],
);

class _PickerHost extends ConsumerWidget {
  const _PickerHost({
    this.currentPid = 'tr-current',
    this.from = CastSource.here,
  });

  final String? currentPid;
  final CastSource from;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => showDevicePicker(
            context,
            from: from,
            currentPid: currentPid,
            positionMs: 5000,
          ),
          child: const Text('open'),
        ),
      ),
    );
  }
}

/// The same container the player tests build, which is the one every
/// surface here needs: a repository and an engine.
ProviderContainer _container({
  required FakeRepository repo,
  List<Override> extra = const <Override>[],
}) => playbackContainer(repo: repo, engine: FakeEngine(), extra: extra);

void main() {
  testWidgets('the picker lists endpoints and starts playback there', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem('tr-current')])
      ..playerEndpoints = [_endpoint];
    final container = _container(repo: repo);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(const _PickerHost()),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Kitchen speaker'), findsOneWidget);
    // Grouped by what an endpoint is, so a cast device sits under the
    // speakers heading rather than in one flat list.
    expect(find.text('Speakers and displays'), findsOneWidget);
    // The capability hint the picker promises, so "can I turn this down?"
    // is answered before the trip rather than after it.
    expect(find.text('Remote volume control'), findsOneWidget);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.endpoint('pe-speaker')),
    );
    await tester.pumpAndSettle();

    // No reported mirror session exists, so the tap creates a session
    // with the current item and position.
    expect(repo.createPlaybackSessionCalls, hasLength(1));
    final call = repo.createPlaybackSessionCalls.single;
    expect(call.endpointId, 'pe-speaker');
    expect(call.itemPids, ['tr-current']);
    expect(call.positionMs, 5000);
    expect(find.text('Playing on Kitchen speaker'), findsOneWidget);

    // Starting playback elsewhere is what the shell now follows: the bar's
    // remote face and the remote screen both read this.
    expect(container.read(remoteSessionProvider)?.id, 'ps-created');

    // A playing remote session feeds a position, which is a timer that
    // lives as long as the session does; the harness checks for pending
    // ones when the tree goes away, and a container teardown runs after
    // that. Letting go here is what a listener does with the triad.
    container.read(remoteSessionProvider.notifier).release();
  });

  // Both faces can be live at once, so which session moves is the face's
  // answer: inferring it sent the observed session to the picked endpoint
  // and left the album playing here where it was.
  testWidgets('casting from here moves what is here, not what is elsewhere', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem('tr-current')])
      ..playerEndpoints = [_endpoint];
    final container = _container(repo: repo);
    // A session in the kitchen while an album plays here.
    container.read(remoteSessionProvider.notifier).adopt(_session());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(const _PickerHost()),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.endpoint('pe-speaker')),
    );
    await tester.pumpAndSettle();

    // The local item went, and the kitchen session was left alone.
    expect(repo.transferPlaybackSessionCalls, isEmpty);
    expect(repo.createPlaybackSessionCalls, hasLength(1));
    expect(repo.createPlaybackSessionCalls.single.itemPids, ['tr-current']);

    container.read(remoteSessionProvider.notifier).release();
  });

  testWidgets('casting from a playing device hands the whole queue over, '
      'and silences it', (tester) async {
    // A device plays one thing. Casting from one that is playing is a
    // handoff: the queue, index, position, and modes move to the target
    // and this device goes quiet - it used to create a session for the
    // one item the row named, leave everything after it behind, and go
    // on playing the album into the room it had just left.
    final repo = FakeRepository(items: [testItem('tr-one'), testItem('tr-two')])
      ..playerEndpoints = [_endpoint];
    final sent = <Map<String, Object?>>[];
    final container = _container(
      repo: repo,
      extra: [
        connectSenderProvider.overrideWithValue(
          ConnectSender()
            ..impl = (frame) {
              sent.add(Map.of(frame));
              return true;
            },
        ),
      ],
    );
    final connect = container.read(connectControllerProvider);
    final started = connect.start();
    final register = sent.firstWhere((f) => f['type'] == 'register-endpoint');
    container.read(connectBusProvider).handleFrame({
      'type': 'ack',
      'id': register['id'],
      'endpointId': 'pe-me',
    });
    await started;

    final harness = PlayerHarness(container);
    harness.play([testItem('tr-one'), testItem('tr-two')], startIndex: 1);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(const _PickerHost(currentPid: 'tr-two')),
      ),
    );
    await tester.pumpAndSettle();
    container.read(queueControllerProvider.notifier).setRepeat(QueueRepeat.all);
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.endpoint('pe-speaker')),
    );
    await tester.pumpAndSettle();

    final call = repo.createPlaybackSessionCalls.single;
    expect(call.itemPids, ['tr-one', 'tr-two']);
    expect(call.index, 1);
    expect(call.repeat, 'all');
    expect(call.shuffle, isFalse);
    expect(call.rate, 1.0);
    // Named itself, so the server can end a mirror session this client
    // never learned the id of.
    expect(call.handoffFrom, 'pe-me');

    // And it stopped: the bar's precedence puts local playback over the
    // remote face, so a device still playing would go on naming its own
    // queue while the sound came out of another room.
    expect(container.read(queueControllerProvider).isEmpty, isTrue);
    expect(connect.mirrorSessionId, isNull);
    expect(container.read(remoteSessionProvider)?.id, 'ps-created');

    container.read(remoteSessionProvider.notifier).release();
  });

  testWidgets('a transfer of a session the server has lost falls through to '
      'a fresh one', (tester) async {
    // The id is the client's memory of an answer, and the server can
    // have moved on: a restart, a session ended from another controller.
    // That is not a refusal to report, it is the create path.
    final repo = FakeRepository(items: [testItem('tr-one')])
      ..playerEndpoints = [_endpoint]
      ..transferSessionError = const WaxDeckApiException(
        code: 'not-found',
        message: 'no such session',
        statusCode: 404,
      );
    final container = _container(repo: repo);
    container.read(connectControllerProvider).mirrorSessionId = 'ps-gone';

    final harness = PlayerHarness(container);
    harness.play([testItem('tr-one')]);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(const _PickerHost(currentPid: 'tr-one')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.endpoint('pe-speaker')),
    );
    await tester.pumpAndSettle();

    expect(repo.transferPlaybackSessionCalls, hasLength(1));
    expect(repo.createPlaybackSessionCalls, hasLength(1));
    expect(find.text('Playing on Kitchen speaker'), findsOneWidget);

    container.read(remoteSessionProvider.notifier).release();
  });

  testWidgets('the picker during live radio says where a station stays', (
    tester,
  ) async {
    // A station is not a session and does not travel. The rows say so
    // rather than offering a handoff that would hand over silence, and
    // the sessions running elsewhere stay controllable from here.
    final repo = FakeRepository(items: [testItem('tr-current')])
      ..playerEndpoints = [_endpoint]
      ..playbackSessions = [_session()];
    final station = RadioStation(
      pid: 'rs-1',
      name: 'Nightjar FM',
      streamUrl: 'https://stream.example/rs-1',
      createdAt: DateTime.utc(2026, 7, 1),
    );
    repo.radioStationsByPid['rs-1'] = station;
    final container = _container(repo: repo);
    await container.read(radioPlaybackProvider.notifier).play(station);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(const _PickerHost()),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Playing radio here'), findsOneWidget);
    expect(
      find.text('Stations play on the device that tuned them'),
      findsOneWidget,
    );
    final row = tester.widget<WaxOptionRow>(
      find.ancestor(
        of: find.bySemanticsIdentifier(SemanticsIds.endpoint('pe-speaker')),
        matching: find.byType(WaxOptionRow),
      ),
    );
    expect(row.onTap, isNull);
    expect(row.enabled, isFalse);

    // A session somewhere else is still somewhere else, and still
    // controllable from here.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.session('ps-remote')),
      findsOneWidget,
    );

    await container.read(radioPlaybackProvider.notifier).stop();
    await tester.pumpAndSettle();
  });

  testWidgets('a station here says nothing about a session over there', (
    tester,
  ) async {
    // The sheet opened over the kitchen's session is about the kitchen.
    // What is playing on this device is beside the point, and refusing
    // to move that session between two other endpoints - with a
    // sentence about stations under every row - takes a control away
    // for no reason and explains it with a non-sequitur.
    final repo = FakeRepository(items: [testItem('tr-current')])
      ..playerEndpoints = [_endpoint];
    final station = RadioStation(
      pid: 'rs-1',
      name: 'Nightjar FM',
      streamUrl: 'https://stream.example/rs-1',
      createdAt: DateTime.utc(2026, 7, 1),
    );
    repo.radioStationsByPid['rs-1'] = station;
    final container = _container(repo: repo);
    await container.read(radioPlaybackProvider.notifier).play(station);
    container.read(remoteSessionProvider.notifier).adopt(_session());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(const _PickerHost(from: CastSource.elsewhere)),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.text('Stations play on the device that tuned them'),
      findsNothing,
    );
    final row = tester.widget<WaxOptionRow>(
      find.ancestor(
        of: find.bySemanticsIdentifier(SemanticsIds.endpoint('pe-speaker')),
        matching: find.byType(WaxOptionRow),
      ),
    );
    expect(row.enabled, isTrue);

    container.read(remoteSessionProvider.notifier).release();
    await container.read(radioPlaybackProvider.notifier).stop();
    await tester.pumpAndSettle();
  });

  // The server answers a transfer to the current endpoint with a 200
  // no-op, so a live row there is a control that does nothing.
  testWidgets('the endpoint a session is already on is not a control', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem('tr-x')])
      ..playerEndpoints = [_endpoint];
    final container = _container(repo: repo);
    container.read(remoteSessionProvider.notifier).adopt(_session());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(
          const _PickerHost(currentPid: null, from: CastSource.elsewhere),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final row = find.bySemanticsIdentifier(SemanticsIds.endpoint('pe-speaker'));
    expect(row, findsOneWidget);
    expect(
      tester
          .getSemantics(row)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
      reason: 'the endpoint the session is on offers no trip to itself',
    );
    await tester.tap(row, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(repo.transferPlaybackSessionCalls, isEmpty);

    container.read(remoteSessionProvider.notifier).release();
  });

  testWidgets('an offline endpoint says why rather than disappearing', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem('tr-current')])
      ..playerEndpoints = [_offline];
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: _container(repo: repo),
        child: routedHost(const _PickerHost()),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Porch radio'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.endpoint('pe-porch')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(repo.createPlaybackSessionCalls, isEmpty);
  });

  testWidgets('the picker holds its rows across a refresh', (tester) async {
    final repo = FakeRepository(items: [testItem('tr-current')])
      ..playerEndpoints = [_endpoint];
    var listings = 0;
    final refetch = Completer<void>();
    final container = _container(
      repo: repo,
      extra: [
        // The second listing is held open, which is the window the
        // sheet has to survive. A real one is a round trip wide.
        playbackSessionsProvider.overrideWith((ref) async {
          if (listings++ > 0) await refetch.future;
          return [_session()];
        }),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(const _PickerHost()),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final row = find.bySemanticsIdentifier(SemanticsIds.session('ps-remote'));
    expect(row, findsOneWidget);

    // The player topic invalidates both lists whenever any session
    // anywhere starts, ends, or changes its queue, which on a busy
    // server is often. The rows stay put through it.
    container.read(connectBinderProvider).onPlayerInvalidate();
    await tester.pump();
    expect(listings, 2);
    expect(row, findsOneWidget);
    expect(find.text('Kitchen speaker'), findsWidgets);

    refetch.complete();
    await tester.pumpAndSettle();
    expect(row, findsOneWidget);
  });

  testWidgets('the remote screen sends commands and transfers here', (
    tester,
  ) async {
    // The endpoint list is where the volume capability comes from: the
    // session reports a level, and whether it can be *set* is the
    // endpoint's own claim, which the server enforces.
    final repo = FakeRepository(items: [testItem('tr-x')])
      ..playerEndpoints = [_endpoint];
    final sent = <Map<String, Object?>>[];
    final container = _container(
      repo: repo,
      extra: [
        connectBusProvider.overrideWith((ref) {
          final bus = ConnectBus(
            send: (f) {
              sent.add(Map.of(f));
              return true;
            },
          );
          ref.onDispose(bus.dispose);
          return bus;
        }),
      ],
    );
    // Adopting is what the picker does; the screen is a viewer of it.
    container.read(remoteSessionProvider.notifier).adopt(_session());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(const RemoteControlScreen(), pushed: true),
      ),
    );
    await tester.pump();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Kitchen speaker'), findsOneWidget);

    // The controller watched the session when it adopted it, which is what
    // makes the deck bar's face survive this screen being left.
    expect(sent.any((f) => f['type'] == 'watch'), isTrue);

    // Toggle sends pause for a playing session; answer the ack so the
    // future settles.
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.remoteToggle));
    await tester.pump();
    final cmd = sent.lastWhere((f) => f['type'] == 'cmd');
    expect(cmd['verb'], 'pause');
    expect(cmd['sessionId'], 'ps-remote');
    container.read(connectBusProvider).handleFrame({
      'type': 'ack',
      'id': cmd['id'],
    });
    await tester.pump();

    // The endpoint reports volume control, so the screen offers its level
    // this is where a phone gets the slider 5.2 gives it, since the
    // compact deck bar has no right cluster to hold one.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.remoteVolume),
      findsOneWidget,
    );

    // Transfer here moves the session to this client's endpoint once
    // registered, and stops treating it as somewhere else.
    container.read(connectControllerProvider).endpointId.value = 'pe-me';
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.remotePlayHere));
    await tester.pumpAndSettle();
    expect(repo.transferPlaybackSessionCalls, hasLength(1));
    expect(repo.transferPlaybackSessionCalls.single, (
      sessionId: 'ps-remote',
      endpointId: 'pe-me',
    ));
    expect(container.read(remoteSessionProvider), isNull);
  });

  testWidgets('routed volume is paced leading and trailing', (tester) async {
    // The slider reports a value per step crossed, and each one here is
    // a WS round trip another device has to apply: the first goes now -
    // that first response is how the user judges the control works -
    // then at most one per gap, always ending on the final value.
    final repo = FakeRepository(items: [testItem('tr-x')])
      ..playerEndpoints = [_endpoint];
    final sent = <Map<String, Object?>>[];
    late ConnectBus bus;
    final container = _container(
      repo: repo,
      extra: [
        connectBusProvider.overrideWith((ref) {
          bus = ConnectBus(
            send: (f) {
              sent.add(Map.of(f));
              // Self-acking, so no command future is left on the 10 s
              // timeout timer.
              if (f['type'] == 'cmd') {
                bus.handleFrame({'type': 'ack', 'id': f['id']});
              }
              return true;
            },
          );
          ref.onDispose(bus.dispose);
          return bus;
        }),
      ],
    );
    final controller = container.read(remoteSessionProvider.notifier);
    controller.adopt(_session());

    List<Object?> volumes() => sent
        .where((f) => f['type'] == 'cmd' && f['verb'] == 'set-volume')
        .map((f) => f['volume'])
        .toList();

    // A swipe: a burst of live step values.
    unawaited(controller.setVolume(0.6));
    unawaited(controller.setVolume(0.55));
    unawaited(controller.setVolume(0.5));
    expect(volumes(), [0.6], reason: 'the first change goes now');

    await tester.pump(const Duration(milliseconds: 200));
    expect(volumes(), [
      0.6,
      0.5,
    ], reason: 'the gap closes on the newest level, skipping the stale one');

    // Nothing pending: the follow-up gap closes silently.
    await tester.pump(const Duration(milliseconds: 200));
    expect(volumes(), [0.6, 0.5]);

    // A level still queued when the session is let go stays unsent.
    unawaited(controller.setVolume(0.4));
    unawaited(controller.setVolume(0.3));
    controller.release();
    await tester.pump(const Duration(milliseconds: 400));
    expect(volumes(), [
      0.6,
      0.5,
      0.4,
    ], reason: 'a released session gets no trailing level');
  });

  testWidgets('a slow ack holds the trailing level to one in flight', (
    tester,
  ) async {
    // The gap bounds the rate and the ack bounds the backlog: with the
    // leading send still un-acked past the gap, the trailing level waits
    // for the answer instead of stacking a second command against its
    // ten-second timeout.
    final repo = FakeRepository(items: [testItem('tr-x')])
      ..playerEndpoints = [_endpoint];
    final sent = <Map<String, Object?>>[];
    late ConnectBus bus;
    final container = _container(
      repo: repo,
      extra: [
        connectBusProvider.overrideWith((ref) {
          bus = ConnectBus(
            send: (f) {
              sent.add(Map.of(f));
              return true;
            },
          );
          ref.onDispose(bus.dispose);
          return bus;
        }),
      ],
    );
    final controller = container.read(remoteSessionProvider.notifier);
    controller.adopt(_session());

    List<Object?> volumes() => sent
        .where((f) => f['type'] == 'cmd' && f['verb'] == 'set-volume')
        .map((f) => f['volume'])
        .toList();

    void ackLastCmd() => bus.handleFrame({
      'type': 'ack',
      'id': sent.lastWhere((f) => f['type'] == 'cmd')['id'],
    });

    unawaited(controller.setVolume(0.6));
    unawaited(controller.setVolume(0.5));
    expect(volumes(), [0.6]);

    // The gap closes with the ack still outstanding: nothing new goes
    // out.
    await tester.pump(const Duration(milliseconds: 400));
    expect(volumes(), [0.6], reason: 'one command in flight at a time');

    // The ack lands; the trailing level follows at once.
    ackLastCmd();
    await tester.pump();
    expect(volumes(), [0.6, 0.5]);

    // Settle the trailing command too, so no future is left on its
    // timeout, and let the session go with its pacing timer.
    ackLastCmd();
    await tester.pump();
    controller.release();
    // One more advance for the provider disposal the release schedules.
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('the routed level is optimistic and settles on frames', (
    tester,
  ) async {
    // Without the optimistic beat a released drag snapped to the previous
    // frame's level for the whole round trip. The sent level holds while
    // a send is out - a stale frame must not bounce the knob - and the
    // frames take over once every send has settled.
    final repo = FakeRepository(items: [testItem('tr-x')])
      ..playerEndpoints = [_endpoint];
    final sent = <Map<String, Object?>>[];
    late ConnectBus bus;
    final container = _container(
      repo: repo,
      extra: [
        connectBusProvider.overrideWith((ref) {
          bus = ConnectBus(
            send: (f) {
              sent.add(Map.of(f));
              return true;
            },
          );
          ref.onDispose(bus.dispose);
          return bus;
        }),
      ],
    );
    final controller = container.read(remoteSessionProvider.notifier);
    controller.adopt(_session());
    expect(container.read(remoteSessionProvider)?.volume, 0.8);

    void frameWithVolume(double volume) => bus.handleFrame({
      'type': 'session',
      'session': <String, dynamic>{
        'id': 'ps-remote',
        'endpointId': 'pe-speaker',
        'playing': true,
        'volume': volume,
        'positionAt': DateTime.now().toUtc().toIso8601String(),
      },
    });

    unawaited(controller.setVolume(0.5));
    expect(
      container.read(remoteSessionProvider)?.volume,
      0.5,
      reason: 'the knob holds the sent level through the round trip',
    );

    // A frame that predates the send carries the old level; the sent one
    // holds until the command settles.
    frameWithVolume(0.8);
    await tester.pump();
    expect(container.read(remoteSessionProvider)?.volume, 0.5);

    // The ack lands; the next frame is the endpoint's own answer and the
    // override lets go - including of a change somebody else made.
    bus.handleFrame({
      'type': 'ack',
      'id': sent.lastWhere((f) => f['type'] == 'cmd')['id'],
    });
    await tester.pump();
    frameWithVolume(0.7);
    await tester.pump();
    expect(container.read(remoteSessionProvider)?.volume, 0.7);

    controller.release();
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('a new session is not gated behind the old one\'s ack', (
    tester,
  ) async {
    // A command can outlive the session it was sent for. Release, adopt,
    // and the first slider move on the new device must lead immediately
    // rather than queue behind a stale command's ten-second timeout - and
    // the stale ack, landing later, must not disturb the new pacing.
    final repo = FakeRepository(items: [testItem('tr-x')])
      ..playerEndpoints = [_endpoint];
    final sent = <Map<String, Object?>>[];
    late ConnectBus bus;
    final container = _container(
      repo: repo,
      extra: [
        connectBusProvider.overrideWith((ref) {
          bus = ConnectBus(
            send: (f) {
              sent.add(Map.of(f));
              return true;
            },
          );
          ref.onDispose(bus.dispose);
          return bus;
        }),
      ],
    );
    final controller = container.read(remoteSessionProvider.notifier);

    List<Object?> volumes() => sent
        .where((f) => f['type'] == 'cmd' && f['verb'] == 'set-volume')
        .map((f) => f['volume'])
        .toList();
    List<Object?> cmdIds() => sent
        .where((f) => f['type'] == 'cmd' && f['verb'] == 'set-volume')
        .map((f) => f['id'])
        .toList();

    controller.adopt(_session());
    unawaited(controller.setVolume(0.6));
    expect(volumes(), [0.6]);

    controller.release();
    await tester.pump(const Duration(milliseconds: 1));
    controller.adopt(_session());

    unawaited(controller.setVolume(0.4));
    expect(volumes(), [
      0.6,
      0.4,
    ], reason: 'the new session leads at once, not behind the stale ack');

    // The stale ack lands late: the new session's in-flight command must
    // keep its place (no double-send of a queued level).
    unawaited(controller.setVolume(0.3));
    bus.handleFrame({'type': 'ack', 'id': cmdIds().first});
    await tester.pump();
    expect(volumes(), [
      0.6,
      0.4,
    ], reason: 'the stale ack does not flush the new session\'s trailing');

    bus.handleFrame({'type': 'ack', 'id': cmdIds().last});
    await tester.pump(const Duration(milliseconds: 200));
    expect(volumes(), [0.6, 0.4, 0.3]);

    bus.handleFrame({'type': 'ack', 'id': cmdIds().last});
    await tester.pump();
    controller.release();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('leaving a session playing stops controlling and nothing else', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem('tr-x')]);
    final container = _container(repo: repo);
    container.read(remoteSessionProvider.notifier).adopt(_session());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(const RemoteControlScreen(), pushed: true),
      ),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.remoteLeave));
    await tester.pumpAndSettle();

    expect(container.read(remoteSessionProvider), isNull);
    // The whole point of the choice: the room keeps playing.
    expect(repo.deletePlaybackSessionCalls, isEmpty);
  });

  testWidgets('stopping playback there ends the session', (tester) async {
    final repo = FakeRepository(items: [testItem('tr-x')]);
    final container = _container(repo: repo);
    container.read(remoteSessionProvider.notifier).adopt(_session());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(const RemoteControlScreen(), pushed: true),
      ),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.remoteStopThere));
    await tester.pumpAndSettle();

    expect(repo.deletePlaybackSessionCalls, ['ps-remote']);
    expect(container.read(remoteSessionProvider), isNull);
  });

  testWidgets('a session ending elsewhere releases the controller', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem('tr-x')]);
    final container = _container(repo: repo);
    final controller = container.read(remoteSessionProvider.notifier);
    controller.adopt(_session());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(const RemoteControlScreen(), pushed: true),
      ),
    );
    await tester.pump();
    expect(find.text('Alpha'), findsOneWidget);

    // Somebody stopped it in the kitchen. The screen has nothing left to
    // control and says so instead of drawing a dead transport.
    container.read(connectBusProvider).handleFrame({
      'type': 'session',
      'session': <String, dynamic>{
        'id': 'ps-remote',
        'endpointId': 'pe-speaker',
        'ended': true,
        'positionAt': DateTime.now().toUtc().toIso8601String(),
      },
    });
    await tester.pumpAndSettle();

    expect(container.read(remoteSessionProvider), isNull);
    expect(find.text('Nothing playing elsewhere'), findsOneWidget);
  });

  testWidgets('the connection check renders each base and its notes', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem('tr-current')])
      ..playerEndpoints = [_endpoint]
      ..preflightBases = const [
        CastPreflightBase(
          base: 'https://waxdeck.example',
          source: 'configured',
          reachable: false,
          notes: ['The certificate is not publicly trusted.'],
        ),
        CastPreflightBase(
          base: 'http://192.168.1.20:4420',
          source: 'detected',
          reachable: true,
          notes: [],
        ),
      ];
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: _container(repo: repo),
        child: routedHost(const _PickerHost()),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.pickerOverflow));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.pickerCheck));
    await tester.pumpAndSettle();

    expect(find.text('https://waxdeck.example'), findsOneWidget);
    expect(find.text('Configured address, not reachable'), findsOneWidget);
    expect(
      find.text('The certificate is not publicly trusted.'),
      findsOneWidget,
    );
    expect(find.text('http://192.168.1.20:4420'), findsOneWidget);
    expect(find.text('Detected on this network, reachable'), findsOneWidget);
  });

  testWidgets('a multi-part book refused by a device offers a way out', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem('bk-1')])
      ..playerEndpoints = [_endpoint]
      ..createSessionError = const WaxDeckApiException(
        code: 'feature-unavailable',
        message: 'multi-part audiobooks cannot play on this endpoint yet: bk-1',
      );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: _container(repo: repo),
        child: routedHost(const _PickerHost(currentPid: 'bk-1')),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.endpoint('pe-speaker')),
    );
    await tester.pumpAndSettle();

    // The server's typed refusal, rendered as the thing to do about it
    // rather than as the sentence a server logs.
    expect(
      find.textContaining("can't play on Kitchen speaker yet"),
      findsOneWidget,
    );
    expect(
      find.textContaining('Play it on this device instead'),
      findsOneWidget,
    );
  });
}
