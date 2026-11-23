import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

/// The boot gate holds the first frame while a start's reads are out, and
/// no longer: a read that failed is answered as far as the gate goes, so a
/// device whose server is out of reach gets the sign-in form, and the way
/// to another server, while the app keeps asking behind it.

const _ann = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDACCANN',
  username: 'ann',
  roles: ['user'],
);
const _anns = SessionState(authenticated: true, user: _ann);

const _lost = WaxDeckApiException(
  code: 'transport',
  message: 'connection refused',
);

/// A server whose session read and first-run probe each fail, as with the
/// server out of reach, while down, and wait while held.
class _Server extends FakeRepository {
  _Server({super.sessionState, super.bootstrapNeeded})
    : super(items: [testItem('tr-A')]);

  var sessionDown = false;
  var probeDown = false;

  /// What a session read fails with while down.
  var sessionFailure = _lost;
  Completer<void>? sessionHeld;
  Completer<void>? probeHeld;
  var sessionReads = 0;
  var probes = 0;

  set down(bool down) => sessionDown = probeDown = down;

  @override
  Future<SessionState> getSession() async {
    sessionReads++;
    await sessionHeld?.future;
    if (sessionDown) throw sessionFailure;
    return super.getSession();
  }

  @override
  Future<BootstrapStatus> bootstrapStatus() async {
    probes++;
    await probeHeld?.future;
    if (probeDown) throw _lost;
    return super.bootstrapStatus();
  }

  @override
  Future<List<OidcProvider>> oidcProviders() async {
    if (sessionDown) throw _lost;
    return super.oidcProviders();
  }

  /// A rotation answers for whoever holds the session.
  @override
  Future<LoginResult> refreshToken() async {
    refreshCalls++;
    authToken = 'rotated-token';
    return LoginResult(
      user: sessionState.user!,
      token: 'rotated-token',
      sessionId: sessionState.sessionId ?? 'se-rotated-token',
    );
  }
}

final _form = find.bySemanticsIdentifier(SemanticsIds.loginSubmit);
final _setup = find.bySemanticsIdentifier(SemanticsIds.setupSubmit);
final _home = find.bySemanticsIdentifier(SemanticsIds.homeScreen);
final _connect = find.bySemanticsIdentifier(SemanticsIds.connectServerAddress);
final _outOfReach = find.text(AppLocalizationsEn().errorNetwork);

/// What is drawn, by name: `emblem` is the gate's own bare screen.
String _drawn() {
  final up = [
    if (_form.evaluate().isNotEmpty) 'sign-in',
    if (_setup.evaluate().isNotEmpty) 'setup',
    if (_home.evaluate().isNotEmpty) 'home',
    if (_connect.evaluate().isNotEmpty) 'connect',
  ];
  if (up.isNotEmpty) return up.join('+');
  return find.byType(WaxWordmark).evaluate().isEmpty ? 'nothing' : 'emblem';
}

/// A start of the whole app, watched frame by frame. Every pump is timed:
/// a bare one draws only a frame that is already scheduled.
class _Start {
  _Start(this.tester);

  final WidgetTester tester;
  late final ProviderContainer container;

  /// What was drawn, each change of it, from the first frame on.
  final seen = <String>[];

  static const _frame = Duration(milliseconds: 50);

  Future<void> open({
    required _Server server,
    InMemoryCredentialStore? store,
    bool configured = true,
  }) async {
    container = appContainer(
      repo: server,
      credentials: store,
      extra: [
        if (!configured) bootServerAddressProvider.overrideWithValue(null),
      ],
    );
    await mountHost(tester, const WaxDeckApp(), container: container);
    _look();
  }

  void _look() {
    expect(tester.takeException(), isNull);
    final now = _drawn();
    if (seen.isEmpty || seen.last != now) seen.add(now);
  }

  Future<void> frames(int count) async {
    for (var frame = 0; frame < count; frame++) {
      await tester.pump(_frame);
      _look();
    }
  }

  /// Frames for [time].
  Future<void> wait(Duration time) =>
      frames(time.inMilliseconds ~/ _frame.inMilliseconds);
}

/// Longer than the wait before any one of Riverpod's rebuilds of a read
/// that failed.
const _oneRung = Duration(seconds: 7);

/// Longer than all of them together.
const _everyRung = Duration(seconds: 45);

void main() {
  group('a start with nothing remembered and the server out of reach', () {
    testWidgets('opens on the sign-in form once the first read has failed, '
        'stays on it while the app keeps asking, and still says the server '
        'was out of reach once the app has stopped', (tester) async {
      final server = _Server()
        ..down = true
        ..sessionHeld = Completer<void>()
        ..probeHeld = Completer<void>();
      final start = _Start(tester);
      await start.open(server: server);

      // The reads are out: the emblem, for as long as they are.
      await start.wait(const Duration(seconds: 1));
      expect(start.seen, ['emblem']);

      // Both fail. The form is up before either is asked again.
      server.sessionHeld!.complete();
      server.probeHeld!.complete();
      await start.frames(2);
      expect(start.seen, ['emblem', 'sign-in']);
      expect(server.sessionReads, 1);
      expect(server.probes, 1);
      expect(_outOfReach, findsOneWidget);

      await tester.enterText(
        find.bySemanticsIdentifier(SemanticsIds.loginUsername),
        'frodo',
      );
      await start.wait(_everyRung);
      expect(start.seen, ['emblem', 'sign-in']);
      expect(server.sessionReads, greaterThan(1));
      expect(find.widgetWithText(WaxTextField, 'frodo'), findsOneWidget);
      expect(_outOfReach, findsOneWidget);
    });

    testWidgets('opens on it when only the first-run probe failed, and '
        'says nothing of the server', (tester) async {
      final server = _Server()
        ..probeDown = true
        ..probeHeld = Completer<void>();
      final start = _Start(tester);
      await start.open(server: server);
      await start.wait(const Duration(seconds: 1));
      expect(start.seen, ['emblem']);

      server.probeHeld!.complete();
      await start.frames(2);
      expect(start.seen, ['emblem', 'sign-in']);
      expect(server.probes, 1);
      expect(_outOfReach, findsNothing);
    });

    testWidgets('opens on it when the server answered with a failure of its '
        'own, and says nothing of reach', (tester) async {
      final server = _Server()
        ..sessionDown = true
        ..sessionFailure = const WaxDeckApiException(
          code: 'internal',
          message: 'catalog not open',
          statusCode: 500,
        );
      final start = _Start(tester);
      await start.open(server: server);
      await start.frames(2);
      expect(start.seen, ['emblem', 'sign-in']);
      expect(find.bySemanticsIdentifier(SemanticsIds.loginError), findsNothing);
    });

    testWidgets('has Change server in reach, which stays up while the app '
        'keeps asking', (tester) async {
      final server = _Server()..down = true;
      final start = _Start(tester);
      await start.open(server: server);
      await start.frames(2);
      expect(start.seen.last, 'sign-in');

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.connectServerOpen),
      );
      await start.wait(const Duration(seconds: 1));
      expect(_connect, findsOneWidget);

      final asked = server.sessionReads;
      await start.wait(_oneRung);
      expect(server.sessionReads, greaterThan(asked));
      expect(_connect, findsOneWidget);
    });

    testWidgets('gives the line to a refusal of what was typed, while the '
        'app keeps asking', (tester) async {
      final server = _Server()..sessionDown = true;
      final start = _Start(tester);
      await start.open(server: server);
      await start.frames(2);
      expect(start.seen.last, 'sign-in');
      expect(_outOfReach, findsOneWidget);

      // The sign-in reaches the server, which says no; the reads still fail.
      server.loginError = const WaxDeckApiException(
        code: 'unauthenticated',
        message: 'invalid credentials',
        statusCode: 401,
      );
      await tester.enterText(
        find.bySemanticsIdentifier(SemanticsIds.loginUsername),
        'frodo',
      );
      await tester.enterText(
        find.bySemanticsIdentifier(SemanticsIds.loginPassword),
        'no',
      );
      await tester.tap(_form);
      await start.frames(2);
      final refused = find.text(AppLocalizationsEn().authSignInRejected);
      expect(refused, findsOneWidget);
      expect(_outOfReach, findsNothing);

      final asked = server.sessionReads;
      await start.wait(_oneRung);
      expect(server.sessionReads, greaterThan(asked));
      expect(refused, findsOneWidget);
      expect(_outOfReach, findsNothing);
      expect(start.seen.last, 'sign-in');
    });

    testWidgets('keeps the form up when a later read answers signed out, '
        'and no longer says the server is out of reach', (tester) async {
      final server = _Server()..down = true;
      final start = _Start(tester);
      await start.open(server: server);
      await start.frames(2);
      expect(start.seen.last, 'sign-in');
      expect(_outOfReach, findsOneWidget);

      server.down = false;
      await start.wait(_oneRung);
      expect(start.seen, ['emblem', 'sign-in']);
      expect(_outOfReach, findsNothing);
    });

    testWidgets('moves to setup when a later probe answers that the server '
        'has no accounts', (tester) async {
      final server = _Server(bootstrapNeeded: true)..down = true;
      final start = _Start(tester);
      await start.open(server: server);
      await start.frames(2);
      expect(start.seen.last, 'sign-in');

      server.down = false;
      await start.wait(_oneRung);
      await start.wait(const Duration(seconds: 1));
      expect(start.seen.last, 'setup');
    });

    testWidgets('moves to Home when a later read answers for the token '
        'held', (tester) async {
      // A token with no session kept for it: nothing to open on.
      final server = _Server(sessionState: _anns)..down = true;
      final start = _Start(tester);
      await start.open(
        server: server,
        store: InMemoryCredentialStore()..token = 'token-ann',
      );
      await start.frames(2);
      expect(start.seen.last, 'sign-in');

      server.down = false;
      await start.wait(_oneRung);
      await start.wait(const Duration(seconds: 1));
      expect(start.seen.last, 'home');
    });

    testWidgets('signed in from the form while the app is still asking, '
        'stays on Home when the next asking answers', (tester) async {
      final server = _Server()..down = true;
      final store = InMemoryCredentialStore();
      final start = _Start(tester);
      await start.open(server: server, store: store);
      // Past the quick rungs, to one with seconds before the next.
      await start.wait(const Duration(seconds: 4));
      expect(start.seen, ['emblem', 'sign-in']);

      // The server is back; the sign-in's answer is the newer word, so
      // nothing is said of reach while it is out.
      server
        ..down = false
        ..loginGate = Completer<void>();
      await tester.enterText(
        find.bySemanticsIdentifier(SemanticsIds.loginUsername),
        'admin',
      );
      await tester.enterText(
        find.bySemanticsIdentifier(SemanticsIds.loginPassword),
        'pw',
      );
      expect(_outOfReach, findsOneWidget);
      await tester.tap(_form);
      await start.frames(2);
      expect(_outOfReach, findsNothing);
      server.loginGate!.complete();
      await start.wait(const Duration(seconds: 1));
      expect(start.seen.last, 'home');
      final signedIn = start.container.read(signedInAccountProvider);
      expect(signedIn, isNotNull);
      final asked = server.sessionReads;

      await start.wait(_oneRung);
      expect(server.sessionReads, greaterThan(asked));
      expect(start.seen.last, 'home');
      expect(start.seen.where((drawn) => drawn == 'home'), hasLength(1));
      expect(start.container.read(signedInAccountProvider), signedIn);
      expect(store.token, server.authToken);
    });
  });

  group('a start that opens as it always has', () {
    testWidgets('with a session remembered and the server out of reach: '
        'Home, and never the sign-in form', (tester) async {
      final server = _Server(sessionState: _anns)..down = true;
      final start = _Start(tester);
      await start.open(
        server: server,
        store: InMemoryCredentialStore()
          ..token = 'token-ann'
          ..session = rememberedRecord('token-ann', _anns.toStored()),
      );

      await start.wait(const Duration(seconds: 2));
      expect(start.seen, ['emblem', 'home']);
      expect(_outOfReach, findsNothing);
    });

    testWidgets('with a session remembered and a server that hangs: the '
        'emblem for the stated wait, then Home', (tester) async {
      final server = _Server(sessionState: _anns)
        ..sessionHeld = Completer<void>();
      final start = _Start(tester);
      await start.open(
        server: server,
        store: InMemoryCredentialStore()
          ..token = 'token-ann'
          ..session = rememberedRecord('token-ann', _anns.toStored()),
      );

      await start.wait(kRememberedSessionWait - const Duration(seconds: 1));
      expect(start.seen, ['emblem']);
      await start.wait(const Duration(seconds: 2));
      expect(start.seen, ['emblem', 'home']);
      server.sessionHeld!.complete();
      await start.frames(2);
    });

    for (final (answer, lands) in [
      ('signed out', 'sign-in'),
      ('for a session', 'home'),
      ('that the server has no accounts', 'setup'),
    ]) {
      testWidgets('whose reads are slow and answer $answer: the emblem '
          'until they do, and no form before', (tester) async {
        final server =
            _Server(
                sessionState: lands == 'home' ? _anns : null,
                bootstrapNeeded: lands == 'setup',
              )
              ..sessionHeld = Completer<void>()
              ..probeHeld = Completer<void>();
        final start = _Start(tester);
        await start.open(server: server);

        // Longer than a remembered session would be waited for.
        await start.wait(kRememberedSessionWait * 2);
        expect(start.seen, ['emblem']);
        expect(server.sessionReads, 1);

        server.sessionHeld!.complete();
        await start.frames(2);
        if (lands != 'home') expect(start.seen, ['emblem']);
        server.probeHeld!.complete();
        await start.wait(const Duration(seconds: 1));
        expect(start.seen, ['emblem', lands]);
        expect(_outOfReach, findsNothing);
      });
    }

    testWidgets('unconfigured, on native: the connect gate, with no read '
        'asked and no form', (tester) async {
      final server = _Server()..down = true;
      final start = _Start(tester);
      await start.open(server: server, configured: false);

      await start.wait(const Duration(seconds: 2));
      expect(start.seen, ['emblem', 'connect']);
      expect(server.sessionReads, 0);
      expect(server.probes, 0);
      expect(_outOfReach, findsNothing);
    });
  });
}
