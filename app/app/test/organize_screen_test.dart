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

  testWidgets('the picker offers each library\'s own and every profile', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..organizeProfiles = const [
        OrganizeProfile(
          name: 'waxbin-native',
          builtIn: true,
          sample: OrganizeSample(music: 'Artist/Album/01 - Title.flac'),
        ),
        OrganizeProfile(
          name: 'flat',
          sample: OrganizeSample(music: 'Title.flac'),
        ),
      ];
    await _pump(tester, _host(repo));
    expect(find.text("Each library's own profile"), findsOneWidget);
    expect(find.text('waxbin-native (built in)'), findsOneWidget);
    expect(find.text('Artist/Album/01 - Title.flac'), findsOneWidget);
    expect(find.text('Title.flac'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileEdit('flat')),
      findsNothing,
      reason: 'nothing to edit until a profile is chosen',
    );

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileOption('flat')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizePreview));
    await tester.pumpAndSettle();
    expect(repo.previewOrganizeCalls.single.profile, 'flat');
    expect(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileEdit('flat')),
      findsOneWidget,
    );
  });

  testWidgets('a new profile is saved with its samples on show', (
    tester,
  ) async {
    final repo = FakeRepository();
    await _pump(tester, _host(repo));
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileNew),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileName),
      'flat',
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileMusic),
      '{title}.{ext}',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Track: {title}.{ext}'), findsOneWidget);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileSave),
    );
    await tester.pumpAndSettle();
    expect(repo.putOrganizeProfileCalls.single.name, 'flat');
    expect(repo.putOrganizeProfileCalls.single.musicTemplate, '{title}.{ext}');
    expect(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileOption('flat')),
      findsOneWidget,
      reason: 'the listing is read again',
    );
  });

  testWidgets('a save still lands once its sheet is dismissed', (tester) async {
    final gate = Completer<void>();
    final repo = FakeRepository()..organizeProfileGate = gate;
    await _pump(tester, _host(repo));
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileNew),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileName),
      'flat',
    );
    await tester.pump();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileSave),
    );
    await tester.pump();
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileSheet),
      findsNothing,
    );

    gate.complete();
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileOption('flat')),
      findsOneWidget,
      reason: 'the listing is read again',
    );
  });

  testWidgets('a profile is deleted behind a confirmation', (tester) async {
    final repo = FakeRepository()
      ..organizeProfiles = const [
        OrganizeProfile(name: 'default', builtIn: true),
        OrganizeProfile(name: 'flat'),
      ];
    await _pump(tester, _host(repo));
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileOption('flat')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileEdit('flat')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileDelete('flat')),
    );
    await tester.pumpAndSettle();
    expect(repo.deleteOrganizeProfileCalls, isEmpty);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileDeleteConfirm),
    );
    await tester.pumpAndSettle();
    expect(repo.deleteOrganizeProfileCalls, ['flat']);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileOption('flat')),
      findsNothing,
    );
  });

  testWidgets('a built-in profile offers no delete', (tester) async {
    final repo = FakeRepository()
      ..organizeProfiles = const [
        OrganizeProfile(name: 'default', builtIn: true),
      ];
    await _pump(tester, _host(repo));
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileOption('default')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileEdit('default')),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileDelete('default')),
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

  testWidgets('a preview says what a read-only server holds back', (
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
      find.text('2 files stay where they are while the server is read-only.'),
      findsOneWidget,
    );
    expect(find.text('Everything is already in place'), findsNothing);
  });

  testWidgets('a preview and a run name the read-only libraries left out', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..organizePlanResult = const OrganizePlan(
        profile: 'default',
        totalActions: 1,
        readOnlyLibraries: 2,
        actions: [
          OrganizeAction(itemPid: 'tr-1', from: '/old/a.flac', to: '/a.flac'),
        ],
      )
      ..organizeReportResult = const OrganizeReport(
        moved: 1,
        skipped: 0,
        readOnlyLibraries: 2,
        failed: 0,
      );
    await _pump(tester, _host(repo));
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizePreview));
    await tester.pumpAndSettle();
    const line = '2 read-only libraries are left as they are.';
    expect(find.text(line), findsOneWidget);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizeApply));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.confirmField),
      'ORGANIZE',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizeConfirm));
    await tester.pumpAndSettle();
    expect(find.text(line), findsOneWidget);
  });

  testWidgets('a run counts what a read-only server held back', (tester) async {
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
      'ORGANIZE',
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

  testWidgets('an edit or a deletion drops the preview laid out by it', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..organizeProfiles = const [
        OrganizeProfile(name: 'default', builtIn: true),
        OrganizeProfile(name: 'flat'),
      ]
      ..organizePlanResult = const OrganizePlan(
        profile: 'flat',
        totalActions: 1,
        actions: [
          OrganizeAction(itemPid: 'tr-1', from: '/old/a.flac', to: '/a.flac'),
        ],
      );
    await _pump(tester, _host(repo));
    Future<void> previewFlat() async {
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.organizeProfileOption('flat')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.organizePreview),
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier(SemanticsIds.organizePlan),
        findsOneWidget,
      );
    }

    await previewFlat();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileEdit('flat')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileMusic),
      '{title}.{ext}',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileSave),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.organizePlan),
      findsNothing,
      reason: 'the edit changed what Apply would do',
    );

    await previewFlat();
    repo.organizeProfiles = const [
      OrganizeProfile(name: 'default', builtIn: true),
    ];
    final element = tester.element(find.byType(OrganizeScreen));
    ProviderScope.containerOf(element).invalidate(organizeProfilesProvider);
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.organizePlan),
      findsNothing,
      reason: 'deleted elsewhere, the profile no longer lays anything out',
    );
  });

  testWidgets('a save landing after its sheet is gone drops the preview', (
    tester,
  ) async {
    final gate = Completer<void>();
    final repo = FakeRepository()
      ..organizeProfiles = const [
        OrganizeProfile(name: 'default', builtIn: true),
        OrganizeProfile(name: 'flat'),
      ]
      ..organizePlanResult = const OrganizePlan(
        profile: 'flat',
        totalActions: 1,
        actions: [
          OrganizeAction(itemPid: 'tr-1', from: '/old/a.flac', to: '/a.flac'),
        ],
      );
    await _pump(tester, _host(repo));
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileOption('flat')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizePreview));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileEdit('flat')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileMusic),
      '{title}.{ext}',
    );
    repo.organizeProfileGate = gate;
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileSave),
    );
    await tester.pump();
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    gate.complete();
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.organizePlan),
      findsNothing,
      reason: 'Apply would lay out by the new templates',
    );
  });

  testWidgets('a new profile cannot take a name already used', (tester) async {
    final repo = FakeRepository()
      ..organizeProfiles = const [
        OrganizeProfile(name: 'default', builtIn: true),
        OrganizeProfile(name: 'flat'),
      ];
    await _pump(tester, _host(repo));
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileNew),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileName),
      'flat',
    );
    await tester.pump();
    expect(find.textContaining('edit it instead'), findsOneWidget);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileSave),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(repo.putOrganizeProfileCalls, isEmpty);
  });

  testWidgets('the editor starts from what the profile sets itself', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..organizeProfiles = const [
        OrganizeProfile(
          name: 'flat',
          musicTemplate: '{title}.{ext}',
          audiobookTemplate: 'Inherited/{title}.{ext}',
          saved: OrganizeTemplates(music: '{title}.{ext}'),
        ),
      ];
    await _pump(tester, _host(repo));
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileOption('flat')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileEdit('flat')),
    );
    await tester.pumpAndSettle();
    TextField field(String id) => tester.widget<TextField>(
      find.descendant(
        of: find.bySemanticsIdentifier(id),
        matching: find.byType(TextField),
      ),
    );
    expect(
      field(SemanticsIds.organizeProfileMusic).controller!.text,
      '{title}.{ext}',
    );
    expect(
      field(SemanticsIds.organizeProfileAudiobook).controller!.text,
      isEmpty,
    );
    expect(
      find.text('Inherited/{title}.{ext}'),
      findsOneWidget,
      reason: 'the inherited template as the hint',
    );
  });

  testWidgets('a sample the template cannot place says so', (tester) async {
    final repo = FakeRepository()
      ..organizeProfiles = const [
        OrganizeProfile(
          name: 'flat',
          sample: OrganizeSample(audiobook: 'a', podcast: 'b'),
        ),
      ];
    await _pump(tester, _host(repo));
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileOption('flat')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileEdit('flat')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('no path for this sample'), findsOneWidget);
  });

  testWidgets('an older sample answer never replaces a newer one', (
    tester,
  ) async {
    final first = Completer<OrganizeSample>();
    final repo = FakeRepository()
      ..organizeSampleAnswer = (music) => music == '{ti'
          ? first.future
          : Future.value(
              OrganizeSample(music: music, audiobook: 'a', podcast: 'b'),
            );
    await _pump(tester, _host(repo));
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileNew),
    );
    await tester.pumpAndSettle();
    final music = find.bySemanticsIdentifier(SemanticsIds.organizeProfileMusic);
    await tester.enterText(music, '{ti');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(music, '{title}.{ext}');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    first.completeError(
      const WaxDeckApiException(
        code: 'invalid-request',
        message: 'unterminated',
        statusCode: 400,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Track: {title}.{ext}'), findsOneWidget);
    expect(find.text('unterminated'), findsNothing);
  });

  testWidgets('a refused save is said inside the sheet', (tester) async {
    final repo = FakeRepository()
      ..putOrganizeProfileError = const WaxDeckApiException(
        code: 'invalid-request',
        message: 'a template is at most 1024 characters',
        statusCode: 400,
      );
    await _pump(tester, _host(repo));
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileNew),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileName),
      'long',
    );
    await tester.pump();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileSave),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.organizeProfileSheet),
        matching: find.textContaining('at most 1024 characters'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the picker names its group', (tester) async {
    final repo = FakeRepository()
      ..organizeProfiles = const [OrganizeProfile(name: 'flat')];
    await _pump(tester, _host(repo));
    expect(find.bySemanticsLabel('Organize profile'), findsOneWidget);
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
    expect(
      repo.previewOrganizeCalls.single.profile,
      isNull,
      reason: "each library's own profile by default",
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.organizePlan),
      findsOneWidget,
    );
    expect(find.text('2 planned moves'), findsOneWidget);
    expect(find.text('/old/a.flac'), findsOneWidget);
    expect(find.text('/library/waves/b.flac'), findsOneWidget);
  });

  testWidgets('apply requires typing the confirm word', (tester) async {
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

    // Confirm stays disabled until the exact word is typed.
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizeConfirm));
    await tester.pumpAndSettle();
    expect(repo.applyOrganizeCalls, isEmpty);

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.confirmField),
      'ORGANIZE',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizeConfirm));
    await tester.pumpAndSettle();

    expect(repo.applyOrganizeCalls, hasLength(1));
    expect(repo.applyOrganizeCalls.single.profile, isNull);
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
      'ORGANIZE',
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
