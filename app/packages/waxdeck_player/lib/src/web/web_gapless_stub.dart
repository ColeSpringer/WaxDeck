/// Native variant: no browser engine, and nothing to select.
///
/// The classes are declared so that a browser-only test still analyzes
/// on the VM, which is where `flutter analyze` runs; constructing one
/// off the web is a mistake worth an exception rather than a silent
/// no-op.
library;

import '../audio_engine_port.dart';

/// Native stand-in for the timeline player. Never constructed.
///
/// The constructor mirrors the browser one so a browser-only test still
/// analyzes here, which is where `flutter analyze` runs. The element
/// type is deliberately loose: naming `package:web` in this half would
/// undo the split the conditional export exists for.
class HlsTimelinePlayer implements TimelineAudioEngine {
  HlsTimelinePlayer({Object? element, Duration? loadDeadline}) {
    throw UnsupportedError('the timeline engine exists only in a browser');
  }

  /// Whether this browser can play a timeline. Never, off the web.
  bool get supported => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('the timeline engine exists only in a browser');
}

/// Native stand-in for the composite engine. Never constructed.
class WebGaplessEngine implements TimelineAudioEngine {
  WebGaplessEngine(AudioEnginePort standard, {HlsTimelinePlayer? timeline}) {
    throw UnsupportedError('the gapless web engine exists only in a browser');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('the gapless web engine exists only in a browser');
}

/// Off the web, the engine handed in is already gapless.
AudioEnginePort createWebGaplessEngine(AudioEnginePort standard) => standard;
