import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_precache.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/artwork/artwork_store.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

const _base = 'http://deck.local:4420';
const _art = '$_base/api/v1/items/tr-01JZX5N8QW3F4V9T2B7KD3M9R6/art';
const _station = 'https://logos.example.net/coastal-fm.png';

void main() {
  // PaintingBinding, for the eviction test: these are plain tests, so
  // nothing else brings a binding up.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('size rungs', () {
    test('a draw takes the smallest rung that covers it', () {
      expect(artworkRung(1), 64);
      expect(artworkRung(64), 64);
      expect(artworkRung(65), 128);
      expect(artworkRung(336), 512);
      expect(artworkRung(512), 512);
    });

    test('anything past the ladder takes the top rung, never a smaller '
        'one', () {
      // Upscaled artwork is visibly soft, and artwork is the surface
      // people look at.
      expect(artworkRung(1025), 1024);
      expect(artworkRung(4000), 1024);
    });

    test('a draw is decoded at a stepped size, so near-equal draws share '
        'one copy', () {
      // Flutter's cache holds one decoded copy per size, and a hero
      // measured from the window is a different size every frame of a
      // resize. Rounded up, never down: a copy decoded smaller than the
      // box it fills is soft.
      expect(artworkDrawSize(1), 32);
      expect(artworkDrawSize(200), 224);
      expect(artworkDrawSize(206), 224);
      expect(artworkDrawSize(224), 224);
      expect(artworkDrawSize(336), 352);
    });

    test('no draw is decoded larger than the largest rung fetched', () {
      expect(artworkDrawSize(1024), 1024);
      expect(artworkDrawSize(4000), 1024);
      expect(kArtworkDrawSizes.last, 1024);
      expect(kArtworkDrawSizes.first, 32);
    });

    test('stepping a draw never changes what is fetched for it', () {
      // The rungs are multiples of the step, so rounding a draw up
      // cannot push it past the rung that covers it.
      for (var px = 1; px <= 1200; px++) {
        expect(
          artworkRung(artworkDrawSize(px)),
          artworkRung(px),
          reason: '$px px',
        );
      }
    });

    test('every size a decode can be keyed at is on the ladder', () {
      // What makes eviction exact without any bookkeeping.
      for (var px = 1; px <= 1200; px += 7) {
        expect(kArtworkDrawSizes, contains(artworkDrawSize(px)));
      }
    });

    test('a size parameter joins the query rather than replacing it', () {
      expect(sizedArtUrl('$_art?role=back', 256), '$_art?role=back&size=256');
      expect(sizedArtUrl(_art, 64), '$_art?size=64');
    });

    // A station logo has no stored original to scale from, so `size` there
    // is accepted and ignored. Asking for a rung anyway splits one
    // identical body across a URL per rung.
    test('an endpoint with one rendition is asked for without a size', () {
      const logo = '/api/v1/radio/stations/rs-01JZX5N8QW3F4V9T2B7KD3M9R6/logo';
      expect(isUnsizedArtUrl(logo), isTrue);
      expect(isUnsizedArtUrl('$logo?v=3'), isTrue);
      expect(isUnsizedArtUrl(_art), isFalse);
      expect(sizedArtUrl(logo, null), logo);
      // A replacement still gets a name no cache has seen.
      expect(sizedArtUrl(logo, null, bust: 3), '$logo?v=3');
    });

    test('an art URL names the item it belongs to, which is how a pin is '
        'found', () {
      expect(artworkPidOf(_art), 'tr-01JZX5N8QW3F4V9T2B7KD3M9R6');
      expect(artworkPidOf('$_art?size=256'), 'tr-01JZX5N8QW3F4V9T2B7KD3M9R6');
      expect(artworkPidOf(_station), isNull);
    });
  });

  group('whose URL it is', () {
    test('relative URLs are ours: the SPA is served by the server', () {
      expect(isWaxDeckUrl('/api/v1/items/tr-1/art', ''), isTrue);
      expect(isWaxDeckUrl('/api/v1/items/tr-1/art', _base), isTrue);
    });

    test('absolute URLs are ours only under the configured origin', () {
      expect(isWaxDeckUrl(_art, _base), isTrue);
      expect(isWaxDeckUrl(_art, '$_base/'), isTrue);
      expect(isWaxDeckUrl(_station, _base), isFalse);
      // A host whose name starts with ours is a different host.
      expect(isWaxDeckUrl('${_base}x/api/v1/items/tr-1/art', _base), isFalse);
      // On web, absolute means somebody else's.
      expect(isWaxDeckUrl(_station, ''), isFalse);
    });

    test('a protocol-relative URL is somebody else, not a path', () {
      // `//host/logo.png` starts with a slash and is not ours: it is a
      // foreign host with the scheme left to the caller, and station
      // logos come from feeds that are free to write one. Reading it as
      // same-origin would hand that host the bearer token.
      expect(isWaxDeckUrl('//cdn.example.net/logo.png', ''), isFalse);
      expect(isWaxDeckUrl('//cdn.example.net/logo.png', _base), isFalse);
      expect(
        authHeadersFor('//cdn.example.net/logo.png', _base, () => 'secret'),
        isEmpty,
      );
    });

    test('a station host is never handed the caller token', () {
      // Radio logos are fetched straight from the station until the
      // proxy lands, so this is a routine path, and a bearer token on it
      // would be handing an arbitrary host the session.
      String? token() => 'secret-token';
      expect(authHeadersFor(_art, _base, token), <String, String>{
        'Authorization': 'Bearer secret-token',
      });
      expect(authHeadersFor(_station, _base, token), isEmpty);
      expect(authHeadersFor(_art, _base, null), isEmpty);
      expect(authHeadersFor(_art, _base, () => null), isEmpty);
    });
  });

  group('the network store', () {
    late NetworkArtworkStore store;

    setUp(() => store = NetworkArtworkStore(baseUrl: _base));
    tearDown(() => store.dispose());

    test('no URL is no artwork, which is a state and not a failure', () {
      expect(store.imageFor(null, 128), isNull);
      expect(store.imageFor('', 128), isNull);
      expect(store.source(null), isNull);
      expect(store.source(''), isNull);
    });

    test('a draw asks the server for the rung and decodes to the draw', () {
      final image = store.imageFor(_art, 336)! as ResizeImage;
      expect((image.imageProvider as NetworkImage).url, '$_art?size=512');
      // Decoded to what will be painted, not to what was fetched: the
      // rung above holds four times the pixels the screen shows.
      expect(image.width, 352);
      expect(image.height, 352);
      expect(image.policy, ResizeImagePolicy.fit);
      expect(image.allowUpscaling, isFalse);
    });

    test('two draws of the same cover at the same size are one cache '
        'entry', () {
      expect(store.imageFor(_art, 128), store.imageFor(_art, 128));
      expect(store.imageFor(_art, 128), isNot(store.imageFor(_art, 256)));
    });

    test('two draws a few pixels apart are one cache entry too', () {
      // A fractional grid extent, a window mid-resize: the same cover at
      // 200 and 206 is one decoded copy, not two.
      expect(store.imageFor(_art, 200), store.imageFor(_art, 206));
    });

    test('forgetting a cover drops it at every size it could be held '
        'at', () async {
      // The URL is stable across a cover change, so nothing else would
      // notice a replacement. Nothing is remembered to make this work:
      // the keys are made of a ladder, and this walks it.
      final drawn = <ImageProvider>[
        store.imageFor(_art, 48)!,
        store.imageFor(_art, 200)!,
        store.imageFor(_art, 336)!,
      ];
      final cache = PaintingBinding.instance.imageCache;
      final keys = <Object>[
        for (final image in drawn)
          await image.obtainKey(ImageConfiguration.empty),
      ];
      for (final key in keys) {
        // A load that never lands: the cache holds it as pending, which
        // is a cache entry as far as eviction is concerned and needs no
        // decoded bitmap to stand up.
        cache.putIfAbsent(
          key,
          () => OneFrameImageStreamCompleter(Completer<ImageInfo>().future),
        );
        expect(cache.containsKey(key), isTrue);
      }

      await store.evict(_art);

      for (final key in keys) {
        expect(cache.containsKey(key), isFalse);
      }
    });

    test('a replaced cover is asked for under a name no cache has '
        'seen', () async {
      // Dropping the decoded copy is all this process can do about the
      // browser's HTTP cache, which now holds the old bytes for a day.
      // Asking under a new name is the rest of it.
      final before = store.imageFor(_art, 128)! as ResizeImage;
      expect((before.imageProvider as NetworkImage).url, '$_art?size=128');

      await store.evict(_art);

      final after = store.imageFor(_art, 128)! as ResizeImage;
      expect((after.imageProvider as NetworkImage).url, '$_art?size=128&v=1');
      expect(after, isNot(before));
      // Another entity's cover is not caught up in it.
      expect(
        ((store.imageFor(_station, 96)! as ResizeImage).imageProvider
                as NetworkImage)
            .url,
        _station,
      );
    });

    test('a credential rides the image request, not just the byte '
        'fetch', () {
      // Web hands this an empty map (the browser attaches a cookie), and
      // that is what keeps the browser-native decode path. Native is
      // never given this store - but if it were, it would authenticate
      // rather than paint monograms over a whole library.
      final authed = NetworkArtworkStore(
        baseUrl: _base,
        token: () => 'secret-token',
      );
      addTearDown(authed.dispose);
      final image = authed.imageFor(_art, 128)! as ResizeImage;
      expect((image.imageProvider as NetworkImage).headers, <String, String>{
        'Authorization': 'Bearer secret-token',
      });
      expect(
        ((authed.imageFor(_station, 96)! as ResizeImage).imageProvider
                as NetworkImage)
            .headers,
        isEmpty,
      );
    });

    test('a foreign logo is fetched as it was given', () {
      final image = store.imageFor(_station, 96)! as ResizeImage;
      // No size parameter: a station host owes us no thumbnail API.
      expect((image.imageProvider as NetworkImage).url, _station);
      expect(image.width, 96);
    });

    test('the source hands the design system a function of the size', () {
      final source = store.source(_art)!;
      final image = source(64)! as ResizeImage;
      expect((image.imageProvider as NetworkImage).url, '$_art?size=64');
    });

    test('there is nothing to pin where there is no offline mode', () async {
      await store.pinForOffline('tr-1', _art);
      await store.unpin('tr-1');
    });

    test('a cover the server says is missing is asked for once, not once '
        'per draw', () async {
      // Every item carries an art URL whether or not there is anything
      // behind it, so an index of art-less rows asks per row and asks
      // again on every scroll back. Once the server has answered, the
      // monogram is the first thing drawn rather than the thing drawn
      // after a failed round trip.
      final absent = NetworkArtworkStore(
        baseUrl: _base,
        client: _fakeDio(<String, _Reply>{
          '$_art?size=128': const _Reply(status: 404),
        }),
      );
      addTearDown(absent.dispose);

      expect(absent.imageFor(_art, 128), isNotNull, reason: 'the first draw');
      expect(await absent.bytesFor(_art, 128), isNull);

      // Every size, not just the one that answered: the item has no
      // artwork at any rung.
      expect(absent.imageFor(_art, 128), isNull);
      expect(absent.imageFor(_art, 512), isNull);
      expect(absent.source(_art)!(128), isNull);

      // Another cover is not caught up in it.
      expect(absent.imageFor(_station, 96), isNotNull);
    });

    test('a cover appearing outlives the absence that was cached', () async {
      final absent = NetworkArtworkStore(
        baseUrl: _base,
        client: _fakeDio(<String, _Reply>{
          '$_art?size=128': const _Reply(status: 404),
          // A replaced cover is asked for under a name no cache has
          // seen, and this one is still not there either.
          '$_art?size=128&v=1': const _Reply(status: 404),
        }),
      );
      addTearDown(absent.dispose);
      expect(await absent.bytesFor(_art, 128), isNull);
      expect(absent.imageFor(_art, 128), isNull);

      // The invalidation that drops the old bytes drops this with them.
      await absent.evict(_art);
      expect(absent.imageFor(_art, 128), isNotNull);

      // As does signing out.
      expect(await absent.bytesFor(_art, 128), isNull);
      expect(absent.imageFor(_art, 128), isNull);
      await absent.forgetEverything();
      expect(absent.imageFor(_art, 128), isNotNull);

      // And so does the catalog changing, which is how a cover
      // normally appears: a scan reading embedded art, enrichment
      // landing, another device writing one. None of those routes
      // through evict, so this is the call the sync binder makes.
      expect(await absent.bytesFor(_art, 128), isNull);
      expect(absent.imageFor(_art, 128), isNull);
      absent.forgetAbsences();
      expect(absent.imageFor(_art, 128), isNotNull);
    });

    test('the absences remembered are bounded, and re-learning one pushes '
        'nothing out', () {
      // A library's art-less items are unbounded in principle, so the
      // set has a ceiling. Re-learning one already known has to be free:
      // several providers for the same cover at different sizes can be
      // in flight at once, and each 404 arrives on its own.
      final probe = _AbsenceProbe();
      probe.note('oldest');
      var filled = 0;
      while (probe.knows('oldest')) {
        probe.note('fill-${filled++}');
        if (filled > 1 << 20) fail('the absence set grows without bound');
      }

      // A fresh one filled to exactly the ceiling, keeping the oldest.
      final steady = _AbsenceProbe();
      steady.note('oldest');
      for (var i = 0; i < filled - 1; i++) {
        steady.note('fill-$i');
      }
      expect(steady.knows('oldest'), isTrue, reason: 'exactly full');

      // Told the same absence over and over, it displaces nothing: a
      // duplicate is not a new thing to remember.
      for (var i = 0; i < 100; i++) {
        steady.note('fill-0');
      }
      expect(steady.knows('oldest'), isTrue);
    });

    // The draw is the path this whole mechanism exists for: an index
    // row painting a cover, not anything calling bytesFor. It runs
    // through the provider the store hands out, so that is what these
    // resolve.
    group('learning from the draw itself', () {
      tearDown(() {
        debugNetworkImageHttpClientProvider = null;
        PaintingBinding.instance.imageCache.clear();
      });

      Future<void> draw(ArtworkStore store, String artUrl, int px) {
        final done = Completer<void>();
        void finish(Object? _, [Object? ignored]) {
          if (!done.isCompleted) done.complete();
        }

        store
            .imageFor(artUrl, px)!
            .resolve(ImageConfiguration.empty)
            .addListener(ImageStreamListener(finish, onError: finish));
        return done.future;
      }

      test('a 404 on the draw is what teaches the store', () async {
        final client = _StubHttpClient(status: 404);
        debugNetworkImageHttpClientProvider = () => client;
        final store = NetworkArtworkStore(baseUrl: _base);
        addTearDown(store.dispose);

        await draw(store, _art, 128);
        expect(client.requests, 1);

        // The next row drawing the same cover gets the monogram with no
        // provider at all, so there is nothing left to ask with.
        expect(store.imageFor(_art, 128), isNull);
        expect(store.imageFor(_art, 512), isNull);
        expect(client.requests, 1);
      });

      test('a server that cannot answer teaches it nothing', () async {
        // An outage arrives at the same listener as a 404 and must not
        // be mistaken for one, or the monogram outlives the outage.
        final client = _StubHttpClient(throws: true);
        debugNetworkImageHttpClientProvider = () => client;
        final store = NetworkArtworkStore(baseUrl: _base);
        addTearDown(store.dispose);

        await draw(store, _art, 128);
        expect(client.requests, 1);
        expect(store.imageFor(_art, 128), isNotNull);
      });

      test('a 500 is not an absent cover either', () async {
        final client = _StubHttpClient(status: 500);
        debugNetworkImageHttpClientProvider = () => client;
        final store = NetworkArtworkStore(baseUrl: _base);
        addTearDown(store.dispose);

        await draw(store, _art, 128);
        expect(store.imageFor(_art, 128), isNotNull);
      });
    });

    test('a server that cannot answer is not an item with no cover', () async {
      // An outage must not be remembered as an absence, or the monogram
      // outlives it.
      final offline = NetworkArtworkStore(
        baseUrl: _base,
        client: _fakeDio(const <String, _Reply>{}),
      );
      addTearDown(offline.dispose);
      expect(await offline.bytesFor(_art, 128), isNull);
      expect(offline.imageFor(_art, 128), isNotNull);
    });
  });

  group('warming a scroll ahead', () {
    test('warms what it is given, skipping the items with no art', () async {
      final store = _RecordingStore();
      ArtworkPrecacher(
        store,
      ).warmAhead(urls: <String?>['c', null, 'd'], px: 300);
      await pumpEventQueue();
      expect(store.warmed, <String>['c', 'd']);
      expect(store.pixels, <int>[300, 300]);
    });

    test('a later scroll supersedes the run in flight', () async {
      final store = _RecordingStore(gate: true);
      final precacher = ArtworkPrecacher(store);
      precacher.warmAhead(
        urls: <String?>['a', 'b', 'c', 'd', 'e', 'f'],
        px: 64,
      );
      await pumpEventQueue();
      precacher.warmAhead(urls: <String?>['x', 'y'], px: 64);
      store.release();
      await pumpEventQueue();
      // The first run got no further than the batch it was blocked on:
      // where the scroll stopped last is the better guess, and the rest
      // of the old window is never asked for.
      expect(store.warmed, <String>['a', 'b', 'c', 'x', 'y']);
    });

    test('a disposed precacher stops warming', () async {
      final store = _RecordingStore(gate: true);
      final precacher = ArtworkPrecacher(store);
      precacher.warmAhead(
        urls: <String?>['a', 'b', 'c', 'd', 'e', 'f'],
        px: 64,
      );
      await pumpEventQueue();
      precacher.dispose();
      store.release();
      await pumpEventQueue();
      expect(store.warmed, <String>['a', 'b', 'c']);
    });

    test('a store that throws does not take the warm loop with it', () async {
      // Nothing awaits the loop, so an escaping error is an unhandled
      // one.
      final store = _RecordingStore(throws: true);
      ArtworkPrecacher(
        store,
      ).warmAhead(urls: <String?>['a', 'b', 'c', 'd'], px: 64);
      await pumpEventQueue();
      expect(store.warmed, <String>['a', 'b', 'c', 'd']);
    });
  });

  group('image cache bounds', () {
    test('every platform gets an explicit bound, and a phone the '
        'tightest', () {
      final phone = artworkImageCacheBounds(
        web: false,
        platform: TargetPlatform.android,
      );
      final desktop = artworkImageCacheBounds(
        web: false,
        platform: TargetPlatform.linux,
      );
      final web = artworkImageCacheBounds(
        web: true,
        platform: TargetPlatform.linux,
      );
      expect(phone.$1, lessThan(desktop.$1));
      expect(web.$1, lessThan(desktop.$1));
      // The framework default is 100 MB for every platform alike, which
      // is the number this exists to stop being.
      expect(<int>[phone.$1, desktop.$1, web.$1], isNot(contains(100)));
    });
  });

  group('fetching', () {
    test('a 304 answers nothing: the caller already has these bytes', () async {
      final dio = _fakeDio(<String, _Reply>{
        '$_art?size=256': const _Reply(status: 304),
      });
      expect(await fetchArtwork(dio, '$_art?size=256'), isNull);
    });

    test(
      'a fetch answers the bytes and the validator to re-ask with',
      () async {
        final dio = _fakeDio(<String, _Reply>{
          '$_art?size=256': _Reply(
            status: 200,
            body: Uint8List.fromList(utf8.encode('cover')),
            etag: '"abc-256"',
          ),
        });
        final fetched = await fetchArtwork(dio, '$_art?size=256');
        expect(utf8.decode(fetched!.bytes), 'cover');
        expect(fetched.etag, '"abc-256"');
      },
    );

    test('an unreachable server is a monogram, not an exception', () async {
      final dio = _fakeDio(const <String, _Reply>{});
      expect(await fetchArtwork(dio, '$_art?size=256'), isNull);
    });
  });
}

/// Answers every image request with one status, or refuses to answer at
/// all, so a draw can be made to fail the way a real one does.
///
/// Through noSuchMethod because `HttpClient` is a wide interface and the
/// image loader touches four of it: `getUrl`, the request's headers and
/// `close`, and the response's `statusCode` and `drain`.
class _StubHttpClient implements HttpClient {
  _StubHttpClient({this.status = 200, this.throws = false});

  final int status;
  final bool throws;
  int requests = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getUrl) {
      requests++;
      if (throws) {
        return Future<HttpClientRequest>.error(
          const SocketException('no route to host'),
        );
      }
      return Future<HttpClientRequest>.value(_StubRequest(status));
    }
    return super.noSuchMethod(invocation);
  }
}

class _StubRequest implements HttpClientRequest {
  _StubRequest(this.status);

  final int status;

  @override
  HttpHeaders get headers => _StubHeaders();

  @override
  Future<HttpClientResponse> close() async => _StubResponse(status);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubHeaders implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubResponse implements HttpClientResponse {
  _StubResponse(this.statusCode);

  @override
  final int statusCode;

  @override
  Future<E> drain<E>([E? futureValue]) async => futureValue as E;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Reaches the base store's absence bookkeeping, which is protected
/// because only a store implementation has any business recording one.
class _AbsenceProbe extends ArtworkStore {
  @override
  String get baseUrl => '';

  void note(String artUrl) => noteAbsent(artUrl);

  bool knows(String artUrl) => knownAbsent(artUrl);

  @override
  ImageProvider? imageFor(String? artUrl, int px) => null;

  @override
  Future<Uint8List?> bytesFor(String artUrl, int px) async => null;

  @override
  Future<void> warm(String artUrl, int px) async {}

  @override
  Future<void> pinForOffline(String pid, String? artUrl) async {}

  @override
  Future<void> unpin(String pid) async {}

  @override
  Future<void> evict(String artUrl) async {}

  @override
  Future<void> forgetEverything() async {}

  @override
  void dispose() {}
}

/// A store that records what it was asked to warm, and can be made to
/// block on the first request so a second run can overtake it.
class _RecordingStore extends ArtworkStore {
  _RecordingStore({bool gate = false, this.throws = false})
    : _gate = gate ? Completer<void>() : null;

  final Completer<void>? _gate;
  final bool throws;
  final List<String> warmed = <String>[];
  final List<int> pixels = <int>[];

  @override
  String get baseUrl => '';

  void release() => _gate?.complete();

  @override
  Future<void> warm(String artUrl, int px) async {
    warmed.add(artUrl);
    pixels.add(px);
    if (_gate != null && !_gate.isCompleted) await _gate.future;
    if (throws) throw StateError('the cache is on fire');
  }

  @override
  ImageProvider? imageFor(String? artUrl, int px) => null;

  @override
  Future<Uint8List?> bytesFor(String artUrl, int px) async => null;

  @override
  Future<void> pinForOffline(String pid, String? artUrl) async {}

  @override
  Future<void> unpin(String pid) async {}

  @override
  Future<void> evict(String artUrl) async {}

  @override
  Future<void> forgetEverything() async {}

  @override
  void dispose() {}
}

class _Reply {
  const _Reply({required this.status, this.body, this.etag});

  final int status;
  final Uint8List? body;
  final String? etag;
}

Dio _fakeDio(Map<String, _Reply> replies) =>
    Dio()..httpClientAdapter = _FakeAdapter(replies);

/// Answers the canned replies and refuses everything else, standing in
/// for a server that is not there.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.replies);

  final Map<String, _Reply> replies;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final reply = replies[options.uri.toString()];
    if (reply == null) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'no route to host',
      );
    }
    return ResponseBody.fromBytes(
      reply.body ?? Uint8List(0),
      reply.status,
      headers: <String, List<String>>{
        if (reply.etag != null) 'etag': <String>[reply.etag!],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
