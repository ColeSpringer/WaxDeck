import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/organize/organize_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'localized_host.dart';

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: localizedHost(const OrganizeScreen()),
);

/// Wide enough for the plan to be a table rather than a card list.
Future<void> _pump(WidgetTester tester, Widget host) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(host);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an empty profile list promises no configuration', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.organizeProfiles = const [];
    await _pump(tester, _host(repo));

    expect(find.text('No organize profiles'), findsOneWidget);
    expect(
      find.text('The server offers no profile to organize files by.'),
      findsOneWidget,
    );
  });

  testWidgets('a lone profile is named as the built-in one', (tester) async {
    final repo = FakeRepository()
      ..organizeProfiles = const [OrganizeProfile(name: 'waxbin-native')];
    await _pump(tester, _host(repo));
    expect(
      find.text('This server has only the built-in profile.'),
      findsOneWidget,
    );

    repo.organizeProfiles = const [
      OrganizeProfile(name: 'waxbin-native'),
      OrganizeProfile(name: 'classical'),
    ];
    await _pump(
      tester,
      ProviderScope(
        key: UniqueKey(),
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: localizedHost(const OrganizeScreen()),
      ),
    );
    expect(
      find.text('This server has only the built-in profile.'),
      findsNothing,
    );
  });

  testWidgets('the hint says a preview checks every managed library', (
    tester,
  ) async {
    await _pump(tester, _host(FakeRepository()));

    expect(
      find.textContaining('checks every managed library against this profile'),
      findsOneWidget,
    );
  });

  testWidgets('with no managed library it says where organizing works', (
    tester,
  ) async {
    final repo = FakeRepository()..organizeManagedLibraries = 0;
    await _pump(tester, _host(repo));

    expect(find.text('No managed library'), findsOneWidget);
    expect(
      find.text(
        'Organizing moves files only within managed libraries, and this '
        'server has none.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.organizePreview),
      findsNothing,
    );
  });

  testWidgets('a preview says what a read-only library holds back', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..organizePlanResult = const OrganizePlan(
        profile: 'default',
        totalActions: 0,
        held: 2,
      );
    await _pump(tester, _host(repo));
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizePreview));
    await tester.pumpAndSettle();

    expect(
      find.text('2 files stay where they are: their libraries are read-only.'),
      findsOneWidget,
    );
    expect(find.text('Everything is already in place'), findsNothing);
  });

  testWidgets('a run counts what a read-only library held back', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..organizePlanResult = const OrganizePlan(
        profile: 'default',
        totalActions: 1,
        held: 2,
        actions: [
          OrganizeAction(itemPid: 'tr-1', from: '/old/a.flac', to: '/a.flac'),
        ],
      )
      ..organizeReportResult = const OrganizeReport(
        moved: 1,
        skipped: 0,
        held: 2,
        failed: 0,
      );
    await _pump(tester, _host(repo));
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizePreview));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizeApply));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.confirmField),
      'default',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizeConfirm));
    await tester.pumpAndSettle();

    final tile = find.ancestor(
      of: find.text('Read-only'),
      matching: find.byType(StatTile),
    );
    expect(find.descendant(of: tile, matching: find.text('2')), findsOneWidget);
  });

  testWidgets('a preview can be discarded', (tester) async {
    final repo = FakeRepository()
      ..organizePlanResult = const OrganizePlan(
        profile: 'default',
        totalActions: 1,
        actions: [
          OrganizeAction(itemPid: 'tr-1', from: '/old/a.flac', to: '/a.flac'),
        ],
      );
    await _pump(tester, _host(repo));
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizePreview));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.organizePlan),
      findsOneWidget,
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizeDiscard));
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier(SemanticsIds.organizePlan), findsNothing);
    expect(
      find.textContaining('checks every managed library against this profile'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<WaxButton>(
            find.byWidgetPredicate(
              (w) =>
                  w is WaxButton && w.semanticsId == SemanticsIds.organizeApply,
            ),
          )
          .onPressed,
      isNull,
      reason: 'no plan, no apply',
    );
    expect(repo.applyOrganizeCalls, isEmpty);
  });

  testWidgets('preview renders the plan', (tester) async {
    final repo = FakeRepository();
    repo.organizePlanResult = const OrganizePlan(
      profile: 'default',
      totalActions: 2,
      actions: [
        OrganizeAction(
          itemPid: 'tr-1',
          from: '/old/a.flac',
          to: '/library/waves/a.flac',
        ),
        OrganizeAction(
          itemPid: 'tr-2',
          from: '/old/b.flac',
          to: '/library/waves/b.flac',
        ),
      ],
    );
    await _pump(tester, _host(repo));

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizePreview));
    await tester.pumpAndSettle();

    expect(repo.previewOrganizeCalls, hasLength(1));
    expect(repo.previewOrganizeCalls.single.profile, 'default');
    expect(
      find.bySemanticsIdentifier(SemanticsIds.organizePlan),
      findsOneWidget,
    );
    expect(find.text('2 planned moves'), findsOneWidget);
    expect(find.text('/old/a.flac'), findsOneWidget);
    expect(find.text('/library/waves/b.flac'), findsOneWidget);
  });

  testWidgets('apply requires typing the profile name', (tester) async {
    final repo = FakeRepository();
    repo.organizePlanResult = const OrganizePlan(
      profile: 'default',
      totalActions: 1,
      actions: [
        OrganizeAction(itemPid: 'tr-1', from: '/old/a.flac', to: '/new/a.flac'),
      ],
    );
    repo.organizeReportResult = const OrganizeReport(
      moved: 1,
      skipped: 0,
      failed: 1,
      failures: [OrganizeFailure(path: '/old/b.flac', reason: 'target exists')],
    );
    await _pump(tester, _host(repo));

    // Apply is refused until a plan says what would move.
    expect(
      tester
          .widget<WaxButton>(
            find.ancestor(
              of: find.text('Apply'),
              matching: find.byType(WaxButton),
            ),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizePreview));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizeApply));
    await tester.pumpAndSettle();

    // Confirm stays disabled until the exact profile name is typed.
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizeConfirm));
    await tester.pumpAndSettle();
    expect(repo.applyOrganizeCalls, isEmpty);

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.confirmField),
      'default',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizeConfirm));
    await tester.pumpAndSettle();

    expect(repo.applyOrganizeCalls, hasLength(1));
    expect(repo.applyOrganizeCalls.single.profile, 'default');
    expect(
      find.bySemanticsIdentifier(SemanticsIds.organizeReport),
      findsOneWidget,
    );
    expect(find.text('Moved'), findsOneWidget);
    expect(find.text('/old/b.flac'), findsOneWidget);
    expect(find.text('target exists'), findsOneWidget);
  });

  testWidgets('apply is busy until the moves answer', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final repo = FakeRepository()..applyOrganizeGate = Completer<void>();
    repo.organizePlanResult = const OrganizePlan(
      profile: 'default',
      totalActions: 1,
      actions: [
        OrganizeAction(
          itemPid: 'tr-1',
          from: '/old/a.flac',
          to: '/library/waves/a.flac',
        ),
      ],
    );
    await _pump(tester, _host(repo));
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizePreview));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizeApply));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.confirmField),
      'default',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizeConfirm));
    await tester.pumpAndSettle();
    WaxButton apply() => tester.widget<WaxButton>(
      find.byWidgetPredicate(
        (w) => w is WaxButton && w.semanticsId == SemanticsIds.organizeApply,
      ),
    );
    expect(apply().busy, isTrue);

    repo.applyOrganizeGate!.complete();
    await tester.pumpAndSettle();
    expect(apply().busy, isFalse);
  });
}
