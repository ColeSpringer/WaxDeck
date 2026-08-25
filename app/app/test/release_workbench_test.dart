import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/metadata/release_workbench.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'routed_host.dart';

const _album = 'al-01JZX5N8QW3F4V9T2B7KDALBUM';
const _regrouped = 'al-01JZX5N8QW3F4V9T2B7KDNEWER';

Finder _byId(String id) => find.bySemanticsIdentifier(id);

FakeRepository _repo() {
  final repo = FakeRepository(
    sessionState: const SessionState(
      authenticated: true,
      user: WaxDeckUser(
        id: 'us-1',
        username: 'admin',
        roles: <String>['admin'],
      ),
    ),
    items: [
      testItem('tr-A', title: 'Salt Harbour'),
      testItem('tr-B', title: 'Nightjar'),
    ],
  );
  repo.albums[_album] = const AlbumDetail(
    pid: _album,
    title: 'Long Exposure',
    year: 1975,
    itemCount: 2,
  );
  repo.facetItems['album ${_album.substring(3)}'] = <ItemSummary>[
    testItem('tr-A', title: 'Salt Harbour'),
    testItem('tr-B', title: 'Nightjar'),
  ];
  // The bulk form reads each member to say which values the selection
  // agrees on: artist is common, year is mixed.
  repo.itemFieldsByPid['tr-A'] = {
    'title': 'Salt Harbour',
    'artist': 'The Casket Girls',
    'album': 'Long Exposure',
    'year': '1975',
  };
  repo.itemFieldsByPid['tr-B'] = {
    'title': 'Nightjar',
    'artist': 'The Casket Girls',
    'album': 'Long Exposure',
    'year': '1976',
  };
  return repo;
}

Future<void> _pump(
  WidgetTester tester,
  FakeRepository repo, {
  Size size = const Size(1200, 2000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        audioEngineProvider.overrideWithValue(FakeEngine()),
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      ],
      child: routedHost(const ReleaseWorkbench(pid: _album)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the album pane opens first and a track tap swaps its editor '
      'in', (tester) async {
    final repo = _repo();
    await _pump(tester, repo);

    // The default selection is the release itself.
    expect(_byId(SemanticsIds.albumEditor), findsOneWidget);
    expect(_byId(SemanticsIds.workbenchRow('tr-A')), findsOneWidget);

    await tester.tap(_byId(SemanticsIds.workbenchRow('tr-A')));
    await tester.pumpAndSettle();

    // The item editor for the tapped member, in place of the album form.
    expect(_byId(SemanticsIds.metadataField('title')), findsOneWidget);
    expect(_byId(SemanticsIds.albumEditor), findsNothing);

    await tester.tap(_byId(SemanticsIds.workbenchAlbumRow));
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.albumEditor), findsOneWidget);
  });

  testWidgets('checked tracks open the bulk form; common values seed and '
      'mixed ones say so', (tester) async {
    final repo = _repo();
    await _pump(tester, repo);

    await tester.longPress(_byId(SemanticsIds.workbenchRow('tr-A')));
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.workbenchRow('tr-B')));
    await tester.pumpAndSettle();

    expect(_byId(SemanticsIds.workbenchBulkPane), findsOneWidget);
    // The selection agrees on the artist, so the field opens on it.
    expect(find.text('The Casket Girls'), findsOneWidget);
    // It disagrees on the title and the year, so those fields open
    // empty under the sentinel: an untouched mixed field is never sent.
    expect(find.text('Mixed'), findsNWidgets(2));

    await tester.enterText(
      _byId(SemanticsIds.workbenchBulkField('artist')),
      'The Harbour Lights',
    );
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.workbenchBulkSave));
    await tester.pumpAndSettle();

    final call = repo.bulkEditCalls.single;
    expect(call.itemPids, ['tr-A', 'tr-B']);
    // Only the edited field rides the batch - not the mixed year, not
    // the agreed-but-untouched title or album.
    expect(call.fields, {'artist': 'The Harbour Lights'});
    expect(call.skipLocked, isFalse);
    expect(call.force, isFalse);
  });

  testWidgets('the rewrite section regroups the release and the workbench '
      'follows it', (tester) async {
    final repo = _repo();
    repo.bulkEditRegroupsTo = _regrouped;
    repo.albums[_regrouped] = const AlbumDetail(
      pid: _regrouped,
      title: 'Renamed Harbour',
      itemCount: 2,
    );
    repo.facetItems['album ${_regrouped.substring(3)}'] =
        repo.facetItems['album ${_album.substring(3)}']!;
    await _pump(tester, repo);

    // The rewrite section sits at the bottom of the pane's scroll.
    await tester.ensureVisible(_byId(SemanticsIds.albumRewriteField('album')));
    await tester.pumpAndSettle();
    await tester.enterText(
      _byId(SemanticsIds.albumRewriteField('album')),
      'Renamed Harbour',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(_byId(SemanticsIds.albumRewriteApply));
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.albumRewriteApply));
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.albumRewriteConfirm));
    await tester.pumpAndSettle();

    // Force, because the rewrite itself locks these fields: without it
    // the second rename would refuse on the first one's locks.
    final call = repo.bulkEditCalls.single;
    expect(call.fields, {'album': 'Renamed Harbour'});
    expect(call.force, isTrue);
    expect(call.itemPids, ['tr-A', 'tr-B']);

    // The regroup moved the members onto a fresh pid, and the surface
    // moved with them: the new release's workbench, not a stale one.
    expect(find.text('Renamed Harbour'), findsWidgets);
    expect(find.text('Long Exposure'), findsNothing);
  });

  testWidgets('keys act on the list, and never while a form field has '
      'focus', (tester) async {
    final repo = _repo();
    await _pump(tester, repo);

    // Cursor onto the first track, then space checks it: the selection
    // starts from the keyboard alone.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.workbenchBulkPane), findsOneWidget);

    // Escape leaves the selection.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.workbenchBulkPane), findsNothing);
    expect(_byId(SemanticsIds.albumEditor), findsOneWidget);

    // With a text field focused, the same keys are typing, not
    // commands: nothing may steal a space mid-word.
    await tester.tap(_byId(SemanticsIds.metadataField('sort')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.workbenchBulkPane), findsNothing);
  });

  testWidgets('compact is the list alone, and a track pushes its own '
      'editor', (tester) async {
    final repo = _repo();
    await _pump(tester, repo, size: const Size(500, 900));

    // No pane below the two-pane width: the list is the screen.
    expect(_byId(SemanticsIds.workbenchPane), findsNothing);
    expect(_byId(SemanticsIds.albumEditor), findsNothing);

    await tester.tap(_byId(SemanticsIds.workbenchRow('tr-A')));
    await tester.pumpAndSettle();

    // The member's canonical location, through the real route table.
    expect(_byId(SemanticsIds.metadataEditor), findsOneWidget);
  });

  testWidgets('compact opens the album form as a sheet', (tester) async {
    final repo = _repo();
    await _pump(tester, repo, size: const Size(500, 900));

    await tester.tap(_byId(SemanticsIds.workbenchAlbumRow));
    await tester.pumpAndSettle();

    expect(_byId(SemanticsIds.albumEditor), findsOneWidget);
  });

  testWidgets('compact bulk bar opens the bulk form as a sheet', (
    tester,
  ) async {
    final repo = _repo();
    await _pump(tester, repo, size: const Size(500, 900));

    await tester.longPress(_byId(SemanticsIds.workbenchRow('tr-A')));
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.workbenchBulkBar), findsOneWidget);

    await tester.tap(_byId(SemanticsIds.workbenchBulkEdit));
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.workbenchBulkPane), findsOneWidget);
  });

  testWidgets('a dirty pane asks before a selection change discards it', (
    tester,
  ) async {
    final repo = _repo();
    await _pump(tester, repo);

    await tester.tap(_byId(SemanticsIds.workbenchRow('tr-A')));
    await tester.pumpAndSettle();
    await tester.enterText(
      _byId(SemanticsIds.metadataField('title')),
      'Half-typed rename',
    );
    await tester.pumpAndSettle();

    // Swapping to the album row would re-key the pane and drop the
    // draft, so the workbench asks first; Cancel keeps everything.
    await tester.tap(_byId(SemanticsIds.workbenchAlbumRow));
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.workbenchDiscardConfirm), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Half-typed rename'), findsOneWidget);
    expect(_byId(SemanticsIds.albumEditor), findsNothing);

    // Confirming really discards and swaps.
    await tester.tap(_byId(SemanticsIds.workbenchAlbumRow));
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.workbenchDiscardConfirm));
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.albumEditor), findsOneWidget);

    // A clean pane swaps without asking.
    await tester.tap(_byId(SemanticsIds.workbenchRow('tr-B')));
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.workbenchDiscardConfirm), findsNothing);
    expect(_byId(SemanticsIds.metadataField('title')), findsOneWidget);
  });

  testWidgets('clearing a mixed bulk field stages a wipe; untouched mixed '
      'fields stay out of the batch', (tester) async {
    final repo = _repo();
    await _pump(tester, repo);

    await tester.longPress(_byId(SemanticsIds.workbenchRow('tr-A')));
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.workbenchRow('tr-B')));
    await tester.pumpAndSettle();

    // The year disagrees across the pair, so it opens empty; typing
    // and clearing it back to empty is the one gesture that means
    // "wipe it on every track", and it must survive the value compare.
    await tester.enterText(
      _byId(SemanticsIds.workbenchBulkField('year')),
      '1999',
    );
    await tester.pumpAndSettle();
    await tester.enterText(_byId(SemanticsIds.workbenchBulkField('year')), '');
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.workbenchBulkSave));
    await tester.pumpAndSettle();

    final call = repo.bulkEditCalls.single;
    expect(call.itemPids, ['tr-A', 'tr-B']);
    // The wiped year rides the batch; the equally mixed but untouched
    // title does not.
    expect(call.fields, {'year': ''});
  });

  testWidgets('a member saved in the pane refreshes the list beside it', (
    tester,
  ) async {
    final repo = _repo();
    await _pump(tester, repo);

    await tester.tap(_byId(SemanticsIds.workbenchRow('tr-A')));
    await tester.pumpAndSettle();

    // What the next fetch will say; without the pane's save
    // invalidating the members, nothing ever asks for it.
    repo.facetItems['album ${_album.substring(3)}'] = <ItemSummary>[
      testItem('tr-A', title: 'Fresh Name'),
      testItem('tr-B', title: 'Nightjar'),
    ];
    await tester.enterText(
      _byId(SemanticsIds.metadataField('title')),
      'Fresh Name',
    );
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.metadataSave));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: _byId(SemanticsIds.workbenchList),
        matching: _byId(SemanticsIds.workbenchRow('tr-A')),
      ),
      findsOneWidget,
    );
    expect(find.text('Salt Harbour'), findsNothing);
  });
}
