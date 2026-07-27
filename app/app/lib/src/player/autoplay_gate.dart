import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// Whether the platform turned down the last programmatic resume.
///
/// Browsers refuse a play that no gesture led to, and the app asks for
/// several: a queue handed over by another device, a queue put back at
/// launch, an item started by a routed Connect command. The media is
/// loaded and standing where it belongs in that case, so the deck bar
/// says "Tap to resume" and the tap that follows is exactly the gesture
/// the browser was waiting for.
///
/// It clears itself on the next playing transition rather than on the
/// tap, so a refusal that turns out not to have stuck (the platform
/// started anyway, another surface pressed play) leaves nothing behind.
class AutoplayGate extends Notifier<bool> {
  @override
  bool build() {
    // Watched, not listened: a refusal belongs to the engine that
    // refused it, so a rebuild here means a different engine, and a
    // different engine has refused nothing. The one in the app never
    // rebuilds (it depends on nothing), so this is about tests and
    // about whatever replaces it later.
    final engine = ref.watch(audioEngineProvider);
    final refusals = engine.playbackRefused.listen((reason) {
      // Terse on screen, whole in the console: this is the one failure a
      // field report has no other trace of.
      debugPrint('playback refused by the platform: $reason');
      state = true;
    });
    final transitions = engine.playingStream.listen((playing) {
      if (playing) state = false;
    });
    ref.onDispose(() {
      refusals.cancel();
      transitions.cancel();
    });
    return false;
  }
}

final autoplayBlockedProvider = NotifierProvider<AutoplayGate, bool>(
  AutoplayGate.new,
);
