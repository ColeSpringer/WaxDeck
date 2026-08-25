import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/libraries_screen.dart';
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

/// Wide enough for the table to be a table rather than a card list.
Future<void> _pump(WidgetTester tester, Widget host) async {
  tester.view.physicalSize = const Size(1200, 1600);
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
    repo.libraries.add(
      const LibraryInfo(pid: 'lb-1', name: 'music', path: '/srv/music'),
    );
    final container = _container(repo);
    await _pump(tester, _host(container));

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.libraryReadOnly('lb-1')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(repo.libraryReadOnlyByPid['lb-1'], isTrue);

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
}
