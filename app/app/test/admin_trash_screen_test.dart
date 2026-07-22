import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/trash_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: const MaterialApp(home: TrashScreen()),
);

TrashEntry _entry(String id, {DateTime? restoredAt}) => TrashEntry(
  id: id,
  itemPid: 'tr-1',
  name: 'Music/Bree Trio/pony.flac',
  reason: 'delete',
  sizeBytes: 2 * 1024 * 1024,
  trashedAt: DateTime.utc(2026, 7, 10),
  restoredAt: restoredAt,
);

void main() {
  testWidgets('lists entries and hides restored ones by default', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.trashEntries.addAll([
      _entry('ts-1'),
      _entry('ts-2', restoredAt: DateTime.utc(2026, 7, 11)),
    ]);
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('trash-row-ts-1')), findsOneWidget);
    expect(find.textContaining('2.0 MB, delete,'), findsWidgets);
    expect(find.byKey(const ValueKey('trash-row-ts-2')), findsNothing);

    await tester.tap(find.byKey(const Key('trash-include-restored')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('trash-row-ts-2')), findsOneWidget);
    expect(find.text('restored'), findsOneWidget);
  });

  testWidgets('restoring an entry drops it from the default view', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.trashEntries.add(_entry('ts-1'));
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('trash-restore-ts-1')));
    await tester.pumpAndSettle();

    expect(repo.restoreTrashCalls, ['ts-1']);
    expect(find.byKey(const ValueKey('trash-row-ts-1')), findsNothing);
    expect(find.textContaining('Restored Music/'), findsOneWidget);
  });

  testWidgets('emptying the trash confirms and reports reclaimed bytes', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.trashEntries.addAll([_entry('ts-1'), _entry('ts-2')]);
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('trash-empty')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trash-empty-confirm')));
    await tester.pumpAndSettle();

    expect(repo.emptyTrashCalls, 1);
    expect(repo.trashEntries, isEmpty);
    expect(find.text('Purged 2 files, reclaimed 4.0 MB'), findsOneWidget);
  });
}
