// The desktop counterpart of the playwright UI journey: the real app on a
// real desktop platform, with the real audio engine (mpv via media_kit),
// against the same cold stack. Run it with e2e/run-desktop.sh, which
// starts the stack, waits for the startup scan, and invokes
// `flutter test integration_test -d linux`.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

const _base = 'http://localhost:4420';

/// The shelf the card is taken from: "Recently added", which a freshly
/// scanned fixture library fills by construction.
const _shelf = 'recent';

Future<Map<String, dynamic>> _readJson(HttpClientResponse resp) async =>
    jsonDecode(await utf8.decodeStream(resp)) as Map<String, dynamic>;

/// Logs in over the API, separate from the session the app form will
/// establish, so server-side assertions have their own bearer token.
/// run-desktop.sh bootstraps the admin account before launching the app,
/// so a plain login suffices here.
Future<String> _apiToken(HttpClient http) async {
  final req = await http.postUrl(Uri.parse('$_base/api/v1/auth/login'));
  req.headers.contentType = ContentType.json;
  req.write(jsonEncode({'username': 'admin', 'password': 'wax-e2e-pass'}));
  final resp = await req.close();
  final body = await _readJson(resp);
  return body['token'] as String;
}

/// The corruption flavors `fixtures.Spec.Filename` spells into a
/// fixture's name, and so into the title a scan reads back off it:
/// `flac-garbage-1000ms-44100hz-2ch`.
///
/// Kept in step from the other side: `fixtures.AllCorruptions` is the
/// list, and `TestCorruptionMarkersReachTheDesktopJourney` fails if a
/// flavor added there is not excluded here.
///
/// The library under this journey is the whole codec matrix, robustness
/// flavors included, so a card being music is not yet a claim that it
/// can be played through. Garbage bytes decode to nothing, so the
/// stream endpoint answers 415 and the load dies on the engine's
/// deadline; a truncated encode streams, but it holds about half a
/// second of audio under the second it declares, which lands under the
/// half-track bar the server counts a play at. Neither can finish this
/// journey, and nothing about the shelf's order keeps them off the
/// front of it, so they are dropped here rather than left to be
/// tapped.
const _brokenByDesign = <String>['-garbage-', '-truncated-'];

/// Which of the "Recently added" pids are music this can play through,
/// by pid.
///
/// Read from the list the shelf itself reads rather than from search: a
/// pid that is in the library is not the same claim as a pid on the
/// screen, and that difference is what let this test rot silently once
/// home was rebuilt around shelves. Music specifically, because that is
/// the medium whose card plays - a book or an episode opens its own
/// screen instead.
Future<Set<String>> _playableShelfPids(HttpClient http, String token) async {
  final req = await http.getUrl(
    Uri.parse('$_base/api/v1/library/browse?list=recently-added&limit=24'),
  );
  req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  final resp = await req.close();
  final body = await _readJson(resp);
  final items = (body['items'] as List<dynamic>).cast<Map<String, dynamic>>();
  return <String>{
    for (final item in items)
      if (item['mediaType'] == 'music' &&
          !_brokenByDesign.any((item['title'] as String).contains))
        item['pid'] as String,
  };
}

/// Every semantics identifier currently in the tree.
Iterable<String> _renderedIdentifiers(WidgetTester tester) => tester
    .widgetList<Semantics>(find.byType(Semantics))
    .map((widget) => widget.properties.identifier)
    .whereType<String>();

/// A music card the shelf has actually built, by pid.
///
/// Taken from the rendered tree, never from a position in the list. Two
/// things make an index the wrong handle: the shelf is a lazy horizontal
/// `ListView`, so a card it counts as drawn can sit past the viewport and
/// never enter the tree at all, and the app re-reads the list after
/// sign-in, so a scan still settling can reorder it under us. Either way
/// the symptom would be a sixty-second timeout that reads like a
/// playback bug. Asking the screen what it built answers both.
Future<String> _builtMusicPid(
  WidgetTester tester,
  Set<String> playable, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  const prefix = 'shelf-$_shelf-';
  final deadline = DateTime.now().add(timeout);
  while (true) {
    for (final id in _renderedIdentifiers(tester)) {
      if (!id.startsWith(prefix)) continue;
      final pid = id.substring(prefix.length);
      if (playable.contains(pid)) return pid;
    }
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'timed out after $timeout waiting for a music card on the '
        '"$_shelf" shelf; the library has ${playable.length} playable '
        'music rows in its recently-added window',
      );
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
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
  await tester.runAsync(() async {
    token = await _apiToken(http);
  });

  // The harness stack is the server, spelled out: main() never runs
  // here, so nothing else seeds the address the provider chain builds
  // from, and the unseeded default would pin every route to /connect.
  await tester.pumpWidget(
    ProviderScope(
      overrides: [bootServerAddressProvider.overrideWithValue(_base)],
      child: const WaxDeckApp(),
    ),
  );
  await _pumpUntilFound(tester, find.byKey(const Key('login-username')));

  await tester.enterText(find.byKey(const Key('login-username')), 'admin');
  await tester.enterText(
    find.byKey(const Key('login-password')),
    'wax-e2e-pass',
  );
  await tester.tap(find.byKey(const Key('login-submit')));

  // Home draws its shelves; a music card plays what it is about rather
  // than opening a screen, which is what starts a session.
  //
  // The list is read here, after sign-in, so it is the same view the app
  // just built rather than one taken before the session existed.
  late final Set<String> playable;
  await tester.runAsync(() async {
    playable = await _playableShelfPids(http, token);
  });
  final pid = await _builtMusicPid(tester, playable);

  // Identifiers come from the generated registry, never typed here: the
  // one this test used to hand-write went stale the moment home was
  // rebuilt, and it took a suite that runs in no CI with it.
  final card = find.bySemanticsIdentifier(SemanticsIds.shelfCard(_shelf, pid));
  await _pumpUntilFound(tester, card);
  // Nothing is playing yet, and the marker below is only worth pumping
  // for if that is true: `_pumpUntilFound` answers before its first
  // frame when the finder already matches, so a handle that could be on
  // screen ahead of the tap would pass this step having proved nothing.
  final transport = find.bySemanticsIdentifier(SemanticsIds.deckPlay);
  expect(
    transport,
    findsNothing,
    reason: 'the deck bar had a transport before the card was tapped',
  );
  await tester.tap(card);
  // The deck bar's transport, not the player's: play lands in the dock
  // and the full player is a choice made from there, so the bar is what
  // proves the tap took, which is what the playwright driver settles on
  // after a play verb for the same reason. The transport rather than the
  // bar
  // itself, because the bar is also drawn for a restored-queue offer,
  // which is a face with no transport and nothing playing behind it.
  // Even this is a marker rather than the proof - it is drawn for a
  // session that failed to load too - and the accounting below is what
  // only real playback can satisfy.
  await _pumpUntilFound(tester, transport);

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
