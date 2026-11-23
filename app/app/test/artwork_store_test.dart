import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_precache.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/artwork/artwork_store.dart';
import 'package:waxdeck/src/settings/client_settings/browser_settings_store.dart';
import 'package:waxdeck_data/waxdeck_data.dart' show OwedPin;
import 'package:waxdeck_ui/waxdeck_ui.dart';

const _base = 'http://deck.local:4420';
const _art = '$_base/api/v1/items/tr-01JZX5N8QW3F4V9T2B7KD3M9R6/art';
const _other = '$_base/api/v1/items/al-01JZX5N8QW3F4V9T2B7KD3M9R7/art';
const _station = 'https://logos.example.net/coastal-fm.png';
const _third = '$_base/api/v1/items/ar-01JZX5N8QW3F4V9T2B7KD3M9R8/art';

/// Every URL [artUrl]'s entity draws a cover from: one per role.
List<String> _roles(String artUrl) => [
  artUrl,
  for (final role in ['back', 'disc', 'booklet', 'background'])
    '$artUrl?role=$role',
];

/// The URL a draw of [artUrl] at 128 pixels is fetched from.
String _asked(ArtworkStore store, [String artUrl = _art]) =>
    ((store.imageFor(artUrl, 128)! as ResizeImage).imageProvider
            as NetworkImage)
        .url;

/// The tag [url] is asked under, or null when it carries none.
int? _tagOf(String url) {
  final tag = Uri.parse(url).queryParameters['v'];
  return tag == null ? null : int.parse(tag);
}

void main() {
  // PaintingBinding, for the eviction test: these are plain tests, so
  // nothing else brings a binding up.
  TestWidgetsFlutterBinding.ensureInitialized();

  // The wall clock every store here reads, so a tag is a known number
  // and a later session is later by exactly what a test says.
  late DateTime at;
  DateTime now() => at;
  setUp(() => at = DateTime.utc(2026, 11, 18, 12));

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

    test('a URL that carries its own v is never given another', () {
      // A station's now-playing cover is asked for by a key the server
      // minted, in the same parameter: it names the bytes already, and
      // writing a tag over it asks for a cover that is not there.
      const playing =
          '/api/v1/radio/stations/rs-01JZX5N8QW3F4V9T2B7KD3M9R6'
          '/now-playing-art?v=0123abcd';
      expect(sizedArtUrl(playing, null, bust: 7), playing);
      expect(sizedArtUrl('$_art?v=k', 64, bust: 7), '$_art?v=k&size=64');
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

    setUp(
      () => store = NetworkArtworkStore(
        baseUrl: _base,
        replaced: ReplacedCovers(now: now),
      ),
    );
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
      expect(
        (after.imageProvider as NetworkImage).url,
        '$_art?size=128&v=${at.microsecondsSinceEpoch}',
      );
      expect(after, isNot(before));
      // Another entity's cover is not caught up in it.
      expect(
        ((store.imageFor(_station, 96)! as ResizeImage).imageProvider
                as NetworkImage)
            .url,
        _station,
      );
    });

    test('evicting one role of a cover asks every role of it under one new '
        'name, and no other cover', () async {
      await store.evict('$_art?role=back');

      final tag = at.microsecondsSinceEpoch;
      for (final url in _roles(_art)) {
        expect(_tagOf(_asked(store, url)), tag, reason: url);
      }
      expect(_asked(store, _other), '$_other?size=128');
      expect(_asked(store, '$_other?role=back'), '$_other?role=back&size=128');
    });

    test('evicting one role of a cover drops every role it is held '
        'under', () async {
      final cache = PaintingBinding.instance.imageCache;
      final keys = <Object>[
        for (final url in _roles(_art))
          await store.imageFor(url, 200)!.obtainKey(ImageConfiguration.empty),
      ];
      for (final key in keys) {
        cache.putIfAbsent(
          key,
          () => OneFrameImageStreamCompleter(Completer<ImageInfo>().future),
        );
      }

      await store.evict(_art);

      for (final key in keys) {
        expect(cache.containsKey(key), isFalse);
      }
    });

    test('a cover replaced forgets every role it was known missing '
        'at', () {
      final probe = _StoreProbe();
      for (final url in [..._roles(_art), _other]) {
        probe.note(url, 128);
      }
      probe.replace('$_art?role=disc');
      for (final url in _roles(_art)) {
        expect(probe.knows(url, 128), isFalse, reason: url);
      }
      expect(probe.knows(_other, 128), isTrue);
    });

    test('an eviction renames the cover before its first await', () async {
      // What lets a write sweep its reads in the turn it evicts in.
      final evicting = store.evict(_art);

      final after = store.imageFor(_art, 128)! as ResizeImage;
      expect(
        (after.imageProvider as NetworkImage).url,
        '$_art?size=128&v=${at.microsecondsSinceEpoch}',
      );
      await evicting;
    });

    test('covers replaced with nothing to say which are all asked for '
        'under one new name, set before the first await', () async {
      await store.evict(_art);
      final own = _tagOf(_asked(store))!;
      at = at.add(const Duration(seconds: 1));

      final evicting = store.evictAll();

      // The replaced one and one nobody named alike, past any tag held.
      final floor = _tagOf(_asked(store, _other));
      expect(floor, at.microsecondsSinceEpoch);
      expect(floor, greaterThan(own));
      expect(_tagOf(_asked(store)), floor);
      // Somebody else's picture is asked for as it was given.
      expect(
        ((store.imageFor(_station, 96)! as ResizeImage).imageProvider
                as NetworkImage)
            .url,
        _station,
      );
      await evicting;

      // One replaced after that is asked for past it, alone.
      await store.evict(_art);
      expect(_tagOf(_asked(store)), greaterThan(floor!));
      expect(_tagOf(_asked(store, _other)), floor);
    });

    test('asked afresh twice in one tick of the clock, every cover has a '
        'new name each time', () async {
      await store.evictAll();
      final first = _tagOf(_asked(store))!;
      await store.evictAll();
      expect(_tagOf(_asked(store)), first + 1);

      // A clock gone backwards does not hand an old name out again.
      await store.evict(_art);
      final own = _tagOf(_asked(store))!;
      at = at.subtract(const Duration(minutes: 1));
      await store.evictAll();
      expect(_tagOf(_asked(store)), own + 1);
      expect(_tagOf(_asked(store, _other)), own + 1);
    });

    test('covers asked afresh are no longer known to be missing', () {
      final probe = _StoreProbe(replaced: ReplacedCovers(now: now))
        ..note(_art, 128)
        ..note(_other, 512);

      probe.replaceAll();

      expect(probe.knows(_art, 128), isFalse);
      expect(probe.knows(_other, 512), isFalse);
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

      // The rung that answered is settled - and only that rung: an
      // unscalable original 404s a thumbnail rung while a larger one,
      // or the whole picture, still answers.
      expect(absent.imageFor(_art, 128), isNull);
      expect(absent.source(_art)!(128), isNull);
      expect(absent.imageFor(_art, 512), isNotNull);

      // Another cover is not caught up in it.
      expect(absent.imageFor(_station, 96), isNotNull);
    });

    test('a cover appearing outlives the absence that was cached', () async {
      final absent = NetworkArtworkStore(
        baseUrl: _base,
        replaced: ReplacedCovers(now: now),
        client: _fakeDio(<String, _Reply>{
          '$_art?size=128': const _Reply(status: 404),
          // A replaced cover is asked for under a name no cache has
          // seen, and this one is still not there either.
          '$_art?size=128&v=${at.microsecondsSinceEpoch}': const _Reply(
            status: 404,
          ),
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
      final probe = _StoreProbe();
      probe.note('oldest');
      var filled = 0;
      while (probe.knows('oldest')) {
        probe.note('fill-${filled++}');
        if (filled > 1 << 20) fail('the absence set grows without bound');
      }

      // A fresh one filled to exactly the ceiling, keeping the oldest.
      final steady = _StoreProbe();
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

    test('forgetting one cover forgets it at every rung, and no other '
        'cover', () {
      final probe = _StoreProbe();
      for (final url in <String>[_art, _other]) {
        probe.note(url);
        for (final rung in kArtworkRungs) {
          probe.note(url, rung);
        }
      }
      probe.forget(_art);
      expect(probe.knows(_art), isFalse);
      expect(probe.knows(_other), isTrue);
      for (final rung in kArtworkRungs) {
        expect(probe.knows(_art, rung), isFalse, reason: '$rung');
        expect(probe.knows(_other, rung), isTrue, reason: '$rung');
      }
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

        // The next row drawing the same cover at the same rung gets the
        // monogram with no provider at all; another rung still asks,
        // since the server refuses some sizes of a cover it serves
        // whole.
        expect(store.imageFor(_art, 128), isNull);
        expect(store.imageFor(_art, 512), isNotNull);
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

  group('a replaced cover, across sessions', () {
    Map<String, dynamic> stored(_TagStorage storage) =>
        (jsonDecode(storage.values[ReplacedCovers.storageKey]!)
                as Map<String, dynamic>)['tags']
            as Map<String, dynamic>;

    test('a cover replaced before a reload is asked for under the same '
        'name after it', () async {
      final storage = _TagStorage();
      final first = NetworkArtworkStore(
        baseUrl: _base,
        replaced: ReplacedCovers(storage: storage, now: now),
      );
      addTearDown(first.dispose);
      await first.evict(_art);
      final tagged = _asked(first);
      expect(_tagOf(tagged), isNotNull);

      // A reload tells nobody: nothing ends the first session, and the
      // write has to have happened on its own.
      await pumpEventQueue();
      at = at.add(const Duration(hours: 3));
      final second = NetworkArtworkStore(
        baseUrl: _base,
        replaced: ReplacedCovers(storage: storage, now: now),
      );
      addTearDown(second.dispose);
      expect(_asked(second), tagged);
      // A cover nobody replaced is asked for as it always was.
      expect(_asked(second, _other), '$_other?size=128');
    });

    test('signing out leaves storage no art URL, and every replacement '
        'still stands', () async {
      final storage = _TagStorage();
      final first = NetworkArtworkStore(
        baseUrl: _base,
        replaced: ReplacedCovers(storage: storage, now: now),
      );
      addTearDown(first.dispose);
      await first.evict(_art);
      final own = _tagOf(_asked(first))!;
      at = at.add(const Duration(minutes: 1));
      await first.evict(_other);
      final newest = _tagOf(_asked(first, _other))!;
      await pumpEventQueue();
      expect(storage.values[ReplacedCovers.storageKey], contains('/items/'));
      final writes = storage.writes;

      await first.forgetEverything();

      // One write, at once: a sign-out can be the last thing a page does.
      expect(storage.writes, writes + 1);
      expect(storage.values[ReplacedCovers.storageKey], isNot(contains('/')));
      expect(stored(storage), isEmpty);
      // The browser's cache outlives the session, so what was replaced
      // is still asked for under a name at least as new as its own.
      expect(_tagOf(_asked(first)), greaterThanOrEqualTo(own));
      expect(_tagOf(_asked(first, _other)), newest);
      final second = NetworkArtworkStore(
        baseUrl: _base,
        replaced: ReplacedCovers(storage: storage, now: now),
      );
      addTearDown(second.dispose);
      expect(_tagOf(_asked(second)), greaterThanOrEqualTo(own));
      expect(_tagOf(_asked(second, _other)), newest);
    });

    test('covers asked afresh before a reload are asked for under the '
        'same name after it, and storage names none of them', () async {
      final storage = _TagStorage();
      final first = NetworkArtworkStore(
        baseUrl: _base,
        replaced: ReplacedCovers(storage: storage, now: now),
      );
      await first.evictAll();
      // Written on its own, as a replacement is: a reload tells nobody.
      await pumpEventQueue();
      expect(storage.writes, 1);

      at = at.add(const Duration(minutes: 1));
      await first.evict(_art);
      at = at.add(const Duration(minutes: 1));
      await first.evictAll();
      final floor = _tagOf(_asked(first, _other));
      expect(floor, at.microsecondsSinceEpoch);
      first.dispose();
      expect(stored(storage), isEmpty);

      at = at.add(const Duration(hours: 3));
      final second = NetworkArtworkStore(
        baseUrl: _base,
        replaced: ReplacedCovers(storage: storage, now: now),
      );
      addTearDown(second.dispose);
      expect(_tagOf(_asked(second)), floor);
      expect(_tagOf(_asked(second, _other)), floor);
    });

    test('a stored tag or floor further ahead of the clock than the cache '
        'lifetime is not believed', () {
      // A clock once wrong, a hand edit. Believed, it would never expire,
      // and every tag after it would be one more than the last.
      final storage = _TagStorage();
      final clock = at.microsecondsSinceEpoch;
      final edge = clock + kArtworkCacheLifetime.inMicroseconds;
      ReplacedCovers holding(int tag) {
        storage.values[ReplacedCovers.storageKey] = jsonEncode(<String, Object>{
          'floor': tag,
          'tags': <String, int>{'/art/a': tag + 1},
        });
        return ReplacedCovers(storage: storage, now: now);
      }

      final past = holding(edge + 1);
      expect(past.tagFor('/art/a'), isNull);
      expect(past.tagFor('/art/never'), isNull);
      past.note('/art/a');
      expect(past.tagFor('/art/a'), clock);
      past.close();

      final within = holding(edge - 1);
      expect(within.tagFor('/art/a'), edge);
      expect(within.tagFor('/art/never'), edge - 1);
    });

    test('a replacement the browser can no longer answer stale for is '
        'forgotten', () async {
      final storage = _TagStorage();
      final first = NetworkArtworkStore(
        baseUrl: _base,
        replaced: ReplacedCovers(storage: storage, now: now),
      );
      await first.evict(_art);
      final tagged = _asked(first);
      first.dispose();

      // One second short of the endpoint's freshness plus its
      // stale-while-revalidate window, the old bytes may still be served.
      at = at.add(kArtworkCacheLifetime - const Duration(seconds: 1));
      final within = NetworkArtworkStore(
        baseUrl: _base,
        replaced: ReplacedCovers(storage: storage, now: now),
      );
      expect(_asked(within), tagged);
      within.dispose();

      at = at.add(const Duration(seconds: 1));
      final past = NetworkArtworkStore(
        baseUrl: _base,
        replaced: ReplacedCovers(storage: storage, now: now),
      );
      expect(_asked(past), '$_art?size=128');
      // And is not written back with the next replacement.
      await past.evict(_other);
      past.dispose();
      expect(stored(storage).keys, <String>[_other]);
    });

    test('two stores made one after the other never mint the same tag for '
        'one URL', () async {
      // No storage: the native store remembers nothing, so the tag alone
      // has to keep a later session off an earlier one's names.
      final seen = <int>[];
      Future<void> replaceIn(ArtworkStore store) async {
        // Several inside one tick of the clock, which is what a burst is.
        for (var i = 0; i < 5; i++) {
          await store.evict(_art);
          final tag = _tagOf(_asked(store))!;
          expect(seen, isNot(contains(tag)));
          if (seen.isNotEmpty) expect(tag, greaterThan(seen.last));
          seen.add(tag);
        }
      }

      final first = NetworkArtworkStore(
        baseUrl: _base,
        replaced: ReplacedCovers(now: now),
      );
      addTearDown(first.dispose);
      await replaceIn(first);

      // The next session starts at least a tick later, and a browser's
      // clock ticks in milliseconds.
      at = at.add(const Duration(milliseconds: 1));
      final second = NetworkArtworkStore(
        baseUrl: _base,
        replaced: ReplacedCovers(now: now),
      );
      addTearDown(second.dispose);
      await replaceIn(second);
    });

    test('a clock that went backwards mints past what storage holds', () async {
      final storage = _TagStorage();
      final first = NetworkArtworkStore(
        baseUrl: _base,
        replaced: ReplacedCovers(storage: storage, now: now),
      );
      await first.evict(_art);
      final before = _tagOf(_asked(first))!;
      first.dispose();

      at = at.subtract(const Duration(hours: 1));
      final second = NetworkArtworkStore(
        baseUrl: _base,
        replaced: ReplacedCovers(storage: storage, now: now),
      );
      addTearDown(second.dispose);
      await second.evict(_art);
      expect(_tagOf(_asked(second)), greaterThan(before));
    });

    test('past the cap the older half stands under one tag, at least as '
        'new as each of its own', () {
      final storage = _TagStorage();
      final covers = ReplacedCovers(storage: storage, now: now);
      final probe = _StoreProbe(replaced: covers);
      void replace(String artUrl) {
        at = at.add(const Duration(milliseconds: 1));
        probe.replace(artUrl);
      }

      replace('/art/oldest');
      final own = probe.tagOf('/art/oldest')!;
      for (var i = 0; i < ReplacedCovers.maxEntries - 1; i++) {
        replace('/art/fill-$i');
      }
      // Replacing one again makes it the newest, not a second entry.
      replace('/art/fill-0');
      // Exactly full: nothing stands in for anything, and a cover nobody
      // replaced is asked for as it always was.
      expect(probe.tagOf('/art/oldest'), own);
      expect(probe.tagOf('/art/never'), isNull);

      replace('/art/one-more');
      final floor = probe.tagOf('/art/never');
      expect(floor, isNotNull, reason: 'a floor stands');
      expect(floor, greaterThanOrEqualTo(own));
      expect(probe.tagOf('/art/oldest'), floor);
      // The newer half keep their own.
      final newest = probe.tagOf('/art/one-more')!;
      expect(newest, greaterThan(floor!));
      expect(probe.tagOf('/art/fill-0'), inExclusiveRange(floor, newest));

      // One the floor stands for, replaced again, is asked past it.
      replace('/art/oldest');
      final again = probe.tagOf('/art/oldest')!;
      expect(again, greaterThan(newest));

      // A reload asks under the same names.
      covers.close();
      expect(
        stored(storage).length,
        lessThanOrEqualTo(ReplacedCovers.maxEntries),
      );
      final reloaded = _StoreProbe(
        replaced: ReplacedCovers(storage: storage, now: now),
      );
      expect(reloaded.tagOf('/art/fill-1'), floor);
      expect(reloaded.tagOf('/art/never'), floor);
      expect(reloaded.tagOf('/art/one-more'), newest);
      expect(reloaded.tagOf('/art/oldest'), again);
    });

    test('every role of one cover replaced is one entry, and moves no '
        'floor', () {
      final storage = _TagStorage();
      final covers = ReplacedCovers(storage: storage, now: now);
      final probe = _StoreProbe(replaced: covers);
      void replace(String artUrl) {
        at = at.add(const Duration(milliseconds: 1));
        probe.replace(artUrl);
      }

      for (var i = 0; i < ReplacedCovers.maxEntries - 1; i++) {
        replace('/art/fill-$i');
      }
      // What a frame naming one entity does, until it names it once.
      for (final url in _roles(_art)) {
        replace(url);
      }

      expect(probe.tagOf('/art/never'), isNull, reason: 'no floor');
      covers.close();
      expect(stored(storage), hasLength(ReplacedCovers.maxEntries));
      expect(stored(storage).keys.where((key) => key.contains('/items/')), [
        _art,
      ]);
    });

    test('a table written before covers were kept by entity still protects '
        'every role of them after an upgrade', () async {
      final storage = _TagStorage();
      final back = at.subtract(const Duration(hours: 1)).microsecondsSinceEpoch;
      final front = at
          .subtract(const Duration(hours: 2))
          .microsecondsSinceEpoch;
      storage.values[ReplacedCovers.storageKey] = jsonEncode({
        'tags': {
          '$_art?role=back': back,
          _art: front,
          '$_other?role=disc': front,
        },
      });

      final upgraded = NetworkArtworkStore(
        baseUrl: _base,
        replaced: ReplacedCovers(storage: storage, now: now),
      );
      for (final url in _roles(_art)) {
        expect(_tagOf(_asked(upgraded, url)), back, reason: url);
      }
      for (final url in _roles(_other)) {
        expect(_tagOf(_asked(upgraded, url)), front, reason: url);
      }

      // Written back by entity.
      await upgraded.evict(_third);
      upgraded.dispose();
      expect(stored(storage), {_art: back, _other: front, _third: isA<int>()});
    });

    test('a cover that names its bytes itself takes no entry', () {
      final storage = _TagStorage();
      final covers = ReplacedCovers(storage: storage, now: now);
      final probe = _StoreProbe(replaced: covers);
      const nowPlaying = '/api/v1/radio/stations/rs-1/now-playing-art?v=k1';
      final told = <String>[];
      probe.source(nowPlaying)!.replaced!.addListener(() => told.add('told'));

      probe.replace(nowPlaying);
      covers.close();

      expect(told, ['told']);
      expect(storage.values[ReplacedCovers.storageKey], isNull);
    });

    test('the floor moves once per half of the cap, not per '
        'replacement', () {
      final probe = _StoreProbe(replaced: ReplacedCovers(now: now));
      final floors = <int>[];
      // One past the cap sets it; each half-cap and one after moves it.
      const total = ReplacedCovers.maxEntries * 2 + 3;
      for (var i = 0; i < total; i++) {
        at = at.add(const Duration(milliseconds: 1));
        probe.replace('/art/$i');
        final floor = probe.tagOf('/art/never');
        if (floor != null && (floors.isEmpty || floors.last != floor)) {
          floors.add(floor);
        }
      }
      expect(floors, hasLength(3));
      expect(floors[1], greaterThan(floors[0]));
      expect(floors[2], greaterThan(floors[1]));
    });

    test('a floor the browser can no longer answer stale under is '
        'forgotten', () {
      final storage = _TagStorage();
      final covers = ReplacedCovers(storage: storage, now: now);
      final probe = _StoreProbe(replaced: covers);
      for (var i = 0; i <= ReplacedCovers.maxEntries; i++) {
        at = at.add(const Duration(milliseconds: 1));
        probe.replace('/art/$i');
      }
      covers.close();
      final floor = probe.tagOf('/art/never');
      expect(floor, isNotNull, reason: 'a floor stands');
      final newest = probe.tagOf('/art/${ReplacedCovers.maxEntries}')!;
      final set = DateTime.fromMicrosecondsSinceEpoch(floor!, isUtc: true);

      at = set.add(kArtworkCacheLifetime - const Duration(seconds: 1));
      final within = _StoreProbe(
        replaced: ReplacedCovers(storage: storage, now: now),
      );
      expect(within.tagOf('/art/0'), floor);
      expect(within.tagOf('/art/never'), floor);

      // Everything it stood for was replaced no later than it was.
      at = set.add(kArtworkCacheLifetime);
      final past = _StoreProbe(
        replaced: ReplacedCovers(storage: storage, now: now),
      );
      expect(past.tagOf('/art/0'), isNull);
      expect(past.tagOf('/art/never'), isNull);
      // What was replaced after it has its own time left.
      expect(past.tagOf('/art/${ReplacedCovers.maxEntries}'), newest);
    });

    test('what storage holds past the cap is cut on load, the older ones '
        'under a floor', () {
      final storage = _TagStorage();
      final base = at.microsecondsSinceEpoch;
      const count = ReplacedCovers.maxEntries + 10;
      storage.values[ReplacedCovers.storageKey] = jsonEncode(<String, Object>{
        'tags': <String, int>{
          // Newest first, as a store that orders by tag must not assume.
          for (var i = count - 1; i >= 0; i--) '/art/$i': base + i,
        },
      });
      at = at.add(const Duration(minutes: 1));
      final probe = _StoreProbe(
        replaced: ReplacedCovers(storage: storage, now: now),
      );
      final floor = probe.tagOf('/art/never');
      expect(floor, isNotNull, reason: 'a floor stands');
      expect(floor, inInclusiveRange(base + 9, base + count - 2));
      expect(probe.tagOf('/art/0'), floor);
      expect(probe.tagOf('/art/${floor! - base}'), floor);
      expect(probe.tagOf('/art/${floor - base + 1}'), floor + 1);
      expect(probe.tagOf('/art/${count - 1}'), base + count - 1);
    });

    test('a floor another tab stored outranks an older tag held here', () {
      // The other tab replaced this cover again and then dropped it under
      // its floor: the entry held here is older than the latest bytes.
      final storage = _TagStorage();
      final covers = ReplacedCovers(storage: storage, now: now);
      final probe = _StoreProbe(replaced: covers);
      probe.replace('/art/a');
      final held = probe.tagOf('/art/a')!;
      covers.close();

      storage.values[ReplacedCovers.storageKey] = jsonEncode(<String, Object>{
        'floor': held + 5000,
        'tags': <String, int>{},
      });
      at = at.add(const Duration(seconds: 1));
      probe.replace('/art/b');
      covers.close();

      expect(probe.tagOf('/art/a'), held + 5000);
      expect(probe.tagOf('/art/b'), at.microsecondsSinceEpoch);
    });

    test('storage that refuses, is absent or holds something else leaves '
        'the store working for the session', () async {
      final refusing = _TagStorage()..refuses = true;
      // A full quota: it reads, and only the write is refused.
      final full = _TagStorage()..refusesWrites = true;
      final storages = <BrowserStorage?>[
        null,
        refusing,
        full,
        for (final junk in <String>[
          'not json',
          '[1, 2]',
          '{"$_art": 5}',
          '{"floor": "x", "tags": {"$_art": "x"}}',
          '{"floor": 1.5, "tags": [1]}',
        ])
          _TagStorage()..values[ReplacedCovers.storageKey] = junk,
      ];
      for (final storage in storages) {
        final store = NetworkArtworkStore(
          baseUrl: _base,
          replaced: ReplacedCovers(storage: storage, now: now),
        );
        expect(_asked(store), '$_art?size=128');
        await store.evict(_art);
        // A write that is refused must not escape the timer it rides.
        await pumpEventQueue();
        final first = _tagOf(_asked(store));
        expect(first, at.microsecondsSinceEpoch);
        await store.evict(_art);
        final second = _tagOf(_asked(store))!;
        expect(second, greaterThan(first!));
        // Nor the write a sign-out makes, nor the one an end makes.
        await store.forgetEverything();
        expect(_tagOf(_asked(store)), second);
        await store.evict(_art);
        store.dispose();
      }
      expect(refusing.values, isEmpty);
      expect(full.values, isEmpty);
    });

    testWidgets('a burst of replacements is one write, and a storm of them '
        'one write an interval', (tester) async {
      final storage = _TagStorage();
      final store = NetworkArtworkStore(
        baseUrl: _base,
        replaced: ReplacedCovers(storage: storage, now: now),
      );
      Future<void> burst(String name) async {
        for (var i = 0; i < 64; i++) {
          await store.evict('$_base/api/v1/items/tr-$name$i/art');
        }
      }

      await burst('a');
      expect(storage.writes, 0, reason: 'no replacement writes for itself');
      await tester.pump(Duration.zero);
      expect(storage.writes, 1);
      expect(stored(storage), hasLength(64));

      // More arriving while the last write is still recent wait for the
      // interval, however many batches that is.
      await burst('b');
      await tester.pump(Duration.zero);
      await burst('c');
      await tester.pump(
        ReplacedCovers.writeEvery - const Duration(milliseconds: 1),
      );
      expect(storage.writes, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(storage.writes, 2);
      expect(stored(storage), hasLength(192));

      // Nothing replaced, nothing written.
      await tester.pump(ReplacedCovers.writeEvery * 3);
      expect(storage.writes, 2);

      // An end that is announced writes what is still waiting.
      await burst('d');
      await tester.pump(Duration.zero);
      await burst('e');
      store.dispose();
      expect(storage.writes, 4);
      expect(stored(storage), hasLength(320));
      await tester.pump(ReplacedCovers.writeEvery * 3);
      expect(storage.writes, 4);
    });

    test('a write keeps what another tab stored since, and takes its tags '
        'up', () async {
      final storage = _TagStorage();
      final one = NetworkArtworkStore(
        baseUrl: _base,
        replaced: ReplacedCovers(storage: storage, now: now),
      );
      final two = NetworkArtworkStore(
        baseUrl: _base,
        replaced: ReplacedCovers(storage: storage, now: now),
      );
      addTearDown(one.dispose);
      addTearDown(two.dispose);

      await one.evict(_art);
      await pumpEventQueue();
      at = at.add(const Duration(seconds: 5));
      await two.evict(_other);
      await pumpEventQueue();

      expect(stored(storage).keys, <String>[_art, _other]);
      expect(_asked(two), _asked(one));
    });
  });

  group('a refresh owed to every cover', () {
    Map<String, dynamic> held(_TagStorage storage) =>
        jsonDecode(storage.values[ReplacedCovers.storageKey]!)
            as Map<String, dynamic>;

    NetworkArtworkStore over(BrowserStorage? storage) {
      final store = NetworkArtworkStore(
        baseUrl: _base,
        replaced: ReplacedCovers(storage: storage, now: now),
      );
      addTearDown(store.dispose);
      return store;
    }

    test('is made by the next store over the same storage, before anything '
        'is asked, and then owed no more', () {
      final storage = _TagStorage();
      final first = over(storage);
      first.oweEvictAll();
      // Written at once: a reload tells nobody, and neither does a kill.
      expect(storage.writes, 1);
      expect(held(storage)['owed'], at.microsecondsSinceEpoch);
      // Owing asks nothing afresh by itself.
      expect(_asked(first), '$_art?size=128');

      at = at.add(const Duration(hours: 3));
      final second = over(storage);
      expect(_tagOf(_asked(second)), at.microsecondsSinceEpoch);
      expect(_tagOf(_asked(second, _other)), at.microsecondsSinceEpoch);
      expect(held(storage).containsKey('owed'), isFalse);
      expect(held(storage)['floor'], at.microsecondsSinceEpoch);

      final floor = at.microsecondsSinceEpoch;
      at = at.add(const Duration(hours: 3));
      expect(_tagOf(_asked(over(storage))), floor);
    });

    test('and made in the session that owed it leaves none', () async {
      final storage = _TagStorage();
      final first = over(storage);
      first.oweEvictAll();
      at = at.add(const Duration(minutes: 20));
      await first.evictAll();
      // Cleared with the floor it was owed, at once.
      expect(storage.writes, 2);
      expect(held(storage).containsKey('owed'), isFalse);
      final floor = at.microsecondsSinceEpoch;
      expect(held(storage)['floor'], floor);

      at = at.add(const Duration(hours: 3));
      expect(_tagOf(_asked(over(storage))), floor);
    });

    test('twice is one', () {
      final storage = _TagStorage();
      final first = over(storage);
      first.oweEvictAll();
      final owed = held(storage)['owed'];
      at = at.add(const Duration(minutes: 5));
      first.oweEvictAll();
      expect(storage.writes, 1);
      expect(held(storage)['owed'], owed);

      at = at.add(const Duration(hours: 1));
      final floor = at.microsecondsSinceEpoch;
      expect(_tagOf(_asked(over(storage))), floor);
      at = at.add(const Duration(hours: 1));
      expect(_tagOf(_asked(over(storage))), floor);
    });

    test('leaves the session working where storage throws', () async {
      final refusing = _TagStorage()..refuses = true;
      final full = _TagStorage()..refusesWrites = true;
      for (final storage in <BrowserStorage?>[null, refusing, full]) {
        final store = over(storage);
        store.oweEvictAll();
        store.oweEvictAll();
        expect(_asked(store), '$_art?size=128');
        at = at.add(const Duration(minutes: 1));
        await store.evictAll();
        expect(_tagOf(_asked(store)), at.microsecondsSinceEpoch);
        await store.evict(_art);
        await pumpEventQueue();
        expect(_tagOf(_asked(store)), greaterThan(at.microsecondsSinceEpoch));
      }
      expect(refusing.values, isEmpty);
      expect(full.values, isEmpty);
    });

    test('by another tab outlives a write made here', () async {
      final storage = _TagStorage();
      final owing = over(storage);
      final other = over(storage);
      owing.oweEvictAll();
      await other.evict(_art);
      await pumpEventQueue();
      expect(held(storage)['owed'], isNotNull);
      expect((held(storage)['tags'] as Map<String, dynamic>).keys, [_art]);

      // Made by the tab that owed it, it is not written back by the other.
      await owing.evictAll();
      expect(held(storage).containsKey('owed'), isFalse);
      at = at.add(const Duration(seconds: 5));
      await other.evict(_other);
      await pumpEventQueue();
      expect(held(storage).containsKey('owed'), isFalse);
    });

    test('is made by a sign-out: the next account asks every cover under a '
        'newer name, and storage names no cover', () async {
      // A stretch made busy with no name told leaves no tag to fold.
      final storage = _TagStorage();
      final first = over(storage);
      first.oweEvictAll();
      final owed = at.microsecondsSinceEpoch;
      at = at.add(const Duration(minutes: 1));
      final floor = at.microsecondsSinceEpoch;
      await first.forgetEverything();

      expect(held(storage).containsKey('owed'), isFalse);
      expect(held(storage)['floor'], floor);
      expect(held(storage)['tags'], isEmpty);
      expect(storage.values[ReplacedCovers.storageKey], isNot(contains('/')));
      // The next account in the same page, with no reload between.
      expect(_tagOf(_asked(first)), greaterThan(owed));
      expect(_tagOf(_asked(first, _other)), greaterThan(owed));

      // And after one: made once, not again.
      at = at.add(const Duration(hours: 3));
      final second = over(storage);
      expect(_tagOf(_asked(second)), floor);
      expect(_tagOf(_asked(second, _other)), floor);
    });

    test('longer ago than a cache can answer for is dropped, not made', () {
      final storage = _TagStorage();
      over(storage).oweEvictAll();
      at = at.add(kArtworkCacheLifetime + const Duration(minutes: 1));
      expect(_asked(over(storage)), '$_art?size=128');
    });
  });

  group('covers on screen', () {
    test('are told of their own cover and of every cover, and of no '
        'other', () {
      final probe = _StoreProbe();
      final told = <String>[];
      void art() => told.add('art');
      void other() => told.add('other');
      probe.source(_art)!.replaced!.addListener(art);
      probe.source(_other)!.replaced!.addListener(other);

      probe.replace(_art);
      expect(told, ['art']);
      probe.replaceAll();
      expect(told, ['art', 'art', 'other']);

      // Another handle on the same cover takes the same listener away.
      probe.source(_art)!.replaced!.removeListener(art);
      probe.source(_other)!.replaced!.removeListener(other);
      expect(probe.listening, 0);
      probe.replace(_art);
      probe.replaceAll();
      expect(told, hasLength(3));
    });

    test('one role replaced tells every role of that cover on screen, and no '
        'other cover', () {
      final probe = _StoreProbe();
      final told = <String>[];
      for (final url in [..._roles(_art), _other]) {
        probe.source(url)!.replaced!.addListener(() => told.add(url));
      }

      probe.replace('$_art?role=booklet');
      expect(told, unorderedEquals(_roles(_art)));
    });

    test('that leave while they are being told do not upset the telling', () {
      final probe = _StoreProbe();
      final told = <String>[];
      final replaced = probe.source(_art)!.replaced!;
      void last() => told.add('last');
      void first() {
        told.add('first');
        replaced.removeListener(first);
        replaced.removeListener(last);
      }

      replaced
        ..addListener(first)
        ..addListener(last);
      probe.replace(_art);
      // Both were on screen when the telling began.
      expect(told, ['first', 'last']);
      expect(probe.listening, 0);
    });
  });

  group('warming a scroll ahead', () {
    test('warms what it is given, skipping the items with no art', () async {
      final store = _RecordingStore();
      ArtworkPrecacher().warmAhead(
        store: store,
        urls: <String?>['c', null, 'd'],
        px: 300,
      );
      await pumpEventQueue();
      expect(store.warmed, <String>['c', 'd']);
      expect(store.pixels, <int>[300, 300]);
    });

    test('a later scroll supersedes the run in flight', () async {
      final store = _RecordingStore(gate: true);
      final precacher = ArtworkPrecacher();
      precacher.warmAhead(
        store: store,
        urls: <String?>['a', 'b', 'c', 'd', 'e', 'f'],
        px: 64,
      );
      await pumpEventQueue();
      precacher.warmAhead(store: store, urls: <String?>['x', 'y'], px: 64);
      store.release();
      await pumpEventQueue();
      // The first run got no further than the batch it was blocked on:
      // where the scroll stopped last is the better guess, and the rest
      // of the old window is never asked for.
      expect(store.warmed, <String>['a', 'b', 'c', 'x', 'y']);
    });

    test('a disposed precacher stops warming', () async {
      final store = _RecordingStore(gate: true);
      final precacher = ArtworkPrecacher();
      precacher.warmAhead(
        store: store,
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
      ArtworkPrecacher().warmAhead(
        store: store,
        urls: <String?>['a', 'b', 'c', 'd'],
        px: 64,
      );
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

/// A browser's storage that counts what it was asked to hold and can be
/// made to refuse everything, as a private window's does, or only what
/// it is asked to keep, as a full one does.
class _TagStorage implements BrowserStorage {
  final Map<String, String> values = <String, String>{};
  bool refuses = false;
  bool refusesWrites = false;
  int writes = 0;

  @override
  String? getItem(String key) {
    if (refuses) throw StateError('storage is denied here');
    return values[key];
  }

  @override
  void setItem(String key, String value) {
    if (refuses) throw StateError('storage is denied here');
    if (refusesWrites) throw StateError('the quota is spent');
    writes++;
    values[key] = value;
  }

  @override
  void removeItem(String key) {
    if (refuses) throw StateError('storage is denied here');
    if (refusesWrites) throw StateError('the quota is spent');
    values.remove(key);
  }
}

/// Reaches the base store's bookkeeping, which is protected because
/// only a store implementation has any business recording an absence
/// or a replacement.
class _StoreProbe extends ArtworkStore {
  _StoreProbe({super.replaced});

  @override
  String get baseUrl => '';

  void note(String artUrl, [int? rung]) => noteAbsent(artUrl, rung);

  bool knows(String artUrl, [int? rung]) => knownAbsent(artUrl, rung);

  void forget(String artUrl) => forgetAbsent(artUrl);

  void replace(String artUrl) => noteReplaced(artUrl);

  void replaceAll() => noteAllReplaced();

  /// The tag [artUrl] is asked under, or null when it carries none.
  int? tagOf(String artUrl) => _tagOf(requestUrl(artUrl, 128));

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
  Future<void> unpinExact(String pid, List<OwedPin> owed) async {}

  @override
  Future<void> evict(String artUrl) async {}

  @override
  Future<void> evictAll() async {}

  @override
  void oweEvictAll() {}

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
  Future<void> unpinExact(String pid, List<OwedPin> owed) async {}

  @override
  Future<void> evict(String artUrl) async {}

  @override
  Future<void> evictAll() async {}

  @override
  void oweEvictAll() {}

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
