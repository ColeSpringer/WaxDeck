import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/lifecycle_banners.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';

/// The banners on their own, the way the shell frame hosts them.
class _BannerHost extends ConsumerWidget {
  const _BannerHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: lifecycleBanners(ref),
    ),
  );
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required FakeRepository repo,
}) async {
  final container = ProviderContainer(
    overrides: [repositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildWaxTheme(), home: const _BannerHost()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('a dropped connection says it is reconnecting, and stops', (
    tester,
  ) async {
    final container = await _pump(tester, repo: FakeRepository());
    // Nothing has answered yet, which is not the same as a broken
    // connection: a client that has not tried is not reconnecting.
    expect(find.byType(WaxBanner), findsNothing);

    container.read(liveLinkProvider.notifier).report(connected: false);
    await tester.pumpAndSettle();
    expect(find.textContaining('Reconnecting'), findsOneWidget);

    container.read(liveLinkProvider.notifier).report(connected: true);
    await tester.pumpAndSettle();
    expect(
      find.byType(WaxBanner),
      findsNothing,
      reason: 'it clears itself, silently',
    );
  });

  testWidgets('a server that came back as another build says so', (
    tester,
  ) async {
    final repo = FakeRepository();
    final container = await _pump(tester, repo: repo);
    final link = container.read(liveLinkProvider.notifier);

    // The first connect is the baseline, never a report of change.
    link.report(connected: true);
    await tester.pumpAndSettle();
    expect(find.byType(WaxBanner), findsNothing);

    // A restart, which is exactly what a reconnect means here.
    repo.serverVersion = '1.1.0';
    link.report(connected: false);
    await tester.pumpAndSettle();
    link.report(connected: true);
    await tester.pumpAndSettle();

    expect(find.textContaining('updated'), findsOneWidget);
  });

  testWidgets('an API version bump counts as a new build', (tester) async {
    // The case the banner exists for: a bundle from before a contract
    // change, still running against the server that changed it.
    final repo = FakeRepository();
    final container = await _pump(tester, repo: repo);
    final link = container.read(liveLinkProvider.notifier);

    link.report(connected: true);
    await tester.pumpAndSettle();

    repo.apiVersion = 2;
    link.report(connected: false);
    await tester.pumpAndSettle();
    link.report(connected: true);
    await tester.pumpAndSettle();

    expect(find.textContaining('updated'), findsOneWidget);
  });

  testWidgets('a probe that fails off-contract says nothing, and survives', (
    tester,
  ) async {
    // The probe runs unawaited, so anything escaping it reaches the zone
    // with no handler. The client maps only transport failures into the
    // structured API error, and a response the generated deserializer
    // cannot build throws something else — which is exactly the shape
    // the one event this watches for can produce.
    final repo = FakeRepository()
      ..serverHealthError = const FormatException('not the health you knew');
    final container = await _pump(tester, repo: repo);

    container.read(liveLinkProvider.notifier).report(connected: true);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(WaxBanner), findsNothing);

    // And the baseline was never taken, so the next probe that answers
    // is the one that establishes it rather than a false alarm.
    repo.serverHealthError = null;
    repo.serverVersion = '1.1.0';
    container.read(liveLinkProvider.notifier).report(connected: false);
    await tester.pumpAndSettle();
    container.read(liveLinkProvider.notifier).report(connected: true);
    await tester.pumpAndSettle();
    expect(find.textContaining('updated'), findsNothing);
  });

  testWidgets('a reconnect onto the same build says nothing', (tester) async {
    final repo = FakeRepository();
    final container = await _pump(tester, repo: repo);
    final link = container.read(liveLinkProvider.notifier);

    link.report(connected: true);
    await tester.pumpAndSettle();
    link.report(connected: false);
    await tester.pumpAndSettle();
    link.report(connected: true);
    await tester.pumpAndSettle();

    expect(find.textContaining('updated'), findsNothing);
  });
}
