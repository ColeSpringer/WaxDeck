import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/admin_console.dart';
import 'package:waxdeck/src/admin/dashboard_screen.dart';
import 'package:waxdeck/src/admin/genres_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

ProviderContainer _container(FakeRepository repo) {
  final container = ProviderContainer(
    overrides: [repositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container,
  Widget screen, {
  Size size = const Size(1280, 1600),
  String? at,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: routedHost(screen, at: at),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the section list', () {
    test('claims a location by the longest declared prefix', () {
      // The dashboard's own location is a prefix of every other one, so
      // it wins only when nothing longer matches. A drill-in keeps its
      // section lit.
      expect(AdminSection.forLocation(WaxRoute.admin), AdminSection.dashboard);
      expect(AdminSection.forLocation(WaxRoute.trash), AdminSection.trash);
      expect(
        AdminSection.forLocation(WaxRoute.healthRule('missing-artwork')),
        AdminSection.health,
      );
      expect(
        AdminSection.forLocation(WaxRoute.adminSettings),
        AdminSection.settings,
      );
      // Not a console location at all.
      expect(AdminSection.forLocation(WaxRoute.home), isNull);
    });

    test('every section names a location the router declares', () {
      // A section pointing nowhere is a link to a 404; the route table
      // test covers the other direction.
      for (final section in AdminSection.values) {
        expect(section.location, startsWith(WaxRoute.admin));
      }
    });
  });

  testWidgets('the console draws its section list where there is room', (
    tester,
  ) async {
    final container = _container(FakeRepository());
    await _pump(
      tester,
      container,
      const AdminConsole(location: WaxRoute.trash, child: SizedBox.shrink()),
    );

    expect(
      find.bySemanticsIdentifier(SemanticsIds.adminConsole),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(AdminSection.trash.semanticsId),
      findsOneWidget,
    );
    expect(find.text('Libraries'), findsOneWidget);
  });

  testWidgets('below sidebar width the console is the page alone', (
    tester,
  ) async {
    final container = _container(FakeRepository());
    await _pump(
      tester,
      container,
      const AdminConsole(location: WaxRoute.trash, child: SizedBox.shrink()),
      size: const Size(420, 900),
    );

    // No rail: a phone spends its width on the page, and `/admin` is the
    // list of sections instead.
    expect(find.bySemanticsIdentifier(SemanticsIds.adminConsole), findsNothing);
    expect(
      find.bySemanticsIdentifier(AdminSection.trash.semanticsId),
      findsNothing,
    );
  });

  testWidgets('the compact dashboard lists every section', (tester) async {
    final container = _container(FakeRepository());
    await _pump(
      tester,
      container,
      const AdminDashboardScreen(),
      size: const Size(420, 2400),
    );

    for (final section in AdminSection.values) {
      if (section == AdminSection.dashboard) continue;
      expect(
        find.bySemanticsIdentifier(section.semanticsId),
        findsOneWidget,
        reason: '${section.title} must be reachable where there is no rail',
      );
    }
  });

  testWidgets('the dashboard starts a scan and says what happened', (
    tester,
  ) async {
    final repo = FakeRepository();
    final container = _container(repo);
    await _pump(tester, container, const AdminDashboardScreen());

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.adminAction('scan')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(repo.rescans, 1);
    expect(container.read(shellMessengerProvider)?.text, 'Scan started');
  });

  testWidgets('the genre editor edits a draft and saves it whole', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..genreTree = <GenreNode>[
        const GenreNode(name: 'Metal'),
        const GenreNode(name: 'Doom Metal', parent: 'Metal'),
      ];
    final container = _container(repo);
    await _pump(tester, container, const GenreTreeScreen());

    expect(
      find.bySemanticsIdentifier(SemanticsIds.genreNode('Doom Metal')),
      findsOneWidget,
    );

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.genreNode('Doom Metal')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    // Typed and not submitted. Waiting for Enter is what made Save
    // write the vocabulary without whatever had just been typed.
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.genreAliases),
      'Funeral Doom, Sludge',
    );
    await tester.pumpAndSettle();

    // Nothing has been written yet: the whole vocabulary goes in one
    // call, because every save rewinds the normalization sweeper.
    expect(repo.genreTree.first.aliases, isEmpty);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.genreSave),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    final doom = repo.genreTree.firstWhere((g) => g.name == 'Doom Metal');
    expect(doom.aliases, <String>['Funeral Doom', 'Sludge']);
    expect(container.read(shellMessengerProvider)?.text, 'Genre tree saved');
  });

  // Removing a parent must not take its children with it: they come up a
  // level, because a genre whose parent is gone would otherwise vanish
  // from the editor while still being sent back on save.
  testWidgets('removing a parent lifts what grouped under it', (tester) async {
    final repo = FakeRepository()
      ..genreTree = <GenreNode>[
        const GenreNode(name: 'Metal'),
        const GenreNode(name: 'Doom Metal', parent: 'Metal'),
      ];
    final container = _container(repo);
    await _pump(tester, container, const GenreTreeScreen());

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.genreNode('Metal')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.genreDelete),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.genreSave),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(repo.genreTree.map((g) => g.name), <String>['Doom Metal']);
    expect(repo.genreTree.single.parent, isNull);
  });

  // The contract's own revert: an empty vocabulary clears the override
  // rather than storing a copy of the shipped tree.
  testWidgets('reverting stores an empty vocabulary once confirmed', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..genreTree = <GenreNode>[const GenreNode(name: 'Metal')];
    final container = _container(repo);
    await _pump(tester, container, const GenreTreeScreen());

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.genreRevert),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.confirmField),
      'REVERT',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.confirmAccept),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(repo.genreTree, isEmpty);
  });

  // Renaming onto a name another genre already has would leave two
  // nodes sharing it: the tree is keyed by name, so the next edit would
  // merge their children and the vocabulary would post unresolvable.
  testWidgets('a rename onto an existing name is refused on the field', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..genreTree = <GenreNode>[
        const GenreNode(name: 'Hip Hop'),
        const GenreNode(name: 'Rap'),
      ];
    final container = _container(repo);
    await _pump(tester, container, const GenreTreeScreen());

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.genreNode('Hip Hop')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.genreName),
      'Rap',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('already called Rap'), findsOneWidget);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.genreSave),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    // Both genres survive under their own names.
    expect(repo.genreTree.map((g) => g.name).toList()..sort(), <String>[
      'Hip Hop',
      'Rap',
    ]);
  });

  testWidgets('the normalize actions start dry and wet runs', (tester) async {
    final repo = FakeRepository();
    final container = _container(repo);
    await _pump(tester, container, const GenreTreeScreen());

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.genreNormalizeDryRun),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.genreNormalize),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(repo.genreNormalizations, <bool>[true, false]);
  });
}
