// The desktop counterpart of the playwright UI journey: the real app on a
// real desktop platform, with the real audio engine (mpv via media_kit on
// Linux), against the same cold stack. Run it with e2e/run-desktop.sh,
// which starts the stack, waits for the startup scan, and invokes
// `flutter test integration_test -d linux`.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

const _base = 'http://localhost:4420';

Future<Map<String, dynamic>> _readJson(HttpClientResponse resp) async =>
    jsonDecode(await utf8.decodeStream(resp)) as Map<String, dynamic>;

/// Logs in over the API, separate from the session the app form will
/// establish, so server-side assertions have their own bearer token.
Future<String> _apiToken(HttpClient http) async {
  final req = await http.postUrl(Uri.parse('$_base/api/v1/auth/login'));
  req.headers.contentType = ContentType.json;
  req.write(jsonEncode({'username': 'admin', 'password': 'e2e'}));
  final resp = await req.close();
  final body = await _readJson(resp);
  return body['token'] as String;
}

Future<String> _alphaPid(HttpClient http, String token) async {
  final req = await http.getUrl(
    Uri.parse('$_base/api/v1/library/search?q=Alpha'),
  );
  req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  final resp = await req.close();
  final body = await _readJson(resp);
  final tracks = body['tracks'] as List<dynamic>;
  return (tracks.first as Map<String, dynamic>)['pid'] as String;
}

/// Pumps real frames until the finder matches. pumpAndSettle is unusable
/// here: network round trips and playback keep the tree animating.
Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out after $timeout waiting for $finder');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login, play a track, and the server accounts the play', (
    tester,
  ) async {
    // Not app.main(): that installs a permanent semantics handle for
    // browser automation, and flutter_test flags any handle still live at
    // test end. Build the same tree and hold a disposable handle instead.
    // The dispose must run inside the body: addTearDown callbacks fire
    // after the framework's end-of-test handle check.
    ensureAudioEngineInitialized();
    final semantics = tester.ensureSemantics();
    try {
      await _run(tester);
    } finally {
      semantics.dispose();
    }
  });
}

Future<void> _run(WidgetTester tester) async {
  final http = HttpClient();
  addTearDown(() => http.close(force: true));

  // run-desktop.sh waits for the startup scan before launching, so the
  // fixture album is queryable by the time this runs.
  late final String token;
  late final String pid;
  await tester.runAsync(() async {
    token = await _apiToken(http);
    pid = await _alphaPid(http, token);
  });

  await tester.pumpWidget(const ProviderScope(child: WaxDeckApp()));
  await _pumpUntilFound(tester, find.byKey(const Key('login-username')));

  await tester.enterText(find.byKey(const Key('login-username')), 'admin');
  await tester.enterText(find.byKey(const Key('login-password')), 'hunter2');
  await tester.tap(find.byKey(const Key('login-submit')));

  // The grid renders the scanned album; opening a card starts playback.
  await _pumpUntilFound(tester, find.bySemanticsIdentifier('item-$pid'));
  await tester.tap(find.bySemanticsIdentifier('item-$pid'));
  await _pumpUntilFound(tester, find.bySemanticsIdentifier('player-toggle'));

  // The fixture track lasts seconds; completing it makes the client
  // report its listen session. The server marking the item played closes
  // the loop: login, grid, stream fetch, engine decode and completion,
  // listen ingest, play accounting.
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  var played = false;
  while (!played && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() async {
      final req = await http.getUrl(
        Uri.parse('$_base/api/v1/items/$pid/play-state'),
      );
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final resp = await req.close();
      if (resp.statusCode != HttpStatus.ok) {
        await resp.drain<void>();
        return;
      }
      final state = await _readJson(resp);
      played = state['played'] == true && (state['playCount'] as int) >= 1;
    });
  }
  expect(
    played,
    isTrue,
    reason: 'completed playback should be accounted as a play',
  );
}
