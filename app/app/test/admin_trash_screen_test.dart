import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/trash_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';
import 'localized_host.dart';

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
      child: localizedHost(const TrashScreen()),
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
      shellMessageText(container.read(shellMessengerProvider)),
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
      shellMessageText(container.read(shellMessengerProvider)),
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
      shellMessageText(container.read(shellMessengerProvider)),
      'Purged 2 files, reclaimed 4.0 MB',
    );
  });

  testWidgets('the artwork cache card reports the census and clears it', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.thumbnailCache = ThumbnailCacheReport(
      rows: 12,
      bytes: 3 * 1024 * 1024,
      sources: 4,
      artSources: 6,
      artSourceBytes: 30 * 1024 * 1024,
      oldestAt: DateTime.utc(2026, 7, 1),
      newestAt: DateTime.utc(2026, 8, 1),
      rungs: const <ThumbnailRung>[
        ThumbnailRung(size: 1024, rows: 4, bytes: 2 * 1024 * 1024),
        ThumbnailRung(size: 256, rows: 8, bytes: 1024 * 1024),
      ],
    );
    final container = _container(repo);
    await tester.pumpWidget(_host(repo, container));
    await tester.pumpAndSettle();

    expect(find.text('3.0 MB in 12 copies'), findsOneWidget);
    expect(find.text('From 4 of 6 covers, which hold 30.0 MB'), findsOneWidget);
    // The ladder is reported largest first, and the rung is what a row
    // is keyed by - so a breakdown naming the box is the point of it.
    expect(find.text('1024 px: 4'), findsOneWidget);
    expect(find.text('256 px: 8'), findsOneWidget);

    final clear = find.bySemanticsIdentifier(SemanticsIds.thumbsClear);
    await tester.ensureVisible(clear);
    await tester.pumpAndSettle();
    await tester.tap(clear);
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.thumbsClearConfirm),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    // A budget of zero, not an absent bound: the server refuses a
    // policy with neither axis set, so "clear everything" has to be
    // spelled as a real zero.
    expect(repo.thumbnailPrunes, [(null, 0)]);
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'Cleared 12 copies, freeing 3.0 MB',
    );
    // And the card re-reads: an emptied cache has no clear button left
    // to press.
    expect(find.text('Nothing generated yet'), findsOneWidget);
    expect(find.bySemanticsIdentifier(SemanticsIds.thumbsClear), findsNothing);
  });
}
