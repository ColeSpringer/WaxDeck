import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/client_settings_providers.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';
import 'player_host.dart';

/// A screen that reads two ports in its build, the way the app's do, and
/// says what it found.
class _ReadsPorts extends ConsumerWidget {
  const _ReadsPorts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    final store = ref.watch(credentialStoreProvider);
    final locale = Localizations.localeOf(context);
    return Text('${repo.runtimeType} ${store.runtimeType} $locale');
  }
}

final _countProvider = NotifierProvider<_Count, int>(_Count.new);

/// The count doubled, which only the container's scheduler recomputes: a
/// scope that never registered with the container never redraws it.
final _doubledProvider = Provider<int>((ref) => ref.watch(_countProvider) * 2);

class _Count extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// A timer a provider holds until its container goes.
final _timerProvider = Provider<Timer>((ref) {
  final timer = Timer(const Duration(hours: 1), () {});
  ref.onDispose(timer.cancel);
  return timer;
});

/// A provider whose disposal throws.
final _throwsOnDisposeProvider = Provider<int>((ref) {
  ref.onDispose(() => throw StateError('disposal'));
  return 0;
});

/// A read that fails as it starts, which is when the retry policy is asked.
final _downProvider = FutureProvider<int>((ref) => throw const _Down());

final class _Down implements Exception {
  const _Down();
}

/// An observer keeping each provider it saw start.
final class _Adds extends ProviderObserver {
  final added = <Object>[];

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) =>
      added.add(context.provider);
}

class _ShowsDoubled extends ConsumerWidget {
  const _ShowsDoubled();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Text('${ref.watch(_doubledProvider)}');
}

class _HoldsTimer extends ConsumerWidget {
  const _HoldsTimer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(_timerProvider);
    return const SizedBox();
  }
}

final _movedInBuildProvider = NotifierProvider<_Count, int>(_Count.new);

/// Moves a provider from its build once the count moves, which Riverpod
/// refuses in debug builds.
class _MovesInBuild extends ConsumerWidget {
  const _MovesInBuild();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(_countProvider) > 0) {
      ref.read(_movedInBuildProvider.notifier).bump();
    }
    return const SizedBox();
  }
}

/// Runs [raise] with flutter_test's failure report held, and returns the
/// errors it would have failed the test with.
Future<List<Object>> _failuresDuring(FutureOr<void> Function() raise) async {
  final failures = <Object>[];
  final report = reportTestException;
  reportTestException = (details, _) => failures.add(details.exception);
  try {
    await raise();
  } finally {
    reportTestException = report;
  }
  return failures;
}

void main() {
  group('appContainer', () {
    test('wires the fakes when given nothing', () {
      final container = appContainer();
      expect(container.read(repositoryProvider), isA<FakeRepository>());
      expect(container.read(audioEngineProvider), isA<FakeEngine>());
      expect(
        container.read(credentialStoreProvider),
        isA<InMemoryCredentialStore>(),
      );
      expect(container.read(artworkStoreProvider), isA<FakeArtworkStore>());
    });

    test('leaves the native ports to their own providers', () {
      final container = appContainer();
      expect(container.read(downloadManagerProvider), isNull);
      expect(container.read(syncEngineProvider), isNull);
      expect(container.read(mirrorDatabaseProvider), isNull);
      expect(
        container.read(clientSettingsStoreProvider),
        isA<MemoryClientSettingsStore>(),
      );
    });

    test('hands back the ports it was given', () {
      final repo = FakeRepository();
      final engine = FakeEngine();
      final credentials = InMemoryCredentialStore();
      final artwork = FakeArtworkStore();
      final downloads = FakeDownloads();
      final settings = MemoryClientSettingsStore();
      final container = appContainer(
        repo: repo,
        engine: engine,
        credentials: credentials,
        artwork: artwork,
        downloads: downloads,
        settings: settings,
      );
      expect(container.read(repositoryProvider), same(repo));
      expect(container.read(audioEngineProvider), same(engine));
      expect(container.read(credentialStoreProvider), same(credentials));
      expect(container.read(artworkStoreProvider), same(artwork));
      expect(container.read(downloadManagerProvider), same(downloads));
      expect(container.read(clientSettingsStoreProvider), same(settings));
    });

    test('hands back the mirror and the engine syncing it', () async {
      final db = inMemoryMirrorDatabase();
      final sync = SyncEngine(
        db: db,
        repository: FakeRepository(),
        channelFactory: deadChannelFactory(),
      );
      addTearDown(() async {
        sync.dispose();
        await db.close();
      });
      final container = appContainer(mirror: db, sync: sync);
      expect(container.read(mirrorDatabaseProvider), same(db));
      expect(container.read(syncEngineProvider), same(sync));
    });

    test('takes a port that is not one of the fakes', () {
      final settings = _OwnSettings();
      final container = appContainer(settings: settings);
      expect(container.read(clientSettingsStoreProvider), same(settings));
    });

    test('applies the extra overrides beside its own', () {
      final container = appContainer(
        repo: FakeRepository(),
        extra: [serverConfiguredProvider.overrideWithValue(false)],
      );
      expect(container.read(serverConfiguredProvider), isFalse);
      expect(container.read(repositoryProvider), isA<FakeRepository>());
      expect(appContainer().read(serverConfiguredProvider), isTrue);
    });

    test('is disposed when the test ends', () {
      late ProviderContainer container;
      // Teardowns run last-in first, so this one sees the disposed container.
      addTearDown(
        () =>
            expect(() => container.read(repositoryProvider), throwsStateError),
      );
      container = appContainer();
    });

    testWidgets('a provider error in the body fails the test', (tester) async {
      final container = appContainer();
      container.listen(_countProvider, (_, _) => throw StateError('listener'));
      final failures = await _failuresDuring(
        () => container.read(_countProvider.notifier).bump(),
      );
      expect(failures, [isStateError]);
    });

    testWidgets('a provider error as its teardown disposes the container '
        'fails the test', (tester) async {
      final failures = <Object>[];
      final report = reportTestException;
      // Teardowns run last-in first, so these two bracket the disposal.
      addTearDown(() {
        reportTestException = report;
        expect(failures, [isStateError]);
      });
      appContainer().read(_throwsOnDisposeProvider);
      addTearDown(() {
        reportTestException = (details, _) => failures.add(details.exception);
      });
    });

    testWidgets('a provider error from a callback a teardown fires fails the '
        'test', (tester) async {
      final container = appContainer();
      container.listen(_countProvider, (_, _) => throw StateError('listener'));
      final events = StreamController<void>();
      // Registered here, so it runs in the body's zone when the stream ends.
      events.stream.listen(
        null,
        onDone: () => container.read(_countProvider.notifier).bump(),
      );
      addTearDown(() async {
        expect(await _failuresDuring(events.close), [isStateError]);
      });
    });

    test('outside a widget test, a provider error still fails it', () {
      Object? caught;
      runZonedGuarded(() {
        final container = appContainer();
        container.listen(
          _countProvider,
          (_, _) => throw StateError('listener'),
        );
        container.read(_countProvider.notifier).bump();
      }, (error, _) => caught = error);
      expect(caught, isStateError);
    });

    test('passes its observers to the container', () {
      final observer = _Adds();
      final container = appContainer(observers: [observer]);
      container.read(_countProvider);
      expect(observer.added, contains(_countProvider));
    });

    test('passes its retry policy to the container', () {
      final asked = <Object>[];
      final container = appContainer(
        retry: (_, error) {
          asked.add(error);
          return null;
        },
      );
      expect(container.read(_downProvider), isA<AsyncError<int>>());
      expect(asked, [isA<_Down>()]);
    });
  });

  group('pumpApp', () {
    testWidgets('mounts a routed screen over the fakes', (tester) async {
      final container = await pumpApp(tester, const _ReadsPorts());
      expect(
        find.text('FakeRepository InMemoryCredentialStore en'),
        findsOneWidget,
      );
      expect(container.read(repositoryProvider), isA<FakeRepository>());
    });

    testWidgets('mounts an unrouted screen over the fakes', (tester) async {
      await pumpApp(tester, const _ReadsPorts(), routed: false);
      expect(
        find.text('FakeRepository InMemoryCredentialStore en'),
        findsOneWidget,
      );
    });

    testWidgets('uses the container it is handed', (tester) async {
      final credentials = _NamedCredentials();
      final container = appContainer(credentials: credentials);
      final returned = await pumpApp(
        tester,
        const _ReadsPorts(),
        container: container,
      );
      expect(returned, same(container));
      expect(find.text('FakeRepository _NamedCredentials en'), findsOneWidget);
    });

    testWidgets('passes the locale to either host', (tester) async {
      await pumpApp(tester, const _ReadsPorts(), locale: const Locale('es'));
      expect(
        find.text('FakeRepository InMemoryCredentialStore es'),
        findsOneWidget,
      );
      await pumpApp(
        tester,
        const _ReadsPorts(),
        routed: false,
        locale: const Locale('es'),
      );
      expect(
        find.text('FakeRepository InMemoryCredentialStore es'),
        findsOneWidget,
      );
    });

    testWidgets('passes a theme to the unrouted host', (tester) async {
      final theme = buildWaxTheme();
      await pumpApp(tester, const _ReadsPorts(), routed: false, theme: theme);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).theme,
        same(theme),
      );
    });

    testWidgets('passes pushed and at to the routed host', (tester) async {
      await pumpApp(tester, const _ReadsPorts());
      var context = tester.element(find.byType(_ReadsPorts));
      expect(Navigator.of(context).canPop(), isFalse);

      await pumpApp(tester, const _ReadsPorts(), pushed: true);
      context = tester.element(find.byType(_ReadsPorts));
      expect(Navigator.of(context).canPop(), isTrue);

      await pumpApp(tester, const _ReadsPorts(), at: '/somewhere');
      context = tester.element(find.byType(_ReadsPorts));
      expect(GoRouterState.of(context).uri.path, '/somewhere');
    });
  });

  group('mountApp', () {
    testWidgets('mounts the screen without settling', (tester) async {
      await mountApp(tester, const _ReadsPorts(), routed: false);
      expect(
        find.text('FakeRepository InMemoryCredentialStore en'),
        findsOneWidget,
      );
    });

    testWidgets('refuses pushed and at without a router', (tester) async {
      await expectLater(
        mountApp(tester, const _ReadsPorts(), routed: false, pushed: true),
        throwsAssertionError,
      );
      await expectLater(
        mountApp(tester, const _ReadsPorts(), routed: false, at: '/x'),
        throwsAssertionError,
      );
    });

    testWidgets('refuses a theme on the routed host', (tester) async {
      await expectLater(
        mountApp(tester, const _ReadsPorts(), theme: buildWaxTheme()),
        throwsAssertionError,
      );
    });

    testWidgets('takes its container down with its tree, timers and all', (
      tester,
    ) async {
      final container = appContainer();
      await mountApp(
        tester,
        const _HoldsTimer(),
        container: container,
        routed: false,
      );
      final timer = container.read(_timerProvider);
      expect(timer.isActive, isTrue);

      await tester.pumpWidget(const SizedBox());
      expect(timer.isActive, isFalse);
    });

    testWidgets('leaving the screen keeps its container, still the tree\'s', (
      tester,
    ) async {
      final container = appContainer();
      await mountApp(
        tester,
        const _HoldsTimer(),
        container: container,
        routed: false,
      );
      final timer = container.read(_timerProvider);

      await leaveScreen(tester, container);
      expect(find.byType(_HoldsTimer), findsNothing);
      expect(timer.isActive, isTrue);

      await tester.pumpWidget(const SizedBox());
      expect(timer.isActive, isFalse);
    });

    testWidgets('keeps its container across a remount over it', (tester) async {
      final container = appContainer();
      await mountApp(
        tester,
        const _ShowsDoubled(),
        container: container,
        routed: false,
      );
      container.read(_countProvider.notifier).bump();

      await mountApp(tester, const _ShowsDoubled(), container: container);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('gives a second container a working scope where the first '
        'was', (tester) async {
      await mountApp(tester, const _ShowsDoubled(), routed: false);
      final second = appContainer();
      await mountApp(
        tester,
        const _ShowsDoubled(),
        container: second,
        routed: false,
      );

      second.read(_countProvider.notifier).bump();
      await tester.pump();
      expect(find.text('2'), findsOneWidget);
    });

    // Mounts a screen over [container] that moves a provider in a build
    // once the count moves, and expects Riverpod to refuse.
    Future<void> mountKeepsCheck(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      await mountApp(
        tester,
        const _MovesInBuild(),
        container: container,
        routed: false,
      );

      container.read(_countProvider.notifier).bump();
      await tester.pump();
      expect(
        tester.takeException(),
        isA<FlutterError>().having(
          (error) => error.message,
          'message',
          contains('modify a provider while the widget tree was building'),
        ),
      );
    }

    // A scope mounted by hand over [container], which never disposes it.
    Future<void> mountByHand(
      WidgetTester tester,
      ProviderContainer container,
    ) => tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SizedBox()),
    );

    // [first] mounts a scope, then a second container takes its place.
    Future<void> swapKeepsCheck(
      WidgetTester tester,
      Future<void> Function() first,
    ) async {
      await first();
      await mountKeepsCheck(tester, appContainer());
    }

    testWidgets(
      'a second container keeps the check on a provider moved in a build',
      (tester) => swapKeepsCheck(
        tester,
        () => mountApp(tester, const SizedBox(), routed: false),
      ),
    );

    testWidgets(
      'a second container keeps the check where the first scope was mounted '
      'by hand',
      (tester) =>
          swapKeepsCheck(tester, () => mountByHand(tester, appContainer())),
    );

    testWidgets(
      'the same container keeps the check where its scope was mounted by hand',
      (tester) async {
        final container = appContainer();
        await mountByHand(tester, container);

        await mountKeepsCheck(tester, container);
      },
    );

    testWidgets('keeps its container across a remount over a screen with a '
        'scope of its own', (tester) async {
      final container = appContainer();
      const screen = ProviderScope(child: _HoldsTimer());
      await mountApp(tester, screen, container: container, routed: false);
      final timer = container.read(_timerProvider);

      await mountApp(tester, screen, container: container, routed: false);
      expect(timer.isActive, isTrue);
    });

    testWidgets('leaving refuses a container that is not the mounted one', (
      tester,
    ) async {
      final container = appContainer();
      await mountApp(
        tester,
        const _HoldsTimer(),
        container: container,
        routed: false,
      );
      final timer = container.read(_timerProvider);

      await expectLater(
        () => leaveScreen(tester, appContainer()),
        throwsAssertionError,
      );
      expect(timer.isActive, isTrue);
    });
  });

  group('pumpWholeApp', () {
    testWidgets('mounts the app over the container it is handed, settled', (
      tester,
    ) async {
      final container = appContainer();
      final returned = await pumpWholeApp(tester, container: container);
      expect(returned, same(container));
      expect(
        ProviderScope.containerOf(tester.element(find.byType(WaxDeckApp))),
        same(container),
      );
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('takes its container down with its tree', (tester) async {
      final container = await pumpWholeApp(tester);
      final timer = container.read(_timerProvider);

      await tester.pumpWidget(const SizedBox());
      expect(timer.isActive, isFalse);
    });

    testWidgets('turns animations off when asked, at the view\'s size', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      MediaQueryData query() =>
          MediaQuery.of(tester.element(find.byType(WaxDeckApp)));

      await pumpWholeApp(tester);
      expect(query().disableAnimations, isFalse);

      await pumpWholeApp(tester, disableAnimations: true);
      expect(query().disableAnimations, isTrue);
      expect(query().size, const Size(1000, 600));

      // The view's own query stays live under it: a window resized after
      // the mount is the size the app sees.
      tester.view.physicalSize = const Size(400, 800);
      await tester.pump();
      expect(query().size, const Size(400, 800));
      expect(query().disableAnimations, isTrue);
    });
  });

  group('mountHost', () {
    testWidgets('mounts a host of the test\'s own, the tree owning its '
        'container', (tester) async {
      final container = appContainer();
      await mountHost(
        tester,
        const Directionality(
          textDirection: TextDirection.ltr,
          child: _HoldsTimer(),
        ),
        container: container,
      );
      final timer = container.read(_timerProvider);
      expect(find.byType(_HoldsTimer), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      expect(timer.isActive, isFalse);
    });
  });

  group('pumpPlayerInto', () {
    testWidgets('takes the player\'s container down with its tree', (
      tester,
    ) async {
      final harness = PlayerHarness(appContainer());
      await pumpPlayerInto(tester, harness);
      final timer = harness.container.read(_timerProvider);

      await tester.pumpWidget(const SizedBox());
      expect(timer.isActive, isFalse);
    });
  });
}

/// A settings store implementing the port itself, as a test's own does.
class _OwnSettings implements ClientSettingsStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  ({String? value})? peek(String key) => null;

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> remove(String key) async {}
}

/// A credential store a test can tell apart by its type.
class _NamedCredentials extends InMemoryCredentialStore {}
