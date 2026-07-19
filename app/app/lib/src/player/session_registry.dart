import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'playback_session.dart';

/// Tracks the playback session currently on screen, so loosely coupled
/// surfaces (a transcript cue tapping into the live player) can reach it
/// without threading the object through every route.
///
/// A plain service object on purpose: registration happens inside widget
/// lifecycles where provider state mutations are not allowed, and no one
/// needs change notifications; consumers read the current value at tap
/// time.
class CurrentSessionRegistry {
  PlaybackSession? _current;

  /// The session currently on screen, if any.
  PlaybackSession? get current => _current;

  void register(PlaybackSession session) => _current = session;

  /// Clears the registration, but only if [session] is still the one
  /// registered: a newer player screen must not be unregistered by an
  /// older one tearing down late.
  void unregister(PlaybackSession session) {
    if (identical(_current, session)) _current = null;
  }
}

final currentSessionRegistryProvider = Provider<CurrentSessionRegistry>(
  (ref) => CurrentSessionRegistry(),
);
