import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// Override lives here rather than in the root library.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/oidc_flow.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/settings/integrations_sections.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';
import 'wax_finders.dart';

/// The switch inside one event row. The key names the row; the control
/// is what a tap has to land on.
Finder _eventSwitch(String event) => find.descendant(
  of: find.byKey(ValueKey('notify-event-$event')),
  matching: find.byType(WaxSwitch),
);

const _admin = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  username: 'admin',
  displayName: 'The Admin',
  roles: ['admin'],
);

Future<void> _mount(
  WidgetTester tester,
  FakeRepository repo,
  Widget child, {
  List<Override> extra = const <Override>[],
}) => mountApp(
  tester,
  Scaffold(body: ListView(children: [child])),
  container: appContainer(repo: repo, extra: extra),
  routed: false,
);

FakeRepository _adminRepo() => FakeRepository(
  sessionState: const SessionState(authenticated: true, user: _admin),
);

/// A server whose credential state cannot be read: the first read fails
/// at once and every retry waits, as on a server that has gone away.
class _ConfigDown extends FakeRepository {
  _ConfigDown()
    : super(
        sessionState: const SessionState(authenticated: true, user: _admin),
      );

  var _reads = 0;

  @override
  Future<ScrobblingAdminConfig> getScrobblingConfig() async {
    if (_reads++ > 0) await Completer<void>().future;
    throw const WaxDeckApiException(
      code: 'internal',
      message: 'down',
      statusCode: 500,
    );
  }
}

/// The reads named in [down] fail as a restarting server's do, until
/// taken out of it.
class _ReadsDown extends FakeRepository {
  _ReadsDown(this.down)
    : super(
        sessionState: const SessionState(authenticated: true, user: _admin),
      );

  final Set<String> down;

  /// How many times each read has been asked, failed or not.
  final reads = <String, int>{};

  Future<T> _read<T>(String name, Future<T> Function() read) async {
    reads[name] = (reads[name] ?? 0) + 1;
    if (down.contains(name)) {
      throw const WaxDeckApiException(
        code: 'internal',
        message: 'boom',
        statusCode: 500,
      );
    }
    return read();
  }

  @override
  Future<List<Scrobbler>> listScrobblers() =>
      _read('scrobblers', super.listScrobblers);

  @override
  Future<List<AppPassword>> listAppPasswords() =>
      _read('passwords', super.listAppPasswords);

  @override
  Future<List<NotificationTarget>> listMyNotificationTargets() =>
      _read('targets', super.listMyNotificationTargets);

  @override
  Future<List<NotifyEvent>> listNotificationEvents() =>
      _read('catalog', super.listNotificationEvents);

  @override
  Future<ScrobblingAdminConfig> getScrobblingConfig() =>
      _read('lastfm', super.getScrobblingConfig);
}

/// Last.fm's connect and disconnect held until [release], counted.
class _HeldLastfm extends FakeRepository {
  final release = Completer<void>();
  var asked = 0;

  @override
  Future<String> startLastfmConnect() async {
    asked++;
    await release.future;
    return super.startLastfmConnect();
  }

  @override
  Future<void> disconnectLastfm() async {
    asked++;
    await release.future;
    return super.disconnectLastfm();
  }
}

/// Records what the app asked the platform to open.
class _Opener implements UrlOpenerPort {
  final opened = <String>[];

  @override
  Future<void> open(String url) async => opened.add(url);
}

/// Deletes that wait for [release], then fail as a dropped connection
/// does, counted.
class _FailingDeletes extends FakeRepository {
  final release = Completer<void>();
  var deletes = 0;

  static const _dropped = WaxDeckApiException(
    code: 'transport',
    message: 'DioException [connection error]',
  );

  @override
  Future<void> deleteMyNotificationTarget(String pid) async {
    deletes++;
    await release.future;
    throw _dropped;
  }

  @override
  Future<void> revokeAppPassword(String id) async {
    deletes++;
    await release.future;
    throw _dropped;
  }
}

/// A repository whose named reads wait on [hold], to look at a section
/// while it loads.
class _Holding extends FakeRepository {
  _Holding({super.sessionState});

  final hold = Completer<void>();
  bool holdScrobblers = false;
  bool holdAppPasswords = false;
  bool holdCatalog = false;
  bool holdTargets = false;
  bool holdLastfmConfig = false;

  @override
  Future<List<Scrobbler>> listScrobblers() async {
    if (holdScrobblers) await hold.future;
    return super.listScrobblers();
  }

  @override
  Future<List<AppPassword>> listAppPasswords() async {
    if (holdAppPasswords) await hold.future;
    return super.listAppPasswords();
  }

  @override
  Future<List<NotifyEvent>> listNotificationEvents() async {
    if (holdCatalog) await hold.future;
    return super.listNotificationEvents();
  }

  @override
  Future<List<NotificationTarget>> listMyNotificationTargets() async {
    if (holdTargets) await hold.future;
    return super.listMyNotificationTargets();
  }

  @override
  Future<ScrobblingAdminConfig> getScrobblingConfig() async {
    if (holdLastfmConfig) await hold.future;
    return super.getScrobblingConfig();
  }
}

/// A window shorter than the default six-row skeleton, so a ghost that
/// does not fit its space throws an overflow here.
void useShortWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 320);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Plays a dialog's entrance in full: a route fades in from nothing, and
/// nothing unpainted is ever checked for overflow. The skeleton animates
/// for good, so this cannot settle.
Future<void> playDialogTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void expectSkeletonNotSpinner() {
  expect(find.byType(SkeletonShapes), findsOneWidget);
  expect(find.byType(WaxSpinner), findsNothing);
}

void main() {
  group('while loading', () {
    testWidgets('the scrobbler slots draw a skeleton, not a spinner', (
      tester,
    ) async {
      useShortWindow(tester);
      final repo = _Holding()..holdScrobblers = true;
      await _mount(tester, repo, const ScrobblingSection());
      await tester.pump();
      expectSkeletonNotSpinner();
    });

    testWidgets('the app passwords draw a skeleton, not a spinner', (
      tester,
    ) async {
      useShortWindow(tester);
      final repo = _Holding()..holdAppPasswords = true;
      await _mount(tester, repo, const AppPasswordsSection());
      await tester.pump();
      expectSkeletonNotSpinner();
    });

    testWidgets('the target list draws a skeleton, not a spinner', (
      tester,
    ) async {
      useShortWindow(tester);
      final repo = _Holding()..holdTargets = true;
      await _mount(tester, repo, const PersonalNotificationTargetsSection());
      await tester.pump();
      expectSkeletonNotSpinner();
    });

    testWidgets('the editor checklist draws a skeleton, not a spinner', (
      tester,
    ) async {
      useShortWindow(tester);
      final repo = _Holding()..holdCatalog = true;
      await _mount(tester, repo, const PersonalNotificationTargetsSection());
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.notifyTargetAdd),
      );
      await playDialogTransition(tester);
      expectSkeletonNotSpinner();
    });

    testWidgets('the Last.fm credentials dialog draws a skeleton', (
      tester,
    ) async {
      useShortWindow(tester);
      final repo = _Holding(
        sessionState: const SessionState(authenticated: true, user: _admin),
      )..holdLastfmConfig = true;
      await _mount(tester, repo, const ScrobblingSection());
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.scrobblerSetupLastfm),
      );
      await playDialogTransition(tester);
      expectSkeletonNotSpinner();
    });
  });

  testWidgets('connects ListenBrainz through the token dialog', (tester) async {
    final repo = FakeRepository();
    await _mount(tester, repo, const ScrobblingSection());
    await tester.pumpAndSettle();

    expect(find.text('Needs server API credentials'), findsOneWidget);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.scrobblerConnect('listenbrainz')),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget(find.byKey(const Key('listenbrainz-token-field'))),
      isA<WaxTextField>(),
    );
    expect(
      waxControl<WaxButton>(SemanticsIds.listenbrainzConnectConfirm),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('listenbrainz-token-field')),
      'token-123',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.listenbrainzConnectConfirm),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connected as listener'), findsOneWidget);

    await tester.tap(
      find.bySemanticsIdentifier(
        SemanticsIds.scrobblerDisconnect('listenbrainz'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Connected as listener'), findsNothing);
  });

  testWidgets('surfaces an invalid ListenBrainz token', (tester) async {
    final repo = FakeRepository()
      ..connectError = const WaxDeckApiException(
        code: 'invalid-request',
        message: 'the service did not accept this token',
      );
    await _mount(tester, repo, const ScrobblingSection());
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.scrobblerConnect('listenbrainz')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('listenbrainz-token-field')),
      'bad',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.listenbrainzConnectConfirm),
    );
    await tester.pumpAndSettle();

    expect(
      shellMessageText(raisedMessage(tester)),
      'the service did not accept this token',
    );
  });

  testWidgets('an unreachable ListenBrainz is said in the app\'s words', (
    tester,
  ) async {
    // Not a refusal of the token, so not the server's sentence either.
    final repo = FakeRepository()
      ..connectError = const WaxDeckApiException(
        code: 'service-unreachable',
        message: 'listenbrainz: dial tcp: i/o timeout',
      );
    await _mount(tester, repo, const ScrobblingSection());
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.scrobblerConnect('listenbrainz')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('listenbrainz-token-field')),
      'token',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.listenbrainzConnectConfirm),
    );
    await tester.pumpAndSettle();

    expect(
      shellMessageText(raisedMessage(tester)),
      'An outside service this needs did not answer. Try again later.',
    );
  });

  testWidgets('creates an app password and shows the secret once', (
    tester,
  ) async {
    final repo = FakeRepository();
    await _mount(tester, repo, const AppPasswordsSection());
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.appPasswordAdd));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('app-password-label-field')),
      'Symfonium',
    );
    await tester.tap(find.byKey(const Key('app-password-create-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app-password-secret')), findsOneWidget);
    await tester.tap(find.byKey(const Key('app-password-secret-done')));
    await tester.pumpAndSettle();

    expect(find.text('Symfonium'), findsOneWidget);
  });

  testWidgets('creates a personal notification target through the editor', (
    tester,
  ) async {
    final repo = FakeRepository();
    await _mount(tester, repo, const PersonalNotificationTargetsSection());
    await tester.pumpAndSettle();
    expect(find.text('No notification targets yet'), findsOneWidget);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.notifyTargetAdd));
    await tester.pumpAndSettle();

    // The kind dropdown swaps the config field group: Pushover's
    // token and key give way to Gotify's server URL and token.
    expect(find.byKey(const ValueKey('notify-config-userKey')), findsOneWidget);
    expect(find.byKey(const ValueKey('notify-config-serverUrl')), findsNothing);
    await tester.tap(find.byKey(const Key('notify-target-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gotify').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notify-config-userKey')), findsNothing);
    expect(
      find.byKey(const ValueKey('notify-config-serverUrl')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('notify-target-label')),
      'My phone',
    );
    await tester.enterText(
      find.byKey(const ValueKey('notify-config-serverUrl')),
      'https://gotify.example.net',
    );
    await tester.enterText(
      find.byKey(const ValueKey('notify-config-token')),
      'app-token',
    );
    await tester.ensureVisible(_eventSwitch('episode-downloaded'));
    await tester.pumpAndSettle();
    await tester.tap(_eventSwitch('episode-downloaded'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('notify-target-save')));
    await tester.pumpAndSettle();

    expect(repo.myNotificationTargets, hasLength(1));
    final saved = repo.myNotificationTargets.single;
    expect(saved.kind, 'gotify');
    expect(saved.label, 'My phone');
    expect(saved.config['serverUrl'], 'https://gotify.example.net');
    expect(saved.config['token'], 'app-token');
    expect(saved.enabledEvents, ['episode-downloaded']);
    expect(find.text('My phone'), findsOneWidget);
  });

  testWidgets('a webhook takes typed headers, a secret, mute and pacing', (
    tester,
  ) async {
    final repo = FakeRepository();
    await _mount(tester, repo, const PersonalNotificationTargetsSection());
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.notifyTargetAdd));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notify-target-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Webhook').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('notify-config-url')),
      'https://hook.example.net/wax',
    );
    // A line per header, which is how everybody writes them down.
    await tester.enterText(
      find.byKey(const ValueKey('notify-config-headers')),
      'X-Routing-Key: ops\nX-Team: night shift',
    );
    await tester.enterText(
      find.byKey(const ValueKey('notify-config-secret')),
      'shhh',
    );
    // Below the checklist in a scrolling dialog, so it is brought into
    // reach rather than tapped at an offset that hit-tests nothing.
    final mute = find.descendant(
      of: find.byKey(const Key('notify-target-muted')),
      matching: find.byType(WaxSwitch),
    );
    await tester.ensureVisible(mute);
    await tester.pumpAndSettle();
    await tester.tap(mute);
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('notify-target-interval')),
      '120',
    );
    await tester.tap(find.byKey(const Key('notify-target-save')));
    await tester.pumpAndSettle();

    final saved = repo.myNotificationTargets.single;
    expect(saved.config['headers'], <String, Object?>{
      'X-Routing-Key': 'ops',
      'X-Team': 'night shift',
    });
    expect(saved.config['secret'], 'shhh');
    expect(saved.muted, isTrue);
    expect(saved.minIntervalSeconds, 120);
    // And the row says the destination is paused rather than broken.
    expect(find.textContaining('Muted'), findsWidgets);
  });

  testWidgets('a header line with no colon is refused before the save', (
    tester,
  ) async {
    final repo = FakeRepository();
    await _mount(tester, repo, const PersonalNotificationTargetsSection());
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.notifyTargetAdd));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notify-target-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Webhook').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('notify-config-url')),
      'https://hook.example.net/wax',
    );
    await tester.enterText(
      find.byKey(const ValueKey('notify-config-headers')),
      'this is not a header',
    );
    await tester.tap(find.byKey(const Key('notify-target-save')));
    await tester.pumpAndSettle();

    expect(repo.myNotificationTargets, isEmpty);
    expect(find.byKey(const Key('notify-target-error')), findsOneWidget);
  });

  testWidgets('the editor refuses a missing required config field', (
    tester,
  ) async {
    final repo = FakeRepository();
    await _mount(tester, repo, const PersonalNotificationTargetsSection());
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.notifyTargetAdd));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notify-target-save')));
    await tester.pump();
    expect(find.text('Application token is required'), findsOneWidget);
    expect(repo.myNotificationTargets, isEmpty);
  });

  testWidgets('a server rejection keeps the editor open with the message', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..notificationTargetError = const WaxDeckApiException(
        code: 'invalid-request',
        message: 'the destination resolves to a private address',
      );
    await _mount(tester, repo, const PersonalNotificationTargetsSection());
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.notifyTargetAdd));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('notify-config-token')),
      't',
    );
    await tester.enterText(
      find.byKey(const ValueKey('notify-config-userKey')),
      'u',
    );
    await tester.tap(find.byKey(const Key('notify-target-save')));
    await tester.pumpAndSettle();

    expect(
      find.text('the destination resolves to a private address'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('notify-target-save')), findsOneWidget);
  });

  testWidgets('the personal checklist offers server events to admins only', (
    tester,
  ) async {
    final repo = FakeRepository();
    await _mount(tester, repo, const PersonalNotificationTargetsSection());
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.notifyTargetAdd));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('notify-event-episode-downloaded')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('notify-event-signup-requested')),
      findsNothing,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final adminRepo = _adminRepo();
    await _mount(tester, adminRepo, const PersonalNotificationTargetsSection());
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.notifyTargetAdd));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('notify-event-signup-requested')),
      findsOneWidget,
    );
    expect(find.text('Server events'), findsOneWidget);
    expect(find.text('My events'), findsOneWidget);
  });

  testWidgets("a listener's checklist leaves out the administrators' work", (
    tester,
  ) async {
    // Only an administrator starts a scan or a health fix, so only one
    // is ever told how it ended.
    const work = NotifyEvent(
      name: 'job-finished',
      scope: 'user',
      description: 'A library job you started finished.',
    );
    final repo = FakeRepository()
      ..notifyEvents = [...FakeRepository().notifyEvents, work];
    await _mount(tester, repo, const PersonalNotificationTargetsSection());
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.notifyTargetAdd));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('notify-event-job-finished')),
      findsNothing,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final adminRepo = _adminRepo()
      ..notifyEvents = [...FakeRepository().notifyEvents, work];
    await _mount(tester, adminRepo, const PersonalNotificationTargetsSection());
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.notifyTargetAdd));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('notify-event-job-finished')),
      findsOneWidget,
    );
  });

  testWidgets('the server section edits server-scope targets only', (
    tester,
  ) async {
    // Tall enough for the whole editor, so the checklist is in reach
    // without a scroll the focused field would pull back.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _adminRepo();
    await _mount(tester, repo, const ServerNotificationTargetsSection());
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.notifyServerTargetAdd),
    );
    await tester.pumpAndSettle();

    // Server-scope editors list server events only, flat.
    expect(
      find.byKey(const ValueKey('notify-event-signup-requested')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('notify-event-episode-downloaded')),
      findsNothing,
    );
    expect(find.text('Server events'), findsNothing);

    await tester.tap(find.byKey(const Key('notify-target-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Webhook').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('notify-config-url')),
      'https://hooks.example.net/ops',
    );
    await tester.tap(_eventSwitch('signup-requested'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('notify-target-save')));
    await tester.pumpAndSettle();

    expect(repo.serverNotificationTargets, hasLength(1));
    expect(repo.serverNotificationTargets.single.scope, 'server');
    expect(repo.serverNotificationTargets.single.kind, 'webhook');
    expect(repo.serverNotificationTargets.single.enabledEvents, [
      'signup-requested',
    ]);
  });

  testWidgets('tests a target and edits it back through the round trip', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..myNotificationTargets.add(
        NotificationTarget(
          pid: 'nt-SEED',
          kind: 'ntfy',
          scope: 'user',
          label: 'Tablet',
          config: const {'topic': 'waxdeck', 'accessToken': 'tk'},
          enabledEvents: const ['episode-downloaded'],
          createdAt: DateTime.utc(2026),
        ),
      );
    await _mount(tester, repo, const PersonalNotificationTargetsSection());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('notify-target-test-nt-SEED')));
    await tester.pumpAndSettle();
    expect(repo.notificationTargetTests['nt-SEED'], 1);

    // Editing seeds the round-tripped config and replaces it whole.
    await tester.tap(find.byKey(const ValueKey('notify-target-nt-SEED')));
    await tester.pumpAndSettle();
    final topicField = tester.widget<WaxTextField>(
      find.byKey(const ValueKey('notify-config-topic')),
    );
    expect(topicField.controller!.text, 'waxdeck');
    await tester.enterText(
      find.byKey(const ValueKey('notify-config-topic')),
      'waxdeck-2',
    );
    await tester.tap(find.byKey(const Key('notify-target-save')));
    await tester.pumpAndSettle();
    expect(repo.myNotificationTargets.single.config['topic'], 'waxdeck-2');
    expect(repo.myNotificationTargets.single.config['accessToken'], 'tk');
  });

  testWidgets('an unhealthy target shows its standing delivery error', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..myNotificationTargets.add(
        NotificationTarget(
          pid: 'nt-SICK',
          kind: 'pushover',
          scope: 'user',
          config: const {'token': 't', 'userKey': 'u'},
          enabledEvents: const [],
          createdAt: DateTime.utc(2026),
          lastError: 'delivery answered status 401',
          lastErrorAt: DateTime.utc(2026, 7, 22),
        ),
      );
    await _mount(tester, repo, const PersonalNotificationTargetsSection());
    await tester.pumpAndSettle();
    expect(find.textContaining('delivery answered status 401'), findsOneWidget);
  });

  testWidgets('shows scrobbler delivery health on the slot row', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..scrobblers = [
        const Scrobbler(service: 'lastfm', available: false, connected: false),
        Scrobbler(
          service: 'listenbrainz',
          available: true,
          connected: true,
          username: 'listener',
          lastSuccessAt: DateTime.utc(2026, 7, 18),
          lastError: 'the service answered status 503',
          lastErrorAt: DateTime.utc(2026, 7, 19),
        ),
      ];
    await _mount(tester, repo, const ScrobblingSection());
    await tester.pumpAndSettle();

    expect(
      find.text('Delivery failing: the service answered status 503'),
      findsOneWidget,
    );
  });

  testWidgets('a healthy delivering slot reads as such', (tester) async {
    final repo = FakeRepository()
      ..scrobblers = [
        Scrobbler(
          service: 'listenbrainz',
          available: true,
          connected: true,
          username: 'listener',
          lastSuccessAt: DateTime.utc(2026, 7, 19),
        ),
      ];
    await _mount(tester, repo, const ScrobblingSection());
    await tester.pumpAndSettle();
    expect(find.text('Connected as listener, delivering'), findsOneWidget);
  });

  testWidgets('non-admins never see the Last.fm setup affordance', (
    tester,
  ) async {
    final repo = FakeRepository();
    await _mount(tester, repo, const ScrobblingSection());
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.scrobblerSetupLastfm),
      findsNothing,
    );
    final connect = tester.widget<WaxButton>(
      waxControl<WaxButton>(SemanticsIds.scrobblerConnect('lastfm')),
    );
    expect(connect.onPressed, isNull);
  });

  testWidgets('an admin sets Last.fm credentials and the slot goes live', (
    tester,
  ) async {
    final repo = _adminRepo();
    await _mount(tester, repo, const ScrobblingSection());
    await tester.pumpAndSettle();

    // No credentials yet: the dead Connect gives way to the setup entry.
    expect(find.text('Needs server API credentials'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.scrobblerConnect('lastfm')),
      findsNothing,
    );

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.scrobblerSetupLastfm),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('lastfm-api-key-field')),
      'key-123',
    );
    await tester.enterText(
      find.byKey(const Key('lastfm-secret-field')),
      'secret-456',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.lastfmCredentialsSave),
    );
    await tester.pumpAndSettle();

    expect(repo.scrobblingConfig.lastfmConfigured, isTrue);
    expect(repo.scrobblingConfig.lastfmApiKey, 'key-123');
    expect(repo.scrobblingConfig.lastfmSource, 'settings');

    // The section reloads live: the row is connectable and the setup
    // moved into the small trailing gear.
    expect(find.text('Needs server API credentials'), findsNothing);
    final connect = tester.widget<WaxButton>(
      waxControl<WaxButton>(SemanticsIds.scrobblerConnect('lastfm')),
    );
    expect(connect.onPressed, isNotNull);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.scrobblerSetupLastfm),
      findsOneWidget,
    );
  });

  testWidgets('a half-set credential pair surfaces the server message', (
    tester,
  ) async {
    final repo = _adminRepo();
    await _mount(tester, repo, const ScrobblingSection());
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.scrobblerSetupLastfm),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('lastfm-api-key-field')),
      'key-123',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.lastfmCredentialsSave),
    );
    await tester.pumpAndSettle();

    expect(
      shellMessageText(raisedMessage(tester)),
      'set both the API key and the secret, or neither',
    );
    // The dialog stays up for the correction.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.lastfmCredentialsSave),
      findsOneWidget,
    );
    expect(repo.scrobblingConfig.lastfmConfigured, isFalse);
  });

  testWidgets('stored credentials prefill the key and can be cleared', (
    tester,
  ) async {
    final repo = _adminRepo()
      ..scrobblingConfig = const ScrobblingAdminConfig(
        lastfmConfigured: true,
        lastfmSource: 'settings',
        lastfmApiKey: 'key-abc',
        lastfmSecretSet: true,
      )
      ..scrobblers = [
        const Scrobbler(service: 'lastfm', available: true, connected: false),
        const Scrobbler(
          service: 'listenbrainz',
          available: true,
          connected: false,
        ),
      ];
    await _mount(tester, repo, const ScrobblingSection());
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.scrobblerSetupLastfm),
    );
    await tester.pumpAndSettle();

    final keyField = tester.widget<WaxTextField>(
      find.byKey(const Key('lastfm-api-key-field')),
    );
    expect(keyField.controller!.text, 'key-abc');
    expect(find.text('Stored sealed; never shown again'), findsOneWidget);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.lastfmCredentialsClear),
    );
    await tester.pumpAndSettle();

    expect(repo.scrobblingConfig.lastfmConfigured, isFalse);
    expect(find.text('Needs server API credentials'), findsOneWidget);
    expect(find.text('Set up…'), findsOneWidget);
  });

  group('a target test waits for its answer', () {
    NotificationTarget target({
      DateTime? lastSuccessAt,
      String? lastError,
      DateTime? lastErrorAt,
    }) => NotificationTarget(
      pid: 'nt-T',
      kind: 'ntfy',
      scope: 'user',
      label: 'Tablet',
      config: const {'topic': 'waxdeck'},
      enabledEvents: const ['episode-downloaded'],
      createdAt: DateTime.utc(2026),
      lastSuccessAt: lastSuccessAt,
      lastError: lastError,
      lastErrorAt: lastErrorAt,
    );

    Future<ProviderContainer> press(
      WidgetTester tester,
      FakeRepository repo,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _mount(tester, repo, const PersonalNotificationTargetsSection());
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.notifyTargetTest('nt-T')),
      );
      await tester.pump();
      return ProviderScope.containerOf(
        tester.element(find.byType(PersonalNotificationTargetsSection)),
      );
    }

    WaxIconButton button(WidgetTester tester) => tester.widget<WaxIconButton>(
      waxControl<WaxIconButton>(SemanticsIds.notifyTargetTest('nt-T')),
    );

    testWidgets('and says it was delivered', (tester) async {
      final repo = FakeRepository()
        ..myNotificationTargets.add(
          target(lastSuccessAt: DateTime.utc(2026, 9, 1)),
        );
      repo.onNotificationTargetTest = (_) => repo.myNotificationTargets[0] =
          target(lastSuccessAt: DateTime.utc(2026, 9, 29, 12));
      final container = await press(tester, repo);
      expect(button(tester).busy, isTrue);
      expect(
        shellMessageText(container.read(shellMessengerProvider)),
        'Test queued; the outcome shows on the target shortly',
      );

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(
        shellMessageText(container.read(shellMessengerProvider)),
        'Test delivered',
      );
      expect(button(tester).busy, isFalse);
    });

    testWidgets('and says why it failed', (tester) async {
      final repo = FakeRepository()..myNotificationTargets.add(target());
      repo.onNotificationTargetTest = (_) =>
          repo.myNotificationTargets[0] = target(
            lastError: 'connection refused',
            lastErrorAt: DateTime.utc(2026, 9, 29, 12),
          );
      final container = await press(tester, repo);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(
        shellMessageText(container.read(shellMessengerProvider)),
        'Test failed: connection refused',
      );
    });

    testWidgets('and says so when nothing answers', (tester) async {
      final repo = FakeRepository()..myNotificationTargets.add(target());
      final container = await press(tester, repo);

      await tester.pump(const Duration(seconds: 28));
      expect(button(tester).busy, isTrue);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(
        shellMessageText(container.read(shellMessengerProvider)),
        'No answer from the test yet; the target shows it when it lands',
      );
      expect(button(tester).busy, isFalse);
    });
  });

  testWidgets('the credentials dialog says a failed read at once, while it '
      'retries', (tester) async {
    // The app's own retry left on: while an attempt runs the read is
    // loading and still carries the last error.
    await _mount(tester, _ConfigDown(), const ScrobblingSection());
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.scrobblerSetupLastfm),
    );
    await tester.pump();
    // Past the first retry's delay: the read is loading again.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    // Explained, with its retry drawn busy while the read asks again.
    expect(find.text(AppLocalizationsEn().errorInternal), findsOneWidget);
    expect(
      tester.widget<WaxButton>(find.widgetWithText(WaxButton, 'Retry')).busy,
      isTrue,
    );
    expect(find.byType(SkeletonShapes), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  group('a read that fails for good says why and asks again', () {
    final en = AppLocalizationsEn();

    // A retry is a timer that re-reads on the next frame, so the ladder
    // (0.2 s doubling to 6.4 s, ten retries) takes one pump per rung. Each
    // pump here outlasts the longest delay: one that draws no new read
    // means no retry is pending.
    Future<void> spendRetries(
      WidgetTester tester,
      _ReadsDown repo,
      String read,
    ) async {
      for (var i = 0; i < 30; i++) {
        final before = repo.reads[read];
        await tester.pump(const Duration(seconds: 7));
        if (repo.reads[read] == before) return;
      }
      fail('the retries of $read never ran out');
    }

    for (final (read, section, title, after) in [
      (
        'scrobblers',
        const ScrobblingSection() as Widget,
        en.settingsScrobblingError,
        'ListenBrainz',
      ),
      (
        'passwords',
        const AppPasswordsSection() as Widget,
        en.settingsAppPasswordsError,
        en.settingsAppPasswordsEmpty,
      ),
      (
        'targets',
        const PersonalNotificationTargetsSection() as Widget,
        en.settingsNotifyTargetsError,
        en.settingsNotifyTargetsEmpty,
      ),
    ]) {
      testWidgets(read, (tester) async {
        final repo = _ReadsDown({read});
        await _mount(tester, repo, section);
        await spendRetries(tester, repo, read);
        final spent = repo.reads[read];

        expect(find.text(title), findsOneWidget);
        expect(find.text(en.errorInternal), findsOneWidget);
        final retry = find.widgetWithText(WaxButton, 'Try again');
        expect(tester.widget<WaxButton>(retry).busy, isFalse);

        repo.down.clear();
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(find.text(after), findsOneWidget);
        expect(repo.reads[read], spent! + 1, reason: 'the press read once');
      });
    }

    testWidgets('the Last.fm credentials, in their dialog', (tester) async {
      final repo = _ReadsDown({'lastfm'})
        ..scrobblers = const [
          Scrobbler(service: 'lastfm', available: false, connected: false),
        ];
      await _mount(tester, repo, const ScrobblingSection());
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.scrobblerSetupLastfm),
      );
      await spendRetries(tester, repo, 'lastfm');
      final spent = repo.reads['lastfm'];

      expect(find.text(en.errorInternal), findsOneWidget);
      final retry = find.widgetWithText(WaxButton, 'Retry');
      expect(tester.widget<WaxButton>(retry).busy, isFalse);
      repo.down.clear();
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lastfm-api-key-field')), findsOneWidget);
      expect(repo.reads['lastfm'], spent! + 1, reason: 'the press read once');
    });

    testWidgets('the event checklist, in the target editor', (tester) async {
      final repo = _ReadsDown({'catalog'});
      await _mount(tester, repo, const PersonalNotificationTargetsSection());
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.notifyTargetAdd),
      );
      await spendRetries(tester, repo, 'catalog');
      final spent = repo.reads['catalog'];
      final switches = find.byType(WaxSwitch).evaluate().length;

      expect(find.text(en.errorInternal), findsOneWidget);
      repo.down.clear();
      // The banner is scrolled out of the editor's view.
      final retry = find.widgetWithText(WaxButton, 'Retry');
      await tester.ensureVisible(retry);
      await tester.pump();
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.byType(WaxSwitch), findsWidgets);
      expect(find.byType(WaxSwitch).evaluate().length, greaterThan(switches));
      expect(repo.reads['catalog'], spent! + 1, reason: 'the press read once');
    });
  });

  group('a Last.fm connect or disconnect takes one press while it runs', () {
    for (final connected in const <bool>[false, true]) {
      final id = connected
          ? SemanticsIds.scrobblerDisconnect('lastfm')
          : SemanticsIds.scrobblerConnect('lastfm');
      testWidgets(connected ? 'disconnect' : 'connect', (tester) async {
        final repo = _HeldLastfm()
          ..scrobblers = [
            Scrobbler(service: 'lastfm', available: true, connected: connected),
          ];
        final opener = _Opener();
        await _mount(
          tester,
          repo,
          const ScrobblingSection(),
          extra: [urlOpenerProvider.overrideWithValue(opener)],
        );
        await tester.pumpAndSettle();
        WaxButton button() =>
            tester.widget<WaxButton>(waxControl<WaxButton>(id));

        await tester.tap(find.bySemanticsIdentifier(id));
        await tester.pump();
        expect(button().busy, isTrue);
        await tester.tap(find.bySemanticsIdentifier(id));
        await tester.pump();
        expect(repo.asked, 1);

        repo.release.complete();
        await tester.pumpAndSettle();
        if (connected) {
          expect(
            find.bySemanticsIdentifier(SemanticsIds.scrobblerConnect('lastfm')),
            findsOneWidget,
          );
        } else {
          expect(opener.opened, hasLength(1));
          expect(button().busy, isFalse);
        }
      });
    }
  });

  group('a removal asks first, draws busy and says what failed', () {
    final en = AppLocalizationsEn();
    NotificationTarget target() => NotificationTarget(
      pid: 'nt-SEED',
      kind: 'ntfy',
      scope: 'user',
      label: 'Tablet',
      config: const {'topic': 'waxdeck'},
      enabledEvents: const [],
      createdAt: DateTime.utc(2026),
    );
    final password = AppPassword(
      id: 'ap-1',
      label: 'Feishin',
      createdAt: DateTime.utc(2026),
    );

    // One shape for both rows: the row, its delete button and the
    // dialog's confirm.
    for (final (name, row, press, confirm, seed, section) in [
      (
        'a notification target',
        const ValueKey('notify-target-nt-SEED'),
        const ValueKey('notify-target-remove-nt-SEED'),
        const Key('notify-target-remove-confirm'),
        (FakeRepository repo) => repo.myNotificationTargets.add(target()),
        const PersonalNotificationTargetsSection() as Widget,
      ),
      (
        'an app password',
        const ValueKey('app-password-ap-1'),
        ValueKey(SemanticsIds.appPasswordRevoke('ap-1')),
        const Key('app-password-revoke-confirm'),
        (FakeRepository repo) => repo.appPasswords.add(password),
        const AppPasswordsSection() as Widget,
      ),
    ]) {
      testWidgets('$name goes only once confirmed', (tester) async {
        final repo = FakeRepository();
        seed(repo);
        await _mount(tester, repo, section);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(press));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.widgetWithText(WaxButton, en.commonCancel));
        await tester.pumpAndSettle();
        expect(find.byKey(row), findsOneWidget);

        await tester.tap(find.byKey(press));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(confirm));
        await tester.pumpAndSettle();
        expect(find.byKey(row), findsNothing);
      });

      testWidgets('$name that fails to go says why and stays, and takes one '
          'press while it is out', (tester) async {
        final repo = _FailingDeletes();
        seed(repo);
        await _mount(tester, repo, section);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(press));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(confirm));
        // The spinner never settles: frames past the dialog's exit.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.widget<WaxIconButton>(find.byKey(press)).busy, isTrue);
        await tester.tap(find.byKey(press));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(AlertDialog), findsNothing);
        expect(repo.deletes, 1);

        repo.release.complete();
        await tester.pumpAndSettle();
        expect(shellMessageText(raisedMessage(tester)), en.errorNetwork);
        expect(find.byKey(row), findsOneWidget);
        expect(tester.widget<WaxIconButton>(find.byKey(press)).busy, isFalse);
      });
    }
  });
}
