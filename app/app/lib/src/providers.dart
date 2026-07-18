import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

/// Server origin: on web the SPA is served by the WaxDeck server itself, so
/// relative URLs hit the same origin. Native/desktop dev builds default to
/// localhost and can override with `--dart-define=WAXDECK_BASE_URL=<url>`.
///
/// Note the Android loopback gotcha: an emulator reaches the host at
/// http://10.0.2.2:4420 (not localhost, which is the emulator itself), and a
/// physical device needs the host's LAN IP; pass either via WAXDECK_BASE_URL.
const _envBase = String.fromEnvironment('WAXDECK_BASE_URL');
String get waxDeckBaseUrl =>
    _envBase.isNotEmpty ? _envBase : (kIsWeb ? '' : 'http://localhost:4420');

/// The one API repository. Tests override this with a fake.
final repositoryProvider = Provider<WaxDeckRepository>(
  (ref) => WaxDeckClient(baseUrl: waxDeckBaseUrl),
);

/// The one audio engine. Tests override this with a [FakeEngine].
final audioEngineProvider = Provider<AudioEnginePort>((ref) {
  final engine = JustAudioEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

/// Client identifier reported with listen sessions.
String get listenClientId {
  if (kIsWeb) return 'waxdeck-flutter-web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'waxdeck-flutter-android',
    TargetPlatform.iOS => 'waxdeck-flutter-ios',
    TargetPlatform.linux => 'waxdeck-flutter-linux',
    TargetPlatform.macOS => 'waxdeck-flutter-macos',
    TargetPlatform.windows => 'waxdeck-flutter-windows',
    TargetPlatform.fuchsia => 'waxdeck-flutter-fuchsia',
  };
}
