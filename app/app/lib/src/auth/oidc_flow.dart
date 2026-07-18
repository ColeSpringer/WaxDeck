import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

/// Opens a URL in the environment's browser. On web this navigates the
/// current tab, so a web-mode OIDC login lands the session cookie and
/// reloads the SPA authenticated; on native it opens the system browser.
abstract interface class UrlOpenerPort {
  Future<void> open(String url);
}

/// Delivers the app's incoming deep links (the waxdeck://auth redirect
/// that closes an app-mode OIDC flow).
abstract interface class DeepLinkPort {
  Stream<Uri> get uriLinkStream;
}

/// A bound localhost listener that receives the loopback-mode redirect
/// and hands over the one-time code.
abstract interface class LoopbackReceiverPort {
  /// The bound port, valid after construction.
  int get port;

  /// Resolves with the one-time code once the browser hits /callback.
  Future<String> get code;

  Future<void> close();
}

/// Runs the client half of the OIDC login flows against the ports above.
/// Pure logic, no widget coupling; tests drive it with fakes.
///
/// Every native flow binds the one-time code to this client: a random
/// verifier stays here while its SHA-256 rides the start URL as the
/// challenge, so a code intercepted in transit is useless alone.
class OidcLoginFlow {
  OidcLoginFlow({
    required this.repository,
    required this.urlOpener,
    this.deepLinks,
    this.bindLoopbackReceiver,
    Random? random,
  }) : _random = random ?? Random.secure();

  final WaxDeckRepository repository;
  final UrlOpenerPort urlOpener;
  final DeepLinkPort? deepLinks;
  final Future<LoopbackReceiverPort> Function()? bindLoopbackReceiver;
  final Random _random;

  static const defaultTimeout = Duration(minutes: 5);

  /// Base64url without padding, matching what the server expects for the
  /// challenge parameter.
  static String _base64UrlNoPad(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  /// The challenge for a verifier: base64url SHA-256, no padding, exactly
  /// like a PKCE code challenge.
  static String deriveChallenge(String verifier) =>
      _base64UrlNoPad(sha256.convert(ascii.encode(verifier)).bytes);

  /// A fresh 256-bit verifier, base64url encoded.
  String newVerifier() =>
      _base64UrlNoPad(List.generate(32, (_) => _random.nextInt(256)));

  /// Appends flow parameters to a provider's start URL, keeping whatever
  /// query it already carries.
  static String startUrlFor(
    OidcProvider provider, {
    required String mode,
    required String challenge,
    int? port,
  }) {
    final uri = Uri.parse(provider.startUrl);
    return uri
        .replace(
          queryParameters: {
            ...uri.queryParameters,
            'mode': mode,
            'challenge': challenge,
            if (port != null) 'port': '$port',
          },
        )
        .toString();
  }

  /// Web mode: hand the browser to the server's start URL. The server
  /// finishes the flow with a cookie and redirects back into the SPA, so
  /// there is nothing to await here; the page navigates away.
  Future<void> startWeb(OidcProvider provider) =>
      urlOpener.open(provider.startUrl);

  /// App mode (Android): open the browser and wait for the waxdeck://auth
  /// deep link carrying the one-time code, then exchange it.
  Future<LoginResult> loginWithDeepLink(
    OidcProvider provider, {
    String? deviceName,
    Duration timeout = defaultTimeout,
  }) async {
    final links = deepLinks;
    if (links == null) {
      throw StateError('deep links are not available on this platform');
    }
    final verifier = newVerifier();
    // Subscribe before opening the browser so a fast redirect cannot slip
    // past the listener.
    final code = links.uriLinkStream
        .where(
          (uri) =>
              uri.scheme == 'waxdeck' &&
              uri.host == 'auth' &&
              uri.queryParameters['code'] != null,
        )
        .map((uri) => uri.queryParameters['code']!)
        .first
        .timeout(timeout);
    await urlOpener.open(
      startUrlFor(provider, mode: 'app', challenge: deriveChallenge(verifier)),
    );
    return repository.oidcExchange(
      code: await code,
      verifier: verifier,
      deviceName: deviceName,
    );
  }

  /// Loopback mode (desktop): bind a localhost listener, open the browser,
  /// and exchange the code the redirect delivers.
  Future<LoginResult> loginWithLoopback(
    OidcProvider provider, {
    String? deviceName,
    Duration timeout = defaultTimeout,
  }) async {
    final bind = bindLoopbackReceiver;
    if (bind == null) {
      throw StateError('loopback login is not available on this platform');
    }
    final receiver = await bind();
    try {
      final verifier = newVerifier();
      await urlOpener.open(
        startUrlFor(
          provider,
          mode: 'loopback',
          challenge: deriveChallenge(verifier),
          port: receiver.port,
        ),
      );
      final code = await receiver.code.timeout(timeout);
      return await repository.oidcExchange(
        code: code,
        verifier: verifier,
        deviceName: deviceName,
      );
    } finally {
      await receiver.close();
    }
  }
}
