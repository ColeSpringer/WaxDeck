import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck/src/artwork/artwork_store.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/auth/forget_server.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_persistence.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/sync/sync_binder.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

/// A native start with the server out of reach opens on the session the
/// device remembers for its token, and the server confirms it, or ends
/// it, when it is next reached. What is remembered is written by the
/// server's answers alone and goes wherever the token goes.

const _ann = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDACCANN',
  username: 'ann',
  roles: ['user'],
);
const _ben = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDACCBEN',
  username: 'ben',
  roles: ['user'],
);

const _anns = SessionState(authenticated: true, user: _ann);
const _bens = SessionState(
  authenticated: true,
  user: _ben,
  sessionId: 'se-ben',
);
const _nobody = SessionState(authenticated: false);

/// Ann, once an administrator let her upload.
const _annsNow = SessionState(
  authenticated: true,
  user: WaxDeckUser(
    id: 'us-01JZX5N8QW3F4V9T2B7KDACCANN',
    username: 'ann',
    roles: ['user'],
    uploadEnabled: true,
  ),
);

/// A connect nothing answered.
const _lost = WaxDeckApiException(
  code: 'transport',
  message: 'connection refused',
);

/// The server saying, in its own words, that the token has no session.
const _noSession = WaxDeckApiException(
  code: 'unauthenticated',
  message: 'no valid session or token was presented',
  statusCode: 401,
);

/// The ways a session read fails that say nothing of the session: all but
/// [_noSession].
const _notTheSessionsEnd = <String, WaxDeckApiException>{
  'a refused connect': _lost,
  'a deadline': WaxDeckApiException(
    code: 'transport-timeout',
    message: 'the server did not answer in time',
  ),
  'a server shutting down': WaxDeckApiException(
    code: 'unavailable',
    message: 'the server is shutting down',
    statusCode: 503,
  ),
  'a gateway with nothing behind it': WaxDeckApiException(
    code: 'transport',
    message: 'Bad Gateway',
    statusCode: 502,
  ),
  'a sign-in page in front of the server': WaxDeckApiException(
    code: 'transport',
    message: 'Unauthorized',
    statusCode: 401,
  ),
  'a server that fails': WaxDeckApiException(
    code: 'internal',
    message: 'internal error',
    statusCode: 500,
  ),
  'a refusal that is not of the session': WaxDeckApiException(
    code: 'forbidden',
    message: 'not for this client',
    statusCode: 403,
  ),
};

/// A server whose session reads can fail or be held, whose sign-ins
/// answer whoever [next] names, and whose rotation keeps the account and,
/// as the client's does, becomes the bearer only of the token it was
/// asked with.
class _Server extends FakeRepository {
  _Server({SessionState session = _anns})
    : super(sessionState: session, items: [testItem('tr-A')]);

  WaxDeckUser next = _ben;

  var sessionReads = 0;

  /// What a session read fails with, while set.
  WaxDeckApiException? sessionError;

  /// Something a session read throws that is no API error, while set.
  Object? sessionFault;

  /// Holds each session read asked while it is set; a read let go answers
  /// what the server says then.
  Completer<void>? gate;

  /// Holds each rotation asked while it is set.
  Completer<void>? rotationGate;

  /// Whether a rotation's token becomes the bearer; false stands for a
  /// client whose credentials moved while the rotation was out.
  var takesRotations = true;

  @override
  Future<SessionState> getSession() async {
    sessionReads++;
    await gate?.future;
    if (sessionFault case final fault?) throw fault;
    if (sessionError case final error?) throw error;
    // Decoded afresh, as the real client's every read is.
    return SessionState.fromStored(sessionState.toStored())!;
  }

  @override
  Future<LoginResult> login({
    required String username,
    required String password,
    String? deviceName,
  }) async {
    final session = 'se-${next.username}';
    sessionState = SessionState(
      authenticated: true,
      user: next,
      serverReadOnly: serverReadOnly,
      sessionId: session,
    );
    authToken = 'token-${next.username}';
    return LoginResult(
      user: next,
      token: 'token-${next.username}',
      sessionId: session,
    );
  }

  @override
  Future<LoginResult> refreshToken() async {
    // Each rotation mints its own, as the server does.
    final token = refreshCalls++ == 0
        ? 'rotated-token'
        : 'rotated-token-$refreshCalls';
    final user = sessionState.user!;
    final sent = authToken;
    await rotationGate?.future;
    if (refreshError case final error?) throw error;
    if (takesRotations && authToken == sent) authToken = token;
    return LoginResult(
      user: user,
      token: token,
      sessionId: sessionState.sessionId ?? 'se-${user.username}',
    );
  }
}

/// A server that says its next answer to whoever asked to hear it, once,
/// as the client does.
class _Heard extends _Server implements ServerAnswers {
  @override
  void Function()? onNextAnswer;

  /// The server answers some request that is not a session read.
  void answer() {
    final hear = onNextAnswer;
    onNextAnswer = null;
    hear?.call();
  }
}

/// A store that says what was asked of it.
class _Recorded extends InMemoryCredentialStore {
  final calls = <String>[];

  @override
  Future<String?> readToken() {
    calls.add('readToken');
    return super.readToken();
  }

  @override
  Future<void> writeToken(String value) {
    calls.add('writeToken');
    return super.writeToken(value);
  }

  @override
  Future<void> clearToken() {
    calls.add('clearToken');
    return super.clearToken();
  }

  @override
  Future<String?> readSession() {
    calls.add('readSession');
    return super.readSession();
  }

  @override
  Future<void> writeSession(String value) {
    calls.add('writeSession');
    return super.writeSession(value);
  }

  @override
  Future<void> clearSession() {
    calls.add('clearSession');
    return super.clearSession();
  }
}

/// A store whose token reads, while [reads] is set, answer what they found
/// when asked only once it completes, as a keystore's answer takes time;
/// whose token writes land only once [writes] does, while it is set;
/// whose token writes fail with [writeFault], while that is set; and
/// whose clears of the token, done when asked, are answered only once
/// [clears] completes, while it is set.
class _SlowStore extends InMemoryCredentialStore {
  Completer<void>? reads;
  Completer<void>? writes;
  Completer<void>? clears;
  Object? writeFault;

  /// How many token reads are waiting on [reads].
  var waiting = 0;

  @override
  Future<String?> readToken() async {
    final found = token;
    if (reads case final gate?) {
      waiting++;
      await gate.future;
      waiting--;
    }
    return found;
  }

  @override
  Future<void> writeToken(String value) async {
    if (writes case final gate?) await gate.future;
    if (writeFault case final fault?) throw fault;
    token = value;
  }

  @override
  Future<void> clearToken() async {
    session = null;
    token = null;
    if (clears case final gate?) await gate.future;
  }
}

/// A store whose writes and clears of what is remembered can fail, as a
/// keystore's do: in silence, and apart from the token's.
class _Faulty extends InMemoryCredentialStore {
  var sessionWritesFail = false;
  var sessionClearsFail = false;

  @override
  Future<void> writeSession(String value) async {
    if (!sessionWritesFail) session = value;
  }

  @override
  Future<void> clearSession() async {
    if (!sessionClearsFail) session = null;
  }

  @override
  Future<void> clearToken() async {
    await clearSession();
    token = null;
  }
}

/// The device's queue store, holding what the account's last launch left.
class _Disk implements QueueStore {
  StoredQueue? saved = StoredQueue(
    entries: const [
      StoredQueueEntry(queueId: 'q0', pid: 'tr-A', sourceRank: 0),
    ],
    currentIndex: 0,
    shuffled: false,
    repeat: 'off',
    sourceKind: 'album',
    sourceLabel: 'Kind of Blue',
    nextQueueId: 1,
    updatedAt: DateTime.utc(2026, 10, 30),
  );

  @override
  Future<StoredQueue?> load() async => saved;

  @override
  Future<void> save(StoredQueue queue) async => saved = queue;

  @override
  Future<void> clear() async => saved = null;
}

/// Artwork whose wipe waits on [gate]: an account's leaving is held
/// there, before the session moves.
class _HeldArtwork extends FakeArtworkStore {
  final gate = Completer<void>();
  final _reached = Completer<void>();

  Future<void> get reached => _reached.future;

  @override
  Future<void> forgetEverything() async {
    if (!_reached.isCompleted) _reached.complete();
    await gate.future;
    await super.forgetEverything();
  }
}

/// The server as the app's own client meets it: out of reach while [down]
/// says how, else Ann's account behind any bearer token it has not
/// [revoked].
class _Wire implements HttpClientAdapter {
  /// What a request fails with, while set; a request it answers null for
  /// goes through.
  DioException? Function(RequestOptions options)? down;

  var revoked = false;

  /// Every request made, as `GET /auth/session`.
  final asked = <String>[];

  /// Every request answered, spelled as in [asked].
  final answered = <String>[];

  /// Holds each request it names, spelled as in [asked], until completed.
  final held = <String, Completer<void>>{};

  /// How many session reads were made.
  int get sessionReads =>
      asked.where((request) => request == 'GET /auth/session').length;

  static final _user = <String, Object?>{
    'id': _ann.id,
    'username': _ann.username,
    'roles': _ann.roles,
    'uploadEnabled': false,
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path.replaceFirst('/api/v1', '');
    final request = '${options.method} $path';
    asked.add(request);
    await held[request]?.future;
    if (down?.call(options) case final failure?) throw failure;
    final known = options.headers['Authorization'] != null && !revoked;
    final (status, body) = switch ((options.method, path)) {
      ('GET', '/auth/session') when known => (
        200,
        {'authenticated': true, 'user': _user, 'csrfToken': 'csrf'},
      ),
      ('GET', '/auth/session') => (200, {'authenticated': false}),
      ('POST', '/auth/refresh') when known => (
        200,
        {
          'user': _user,
          'token': 'rotated-token',
          'csrfToken': 'csrf',
          'sessionId': 'se-1',
        },
      ),
      ('GET', '/library/items') when known => (200, {'items': <Object>[]}),
      ('GET', '/library/items') => (
        401,
        {'code': _noSession.code, 'message': _noSession.message},
      ),
      _ => (404, {'code': 'not-found', 'message': 'not found'}),
    };
    answered.add(request);
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

/// How a server out of reach fails a request of the app's own client.
final _outOfReach = <String, DioException Function(RequestOptions)>{
  'a refused connect': (options) => DioException.connectionError(
    requestOptions: options,
    reason: 'Connection refused',
  ),
  'a connect deadline': (options) => DioException.connectionTimeout(
    timeout: const Duration(seconds: 10),
    requestOptions: options,
  ),
  'a receive deadline': (options) => DioException.receiveTimeout(
    timeout: const Duration(seconds: 30),
    requestOptions: options,
  ),
};

typedef _Client = ({
  ProviderContainer container,
  _Server server,
  InMemoryCredentialStore store,
  _Disk disk,
});

/// A native client holding Ann's token and, unless [remembered] is null,
/// the session the server last answered for it, or for [keptFor]; with
/// [planted] false, whatever [store] already holds. The session is
/// watched, as the app's first frame watches it.
_Client _client({
  String? token = 'token-ann',
  SessionState? remembered = _anns,
  String keptFor = 'token-ann',
  bool planted = true,
  InMemoryCredentialStore? store,
  _Server? server,
  ArtworkStore? artwork,
  SyncEngine? sync,
  MirrorDatabase? mirror,
  FakeDownloads? downloads,
}) {
  final repo = server ?? _Server();
  final credentials = store ?? InMemoryCredentialStore();
  if (planted) {
    credentials
      ..token = token
      ..session = remembered == null
          ? null
          : rememberedRecord(keptFor, remembered.toStored());
  }
  final disk = _Disk();
  final container = appContainer(
    repo: repo,
    credentials: credentials,
    artwork: artwork,
    sync: sync,
    mirror: mirror,
    downloads: downloads,
    settings: MemoryClientSettingsStore(),
    extra: [
      // With a mirror the queue is the mirror's, which these do not read.
      if (mirror == null) queueStoreProvider.overrideWithValue(disk),
      queueSaveDebounceProvider.overrideWithValue(Duration.zero),
    ],
  );
  final watched = container.listen(authControllerProvider, (_, _) {});
  addTearDown(watched.close);
  return (container: container, server: repo, store: credentials, disk: disk);
}

/// A client started with the server out of reach, open on what it
/// remembers.
Future<_Client> _startedOutOfReach({ArtworkStore? artwork}) async {
  final client = _client(artwork: artwork);
  client.server.sessionError = _lost;
  await pumpEventQueue();
  expect(_session(client)?.user?.id, _ann.id);
  expect(_auth(client).unconfirmed, isTrue);
  return client;
}

/// Until [settled] holds, for at most three seconds.
Future<void> _until(bool Function() settled) async {
  for (var i = 0; i < 300 && !settled(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(settled(), isTrue, reason: 'did not settle');
}

AuthController _auth(_Client client) =>
    client.container.read(authControllerProvider.notifier);

SessionState? _session(_Client client) =>
    client.container.read(authControllerProvider).value;

/// What the store remembers for the token it holds.
SessionState? _remembered(_Client client) {
  final token = client.store.token;
  final record = client.store.session;
  if (token == null || record == null) return null;
  return switch (rememberedFor(token, record)) {
    final text? => SessionState.fromStored(text),
    null => null,
  };
}

void main() {
  group('a start that cannot reach the server', () {
    testWidgets('opens on the session the device remembers, after one read '
        'and no more', (tester) async {
      final client = _client();
      client.server.sessionError = _lost;
      await tester.pump(Duration.zero);

      expect(_session(client), _anns);
      expect(_auth(client).unconfirmed, isTrue);
      expect(client.server.sessionReads, 1);

      // Longer than the whole of the ladder a failed read once climbed.
      await tester.pump(const Duration(minutes: 1));
      expect(client.server.sessionReads, 1);
      expect(_session(client), _anns);
      expect(client.store.token, 'token-ann');
      expect(client.server.authToken, 'token-ann');
      expect(client.server.refreshCalls, 0, reason: 'nobody to rotate with');
      expect(await client.disk.load(), isNotNull);
    });

    testWidgets('lands on Home', (tester) async {
      final client = _client();
      client.server.sessionError = _lost;
      await pumpWholeApp(tester, container: client.container);

      expect(
        find.bySemanticsIdentifier(SemanticsIds.homeScreen),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.loginUsername),
        findsNothing,
      );
      expect(client.server.sessionReads, 1);
    });

    for (final MapEntry(key: what, value: error)
        in _notTheSessionsEnd.entries) {
      test('$what opens on it too', () async {
        final client = _client();
        client.server.sessionError = error;
        await pumpEventQueue();

        expect(_session(client), _anns);
        expect(_auth(client).unconfirmed, isTrue);
        expect(client.server.sessionReads, 1);
      });
    }

    testWidgets('waits on a server that hangs for the stated bound and no '
        'longer', (tester) async {
      final client = _client();
      client.server.gate = Completer<void>();

      await tester.pump(
        kRememberedSessionWait - const Duration(milliseconds: 1),
      );
      expect(_session(client), isNull, reason: 'still the server\'s to say');
      await tester.pump(const Duration(milliseconds: 1));

      expect(_session(client), _anns);
      expect(_auth(client).unconfirmed, isTrue);
      expect(client.server.sessionReads, 1);
    });

    testWidgets('draws the emblem for that bound, then Home', (tester) async {
      final client = _client();
      client.server.gate = Completer<void>();
      await mountHost(tester, const WaxDeckApp(), container: client.container);

      await tester.pump(
        kRememberedSessionWait - const Duration(milliseconds: 1),
      );
      expect(find.byType(WaxWordmark), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier(SemanticsIds.homeScreen),
        findsOneWidget,
      );
      expect(client.server.sessionReads, 1);
    });

    testWidgets('a server that answers inside the bound is the one '
        'believed', (tester) async {
      final client = _client();
      final gate = client.server.gate = Completer<void>();
      client.server.sessionState = _annsNow;
      await tester.pump(const Duration(seconds: 1));
      gate.complete();
      await tester.pump(Duration.zero);

      expect(_session(client), _annsNow);
      expect(_auth(client).unconfirmed, isFalse);
      expect(_remembered(client), _annsNow);
      expect(client.server.refreshCalls, 1);
    });

    testWidgets('with nothing remembered asks again as it always has, and '
        'ends signed out with its token kept', (tester) async {
      final client = _client(remembered: null);
      client.server.sessionError = _lost;
      await tester.pump(Duration.zero);
      expect(_session(client), isNull);
      expect(client.server.sessionReads, 1);

      await tester.pump(const Duration(seconds: 45));
      final state = client.container.read(authControllerProvider);
      expect(state.hasError, isTrue);
      expect(state.isLoading, isFalse);
      expect(state.value, isNull);
      expect(client.server.sessionReads, 11);
      expect(_auth(client).unconfirmed, isFalse);
      expect(client.store.token, 'token-ann');
    });

    test('with nothing readable remembered asks again as it always '
        'has', () async {
      final client = _client();
      client.store.session = 'not a session';
      client.server.sessionError = _lost;
      await pumpEventQueue();

      expect(_session(client), isNull);
      expect(_auth(client).unconfirmed, isFalse);
    });

    test('with a signed-out session remembered asks again as it always '
        'has', () async {
      final client = _client(remembered: _nobody);
      client.server.sessionError = _lost;
      await pumpEventQueue();

      expect(_session(client), isNull);
      expect(_auth(client).unconfirmed, isFalse);
    });
  });

  group('a start the server refuses', () {
    test('with no session for the token loses the token, what is '
        'remembered and what the account left', () async {
      final client = _client(server: _Server(session: _nobody));
      await pumpEventQueue();

      expect(_session(client), _nobody);
      expect(_auth(client).unconfirmed, isFalse);
      expect(client.server.sessionReads, 1);
      expect(client.store.token, isNull);
      expect(client.store.session, isNull);
      expect(client.server.authToken, isNull);
      expect(await client.disk.load(), isNull);
    });

    test('in its own words loses them too, and is not answered from what '
        'is remembered', () async {
      final client = _client();
      client.server.sessionError = _noSession;
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(_session(client), _nobody);
      expect(_auth(client).unconfirmed, isFalse);
      expect(client.server.sessionReads, 1);
      expect(client.store.token, isNull);
      expect(client.store.session, isNull);
      expect(client.server.authToken, isNull);
      expect(await client.disk.load(), isNull);
    });

    test('in its own words with nothing remembered ends as it always has: '
        'an error, not asked again, its token kept', () async {
      final client = _client(remembered: null);
      client.server.sessionError = _noSession;
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final state = client.container.read(authControllerProvider);
      expect(state.hasError, isTrue);
      expect(state.value, isNull);
      expect(client.server.sessionReads, 1);
      expect(client.store.token, 'token-ann');
    });
  });

  group('a session the device remembered, once the server is reached', () {
    test('stands for the same account: the token rotates, once, and what '
        'is remembered is rewritten', () async {
      final client = await _startedOutOfReach();
      client.server
        ..sessionError = null
        ..sessionState = _annsNow;

      expect(await _auth(client).refreshSession(), SessionRecheck.stands);
      await pumpEventQueue();

      expect(_session(client), _annsNow);
      expect(_auth(client).unconfirmed, isFalse);
      expect(client.server.refreshCalls, 1);
      expect(client.store.token, 'rotated-token');
      expect(_remembered(client), _annsNow);
      expect(await client.disk.load(), isNotNull);

      expect(await _auth(client).refreshSession(), SessionRecheck.stands);
      await pumpEventQueue();
      expect(client.server.refreshCalls, 1, reason: 'a start rotates once');
    });

    test('is signed out when the server ended it, and nothing of the '
        'account is left', () async {
      final client = await _startedOutOfReach();
      client.server
        ..sessionError = null
        ..sessionState = _nobody;

      expect(await _auth(client).refreshSession(), SessionRecheck.left);

      expect(_session(client), _nobody);
      expect(_auth(client).unconfirmed, isFalse);
      expect(client.store.token, isNull);
      expect(client.store.session, isNull);
      expect(client.server.authToken, isNull);
      expect(await client.disk.load(), isNull);
      expect(client.server.refreshCalls, 0);
    });

    test('is signed out by a 401 in the server\'s own words too', () async {
      final client = await _startedOutOfReach();
      client.server.sessionError = _noSession;

      expect(await _auth(client).refreshSession(), SessionRecheck.left);

      expect(_session(client), _nobody);
      expect(client.store.token, isNull);
      expect(client.store.session, isNull);
      expect(await client.disk.load(), isNull);
    });

    test('that turns out to be another account\'s is a sign-out and a '
        'sign-in, with nothing remembered in between', () async {
      final artwork = _HeldArtwork();
      final client = await _startedOutOfReach(artwork: artwork);
      client.server
        ..sessionError = null
        ..sessionState = _bens;

      final read = _auth(client).refreshSession();
      await artwork.reached;
      expect(
        client.store.session,
        isNull,
        reason: 'Ann is leaving: a kill here must not start as her',
      );
      artwork.gate.complete();

      expect(await read, SessionRecheck.left);
      await pumpEventQueue();
      expect(_session(client), _bens);
      expect(_auth(client).unconfirmed, isFalse);
      expect(await client.disk.load(), isNull);
      expect(_remembered(client), _bens);
    });

    test('stays as it was when the server still does not answer', () async {
      final client = await _startedOutOfReach();

      expect(await _auth(client).refreshSession(), SessionRecheck.unanswered);
      await pumpEventQueue();

      expect(_session(client), _anns);
      expect(_auth(client).unconfirmed, isTrue);
      expect(client.server.refreshCalls, 0);
      expect(_remembered(client), _anns);
      expect(client.store.token, 'token-ann');
    });
  });

  group('a server that answers after the bound is still the one believed', () {
    /// Ann's client, open on what it remembers over a read still out.
    Future<(_Client, Completer<void>)> waitedOut(WidgetTester tester) async {
      final client = _client();
      final gate = client.server.gate = Completer<void>();
      await tester.pump(kRememberedSessionWait);
      expect(_session(client), _anns);
      expect(_auth(client).unconfirmed, isTrue);
      client.server.gate = null;
      return (client, gate);
    }

    testWidgets('for the same account it stands, the token rotates and '
        'what is remembered is rewritten, on the one read', (tester) async {
      final (client, gate) = await waitedOut(tester);
      client.server.sessionState = _annsNow;
      gate.complete();
      await tester.pump(Duration.zero);

      expect(_session(client), _annsNow);
      expect(_auth(client).unconfirmed, isFalse);
      expect(client.server.sessionReads, 1);
      expect(client.server.refreshCalls, 1);
      expect(client.store.token, 'rotated-token');
      expect(_remembered(client), _annsNow);
    });

    testWidgets('with no session for the token it signs out, and nothing '
        'of the account is left', (tester) async {
      final (client, gate) = await waitedOut(tester);
      client.server.sessionState = _nobody;
      gate.complete();
      await tester.pump(Duration.zero);

      expect(_session(client), _nobody);
      expect(client.store.token, isNull);
      expect(client.store.session, isNull);
      expect(await client.disk.load(), isNull);
      expect(client.server.sessionReads, 1);
    });

    testWidgets('with no answer after all the session stays as it '
        'was', (tester) async {
      final (client, gate) = await waitedOut(tester);
      client.server.sessionError = _lost;
      gate.complete();
      await tester.pump(const Duration(minutes: 1));

      expect(_session(client), _anns);
      expect(_auth(client).unconfirmed, isTrue);
      expect(client.server.sessionReads, 1);
      expect(_remembered(client), _anns);
    });

    testWidgets('once the account signed out it is heard by '
        'nobody', (tester) async {
      final (client, gate) = await waitedOut(tester);
      await _auth(client).signOutLocally();
      expect(_session(client), _nobody);

      gate.complete();
      await tester.pump(Duration.zero);

      expect(_session(client), _nobody);
      expect(client.store.token, isNull);
      expect(client.store.session, isNull);
      expect(client.server.refreshCalls, 0);
    });

    testWidgets('once another account signed in it is heard by '
        'nobody', (tester) async {
      final (client, gate) = await waitedOut(tester);
      await _auth(client).signOutLocally();
      await _auth(client).login(username: 'ben', password: 'pw');
      await tester.pump(Duration.zero);
      final reads = client.server.sessionReads;
      expect(_session(client), _bens);

      // Ann's read, let go at last, answers for the token it was sent
      // with: hers.
      client.server.sessionState = _anns;
      gate.complete();
      await tester.pump(Duration.zero);

      expect(_session(client), _bens);
      expect(client.server.sessionReads, reads);
      expect(client.store.token, 'token-ben');
      expect(client.server.authToken, 'token-ben');
      expect(_remembered(client), _bens);
      expect(client.server.refreshCalls, 0);
    });
  });

  group('the sync engine reaching the server', () {
    /// Ann's client open on what it remembers, the sync binder running
    /// over a real engine whose socket cannot come up yet.
    Future<(_Client, SyncEngine, FakeLink)> offline() async {
      final db = inMemoryMirrorDatabase();
      addTearDown(db.close);
      final downloads = FakeDownloads();
      addTearDown(downloads.dispose);
      final server = _Server()..sessionError = _lost;
      final link = FakeLink()..reachable = false;
      final engine = SyncEngine(
        db: db,
        repository: server,
        channelFactory: link.factory,
      );
      addTearDown(engine.dispose);
      final client = _client(
        server: server,
        sync: engine,
        mirror: db,
        downloads: downloads,
      );
      await pumpEventQueue();
      expect(_session(client)?.user?.id, _ann.id);
      expect(_auth(client).unconfirmed, isTrue);
      final alive = client.container.listen(syncBinderProvider, (_, _) {});
      addTearDown(alive.close);
      // As the router's signed-in scope goes with the session.
      final scope = client.container.listen(authControllerProvider, (_, next) {
        if (next.value?.authenticated == false) alive.close();
      });
      addTearDown(scope.close);
      await pumpEventQueue();
      expect(engine.current.online, isFalse);
      expect(client.server.sessionReads, 1, reason: 'nothing was reached');
      return (client, engine, link);
    }

    test('reads the session it opened on, once: it stands, the token '
        'rotates, and a later return reads nothing', () async {
      final (client, engine, link) = await offline();

      client.server
        ..sessionError = null
        ..sessionState = _annsNow;
      link.reachable = true;
      // The engine's own reconnect, a second after its first attempt.
      await _until(() => engine.current.online);
      await engine.beforeSync(() async {});
      await pumpEventQueue();

      expect(client.server.sessionReads, 2);
      expect(_session(client), _annsNow);
      expect(_auth(client).unconfirmed, isFalse);
      expect(client.server.refreshCalls, 1);
      expect(client.store.token, 'rotated-token');
      expect(_remembered(client), _annsNow);

      // A drop and a return: a bearer token cannot change hands across one.
      link.attempts.last.drop(null);
      expect(engine.current.online, isFalse);
      await _until(() => engine.current.online);
      await engine.beforeSync(() async {});
      await pumpEventQueue();
      expect(client.server.sessionReads, 2);
      expect(client.server.refreshCalls, 1);
    });

    test('with a token revoked while the device was away signs out, and '
        'nothing of the account is left', () async {
      final (client, engine, link) = await offline();

      client.server
        ..sessionError = null
        ..sessionState = _nobody;
      link
        ..reachable = true
        ..refusal = const UpgradeRefused(401);
      await _until(() => _session(client)?.authenticated == false);
      await pumpEventQueue();

      expect(_session(client), _nobody);
      expect(client.store.token, isNull);
      expect(client.store.session, isNull);
      expect(client.server.authToken, isNull);
      expect(engine.started, isFalse);
    });
  });

  group('over the app\'s own client', () {
    /// Ann's client over [wire], and the session requests it made.
    (ProviderContainer, InMemoryCredentialStore) over(_Wire wire) {
      final store = InMemoryCredentialStore()
        ..token = 'token-ann'
        ..session = rememberedRecord('token-ann', _anns.toStored());
      final container = appContainer(server: wire, credentials: store);
      final watched = container.listen(authControllerProvider, (_, _) {});
      addTearDown(watched.close);
      return (container, store);
    }

    for (final MapEntry(key: what, value: fail) in _outOfReach.entries) {
      test('$what at start opens on what is remembered; back in reach '
          'the session stands and the token rotates', () async {
        final wire = _Wire()..down = fail;
        final (container, store) = over(wire);
        final auth = container.read(authControllerProvider.notifier);
        await _until(() => container.read(authControllerProvider).hasValue);

        expect(container.read(authControllerProvider).value, _anns);
        expect(auth.unconfirmed, isTrue);
        expect(wire.asked, ['GET /auth/session']);

        wire.down = null;
        expect(await auth.refreshSession(), SessionRecheck.stands);
        await _until(() => store.token == 'rotated-token');

        expect(auth.unconfirmed, isFalse);
        expect(wire.asked, [
          'GET /auth/session',
          'GET /auth/session',
          'POST /auth/refresh',
        ]);
        expect(container.read(repositoryProvider).authToken, 'rotated-token');
        expect(store.session, isNotNull);
      });
    }

    test('a token revoked while the device was out of reach signs out at '
        'the first answer, and nothing is left remembered', () async {
      final wire = _Wire()..down = _outOfReach.values.first;
      final (container, store) = over(wire);
      final auth = container.read(authControllerProvider.notifier);
      await _until(() => container.read(authControllerProvider).hasValue);
      expect(auth.unconfirmed, isTrue);

      wire
        ..down = null
        ..revoked = true;
      expect(await auth.refreshSession(), SessionRecheck.left);

      expect(container.read(authControllerProvider).value, _nobody);
      expect(store.token, isNull);
      expect(store.session, isNull);
      expect(container.read(repositoryProvider).authToken, isNull);
      expect(wire.asked, ['GET /auth/session', 'GET /auth/session']);
    });
  });

  test('over the app\'s own client, a rotation that lands after a sign-out '
      'is nobody\'s bearer and is not stored', () async {
    final wire = _Wire();
    final rotation = wire.held['POST /auth/refresh'] = Completer<void>();
    final store = InMemoryCredentialStore()
      ..token = 'token-ann'
      ..session = rememberedRecord('token-ann', _anns.toStored());
    final container = appContainer(server: wire, credentials: store);
    final watched = container.listen(authControllerProvider, (_, _) {});
    addTearDown(watched.close);
    final auth = container.read(authControllerProvider.notifier);
    final repo = container.read(repositoryProvider);
    await _until(() => wire.asked.contains('POST /auth/refresh'));
    expect(container.read(authControllerProvider).value, _anns);

    await auth.signOutLocally();
    expect(repo.authToken, isNull);
    rotation.complete();
    await _until(() => wire.answered.contains('POST /auth/refresh'));
    await pumpEventQueue();

    expect(repo.authToken, isNull);
    expect(store.token, isNull);
    expect(store.session, isNull);
  });

  group('a request the server answers, with no socket ever up', () {
    /// Ann's client over [wire], open on what it remembers with the server
    /// out of reach. No sync engine runs here, so nothing but a request
    /// can say the server is back.
    Future<(ProviderContainer, InMemoryCredentialStore)> outOfReach(
      _Wire wire,
    ) async {
      wire.down = _outOfReach.values.first;
      final store = InMemoryCredentialStore()
        ..token = 'token-ann'
        ..session = rememberedRecord('token-ann', _anns.toStored());
      final container = appContainer(server: wire, credentials: store);
      final watched = container.listen(authControllerProvider, (_, _) {});
      addTearDown(watched.close);
      await _until(() => container.read(authControllerProvider).hasValue);
      expect(
        container.read(authControllerProvider.notifier).unconfirmed,
        isTrue,
      );
      expect(wire.asked, ['GET /auth/session']);
      return (container, store);
    }

    test('confirms the session it opened on: one session read, the token '
        'rotates, and a later answer reads nothing', () async {
      final wire = _Wire();
      final (container, store) = await outOfReach(wire);
      final auth = container.read(authControllerProvider.notifier);
      final repo = container.read(repositoryProvider);

      wire.down = null;
      await repo.listItems();
      await _until(() => store.token == 'rotated-token');

      expect(auth.unconfirmed, isFalse);
      expect(container.read(authControllerProvider).value, _anns);
      expect(wire.asked, [
        'GET /auth/session',
        'GET /library/items',
        'GET /auth/session',
        'POST /auth/refresh',
      ]);
      expect(repo.authToken, 'rotated-token');

      await repo.listItems();
      await pumpEventQueue();
      expect(wire.sessionReads, 2);
      expect(wire.asked, hasLength(5));
    });

    test('with a refusal for want of a session signs out, and nothing is '
        'left remembered', () async {
      final wire = _Wire();
      final (container, store) = await outOfReach(wire);
      final repo = container.read(repositoryProvider);

      wire
        ..down = null
        ..revoked = true;
      await expectLater(
        repo.listItems(),
        throwsA(
          isA<WaxDeckApiException>().having(
            (e) => e.code,
            'code',
            _noSession.code,
          ),
        ),
      );
      await _until(
        () =>
            container.read(authControllerProvider).value?.authenticated ==
            false,
      );

      expect(store.token, isNull);
      expect(store.session, isNull);
      expect(repo.authToken, isNull);
      expect(wire.asked, [
        'GET /auth/session',
        'GET /library/items',
        'GET /auth/session',
      ]);
    });

    test('asks once: answers that come while the read is out ask nothing '
        'more', () async {
      final wire = _Wire();
      final (container, store) = await outOfReach(wire);
      final auth = container.read(authControllerProvider.notifier);
      final repo = container.read(repositoryProvider);

      wire.down = null;
      final reading = wire.held['GET /auth/session'] = Completer<void>();
      await repo.listItems();
      await repo.listItems();
      await pumpEventQueue();
      expect(wire.sessionReads, 2, reason: 'the start\'s, and one');
      expect(auth.unconfirmed, isTrue);

      reading.complete();
      await _until(() => store.token == 'rotated-token');
      expect(wire.sessionReads, 2);
      expect(auth.unconfirmed, isFalse);
    });

    test('asks nothing while a session read is already out, as the one the '
        'socket coming up asks is; when that read gets no answer, the answer '
        'heard meanwhile asks after a second', () async {
      final wire = _Wire();
      final (container, store) = await outOfReach(wire);
      final auth = container.read(authControllerProvider.notifier);
      final repo = container.read(repositoryProvider);

      final lost = _outOfReach.values.first;
      wire.down = (options) =>
          options.uri.path.endsWith('/auth/session') ? lost(options) : null;
      final reading = wire.held['GET /auth/session'] = Completer<void>();
      final read = auth.refreshSession();
      await repo.listItems();
      await repo.listItems();
      await pumpEventQueue();
      expect(wire.sessionReads, 2, reason: 'the start\'s, and the one out');

      wire.held.clear();
      reading.complete();
      expect(await read, SessionRecheck.unanswered);
      await pumpEventQueue();
      expect(auth.unconfirmed, isTrue);
      expect(wire.sessionReads, 2);

      wire.down = null;
      await _until(() => store.token == 'rotated-token');
      expect(wire.sessionReads, 3);
      expect(auth.unconfirmed, isFalse);
    });

    test('that fails with nothing of the server\'s asks nothing', () async {
      final wire = _Wire();
      final (container, _) = await outOfReach(wire);
      final auth = container.read(authControllerProvider.notifier);

      await expectLater(
        container.read(repositoryProvider).listItems(),
        throwsA(isA<WaxDeckApiException>()),
      );
      await pumpEventQueue();

      expect(wire.asked, ['GET /auth/session', 'GET /library/items']);
      expect(auth.unconfirmed, isTrue);
    });

    test('when the session read then gets no answer, the next answer asks '
        'again, a second after', () async {
      final wire = _Wire();
      final (container, store) = await outOfReach(wire);
      final auth = container.read(authControllerProvider.notifier);
      final repo = container.read(repositoryProvider);

      final lost = _outOfReach.values.first;
      wire.down = (options) =>
          options.uri.path.endsWith('/auth/session') ? lost(options) : null;
      await repo.listItems();
      await _until(() => wire.sessionReads == 2);
      await pumpEventQueue();
      expect(auth.unconfirmed, isTrue);
      expect(store.token, 'token-ann');

      wire.down = null;
      await repo.listItems();
      await _until(() => store.token == 'rotated-token');

      expect(auth.unconfirmed, isFalse);
      expect(wire.asked, [
        'GET /auth/session',
        'GET /library/items',
        'GET /auth/session',
        'GET /library/items',
        'GET /auth/session',
        'POST /auth/refresh',
      ]);
    });
  });

  group('what is remembered is what the server last answered', () {
    test('a start the server answers remembers its answer', () async {
      final client = _client(remembered: null);
      client.server.sessionState = _annsNow;
      await pumpEventQueue();

      expect(_session(client), _annsNow);
      expect(_auth(client).unconfirmed, isFalse);
      expect(_remembered(client), _annsNow);
    });

    test('a start the server answers replaces what was remembered', () async {
      final client = _client();
      client.server.sessionState = _annsNow;
      await pumpEventQueue();

      expect(_remembered(client), _annsNow);
    });

    test('a sign-in remembers who signed in, and then the session the '
        'server reads back', () async {
      final client = _client(
        token: null,
        remembered: null,
        server: _Server(session: _nobody)..serverReadOnly = true,
      );
      await pumpEventQueue();
      expect(_session(client), _nobody);
      expect(client.store.session, isNull);

      // The read the sign-in starts is held: what is remembered meanwhile
      // is what the sign-in itself answered.
      final held = client.server.gate = Completer<void>();
      await _auth(client).login(username: 'ben', password: 'pw');
      expect(client.store.token, 'token-ben');
      expect(_remembered(client), _bens);

      client.server.gate = null;
      held.complete();
      await pumpEventQueue();
      expect(
        _remembered(client),
        const SessionState(
          authenticated: true,
          user: _ben,
          serverReadOnly: true,
          sessionId: 'se-ben',
        ),
      );
    });

    test('rights that moved are remembered as they are now', () async {
      final client = _client();
      await pumpEventQueue();
      expect(_remembered(client), _anns);

      client.server.sessionState = _annsNow;
      await _auth(client).refreshSession();
      await pumpEventQueue();

      expect(_remembered(client), _annsNow);
    });
  });

  group('a session opened on from memory, as the server is heard to '
      'answer', () {
    /// Ann's client open on what it remembers, the server out of reach,
    /// over a repository that says its answers.
    (_Client, _Heard) over() {
      final server = _Heard()..sessionError = _lost;
      return (_client(server: server), server);
    }

    void expectUnconfirmed(_Client client, _Heard server) {
      expect(_auth(client).unconfirmed, isTrue);
      expect(server.sessionReads, 1);
      expect(server.onNextAnswer, isNotNull);
    }

    testWidgets('twenty answers while the session read keeps failing make '
        'one read at once and one a second later; an answer after the next '
        'wait asks at once', (tester) async {
      final (client, server) = over();
      await tester.pump(Duration.zero);
      expectUnconfirmed(client, server);

      for (var i = 0; i < 20; i++) {
        server.answer();
        await tester.pump(Duration.zero);
      }
      expect(server.sessionReads, 2);
      await tester.pump(const Duration(milliseconds: 999));
      expect(server.sessionReads, 2);
      await tester.pump(const Duration(milliseconds: 1));
      expect(server.sessionReads, 3, reason: 'for the answers heard since');

      // Nothing was heard since that read: the wait after it ends on
      // nothing.
      await tester.pump(const Duration(seconds: 2));
      expect(server.sessionReads, 3);
      expect(_auth(client).unconfirmed, isTrue);

      server
        ..sessionError = null
        ..answer();
      await tester.pump(Duration.zero);
      expect(server.sessionReads, 4);
      expect(_auth(client).unconfirmed, isFalse);
      expect(server.refreshCalls, 1);
      expect(server.onNextAnswer, isNull);
    });

    testWidgets('the wait between reads the server does not answer '
        'doubles', (tester) async {
      final (client, server) = over();
      await tester.pump(Duration.zero);
      expectUnconfirmed(client, server);

      server.answer();
      await tester.pump(Duration.zero);
      expect(server.sessionReads, 2);
      server.answer();
      await tester.pump(const Duration(seconds: 1));
      expect(server.sessionReads, 3);
      server.answer();
      await tester.pump(const Duration(milliseconds: 1999));
      expect(server.sessionReads, 3);
      await tester.pump(const Duration(milliseconds: 1));
      expect(server.sessionReads, 4);
      server.answer();
      await tester.pump(const Duration(milliseconds: 3999));
      expect(server.sessionReads, 4);
      await tester.pump(const Duration(milliseconds: 1));
      expect(server.sessionReads, 5);

      server
        ..sessionError = null
        ..answer();
      await tester.pump(const Duration(seconds: 8));
      expect(server.sessionReads, 6);
      expect(_auth(client).unconfirmed, isFalse);
    });

    testWidgets('an answer heard while a session read was out asks again, '
        'a second after that read got no answer and with no request '
        'since', (tester) async {
      final (client, server) = over();
      await tester.pump(Duration.zero);
      expectUnconfirmed(client, server);

      // As the socket coming up asks.
      final gate = server.gate = Completer<void>();
      final read = _auth(client).refreshSession();
      server.answer();
      await tester.pump(Duration.zero);
      expect(server.sessionReads, 2);

      server.gate = null;
      gate.complete();
      expect(await read, SessionRecheck.unanswered);
      server.sessionError = null;
      await tester.pump(const Duration(milliseconds: 999));
      expect(server.sessionReads, 2);
      await tester.pump(const Duration(milliseconds: 1));

      expect(server.sessionReads, 3);
      expect(_auth(client).unconfirmed, isFalse);
      expect(server.refreshCalls, 1);
    });

    testWidgets('an answer heard while a session read was out asks again, a '
        'second after that read threw what is no API error to whoever asked '
        'it', (tester) async {
      final (client, server) = over();
      await tester.pump(Duration.zero);
      expectUnconfirmed(client, server);

      // As the socket coming up asks.
      final gate = server.gate = Completer<void>();
      final read = _auth(client).refreshSession();
      server.answer();
      await tester.pump(Duration.zero);
      expect(server.sessionReads, 2);

      server
        ..gate = null
        ..sessionFault = StateError('no session read today');
      gate.complete();
      await expectLater(read, throwsStateError);
      server
        ..sessionFault = null
        ..sessionError = null;
      await tester.pump(const Duration(milliseconds: 999));
      expect(server.sessionReads, 2);
      await tester.pump(const Duration(milliseconds: 1));

      expect(server.sessionReads, 3);
      expect(_auth(client).unconfirmed, isFalse);
      expect(server.refreshCalls, 1);
    });

    /// Ann's client built again, out of reach both times, over a session
    /// read asked of the first build and still out: with that read, and
    /// the gate that holds it.
    Future<(_Client, _Heard, Future<SessionRecheck>, Completer<void>)>
    rebuiltOverARead(WidgetTester tester) async {
      final (client, server) = over();
      await tester.pump(Duration.zero);
      expectUnconfirmed(client, server);
      final auth = _auth(client);

      final gate = server.gate = Completer<void>();
      final read = auth.refreshSession();
      server.gate = null;
      client.container.invalidate(authControllerProvider);
      await tester.pump(Duration.zero);
      expect(auth.unconfirmed, isTrue);
      expect(server.sessionReads, 3, reason: 'each start\'s, and the one out');
      return (client, server, read, gate);
    }

    for (final answered in [true, false]) {
      testWidgets('an answer heard while a session read asked of the build '
          'before was out asks once that read lands, '
          '${answered ? 'answered' : 'unanswered'}', (tester) async {
        final (client, server, read, gate) = await rebuiltOverARead(tester);

        server.answer();
        await tester.pump(Duration.zero);
        expect(server.sessionReads, 3, reason: 'a session read is out');

        if (answered) server.sessionError = null;
        gate.complete();
        expect(await read, SessionRecheck.stands);
        await tester.pump(Duration.zero);

        expect(server.sessionReads, 4);
        expect(_auth(client).unconfirmed, !answered);
        expect(server.refreshCalls, answered ? 1 : 0);

        // Unanswered, the read it asked starts the wait, which ends on
        // nothing heard.
        await tester.pump(const Duration(seconds: 1));
        expect(server.sessionReads, 4);
      });
    }

    testWidgets('and not before the wait after an unanswered read has '
        'ended', (tester) async {
      final (client, server, read, gate) = await rebuiltOverARead(tester);
      final auth = _auth(client);

      expect(await auth.refreshSession(), SessionRecheck.unanswered);
      expect(server.sessionReads, 4);
      server.answer();
      await tester.pump(Duration.zero);

      server.sessionError = null;
      gate.complete();
      expect(await read, SessionRecheck.stands);
      await tester.pump(const Duration(milliseconds: 999));
      expect(server.sessionReads, 4, reason: 'the wait has not ended');
      await tester.pump(const Duration(milliseconds: 1));

      expect(server.sessionReads, 5);
      expect(auth.unconfirmed, isFalse);
    });

    for (final thrown in [false, true]) {
      testWidgets('a session read that ${thrown ? 'throws' : 'is answered'} '
          'after its account signed out asks nothing, whatever was heard '
          'while it was out', (tester) async {
        final (client, server) = over();
        await tester.pump(Duration.zero);
        expectUnconfirmed(client, server);
        final auth = _auth(client);

        final gate = server.gate = Completer<void>();
        final read = auth.refreshSession();
        server.answer();
        await tester.pump(Duration.zero);
        expect(server.sessionReads, 2);

        await auth.signOutLocally();
        server
          ..gate = null
          ..sessionError = null
          ..sessionFault = thrown ? StateError('no session read today') : null;
        gate.complete();
        if (thrown) {
          await expectLater(read, throwsStateError);
        } else {
          expect(await read, SessionRecheck.left);
        }
        await tester.pump(const Duration(minutes: 1));

        expect(server.sessionReads, 2);
        expect(server.onNextAnswer, isNull);
        expect(_session(client), _nobody);
      });
    }

    test('a confirming read that throws what is no API error is reported, '
        'not left uncaught, and counts as one the server did not '
        'answer', () async {
      final reported = <FlutterErrorDetails>[];
      final before = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = before);
      final (client, server) = over();
      await pumpEventQueue();
      expectUnconfirmed(client, server);

      server
        ..sessionFault = StateError('no session read today')
        ..answer();
      await pumpEventQueue();
      expect(reported.single.exception, isStateError);
      expect(server.sessionReads, 2);
      expect(_session(client), _anns);
      expect(_auth(client).unconfirmed, isTrue);

      // The wait runs: an answer inside it asks nothing yet.
      server
        ..sessionFault = null
        ..sessionError = null
        ..answer();
      await pumpEventQueue();
      expect(server.sessionReads, 2);
    });

    test('a rebuild that ends on no session leaves nothing '
        'listening', () async {
      final (client, server) = over();
      await pumpEventQueue();
      expectUnconfirmed(client, server);

      client.store.session = null;
      client.container.invalidate(authControllerProvider);
      await pumpEventQueue();

      expect(_auth(client).unconfirmed, isFalse);
      expect(server.onNextAnswer, isNull);
    });

    testWidgets('a build another replaced while it waited marks nothing '
        'unconfirmed', (tester) async {
      final server = _Heard();
      final gate = server.gate = Completer<void>();
      final client = _client(server: server);
      await tester.pump(const Duration(seconds: 1));
      expect(_session(client), isNull, reason: 'the first build still waits');

      server.gate = null;
      client.container.invalidate(authControllerProvider);
      await tester.pump(Duration.zero);
      expect(_session(client), _anns);
      expect(_auth(client).unconfirmed, isFalse);

      // The first build's wait runs out over its read, still held.
      await tester.pump(kRememberedSessionWait);
      expect(_auth(client).unconfirmed, isFalse);
      expect(server.onNextAnswer, isNull);

      gate.complete();
      await tester.pump(Duration.zero);
      expect(_session(client), _anns);
      expect(server.refreshCalls, 1);
    });

    testWidgets('a build whose wait runs out after another was asked for and '
        'before it began marks nothing unconfirmed', (tester) async {
      final server = _Heard();
      final gate = server.gate = Completer<void>();
      late final _Client client;
      // Made before the build's own, so of the two timers due together it
      // fires first: the rebuild is asked for, the wait runs out, and only
      // then does the rebuild begin.
      Timer(kRememberedSessionWait, () {
        expectSync(
          _session(client),
          isNull,
          reason: 'the wait has not run out',
        );
        server.gate = null;
        client.container.invalidate(authControllerProvider);
      });
      client = _client(server: server);
      final auth = _auth(client);

      await tester.pump(kRememberedSessionWait);
      expect(_session(client), _anns);
      expect(server.sessionReads, 2, reason: 'the next build was answered');
      expect(auth.unconfirmed, isFalse);
      expect(server.onNextAnswer, isNull);

      gate.complete();
      await tester.pump(const Duration(minutes: 1));
      expect(auth.unconfirmed, isFalse);
      expect(server.sessionReads, 2);
      expect(server.refreshCalls, 1);
    });

    testWidgets('a client closed while it waits to ask again leaves '
        'nothing listening and nothing timed', (tester) async {
      final (client, server) = over();
      await tester.pump(Duration.zero);
      expectUnconfirmed(client, server);
      server.answer();
      await tester.pump(Duration.zero);
      expect(server.sessionReads, 2);
      server.answer();

      client.container.dispose();

      expect(server.onNextAnswer, isNull);
      await tester.pump(const Duration(minutes: 1));
      expect(server.sessionReads, 2);
    });
  });

  group('what is remembered is tied to its token', () {
    test('it is kept under a digest of the token, which it never '
        'holds', () async {
      final client = _client(remembered: null);
      await pumpEventQueue();
      final token = client.store.token!;
      final record = client.store.session!;

      expect(token, 'rotated-token');
      expect(record, isNot(contains('token-ann')));
      expect(record, isNot(contains(token)));
      expect(SessionState.fromStored(rememberedFor(token, record)!), _anns);
      expect(rememberedFor('token-ann', record), isNull);
      expect(rememberedFor('token-ben', record), isNull);
    });

    test('it follows the token through a rotation: the next start out of '
        'reach opens on it', () async {
      final first = _client(remembered: null);
      await pumpEventQueue();
      expect(first.store.token, 'rotated-token');

      final next = _client(
        store: first.store,
        planted: false,
        server: _Server()..sessionError = _lost,
      );
      await pumpEventQueue();

      expect(_session(next), _anns);
      expect(_auth(next).unconfirmed, isTrue);
    });

    test('a session remembered for another token is not offered', () async {
      final client = _client(token: 'token-ben');
      client.server.sessionError = _lost;
      await pumpEventQueue();

      expect(_session(client), isNull);
      expect(_auth(client).unconfirmed, isFalse);
      expect(client.store.token, 'token-ben');
    });

    test('a session two failed writes left beside the next account\'s '
        'token is not offered', () async {
      final store = _Faulty();
      final first = _client(store: store);
      await pumpEventQueue();
      expect(_session(first), _anns);

      // Ann signs out, and the clear of what is remembered fails.
      store.sessionClearsFail = true;
      await _auth(first).signOutLocally();
      expect(store.token, isNull);
      expect(store.session, isNotNull);

      // Ben signs in, and the write of what is remembered fails.
      store
        ..sessionClearsFail = false
        ..sessionWritesFail = true;
      await _auth(first).login(username: 'ben', password: 'pw');
      await pumpEventQueue();
      expect(store.token, 'token-ben');
      expect(store.session, isNotNull, reason: 'Ann\'s, still');

      final next = _client(
        store: store,
        planted: false,
        server: _Server()..sessionError = _lost,
      );
      await pumpEventQueue();

      expect(_session(next), isNull);
      expect(_auth(next).unconfirmed, isFalse);
    });
  });

  group('what is remembered goes where the token goes', () {
    Future<_Client> signedIn() async {
      final client = _client();
      await pumpEventQueue();
      expect(_session(client), _anns);
      expect(client.store.session, isNotNull);
      return client;
    }

    test('a sign-out', () async {
      final client = await signedIn();
      await _auth(client).logout();

      expect(client.store.token, isNull);
      expect(client.store.session, isNull);
    });

    test('a sign-out the server never hears of', () async {
      final client = await _startedOutOfReach();
      await _auth(client).signOutLocally();

      expect(client.store.token, isNull);
      expect(client.store.session, isNull);
      expect(_auth(client).unconfirmed, isFalse);
    });

    test('forgetting the server', () async {
      final client = await signedIn();
      client.store.serverAddress = 'http://server.test';
      await client.container.read(forgetServerProvider)();
      await pumpEventQueue();

      expect(client.store.token, isNull);
      expect(client.store.session, isNull);
      expect(client.store.serverAddress, isNull);
    });

    test('adopting another server', () async {
      final client = await signedIn();
      await client.container
          .read(serverAddressProvider.notifier)
          .adopt('http://other.test');

      expect(client.store.token, isNull);
      expect(client.store.session, isNull);
    });

    test('a rotation the server refuses for want of a session', () async {
      final client = _client();
      client.server.refreshError = const WaxDeckApiException(
        code: 'unauthenticated',
        message: 'session revoked',
        statusCode: 401,
      );
      await pumpEventQueue();

      expect(_session(client), _nobody);
      expect(client.store.token, isNull);
      expect(client.store.session, isNull);
    });
  });

  test('a token rotation that lands after its client was closed is still '
      'stored, with what is remembered', () async {
    final client = _client();
    final gate = client.server.rotationGate = Completer<void>();
    await pumpEventQueue();
    expect(client.server.refreshCalls, 1);
    client.container.dispose();

    gate.complete();
    await pumpEventQueue();

    expect(client.store.token, 'rotated-token');
    expect(_remembered(client), _anns);
  });

  test('a rotated token the client did not take up is not stored', () async {
    final client = _client(server: _Server()..takesRotations = false);
    await pumpEventQueue();

    expect(client.server.refreshCalls, 1);
    expect(_session(client), _anns);
    expect(client.server.authToken, 'token-ann');
    expect(client.store.token, 'token-ann');
    expect(_remembered(client), _anns);
  });

  test('a rebuild while a rotation is out asks no second one: the client, '
      'the store and what is remembered end on the one token, signed '
      'in', () async {
    final client = _client();
    final gate = client.server.rotationGate = Completer<void>();
    await pumpEventQueue();
    expect(client.server.refreshCalls, 1);

    client.container.invalidate(authControllerProvider);
    await pumpEventQueue();
    expect(_session(client), _anns);
    expect(client.server.refreshCalls, 1);

    gate.complete();
    await pumpEventQueue();
    expect(client.server.refreshCalls, 1);
    expect(client.server.authToken, 'rotated-token');
    expect(client.store.token, 'rotated-token');
    expect(_remembered(client), _anns);
    expect(_session(client), _anns);
  });

  test('a rebuild whose read of the stored token is out as a rotation lands '
      'waits for that rotation: the client, the store and what is remembered '
      'end on its token, signed in', () async {
    final store = _SlowStore();
    final client = _client(store: store);
    final rotation = client.server.rotationGate = Completer<void>();
    await pumpEventQueue();
    expect(client.server.refreshCalls, 1);

    // The rebuild asks the store what it holds, and is not told yet.
    final reads = store.reads = Completer<void>();
    final writes = store.writes = Completer<void>();
    client.container.invalidate(authControllerProvider);
    await pumpEventQueue();
    // The rotation lands meanwhile, and its token is slow to be stored:
    // slower than the session read of a build that did not wait.
    rotation.complete();
    await pumpEventQueue();
    store.reads = null;
    reads.complete();
    await pumpEventQueue();
    store.writes = null;
    writes.complete();
    await pumpEventQueue();

    expect(client.server.refreshCalls, 1);
    expect(client.server.authToken, 'rotated-token');
    expect(client.store.token, 'rotated-token');
    expect(_remembered(client), _anns);
    expect(_session(client), _anns);
  });

  test('a rotation that fails while a rebuild waits for it is raised as it '
      'is with nobody waiting, and the rebuild goes on', () async {
    final store = _SlowStore();
    final uncaught = <Object>[];
    late final _Client client;
    late final Zone zone;
    runZonedGuarded(() {
      zone = Zone.current;
      client = _client(store: store);
    }, (error, _) => uncaught.add(error));
    final rotation = client.server.rotationGate = Completer<void>();
    await pumpEventQueue();
    expect(client.server.refreshCalls, 1);

    zone.run(() => client.container.invalidate(authControllerProvider));
    await pumpEventQueue();
    store.writeFault = StateError('the keystore is locked');
    rotation.complete();
    await pumpEventQueue();

    expect(uncaught.single, isStateError);
    final state = client.container.read(authControllerProvider);
    expect(state.hasError, isFalse);
    expect(state.isLoading, isFalse);
    expect(state.value, _anns);
  });

  group('a start overtaken before its answer came', () {
    /// Ann's client, its first start still waiting on its session read
    /// behind the gate, and a second start answered meanwhile.
    Future<(_Client, Completer<void>)> startedAgain({
      required bool remembering,
    }) async {
      final client = _client(remembered: remembering ? _anns : null);
      final gate = client.server.gate = Completer<void>();
      await pumpEventQueue();
      expect(_session(client), isNull, reason: 'the first start still waits');

      client.server.gate = null;
      client.container.invalidate(authControllerProvider);
      await pumpEventQueue();
      expect(_session(client), _anns);
      expect(client.server.refreshCalls, 1);
      expect(client.store.token, 'rotated-token');
      return (client, gate);
    }

    void expectAsTheSecondLeftIt(_Client client) {
      expect(_session(client), _anns);
      expect(client.server.refreshCalls, 1);
      expect(client.server.authToken, 'rotated-token');
      expect(client.store.token, 'rotated-token');
      expect(_remembered(client), _anns);
    }

    for (final remembering in [true, false]) {
      final having = remembering
          ? 'with a session remembered'
          : 'with none remembered';

      test('by another start, $having, and then answered a live session, '
          'asks no rotation', () async {
        final (client, gate) = await startedAgain(remembering: remembering);

        gate.complete();
        await pumpEventQueue();

        expectAsTheSecondLeftIt(client);
      });

      test('by another start, $having, and then answered that its token is '
          'dead, clears nothing', () async {
        final (client, gate) = await startedAgain(remembering: remembering);

        // Its read went out with the token since rotated away.
        client.server.sessionState = _nobody;
        gate.complete();
        await pumpEventQueue();

        expectAsTheSecondLeftIt(client);
        expect(await client.disk.load(), isNotNull);
      });
    }

    for (final dead in [false, true]) {
      test('by a sign-in, and then answered '
          '${dead ? 'that its token is dead' : 'a live session'}, leaves the '
          'account that signed in its token and its session', () async {
        final client = _client();
        final gate = client.server.gate = Completer<void>();
        await pumpEventQueue();
        client.server.gate = null;
        await _auth(client).login(username: 'ben', password: 'pw');
        await pumpEventQueue();
        expect(_session(client), _bens);

        // The start's read answers for the token it went out with: Ann's.
        if (dead) {
          client.server.sessionError = _noSession;
        } else {
          client.server.sessionState = _anns;
        }
        gate.complete();
        await pumpEventQueue();

        expect(_session(client), _bens);
        expect(client.server.authToken, 'token-ben');
        expect(client.store.token, 'token-ben');
        expect(_remembered(client), _bens);
        expect(client.server.refreshCalls, 0);
      });
    }

    test('by a sign-in while it asked the store for the token, does not put '
        'the token it finds there in the place of that account\'s', () async {
      final store = _SlowStore();
      final reads = store.reads = Completer<void>();
      final client = _client(store: store);
      await pumpEventQueue();
      expect(store.waiting, 1);

      store.reads = null;
      await _auth(client).login(username: 'ben', password: 'pw');
      await pumpEventQueue();
      expect(_session(client), _bens);

      reads.complete();
      await pumpEventQueue();

      expect(client.server.authToken, 'token-ben');
      expect(client.store.token, 'token-ben');
      expect(_session(client), _bens);
      expect(_remembered(client), _bens);
    });

    test('by a sign-in still on its way, answers signed out until that '
        'sign-in lands, and the account that signed in stands', () async {
      final store = _SlowStore();
      final client = _client(store: store);
      final gate = client.server.gate = Completer<void>();
      await pumpEventQueue();

      // The sign-in is answered, and its token is slow to be stored.
      client.server.gate = null;
      final writes = store.writes = Completer<void>();
      final signingIn = _auth(client).login(username: 'ben', password: 'pw');
      await pumpEventQueue();
      expect(_session(client), isNull, reason: 'neither has landed');

      // The start's read answers for the token it went out with: Ann's.
      client.server.sessionState = _anns;
      gate.complete();
      await pumpEventQueue();
      expect(_session(client), _nobody);
      expect(client.server.refreshCalls, 0);
      expect(client.server.authToken, 'token-ben');

      client.server.sessionState = _bens;
      store.writes = null;
      writes.complete();
      await signingIn;
      await pumpEventQueue();

      expect(_session(client), _bens);
      expect(client.store.token, 'token-ben');
      expect(_remembered(client), _bens);
      expect(client.server.refreshCalls, 0);
    });

    test('by a sign-in while the store cleared its dead token, forgets '
        'nothing of the account that signed in', () async {
      final store = _SlowStore();
      final clears = store.clears = Completer<void>();
      final client = _client(
        server: _Server(session: _nobody),
        store: store,
      );
      await pumpEventQueue();
      expect(store.token, isNull, reason: 'the clear is asked, and held');
      expect(_session(client), isNull);

      await _auth(client).login(username: 'ben', password: 'pw');
      await pumpEventQueue();
      expect(_session(client), _bens);

      store.clears = null;
      clears.complete();
      await pumpEventQueue();

      expect(_session(client), _bens);
      expect(client.server.authToken, 'token-ben');
      expect(client.store.token, 'token-ben');
      expect(_remembered(client), _bens);
      expect(await client.disk.load(), isNotNull);
      expect(client.container.read(playbackHeldProvider), isFalse);
    });

    test('by a sign-in while what its dead token left was forgotten, does '
        'not answer signed out over the account that signed in', () async {
      final artwork = _HeldArtwork();
      final client = _client(
        server: _Server(session: _nobody),
        artwork: artwork,
      );
      await artwork.reached;

      await _auth(client).login(username: 'ben', password: 'pw');
      await pumpEventQueue();
      expect(_session(client), _bens);

      artwork.gate.complete();
      await pumpEventQueue();

      expect(_session(client), _bens);
      expect(client.server.authToken, 'token-ben');
      expect(client.store.token, 'token-ben');
      expect(_remembered(client), _bens);
      expect(client.container.read(playbackHeldProvider), isFalse);
    });
  });

  group('a start whose client is closed before its answer comes', () {
    void expectUntouched(_Heard server, _Recorded store) {
      expect(server.onNextAnswer, isNull);
      expect(server.refreshCalls, 0);
      expect(server.authToken, 'token-ann');
      expect(store.calls, ['readToken', 'readSession']);
      expect(store.token, 'token-ann');
      expect(store.session, isNotNull);
    }

    final landings = <String, void Function(_Heard)>{
      'given no answer': (server) => server.sessionError = _lost,
      'answered a live session': (_) {},
      'answered that its token is dead': (server) =>
          server.sessionState = _nobody,
    };
    for (final MapEntry(key: what, value: land) in landings.entries) {
      test('and is then $what, marks nothing, arms nothing, writes nothing '
          'and forgets nothing', () async {
        final reported = <FlutterErrorDetails>[];
        final before = FlutterError.onError;
        FlutterError.onError = reported.add;
        addTearDown(() => FlutterError.onError = before);
        final server = _Heard();
        final gate = server.gate = Completer<void>();
        final store = _Recorded();
        final client = _client(server: server, store: store);
        final auth = _auth(client);
        await pumpEventQueue();
        client.container.dispose();

        land(server);
        server.gate = null;
        gate.complete();
        await pumpEventQueue();

        expect(auth.unconfirmed, isFalse);
        expectUntouched(server, store);
        expect(await client.disk.load(), isNotNull);
        expect(reported, isEmpty);
      });
    }

    testWidgets('while it waits out its bound, marks nothing and arms '
        'nothing when the bound ends', (tester) async {
      final server = _Heard();
      final gate = server.gate = Completer<void>();
      final store = _Recorded();
      final client = _client(server: server, store: store);
      final auth = _auth(client);
      await tester.pump(const Duration(seconds: 1));
      client.container.dispose();

      await tester.pump(kRememberedSessionWait);
      expect(auth.unconfirmed, isFalse);
      expectUntouched(server, store);

      server.gate = null;
      gate.complete();
      await tester.pump(const Duration(minutes: 1));
      expect(auth.unconfirmed, isFalse);
      expect(server.sessionReads, 1);
      expectUntouched(server, store);
    });
  });

  group('a token rotation that lands after its account left', () {
    Future<(_Client, Completer<void>)> rotating() async {
      final client = _client();
      final gate = client.server.rotationGate = Completer<void>();
      await pumpEventQueue();
      expect(_session(client), _anns);
      expect(client.server.refreshCalls, 1);
      return (client, gate);
    }

    test('stores nothing once the account signed out', () async {
      final (client, gate) = await rotating();
      await _auth(client).signOutLocally();

      gate.complete();
      await pumpEventQueue();

      expect(client.store.token, isNull);
      expect(client.server.authToken, isNull);
      expect(client.store.session, isNull);
    });

    test('leaves the token of the account that signed in since', () async {
      final (client, gate) = await rotating();
      await _auth(client).signOutLocally();
      await _auth(client).login(username: 'ben', password: 'pw');
      await pumpEventQueue();

      gate.complete();
      await pumpEventQueue();

      expect(client.store.token, 'token-ben');
      expect(client.server.authToken, 'token-ben');
      expect(_remembered(client), _bens);
    });

    test('and is refused signs out nobody who signed in since', () async {
      final (client, gate) = await rotating();
      await _auth(client).signOutLocally();
      await _auth(client).login(username: 'ben', password: 'pw');
      await pumpEventQueue();

      // Ann's session is gone, so the server refuses her rotation.
      client.server.refreshError = const WaxDeckApiException(
        code: 'unauthenticated',
        message: 'session revoked',
        statusCode: 401,
      );
      gate.complete();
      await pumpEventQueue();

      expect(_session(client)?.user?.id, _ben.id);
      expect(client.store.token, 'token-ben');
    });
  });

  test('a token rotation that lands after its account left is nobody\'s '
      'bearer on the repository the other suites share, as on the '
      'client', () async {
    final repo = FakeRepository(sessionState: _anns);
    final gate = repo.refreshGate = Completer<void>();
    final store = InMemoryCredentialStore()..token = 'token-ann';
    final container = appContainer(
      repo: repo,
      credentials: store,
      settings: MemoryClientSettingsStore(),
      extra: [
        queueStoreProvider.overrideWithValue(_Disk()),
        queueSaveDebounceProvider.overrideWithValue(Duration.zero),
      ],
    );
    final watched = container.listen(authControllerProvider, (_, _) {});
    addTearDown(watched.close);
    await pumpEventQueue();
    expect(repo.refreshCalls, 1);
    expect(repo.authToken, 'token-ann');

    await container.read(authControllerProvider.notifier).signOutLocally();
    gate.complete();
    await pumpEventQueue();

    expect(repo.authToken, isNull);
    expect(store.token, isNull);
    expect(
      container.read(authControllerProvider).value,
      const SessionState(authenticated: false),
    );
  });

  test('on that repository, as on the client, a rotation out across a '
      'sign-out and a sign-in is not taken up, though the sign-in minted '
      'the very token it was asked with', () async {
    final repo = FakeRepository(sessionState: _anns);
    final gate = repo.refreshGate = Completer<void>();
    final store = InMemoryCredentialStore()..token = 'test-token';
    final container = appContainer(
      repo: repo,
      credentials: store,
      settings: MemoryClientSettingsStore(),
      extra: [
        queueStoreProvider.overrideWithValue(_Disk()),
        queueSaveDebounceProvider.overrideWithValue(Duration.zero),
      ],
    );
    final watched = container.listen(authControllerProvider, (_, _) {});
    addTearDown(watched.close);
    await pumpEventQueue();
    expect(repo.refreshCalls, 1);

    final auth = container.read(authControllerProvider.notifier);
    await auth.signOutLocally();
    await auth.login(username: 'admin', password: 'pw');
    await pumpEventQueue();
    expect(repo.authToken, 'test-token');
    final signedIn = container.read(authControllerProvider).value;
    expect(signedIn?.user?.username, 'admin');

    gate.complete();
    await pumpEventQueue();

    expect(repo.authToken, 'test-token');
    expect(store.token, 'test-token');
    expect(container.read(authControllerProvider).value, signedIn);
    expect(repo.refreshCalls, 1);
  });

  group('a token rotation out while its token turned out to be another '
      'account\'s', () {
    /// A client whose token the server came to answer Ben for while its
    /// rotation was out: the account moved, the token did not.
    Future<(_Client, Completer<void>)> swapped(
      InMemoryCredentialStore store,
    ) async {
      final client = _client(store: store);
      final gate = client.server.rotationGate = Completer<void>();
      await pumpEventQueue();
      expect(_session(client), _anns);
      expect(client.server.refreshCalls, 1);

      client.server.sessionState = _bens;
      expect(await _auth(client).refreshSession(), SessionRecheck.left);
      await pumpEventQueue();
      expect(_session(client), _bens);
      expect(client.store.token, 'token-ann');
      return (client, gate);
    }

    test('is stored: the token it rotated is still the one held', () async {
      final (client, gate) = await swapped(InMemoryCredentialStore());

      gate.complete();
      await pumpEventQueue();

      expect(client.store.token, 'rotated-token');
      expect(client.server.authToken, 'rotated-token');
      expect(_session(client), _bens);
      expect(_remembered(client), _bens);
    });

    test('stores nothing when the account signs out while the store is '
        'asked what it holds', () async {
      final store = _SlowStore();
      final (client, gate) = await swapped(store);

      final reads = store.reads = Completer<void>();
      gate.complete();
      await _until(() => store.waiting == 1);
      await _auth(client).signOutLocally();
      reads.complete();
      await pumpEventQueue();

      expect(client.store.token, isNull);
      expect(client.store.session, isNull);
      expect(client.server.authToken, isNull);
    });
  });

  group('a session held without a token, as a browser\'s cookie is', () {
    test('reads nothing remembered and remembers nothing', () async {
      final store = _Recorded();
      final client = _client(token: null, remembered: null, store: store);
      // Whatever the store holds, it is not this session's.
      store.session = rememberedRecord('token-ben', _bens.toStored());
      await pumpEventQueue();
      expect(_session(client), _anns);

      client.server.sessionState = _annsNow;
      expect(await _auth(client).refreshSession(), SessionRecheck.stands);
      await pumpEventQueue();

      expect(store.calls, ['readToken']);
      expect(client.server.refreshCalls, 0);
    });

    test('is not opened from what is remembered when the server is out of '
        'reach', () async {
      final store = _Recorded();
      final client = _client(token: null, remembered: null, store: store);
      store.session = rememberedRecord('token-ann', _anns.toStored());
      client.server.sessionError = _lost;
      await pumpEventQueue();

      expect(_session(client), isNull);
      expect(store.calls, ['readToken']);
    });
  });
}
