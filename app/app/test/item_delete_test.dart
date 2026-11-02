import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_es.dart';
import 'package:waxdeck/src/library/item_delete.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'localized_host.dart';

const _admin = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  username: 'admin',
  roles: ['admin'],
);

/// A screen whose one button deletes [pids], or with [filePids] those
/// files of the one item, drawn as every surface offering the verb draws
/// it: only for an account holding the delete right.
Widget _host(
  FakeRepository repo, {
  List<String> pids = const ['tr-1'],
  List<String>? filePids,
  VoidCallback? onDeleted,
}) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
  ],
  child: localizedHost(
    Scaffold(
      body: Center(
        child: Consumer(
          builder: (context, ref, _) {
            if (!canDeleteItems(ref)) return const SizedBox.shrink();
            return TextButton(
              onPressed: () => filePids == null
                  ? confirmDeleteItems(
                      context,
                      pids: pids,
                      onDeleted: onDeleted,
                    )
                  : confirmDeleteItem(
                      context,
                      pid: pids.single,
                      filePids: filePids,
                      onDeleted: onDeleted,
                    ),
              child: const Text('Delete'),
            );
          },
        ),
      ),
    ),
  ),
);

/// Asks for the delete, as a surface's delete row does.
Future<void> _delete(WidgetTester tester) async {
  await tester.tap(find.text('Delete'));
  await tester.pumpAndSettle();
}

/// A cue rip refusal naming every track of the rip.
const _ripRefusal = WaxDeckApiException(
  code: 'invalid-request',
  message: "a cue rip's tracks share one file",
  statusCode: 400,
  params: {'reason': 'cue-rip', 'tracks': 'tr-1,tr-2,tr-3'},
);

void main() {
  testWidgets('previews with a dry run, then deletes with the chosen mode', (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
      items: [testItem('tr-1')],
    );
    repo.deletePlansByPid['tr-1'] = const DeletePlanEntry(
      pid: 'tr-1',
      name: 'Prancing Pony Blues',
      files: 3,
      bytes: 5 * 1024 * 1024,
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await _delete(tester);

    // The preview came from a dry run: nothing deleted yet.
    expect(repo.deleteItemsCalls.single.dryRun, isTrue);
    expect(repo.libraryItems, hasLength(1));
    expect(find.text('This removes 3 files, 5.0 MB.'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is WaxButton && w.kind == WaxButtonKind.destructive,
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.itemDeleteMode('permanent')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.itemDeleteConfirm),
    );
    await tester.pumpAndSettle();

    final applied = repo.deleteItemsCalls.last;
    expect(applied.dryRun, isFalse);
    expect(applied.mode, 'permanent');
    expect(repo.libraryItems, isEmpty);
    expect(shellMessageText(raisedMessage(tester)), 'Deleted 3 files for good');
  });

  testWidgets('the preview names the files and says when the item stays', (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
      items: [testItem('tr-1')],
    );
    repo.deletePlansByPid['tr-1'] = const DeletePlanEntry(
      pid: 'tr-1',
      name: 'Prancing Pony Blues',
      files: 1,
      bytes: 4613734,
      fileList: [
        DeletePlanFile(
          filePid: 'f-1',
          name: '01 - Prancing Pony Blues.m4a',
          sizeBytes: 4613734,
          role: 'primary',
        ),
      ],
      itemSurvives: true,
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await _delete(tester);

    expect(find.text('This removes 1 file, 4.4 MB.'), findsOneWidget);
    expect(find.text('01 - Prancing Pony Blues.m4a'), findsOneWidget);
    expect(
      find.text('The item stays in your library on its remaining files.'),
      findsOneWidget,
    );
  });

  testWidgets('the preview names the files by their place in the library', (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
      items: [testItem('tr-1')],
    );
    repo.deletePlansByPid['tr-1'] = const DeletePlanEntry(
      pid: 'tr-1',
      name: 'Prancing Pony Blues',
      files: 1,
      bytes: 4613734,
      fileList: [
        DeletePlanFile(
          filePid: 'f-1',
          name: '01 - Prancing Pony Blues.m4a',
          sizeBytes: 4613734,
          role: 'primary',
        ),
      ],
      paths: ['Hum Collective/Shell Songs/01 - Prancing Pony Blues.m4a'],
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await _delete(tester);

    expect(
      find.text('Hum Collective/Shell Songs/01 - Prancing Pony Blues.m4a'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        '1 file: Hum Collective/Shell Songs/01 - Prancing Pony Blues.m4a',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.itemDeletePaths),
      findsOneWidget,
    );
  });

  testWidgets('the preview names the sidecars that go with the files', (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
      items: [testItem('tr-1')],
    );
    repo.deletePlansByPid['tr-1'] = const DeletePlanEntry(
      pid: 'tr-1',
      name: 'Prancing Pony Blues',
      files: 1,
      bytes: 4613734,
      paths: ['Hum Collective/Shell Songs/01 - Prancing Pony Blues.m4a'],
      sidecars: [
        'Hum Collective/Shell Songs/01 - Prancing Pony Blues.lrc',
        'Hum Collective/Shell Songs/01 - Prancing Pony Blues.jpg',
      ],
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await _delete(tester);

    expect(find.text('Also removes 2 sidecars:'), findsOneWidget);
    for (final (i, path) in repo.deletePlansByPid['tr-1']!.sidecars.indexed) {
      expect(find.text(path), findsOneWidget);
      expect(find.byKey(ValueKey('$i:$path')), findsOneWidget);
    }
    // Under the files, not among them.
    expect(
      tester.getTopLeft(find.text('Also removes 2 sidecars:')).dy,
      greaterThan(
        tester
            .getTopLeft(
              find.text(
                'Hum Collective/Shell Songs/01 - Prancing Pony Blues.m4a',
              ),
            )
            .dy,
      ),
    );
    expect(
      find.bySemanticsLabel(
        '2 sidecars: '
        'Hum Collective/Shell Songs/01 - Prancing Pony Blues.lrc, '
        'Hum Collective/Shell Songs/01 - Prancing Pony Blues.jpg',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.itemDeleteSidecars),
      findsOneWidget,
    );
  });

  testWidgets('sidecars of several items are one list, capped like files', (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
      items: [testItem('tr-1'), testItem('tr-2')],
    );
    repo.deletePlansByPid['tr-1'] = DeletePlanEntry(
      pid: 'tr-1',
      files: 1,
      bytes: 1024,
      paths: const ['Album/01.flac'],
      sidecars: [for (var i = 1; i <= 4; i++) 'Album/01-$i.jpg'],
    );
    repo.deletePlansByPid['tr-2'] = DeletePlanEntry(
      pid: 'tr-2',
      files: 1,
      bytes: 1024,
      paths: const ['Album/02.flac'],
      sidecars: [for (var i = 1; i <= 3; i++) 'Album/02-$i.jpg'],
    );
    await tester.pumpWidget(_host(repo, pids: const ['tr-1', 'tr-2']));
    await tester.pumpAndSettle();

    await _delete(tester);

    expect(find.text('Also removes 7 sidecars:'), findsOneWidget);
    expect(find.text('Album/01-1.jpg'), findsOneWidget);
    expect(find.text('Album/02-1.jpg'), findsOneWidget);
    expect(find.text('Album/02-2.jpg'), findsNothing);
    // The five sidecars named make no room for a sixth; the count is said
    // once, drawn and spoken.
    expect(find.text('and 2 more files'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        '7 sidecars: Album/01-1.jpg, Album/01-2.jpg, Album/01-3.jpg, '
        'Album/01-4.jpg, Album/02-1.jpg, and 2 more files',
      ),
      findsOneWidget,
    );
  });

  testWidgets('one path in two libraries is two rows, not a clash', (
    tester,
  ) async {
    // An item and its copy in a second library laid out alike send the same
    // relative path twice, for the files and for their sidecars.
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
      items: [testItem('tr-1'), testItem('tr-2')],
    );
    for (final pid in ['tr-1', 'tr-2']) {
      repo.deletePlansByPid[pid] = DeletePlanEntry(
        pid: pid,
        files: 1,
        bytes: 1024,
        paths: const ['Album/01.flac'],
        sidecars: const ['Album/01.lrc'],
      );
    }
    await tester.pumpWidget(_host(repo, pids: const ['tr-1', 'tr-2']));
    await tester.pumpAndSettle();

    await _delete(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Album/01.flac'), findsNWidgets(2));
    expect(find.text('Album/01.lrc'), findsNWidgets(2));
    expect(find.text('Also removes 2 sidecars:'), findsOneWidget);
  });

  testWidgets('a plan with no sidecars says nothing of them', (tester) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
      items: [testItem('tr-1')],
    );
    repo.deletePlansByPid['tr-1'] = const DeletePlanEntry(
      pid: 'tr-1',
      files: 1,
      bytes: 1024,
      paths: ['Album/01.flac'],
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await _delete(tester);

    expect(find.textContaining('sidecar'), findsNothing);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.itemDeleteSidecars),
      findsNothing,
    );
  });

  test('the sidecar line reads in Spanish too', () {
    expect(
      AppLocalizationsEs().libraryDeleteSidecarsHeading(1),
      'También elimina 1 archivo acompañante:',
    );
    expect(
      AppLocalizationsEs().libraryDeleteSidecarsHeading(3),
      'También elimina 3 archivos acompañantes:',
    );
  });

  testWidgets('a refused delete says the folder is unwritable', (tester) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
      items: [testItem('tr-1')],
    );
    repo.deleteItemsRefusal = (pids, dryRun) => dryRun
        ? null
        : const WaxDeckApiException(
            code: 'storage-unwritable',
            message: 'the library folder refused the write: permission denied',
            statusCode: 409,
          );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await _delete(tester);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.itemDeleteConfirm),
    );
    await tester.pumpAndSettle();

    expect(
      shellMessageText(raisedMessage(tester)),
      "The server cannot write to that library's folder, so nothing was "
      "changed. Check the folder's ownership and permissions.",
    );
    expect(repo.libraryItems, hasLength(1));
  });

  testWidgets('a partial delete says how many stayed', (tester) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
      items: [testItem('tr-1')],
    );
    repo.deletePlansByPid['tr-1'] = const DeletePlanEntry(
      pid: 'tr-1',
      name: 'Prancing Pony Blues',
      files: 3,
      bytes: 3 * 1024 * 1024,
    );
    repo.deleteItemsFailed = 1;
    var left = false;
    await tester.pumpWidget(_host(repo, onDeleted: () => left = true));
    await tester.pumpAndSettle();

    await _delete(tester);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.itemDeleteConfirm),
    );
    await tester.pumpAndSettle();

    expect(
      shellMessageText(raisedMessage(tester)),
      'Moved 2 files to the trash\n'
      '1 of 3 files could not be moved to the trash',
    );
    expect(left, isFalse, reason: 'a file stayed, so the item did');
  });

  testWidgets('a partial permanent delete says how many stayed', (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
      items: [testItem('tr-1')],
    );
    repo.deletePlansByPid['tr-1'] = const DeletePlanEntry(
      pid: 'tr-1',
      name: 'Prancing Pony Blues',
      files: 3,
      bytes: 3 * 1024 * 1024,
    );
    repo.deleteItemsFailed = 1;
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await _delete(tester);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.itemDeleteMode('permanent')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.itemDeleteConfirm),
    );
    await tester.pumpAndSettle();

    expect(
      shellMessageText(raisedMessage(tester)),
      'Deleted 2 files for good\n'
      '1 of 3 files could not be deleted',
    );
  });

  testWidgets('an item a file keeps is not left', (tester) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
      items: [testItem('tr-1')],
    );
    repo.deletePlansByPid['tr-1'] = const DeletePlanEntry(
      pid: 'tr-1',
      name: 'Prancing Pony Blues',
      files: 1,
      bytes: 1024,
      itemSurvives: true,
    );
    var left = false;
    await tester.pumpWidget(_host(repo, onDeleted: () => left = true));
    await tester.pumpAndSettle();

    await _delete(tester);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.itemDeleteConfirm),
    );
    await tester.pumpAndSettle();

    expect(left, isFalse);
  });

  testWidgets('the file list reads out no longer than it shows', (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
      items: [testItem('tr-1')],
    );
    repo.deletePlansByPid['tr-1'] = DeletePlanEntry(
      pid: 'tr-1',
      name: 'Long Album',
      files: 8,
      bytes: 8 * 1024,
      paths: [for (var i = 1; i <= 8; i++) 'Album/0$i.flac'],
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await _delete(tester);

    expect(
      find.bySemanticsLabel(
        '8 files: Album/01.flac, Album/02.flac, Album/03.flac, '
        'Album/04.flac, Album/05.flac, and 3 more files',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a track of one shared file offers every track of the file', (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
      items: [testItem('tr-1'), testItem('tr-2'), testItem('tr-3')],
    );
    repo.deleteItemsRefusal = (pids, dryRun) =>
        pids.length == 1 ? _ripRefusal : null;
    var left = false;
    await tester.pumpWidget(_host(repo, onDeleted: () => left = true));
    await tester.pumpAndSettle();

    await _delete(tester);

    expect(find.text('Delete the other tracks too?'), findsOneWidget);
    expect(
      find.text(
        '2 more tracks are cut from the same file as the track you picked, '
        'and tracks cut from one file are deleted together or not at all.',
      ),
      findsOneWidget,
    );
    expect(find.text('Delete all 3 tracks...'), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.itemDeleteRip));
    await tester.pumpAndSettle();

    expect(repo.deleteItemsCalls.last.pids, ['tr-1', 'tr-2', 'tr-3']);
    expect(repo.deleteItemsCalls.last.dryRun, isTrue);
    expect(find.text('This removes 3 files, 3.0 MB.'), findsOneWidget);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.itemDeleteConfirm),
    );
    await tester.pumpAndSettle();

    expect(repo.deleteItemsCalls.last.dryRun, isFalse);
    expect(repo.deleteItemsCalls.last.pids, ['tr-1', 'tr-2', 'tr-3']);
    expect(repo.libraryItems, isEmpty);
    expect(left, isTrue, reason: 'the track asked for went with its file');
  });

  testWidgets('a refusal naming no track beyond those asked for is said '
      'as it stands, with nothing offered', (tester) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
      items: [testItem('tr-1'), testItem('tr-2')],
    );
    // The file's tracks are all asked for already: offering them again
    // would only be refused again.
    repo.deleteItemsRefusal = (pids, dryRun) => const WaxDeckApiException(
      code: 'invalid-request',
      message: "a cue rip's tracks share one file",
      statusCode: 400,
      params: {'reason': 'cue-rip', 'tracks': 'tr-2,tr-1'},
    );
    await tester.pumpWidget(_host(repo, pids: const ['tr-1', 'tr-2']));
    await tester.pumpAndSettle();

    await _delete(tester);

    expect(
      find.bySemanticsIdentifier(SemanticsIds.itemDeleteRip),
      findsNothing,
    );
    expect(find.textContaining('more track'), findsNothing);
    expect(
      shellMessageText(raisedMessage(tester)),
      'This track is part of a larger file that holds other tracks too, so '
      'it can only be deleted together with them.',
    );
    expect(repo.deleteItemsCalls, hasLength(1));
  });

  test('the offer agrees in number with what was picked and what more '
      'goes, in English and Spanish', () {
    final en = AppLocalizationsEn();
    final es = AppLocalizationsEs();
    const rest =
        ', and tracks cut from one file are deleted together or not at all.';
    expect(
      en.libraryDeleteRipShared(1, 1),
      '1 more track is cut from the same file as the track you picked$rest',
    );
    expect(
      en.libraryDeleteRipShared(1, 3),
      '3 more tracks are cut from the same file as the track you picked'
      '$rest',
    );
    expect(
      en.libraryDeleteRipShared(12, 1),
      '1 more track is cut from the same file as tracks you picked$rest',
    );
    expect(
      en.libraryDeleteRipShared(12, 5),
      '5 more tracks are cut from the same file as tracks you picked$rest',
    );
    const resto =
        ', y las pistas que salen de un mismo archivo se eliminan juntas o '
        'ninguna.';
    expect(
      es.libraryDeleteRipShared(1, 1),
      '1 pista más sale del mismo archivo que la pista que elegiste$resto',
    );
    expect(
      es.libraryDeleteRipShared(1, 3),
      '3 pistas más salen del mismo archivo que la pista que elegiste'
      '$resto',
    );
    expect(
      es.libraryDeleteRipShared(12, 1),
      '1 pista más sale del mismo archivo que pistas de las que elegiste'
      '$resto',
    );
    expect(
      es.libraryDeleteRipShared(12, 5),
      '5 pistas más salen del mismo archivo que pistas de las que elegiste'
      '$resto',
    );
  });

  testWidgets('cancelling the offer of the whole file deletes nothing', (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
      items: [testItem('tr-1'), testItem('tr-2'), testItem('tr-3')],
    );
    repo.deleteItemsRefusal = (pids, dryRun) =>
        pids.length == 1 ? _ripRefusal : null;
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await _delete(tester);
    expect(find.bySemanticsIdentifier(SemanticsIds.itemDeleteRip), findsOne);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repo.deleteItemsCalls, hasLength(1));
    expect(repo.deleteItemsCalls.single.dryRun, isTrue);
    expect(repo.libraryItems, hasLength(3));
  });

  testWidgets('a files delete refused for a rip is not widened to its '
      'tracks', (tester) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
      items: [testItem('tr-1'), testItem('tr-2'), testItem('tr-3')],
    );
    repo.deleteItemFilesRefusal = (filePids, dryRun) => _ripRefusal;
    await tester.pumpWidget(_host(repo, filePids: ['fl-1']));
    await tester.pumpAndSettle();

    await _delete(tester);

    expect(
      find.bySemanticsIdentifier(SemanticsIds.itemDeleteRip),
      findsNothing,
    );
    expect(repo.deleteItemsCalls, isEmpty);
    expect(
      shellMessageText(raisedMessage(tester)),
      'This track is part of a larger file that holds other tracks too, so '
      'it can only be deleted together with them.',
    );
  });

  testWidgets('a copy that keeps the item is named after the delete', (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
      items: [testItem('tr-1')],
    );
    repo.deleteItemsWarnings = const [
      "Prancing Pony Blues: pony.flac is now the item's main file",
    ];
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await _delete(tester);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.itemDeleteConfirm),
    );
    await tester.pumpAndSettle();

    expect(
      shellMessageText(raisedMessage(tester)),
      "Moved 1 file to the trash\n"
      "Prancing Pony Blues: pony.flac is now the item's main file",
    );
  });

  testWidgets('cancelling the dialog deletes nothing', (tester) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
      items: [testItem('tr-1')],
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await _delete(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repo.deleteItemsCalls, hasLength(1));
    expect(repo.deleteItemsCalls.single.dryRun, isTrue);
    expect(repo.libraryItems, hasLength(1));
  });

  testWidgets('on a short window the dialog scrolls to every choice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
      items: [testItem('tr-1')],
    );
    repo.deletePlansByPid['tr-1'] = DeletePlanEntry(
      pid: 'tr-1',
      name: 'Long Album',
      files: 8,
      bytes: 8 * 1024,
      paths: [for (var i = 1; i <= 8; i++) 'Album/0$i.flac'],
      itemSurvives: true,
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await _delete(tester);
    final permanent = find.bySemanticsIdentifier(
      SemanticsIds.itemDeleteMode('permanent'),
    );
    await tester.ensureVisible(permanent);
    await tester.pumpAndSettle();
    await tester.tap(permanent);
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.itemDeleteConfirm),
    );
    await tester.pumpAndSettle();

    expect(repo.deleteItemsCalls.last.dryRun, isFalse);
    expect(repo.deleteItemsCalls.last.mode, 'permanent');
  });

  testWidgets('on a short window the whole-file offer scrolls to its '
      'choices', (tester) async {
    tester.view.physicalSize = const Size(320, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
      items: [testItem('tr-1'), testItem('tr-2'), testItem('tr-3')],
    );
    repo.deleteItemsRefusal = (pids, dryRun) =>
        pids.length == 1 ? _ripRefusal : null;
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await _delete(tester);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.itemDeleteRip));
    await tester.pumpAndSettle();

    expect(repo.deleteItemsCalls.last.pids, ['tr-1', 'tr-2', 'tr-3']);
  });

  testWidgets('a delete-right holder is never offered Permanent', (
    tester,
  ) async {
    // The permanent mode stays admin-only on the server whatever the
    // delete right says, so offering its radio here would be a 403
    // dressed as a choice.
    final repo = FakeRepository(
      sessionState: const SessionState(
        authenticated: true,
        user: WaxDeckUser(
          id: 'us-3',
          username: 'kim',
          roles: ['user'],
          canDelete: true,
        ),
      ),
      items: [testItem('tr-1')],
    );
    repo.deletePlansByPid['tr-1'] = const DeletePlanEntry(
      pid: 'tr-1',
      name: 'Prancing Pony Blues',
      files: 1,
      bytes: 1024,
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await _delete(tester);

    expect(
      find.bySemanticsIdentifier(SemanticsIds.itemDeleteMode('trash')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.itemDeleteMode('permanent')),
      findsNothing,
      reason: 'permanent deletion is admin-only on the server',
    );
  });
}
