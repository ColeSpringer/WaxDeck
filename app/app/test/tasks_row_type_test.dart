import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/tools/tasks_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'bundled_type.dart';
import 'fakes.dart';
import 'routed_host.dart';

Finder _row(String id) => find.bySemanticsIdentifier(SemanticsIds.taskRow(id));

// A task row's status at large type on a narrow window, in the faces the
// app ships: the longest words it says (Needs attention, Running with its
// percentage) stay whole inside the row, in English and Spanish.
void main() {
  setUpAll(loadBundledType);

  for (final (size, scale) in const [
    (Size(360, 640), 3.0),
    (Size(320, 480), 2.0),
  ]) {
    for (final locale in const [Locale('en'), Locale('es')]) {
      testWidgets('a row keeps its status whole at ${size.width.round()} '
          'wide, text x$scale (${locale.languageCode})', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final repo = FakeRepository();
        repo.toolTasksById['tt-p'] = ToolTask(
          id: 'tt-p',
          type: 'book-merge',
          state: 'parked',
          itemTitle: 'The Merge Book',
          error: 'stopped: its last 3 runs ended with the server',
          createdAt: DateTime.utc(2026, 7, 1, 2),
          finishedAt: DateTime.utc(2026, 7, 1, 3),
        );
        repo.toolTasksById['tt-r'] = ToolTask(
          id: 'tt-r',
          type: 'book-split',
          state: 'running',
          itemTitle: 'The Split Book',
          progressPct: 100,
          createdAt: DateTime.utc(2026, 7, 1, 1),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              repositoryProvider.overrideWithValue(repo),
              credentialStoreProvider.overrideWithValue(
                InMemoryCredentialStore(),
              ),
            ],
            child: routedHost(const TasksScreen(), locale: locale),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(tester.takeException(), isNull);
        final l10n = lookupAppLocalizations(locale);
        for (final (id, status) in [
          ('tt-p', l10n.toolsStateParked),
          ('tt-r', l10n.toolsStateRunningPct(100)),
        ]) {
          await tester.scrollUntilVisible(_row(id), 100);
          final row = tester.getRect(_row(id));
          final label = tester.getRect(
            find.descendant(of: _row(id), matching: find.text(status)),
          );
          expect(row.intersect(label), label, reason: '$status in its row');
          expect(label.right, lessThanOrEqualTo(size.width));
        }
      });
    }
  }
}
