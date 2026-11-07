import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/diagnostics/defect_log.dart';
import 'package:waxdeck/src/diagnostics/defect_log_screen.dart';
import 'package:waxdeck/src/settings/about_screen.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';
import 'wax_finders.dart';

Finder _byId(String id) => find.bySemanticsIdentifier(id);

void main() {
  testWidgets('About reaches the defect log, and the log shows what it holds', (
    tester,
  ) async {
    final container = appContainer();
    container
        .read(defectLogProvider.notifier)
        .record(
          source: 'async',
          error: StateError('a decode failure'),
          stack: StackTrace.fromString('the stack'),
        );

    await pumpApp(tester, const AboutScreen(), container: container);

    expect(find.textContaining('newest first'), findsNothing);
    await tester.tap(_byId(SemanticsIds.aboutDefects));
    await tester.pumpAndSettle();

    expect(_byId(SemanticsIds.defectsScreen), findsOneWidget);
    expect(find.textContaining('a decode failure'), findsOneWidget);
    expect(find.textContaining('[async]'), findsOneWidget);
  });

  testWidgets("a server version that cannot be read says why, in the app's "
      'words', (tester) async {
    await mountApp(
      tester,
      const AboutScreen(),
      container: appContainer(
        repo: FakeRepository()
          ..serverHealthError = const WaxDeckApiException(
            code: 'internal',
            message: 'boom',
            statusCode: 500,
          ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(
      find.text('The server ran into a problem it could not handle.'),
      findsOneWidget,
    );
    // Unmounted inside the test, so no retry timer outlives it.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an empty log says so rather than showing a blank page', (
    tester,
  ) async {
    await pumpApp(tester, const DefectLogScreen());

    expect(find.text('Nothing has gone wrong'), findsOneWidget);
    expect(
      tester
          .widget<EmptyState>(emptyStateTitled('Nothing has gone wrong'))
          .message,
      isNull,
    );
    expect(_byId(SemanticsIds.defectsCopy), findsNothing);
  });

  testWidgets('clear flips the log to its empty state', (tester) async {
    final container = appContainer();
    container
        .read(defectLogProvider.notifier)
        .record(source: 'async', error: StateError('a stale failure'));

    await pumpApp(tester, const DefectLogScreen(), container: container);

    await tester.tap(_byId(SemanticsIds.defectsClear));
    await tester.pumpAndSettle();

    expect(container.read(defectLogProvider), isEmpty);
    expect(find.text('Nothing has gone wrong'), findsOneWidget);
    expect(_byId(SemanticsIds.defectsClear), findsNothing);
  });

  testWidgets('copy puts the whole report on the clipboard', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(
            (call.arguments as Map<Object?, Object?>)['text']! as String,
          );
        }
        return null;
      },
    );
    // The messenger has no automatic reset, and a handler that swallows
    // every platform call would outlive this test into the next one.
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final container = appContainer();
    container
        .read(defectLogProvider.notifier)
        .record(source: 'framework', error: StateError('a build error'));

    await pumpApp(tester, const DefectLogScreen(), container: container);

    await tester.tap(_byId(SemanticsIds.defectsCopy));
    await tester.pumpAndSettle();

    expect(copied, hasLength(1));
    expect(copied.single, contains('WaxDeck defect log'));
    expect(copied.single, contains('a build error'));
    expect(shellMessageText(raisedMessage(tester)), 'Defect log copied');
  });
}
