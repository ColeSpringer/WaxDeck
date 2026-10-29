import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/health/health_screen.dart';
import 'package:waxdeck/src/l10n/l10n.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

const _admin = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  username: 'admin',
  roles: ['admin'],
);

final _l10n = lookupAppLocalizations(const Locale('en'));

/// A check with the given counts above zero and the verdicts the server
/// would draw from them.
CatalogConsistency _check({
  int sortKeyDrift = 0,
  int itemsMissingFromSearch = 0,
  int playlistPositionDrift = 0,
  int orphanArtSources = 0,
}) => CatalogConsistency(
  itemsMissingFromSearch: itemsMissingFromSearch,
  orphanSearchRows: 0,
  artistRollupDrift: 0,
  genreRollupDrift: 0,
  releaseGroupRollupDrift: 0,
  sortKeyDrift: sortKeyDrift,
  bookDurationDrift: 0,
  bookIsbnKeyDrift: 0,
  albumYearDrift: 0,
  releaseYearDrift: 0,
  playlistPositionDrift: playlistPositionDrift,
  orphanArtSources: orphanArtSources,
  orphanThumbnails: 0,
  orphanTagProvenance: 0,
  strandedTagRows: 0,
  consistent: sortKeyDrift == 0 && itemsMissingFromSearch == 0,
  reclaimable: orphanArtSources > 0,
);

FakeRepository _repo({WaxDeckUser user = _admin}) =>
    FakeRepository(sessionState: SessionState(authenticated: true, user: user))
      ..healthSummary = const HealthSummary(
        score: 90,
        totalItems: 4,
        evaluatedItems: 4,
        rules: [],
      );

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeRepository repo, {
  DateTime Function()? clock,
}) async {
  tester.view.physicalSize = const Size(1280, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      if (clock != null) wallClockProvider.overrideWithValue(clock),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: routedHost(const HealthScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// The section over the server at [a]'s address, which [switchTo] moves to
/// [b]'s: the repository follows the address, as the app's does.
Future<Future<void> Function()> _pumpSwitching(
  WidgetTester tester,
  FakeRepository a,
  FakeRepository b,
) async {
  tester.view.physicalSize = const Size(1280, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  a.baseUrl = 'http://a.test';
  b.baseUrl = 'http://b.test';
  final container = ProviderContainer(
    overrides: [
      bootServerAddressProvider.overrideWithValue(a.baseUrl),
      repositoryProvider.overrideWith(
        (ref) => ref.watch(serverBaseUrlProvider) == a.baseUrl ? a : b,
      ),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: routedHost(const HealthScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return () async {
    await container.read(serverAddressProvider.notifier).adopt(b.baseUrl);
    await tester.pumpAndSettle();
  };
}

Future<void> _tap(WidgetTester tester, String id) async {
  await tester.ensureVisible(find.bySemanticsIdentifier(id));
  await tester.tap(find.bySemanticsIdentifier(id));
  await tester.pumpAndSettle();
}

Finder _inResult(String text) => find.descendant(
  of: find.bySemanticsIdentifier(SemanticsIds.catalogCheckResult),
  matching: find.text(text),
);

/// The count drawn in the same row as [label].
Finder _besideLabel(String label, int count) => find.descendant(
  of: find.ancestor(of: _inResult(label), matching: find.byType(Row)).first,
  matching: find.text('$count'),
);

/// Busy controls held still, so the frames settle while a call is out.
void _heldStill(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// Confirms a repair from the section.
Future<void> _confirmRepair(WidgetTester tester) async {
  await _tap(tester, SemanticsIds.catalogCheckRepair);
  await tester.tap(
    find.bySemanticsIdentifier(SemanticsIds.catalogCheckRepairConfirm),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('verify reads a clean catalog, then names the drift a repair '
      'clears', (tester) async {
    final repo = _repo();
    await _pump(tester, repo);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.catalogCheckResult),
      findsNothing,
      reason: 'the check runs when asked, not with the screen',
    );

    await _tap(tester, SemanticsIds.catalogCheckVerify);
    expect(repo.catalogChecks, 1);
    // Only what the check reads: it never reads a search entry's content.
    expect(_inResult('Consistent: nothing out of step.'), findsOneWidget);
    expect(
      lookupAppLocalizations(const Locale('es')).healthCatalogClean,
      'Coherente: nada desajustado.',
    );

    repo.catalogConsistency = _check(
      sortKeyDrift: 6,
      itemsMissingFromSearch: 2,
      playlistPositionDrift: 1,
    );
    await _tap(tester, SemanticsIds.catalogCheckVerify);
    expect(_inResult(_l10n.healthCatalogDrift), findsOneWidget);
    for (final (label, count) in [
      (_l10n.healthCatalogSortKeys, 6),
      (_l10n.healthCatalogMissingFromSearch, 2),
      (_l10n.healthCatalogPlaylistNumbering, 1),
    ]) {
      expect(_besideLabel(label, count), findsOneWidget, reason: label);
    }
    expect(
      _inResult(_l10n.healthCatalogAlbumYears),
      findsNothing,
      reason: 'a count at zero is not drift',
    );
  });

  testWidgets('the verdict says when it was read', (tester) async {
    var now = DateTime.utc(2026, 10, 28, 15, 4);
    final repo = _repo()..catalogConsistency = _check(sortKeyDrift: 6);
    await _pump(tester, repo, clock: () => now);
    await _tap(tester, SemanticsIds.catalogCheckVerify);
    final first = now;
    // Kept on screen for as long as the session lasts, and still dated.
    now = now.add(const Duration(days: 2));
    await tester.pumpAndSettle();
    expect(
      _inResult(_l10n.healthCatalogCheckedAt(_l10n.formatStamp(first))),
      findsOneWidget,
    );
    expect(
      lookupAppLocalizations(const Locale('es')).healthCatalogCheckedAt('x'),
      'Comprobado el x',
    );
  });

  testWidgets('every count sits beside its own label', (tester) async {
    final repo = _repo()
      ..catalogConsistency = const CatalogConsistency(
        itemsMissingFromSearch: 1,
        orphanSearchRows: 2,
        artistRollupDrift: 3,
        genreRollupDrift: 4,
        releaseGroupRollupDrift: 5,
        sortKeyDrift: 6,
        bookDurationDrift: 7,
        bookIsbnKeyDrift: 8,
        albumYearDrift: 9,
        releaseYearDrift: 10,
        playlistPositionDrift: 11,
        orphanArtSources: 12,
        orphanThumbnails: 13,
        orphanTagProvenance: 14,
        strandedTagRows: 15,
        consistent: false,
        reclaimable: true,
      );
    await _pump(tester, repo);
    await _tap(tester, SemanticsIds.catalogCheckVerify);
    final labels = [
      _l10n.healthCatalogMissingFromSearch,
      _l10n.healthCatalogOrphanSearchRows,
      _l10n.healthCatalogArtistTotals,
      _l10n.healthCatalogGenreTotals,
      _l10n.healthCatalogReleaseGroupTotals,
      _l10n.healthCatalogSortKeys,
      _l10n.healthCatalogBookLengths,
      _l10n.healthCatalogBookIsbnKeys,
      _l10n.healthCatalogAlbumYears,
      _l10n.healthCatalogReleaseYears,
      _l10n.healthCatalogPlaylistNumbering,
      _l10n.healthCatalogUnusedImages,
      _l10n.healthCatalogUnusedThumbnails,
      _l10n.healthCatalogReservedTagRecords,
      _l10n.healthCatalogRefusedTagRows,
    ];
    for (final (i, label) in labels.indexed) {
      expect(_besideLabel(label, i + 1), findsOneWidget, reason: label);
    }
  });

  testWidgets('a consistent catalog with unused rows reads as one to tidy', (
    tester,
  ) async {
    final repo = _repo()..catalogConsistency = _check(orphanArtSources: 3);
    await _pump(tester, repo);
    await _tap(tester, SemanticsIds.catalogCheckVerify);
    expect(_inResult(_l10n.healthCatalogTidy), findsOneWidget);
    expect(_inResult(_l10n.healthCatalogUnusedImages), findsOneWidget);
    expect(_inResult('3'), findsOneWidget);
  });

  testWidgets('a failed check says why', (tester) async {
    final repo = _repo();
    await _pump(tester, repo);
    repo.adminError = const WaxDeckApiException(
      code: 'catalog-maintenance',
      message: 'the catalog is temporarily under maintenance',
      statusCode: 503,
    );
    await _tap(tester, SemanticsIds.catalogCheckVerify);
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.catalogCheck),
        matching: find.text(
          explainError(
            _l10n,
            const WaxDeckApiException(
              code: 'catalog-maintenance',
              message: 'the catalog is temporarily under maintenance',
              statusCode: 503,
            ),
          ),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('repair asks first, then starts the task and points at Tasks', (
    tester,
  ) async {
    final repo = _repo();
    final container = await _pump(tester, repo);

    await _tap(tester, SemanticsIds.catalogCheckRepair);
    expect(find.text(_l10n.healthCatalogRepairTitle), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.confirmCancel));
    await tester.pumpAndSettle();
    expect(repo.catalogRepairs, isEmpty, reason: 'cancelled, nothing runs');

    await _confirmRepair(tester);
    expect(repo.catalogRepairs, hasLength(1));
    final message = container.read(shellMessengerProvider);
    expect(shellMessageText(message), _l10n.healthCatalogRepairStarted);
    expect(message?.actionSemanticsId, SemanticsIds.openTasks);

    // Pumped by frame: the queued repair's bar moves for as long as Tasks
    // draws it, so the tree never settles.
    message!.onAction!();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.bySemanticsIdentifier(SemanticsIds.taskRow('tt-repair-0')),
      findsOneWidget,
      reason: 'Tasks lists the repair it was opened for',
    );
  });

  testWidgets('a repair already under way says so and points at Tasks', (
    tester,
  ) async {
    final repo = _repo()
      ..catalogRepairError = const WaxDeckApiException(
        code: 'conflict',
        message: 'a catalog repair has not finished yet',
        statusCode: 409,
        params: {'reason': 'task-running', 'task': 'tk-1'},
      );
    final container = await _pump(tester, repo);
    await _confirmRepair(tester);
    final message = container.read(shellMessengerProvider);
    expect(shellMessageText(message), _l10n.healthCatalogRepairRunning);
    expect(message?.actionSemanticsId, SemanticsIds.openTasks);
  });

  testWidgets('a started repair drops the check read before it', (
    tester,
  ) async {
    final repo = _repo()..catalogConsistency = _check(sortKeyDrift: 6);
    await _pump(tester, repo);
    await _tap(tester, SemanticsIds.catalogCheckVerify);
    expect(_inResult(_l10n.healthCatalogDrift), findsOneWidget);
    await _confirmRepair(tester);
    expect(repo.catalogRepairs, hasLength(1));
    expect(
      find.bySemanticsIdentifier(SemanticsIds.catalogCheckResult),
      findsNothing,
      reason: 'the repair is about to change what that check read',
    );
  });

  testWidgets('a check still out when a repair starts does not come back '
      'after it', (tester) async {
    _heldStill(tester);
    final repo = _repo()
      ..catalogConsistency = _check(sortKeyDrift: 6)
      ..catalogCheckGate = Completer<void>();
    await _pump(tester, repo);
    await _tap(tester, SemanticsIds.catalogCheckVerify);
    await _confirmRepair(tester);
    expect(repo.catalogRepairs, hasLength(1));

    repo.catalogCheckGate!.complete();
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.catalogCheckResult),
      findsNothing,
      reason: 'it read the catalog from before the repair',
    );
  });

  testWidgets('another server drops the verdict of the last one', (
    tester,
  ) async {
    final a = _repo()..catalogConsistency = _check(sortKeyDrift: 6);
    final b = _repo();
    final switchTo = await _pumpSwitching(tester, a, b);
    await _tap(tester, SemanticsIds.catalogCheckVerify);
    expect(_inResult(_l10n.healthCatalogDrift), findsOneWidget);

    await switchTo();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.catalogCheckResult),
      findsNothing,
      reason: 'it counted the other server\'s catalog',
    );
    expect(b.catalogChecks, 0);
  });

  testWidgets('a check still out when the server changes does not land', (
    tester,
  ) async {
    _heldStill(tester);
    final a = _repo()
      ..catalogConsistency = _check(sortKeyDrift: 6)
      ..catalogCheckGate = Completer<void>();
    final switchTo = await _pumpSwitching(tester, a, _repo());
    await _tap(tester, SemanticsIds.catalogCheckVerify);
    await switchTo();

    a.catalogCheckGate!.complete();
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.catalogCheckResult),
      findsNothing,
      reason: 'it read the other server\'s catalog',
    );
  });

  testWidgets('a repair refused while the catalog is handed off says why '
      'and points nowhere', (tester) async {
    const refusal = WaxDeckApiException(
      code: 'catalog-maintenance',
      message: 'the catalog is temporarily under maintenance',
      statusCode: 503,
    );
    final repo = _repo()..catalogRepairError = refusal;
    final container = await _pump(tester, repo);
    await _confirmRepair(tester);
    final message = container.read(shellMessengerProvider);
    expect(shellMessageText(message), explainError(_l10n, refusal));
    expect(message?.actionSemanticsId, isNull);
    expect(repo.catalogRepairs, isEmpty);
  });

  testWidgets('a listener sees no catalog check', (tester) async {
    await _pump(
      tester,
      _repo(
        user: const WaxDeckUser(id: 'us-2', username: 'sam'),
      ),
    );
    expect(find.bySemanticsIdentifier(SemanticsIds.catalogCheck), findsNothing);
  });
}
