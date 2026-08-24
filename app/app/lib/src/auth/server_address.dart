import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import 'credential_store.dart';

/// The port a bare host is tried on after https and http fail.
const kDefaultServerPort = 4420;

/// Normalizes what somebody typed into the bases to probe, best first.
///
/// A full URL is tried exactly as given (its scheme is a statement, not
/// a hint); a bare host tries https, then http, then http on the
/// default port when none was named. Path-prefix bases (a reverse proxy
/// mounting the server under /wax) are preserved - WebSocket and media
/// resolution already handle them. Credentials, whitespace, non-http
/// schemes, and query or fragment cruft answer no candidates at all.
List<String> serverAddressCandidates(String input) {
  final raw = input.trim();
  if (raw.isEmpty || RegExp(r'\s').hasMatch(raw)) return const [];
  final hasScheme = raw.contains('://');
  final lower = raw.toLowerCase();
  if (hasScheme &&
      !lower.startsWith('http://') &&
      !lower.startsWith('https://')) {
    return const [];
  }
  Uri? sane(String candidate) {
    final u = Uri.tryParse(candidate);
    if (u == null ||
        u.host.isEmpty ||
        u.userInfo.isNotEmpty ||
        u.hasQuery ||
        u.hasFragment) {
      return null;
    }
    return u;
  }

  // Trailing slashes go here so the stored base never mints "//api".
  String base(Uri u) => u.toString().replaceAll(RegExp(r'/+$'), '');

  if (hasScheme) {
    final u = sane(raw);
    return u == null ? const [] : [base(u)];
  }
  final https = sane('https://$raw');
  if (https == null) return const [];
  final http = https.replace(scheme: 'http');
  return [
    base(https),
    base(http),
    if (!https.hasPort) base(http.replace(port: kDefaultServerPort)),
  ];
}

/// Probes one candidate base for a WaxDeck server; a typed health
/// decode is the yes. Injected as a provider so widget tests answer
/// without a socket.
final serverProbeProvider = Provider<Future<ServerHealth> Function(String)>(
  (ref) => (base) async {
    // A throwaway transport per probe, closed either way: the ladder
    // tries several candidates and must not stack keep-alive pools.
    final dio = Dio();
    try {
      return await WaxDeckClient(baseUrl: base, dio: dio).health();
    } finally {
      dio.close(force: true);
    }
  },
);

/// The address `main()` seeds the provider chain with, before the first
/// request can fire. Precedence: the stored address, then the
/// compile-time dart-define, then nothing - which is what routes a
/// fresh native launch to the connect screen.
///
/// The one write here is the migration: a pre-address install with a
/// live session was implicitly using the compile-time base, so that
/// base becomes its stored address and the signed-in session never sees
/// the gate.
Future<String?> resolveBootServerAddress(CredentialStorePort store) async {
  if (kIsWeb) return null;
  // This await sits ahead of runApp, so it must resolve even against a
  // keyring that hangs instead of throwing (a locked keyring prompting
  // for a password it will never get). Timing out reads as "nothing
  // stored", which lands on the connect screen - an app that asks again
  // beats one that never draws a frame.
  try {
    return await _resolveBootServerAddress(
      store,
    ).timeout(const Duration(seconds: 5));
  } on TimeoutException {
    return compileTimeBaseOverride.isNotEmpty ? compileTimeBaseOverride : null;
  }
}

Future<String?> _resolveBootServerAddress(CredentialStorePort store) async {
  final stored = await store.readServerAddress();
  if (stored != null && stored.isNotEmpty) return stored;
  if (await store.readToken() != null) {
    final adopted = compileTimeBaseUrl;
    await store.writeServerAddress(adopted);
    return adopted;
  }
  if (compileTimeBaseOverride.isNotEmpty) return compileTimeBaseOverride;
  return null;
}
