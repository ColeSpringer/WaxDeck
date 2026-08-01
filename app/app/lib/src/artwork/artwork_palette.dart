import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'artwork_providers.dart';

/// How wide the artwork is decoded before its colour is read.
///
/// A histogram does not get better with pixels: 64 px is four thousand
/// samples, which finds a sleeve's dominant colour as reliably as four
/// hundred thousand and costs a thousandth of the decode. It is also a
/// rung the store already fetches for small covers, so the player's
/// palette usually comes out of a cache rather than off the network.
const int artworkPaletteSize = 64;

/// The palette behind one piece of artwork, or null when it has no
/// colour worth using.
///
/// Null is a real answer, not a failure: a monochrome sleeve, a cover
/// that will not load, an item with no art at all. The caller draws the
/// domain hue for it, which is what [WaxPalette.forDomain] is, and which
/// is why this does not build the fallback itself - it has no
/// `BuildContext` to read the theme's hues from.
///
/// **Extraction scope is a hard rule**: only the playing item and the one
/// entity header on screen ever extract. Grid and shelf cards use the
/// domain hue. Flutter web has no real isolates, and per-card extraction
/// at grid scale would put the decode of every visible cover on the
/// frame that scrolled it.
///
/// Keyed by artwork URL rather than by pid, which is the one deviation
/// from the plan's shape here and is the cheaper key: the colour is a
/// property of the cover, so an album's twelve tracks extract once
/// between them, and an item with no cover never creates an entry at
/// all.
final artworkPaletteProvider = FutureProvider.autoDispose
    .family<WaxPalette?, String>((ref, artUrl) async {
      final cache = ref.watch(paletteCacheProvider);
      if (cache.holds(artUrl)) return cache.recall(artUrl);

      final bytes = await ref
          .watch(artworkStoreProvider)
          .bytesFor(artUrl, artworkPaletteSize);
      WaxPalette? palette;
      if (bytes != null && bytes.isNotEmpty) {
        try {
          palette = extractPalette(await decodeArtworkPixels(bytes));
        } catch (_) {
          // A cover the engine cannot decode: a truncated file, a format
          // this platform has no codec for, an upload that is not an
          // image at all. Deterministic, so it is remembered as "no
          // colour" like any other - the store already answers a failed
          // fetch with null, and leaving this one to throw would make
          // every reopen of the player decode it again to fail again.
          palette = null;
        }
      }
      cache.remember(artUrl, palette);
      return palette;
    });

/// Decodes [bytes] down to [artworkPaletteSize] square and hands back its
/// raw RGBA.
///
/// Square rather than aspect-correct on purpose: this feeds a histogram,
/// where the shape of the image means nothing and an even sample of it
/// means everything. The decode itself happens off the UI thread in the
/// engine, and what is left - reading four thousand pixels - is under a
/// millisecond, so it runs inline rather than through `compute`. That is
/// a deviation from the plan's "isolate on native, inline on web", and
/// the reason is arithmetic: spawning an isolate costs more than the
/// work it would carry, and web has no isolates to spawn.
Future<Uint8List> decodeArtworkPixels(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final codec = await PaintingBinding.instance.instantiateImageCodecWithSize(
    buffer,
    getTargetSize: (int width, int height) => const ui.TargetImageSize(
      width: artworkPaletteSize,
      height: artworkPaletteSize,
    ),
  );
  try {
    final frame = await codec.getNextFrame();
    try {
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      // The view's own window, not the whole backing buffer: today the
      // engine hands back a buffer of exactly these bytes, and a padded
      // or pooled one would otherwise be read as pixels.
      return data == null
          ? Uint8List(0)
          : data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

/// Puts the artwork's own colour in scope for one subtree.
///
/// Scoped, never global: the accent belongs to the surface showing the
/// artwork, and a track change repaints that subtree and nothing else.
/// Wrapping the app in one of these would repaint every screen every
/// time a song ended.
///
/// The colour crossfades rather than cutting. It is the largest thing on
/// a player, and a hard swap at a track boundary reads as a flash - so
/// the palette is tweened and the fallback hue is a legitimate end of
/// that tween, which is what a track with no cover following one with a
/// cover looks like.
class ArtworkAccent extends ConsumerWidget {
  const ArtworkAccent({
    required this.artUrl,
    required this.domain,
    required this.child,
    super.key,
  });

  /// Null draws the domain hue and asks for nothing: an item with no
  /// cover is a real state, not a pending one.
  final String? artUrl;

  final WaxDomain domain;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = artUrl;
    final extracted = url == null || url.isEmpty
        ? null
        : ref.watch(artworkPaletteProvider(url)).value;
    final palette =
        extracted ?? WaxPalette.forDomain(WaxColors.of(context), domain);
    return TweenAnimationBuilder<WaxPalette>(
      tween: WaxPaletteTween(end: palette),
      duration: WaxMotion.of(context).artworkCrossfade,
      curve: WaxMotion.emphasized,
      builder: (context, tweened, child) =>
          WaxAccent(palette: tweened, domain: domain, child: child!),
      child: child,
    );
  }
}

/// The palettes this session has read, newest [_capacity] kept.
///
/// Bounded because the alternative is a map that grows for the length of
/// a listening session, and unbounded because a palette is small is the
/// reasoning that produces a leak. A hundred and twenty-eight covers is
/// more than a sitting's listening and a few kilobytes in total; past it
/// the least recently wanted is dropped and re-read if it comes back.
///
/// A null palette is remembered too. "This sleeve has no usable colour"
/// costs a fetch and a decode to learn, and it is the answer for a whole
/// genre of artwork.
final paletteCacheProvider = Provider<ArtworkPaletteCache>(
  (ref) => ArtworkPaletteCache(),
);

class ArtworkPaletteCache {
  static const int _capacity = 128;

  // Insertion-ordered, and re-inserted on every hit, so the first key is
  // always the least recently wanted.
  final LinkedHashMap<String, WaxPalette?> _entries =
      LinkedHashMap<String, WaxPalette?>();

  bool holds(String artUrl) => _entries.containsKey(artUrl);

  /// The remembered palette for [artUrl], which may legitimately be
  /// null. Ask [holds] first: this cannot tell absence from a remembered
  /// nothing.
  WaxPalette? recall(String artUrl) {
    if (!_entries.containsKey(artUrl)) return null;
    final palette = _entries.remove(artUrl);
    _entries[artUrl] = palette;
    return palette;
  }

  void remember(String artUrl, WaxPalette? palette) {
    _entries.remove(artUrl);
    _entries[artUrl] = palette;
    if (_entries.length > _capacity) _entries.remove(_entries.keys.first);
  }

  /// Forgets one cover, for when its bytes are replaced under the same
  /// URL: the artwork editors evict the image, and the colour read off
  /// it has to go with it.
  void forget(String artUrl) => _entries.remove(artUrl);

  void clear() => _entries.clear();

  int get length => _entries.length;
}
