import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/diagnostics/defect_log.dart';
import 'package:waxdeck/src/diagnostics/defect_log_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/about_screen.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';

import 'fakes.dart';
import 'routed_host.dart';

Finder _byId(String id) => find.bySemanticsIdentifier(id);

void main() {
  testWidgets('About reaches the defect log, and the log shows what it holds', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(FakeRepository())],
    );
    addTearDown(container.dispose);
    container
        .read(defectLogProvider.notifier)
        .record(
          source: 'async',
          error: StateError('a decode failure'),
          stack: StackTrace.fromString('the stack'),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(const AboutScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(_byId(SemanticsIds.aboutDefects));
    await tester.pumpAndSettle();

    expect(_byId(SemanticsIds.defectsScreen), findsOneWidget);
    expect(find.textContaining('a decode failure'), findsOneWidget);
    expect(find.textContaining('[async]'), findsOneWidget);
  });

  testWidgets('an empty log says so rather than showing a blank page', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(FakeRepository())],
        child: routedHost(const DefectLogScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing has gone wrong'), findsOneWidget);
    expect(_byId(SemanticsIds.defectsCopy), findsNothing);
  });

  testWidgets('clear flips the log to its empty state', (tester) async {
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(FakeRepository())],
    );
    addTearDown(container.dispose);
    container
        .read(defectLogProvider.notifier)
        .record(source: 'async', error: StateError('a stale failure'));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(const DefectLogScreen()),
      ),
    );
    await tester.pumpAndSettle();

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
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(FakeRepository())],
    );
    addTearDown(container.dispose);
    container
        .read(defectLogProvider.notifier)
        .record(source: 'framework', error: StateError('a build error'));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(const DefectLogScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(_byId(SemanticsIds.defectsCopy));
    await tester.pumpAndSettle();

    expect(copied, hasLength(1));
    expect(copied.single, contains('WaxDeck defect log'));
    expect(copied.single, contains('a build error'));
    expect(find.text('Defect log copied'), findsOneWidget);
  });
}
