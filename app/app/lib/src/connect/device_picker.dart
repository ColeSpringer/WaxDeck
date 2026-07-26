import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'connect_providers.dart';

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
    // Every watch belongs to this build, never to the nested builder
    // below: a ref used from a descendant's build runs after this
    // element has closed the dependencies it did not see re-read, so
    // the subscriptions would be torn down and re-listened every time
    // the sheet rebuilt.
    final endpoints = ref.watch(playerEndpointsProvider);
    final sessions = ref.watch(playbackSessionsProvider);
    // This device's own endpoint id arrives with registration, which may
    // land after the sheet opens: listened to rather than read once, or
    // the picker offers to play here, on the device already playing.
    return SafeArea(
      child: ValueListenableBuilder<String?>(
        valueListenable: ref.watch(connectControllerProvider).endpointId,
        builder: (context, ownEndpoint, _) =>
            _rows(context, ref, ownEndpoint, endpoints, sessions),
      ),
    );
  }

  Widget _rows(
    BuildContext context,
    WidgetRef ref,
    String? ownEndpoint,
    AsyncValue<List<PlayerEndpoint>> endpoints,
    AsyncValue<List<PlaybackSessionInfo>> sessions,
  ) {
    // Whatever was listed last stays listed while a refetch runs: both
    // lists are invalidated whenever any session anywhere starts, ends,
    // or changes its queue, and a sheet that empties for the length of
    // every one of those is one whose rows move under a finger already
    // on the way to them. (Riverpod keeps the value across a refresh,
    // so this is about the error case: stale devices beat none.)
    final devices = endpoints.value;
    final playing = sessions.value;
    return ListView(
      shrinkWrap: true,
      children: [
        const ListTile(title: Text('Play on', style: TextStyle())),
        ...switch (devices) {
          null when endpoints.hasError => const [
            ListTile(title: Text('Could not list devices')),
          ],
          null => const [ListTile(title: Text('Looking for devices'))],
          final value => [
            for (final ep in value.where((e) => e.id != ownEndpoint))
              Semantics(
                identifier: SemanticsIds.endpoint(ep.id),
                label: ep.name,
                button: true,
                excludeSemantics: true,
                onTap: () => _playOn(context, ref, ep),
                child: ListTile(
                  key: Key(SemanticsIds.endpoint(ep.id)),
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
        },
        for (final s in (playing ?? const <PlaybackSessionInfo>[]).where(
          (s) => s.endpointId != ownEndpoint,
        ))
          Semantics(
            identifier: SemanticsIds.session(s.id),
            label: 'Now playing on ${s.endpointName ?? s.endpointId}',
            button: true,
            excludeSemantics: true,
            onTap: () => _openRemote(context, s),
            child: ListTile(
              key: Key(SemanticsIds.session(s.id)),
              leading: const Icon(Icons.play_circle_outline),
              title: Text(s.currentEntry?.title ?? 'Playing'),
              subtitle: Text('on ${s.endpointName ?? s.endpointId}'),
              onTap: () => _openRemote(context, s),
            ),
          ),
      ],
    );
  }

  void _openRemote(BuildContext context, PlaybackSessionInfo session) {
    Navigator.of(context).pop();
    GoRouter.of(hostRef.context).push<void>(WaxRoute.remote, extra: session);
  }
}
