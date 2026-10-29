import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/playlists/playlist_create.dart';
import 'package:waxdeck/src/playlists/playlists_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'localized_host.dart';
import 'routed_host.dart';

/// What a name field holds once 201 characters are typed into it.
Future<String> _typed(WidgetTester tester, String id) async {
  final field = find.descendant(
    of: find.bySemanticsIdentifier(id),
    matching: find.byType(TextField),
  );
  await tester.enterText(field, 'n' * 201);
  return tester.widget<TextField>(field).controller!.text;
}

Widget _playlists() => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(FakeRepository())],
  child: routedHost(const PlaylistsScreen(), pushed: true),
);

// Every field that names a playlist stops at the 200 characters the
// server takes, so its refusal is never the first a person hears of it.
void main() {
  testWidgets('the new playlist dialog, smart or static', (tester) async {
    await tester.pumpWidget(_playlists());
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistAdd));
    await tester.pumpAndSettle();

    expect((await _typed(tester, SemanticsIds.playlistNameField)).length, 200);
  });

  testWidgets('the name prompt that renames and makes from the add sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      localizedHost(
        Scaffold(
          body: Builder(
            builder: (context) => WaxButton(
              label: 'Open',
              onPressed: () => promptPlaylistName(
                context,
                title: 'Rename',
                confirmLabel: 'Rename',
                initial: 'Old name',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect((await _typed(tester, SemanticsIds.playlistNameField)).length, 200);
  });

  testWidgets('the import dialog', (tester) async {
    await tester.pumpWidget(_playlists());
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistImport));
    await tester.pumpAndSettle();
    await tester.tap(find.text('M3U file'));
    await tester.pumpAndSettle();

    expect((await _typed(tester, SemanticsIds.playlistImportName)).length, 200);
  });
}
