import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/playlists/playlists_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';
import 'wax_finders.dart';

const _pony = ItemSummary(
  pid: 'tr-01JZX5N8QW3F4V9T2B7KD3M9R6',
  mediaType: MediaType.music,
  title: 'Prancing Pony Blues',
  artist: 'The Bree Trio',
  durationMs: 214000,
);

const _book = ItemSummary(
  pid: 'bk-01JZX5N8QW3F4V9T2B7KD3M9R7',
  mediaType: MediaType.audiobook,
  title: 'The Fixture Book',
  durationMs: 15000,
);

const _document =
    '#EXTM3U\n/music/pony.flac\n/books/part1.m4b\n/books/part2.m4b\n'
    '/music/missing.flac\n';

const _preview = M3uPreview(
  matched: 2,
  merged: 1,
  unmatched: 1,
  lines: [
    M3uPreviewLine(
      path: '/music/pony.flac',
      outcome: M3uLineOutcome.matched,
      item: _pony,
    ),
    M3uPreviewLine(
      path: '/books/part1.m4b',
      outcome: M3uLineOutcome.matched,
      item: _book,
    ),
    M3uPreviewLine(
      path: '/books/part2.m4b',
      outcome: M3uLineOutcome.merged,
      item: _book,
    ),
    M3uPreviewLine(
      path: '/music/missing.flac',
      outcome: M3uLineOutcome.unmatched,
    ),
  ],
);

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: routedHost(const PlaylistsScreen(), pushed: true),
);

Finder _id(String id) => find.bySemanticsIdentifier(id);

/// Opens the M3U paste box, names the playlist and pastes [_document].
Future<void> _paste(WidgetTester tester, FakeRepository repo) async {
  await tester.pumpWidget(_host(repo));
  await tester.pumpAndSettle();
  await _open(tester);
}

/// Opens the M3U paste box on the screen already up, names the playlist
/// and pastes [_document].
Future<void> _open(WidgetTester tester) async {
  await tester.tap(_id(SemanticsIds.playlistImport));
  await tester.pumpAndSettle();
  // By its label: the centre of the row's identifier node is not on the
  // widget that takes the tap.
  await tester.tap(find.text('M3U file'));
  await tester.pumpAndSettle();
  await tester.enterText(_id(SemanticsIds.playlistImportName), 'From M3U');
  await tester.enterText(_id(SemanticsIds.playlistImportPayload), _document);
}

Future<void> _tap(WidgetTester tester, String id) async {
  await tester.tap(_id(id));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a check shows the counts and every line, then imports once', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_pony])
      ..m3uPreview = _preview
      ..importMatched = 2
      ..importUnmatched = 1;
    await _paste(tester, repo);
    await _tap(tester, SemanticsIds.playlistM3uCheck);

    expect(repo.previewedM3uContents, [_document]);
    expect(repo.importedM3uContents, isEmpty);
    expect(
      find.text(
        '2 lines become entries, 1 joins the entry before it, '
        '1 has no match in the library.',
      ),
      findsOneWidget,
    );
    Finder inRow(int index, String text) => find.descendant(
      of: _id(SemanticsIds.playlistM3uPreviewRow(index)),
      matching: find.text(text),
    );
    expect(inRow(0, 'Entry'), findsOneWidget);
    expect(inRow(0, 'The Bree Trio - Prancing Pony Blues'), findsOneWidget);
    expect(inRow(1, 'The Fixture Book'), findsOneWidget);
    expect(inRow(2, 'Joins the entry before it'), findsOneWidget);
    expect(inRow(2, 'The Fixture Book'), findsOneWidget);
    expect(inRow(3, 'No match in the library'), findsOneWidget);
    expect(inRow(3, '/music/missing.flac'), findsOneWidget);
    expect(_id(SemanticsIds.playlistM3uCheck), findsNothing);

    await _tap(tester, SemanticsIds.playlistM3uImport);
    expect(repo.importedM3uContents, [_document]);
    expect(_id(SemanticsIds.playlistM3uPreview), findsNothing);
    expect(
      shellMessageText(raisedMessage(tester)),
      'Imported "From M3U": 2 matched, 1 not in the library',
    );
  });

  testWidgets('an edit to the paste drops the check', (tester) async {
    final repo = FakeRepository(items: const [_pony])..m3uPreview = _preview;
    await _paste(tester, repo);
    await _tap(tester, SemanticsIds.playlistM3uCheck);
    expect(_id(SemanticsIds.playlistM3uPreview), findsOneWidget);

    await tester.enterText(
      _id(SemanticsIds.playlistImportPayload),
      '#EXTM3U\n/music/other.flac\n',
    );
    await tester.pumpAndSettle();
    expect(_id(SemanticsIds.playlistM3uPreview), findsNothing);
    expect(_id(SemanticsIds.playlistM3uPreviewRow(0)), findsNothing);
    expect(_id(SemanticsIds.playlistM3uImport), findsNothing);
    expect(_id(SemanticsIds.playlistM3uCheck), findsOneWidget);
    expect(repo.importedM3uContents, isEmpty);
  });

  testWidgets('the check waits within a short dialog', (tester) async {
    final gate = Completer<void>();
    final repo = FakeRepository(items: const [_pony])
      ..m3uPreview = _preview
      ..m3uPreviewGate = gate;
    await _paste(tester, repo);
    tester.view.physicalSize = const Size(360, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.tap(_id(SemanticsIds.playlistM3uCheck));
    await tester.pump();

    expect(find.byType(SkeletonShapes), findsOneWidget);
    expect(tester.takeException(), isNull);
    // The dialog stays inside the window with its buttons on it: the
    // wait shrinks to the room left, it does not push them off.
    final window = Offset.zero & const Size(360, 300);
    final dialog = tester.getRect(find.byType(Dialog));
    expect(window.intersect(dialog), dialog);
    final check = tester.getRect(_id(SemanticsIds.playlistM3uCheck));
    expect(dialog.intersect(check), check);
    final ghost = tester.getRect(find.byType(SkeletonShapes));
    expect(ghost.top, greaterThanOrEqualTo(dialog.top));
    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a check answered after an edit is dropped', (tester) async {
    final gate = Completer<void>();
    final repo = FakeRepository(items: const [_pony])
      ..m3uPreview = _preview
      ..m3uPreviewGate = gate;
    await _paste(tester, repo);
    await tester.tap(_id(SemanticsIds.playlistM3uCheck));
    await tester.pump();
    await tester.enterText(
      _id(SemanticsIds.playlistImportPayload),
      '#EXTM3U\n/music/other.flac\n',
    );
    gate.complete();
    await tester.pumpAndSettle();

    expect(_id(SemanticsIds.playlistM3uPreview), findsNothing);
    expect(_id(SemanticsIds.playlistM3uCheck), findsOneWidget);
  });

  testWidgets('a refused check keeps the paste box and its sentence', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_pony])
      ..m3uPreviewError = const WaxDeckApiException(
        code: 'invalid-request',
        message: 'an M3U8 document may be at most 1048576 characters',
        statusCode: 400,
      );
    await _paste(tester, repo);
    await _tap(tester, SemanticsIds.playlistM3uCheck);

    expect(
      find.text('an M3U8 document may be at most 1048576 characters'),
      findsOneWidget,
    );
    expect(_id(SemanticsIds.playlistM3uPreview), findsNothing);
    expect(_id(SemanticsIds.playlistM3uCheck), findsOneWidget);
  });

  testWidgets('a long check builds only the lines in view', (tester) async {
    // Tall enough that the list of lines clears the dialog's buttons.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = FakeRepository(items: const [_pony])
      ..m3uPreview = M3uPreview(
        matched: 0,
        merged: 0,
        unmatched: 3000,
        lines: [
          for (var i = 0; i < 3000; i++)
            M3uPreviewLine(
              path: '/music/line$i.flac',
              outcome: M3uLineOutcome.unmatched,
            ),
        ],
      );
    await _paste(tester, repo);
    await _tap(tester, SemanticsIds.playlistM3uCheck);

    expect(find.text('/music/line0.flac'), findsOneWidget);
    expect(find.text('/music/line2999.flac'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('/music/line2999.flac'),
      3000,
      // The dialog's last scrollable: the paste box and the dialog's
      // own body come before the list of lines.
      scrollable: find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Scrollable),
          )
          .last,
    );
    expect(_id(SemanticsIds.playlistM3uPreviewRow(2999)), findsOneWidget);
  });

  testWidgets('a refused import keeps the dialog, its sentence and Import', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_pony])
      ..m3uPreview = _preview
      ..importM3uError = const WaxDeckApiException(
        code: 'invalid-request',
        message: 'a playlist name may be at most 200 characters',
        statusCode: 400,
      );
    await _paste(tester, repo);
    await _tap(tester, SemanticsIds.playlistM3uCheck);
    await _tap(tester, SemanticsIds.playlistM3uImport);

    expect(
      find.text('a playlist name may be at most 200 characters'),
      findsOneWidget,
    );
    expect(_id(SemanticsIds.playlistM3uPreview), findsOneWidget);
    final import = tester.widget<WaxButton>(
      find.ancestor(
        of: _id(SemanticsIds.playlistM3uImport),
        matching: find.byType(WaxButton),
      ),
    );
    expect(import.onPressed, isNotNull);
    expect(raisedMessage(tester), isNull);
  });

  testWidgets('a dismissal mid-check leaves the screen underneath', (
    tester,
  ) async {
    final gate = Completer<void>();
    final repo = FakeRepository(items: const [_pony])
      ..m3uPreview = _preview
      ..m3uPreviewGate = gate;
    await _paste(tester, repo);
    await tester.tap(_id(SemanticsIds.playlistM3uCheck));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(PlaylistsScreen), findsOneWidget);
    expect(_id(SemanticsIds.playlistImportPayload), findsNothing);
  });

  testWidgets('a dismissal mid-import leaves the screen underneath', (
    tester,
  ) async {
    final gate = Completer<void>();
    final repo = FakeRepository(items: const [_pony])
      ..m3uPreview = _preview
      ..importM3uGate = gate
      ..importMatched = 2
      ..importUnmatched = 1;
    await _paste(tester, repo);
    await _tap(tester, SemanticsIds.playlistM3uCheck);
    await tester.tap(_id(SemanticsIds.playlistM3uImport));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();

    // The import outlives the dialog, and still says what it made.
    expect(find.byType(PlaylistsScreen), findsOneWidget);
    expect(repo.importedM3uContents, [_document]);
    expect(
      shellMessageText(raisedMessage(tester)),
      'Imported "From M3U": 2 matched, 1 not in the library',
    );
  });

  testWidgets('a path named twice is two lines', (tester) async {
    final repo = FakeRepository(items: const [_pony])
      ..m3uPreview = const M3uPreview(
        matched: 2,
        merged: 0,
        unmatched: 0,
        lines: [
          M3uPreviewLine(
            path: '/music/pony.flac',
            outcome: M3uLineOutcome.matched,
            item: _pony,
          ),
          M3uPreviewLine(
            path: '/music/pony.flac',
            outcome: M3uLineOutcome.matched,
            item: _pony,
          ),
        ],
      );
    await _paste(tester, repo);
    await _tap(tester, SemanticsIds.playlistM3uCheck);

    for (final index in [0, 1]) {
      expect(
        find.descendant(
          of: _id(SemanticsIds.playlistM3uPreviewRow(index)),
          matching: find.text('The Bree Trio - Prancing Pony Blues'),
        ),
        findsOneWidget,
      );
    }
    expect(find.text('2 lines become entries.'), findsOneWidget);
  });

  testWidgets('a check that takes a while says so', (tester) async {
    final gate = Completer<void>();
    final repo = FakeRepository(items: const [_pony])
      ..m3uPreview = _preview
      ..m3uPreviewGate = gate;
    await _paste(tester, repo);
    await tester.tap(_id(SemanticsIds.playlistM3uCheck));
    await tester.pump();

    const checking =
        'Checking each line of the file. A long one takes a while.';
    expect(find.text(checking), findsOneWidget);
    expect(find.byType(SkeletonShapes), findsOneWidget);
    // The one spinner is the pressed button's own, busy where it stood.
    expect(
      tester
          .widget<WaxButton>(
            waxControl<WaxButton>(SemanticsIds.playlistM3uCheck),
          )
          .busy,
      isTrue,
    );
    expect(
      find.descendant(
        of: waxControl<WaxButton>(SemanticsIds.playlistM3uCheck),
        matching: find.byType(WaxSpinner),
      ),
      findsOneWidget,
    );
    expect(find.byType(WaxSpinner), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text(checking), findsNothing);
    expect(find.byType(SkeletonShapes), findsNothing);
  });

  testWidgets('an import says it is running, and no second one of the file '
      'starts while it does', (tester) async {
    final gate = Completer<void>();
    final repo = FakeRepository(items: const [_pony])
      ..m3uPreview = _preview
      ..importM3uGate = gate
      ..importMatched = 2
      ..importUnmatched = 1;
    await _paste(tester, repo);
    await _tap(tester, SemanticsIds.playlistM3uCheck);
    await tester.tap(_id(SemanticsIds.playlistM3uImport));
    await tester.pump();
    expect(
      find.text('Importing the playlist. A long file takes a while.'),
      findsOneWidget,
    );
    // The check's lines are already up, so the wait is on the button.
    expect(find.byType(SkeletonShapes), findsNothing);
    expect(
      tester
          .widget<WaxButton>(
            find.ancestor(
              of: _id(SemanticsIds.playlistM3uImport),
              matching: find.byType(WaxButton),
            ),
          )
          .busy,
      isTrue,
    );

    // Given up on, opened again and checked on the same file.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await _open(tester);
    await _tap(tester, SemanticsIds.playlistM3uCheck);
    WaxButton import() => tester.widget<WaxButton>(
      find.ancestor(
        of: _id(SemanticsIds.playlistM3uImport),
        matching: find.byType(WaxButton),
      ),
    );
    const still =
        'This file is still being imported. It can be imported again once '
        'that finishes.';
    expect(find.text(still), findsOneWidget);
    expect(import().onPressed, isNull);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text(still), findsNothing);
    expect(import().onPressed, isNotNull);
    expect(repo.importedM3uContents, [_document]);
  });
}
