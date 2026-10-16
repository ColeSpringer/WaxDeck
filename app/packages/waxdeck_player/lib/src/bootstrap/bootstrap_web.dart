import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import '../release_bound.dart';

/// Web variant: just_audio ships its own web backend, wrapped so a player
/// it cannot let go holds nothing behind it (see [ReleaseBoundedPlatform]).
/// Keeping media_kit out of this compilation unit keeps ffi out of WasmGC
/// builds.
void ensureAudioEngineInitialized() {
  final platform = JustAudioPlatform.instance;
  if (platform is ReleaseBoundedPlatform) return;
  JustAudioPlatform.instance = ReleaseBoundedPlatform(platform);
}
