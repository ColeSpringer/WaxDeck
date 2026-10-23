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

Widget _host(FakeRepository repo) => _hostOf(repo, const OrganizeScreen());

/// [child] under the same scope, so a test can leave the screen and come
/// back to it with the providers it left behind.
Widget _hostOf(FakeRepository repo, Widget child) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: localizedHost(child),
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
        heldByCode: {'read-only': 2},
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

  // The catalog holds moves back for its own reasons too - an item with
  // nothing to file it under, a destination another file wants - and a
  // writable server must not blame those on being read-only.
  testWidgets('a preview says moves held for other causes are held back', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..organizePlanResult = const OrganizePlan(
        profile: 'default',
        totalActions: 1,
        held: 2,
        heldByCode: {'untagged': 1, 'collision': 1},
        actions: [
          OrganizeAction(itemPid: 'tr-1', from: '/old/a.flac', to: '/a.flac'),
        ],
      );
    await _pump(tester, _host(repo));
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizePreview));
    await tester.pumpAndSettle();

    expect(
      find.text('2 files are held back and stay where they are.'),
      findsOneWidget,
    );
    expect(find.textContaining('read-only'), findsNothing);
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
      of: find.text('Held back'),
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

  testWidgets('preview is busy until its dry run answers', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final repo = FakeRepository()..previewOrganizeGate = Completer<void>();
    await _pump(tester, _host(repo));
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizePreview));
    await tester.pump();
    WaxButton preview() => tester.widget<WaxButton>(
      find.byWidgetPredicate(
        (w) => w is WaxButton && w.semanticsId == SemanticsIds.organizePreview,
      ),
    );
    expect(preview().busy, isTrue);

    repo.previewOrganizeGate!.complete();
    await tester.pumpAndSettle();
    expect(preview().busy, isFalse);
  });

  testWidgets('opened to preview, it plans each library at once', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..organizePlanResult = const OrganizePlan(
        profile: 'waxbin-native',
        totalActions: 1,
        actions: [
          OrganizeAction(itemPid: 'tr-1', from: 'a.flac', to: 'A/a.flac'),
        ],
      );
    await _pump(
      tester,
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: localizedHost(const OrganizeScreen(previewOnOpen: true)),
      ),
    );
    expect(repo.previewOrganizeCalls, hasLength(1));
    expect(repo.previewOrganizeCalls.single.profile, isNull);
    expect(repo.previewOrganizeCalls.single.itemPids, isNull);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.organizePlan),
      findsOneWidget,
    );
  });

  testWidgets('a dry run asked for over a chosen profile selects its own', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..organizeProfiles = const [OrganizeProfile(name: 'flat')]
      ..organizePlanResult = const OrganizePlan(
        profile: 'waxbin-native',
        totalActions: 1,
        actions: [
          OrganizeAction(itemPid: 'tr-1', from: 'a.flac', to: 'A/a.flac'),
        ],
      );
    await _pump(tester, _host(repo));
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileOption('flat')),
    );
    await tester.pumpAndSettle();
    // The console keeps the page when its location asks for the dry run.
    await tester.pumpWidget(
      _hostOf(repo, const OrganizeScreen(previewOnOpen: true)),
    );
    await tester.pumpAndSettle();
    expect(repo.previewOrganizeCalls.single.profile, isNull);
    expect(
      tester
          .widget<WaxRadioGroup<String>>(find.byType(WaxRadioGroup<String>))
          .value,
      '',
      reason: 'the plan shown is laid out by each library\'s own profile',
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizeApply));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.confirmField),
      'ORGANIZE',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizeConfirm));
    await tester.pumpAndSettle();
    expect(repo.applyOrganizeCalls.single.profile, isNull);
  });

  testWidgets('a dry run that fails keeps the profile and plan shown', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..organizeProfiles = const [OrganizeProfile(name: 'flat')]
      ..organizePlanResult = const OrganizePlan(
        profile: 'flat',
        totalActions: 1,
        actions: [
          OrganizeAction(itemPid: 'tr-1', from: 'a.flac', to: 'A/a.flac'),
        ],
      );
    await _pump(tester, _host(repo));
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileOption('flat')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizePreview));
    await tester.pumpAndSettle();
    // The location asks for each library's own over the kept page, and
    // that dry run fails.
    repo.previewOrganizeError = const WaxDeckApiException(
      code: 'internal',
      message: 'the catalog is closed',
    );
    await tester.pumpWidget(
      _hostOf(repo, const OrganizeScreen(previewOnOpen: true)),
    );
    await tester.pumpAndSettle();
    expect(repo.previewOrganizeCalls.map((c) => c.profile), ['flat', null]);
    expect(
      tester
          .widget<WaxRadioGroup<String>>(find.byType(WaxRadioGroup<String>))
          .value,
      'flat',
      reason: 'the plan still shown is laid out by flat',
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.organizePlan),
      findsOneWidget,
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizeApply));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.confirmField),
      'flat',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizeConfirm));
    await tester.pumpAndSettle();
    expect(repo.applyOrganizeCalls.single.profile, 'flat');
  });

  testWidgets('a preview lists held moves with their reasons', (tester) async {
    final repo = FakeRepository()
      ..organizePlanResult = const OrganizePlan(
        profile: 'default',
        totalActions: 0,
        held: 2,
        heldByCode: {'untagged': 1, 'collision': 1},
        holds: [
          OrganizeHold(
            itemPid: 'tr-2',
            from: 'nameless.flac',
            code: 'untagged',
            reason: 'no artist, album artist or album to file it under',
          ),
          OrganizeHold(
            itemPid: 'tr-3',
            from: 'twin-b.flac',
            to: 'Pair/Doubles/01 Twin.flac',
            code: 'collision',
            reason: 'twin-a.flac takes Pair/Doubles/01 Twin.flac first',
          ),
        ],
      );
    await _pump(tester, _host(repo));
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizePreview));
    await tester.pumpAndSettle();

    final holds = find.bySemanticsIdentifier(SemanticsIds.organizeHolds);
    expect(holds, findsOneWidget);
    expect(
      find.descendant(of: holds, matching: find.text('2 moves held back')),
      findsOneWidget,
    );
    expect(
      find.text('2 files are held back and stay where they are.'),
      findsNothing,
      reason: 'the table counts them once',
    );
    final untagged = find.bySemanticsIdentifier(
      SemanticsIds.organizeHold('nameless.flac'),
    );
    expect(
      find.descendant(
        of: untagged,
        matching: find.text('No artist or album to file it under'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: untagged,
        matching: find.text(
          'no artist, album artist or album to file it under',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(
          SemanticsIds.organizeHold('twin-b.flac'),
        ),
        matching: find.text('Another file in this run takes the destination'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'a preview held by a read-only server names the server, and a run held by a library names it',
    (tester) async {
      // A plan leaves a read-only library out, so its read-only holds are
      // the server's; a run's are a library's, flagged since its plan.
      final repo = FakeRepository()
        ..organizePlanResult = const OrganizePlan(
          profile: 'default',
          totalActions: 0,
          held: 1,
          heldByCode: {'read-only': 1},
          holds: [
            OrganizeHold(
              itemPid: 'tr-1',
              from: 'stray.flac',
              to: 'Nomad/Wander/01 Stray.flac',
              code: 'read-only',
              reason: 'read-only server',
            ),
          ],
        )
        ..organizeHistory = [
          OrganizeBatch(
            jobPid: 'jb-2',
            kind: 'organize',
            state: 'done',
            startedAt: DateTime.utc(2026, 7, 2, 9),
            committed: 1,
            undoable: true,
          ),
        ]
        ..undoOrganizeResult = const OrganizeReport(
          jobPid: 'jb-3',
          moved: 0,
          skipped: 0,
          held: 1,
          failed: 0,
          holds: [
            OrganizeHold(
              from: 'Nomad/Wander/01 Stray.flac',
              to: 'stray.flac',
              code: 'read-only',
              reason: 'library is read-only',
            ),
          ],
        );
      await _pump(tester, _host(repo));
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.organizePreview),
      );
      await tester.pumpAndSettle();
      final planned = find.bySemanticsIdentifier(
        SemanticsIds.organizeHold('stray.flac'),
      );
      expect(
        find.descendant(
          of: planned,
          matching: find.text('The server is read-only'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: planned,
          matching: find.text('The library is read-only'),
        ),
        findsNothing,
      );

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.organizeUndo('jb-2')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.bySemanticsIdentifier(SemanticsIds.confirmField),
        'UNDO',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.organizeUndoConfirm),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier(
            SemanticsIds.organizeHold('Nomad/Wander/01 Stray.flac'),
          ),
          matching: find.text('The library is read-only'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('history lists runs and undo needs the typed word', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..organizeHistory = [
        OrganizeBatch(
          jobPid: 'jb-2',
          kind: 'organize',
          state: 'done',
          startedAt: DateTime.utc(2026, 7, 2, 9),
          profile: 'waxbin-native',
          committed: 3,
          undoable: true,
        ),
        OrganizeBatch(
          jobPid: 'jb-1',
          kind: 'organize-undo',
          state: 'running',
          startedAt: DateTime.utc(2026, 7, 1, 9),
        ),
      ]
      ..undoOrganizeResult = const OrganizeReport(
        jobPid: 'jb-3',
        moved: 3,
        skipped: 0,
        failed: 0,
      );
    await _pump(tester, _host(repo));

    expect(
      find.bySemanticsIdentifier(SemanticsIds.organizeHistory),
      findsOneWidget,
    );
    final run = find.bySemanticsIdentifier(
      SemanticsIds.organizeHistoryRow('jb-2'),
    );
    expect(
      find.descendant(
        of: run,
        matching: find.textContaining('Organize - 3 moved - '),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.organizeHistoryRow('jb-1')),
        matching: find.textContaining('Undo - 0 moved back - '),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.organizeUndo('jb-1')),
      findsNothing,
      reason: 'a run still going cannot be undone',
    );

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeUndo('jb-2')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Undo this run?'), findsOneWidget);
    // Confirm stays disabled until the exact word is typed.
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeUndoConfirm),
    );
    await tester.pumpAndSettle();
    expect(repo.undoOrganizeCalls, isEmpty);
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.confirmField),
      'UNDONE',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeUndoConfirm),
    );
    await tester.pumpAndSettle();
    expect(repo.undoOrganizeCalls, isEmpty, reason: 'a word that is not UNDO');

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.confirmField),
      'UNDO',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeUndoConfirm),
    );
    await tester.pumpAndSettle();
    expect(repo.undoOrganizeCalls, ['jb-2']);
    expect(shellMessageText(raisedMessage(tester)), '3 files moved back');
    expect(
      find.bySemanticsIdentifier(SemanticsIds.organizeReport),
      findsOneWidget,
    );
    expect(
      repo.listOrganizeHistoryCalls,
      2,
      reason: 'the history is read again',
    );
  });

  testWidgets('an apply lists the run it made in the history', (tester) async {
    final repo = FakeRepository()
      ..organizeHistory = [
        OrganizeBatch(
          jobPid: 'jb-1',
          kind: 'organize',
          state: 'done',
          startedAt: DateTime.utc(2026, 6, 30, 9),
          committed: 7,
          undoable: true,
        ),
      ]
      ..organizePlanResult = const OrganizePlan(
        profile: 'default',
        totalActions: 1,
        actions: [
          OrganizeAction(itemPid: 'tr-1', from: 'a.flac', to: 'A/a.flac'),
        ],
      )
      ..organizeReportResult = const OrganizeReport(
        jobPid: 'jb-9',
        moved: 1,
        skipped: 0,
        failed: 0,
        dirsPruned: 2,
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

    expect(find.text('2 emptied folders removed'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.organizeHistoryRow('jb-9')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.organizeUndo('jb-9')),
      findsOneWidget,
    );
    // The run already listed keeps its own row under the new one.
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.organizeHistoryRow('jb-1')),
        matching: find.textContaining('Organize - 7 moved - '),
      ),
      findsOneWidget,
    );
  });

  testWidgets('an undo lists the files it left where they were, and why', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..organizeHistory = [
        OrganizeBatch(
          jobPid: 'jb-2',
          kind: 'organize',
          state: 'done',
          startedAt: DateTime.utc(2026, 7, 2, 9),
          committed: 2,
          undoable: true,
        ),
      ]
      ..undoOrganizeResult = const OrganizeReport(
        jobPid: 'jb-3',
        moved: 1,
        skipped: 0,
        held: 1,
        failed: 0,
        holds: [
          OrganizeHold(
            from: '/music/Nomad/Wander/01 Stray.flac',
            to: '/music/stray.flac',
            code: 'moved-since',
            reason: 'moved again since the organize left it at /music/x.flac',
          ),
        ],
      );
    await _pump(tester, _host(repo));
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeUndo('jb-2')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.confirmField),
      'UNDO',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.organizeUndoConfirm),
    );
    await tester.pumpAndSettle();

    final report = find.bySemanticsIdentifier(SemanticsIds.organizeReport);
    final hold = find.bySemanticsIdentifier(
      SemanticsIds.organizeHold('/music/Nomad/Wander/01 Stray.flac'),
    );
    expect(
      find.descendant(
        of: report,
        matching: find.bySemanticsIdentifier(SemanticsIds.organizeHolds),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: hold,
        matching: find.text('Moved again since that run'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a one-file run reads in the singular in Spanish', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..organizeHistory = [
        OrganizeBatch(
          jobPid: 'jb-2',
          kind: 'organize-undo',
          state: 'done',
          startedAt: DateTime.utc(2026, 7, 2, 9),
          committed: 1,
        ),
        OrganizeBatch(
          jobPid: 'jb-1',
          kind: 'organize',
          state: 'done',
          startedAt: DateTime.utc(2026, 7, 1, 9),
          committed: 1,
        ),
      ];
    await _pump(
      tester,
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: localizedHost(
          const OrganizeScreen(),
          locale: const Locale('es'),
        ),
      ),
    );
    expect(find.textContaining('Organizar - 1 movido - '), findsOneWidget);
    expect(find.textContaining('Deshacer - 1 devuelto - '), findsOneWidget);
  });

  testWidgets('the history is read again each time the screen opens', (
    tester,
  ) async {
    OrganizeBatch run(String pid) => OrganizeBatch(
      jobPid: pid,
      kind: 'organize',
      state: 'done',
      startedAt: DateTime.utc(2026, 7, 1, 9),
      committed: 1,
      undoable: true,
    );
    final repo = FakeRepository()..organizeHistory = [run('jb-1')];
    await _pump(tester, _host(repo));
    await tester.pumpWidget(_hostOf(repo, const SizedBox()));
    await tester.pumpAndSettle();
    // A run made elsewhere meanwhile: a fix from Health, another session.
    repo.organizeHistory = [run('jb-2'), run('jb-1')];
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.organizeHistoryRow('jb-2')),
      findsOneWidget,
    );
  });

  testWidgets('a run that ends after the screen closed is listed on return', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..applyOrganizeGate = Completer<void>()
      ..organizePlanResult = const OrganizePlan(
        profile: 'default',
        totalActions: 1,
        actions: [
          OrganizeAction(itemPid: 'tr-1', from: 'a.flac', to: 'A/a.flac'),
        ],
      )
      ..organizeReportResult = const OrganizeReport(
        jobPid: 'jb-7',
        moved: 1,
        skipped: 0,
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
    await tester.pump();
    await tester.pumpWidget(_hostOf(repo, const SizedBox()));
    await tester.pumpAndSettle();
    repo.applyOrganizeGate!.complete();
    await tester.pumpAndSettle();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.organizeHistoryRow('jb-7')),
      findsOneWidget,
    );
  });

  testWidgets('with no run yet there is no history', (tester) async {
    final repo = FakeRepository();
    await _pump(tester, _host(repo));
    expect(
      find.bySemanticsIdentifier(SemanticsIds.organizeHistory),
      findsNothing,
    );
    expect(repo.organizeHistoryLimits, [organizeHistoryPageSize]);
  });

  testWidgets('older runs come a page at a time, until the oldest', (
    tester,
  ) async {
    OrganizeBatch run(String pid) => OrganizeBatch(
      jobPid: pid,
      kind: 'organize',
      state: 'done',
      startedAt: DateTime.utc(2026, 7, 1, 9),
      committed: 1,
      undoable: true,
    );
    final repo = FakeRepository()
      ..organizeHistory = [run('jb-3'), run('jb-2'), run('jb-1')]
      ..organizeHistoryPageCap = 2;
    await _pump(tester, _host(repo));
    Finder row(String pid) =>
        find.bySemanticsIdentifier(SemanticsIds.organizeHistoryRow(pid));
    expect(row('jb-3'), findsOneWidget);
    expect(row('jb-2'), findsOneWidget);
    expect(row('jb-1'), findsNothing);

    final more = find.bySemanticsIdentifier(SemanticsIds.organizeHistoryMore);
    await tester.ensureVisible(more);
    await tester.pumpAndSettle();
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(row('jb-1'), findsOneWidget);
    expect(row('jb-3'), findsOneWidget);
    expect(more, findsNothing);
    expect(repo.organizeHistoryCursors, [null, '2']);
  });

  testWidgets('older runs that fail to come say why, and asking again '
      'lists them', (tester) async {
    OrganizeBatch run(String pid) => OrganizeBatch(
      jobPid: pid,
      kind: 'organize',
      state: 'done',
      startedAt: DateTime.utc(2026, 7, 1, 9),
      committed: 1,
      undoable: true,
    );
    final repo = FakeRepository()
      ..organizeHistory = [run('jb-3'), run('jb-2'), run('jb-1')]
      ..organizeHistoryPageCap = 2
      ..organizeHistoryOlderError = const WaxDeckApiException(
        code: 'transport',
        message: 'connection refused',
      );
    await _pump(tester, _host(repo));
    Finder row(String pid) =>
        find.bySemanticsIdentifier(SemanticsIds.organizeHistoryRow(pid));
    final more = find.bySemanticsIdentifier(SemanticsIds.organizeHistoryMore);
    await tester.ensureVisible(more);
    await tester.pumpAndSettle();
    await tester.tap(more);
    await tester.pumpAndSettle();

    expect(
      shellMessageText(raisedMessage(tester)),
      'Could not reach the server. Check the connection and try again.',
    );
    expect(row('jb-1'), findsNothing);
    expect(row('jb-2'), findsOneWidget);
    expect(more, findsOneWidget);

    repo.organizeHistoryOlderError = null;
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(row('jb-1'), findsOneWidget);
    expect(more, findsNothing);
    expect(repo.organizeHistoryCursors, [null, '2', '2']);
  });
}
