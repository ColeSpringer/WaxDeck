import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/metadata/release_workbench.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';
import 'row_finders.dart';

const _album = 'al-01JZX5N8QW3F4V9T2B7KDALBUM';
const _regrouped = 'al-01JZX5N8QW3F4V9T2B7KDNEWER';

Finder _byId(String id) => find.bySemanticsIdentifier(id);

Finder _trackRow(String pid) =>
    rowWithIdentifier(SemanticsIds.workbenchRow(pid));

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
  await tester.pumpWidget(_bench(repo));
  await tester.pumpAndSettle();
}

Widget _bench(FakeRepository repo) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    audioEngineProvider.overrideWithValue(FakeEngine()),
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
  ],
  child: routedHost(const ReleaseWorkbench(pid: _album)),
);

void main() {
  for (final height in <double>[390, 300]) {
    for (final width in <double>[1200, 420]) {
      testWidgets('lays out without overflow at ${width}x$height', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_bench(_repo()));
        expect(tester.takeException(), isNull, reason: 'first frame');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'settled');
      });
    }
  }

  testWidgets('waits for the session before it refuses anyone', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _repo()..getSessionGate = Completer<void>();
    await tester.pumpWidget(_bench(repo));
    await tester.pump();

    expect(find.text('Only administrators can edit a release'), findsNothing);
    expect(find.byType(SkeletonShapes), findsOneWidget);

    repo.getSessionGate!.complete();
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.metadataWorkbench), findsOneWidget);
  });

  testWidgets(
    'the member list on its way is a ghost that fits a short window',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 440);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = _repo()..listItemsGate = Completer<void>();
      await tester.pumpWidget(_bench(repo));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SkeletonShapes), findsWidgets);
      expect(tester.takeException(), isNull);
      repo.listItemsGate!.complete();
      repo.listItemsGate = null;
      await tester.pumpAndSettle();
    },
  );

  testWidgets('the next page of members is one ghost row, not a spinner', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _repo();
    repo.facetItems['album ${_album.substring(3)}'] = <ItemSummary>[
      for (var i = 0; i <= kQueueCap; i++) testItem('tr-$i', title: 'Track $i'),
    ];
    await tester.pumpWidget(_bench(repo));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ReleaseWorkbench)),
    );
    repo.listItemsGate = Completer<void>();
    final loading = container
        .read(
          musicItemsProvider((
            dimension: MusicDimension.albums,
            segment: _album,
          )).notifier,
        )
        .loadMore();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final list = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    list.position.jumpTo(list.position.maxScrollExtent);
    await tester.pump();
    list.position.jumpTo(list.position.maxScrollExtent);
    await tester.pump();

    expect(find.byType(SkeletonShapes), findsOneWidget);
    expect(find.byType(WaxSpinner), findsNothing);
    expect(tester.takeException(), isNull);
    repo.listItemsGate!.complete();
    repo.listItemsGate = null;
    await loading;
    await tester.pumpAndSettle();
  });

  testWidgets('the album pane opens first and a track tap swaps its editor '
      'in', (tester) async {
    final repo = _repo();
    await _pump(tester, repo);

    // The default selection is the release itself.
    expect(_byId(SemanticsIds.albumEditor), findsOneWidget);
    expect(_byId(SemanticsIds.workbenchRow('tr-A')), findsOneWidget);

    await tester.tap(_trackRow('tr-A'));
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

    await tester.longPress(_trackRow('tr-A'));
    await tester.pumpAndSettle();
    await tester.tap(_trackRow('tr-B'));
    await tester.pumpAndSettle();

    expect(_byId(SemanticsIds.workbenchBulkPane), findsOneWidget);
    // The selection agrees on the artist, so the field opens on it.
    expect(find.text('The Casket Girls'), findsOneWidget);
    // It disagrees on the title and the year, so those fields open
    // empty under the sentinel: an untouched mixed field is never sent.
    expect(find.text('Mixed'), findsNWidgets(2));
    // Artist and album are common values read from the files; the fields
    // neither track holds draw no chip.
    expect(find.text('tags'), findsNWidgets(2));
    expect(find.byType(CodecChip), findsNWidgets(4));

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

    // The toggle is the pointer's way out of selection, and it lives in
    // the list header rather than in a virtualised row, so a scroll
    // down a long release can never dispose it.
    expect(_byId(SemanticsIds.workbenchSelectToggle), findsOneWidget);
    await tester.tap(_byId(SemanticsIds.workbenchSelectToggle));
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.workbenchBulkPane), findsNothing);
  });

  testWidgets('a shared value credits whoever set it on every track, and '
      'sources that differ credit no one', (tester) async {
    final repo = _repo();
    // Both tracks' artist was set by hand, and their album read from the
    // files. Their album artist agrees, but one track's was set by hand.
    repo.itemProvenance['tr-A'] = const [
      FieldProvenance(field: 'artist', source: 'user', locked: true),
      FieldProvenance(field: 'album_artist', source: 'user', locked: true),
    ];
    repo.itemProvenance['tr-B'] = const [
      FieldProvenance(field: 'artist', source: 'user', locked: true),
    ];
    repo.itemFieldsByPid['tr-A']!['album_artist'] = 'The Casket Girls';
    repo.itemFieldsByPid['tr-B']!['album_artist'] = 'The Casket Girls';
    await _pump(tester, repo);

    await tester.longPress(_trackRow('tr-A'));
    await tester.pumpAndSettle();
    await tester.tap(_trackRow('tr-B'));
    await tester.pumpAndSettle();

    /// The chip drawn level with [field]'s box, if any.
    String? chipBeside(String field) {
      final box = tester.getRect(_byId(SemanticsIds.workbenchBulkField(field)));
      for (final chip in find.byType(CodecChip).evaluate()) {
        final at = tester.getCenter(find.byWidget(chip.widget));
        if (at.dy >= box.top && at.dy <= box.bottom) {
          return (chip.widget as CodecChip).label;
        }
      }
      return null;
    }

    expect(chipBeside('artist'), 'you');
    expect(chipBeside('album'), 'tags');
    expect(chipBeside('album_artist'), isNull);
    expect(chipBeside('title'), 'Mixed');
  });

  // The rewrite goes through the entity rename, not a bulk edit over a
  // drained member list: the server enumerates the members, so a page
  // that scrolled only part of the way cannot split the release.
  Future<void> rewriteAlbum(WidgetTester tester, String title) async {
    await tester.ensureVisible(_byId(SemanticsIds.albumRewriteField('album')));
    await tester.pumpAndSettle();
    await tester.enterText(
      _byId(SemanticsIds.albumRewriteField('album')),
      title,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(_byId(SemanticsIds.albumRewriteApply));
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.albumRewriteApply));
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.albumRewriteConfirm));
    await tester.pumpAndSettle();
  }

  testWidgets('the rewrite section renames the release in place', (
    tester,
  ) async {
    final repo = _repo();
    await _pump(tester, repo);
    await rewriteAlbum(tester, 'Renamed Harbour');

    // Force, because the rewrite itself locks these fields: without it
    // the second rename would refuse on the first one's locks.
    final call = repo.renameEntityCalls.single;
    expect(call.entityType, 'album');
    expect(call.entityPid, _album);
    expect(call.fields, {'album': 'Renamed Harbour'});
    expect(call.force, isTrue);
    expect(repo.bulkEditCalls, isEmpty);

    // The release kept its pid, so the workbench stays where it is and
    // shows the new title.
    expect(find.text('Renamed Harbour'), findsWidgets);
    expect(find.text('Long Exposure'), findsNothing);
  });

  // An album's year follows its tracks rather than keying the release,
  // and the server refuses one in a rename, so the section offers the
  // two fields that key it and nothing it would only refuse.
  testWidgets('the rewrite section offers the keying fields alone', (
    tester,
  ) async {
    await _pump(tester, _repo());
    await tester.ensureVisible(_byId(SemanticsIds.albumRewriteField('album')));
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.albumRewriteField('album')), findsOneWidget);
    expect(
      _byId(SemanticsIds.albumRewriteField('album_artist')),
      findsOneWidget,
    );
    expect(_byId(SemanticsIds.albumRewriteField('year')), findsNothing);
    expect(find.text('Album and album artist'), findsOneWidget);
  });

  testWidgets('a rewrite onto a taken name merges, and the workbench '
      'follows the survivor', (tester) async {
    final repo = _repo();
    repo.renameEntityResult = const EntityRenameResult(
      entityPid: _album,
      outcome: EntityRenameOutcome.merged,
      members: 2,
      credits: 0,
      mergedInto: _regrouped,
    );
    repo.albums[_regrouped] = const AlbumDetail(
      pid: _regrouped,
      title: 'Renamed Harbour',
      itemCount: 2,
    );
    repo.facetItems['album ${_regrouped.substring(3)}'] =
        repo.facetItems['album ${_album.substring(3)}']!;
    await _pump(tester, repo);
    await rewriteAlbum(tester, 'Renamed Harbour');

    // The named release is gone, so the surface moved to the one that
    // absorbed it rather than sitting on a dead pid.
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

    await tester.tap(_trackRow('tr-A'));
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

    await tester.longPress(_trackRow('tr-A'));
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

    await tester.tap(_trackRow('tr-A'));
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
    await tester.tap(_trackRow('tr-B'));
    await tester.pumpAndSettle();
    expect(_byId(SemanticsIds.workbenchDiscardConfirm), findsNothing);
    expect(_byId(SemanticsIds.metadataField('title')), findsOneWidget);
  });

  testWidgets('clearing a mixed bulk field stages a wipe; untouched mixed '
      'fields stay out of the batch', (tester) async {
    final repo = _repo();
    await _pump(tester, repo);

    await tester.longPress(_trackRow('tr-A'));
    await tester.pumpAndSettle();
    await tester.tap(_trackRow('tr-B'));
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

    await tester.tap(_trackRow('tr-A'));
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
