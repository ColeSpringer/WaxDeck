import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// Whether this build should offer a slider over its own output.
///
/// The layout system's first volume condition, and its whole extent:
/// desktop and web get one, a phone and a tablet do not. Hardware buttons
/// own local volume on mobile, where a software slider fights the OS
/// volume stack rather than driving it - the engine's own gain rides
/// underneath whatever the side buttons set, so two controls would
/// disagree about one loudness. The other condition is a remote endpoint
/// that reports volume control, which is a different piece of state
/// entirely and is answered by the remote session.
///
/// A provider rather than a bare function because it is a fact about the
/// platform that surfaces branch on, and a test needs to be able to say
/// which platform it is standing on without reaching for a foundation
/// debug global (the test harness pins the target platform to Android,
/// and resetting that global is checked for). P16's settings and P21's
/// volume keys read the same answer.
final localVolumeAvailableProvider = Provider<bool>(
  (ref) =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows,
);

/// This device's own output level, 0 to 1.
///
/// A follower of the engine rather than a store of its own, and that is
/// the whole design: the engine's gain is written from three places
/// nothing in the widget tree hears about - a routed `set-volume` from
/// another device, the sleep timer's fade, and whatever the slider does -
/// so a control keeping its own copy of the number would draw a loudness
/// the output no longer has. The deferred entry that scheduled this named
/// the case exactly: another device could already turn this one down
/// while its own user had no way to.
///
/// The mute is a level of its own rather than a flag, because that is what
/// the engine has: silencing remembers where the slider was, and
/// unsilencing puts it back. A restored level of zero would be a control
/// that cannot undo itself, so it falls back to full.
class OutputVolumeController extends Notifier<double> {
  StreamSubscription<double>? _feed;

  /// Where the level stood when it was silenced, for putting back.
  double? _beforeMute;

  @override
  double build() {
    final engine = ref.watch(audioEngineProvider);
    _feed = engine.volumeStream.listen((volume) {
      final level = volume.clamp(0.0, 1.0);
      // A change from elsewhere lands here too, and a level somebody else
      // set is not a mute this controller can undo: forgetting the
      // remembered level keeps the glyph honest about what it will do.
      if (level > 0) _beforeMute = null;
      state = level;
    });
    ref.onDispose(() => unawaited(_feed?.cancel()));
    return engine.volume.clamp(0.0, 1.0);
  }

  /// Sets the level. Optimistic: the state moves now and the stream
  /// confirms it, because a slider that waits for a platform round trip
  /// per drag frame stutters under the finger.
  ///
  /// A write the platform turns down puts the state back to what the
  /// engine actually has, which is the whole promise of this controller:
  /// optimism that survives its own failure is a control drawing a
  /// loudness the output never took. Back to the *engine's* level rather
  /// than the one held before the call, because the write is not the only
  /// thing that moves the gain - another device raising it during the
  /// await is a level this must not undo.
  ///
  /// The failure is not raised. Every caller is a slider or a glyph that
  /// fires and forgets, so a raised one is an unhandled zone error per
  /// drag frame and nothing on screen; the level snapping back to what the
  /// output has is the report, and it is the one a listener can act on.
  Future<void> set(double volume) async {
    final level = volume.clamp(0.0, 1.0);
    state = level;
    final engine = ref.read(audioEngineProvider);
    try {
      await engine.setVolume(level);
    } on Object catch (failure) {
      debugPrint('the platform would not take the level: $failure');
      if (ref.mounted) state = engine.volume.clamp(0.0, 1.0);
      return;
    }
    // Spent only once the level actually took. Cleared before the write,
    // a refused unmute forgot the level it was restoring and left the
    // retry with nothing to go back to but full.
    if (level > 0) _beforeMute = null;
  }

  /// Silences the output, or puts it back where it was.
  ///
  /// Restoring to full when nothing was remembered is what covers the
  /// launch that finds the engine already at zero: there is no level to go
  /// back to, and a control whose only effect is to stay silent is worse
  /// than one that guesses.
  /// The level is remembered *before* the write, not after it. Assigning
  /// afterwards would step on the stream: another device raising the volume
  /// during the await clears the memory through [_feed], and a late
  /// assignment would put a stale level back and offer to restore it.
  Future<void> toggleMute() async {
    if (state > 0) {
      // set() only forgets a remembered level for a level above zero, so
      // silencing does not clear what was just recorded.
      _beforeMute = state;
      await set(0);
      return;
    }
    final restore = _beforeMute ?? 1.0;
    await set(restore > 0 ? restore : 1.0);
  }
}

final outputVolumeProvider = NotifierProvider<OutputVolumeController, double>(
  OutputVolumeController.new,
);
