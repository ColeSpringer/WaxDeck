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
  testWidgets('an empty profile list explains server configuration', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.organizeProfiles = const [];
    await _pump(tester, _host(repo));

    expect(find.text('No organize profiles'), findsOneWidget);
    expect(
      find.textContaining('part of the server configuration'),
      findsOneWidget,
    );
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
}
