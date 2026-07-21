import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/connect/connect_bus.dart';
import 'package:waxdeck/src/connect/connect_providers.dart';
import 'package:waxdeck/src/connect/device_picker.dart';
import 'package:waxdeck/src/connect/remote_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

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
  const _PickerHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => showDevicePicker(
            context,
            ref,
            currentPid: 'tr-current',
            positionMs: 5000,
          ),
          child: const Text('open'),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('the picker lists endpoints and starts playback there', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem('tr-current')])
      ..playerEndpoints = [_endpoint];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          audioEngineProvider.overrideWithValue(FakeEngine()),
        ],
        child: const MaterialApp(home: _PickerHost()),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Kitchen speaker'), findsOneWidget);
    await tester.tap(find.byKey(const Key('endpoint-pe-speaker')));
    await tester.pumpAndSettle();

    // No reported mirror session exists, so the tap creates a session
    // with the current item and position.
    expect(repo.createPlaybackSessionCalls, hasLength(1));
    final call = repo.createPlaybackSessionCalls.single;
    expect(call.endpointId, 'pe-speaker');
    expect(call.itemPids, ['tr-current']);
    expect(call.positionMs, 5000);
    expect(find.text('Playing on Kitchen speaker'), findsOneWidget);
  });

  testWidgets('the remote screen sends commands and transfers here', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem('tr-x')]);
    final sent = <Map<String, Object?>>[];
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        audioEngineProvider.overrideWithValue(FakeEngine()),
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
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: RemoteControlScreen(initial: _session())),
      ),
    );
    await tester.pump();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Kitchen speaker'), findsOneWidget);

    // The screen watched its session on init.
    expect(sent.any((f) => f['type'] == 'watch'), isTrue);

    // Toggle sends pause for a playing session; answer the ack so the
    // future settles.
    await tester.tap(find.byKey(const Key('remote-toggle')));
    await tester.pump();
    final cmd = sent.lastWhere((f) => f['type'] == 'cmd');
    expect(cmd['verb'], 'pause');
    expect(cmd['sessionId'], 'ps-remote');
    container.read(connectBusProvider).handleFrame({
      'type': 'ack',
      'id': cmd['id'],
    });
    await tester.pump();

    // Play here transfers to this client's endpoint once registered.
    container.read(connectControllerProvider).endpointId.value = 'pe-me';
    await tester.tap(find.byKey(const Key('remote-play-here')));
    await tester.pumpAndSettle();
    expect(repo.transferPlaybackSessionCalls, hasLength(1));
    expect(repo.transferPlaybackSessionCalls.single, (
      sessionId: 'ps-remote',
      endpointId: 'pe-me',
    ));
  });
}
