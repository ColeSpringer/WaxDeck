import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_store.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/settings/prefs_controller.dart';
import 'package:waxdeck/src/sync/session_doubt.dart';
import 'package:waxdeck/src/sync/sync_binder.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import 'app_host.dart';
import 'fakes.dart';

/// What the native sync engine hears about the session reaches the
/// session: the engine says, the controller reads, the server decides.

const _ann = WaxDeckUser(id: 'us-ann', username: 'ann', roles: ['user']);

const _lost = WaxDeckApiException(
  code: 'transport',
  message: 'connection refused',
);

/// A server that can refuse the sync walk for want of a session, and
/// records the session reads and sync calls made of it, in order.
class _Server extends FakeRepository {
  _Server()
    : super(sessionState: const SessionState(authenticated: true, user: _ann));

  /// `session`, `catalog`, `server`, `removed`; a refused sync call ends
  /// in `!`.
  final calls = <String>[];

  int get sessionReads => calls.where((call) => call == 'session').length;

  /// Refuses every sync call while set.
  bool refusing = false;

  /// Refuses this many sync calls more.
  int refusals = 0;

  /// What a session read fails with, while set.
  WaxDeckApiException? sessionError;

  static const _refused = WaxDeckApiException(
    code: 'unauthenticated',
    message: 'no valid session or token was presented',
    statusCode: 401,
  );

  void _sync(String call) {
    if (refusing || refusals > 0) {
      if (refusals > 0) refusals--;
      calls.add('$call!');
      throw _refused;
    }
    calls.add(call);
  }

  /// A session decoded afresh, as the real client's every read is.
  @override
  Future<SessionState> getSession() async {
    calls.add('session');
    if (sessionError case final error?) throw error;
    final read = await super.getSession();
    final user = read.user;
    return SessionState(
      authenticated: read.authenticated,
      serverReadOnly: read.serverReadOnly,
      user: user == null
          ? null
          : WaxDeckUser(
              id: user.id,
              username: user.username,
              roles: [...user.roles],
            ),
    );
  }

  @override
  Future<Prefs> getPrefs() {
    calls.add('prefs');
    return super.getPrefs();
  }

  @override
  Future<CatalogSyncPage> syncCatalog({
    String? since,
    String? cursor,
    int? limit,
  }) async {
    _sync('catalog');
    return super.syncCatalog(since: since, cursor: cursor, limit: limit);
  }

  @override
  Future<ServerSyncPage> syncServer({String? since, int? limit}) async {
    _sync('server');
    return super.syncServer(since: since, limit: limit);
  }

  /// Refuses this many removed-checks more, the question a walk puts last.
  int questionRefusals = 0;

  @override
  Future<List<String>> syncCatalogRemoved(List<String> pids) async {
    if (questionRefusals > 0) {
      questionRefusals--;
      calls.add('removed!');
      throw _refused;
    }
    calls.add('removed');
    return super.syncCatalogRemoved(pids);
  }
}

typedef _Session = ({
  ProviderContainer container,
  _Server server,
  SyncEngine engine,
  FakeLink link,
  void Function() leave,
});

/// Artwork whose wipe waits on [gate]: a sign-out's cleanup is held there,
/// before the session flips.
class _HeldArtwork extends FakeArtworkStore {
  final gate = Completer<void>();
  final _reached = Completer<void>();

  /// How many cleanups reached the wipe.
  var wipes = 0;

  Future<void> get reached => _reached.future;

  @override
  Future<void> forgetEverything() async {
    wipes++;
    if (!_reached.isCompleted) _reached.complete();
    await gate.future;
    await super.forgetEverything();
  }
}

/// A socket over [FakeLink] whose close waits on [_gate]: a real one can
/// take longer to close than the request that failed takes to answer.
class _SlowToClose extends EventsChannel {
  _SlowToClose(this._inner, this._gate)
    : super(
        url: _inner.url,
        authToken: null,
        onFrame: _inner.onFrame,
        onDone: _inner.onDone,
        subscribe: _inner.subscribe,
      );

  final EventsChannel _inner;
  final Future<void> _gate;

  @override
  Future<void> connect() => _inner.connect();

  @override
  int? get closeCode => _inner.closeCode;

  @override
  bool send(String frame) => _inner.send(frame);

  @override
  Future<void> close() async {
    await _gate;
    await _inner.close();
  }
}

/// Ann, or the [session] given, signed in on a native client, the sync
/// binder running over a real engine whose socket is up on [FakeLink],
/// each closing only once [closing] completes when it is given. The binder
/// goes once the session shows signed out, as the router's signed-in scope
/// takes it, or when the test calls `leave`. Given a [tester], it runs on
/// the tester's fake clock.
Future<_Session> _signedIn({
  ArtworkStore? artwork,
  SessionState? session,
  Future<void>? closing,
  WidgetTester? tester,
}) async {
  final db = inMemoryMirrorDatabase();
  addTearDown(db.close);
  final downloads = FakeDownloads();
  addTearDown(downloads.dispose);
  final server = _Server();
  if (session != null) server.sessionState = session;
  final link = FakeLink();
  final engine = SyncEngine(
    db: db,
    repository: server,
    channelFactory: closing == null
        ? link.factory
        : ({required onFrame, required onDone, required subscribe}) =>
              _SlowToClose(
                link.factory(
                  onFrame: onFrame,
                  onDone: onDone,
                  subscribe: subscribe,
                ),
                closing,
              ),
  );
  addTearDown(engine.dispose);
  final container = appContainer(
    repo: server,
    downloads: downloads,
    artwork: artwork,
    sync: engine,
    mirror: db,
  );
  await container.read(authControllerProvider.future);
  final alive = container.listen(syncBinderProvider, (_, _) {});
  addTearDown(alive.close);
  final scope = container.listen(authControllerProvider, (_, next) {
    if (next.value?.authenticated == false) alive.close();
  });
  addTearDown(scope.close);
  await (tester?.pump(Duration.zero) ?? pumpEventQueue());
  // Behind the first sync the connect started, which is serialized.
  await engine.beforeSync(() async {});
  expect(engine.current.online, isTrue);
  return (
    container: container,
    server: server,
    engine: engine,
    link: link,
    leave: alive.close,
  );
}

bool _signedOut(ProviderContainer container) =>
    container.read(authControllerProvider).value?.authenticated == false;

/// Until [settled] holds, for at most two seconds.
Future<void> _until(bool Function() settled) async {
  for (var i = 0; i < 200 && !settled(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(settled(), isTrue, reason: 'did not settle');
}

/// What an earlier sync could not get answered, which every walk puts
/// again as its last question: whether the server can put back a track
/// the device holds a download of and the mirror does not list.
Future<void> _questionWaits(_Session s) async {
  const pid = 'tr-01JZX5N8QW3F4V9T2B7KDGONE1';
  final db = s.engine.db;
  await db
      .into(db.downloadRecords)
      .insert(
        DownloadRecordsCompanion.insert(
          pid: pid,
          fileIndex: 0,
          essenceHash: 'e',
          etag: 'x',
          fileName: 'gone.mp3',
          localPath: '/downloads/gone.mp3',
          sizeBytes: 1024,
          state: 'complete',
          server: Value(s.server.baseUrl),
        ),
      );
  await db
      .into(db.clientSettings)
      .insert(
        ClientSettingsCompanion.insert(
          key: 'waxdeck.sync.removedUnanswered',
          value: jsonEncode([pid]),
        ),
      );
}

/// Steps the fake clock through [waits], in seconds: one more attempt on
/// [s]'s link at the end of each, and none a moment before it.
Future<void> _restartsAfter(
  WidgetTester tester,
  _Session s,
  List<int> waits,
) async {
  const justBefore = Duration(milliseconds: 1);
  for (final wait in waits) {
    final made = s.link.attempts.length;
    await tester.pump(Duration(seconds: wait) - justBefore);
    expect(s.link.attempts.length, made, reason: 'not before $wait s');
    await tester.pump(justBefore);
    expect(s.link.attempts.length, made + 1, reason: 'after $wait s');
  }
}

/// Ends a session on the fake clock inside its test, which fails on a
/// timer left pending: the restart, the reconnect, the session reads.
Future<void> _end(WidgetTester tester, _Session s) async {
  s.leave();
  s.container.dispose();
  await tester.pump(Duration.zero);
}

/// Session reads answering [answer], held on [gate] while one is set.
class _Reads {
  SessionRecheck answer = SessionRecheck.unanswered;
  Completer<void>? gate;
  var made = 0;

  Future<SessionRecheck> call() async {
    made++;
    final answer = this.answer;
    await gate?.future;
    return answer;
  }
}

void main() {
  group('a session in doubt', () {
    testWidgets('a read the server did not answer is asked again after 1 s, '
        '2 s and 4 s, and never further apart than a minute', (tester) async {
      final reads = _Reads();
      final doubt = SessionDoubt(read: reads.call);

      doubt.ask().ignore();
      await tester.pump();
      expect(reads.made, 1);

      const justBefore = Duration(milliseconds: 1);
      for (final (wait, made) in const [
        (1, 2),
        (2, 3),
        (4, 4),
        (8, 5),
        (16, 6),
        (32, 7),
        (60, 8),
        (60, 9),
      ]) {
        await tester.pump(Duration(seconds: wait) - justBefore);
        expect(reads.made, made - 1, reason: 'not before $wait s');
        await tester.pump(justBefore);
        expect(reads.made, made, reason: 'after $wait s');
      }
      doubt.dispose();
    });

    testWidgets('an answered read ends the asking, and a later doubt starts '
        'from a second again', (tester) async {
      final reads = _Reads();
      var stood = 0;
      final doubt = SessionDoubt(read: reads.call)..onStands = () => stood++;

      doubt.ask().ignore();
      await tester.pump();
      reads.answer = SessionRecheck.stands;
      await tester.pump(const Duration(seconds: 1));
      expect(reads.made, 2);
      expect(stood, 1);

      await tester.pump(const Duration(minutes: 10));
      expect(reads.made, 2, reason: 'the server answered');

      reads.answer = SessionRecheck.unanswered;
      doubt.ask().ignore();
      await tester.pump(const Duration(seconds: 1));
      expect(reads.made, 4);
      doubt.dispose();
    });

    testWidgets('no read is made while another is out: an ask joins it, and '
        'one while it waits to ask again reads at once', (tester) async {
      final reads = _Reads()..gate = Completer<void>();
      final doubt = SessionDoubt(read: reads.call);

      final answers = <SessionRecheck>[];
      doubt.ask().then(answers.add).ignore();
      doubt.ask().then(answers.add).ignore();
      await tester.pump(const Duration(seconds: 5));
      expect(reads.made, 1, reason: 'one read, however long it takes');

      reads.gate!.complete();
      reads.gate = null;
      await tester.pump();
      expect(answers, [SessionRecheck.unanswered, SessionRecheck.unanswered]);

      // A second away from asking again, something else says the session
      // is in doubt: it is read now, and the next wait is the longer one.
      await tester.pump(const Duration(milliseconds: 500));
      doubt.ask().ignore();
      await tester.pump();
      expect(reads.made, 2);
      await tester.pump(const Duration(milliseconds: 1999));
      expect(reads.made, 2);
      await tester.pump(const Duration(milliseconds: 1));
      expect(reads.made, 3);
      doubt.dispose();
    });

    testWidgets('the account leaving ends the asking for good', (tester) async {
      final reads = _Reads()..answer = SessionRecheck.left;
      final doubt = SessionDoubt(read: reads.call);

      doubt.ask().ignore();
      await tester.pump();
      final answers = <SessionRecheck>[];
      doubt.ask().then(answers.add).ignore();
      await tester.pump(const Duration(minutes: 10));

      expect(reads.made, 1);
      expect(answers, [SessionRecheck.left]);
      doubt.dispose();
    });

    testWidgets('a read that throws before it is under way is no answer: it '
        'is asked again, and an ask after reads again', (tester) async {
      var made = 0;
      final doubt = SessionDoubt(
        read: () {
          made++;
          throw StateError('no client to read with');
        },
      );

      final answers = <SessionRecheck>[];
      doubt.ask().then(answers.add).ignore();
      await tester.pump();
      expect(made, 1);
      expect(answers, [SessionRecheck.unanswered]);

      await tester.pump(const Duration(seconds: 1));
      expect(made, 2, reason: 'asked again a second later');

      doubt.ask().ignore();
      await tester.pump();
      expect(made, 3, reason: 'a later ask reads again');
      doubt.dispose();
    });

    testWidgets('disposed, it asks no more', (tester) async {
      final reads = _Reads();
      final doubt = SessionDoubt(read: reads.call);

      doubt.ask().ignore();
      await tester.pump();
      doubt.dispose();
      await tester.pump(const Duration(minutes: 10));
      final answers = <SessionRecheck>[];
      doubt.ask().then(answers.add).ignore();
      await tester.pump();

      expect(reads.made, 1);
      expect(answers, [SessionRecheck.left], reason: 'its session is over');
    });
  });

  test('a client that holds no session is not asked about one', () async {
    // The binder mounted over a client signed out, as a test of something
    // else may mount it, on a link that never comes up.
    final db = inMemoryMirrorDatabase();
    addTearDown(db.close);
    final downloads = FakeDownloads();
    addTearDown(downloads.dispose);
    final server = _Server()
      ..sessionState = const SessionState(authenticated: false);
    final engine = SyncEngine(
      db: db,
      repository: server,
      channelFactory: deadChannelFactory(),
    );
    addTearDown(engine.dispose);
    final container = appContainer(
      repo: server,
      downloads: downloads,
      sync: engine,
      mirror: db,
    );
    await container.read(authControllerProvider.future);
    final reads = server.sessionReads;

    final alive = container.listen(syncBinderProvider, (_, _) {});
    addTearDown(alive.close);
    await pumpEventQueue();
    expect(engine.started, isTrue);

    // The server refuses the walk for want of a session.
    server.refusing = true;
    await engine.reconcile();
    await pumpEventQueue();

    expect(server.sessionReads, reads);
  });

  test('a sync the server refuses for want of a session reads the session, '
      'and the server\'s answer signs out', () async {
    final s = await _signedIn();
    final reads = s.server.sessionReads;

    // This device was revoked: the server answers its sync with a 401
    // and its session read with no session.
    s.server
      ..refusing = true
      ..sessionState = const SessionState(authenticated: false);
    await s.engine.reconcile();
    await pumpEventQueue();

    expect(s.server.sessionReads, reads + 1);
    expect(_signedOut(s.container), isTrue);
  });

  test('a socket the server closes as ended reads the session, and the '
      'server\'s answer signs out', () async {
    final s = await _signedIn();
    final reads = s.server.sessionReads;

    s.server.sessionState = const SessionState(authenticated: false);
    s.link.reachable = false;
    s.link.attempts.last.drop(sessionEndedCloseCode);
    await pumpEventQueue();

    expect(s.server.sessionReads, reads + 1);
    expect(_signedOut(s.container), isTrue);
  });

  group('a session that ended while the socket was down', () {
    test('a reconnect the server refuses for want of a session reads it; '
        'its answer signs out and the reconnecting stops', () async {
      final s = await _signedIn();
      final reads = s.server.sessionReads;

      s.server.sessionState = const SessionState(authenticated: false);
      s.link.refusal = const UpgradeRefused(401);
      s.link.attempts.last.drop(null);
      await pumpEventQueue();
      expect(s.server.sessionReads, reads, reason: 'a drop says nothing');

      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(s.server.sessionReads, reads + 1);
      expect(_signedOut(s.container), isTrue);
      expect(s.engine.started, isFalse);
      final attempts = s.link.attempts.length;
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      expect(s.link.attempts, hasLength(attempts));
    });

    test('a reconnect that reaches nobody reads nothing, and the '
        'reconnecting goes on', () async {
      final s = await _signedIn();
      final reads = s.server.sessionReads;

      s.link.reachable = false;
      s.link.attempts.last.drop(null);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      final attempts = s.link.attempts.length;
      await Future<void>.delayed(const Duration(milliseconds: 2200));

      expect(s.link.attempts.length, greaterThan(attempts));
      expect(s.server.sessionReads, reads, reason: 'a dead link says nothing');
      expect(s.container.read(signedInAccountProvider), _ann.id);
      expect(s.engine.started, isTrue);
    });
  });

  test('a doubt the server did not answer is asked again, until the '
      'signed-in scope goes', () async {
    final s = await _signedIn();
    final reads = s.server.sessionReads;

    // The socket stays down, and its attempts are refused for a reason
    // that is not the session.
    s.server.sessionError = _lost;
    s.link.refusal = const UpgradeRefused(503);
    s.link.attempts.last.drop(sessionEndedCloseCode);
    await pumpEventQueue();
    expect(s.server.sessionReads, reads + 1);

    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(s.server.sessionReads, reads + 2, reason: 'asked again');

    // Two seconds from asking again, the scope goes.
    s.leave();
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    expect(s.server.sessionReads, reads + 2);
  });

  group('an engine a refused sync stopped', () {
    test('two signals together make one read', () async {
      final s = await _signedIn();
      final reads = s.server.sessionReads;

      s.server.getSessionGate = Completer<void>();
      s.link.reachable = false;
      s.link.attempts.last.drop(sessionEndedCloseCode);
      s.server.refusing = true;
      await s.engine.reconcile();
      await pumpEventQueue();
      expect(
        s.server.calls.where((call) => call.endsWith('!')),
        hasLength(2),
        reason: 'the socket closed as ended and two calls refused',
      );
      expect(s.server.sessionReads, reads + 1);

      s.server.sessionState = const SessionState(authenticated: false);
      s.server.getSessionGate!.complete();
      await pumpEventQueue();
      expect(_signedOut(s.container), isTrue);
    });

    test('runs again and pulls once the session stands', () async {
      final s = await _signedIn();
      final attempts = s.link.attempts.length;
      final before = s.server.calls.length;

      // One walk refused, both its calls, and the session read vouches
      // for Ann.
      s.server.refusals = 2;
      await s.engine.beforeSync(s.engine.reconcile);
      await _until(() => s.server.calls.sublist(before).contains('server'));
      // Behind the work the restart queued, the walk with it.
      await s.engine.beforeSync(() async {});
      await pumpEventQueue();

      expect(s.engine.started, isTrue);
      expect(s.link.attempts, hasLength(attempts + 1));
      final since = s.server.calls.sublist(before);
      expect(since.take(2), ['catalog!', 'session'], reason: '$since');
      // Two of each: one pair from the server's resubscribe invalidates,
      // which the engine pulls by itself, and one from its own walk.
      for (final call in ['catalog', 'server']) {
        expect(since.where((made) => made == call), hasLength(2), reason: call);
      }
      expect(s.container.read(signedInAccountProvider), _ann.id);
    });

    test('under a session that names no user, reads it, and runs again and '
        'pulls once it stands', () async {
      // The contract leaves the session's user optional.
      final s = await _signedIn(
        session: const SessionState(authenticated: true),
      );
      final reads = s.server.sessionReads;
      final attempts = s.link.attempts.length;
      final before = s.server.calls.length;

      s.server.refusals = 2;
      await s.engine.beforeSync(s.engine.reconcile);
      await pumpEventQueue();
      expect(
        s.server.sessionReads,
        greaterThan(reads),
        reason: 'a session it holds',
      );

      await _until(() => s.server.calls.sublist(before).contains('server'));
      await s.engine.beforeSync(() async {});
      await pumpEventQueue();
      expect(s.engine.started, isTrue);
      expect(s.link.attempts, hasLength(attempts + 1));
      // The walk, and what the server invalidates on the resubscribe.
      final since = s.server.calls.sublist(before);
      for (final call in ['catalog', 'server']) {
        expect(since.where((made) => made == call), hasLength(2), reason: call);
      }
      expect(_signedOut(s.container), isFalse);
    });

    test('stays stopped once the session is gone', () async {
      final s = await _signedIn();
      final attempts = s.link.attempts.length;

      s.server
        ..refusing = true
        ..sessionState = const SessionState(authenticated: false);
      await s.engine.beforeSync(s.engine.reconcile);
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      expect(_signedOut(s.container), isTrue);
      expect(s.engine.started, isFalse);
      expect(s.link.attempts, hasLength(attempts));
    });

    test('and started again that caught up is started again at once the '
        'next time', () async {
      final s = await _signedIn();
      final attempts = s.link.attempts.length;

      // A walk refused, both its calls, and the session stands: started
      // again at once, and its walk goes through.
      s.server.refusals = 2;
      await s.engine.beforeSync(s.engine.reconcile);
      await _until(() => s.link.attempts.length == attempts + 1);
      await _until(() => s.engine.current.online);
      await s.engine.beforeSync(() async {});
      await pumpEventQueue();
      expect(s.server.refusals, 0);

      // Later, another walk refused.
      s.server.refusals = 2;
      await s.engine.beforeSync(s.engine.reconcile);
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(
        s.link.attempts,
        hasLength(attempts + 2),
        reason: 'at once, not a second later',
      );
      expect(s.engine.started, isTrue);
    });

    testWidgets('by a server that vouches for the session is started again '
        'at once, then after 1 s, doubling, and never further apart than a '
        'minute', (tester) async {
      final s = await _signedIn(tester: tester);
      final attempts = s.link.attempts.length;

      // Every walk refused; bounded, so a loop fails the count rather than
      // holding the clock.
      s.server.refusals = 200;
      await s.engine.beforeSync(s.engine.reconcile);
      await tester.pump(Duration.zero);
      expect(s.link.attempts.length - attempts, 1, reason: 'at once');

      await _restartsAfter(tester, s, const [1, 2, 4, 8, 16, 32, 60, 60]);
      expect(s.container.read(signedInAccountProvider), _ann.id);
      await _end(tester, s);
    });

    test('by such a server is not started again in a loop when its sockets '
        'are slow to close', () async {
      // The stop each refusal makes then waits on the socket's close.
      final closing = Completer<void>();
      addTearDown(closing.complete);
      final s = await _signedIn(closing: closing.future);
      final attempts = s.link.attempts.length;

      s.server.refusing = true;
      await s.engine.beforeSync(s.engine.reconcile);
      await Future<void>.delayed(const Duration(milliseconds: 2500));

      expect(s.link.attempts.length - attempts, inInclusiveRange(1, 2));
    });

    testWidgets('by a server that refuses the question a walk puts last, '
        'while it vouches for the session, is started again at once, then a '
        'second later, then two', (tester) async {
      final s = await _signedIn(tester: tester);
      await _questionWaits(s);
      final attempts = s.link.attempts.length;

      // Bounded, so a loop fails the count rather than holding the clock.
      s.server.questionRefusals = 50;
      await s.engine.beforeSync(s.engine.reconcile);
      expect(s.engine.started, isFalse);
      await tester.pump(Duration.zero);
      expect(s.link.attempts.length - attempts, 1, reason: 'at once');

      await _restartsAfter(tester, s, const [1, 2]);
      // Each walk went through to its last question, refused there.
      expect(s.server.calls.where((call) => call == 'removed!'), hasLength(4));
      expect(s.container.read(signedInAccountProvider), _ann.id);
      await _end(tester, s);
    });

    test('stays stopped when the read lands while the account signs out, '
        'which signs out once', () async {
      final artwork = _HeldArtwork();
      final s = await _signedIn(artwork: artwork);
      final reads = s.server.sessionReads;
      final attempts = s.link.attempts.length;

      // A walk refused, and the read it starts held.
      s.server
        ..getSessionGate = Completer<void>()
        ..refusing = true;
      await s.engine.beforeSync(s.engine.reconcile);
      await pumpEventQueue();
      expect(s.engine.started, isFalse);
      expect(s.server.sessionReads, reads + 1);

      // Ann signs out, and the server ends her session: a socket opened
      // now would be refused. Her cleanup is held part way.
      s.link.refusal = const UpgradeRefused(401);
      final out = s.container.read(authControllerProvider.notifier).logout();
      await artwork.reached;
      s.server.getSessionGate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      expect(s.engine.started, isFalse, reason: 'her account is leaving');
      expect(s.link.attempts, hasLength(attempts));
      expect(artwork.wipes, 1, reason: 'one sign-out, not a second inside it');

      artwork.gate.complete();
      await out;
      expect(_signedOut(s.container), isTrue);
      expect(s.server.sessionReads, reads + 1);
    });
  });

  test('a return reads no session: the walk runs at once, and nothing else '
      'is asked', () async {
    final s = await _signedIn();
    // What awaits the session, as the preferences do.
    final prefs = s.container.listen(prefsControllerProvider, (_, _) {});
    addTearDown(prefs.close);
    await s.container.read(prefsControllerProvider.future);
    final before = s.server.calls.length;

    // A read that never answers, so anything waiting on one shows.
    s.server.getSessionGate = Completer<void>();
    s.link.attempts.last.drop(null);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    await s.engine.beforeSync(() async {});
    await pumpEventQueue();

    expect(s.link.attempts, hasLength(2));
    expect(s.engine.current.online, isTrue);
    // The engine's own walk, then the pulls of what the server invalidates
    // on the resubscribe.
    expect(s.server.calls.sublist(before), [
      'catalog',
      'server',
      'catalog',
      'server',
    ]);
  });
}
