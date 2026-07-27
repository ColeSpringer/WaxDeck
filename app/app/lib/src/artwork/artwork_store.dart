/// Where artwork comes from: the sizes it is fetched at, the rules for
/// whose URLs may carry the caller's credentials, and the store every
/// screen asks.
///
/// Artwork is the one request the app makes hundreds of at a time, and
/// the three things that decide what that costs — how big a copy is
/// asked for, whether it comes off the network at all, and how many
/// pixels it decodes to — are all decided here rather than at each of
/// the fifty places that draw a cover.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// The sizes artwork is ever requested at.
///
/// Buckets, not exact extents: the server renders and caches a thumbnail
/// per distinct size, and a client that asked for 337 pixels here and
/// 341 there would make it render one per screen width in the house. Five
/// rungs cover every surface from a queue row to a tablet player hero.
const List<int> kArtworkRungs = <int>[64, 128, 256, 512, 1024];

/// The rungs kept on disk for an item downloaded for offline: one big
/// enough for a player hero, one for a grid cell. A phone's whole
/// offline library at these two sizes is a few megabytes.
const List<int> kOfflineArtworkRungs = <int>[1024, 256];

/// The rung a draw of [px] physical pixels asks for: the smallest one
/// that covers it, or the largest rung when nothing does. Fetching a
/// smaller copy than will be painted is the one failure worth avoiding —
/// upscaled artwork is visibly soft, and artwork is the surface people
/// look at.
int artworkRung(int px) {
  for (final rung in kArtworkRungs) {
    if (rung >= px) return rung;
  }
  return kArtworkRungs.last;
}

/// The step a painted size is rounded up to before it becomes a decode.
///
/// Flutter's image cache holds one decoded copy per key, and the key
/// includes the size it was decoded at, so a cover painted at 200 pixels
/// in one place and 206 in another would be decoded and held twice for
/// no visible difference. Rounding up to a step collapses those into
/// one. It matters most where the size is continuous rather than chosen:
/// a player hero is measured from the window, so a drag-resize would
/// otherwise mint a decode per frame.
///
/// Rounded up, never down — a copy decoded smaller than the box it fills
/// is visibly soft — and never past the largest rung, since nothing
/// bigger is ever fetched.
const int kArtworkDrawStep = 32;

/// Every size a decode can be keyed at. Rungs are multiples of the step,
/// so rounding up never crosses a rung: what is fetched is decided by
/// [artworkRung] either way.
final List<int> kArtworkDrawSizes = <int>[
  for (
    var size = kArtworkDrawStep;
    size <= kArtworkRungs.last;
    size += kArtworkDrawStep
  )
    size,
];

/// The size a draw of [px] physical pixels is decoded and cached at.
int artworkDrawSize(int px) {
  if (px <= kArtworkDrawStep) return kArtworkDrawStep;
  final stepped =
      ((px + kArtworkDrawStep - 1) ~/ kArtworkDrawStep) * kArtworkDrawStep;
  return stepped < kArtworkRungs.last ? stepped : kArtworkRungs.last;
}

/// The same art URL asking for one size rung, and optionally under a
/// name no cache has seen ([bust], the endpoint's ignored `v`).
///
/// Built through [Uri] rather than string concatenation because art URLs
/// already carry a `role` for anything but a front cover, and a naive
/// `?size=` would strip it.
String sizedArtUrl(String artUrl, int rung, {int? bust}) {
  final uri = Uri.parse(artUrl);
  return uri
      .replace(
        queryParameters: <String, String>{
          ...uri.queryParameters,
          'size': '$rung',
          if (bust != null) 'v': '$bust',
        },
      )
      .toString();
}

/// The PID an art URL belongs to, or null for a URL that names none.
///
/// Pins are keyed by PID (that is what a download is), while the drawing
/// side only ever has a URL, so this is the bridge between them.
String? artworkPidOf(String artUrl) {
  final match = RegExp(r'/items/([^/?#]+)/art').firstMatch(artUrl);
  return match?.group(1);
}

/// Whether [artUrl] is served by the WaxDeck server this app is signed
/// in to.
///
/// This gates two things that must never happen to a stranger's host: a
/// `size` parameter it does not understand, and the caller's bearer
/// token. Radio station logos are fetched straight from the station
/// (recorded behaviour until the logo proxy lands), so foreign URLs are
/// a real, routine case rather than a defensive one.
bool isWaxDeckUrl(String artUrl, String baseUrl) {
  // A path is same-origin by construction: the web SPA is served by the
  // WaxDeck server itself. Two slashes is not a path — `//host/logo.png`
  // is somebody else's host with the scheme left to the caller, and
  // station logos come from feeds that are free to write one.
  if (artUrl.startsWith('//')) return false;
  if (artUrl.startsWith('/')) return true;
  if (baseUrl.isEmpty) return false;
  final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
  return artUrl == base || artUrl.startsWith('$base/');
}

/// What one artwork fetch answered.
class ArtworkBytes {
  const ArtworkBytes({required this.bytes, required this.etag});

  final Uint8List bytes;

  /// The validator, so the next fetch of the same variant can present it
  /// and be told nothing changed. Empty when the server sent none.
  final String etag;
}

/// Where artwork comes from, for everything that draws it.
///
/// Native and web are genuinely different problems: native must attach a
/// credential the browser attaches for itself, has a disk cache of its
/// own to keep, and has an offline mode to answer; web has a browser
/// cache that is better than anything reimplementable and no offline
/// mode at all. The port is what the screens see either way.
abstract class ArtworkStore {
  /// The server origin, empty on web where art URLs are relative.
  String get baseUrl;

  /// Covers this store has been told were replaced, and the tag that
  /// tells the old bytes from the new ones apart.
  ///
  /// Artwork lives at one URL whatever it holds, and the endpoint now
  /// answers with a day of freshness, so after a cover write every cache
  /// between here and the disk would go on serving the old image — the
  /// browser's most stubbornly, since nothing in this process can reach
  /// into it. Asking under a name no cache has seen is what can be done
  /// from this side. It grows only when somebody edits a cover, which is
  /// a handful of times in a session, never per draw.
  final Map<String, int> _replaced = <String, int>{};
  int _replacements = 0;

  /// Where to fetch [artUrl] for a draw of [px] physical pixels: ours
  /// asks for the rung that covers it, a stranger's is asked for exactly
  /// as it was given, and either carries the tag of a replacement this
  /// store has seen.
  @protected
  String requestUrl(String artUrl, int px) {
    if (!isWaxDeckUrl(artUrl, baseUrl)) return artUrl;
    return sizedArtUrl(artUrl, artworkRung(px), bust: _replaced[artUrl]);
  }

  /// Records that the bytes behind [artUrl] have changed, so everything
  /// asked for afterwards is asked for under a new name.
  @protected
  void noteReplaced(String artUrl) => _replaced[artUrl] = ++_replacements;

  /// The artwork at [artUrl] ready to paint at [px] physical pixels, or
  /// null when there is no artwork. Null is a real state (fresh imports,
  /// feeds without art), and the design system draws a monogram for it.
  ImageProvider? imageFor(String? artUrl, int px);

  /// [artUrl] as the design system takes it: a function from the size a
  /// component decides to draw at to a provider for exactly that size.
  WaxArtwork? source(String? artUrl) {
    if (artUrl == null || artUrl.isEmpty) return null;
    return (int px) => imageFor(artUrl, px);
  }

  /// The bytes behind [artUrl] at the rung covering [px]. For everything
  /// that needs the image rather than a way to paint it: palette
  /// extraction, a cast device's copy, a share card.
  Future<Uint8List?> bytesFor(String artUrl, int px);

  /// Fetches [artUrl] at the rung covering [px] into whatever cache this
  /// platform has, and decodes nothing. For warming a scroll ahead of
  /// itself: see [ArtworkPrecacher] for why the size is allowed to be a
  /// guess and the decode is not warmed with it.
  Future<void> warm(String artUrl, int px);

  /// Keeps [artUrl] on disk for [pid] until it is unpinned, so a
  /// downloaded item has a cover with the server unreachable. A no-op
  /// where there is no offline mode.
  Future<void> pinForOffline(String pid, String? artUrl);

  /// Drops the pins for [pid] and the files behind them.
  Future<void> unpin(String pid);

  /// Forgets everything held for [artUrl], at every size. Called when an
  /// entity's artwork is replaced: the URL is stable across a cover
  /// change, so nothing else would notice.
  Future<void> evict(String artUrl);

  /// Drops every cached and pinned byte. Sign-out: the next account has
  /// no business reading the last one's covers.
  Future<void> forgetEverything();

  void dispose();
}

/// The store that leans on the platform: sized requests, and the HTTP
/// cache underneath does the rest.
///
/// This is the web build, where the session cookie rides every
/// same-origin request, the browser's own cache is honest about ETag and
/// `Cache-Control` (a day of freshness, a week of stale-while-revalidate
/// as of the art endpoint's caching contract), and there is no offline
/// mode to pin for. Native tests use it too: it reaches the network only
/// when something actually paints, which under `flutter test` is a
/// refused request and a monogram.
///
/// Not a native build, ever: `NetworkImage` carries no credential, which
/// is the bug the whole pipeline was built to fix. Native gets
/// `CachedArtworkStore`.
class NetworkArtworkStore extends ArtworkStore {
  NetworkArtworkStore({required this.baseUrl, this.token, Dio? client})
    : _dio = client ?? Dio();

  @override
  final String baseUrl;

  /// The bearer token, read at request time because it rotates. Null on
  /// web, where the credential is an HttpOnly cookie the browser
  /// attaches itself.
  final String? Function()? token;

  final Dio _dio;

  @override
  ImageProvider? imageFor(String? artUrl, int px) {
    if (artUrl == null || artUrl.isEmpty) return null;
    final draw = artworkDrawSize(px);
    return ResizeImage(
      NetworkImage(
        requestUrl(artUrl, draw),
        // Empty wherever the browser is attaching a cookie for us, which
        // is where this store belongs and is what keeps the fast
        // browser-native decode path. Carried anyway, so this class is
        // not one condition away from being the unauthenticated fetch
        // the whole pipeline exists to have got rid of.
        headers: authHeadersFor(artUrl, baseUrl, token),
      ),
      width: draw,
      height: draw,
      // Fit, not exact: a portrait book cover bounded on its width alone
      // decodes taller than the box that will hold it.
      policy: ResizeImagePolicy.fit,
      allowUpscaling: false,
    );
  }

  @override
  Future<Uint8List?> bytesFor(String artUrl, int px) async {
    final fetched = await fetchArtwork(
      _dio,
      requestUrl(artUrl, px),
      headers: authHeadersFor(artUrl, baseUrl, token),
    );
    return fetched?.bytes;
  }

  @override
  Future<void> warm(String artUrl, int px) async {
    // The bytes land in the browser's HTTP cache on the way past; there
    // is nothing to hold on to here.
    await bytesFor(artUrl, px);
  }

  @override
  Future<void> pinForOffline(String pid, String? artUrl) async {}

  @override
  Future<void> unpin(String pid) async {}

  @override
  Future<void> evict(String artUrl) async {
    // The whole ladder, because that is the whole set of keys a cover
    // can be held under. Nothing has to be remembered to be dropped.
    // Built before the replacement is noted, since these are the keys
    // the old bytes are under.
    final held = <ImageProvider?>[
      for (final draw in kArtworkDrawSizes) imageFor(artUrl, draw),
    ];
    noteReplaced(artUrl);
    for (final image in held) {
      await image?.evict();
    }
  }

  @override
  Future<void> forgetEverything() async {
    dropDecodedArtwork();
  }

  @override
  void dispose() => _dio.close(force: true);
}

/// Drops every decoded copy from Flutter's own image cache.
///
/// Guarded because sign-out is reachable from a provider-level test,
/// which runs with no painting binding at all — and with nothing
/// decoded to drop.
void dropDecodedArtwork() {
  try {
    PaintingBinding.instance.imageCache.clear();
  } on Error {
    // No binding in this isolate; there is no image cache to clear.
  }
}

/// The bearer header for a WaxDeck URL, and nothing at all for anyone
/// else's: a station logo host must never be handed the caller's token.
Map<String, String> authHeadersFor(
  String artUrl,
  String baseUrl,
  String? Function()? token,
) {
  if (token == null || !isWaxDeckUrl(artUrl, baseUrl)) {
    return const <String, String>{};
  }
  final value = token();
  if (value == null || value.isEmpty) return const <String, String>{};
  return <String, String>{'Authorization': 'Bearer $value'};
}

/// One artwork GET. Answers null for a 304 (the caller already has these
/// bytes) and for any failure, which is always drawable: a missing cover
/// is a monogram, not an error dialog.
Future<ArtworkBytes?> fetchArtwork(
  Dio dio,
  String url, {
  Map<String, String> headers = const <String, String>{},
  String? ifNoneMatch,
}) async {
  try {
    final response = await dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: <String, String>{
          ...headers,
          if (ifNoneMatch != null && ifNoneMatch.isNotEmpty)
            'If-None-Match': ifNoneMatch,
        },
        validateStatus: (int? status) => status == 200 || status == 304,
      ),
    );
    final body = response.data;
    if (response.statusCode != 200 || body == null || body.isEmpty) return null;
    return ArtworkBytes(
      bytes: Uint8List.fromList(body),
      etag: response.headers.value('etag') ?? '',
    );
  } catch (_) {
    // Everything, not just DioException: dio casts the response body
    // outside its own error wrapping, so a body that is not what was
    // asked for arrives as a plain TypeError. This is called from
    // background work nobody is awaiting — a warm-ahead, a pin beside a
    // download — where an escaping error is an unhandled one, and the
    // answer to every failure here is the same anyway: no bytes, and the
    // monogram that is already the drawn state for a cover there is none
    // of.
    return null;
  }
}
