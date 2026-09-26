import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/artwork/artwork_store.dart';
import 'package:waxdeck/src/auth/connect_server_screen.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/auth/server_address.dart';
import 'package:waxdeck/src/downloads/downloads_controller.dart';
import 'package:waxdeck/src/downloads/download_notices.dart';
import 'package:waxdeck/src/l10n/off_tree.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

void main() {
  const health = ServerHealth(status: 'ok', version: 'test', apiVersion: 1);

  Widget host({
    required CredentialStorePort store,
    required Future<ServerHealth> Function(String) probe,
  }) => ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(FakeRepository()),
      credentialStoreProvider.overrideWithValue(store),
      bootServerAddressProvider.overrideWithValue(null),
      serverProbeProvider.overrideWithValue(probe),
    ],
    child: routedHost(const ConnectServerScreen()),
  );

  testWidgets('a reachable address is adopted and the token dropped', (
    tester,
  ) async {
    final store = InMemoryCredentialStore()..token = 'stale-token';
    final probed = <String>[];
    await tester.pumpWidget(
      host(
        store: store,
        probe: (base) async {
          probed.add(base);
          if (base == 'http://wax.example.com') return health;
          throw const WaxDeckApiException(
            code: 'transport',
            message: 'no route',
          );
        },
      ),
    );
    await tester.enterText(
      find.byKey(const Key(SemanticsIds.connectServerAddress)),
      'wax.example.com',
    );
    await tester.tap(find.byKey(const Key(SemanticsIds.connectServerSubmit)));
    await tester.pumpAndSettle();

    // https was tried first and refused; http answered and won.
    expect(probed, ['https://wax.example.com', 'http://wax.example.com']);
    expect(store.serverAddress, 'http://wax.example.com');
    expect(
      store.token,
      isNull,
      reason: 'a token minted elsewhere is never presented to this server',
    );
  });

  testWidgets('an unreachable address reports and adopts nothing', (
    tester,
  ) async {
    final store = InMemoryCredentialStore();
    await tester.pumpWidget(
      host(
        store: store,
        probe: (_) async => throw const WaxDeckApiException(
          code: 'transport-timeout',
          message: 'timed out',
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key(SemanticsIds.connectServerAddress)),
      'wax.example.com',
    );
    await tester.tap(find.byKey(const Key(SemanticsIds.connectServerSubmit)));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key(SemanticsIds.connectServerError)),
      findsOneWidget,
    );
    expect(store.serverAddress, isNull);
  });

  testWidgets('junk is refused before any probe fires', (tester) async {
    var probes = 0;
    await tester.pumpWidget(
      host(
        store: InMemoryCredentialStore(),
        probe: (_) async {
          probes++;
          return health;
        },
      ),
    );
    await tester.enterText(
      find.byKey(const Key(SemanticsIds.connectServerAddress)),
      'not an address',
    );
    await tester.tap(find.byKey(const Key(SemanticsIds.connectServerSubmit)));
    await tester.pumpAndSettle();

    expect(probes, 0);
    expect(
      find.byKey(const Key(SemanticsIds.connectServerError)),
      findsOneWidget,
    );
  });
  testWidgets('forgetting is offered only for a stored address', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(store: InMemoryCredentialStore(), probe: (_) async => health),
    );

    expect(
      find.byKey(const Key(SemanticsIds.connectServerForget)),
      findsNothing,
    );
  });

  testWidgets('forget wipes the mirror, downloads and artwork and drops the '
      'address', (tester) async {
    const address = 'http://wax.example.com';
    final store = InMemoryCredentialStore()
      ..token = 'token'
      ..serverAddress = address;
    final db = inMemoryMirrorDatabase();
    addTearDown(db.close);
    await db
        .into(db.mirrorItems)
        .insert(
          MirrorItemsCompanion.insert(
            pid: 'tr-A',
            ulid: 'A',
            mediaType: 'music',
            title: 'Alpha',
            durationMs: 1000,
            sortKey: 'alpha',
          ),
        );
    final dir = Directory.systemTemp.createTempSync('waxdeck-forget');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/e.flac')..writeAsStringSync('bytes');
    await db
        .into(db.downloadRecords)
        .insert(
          DownloadRecordsCompanion.insert(
            pid: 'tr-A',
            fileIndex: 0,
            essenceHash: 'e',
            etag: '1',
            fileName: 'e.flac',
            localPath: file.path,
            sizeBytes: 1,
            state: 'complete',
          ),
        );
    final downloads = BackgroundDownloadManager(
      db: db,
      repository: FakeRepository.new,
      engine: _NoTransfers(),
      copy: () => downloadCopy(l10nFor(const [Locale('en')])),
    );
    addTearDown(downloads.dispose);
    final artwork = FakeArtworkStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(FakeRepository()),
          credentialStoreProvider.overrideWithValue(store),
          bootServerAddressProvider.overrideWithValue(address),
          serverProbeProvider.overrideWithValue((_) async => health),
          mirrorDatabaseProvider.overrideWithValue(db),
          downloadManagerProvider.overrideWithValue(downloads),
          artworkStoreProvider.overrideWithValue(artwork),
        ],
        child: routedHost(const ConnectServerScreen()),
      ),
    );

    await tester.tap(find.byKey(const Key(SemanticsIds.connectServerForget)));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key(SemanticsIds.connectServerForgetConfirm)),
    );
    // The unlink is real IO, which fake time does not wait for.
    for (var i = 0; i < 100 && store.serverAddress != null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(
      file.existsSync(),
      isFalse,
      reason: 'its bytes go before its record',
    );
    expect(artwork.unpinned, ['tr-A']);
    expect(artwork.forgotten, 1);
    expect(await db.select(db.mirrorItems).get(), isEmpty);
    expect(store.serverAddress, isNull);
    expect(store.token, isNull);
    expect(
      find.byKey(const Key(SemanticsIds.connectServerForget)),
      findsNothing,
    );
    final field = tester.widget<TextField>(
      find.byKey(const Key(SemanticsIds.connectServerAddress)),
    );
    expect(field.controller!.text, isEmpty);
  });
  group('forgetting', () {
    const address = 'http://wax.example.com';
    late InMemoryCredentialStore store;
    late MirrorDatabase db;
    late Directory dir;

    setUp(() {
      store = InMemoryCredentialStore()
        ..token = 'token'
        ..serverAddress = address;
      db = inMemoryMirrorDatabase();
      dir = Directory.systemTemp.createTempSync('waxdeck-forget');
    });

    tearDown(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });

    Future<File> held(String pid) async {
      final file = File('${dir.path}/$pid.flac')..writeAsStringSync('bytes');
      await db
          .into(db.downloadRecords)
          .insert(
            DownloadRecordsCompanion.insert(
              pid: pid,
              fileIndex: 0,
              essenceHash: pid,
              etag: '1',
              fileName: '$pid.flac',
              localPath: file.path,
              sizeBytes: 1,
              state: 'complete',
            ),
          );
      return file;
    }

    BackgroundDownloadManager manager() {
      final downloads = BackgroundDownloadManager(
        db: db,
        repository: FakeRepository.new,
        engine: _NoTransfers(),
        copy: () => downloadCopy(l10nFor(const [Locale('en')])),
      );
      addTearDown(downloads.dispose);
      return downloads;
    }

    var probes = 0;

    Future<ProviderContainer> pump(
      WidgetTester tester, {
      required DownloadManagerPort downloads,
      ArtworkStore? artwork,
    }) async {
      probes = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(FakeRepository()),
            credentialStoreProvider.overrideWithValue(store),
            bootServerAddressProvider.overrideWithValue(address),
            serverProbeProvider.overrideWithValue((_) async {
              probes++;
              return health;
            }),
            mirrorDatabaseProvider.overrideWithValue(db),
            downloadManagerProvider.overrideWithValue(downloads),
            artworkStoreProvider.overrideWithValue(
              artwork ?? FakeArtworkStore(),
            ),
          ],
          child: routedHost(const ConnectServerScreen()),
        ),
      );
      return ProviderScope.containerOf(
        tester.element(find.byType(ConnectServerScreen)),
      );
    }

    /// Confirms a forget and lets its real file IO run out.
    Future<void> confirm(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key(SemanticsIds.connectServerForget)));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key(SemanticsIds.connectServerForgetConfirm)),
      );
      for (var i = 0; i < 100 && store.serverAddress != null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    testWidgets('reaches a download the listing had not seen', (tester) async {
      final first = await held('tr-A');
      final container = await pump(tester, downloads: manager());
      await tester.runAsync(() => container.read(downloadsProvider.future));
      final second = await held('tr-B');

      await confirm(tester);

      expect(first.existsSync(), isFalse);
      expect(second.existsSync(), isFalse);
    });

    testWidgets('clears pinned covers while their records remain', (
      tester,
    ) async {
      await held('tr-A');
      await db
          .into(db.artworkPins)
          .insert(
            ArtworkPinsCompanion.insert(
              pid: 'tr-A',
              sizePx: 256,
              artUrl: '/art',
              etag: '1',
              localPath: '${dir.path}/art',
              sizeBytes: 1,
              pinnedAt: DateTime.utc(2026, 9, 26),
            ),
          );
      final artwork = _PinCountingArtwork(db);
      await pump(tester, downloads: manager(), artwork: artwork);

      await confirm(tester);

      expect(artwork.pinsAtForget, 1);
    });

    testWidgets('nothing else can be asked while it runs', (tester) async {
      final downloads = FakeDownloads(
        items: const [
          DownloadedItem(pid: 'tr-A', sizeBytes: 1, files: 1, complete: true),
        ],
      )..removeGate = Completer<void>();
      addTearDown(downloads.dispose);
      await pump(tester, downloads: downloads);

      await tester.tap(find.byKey(const Key(SemanticsIds.connectServerForget)));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key(SemanticsIds.connectServerForgetConfirm)),
      );
      await tester.pump();
      await tester.pump();

      final connect = tester.widget<FilledButton>(
        find.byKey(const Key(SemanticsIds.connectServerSubmit)),
      );
      final forget = tester.widget<WaxButton>(
        find.byKey(const Key(SemanticsIds.connectServerForget)),
      );
      expect(connect.onPressed, isNull);
      expect(forget.onPressed, isNull);
      await tester.showKeyboard(
        find.byKey(const Key(SemanticsIds.connectServerAddress)),
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(probes, 0, reason: 'the field submits past the button');
      downloads.removeGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a forget that fails says so and keeps the address', (
      tester,
    ) async {
      final downloads = FakeDownloads(
        items: const [
          DownloadedItem(pid: 'tr-A', sizeBytes: 1, files: 1, complete: true),
        ],
      )..removeError = const WaxDeckApiException(code: 'io', message: 'busy');
      addTearDown(downloads.dispose);
      await pump(tester, downloads: downloads);

      await tester.tap(find.byKey(const Key(SemanticsIds.connectServerForget)));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key(SemanticsIds.connectServerForgetConfirm)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key(SemanticsIds.connectServerError)),
        findsOneWidget,
      );
      expect(store.serverAddress, address);
    });
  });
}

/// Counts the pin records left when the covers are forgotten, which is
/// how the real store finds the files to delete.
class _PinCountingArtwork extends FakeArtworkStore {
  _PinCountingArtwork(this.db);

  final MirrorDatabase db;
  int? pinsAtForget;

  @override
  Future<void> forgetEverything() async {
    pinsAtForget = (await db.select(db.artworkPins).get()).length;
    await super.forgetEverything();
  }
}

/// An engine with nothing in flight, under the real manager.
class _NoTransfers implements TransferEnginePort {
  @override
  Stream<TransferEvent> get events => const Stream<TransferEvent>.empty();

  @override
  Future<List<TrackedTransfer>> trackedTransfers() async => const [];

  @override
  Future<void> recover() async {}

  @override
  Future<void> describe(TransferGroup group) async {}

  @override
  Future<String> start(TransferRequest request) async => 'task';

  @override
  Future<bool> pause(String taskId) async => false;

  @override
  Future<void> resume(String taskId, {String? url, DateTime? staleAt}) async {}

  @override
  Future<void> cancel(List<String> taskIds) async {}

  @override
  Future<NotificationPermission> notificationPermission() async =>
      NotificationPermission.granted;

  @override
  Future<NotificationPermission> requestNotificationPermission() async =>
      NotificationPermission.granted;

  @override
  void dispose() {}
}
