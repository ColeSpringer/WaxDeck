import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/books/book_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'bundled_type.dart';
import 'fakes.dart';
import 'routed_host.dart';

const bookPid = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';

const _sizes = [(Size(360, 640), 3.0), (Size(320, 480), 2.0)];

Finder _byId(String id) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.identifier == id,
);

Future<void> _tap(WidgetTester tester, String id) async {
  final finder = _byId(id).first;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

FakeRepository _repo({required bool merge}) =>
    FakeRepository(
        sessionState: const SessionState(
          authenticated: true,
          user: WaxDeckUser(
            id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
            username: 'admin',
            roles: ['admin'],
          ),
        ),
      )
      ..books[bookPid] = merge
          ? testBook(bookPid, partCount: 3)
          : testBook(
              bookPid,
              chapters: const [
                ChapterMark(index: 0, title: 'One', startMs: 0),
                ChapterMark(index: 1, title: 'Two', startMs: 600000),
              ],
            );

/// Opens the dialog on a window of [size] at text [scale], checks that
/// both actions sit whole inside it, keeps the originals and confirms.
Future<FakeRepository> _confirmTool(
  WidgetTester tester, {
  required bool merge,
  required Size size,
  required double scale,
  required Locale locale,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final repo = _repo(merge: merge);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        audioEngineProvider.overrideWithValue(FakeEngine()),
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      ],
      child: routedHost(const BookScreen(pid: bookPid), locale: locale),
    ),
  );
  await tester.pumpAndSettle();

  await _tap(tester, SemanticsIds.bookOverflow);
  await _tap(tester, merge ? SemanticsIds.bookMerge : SemanticsIds.bookSplit);
  final dialog = find.byType(AlertDialog);
  final window = Offset.zero & size;
  final actions = tester.widget<AlertDialog>(dialog).actions!;
  expect(actions, hasLength(2));
  for (final action in actions) {
    final button = tester.getRect(find.byWidget(action));
    final label = tester.getRect(
      find.descendant(of: find.byWidget(action), matching: find.byType(Text)),
    );
    for (final (rect, boxes) in [
      (button, [tester.getRect(dialog), window]),
      (label, [button]),
    ]) {
      for (final box in boxes) {
        expect(box.intersect(rect), rect, reason: '$rect within $box');
      }
    }
  }
  await _tap(
    tester,
    merge ? SemanticsIds.bookMergeKeep : SemanticsIds.bookSplitKeep,
  );
  await _tap(
    tester,
    merge ? SemanticsIds.bookMergeConfirm : SemanticsIds.bookSplitConfirm,
  );
  expect(
    merge
        ? repo.mergeBookCalls.single.keepOriginals
        : repo.splitBookCalls.single.keepOriginals,
    isTrue,
  );
  return repo;
}

/// The render object an overflow report is about.
RenderObject? _overflowing(FlutterErrorDetails details) {
  for (final node in details.informationCollector?.call() ?? const []) {
    if (node is DiagnosticableNode && node.value is RenderObject) {
      return node.value as RenderObject;
    }
  }
  return null;
}

/// Whether [box] was built by the dialog, read off the creator chains of
/// it and its ancestors.
bool _inDialog(RenderObject? box) {
  for (var at = box; at != null; at = at.parent) {
    if (at.debugCreator.toString().contains('\u2190 AlertDialog \u2190')) {
      return true;
    }
  }
  return false;
}

// The merge and split dialogs at large type on a narrow window, measured
// twice. flutter_test draws text in square glyphs an em wide, about twice
// what the bundled faces take, so a dialog whose choices fit there fits
// in any language the app ships: the dialog is held to that. The screen
// behind it overflows in those glyphs and not in its own type, so the
// second pass holds everything on screen to the faces a listener sees.
void main() {
  for (final (size, scale) in _sizes) {
    for (final locale in const [Locale('en'), Locale('es')]) {
      for (final merge in [true, false]) {
        final what =
            '${merge ? 'merge' : 'split'} dialog at '
            '${size.width.round()} wide, text x$scale '
            '(${locale.languageCode})';

        testWidgets('the $what keeps its choices whole in square glyphs', (
          tester,
        ) async {
          final inDialog = <String>[];
          final previous = FlutterError.onError;
          // The screen behind is the bundled-type pass's: only what
          // overflows inside the dialog counts here.
          FlutterError.onError = (details) {
            if (_inDialog(_overflowing(details))) {
              inDialog.add(details.exceptionAsString());
            } else if (!details.exceptionAsString().contains('overflowed')) {
              previous?.call(details);
            }
          };
          try {
            await _confirmTool(
              tester,
              merge: merge,
              size: size,
              scale: scale,
              locale: locale,
            );
          } finally {
            FlutterError.onError = previous;
          }
          expect(inDialog, isEmpty);
        });
      }
    }
  }

  group('in the bundled type', () {
    setUpAll(loadBundledType);

    for (final (size, scale) in _sizes) {
      for (final locale in const [Locale('en'), Locale('es')]) {
        for (final merge in [true, false]) {
          testWidgets('the screen and its ${merge ? 'merge' : 'split'} '
              'dialog fit at ${size.width.round()} wide, text x$scale '
              '(${locale.languageCode})', (tester) async {
            await _confirmTool(
              tester,
              merge: merge,
              size: size,
              scale: scale,
              locale: locale,
            );
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });
}
