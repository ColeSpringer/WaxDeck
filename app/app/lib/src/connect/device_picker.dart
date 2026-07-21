import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import 'connect_providers.dart';
import 'remote_screen.dart';

/// The device picker: every endpoint the caller can play to, plus the
/// active sessions playing elsewhere. Tapping an endpoint moves the
/// current playback there (a transfer when this client's playback
/// already reports a session, a fresh session otherwise); tapping a
/// session opens its remote control.
Future<void> showDevicePicker(
  BuildContext context,
  WidgetRef ref, {
  required String currentPid,
  required int positionMs,
}) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => _DevicePickerSheet(
      hostRef: ref,
      currentPid: currentPid,
      positionMs: positionMs,
    ),
  );
}

class _DevicePickerSheet extends ConsumerWidget {
  const _DevicePickerSheet({
    required this.hostRef,
    required this.currentPid,
    required this.positionMs,
  });

  final WidgetRef hostRef;
  final String currentPid;
  final int positionMs;

  Future<void> _playOn(
    BuildContext context,
    WidgetRef ref,
    PlayerEndpoint endpoint,
  ) async {
    final controller = ref.read(connectControllerProvider);
    final repository = ref.read(repositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    try {
      final sessionId = controller.mirrorSessionId;
      if (sessionId != null) {
        await repository.transferPlaybackSession(sessionId, endpoint.id);
      } else {
        await repository.createPlaybackSession(
          endpointId: endpoint.id,
          itemPids: [currentPid],
          positionMs: positionMs,
        );
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Playing on ${endpoint.name}')),
      );
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final endpoints = ref.watch(playerEndpointsProvider);
    final sessions = ref.watch(playbackSessionsProvider);
    final ownEndpoint = ref.watch(connectControllerProvider).endpointId.value;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Play on', style: TextStyle())),
          ...switch (endpoints) {
            AsyncData(:final value) => [
              for (final ep in value.where((e) => e.id != ownEndpoint))
                Semantics(
                  identifier: 'endpoint-${ep.id}',
                  label: ep.name,
                  button: true,
                  excludeSemantics: true,
                  onTap: () => _playOn(context, ref, ep),
                  child: ListTile(
                    key: Key('endpoint-${ep.id}'),
                    leading: Icon(switch (ep.kind) {
                      'cast' => Icons.cast,
                      'dlna' => Icons.speaker,
                      'jukebox' => Icons.speaker_group,
                      _ => Icons.devices,
                    }),
                    title: Text(ep.name),
                    subtitle: ep.online ? null : const Text('Offline'),
                    enabled: ep.online,
                    onTap: () => _playOn(context, ref, ep),
                  ),
                ),
            ],
            AsyncError() => const [
              ListTile(title: Text('Could not list devices')),
            ],
            _ => const [ListTile(title: Text('Looking for devices'))],
          },
          if (sessions case AsyncData(:final value))
            for (final s in value.where((s) => s.endpointId != ownEndpoint))
              Semantics(
                identifier: 'session-${s.id}',
                label: 'Now playing on ${s.endpointName ?? s.endpointId}',
                button: true,
                excludeSemantics: true,
                onTap: () => _openRemote(context, s),
                child: ListTile(
                  key: Key('session-${s.id}'),
                  leading: const Icon(Icons.play_circle_outline),
                  title: Text(s.currentEntry?.title ?? 'Playing'),
                  subtitle: Text('on ${s.endpointName ?? s.endpointId}'),
                  onTap: () => _openRemote(context, s),
                ),
              ),
        ],
      ),
    );
  }

  void _openRemote(BuildContext context, PlaybackSessionInfo session) {
    Navigator.of(context).pop();
    Navigator.of(hostRef.context).push(
      MaterialPageRoute<void>(
        builder: (_) => RemoteControlScreen(initial: session),
      ),
    );
  }
}
