import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/metadata/metadata_screen.dart';
import 'package:waxdeck/src/providers.dart';

import 'fakes.dart';

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: const MaterialApp(home: MetadataScreen(pid: 'tr-1')),
);

FakeRepository _repo() {
  final repo = FakeRepository(items: [testItem('tr-1', title: 'Old Title')]);
  repo.itemFieldsByPid['tr-1'] = {
    'title': 'Old Title',
    'artist': 'The Bree Trio',
    'album': 'Prancing Pony Blues',
    'year': '2011',
  };
  return repo;
}

void main() {
  testWidgets('the artwork card distinguishes own from inherited cover', (
    tester,
  ) async {
    // No cover.
    await tester.pumpWidget(_host(_repo()));
    await tester.pumpAndSettle();
    expect(find.text('No cover'), findsOneWidget);

    // Inherited cover (resolves art, but not its own).
    final inherited = _repo()..artworkPids.add('tr-1');
    await tester.pumpWidget(_host(inherited));
    await tester.pumpAndSettle();
    expect(
      find.text('Inherits a cover from its album or artist'),
      findsOneWidget,
    );

    // Its own cover.
    final own = _repo()..ownArtworkPids.add('tr-1');
    await tester.pumpWidget(_host(own));
    await tester.pumpAndSettle();
    expect(find.text('Has its own cover'), findsOneWidget);
  });

  testWidgets('builds the field form from the kind vocabulary', (tester) async {
    await tester.pumpWidget(_host(_repo()));
    await tester.pumpAndSettle();

    // The fake vocabulary defines exactly these music fields.
    for (final field in ['title', 'artist', 'album', 'year']) {
      expect(find.byKey(Key('field-$field')), findsOneWidget);
      expect(find.byKey(Key('field-lock-$field')), findsOneWidget);
    }
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('field-title')))
          .controller
          ?.text,
      'Old Title',
    );
  });

  testWidgets('save sends only the dirty fields', (tester) async {
    final repo = _repo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('field-title')),
      'Neon Meridian',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('metadata-save')));
    await tester.tap(find.byKey(const Key('metadata-save')));
    await tester.pumpAndSettle();

    expect(repo.editItemMetadataCalls, hasLength(1));
    expect(repo.editItemMetadataCalls.single.fields, {
      'title': 'Neon Meridian',
    });
    expect(repo.editItemMetadataCalls.single.writeBack, isFalse);
  });

  testWidgets('the lock toggle calls setItemLocks', (tester) async {
    final repo = _repo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('field-lock-album')));
    await tester.tap(find.byKey(const Key('field-lock-album')));
    await tester.pumpAndSettle();

    expect(repo.setItemLocksCalls, hasLength(1));
    expect(repo.setItemLocksCalls.single.fields, ['album']);
    expect(repo.setItemLocksCalls.single.locked, isTrue);
    expect(repo.lockedFieldsByPid['tr-1'], contains('album'));
  });

  testWidgets('the unofficial switch calls setReleaseStatus', (tester) async {
    final repo = _repo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('unofficial-switch')));
    await tester.tap(find.byKey(const Key('unofficial-switch')));
    await tester.pumpAndSettle();

    expect(repo.setReleaseStatusCalls, hasLength(1));
    expect(repo.setReleaseStatusCalls.single.unofficial, isTrue);
    expect(repo.unofficialPids, contains('tr-1'));
  });

  testWidgets('a locked-field rejection hints at force', (tester) async {
    final repo = _repo();
    repo.lockedFieldsByPid['tr-1'] = {'title'};
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('field-title')),
      'Neon Meridian',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('metadata-save')));
    await tester.tap(find.byKey(const Key('metadata-save')));
    await tester.pumpAndSettle();

    expect(
      find.text('field locked. Check "Force" to overwrite locked fields.'),
      findsOneWidget,
    );
  });

  testWidgets('rematch reports the queued review entry', (tester) async {
    final repo = _repo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('metadata-rematch')));
    await tester.tap(find.byKey(const Key('metadata-rematch')));
    await tester.pumpAndSettle();

    expect(repo.rematchCalls, ['tr-1']);
    expect(find.textContaining('Queued for identification'), findsOneWidget);
  });
}
