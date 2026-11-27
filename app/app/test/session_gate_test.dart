import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_store.dart';
import 'package:waxdeck/src/auth/account_binder.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/owed_revoke.dart';
import 'package:waxdeck/src/home/home_shelves.dart';
import 'package:waxdeck/src/notifications/notifications_controller.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/player/play_state_controller.dart';
import 'package:waxdeck/src/player/playback_session.dart';
import 'package:waxdeck/src/podcasts/show_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck/src/settings/client_settings/browser_settings_store.dart';
import 'package:waxdeck/src/shell/lifecycle_banners.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/sync/catalog_cursor.dart';
import 'package:waxdeck/src/sync/page_resume/page_thaws.dart';
import 'package:waxdeck/src/sync/refresh_pacing.dart';
import 'package:waxdeck/src/sync/server_event_bus.dart';
import 'package:waxdeck/src/sync/session_doubt.dart';
import 'package:waxdeck/src/sync/session_gate.dart';
import 'package:waxdeck/src/sync/sync_binder.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

/// What a browser tab sends while the session it rides is in doubt: the
/// app's own client over one browser's cookie, which another tab can sign
/// another account in over.

/// The server through one browser's cookie: out of reach while [down], and
/// answering for whoever the cookie names now.
class _Cookie implements HttpClientAdapter {
  /// The account the cookie names: another tab signs in over it.
  String account = 'ann';

  /// Sign-ins made here, each a new session.
  var signIns = 0;

  String get session => signIns == 0 ? 'se-$account' : 'se-$account-$signIns';

  Map<String, Object?> get user => {
    'id': 'us-$account',
    'username': account,
    'roles': ['user'],
    'uploadEnabled': false,
  };

  bool down = false;

  /// Whether a write the cookie carries needs its session's CSRF token, as
  /// the server's does; off for a bare transport that holds no session.
  bool checksCsrf = true;

  /// Holds each session read until completed, while set.
  Completer<void>? sessionHeld;

  /// Awaited before a revoke by id is answered, while set: a step of the
  /// revoke's road.
  Future<void> Function()? onRevoke;

  /// Awaited before a sign-in is answered, while set: a step of the
  /// sign-in's road.
  Future<void> Function()? onSignIn;

  /// Awaited before a cookie's write is checked, while set: the server
  /// holding [request] (as `PUT /items/tr-1/play-state`) while the cookie
  /// changes hands.
  Future<void> Function(String request)? onWrite;

  /// Whether the cookie names nobody: a session read answers signed out.
  bool nobody = false;

  /// Awaited as each request arrives, while set: a step taken while
  /// [request] (as `GET /users/me/prefs`) is at the server.
  Future<void> Function(String request)? onRequest;

  /// Every request that reached the server, as `GET /library/items`.
  final sent = <String>[];

  /// Every request answered, as `GET /library/items as ann`.
  final answered = <String>[];

  /// Every request that reached the server with the CSRF token it carried,
  /// as `PUT /items/tr-1/play-state csrf-ann` (`-` for none).
  final presented = <String>[];

  /// Every write the server took, as `PUT /items/tr-1/play-state as ben`.
  final landed = <String>[];

  /// The routes the server takes a cookie's write on without its token.
  static const _public = {
    'POST /auth/login',
    'POST /auth/logout',
    'POST /auth/signup',
    'POST /auth/bootstrap',
    'POST /auth/oidc/exchange',
  };

  /// What reached the server from [from] on, but the session's own routes.
  List<String> forTheAccount([int from = 0]) => [
    for (final request in sent.skip(from))
      if (!request.contains(' /auth/')) request,
  ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path.replaceFirst('/api/v1', '');
    final request = '${options.method} $path';
    sent.add(request);
    final csrf = options.headers['X-CSRF-Token'];
    presented.add('$request ${csrf ?? '-'}');
    if (down) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'net::ERR_INTERNET_DISCONNECTED',
      );
    }
    await onRequest?.call(request);
    if (path == '/auth/session') await sessionHeld?.future;
    if (options.method == 'DELETE' && path.startsWith('/auth/sessions/')) {
      await onRevoke?.call();
    }
    if (request == 'POST /auth/login') await onSignIn?.call();
    final write = options.method != 'GET';
    if (write && !_public.contains(request)) await onWrite?.call(request);
    final account = this.account;
    // The server's own check: a write the cookie carries needs the token
    // of the session that cookie names.
    final refused =
        checksCsrf &&
        write &&
        !_public.contains(request) &&
        options.headers['Authorization'] == null &&
        csrf != 'csrf-$account';
    final (status, body) = switch ((options.method, path)) {
      _ when refused => (
        403,
        <String, Object?>{
          'code': 'forbidden',
          'message': 'missing or wrong CSRF token',
        },
      ),
      ('GET', '/auth/session') when nobody => (
        200,
        <String, Object?>{'authenticated': false},
      ),
      ('GET', '/auth/session') => (
        200,
        <String, Object?>{
          'authenticated': true,
          'user': user,
          'csrfToken': 'csrf-$account',
          'sessionId': session,
        },
      ),
      ('POST', '/auth/login') => (
        200,
        <String, Object?>{
          'user': user,
          'token': 'token-${++signIns}',
          'sessionId': session,
          'csrfToken': 'csrf-$account',
        },
      ),
      ('GET', '/auth/bootstrap') => (200, <String, Object?>{'required': false}),
      ('POST', '/auth/logout') => (200, <String, Object?>{}),
      ('DELETE', final revoke) when revoke.startsWith('/auth/sessions/') => (
        200,
        <String, Object?>{},
      ),
      ('GET', '/library/browse' || '/library/items') => (
        200,
        <String, Object?>{'items': <Object>[]},
      ),
      ('PUT', final star) when star.endsWith('/star') => (
        200,
        <String, Object?>{
          'pid': 'tr-1',
          'positionMs': 0,
          'played': false,
          'finished': false,
          'playCount': 0,
          'starred': true,
        },
      ),
      ('GET', '/items/tr-1/play-state') => (
        200,
        <String, Object?>{
          'pid': 'tr-1',
          'positionMs': 0,
          'played': false,
          'finished': false,
          'playCount': 0,
          'starred': false,
        },
      ),
      ('PUT', final checkpoint) when checkpoint.endsWith('/play-state') => (
        200,
        <String, Object?>{},
      ),
      ('GET', '/items/tr-1/play-info') => (
        200,
        <String, Object?>{
          'pid': 'tr-1',
          'url': '/media/tr-1',
          'mimeType': 'audio/flac',
          'durationMs': 214000,
          'seekable': true,
          'expiresAt': '2099-01-01T00:00:00Z',
        },
      ),
      ('POST', '/listens') => (
        200,
        <String, Object?>{'accepted': 1, 'duplicates': 0},
      ),
      ('GET', '/podcasts/pc-1') => (
        200,
        <String, Object?>{
          'show': {'pid': 'pc-1', 'title': 'The Show', 'sourceType': 'rss'},
          'subscribed': true,
        },
      ),
      ('GET', '/podcasts/pc-1/episodes') => (
        200,
        <String, Object?>{
          'items': [
            for (final n in [1, 2, 3])
              {
                'pid': 'tr-e$n',
                'mediaType': 'podcast',
                'title': 'Episode $n',
                'durationMs': 60000,
                'showPid': 'pc-1',
                'downloaded': false,
                'publishedAt': '2026-0$n-01T00:00:00Z',
              },
          ],
        },
      ),
      // Ben has nothing waiting under the show, so his own inbox settles
      // nothing there.
      ('GET', '/users/me/notifications') when account != 'ann' => (
        200,
        <String, Object?>{'notifications': <Object>[], 'unreadCount': 0},
      ),
      ('GET', '/users/me/notifications') => (
        200,
        <String, Object?>{
          'notifications': [
            {
              'id': 'nt-1',
              'event': 'feed-disabled',
              'title': 'A feed stopped',
              'body': 'The Show stopped answering.',
              'targetPid': 'pc-1',
              'createdAt': '2026-01-01T00:00:00Z',
              'updatedAt': '2026-01-01T00:00:00Z',
            },
          ],
          // More unread than the page holds: a visit reaches past it.
          'unreadCount': 3,
        },
      ),
      ('POST', '/users/me/notifications/read') => (200, <String, Object?>{}),
      ('GET' || 'PUT', '/users/me/prefs') => (200, <String, Object?>{}),
      ('GET', '/radio/stations') => (
        200,
        <String, Object?>{'stations': <Object>[]},
      ),
      ('POST', '/books/bk-1/bookmarks') => (
        201,
        <String, Object?>{
          'id': 'bm-1',
          'positionMs': 1000,
          'createdAt': '2026-01-01T00:00:00Z',
        },
      ),
      _ => (
        404,
        <String, Object?>{'code': 'not-found', 'message': 'not found'},
      ),
    };
    answered.add('$request as $account');
    if (write && status < 300) landed.add('$request as $account');
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A page's storage, in memory.
class _PageStorage implements BrowserStorage {
  final values = <String, String>{};

  @override
  String? getItem(String key) => values[key];

  @override
  void setItem(String key, String value) => values[key] = value;

  @override
  void removeItem(String key) => values.remove(key);
}

Future<void> _until(WidgetTester tester, bool Function() settled) async {
  for (var i = 0; i < 300 && !settled(); i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(settled(), isTrue, reason: 'did not settle');
}

typedef _Tab = (
  ProviderContainer container,
  FakeLink link,
  StreamController<void> online,
  ProviderSubscription<void> binder,
);

/// A browser tab signed in as Ann over [server]'s cookie, its socket up;
/// [resumes] says when the browser thaws it.
Future<_Tab> _tab(
  WidgetTester tester,
  _Cookie server, {
  Stream<void> resumes = const Stream<void>.empty(),
}) async {
  final link = FakeLink();
  final online = StreamController<void>.broadcast();
  addTearDown(online.close);
  final container = appContainer(
    server: server,
    observers: [FirstBuildObserver()],
    extra: [
      liveListenerProvider.overrideWithValue(true),
      liveChannelFactoryProvider.overrideWithValue(link.factory),
      catalogCursorStorageProvider.overrideWithValue(null),
      networkReturnsProvider.overrideWithValue(online.stream),
      pageResumesProvider.overrideWithValue(resumes),
    ],
  );
  container.listen(authControllerProvider, (_, _) {});
  await _until(tester, () => container.read(authControllerProvider).hasValue);
  expect(container.read(authControllerProvider).value?.user?.id, 'us-ann');
  final binder = container.listen(syncBinderProvider, (_, _) {});
  await tester.pump(const Duration(seconds: 6));
  expect(container.read(liveLinkProvider), isTrue);
  return (container, link, online, binder);
}

/// The API's own client with [gate] in its transport, over a server that
/// answers through one cookie; what reached it is [_Cookie.sent].
(WaxDeckClient, List<String>) _gated(SessionGate gate) {
  final server = _Cookie()..checksCsrf = false;
  final dio = Dio()
    ..interceptors.add(SessionGateInterceptor(gate))
    ..httpClientAdapter = server;
  return (WaxDeckClient(baseUrl: 'http://server.test', dio: dio), server.sent);
}

/// Ends the tab on the fake clock, which fails on a timer left pending.
Future<void> _close(WidgetTester tester, ProviderContainer container) async {
  container.dispose();
  await tester.pump(const Duration(minutes: 1));
}

typedef _Playing = (
  ProviderContainer container,
  FakeLink link,
  FakeEngine engine,
);

/// A tab signed in as Ann over [server]'s cookie, its socket up, playing
/// tr-1 long enough to have a listen to report. The signed-in scope is
/// stood in for as the router keeps it: the binders and the screens a
/// next session waits on, taken down a frame after no account shows and
/// put up again once one does.
Future<_Playing> _playing(WidgetTester tester, _Cookie server) async {
  final link = FakeLink();
  final engine = FakeEngine();
  final container = appContainer(
    server: server,
    engine: engine,
    observers: [FirstBuildObserver()],
    extra: [
      liveListenerProvider.overrideWithValue(true),
      liveChannelFactoryProvider.overrideWithValue(link.factory),
      catalogCursorStorageProvider.overrideWithValue(null),
      networkReturnsProvider.overrideWithValue(const Stream<void>.empty()),
      pageResumesProvider.overrideWithValue(const Stream<void>.empty()),
    ],
  );
  container.listen(authControllerProvider, (_, _) {});
  await _until(tester, () => container.read(authControllerProvider).hasValue);
  expect(container.read(authControllerProvider).value?.user?.id, 'us-ann');

  List<ProviderSubscription<Object?>>? scope;
  void mount() => scope = [
    container.listen(signedInScreensProvider, (_, _) {}),
    container.listen(syncBinderProvider, (_, _) {}),
    container.listen(accountBinderProvider, (_, _) {}),
  ];
  mount();
  container.listen(authControllerProvider, (_, next) {
    final shows = next.value?.authenticated == true;
    Timer.run(() {
      final up = scope;
      if (!shows && up != null) {
        for (final subscription in up) {
          subscription.close();
        }
        scope = null;
      } else if (shows && up == null) {
        mount();
      }
    });
  });
  await tester.pump(const Duration(seconds: 6));
  expect(container.read(liveLinkProvider), isTrue);

  container.read(nowPlayingProvider.notifier).enqueue([testItem('tr-1')]);
  await _until(tester, () => engine.playing);
  for (var i = 0; i < 5; i++) {
    engine.advance(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
  }
  return (container, link, engine);
}

/// What the leaving account's playback sends as it goes: its last
/// checkpoint and its listen report.
bool _annsWrite(String request) =>
    request.startsWith('PUT /items/tr-1/play-state') ||
    request.startsWith('POST /listens');

/// Nothing of Ann's playback landed in Ben's account, and none of it went
/// with Ben's token; Ben's own write, made once he shows, goes with his.
Future<void> _nothingOfAnnsAsBen(
  WidgetTester tester,
  ProviderContainer container,
  _Cookie server,
) async {
  final presented = server.presented.where(_annsWrite).toList();
  expect(
    server.landed.where((w) => _annsWrite(w) && w.endsWith(' as ben')),
    isEmpty,
    reason: 'landed as Ben; presented: $presented',
  );
  expect(
    presented.where((p) => p.endsWith(' csrf-ben')),
    isEmpty,
    reason: 'sent with the next account\'s token',
  );
  var done = false;
  container
      .read(repositoryProvider)
      .setStar('tr-1', true)
      .then((_) => done = true)
      .ignore();
  await _until(tester, () => done);
  expect(server.presented, contains('PUT /items/tr-1/star csrf-ben'));
  expect(server.landed, contains('PUT /items/tr-1/star as ben'));
}

/// What [call] ended as: `answered`, or the API error's code.
Future<String> _outcome(Future<Object?> call) => call.then<String>(
  (_) => 'answered',
  onError: (Object e) => e is WaxDeckApiException ? e.code : '$e',
);

/// A tab signed in as Ann over [server]'s cookie, with nothing bound.
Future<ProviderContainer> _signedIn(
  WidgetTester tester,
  _Cookie server, {
  ArtworkStore? artwork,
}) async {
  final container = appContainer(server: server, artwork: artwork);
  container.listen(authControllerProvider, (_, _) {});
  await _until(tester, () => container.read(authControllerProvider).hasValue);
  return container;
}

/// Another tab signs Ben in over the cookie, and this one reads its
/// session, as the account marker has it do: it swaps to Ben.
Future<void> _benSignsInElsewhere(
  WidgetTester tester,
  ProviderContainer container,
  _Cookie server,
) async {
  server.account = 'ben';
  container.read(authControllerProvider.notifier).refreshSession().ignore();
  await _until(
    tester,
    () => container.read(authControllerProvider).value?.user?.id == 'us-ben',
  );
}

/// An artwork store whose forgetting, a step of every road out of an
/// account, runs [onForget] first.
class _Forgetting extends FakeArtworkStore {
  Future<void> Function()? onForget;

  @override
  Future<void> forgetEverything() async {
    await onForget?.call();
    return super.forgetEverything();
  }
}

void main() {
  group('over the app\'s own client, a tab that was away', () {
    for (final handedOver in [false, true]) {
      testWidgets(
        handedOver
            ? 'sends nothing it made before the session answered, once that '
                  'answer is another account: a retry, a first read, a tap\'s '
                  'write and a timed write'
            : 'sends what it made before the session answered once the '
                  'account stands: a retry, a first read, a tap\'s write and a '
                  'timed write',
        (tester) async {
          final server = _Cookie();
          final (container, link, online, _) = await _tab(tester, server);

          // Away: the network goes, and the socket with it.
          server.down = true;
          link.reachable = false;
          link.attempts.last.drop(1006);
          // A screen up meanwhile reads, fails, and is retried.
          container.listen(recentlyAddedShelfProvider, (_, _) {});
          await tester.pump(const Duration(seconds: 2));
          // Another tab signs Ben in over the cookie, or nobody does.
          if (handedOver) server.account = 'ben';

          // Back, and the browser says so: the socket comes up at once and
          // its session read is out.
          final held = server.sessionHeld = Completer<void>();
          server.down = false;
          link.reachable = true;
          final back = server.sent.length;
          final answeredBack = server.answered.length;
          online.add(null);
          await _until(tester, () => server.sent.length > back);
          expect(server.sent.sublist(back), ['GET /auth/session']);

          // Made while that read is out.
          final repo = container.read(repositoryProvider);
          final outcomes = <String, String>{};
          void track(String what, Future<Object?> call) => call.then(
            (_) => outcomes[what] = 'answered',
            onError: (Object error) => outcomes[what] =
                error is WaxDeckApiException ? error.code : '$error',
          );
          track('first read', repo.listItems());
          track('tap', repo.setStar('tr-1', true));
          Timer(
            const Duration(seconds: 1),
            () => track('timed write', repo.putPlayState('tr-1', 5000)),
          );
          // Long enough for the shelf's retry to come due.
          await tester.pump(const Duration(seconds: 8));
          expect(
            server.forTheAccount(back),
            isEmpty,
            reason: 'sent before the session answered',
          );

          held.complete();
          server.sessionHeld = null;
          await tester.pump(const Duration(seconds: 1));
          if (handedOver) {
            expect(
              container.read(authControllerProvider).value?.user?.id,
              'us-ben',
            );
            await tester.pump(const Duration(minutes: 1));
            expect(
              server.forTheAccount(back),
              isEmpty,
              reason: 'sent for an account that left',
            );
            expect(outcomes, {
              'first read': 'transport',
              'tap': 'transport',
              'timed write': 'transport',
            });
          } else {
            final answered = server.answered.sublist(answeredBack);
            expect(answered.first, 'GET /auth/session as ann');
            expect(
              answered,
              containsAll([
                'GET /library/browse as ann',
                'GET /library/items as ann',
                'PUT /items/tr-1/star as ann',
                'PUT /items/tr-1/play-state as ann',
              ]),
            );
            expect(outcomes, {
              'first read': 'answered',
              'tap': 'answered',
              'timed write': 'answered',
            });
          }
          await _close(tester, container);
        },
      );
    }
  });

  group('over the app\'s own client, a tab in doubt', () {
    testWidgets('with the server out of reach, a request fails at once as '
        'the transport, unsent, and the next asks again; back in reach, one '
        'goes once the account stands', (tester) async {
      final server = _Cookie();
      final (container, link, _, _) = await _tab(tester, server);
      final repo = container.read(repositoryProvider);

      server.down = true;
      link.reachable = false;
      link.attempts.last.drop(1006);
      final away = server.sent.length;
      Object? failed;
      repo.listItems().catchError((Object error) {
        failed = error;
        return const ItemPage(items: []);
      }).ignore();
      await _until(tester, () => failed != null);
      expect(
        failed,
        isA<WaxDeckApiException>().having((e) => e.code, 'code', 'transport'),
      );
      expect(server.sent.sublist(away), ['GET /auth/session']);

      failed = null;
      repo.listItems().catchError((Object error) {
        failed = error;
        return const ItemPage(items: []);
      }).ignore();
      await _until(tester, () => failed != null);
      expect(failed, isA<WaxDeckApiException>());
      expect(server.sent.sublist(away), [
        'GET /auth/session',
        'GET /auth/session',
      ]);

      server.down = false;
      final back = server.sent.length;
      var answered = false;
      repo.listItems().then((_) => answered = true).ignore();
      await _until(tester, () => answered);
      expect(server.sent.sublist(back), [
        'GET /auth/session',
        'GET /library/items',
      ]);
      await _close(tester, container);
    });

    testWidgets('a revoke on its way that the session read joins: a request '
        'it waits on fails at once, unsent, and one made outside it waits '
        'and goes once the account stands', (tester) async {
      final server = _Cookie();
      final container = appContainer(
        server: server,
        extra: [
          owedRevokeProvider.overrideWithValue(OwedRevoke(_PageStorage())),
        ],
      );
      container.listen(authControllerProvider, (_, _) {});
      await _until(
        tester,
        () => container.read(authControllerProvider).hasValue,
      );
      expect(container.read(authControllerProvider).value?.user?.id, 'us-ann');
      final auth = container.read(authControllerProvider.notifier);
      final repo = container.read(repositoryProvider);
      final doubt = SessionDoubt(read: auth.refreshSession);
      addTearDown(doubt.dispose);
      container.read(sessionGateProvider).bind(doubt.pass);

      // An earlier session of this browser's is owed a revoke, and a
      // session read outside the doubt sends it.
      container.read(owedRevokeProvider).owe('se-old');
      final outcomes = <String, String>{};
      void track(String what, Future<Object?> call) => call.then(
        (_) => outcomes[what] = 'answered',
        onError: (Object e) =>
            outcomes[what] = e is WaxDeckApiException ? e.code : '$e',
      );
      // A step of the revoke's road that asks the server.
      server.onRevoke = () async {
        server.onRevoke = null;
        await repo.listItems().then(
          (_) => outcomes['revoke\'s own'] = 'answered',
          onError: (Object e) => outcomes['revoke\'s own'] =
              e is WaxDeckApiException ? e.code : '$e',
        );
      };
      final held = server.sessionHeld = Completer<void>();
      final from = server.sent.length;
      track('refresh', auth.refreshSession());
      await _until(tester, () => server.sent.length > from);
      expect(server.sent.sublist(from), ['GET /auth/session']);

      // In doubt, and a request made outside any session work: its read
      // joins the revoke on its way.
      doubt.suspect();
      track('outside', repo.setStar('tr-1', true));
      await tester.pump(const Duration(seconds: 1));
      expect(server.forTheAccount(from), isEmpty);

      held.complete();
      server.sessionHeld = null;
      await _until(tester, () => outcomes.containsKey('outside'));
      expect(outcomes, {
        'revoke\'s own': 'transport',
        'refresh': 'answered',
        'outside': 'answered',
      });
      expect(server.forTheAccount(from), ['PUT /items/tr-1/star']);
      expect(server.sent, contains('DELETE /auth/sessions/se-old'));
      await _close(tester, container);
    });

    testWidgets('after an answer that the account left, the binder goes with '
        'the signed-in screens, and the next account\'s first request goes '
        'out', (tester) async {
      final server = _Cookie();
      final (container, link, _, binder) = await _tab(tester, server);
      final repo = container.read(repositoryProvider);

      // Ben signs in over the cookie; this tab's socket drops and its
      // return asks whose the session is.
      server.account = 'ben';
      link.attempts.last.drop(1006);
      await _until(
        tester,
        () =>
            container.read(authControllerProvider).value?.user?.id == 'us-ben',
      );
      Object? refused;
      repo.listItems().catchError((Object error) {
        refused = error;
        return const ItemPage(items: []);
      }).ignore();
      await _until(tester, () => refused != null);
      expect(
        refused,
        isA<WaxDeckApiException>().having((e) => e.code, 'code', 'transport'),
        reason: 'the old binder still holds the gate',
      );

      // The signed-in scope goes, and Ben's comes up with its own binder.
      binder.close();
      await tester.pump(const Duration(seconds: 1));
      expect(container.exists(syncBinderProvider), isFalse);
      expect(container.read(sessionGateProvider).bound, isFalse);
      container.listen(syncBinderProvider, (_, _) {});
      await tester.pump(const Duration(seconds: 1));
      expect(container.read(sessionGateProvider).bound, isTrue);

      final first = server.sent.length;
      final answered = server.answered.length;
      var done = false;
      // Ben's screens read Ben's repository.
      container
          .read(repositoryProvider)
          .listItems()
          .then((_) => done = true)
          .ignore();
      await _until(tester, () => done);
      expect(server.forTheAccount(first), ['GET /library/items']);
      expect(server.sent.sublist(first), ['GET /library/items']);
      expect(server.answered.sublist(answered), ['GET /library/items as ben']);
      await _close(tester, container);
    });

    testWidgets('a binder rebuilt while the session is in doubt starts in '
        'doubt for that same session: its first request asks', (tester) async {
      final server = _Cookie();
      final (container, link, _, _) = await _tab(tester, server);
      final repo = container.read(repositoryProvider);

      // The socket drops and its reconnect fails; the read that asks is
      // still out when the binder rebuilds.
      final held = server.sessionHeld = Completer<void>();
      link.reachable = false;
      link.attempts.last.drop(1006);
      await tester.pump(const Duration(seconds: 2));
      link.reachable = true;
      final rebuilt = server.sent.length;
      container.invalidate(syncBinderProvider);
      await tester.pump(const Duration(seconds: 1));
      expect(container.read(liveLinkProvider), isTrue);

      var done = false;
      repo.listItems().then((_) => done = true).ignore();
      await tester.pump(const Duration(seconds: 1));
      expect(server.forTheAccount(rebuilt), isEmpty);

      final answered = server.answered.length;
      held.complete();
      server.sessionHeld = null;
      await _until(tester, () => done);
      final after = server.answered.sublist(answered);
      expect(
        after.indexOf('GET /auth/session as ann'),
        lessThan(after.indexOf('GET /library/items as ann')),
      );
      expect(after.indexOf('GET /auth/session as ann'), isNonNegative);
      await _close(tester, container);
    });

    testWidgets('a binder started after a fresh sign-in in this tab starts '
        'clean: the new session carries no doubt', (tester) async {
      final server = _Cookie();
      final (container, link, _, binder) = await _tab(tester, server);

      // The tab signs out with its session in doubt: the socket dropped
      // and nothing has answered.
      server.down = true;
      link.reachable = false;
      link.attempts.last.drop(1006);
      await tester.pump(const Duration(milliseconds: 100));
      var out = false;
      container
          .read(authControllerProvider.notifier)
          .signOutLocally()
          .then((_) => out = true)
          .ignore();
      await _until(tester, () => out);
      binder.close();
      await tester.pump(const Duration(seconds: 1));
      expect(container.exists(syncBinderProvider), isFalse);

      // Ann signs in again here: a new session, and its own binder.
      server.down = false;
      link.reachable = true;
      var signedIn = false;
      container
          .read(authControllerProvider.notifier)
          .login(username: 'ann', password: 'pw')
          .then((ok) => signedIn = ok)
          .ignore();
      await _until(tester, () => signedIn);
      container.listen(syncBinderProvider, (_, _) {});
      await tester.pump(const Duration(seconds: 6));
      expect(
        container.read(authControllerProvider).value?.sessionId,
        'se-ann-1',
      );

      final first = server.sent.length;
      var done = false;
      container
          .read(repositoryProvider)
          .listItems()
          .then((_) => done = true)
          .ignore();
      await _until(tester, () => done);
      expect(server.sent.sublist(first), ['GET /library/items']);
      await _close(tester, container);
    });

    testWidgets('the binder binds its doubt in a browser and lets go as it '
        'goes; with no live listener, nothing is bound', (tester) async {
      final server = _Cookie();
      final (container, _, _, binder) = await _tab(tester, server);
      final gate = container.read(sessionGateProvider);
      expect(gate.bound, isTrue);

      // The signed-in screens go: nothing watches the binder.
      binder.close();
      await tester.pump(const Duration(seconds: 1));
      expect(container.exists(syncBinderProvider), isFalse);
      expect(gate.bound, isFalse);
      await _close(tester, container);

      final native = appContainer(
        server: _Cookie(),
        extra: [liveListenerProvider.overrideWithValue(false)],
      );
      native.listen(authControllerProvider, (_, _) {});
      await _until(tester, () => native.read(authControllerProvider).hasValue);
      final watched = native.listen(syncBinderProvider, (_, _) {});
      await tester.pump();
      expect(native.read(sessionGateProvider).bound, isFalse);
      watched.close();
      await _close(tester, native);
    });

    testWidgets('a walk of the events that read another account\'s stream puts '
        'the session in doubt: a request waits for the read, which finds that '
        'account, and the tab swaps to it', (tester) async {
      final server = _Cookie();
      final (container, _, _, _) = await _tab(tester, server);
      final anns = container.read(repositoryProvider);

      // Another tab signs Ben in over the cookie; nothing dropped, so
      // nothing here is in doubt until the walk reads Ben's page.
      server.account = 'ben';
      final held = server.sessionHeld = Completer<void>();
      container.read(serverEventBusProvider).heardAnotherAccount();
      await tester.pump(const Duration(seconds: 1));
      final from = server.sent.length;
      final outcome = _outcome(anns.setStar('tr-1', true));
      await tester.pump(const Duration(seconds: 1));
      expect(server.forTheAccount(from), isEmpty);

      held.complete();
      server.sessionHeld = null;
      await _until(
        tester,
        () =>
            container.read(authControllerProvider).value?.user?.id == 'us-ben',
      );
      expect(await outcome, 'transport');
      expect(server.landed.where((w) => w.endsWith(' as ben')), isEmpty);
      await _close(tester, container);
    });
  });

  group('over the app\'s own client, a tab the browser froze', () {
    // Thawed, it may send before it handles its socket's close: the
    // socket here never says it dropped.
    for (final handedOver in [false, true]) {
      testWidgets(
        handedOver
            ? 'asks the session before its first request on the thaw, and '
                  'sends nothing once the answer is another account'
            : 'asks the session before its first request on the thaw, and '
                  'sends it once the account stands',
        (tester) async {
          final server = _Cookie();
          final resumes = StreamController<void>.broadcast();
          addTearDown(resumes.close);
          final (container, _, _, _) = await _tab(
            tester,
            server,
            resumes: resumes.stream,
          );
          if (handedOver) server.account = 'ben';

          final held = server.sessionHeld = Completer<void>();
          final thawed = server.sent.length;
          final answeredThawed = server.answered.length;
          resumes.add(null);
          await tester.pump();
          // The thaw itself reads nothing: only a request asks.
          expect(server.sent.sublist(thawed), isEmpty);

          final repo = container.read(repositoryProvider);
          final outcomes = <String, String>{};
          void track(String what, Future<Object?> call) => call.then(
            (_) => outcomes[what] = 'answered',
            onError: (Object error) => outcomes[what] =
                error is WaxDeckApiException ? error.code : '$error',
          );
          track('read', repo.listItems());
          track('tap', repo.setStar('tr-1', true));
          await tester.pump(const Duration(seconds: 2));
          expect(server.sent.sublist(thawed), ['GET /auth/session']);

          held.complete();
          server.sessionHeld = null;
          await tester.pump(const Duration(seconds: 1));
          if (handedOver) {
            expect(
              container.read(authControllerProvider).value?.user?.id,
              'us-ben',
            );
            await tester.pump(const Duration(minutes: 1));
            expect(
              server.forTheAccount(thawed),
              isEmpty,
              reason: 'sent for an account that left',
            );
            expect(outcomes, {'read': 'transport', 'tap': 'transport'});
          } else {
            final answered = server.answered.sublist(answeredThawed);
            expect(answered.first, 'GET /auth/session as ann');
            expect(
              answered,
              containsAll([
                'GET /library/items as ann',
                'PUT /items/tr-1/star as ann',
              ]),
            );
            expect(outcomes, {'read': 'answered', 'tap': 'answered'});
            // Answered: the next goes at once.
            final next = server.sent.length;
            var nextAnswered = false;
            repo.listItems().then((_) => nextAnswered = true).ignore();
            await _until(tester, () => nextAnswered);
            expect(server.sent.sublist(next), ['GET /library/items']);
          }
          await _close(tester, container);
        },
      );
    }

    testWidgets('a tab hidden and shown again (the app lifecycle\'s hidden '
        'then resumed, which a browser\'s visibilitychange drives) asks '
        'nothing: it kept running and heard its socket', (tester) async {
      final server = _Cookie();
      final (container, _, _, _) = await _tab(tester, server);
      // What a browser's `visibilitychange` becomes in the app.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump(const Duration(seconds: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      final shown = server.sent.length;
      var answered = false;
      container
          .read(repositoryProvider)
          .listItems()
          .then((_) => answered = true)
          .ignore();
      await _until(tester, () => answered);
      expect(server.sent.sublist(shown), ['GET /library/items']);
      await _close(tester, container);
    });

    test('a thaw is a resume, or a page shown again from the back/forward '
        'cache; a page shown fresh is none', () async {
      final resumes = StreamController<void>();
      final shows = StreamController<bool>();
      final thaws = <String>[];
      var at = 'start';
      final sub = pageThaws(
        resumes: resumes.stream,
        shows: shows.stream,
      ).listen((_) => thaws.add(at));

      at = 'resume';
      resumes.add(null);
      await pumpEventQueue();
      at = 'shown fresh';
      shows.add(false);
      await pumpEventQueue();
      at = 'restored';
      shows.add(true);
      await pumpEventQueue();

      expect(thaws, ['resume', 'restored']);
      await sub.cancel();
      expect(resumes.hasListener, isFalse);
      expect(shows.hasListener, isFalse);
    });

    test('heard again by the next binder: a new account\'s binder listens to '
        'the same stream after the last let go', () async {
      final resumes = StreamController<void>.broadcast();
      final shows = StreamController<bool>.broadcast();
      final thaws = pageThaws(resumes: resumes.stream, shows: shows.stream);
      var heard = 0;

      await thaws.listen((_) => heard++).cancel();
      final next = thaws.listen((_) => heard++);
      resumes.add(null);
      shows.add(true);
      await pumpEventQueue();

      expect(heard, 2);
      await next.cancel();
      await resumes.close();
      await shows.close();
    });
  });

  group('the session gate', () {
    test('with nothing bound, a request goes at once', () async {
      final (client, sent) = _gated(SessionGate());
      await client.listItems();
      expect(sent, ['GET /library/items']);
    });

    test('a request waits on what is bound: let go, it is sent; refused, it '
        'fails as the transport and nothing is sent', () async {
      final gate = SessionGate();
      final (client, sent) = _gated(gate);
      final answer = Completer<bool>();
      gate.bind(() => answer.future);

      var done = false;
      final going = client.listItems().whenComplete(() => done = true);
      await pumpEventQueue();
      expect(sent, isEmpty);
      expect(done, isFalse);
      answer.complete(true);
      await going;
      expect(sent, ['GET /library/items']);

      gate.bind(() async => false);
      await expectLater(
        client.listItems(),
        throwsA(
          isA<WaxDeckApiException>().having((e) => e.code, 'code', 'transport'),
        ),
      );
      expect(sent, ['GET /library/items']);
    });

    test('the session\'s own routes go without asking, and only those: the '
        'list of its sessions, a rename and any other route under /auth/ '
        'ask', () async {
      expect(SessionGateInterceptor.sessionRoutes, {
        'GET /auth/session',
        'POST /auth/login',
        'POST /auth/logout',
        'POST /auth/signup',
        'POST /auth/refresh',
        'GET /auth/bootstrap',
        'POST /auth/bootstrap',
        'GET /auth/oidc/providers',
        'GET /auth/oidc/start',
        'GET /auth/oidc/callback',
        'POST /auth/oidc/exchange',
      });
      final gate = SessionGate();
      final server = _Cookie();
      final dio =
          Dio(
              BaseOptions(
                baseUrl: 'http://server.test/api/v1',
                validateStatus: (_) => true,
              ),
            )
            ..interceptors.add(SessionGateInterceptor(gate))
            ..httpClientAdapter = server;
      var asked = 0;
      gate.bind(() async {
        asked++;
        return false;
      });

      for (final route in SessionGateInterceptor.sessionRoutes) {
        final [method, path] = route.split(' ');
        await dio.request<Object?>(path, options: Options(method: method));
      }
      expect(asked, 0);
      expect(server.sent, SessionGateInterceptor.sessionRoutes.toList());

      final own = server.sent.length;
      for (final (method, path) in const [
        ('GET', '/auth/sessions'),
        ('PATCH', '/auth/sessions/se-1'),
        ('DELETE', '/auth/sessions/se-1'),
        ('GET', '/auth/tokens'),
        ('POST', '/auth/session'),
        ('DELETE', '/auth/sessions/se-1/devices'),
      ]) {
        await expectLater(
          dio.request<Object?>(path, options: Options(method: method)),
          throwsA(isA<DioException>()),
          reason: '$method $path',
        );
      }
      expect(asked, 6);
      expect(server.sent, hasLength(own), reason: 'refused, unsent');
    });

    test('a revoke from the devices screen waits while the session is in '
        'doubt and goes once it stands; the revoke a sign-out owes goes at '
        'once, from the session work that sends it too', () async {
      final gate = SessionGate();
      final (client, sent) = _gated(gate);
      final released = Completer<void>();
      final doubt = SessionDoubt(
        read: () async {
          await released.future;
          return SessionRecheck.stands;
        },
      )..suspect();
      addTearDown(doubt.dispose);
      gate.bind(doubt.pass);

      var devicesDone = false;
      final devices = client
          .revokeSession('se-ann-2')
          .whenComplete(() => devicesDone = true);
      await client.revokeOwedSession('se-old');
      await asSessionWork(() => client.revokeOwedSession('se-older'));
      await pumpEventQueue();
      expect(sent, [
        'DELETE /auth/sessions/se-old',
        'DELETE /auth/sessions/se-older',
      ]);
      expect(devicesDone, isFalse, reason: 'held until the read answers');

      released.complete();
      await devices;
      expect(sent, [
        'DELETE /auth/sessions/se-old',
        'DELETE /auth/sessions/se-older',
        'DELETE /auth/sessions/se-ann-2',
      ]);
    });

    test('a request the session read itself waits on fails at once, '
        'unsent, rather than wait on that read; one made outside it waits '
        'and goes once the account stands', () async {
      final gate = SessionGate();
      final (client, sent) = _gated(gate);
      final inside = Completer<String>();
      final released = Completer<void>();
      final doubt = SessionDoubt(
        read: () async {
          // A step of the read's own that asks the server.
          inside.complete(
            await client.listItems().then(
              (_) => 'answered',
              onError: (Object e) => e is WaxDeckApiException ? e.code : '$e',
            ),
          );
          await released.future;
          return SessionRecheck.stands;
        },
      )..suspect();
      addTearDown(doubt.dispose);
      gate.bind(doubt.pass);

      var outsideDone = false;
      final outside = client
          .setStar('tr-1', true)
          .whenComplete(() => outsideDone = true);
      final inner = await inside.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail('the read waits on its own request for good'),
      );
      expect(inner, 'transport');
      await pumpEventQueue();
      expect(sent, isEmpty);
      expect(outsideDone, isFalse, reason: 'held until the read answers');

      released.complete();
      await outside;
      expect(sent, ['PUT /items/tr-1/star']);
    });

    test('what the leaving account\'s work sends under the read, once that '
        'read found another account in its place, is refused, never sent '
        'as that account', () async {
      final gate = SessionGate();
      final server = _Cookie();
      final dio = Dio()
        ..interceptors.add(SessionGateInterceptor(gate))
        ..httpClientAdapter = server;
      final client = WaxDeckClient(baseUrl: 'http://server.test', dio: dio);
      final presented = <String, Object?>{};
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            presented['${options.method} ${options.path}'] =
                options.headers['X-CSRF-Token'];
            handler.next(options);
          },
        ),
      );
      await client.getSession();
      // Another tab signs Ben in over the cookie.
      server.account = 'ben';
      final released = Completer<void>();
      final outcomes = <String, String>{};
      final fired = <Future<void>>[];
      void track(String what, Future<Object?> call) => fired.add(
        call.then(
          (_) => outcomes[what] = 'answered',
          onError: (Object e) =>
              outcomes[what] = e is WaxDeckApiException ? e.code : '$e',
        ),
      );
      final doubt = SessionDoubt(
        read: () async {
          final session = await client.getSession();
          expect(session.user?.id, 'us-ben');
          // The swap forgets Ann's queue, and her playing item's last
          // checkpoint and listen report go from that step, unawaited.
          track('checkpoint', client.putPlayState('tr-1', 1000));
          track(
            'listen',
            client.reportListens([
              ListenSession(
                sessionId: 'ls-1',
                pid: 'tr-1',
                startedAt: DateTime.utc(2026),
                msPlayed: 1000,
              ),
            ]),
          );
          await released.future;
          return SessionRecheck.left;
        },
      )..suspect();
      addTearDown(doubt.dispose);
      gate.bind(doubt.pass);

      track('outside', client.listItems());
      await pumpEventQueue();
      released.complete();
      await Future.wait(fired);
      expect(outcomes, {
        'checkpoint': 'transport',
        'listen': 'transport',
        'outside': 'transport',
      });
      expect(server.answered.where((a) => a.endsWith(' as ben')).toList(), [
        'GET /auth/session as ben',
      ], reason: 'csrf presented: $presented');
    });

    test('the read\'s mark ends with it: work it left behind asks the next '
        'doubt like any request', () async {
      final gate = SessionGate();
      final (client, sent) = _gated(gate);
      var reads = 0;
      late Zone within;
      Completer<void>? held;
      final doubt = SessionDoubt(
        read: () async {
          reads++;
          within = Zone.current;
          await held?.future;
          return SessionRecheck.stands;
        },
      );
      addTearDown(doubt.dispose);
      gate.bind(doubt.pass);
      await doubt.ask();
      expect(reads, 1);

      doubt.suspect();
      held = Completer<void>();
      var done = false;
      final leftover = within
          .run(() => client.listItems())
          .whenComplete(() => done = true);
      await pumpEventQueue();
      expect(reads, 2, reason: 'asked the session again');
      expect(sent, isEmpty);
      expect(done, isFalse);

      held.complete();
      await leftover;
      expect(sent, ['GET /library/items']);
    });

    test('a binding that throws refuses the request, unsent', () async {
      final gate = SessionGate();
      final (client, sent) = _gated(gate);
      gate.bind(() => throw StateError('no session to ask'));

      await expectLater(
        client.listItems(),
        throwsA(
          isA<WaxDeckApiException>().having((e) => e.code, 'code', 'transport'),
        ),
      );
      expect(sent, isEmpty);
    });

    test('lets go only of the binding it is told to: a later one stays', () {
      final gate = SessionGate();
      Future<bool> first() async => true;
      Future<bool> second() async => true;

      gate.bind(first);
      gate.bind(second);
      gate.unbind(first);
      expect(gate.bound, isTrue);
      gate.unbind(second);
      expect(gate.bound, isFalse);
    });
  });

  group('over the app\'s own client, a session read that finds another '
      'account in this one\'s place', () {
    testWidgets('read on the account marker, with nothing in doubt: what the '
        'leaving account\'s playback sends as it goes lands nowhere as the '
        'next account, and his own write goes with his token', (tester) async {
      final server = _Cookie();
      final (container, _, engine) = await _playing(tester, server);

      // Another tab signs Ben in over the cookie. Ann's session lives on,
      // so her socket stays up and nothing is in doubt.
      server.account = 'ben';
      container
          .read(serverEventBusProvider)
          .add(const ServerSyncEvent(kind: 'account'));
      await _until(
        tester,
        () =>
            container.read(authControllerProvider).value?.user?.id == 'us-ben',
      );
      await tester.pump(const Duration(minutes: 1));
      expect(engine.playing, isFalse, reason: 'the leaving session played on');
      await _nothingOfAnnsAsBen(tester, container, server);
      await _close(tester, container);
    });

    testWidgets('read on a rebuild that found it (the hand-over): the same', (
      tester,
    ) async {
      final server = _Cookie();
      final (container, _, engine) = await _playing(tester, server);

      server.account = 'ben';
      container.invalidate(authControllerProvider);
      await _until(
        tester,
        () =>
            container.read(authControllerProvider).value?.user?.id == 'us-ben',
      );
      await tester.pump(const Duration(minutes: 1));
      expect(engine.playing, isFalse, reason: 'the leaving session played on');
      await _nothingOfAnnsAsBen(tester, container, server);
      await _close(tester, container);
    });

    test('read after a sign-in: a write goes with the signed-in account\'s '
        'token, never the one the read found', () async {
      final server = _Cookie();
      final client = WaxDeckClient(
        baseUrl: 'http://server.test',
        dio: Dio()..httpClientAdapter = server,
      );
      await client.login(username: 'ann', password: 'pw');
      // The cookie as a browser's client rides it: no bearer.
      client.authToken = null;
      server.account = 'ben';
      expect((await client.getSession()).user?.id, 'us-ben');

      final outcomes = <String, String>{};
      Future<void> track(String what, Future<Object?> call) => call.then(
        (_) => outcomes[what] = 'answered',
        onError: (Object e) =>
            outcomes[what] = e is WaxDeckApiException ? e.code : '$e',
      );
      await track('checkpoint', client.putPlayState('tr-1', 1000));
      await track(
        'listen',
        client.reportListens([
          ListenSession(
            sessionId: 'ls-1',
            pid: 'tr-1',
            startedAt: DateTime.utc(2026),
            msPlayed: 1000,
          ),
        ]),
      );
      expect(outcomes, {'checkpoint': 'forbidden', 'listen': 'forbidden'});
      expect(
        server.landed.where(_annsWrite),
        isEmpty,
        reason: 'presented: ${server.presented}',
      );
    });

    testWidgets('read by the doubt, the signed-in scope going while it is '
        'out: the shutdown\'s checkpoint queued behind one the gate held, and '
        'the listen report after it, are refused unsent', (tester) async {
      final server = _Cookie();
      final (container, link, engine) = await _playing(tester, server);

      // The socket drops; its reconnect asks the session, and that read is
      // held. Another tab signs Ben in over the cookie meanwhile.
      final held = server.sessionHeld = Completer<void>();
      link.attempts.last.drop(1006);
      await tester.pump(const Duration(seconds: 2));
      server.account = 'ben';
      final from = server.sent.length;
      // A periodic checkpoint comes due and waits on that read.
      engine.advance(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 5));
      expect(server.forTheAccount(from), isEmpty);

      // The read answers Ben. The swap forgets Ann's queue; her session's
      // shutdown queues its checkpoint behind the held one, and the scope
      // goes, the gate with it, before the held one is refused.
      held.complete();
      server.sessionHeld = null;
      await _until(
        tester,
        () =>
            container.read(authControllerProvider).value?.user?.id == 'us-ben',
      );
      await tester.pump(const Duration(minutes: 1));
      expect(engine.playing, isFalse);
      expect(
        server.sent.skip(from).where(_annsWrite),
        isEmpty,
        reason: 'presented: ${server.presented.skip(from).toList()}',
      );
      await _nothingOfAnnsAsBen(tester, container, server);
      await _close(tester, container);
    });

    test('a request made for one account and let go once the client holds '
        'another is refused unsent; one made with no session goes', () async {
      final gate = SessionGate();
      final server = _Cookie();
      final dio = Dio()
        ..interceptors.add(SessionGateInterceptor(gate))
        ..httpClientAdapter = server;
      final client = WaxDeckClient(baseUrl: 'http://server.test', dio: dio);

      // Made before any session: it goes once let go, as whoever signed in.
      var answer = Completer<bool>();
      gate.bind(() => answer.future);
      final beforeAny = client.listItems();
      await pumpEventQueue();
      await client.login(username: 'ann', password: 'pw');
      client.authToken = null;
      answer.complete(true);
      await beforeAny;
      expect(server.sent.last, 'GET /library/items');

      // Made for Ann and held; Ben signs in on this client meanwhile.
      answer = Completer<bool>();
      final outcome = client
          .putPlayState('tr-1', 1000)
          .then<String>(
            (_) => 'answered',
            onError: (Object e) => e is WaxDeckApiException ? e.code : '$e',
          );
      await pumpEventQueue();
      server.account = 'ben';
      await client.login(username: 'ben', password: 'pw');
      client.authToken = null;
      answer.complete(true);
      expect(await outcome, 'transport');
      expect(
        server.landed.where(_annsWrite),
        isEmpty,
        reason: 'presented: ${server.presented}',
      );
    });
  });

  group('over the app\'s own client, a session read that joins a road', () {
    testWidgets('a revoke owed whose read finds another account is delivered '
        'with the token that read found, and settles', (tester) async {
      final server = _Cookie();
      final container = appContainer(
        server: server,
        extra: [
          owedRevokeProvider.overrideWithValue(OwedRevoke(_PageStorage())),
        ],
      );
      container.listen(authControllerProvider, (_, _) {});
      await _until(
        tester,
        () => container.read(authControllerProvider).hasValue,
      );
      final owed = container.read(owedRevokeProvider)..owe('se-old');
      server.account = 'ben';
      final from = server.presented.length;
      var done = false;
      container
          .read(authControllerProvider.notifier)
          .refreshSession()
          .then((_) => done = true)
          .ignore();
      await _until(tester, () => done);
      expect(
        server.presented.skip(from),
        contains('DELETE /auth/sessions/se-old csrf-ben'),
      );
      expect(owed.owed, isFalse);
      await _close(tester, container);
    });

    testWidgets('a sign-in out that the session read joins: a request it '
        'waits on fails at once, unsent, and one made outside it waits and '
        'goes once the account stands', (tester) async {
      final server = _Cookie();
      final container = appContainer(
        server: server,
        extra: [
          owedRevokeProvider.overrideWithValue(OwedRevoke(_PageStorage())),
        ],
      );
      container.listen(authControllerProvider, (_, _) {});
      await _until(
        tester,
        () => container.read(authControllerProvider).hasValue,
      );
      final auth = container.read(authControllerProvider.notifier);
      final repo = container.read(repositoryProvider);
      final doubt = SessionDoubt(read: auth.refreshSession);
      addTearDown(doubt.dispose);
      container.read(sessionGateProvider).bind(doubt.pass);

      // A revoke owed that does not go yet: the sign-in leaves it owed, so
      // a session read made while the sign-in is out waits on it.
      container.read(owedRevokeProvider).owe('se-old');
      server.onRevoke = () async {
        server.onRevoke = null;
        throw StateError('the revoke does not reach the server');
      };
      final outcomes = <String, String>{};
      void track(String what, Future<Object?> call) => call.then(
        (_) => outcomes[what] = 'answered',
        onError: (Object e) =>
            outcomes[what] = e is WaxDeckApiException ? e.code : '$e',
      );
      // A step of the sign-in's road that asks the server, once the
      // session is in doubt and a request made outside the road waits on
      // its read.
      final outside = Zone.current;
      server.onSignIn = () async {
        server.onSignIn = null;
        doubt.suspect();
        outside.run(() => track('outside', repo.setStar('tr-1', true)));
        await repo.listItems().then(
          (_) => outcomes['sign-in\'s own'] = 'answered',
          onError: (Object e) => outcomes['sign-in\'s own'] =
              e is WaxDeckApiException ? e.code : '$e',
        );
      };
      track('sign-in', auth.login(username: 'ann', password: 'pw'));
      await _until(tester, () => outcomes.containsKey('outside'));
      expect(outcomes, {
        'sign-in\'s own': 'transport',
        'sign-in': 'answered',
        'outside': 'answered',
      });
      await _close(tester, container);
    });
  });

  group(
    'over the app\'s own client, the repository a signed-in screen holds',
    () {
      testWidgets('is a view for its account: a call made through it once '
          'another account shows is refused unsent, and the next account\'s '
          'own goes with its token', (tester) async {
        final server = _Cookie();
        final container = await _signedIn(tester, server);
        final anns = container.read(repositoryProvider);

        await _benSignsInElsewhere(tester, container, server);
        final from = server.sent.length;
        final outcome = _outcome(anns.setStar('tr-1', true));
        await tester.pump(const Duration(seconds: 1));
        expect(await outcome, 'transport');
        expect(server.sent.skip(from), isEmpty);
        await _nothingOfAnnsAsBen(tester, container, server);
        await _close(tester, container);
      });

      testWidgets('is not what a server-wide list reads: an account change '
          'reads it no more', (tester) async {
        final server = _Cookie();
        final container = await _signedIn(tester, server);
        container.listen(radioStationsProvider, (_, _) {});
        await _until(
          tester,
          () => container.read(radioStationsProvider).hasValue,
        );

        await _benSignsInElsewhere(tester, container, server);
        await tester.pump(const Duration(seconds: 1));

        expect(
          server.sent.where((r) => r == 'GET /radio/stations'),
          hasLength(1),
        );
        await _close(tester, container);
      });

      testWidgets(
        'the show screen\'s mark-played loop, carried on past a swap: '
        'what is left of it is refused unsent, and nothing lands as the next '
        'account',
        (tester) async {
          tester.view.physicalSize = const Size(900, 1800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final server = _Cookie();
          final container = await _signedIn(tester, server);
          await mountApp(
            tester,
            const ShowScreen(pid: 'pc-1'),
            container: container,
          );
          final second = find.bySemanticsIdentifier(
            SemanticsIds.episode('tr-e2'),
          );
          await _until(tester, () => second.evaluate().isNotEmpty);
          await tester.longPress(
            find.bySemanticsIdentifier(SemanticsIds.episode('tr-e1')),
          );
          await tester.pump(const Duration(seconds: 1));
          await tester.longPress(second);
          await tester.pump(const Duration(seconds: 1));

          // The first write waits at the server while another tab signs Ben in
          // over the cookie, and this one swaps to him.
          final held = Completer<void>();
          server.onWrite = (request) async {
            if (request == 'PUT /items/tr-e1/play-state') await held.future;
          };
          await tester.tap(
            find.bySemanticsIdentifier(SemanticsIds.selectionMarkPlayed),
          );
          await _until(
            tester,
            () => server.sent.contains('PUT /items/tr-e1/play-state'),
          );
          await _benSignsInElsewhere(tester, container, server);
          held.complete();
          await tester.pump(const Duration(seconds: 5));

          expect(
            server.landed.where((w) => w.contains('/play-state')),
            isEmpty,
            reason: 'presented: ${server.presented}',
          );
          expect(
            server.presented.where(
              (p) => p.startsWith('PUT /items/') && p.endsWith(' csrf-ben'),
            ),
            isEmpty,
            reason: 'sent with the next account\'s token',
          );
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(minutes: 1));
        },
      );

      testWidgets(
        'the inbox\'s mark-read chain, carried on past a swap: what is '
        'left of it is refused unsent',
        (tester) async {
          final server = _Cookie();
          final container = await _signedIn(tester, server);
          container.listen(notificationsProvider, (_, _) {});
          await _until(
            tester,
            () =>
                container.read(notificationsProvider).value?.rows.isNotEmpty ??
                false,
          );

          // A visit to the show: the inbox settles by event, a call for the
          // surface and one for the show, one after the other. The first waits
          // at the server while the cookie changes hands.
          final held = Completer<void>();
          var first = true;
          server.onWrite = (request) async {
            if (request != 'POST /users/me/notifications/read' || !first) {
              return;
            }
            first = false;
            await held.future;
          };
          container
              .read(notificationsProvider.notifier)
              .dismissUnder('/podcasts/pc-1');
          await _until(
            tester,
            () => server.sent.contains('POST /users/me/notifications/read'),
          );
          await _benSignsInElsewhere(tester, container, server);
          held.complete();
          await tester.pump(const Duration(seconds: 5));

          expect(
            server.landed.where((w) => w.contains('/notifications')),
            isEmpty,
            reason: 'presented: ${server.presented}',
          );
          expect(
            server.presented.where(
              (p) => p.contains('/notifications') && p.endsWith(' csrf-ben'),
            ),
            isEmpty,
            reason: 'sent with the next account\'s token',
          );
          await _close(tester, container);
        },
      );

      testWidgets('read after a sign-in, through the controller: what the '
          'signed-in account sends while the read\'s account is on its way in '
          'goes with its own token, and lands nowhere', (tester) async {
        final server = _Cookie()..nobody = true;
        final artwork = _Forgetting();
        final container = await _signedIn(tester, server, artwork: artwork);
        expect(
          container.read(authControllerProvider).value?.authenticated,
          isFalse,
        );
        final client = container.read(repositoryProvider) as WaxDeckClient;

        server
          ..nobody = false
          ..account = 'ann';
        WaxDeckRepository? anns;
        container.listen(authControllerProvider, (_, next) {
          if (anns != null || next.value?.user?.id != 'us-ann') return;
          anns = container.read(repositoryProvider);
          // A browser's client rides the cookie, which another tab signs Ben
          // in over before the read this sign-in makes.
          client.authToken = null;
          server.account = 'ben';
        });
        String? inTheWindow;
        artwork.onForget = () async {
          // A request Ann's screens send while she is seen out.
          inTheWindow ??= await _outcome(anns!.setStar('tr-1', true));
        };
        container
            .read(authControllerProvider.notifier)
            .login(username: 'ann', password: 'pw')
            .ignore();
        await _until(
          tester,
          () =>
              container.read(authControllerProvider).value?.user?.id ==
              'us-ben',
        );

        expect(inTheWindow, 'forbidden');
        expect(server.presented, contains('PUT /items/tr-1/star csrf-ann'));
        expect(
          server.presented,
          isNot(contains('PUT /items/tr-1/star csrf-ben')),
        );
        expect(server.landed.where((w) => w.endsWith(' as ben')), isEmpty);
        await _nothingOfAnnsAsBen(tester, container, server);
        await _close(tester, container);
      });

      test(
        'a revoke by id from the devices screen presents the token held, as '
        'any other call does, never one a read found for another account',
        () async {
          final server = _Cookie();
          final client = WaxDeckClient(
            baseUrl: 'http://server.test',
            dio: Dio()..httpClientAdapter = server,
          );
          await client.login(username: 'ann', password: 'pw');
          client.authToken = null;
          server.account = 'ben';
          expect((await client.getSession()).user?.id, 'us-ben');

          expect(await _outcome(client.revokeSession('se-ann-2')), 'forbidden');
          expect(
            server.presented.last,
            'DELETE /auth/sessions/se-ann-2 csrf-ann',
          );
        },
      );
    },
  );

  test(
    'on a device, what the refusal stops of a session\'s writes waits in '
    'the outbox for the session\'s own account, never the next one\'s',
    () async {
      final server = _Cookie();
      final client = WaxDeckClient(
        baseUrl: 'http://server.test',
        dio: Dio()..httpClientAdapter = server,
      );
      await client.login(username: 'ann', password: 'pw');
      final db = inMemoryMirrorDatabase();
      final sync = SyncEngine(
        db: db,
        repository: client,
        channelFactory: deadChannelFactory(),
      )..account = 'us-ann';
      addTearDown(() async {
        sync.dispose();
        await db.close();
      });
      final engine = FakeEngine();
      final session = PlaybackSession(
        repository: client.forAccount('us-ann'),
        engine: engine,
        item: testItem('tr-1'),
        clientId: 'test',
        sync: sync,
        initialPositionMs: 0,
      );
      await session.start();
      for (var i = 0; i < 3; i++) {
        engine.advance(const Duration(seconds: 1));
        await pumpEventQueue();
      }

      // Ann signs out and Ben signs in on this device while her session is
      // still on its way out: its last checkpoint and its listen report are
      // refused unsent.
      server.account = 'ben';
      await client.login(username: 'ben', password: 'pw');
      sync.account = 'us-ben';
      await session.dispose();

      expect(
        server.landed.where((w) => _annsWrite(w) && w.endsWith(' as ben')),
        isEmpty,
      );
      final queued = await db.select(db.outboxMutations).get();
      expect(
        [for (final m in queued) (m.kind, m.owner)],
        [('position', 'us-ann')],
      );
      final listens = await db.select(db.outboxListens).get();
      expect([for (final l in listens) l.owner], ['us-ann']);
      // The mirror's play states are the engine's account's: Ann's
      // position is not shown on Ben's screens.
      final marks = await db
          .customSelect('SELECT pid FROM mirror_play_states')
          .get();
      expect([for (final m in marks) m.read<String>('pid')], isEmpty);
    },
  );

  group('a star tapped for one account and refused once the client holds '
      'another', () {
    /// Ann's tap, held in the gate while Ben signs in on the client, then let
    /// go: refused unsent. [sync] stands for the device's engine, null for a
    /// build without one.
    Future<ProviderContainer> tapAcrossSignIn(
      WidgetTester tester,
      _Cookie server, {
      SyncEngine Function(WaxDeckRepository client)? sync,
    }) async {
      final container = appContainer(
        server: server,
        extra: [
          if (sync != null)
            syncEngineProvider.overrideWith((ref) {
              final engine = sync(ref.watch(apiClientProvider));
              ref.onDispose(engine.dispose);
              return engine;
            }),
        ],
      );
      container.listen(authControllerProvider, (_, _) {});
      await _until(
        tester,
        () => container.read(authControllerProvider).hasValue,
      );
      final star = playStateControllerProvider('tr-1');
      container.listen(star, (_, _) {});
      await _until(tester, () => container.read(star).hasValue);
      final engine = container.read(syncEngineProvider);

      final pass = Completer<bool>();
      container.read(sessionGateProvider).bind(() => pass.future);
      var settled = false;
      container
          .read(star.notifier)
          .setStarred(true)
          .whenComplete(() => settled = true)
          .ignore();
      await tester.pump();
      expect(container.read(star).value?.starred, isTrue);
      server.account = 'ben';
      final client = container.read(apiClientProvider) as WaxDeckClient;
      var benIn = false;
      client
          .login(username: 'ben', password: 'pw')
          .whenComplete(() => benIn = true)
          .ignore();
      await _until(tester, () => benIn);
      engine?.account = 'us-ben';
      pass.complete(true);
      await _until(tester, () => settled);
      // Ann's screens are gone: the tap does not stand on them.
      expect(container.read(star).value?.starred, isFalse);
      return container;
    }

    Future<void> flush(WidgetTester tester, SyncEngine sync) async {
      var flushed = false;
      sync.flushOutbox().whenComplete(() => flushed = true).ignore();
      await _until(tester, () => flushed);
    }

    testWidgets('on a device, waits in the outbox as the tapping account\'s: '
        'never sent for the next account, sent once it is back', (
      tester,
    ) async {
      final server = _Cookie();
      final db = inMemoryMirrorDatabase();
      addTearDown(db.close);
      late SyncEngine sync;
      final container = await tapAcrossSignIn(
        tester,
        server,
        sync: (client) => sync = SyncEngine(
          db: db,
          repository: client,
          channelFactory: deadChannelFactory(),
        )..account = 'us-ann',
      );

      final queued = [
        for (final m in await db.select(db.outboxMutations).get())
          (m.kind, m.owner),
      ];
      await flush(tester, sync);
      expect(
        server.landed.where((w) => w.contains('/star')),
        isEmpty,
        reason: 'queued: $queued',
      );
      expect(queued, [('star', 'us-ann')]);
      // The mirror's play states are Ben's now.
      final marks = await db
          .customSelect('SELECT pid FROM mirror_play_states')
          .get();
      expect(marks, isEmpty);

      // Ann back on the device: her star goes, as hers.
      server.account = 'ann';
      final client = container.read(apiClientProvider) as WaxDeckClient;
      var annIn = false;
      client
          .login(username: 'ann', password: 'pw')
          .whenComplete(() => annIn = true)
          .ignore();
      await _until(tester, () => annIn);
      sync.account = 'us-ann';
      await flush(tester, sync);
      expect(server.landed.where((w) => w.contains('/star')), [
        'PUT /items/tr-1/star as ann',
      ]);
      expect(await db.select(db.outboxMutations).get(), isEmpty);
      await _close(tester, container);
    });

    testWidgets('with no outbox to keep it in, is dropped', (tester) async {
      final server = _Cookie();
      final container = await tapAcrossSignIn(tester, server);
      expect(container.read(syncEngineProvider), isNull);
      await tester.pump(const Duration(seconds: 5));
      expect(server.landed.where((w) => w.contains('/star')), isEmpty);
      await _close(tester, container);
    });
  });

  group('on a device, the sync engine over the app\'s own client', () {
    late _Cookie server;
    late WaxDeckClient client;
    late MirrorDatabase db;
    late SyncEngine sync;

    setUp(() async {
      server = _Cookie();
      client = WaxDeckClient(
        baseUrl: 'http://server.test',
        dio: Dio()..httpClientAdapter = server,
      );
      await client.login(username: 'ann', password: 'pw');
      db = inMemoryMirrorDatabase();
      sync = SyncEngine(
        db: db,
        repository: client,
        channelFactory: deadChannelFactory(),
      )..account = 'us-ann';
    });

    tearDown(() async {
      sync.dispose();
      await db.close();
    });

    /// Ben signs in on the device while [request] is at the server.
    void benSignsInAt(String request) {
      server.onRequest = (arrived) async {
        if (arrived != request) return;
        server.onRequest = null;
        server.account = 'ben';
        await client.login(username: 'ben', password: 'pw');
        sync.account = 'us-ben';
      };
    }

    test(
      'a flush begun for one account sends none of what is left of it '
      'once the client holds another: it waits for its own account',
      () async {
        await sync.queueCheckpoint('tr-1', 1000);
        await sync.queueCheckpoint('tr-2', 2000);
        benSignsInAt('PUT /items/tr-1/play-state');

        final outcome = await _outcome(sync.flushOutbox());

        expect(server.forTheAccount(), [
          'PUT /items/tr-1/play-state',
        ], reason: 'flushed: $outcome');
        expect(outcome, 'transport');
        final waiting = await db.select(db.outboxMutations).get();
        expect(
          [for (final m in waiting) (m.pid, m.owner)],
          [('tr-2', 'us-ann')],
        );
      },
    );

    test('a preference patch sent for one account is not sent once the '
        'client holds another: it waits for its own account', () async {
      await sync.queuePrefsPatch({'identifyOptOut': true}, owner: 'us-ann');
      benSignsInAt('GET /users/me/prefs');

      final outcome = await _outcome(sync.sendPrefs('us-ann'));

      expect(server.forTheAccount(), [
        'GET /users/me/prefs',
      ], reason: 'sent: $outcome');
      expect(outcome, 'transport');
      expect(await sync.pendingPrefsPatch('us-ann'), {'identifyOptOut': true});
    });

    test('a book\'s marks sent for one account are not sent once the client '
        'holds another: what is left waits for its own account', () async {
      for (final id in ['bm-1', 'bm-2']) {
        await sync.queueBookmarkCreate(
          'bk-1',
          Bookmark(id: id, positionMs: 1000, createdAt: DateTime.utc(2026)),
          owner: 'us-ann',
        );
      }
      benSignsInAt('POST /books/bk-1/bookmarks');

      final outcome = await _outcome(sync.sendBookmarks('bk-1'));

      expect(server.forTheAccount(), [
        'POST /books/bk-1/bookmarks',
      ], reason: 'sent: $outcome');
      expect(outcome, 'transport');
      final waiting = await db.select(db.outboxMutations).get();
      expect(
        [for (final m in waiting) (m.owner, m.payload?.contains('bm-2'))],
        [('us-ann', true)],
      );
    });
  });
}
