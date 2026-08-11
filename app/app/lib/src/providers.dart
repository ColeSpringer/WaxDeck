import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

import 'auth/credential_store.dart';
import 'connectivity/connectivity_port.dart';
import 'fonts_warmup.dart';
import 'auth/loopback/loopback.dart';
import 'auth/oidc_flow.dart';
import 'auth/oidc_ports.dart';
import 'uploads/share_intake.dart';

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
///
/// The transport carries the font-warmup interceptor: every response is
/// where library metadata first arrives, so the deferred script faces
/// (the deferred scripts) start loading before any screen lays the
/// text out, with no per-screen wiring to forget.
final repositoryProvider = Provider<WaxDeckRepository>(
  (ref) => WaxDeckClient(
    baseUrl: waxDeckBaseUrl,
    dio: Dio()..interceptors.add(FontWarmupInterceptor()),
  ),
);

/// Where the bearer token persists between launches. Web builds keep
/// nothing: the HttpOnly session cookie is the credential there.
final credentialStoreProvider = Provider<CredentialStorePort>(
  (ref) => kIsWeb ? InMemoryCredentialStore() : const SecureCredentialStore(),
);

/// Browser opening, wrapped so widget code never touches url_launcher.
final urlOpenerProvider = Provider<UrlOpenerPort>(
  (ref) => const LauncherUrlOpener(),
);

/// What this device's connection costs, wrapped so widget code never
/// touches connectivity_plus. Read by the two wifi-only settings.
final connectivityProvider = Provider<ConnectivityPort>(
  (ref) => createConnectivityPort(),
);

/// Whether this is a machine somebody walks away from.
///
/// A desktop build and nothing else: not web, whose tab is not a room's
/// stereo and whose window the app does not own, and not a phone, which
/// locks its own screen. A provider rather than a bare check because it
/// is a fact about the platform that surfaces branch on, and a test has
/// to be able to say which platform it is standing on - the harness pins
/// the target platform to Android, and resetting that global is checked
/// for. Same shape and same reason as `localVolumeAvailableProvider`,
/// which asks a different question about the same set.
final desktopProvider = Provider<bool>(
  (ref) =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows),
);

/// Incoming deep links, wrapped so widget code never touches app_links.
final deepLinkProvider = Provider<DeepLinkPort>((ref) => AppLinksDeepLinks());

/// Share-sheet payloads, wrapped so widget code never touches the
/// platform channel. Inert everywhere but Android.
final shareIntakeProvider = Provider<ShareIntakePort>(
  (ref) => createShareIntakePort(),
);

/// The OIDC client flow with its platform ports plugged in.
final oidcFlowProvider = Provider<OidcLoginFlow>(
  (ref) => OidcLoginFlow(
    repository: ref.watch(repositoryProvider),
    urlOpener: ref.watch(urlOpenerProvider),
    deepLinks: ref.watch(deepLinkProvider),
    bindLoopbackReceiver: bindLoopbackReceiver,
  ),
);

/// The one audio engine. Tests override this with a [FakeEngine].
final audioEngineProvider = Provider<AudioEnginePort>((ref) {
  final engine = JustAudioEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

/// The app's handle on the OS media session's extra control.
///
/// Bound by `initMediaSession` where the platform registers one, and a
/// no-op everywhere else, so a caller raising a control never has to
/// ask which platform it is on.
final mediaSessionProvider = Provider<MediaSessionHandle>(
  (ref) => MediaSessionHandle(),
);

/// Client identifier reported with listen sessions.
String get listenClientId {
  if (kIsWeb) return 'waxdeck-flutter-web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'waxdeck-flutter-android',
    TargetPlatform.linux => 'waxdeck-flutter-linux',
    TargetPlatform.windows => 'waxdeck-flutter-windows',
    // Nothing else builds; the arm keeps the switch total.
    _ => 'waxdeck-flutter',
  };
}

/// Device-list label sent with native logins. Null on web, where the
/// server labels the session from the user agent instead.
String? get waxDeckDeviceName {
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'WaxDeck Android',
    TargetPlatform.linux => 'WaxDeck Linux',
    TargetPlatform.windows => 'WaxDeck Windows',
    _ => 'WaxDeck',
  };
}
