import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/admin_shares_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/sharing/shares_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

Share _share({
  required String pid,
  required String title,
  String? owner,
  int plays = 0,
  String kind = 'track',
}) => Share(
  pid: pid,
  url: '/s/SECRET$pid',
  targetPid: 'tr-$pid',
  targetKind: kind,
  targetTitle: title,
  allowDownload: false,
  createdAt: DateTime.utc(2026, 7, 20, 12),
  plays: plays,
  owner: owner,
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeRepository repo,
  Widget screen,
) async {
  tester.view.physicalSize = const Size(1280, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [repositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: routedHost(screen)),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('the console lists every account\'s links and names them', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..allShares.addAll(<Share>[
        _share(pid: 'sh-1', title: 'Prancing Pony Blues', owner: 'Sam Gamgee'),
        _share(pid: 'sh-2', title: 'The Road Goes Ever On', owner: 'admin'),
      ]);
    await _pump(tester, repo, const AdminSharesScreen());

    // The wide listing, not the caller's own: the screen exists to show
    // what everybody published.
    expect(repo.listSharesCalls, <bool>[true]);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.shareRow('sh-1')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.shareRow('sh-2')),
      findsOneWidget,
    );
    // The owner leads the caption: it is what turns a row into
    // somebody's.
    expect(find.textContaining('Sam Gamgee · Track'), findsOneWidget);
  });

  testWidgets('a link revoked here leaves the wide listing', (tester) async {
    final repo = FakeRepository()
      ..allShares.add(_share(pid: 'sh-1', title: 'Gone', owner: 'Sam Gamgee'));
    await _pump(tester, repo, const AdminSharesScreen());

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.shareRevoke('sh-1')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(repo.revokeShareCalls, <String>['sh-1']);
  });

  testWidgets('nothing shared reads as its own state', (tester) async {
    final repo = FakeRepository();
    await _pump(tester, repo, const AdminSharesScreen());

    expect(
      find.bySemanticsIdentifier(SemanticsIds.adminSharesEmpty),
      findsOneWidget,
    );
  });

  // The two listings are separate providers because an administrator can
  // hold both screens in one history, and each answers different rows.
  testWidgets('the personal listing still asks for the caller\'s own', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..shares.add(_share(pid: 'sh-9', title: 'Mine'));
    await _pump(tester, repo, const SharesScreen());

    expect(repo.listSharesCalls, <bool>[false]);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.shareRow('sh-9')),
      findsOneWidget,
    );
  });
}
