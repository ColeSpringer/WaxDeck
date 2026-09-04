/// Browser variant: the real engines, plus the factory the app calls.
library;

import '../audio_engine_port.dart';
import 'web_gapless_engine_web.dart';

export 'hls_timeline_player_web.dart';
export 'web_gapless_engine_web.dart';

/// Wraps [standard] so a music queue can play as one stream where a
/// listener has asked for that.
AudioEnginePort createWebGaplessEngine(AudioEnginePort standard) =>
    WebGaplessEngine(standard);
