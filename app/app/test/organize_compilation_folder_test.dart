import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/organize/organize_screen.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';
import 'wax_finders.dart';

Future<void> _pump(WidgetTester tester, FakeRepository repo) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpApp(
    tester,
    const OrganizeScreen(),
    container: appContainer(repo: repo),
    routed: false,
  );
}

Future<void> _newProfile(WidgetTester tester, String name) async {
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.organizeProfileNew));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.bySemanticsIdentifier(SemanticsIds.organizeProfileName),
    name,
  );
  await tester.pump();
}

Future<void> _editProfile(WidgetTester tester, String name) async {
  await tester.tap(
    find.bySemanticsIdentifier(SemanticsIds.organizeProfileOption(name)),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.bySemanticsIdentifier(SemanticsIds.organizeProfileEdit(name)),
  );
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(
    find.bySemanticsIdentifier(SemanticsIds.organizeProfileSave),
  );
  await tester.pumpAndSettle();
}

TextField _folderField(WidgetTester tester) => tester.widget<TextField>(
  find.descendant(
    of: find.bySemanticsIdentifier(SemanticsIds.organizeProfileCompilation),
    matching: find.byType(TextField),
  ),
);

void main() {
  testWidgets('a default left alone sends no compilation folder', (
    tester,
  ) async {
    final repo = FakeRepository();
    await _pump(tester, repo);
    await _newProfile(tester, 'flat');
    expect(
      find.textContaining('Various Artists unless set'),
      findsNothing,
      reason: 'the hint inside the field says it',
    );
    expect(infoTipContaining('Rewrites unlocked'), findsOneWidget);
    expect(_folderField(tester).decoration?.hintText, 'Various Artists');

    await _save(tester);
    expect(repo.putOrganizeProfileCalls.single.name, 'flat');
    expect(repo.putOrganizeProfileCalls.single.compilationFolder, isNull);
  });

  testWidgets('a cleared folder sends an empty one', (tester) async {
    final repo = FakeRepository()
      ..organizeProfiles = const [
        OrganizeProfile(
          name: 'mixes',
          compilationFolder: 'Mixes',
          saved: OrganizeTemplates(),
        ),
      ];
    await _pump(tester, repo);
    await _editProfile(tester, 'mixes');
    expect(_folderField(tester).controller!.text, 'Mixes');

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileCompilation),
      '',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(
      _folderField(tester).decoration?.hintText,
      "Each one's tagged album artist",
      reason: 'the hint says what an emptied folder does',
    );
    expect(repo.previewOrganizeProfileFolders.last, '');

    await _save(tester);
    expect(repo.putOrganizeProfileCalls.single.compilationFolder, '');
  });

  testWidgets('a typed folder sends its name and the sample follows it', (
    tester,
  ) async {
    final repo = FakeRepository();
    await _pump(tester, repo);
    await _newProfile(tester, 'flat');
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileCompilation),
      'Compilations',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(repo.previewOrganizeProfileFolders.last, 'Compilations');
    expect(
      find.text(
        'Compilation: Compilations/Coastal Nights/04 - Night Drive.flac',
      ),
      findsOneWidget,
    );

    await _save(tester);
    expect(
      repo.putOrganizeProfileCalls.single.compilationFolder,
      'Compilations',
    );
  });

  testWidgets('an unset folder stays unset when a template is edited', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..organizeProfiles = const [
        OrganizeProfile(name: 'flat', saved: OrganizeTemplates()),
      ];
    await _pump(tester, repo);
    await _editProfile(tester, 'flat');
    expect(_folderField(tester).controller!.text, isEmpty);
    expect(_folderField(tester).decoration?.hintText, 'Various Artists');
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.organizeProfileMusic),
      '{title}.{ext}',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(repo.previewOrganizeProfileFolders.last, isNull);

    await _save(tester);
    expect(repo.putOrganizeProfileCalls.single.musicTemplate, '{title}.{ext}');
    expect(repo.putOrganizeProfileCalls.single.compilationFolder, isNull);
  });

  testWidgets('a saved empty folder left alone stays empty', (tester) async {
    final repo = FakeRepository()
      ..organizeProfiles = const [
        OrganizeProfile(
          name: 'own',
          compilationFolder: '',
          saved: OrganizeTemplates(),
        ),
      ];
    await _pump(tester, repo);
    await _editProfile(tester, 'own');
    expect(
      _folderField(tester).decoration?.hintText,
      "Each one's tagged album artist",
    );

    await _save(tester);
    expect(repo.putOrganizeProfileCalls.single.compilationFolder, '');
  });
}
