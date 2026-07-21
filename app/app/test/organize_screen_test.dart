import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/organize/organize_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: const MaterialApp(home: OrganizeScreen()),
);

void main() {
  testWidgets('an empty profile list explains server configuration', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.organizeProfiles = const [];
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('No organize profiles are configured'),
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
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('organize-preview')));
    await tester.pumpAndSettle();

    expect(repo.previewOrganizeCalls, hasLength(1));
    expect(repo.previewOrganizeCalls.single.profile, 'default');
    expect(find.byKey(const Key('organize-plan')), findsOneWidget);
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
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('organize-preview')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('organize-apply')));
    await tester.pumpAndSettle();

    // Confirm stays disabled until the exact profile name is typed.
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('organize-confirm')))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const Key('organize-confirm-field')),
      'default',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('organize-confirm')));
    await tester.pumpAndSettle();

    expect(repo.applyOrganizeCalls, hasLength(1));
    expect(repo.applyOrganizeCalls.single.profile, 'default');
    expect(find.byKey(const Key('organize-report')), findsOneWidget);
    expect(find.text('Moved 1, skipped 0, failed 1'), findsOneWidget);
    expect(find.text('/old/b.flac: target exists'), findsOneWidget);
  });
}
