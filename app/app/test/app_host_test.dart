import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/client_settings_providers.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'app_host.dart';
import 'fakes.dart';

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
