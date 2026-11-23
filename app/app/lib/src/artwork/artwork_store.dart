/// Where artwork comes from: the sizes it is fetched at, the rules for
/// whose URLs may carry the caller's credentials, and the store every
/// screen asks.
///
/// Artwork is the one request the app makes hundreds of at a time, and
/// the three things that decide what that costs - how big a copy is
/// asked for, whether it comes off the network at all, and how many
/// pixels it decodes to - are all decided here rather than at each of
/// the fifty places that draw a cover.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:waxdeck_data/waxdeck_data.dart' show OwedPin;
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'art_slot.dart';
import 'replaced_covers.dart';

export 'replaced_covers.dart';

/// The sizes artwork is ever requested at.
///
/// Buckets, not exact extents: the server renders and caches a thumbnail
/// per distinct size, and a client that asked for 337 pixels here and
/// 341 there would make it render one per screen width in the house. Five
/// rungs cover every surface from a queue row to a tablet player hero.
///
/// Every entry is also a rung of the catalog's own ladder
/// (`waxbin/art.Rungs()`, 32 through 2048), which is the authoritative
/// list: the server rounds a requested box up to the next one of those
/// and answers there, so asking off-ladder buys nothing but a taller
/// picture than was asked for. A size added here picks from that list.
const List<int> kArtworkRungs = <int>[64, 128, 256, 512, 1024];

/// The rungs kept on disk for an item downloaded for offline: one big
/// enough for a player hero, one for a grid cell. A phone's whole
/// offline library at these two sizes is a few megabytes.
const List<int> kOfflineArtworkRungs = <int>[1024, 256];

/// The rung a draw of [px] physical pixels asks for: the smallest one
/// that covers it, or the largest rung when nothing does. Fetching a
/// smaller copy than will be painted is the one failure worth avoiding -
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
/// Rounded up, never down - a copy decoded smaller than the box it fills
/// is visibly soft - and never past the largest rung, since nothing
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
/// name no cache has seen ([bust], the endpoint's ignored `v`). A URL
/// that carries a `v` of its own keeps it: a station's now-playing cover
/// is asked for by a key in that parameter, which names the bytes
/// already.
///
/// Built through [Uri] rather than string concatenation because art URLs
/// already carry a `role` for anything but a front cover, and a naive
/// `?size=` would strip it.
/// A null [rung] asks for whatever the endpoint has, for the endpoints
/// that hold one rendition (see [isUnsizedArtUrl]).
String sizedArtUrl(String artUrl, int? rung, {int? bust}) {
  final uri = Uri.parse(artUrl);
  final tag = uri.queryParameters.containsKey('v') ? null : bust;
  if (rung == null && tag == null) return artUrl;
  return uri
      .replace(
        queryParameters: <String, String>{
          ...uri.queryParameters,
          if (rung != null) 'size': '$rung',
          if (tag != null) 'v': '$tag',
        },
      )
      .toString();
}

/// Whether [artUrl] answers one rendition however it is asked.
///
/// Neither radio endpoint has a stored original to scale from, so the
/// contract says `size` on both is accepted and ignored. Asking for a
/// rung anyway splits one identical body across a URL per rung: the dial
/// and the grid draw at different sizes, so that is two fetches of the
/// same bytes, and two decoded copies of them.
bool isUnsizedArtUrl(String artUrl) =>
    _unsizedArt.hasMatch(Uri.parse(artUrl).path);

final RegExp _unsizedArt = RegExp(
  r'/radio/stations/[^/]+/(logo|now-playing-art)$',
);

/// The PID an art URL belongs to, or null for a URL that names none.
///
/// Pins are keyed by PID (that is what a download is), while the drawing
/// side only ever has a URL, so this is the bridge between them.
String? artworkPidOf(String artUrl) {
  final match = RegExp(r'/items/([^/?#]+)/art').firstMatch(artUrl);
  return match?.group(1);
}

/// Every URL a picture of [artUrl]'s entity is drawn from: one per role
/// for an item's art, or [artUrl] alone.
List<String> coverUrlsOf(String artUrl) {
  final uri = Uri.tryParse(artUrl);
  if (uri == null || !isItemArt(uri) || uri.queryParameters.containsKey('v')) {
    return <String>[artUrl];
  }
  final key = coverKeyOf(artUrl);
  final rest = Uri.parse(key).queryParameters;
  return <String>[
    for (final slot in ArtSlot.values)
      if (slot == ArtSlot.front)
        key
      else if (rest.isEmpty)
        '$key?role=${slot.role}'
      else
        Uri.parse(
          key,
        ).replace(queryParameters: {...rest, 'role': slot.role}).toString(),
  ];
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
  // WaxDeck server itself. Two slashes is not a path - `//host/logo.png`
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
  /// [replaced] carries the store's clock and, on web, its storage. A
  /// store handed one over storage closes it in [dispose].
  ArtworkStore({ReplacedCovers? replaced})
    : _replaced = replaced ?? ReplacedCovers();

  /// The server origin, empty on web where art URLs are relative.
  String get baseUrl;

  /// Covers this store has been told were replaced, and the tag that
  /// tells the old bytes from the new ones apart.
  final ReplacedCovers _replaced;

  /// Covers the server has answered 404 for.
  ///
  /// Every item carries an art URL whether or not there is anything
  /// behind it - the contract says so, and the endpoint 404s for the
  /// ones there is not - so an index of art-less rows asks once per row
  /// and asks again every time it is scrolled back over. Remembering
  /// the answer turns that into one request per cover for the life of
  /// the session, and turns the monogram into the first thing drawn
  /// rather than the thing drawn after a failed round trip.
  ///
  /// Keyed per rung: the server refuses some sizes of a cover it still
  /// serves whole (an unscalable original in a thumbnail slot), so one
  /// rung's 404 must not silence the others.
  final Set<String> _absent = <String>{};

  /// How many absences are worth remembering. A library's art-less
  /// items are unbounded in principle, and each entry is a short
  /// string, so this is a ceiling on a leak rather than a working-set
  /// estimate: past it the oldest are dropped and, if they are drawn
  /// again, asked for again. Comfortably more than a screen and its
  /// scroll-back either way.
  static const int _maxAbsent = 4096;

  /// Where to fetch [artUrl] for a draw of [px] physical pixels: a
  /// stranger's is asked for exactly as it was given, ours asks for the
  /// rung that covers it, under the tag of a replacement this store has
  /// seen. [tagged] false is the name it had before any replacement.
  @protected
  String requestUrl(String artUrl, int px, {bool tagged = true}) {
    if (!isWaxDeckUrl(artUrl, baseUrl)) return artUrl;
    return sizedArtUrl(
      artUrl,
      isUnsizedArtUrl(artUrl) ? null : artworkRung(px),
      bust: tagged ? _replaced.tagFor(artUrl) : null,
    );
  }

  /// Records that the bytes behind [artUrl] have changed, so everything
  /// asked for afterwards is asked for under a new name - and that
  /// whatever this store knew about the old bytes no longer holds,
  /// including their absence. For every role of its entity: a cover is
  /// kept by entity ([coverKeyOf]).
  @protected
  void noteReplaced(String artUrl) {
    _replaced.note(artUrl);
    final covers = coverUrlsOf(artUrl);
    for (final url in covers) {
      forgetAbsent(url);
    }
    _tell([for (final url in covers) ...?_listeners[url]]);
  }

  /// The drops under way, by cover.
  final Map<String, Future<void>> _dropping = <String, Future<void>>{};

  /// What [evict] has in common on every platform: forgets every role's
  /// absence, takes the names the old bytes are held under ([held], read
  /// before the replacement is noted), notes it, and runs the drop
  /// [held] returns. A cover evicted again while a drop of it is under
  /// way joins that drop: what it would drop is nothing a draw asks for
  /// again.
  @protected
  Future<void> replaceCover(
    String artUrl,
    Future<void> Function() Function(List<String> covers) held,
  ) {
    final covers = coverUrlsOf(artUrl);
    // The absence first: a known-absent URL answers null for every
    // provider, which would leave real decoded bytes behind.
    for (final url in covers) {
      forgetAbsent(url);
    }
    final key = coverKeyOf(artUrl);
    final under = _dropping[key];
    final drop = under == null ? held(covers) : null;
    noteReplaced(artUrl);
    if (drop == null) return under!;
    late final Future<void> dropping;
    dropping = () async {
      try {
        await drop();
      } finally {
        if (identical(_dropping[key], dropping)) _dropping.remove(key);
      }
    }();
    return _dropping[key] = dropping;
  }

  /// Records that covers changed and nothing says which, so every one
  /// is asked for afterwards under a name no cache has seen, the ones
  /// known to be missing included.
  @protected
  void noteAllReplaced() {
    _replaced.raiseFloor();
    forgetAbsences();
    _tell(_listeners.values.expand((listening) => listening));
  }

  /// The rung an absence at [px] is recorded under; null where requests
  /// carry no size (a stranger's URL, a one-rendition endpoint).
  @protected
  int? absentRung(String artUrl, int px) =>
      !isWaxDeckUrl(artUrl, baseUrl) || isUnsizedArtUrl(artUrl)
      ? null
      : artworkRung(px);

  String _absentKey(String artUrl, int? rung) =>
      rung == null ? artUrl : '$artUrl#$rung';

  /// Records that the server has no artwork at [artUrl].
  ///
  /// Re-recording one already known must cost nothing, because it is
  /// routine: several providers for the same cover at different sizes
  /// can be in flight at once, and each 404 arrives separately.
  @protected
  void noteAbsent(String artUrl, int? rung) {
    if (!_absent.add(_absentKey(artUrl, rung))) return;
    if (_absent.length > _maxAbsent) {
      // Insertion-ordered, so this is the least recently learned.
      _absent.remove(_absent.first);
    }
  }

  /// Whether the server has already said there is nothing at [artUrl].
  @protected
  bool knownAbsent(String artUrl, int? rung) =>
      _absent.contains(_absentKey(artUrl, rung));

  /// Forgets which covers are missing, so they are asked for again.
  ///
  /// Public because the important caller is outside: artwork mostly
  /// appears without anything here being told which cover. Without this
  /// the monogram cached during a browse of a fresh
  /// library would outlast the enrichment that filled it in, for the
  /// rest of the session. Anything that invalidates the catalog calls
  /// this; sign-out does too.
  void forgetAbsences() => _absent.clear();

  /// Forgets that one cover was missing. For an invalidation that names
  /// the URL it is about. By key, never a walk of the set: a scan
  /// invalidates covers by the dozen a frame.
  @protected
  void forgetAbsent(String artUrl) {
    _absent.remove(artUrl);
    for (final rung in kArtworkRungs) {
      _absent.remove(_absentKey(artUrl, rung));
    }
  }

  /// The artwork at [artUrl] ready to paint at [px] physical pixels, or
  /// null when there is no artwork. Null is a real state (fresh imports,
  /// feeds without art), and the design system draws a monogram for it.
  ImageProvider? imageFor(String? artUrl, int px);

  /// What is listening for each cover, by art URL: the covers on
  /// screen, and nothing else. An entry goes with its last listener.
  final Map<String, List<VoidCallback>> _listeners =
      <String, List<VoidCallback>>{};

  /// How many covers something on screen is listening for.
  @visibleForTesting
  int get listening => _listeners.length;

  void _tell(Iterable<VoidCallback> listeners) {
    // A copy: a listener that leaves while it is told changes the list.
    for (final listener in listeners.toList()) {
      listener();
    }
  }

  /// [artUrl] as the design system takes it: a function from the size a
  /// component decides to draw at to a provider for exactly that size.
  WaxArtwork? source(String? artUrl) {
    if (artUrl == null || artUrl.isEmpty) return null;
    return WaxArtwork(
      (int px) => imageFor(artUrl, px),
      cover: artUrl,
      replaced: _CoverReplaced(this, artUrl),
    );
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
  /// downloaded item has a cover with the server unreachable. Only while
  /// the device holds a download for [pid] and is not freeing it: a cover
  /// that arrives after that takes itself back. A no-op where there is no
  /// offline mode.
  Future<void> pinForOffline(String pid, String? artUrl);

  /// Drops the pins for [pid] and the files behind them.
  Future<void> unpin(String pid);

  /// Drops exactly the pins listed, each by its size and the instant it
  /// was pinned, with the files behind them, and no others: a cover the
  /// device pinned since is not what was listed and stays. Required of
  /// every store, with no default, so one that keeps pins cannot forget it
  /// and strand covers; one with no offline mode says so with a body that
  /// does nothing.
  Future<void> unpinExact(String pid, List<OwedPin> owed);

  /// Forgets everything held for [artUrl]'s entity, every role of it at
  /// every size. Called when an entity's artwork is replaced: the URL is
  /// stable across a cover change, so nothing else would notice. One
  /// call per entity, with any of its art URLs, is enough.
  ///
  /// The replacement is noted before the first await, so a surface that
  /// asks again in the same turn already gets the new bytes; what is
  /// dropped after that is nothing a redraw waits for. A cover on screen
  /// drawn from [source] is told then, and asks again by itself. Where
  /// the picture [artUrl] names is pinned for offline, that pin is asked
  /// about again in the background, as [evictAll] asks about every pin.
  Future<void> evict(String artUrl);

  /// [evict] for every cover at once, for when covers were replaced and
  /// nothing says which: each is asked for afresh, once, at the cost of
  /// fetching every one drawn again. Noted before the first await, as
  /// there, and every cover on screen is told. Where covers are pinned
  /// for offline, each is asked about again in the background.
  Future<void> evictAll();

  /// Marks every cover as owed a fresh ask, so a session that ends before
  /// [evictAll] makes it still does at its next start.
  void oweEvictAll();

  /// The server is known to be in reach again. Where covers are pinned
  /// for offline, one drawn off a pin still owed its refresh is told
  /// replaced and asks the server, whatever holds the refresh back.
  /// Nothing where there are no pins.
  void serverReached() {}

  /// [told] hears the art URL of each cover drawn off a pin that this
  /// store names anew by itself (the pin rewritten, the server back in
  /// reach), for what was read off the old bytes elsewhere. Once however
  /// often it is handed in. Nothing where there are no pins.
  void onRenamed(void Function(String artUrl) told) {}

  /// Pins the cover of each download in [held], its art URL by pid, at
  /// every offline size it has no pin at: a download pins its cover only
  /// as it lands, and a sign-out drops every pin and keeps the audio.
  /// [held] is every download there is: what was kept of one not in it
  /// is dropped.
  ///
  /// The pin walk's work, in the background behind its gate and at its
  /// pace: a size the server will not give is asked for again in the
  /// walk's rounds, and one it could not be asked about once the walk's
  /// wait is up, however often this is called meanwhile. A size still
  /// refused after the rounds, or one the server answers it has no cover
  /// at, is not asked for again until the item is named replaced, every
  /// cover is, or a sign-out: the first until the next launch at most,
  /// the second in a later launch too. [landed] hears each pid a cover
  /// was pinned for, once a call. Nothing where there are no pins.
  void pinHeld(Map<String, String> held, {void Function(String pid)? landed}) {}

  /// Drops every cached and pinned byte. Sign-out: the next account has
  /// no business reading the last one's covers.
  Future<void> forgetEverything();

  void dispose();
}

/// Says when its store is told one cover, or every cover, was replaced.
///
/// Handed out with every [ArtworkStore.source] and costing nothing until
/// something listens: the store keeps a listener, not this. Equal for
/// one cover of one store, so a widget handed another of them on each
/// build does not listen afresh each time.
@immutable
class _CoverReplaced implements Listenable {
  const _CoverReplaced(this._store, this._artUrl);

  final ArtworkStore _store;
  final String _artUrl;

  @override
  void addListener(VoidCallback listener) =>
      (_store._listeners[_artUrl] ??= <VoidCallback>[]).add(listener);

  @override
  void removeListener(VoidCallback listener) {
    final listening = _store._listeners[_artUrl];
    if (listening == null) return;
    listening.remove(listener);
    if (listening.isEmpty) _store._listeners.remove(_artUrl);
  }

  @override
  bool operator ==(Object other) =>
      other is _CoverReplaced &&
      identical(other._store, _store) &&
      other._artUrl == _artUrl;

  @override
  int get hashCode => Object.hash(identityHashCode(_store), _artUrl);
}

/// The store that leans on the platform: sized requests, and the HTTP
/// cache underneath does the rest.
///
/// This is the web build, where the session cookie rides every
/// same-origin request, the browser's own cache is honest about ETag and
/// `Cache-Control` (a day of freshness, a week of stale-while-revalidate
/// as of the art endpoint's caching contract), and there is no offline
/// mode to pin for. That cache outlives the page, so the web build hands
/// in a memory over browser storage and a replaced cover is still asked
/// for under its tag after a reload. Native tests use it too: it reaches the network only
/// when something actually paints, which under `flutter test` is a
/// refused request and a monogram.
///
/// Not a native build, ever: `NetworkImage` carries no credential, which
/// is the bug the whole pipeline was built to fix. Native gets
/// `CachedArtworkStore`.
class NetworkArtworkStore extends ArtworkStore {
  NetworkArtworkStore({
    required this.baseUrl,
    this.token,
    Dio? client,
    super.replaced,
  }) : _dio = client ?? artworkTransport();

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
    if (knownAbsent(artUrl, absentRung(artUrl, draw))) return null;
    return _WatchedArtwork(
      NetworkImage(
        requestUrl(artUrl, draw),
        // Empty wherever the browser is attaching a cookie for us, which
        // is where this store belongs and is what keeps the fast
        // browser-native decode path. Carried anyway, so this class is
        // not one condition away from being the unauthenticated fetch
        // the whole pipeline exists to have got rid of.
        headers: authHeadersFor(artUrl, baseUrl, token),
      ),
      store: this,
      artUrl: artUrl,
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
    final rung = absentRung(artUrl, px);
    if (knownAbsent(artUrl, rung)) return null;
    final fetched = await fetchArtwork(
      _dio,
      requestUrl(artUrl, px),
      headers: authHeadersFor(artUrl, baseUrl, token),
      onAbsent: () => noteAbsent(artUrl, rung),
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
  Future<void> unpinExact(String pid, List<OwedPin> owed) async {}

  @override
  Future<void> evict(String artUrl) async {
    // Async, so a URL that cannot be read fails the future, not the
    // caller; the replacement is still noted before the first await.
    await replaceCover(artUrl, (covers) {
      // The whole ladder, because that is the whole set of keys a cover
      // can be held under. Nothing has to be remembered to be dropped.
      final held = <ImageProvider?>[
        for (final url in covers)
          for (final draw in kArtworkDrawSizes) imageFor(url, draw),
      ];
      return () async {
        for (final image in held) {
          await image?.evict();
        }
      };
    });
  }

  @override
  Future<void> evictAll() async {
    // The decoded copies are under the old names and age out; the
    // browser's are not ours to drop.
    noteAllReplaced();
  }

  @override
  void oweEvictAll() => _replaced.owe();

  @override
  Future<void> forgetEverything() async {
    // The replacement tags are folded, not dropped: the browser's cache
    // is not ours to empty and can answer the next sign-in's draw of a
    // replaced cover with the old bytes, but which covers those were is
    // not the next account's to read.
    _replaced.fold();
    dropDecodedArtwork();
    forgetAbsences();
  }

  @override
  void dispose() {
    _replaced.close();
    _dio.close(force: true);
  }
}

/// The sized cover the web store hands out, which tells its store when
/// the server answers that there is no artwork at this URL.
///
/// The store hands out providers rather than drawing, so this is where a
/// failed draw can be seen: [WaxArtwork] is a one-way function from a
/// size to a provider and cannot report anything back, but the store
/// builds the provider, so it can watch the load it just handed out.
///
/// A [ResizeImage] subclass rather than a wrapper around one, so the
/// shape a caller sees is unchanged: still a resize of a [NetworkImage],
/// still keyed and cached identically.
///
/// Only a 404 counts. Being offline, or a server that is down, must not
/// be remembered as "this item has no cover" - the next attempt would
/// find one, and the monogram would outlive the outage.
class _WatchedArtwork extends ResizeImage {
  const _WatchedArtwork(
    super.imageProvider, {
    required this.store,
    required this.artUrl,
    super.width,
    super.height,
    super.policy,
    super.allowUpscaling,
  });

  final ArtworkStore store;

  /// The unsized URL the absence is recorded against, at the rung the
  /// fetch carried.
  final String artUrl;

  @override
  ImageStreamCompleter loadImage(
    ResizeImageKey key,
    ImageDecoderCallback decode,
  ) {
    final completer = super.loadImage(key, decode);
    // Ephemeral: it removes itself after the first error or image, and
    // by contract affects neither the completer's listener count nor its
    // disposal, so watching costs the image cache nothing.
    completer.addEphemeralErrorListener((Object error, StackTrace? stack) {
      if (error is NetworkImageLoadException && error.statusCode == 404) {
        final w = width;
        store.noteAbsent(
          artUrl,
          w == null ? null : store.absentRung(artUrl, w),
        );
      }
    });
    return completer;
  }

  @override
  bool operator ==(Object other) =>
      other is _WatchedArtwork &&
      super == other &&
      other.artUrl == artUrl &&
      identical(other.store, store);

  @override
  int get hashCode =>
      Object.hash(super.hashCode, artUrl, identityHashCode(store));
}

/// Drops every decoded copy from Flutter's own image cache.
///
/// Guarded because sign-out is reachable from a provider-level test,
/// which runs with no painting binding at all - and with nothing
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

/// The transport an artwork store fetches over.
///
/// Its own deadlines, tighter than the API client's: a cover is one
/// small image among a screenful, and a request that hangs holds a
/// connection out of a pool the rest of the grid is queueing for. A
/// failure here is a monogram, so a short budget costs nothing.
Dio artworkTransport() => Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ),
);

/// What one artwork GET came to.
sealed class ArtworkAnswer {
  const ArtworkAnswer();
}

/// The bytes, and the validator to ask with next time.
final class ArtworkFetched extends ArtworkAnswer {
  const ArtworkFetched(this.art);

  final ArtworkBytes art;
}

/// A 304: the caller's validator still names the server's bytes.
final class ArtworkUnchanged extends ArtworkAnswer {
  const ArtworkUnchanged();
}

/// A 404: the server saying there is nothing here.
final class ArtworkAbsent extends ArtworkAnswer {
  const ArtworkAbsent();
}

/// The server answered with a [status] that gives no cover: a refusal,
/// a failure of its own, or a 200 with nothing in it.
final class ArtworkRefused extends ArtworkAnswer {
  const ArtworkRefused(this.status);

  final int status;

  /// Whether the status is about the session or the server as a whole
  /// and says nothing of this cover: a credential it will not hear, a
  /// request it has no time for, a gateway with nothing behind it.
  bool get ofTheServer =>
      const <int>{401, 408, 429, 502, 503, 504}.contains(status);
}

/// No answer at all: unreachable, cut off, or one that cannot be read.
final class ArtworkUnanswered extends ArtworkAnswer {
  const ArtworkUnanswered();
}

/// One artwork GET, for a caller that tells the answers apart: a walk
/// of pinned covers goes on past a 304, a 404 and a cover the server
/// will not give, and stops for a server that did not answer.
Future<ArtworkAnswer> askArtwork(
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
        // Every status is an answer: which one is the caller's to read.
        validateStatus: (int? status) => true,
      ),
    );
    final status = response.statusCode;
    if (status == null) return const ArtworkUnanswered();
    if (status == 404) return const ArtworkAbsent();
    if (status == 304) return const ArtworkUnchanged();
    final body = response.data;
    if (status != 200 || body == null || body.isEmpty) {
      return ArtworkRefused(status);
    }
    return ArtworkFetched(
      ArtworkBytes(
        bytes: Uint8List.fromList(body),
        etag: response.headers.value('etag') ?? '',
      ),
    );
  } catch (_) {
    // Everything, not just DioException: dio casts the response body
    // outside its own error wrapping, so a body that is not what was
    // asked for arrives as a plain TypeError. This is called from
    // background work nobody is awaiting - a warm-ahead, a pin beside a
    // download - where an escaping error is an unhandled one, and the
    // answer to every failure here is the same anyway: no bytes, and the
    // monogram that is already the drawn state for a cover there is none
    // of.
    return const ArtworkUnanswered();
  }
}

/// One artwork GET. Answers null for a 304 (the caller already has these
/// bytes) and for any failure, which is always drawable: a missing cover
/// is a monogram, not an error dialog.
///
/// [onAbsent] fires only for a 404 - the server saying there is nothing
/// here, as opposed to being unable to say - so a caller can stop
/// asking without confusing an outage for an empty cover.
Future<ArtworkBytes?> fetchArtwork(
  Dio dio,
  String url, {
  Map<String, String> headers = const <String, String>{},
  String? ifNoneMatch,
  void Function()? onAbsent,
}) async {
  final answer = await askArtwork(
    dio,
    url,
    headers: headers,
    ifNoneMatch: ifNoneMatch,
  );
  if (answer is ArtworkAbsent) onAbsent?.call();
  return answer is ArtworkFetched ? answer.art : null;
}
