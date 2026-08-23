import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waxdeck/src/artwork/artwork_store_io.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

const _base = 'http://deck.local:4420';
const _pid = 'tr-01JZX5N8QW3F4V9T2B7KD3M9R6';
const _art = '$_base/api/v1/items/$_pid/art';
const _station = 'https://logos.example.net/coastal-fm.png';

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
  late _FakeServer server;
  late CachedArtworkStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('waxdeck-artwork');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall call) async => temp.path,
        );
    db = inMemoryMirrorDatabase();
    pins = DriftArtworkPinStore(db);
    server = _FakeServer();
    store = CachedArtworkStore(
      baseUrl: _base,
      pins: pins,
      token: () => 'secret-token',
      client: Dio()..httpClientAdapter = server,
      pinDirectory: temp,
      cache: _UnreachableCache(),
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
      cache: _UnreachableCache(),
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

  test('a pinned cover is decoded to the size it is painted at', () async {
    // Through the pin, which is the only layer this harness can put
    // bytes into: the disk cache fetches with its own HTTP client, and
    // under `flutter test` that client is refused. The pinned copy is a
    // player-sized 640 by 480 and this paints a grid cell, so the
    // decode has real downscaling to do.
    server.serveBytes('$_art?size=1024', await _png(640, 480));
    server.serveBytes('$_art?size=256', await _png(160, 120));
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
    server.serveBytes('$_art?size=1024', await _png(64, 64));
    server.serveBytes('$_art?size=256', await _png(64, 64));
    await store.pinForOffline(_pid, _art);
    final counting = _CountingPinStore(pins);
    final store404 = CachedArtworkStore(
      baseUrl: _base,
      pins: counting,
      client: Dio()..httpClientAdapter = server,
      pinDirectory: temp,
      cache: _NotFoundCache(),
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

  test(
    'replacing a cover re-pins it, so offline gets the new one too',
    () async {
      server.serve('$_art?size=1024', 'old hero', etag: '"old-1024"');
      server.serve('$_art?size=256', 'old cell', etag: '"old-256"');
      await store.pinForOffline(_pid, _art);

      server.serve('$_art?size=1024', 'new hero', etag: '"new-1024"');
      server.serve('$_art?size=256', 'new cell', etag: '"new-256"');
      await store.evict(_art);

      final held = await pins.pinsFor(_pid);
      expect(held.first.etag, '"new-1024"');
      expect(File(held.first.localPath).readAsStringSync(), 'new hero');
    },
  );
}

/// A cache that cannot reach the server and is holding nothing: what a
/// device offline, or one whose cache has never seen an item, looks like
/// from the store's side.
class _UnreachableCache implements CacheManager {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getSingleFile) {
      throw const SocketException('no route to host');
    }
    if (invocation.memberName == #getFileFromCache) {
      return Future<FileInfo?>.value();
    }
    if (invocation.memberName == #removeFile ||
        invocation.memberName == #emptyCache ||
        invocation.memberName == #dispose) {
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
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

/// Counts pin lookups, to prove the ones that should not happen do not.
class _CountingPinStore implements ArtworkPinStore {
  _CountingPinStore(this.inner);

  final ArtworkPinStore inner;
  int lookups = 0;

  @override
  Future<List<ArtworkPinRecord>> pinsFor(String pid) {
    lookups++;
    return inner.pinsFor(pid);
  }

  @override
  Future<void> put(ArtworkPinRecord pin) => inner.put(pin);

  @override
  Future<List<ArtworkPinRecord>> remove(String pid) => inner.remove(pid);

  @override
  Future<List<ArtworkPinRecord>> clear() => inner.clear();
}

/// A solid PNG of a given size, so a decode has something real to chew.
Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF2E6F9E),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
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

/// The server, as far as the store can tell: canned replies by URL, a
/// connection error for everything else, and a record of what was asked.
class _FakeServer implements HttpClientAdapter {
  final Map<String, Uint8List> _bodies = <String, Uint8List>{};
  final Map<String, String?> _etags = <String, String?>{};
  final Set<String> _notModified = <String>{};
  final Map<String, Map<String, List<String>>> _headers =
      <String, Map<String, List<String>>>{};
  final List<String> requested = <String>[];

  void serve(String url, String body, {String? etag}) =>
      serveBytes(url, Uint8List.fromList(utf8.encode(body)), etag: etag);

  void serveBytes(String url, Uint8List body, {String? etag}) {
    _bodies[url] = body;
    _etags[url] = etag;
    _notModified.remove(url);
  }

  void serveNotModified(String url) => _notModified.add(url);

  Map<String, List<String>> headersFor(String url) =>
      _headers[url] ?? <String, List<String>>{};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    requested.add(url);
    _headers[url] = <String, List<String>>{
      for (final entry in options.headers.entries)
        entry.key: <String>['${entry.value}'],
    };
    if (_notModified.contains(url)) {
      return ResponseBody.fromBytes(Uint8List(0), 304);
    }
    final body = _bodies[url];
    if (body == null) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'no route to host',
      );
    }
    final etag = _etags[url];
    return ResponseBody.fromBytes(
      body,
      200,
      headers: <String, List<String>>{
        if (etag != null) 'etag': <String>[etag],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
