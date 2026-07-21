import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../player/session_registry.dart';
import '../providers.dart';
import '../sync/sync_providers.dart';
import 'connect_bus.dart';
import 'connect_controller.dart';

/// The bus sends through whichever transport the platform runs (the
/// sync engine natively, the invalidations follower on web); the sync
/// binder plugs the live transport in here once it exists.
class ConnectSender {
  ControlSender? impl;
  bool call(Map<String, Object?> frame) => impl?.call(frame) ?? false;
}

final connectSenderProvider = Provider<ConnectSender>((ref) {
  return ConnectSender();
});

final connectBusProvider = Provider<ConnectBus>((ref) {
  final sender = ref.watch(connectSenderProvider);
  final bus = ConnectBus(send: sender.call);
  ref.onDispose(bus.dispose);
  return bus;
});

final connectControllerProvider = Provider<ConnectEndpointController>((ref) {
  final controller = ConnectEndpointController(
    bus: ref.watch(connectBusProvider),
    repository: ref.watch(repositoryProvider),
    engine: ref.watch(audioEngineProvider),
    registry: ref.watch(currentSessionRegistryProvider),
    deviceName: waxDeckDeviceName ?? 'WaxDeck client',
    clientId: listenClientId,
    sync: ref.watch(syncEngineProvider),
    downloads: ref.watch(downloadManagerProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// Endpoints the caller can play to, refetched on player-topic
/// invalidations.
final playerEndpointsProvider =
    FutureProvider.autoDispose<List<PlayerEndpoint>>(
      (ref) => ref.watch(repositoryProvider).listPlayerEndpoints(),
    );

/// Active sessions visible to the caller.
final playbackSessionsProvider =
    FutureProvider.autoDispose<List<PlaybackSessionInfo>>(
      (ref) => ref.watch(repositoryProvider).listPlaybackSessions(),
    );

/// Wires the connect layer onto a live transport: called by the sync
/// binder once per (re)connect wiring, passing hooks it can attach.
class ConnectBinder {
  ConnectBinder(this._ref);

  final Ref _ref;
  Timer? _pingTimer;
  bool _started = false;

  ConnectBus get bus => _ref.read(connectBusProvider);

  /// Attaches the transport's sender and control routing.
  void bind({
    required ControlSender sender,
    required void Function(void Function(Map<String, Object?>)) routeControl,
  }) {
    _ref.read(connectSenderProvider).impl = sender;
    routeControl(bus.handleFrame);
  }

  /// Runs on every successful (re)connect: register the endpoint,
  /// restore the watch, and refresh the clock offset.
  void onConnected() {
    final controller = _ref.read(connectControllerProvider);
    if (!_started) {
      _started = true;
      unawaited(controller.start());
    } else {
      unawaited(controller.register());
    }
    final watched = bus.watched;
    if (watched != null) bus.watch(watched);
    bus.ping();
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 60), (_) => bus.ping());
  }

  /// Player-topic invalidation: the endpoint and session lists moved.
  void onPlayerInvalidate() {
    _ref.invalidate(playerEndpointsProvider);
    _ref.invalidate(playbackSessionsProvider);
  }

  void dispose() {
    _pingTimer?.cancel();
  }
}

final connectBinderProvider = Provider<ConnectBinder>((ref) {
  final binder = ConnectBinder(ref);
  ref.onDispose(binder.dispose);
  return binder;
});
