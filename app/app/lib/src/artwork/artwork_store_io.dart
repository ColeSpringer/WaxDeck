/// The native artwork store: a disk cache that authenticates, and pins
/// that survive going offline.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../sync/test_env/test_env.dart';
import 'artwork_store.dart';

/// The native store. Web and tests get [NetworkArtworkStore] instead.
ArtworkStore createArtworkStore({
  required String baseUrl,
  required ArtworkPinStore pins,
  String? Function()? token,
}) {
  // A widget test has no application-support directory to cache into and
  // no server to fetch from; the plain network store draws monograms
  // there, which is what a test that does not stub artwork wants.
  if (inFlutterTest) {
    return NetworkArtworkStore(baseUrl: baseUrl, token: token);
  }
  return CachedArtworkStore(baseUrl: baseUrl, pins: pins, token: token);
}

/// Artwork on a device that owns its own cache.
///
/// Three layers, tried in order, and the reason there are three:
///
/// 1. A disk cache ([flutter_cache_manager], kept behind this port per
///    the plugin-wrapping rule) holding whatever was looked at recently,
///    revalidated by ETag. Every request carries the bearer token - the
///    bug this store was built to fix is that native builds fetched
///    artwork with no credential at all and silently painted monograms
///    over a library full of covers.
/// 2. Whatever of that cache is stale but still on disk, for when the
///    revalidation cannot be made.
/// 3. The pins: copies promised when the listener downloaded the item,
///    which the cache may not evict and being offline may not lose.
class CachedArtworkStore extends ArtworkStore {
  CachedArtworkStore({
    required this.baseUrl,
    required this.pins,
    this.token,
    Dio? client,
    CacheManager? cache,
    Directory? pinDirectory,
  }) : _dio = client ?? Dio(),
       _pinDir = pinDirectory == null
           ? null
           : Future<Directory>.value(pinDirectory),
       _cache =
           cache ??
           CacheManager(
             Config(
               'waxdeck_art',
               stalePeriod: const Duration(days: 30),
               // Roughly a large library's worth of grid cells at one
               // rung; the pins are what must survive, not this.
               maxNrOfCacheObjects: 1200,
             ),
           );

  @override
  final String baseUrl;

  final ArtworkPinStore pins;
  final String? Function()? token;

  final Dio _dio;
  final CacheManager _cache;

  /// Where pinned covers are written. Resolved once, and supplied
  /// directly by tests, which have no application-support directory.
  Future<Directory>? _pinDir;

  @override
  ImageProvider? imageFor(String? artUrl, int px) {
    if (artUrl == null || artUrl.isEmpty) return null;
    if (knownAbsent(artUrl)) return null;
    return _StoredArtwork(store: this, artUrl: artUrl, px: artworkDrawSize(px));
  }

  @override
  Future<Uint8List?> bytesFor(String artUrl, int px) async {
    if (knownAbsent(artUrl)) return null;
    final url = requestUrl(artUrl, px);
    try {
      final file = await _cache.getSingleFile(
        url,
        headers: authHeadersFor(artUrl, baseUrl, token),
      );
      return await file.readAsBytes();
    } on HttpExceptionWithStatus catch (e) {
      // The server answered, and the answer was that there is no
      // artwork here. Every item carries an art URL whether or not it
      // has art, so this is the ordinary state of a library that has
      // not been enriched, and it must not walk the fallbacks: a stale
      // copy or a pin would draw a cover the server has stopped
      // serving, and a pin lookup is a database query per paint of
      // every art-less cell in the grid. Remembered, so scrolling back
      // over the same art-less row does not ask a second time.
      if (e.statusCode == 404) {
        noteAbsent(artUrl);
        return null;
      }
      return _fallbackBytes(artUrl, url, px);
    } catch (_) {
      // Offline, server down, or a credential the server refused.
      return _fallbackBytes(artUrl, url, px);
    }
  }

  /// What can be drawn when the server could not be asked. A stale copy
  /// of exactly this size beats a pin of another size, and either beats
  /// an empty tile.
  Future<Uint8List?> _fallbackBytes(String artUrl, String url, int px) async {
    try {
      final stale = await _cache.getFileFromCache(url);
      if (stale != null && stale.file.existsSync()) {
        return stale.file.readAsBytes();
      }
    } catch (_) {
      // The cache itself is unavailable (no storage to open, a corrupt
      // index). The pin is the layer that does not depend on it.
    }
    return _pinnedBytes(artUrl, px);
  }

  @override
  Future<void> warm(String artUrl, int px) async {
    if (knownAbsent(artUrl)) return;
    try {
      // Into the disk cache, and no further: reading the file back would
      // be work for a cover nobody has asked to paint yet.
      await _cache.getSingleFile(
        requestUrl(artUrl, px),
        headers: authHeadersFor(artUrl, baseUrl, token),
      );
    } catch (_) {
      // Warming is a nicety; failing at it is not worth reporting.
    }
  }

  @override
  Future<void> pinForOffline(String pid, String? artUrl) async {
    if (artUrl == null || artUrl.isEmpty) return;
    if (!isWaxDeckUrl(artUrl, baseUrl)) return;
    // An item known to have no cover has none at either rung; there is
    // nothing to pin and no reason to ask twice to find that out.
    if (knownAbsent(artUrl)) return;
    final dir = await _pinDirectory();
    final held = <int, ArtworkPinRecord>{
      for (final pin in await pins.pinsFor(pid)) pin.sizePx: pin,
    };
    for (final rung in kOfflineArtworkRungs) {
      final existing = held[rung];
      // A validator is only worth presenting when the file it validates
      // is still there; a 304 against a deleted pin would leave the row
      // pointing at nothing.
      final have =
          existing != null &&
          existing.artUrl == artUrl &&
          File(existing.localPath).existsSync();
      final fetched = await fetchArtwork(
        _dio,
        sizedArtUrl(artUrl, rung),
        headers: authHeadersFor(artUrl, baseUrl, token),
        ifNoneMatch: have ? existing.etag : null,
        // A download of an art-less item is as good a way to learn
        // there is no cover as a draw is, and it stops the second rung
        // asking again.
        onAbsent: () => noteAbsent(artUrl),
      );
      if (fetched == null) {
        // Absent, unchanged, or unreachable. Absent settles both rungs
        // at once, so stop rather than ask the same question again.
        if (knownAbsent(artUrl)) return;
        continue;
      }
      final file = File(p.join(dir.path, '${_fileSafe(pid)}-$rung.img'));
      try {
        await writeFileDurably(file, fetched.bytes);
        await pins.put(
          ArtworkPinRecord(
            pid: pid,
            sizePx: rung,
            artUrl: artUrl,
            etag: fetched.etag,
            localPath: file.path,
            sizeBytes: fetched.bytes.length,
            pinnedAt: DateTime.now().toUtc(),
          ),
        );
      } catch (_) {
        // A full disk, a revoked directory. This runs beside a download
        // that has already succeeded, and a cover that could not be kept
        // is not a failed download - the next one tries again, and until
        // then the item plays offline under a monogram.
      }
    }
  }

  @override
  Future<void> unpin(String pid) async {
    await _delete(await pins.remove(pid));
  }

  @override
  Future<void> evict(String artUrl) async {
    // The absence first: a known-absent URL answers null for every
    // provider, which would leave real decoded bytes behind. See
    // [NetworkArtworkStore.evict].
    forgetAbsent(artUrl);
    // Both ladders: every size the decode can be keyed at, and every
    // rung a file can be held under. Built before the replacement is
    // noted, since these are the names the old bytes are under.
    final held = <ImageProvider?>[
      for (final draw in kArtworkDrawSizes) imageFor(artUrl, draw),
    ];
    final files = <String>[
      for (final rung in kArtworkRungs) requestUrl(artUrl, rung),
    ];
    noteReplaced(artUrl);
    for (final image in held) {
      await image?.evict();
    }
    for (final file in files) {
      await _cache.removeFile(file);
    }
    // A pin is a promise that a downloaded item has a cover offline, and
    // the promise is for the cover it has now. Nothing else would ever
    // revisit it: pins are written by downloads, and this item was
    // downloaded before its artwork changed.
    final pid = artworkPidOf(artUrl);
    if (pid != null && (await pins.pinsFor(pid)).isNotEmpty) {
      await pinForOffline(pid, artUrl);
    }
  }

  @override
  Future<void> forgetEverything() async {
    dropDecodedArtwork();
    forgetAbsences();
    await _delete(await pins.clear());
    await _cache.emptyCache();
  }

  @override
  void dispose() {
    _dio.close(force: true);
    // The manager owns a cache-info store (a file or a database) and a
    // cleanup timer; this store built it, so this store closes it.
    // Closing one that never opened throws from inside the manager (an
    // install that drew no artwork, a test), and a teardown is no place
    // to report that.
    unawaited(_cache.dispose().catchError((Object _) {}));
  }

  /// The smallest pinned copy that still covers [px], or the largest
  /// there is when none does. Pins come back largest first, so the last
  /// one big enough is the tightest fit.
  Future<Uint8List?> _pinnedBytes(String artUrl, int px) async {
    final pid = artworkPidOf(artUrl);
    if (pid == null) return null;
    final held = await pins.pinsFor(pid);
    if (held.isEmpty) return null;
    var chosen = held.first;
    for (final pin in held) {
      if (pin.sizePx >= px) chosen = pin;
    }
    final file = File(chosen.localPath);
    if (!file.existsSync()) return null;
    return file.readAsBytes();
  }

  Future<Directory> _pinDirectory() {
    return _pinDir ??= () async {
      final support = await getApplicationSupportDirectory();
      final dir = Directory(p.join(support.path, 'waxdeck', 'art'));
      await dir.create(recursive: true);
      return dir;
    }();
  }

  Future<void> _delete(List<ArtworkPinRecord> gone) async {
    for (final pin in gone) {
      final file = File(pin.localPath);
      if (file.existsSync()) {
        await file.delete();
      }
    }
  }
}

/// A PID as a file name. PIDs are ULIDs with a type prefix, so this
/// changes nothing in practice; it is here because the name is built
/// from a string the server chose, and a path is not the place to trust
/// one.
String _fileSafe(String pid) => pid.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

/// Bytes on disk, in one piece or not at all: written to a temporary
/// beside the target so the rename cannot cross a filesystem, flushed
/// before it is named, and only then moved into place. A pin row that
/// points at a half-written file is worse than no pin.
Future<void> writeFileDurably(File target, Uint8List bytes) async {
  final temp = File('${target.path}.part');
  final handle = await temp.open(mode: FileMode.writeOnly);
  try {
    await handle.writeFrom(bytes);
    await handle.flush();
  } finally {
    await handle.close();
  }
  if (await temp.length() != bytes.length) {
    await temp.delete();
    throw FileSystemException('short write', temp.path);
  }
  await temp.rename(target.path);
}

/// Artwork drawn from the store rather than straight off the network.
///
/// Its identity is the URL and the size it will paint at, which is what
/// makes the two caches agree: Flutter's image cache holds one decoded
/// copy per (URL, size), and the store holds one file per (URL, rung)
/// under it.
@immutable
class _StoredArtwork extends ImageProvider<_StoredArtwork> {
  const _StoredArtwork({
    required this.store,
    required this.artUrl,
    required this.px,
  });

  final CachedArtworkStore store;
  final String artUrl;

  /// The size this will be decoded at, already rounded to the draw
  /// ladder: it is half the cache key, so two nearby draws that round to
  /// the same step share one decoded copy.
  final int px;

  @override
  Future<_StoredArtwork> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_StoredArtwork>(this);

  @override
  ImageStreamCompleter loadImage(
    _StoredArtwork key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: key._decode(decode),
      scale: 1,
      debugLabel: key.artUrl,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<String>('Artwork', key.artUrl),
        DiagnosticsProperty<int>('Painted at', key.px),
      ],
    );
  }

  Future<ui.Codec> _decode(ImageDecoderCallback decode) async {
    final bytes = await store.bytesFor(artUrl, px);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('no artwork bytes for $artUrl');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    // The fetched rung is the next size up from what will be painted, so
    // decoding it whole would hold up to four times the pixels the
    // screen shows. Bounded on the longest edge, so a portrait cover
    // keeps its shape.
    return decode(
      buffer,
      getTargetSize: (int width, int height) {
        final longest = math.max(width, height);
        if (longest <= px) {
          return ui.TargetImageSize(width: width, height: height);
        }
        final scale = px / longest;
        return ui.TargetImageSize(
          width: math.max(1, (width * scale).round()),
          height: math.max(1, (height * scale).round()),
        );
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _StoredArtwork &&
      other.artUrl == artUrl &&
      other.px == px &&
      identical(other.store, store);

  @override
  int get hashCode => Object.hash(artUrl, px, identityHashCode(store));

  @override
  String toString() => 'Artwork($artUrl at ${px}px)';
}
