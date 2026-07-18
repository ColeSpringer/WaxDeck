import 'package:flutter/foundation.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

bool _initialized = false;

/// Native variant: routes just_audio through media_kit (mpv) on the desktop
/// platforms that have no first-party just_audio backend. Mobile keeps the
/// bundled backends untouched.
void ensureAudioEngineInitialized() {
  if (_initialized || kIsWeb) return;
  _initialized = true;
  if (defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows) {
    JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
  }
}
