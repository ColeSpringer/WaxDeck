import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart'
    show CacheManager, HttpExceptionWithStatus;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waxdeck/src/artwork/artwork_palette.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart'
    show pinRefreshGate, serverReachable;
import 'package:waxdeck/src/artwork/artwork_store.dart'
    show ReplacedCovers, kOfflineArtworkRungs;
import 'package:waxdeck/src/artwork/artwork_store_io.dart';
import 'package:waxdeck/src/artwork/pin_refresh.dart';
import 'package:waxdeck/src/connectivity/connectivity_port.dart';
import 'package:waxdeck/src/downloads/wifi_only_gate.dart';
import 'package:waxdeck/src/providers.dart' show connectivityProvider;
import 'package:waxdeck/src/settings/client_prefs.dart'
    show downloadsOnWifiOnlyProvider;
import 'package:waxdeck/src/sync/sync_binder.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'artwork_fixtures.dart';
import 'fakes.dart';

const _base = 'http://deck.local:4420';
const _pid = 'tr-01JZX5N8QW3F4V9T2B7KD3M9R6';
const _art = '$_base/api/v1/items/$_pid/art';
const _station = 'https://logos.example.net/coastal-fm.png';

/// The reach the app hands its store.
final _reach = Provider<bool Function()>(serverReachable);

/// The gate the app hands its store.
final _appGate = Provider<TransferGate>(pinRefreshGate);

/// The native store, in a directory of its own.
///
/// The disk cache is stubbed and nothing else is: files are really
/// written, the pin rows are a real database, and the fetches the server
/// does not answer fail the way an unreachable server fails. The cache
/// is stubbed because what these tests are about is the layers under it
/// what draws when it cannot answer - and because the real one opens
/// its own store asynchronously, which races a temporary directory being
/// taken away at the end of a test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late MirrorDatabase db;
  late DriftArtworkPinStore pins;
  late FakeArtServer server;
  late CachedArtworkStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('waxdeck-artwork');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall call) async => temp.path,
        );
    db = inMemoryMirrorDatabase();
    // A cover is only pinned for an item the device has downloaded.
    await db
        .into(db.downloadRecords)
        .insert(
          DownloadRecordsCompanion.insert(
            pid: _pid,
            fileIndex: 0,
            essenceHash: 'essence',
            etag: '1-1',
            fileName: 'track.flac',
            localPath: '/downloads/track.flac',
            sizeBytes: 1024,
            state: 'complete',
          ),
        );
    pins = DriftArtworkPinStore(db);
    server = FakeArtServer();
    store = CachedArtworkStore(
      baseUrl: _base,
      pins: pins,
      token: () => 'secret-token',
      client: Dio()..httpClientAdapter = server,
      pinDirectory: temp,
      cache: FakeArtCache(),
      reachable: () => true,
    );
  });

  tearDown(() async {
    store.dispose();
    await db.close();
    await temp.delete(recursive: true);
  });

  test('downloading an item keeps a cover big enough for a player and one '
      'for a grid', () async {
    server.serve('$_art?size=1024', 'hero bytes', etag: '"cover-1024"');
    server.serve('$_art?size=256', 'cell bytes', etag: '"cover-256"');

    await store.pinForOffline(_pid, _art);

    final held = await pins.pinsFor(_pid);
    expect(held.map((p) => p.sizePx), <int>[1024, 256]);
    expect(held.first.etag, '"cover-1024"');
    expect(held.first.artUrl, _art);
    expect(File(held.first.localPath).readAsStringSync(), 'hero bytes');
    expect(File(held.last.localPath).readAsStringSync(), 'cell bytes');
    // Written through a temporary and renamed, so nothing is left half
    // written under a name a pin row points at.
    expect(
      temp
          .listSync()
          .map((e) => p.basename(e.path))
          .where((name) => name.endsWith('.part')),
      isEmpty,
    );
    // The credential goes with the request. A native build that fetched
    // artwork without one is the bug this store exists to fix.
    expect(server.headersFor('$_art?size=1024')['Authorization'], [
      'Bearer secret-token',
    ]);
  });

  test(
    're-pinning presents the validator and keeps the bytes it has',
    () async {
      server.serve('$_art?size=1024', 'hero bytes', etag: '"cover-1024"');
      server.serve('$_art?size=256', 'cell bytes', etag: '"cover-256"');
      await store.pinForOffline(_pid, _art);

      server.serveNotModified('$_art?size=1024');
      server.serveNotModified('$_art?size=256');
      await store.pinForOffline(_pid, _art);

      expect(server.headersFor('$_art?size=1024')['If-None-Match'], [
        '"cover-1024"',
      ]);
      final held = await pins.pinsFor(_pid);
      expect(held, hasLength(2));
      expect(held.first.etag, '"cover-1024"');
      expect(File(held.first.localPath).readAsStringSync(), 'hero bytes');
    },
  );

  test(
    'a pin whose file is gone is fetched again rather than revalidated',
    () async {
      server.serve('$_art?size=1024', 'hero bytes', etag: '"cover-1024"');
      server.serve('$_art?size=256', 'cell bytes', etag: '"cover-256"');
      await store.pinForOffline(_pid, _art);
      File((await pins.pinsFor(_pid)).first.localPath).deleteSync();

      server.serve('$_art?size=1024', 'hero again', etag: '"cover-1024b"');
      await store.pinForOffline(_pid, _art);

      // No validator: presenting one against bytes that are gone would
      // answer 304 and leave the row pointing at nothing.
      expect(
        server.headersFor('$_art?size=1024').containsKey('If-None-Match'),
        isFalse,
      );
      final held = await pins.pinsFor(_pid);
      expect(File(held.first.localPath).readAsStringSync(), 'hero again');
    },
  );

  test('with the server unreachable, a pinned cover is what draws', () async {
    server.serve('$_art?size=1024', 'hero bytes', etag: '"cover-1024"');
    server.serve('$_art?size=256', 'cell bytes', etag: '"cover-256"');
    await store.pinForOffline(_pid, _art);

    // Nothing answers now: the cache has never seen this item, and the
    // fetch behind it fails. The pin is the only copy there is.
    final drawn = await store.bytesFor(_art, 300);
    expect(utf8.decode(drawn!), 'hero bytes');

    // A small draw takes the small pin: the point of keeping two.
    expect(utf8.decode((await store.bytesFor(_art, 100))!), 'cell bytes');
    // A draw bigger than anything pinned takes the biggest there is.
    expect(utf8.decode((await store.bytesFor(_art, 2000))!), 'hero bytes');
  });

  group('out of reach', () {
    var reach = false;
    late FakeArtCache cache;
    late CachedArtworkStore away;

    setUp(() async {
      server.serve('$_art?size=1024', 'hero bytes', etag: '"cover-1024"');
      server.serve('$_art?size=256', 'cell bytes', etag: '"cover-256"');
      await store.pinForOffline(_pid, _art);
      server.requested.clear();
      reach = false;
      cache = FakeArtCache();
      away = CachedArtworkStore(
        baseUrl: _base,
        pins: pins,
        token: () => 'secret-token',
        client: Dio()..httpClientAdapter = server,
        pinDirectory: temp,
        cache: cache,
        reachable: () => reach,
      );
    });
    tearDown(() => away.dispose());

    test('a pinned cover is read from its pin and nothing is asked', () async {
      expect(utf8.decode((await away.bytesFor(_art, 300))!), 'hero bytes');
      expect(utf8.decode((await away.bytesFor(_art, 100))!), 'cell bytes');
      // A fetch nobody can answer only holds the row on its placeholder
      // for as long as the connect hangs.
      expect(cache.asked, isEmpty, reason: "not even the disk cache's fetch");
      expect(server.requested, isEmpty);
    });

    test('a cached copy of the size asked for is what draws, ahead of the '
        'pin, and nothing is asked', () async {
      // Fetched since the pin was last refreshed, so the newer of the two.
      await cache.hold('$_art?size=512', utf8.encode('fetched since'));

      expect(utf8.decode((await away.bytesFor(_art, 300))!), 'fetched since');
      // No copy at this rung: the pin.
      expect(utf8.decode((await away.bytesFor(_art, 100))!), 'cell bytes');
      expect(cache.asked, isEmpty);
      expect(server.requested, isEmpty);
    });

    test('a pin that cannot be read leaves the draw to the fetch', () async {
      final unread = CachedArtworkStore(
        baseUrl: _base,
        pins: _UnreadablePinStore(pins),
        client: Dio()..httpClientAdapter = server,
        pinDirectory: temp,
        cache: cache,
        reachable: () => reach,
      );
      addTearDown(unread.dispose);
      cache.serve('$_art?size=512', utf8.encode('fetched'));

      expect(utf8.decode((await unread.bytesFor(_art, 300))!), 'fetched');
      expect(cache.asked, ['$_art?size=512']);
    });

    test('the native factory hands the store its reach', () async {
      final made = createArtworkStore(
        baseUrl: _base,
        pins: pins,
        reachable: () => reach,
        cache: cache,
      );
      addTearDown(made.dispose);

      expect(made, isA<CachedArtworkStore>());
      expect(utf8.decode((await made.bytesFor(_art, 300))!), 'hero bytes');
      expect(cache.asked, isEmpty);
      reach = true;
      await made.bytesFor(_art, 300);
      expect(cache.asked, ['$_art?size=512']);
    });

    test('a summary hydrated after the server moved address names this '
        'one: its pin draws, and in reach this server is asked', () async {
      await db
          .into(db.mirrorItems)
          .insert(
            MirrorItemsCompanion.insert(
              pid: _pid,
              ulid: _pid.substring(3),
              mediaType: 'music',
              title: 'Salt Harbour',
              durationMs: 60000,
              sortKey: 'salt harbour',
            ),
          );
      // Pinned while the server was at another address.
      for (final pin in await pins.pinsFor(_pid)) {
        await pins.put(
          ArtworkPinRecord(
            pid: pin.pid,
            sizePx: pin.sizePx,
            artUrl: 'http://old.local:4420/api/v1/items/$_pid/art',
            etag: pin.etag,
            localPath: pin.localPath,
            sizeBytes: pin.sizeBytes,
            pinnedAt: pin.pinnedAt,
          ),
        );
      }

      final item = await mirrorItemByPid(
        db,
        _pid,
        artUrlFor: (pid) => '$_base/api/v1/items/$pid/art',
      );
      expect(item!.artUrl, _art);
      expect(
        utf8.decode((await away.bytesFor(item.artUrl!, 300))!),
        'hero bytes',
      );
      expect(cache.asked, isEmpty);
      reach = true;
      await away.bytesFor(item.artUrl!, 300);
      expect(cache.asked, ['$_art?size=512']);
      expect(server.requested, isEmpty, reason: 'nothing of the old address');
    });

    test('a cover replaced while the pin walk waits at its gate draws the '
        'copy fetched since, once the socket drops', () async {
      // Wifi-only downloads on mobile data: the frame names the cover,
      // what is on screen is fetched again, and the pin stays as it was.
      final old = await artPng(40);
      final fresh = await artPng(24);
      for (final rung in <int>[1024, 256]) {
        server.serveBytes('$_art?size=$rung', old, etag: '"40-$rung"');
      }
      await store.pinForOffline(_pid, _art);
      server.requested.clear();
      cache.serve('$_art?size=128', fresh);
      final gated = CachedArtworkStore(
        baseUrl: _base,
        pins: pins,
        client: Dio()..httpClientAdapter = server,
        pinDirectory: temp,
        cache: cache,
        pinGate: _Gate()..open = false,
        reachable: () => reach,
      );
      addTearDown(gated.dispose);
      reach = true;
      await gated.evict(_art);
      await gated.settled;
      final shown = gated.imageFor(_art, 96)!;
      addTearDown(shown.evict);
      expect((await _resolve(shown)).image.width, 24);
      expect(server.requested, isEmpty, reason: 'the walk waits');

      reach = false;
      cache.asked.clear();
      // Another surface, at another size of the same rung.
      final again = gated.imageFor(_art, 128)!;
      addTearDown(again.evict);
      expect((await _resolve(again)).image.width, 24);
      expect(cache.asked, isEmpty);
      expect((await pins.pinsFor(_pid)).map((pin) => pin.etag), [
        '"40-1024"',
        '"40-256"',
      ], reason: 'the pin is still the old cover');
    });

    test('reach returning names anew a cover drawn off a pin still owed its '
        'refresh, and not one drawn from the server', () async {
      cache.serve('$_art?size=128', utf8.encode('fetched'));
      final gated = CachedArtworkStore(
        baseUrl: _base,
        pins: pins,
        client: Dio()..httpClientAdapter = server,
        pinDirectory: temp,
        cache: cache,
        pinGate: _Gate()..open = false,
        reachable: () => reach,
      );
      addTearDown(gated.dispose);
      reach = true;
      await gated.evict(_art);
      await gated.settled;
      expect(utf8.decode((await gated.bytesFor(_art, 128))!), 'fetched');
      final shown = gated.imageFor(_art, 128);

      // Every reconnect on mobile data would fetch it once more.
      gated.serverReached();
      await pumpEventQueue();
      expect(gated.imageFor(_art, 128), shown);

      // At a size the cache holds no copy of, the socket down: the pin.
      reach = false;
      expect(utf8.decode((await gated.bytesFor(_art, 300))!), 'hero bytes');
      reach = true;
      gated.serverReached();
      await pumpEventQueue();
      expect(gated.imageFor(_art, 128), isNot(shown));
    });

    test('a tint read off a pin is read again off the new bytes once the '
        'store names the cover anew', () async {
      final red = await artPng(40, 40, const Color(0xFFC0392B));
      final blue = await artPng(40, 40, const Color(0xFF2B4FCB));
      for (final rung in <int>[1024, 256]) {
        server.serveBytes('$_art?size=$rung', red, etag: '"red-$rung"');
      }
      await store.pinForOffline(_pid, _art);
      final container = appContainer(artwork: away);
      addTearDown(container.dispose);
      Future<WaxPalette?> tint() async {
        container.invalidate(artworkPaletteProvider(_art));
        final read = container.listen(
          artworkPaletteProvider(_art).future,
          (_, _) {},
        );
        try {
          return await read.read();
        } finally {
          read.close();
        }
      }

      final before = await tint();
      expect(before, extractPalette(await decodeArtworkPixels(red)));

      // The item downloaded again, its cover replaced since: the store
      // rewrites the pin and names anew the cover drawn off it.
      for (final rung in <int>[1024, 256]) {
        server.serveBytes('$_art?size=$rung', blue, etag: '"blue-$rung"');
      }
      await away.pinForOffline(_pid, _art);
      final after = extractPalette(await decodeArtworkPixels(blue));
      expect(after, isNot(before));
      expect(await tint(), after);
    });

    test('a warm ahead of a scroll asks nothing either', () async {
      // The disk cache fetches a few at a time, so warms hung on a server
      // nobody can reach would hold up the draws behind them.
      await away.warm(_art, 300);
      await away.warm(
        '$_base/api/v1/items/tr-01JZX5N8QW3F4V9T2B7KDOTHER1/art',
        300,
      );
      expect(cache.asked, isEmpty);
    });

    test('in reach, the network is asked first and the pin is what is left '
        'when it cannot answer', () async {
      reach = true;
      expect(utf8.decode((await away.bytesFor(_art, 300))!), 'hero bytes');
      expect(cache.asked, ['$_art?size=512']);
    });

    test('an item with nothing pinned is asked for as before', () async {
      const other = '$_base/api/v1/items/tr-01JZX5N8QW3F4V9T2B7KDOTHER1/art';
      expect(await away.bytesFor(other, 300), isNull);
      expect(cache.asked, ['$other?size=512']);
    });

    test('a cold start, before the first connect has answered, is out of '
        'reach', () async {
      final sync = SyncEngine(
        db: db,
        repository: FakeRepository(),
        channelFactory: _UnansweredChannel.new,
      );
      addTearDown(sync.dispose);
      final container = appContainer(sync: sync, mirror: db);
      addTearDown(container.dispose);
      final reachable = container.read(_reach);
      final cold = CachedArtworkStore(
        baseUrl: _base,
        pins: pins,
        client: Dio()..httpClientAdapter = server,
        pinDirectory: temp,
        cache: cache,
        reachable: reachable,
      );
      addTearDown(cold.dispose);

      expect(reachable(), isFalse, reason: 'the engine has not started');
      await sync.start();
      expect(sync.current.connection, SyncConnection.connecting);
      expect(reachable(), isFalse);
      expect(utf8.decode((await cold.bytesFor(_art, 300))!), 'hero bytes');
      expect(cache.asked, isEmpty);
      expect(server.requested, isEmpty);
    });
  });

  test('an unpinned item offline has nothing to draw, and says so', () async {
    expect(await store.bytesFor(_art, 300), isNull);
  });

  test('unpinning takes the files with the rows', () async {
    server.serve('$_art?size=1024', 'hero bytes', etag: '"cover-1024"');
    server.serve('$_art?size=256', 'cell bytes', etag: '"cover-256"');
    await store.pinForOffline(_pid, _art);
    final paths = (await pins.pinsFor(_pid)).map((p) => p.localPath).toList();

    await store.unpin(_pid);

    expect(await pins.pinsFor(_pid), isEmpty);
    for (final path in paths) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }
  });

  test('an unpin cut short leaves its rows for the next to finish', () async {
    final killed = _KilledPinStore(pins);
    final cut = CachedArtworkStore(
      baseUrl: _base,
      pins: killed,
      token: () => 'secret-token',
      client: Dio()..httpClientAdapter = server,
      pinDirectory: temp,
      cache: FakeArtCache(),
      reachable: () => true,
    );
    addTearDown(cut.dispose);
    server.serve('$_art?size=1024', 'hero bytes', etag: '"cover-1024"');
    server.serve('$_art?size=256', 'cell bytes', etag: '"cover-256"');
    await cut.pinForOffline(_pid, _art);
    final held = await pins.pinsFor(_pid);

    killed.killNext = true;
    await expectLater(cut.unpin(_pid), throwsStateError);

    // The files went first, so what is left is a row the next unpin can
    // finish, not a file nothing names: an unpin is retried (the free a
    // commit promised is finished at the next start), and a retry can only
    // find what the rows still say.
    for (final pin in held) {
      expect(File(pin.localPath).existsSync(), isFalse, reason: pin.localPath);
    }
    expect(await pins.pinsFor(_pid), hasLength(held.length));

    await cut.unpin(_pid);
    expect(await pins.pinsFor(_pid), isEmpty);
  });

  test('an unpin leaves a cover pinned while it ran, row and file', () async {
    final racing = _PinsBeforeRemoval(pins);
    final cut = CachedArtworkStore(
      baseUrl: _base,
      pins: racing,
      token: () => 'secret-token',
      client: Dio()..httpClientAdapter = server,
      pinDirectory: temp,
      cache: FakeArtCache(),
      reachable: () => true,
    );
    addTearDown(cut.dispose);
    server.serve('$_art?size=1024', 'hero bytes', etag: '"cover-1024"');
    server.serve('$_art?size=256', 'cell bytes', etag: '"cover-256"');
    await cut.pinForOffline(_pid, _art);
    final [hero, cell] = await pins.pinsFor(_pid);
    final larger = File('${temp.path}/larger.img');
    // After the unpin read the pins: the hero is pinned again (fresh bytes
    // under its file name, a later instant) and a size it never held lands.
    racing.before = () async {
      File(hero.localPath).writeAsStringSync('fresh hero');
      larger.writeAsStringSync('larger');
      for (final (size, path) in [(1024, hero.localPath), (512, larger.path)]) {
        await pins.put(
          ArtworkPinRecord(
            pid: _pid,
            sizePx: size,
            artUrl: _art,
            etag: 'since',
            localPath: path,
            sizeBytes: 6,
            pinnedAt: DateTime.utc(2030),
          ),
        );
      }
    };

    await cut.unpin(_pid);

    final held = await pins.pinsFor(_pid);
    expect(held.map((p) => (p.sizePx, p.etag)), [
      (1024, 'since'),
      (512, 'since'),
    ]);
    expect(File(hero.localPath).readAsStringSync(), 'fresh hero');
    expect(larger.readAsStringSync(), 'larger');
    expect(File(cell.localPath).existsSync(), isFalse, reason: 'it was read');
  });

  group('a cover is for an item the device holds and is not freeing', () {
    void serveBoth() {
      server.serve('$_art?size=1024', 'hero bytes', etag: '"cover-1024"');
      server.serve('$_art?size=256', 'cell bytes', etag: '"cover-256"');
    }

    List<File> files() => temp.listSync().whereType<File>().toList();

    test(
      'none is pinned for an item the device holds no download of',
      () async {
        serveBoth();
        await db.delete(db.downloadRecords).go();

        await store.pinForOffline(_pid, _art);

        expect(server.requested, isEmpty, reason: 'nothing is even asked for');
        expect(await pins.pinsFor(_pid), isEmpty);
        expect(files(), isEmpty);
      },
    );

    test('none for an item a commit has promised to free, which is where '
        'a download that landed after the commit pins', () async {
      serveBoth();
      await db.transaction(() => PendingFrees(db).condemn(_pid));

      await store.pinForOffline(_pid, _art);

      expect(server.requested, isEmpty);
      expect(await pins.pinsFor(_pid), isEmpty);
      expect(files(), isEmpty);
      // So the free it was owed still comes, and takes the audio too.
      expect(await PendingFrees(db).due(), [_pid]);
    });

    test('a cover on its way when the item is freed does not land', () async {
      serveBoth();
      server.hold = Completer<void>();
      final pinning = store.pinForOffline(_pid, _art);
      await pumpEventQueue();
      expect(server.requested, isNotEmpty, reason: 'the fetch is out');

      // The free runs and settles while the cover is still coming.
      await db.delete(db.downloadRecords).go();
      server.hold!.complete();
      await pinning;

      expect(await pins.pinsFor(_pid), isEmpty);
      expect(files(), isEmpty);
    });

    test('a cover on its way when a commit promises the free takes itself '
        'back', () async {
      serveBoth();
      server.hold = Completer<void>();
      final pinning = store.pinForOffline(_pid, _art);
      await pumpEventQueue();

      await db.transaction(() => PendingFrees(db).condemn(_pid));
      server.hold!.complete();
      await pinning;

      expect(await pins.pinsFor(_pid), isEmpty);
      expect(files(), isEmpty);
      expect(await PendingFrees(db).due(), [_pid], reason: 'still owed');
    });

    test('a download that finishes after the commit pins nothing, and the '
        'free then leaves nothing behind', () async {
      // Still going when the commit promised the free.
      await (db.update(
        db.downloadRecords,
      )..where((t) => t.pid.equals(_pid))).write(
        const DownloadRecordsCompanion(
          state: Value('pending'),
          localPath: Value(''),
        ),
      );
      await db.transaction(() => PendingFrees(db).condemn(_pid));
      // It lands, and the action that waited on it asks for the cover.
      await (db.update(
        db.downloadRecords,
      )..where((t) => t.pid.equals(_pid))).write(
        const DownloadRecordsCompanion(
          state: Value('complete'),
          localPath: Value('/downloads/track.flac'),
        ),
      );
      serveBoth();

      await store.pinForOffline(_pid, _art);

      expect(server.requested, isEmpty);
      expect(await pins.pinsFor(_pid), isEmpty);
      // The cover being no take-up, the free still comes, and takes the
      // audio; there is no cover of this download for it to leave.
      final owed = (await PendingFrees(db).owed(_pid))!;
      expect(owed.files.map((f) => f.index), [0]);
      await db.delete(db.downloadRecords).go();
      await store.unpinExact(_pid, owed.pins);
      expect(await PendingFrees(db).settle(_pid), isTrue);
      expect(await PendingFrees(db).due(), isEmpty);
      expect(files(), isEmpty);
    });

    test('a cover on its way for an item the device keeps lands', () async {
      serveBoth();
      server.hold = Completer<void>();
      final pinning = store.pinForOffline(_pid, _art);
      await pumpEventQueue();

      server.hold!.complete();
      await pinning;

      expect(await pins.pinsFor(_pid), hasLength(2));
    });
  });

  group('unpinning exactly', () {
    test('takes the covers listed and leaves one pinned since', () async {
      server.serve('$_art?size=1024', 'hero bytes', etag: '"cover-1024"');
      server.serve('$_art?size=256', 'cell bytes', etag: '"cover-256"');
      await store.pinForOffline(_pid, _art);
      final listed = [
        for (final pin in await pins.pinsFor(_pid))
          (sizePx: pin.sizePx, pinnedAt: pin.pinnedAt),
      ];
      // After the list was made, a cover lands for the same item.
      final late = File('${temp.path}/late.img')..writeAsStringSync('late');
      await pins.put(
        ArtworkPinRecord(
          pid: _pid,
          sizePx: 512,
          artUrl: _art,
          etag: 'late',
          localPath: late.path,
          sizeBytes: 4,
          pinnedAt: DateTime.utc(2030),
        ),
      );
      final paths = (await pins.pinsFor(
        _pid,
      )).where((p) => p.sizePx != 512).map((p) => p.localPath).toList();

      await store.unpinExact(_pid, listed);

      expect((await pins.pinsFor(_pid)).map((p) => p.sizePx), [512]);
      expect(late.existsSync(), isTrue);
      for (final path in paths) {
        expect(File(path).existsSync(), isFalse, reason: path);
      }
    });

    test('leaves a size pinned again since, row and file', () async {
      server.serve('$_art?size=1024', 'hero bytes', etag: '"cover-1024"');
      server.serve('$_art?size=256', 'cell bytes', etag: '"cover-256"');
      await store.pinForOffline(_pid, _art);
      final listed = [
        for (final pin in await pins.pinsFor(_pid))
          (sizePx: pin.sizePx, pinnedAt: pin.pinnedAt),
      ];
      // The 1024 cover is pinned again at a later instant: same file name,
      // fresh bytes, and not the cover that was listed.
      final again = (await pins.pinsFor(_pid)).first;
      File(again.localPath).writeAsStringSync('fresh hero');
      await pins.put(
        ArtworkPinRecord(
          pid: _pid,
          sizePx: again.sizePx,
          artUrl: again.artUrl,
          etag: 'fresh',
          localPath: again.localPath,
          sizeBytes: 10,
          pinnedAt: DateTime.utc(2030),
        ),
      );

      await store.unpinExact(_pid, listed);

      final held = await pins.pinsFor(_pid);
      expect(held.map((p) => p.sizePx), [1024]);
      expect(File(held.single.localPath).readAsStringSync(), 'fresh hero');
    });

    test('cut short, leaves its rows for the next to finish', () async {
      final killed = _KilledPinStore(pins);
      final cut = CachedArtworkStore(
        baseUrl: _base,
        pins: killed,
        token: () => 'secret-token',
        client: Dio()..httpClientAdapter = server,
        pinDirectory: temp,
        cache: FakeArtCache(),
        reachable: () => true,
      );
      addTearDown(cut.dispose);
      server.serve('$_art?size=1024', 'hero bytes', etag: '"cover-1024"');
      server.serve('$_art?size=256', 'cell bytes', etag: '"cover-256"');
      await cut.pinForOffline(_pid, _art);
      final held = await pins.pinsFor(_pid);
      final listed = [
        for (final pin in held) (sizePx: pin.sizePx, pinnedAt: pin.pinnedAt),
      ];

      killed.killNext = true;
      await expectLater(cut.unpinExact(_pid, listed), throwsStateError);

      for (final pin in held) {
        expect(
          File(pin.localPath).existsSync(),
          isFalse,
          reason: pin.localPath,
        );
      }
      expect(await pins.pinsFor(_pid), hasLength(held.length));

      await cut.unpinExact(_pid, listed);
      expect(await pins.pinsFor(_pid), isEmpty);
    });
  });

  test('signing out leaves the next account nothing', () async {
    server.serve('$_art?size=1024', 'hero bytes', etag: '"cover-1024"');
    server.serve('$_art?size=256', 'cell bytes', etag: '"cover-256"');
    await store.pinForOffline(_pid, _art);

    await store.forgetEverything();

    expect(await pins.pinsFor(_pid), isEmpty);
    expect(temp.listSync().whereType<File>(), isEmpty);
  });

  test('a cover that cannot be written is not a failed download', () async {
    // This runs beside a download that has already succeeded. A full
    // disk is a monogram, not an exception thrown out of a button.
    final unwritable = CachedArtworkStore(
      baseUrl: _base,
      pins: pins,
      client: Dio()..httpClientAdapter = server,
      pinDirectory: Directory(p.join(temp.path, 'not-there')),
      cache: FakeArtCache(),
      reachable: () => true,
    );
    addTearDown(unwritable.dispose);
    server.serve('$_art?size=1024', 'hero bytes', etag: '"cover-1024"');
    server.serve('$_art?size=256', 'cell bytes', etag: '"cover-256"');

    await unwritable.pinForOffline(_pid, _art);

    expect(await pins.pinsFor(_pid), isEmpty);
  });

  test('a station logo is never pinned and never carries the token', () async {
    server.serve('$_station?size=1024', 'logo');
    await store.pinForOffline('st-1', _station);
    expect(await pins.pinsFor('st-1'), isEmpty);
    expect(server.requested, isEmpty);
  });

  test('a draw is one image-cache entry per URL and painted size', () {
    expect(store.imageFor(_art, 128), store.imageFor(_art, 128));
    expect(store.imageFor(_art, 128), isNot(store.imageFor(_art, 256)));
    expect(store.imageFor(null, 128), isNull);
  });

  test('a replaced cover is another image, so a row holding the old one '
      'draws again', () async {
    // An Image resolves again only when it is handed a provider unequal
    // to the one it holds, and a cover keeps its URL across a change.
    final before = store.imageFor(_art, 128);

    final evicting = store.evict(_art);
    final after = store.imageFor(_art, 128);
    expect(after, isNot(before));
    expect(store.imageFor(_art, 128), after);
    await evicting;

    await store.evictAll();
    expect(store.imageFor(_art, 128), isNot(after));
  });

  test('a pinned cover is decoded to the size it is painted at', () async {
    // Through the pin, which is the only layer this harness can put
    // bytes into: the disk cache fetches with its own HTTP client, and
    // under `flutter test` that client is refused. The pinned copy is a
    // player-sized 640 by 480 and this paints a grid cell, so the
    // decode has real downscaling to do.
    server.serveBytes('$_art?size=1024', await artPng(640, 480));
    server.serveBytes('$_art?size=256', await artPng(160, 120));
    await store.pinForOffline(_pid, _art);

    final hero = store.imageFor(_art, 300)!;
    addTearDown(() => hero.evict());
    final large = await _resolve(hero);
    // 300 steps up to 320, and the 1024 pin is what covers it. Bounded
    // on the longest edge, so a cover that is not square keeps its shape
    // rather than being squashed into the box.
    expect(large.image.width, 320);
    expect(large.image.height, 240);

    final cell = store.imageFor(_art, 128)!;
    addTearDown(() => cell.evict());
    final small = await _resolve(cell);
    // The 256 pin covers this one, and 160 by 120 is already inside a
    // 128 bound on one edge only, so it still comes down.
    expect(small.image.width, 128);
    expect(small.image.height, 96);
  });

  test('an item the server says has no artwork asks nothing further', () async {
    // Every item carries an art URL whether or not it has art, so a
    // library that has not been enriched answers 404 for most of its
    // grid. A stale copy or a pin would draw a cover the server has
    // stopped serving, and looking for one is a database query per
    // paint of every art-less cell.
    server.serveBytes('$_art?size=1024', await artPng(64, 64));
    server.serveBytes('$_art?size=256', await artPng(64, 64));
    await store.pinForOffline(_pid, _art);
    final counting = _CountingPinStore(pins);
    final store404 = CachedArtworkStore(
      baseUrl: _base,
      pins: counting,
      client: Dio()..httpClientAdapter = server,
      pinDirectory: temp,
      cache: _NotFoundCache(),
      reachable: () => true,
    );
    addTearDown(store404.dispose);

    expect(await store404.bytesFor(_art, 128), isNull);
    expect(counting.lookups, 0);
  });

  test('a cover the server says is missing is asked for once, not once '
      'per draw', () async {
    // The other half of the same 404: an index of art-less rows asked
    // per row, and asked again every time it was scrolled back over.
    final cache = _NotFoundCache();
    final store404 = CachedArtworkStore(
      baseUrl: _base,
      pins: pins,
      client: Dio()..httpClientAdapter = server,
      pinDirectory: temp,
      cache: cache,
      reachable: () => true,
    );
    addTearDown(store404.dispose);

    expect(store404.imageFor(_art, 128), isNotNull, reason: 'the first draw');
    expect(await store404.bytesFor(_art, 128), isNull);
    expect(cache.fetches, 1);

    // Now the monogram is the first thing drawn rather than the thing
    // drawn after a round trip - at that rung. Another rung still asks:
    // the server refuses some sizes of a cover it serves whole.
    expect(store404.imageFor(_art, 128), isNull);
    expect(store404.source(_art)!(128), isNull);
    await store404.warm(_art, 128);
    expect(cache.fetches, 1);
    expect(store404.imageFor(_art, 512), isNotNull);
    expect(await store404.bytesFor(_art, 256), isNull);
    expect(cache.fetches, 2);

    // A cover appearing outlives the absence: the invalidation that
    // drops the old bytes drops this too.
    await store404.evict(_art);
    expect(store404.imageFor(_art, 128), isNotNull);
    expect(await store404.bytesFor(_art, 128), isNull);
    expect(cache.fetches, 3);

    // As does signing out.
    await store404.forgetEverything();
    expect(store404.imageFor(_art, 128), isNotNull);
  });

  test('a later launch never asks the disk cache under a name an earlier '
      'one used', () async {
    // The cache's files outlive the process, and a replaced cover's are
    // fetched under a tag: a tag two launches could both mint would
    // answer the second replacement with the first one's bytes.
    var at = DateTime.utc(2026, 11, 18, 12);
    final cache = FakeArtCache();
    CachedArtworkStore launch() {
      final launched = CachedArtworkStore(
        baseUrl: _base,
        pins: pins,
        client: Dio()..httpClientAdapter = server,
        pinDirectory: temp,
        cache: cache,
        replaced: ReplacedCovers(now: () => at),
        reachable: () => true,
      );
      addTearDown(launched.dispose);
      return launched;
    }

    final first = launch();
    await first.evict(_art);
    await first.bytesFor(_art, 128);

    at = at.add(const Duration(seconds: 1));
    final second = launch();
    // Nothing is remembered: the old files went with the eviction.
    await second.bytesFor(_art, 128);
    await second.evict(_art);
    await second.bytesFor(_art, 128);

    expect(cache.asked, hasLength(3));
    expect(cache.asked[0], startsWith('$_art?size=128&v='));
    expect(cache.asked[1], '$_art?size=128');
    expect(cache.asked[2], startsWith('$_art?size=128&v='));
    expect(cache.asked[2], isNot(cache.asked[0]));
  });

  test('a cover replaced while a floor stands drops its untagged files '
      'too', () async {
    // A floor moves every cover off its untagged name without removing
    // what the cache holds there, and the next launch, which remembers no
    // floor, asks under that name again.
    var at = DateTime.utc(2026, 11, 18, 12);
    final covers = ReplacedCovers(now: () => at);
    for (var i = 0; i <= ReplacedCovers.maxEntries; i++) {
      at = at.add(const Duration(milliseconds: 1));
      covers.note('$_base/api/v1/items/tr-$i/art');
    }
    final floor = covers.tagFor(_art);
    expect(floor, isNotNull);
    final cache = FakeArtCache();
    final floored = CachedArtworkStore(
      baseUrl: _base,
      pins: pins,
      client: Dio()..httpClientAdapter = server,
      pinDirectory: temp,
      cache: cache,
      replaced: covers,
      reachable: () => true,
    );
    addTearDown(floored.dispose);

    await floored.evict(_art);

    expect(
      cache.removed,
      containsAll(<String>[
        '$_art?size=128',
        '$_art?size=128&v=$floor',
        '$_art?size=1024',
        '$_art?size=1024&v=$floor',
      ]),
    );
  });

  test('covers replaced with nothing to say which leave the disk cache '
      'nothing, and are asked for under a new name', () async {
    // The files as much as the name: a later launch remembers no floor
    // and asks under the untagged name again.
    final at = DateTime.utc(2026, 11, 18, 12);
    final cache = FakeArtCache();
    final all = CachedArtworkStore(
      baseUrl: _base,
      pins: pins,
      client: Dio()..httpClientAdapter = server,
      pinDirectory: temp,
      cache: cache,
      replaced: ReplacedCovers(now: () => at),
      reachable: () => true,
    );
    addTearDown(all.dispose);

    final evicting = all.evictAll();
    // Renamed before the first await, as one cover's eviction is.
    await all.bytesFor(_art, 128);
    await evicting;

    expect(cache.emptied, 1);
    expect(cache.asked, ['$_art?size=128&v=${at.microsecondsSinceEpoch}']);
  });

  group('covers changed and nothing says which', () {
    const second = 'tr-01JZX5N8QW3F4V9T2B7KD3M9R7';
    const third = 'tr-01JZX5N8QW3F4V9T2B7KD3M9R8';
    String art(String pid) => '$_base/api/v1/items/$pid/art';
    String asked(String pid, int rung) => '${art(pid)}?size=$rung';

    File marker() => File(p.join(temp.path, CachedArtworkStore.owedFile));

    CachedArtworkStore over({CacheManager? cache, TransferGate? gate}) {
      final made = CachedArtworkStore(
        baseUrl: _base,
        pins: pins,
        token: () => 'secret-token',
        client: Dio()..httpClientAdapter = server,
        pinDirectory: temp,
        cache: cache ?? FakeArtCache(),
        pinGate: gate ?? const OpenGate(),
        pinPace: Duration.zero,
        pinRetry: const Duration(hours: 1),
        reachable: () => true,
      );
      addTearDown(made.dispose);
      return made;
    }

    /// Pins [pid]'s cover at both rungs, as a download of it does.
    Future<void> pin(String pid, {String says = 'old'}) async {
      if (pid != _pid) {
        await db
            .into(db.downloadRecords)
            .insert(
              DownloadRecordsCompanion.insert(
                pid: pid,
                fileIndex: 0,
                essenceHash: 'essence-$pid',
                etag: '1-1',
                fileName: 'track.flac',
                localPath: '/downloads/$pid.flac',
                sizeBytes: 1024,
                state: 'complete',
              ),
            );
      }
      for (final rung in <int>[1024, 256]) {
        server.serve(asked(pid, rung), '$says $rung', etag: '"$says-$rung"');
      }
      await store.pinForOffline(pid, art(pid));
      server.requested.clear();
    }

    setUp(() => server.honoursValidators = true);

    test('a pinned cover that changed is replaced', () async {
      await pin(_pid);
      server.serve(asked(_pid, 1024), 'new 1024', etag: '"new-1024"');
      server.serve(asked(_pid, 256), 'new 256', etag: '"new-256"');

      final all = over();
      await all.evictAll();
      await all.settled;

      final held = await pins.pinsFor(_pid);
      expect(held.map((pin) => pin.etag), ['"new-1024"', '"new-256"']);
      expect(File(held.first.localPath).readAsStringSync(), 'new 1024');
      expect(File(held.last.localPath).readAsStringSync(), 'new 256');
      expect(marker().existsSync(), isFalse);
    });

    test('one that did not costs a conditional request and no write', () async {
      await pin(_pid);
      final before = await pins.pinsFor(_pid);
      final written = {
        for (final pin in before)
          pin.sizePx: File(pin.localPath).lastModifiedSync(),
      };

      final all = over();
      await all.evictAll();
      await all.settled;

      expect(server.requested, [asked(_pid, 256), asked(_pid, 1024)]);
      expect(server.headersFor(asked(_pid, 256))['If-None-Match'], [
        '"old-256"',
      ]);
      expect(server.headersFor(asked(_pid, 1024))['If-None-Match'], [
        '"old-1024"',
      ]);
      final after = await pins.pinsFor(_pid);
      for (var i = 0; i < before.length; i++) {
        expect(after[i].pinnedAt, before[i].pinnedAt);
        expect(after[i].etag, before[i].etag);
        expect(
          File(after[i].localPath).lastModifiedSync(),
          written[after[i].sizePx],
        );
        expect(File(after[i].localPath).readAsStringSync(), startsWith('old'));
      }
    });

    test('one whose cover is gone keeps its file', () async {
      await pin(_pid);
      server.serveGone(asked(_pid, 1024));
      server.serveGone(asked(_pid, 256));

      final all = over();
      await all.evictAll();
      await all.settled;

      expect(server.requested, hasLength(2));
      final held = await pins.pinsFor(_pid);
      expect(held, hasLength(2));
      expect(File(held.first.localPath).readAsStringSync(), 'old 1024');
      expect(File(held.last.localPath).readAsStringSync(), 'old 256');
      // Nor is the walk left owing for it.
      expect(marker().existsSync(), isFalse);
    });

    test('a walk cut short resumes from where it stopped, in the next '
        'session too', () async {
      await pin(_pid);
      await pin(second);
      await pin(third);
      server.cut(asked(second, 1024));

      final first = over();
      await first.evictAll();
      await first.settled;
      expect(server.requested, [
        asked(_pid, 256),
        asked(_pid, 1024),
        asked(second, 256),
        asked(second, 1024),
      ]);
      expect(marker().existsSync(), isTrue);
      first.dispose();

      server.requested.clear();
      server.serve(asked(second, 1024), 'new 1024', etag: '"new-1024"');
      final next = over();
      await next.settled;
      expect(server.requested, [
        asked(second, 1024),
        asked(third, 256),
        asked(third, 1024),
      ]);
      expect((await pins.pinsFor(second)).first.etag, '"new-1024"');
      expect(marker().existsSync(), isFalse);
    });

    test(
      'a cover the server refuses does not hold the pins after it',
      () async {
        await pin(_pid);
        await pin(second);
        await pin(third);
        // A source a scan left unreadable: a standing 500, at both rungs.
        server.refuse(asked(second, 256), 500);
        server.refuse(asked(second, 1024), 500);
        server.serve(asked(third, 1024), 'new 1024', etag: '"new-1024"');

        final all = over();
        await all.evictAll();
        await all.settled;

        expect(server.requested, [
          asked(_pid, 256),
          asked(_pid, 1024),
          asked(second, 256),
          asked(second, 1024),
          asked(third, 256),
          asked(third, 1024),
        ]);
        expect((await pins.pinsFor(third)).first.etag, '"new-1024"');
        // The refused cover keeps its file, and is still owed a look.
        final kept = await pins.pinsFor(second);
        expect(File(kept.first.localPath).readAsStringSync(), 'old 1024');
        expect(jsonDecode(marker().readAsStringSync()), {
          'pins': {
            'after': [third, 1024],
            'passed': [
              [second, 256],
              [second, 1024],
            ],
            'retried': 0,
          },
        });
        all.dispose();

        // The next session asks it again, and only it.
        server.requested.clear();
        server.serve(asked(second, 1024), 'new 1024', etag: '"new-1024"');
        server.serve(asked(second, 256), 'new 256', etag: '"new-256"');
        final next = over();
        await next.settled;
        expect(server.requested, [asked(second, 256), asked(second, 1024)]);
        expect((await pins.pinsFor(second)).first.etag, '"new-1024"');
        expect(marker().existsSync(), isFalse);
      },
    );

    test('the stops a refusing server cost are counted across a restart, '
        'so short sessions still get past them', () async {
      await pin(_pid);
      await pin(second);
      await pin(third);
      server.refuseAll = 500;
      final asks = <int>[];
      for (var session = 0; session < 3; session++) {
        server.requested.clear();
        final all = over();
        if (session == 0) await all.evictAll();
        await all.settled;
        asks.add(server.requested.length);
        if (session == 0) {
          expect(jsonDecode(marker().readAsStringSync()), {
            'pins': {'tries': 1},
          });
        }
        all.dispose();
      }
      expect(asks, [PinRefresh.refusedRun, PinRefresh.refusedRun, 6]);
    });

    test('a session the server will not hear stops the walk, which goes on '
        'once it is heard again', () async {
      await pin(_pid);
      await pin(second);
      server.refuseAll = 401;
      final gate = _Gate();

      final all = over(gate: gate);
      await all.evictAll();
      await all.settled;
      expect(server.requested, [asked(_pid, 256)]);
      expect(marker().existsSync(), isTrue);

      // Signed in again: the engine drops and comes back.
      server.refuseAll = null;
      server.requested.clear();
      gate
        ..set(false)
        ..set(true);
      await all.settled;
      expect(server.requested, [
        asked(_pid, 256),
        asked(_pid, 1024),
        asked(second, 256),
        asked(second, 1024),
      ]);
      expect(marker().existsSync(), isFalse);
    });

    test('a gateway with no server behind it stops the walk too', () async {
      await pin(_pid);
      for (final status in <int>[502, 503, 504, 429]) {
        server.refuseAll = status;
        server.requested.clear();
        final all = over();
        await all.evictAll();
        await all.settled;
        // Never past the first pin, however often it is let on.
        expect(server.requested, isNotEmpty);
        expect(
          server.requested,
          everyElement(asked(_pid, 256)),
          reason: '$status',
        );
        expect(marker().existsSync(), isTrue);
        all.dispose();
      }
    });

    test('every cover refused is the server: the walk stops owed, and every '
        'pin is refreshed once it answers', () async {
      await pin(_pid);
      await pin(second);
      await pin(third);
      server.refuseAll = 500;
      final gate = _Gate();

      final all = over(gate: gate);
      await all.evictAll();
      await all.settled;
      expect(server.requested, hasLength(PinRefresh.refusedRun));
      expect(marker().existsSync(), isTrue);

      server.refuseAll = null;
      server.requested.clear();
      for (final pid in <String>[_pid, second, third]) {
        server.serve(asked(pid, 1024), 'new 1024', etag: '"new-1024"');
      }
      // Let on before its wait is up.
      gate
        ..set(false)
        ..set(true);
      await all.settled;
      expect(server.requested, hasLength(6));
      for (final pid in <String>[_pid, second, third]) {
        expect((await pins.pinsFor(pid)).first.etag, '"new-1024"');
      }
      expect(marker().existsSync(), isFalse);
    });

    test('nothing is asked while the gate is shut', () async {
      await pin(_pid);
      final gate = _Gate()..open = false;

      final all = over(gate: gate);
      await all.evictAll();
      await all.settled;
      expect(server.requested, isEmpty);
      // Owed all the same.
      expect(marker().existsSync(), isTrue);

      gate.set(true);
      await all.settled;
      expect(server.requested, hasLength(2));
      expect(marker().existsSync(), isFalse);
    });

    test('a second round during a walk starts no second walk', () async {
      await pin(_pid);
      final all = over();
      server.hold = Completer<void>();
      await all.evictAll();
      await pumpEventQueue();
      expect(server.requested, [asked(_pid, 256)]);

      await all.evictAll();
      await pumpEventQueue();
      expect(server.requested, [asked(_pid, 256)]);
      server.hold!.complete();
      server.hold = null;
      await all.settled;

      expect(server.mostInFlight, 1);
      // The walk in hand, then one more for what changed during it.
      expect(server.requested, [
        asked(_pid, 256),
        asked(_pid, 1024),
        asked(_pid, 256),
        asked(_pid, 1024),
      ]);
    });

    test('owed by a session that ended, the next store empties its disk '
        'cache before its first draw is answered, asks about its pins, and '
        'owes nothing after', () async {
      await pin(_pid);
      final first = over();
      first.oweEvictAll();
      await first.settled;
      expect(marker().existsSync(), isTrue);
      // Owing empties nothing by itself.
      expect(server.requested, isEmpty);
      first.dispose();

      final cache = FakeArtCache();
      final next = over(cache: cache);
      await next.bytesFor(_art, 128);
      expect(cache.did.first, 'emptied');
      expect(cache.emptied, 1);
      await next.settled;
      expect(server.requested, [asked(_pid, 256), asked(_pid, 1024)]);
      expect(marker().existsSync(), isFalse);
      next.dispose();

      final later = FakeArtCache();
      final third = over(cache: later);
      await third.bytesFor(_art, 128);
      await third.settled;
      expect(later.emptied, 0);
    });

    test('owed and made in the session that owed it leaves none', () async {
      final cache = FakeArtCache();
      final all = over(cache: cache);
      all.oweEvictAll();
      await all.settled;
      expect(marker().existsSync(), isTrue);

      await all.evictAll();
      await all.settled;
      expect(cache.emptied, 1);
      expect(marker().existsSync(), isFalse);
      all.dispose();

      final later = FakeArtCache();
      final next = over(cache: later);
      await next.settled;
      expect(later.emptied, 0);
    });

    test('owed twice is one', () async {
      final first = over();
      first.oweEvictAll();
      first.oweEvictAll();
      await first.settled;
      final written = marker().readAsStringSync();
      first.oweEvictAll();
      await first.settled;
      expect(marker().readAsStringSync(), written);
      first.dispose();

      final cache = FakeArtCache();
      final next = over(cache: cache);
      await next.settled;
      expect(cache.emptied, 1);
      next.dispose();

      final later = FakeArtCache();
      final third = over(cache: later);
      await third.settled;
      expect(later.emptied, 0);
    });

    test('a directory that cannot be written leaves the session '
        'working', () async {
      File(p.join(temp.path, 'blocked')).writeAsStringSync('in the way');
      final at = DateTime.utc(2026, 11, 18, 12);
      final cache = FakeArtCache();
      final all = CachedArtworkStore(
        baseUrl: _base,
        pins: pins,
        client: Dio()..httpClientAdapter = server,
        pinDirectory: Directory(p.join(temp.path, 'blocked', 'art')),
        cache: cache,
        pinPace: Duration.zero,
        replaced: ReplacedCovers(now: () => at),
        reachable: () => true,
      );
      addTearDown(all.dispose);

      all.oweEvictAll();
      await all.settled;
      await all.evictAll();
      await all.settled;
      await all.bytesFor(_art, 128);
      expect(cache.emptied, 1);
      expect(cache.asked, ['$_art?size=128&v=${at.microsecondsSinceEpoch}']);
    });

    test('a file that cannot be read owes everything, and is replaced by '
        'what is then owed', () async {
      await pin(_pid);
      marker().writeAsStringSync('{"cache": tr');

      final cache = FakeArtCache();
      final all = over(cache: cache);
      await all.bytesFor(_art, 128);
      expect(cache.did.first, 'emptied');
      await all.settled;
      expect(server.requested, [asked(_pid, 256), asked(_pid, 1024)]);
      expect(marker().existsSync(), isFalse);
    });

    test('with nothing pinned nothing is walked: the gate is not asked and '
        'nothing stays owed', () async {
      final gate = _Gate()..open = false;
      final all = over(gate: gate);
      await all.evictAll();
      await all.settled;
      expect(gate.asks, 0);
      expect(marker().existsSync(), isFalse);
      expect(server.requested, isEmpty);
    });

    test('a store that was disposed writes nothing more', () async {
      // Another store over the same directory may have taken its place.
      final gone = over();
      gone.oweEvictAll();
      gone.dispose();
      await gone.settled;
      expect(marker().existsSync(), isFalse);
    });

    test('a sign-out makes what was owed and leaves nothing owed', () async {
      await pin(_pid);
      final gate = _Gate()..open = false;
      final cache = FakeArtCache();
      final all = over(gate: gate, cache: cache);
      all.oweEvictAll();
      await all.settled;
      expect(marker().existsSync(), isTrue);
      expect(cache.emptied, 0);

      await all.forgetEverything();
      await all.settled;
      // The files the promise was for are gone with every other.
      expect(cache.emptied, 1);
      expect(await pins.pinsAfter(null, limit: 1), isEmpty);
      expect(marker().existsSync(), isFalse);
      gate.set(true);
      await all.settled;
      expect(server.requested, isEmpty);
      all.dispose();

      // Nothing is left for the next start to make.
      final later = FakeArtCache();
      final next = over(cache: later);
      await next.bytesFor(_art, 128);
      await next.settled;
      expect(later.emptied, 0);
      expect(later.asked, ['$_art?size=128']);
    });

    /// Every URL a frame naming [pid] evicts: one per role.
    List<String> roles(String pid) => [
      art(pid),
      for (final role in ['back', 'disc', 'booklet', 'background'])
        '${art(pid)}?role=$role',
    ];

    test('a named cover of a pinned item is asked about by the walk alone: '
        'nothing while the gate is shut, the new picture once it '
        'opens', () async {
      await pin(_pid);
      server.serve(asked(_pid, 1024), 'new 1024', etag: '"new-1024"');
      server.serve(asked(_pid, 256), 'new 256', etag: '"new-256"');
      final gate = _Gate()..open = false;
      final named = over(gate: gate);

      for (final url in roles(_pid)) {
        await named.evict(url);
      }
      await named.settled;
      expect(server.requested, isEmpty);
      // Owed all the same, across a kill too.
      expect(marker().existsSync(), isTrue);

      gate.set(true);
      await named.settled;
      expect(
        server.requested,
        unorderedEquals([asked(_pid, 1024), asked(_pid, 256)]),
      );
      final held = await pins.pinsFor(_pid);
      expect(held.map((pin) => pin.etag), ['"new-1024"', '"new-256"']);
      expect(File(held.first.localPath).readAsStringSync(), 'new 1024');
      expect(marker().existsSync(), isFalse);
    });

    test("the cover editor's own write waits at the gate too", () async {
      await pin(_pid);
      server.serve(asked(_pid, 1024), 'new 1024', etag: '"new-1024"');
      server.serve(asked(_pid, 256), 'new 256', etag: '"new-256"');
      final gate = _Gate()..open = false;
      final editing = over(gate: gate);

      await editing.evict(art(_pid));
      await editing.settled;
      expect(server.requested, isEmpty);

      gate.set(true);
      await editing.settled;
      final held = await pins.pinsFor(_pid);
      expect(held.map((pin) => pin.etag), ['"new-1024"', '"new-256"']);
    });

    test('named covers of pinned items are asked about one at a '
        'time', () async {
      await pin(_pid);
      await pin(second);
      await pin(third);
      server.hold = Completer<void>();
      final named = over();

      final evicting = [
        for (final pid in [_pid, second, third]) named.evict(art(pid)),
      ];
      for (var i = 0; i < 200 && server.requested.isEmpty; i++) {
        await pumpEventQueue();
      }
      await pumpEventQueue(times: 50);
      expect(server.requested, hasLength(1));
      server.hold!.complete();
      await Future.wait(evicting);
      await named.settled;
      expect(server.requested, hasLength(6));
      expect(server.mostInFlight, 1);
    });

    test('a cover replaced again while its pin is being asked about is '
        'asked about once more, and ends on the newest', () async {
      await pin(_pid);
      server
        ..serve(asked(_pid, 1024), 'mid 1024', etag: '"mid-1024"')
        ..serve(asked(_pid, 256), 'mid 256', etag: '"mid-256"')
        ..answersAsAsked = true
        ..hold = Completer<void>();
      final named = over();

      final first = named.evict(art(_pid));
      for (var i = 0; i < 200 && server.requested.isEmpty; i++) {
        await pumpEventQueue();
      }
      expect(server.requested, [asked(_pid, 1024)]);
      // Replaced again while that answer is on its way.
      server
        ..serve(asked(_pid, 1024), 'new 1024', etag: '"new-1024"')
        ..serve(asked(_pid, 256), 'new 256', etag: '"new-256"');
      await named.evict(art(_pid));
      server.hold!.complete();
      await first;
      await named.settled;

      final held = await pins.pinsFor(_pid);
      expect(held.map((pin) => pin.etag), ['"new-1024"', '"new-256"']);
      expect(File(held.first.localPath).readAsStringSync(), 'new 1024');
    });

    test('a named pin the session ended owing is asked about at the next '
        'start', () async {
      await pin(_pid);
      server.serve(asked(_pid, 1024), 'new 1024', etag: '"new-1024"');
      server.serve(asked(_pid, 256), 'new 256', etag: '"new-256"');
      final shut = over(gate: _Gate()..open = false);
      await shut.evict(art(_pid));
      await shut.settled;
      expect(server.requested, isEmpty);
      shut.dispose();

      final next = over();
      await next.settled;
      expect(server.requested, hasLength(2));
      final held = await pins.pinsFor(_pid);
      expect(held.map((pin) => pin.etag), ['"new-1024"', '"new-256"']);
      expect(marker().existsSync(), isFalse);
    });

    /// Pins [pid], its covers recorded under [recorded]: pinned before
    /// the URL its cover has now.
    Future<void> pinRecordedAt(String pid, String recorded) async {
      await pin(pid);
      for (final held in await pins.pinsFor(pid)) {
        await pins.put(
          ArtworkPinRecord(
            pid: held.pid,
            sizePx: held.sizePx,
            artUrl: recorded,
            etag: held.etag,
            localPath: held.localPath,
            sizeBytes: held.sizeBytes,
            pinnedAt: held.pinnedAt,
          ),
        );
      }
    }

    void servesNew(String pid) {
      server.serve(asked(pid, 1024), 'new 1024', etag: '"new-1024"');
      server.serve(asked(pid, 256), 'new 256', etag: '"new-256"');
    }

    group('a named cover refreshes the pin of its entity', () {
      const ulid = '01JZX5N8QW3F4V9T2B7KD3M9R9';
      const book = 'bk-$ulid';

      test('one a kind change moved, and records where the cover is '
          'now', () async {
        // Moved to the book's pid by the sync, its URL still the track's.
        await pinRecordedAt(book, art('tr-$ulid'));
        servesNew(book);
        final named = over();

        await named.evict(art(book));
        await named.settled;

        expect(
          server.requested,
          unorderedEquals([asked(book, 1024), asked(book, 256)]),
        );
        final held = await pins.pinsFor(book);
        expect(held.map((pin) => pin.artUrl).toSet(), {art(book)});
        expect(held.map((pin) => pin.etag), ['"new-1024"', '"new-256"']);
        expect(File(held.first.localPath).readAsStringSync(), 'new 1024');
      });

      test('a moved one the session ended owing, under its own pid at the '
          'next start', () async {
        await pinRecordedAt(book, art('tr-$ulid'));
        servesNew(book);
        final shut = over(gate: _Gate()..open = false);
        await shut.evict(art(book));
        await shut.settled;
        expect(server.requested, isEmpty);
        shut.dispose();

        final next = over();
        await next.settled;
        expect(
          server.requested,
          unorderedEquals([asked(book, 1024), asked(book, 256)]),
        );
        final held = await pins.pinsFor(book);
        expect(held.map((pin) => pin.artUrl).toSet(), {art(book)});
        expect(held.map((pin) => pin.etag), ['"new-1024"', '"new-256"']);
      });

      test('one recorded under an earlier address the session ended owing, '
          'of this address at the next start', () async {
        await pinRecordedAt(
          _pid,
          'http://old.local:4420/api/v1/items/$_pid/art',
        );
        servesNew(_pid);
        final shut = over(gate: _Gate()..open = false);
        await shut.evict(art(_pid));
        await shut.settled;
        expect(server.requested, isEmpty);
        shut.dispose();

        final next = over();
        await next.settled;
        expect(
          server.requested,
          unorderedEquals([asked(_pid, 1024), asked(_pid, 256)]),
        );
        final held = await pins.pinsFor(_pid);
        expect(held.map((pin) => pin.artUrl).toSet(), {art(_pid)});
        expect(held.map((pin) => pin.etag), ['"new-1024"', '"new-256"']);
      });

      test(
        'one recorded under an earlier address, asked of this one',
        () async {
          await pinRecordedAt(
            _pid,
            'http://old.local:4420/api/v1/items/$_pid/art',
          );
          servesNew(_pid);
          final named = over();

          await named.evict(art(_pid));
          await named.settled;

          expect(
            server.requested,
            unorderedEquals([asked(_pid, 1024), asked(_pid, 256)]),
          );
          expect(server.headersFor(asked(_pid, 1024))['Authorization'], [
            'Bearer secret-token',
          ]);
          final held = await pins.pinsFor(_pid);
          expect(held.map((pin) => pin.artUrl).toSet(), {art(_pid)});
          expect(held.map((pin) => pin.etag), ['"new-1024"', '"new-256"']);
        },
      );
    });

    test('a sign-out while a pinned cover is being asked about leaves no '
        'pin of it', () async {
      await pin(_pid);
      server.serve(asked(_pid, 1024), 'new 1024', etag: '"new-1024"');
      server.serve(asked(_pid, 256), 'new 256', etag: '"new-256"');
      server.hold = Completer<void>();
      final all = over();

      final evicting = all.evictAll();
      for (var i = 0; i < 200 && server.requested.isEmpty; i++) {
        await pumpEventQueue();
      }
      expect(server.requested, hasLength(1));
      await all.forgetEverything();
      // The answer lands after the pins were cleared.
      server.hold!.complete();
      await evicting;
      await all.settled;

      expect(await pins.pinsAfter(null, limit: 8), isEmpty);
      expect(
        temp.listSync().where((entry) => entry.path.endsWith('.img')),
        isEmpty,
      );
      expect(marker().existsSync(), isFalse);
    });
  });

  // As a sign-out leaves them: the audio kept, every pin dropped.
  group('downloads held with no cover pinned', () {
    const second = 'tr-01JZX5N8QW3F4V9T2B7KD3M9R7';
    String art(String pid) => '$_base/api/v1/items/$pid/art';
    String asked(String pid, int rung) => '${art(pid)}?size=$rung';

    CachedArtworkStore over({
      TransferGate? gate,
      Duration pace = Duration.zero,
      Duration retry = const Duration(hours: 1),
      ArtworkPinStore? through,
    }) {
      final made = CachedArtworkStore(
        baseUrl: _base,
        pins: through ?? pins,
        token: () => 'secret-token',
        client: Dio()..httpClientAdapter = server,
        pinDirectory: temp,
        cache: FakeArtCache(),
        pinGate: gate ?? const OpenGate(),
        pinPace: pace,
        pinRetry: retry,
        reachable: () => true,
      );
      addTearDown(made.dispose);
      return made;
    }

    void serve(String pid) {
      for (final rung in kOfflineArtworkRungs) {
        server.serve(asked(pid, rung), '$pid $rung', etag: '"$pid-$rung"');
      }
    }

    /// The server has no cover for [pid].
    void serveNone(String pid) {
      for (final rung in kOfflineArtworkRungs) {
        server.serveGone(asked(pid, rung));
      }
    }

    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 200 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(done(), isTrue);
    }

    /// Until [pid] holds a cover at every offline size.
    Future<void> untilPinned(String pid) async {
      var sizes = const <int>[];
      for (var i = 0; i < 400 && sizes.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        sizes = [for (final pin in await pins.pinsFor(pid)) pin.sizePx];
      }
      expect(sizes, kOfflineArtworkRungs);
    }

    /// Lets [held] come to rest, and anything it wrongly set going show.
    Future<void> rests(CachedArtworkStore held) async {
      await held.settled;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await held.settled;
    }

    setUp(() async {
      await db
          .into(db.downloadRecords)
          .insert(
            DownloadRecordsCompanion.insert(
              pid: second,
              fileIndex: 0,
              essenceHash: 'essence-second',
              etag: '1-1',
              fileName: 'second.flac',
              localPath: '/downloads/second.flac',
              sizeBytes: 1024,
              state: 'complete',
            ),
          );
    });

    test('each gets its cover, which draws with the server out of '
        'reach', () async {
      serve(_pid);
      serve(second);
      final landed = <String>[];
      final held = over();

      held.pinHeld({_pid: art(_pid), second: art(second)}, landed: landed.add);
      await held.settled;

      expect(landed, [_pid, second]);
      for (final pid in <String>[_pid, second]) {
        final kept = await pins.pinsFor(pid);
        expect(kept.map((pin) => pin.sizePx), kOfflineArtworkRungs);
        expect(kept.map((pin) => pin.artUrl).toSet(), {art(pid)});
      }
      final away = CachedArtworkStore(
        baseUrl: _base,
        pins: pins,
        client: Dio()..httpClientAdapter = server,
        pinDirectory: temp,
        cache: FakeArtCache(),
        reachable: () => false,
      );
      addTearDown(away.dispose);
      server.requested.clear();
      expect(
        utf8.decode((await away.bytesFor(art(second), 300))!),
        '$second 1024',
      );
      expect(server.requested, isEmpty);
    });

    test('nothing is asked while the gate is shut, and each is once it '
        'opens', () async {
      serve(_pid);
      final gate = _Gate()..open = false;
      final held = over(gate: gate);

      held.pinHeld({_pid: art(_pid)});
      await held.settled;
      await pumpEventQueue();
      expect(server.requested, isEmpty);
      expect(await pins.pinsFor(_pid), isEmpty);

      gate.set(true);
      await until(() => server.requested.length == 2);
      await held.settled;
      expect(server.requested, [asked(_pid, 1024), asked(_pid, 256)]);
      expect(await pins.pinsFor(_pid), hasLength(2));
    });

    test('one with no cover is asked about once, not at every reach', () async {
      for (final rung in kOfflineArtworkRungs) {
        server.serveGone(asked(_pid, rung));
      }
      final held = over();

      held.pinHeld({_pid: art(_pid)});
      await held.settled;
      expect(server.requested, hasLength(2));
      // A catalog pass forgets which covers answered missing; what the
      // server said about this download stands.
      held.forgetAbsences();
      held.pinHeld({_pid: art(_pid)});
      await held.settled;
      held.pinHeld({_pid: art(_pid)});
      await held.settled;

      expect(server.requested, hasLength(2));
      expect(await pins.pinsFor(_pid), isEmpty);
    });

    test('one named replaced since it answered no cover is asked again at '
        'the next reach', () async {
      for (final rung in kOfflineArtworkRungs) {
        server.serveGone(asked(_pid, rung));
      }
      final held = over();
      held.pinHeld({_pid: art(_pid)});
      await held.settled;
      expect(server.requested, hasLength(2));

      // A scan found it a cover, and the frame named the item.
      for (final rung in kOfflineArtworkRungs) {
        server.cut(asked(_pid, rung));
      }
      serve(_pid);
      await held.evict(art(_pid));
      held.pinHeld({_pid: art(_pid)});
      await held.settled;

      expect(server.requested, hasLength(4));
      expect(await pins.pinsFor(_pid), hasLength(2));
    });

    test('one the server could not be asked about stops the walk: the next '
        'reach asks for the rest, and for it not before its wait is '
        'up', () async {
      // Nothing served: every fetch fails as an unreachable server's does.
      final held = over();

      held.pinHeld({_pid: art(_pid), second: art(second)});
      await rests(held);
      expect(server.requested, [
        asked(_pid, 1024),
      ], reason: 'the rest wait, and nothing loops');

      serve(_pid);
      serve(second);
      held.pinHeld({_pid: art(_pid), second: art(second)});
      await rests(held);
      expect(await pins.pinsFor(second), hasLength(2));
      expect(await pins.pinsFor(_pid), isEmpty);
      expect(server.requested.skip(1), [
        asked(second, 1024),
        asked(second, 256),
      ]);
    });

    test('with no reach to come, it is asked again when the wait of a '
        'stopped walk is up', () async {
      final held = over(retry: const Duration(milliseconds: 200));

      held.pinHeld({_pid: art(_pid), second: art(second)});
      await rests(held);
      expect(server.requested, [asked(_pid, 1024)]);

      serve(_pid);
      serve(second);
      await untilPinned(second);
      await untilPinned(_pid);
    });

    test('one whose cover is pinned is left alone', () async {
      serve(_pid);
      await store.pinForOffline(_pid, art(_pid));
      final before = await pins.pinsFor(_pid);
      server.requested.clear();
      final landed = <String>[];
      final held = over();

      held.pinHeld({_pid: art(_pid)}, landed: landed.add);
      await held.settled;

      expect(server.requested, isEmpty);
      expect(landed, isEmpty);
      expect(
        (await pins.pinsFor(_pid)).map((pin) => pin.pinnedAt),
        before.map((pin) => pin.pinnedAt),
      );
    });

    test('one at a time, no faster than the pin walk', () async {
      serve(_pid);
      serve(second);
      final held = over(pace: const Duration(hours: 1));

      held.pinHeld({_pid: art(_pid), second: art(second)});
      await until(() => server.requested.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(server.requested, [asked(_pid, 1024)]);
    });

    test('a sign-out while one is on its way leaves no pin, and the next '
        'account is asked afresh', () async {
      for (final rung in kOfflineArtworkRungs) {
        server.serveGone(asked(second, rung));
      }
      serve(_pid);
      final held = over();
      held.pinHeld({second: art(second)});
      await held.settled;
      expect(server.requested, hasLength(2));

      server.hold = Completer<void>();
      held.pinHeld({_pid: art(_pid)});
      await until(() => server.requested.length == 3);
      await held.forgetEverything();
      server.hold!.complete();
      server.hold = null;
      await held.settled;

      expect(await pins.pinsAfter(null, limit: 8), isEmpty);
      expect(
        temp.listSync().where((entry) => entry.path.endsWith('.img')),
        isEmpty,
      );
      server.requested.clear();
      held.pinHeld({second: art(second)});
      await held.settled;
      expect(server.requested, hasLength(2));
    });

    test('one with no cover is not asked about again by a later '
        'launch', () async {
      serveNone(_pid);
      final first = over();
      first.pinHeld({_pid: art(_pid)});
      await first.settled;
      expect(server.requested, hasLength(2));
      first.dispose();

      final next = over();
      next.pinHeld({_pid: art(_pid)});
      await rests(next);
      expect(server.requested, hasLength(2));
      expect(await pins.pinsFor(_pid), isEmpty);
    });

    group('one that answered no cover is asked about by a later launch '
        'once', () {
      /// A launch that asks, [then] what happens, and the launch after.
      Future<void> askedAgainAfter(
        Future<void> Function(CachedArtworkStore first) then,
      ) async {
        serveNone(_pid);
        final first = over();
        first.pinHeld({_pid: art(_pid)});
        await first.settled;
        expect(server.requested, hasLength(2));
        await then(first);
        await first.settled;
        first.dispose();

        final next = over();
        next.pinHeld({_pid: art(_pid)});
        await rests(next);
        expect(server.requested, hasLength(4));
      }

      test('its item was named replaced', () async {
        await askedAgainAfter((first) => first.evict(art(_pid)));
      });

      test('every cover was told replaced', () async {
        await askedAgainAfter((first) => first.evictAll());
      });

      test('every cover was owed a fresh ask when the session ended', () async {
        await askedAgainAfter((first) async => first.oweEvictAll());
      });

      test('the account signed out', () async {
        await askedAgainAfter((first) => first.forgetEverything());
      });
    });

    test('what the server said of a download no longer held is not '
        'kept', () async {
      serveNone(_pid);
      serveNone(second);
      final held = over();
      held.pinHeld({_pid: art(_pid), second: art(second)});
      await held.settled;
      expect(server.requested, hasLength(4));

      // Removed, and downloaded again in a later session.
      held.pinHeld({_pid: art(_pid)});
      await held.settled;
      held.dispose();
      final next = over();
      next.pinHeld({_pid: art(_pid), second: art(second)});
      await rests(next);
      expect(server.requested.skip(4), [
        asked(second, 1024),
        asked(second, 256),
      ]);
    });

    test('a debt file from before covers asked for were kept in it still '
        'loads', () async {
      serve(_pid);
      await store.pinForOffline(_pid, art(_pid));
      server.requested.clear();
      File(
        p.join(temp.path, CachedArtworkStore.owedFile),
      ).writeAsStringSync('{"pins":{"named":[["$_pid",256]],"whole":false}}');
      final cache = FakeArtCache();
      final held = CachedArtworkStore(
        baseUrl: _base,
        pins: pins,
        client: Dio()..httpClientAdapter = server,
        pinDirectory: temp,
        cache: cache,
        pinPace: Duration.zero,
        reachable: () => true,
      );
      addTearDown(held.dispose);
      await held.settled;

      // Read as it was written: the one pin it named, and no more owed.
      expect(server.requested, [asked(_pid, 256)]);
      expect(cache.emptied, 0);
    });

    test('one holding one of its sizes is asked for the other alone', () async {
      serve(_pid);
      await store.pinForOffline(_pid, art(_pid));
      final small = (await pins.pinsFor(_pid)).last;
      await pins.removeExactly(_pid, [
        (sizePx: small.sizePx, pinnedAt: small.pinnedAt),
      ]);
      server.requested.clear();
      final landed = <String>[];
      final held = over();

      held.pinHeld({_pid: art(_pid)}, landed: landed.add);
      await held.settled;

      expect(server.requested, [asked(_pid, 256)]);
      expect(
        (await pins.pinsFor(_pid)).map((pin) => pin.sizePx),
        kOfflineArtworkRungs,
      );
      expect(landed, [_pid]);
    });

    test('with every cover pinned a reach looks at no gate, asks the '
        'platform nothing and reads the pins a page at a time', () async {
      final many = <String>[
        for (var i = 0; i < 500; i++) 'tr-01JZX5N8QW3F4V9T2B7KD${1000 + i}',
      ];
      await db.batch((batch) {
        for (final pid in many) {
          batch.insert(
            db.downloadRecords,
            DownloadRecordsCompanion.insert(
              pid: pid,
              fileIndex: 0,
              essenceHash: 'essence-$pid',
              etag: '1-1',
              fileName: '$pid.flac',
              localPath: '/downloads/$pid.flac',
              sizeBytes: 1024,
              state: 'complete',
            ),
          );
          for (final rung in kOfflineArtworkRungs) {
            batch.insert(
              db.artworkPins,
              ArtworkPinsCompanion.insert(
                pid: pid,
                sizePx: rung,
                artUrl: art(pid),
                etag: '"$rung"',
                localPath: '/art/$pid-$rung.img',
                sizeBytes: 1,
                pinnedAt: DateTime.utc(2026, 11, 18),
              ),
            );
          }
        }
      });
      final net = _Net()..now = ConnectionCost.unmetered;
      final wifi = WifiOnlyGate(connectivity: net, wifiOnly: () => true);
      addTearDown(wifi.dispose);
      var looks = 0;
      final gate = PinRefreshGate(
        reachable: () {
          looks++;
          return true;
        },
        playbackWaiting: () => false,
        transfers: () => wifi,
        downloading: () async => false,
        moved: () => const <Stream<void>>[],
      );
      final counted = _CountingPinStore(pins);
      final held = over(gate: gate, through: counted);
      await held.settled;
      final before = counted.reads;

      held.pinHeld({for (final pid in many) pid: art(pid)});
      await rests(held);

      expect(looks, 0);
      expect(net.asked, 0);
      expect(counted.reads - before, lessThanOrEqualTo(4));
      expect(server.requested, isEmpty);
    });

    test('the gate shutting after one size holds the next until it '
        'opens', () async {
      serve(_pid);
      final gate = _Gate();
      final held = over(gate: gate);
      server.hold = Completer<void>();
      held.pinHeld({_pid: art(_pid)});
      await until(() => server.requested.length == 1);

      // Wifi lost, or a download started, with the first on its way.
      gate.set(false);
      server.hold!.complete();
      server.hold = null;
      await rests(held);
      expect(server.requested, [asked(_pid, 1024)]);

      gate.set(true);
      await untilPinned(_pid);
      expect(server.requested, [asked(_pid, 1024), asked(_pid, 256)]);
    });

    test('one named replaced while it is being asked about is asked again, '
        'and the answer from before is not kept', () async {
      serveNone(_pid);
      server.answersAsAsked = true;
      final held = over(retry: const Duration(milliseconds: 100));
      server.hold = Completer<void>();
      held.pinHeld({_pid: art(_pid)});
      await until(() => server.requested.length == 1);

      // A scan found it a cover, and the frame named the item, with the
      // question on its way.
      for (final rung in kOfflineArtworkRungs) {
        server.cut(asked(_pid, rung));
      }
      serve(_pid);
      await held.evict(art(_pid));
      server.hold!.complete();
      server.hold = null;

      await untilPinned(_pid);
      expect(server.requested, [
        asked(_pid, 1024),
        asked(_pid, 256),
        asked(_pid, 1024),
      ]);
      expect(held.imageFor(art(_pid), 1024), isNotNull);
    });

    test('a cover replaced while its first pin is on its way is asked '
        'about again, so the pin is the new picture', () async {
      serve(_pid);
      server.answersAsAsked = true;
      final held = over();
      server.hold = Completer<void>();
      held.pinHeld({_pid: art(_pid)});
      await until(() => server.requested.length == 1);

      // The editor wrote a new cover with the old one on its way.
      for (final rung in kOfflineArtworkRungs) {
        server.serve(asked(_pid, rung), 'new $rung', etag: '"new-$rung"');
      }
      await held.evict(art(_pid));
      server.hold!.complete();
      server.hold = null;

      await until(() => server.requested.length == 3);
      await held.settled;
      expect(server.requested, [
        asked(_pid, 1024),
        asked(_pid, 1024),
        asked(_pid, 256),
      ]);
      for (final pin in await pins.pinsFor(_pid)) {
        expect(File(pin.localPath).readAsStringSync(), 'new ${pin.sizePx}');
      }
    });

    test('one the server never answers for does not hold the rest '
        'back', () async {
      // Nothing served for the first: every fetch of it fails.
      serve(second);
      final held = over();
      final both = {_pid: art(_pid), second: art(second)};

      held.pinHeld(both);
      await rests(held);
      held.pinHeld(both);
      await rests(held);

      expect(await pins.pinsFor(second), hasLength(2));
      // Stopped at the first no answer, and the one that got it waits its
      // wait out.
      expect(server.requested, [
        asked(_pid, 1024),
        asked(second, 1024),
        asked(second, 256),
      ]);
    });

    test('one the server will not give, for a reason that is not the '
        "session's, is asked again in rounds, and the rest are not held "
        'back', () async {
      for (final rung in kOfflineArtworkRungs) {
        server.refuse(asked(_pid, rung), 500);
      }
      serve(second);
      final held = over(retry: const Duration(milliseconds: 100));

      held.pinHeld({_pid: art(_pid), second: art(second)});
      await rests(held);
      expect(server.requested, [
        asked(_pid, 1024),
        asked(_pid, 256),
        asked(second, 1024),
        asked(second, 256),
      ]);
      expect(await pins.pinsFor(second), hasLength(2));

      // Asked again after a wait, and by then the server can read it.
      await until(() => server.requested.length > 4);
      serve(_pid);
      await untilPinned(_pid);
    });

    test('one the server refused to the end of its rounds is not asked for '
        'by a later reach, until its item is named replaced', () async {
      for (final rung in kOfflineArtworkRungs) {
        server.refuse(asked(_pid, rung), 500);
      }
      final held = over(retry: const Duration(milliseconds: 30));
      // Both sizes three times before they are passed, and in each round.
      const through = 2 * 3 + 2 * PinRefresh.retryRounds;

      held.pinHeld({_pid: art(_pid)});
      await until(() => server.requested.length == through);
      await rests(held);
      held.pinHeld({_pid: art(_pid)});
      await rests(held);
      expect(server.requested, hasLength(through));

      // A scan gave it another cover, and the frame named the item.
      serve(_pid);
      await held.evict(art(_pid));
      held.pinHeld({_pid: art(_pid)});
      await untilPinned(_pid);
      expect(server.requested, hasLength(through + 2));
    });

    test('against a server that refuses every cover, reach after reach asks '
        'for each size of six hundred downloads once, not once a '
        'reach', () async {
      final many = <String>[
        for (var i = 0; i < 600; i++) 'tr-01JZX5N8QW3F4V9T2B7KD${1000 + i}',
      ];
      await db.batch((batch) {
        for (final pid in many) {
          batch.insert(
            db.downloadRecords,
            DownloadRecordsCompanion.insert(
              pid: pid,
              fileIndex: 0,
              essenceHash: 'essence-$pid',
              etag: '1-1',
              fileName: '$pid.flac',
              localPath: '/downloads/$pid.flac',
              sizeBytes: 1024,
              state: 'complete',
            ),
          );
        }
      });
      server.refuseAll = 500;
      final held = over();
      final all = {for (final pid in many) pid: art(pid)};

      // Four refusals in a row with nothing answering stop the walk, and
      // the third time the same four do it goes on past them.
      held.pinHeld(all);
      await rests(held);
      expect(server.requested, hasLength(4));
      held.pinHeld(all);
      await rests(held);
      expect(server.requested, hasLength(8));
      held.pinHeld(all);
      await rests(held);
      expect(server.requested, hasLength(8 + 1200));

      // Those refused wait for the rounds of the ones kept to ask again.
      held.pinHeld(all);
      await rests(held);
      held.pinHeld(all);
      await rests(held);
      expect(server.requested, hasLength(8 + 1200));
    });

    test('with pinned covers to ask about too, the two are asked no faster '
        'than the pace between them', () async {
      serve(second);
      await store.pinForOffline(second, art(second));
      server.requested.clear();
      serve(_pid);
      final held = over(pace: const Duration(hours: 1));

      await held.evictAll();
      held.pinHeld({_pid: art(_pid), second: art(second)});
      await until(() => server.requested.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(server.requested, hasLength(1));
    });

    test('the wifi-only setting holds them back, through the gate the app '
        'builds', () async {
      serve(_pid);
      final net = _Net();
      final sync = SyncEngine(
        db: db,
        repository: FakeRepository(),
        channelFactory: FakeLink().factory,
      );
      addTearDown(sync.dispose);
      final downloads = FakeDownloads();
      addTearDown(downloads.dispose);
      final container = appContainer(
        downloads: downloads,
        sync: sync,
        mirror: db,
        settings: MemoryClientSettingsStore(),
        extra: [connectivityProvider.overrideWithValue(net)],
      );
      await sync.start();
      await pumpEventQueue();
      expect(sync.current.online, isTrue);
      expect(container.read(downloadsOnWifiOnlyProvider), isTrue);
      final held = over(gate: container.read(_appGate));

      held.pinHeld({_pid: art(_pid)});
      await rests(held);
      expect(server.requested, isEmpty);
      expect(await pins.pinsFor(_pid), isEmpty);

      net.move(ConnectionCost.unmetered);
      await untilPinned(_pid);
    });

    test('after a sign-out with one on its way, nothing more is '
        'asked', () async {
      serve(_pid);
      serve(second);
      final held = over();
      server.hold = Completer<void>();
      held.pinHeld({_pid: art(_pid), second: art(second)});
      await until(() => server.requested.length == 1);

      await held.forgetEverything();
      server.hold!.complete();
      server.hold = null;
      await rests(held);

      expect(server.requested, hasLength(1));
      expect(await pins.pinsAfter(null, limit: 8), isEmpty);
    });

    test('an answer on its way across a sign-out is not the next '
        "account's: it is asked for every size afresh", () async {
      serve(_pid);
      final held = over();
      server.hold = Completer<void>();
      held.pinHeld({_pid: art(_pid)});
      await until(() => server.requested.length == 1);

      await held.forgetEverything();
      // The next sign-in, and its reach, before the answer lands.
      held.pinHeld({_pid: art(_pid)});
      await Future<void>.delayed(const Duration(milliseconds: 40));
      server.hold!.complete();
      server.hold = null;

      await untilPinned(_pid);
      expect(server.requested, [
        asked(_pid, 1024),
        asked(_pid, 1024),
        asked(_pid, 256),
      ]);
    });

    test('a sign-out while they wait at the gate leaves nothing to ask '
        'when it opens', () async {
      serve(_pid);
      final gate = _Gate()..open = false;
      final held = over(gate: gate);
      held.pinHeld({_pid: art(_pid)});
      await rests(held);
      expect(server.requested, isEmpty);

      await held.forgetEverything();
      gate.set(true);
      await rests(held);

      expect(server.requested, isEmpty);
      expect(await pins.pinsAfter(null, limit: 8), isEmpty);
    });
  });

  test('one eviction drops what the disk cache holds of every role of the '
      'cover', () async {
    final cache = FakeArtCache();
    final roles = CachedArtworkStore(
      baseUrl: _base,
      pins: pins,
      client: Dio()..httpClientAdapter = server,
      pinDirectory: temp,
      cache: cache,
      reachable: () => true,
    );
    addTearDown(roles.dispose);

    await roles.evict('$_art?role=back');

    expect(
      cache.removed,
      containsAll(<String>[
        '$_art?size=128',
        '$_art?size=1024',
        '$_art?role=back&size=128',
        '$_art?role=disc&size=128',
        '$_art?role=booklet&size=512',
        '$_art?role=background&size=1024',
      ]),
    );
  });

  test(
    'every role of a cover evicted in one turn drops each file once',
    () async {
      final cache = FakeArtCache();
      final roles = CachedArtworkStore(
        baseUrl: _base,
        pins: pins,
        client: Dio()..httpClientAdapter = server,
        pinDirectory: temp,
        cache: cache,
        reachable: () => true,
      );
      addTearDown(roles.dispose);

      await Future.wait([
        for (final url in [
          _art,
          for (final role in ['back', 'disc', 'booklet', 'background'])
            '$_art?role=$role',
        ])
          roles.evict(url),
      ]);

      expect(cache.removed, hasLength(cache.removed.toSet().length));
      expect(cache.removed, contains('$_art?role=background&size=64'));
    },
  );

  test('evicting another role of a pinned item leaves its offline cover '
      'alone', () async {
    // The pin is the item's one offline cover, made from its front. A
    // frame that names the item evicts every role's URL.
    server.serve('$_art?size=1024', 'front hero', etag: '"front-1024"');
    server.serve('$_art?size=256', 'front cell', etag: '"front-256"');
    await store.pinForOffline(_pid, _art);
    const back = '$_art?role=back';
    server.serve('$back&size=1024', 'back hero', etag: '"back-1024"');
    server.serve('$back&size=256', 'back cell', etag: '"back-256"');
    server.requested.clear();

    await store.evict(back);
    await store.settled;

    final held = await pins.pinsFor(_pid);
    expect(held.map((pin) => pin.artUrl).toSet(), {_art});
    expect(File(held.first.localPath).readAsStringSync(), 'front hero');
    expect(File(held.last.localPath).readAsStringSync(), 'front cell');
    expect(server.requested, isEmpty);
  });

  group('a mounted cover', () {
    // Mounted once: nothing builds what holds it again.
    Future<void> mount(WidgetTester tester, [CachedArtworkStore? over]) =>
        tester.pumpWidget(
          MaterialApp(
            theme: buildWaxTheme(),
            home: Scaffold(
              body: ArtworkImage(
                size: 48,
                monogram: 'Salt Harbour',
                artwork: (over ?? store).source(_art),
              ),
            ),
          ),
        );

    Future<void> serves(WidgetTester tester, int width) async {
      final picture = (await tester.runAsync(() => artPng(width, width)))!;
      for (final rung in <int>[1024, 256]) {
        server.serveBytes('$_art?size=$rung', picture, etag: '"$width-$rung"');
      }
    }

    testWidgets('told replaced draws the new picture, and the old one '
        'until it is ready', (tester) async {
      await serves(tester, 40);
      await tester.runAsync(() => store.pinForOffline(_pid, _art));
      await mount(tester);
      await coverDraws(tester, 40);

      // What a frame naming the item does. The cover draws from its pin
      // here (the cache is unreachable), which the walk brings up to date.
      await serves(tester, 24);
      await tester.runAsync(() async {
        await store.evict(_art);
        await store.settled;
      });
      await tester.pump();
      expect(coverDrawn(tester), 40);
      expect(find.text('SH'), findsNothing);
      await coverDraws(tester, 24);
    });

    group('out of reach', () {
      // Built outside the test's fake clock: the walk an eviction starts
      // is awaited from real time.
      var reach = false;
      late FakeArtCache cache;
      late CachedArtworkStore away;

      setUp(() {
        reach = false;
        cache = FakeArtCache();
        away = CachedArtworkStore(
          baseUrl: _base,
          pins: pins,
          client: Dio()..httpClientAdapter = server,
          pinDirectory: temp,
          cache: cache,
          reachable: () => reach,
        );
      });
      tearDown(() => away.dispose());

      testWidgets('drawn from its pin, and told replaced once reach is '
          'back, asks the server first and draws what the walk pinned', (
        tester,
      ) async {
        await serves(tester, 40);
        await tester.runAsync(() => store.pinForOffline(_pid, _art));
        await mount(tester, away);
        await coverDraws(tester, 40);
        expect(cache.asked, isEmpty);

        // Back in reach, the frame answering the subscribe names the
        // item: what the sync binder does with it.
        reach = true;
        await serves(tester, 24);
        await tester.runAsync(() async {
          await away.evict(_art);
          await away.settled;
        });
        await tester.pump();
        await coverDraws(tester, 24);
        expect(
          cache.asked,
          isNotEmpty,
          reason: 'in reach the network is first',
        );
      });
    });

    group('drawn off a pin an earlier session left owed its refresh', () {
      // Built outside the test's fake clock, the earlier session with
      // them: an eviction's walk is awaited from real time.
      var reach = false;
      late _Gate gate;
      late FakeArtCache cache;
      late _HeldDraws draws;
      late CachedArtworkStore next;
      const retry = Duration(minutes: 2);

      setUp(() async {
        final old = await artPng(40);
        final fresh = await artPng(24);
        for (final rung in <int>[1024, 256]) {
          server.serveBytes('$_art?size=$rung', old, etag: '"40-$rung"');
        }
        await store.pinForOffline(_pid, _art);
        // The cover is replaced and named, the walk waits at its gate,
        // and the session ends.
        final earlier = CachedArtworkStore(
          baseUrl: _base,
          pins: pins,
          client: Dio()..httpClientAdapter = server,
          pinDirectory: temp,
          cache: FakeArtCache(),
          pinGate: _Gate()..open = false,
          reachable: () => true,
        );
        await earlier.evict(_art);
        await earlier.settled;
        earlier.dispose();
        for (final rung in <int>[1024, 256]) {
          server.serveBytes('$_art?size=$rung', fresh, etag: '"24-$rung"');
        }
        server.requested.clear();

        reach = false;
        gate = _Gate()..open = false;
        cache = FakeArtCache();
        for (final rung in <int>[64, 128, 256, 512, 1024]) {
          cache.serve('$_art?size=$rung', fresh);
        }
        draws = _HeldDraws(pins);
        next = CachedArtworkStore(
          baseUrl: _base,
          pins: draws,
          client: Dio()..httpClientAdapter = server,
          pinDirectory: temp,
          cache: cache,
          pinGate: gate,
          pinPace: Duration.zero,
          pinRetry: retry,
          reachable: () => reach,
        );
      });
      tearDown(() => next.dispose());

      testWidgets('asks the server when reach returns, the walk still at '
          'its gate', (tester) async {
        await mount(tester, next);
        await coverDraws(tester, 40);
        expect(cache.asked, isEmpty);

        reach = true;
        next.serverReached();
        await coverDraws(tester, 24);
        expect(cache.asked, hasLength(1));
        expect(server.requested, isEmpty, reason: 'the walk has not run');
      });

      testWidgets('draws the new picture once the walk has pinned it', (
        tester,
      ) async {
        await mount(tester, next);
        await coverDraws(tester, 40);

        // The gate opens with nothing naming the cover again.
        await tester.runAsync(() async {
          gate.set(true);
          await next.settled;
        });
        await tester.pump();
        await coverDraws(tester, 24);
        expect(cache.asked, isEmpty, reason: 'off the pin the walk rewrote');
        expect(server.requested, hasLength(2));
      });

      /// Lets the store's real reads land until [done].
      Future<void> until(WidgetTester tester, bool Function() done) async {
        for (var i = 0; i < 500 && !done(); i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(done(), isTrue);
      }

      /// Lets what the store has queued run, on both clocks.
      Future<void> settle(WidgetTester tester) async {
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(() => pumpEventQueue());
          await tester.pump();
        }
      }

      // The socket comes up while a draw that found the server out of
      // reach is still on its way to the pin, so the check the turn
      // makes has passed before the draw is recorded.
      Future<void> reachedWhileHeld(WidgetTester tester, Hold hold) async {
        reach = true;
        // The store's start finished outside the test's clock, so what
        // waits on it runs there: the check is made before the release.
        await tester.runAsync(() async {
          next.serverReached();
          await pumpEventQueue();
        });
        hold.release();
        await coverDraws(tester, 24);
        expect(cache.asked, hasLength(1));
        expect(server.requested, isEmpty, reason: 'the walk has not run');
      }

      testWidgets('reached while its draw waits on the disk cache, asks the '
          'server once the draw lands', (tester) async {
        final hold = cache.holdReads = Hold();
        await mount(tester, next);
        await until(tester, () => hold.reached);
        await reachedWhileHeld(tester, hold);
      });

      testWidgets('reached while its draw waits on its pin lookup, asks the '
          'server once the draw lands', (tester) async {
        final hold = draws.hold = Hold();
        await mount(tester, next);
        await until(tester, () => hold.reached);
        await reachedWhileHeld(tester, hold);
      });

      testWidgets('reached while its draw waits on an emptying of the disk '
          'cache, asks the server once the draw lands', (tester) async {
        final hold = cache.holdEmptying = Hold();
        // Outside the test's clock, as the store's own work is.
        await tester.runAsync(() async => unawaited(next.evictAll()));
        await mount(tester, next);
        await reachedWhileHeld(tester, hold);
      });

      testWidgets('drawn in reach because the fetch failed, asks again no '
          'sooner than a stopped walk looks again, until it is answered', (
        tester,
      ) async {
        reach = true;
        cache.refuseAll = 502;
        await mount(tester, next);
        await coverDraws(tester, 40);
        await settle(tester);
        expect(cache.asked, hasLength(1));

        await tester.pump(retry - const Duration(seconds: 1));
        await settle(tester);
        expect(cache.asked, hasLength(1));
        await tester.pump(const Duration(seconds: 1));
        await until(tester, () => draws.looked == 2);
        expect(cache.asked, hasLength(2));
        expect(coverDrawn(tester), 40);

        // Still failing: once more a wait later, and no sooner.
        await settle(tester);
        await tester.pump(retry - const Duration(seconds: 1));
        await settle(tester);
        expect(cache.asked, hasLength(2));
        cache.refuseAll = null;
        await tester.pump(const Duration(seconds: 1));
        await coverDraws(tester, 24);
        expect(cache.asked, hasLength(3));
        expect(server.requested, isEmpty, reason: 'the walk has not run');
      });
    });

    testWidgets('redraws when covers changed and nothing says which', (
      tester,
    ) async {
      await serves(tester, 40);
      await tester.runAsync(() => store.pinForOffline(_pid, _art));
      await mount(tester);
      await coverDraws(tester, 40);

      await serves(tester, 24);
      await tester.runAsync(() async {
        await store.evictAll();
        await store.settled;
      });
      await tester.pump();
      expect(coverDrawn(tester), 40);
      await coverDraws(tester, 24);
    });
  });

  test("the store is told each time the engine's socket comes up", () async {
    final repo = FakeRepository();
    final sync = SyncEngine(
      db: db,
      repository: repo,
      channelFactory: FakeLink().factory,
    );
    addTearDown(sync.dispose);
    final downloads = FakeDownloads();
    addTearDown(downloads.dispose);
    final told = _ReachTold();
    final container = appContainer(
      repo: repo,
      mirror: db,
      downloads: downloads,
      sync: sync,
      artwork: told,
    );
    // Listened, as the signed-in shell holds the binder.
    final bound = container.listen(syncBinderProvider, (_, _) {});
    addTearDown(bound.close);

    await pumpEventQueue();
    expect(sync.current.online, isTrue);
    expect(told.reached, 1);

    await sync.stop();
    await pumpEventQueue();
    expect(told.reached, 1, reason: 'going out of reach says nothing');
    await sync.start();
    await pumpEventQueue();
    expect(told.reached, 2);
  });

  test('each time the socket comes up the store is handed every complete '
      'download, with its cover at this server', () async {
    const other = 'bk-01JZX5N8QW3F4V9T2B7KD3M9R7';
    const fetching = 'tr-01JZX5N8QW3F4V9T2B7KD3M9R8';
    final repo = ArtUnderBase(_base);
    final sync = SyncEngine(
      db: db,
      repository: repo,
      channelFactory: FakeLink().factory,
    );
    addTearDown(sync.dispose);
    final downloads = FakeDownloads()
      ..setStored(const <DownloadedItem>[
        DownloadedItem(pid: _pid, sizeBytes: 1024, files: 1, complete: true),
        DownloadedItem(pid: other, sizeBytes: 1024, files: 2, complete: true),
        DownloadedItem(
          pid: fetching,
          sizeBytes: 1024,
          files: 1,
          complete: false,
        ),
      ]);
    addTearDown(downloads.dispose);
    final told = _HeldTold();
    final container = appContainer(
      repo: repo,
      mirror: db,
      downloads: downloads,
      sync: sync,
      artwork: told,
    );
    final bound = container.listen(syncBinderProvider, (_, _) {});
    addTearDown(bound.close);

    await pumpEventQueue();
    expect(sync.current.online, isTrue);
    expect(told.held, [
      {_pid: _art, other: '$_base/api/v1/items/$other/art'},
    ]);

    await sync.stop();
    await pumpEventQueue();
    expect(told.held, hasLength(1));
    await sync.start();
    await pumpEventQueue();
    expect(told.held, hasLength(2));
  });

  test("the cover editor's own write re-pins it, so offline gets the new one "
      'too', () async {
    server.serve('$_art?size=1024', 'old hero', etag: '"old-1024"');
    server.serve('$_art?size=256', 'old cell', etag: '"old-256"');
    await store.pinForOffline(_pid, _art);

    server.serve('$_art?size=1024', 'new hero', etag: '"new-1024"');
    server.serve('$_art?size=256', 'new cell', etag: '"new-256"');
    await store.evict(_art);
    // Through the walk, at once with nothing holding it back.
    await store.settled;

    final held = await pins.pinsFor(_pid);
    expect(held.first.etag, '"new-1024"');
    expect(File(held.first.localPath).readAsStringSync(), 'new hero');
  });
}

/// Counts the times it is told the server is back in reach.
class _ReachTold extends FakeArtworkStore {
  int reached = 0;

  @override
  void serverReached() => reached++;
}

/// Records the downloads it is handed to pin covers for.
class _HeldTold extends FakeArtworkStore {
  final List<Map<String, String>> held = <Map<String, String>>[];

  @override
  void pinHeld(Map<String, String> held, {void Function(String pid)? landed}) =>
      this.held.add(held);
}

/// A pin store that cannot say what is pinned for a draw: a database
/// that has closed under it.
class _UnreadablePinStore implements ArtworkPinStore {
  _UnreadablePinStore(this.inner);

  final ArtworkPinStore inner;

  @override
  Future<List<ArtworkPinRecord>> pinsFor(String pid) => inner.pinsFor(pid);

  @override
  Future<List<ArtworkPinRecord>> pinsToDraw(String pid) =>
      throw StateError('closed');

  @override
  Future<List<ArtworkPinRecord>> pinsAfter(
    PinCursor? after, {
    required int limit,
  }) => inner.pinsAfter(after, limit: limit);

  @override
  Future<void> put(ArtworkPinRecord pin) => inner.put(pin);

  @override
  Future<void> recordUrl(ArtworkPinRecord pin, String artUrl) =>
      inner.recordUrl(pin, artUrl);

  @override
  Future<void> removeExactly(String pid, List<OwedPin> pins) =>
      inner.removeExactly(pid, pins);

  @override
  Future<bool> mayPin(String pid) => inner.mayPin(pid);

  @override
  Future<List<ArtworkPinRecord>> clear() => inner.clear();
}

/// A socket whose connect never answers: a cold start, with the server
/// out of reach behind a network that drops what it is sent.
class _UnansweredChannel extends EventsChannel {
  _UnansweredChannel({
    required super.onFrame,
    required super.onDone,
    required super.subscribe,
  }) : super(url: 'ws://deck.local:4420', authToken: null);

  @override
  Future<void> connect() => Completer<void>().future;

  @override
  bool send(String frame) => false;

  @override
  Future<void> close() async {}
}

/// A connection on mobile data until the test moves it.
class _Net implements ConnectivityPort {
  ConnectionCost now = ConnectionCost.metered;
  final StreamController<ConnectionCost> _costs =
      StreamController<ConnectionCost>.broadcast();

  /// How many times the platform was asked.
  int asked = 0;

  @override
  Future<ConnectionCost> cost() async {
    asked++;
    return now;
  }

  @override
  Stream<ConnectionCost> get costs => _costs.stream;

  @override
  Stream<void> get returns => const Stream<void>.empty();

  void move(ConnectionCost cost) {
    now = cost;
    _costs.add(cost);
  }
}

/// A gate the test moves.
class _Gate implements TransferGate {
  bool open = true;
  final StreamController<bool> _changes = StreamController<bool>.broadcast(
    sync: true,
  );

  void set(bool value) {
    open = value;
    _changes.add(value);
  }

  /// How often it was asked in full.
  int asks = 0;

  @override
  Future<bool> isOpen() async {
    asks++;
    return open;
  }

  /// Like the gate the app builds, it tells each new listener where it
  /// stands, a moment after it listens.
  @override
  Stream<bool> get changes => Stream<bool>.multi((listener) {
    final heard = _changes.stream.listen(listener.add);
    scheduleMicrotask(() {
      if (!listener.isClosed) listener.add(open);
    });
    listener.onCancel = heard.cancel;
  });
}

/// A cache that answers every request the way the server answers a
/// request for an item with no artwork.
class _NotFoundCache implements CacheManager {
  /// How many times the server was actually asked, which is the whole
  /// point of the negative cache.
  int fetches = 0;

  // Through noSuchMethod rather than an override: the manager's files
  // are package:file's, which this package has no business naming.
  // Anything but the fetch is a call these tests say must not happen -
  // bar the two an invalidation makes.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getSingleFile) {
      fetches++;
      throw const HttpExceptionWithStatus(404, 'no artwork');
    }
    if (invocation.memberName == #removeFile ||
        invocation.memberName == #emptyCache ||
        invocation.memberName == #dispose) {
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

/// A pin store whose next removal of rows dies, as a process does between one
/// step and the next.
class _KilledPinStore implements ArtworkPinStore {
  _KilledPinStore(this.inner);

  final ArtworkPinStore inner;
  bool killNext = false;

  @override
  Future<List<ArtworkPinRecord>> pinsFor(String pid) => inner.pinsFor(pid);

  @override
  Future<List<ArtworkPinRecord>> pinsToDraw(String pid) =>
      inner.pinsToDraw(pid);

  @override
  Future<List<ArtworkPinRecord>> pinsAfter(
    PinCursor? after, {
    required int limit,
  }) => inner.pinsAfter(after, limit: limit);

  @override
  Future<void> put(ArtworkPinRecord pin) => inner.put(pin);

  @override
  Future<void> recordUrl(ArtworkPinRecord pin, String artUrl) =>
      inner.recordUrl(pin, artUrl);

  @override
  Future<void> removeExactly(String pid, List<OwedPin> pins) async {
    if (killNext) {
      killNext = false;
      throw StateError('killed');
    }
    return inner.removeExactly(pid, pins);
  }

  @override
  Future<bool> mayPin(String pid) => inner.mayPin(pid);

  @override
  Future<List<ArtworkPinRecord>> clear() => inner.clear();
}

/// A pin store that runs [before] once, just ahead of its next removal of
/// rows: a cover pinned while an unpin is part-way.
class _PinsBeforeRemoval implements ArtworkPinStore {
  _PinsBeforeRemoval(this.inner);

  final ArtworkPinStore inner;
  Future<void> Function()? before;

  Future<void> _landBefore() async {
    final land = before;
    before = null;
    await land?.call();
  }

  @override
  Future<List<ArtworkPinRecord>> pinsFor(String pid) => inner.pinsFor(pid);

  @override
  Future<List<ArtworkPinRecord>> pinsToDraw(String pid) =>
      inner.pinsToDraw(pid);

  @override
  Future<List<ArtworkPinRecord>> pinsAfter(
    PinCursor? after, {
    required int limit,
  }) => inner.pinsAfter(after, limit: limit);

  @override
  Future<void> put(ArtworkPinRecord pin) => inner.put(pin);

  @override
  Future<void> recordUrl(ArtworkPinRecord pin, String artUrl) =>
      inner.recordUrl(pin, artUrl);

  @override
  Future<void> removeExactly(String pid, List<OwedPin> pins) async {
    await _landBefore();
    return inner.removeExactly(pid, pins);
  }

  @override
  Future<bool> mayPin(String pid) => inner.mayPin(pid);

  @override
  Future<List<ArtworkPinRecord>> clear() => inner.clear();
}

/// A pin store whose lookups for a draw wait on [hold] while it is set,
/// and are counted as they answer.
class _HeldDraws implements ArtworkPinStore {
  _HeldDraws(this.inner);

  final ArtworkPinStore inner;
  Hold? hold;
  int looked = 0;

  @override
  Future<List<ArtworkPinRecord>> pinsFor(String pid) => inner.pinsFor(pid);

  @override
  Future<List<ArtworkPinRecord>> pinsToDraw(String pid) async {
    final held =
        await (hold?.wait(() => inner.pinsToDraw(pid)) ??
            inner.pinsToDraw(pid));
    looked++;
    return held;
  }

  @override
  Future<List<ArtworkPinRecord>> pinsAfter(
    PinCursor? after, {
    required int limit,
  }) => inner.pinsAfter(after, limit: limit);

  @override
  Future<void> put(ArtworkPinRecord pin) => inner.put(pin);

  @override
  Future<void> recordUrl(ArtworkPinRecord pin, String artUrl) =>
      inner.recordUrl(pin, artUrl);

  @override
  Future<void> removeExactly(String pid, List<OwedPin> pins) =>
      inner.removeExactly(pid, pins);

  @override
  Future<bool> mayPin(String pid) => inner.mayPin(pid);

  @override
  Future<List<ArtworkPinRecord>> clear() => inner.clear();
}

/// Counts pin lookups, to prove the ones that should not happen do not.
class _CountingPinStore implements ArtworkPinStore {
  _CountingPinStore(this.inner);

  final ArtworkPinStore inner;
  int lookups = 0;

  /// Every read of the pins: the lookups, and the pages of them all.
  int reads = 0;

  @override
  Future<List<ArtworkPinRecord>> pinsFor(String pid) {
    lookups++;
    reads++;
    return inner.pinsFor(pid);
  }

  @override
  Future<List<ArtworkPinRecord>> pinsToDraw(String pid) {
    lookups++;
    reads++;
    return inner.pinsToDraw(pid);
  }

  @override
  Future<List<ArtworkPinRecord>> pinsAfter(
    PinCursor? after, {
    required int limit,
  }) {
    reads++;
    return inner.pinsAfter(after, limit: limit);
  }

  @override
  Future<void> put(ArtworkPinRecord pin) => inner.put(pin);

  @override
  Future<void> recordUrl(ArtworkPinRecord pin, String artUrl) =>
      inner.recordUrl(pin, artUrl);

  @override
  Future<void> removeExactly(String pid, List<OwedPin> pins) =>
      inner.removeExactly(pid, pins);

  @override
  Future<bool> mayPin(String pid) => inner.mayPin(pid);

  @override
  Future<List<ArtworkPinRecord>> clear() => inner.clear();
}

Future<ImageInfo> _resolve(ImageProvider provider) {
  final completer = Completer<ImageInfo>();
  provider
      .resolve(ImageConfiguration.empty)
      .addListener(
        ImageStreamListener(
          (ImageInfo info, bool _) {
            if (!completer.isCompleted) completer.complete(info);
          },
          onError: (Object error, StackTrace? stack) {
            if (!completer.isCompleted) completer.completeError(error, stack);
          },
        ),
      );
  return completer.future;
}
