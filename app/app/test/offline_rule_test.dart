import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart'
    show serverReachable;
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/player/bookmarks.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/player/playback_session.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_persistence.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/shell/lifecycle_banners.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck/src/sync/sync_binder.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'app_host.dart';
import 'debug_prints.dart';
import 'fakes.dart';

/// What "offline" means to the screens, the shell and the player: the
/// engine is past a failure, or was started on a session the device
/// remembered at a start the server did not answer. Any other first
/// connect still out is neither.

const _ann = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDACCANN',
  username: 'ann',
  roles: ['user'],
  uploadEnabled: true,
);

const _anns = SessionState(authenticated: true, user: _ann);

const _book = 'bk-01JZX5N8QW3F4V9T2B7KD3M9R6';

const _track = 'tr-A';

const _other = 'tr-B';

const _show = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';

const _episode = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';

const _album = QueueSource(
  kind: QueueSourceKind.album,
  label: 'Kind of Blue',
  pid: 'al-1',
);

/// A request nothing answered, as the player meets one.
const _outOfReach = WaxDeckApiException(
  code: 'transport-unreachable',
  message: 'offline',
);

final _l10n = AppLocalizationsEn();

/// A connect nothing answered.
const _lost = WaxDeckApiException(
  code: 'transport',
  message: 'connection refused',
);

/// The server's answer for an item it does not have: nothing a connect
/// cures.
const _notFound = WaxDeckApiException(
  code: 'not-found',
  message: 'no such item',
  statusCode: 404,
);

/// A server whose session reads can fail or be held.
class _Server extends FakeRepository {
  _Server()
    : super(sessionState: _anns, items: [testItem(_track), testItem(_other)]) {
    browseLists[DiscoveryList.recentlyAdded] = [testItem(_track)];
    books[_book] = testBook(_book, durationMs: 3600000);
  }

  WaxDeckApiException? sessionError;

  /// Holds each session read asked while it is set.
  Completer<void>? sessionGate;

  @override
  Future<SessionState> getSession() async {
    await sessionGate?.future;
    if (sessionError case final error?) throw error;
    return SessionState.fromStored(sessionState.toStored())!;
  }

  /// How often a start asked for its stream, the refused asks included.
  var playInfoAsked = 0;

  /// Holds each play-state read asked while it is set.
  Completer<void>? playStateGate;

  /// How often a play state was asked for, held reads included.
  var playStateAsked = 0;

  @override
  Future<PlayState> getPlayState(String pid) async {
    playStateAsked++;
    await playStateGate?.future;
    return super.getPlayState(pid);
  }

  @override
  Future<PlayInfo> getPlayInfo(
    String pid, {
    int? positionMs,
    bool? voiceBoost,
    bool? voiceBoostDefault,
    int? maxBitrateKbps,
    bool? hls,
  }) {
    playInfoAsked++;
    return super.getPlayInfo(
      pid,
      positionMs: positionMs,
      voiceBoost: voiceBoost,
      voiceBoostDefault: voiceBoostDefault,
      maxBitrateKbps: maxBitrateKbps,
      hls: hls,
    );
  }

  /// Run as a sign-out reaches the server, before it answers: where it
  /// closes the session's socket.
  void Function()? onLogout;

  /// Holds the answer to a sign-out while it is set.
  Completer<void>? logoutGate;

  @override
  Future<void> logout() async {
    onLogout?.call();
    await logoutGate?.future;
    return super.logout();
  }

  /// Holds each answer about the server's build, read as it was asked,
  /// while it is set.
  Completer<void>? buildGate;

  var buildAsked = 0;

  @override
  Future<ServerHealth> health() async {
    buildAsked++;
    final answer = await super.health();
    await buildGate?.future;
    return answer;
  }
}

/// The network under the engine's socket: each connect waits for the test
/// to answer or fail it.
class _Net {
  final attempts = <_Attempt>[];

  EventsChannelFactory get factory =>
      ({required onFrame, required onDone, required subscribe}) {
        final attempt = _Attempt(
          onFrame: onFrame,
          onDone: onDone,
          subscribe: subscribe,
        );
        attempts.add(attempt);
        return attempt;
      };
}

class _Attempt extends EventsChannel {
  _Attempt({
    required super.onFrame,
    required super.onDone,
    required super.subscribe,
  }) : super(url: 'ws://held', authToken: null);

  final _answer = Completer<void>();
  var _up = false;
  int? _code;

  @override
  int? get closeCode => _code;

  @override
  Future<void> connect() async {
    await _answer.future;
    _up = true;
  }

  void answer() => _answer.complete();

  void fail() => _answer.completeError(Exception('unreachable'));

  /// The server's refusal of the upgrade, with its status.
  void refuse(int status) => _answer.completeError(UpgradeRefused(status));

  /// The link lost, or with [code] the server's close.
  void drop([int? code]) {
    _code = code;
    _up = false;
    onDone();
  }

  @override
  bool send(String frame) => _up;

  @override
  Future<void> close() async => _up = false;
}

typedef _Device = ({
  ProviderContainer container,
  _Server server,
  SyncEngine engine,
  _Net net,
  FakeEngine audio,
  FakeDownloads downloads,
});

/// Ann's device at a cold start: her token and the session the server
/// last answered for it in the store, a real engine over [_Net].
_Device _device({DateTime Function()? clock}) {
  final db = inMemoryMirrorDatabase();
  addTearDown(db.close);
  final downloads = FakeDownloads();
  addTearDown(downloads.dispose);
  final server = _Server();
  final net = _Net();
  final engine = SyncEngine(
    db: db,
    repository: server,
    channelFactory: net.factory,
  );
  addTearDown(engine.dispose);
  final audio = FakeEngine(mediaDuration: const Duration(minutes: 3));
  final container = appContainer(
    repo: server,
    engine: audio,
    credentials: InMemoryCredentialStore()
      ..token = 'token-ann'
      ..session = rememberedRecord('token-ann', _anns.toStored()),
    sync: engine,
    mirror: db,
    downloads: downloads,
    settings: MemoryClientSettingsStore(),
    extra: [
      queueSaveDebounceProvider.overrideWithValue(Duration.zero),
      if (clock != null) wallClockProvider.overrideWithValue(clock),
    ],
  );
  return (
    container: container,
    server: server,
    engine: engine,
    net: net,
    audio: audio,
    downloads: downloads,
  );
}

/// Ann signed in, the session read answered or not, and the binder running
/// the engine as the signed-in screens do.
Future<_Device> _signedIn(
  WidgetTester tester, {
  bool serverAnswers = true,
  DateTime Function()? clock,
}) async {
  final device = _device(clock: clock);
  if (!serverAnswers) device.server.sessionError = _lost;
  final session = device.container.listen(authControllerProvider, (_, _) {});
  addTearDown(session.close);
  await tester.pump(Duration.zero);
  expect(session.read().value?.user?.id, _ann.id);
  final binder = device.container.listen(syncBinderProvider, (_, _) {});
  addTearDown(binder.close);
  await tester.pump(Duration.zero);
  expect(device.engine.started, isTrue);
  return device;
}

final _banner = find.bySemanticsIdentifier(SemanticsIds.offlineBanner);

/// The banner anywhere in the tree, drawn or not.
final _bannerBuilt = find.bySemanticsIdentifier(
  SemanticsIds.offlineBanner,
  skipOffstage: false,
);

/// The shell's own banner, drawn, and anywhere in the tree.
final _reconnecting = find.bySemanticsIdentifier(
  SemanticsIds.bannerReconnecting,
);
final _reconnectingBuilt = find.bySemanticsIdentifier(
  SemanticsIds.bannerReconnecting,
  skipOffstage: false,
);

/// The player's offer to try a failed start again, on the shell's bar.
final _retry = find.bySemanticsIdentifier(SemanticsIds.playerStartRetry);
final _retryBuilt = find.bySemanticsIdentifier(
  SemanticsIds.playerStartRetry,
  skipOffstage: false,
);
final _home = find.bySemanticsIdentifier(SemanticsIds.homeScreen);
final _signIn = find.bySemanticsIdentifier(SemanticsIds.loginUsername);

/// The shell's word that the server came back as another build.
final _updated = find.bySemanticsIdentifier(SemanticsIds.bannerUpdated);
final _updatedBuilt = find.bySemanticsIdentifier(
  SemanticsIds.bannerUpdated,
  skipOffstage: false,
);
final _add = find.bySemanticsIdentifier(SemanticsIds.homeAdd);

/// Home's server-backed half, which is private to its file. Mounted, not
/// necessarily painting: its shelves hold their skeletons back a moment.
final _onlineHome = find.byWidgetPredicate(
  (widget) => '${widget.runtimeType}' == '_OnlineHome',
  skipOffstage: false,
);

const _frame = Duration(milliseconds: 50);

/// Pumps a frame at a time until Home is drawn, running [each] on every
/// frame, the one Home first shows in included.
Future<void> _untilInside(
  WidgetTester tester, {
  required void Function(int frame) each,
}) async {
  for (var frame = 0; frame < 200; frame++) {
    if (frame > 0) await tester.pump(_frame);
    each(frame);
    if (_home.evaluate().isNotEmpty) return;
  }
  fail('Home was never drawn');
}

/// [count] more frames, [each] run on every one.
Future<void> _frames(
  WidgetTester tester,
  int count, {
  required void Function(int frame) each,
}) async {
  for (var frame = 0; frame < count; frame++) {
    await tester.pump(_frame);
    each(frame);
  }
}

/// Frames until [work] is done, [each] run on every one: for a sign-out or
/// a sign-in, which the app's own frames carry.
Future<void> _through(
  WidgetTester tester,
  Future<void> work, {
  void Function(int frame)? each,
}) async {
  var done = false;
  unawaited(work.whenComplete(() => done = true));
  for (var frame = 0; frame < 200 && !done; frame++) {
    await tester.pump(_frame);
    each?.call(frame);
  }
  await work;
}

/// A widget test of a start that fails, which the player says on the
/// console: those lines are kept for a failure.
void _testFailedStart(
  String description,
  Future<void> Function(WidgetTester tester) body,
) => testWidgets(description, (tester) async {
  await captureDebugPrints(() => body(tester));
});

final _reach = Provider<bool Function()>(serverReachable);

/// Ends what runs over [device] inside the test's body, where a timer
/// still running fails it.
Future<void> _end(WidgetTester tester, _Device device) async {
  device.container.dispose();
  await tester.pump(Duration.zero);
}

void main() {
  group('the whole app, from a cold start', () {
    testWidgets('with the server in reach never builds the offline banner, '
        'and the first frame inside is the online home with its add', (
      tester,
    ) async {
      final device = _device();
      await mountHost(tester, const WaxDeckApp(), container: device.container);

      await _untilInside(
        tester,
        each: (frame) =>
            expect(_bannerBuilt, findsNothing, reason: 'frame $frame'),
      );
      expect(_onlineHome, findsOneWidget);
      expect(_add, findsOneWidget);
      expect(device.engine.started, isTrue);

      // For as long as the socket takes to come up.
      await _frames(
        tester,
        40,
        each: (frame) {
          expect(_bannerBuilt, findsNothing, reason: 'frame $frame inside');
          expect(_onlineHome, findsOneWidget);
          expect(_add, findsOneWidget);
        },
      );
      expect(device.engine.current.connection, SyncConnection.connecting);

      device.net.attempts.single.answer();
      await _frames(
        tester,
        10,
        each: (frame) => expect(
          _bannerBuilt,
          findsNothing,
          reason: 'frame $frame connected',
        ),
      );
      expect(device.engine.current.online, isTrue);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.shelf('recent')),
        findsOneWidget,
      );
      await device.engine.stop();
    });

    testWidgets('whose first connect fails is offline from the failure, '
        'through the retry, until a connect answers', (tester) async {
      final device = _device();
      await mountHost(tester, const WaxDeckApp(), container: device.container);
      await _untilInside(tester, each: (_) {});
      expect(_banner, findsNothing);

      device.net.attempts.single.fail();
      await tester.pump();
      expect(_banner, findsOneWidget);
      expect(_onlineHome, findsNothing);
      expect(_add, findsNothing);

      // Across the wait and into the retry, which hangs.
      await _frames(
        tester,
        40,
        each: (frame) => expect(_banner, findsOneWidget, reason: '$frame'),
      );
      expect(device.net.attempts, hasLength(2));
      expect(device.engine.current.connection, SyncConnection.connecting);

      device.net.attempts.last.answer();
      await tester.pump();
      await tester.pump(_frame);
      expect(_banner, findsNothing);
      expect(_onlineHome, findsOneWidget);
      await device.engine.stop();
    });

    testWidgets('opened on the remembered session, the connect hanging, is '
        'offline from its first frame inside, until the socket is up', (
      tester,
    ) async {
      final device = _device();
      // The server takes the request and never answers it.
      device.server.sessionGate = Completer<void>();
      await mountHost(tester, const WaxDeckApp(), container: device.container);

      await _untilInside(tester, each: (_) {});
      final auth = device.container.read(authControllerProvider.notifier);
      expect(auth.unconfirmed, isTrue);
      expect(_banner, findsOneWidget, reason: 'the first frame inside');
      expect(_onlineHome, findsNothing);

      await _frames(
        tester,
        40,
        each: (frame) => expect(_banner, findsOneWidget, reason: '$frame'),
      );
      // Not by a failed connect: the one attempt is still out, and the
      // engine was started knowing.
      expect(device.net.attempts, hasLength(1));
      expect(device.engine.current.connection, SyncConnection.connecting);
      expect(device.engine.current.retrying, isTrue);

      device.server.sessionGate = null;
      device.net.attempts.single.answer();
      await tester.pump();
      await tester.pump(_frame);
      expect(_banner, findsNothing);
      expect(_onlineHome, findsOneWidget);
      expect(auth.unconfirmed, isFalse);
      await device.engine.stop();
    });

    testWidgets('opened on the remembered session, which a plain request '
        'then confirms with the connect still out, stays offline until the '
        'socket is up', (tester) async {
      final device = _device();
      device.server.sessionError = _lost;
      await mountHost(tester, const WaxDeckApp(), container: device.container);

      void offline(String when) {
        expect(_banner, findsOneWidget, reason: when);
        expect(_onlineHome, findsNothing, reason: when);
      }

      await _untilInside(tester, each: (_) {});
      offline('the first frame inside');
      final auth = device.container.read(authControllerProvider.notifier);
      expect(auth.unconfirmed, isTrue);

      device.server.sessionError = null;
      final recheck = auth.refreshSession();
      await _through(
        tester,
        recheck,
        each: (frame) => offline('confirming, frame $frame'),
      );
      expect(await recheck, SessionRecheck.stands);
      expect(auth.unconfirmed, isFalse);
      await _frames(
        tester,
        40,
        each: (frame) => offline('confirmed, frame $frame'),
      );
      expect(device.net.attempts, hasLength(1));

      device.net.attempts.single.answer();
      await tester.pump();
      await tester.pump(_frame);
      expect(_banner, findsNothing);
      expect(_onlineHome, findsOneWidget);
      await device.engine.stop();
    });

    testWidgets('behind a proxy that passes requests and not the socket is '
        'offline on every frame: confirmed, the connect failing, the retry '
        'out', (tester) async {
      final device = _device();
      device.server.sessionError = _lost;
      await mountHost(tester, const WaxDeckApp(), container: device.container);

      // Both banners up and the online home never built.
      void offline(String when) {
        expect(_banner, findsOneWidget, reason: when);
        expect(_reconnecting, findsOneWidget, reason: when);
        expect(_onlineHome, findsNothing, reason: when);
      }

      await _untilInside(tester, each: (_) {});
      offline('the first frame inside');
      final auth = device.container.read(authControllerProvider.notifier);

      device.server.sessionError = null;
      final recheck = auth.refreshSession();
      await _through(
        tester,
        recheck,
        each: (frame) => offline('confirming, frame $frame'),
      );
      expect(await recheck, SessionRecheck.stands);
      expect(auth.unconfirmed, isFalse);
      await _frames(
        tester,
        10,
        each: (frame) => offline('confirmed, frame $frame'),
      );

      device.net.attempts.single.fail();
      // Across the wait and into the retry, which hangs.
      await _frames(
        tester,
        40,
        each: (frame) => offline('the connect failed, frame $frame'),
      );
      expect(device.net.attempts, hasLength(2));
      expect(device.engine.current.connection, SyncConnection.connecting);

      device.net.attempts.last.fail();
      await _frames(
        tester,
        10,
        each: (frame) => offline('the retry failed, frame $frame'),
      );
      await device.engine.stop();
    });

    testWidgets('whose socket drops is offline at once, through the retry, '
        'until the socket is up again', (tester) async {
      final device = _device();
      await mountHost(tester, const WaxDeckApp(), container: device.container);
      await _untilInside(tester, each: (_) {});
      device.net.attempts.single.answer();
      await tester.pump();
      await tester.pump(_frame);
      expect(device.engine.current.online, isTrue);
      expect(_banner, findsNothing);

      device.net.attempts.single.drop();
      // The engine does not pass through connecting on its way down.
      expect(device.engine.current.connection, SyncConnection.offline);
      await tester.pump();
      expect(_banner, findsOneWidget);

      await _frames(
        tester,
        40,
        each: (frame) => expect(_banner, findsOneWidget, reason: '$frame'),
      );
      expect(device.net.attempts, hasLength(2));
      expect(device.engine.current.connection, SyncConnection.connecting);

      device.net.attempts.last.answer();
      await tester.pump();
      await tester.pump(_frame);
      expect(_banner, findsNothing);
      await device.engine.stop();
    });
  });

  group('the shell\'s reconnecting banner, from a cold start', () {
    testWidgets('with the server in reach is never built', (tester) async {
      final device = _device();
      await mountHost(tester, const WaxDeckApp(), container: device.container);

      await _untilInside(
        tester,
        each: (frame) =>
            expect(_reconnectingBuilt, findsNothing, reason: 'frame $frame'),
      );
      await _frames(
        tester,
        40,
        each: (frame) => expect(
          _reconnectingBuilt,
          findsNothing,
          reason: 'frame $frame inside',
        ),
      );
      expect(device.engine.current.connection, SyncConnection.connecting);

      device.net.attempts.single.answer();
      await _frames(
        tester,
        10,
        each: (frame) => expect(
          _reconnectingBuilt,
          findsNothing,
          reason: 'frame $frame connected',
        ),
      );
      expect(device.engine.current.online, isTrue);
      await device.engine.stop();
    });

    testWidgets('whose first connect fails is shown from the failure, '
        'through the retry, until a connect answers', (tester) async {
      final device = _device();
      await mountHost(tester, const WaxDeckApp(), container: device.container);
      await _untilInside(
        tester,
        each: (frame) =>
            expect(_reconnectingBuilt, findsNothing, reason: 'frame $frame'),
      );

      device.net.attempts.single.fail();
      await tester.pump();
      expect(_reconnecting, findsOneWidget);

      // Across the wait and into the retry, which hangs.
      await _frames(
        tester,
        40,
        each: (frame) =>
            expect(_reconnecting, findsOneWidget, reason: '$frame'),
      );
      expect(device.net.attempts, hasLength(2));
      expect(device.engine.current.connection, SyncConnection.connecting);

      device.net.attempts.last.answer();
      await tester.pump();
      await tester.pump(_frame);
      expect(_reconnectingBuilt, findsNothing);
      await device.engine.stop();
    });

    testWidgets('whose socket drops is shown at once, through the retry, '
        'until the socket is up again', (tester) async {
      final device = _device();
      await mountHost(tester, const WaxDeckApp(), container: device.container);
      await _untilInside(tester, each: (_) {});
      device.net.attempts.single.answer();
      await tester.pump();
      await tester.pump(_frame);
      expect(_reconnectingBuilt, findsNothing);

      device.net.attempts.single.drop();
      await tester.pump();
      expect(_reconnecting, findsOneWidget);

      await _frames(
        tester,
        40,
        each: (frame) =>
            expect(_reconnecting, findsOneWidget, reason: '$frame'),
      );
      expect(device.net.attempts, hasLength(2));
      expect(device.engine.current.connection, SyncConnection.connecting);

      device.net.attempts.last.answer();
      await tester.pump();
      await tester.pump(_frame);
      expect(_reconnectingBuilt, findsNothing);
      await device.engine.stop();
    });

    testWidgets('opened on the remembered session, the connect hanging, is '
        'shown from the first frame inside, above Home\'s own banner', (
      tester,
    ) async {
      final device = _device();
      device.server.sessionGate = Completer<void>();
      await mountHost(tester, const WaxDeckApp(), container: device.container);

      await _untilInside(tester, each: (_) {});
      expect(_reconnecting, findsOneWidget, reason: 'the first frame inside');
      expect(_banner, findsOneWidget);
      // Two banners, one over the other and neither on the other.
      expect(
        tester.getRect(_reconnecting).bottom,
        lessThanOrEqualTo(tester.getRect(_banner).top),
      );

      await _frames(
        tester,
        40,
        each: (frame) =>
            expect(_reconnecting, findsOneWidget, reason: '$frame'),
      );
      expect(device.net.attempts, hasLength(1));
      expect(device.engine.current.retrying, isTrue);

      device.server.sessionGate = null;
      device.net.attempts.single.answer();
      await tester.pump();
      await tester.pump(_frame);
      expect(_reconnectingBuilt, findsNothing);
      expect(_bannerBuilt, findsNothing);
      await device.engine.stop();
    });
  });

  group('a session the server says has ended', () {
    void neither(String when) {
      expect(_bannerBuilt, findsNothing, reason: when);
      expect(_reconnectingBuilt, findsNothing, reason: when);
    }

    /// Ann inside, the socket up.
    Future<_Device> connected(WidgetTester tester) async {
      final device = _device();
      await mountHost(tester, const WaxDeckApp(), container: device.container);
      await _untilInside(tester, each: (_) {});
      device.net.attempts.single.answer();
      await _frames(tester, 6, each: (_) {});
      expect(device.engine.current.online, isTrue);
      neither('connected');
      return device;
    }

    /// Frames until the sign-in form is drawn, [each] run on every one.
    Future<void> untilSignIn(
      WidgetTester tester, {
      required void Function(int frame) each,
    }) async {
      for (var frame = 0; frame < 200; frame++) {
        await tester.pump(_frame);
        each(frame);
        if (_signIn.evaluate().isNotEmpty) return;
      }
      fail('the sign-in form was never drawn');
    }

    for (final held in [true, false]) {
      testWidgets('by a sign-out whose socket closes '
          '${held ? 'before the server answers' : 'as the server answers'} '
          'builds neither the offline banner nor the band, not for a frame, '
          'on the way to the sign-in form', (tester) async {
        final device = await connected(tester);
        final answer = Completer<void>();
        if (held) device.server.logoutGate = answer;
        device.server.onLogout = () =>
            device.net.attempts.last.drop(sessionEndedCloseCode);

        final out = device.container
            .read(authControllerProvider.notifier)
            .logout();
        if (held) {
          await _frames(
            tester,
            30,
            each: (frame) => neither('the answer held, frame $frame'),
          );
          // A sign-out takes effect on screen before the server answers it.
          expect(_home, findsNothing);
          expect(_signIn, findsOneWidget);
          answer.complete();
        }
        await _through(
          tester,
          out,
          each: (frame) => neither('signing out, frame $frame'),
        );
        await untilSignIn(tester, each: (frame) => neither('frame $frame'));
        await _frames(
          tester,
          20,
          each: (frame) => neither('signed out, frame $frame'),
        );
        expect(device.engine.started, isFalse);
      });
    }

    testWidgets('from elsewhere builds neither while the session is read '
        'again, nor on the way to the sign-in form', (tester) async {
      final device = await connected(tester);
      final read = device.server.sessionGate = Completer<void>();
      device.server.sessionState = const SessionState(authenticated: false);

      device.net.attempts.single.drop(sessionEndedCloseCode);
      await _frames(
        tester,
        30,
        each: (frame) => neither('the read out, frame $frame'),
      );
      expect(_home, findsOneWidget);
      // The reconnect, refused for want of a session.
      expect(device.net.attempts, hasLength(2));
      device.net.attempts.last.refuse(401);
      await _frames(
        tester,
        10,
        each: (frame) => neither('refused, frame $frame'),
      );

      device.server.sessionGate = null;
      read.complete();
      await untilSignIn(tester, each: (frame) => neither('frame $frame'));
      await _frames(
        tester,
        20,
        each: (frame) => neither('signed out, frame $frame'),
      );
      expect(_home, findsNothing);
      expect(device.engine.started, isFalse);
    });

    testWidgets('and whose reconnect then fails for want of the server is '
        'offline from that failure, until a connect answers', (tester) async {
      final device = await connected(tester);
      final read = device.server.sessionGate = Completer<void>();

      device.net.attempts.single.drop(sessionEndedCloseCode);
      await _frames(
        tester,
        30,
        each: (frame) => neither('the read out, frame $frame'),
      );
      expect(device.net.attempts, hasLength(2));

      device.net.attempts.last.fail();
      // Nothing has a frame scheduled here, so the pump that hears the
      // failure draws none: the next one is the first to.
      await tester.pump();
      await tester.pump(_frame);
      expect(_banner, findsOneWidget);
      expect(_reconnecting, findsOneWidget);
      // Into the retry, two seconds on.
      await _frames(
        tester,
        45,
        each: (frame) {
          expect(_banner, findsOneWidget, reason: '$frame');
          expect(_reconnecting, findsOneWidget, reason: '$frame');
        },
      );

      // The session stands, and the retry answers.
      device.server.sessionGate = null;
      read.complete();
      expect(device.net.attempts, hasLength(3));
      device.net.attempts.last.answer();
      await tester.pump();
      await tester.pump(_frame);
      neither('the socket up again');
      expect(_home, findsOneWidget);
      await device.engine.stop();
    });
  });

  _testFailedStart('a press of play that fails while the first connect is '
      'out offers a retry, and the offer leaves when that connect starts it', (
    tester,
  ) async {
    final device = _device();
    await mountHost(tester, const WaxDeckApp(), container: device.container);
    await _untilInside(tester, each: (_) {});

    device.server.playInfoError = _outOfReach;
    device.container.read(queueControllerProvider.notifier).playNow([
      _track,
    ], source: _album);
    await _frames(tester, 10, each: (_) {});
    expect(_retry, findsOneWidget);
    expect(
      find.text(_l10n.playerCouldNotStart(testItem(_track).title)),
      findsOneWidget,
    );
    expect(device.audio.playing, isFalse);

    device.server.playInfoError = null;
    device.net.attempts.single.answer();
    // Well inside the time a bar stands for when nothing takes it down.
    await _frames(tester, 12, each: (_) {});
    expect(device.audio.playing, isTrue);
    expect(_retryBuilt, findsNothing);

    device.container.read(queueControllerProvider.notifier).clear();
    await _frames(tester, 4, each: (_) {});
    await device.engine.stop();
  });

  _testFailedStart('a press of play that fails while the first connect is '
      'out says it could not start; once that connect fails the one bar says '
      'offline instead, and leaves when the retry starts it', (tester) async {
    final device = _device();
    await mountHost(tester, const WaxDeckApp(), container: device.container);
    await _untilInside(tester, each: (_) {});
    final couldNot = find.text(
      _l10n.playerCouldNotStart(testItem(_track).title),
    );
    final offline = find.text(_l10n.playerOfflineStart);

    device.server.playInfoError = _outOfReach;
    device.container.read(queueControllerProvider.notifier).playNow([
      _track,
    ], source: _album);
    await _frames(tester, 10, each: (_) {});
    expect(couldNot, findsOneWidget);
    expect(offline, findsNothing);

    device.net.attempts.single.fail();
    await _frames(tester, 12, each: (_) {});
    expect(offline, findsOneWidget);
    expect(couldNot, findsNothing);
    expect(_retry, findsOneWidget);
    expect(device.audio.playing, isFalse);

    // The retry, a second after the failure.
    await _frames(tester, 10, each: (_) {});
    expect(device.net.attempts, hasLength(2));
    device.server.playInfoError = null;
    device.net.attempts.last.answer();
    await _frames(tester, 12, each: (_) {});
    expect(device.audio.playing, isTrue);
    expect(_retryBuilt, findsNothing);

    device.container.read(queueControllerProvider.notifier).clear();
    await _frames(tester, 4, each: (_) {});
    await device.engine.stop();
  });

  _testFailedStart('a press of play that fails after the socket dropped '
      'says offline, and the bar leaves when the socket is up again and '
      'starts it', (tester) async {
    final device = _device();
    await mountHost(tester, const WaxDeckApp(), container: device.container);
    await _untilInside(tester, each: (_) {});
    device.net.attempts.single.answer();
    await _frames(tester, 4, each: (_) {});
    device.net.attempts.single.drop();
    await tester.pump();

    device.server.playInfoError = _outOfReach;
    device.container.read(queueControllerProvider.notifier).playNow([
      _track,
    ], source: _album);
    await _frames(tester, 10, each: (_) {});
    expect(find.text(_l10n.playerOfflineStart), findsOneWidget);
    expect(_retry, findsOneWidget);

    // The retry, a second after the drop: the bar is not two seconds old.
    await _frames(tester, 12, each: (_) {});
    expect(device.net.attempts, hasLength(2));
    expect(_retry, findsOneWidget);
    device.server.playInfoError = null;
    device.net.attempts.last.answer();
    await _frames(tester, 12, each: (_) {});
    expect(device.audio.playing, isTrue);
    expect(_retryBuilt, findsNothing);

    device.container.read(queueControllerProvider.notifier).clear();
    await _frames(tester, 4, each: (_) {});
    await device.engine.stop();
  });

  _testFailedStart('across a sign-out and a sign-in in one process the next '
      'session starts clean, makes no start the last one left, and hears its '
      'own link', (tester) async {
    final device = _device();
    await mountHost(tester, const WaxDeckApp(), container: device.container);
    await _untilInside(tester, each: (_) {});
    final heard = <bool?>[];
    final link = device.container.listen(
      liveConnectionProvider,
      (_, next) => heard.add(next),
      fireImmediately: true,
    );
    addTearDown(link.close);
    final auth = device.container.read(authControllerProvider.notifier);
    final queue = device.container.read(queueControllerProvider.notifier);

    // The first session: a press fails for want of the server with the
    // first connect still out, and stands armed as the account leaves.
    device.server.playInfoError = _outOfReach;
    queue.playNow([_track], source: _album);
    await _frames(tester, 10, each: (_) {});
    expect(_retry, findsOneWidget);
    expect(heard, [null]);
    final asked = device.server.playInfoAsked;

    await _through(tester, auth.logout());
    // Past the time the first session's bar stood for.
    await _frames(tester, 100, each: (_) {});
    expect(_home, findsNothing);
    expect(device.engine.started, isFalse);
    expect(_reconnectingBuilt, findsNothing);
    expect(_retryBuilt, findsNothing);
    expect(heard, [null]);
    final attempts = device.net.attempts.length;

    // The next session, the server in reach again for a plain request.
    device.server.playInfoError = null;
    void clean(String when) {
      expect(_reconnectingBuilt, findsNothing, reason: when);
      expect(_bannerBuilt, findsNothing, reason: when);
      expect(_retryBuilt, findsNothing, reason: when);
    }

    await _through(
      tester,
      auth.login(username: 'ann', password: 'pw'),
      each: (frame) => clean('signing in, frame $frame'),
    );
    await _untilInside(tester, each: (frame) => clean('frame $frame'));
    await _frames(tester, 20, each: (frame) => clean('frame $frame inside'));
    expect(device.net.attempts, hasLength(attempts + 1));
    expect(device.engine.current.connection, SyncConnection.connecting);
    expect(device.engine.current.retrying, isFalse);
    expect(heard, [null]);

    // Its first connect fails: said, and the start the last account left
    // is neither offered again nor made when the retry answers.
    device.net.attempts.last.fail();
    await _frames(
      tester,
      30,
      each: (frame) {
        expect(_reconnecting, findsOneWidget, reason: 'frame $frame');
        expect(_banner, findsOneWidget, reason: 'frame $frame');
        expect(_retryBuilt, findsNothing, reason: 'frame $frame');
      },
    );
    expect(heard, [null, false]);
    expect(device.net.attempts, hasLength(attempts + 2));
    device.net.attempts.last.answer();
    await _frames(tester, 12, each: (_) {});
    expect(heard, [null, false, true]);
    expect(_reconnectingBuilt, findsNothing);
    expect(_bannerBuilt, findsNothing);
    expect(device.server.playInfoAsked, asked);
    expect(device.audio.playing, isFalse);
    expect(device.audio.loadedUrl, isNull);

    // And a press of its own that fails after a drop is made at the return.
    device.net.attempts.last.drop();
    await _frames(tester, 2, each: (_) {});
    expect(_reconnecting, findsOneWidget);
    device.server.playInfoError = _outOfReach;
    queue.playNow([_other], source: _album);
    await _frames(tester, 24, each: (_) {});
    expect(device.net.attempts, hasLength(attempts + 3));
    expect(device.audio.playing, isFalse);
    device.server.playInfoError = null;
    device.net.attempts.last.answer();
    await _frames(tester, 12, each: (_) {});
    expect(device.audio.playing, isTrue);
    expect(device.server.playInfoCalls.last.pid, _other);
    expect(_reconnectingBuilt, findsNothing);

    queue.clear();
    await _frames(tester, 4, each: (_) {});
    await device.engine.stop();
  });

  group('the server build watcher, across a sign-out and a sign-in', () {
    /// Ann inside with the socket up, the server's build read.
    Future<_Device> connected(WidgetTester tester) async {
      final device = _device();
      await mountHost(tester, const WaxDeckApp(), container: device.container);
      await _untilInside(tester, each: (_) {});
      device.net.attempts.single.answer();
      await _frames(tester, 6, each: (_) {});
      expect(_updatedBuilt, findsNothing);
      return device;
    }

    /// Out, and the sign-in screen settled in Home's place.
    Future<void> signOut(WidgetTester tester, _Device device) async {
      await _through(
        tester,
        device.container.read(authControllerProvider.notifier).logout(),
      );
      await _frames(tester, 20, each: (_) {});
      expect(_home, findsNothing);
      expect(device.engine.started, isFalse);
    }

    /// The socket drops and is up again a second later.
    Future<void> returns(WidgetTester tester, _Device device) async {
      final tried = device.net.attempts.length;
      device.net.attempts.last.drop();
      await _frames(tester, 24, each: (_) {});
      expect(device.net.attempts, hasLength(tried + 1));
      device.net.attempts.last.answer();
      await _frames(tester, 6, each: (_) {});
      expect(device.engine.current.online, isTrue);
    }

    testWidgets('on another server, which runs another build: nothing was '
        'updated, and that build is the one a later return is held to', (
      tester,
    ) async {
      final device = await connected(tester);
      final auth = device.container.read(authControllerProvider.notifier);
      void quiet(String when) =>
          expect(_updatedBuilt, findsNothing, reason: when);

      await signOut(tester, device);
      await _through(
        tester,
        device.container
            .read(serverAddressProvider.notifier)
            .adopt('http://other.test'),
      );
      device.server.serverVersion = '2.0.0';
      await _through(
        tester,
        auth.login(username: 'ann', password: 'pw'),
        each: (frame) => quiet('signing in, frame $frame'),
      );
      await _untilInside(tester, each: (frame) => quiet('frame $frame'));
      expect(device.net.attempts, hasLength(2));
      device.net.attempts.last.answer();
      await _frames(
        tester,
        20,
        each: (frame) => quiet('frame $frame connected'),
      );
      expect(device.engine.current.online, isTrue);

      // It comes back as the build it was first seen on, then as another.
      await returns(tester, device);
      quiet('back on the same build');
      device.server.serverVersion = '2.1.0';
      await returns(tester, device);
      expect(_updated, findsOneWidget);
      await device.engine.stop();
    });

    testWidgets('on the same server, updated in between: it is said', (
      tester,
    ) async {
      final device = await connected(tester);
      final auth = device.container.read(authControllerProvider.notifier);

      await signOut(tester, device);
      device.server.serverVersion = '1.1.0';
      await _through(tester, auth.login(username: 'ann', password: 'pw'));
      await _untilInside(
        tester,
        each: (frame) =>
            expect(_updatedBuilt, findsNothing, reason: 'frame $frame'),
      );
      expect(device.net.attempts, hasLength(2));
      device.net.attempts.last.answer();
      await _frames(tester, 6, each: (_) {});
      expect(_updated, findsOneWidget);
      await device.engine.stop();
    });

    testWidgets('on the same server and the same build: nothing is said', (
      tester,
    ) async {
      final device = await connected(tester);
      final auth = device.container.read(authControllerProvider.notifier);

      await signOut(tester, device);
      await _through(tester, auth.login(username: 'ann', password: 'pw'));
      await _untilInside(tester, each: (_) {});
      expect(device.net.attempts, hasLength(2));
      device.net.attempts.last.answer();
      await _frames(
        tester,
        10,
        each: (frame) =>
            expect(_updatedBuilt, findsNothing, reason: 'frame $frame'),
      );

      // Still held to the build first seen: a return as another is said.
      device.server.serverVersion = '1.1.0';
      await returns(tester, device);
      expect(_updated, findsOneWidget);
      await device.engine.stop();
    });
  });

  group('the player, at a press of play the server cannot be reached for', () {
    /// What the player's own listener hears of the link, from now on.
    List<bool?> linkHeard(_Device device) {
      final heard = <bool?>[];
      final link = device.container.listen(
        liveConnectionProvider,
        (_, next) => heard.add(next),
        fireImmediately: true,
      );
      addTearDown(link.close);
      return heard;
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(Duration.zero);
      }
    }

    /// The press, which fails: the pane stands on its error.
    Future<void> press(WidgetTester tester, _Device device) async {
      device.server.playInfoError = _outOfReach;
      device.container.read(nowPlayingProvider.notifier);
      device.container.read(queueControllerProvider.notifier).playNow([
        _track,
      ], source: _album);
      await settle(tester);
      expect(device.container.read(nowPlayingProvider).error, isNotNull);
      expect(device.audio.playing, isFalse);
    }

    String? said(_Device device) =>
        device.container.read(shellMessagesProvider)?.resolve(_l10n);

    /// Every message the shell is asked for, from now on.
    List<ShellMessage> raisedOn(_Device device) {
      final raised = <ShellMessage>[];
      final messages = device.container.listen(shellMessagesProvider, (
        _,
        next,
      ) {
        if (next != null) raised.add(next);
      });
      addTearDown(messages.close);
      return raised;
    }

    Future<void> done(WidgetTester tester, _Device device) async {
      device.container.read(queueControllerProvider.notifier).clear();
      await settle(tester);
      await _end(tester, device);
    }

    /// [_track] downloaded, and the player built.
    String downloaded(_Device device) {
      device.downloads.byPid[_track] = testLocal('/downloads/A.flac');
      device.container.read(nowPlayingProvider.notifier);
      return Uri.file('/downloads/A.flac').toString();
    }

    testWidgets('on a downloaded track while the first connect is out plays '
        'it from the device at once, asking the server for nothing', (
      tester,
    ) async {
      final device = await _signedIn(tester);
      final local = downloaded(device);
      final queue = device.container.read(queueControllerProvider.notifier);

      queue.playNow([_track], source: _album);
      await settle(tester);
      expect(device.engine.current.connection, SyncConnection.connecting);
      // A track from a listing starts at its head, so there is nothing to
      // read either: no short wait.
      expect(device.server.playStateReads, isEmpty);
      expect(device.server.playInfoAsked, 0);
      expect(device.audio.loadedUrls, [local]);
      expect(device.audio.playing, isTrue);
      await done(tester, device);
    });

    testWidgets('on a downloaded episode while the first connect is out, its '
        'play state held, plays it from the device after the short wait, and '
        'the answer landing after changes nothing', (tester) async {
      final device = await _signedIn(tester);
      device.server
        ..libraryItems.add(testItem(_episode, mediaType: MediaType.podcast))
        ..addSubscription(testShow(_show))
        ..episodesByShow[_show] = [testEpisode(_episode, showPid: _show)]
        ..playPositions[_episode] = 40000;
      device.downloads.byPid[_episode] = testLocal('/downloads/EP.mp3');
      final local = Uri.file('/downloads/EP.mp3').toString();
      device.container.read(nowPlayingProvider.notifier);
      // The server takes the request and holds its answer.
      final held = device.server.playStateGate = Completer<void>();
      final queue = device.container.read(queueControllerProvider.notifier);

      queue.playNow([_episode], source: _album);
      await settle(tester);
      expect(device.engine.current.connection, SyncConnection.connecting);
      await tester.pump(
        PlaybackSession.unansweredStartWait - const Duration(milliseconds: 300),
      );
      expect(device.audio.loadedUrl, isNull, reason: 'the server has time');
      expect(device.server.playStateAsked, 1);

      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);
      expect(device.audio.loadedUrl, local);
      expect(device.audio.playing, isTrue);
      expect(device.server.playInfoAsked, 0);
      final loads = device.audio.loadedUrls.length;
      final seeks = device.audio.seekCalls.length;

      held.complete();
      await settle(tester);
      expect(device.audio.loadedUrls, hasLength(loads));
      expect(device.audio.seekCalls, hasLength(seeks));
      expect(device.audio.loadedUrl, local);
      expect(device.audio.playing, isTrue);
      await done(tester, device);
    });

    testWidgets('on a downloaded track on a session opened from memory plays '
        'it from the device at once, the server unasked', (tester) async {
      final device = await _signedIn(tester, serverAnswers: false);
      expect(device.net.attempts, hasLength(1), reason: 'its connect out');
      expect(device.engine.current.retrying, isTrue);
      final local = downloaded(device);

      device.container.read(queueControllerProvider.notifier).playNow([
        _track,
      ], source: _album);
      await settle(tester);
      expect(device.audio.loadedUrl, local);
      expect(device.audio.playing, isTrue);
      expect(device.server.playInfoAsked, 0);
      await done(tester, device);
    });

    testWidgets('on a downloaded track once the first connect failed plays it '
        'from the device at once, the server unasked; with the socket up it '
        'plays from the device too, the server asked for no media', (
      tester,
    ) async {
      final device = await _signedIn(tester);
      final local = downloaded(device);
      final queue = device.container.read(queueControllerProvider.notifier);
      device.net.attempts.single.fail();
      await settle(tester);
      expect(device.engine.current.retrying, isTrue);

      queue.playNow([_track], source: _album);
      await settle(tester);
      expect(device.audio.loadedUrl, local);
      expect(device.audio.playing, isTrue);
      expect(device.server.playInfoAsked, 0);

      await tester.pump(const Duration(seconds: 1));
      expect(device.net.attempts, hasLength(2));
      device.net.attempts.last.answer();
      await settle(tester);
      expect(device.engine.current.online, isTrue);
      queue.playNow([_track], source: _album);
      await settle(tester);
      expect(device.server.playInfoAsked, 0);
      expect(device.audio.loadedUrl, local);
      expect(device.audio.playing, isTrue);
      await done(tester, device);
    });

    _testFailedStart('while a first connect is out is not called offline, and '
        'starts by itself when that connect answers', (tester) async {
      final device = await _signedIn(tester);
      final heard = linkHeard(device);
      expect(heard, [null]);

      await press(tester, device);
      final title = device.container.read(nowPlayingProvider).item!.title;
      expect(said(device), _l10n.playerCouldNotStart(title));

      device.server.playInfoError = null;
      device.net.attempts.single.answer();
      await settle(tester);
      expect(heard, [null, true], reason: 'never down');
      expect(device.container.read(nowPlayingProvider).error, isNull);
      expect(device.audio.playing, isTrue);
      await done(tester, device);
    });

    _testFailedStart('while a first connect is out, which then fails: the link '
        'reads down, and it starts when a connect answers', (tester) async {
      final device = await _signedIn(tester);
      final heard = linkHeard(device);

      await press(tester, device);
      final title = device.container.read(nowPlayingProvider).item!.title;
      expect(said(device), _l10n.playerCouldNotStart(title));

      device.net.attempts.single.fail();
      await settle(tester);
      expect(heard, [null, false]);
      expect(device.audio.playing, isFalse);

      await tester.pump(const Duration(seconds: 1));
      expect(device.net.attempts, hasLength(2));
      device.server.playInfoError = null;
      device.net.attempts.last.answer();
      await settle(tester);
      expect(heard, [null, false, true]);
      expect(device.container.read(nowPlayingProvider).error, isNull);
      expect(device.audio.playing, isTrue);
      await done(tester, device);
    });

    _testFailedStart('while a first connect is out, which is seen to fail '
        'long after: no clock ran on it, and it starts when a connect '
        'answers', (tester) async {
      var now = DateTime.utc(2026, 10, 15, 12);
      final device = await _signedIn(tester, clock: () => now);
      final heard = linkHeard(device);
      await press(tester, device);

      // The process slept through the connect's deadline.
      now = now.add(const Duration(minutes: 5));
      device.net.attempts.single.fail();
      await settle(tester);
      expect(heard, [null, false]);
      expect(device.audio.playing, isFalse);

      await tester.pump(const Duration(seconds: 1));
      expect(device.net.attempts, hasLength(2));
      now = now.add(const Duration(minutes: 5));
      device.server.playInfoError = null;
      device.net.attempts.last.answer();
      await settle(tester);
      expect(device.container.read(nowPlayingProvider).error, isNull);
      expect(device.audio.playing, isTrue);
      await done(tester, device);
    });

    _testFailedStart('while a first connect is out says only that it could '
        'not start; when the link is then seen down the offer is raised '
        'again as offline, once, for the same bar', (tester) async {
      final device = await _signedIn(tester);
      final raised = raisedOn(device);
      await press(tester, device);
      final title = device.container.read(nowPlayingProvider).item!.title;
      expect(
        [for (final message in raised) message.resolve(_l10n)],
        [_l10n.playerCouldNotStart(title)],
      );

      device.net.attempts.single.fail();
      await settle(tester);
      expect(
        [for (final message in raised) message.resolve(_l10n)],
        [_l10n.playerCouldNotStart(title), _l10n.playerOfflineStart],
      );
      expect(raised.last.channel, ShellChannel.startRetry);
      expect(raised.last.channel, raised.first.channel);
      expect(raised.last.subject, raised.first.subject);
      expect(raised.last.actionSemanticsId, SemanticsIds.playerStartRetry);

      // The retry going out and failing says nothing more.
      await tester.pump(const Duration(seconds: 1));
      expect(device.net.attempts, hasLength(2));
      device.net.attempts.last.fail();
      await settle(tester);
      expect(raised, hasLength(2));
      expect(device.audio.playing, isFalse);
      await done(tester, device);
    });

    testWidgets('never made: the first connect starts nothing and reports '
        'nothing', (tester) async {
      final device = await _signedIn(tester);
      final heard = linkHeard(device);
      device.container.read(nowPlayingProvider.notifier);
      await settle(tester);

      device.net.attempts.single.answer();
      await settle(tester);
      expect(heard, [null, true]);
      expect(device.server.playInfoCalls, isEmpty);
      expect(device.server.reportedSessions, isEmpty);
      expect(device.audio.loadedUrl, isNull);
      expect(device.audio.playing, isFalse);
      expect(device.container.read(shellMessagesProvider), isNull);
      await _end(tester, device);
    });

    _testFailedStart('a queue put back at launch whose load failed for want of '
        'the server stays silent when the first connect answers', (
      tester,
    ) async {
      final device = await _signedIn(tester);
      device.server.playInfoError = _outOfReach;
      device.container
          .read(nowPlayingProvider.notifier)
          .restore(
            QueueState.fromStored(
              StoredQueue(
                entries: const [
                  StoredQueueEntry(queueId: 'q0', pid: _track, sourceRank: 0),
                ],
                currentIndex: 0,
                shuffled: false,
                repeat: 'off',
                sourceKind: 'album',
                sourceLabel: 'Kind of Blue',
                nextQueueId: 1,
                updatedAt: DateTime.utc(2026, 7, 25),
              ),
            ),
          );
      await settle(tester);
      expect(device.container.read(nowPlayingProvider).error, isNotNull);

      device.server.playInfoError = null;
      device.net.attempts.single.answer();
      await settle(tester);
      expect(device.audio.playing, isFalse);
      expect(device.container.read(nowPlayingProvider).session, isNull);
      await done(tester, device);
    });

    _testFailedStart('a stream that broke with the link up, which never went '
        'down, starts nothing when the engine starts again much later', (
      tester,
    ) async {
      var now = DateTime.utc(2026, 10, 15, 12);
      final device = await _signedIn(tester, clock: () => now);
      device.net.attempts.single.answer();
      await settle(tester);
      device.container.read(nowPlayingProvider.notifier);
      device.container.read(queueControllerProvider.notifier).playNow([
        _track,
      ], source: _album);
      await settle(tester);
      expect(device.audio.playing, isTrue, reason: 'precondition: it plays');
      device.server.playInfoError = _outOfReach;
      device.audio.failPlayback();
      await settle(tester);
      expect(device.container.read(nowPlayingProvider).error, isNotNull);
      device.server.playInfoError = null;

      now = now.add(const Duration(minutes: 5));
      await device.engine.stop();
      await settle(tester);
      await device.engine.start();
      await settle(tester);
      device.net.attempts.last.answer();
      await settle(tester);
      expect(device.engine.current.online, isTrue);
      expect(device.audio.playing, isFalse);
      await done(tester, device);
    });

    _testFailedStart('after a first connect that failed is called offline, and '
        'starts when a connect answers', (tester) async {
      final device = await _signedIn(tester);
      final heard = linkHeard(device);
      device.net.attempts.single.fail();
      await settle(tester);

      await press(tester, device);
      expect(said(device), _l10n.playerOfflineStart);

      // The retry, a second on, which hangs: still down, said once.
      await tester.pump(const Duration(seconds: 1));
      expect(device.net.attempts, hasLength(2));
      expect(heard, [null, false]);
      expect(device.audio.playing, isFalse);

      device.server.playInfoError = null;
      device.net.attempts.last.answer();
      await settle(tester);
      expect(heard, [null, false, true]);
      expect(device.container.read(nowPlayingProvider).error, isNull);
      expect(device.audio.playing, isTrue);
      await done(tester, device);
    });

    _testFailedStart(
      'after the socket dropped is called offline, and starts when '
      'the socket is up again',
      (tester) async {
        final device = await _signedIn(tester);
        final heard = linkHeard(device);
        device.net.attempts.single.answer();
        await settle(tester);
        device.net.attempts.single.drop();
        await settle(tester);

        await press(tester, device);
        expect(said(device), _l10n.playerOfflineStart);

        await tester.pump(const Duration(seconds: 1));
        expect(device.net.attempts, hasLength(2));
        expect(heard, [null, true, false]);

        device.server.playInfoError = null;
        device.net.attempts.last.answer();
        await settle(tester);
        expect(heard, [null, true, false, true]);
        expect(device.container.read(nowPlayingProvider).error, isNull);
        expect(device.audio.playing, isTrue);
        await done(tester, device);
      },
    );

    _testFailedStart(
      'on a remembered session, the connect still out, is called '
      'offline, and starts when the socket is up',
      (tester) async {
        final device = await _signedIn(tester, serverAnswers: false);
        final heard = linkHeard(device);
        expect(heard, [false]);
        // By what the engine was started knowing: its one attempt is out.
        expect(device.net.attempts, hasLength(1));
        expect(device.engine.current.retrying, isTrue);

        await press(tester, device);
        expect(said(device), _l10n.playerOfflineStart);

        device.server
          ..sessionError = null
          ..playInfoError = null;
        device.net.attempts.single.answer();
        await settle(tester);
        expect(heard, [false, true]);
        expect(device.container.read(nowPlayingProvider).error, isNull);
        expect(device.audio.playing, isTrue);
        await done(tester, device);
      },
    );

    _testFailedStart('on a remembered session a plain request then '
        'confirms: the link reads down until the socket is up, and the '
        'start is made then', (tester) async {
      final device = await _signedIn(tester, serverAnswers: false);
      final heard = linkHeard(device);
      await press(tester, device);
      expect(said(device), _l10n.playerOfflineStart);

      device.server.sessionError = null;
      final auth = device.container.read(authControllerProvider.notifier);
      expect(await auth.refreshSession(), SessionRecheck.stands);
      await settle(tester);
      expect(auth.unconfirmed, isFalse);
      expect(heard, [false]);
      expect(device.audio.playing, isFalse);

      device.server.playInfoError = null;
      device.net.attempts.single.answer();
      await settle(tester);
      expect(heard, [false, true]);
      expect(device.container.read(nowPlayingProvider).error, isNull);
      expect(device.audio.playing, isTrue);
      await done(tester, device);
    });
  });

  group('the player starts nothing when a first connect answers', () {
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(Duration.zero);
      }
    }

    /// A press of [pid] that fails as the server is set to fail it.
    Future<void> press(WidgetTester tester, _Device device, String pid) async {
      device.container.read(nowPlayingProvider.notifier);
      device.container.read(queueControllerProvider.notifier).playNow([
        pid,
      ], source: _album);
      await settle(tester);
      expect(device.container.read(nowPlayingProvider).error, isNotNull);
      expect(device.audio.playing, isFalse);
    }

    /// The connect answers, the server serving again: nothing is asked
    /// of it and nothing plays.
    Future<void> answersToSilence(WidgetTester tester, _Device device) async {
      final asked = device.server.playInfoAsked;
      device.server.playInfoError = null;
      device.net.attempts.single.answer();
      await settle(tester);
      expect(device.engine.current.online, isTrue);
      expect(device.server.playInfoAsked, asked);
      expect(device.audio.playing, isFalse);
      expect(device.container.read(nowPlayingProvider).session, isNull);

      device.container.read(queueControllerProvider.notifier).clear();
      await settle(tester);
      await _end(tester, device);
    }

    _testFailedStart('after a start the server refused for a reason no '
        'connect cures', (tester) async {
      final device = await _signedIn(tester);
      device.server.playInfoError = _notFound;
      await press(tester, device, _track);
      await answersToSilence(tester, device);
    });

    _testFailedStart('after a start that failed for want of the server and '
        'a press of pause', (tester) async {
      final device = await _signedIn(tester);
      device.server.playInfoError = _outOfReach;
      await press(tester, device, _track);
      await device.container.read(nowPlayingProvider.notifier).transportPause();
      await settle(tester);
      await answersToSilence(tester, device);
    });

    _testFailedStart('after a start that failed for want of the server and '
        'another choice, which the server refused', (tester) async {
      final device = await _signedIn(tester);
      device.server.playInfoError = _outOfReach;
      await press(tester, device, _track);
      device.server.playInfoError = _notFound;
      await press(tester, device, _other);
      await answersToSilence(tester, device);
    });
  });

  testWidgets('the link is heard again after the engine stopped and '
      'started', (tester) async {
    final device = await _signedIn(tester);
    final heard = <bool?>[];
    final link = device.container.listen(
      liveConnectionProvider,
      (_, next) => heard.add(next),
      fireImmediately: true,
    );
    addTearDown(link.close);
    device.net.attempts.single.answer();
    for (var i = 0; i < 6; i++) {
      await tester.pump(Duration.zero);
    }
    expect(heard, [null, true]);

    await device.engine.stop();
    await tester.pump(Duration.zero);
    expect(heard, [null, true, null]);

    await device.engine.start();
    await tester.pump(Duration.zero);
    device.net.attempts.last.answer();
    for (var i = 0; i < 6; i++) {
      await tester.pump(Duration.zero);
    }
    expect(heard, [null, true, null, true]);
    await _end(tester, device);
  });

  testWidgets('the server build watcher takes the first connect as its '
      'baseline and looks again at a return', (tester) async {
    final device = await _signedIn(tester);
    final updated = device.container.listen(serverUpdatedProvider, (_, _) {});
    addTearDown(updated.close);

    device.net.attempts.single.answer();
    for (var i = 0; i < 6; i++) {
      await tester.pump(Duration.zero);
    }
    expect(updated.read(), isFalse);

    // The server comes back as another build.
    device.server.serverVersion = '1.1.0';
    device.net.attempts.single.drop();
    await tester.pump(const Duration(seconds: 1));
    device.net.attempts.last.answer();
    for (var i = 0; i < 6; i++) {
      await tester.pump(Duration.zero);
    }
    expect(updated.read(), isTrue);
    await _end(tester, device);
  });

  testWidgets('the server build watcher drops an answer still out when the '
      'app is pointed at another server: it is not that server\'s baseline', (
    tester,
  ) async {
    final device = await _signedIn(tester);
    final updated = device.container.listen(serverUpdatedProvider, (_, _) {});
    addTearDown(updated.close);
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(Duration.zero);
      }
    }

    // The first server's build is asked for, and the answer held.
    final held = device.server.buildGate = Completer<void>();
    device.net.attempts.single.answer();
    await settle();
    expect(device.server.buildAsked, 1);

    await device.container
        .read(serverAddressProvider.notifier)
        .adopt('http://other.test');
    device.server
      ..serverVersion = '2.0.0'
      ..buildGate = null;
    await settle();
    held.complete();
    await settle();
    expect(updated.read(), isFalse);

    // The other server, back on the build it was first seen on.
    device.net.attempts.single.drop();
    await tester.pump(const Duration(seconds: 1));
    device.net.attempts.last.answer();
    await settle();
    expect(updated.read(), isFalse);
    expect(device.server.buildAsked, 3, reason: 'each was a real read');
    await _end(tester, device);
  });

  group('the rule', () {
    testWidgets('and the artwork store\'s differ while a first connect is '
        'out: not offline, and not known to be in reach', (tester) async {
      final device = await _signedIn(tester);
      expect(device.engine.current.connection, SyncConnection.connecting);

      expect(device.container.read(offlineProvider), isFalse);
      expect(device.container.read(_reach)(), isFalse);

      device.net.attempts.single.answer();
      await tester.pump(Duration.zero);
      expect(device.container.read(offlineProvider), isFalse);
      expect(device.container.read(_reach)(), isTrue);
      await _end(tester, device);
    });

    testWidgets('is the same to a reader that arrives during a retry, with '
        'nobody watching in between', (tester) async {
      final device = await _signedIn(tester);
      device.net.attempts.single.fail();
      await tester.pump(Duration.zero);
      // The retry, a second on, which hangs.
      await tester.pump(const Duration(seconds: 1));
      expect(device.net.attempts, hasLength(2));
      expect(device.engine.current.connection, SyncConnection.connecting);

      expect(device.container.read(offlineProvider), isTrue);
      // The reader gone, and the provider with it.
      await tester.pump(Duration.zero);
      expect(device.container.exists(offlineProvider), isFalse);
      expect(device.container.read(offlineProvider), isTrue);

      device.net.attempts.last.answer();
      await tester.pump(Duration.zero);
      expect(device.container.read(offlineProvider), isFalse);
      await _end(tester, device);
    });

    testWidgets('holds through a session controller built again and answered '
        'over a remembered session, until the socket is up', (tester) async {
      final device = await _signedIn(tester, serverAnswers: false);
      final said = <bool>[];
      final watched = device.container.listen(
        offlineProvider,
        (_, next) => said.add(next),
        fireImmediately: true,
      );
      addTearDown(watched.close);
      expect(said, [true]);

      // The server answers the next build.
      device.server.sessionError = null;
      device.container.invalidate(authControllerProvider);
      await tester.pump(Duration.zero);
      expect(
        device.container.read(authControllerProvider.notifier).unconfirmed,
        isFalse,
      );
      expect(said, [true]);

      device.net.attempts.single.answer();
      await tester.pump(Duration.zero);
      expect(said, [true, false]);
      await _end(tester, device);
    });
  });

  test('a book\'s marks opened while a first connect is out are read from '
      'the server first, as online', () async {
    final db = inMemoryMirrorDatabase();
    addTearDown(db.close);
    final server = _Server();
    final net = _Net();
    final engine = SyncEngine(
      db: db,
      repository: server,
      channelFactory: net.factory,
    )..account = _ann.id;
    addTearDown(engine.dispose);
    // What the mirror holds from an earlier session, and what the server
    // holds now.
    await engine.storeBookmarks(_book, [
      Bookmark(id: 'bm-old', positionMs: 1000, createdAt: DateTime.utc(2026)),
    ], owner: _ann.id);
    server.bookmarks[_book] = [
      Bookmark(id: 'bm-new', positionMs: 2000, createdAt: DateTime.utc(2026)),
    ];
    final container = appContainer(
      repo: server,
      sync: engine,
      mirror: db,
      extra: [signedInAccountProvider.overrideWithValue(_ann.id)],
    );
    await engine.start();
    expect(engine.current.connection, SyncConnection.connecting);

    final held = server.listBookmarksGate = Completer<void>();
    final shown = <List<String>>[];
    final marks = container.listen(bookmarksProvider(_book), (_, next) {
      if (next.value case final list?) {
        shown.add([for (final mark in list) mark.mark.id]);
      }
    });
    addTearDown(marks.close);
    await pumpEventQueue();
    expect(server.listBookmarksCalls, 1);
    expect(shown, isEmpty, reason: 'the mirror alone is not shown first');

    held.complete();
    await container.read(bookmarksProvider(_book).future);
    expect(shown, [
      ['bm-new'],
    ]);
  });
}
