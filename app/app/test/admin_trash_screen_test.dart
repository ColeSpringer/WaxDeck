import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/trash_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

ProviderContainer _container(FakeRepository repo) {
  final container = ProviderContainer(
    overrides: [repositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _host(FakeRepository repo, [ProviderContainer? container]) =>
    UncontrolledProviderScope(
      container: container ?? _container(repo),
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

    expect(find.bySemanticsIdentifier('trash-row-ts-1'), findsOneWidget);
    expect(find.text('2.0 MB'), findsWidgets);
    expect(find.text('delete'), findsWidgets);
    expect(find.bySemanticsIdentifier('trash-row-ts-2'), findsNothing);

    await tester.tap(
      find.bySemanticsIdentifier('trash-include-restored'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsIdentifier('trash-row-ts-2'), findsOneWidget);
    expect(find.text('restored'), findsOneWidget);
  });

  testWidgets('restoring an entry drops it from the default view', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.trashEntries.add(_entry('ts-1'));
    final container = _container(repo);
    await tester.pumpWidget(_host(repo, container));
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsIdentifier('trash-restore-ts-1'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(repo.restoreTrashCalls, ['ts-1']);
    expect(find.bySemanticsIdentifier('trash-row-ts-1'), findsNothing);
    expect(
      container.read(shellMessengerProvider)?.text,
      startsWith('Restored Music/'),
    );
  });

  testWidgets('purging one entry confirms and drops it from the view', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.trashEntries.addAll([_entry('ts-1'), _entry('ts-2')]);
    final container = _container(repo);
    await tester.pumpWidget(_host(repo, container));
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsIdentifier('trash-purge-ts-1'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier('trash-purge-confirm'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(repo.purgeTrashCalls, ['ts-1']);
    expect(find.bySemanticsIdentifier('trash-row-ts-1'), findsNothing);
    expect(find.bySemanticsIdentifier('trash-row-ts-2'), findsOneWidget);
    expect(
      container.read(shellMessengerProvider)?.text,
      contains('reclaimed 2.0 MB'),
    );
  });

  testWidgets('emptying the trash confirms and reports reclaimed bytes', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.trashEntries.addAll([_entry('ts-1'), _entry('ts-2')]);
    final container = _container(repo);
    await tester.pumpWidget(_host(repo, container));
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsIdentifier('trash-empty'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    // Emptying takes the typed word now: the confirm stays disabled
    // until it matches, so a muscle-memory double tap is not a purge.
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.confirmAccept),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(repo.emptyTrashCalls, 0);
    expect(repo.trashEntries, isNotEmpty);

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.confirmField),
      'EMPTY',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.confirmAccept),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(repo.emptyTrashCalls, 1);
    expect(repo.trashEntries, isEmpty);
    expect(
      container.read(shellMessengerProvider)?.text,
      'Purged 2 files, reclaimed 4.0 MB',
    );
  });
}
