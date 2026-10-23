import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/admin_providers.dart';
import 'package:waxdeck/src/admin/libraries_screen.dart';
import 'package:waxdeck/src/organize/organize_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'localized_host.dart';

ProviderContainer _container(FakeRepository repo) {
  final container = ProviderContainer(
    overrides: [repositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _host(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: localizedHost(const LibrariesScreen()),
);

/// Wide enough for the table to be a table rather than a card list, which
/// the table test below holds it to.
Future<void> _pump(WidgetTester tester, Widget host) async {
  tester.view.physicalSize = const Size(1300, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(host);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists each root with its path, count, and controls', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.libraries.add(
      const LibraryInfo(
        pid: 'lb-1',
        name: 'music',
        media: 'music',
        path: '/srv/media/music',
        itemCount: 4210,
      ),
    );
    final container = _container(repo);
    await _pump(tester, _host(container));

    expect(find.text('music'), findsWidgets);
    // findsWidgets: the add form's own path field hints with an example
    // path, and the row below carries the real one.
    expect(find.text('/srv/media/music'), findsWidgets);
    expect(find.text('4210'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.libraryRow('lb-1')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.libraryMatching('lb-1')),
      findsOneWidget,
    );
    // This is the screen that shows the number, so it is the one that
    // asks for it. Counting is a scan per root, and the permission
    // editor and the matching menu read the same endpoint without it.
    expect(repo.listLibrariesCalls, contains(true));
  });

  testWidgets('adding a library creates it and refreshes the list', (
    tester,
  ) async {
    final repo = FakeRepository();
    final container = _container(repo);
    await _pump(tester, _host(container));

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.libraryName),
      'audiobooks',
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.libraryPath),
      '/srv/media/audiobooks',
    );
    await tester.ensureVisible(
      find.bySemanticsIdentifier(SemanticsIds.librarySubmit),
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.librarySubmit),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(repo.libraries.map((l) => l.name), contains('audiobooks'));
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      contains('Library "audiobooks" created'),
    );
    // The list picked the new root up.
    expect(find.text('/srv/media/audiobooks'), findsWidgets);
  });

  testWidgets('a library made managed is one Organize counts at once', (
    tester,
  ) async {
    final repo = FakeRepository()..organizeManagedLibraries = 0;
    final container = _container(repo);
    container.listen(organizeProfilesProvider, (_, _) {});
    expect(
      (await container.read(organizeProfilesProvider.future)).managedLibraries,
      0,
    );
    await _pump(tester, _host(container));

    repo.organizeManagedLibraries = 1;
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.libraryName),
      'sorted',
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.libraryPath),
      '/srv/media/sorted',
    );
    await tester.ensureVisible(
      find.bySemanticsIdentifier(SemanticsIds.librarySubmit),
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.librarySubmit),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(
      (await container.read(organizeProfilesProvider.future)).managedLibraries,
      1,
    );
  });

  testWidgets('a blank name or path is refused before any call', (
    tester,
  ) async {
    final repo = FakeRepository();
    final container = _container(repo);
    await _pump(tester, _host(container));

    await tester.ensureVisible(
      find.bySemanticsIdentifier(SemanticsIds.librarySubmit),
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.librarySubmit),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(repo.libraries, isEmpty);
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      contains('name and an absolute path are required'),
    );
  });

  // The library exists but streaming from it does not, and the create is
  // the only place that knows. A toast would carry it for four seconds;
  // this is a sentence about something now permanently half-working.
  testWidgets('a degraded create keeps its streaming warning on screen', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..createLibraryWarning =
          'streaming from this library is not available yet: sidecar refused';
    final container = _container(repo);
    await _pump(tester, _host(container));

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.libraryName),
      'shelf',
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.libraryPath),
      '/srv/media/shelf',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.librarySubmit),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.libraryWarning),
      findsOneWidget,
    );
    expect(find.textContaining('sidecar refused'), findsOneWidget);
  });

  testWidgets('the per-library switches reach the server', (tester) async {
    final repo = FakeRepository();
    repo.libraries.addAll(const [
      LibraryInfo(pid: 'lb-1', name: 'music', path: '/srv/music'),
      LibraryInfo(
        pid: 'lb-2',
        name: 'vinyl',
        path: '/srv/vinyl',
        readOnly: true,
      ),
    ]);
    final container = _container(repo);
    await _pump(tester, _host(container));
    WaxSwitch readOnlySwitch(String pid) => tester.widget<WaxSwitch>(
      find.ancestor(
        of: find.bySemanticsIdentifier(SemanticsIds.libraryReadOnly(pid)),
        matching: find.byType(WaxSwitch),
      ),
    );
    expect(
      readOnlySwitch('lb-2').value,
      isTrue,
      reason: 'the listing carries the flag',
    );

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryReadOnly('lb-1')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(repo.setLibraryReadOnlyCalls, [
      (libraryPid: 'lb-1', readOnly: true),
    ]);
    expect(
      readOnlySwitch('lb-1').value,
      isTrue,
      reason: 'the reloaded listing',
    );

    // Rescanning covers every root: the contract has one scan verb, and
    // the row's button is where somebody looks for it - which is why a
    // confirm dialog now says so before anything starts.
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryRescan('lb-1')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(repo.rescans, 0, reason: 'nothing starts before the confirm');
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryRescanConfirm),
    );
    await tester.pumpAndSettle();
    expect(repo.rescans, 1);
    expect(repo.rescanForces, [false]);
  });

  testWidgets('an in-place library names untagged files from folders', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.libraries.addAll(const [
      LibraryInfo(pid: 'lb-1', name: 'music', path: '/srv/music'),
      LibraryInfo(
        pid: 'lb-2',
        name: 'placed',
        path: '/srv/placed',
        managed: true,
      ),
    ]);
    final container = _container(repo);
    await _pump(tester, _host(container));

    expect(
      find.bySemanticsIdentifier(SemanticsIds.libraryFolderFallback('lb-2')),
      findsNothing,
      reason: "a managed library's folders are the catalog's own",
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryFolderFallback('lb-1')),
    );
    await tester.pumpAndSettle();
    expect(repo.setLibraryFolderFallbackCalls, [
      (libraryPid: 'lb-1', on: true),
    ]);
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'Applies to new files now. Re-read unchanged files in Rescan to apply '
      'it to files already scanned.',
    );
  });

  testWidgets('the folder switch reads what the server stored on return', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.libraries.add(
      const LibraryInfo(pid: 'lb-1', name: 'music', path: '/srv/music'),
    );
    final container = _container(repo);
    await _pump(tester, _host(container));
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryFolderFallback('lb-1')),
    );
    await tester.pumpAndSettle();

    // Away and back: a fresh switch holds no value of its own, so what
    // it draws is the table's listing.
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SizedBox()),
    );
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();
    final folders = tester.widget<WaxSwitch>(
      find.ancestor(
        of: find.bySemanticsIdentifier(
          SemanticsIds.libraryFolderFallback('lb-1'),
        ),
        matching: find.byType(WaxSwitch),
      ),
    );
    expect(folders.value, isTrue, reason: 'the server holds it on');
  });

  testWidgets('changing what a library holds asks first, then scans', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.libraries.addAll(const [
      LibraryInfo(
        pid: 'lb-1',
        name: 'spoken',
        path: '/srv/spoken',
        media: 'mixed',
      ),
      LibraryInfo(pid: 'lb-p', name: 'podcasts', media: 'podcast'),
    ]);
    final container = _container(repo);
    await _pump(tester, _host(container));
    expect(
      find.bySemanticsIdentifier(SemanticsIds.libraryMediaChoice('lb-p')),
      findsNothing,
      reason: 'the podcast library holds podcasts',
    );

    Future<void> choose(String label) async {
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.libraryMediaChoice('lb-1')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    await choose('Books');
    expect(
      find.text(
        'Every audio file in spoken becomes a book on the scan this '
        'starts, the parts in one folder gathered into one book. Items '
        'whose kind was set by hand keep it.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.setLibraryMediaCalls, isEmpty);

    await choose('Books');
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryMediaConfirm),
    );
    await tester.pumpAndSettle();
    expect(repo.setLibraryMediaCalls, [
      (libraryPid: 'lb-1', media: 'audiobook'),
    ]);
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'Scanning spoken to apply the change.',
    );

    repo.libraryMediaScanStarts = false;
    await choose('Music');
    expect(find.textContaining('read again'), findsOneWidget);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryMediaConfirm),
    );
    await tester.pumpAndSettle();
    expect(repo.setLibraryMediaCalls.last.media, 'music');
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'Another job is running. Once it ends, rescan with Re-read unchanged '
      'files on to apply the change to spoken.',
    );
  });

  testWidgets('a library the configuration declares says what it holds, and '
      'why it stays', (tester) async {
    final repo = FakeRepository();
    repo.libraries.addAll(const [
      LibraryInfo(
        pid: 'lb-b',
        name: 'books',
        path: '/srv/books',
        media: 'audiobook',
        mediaDeclared: true,
      ),
      LibraryInfo(pid: 'lb-m', name: 'music', path: '/srv/music'),
    ]);
    await _pump(tester, _host(_container(repo)));

    expect(
      find.bySemanticsIdentifier(SemanticsIds.libraryMediaChoice('lb-b')),
      findsNothing,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.libraryMediaChoice('lb-m')),
      findsOneWidget,
    );
    final row = find.bySemanticsIdentifier(SemanticsIds.libraryRow('lb-b'));
    expect(
      find.descendant(of: row, matching: find.text('Books')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row,
        matching: find.text("Set by the server's configuration"),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a kind change that starts a scan reads the jobs again', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.libraries.add(
      const LibraryInfo(
        pid: 'lb-1',
        name: 'spoken',
        path: '/srv/spoken',
        media: 'mixed',
      ),
    );
    final container = _container(repo);
    await _pump(tester, _host(container));
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryMediaChoice('lb-1')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Books').last);
    await tester.pumpAndSettle();
    final reads = repo.jobReads;

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryMediaConfirm),
    );
    await tester.pumpAndSettle();

    // As the rescan and a new library do: the scan it started is in
    // the list the Rescan buttons and the dashboard read.
    expect(repo.jobReads, reads + 1);
  });

  testWidgets('a kind change confirmed after its row was rebuilt still lands', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.libraries.add(
      const LibraryInfo(
        pid: 'lb-1',
        name: 'spoken',
        path: '/srv/spoken',
        media: 'mixed',
      ),
    );
    final container = _container(repo);
    await _pump(tester, _host(container));
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryMediaChoice('lb-1')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Books').last);
    await tester.pumpAndSettle();

    // The window narrows under the dialog: the table becomes cards, and
    // the row that asked is gone by the answer.
    tester.view.physicalSize = const Size(600, 1600);
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryMediaConfirm),
    );
    await tester.pumpAndSettle();

    expect(repo.setLibraryMediaCalls, [
      (libraryPid: 'lb-1', media: 'audiobook'),
    ]);
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'Scanning spoken to apply the change.',
    );
  });

  testWidgets('the podcast library offers no read-only switch', (tester) async {
    final repo = FakeRepository();
    repo.libraries.add(
      const LibraryInfo(
        pid: 'lb-9',
        name: 'podcasts',
        media: 'podcast',
        path: '/srv/podcasts',
      ),
    );
    await _pump(tester, _host(_container(repo)));
    expect(
      find.bySemanticsIdentifier(SemanticsIds.libraryRow('lb-9')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.libraryReadOnly('lb-9')),
      findsNothing,
      reason: 'episode fetching needs the library writable',
    );
  });

  testWidgets('the podcast library offers no matching choice and no rescan', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.libraries.addAll(const <LibraryInfo>[
      LibraryInfo(
        pid: 'lb-1',
        name: 'music',
        media: 'music',
        path: '/srv/music',
      ),
      LibraryInfo(
        pid: 'lb-9',
        name: 'podcasts',
        media: 'podcast',
        path: '/srv/podcasts',
      ),
    ]);
    await _pump(tester, _host(_container(repo)));
    expect(
      find.bySemanticsIdentifier(SemanticsIds.libraryMatching('lb-9')),
      findsNothing,
      reason: 'episodes come from their feeds, which nothing matches',
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.libraryRescan('lb-9')),
      findsNothing,
      reason: 'a rescan reads every root but the podcast library',
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.libraryMatching('lb-1')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.libraryRescan('lb-1')),
      findsOneWidget,
    );
  });

  testWidgets('a flag answered after its row left still refreshes', (
    tester,
  ) async {
    final gate = Completer<void>();
    final repo = FakeRepository()..libraryWriteGate = gate;
    repo.libraries.add(
      const LibraryInfo(pid: 'lb-1', name: 'music', path: '/srv/music'),
    );
    final container = _container(repo);
    await _pump(tester, _host(container));
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryReadOnly('lb-1')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SizedBox()),
    );
    final reads = repo.listLibrariesCalls.length;

    gate.complete();
    await tester.pumpAndSettle();
    await container.read(libraryCountsProvider.future);
    expect(repo.listLibrariesCalls.length, reads + 1);
  });

  testWidgets('a managed library\'s profile choice reaches the server', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..organizeProfiles = const [
        OrganizeProfile(name: 'waxbin-native', builtIn: true),
        OrganizeProfile(name: 'flat'),
      ];
    repo.libraries.addAll(const [
      LibraryInfo(
        pid: 'lb-1',
        name: 'music',
        path: '/srv/music',
        managed: true,
        profile: 'waxbin-native',
      ),
      LibraryInfo(pid: 'lb-2', name: 'vinyl', path: '/srv/vinyl'),
    ]);
    final container = _container(repo);
    await _pump(tester, _host(container));
    expect(
      find.bySemanticsIdentifier(SemanticsIds.libraryProfile('lb-2')),
      findsNothing,
      reason: 'an in-place library is never laid out',
    );
    expect(find.text('In place'), findsOneWidget);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryProfile('lb-1')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('flat').last);
    await tester.pumpAndSettle();
    expect(repo.setLibraryProfileCalls, [
      (libraryPid: 'lb-1', profile: 'flat'),
    ]);
    expect(
      tester
          .widget<WaxChoice<String>>(
            find.ancestor(
              of: find.bySemanticsIdentifier(
                SemanticsIds.libraryProfile('lb-1'),
              ),
              matching: find.byType(WaxChoice<String>),
            ),
          )
          .value,
      'flat',
      reason: 'the reloaded listing',
    );
  });

  testWidgets('the rescan dialog carries the repair pass', (tester) async {
    final repo = FakeRepository();
    repo.libraries.add(
      const LibraryInfo(pid: 'lb-1', name: 'music', path: '/srv/music'),
    );
    final container = _container(repo);
    await _pump(tester, _host(container));

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryRescan('lb-1')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryRescanForce),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryRescanConfirm),
    );
    await tester.pumpAndSettle();
    expect(repo.rescanForces, [true]);
  });

  testWidgets('a library made while another job runs says its scan waits', (
    tester,
  ) async {
    final repo = FakeRepository()..createLibraryScanStarted = false;
    final container = _container(repo);
    await _pump(tester, _host(container));

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.libraryName),
      'audiobooks',
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.libraryPath),
      '/srv/media/audiobooks',
    );
    await tester.ensureVisible(
      find.bySemanticsIdentifier(SemanticsIds.librarySubmit),
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.librarySubmit),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'Library "audiobooks" created. Another catalog job is running, so '
      'the next scan will index it.',
    );
  });

  testWidgets('a rescan refused while a job runs says so', (tester) async {
    final repo = FakeRepository()
      ..rescanError = const WaxDeckApiException(
        code: 'conflict',
        message: 'a conflicting catalog job is already running',
        statusCode: 409,
      );
    repo.libraries.add(
      const LibraryInfo(pid: 'lb-1', name: 'music', path: '/srv/music'),
    );
    final container = _container(repo);
    await _pump(tester, _host(container));

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryRescan('lb-1')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryRescanConfirm),
    );
    await tester.pumpAndSettle();

    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'A scan or another catalog job is already running.',
    );
  });

  testWidgets('rescan is busy while a scan runs', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final repo = FakeRepository()
      ..jobs = [const Job(pid: 'jb-1', kind: 'scan', state: 'running')];
    repo.libraries.add(
      const LibraryInfo(pid: 'lb-1', name: 'music', path: '/srv/music'),
    );
    await _pump(tester, _host(_container(repo)));

    final rescan = tester.widget<WaxIconButton>(
      find.byWidgetPredicate(
        (w) =>
            w is WaxIconButton &&
            w.semanticsId == SemanticsIds.libraryRescan('lb-1'),
      ),
    );
    expect(rescan.busy, isTrue);
  });

  testWidgets('removing a library needs the typed name and follows the job', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.libraries.addAll(const [
      LibraryInfo(pid: 'lb-1', name: 'music', path: '/srv/music'),
      LibraryInfo(pid: 'lb-2', name: 'spare', path: '/srv/spare'),
    ]);
    final container = _container(repo);
    await _pump(tester, _host(container));

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryMenu('lb-2')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryRemove('lb-2')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Remove "spare"?'), findsOneWidget);

    final confirm = find.bySemanticsIdentifier(
      SemanticsIds.libraryRemoveConfirm,
    );
    await tester.tap(confirm, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(repo.removeLibraryCalls, isEmpty, reason: 'nothing before the name');
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.confirmField),
      'spare',
    );
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(repo.removeLibraryCalls, ['lb-2']);
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'Removing "spare"; follow it in Tasks',
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.libraryRow('lb-2')),
      findsNothing,
      reason: 'the listing is read again',
    );
  });

  testWidgets('a configured library offers no remove and says why', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.libraries.add(
      const LibraryInfo(
        pid: 'lb-1',
        name: 'music',
        path: '/srv/music',
        configured: true,
      ),
    );
    final container = _container(repo);
    await _pump(tester, _host(container));
    expect(find.text('Configured on the server'), findsOneWidget);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryMenu('lb-1')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Configured on the server; remove it from WAXDECK_LIBRARY_ROOTS first',
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryRemove('lb-1')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.text('Remove "music"?'), findsNothing);
    expect(repo.removeLibraryCalls, isEmpty);
  });

  testWidgets('the podcast library has nothing to remove', (tester) async {
    final repo = FakeRepository();
    repo.libraries.add(
      const LibraryInfo(pid: 'lb-p', name: 'podcasts', media: 'podcast'),
    );
    final container = _container(repo);
    await _pump(tester, _host(container));
    expect(
      find.bySemanticsIdentifier(SemanticsIds.libraryMenu('lb-p')),
      findsNothing,
    );
  });

  testWidgets('a row says when its folder is gone or not writable', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.libraries.addAll(const [
      LibraryInfo(
        pid: 'lb-1',
        name: 'drive',
        path: '/mnt/drive',
        unreachable: true,
      ),
      LibraryInfo(
        pid: 'lb-2',
        name: 'locked',
        path: '/srv/locked',
        managed: true,
        writable: false,
      ),
      LibraryInfo(
        pid: 'lb-3',
        name: 'open',
        path: '/srv/open',
        managed: true,
        writable: true,
      ),
      // Read-only: the server does not try its folder, so says nothing.
      LibraryInfo(
        pid: 'lb-4',
        name: 'kept',
        path: '/srv/kept',
        managed: true,
        readOnly: true,
      ),
    ]);
    final container = _container(repo);
    await _pump(tester, _host(container));
    expect(find.text('Folder not reachable'), findsOneWidget);
    expect(
      find.text('Not writable by the server'),
      findsOneWidget,
      reason: 'the locked library only, not the read-only one',
    );
    expect(find.text('Configured on the server'), findsNothing);
  });

  testWidgets('a refused path keeps the form and says why', (tester) async {
    final repo = FakeRepository()
      ..createLibraryError = const WaxDeckApiException(
        code: 'invalid-request',
        message: 'the library path must be absolute',
        statusCode: 400,
      );
    final container = _container(repo);
    await _pump(tester, _host(container));
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.libraryName),
      'shelf',
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.libraryPath),
      'relative/path',
    );
    await tester.ensureVisible(
      find.bySemanticsIdentifier(SemanticsIds.librarySubmit),
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.librarySubmit),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'the library path must be absolute',
    );
    expect(find.text('shelf'), findsOneWidget);
    expect(find.text('relative/path'), findsOneWidget);
  });

  testWidgets('the absent-folder switch reaches the request', (tester) async {
    final repo = FakeRepository();
    final container = _container(repo);
    await _pump(tester, _host(container));
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.libraryName),
      'later',
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.libraryPath),
      '/mnt/later',
    );
    await tester.ensureVisible(
      find.bySemanticsIdentifier(SemanticsIds.libraryAbsent),
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryAbsent),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.bySemanticsIdentifier(SemanticsIds.librarySubmit),
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.librarySubmit),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(repo.createLibraryCalls, [
      (name: 'later', path: '/mnt/later', allowAbsent: true),
    ]);
    final absent = tester.widget<WaxSwitch>(
      find.ancestor(
        of: find.bySemanticsIdentifier(SemanticsIds.libraryAbsent),
        matching: find.byType(WaxSwitch),
      ),
    );
    expect(absent.value, isFalse, reason: 'the form starts over');
  });

  testWidgets('a refused removal says why and reads the lists again', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..removeLibraryError = const WaxDeckApiException(
        code: 'catalog-busy',
        message:
            'a conflicting catalog job is already running; retry when it finishes',
        statusCode: 409,
      );
    repo.libraries.add(
      const LibraryInfo(pid: 'lb-2', name: 'spare', path: '/srv/spare'),
    );
    final container = _container(repo);
    await _pump(tester, _host(container));
    final countsRead = repo.listLibrariesCalls.where((c) => c).length;
    final jobsRead = repo.jobReads;

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryMenu('lb-2')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryRemove('lb-2')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.confirmField),
      'spare',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryRemoveConfirm),
    );
    await tester.pumpAndSettle();

    expect(repo.removeLibraryCalls, ['lb-2']);
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      "Another job is holding the library's files. Try again shortly.",
      reason: "the table's sentence, not the server's",
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.libraryRow('lb-2')),
      findsOneWidget,
    );
    expect(
      repo.listLibrariesCalls.where((c) => c).length,
      greaterThan(countsRead),
      reason: 'the libraries are read again',
    );
    expect(repo.jobReads, greaterThan(jobsRead), reason: 'and the jobs');
  });

  testWidgets('a removal refused on a stale list says to look again', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..removeLibraryError = const WaxDeckApiException(
        code: 'conflict',
        message:
            'this library is configured in WAXDECK_LIBRARY_ROOTS; take it out '
            'of the configuration and restart, then remove it here',
        statusCode: 409,
      );
    repo.libraries.add(
      const LibraryInfo(pid: 'lb-2', name: 'spare', path: '/srv/spare'),
    );
    final container = _container(repo);
    // Read by the screens that list libraries without their counts.
    container.listen(librariesProvider, (_, _) {});
    await _pump(tester, _host(container));
    final listed = repo.listLibrariesCalls.where((c) => !c).length;

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryMenu('lb-2')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryRemove('lb-2')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.confirmField),
      'spare',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryRemoveConfirm),
    );
    await tester.pumpAndSettle();

    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'Something else changed this first. Take another look and try again.',
      reason: "the table's sentence: the row it acted on was out of date",
    );
    expect(
      repo.listLibrariesCalls.where((c) => !c).length,
      greaterThan(listed),
      reason: 'the libraries other screens list are read again',
    );
  });

  testWidgets('a wide window draws a table whose header labels the menus', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.libraries.addAll(const [
      LibraryInfo(pid: 'lb-2', name: 'spare', path: '/srv/spare'),
      LibraryInfo(pid: 'lb-3', name: 'tapes', path: '/srv/tapes'),
    ]);
    await _pump(tester, _host(_container(repo)));
    expect(
      find.text('Actions'),
      findsOneWidget,
      reason: 'one header over both rows, not a label on each card',
    );
    for (final pid in ['lb-2', 'lb-3']) {
      expect(
        find.bySemanticsIdentifier(SemanticsIds.libraryMenu(pid)),
        findsOneWidget,
      );
    }
  });

  testWidgets('a narrow window labels the row menu and opens it', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.libraries.addAll(const [
      LibraryInfo(pid: 'lb-2', name: 'spare', path: '/srv/spare'),
      LibraryInfo(pid: 'lb-3', name: 'tapes', path: '/srv/tapes'),
    ]);
    final container = _container(repo);
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    final trigger = find.bySemanticsIdentifier(
      SemanticsIds.libraryMenu('lb-2'),
    );
    expect(
      find.text('Actions'),
      findsNWidgets(2),
      reason: 'each card row says what it is',
    );
    expect(
      tester.getSize(trigger).width,
      lessThanOrEqualTo(48),
      reason: 'the button keeps its own size on a card',
    );
    await tester.tap(trigger, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.libraryRemove('lb-2')),
      findsOneWidget,
    );
  });
}
