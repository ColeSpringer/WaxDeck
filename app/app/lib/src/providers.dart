import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

import 'auth/credential_store.dart';
import 'connectivity/connectivity_port.dart';
import 'fonts_warmup.dart';
import 'sync/test_env/test_env.dart';
import 'auth/loopback/loopback.dart';
import 'auth/oidc_flow.dart';
import 'auth/oidc_ports.dart';
import 'uploads/share_intake.dart';

/// The compile-time server base, for native builds only: the
/// `--dart-define=WAXDECK_BASE_URL=<url>` override when set, else the
/// dev default. What every install used before addresses became a
/// runtime choice, which is why the migration in `main()` adopts it.
///
/// Note the Android loopback gotcha: an emulator reaches the host at
/// http://10.0.2.2:4420 (not localhost, which is the emulator itself),
/// and a physical device needs the host's LAN IP; pass either via
/// WAXDECK_BASE_URL, or use the connect screen.
const compileTimeBaseOverride = String.fromEnvironment('WAXDECK_BASE_URL');
String get compileTimeBaseUrl => compileTimeBaseOverride.isNotEmpty
    ? compileTimeBaseOverride
    : 'http://localhost:4420';

/// The server address adopted before the first frame: `main()` reads
/// the credential store (native) and overrides this. Null means no
/// server is configured yet; web never reads it. Widget tests pump the
/// app without `main()` and over a fake repository, so they default to
/// a stand-in address; a test standing on the connect gate overrides
/// this with null.
final bootServerAddressProvider = Provider<String?>(
  (ref) => inFlutterTest ? 'http://server.test' : null,
);

/// The adopted server address: seeded from [bootServerAddressProvider],
/// moved by the connect screen when a new address is adopted. Null
/// gates a native build behind the connect screen.
final serverAddressProvider =
    NotifierProvider<ServerAddressController, String?>(
      ServerAddressController.new,
    );

class ServerAddressController extends Notifier<String?> {
  @override
  String? build() => ref.watch(bootServerAddressProvider);

  /// Adopts a probed address: persisted, with the stored bearer token
  /// dropped first - a token minted by server A is never presented
  /// elsewhere, which costs one re-login even on a same-server rename.
  /// The mirror and downloads are kept: sync cursors are
  /// generation-bound, so a genuinely different server answers
  /// sync-reset and the mirror rebuilds itself.
  Future<void> adopt(String address) async {
    final store = ref.read(credentialStoreProvider);
    await store.clearToken();
    await store.writeServerAddress(address);
    state = address;
  }
}

/// The base URL every transport derives from. Empty on web, where the
/// SPA is served by the WaxDeck server itself and every URL stays
/// origin-relative; the adopted address on native.
final serverBaseUrlProvider = Provider<String>(
  (ref) => kIsWeb ? '' : (ref.watch(serverAddressProvider) ?? ''),
);

/// Whether this client knows which server it talks to. Web always does
/// (its own origin); native needs an adopted address. Everything that
/// probes the server pre-auth gates on this, so Riverpod's retry
/// ladder never hammers a localhost nobody chose.
final serverConfiguredProvider = Provider<bool>(
  (ref) => kIsWeb || ref.watch(serverAddressProvider) != null,
);

/// The one API repository. Tests override this with a fake.
///
/// The transport carries the font-warmup interceptor: every response is
/// where library metadata first arrives, so the deferred script faces
/// (the deferred scripts) start loading before any screen lays the
/// text out, with no per-screen wiring to forget. Rebuilt whenever the
/// server address moves; everything downstream watches this and
/// cascades.
final repositoryProvider = Provider<WaxDeckRepository>((ref) {
  final dio = Dio()..interceptors.add(FontWarmupInterceptor());
  // A rebuild (the server address moved) replaces the transport; the
  // old one's socket pool goes with it instead of lingering.
  ref.onDispose(dio.close);
  return WaxDeckClient(baseUrl: ref.watch(serverBaseUrlProvider), dio: dio);
});

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

/// Whether this device rides a mobile OS, where the connection in use
/// can be metered and is worth asking about separately. A provider for
/// the same reason [desktopProvider] is: tests stand on a pinned
/// platform.
final mobileProvider = Provider<bool>(
  (ref) =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS),
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
