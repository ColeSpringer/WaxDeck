import 'localized_host.dart';

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_palette.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';

const _red = WaxPalette(
  glow: Color(0xFFB4321E),
  wash: Color(0xFF7A2214),
  isFallback: false,
);
const _blue = WaxPalette(
  glow: Color(0xFF2B4FCB),
  wash: Color(0xFF1B347F),
  isFallback: false,
);

void main() {
  group('the palette cache', () {
    test('remembers a reading and tells absence from a remembered null', () {
      final cache = ArtworkPaletteCache();
      expect(cache.holds('/art/a'), isFalse);

      // A sleeve with no usable colour costs a fetch and a decode to
      // learn about, so the nothing is worth remembering too.
      cache.remember('/art/a', null);
      expect(cache.holds('/art/a'), isTrue);
      expect(cache.recall('/art/a'), isNull);

      cache.remember('/art/b', _red);
      expect(cache.recall('/art/b'), _red);
    });

    test('drops the least recently wanted past its cap', () {
      final cache = ArtworkPaletteCache();
      for (var i = 0; i < 128; i++) {
        cache.remember('/art/$i', _red);
      }
      expect(cache.length, 128);

      // Asking for the oldest makes it the newest, so the next eviction
      // takes the one after it instead.
      cache.recall('/art/0');
      cache.remember('/art/128', _blue);

      expect(cache.length, 128);
      expect(cache.holds('/art/0'), isTrue);
      expect(cache.holds('/art/1'), isFalse);
      expect(cache.holds('/art/128'), isTrue);
    });

    test('a peek reads a palette without making it the newest', () {
      // What a build reads through: reordering an LRU from a build is a
      // mutation in the wrong phase, and eviction order would then
      // follow whatever happened to rebuild.
      final cache = ArtworkPaletteCache();
      for (var i = 0; i < 128; i++) {
        cache.remember('/art/$i', _red);
      }
      expect(cache.peek('/art/0'), _red);
      cache.remember('/art/128', _blue);
      expect(cache.holds('/art/0'), isFalse);
      expect(cache.holds('/art/1'), isTrue);
    });

    test('forgets one cover, and forgets them all', () {
      final cache = ArtworkPaletteCache()
        ..remember('/art/a', _red)
        ..remember('/art/b', _blue);

      // The bytes behind a URL can be replaced under the same name (a
      // playlist cover regenerates on every membership write), and the
      // colour read off them is as stale as they are.
      cache.forget('/art/a');
      expect(cache.holds('/art/a'), isFalse);
      expect(cache.holds('/art/b'), isTrue);

      cache.clear();
      expect(cache.length, 0);
    });
  });

  group('the accent in scope', () {
    // The palette provider is an async family, so it hands back a frame
    // of AsyncLoading even for a cover this session has already read -
    // and that frame drew the domain hue, which is a flash to grey and
    // back at every track change.
    Future<WaxPalette> accentAfterOneFrame(
      WidgetTester tester, {
      required String? artUrl,
      required ArtworkPaletteCache cache,
    }) async {
      late WaxPalette seen;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paletteCacheProvider.overrideWithValue(cache),
            artworkStoreProvider.overrideWithValue(FakeArtworkStore()),
          ],
          child: localizedHost(
            ArtworkAccent(
              artUrl: artUrl,
              domain: WaxDomain.music,
              child: Builder(
                builder: (context) {
                  seen = WaxAccent.of(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      return seen;
    }

    testWidgets('a cover already read draws its colour on the first frame', (
      tester,
    ) async {
      final cache = ArtworkPaletteCache()..remember('/art/a', _red);
      expect(
        await accentAfterOneFrame(tester, artUrl: '/art/a', cache: cache),
        _red,
      );
    });

    testWidgets('an item with no cover is a fallback, not a wait', (
      tester,
    ) async {
      final palette = await accentAfterOneFrame(
        tester,
        artUrl: null,
        cache: ArtworkPaletteCache(),
      );
      expect(palette.isFallback, isTrue);
    });

    testWidgets('a cold cover holds the colour it is replacing', (
      tester,
    ) async {
      // Nothing in the cache for the second URL, so the read is a real
      // one - and until it lands the surface keeps the palette it had
      // rather than dropping to the domain hue and coming back.
      final cache = ArtworkPaletteCache()..remember('/art/a', _red);
      late WaxPalette seen;
      Widget host(String artUrl) => ProviderScope(
        overrides: [
          paletteCacheProvider.overrideWithValue(cache),
          artworkStoreProvider.overrideWithValue(FakeArtworkStore()),
        ],
        child: localizedHost(
          ArtworkAccent(
            artUrl: artUrl,
            domain: WaxDomain.music,
            child: Builder(
              builder: (context) {
                seen = WaxAccent.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      await tester.pumpWidget(host('/art/a'));
      expect(seen, _red);
      await tester.pumpWidget(host('/art/cold'));
      expect(seen, _red);
    });
  });

  group('decoding for extraction', () {
    testWidgets('a cover comes back as square RGBA at the sampling size', (
      tester,
    ) async {
      // Through runAsync: the decode is real engine work on a real
      // thread, and the fake clock a widget test runs under never lets
      // its future complete.
      final pixels = (await tester.runAsync(
        () => decodeArtworkPixels(_onePixelPng()),
      ))!;
      // Four bytes a pixel, at whatever the decode was asked for, so the
      // extractor reads the same number of samples whatever size the
      // stored cover happens to be.
      expect(pixels, hasLength(artworkPaletteSize * artworkPaletteSize * 4));
      // And the colour survives the scale: one crimson pixel blown up is
      // still crimson.
      final palette = extractPalette(pixels);
      expect(palette, isNotNull);
      expect(HSLColor.fromColor(palette!.glow).hue, closeTo(13, 10));
    });
  });
}

/// A 1x1 crimson PNG, written out rather than vendored: no binary media
/// in git, and a test fixture is media like any other.
Uint8List _onePixelPng() {
  const header = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  final bytes = <int>[
    ...header,
    ..._chunk('IHDR', <int>[
      0, 0, 0, 1, // width
      0, 0, 0, 1, // height
      8, // bit depth
      2, // truecolour
      0, 0, 0, // deflate, adaptive filtering, no interlace
    ]),
    ..._chunk('IDAT', _deflateStored(<int>[0, 0xB4, 0x32, 0x1E])),
    ..._chunk('IEND', const <int>[]),
  ];
  return Uint8List.fromList(bytes);
}

List<int> _chunk(String type, List<int> data) {
  final typeBytes = type.codeUnits;
  final body = <int>[...typeBytes, ...data];
  return <int>[..._be32(data.length), ...body, ..._be32(_crc32(body))];
}

List<int> _be32(int value) => <int>[
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

/// A zlib stream with one stored (uncompressed) block. Enough for four
/// bytes, and it keeps the fixture readable.
List<int> _deflateStored(List<int> data) {
  final length = data.length;
  return <int>[
    0x78, 0x01, // zlib header, no preset dictionary
    0x01, // final block, stored
    length & 0xFF, (length >> 8) & 0xFF,
    (~length) & 0xFF, ((~length) >> 8) & 0xFF,
    ...data,
    ..._be32(_adler32(data)),
  ];
}

int _adler32(List<int> data) {
  var a = 1;
  var b = 0;
  for (final byte in data) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  return (b << 16) | a;
}

int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}
