import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/admin_providers.dart';
import 'package:waxdeck/src/admin/dashboard_screen.dart';
import 'package:waxdeck/src/admin/first_run_wizard.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/health/health_controller.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/client_settings_providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

const _admin = WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']);

/// A health read that never lands.
class _PendingHealth extends HealthController {
  @override
  Future<HealthSummary> build() => Completer<HealthSummary>().future;
}

/// A health read that fails, having never landed once.
class _FailingHealth extends HealthController {
  @override
  Future<HealthSummary> build() async => throw StateError('health is down');
}

/// A repository whose library list never answers.
class _PendingLibraries extends FakeRepository {
  _PendingLibraries()
    : super(
        sessionState: const SessionState(authenticated: true, user: _admin),
      );

  @override
  Future<List<LibraryInfo>> listLibraries({bool counts = false}) =>
      Completer<List<LibraryInfo>>().future;
}

ProviderContainer _container(
  FakeRepository repo, {
  ClientSettingsStore? store,
}) {
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      // The session only resolves with a store behind it: the auth
      // controller reads the stored token before it probes.
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      // The device's own store, which is where the tour's progress
      // lives. Passing the same one to a second container is this
      // suite's version of a reload.
      clientSettingsStoreProvider.overrideWithValue(
        store ?? MemoryClientSettingsStore(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Every case here is an administrator looking at their own console;
/// the one that is not says so.
FakeRepository _repo() => FakeRepository(
  sessionState: const SessionState(authenticated: true, user: _admin),
);

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  tester.view.physicalSize = const Size(1280, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: routedHost(const AdminDashboardScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

LibraryInfo _library() => const LibraryInfo(pid: 'lb-1', name: 'Music');

Job _scan(String state) => Job(pid: 'jb-1', kind: 'scan', state: state);

Finder _step(FirstRunStep step) =>
    find.bySemanticsIdentifier(SemanticsIds.adminWizardStep(step.id));

void main() {
  testWidgets('a server with no libraries opens on step one', (tester) async {
    final container = _container(_repo());
    await _pump(tester, container);

    expect(
      find.bySemanticsIdentifier(SemanticsIds.adminWizard),
      findsOneWidget,
    );
    expect(_step(FirstRunStep.addLibrary), findsOneWidget);
    // A takeover, not a card among tiles: there is no status worth
    // reading on a server with nothing in it.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.adminTile('health')),
      findsNothing,
    );
  });

  testWidgets('a library added during the session advances to step two', (
    tester,
  ) async {
    final repo = _repo();
    final container = _container(repo);
    await _pump(tester, container);
    expect(_step(FirstRunStep.addLibrary), findsOneWidget);

    repo.libraries.add(_library());
    container.invalidate(librariesProvider);
    await tester.pumpAndSettle();

    expect(_step(FirstRunStep.scan), findsOneWidget);
  });

  // The step that starts the scan must not be skipped: `warmingUp` is
  // true from a server's first boot, before there is anything warming,
  // so reading it alone would jump the tour straight to step three.
  testWidgets('step two survives a server that has never swept', (
    tester,
  ) async {
    final repo = _repo()
      ..healthSummary = const HealthSummary(
        score: 0,
        totalItems: 0,
        evaluatedItems: 0,
        warmingUp: true,
      );
    final container = _container(repo);
    await _pump(tester, container);

    repo.libraries.add(_library());
    container.invalidate(librariesProvider);
    await tester.pumpAndSettle();

    expect(_step(FirstRunStep.scan), findsOneWidget);
  });

  testWidgets('a running scan is step three, and finishing ends the tour', (
    tester,
  ) async {
    final repo = _repo()
      ..healthSummary = const HealthSummary(
        score: 0,
        totalItems: 0,
        evaluatedItems: 0,
        warmingUp: true,
      );
    final container = _container(repo);
    await _pump(tester, container);

    repo.libraries.add(_library());
    repo.jobs = <Job>[_scan('running')];
    container.invalidate(librariesProvider);
    container.invalidate(adminJobsProvider);
    await tester.pumpAndSettle();
    expect(_step(FirstRunStep.warming), findsOneWidget);

    // The scan lands and the first health sweep with it: nothing is left
    // to guide anybody through, so the wizard goes - without a stored
    // flag to un-set later.
    repo.jobs = <Job>[_scan('done')];
    repo.healthSummary = const HealthSummary(
      score: 90,
      totalItems: 10,
      evaluatedItems: 10,
    );
    container.invalidate(adminJobsProvider);
    container.invalidate(healthProvider);
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier(SemanticsIds.adminWizard), findsNothing);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.adminTile('health')),
      findsOneWidget,
    );
  });

  // Ending the tour on an unanswered read is permanent, so looking at
  // the console a beat too early would lose the rest of it.
  testWidgets('an unanswered health read does not end the tour', (
    tester,
  ) async {
    final repo = _repo()
      ..healthSummary = const HealthSummary(
        score: 0,
        totalItems: 0,
        evaluatedItems: 0,
        warmingUp: true,
      );
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        clientSettingsStoreProvider.overrideWithValue(
          MemoryClientSettingsStore(),
        ),
        healthProvider.overrideWith(_PendingHealth.new),
      ],
    );
    addTearDown(container.dispose);
    await _pump(tester, container);

    // Library in, scan recorded: only health stands before the end.
    repo.libraries.add(_library());
    repo.jobs = <Job>[_scan('done')];
    container.invalidate(librariesProvider);
    container.invalidate(adminJobsProvider);
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.adminWizard),
      findsOneWidget,
      reason: 'the tour waits for the answer rather than assuming one',
    );
    expect(
      _step(FirstRunStep.warming),
      findsOneWidget,
      reason: 'and holds the step the scan already reached, not an older one',
    );
  });

  // An error is as unknown as a pending read, and a first one carries no
  // previous value to fall back on.
  testWidgets('a failed health read does not end the tour either', (
    tester,
  ) async {
    final repo = _repo();
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        clientSettingsStoreProvider.overrideWithValue(
          MemoryClientSettingsStore(),
        ),
        healthProvider.overrideWith(_FailingHealth.new),
      ],
    );
    addTearDown(container.dispose);
    await _pump(tester, container);

    repo.libraries.add(_library());
    repo.jobs = <Job>[_scan('done')];
    container.invalidate(librariesProvider);
    container.invalidate(adminJobsProvider);
    await tester.pumpAndSettle();

    expect(_step(FirstRunStep.warming), findsOneWidget);
  });

  // The case that makes the entry condition strict rather than derived:
  // a healthy idle server, or one somebody just rescanned, must never be
  // handed a wizard.
  testWidgets('a server that already has libraries never sees the tour', (
    tester,
  ) async {
    final repo = _repo()
      ..libraries.add(_library())
      ..jobs = <Job>[_scan('running')]
      ..healthSummary = const HealthSummary(
        score: 0,
        totalItems: 0,
        evaluatedItems: 0,
        warmingUp: true,
      );
    await _pump(tester, _container(repo));

    expect(find.bySemanticsIdentifier(SemanticsIds.adminWizard), findsNothing);
  });

  testWidgets('skipping ends it for the session', (tester) async {
    final repo = _repo();
    final container = _container(repo);
    await _pump(tester, container);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.adminWizardSkip),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier(SemanticsIds.adminWizard), findsNothing);

    // And it does not come back when the thing that summoned it is still
    // true.
    container.invalidate(librariesProvider);
    await tester.pumpAndSettle();
    expect(find.bySemanticsIdentifier(SemanticsIds.adminWizard), findsNothing);
  });

  // A create starts a scan server-side, so the job list is stale on
  // arrival: the wizard offers a scan already running, and if the
  // refusal refetched nothing, step two would own the console.
  testWidgets('a refused scan refreshes the job list rather than sticking', (
    tester,
  ) async {
    final repo = _repo()
      ..rescanError = const WaxDeckApiException(
        code: 'conflict',
        message: 'a scan is already running',
        statusCode: 409,
      );
    final container = _container(repo);
    await _pump(tester, container);
    expect(_step(FirstRunStep.addLibrary), findsOneWidget);

    // A library arrives, and the client's job list still says nothing
    // is running - which is exactly what the create leaves behind if
    // nothing invalidates it.
    repo.libraries.add(_library());
    container.invalidate(librariesProvider);
    await tester.pumpAndSettle();
    expect(_step(FirstRunStep.scan), findsOneWidget);

    // What is actually true, which the refusal is evidence of.
    repo.jobs = <Job>[_scan('running')];
    final before = repo.jobReads;

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.adminAction('scan')),
    );
    await tester.pumpAndSettle();

    expect(
      repo.jobReads,
      greaterThan(before),
      reason: 'the refusal proves the job list is stale, so it is re-read',
    );
    expect(_step(FirstRunStep.warming), findsOneWidget);
  });

  /// A reload as these two providers see one: both disposed and rebuilt,
  /// so the wizard starts with no memory and the progress re-reads the
  /// device store. The rest of the container is left alone, since a
  /// second live one leaves the first's timers running.
  Future<void> reload(WidgetTester tester, ProviderContainer container) async {
    container
      ..invalidate(firstRunWizardProvider)
      ..invalidate(firstRunProgressProvider);
    await tester.pumpAndSettle();
  }

  testWidgets('a reload mid-tour resumes where it was', (tester) async {
    final repo = _repo();
    final container = _container(repo);
    await _pump(tester, container);
    expect(_step(FirstRunStep.addLibrary), findsOneWidget);

    // Step two, which is the point where nothing about the server says
    // "mid-tour" any more: it has a library, like every healthy server.
    repo.libraries.add(_library());
    container.invalidate(librariesProvider);
    await tester.pumpAndSettle();
    expect(_step(FirstRunStep.scan), findsOneWidget);

    await reload(tester, container);

    expect(
      _step(FirstRunStep.scan),
      findsOneWidget,
      reason: 'the tour continues rather than ending two steps early',
    );
  });

  testWidgets('a skipped tour stays skipped across a reload', (tester) async {
    final container = _container(_repo());
    await _pump(tester, container);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.adminWizard),
      findsOneWidget,
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.adminWizardSkip));
    await tester.pumpAndSettle();
    expect(find.bySemanticsIdentifier(SemanticsIds.adminWizard), findsNothing);

    // Still no libraries, so the condition that summoned it is as true
    // as ever - and it stays dismissed anyway, which is what the word
    // "skip" promises.
    await reload(tester, container);

    expect(find.bySemanticsIdentifier(SemanticsIds.adminWizard), findsNothing);
  });

  // The asymmetry with the health guard above, which holds a step when
  // its read is unknown. Here nothing about the server is known at all,
  // and the stored stage alone is not evidence the tour is still on:
  // warm-up may have finished while this device was away. So an
  // unanswered library list draws no wizard, not the stage's step.
  testWidgets('an unanswered library list draws no wizard mid-tour', (
    tester,
  ) async {
    final store = MemoryClientSettingsStore();
    await store.write(
      ClientSettingKeys.firstRunProgress,
      FirstRunStage.scan.name,
    );

    await _pump(tester, _container(_PendingLibraries(), store: store));

    expect(find.bySemanticsIdentifier(SemanticsIds.adminWizard), findsNothing);
  });

  testWidgets('a reload on a healthy server still summons nothing', (
    tester,
  ) async {
    // The other direction, which is the one durability could have
    // broken: a device that never took the tour, on a server that was
    // already running, must not be handed it by a stored value.
    final container = _container(_repo()..libraries.add(_library()));
    await _pump(tester, container);
    expect(find.bySemanticsIdentifier(SemanticsIds.adminWizard), findsNothing);

    await reload(tester, container);

    expect(find.bySemanticsIdentifier(SemanticsIds.adminWizard), findsNothing);
  });

  // A small library is indexed between two reads of the job list, so a
  // step two that waited to catch a scan *running* would strand exactly
  // the servers that finish fastest - the tour sitting on "Scan
  // library" for a library that has already been read.
  testWidgets('a scan that finished before anyone looked still counts', (
    tester,
  ) async {
    final repo = _repo();
    final container = _container(repo);
    await _pump(tester, container);
    expect(_step(FirstRunStep.addLibrary), findsOneWidget);

    // The library lands, and its scan is over by the time the console
    // reads the list: done, never observed running.
    repo.libraries.add(_library());
    repo.jobs = <Job>[_scan('done')];
    container
      ..invalidate(librariesProvider)
      ..invalidate(adminJobsProvider);
    await tester.pumpAndSettle();

    // Nothing left to warm up either, so the tour is simply over.
    expect(_step(FirstRunStep.scan), findsNothing);
    expect(find.bySemanticsIdentifier(SemanticsIds.adminWizard), findsNothing);
  });

  testWidgets('a listener gets no wizard at all', (tester) async {
    final container = _container(
      FakeRepository(
        sessionState: const SessionState(
          authenticated: true,
          user: WaxDeckUser(id: 'us-2', username: 'sam', roles: ['user']),
        ),
      ),
    );
    await _pump(tester, container);

    expect(find.bySemanticsIdentifier(SemanticsIds.adminWizard), findsNothing);
  });
}
