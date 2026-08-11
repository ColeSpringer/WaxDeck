import 'package:flutter/foundation.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

bool _initialized = false;

/// Native variant: routes just_audio through media_kit (mpv) on the
/// desktops, which have no first-party just_audio backend. Android keeps
/// the bundled backend untouched.
void ensureAudioEngineInitialized() {
  if (_initialized || kIsWeb) return;
  _initialized = true;
  if (defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows) {
    // The engine's preload window is two audio sources; on mpv it is
    // `prefetch-playlist`, which opens and buffers the next entry while
    // the current one plays, that makes crossing between them gapless.
    // Without it desktop still plays the window correctly, just with the
    // load gap the port allows engines to degrade to. Read when each
    // player is created, so it has to be set before the first one is.
    JustAudioMediaKit.prefetchPlaylist = true;
    JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
  }
}
