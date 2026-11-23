import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'app_host.dart';
import 'fakes.dart';

/// A device on the sign-in, setup or connect screen because its server was
/// out of reach keeps asking after Riverpod's own asking has stopped, at a
/// pace that grows to about a minute, until the server answers; then it
/// goes where the answer says, with no touch.

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

/// A server whose session read and first-run probe fail, as with it out
/// of reach, while down; each read noted with when it was asked.
class _Server extends FakeRepository {
  _Server({super.sessionState, super.bootstrapNeeded})
    : super(items: [testItem('tr-A')]);

  var down = false;

  /// What a session read fails with, out of reach or not.
  WaxDeckApiException? sessionFailure;

  /// The test's clock, which [_Start] moves.
  var now = Duration.zero;
  final asked = <Duration>[];
  final sessionAsked = <Duration>[];
  var probes = 0;
  var sessionReads = 0;

  @override
  Future<SessionState> getSession() async {
    sessionReads++;
    asked.add(now);
    sessionAsked.add(now);
    if (sessionFailure case final failure?) throw failure;
    if (down) throw _lost;
    return super.getSession();
  }

  @override
  Future<BootstrapStatus> bootstrapStatus() async {
    probes++;
    asked.add(now);
    if (down) throw _lost;
    return super.bootstrapStatus();
  }

  @override
  Future<List<OidcProvider>> oidcProviders() async {
    if (down) throw _lost;
    return super.oidcProviders();
  }

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
final _outOfReach = find.text(AppLocalizationsEn().errorNetwork);

String _drawn() => [
  if (_form.evaluate().isNotEmpty) 'sign-in',
  if (_setup.evaluate().isNotEmpty) 'setup',
  if (_home.evaluate().isNotEmpty) 'home',
].join('+');

/// The whole app over [server], its clock moved a second at a time.
class _Start {
  _Start(this.tester, this.server);

  final WidgetTester tester;
  final _Server server;
  late final ProviderContainer container;

  Future<void> open({InMemoryCredentialStore? store}) async {
    container = appContainer(repo: server, credentials: store);
    await mountHost(tester, const WaxDeckApp(), container: container);
    await wait(const Duration(seconds: 1));
  }

  Future<void> wait(Duration time) async {
    for (var left = time; left > Duration.zero;) {
      final step = left < const Duration(seconds: 1)
          ? left
          : const Duration(seconds: 1);
      await tester.pump(step);
      server.now += step;
      left -= step;
      expect(tester.takeException(), isNull);
    }
  }
}

/// Past Riverpod's own asking, which stops about forty seconds in.
const _pastTheLadder = Duration(seconds: 60);

/// Riverpod's last asking: its waits add up to 38.2 seconds.
const _ladderDone = Duration(seconds: 38);

/// Longer than any one wait of the asking after it.
const _oneAsking = Duration(seconds: 62);

void main() {
  for (final (answer, lands, token) in [
    ('signed out', 'sign-in', false),
    ('for the token held', 'home', true),
    ('that the server has no accounts', 'setup', false),
  ]) {
    testWidgets('out of reach past Riverpod\'s asking, then back: the server '
        'is asked again and answers $answer, and the app goes there with no '
        'touch', (tester) async {
      final server = _Server(
        sessionState: token ? _anns : null,
        bootstrapNeeded: lands == 'setup',
      )..down = true;
      final start = _Start(tester, server);
      await start.open(
        store: token ? (InMemoryCredentialStore()..token = 'token-ann') : null,
      );
      await start.wait(_pastTheLadder);
      expect(_drawn(), 'sign-in');
      expect(_outOfReach, findsOneWidget);

      server.down = false;
      await start.wait(_oneAsking);
      expect(_drawn(), lands);
      expect(_outOfReach, findsNothing);
    });
  }

  testWidgets('asks no faster than Riverpod\'s last wait and no slower than '
      'about a minute while the server stays out of reach', (tester) async {
    final server = _Server()..down = true;
    final start = _Start(tester, server);
    await start.open();
    await start.wait(const Duration(minutes: 10));
    expect(_drawn(), 'sign-in');

    // From Riverpod's last asking on.
    final after = server.asked.sublist(
      server.asked.lastIndexWhere((at) => at <= _ladderDone),
    );
    expect(after.length, greaterThan(5));
    final gaps = [
      for (var i = 1; i < after.length; i++) after[i] - after[i - 1],
    ];
    for (final gap in gaps) {
      expect(gap, greaterThanOrEqualTo(const Duration(seconds: 6)));
      expect(gap, lessThanOrEqualTo(const Duration(seconds: 61)));
    }
    expect(gaps.last, greaterThanOrEqualTo(const Duration(seconds: 59)));
  });

  testWidgets('a server whose probe answers while its session read stays out '
      'of reach is asked at a pace that grows to about a minute, and once it '
      'answers both the asking ends', (tester) async {
    final server = _Server()..sessionFailure = _lost;
    final start = _Start(tester, server);
    await start.open();
    await start.wait(const Duration(minutes: 10));
    expect(_drawn(), 'sign-in');
    expect(_outOfReach, findsOneWidget);

    // From Riverpod's last asking on.
    final after = server.sessionAsked.sublist(
      server.sessionAsked.lastIndexWhere((at) => at <= _ladderDone),
    );
    // A wait of 6.4 s doubling to a minute: about a dozen asks over the
    // ten minutes, where one every 6.4 s would be near ninety.
    expect(after.length, lessThanOrEqualTo(15));
    expect(server.probes, lessThanOrEqualTo(15));
    final gaps = [
      for (var i = 1; i < after.length; i++) after[i] - after[i - 1],
    ];
    expect(gaps.length, greaterThan(5));
    for (var i = 0; i < gaps.length; i++) {
      expect(gaps[i], greaterThanOrEqualTo(const Duration(seconds: 6)));
      expect(gaps[i], lessThanOrEqualTo(const Duration(seconds: 61)));
      // The clock moves a second at a time.
      if (i > 0) {
        expect(
          gaps[i],
          greaterThanOrEqualTo(gaps[i - 1] - const Duration(seconds: 1)),
        );
      }
    }
    expect(gaps.last, greaterThanOrEqualTo(const Duration(seconds: 59)));

    server.sessionFailure = null;
    await start.wait(_oneAsking);
    expect(_drawn(), 'sign-in');
    expect(_outOfReach, findsNothing);
    final asked = server.asked.length;
    await start.wait(const Duration(minutes: 5));
    expect(server.asked.length, asked);
  });

  testWidgets('a refusal is not asked again', (tester) async {
    final server = _Server()
      ..sessionFailure = const WaxDeckApiException(
        code: 'forbidden',
        message: 'not from here',
        statusCode: 403,
      );
    final start = _Start(tester, server);
    await start.open();
    expect(_drawn(), 'sign-in');
    final asked = server.asked.length;

    await start.wait(const Duration(minutes: 5));
    expect(server.sessionReads, 1);
    expect(server.asked.length, asked);
  });

  testWidgets('stops asking once someone signs in', (tester) async {
    final server = _Server()..down = true;
    final start = _Start(tester, server);
    await start.open();
    await start.wait(_pastTheLadder);

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.loginUsername),
      'admin',
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.loginPassword),
      'pw',
    );
    await tester.tap(_form);
    await start.wait(const Duration(seconds: 2));
    expect(_drawn(), 'home');

    final asked = server.asked.length;
    await start.wait(const Duration(minutes: 5));
    expect(server.asked.length, asked);
  });

  testWidgets('stops asking once the screen goes, and leaves no timer '
      'behind', (tester) async {
    final server = _Server()..down = true;
    final start = _Start(tester, server);
    await start.open();
    await start.wait(_pastTheLadder);
    expect(_drawn(), 'sign-in');

    await tester.pumpWidget(const SizedBox());
    final asked = server.asked.length;
    await start.wait(const Duration(minutes: 5));
    expect(server.asked.length, asked);
  });
}
