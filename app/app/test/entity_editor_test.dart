import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/metadata/entity_editor_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

// The artist and release-group editors: curation-seeded fields, sparse
// saves through the entity endpoint, the write-back switch only where a
// value has files to reach, and the administrators-only refusal.

const _artist = 'ar-01HZX5N8QW3F4V9T2B7KD3M9R6';
const _group = 'rg-01HZX5N8QW3F4V9T2B7KD3M9R6';

FakeRepository _repo({bool admin = true}) => FakeRepository(
  sessionState: SessionState(
    authenticated: true,
    user: WaxDeckUser(
      id: 'us-1',
      username: admin ? 'admin' : 'listener',
      roles: <String>[admin ? 'admin' : 'member'],
    ),
  ),
  items: [testItem('tr-1')],
);

Future<void> _pump(
  WidgetTester tester,
  FakeRepository repo, {
  required EditableEntity entity,
  required String pid,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      ],
      child: routedHost(EntityEditorScreen(entity: entity, pid: pid)),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _field(String name) =>
    find.bySemanticsIdentifier(SemanticsIds.metadataField(name));

Future<void> _save(WidgetTester tester) async {
  final save = find.bySemanticsIdentifier(SemanticsIds.metadataSave);
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  await tester.tap(save);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the artist editor seeds from curation and saves sparsely', (
    tester,
  ) async {
    final repo = _repo();
    repo.entityCurationByKey['artist/$_artist'] = const [
      EntityCuratedField(
        field: 'sort',
        value: 'Bree Trio, The',
        source: 'user',
        locked: true,
      ),
    ];
    await _pump(tester, repo, entity: EditableEntity.artist, pid: _artist);

    // The curated override is what the input holds; the uncurated
    // field is honestly empty.
    expect(find.text('Bree Trio, The'), findsOneWidget);
    await tester.enterText(
      _field('mbid'),
      'b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d',
    );
    await tester.pump();
    await _save(tester);

    // Only the field that changed rides the write.
    final edit = repo.entityEdits.single;
    expect(edit.entityType, 'artist');
    expect(edit.entityPid, _artist);
    expect(edit.edits, {'mbid': 'b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d'});
    expect(edit.writeBack, isFalse);
  });

  testWidgets('an artist sort can fan out to the crediting files', (
    tester,
  ) async {
    final repo = _repo();
    await _pump(tester, repo, entity: EditableEntity.artist, pid: _artist);

    final writeBack = find.bySemanticsIdentifier(
      SemanticsIds.metadataWriteback,
    );
    await tester.ensureVisible(writeBack);
    await tester.pumpAndSettle();
    await tester.tap(writeBack);
    await tester.pump();
    await tester.enterText(_field('sort'), 'Bree Trio, The');
    await tester.pump();
    await _save(tester);

    expect(repo.entityEdits.single.writeBack, isTrue);
  });

  testWidgets('the artist editor manages the entity artwork', (tester) async {
    final repo = _repo();
    await _pump(tester, repo, entity: EditableEntity.artist, pid: _artist);

    // The slot grid and the entity pin, exactly as the album pane
    // mounts them.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.artSlot('front')),
      findsOneWidget,
    );
    expect(find.bySemanticsIdentifier(SemanticsIds.artLock), findsOneWidget);
  });

  testWidgets('the release-group editor writes its closed type choice', (
    tester,
  ) async {
    final repo = _repo();
    await _pump(tester, repo, entity: EditableEntity.releaseGroup, pid: _group);

    // No artwork manager: a release group draws its releases' art.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.artSlot('front')),
      findsNothing,
    );
    // No write-back switch: every release-group field is database-only.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.metadataWriteback),
      findsNothing,
    );

    final choice = _field('type');
    await tester.ensureVisible(choice);
    await tester.pumpAndSettle();
    await tester.tap(choice);
    await tester.pumpAndSettle();
    await tester.tap(find.text('EP').last);
    await tester.pumpAndSettle();
    await _save(tester);

    final edit = repo.entityEdits.single;
    expect(edit.entityType, 'release-group');
    expect(edit.edits, {'type': 'ep'});
  });

  testWidgets('clearing an mbid that merges takes the screen to the '
      'survivor', (tester) async {
    const survivor = 'ar-01HZX5N8QW3F4V9T2B7KD3M9SUR';
    final repo = _repo();
    repo.entityEditMergesInto = survivor;
    repo.entityCurationByKey['artist/$_artist'] = const [
      EntityCuratedField(
        field: 'mbid',
        value: 'b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d',
        source: 'user',
        locked: false,
      ),
    ];
    await _pump(tester, repo, entity: EditableEntity.artist, pid: _artist);

    await tester.enterText(_field('mbid'), '');
    await tester.pump();
    await _save(tester);

    // The edited row is gone, so the editor moved onto the one that
    // absorbed it rather than sitting on a dead pid.
    expect(repo.entityEdits.single.edits, {'mbid': ''});
    expect(find.text(survivor), findsNothing);
    expect(
      tester.widget<EntityEditorScreen>(find.byType(EntityEditorScreen)).pid,
      survivor,
    );
  });

  testWidgets('the artist rename moves every crediting track', (tester) async {
    final repo = _repo();
    repo.facetItems['artist ${_artist.substring(3)}'] = <ItemSummary>[
      testItem('tr-1'),
    ];
    await _pump(tester, repo, entity: EditableEntity.artist, pid: _artist);

    // The box starts empty rather than seeded from the member's display
    // credit: that string is the whole ARTIST tag, which on a
    // collaboration names people this entity is not, and the rename
    // applies with force. The new name is stated in full.
    final field = find.bySemanticsIdentifier(
      SemanticsIds.entityRenameField('name'),
    );
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .controller
          .text,
      isEmpty,
      reason: 'a joined credit must not become the rename baseline',
    );
    await tester.enterText(field, 'The Bree Quartet');
    await tester.pumpAndSettle();

    final apply = find.bySemanticsIdentifier(SemanticsIds.entityRenameApply);
    await tester.ensureVisible(apply);
    await tester.pumpAndSettle();
    await tester.tap(apply);
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.entityRenameConfirm),
    );
    await tester.pumpAndSettle();

    // Force, because the rename locks what it writes: a second one
    // would otherwise refuse on the first one's locks.
    final call = repo.renameEntityCalls.single;
    expect(call.entityType, 'artist');
    expect(call.entityPid, _artist);
    expect(call.fields, {'name': 'The Bree Quartet'});
    expect(call.force, isTrue);
    // The entity edit endpoint is untouched: the two forms write
    // through different verbs.
    expect(repo.entityEdits, isEmpty);
  });

  testWidgets('the release-group rename takes both keying fields', (
    tester,
  ) async {
    final repo = _repo();
    repo.facetItems['release-group ${_group.substring(3)}'] = <ItemSummary>[
      testItem('tr-1'),
    ];
    repo.itemFieldsByPid['tr-1'] = {
      'album': 'Long Exposure',
      'album_artist': 'The Bree Trio',
    };
    await _pump(tester, repo, entity: EditableEntity.releaseGroup, pid: _group);

    final album = find.bySemanticsIdentifier(
      SemanticsIds.entityRenameField('album'),
    );
    await tester.ensureVisible(album);
    await tester.pumpAndSettle();
    await tester.enterText(album, 'Short Exposure');
    await tester.pumpAndSettle();

    final apply = find.bySemanticsIdentifier(SemanticsIds.entityRenameApply);
    await tester.ensureVisible(apply);
    await tester.pumpAndSettle();
    await tester.tap(apply);
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.entityRenameConfirm),
    );
    await tester.pumpAndSettle();

    // Only what changed: album_artist was left alone, so it stays out
    // of the write.
    expect(repo.renameEntityCalls.single.fields, {'album': 'Short Exposure'});
  });

  testWidgets('a member gets the refusal, not a form', (tester) async {
    final repo = _repo(admin: false);
    await _pump(tester, repo, entity: EditableEntity.artist, pid: _artist);

    expect(
      find.bySemanticsIdentifier(SemanticsIds.metadataForbidden),
      findsOneWidget,
    );
    expect(find.bySemanticsIdentifier(SemanticsIds.entityEditor), findsNothing);
  });
}
