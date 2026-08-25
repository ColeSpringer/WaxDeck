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
