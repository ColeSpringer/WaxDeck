// A harness probe that runs the real desktop loopback sign-on flow
// against a running server and prints its progress as line protocol:
//
//   OPEN <url>      the browser navigation the flow requested
//   RESULT <json>   the completed login (username, token)
//   ERROR <text>    the failure, then a non-zero exit
//
// The spawning test plays the human: it drives a real browser through
// the OPEN url (identity provider login and redirects) while this
// process's genuine localhost listener waits for the loopback
// redirect and finishes the code exchange. Pure Dart on purpose so
// `dart run tool/oidc_loopback_probe.dart` works without a display.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:waxdeck/src/auth/loopback/loopback.dart';
import 'package:waxdeck/src/auth/oidc_flow.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

class StdoutUrlOpener implements UrlOpenerPort {
  @override
  Future<void> open(String url) async {
    stdout.writeln('OPEN $url');
    await stdout.flush();
  }
}

Future<void> main(List<String> args) async {
  final baseUrl = args.isNotEmpty ? args.first : 'http://localhost:4420';
  try {
    final client = WaxDeckClient(baseUrl: baseUrl);
    final providers = await client.oidcProviders();
    if (providers.isEmpty) {
      stdout.writeln('ERROR no OIDC providers configured');
      exit(2);
    }
    final flow = OidcLoginFlow(
      repository: client,
      urlOpener: StdoutUrlOpener(),
      bindLoopbackReceiver: bindLoopbackReceiver,
    );
    final result = await flow.loginWithLoopback(
      providers.first,
      deviceName: 'Loopback Probe',
      timeout: const Duration(seconds: 90),
    );
    stdout.writeln(
      'RESULT ${jsonEncode({'username': result.user.username, 'token': result.token})}',
    );
    await stdout.flush();
    exit(0);
  } catch (e) {
    stdout.writeln('ERROR $e');
    await stdout.flush();
    exit(1);
  }
}
