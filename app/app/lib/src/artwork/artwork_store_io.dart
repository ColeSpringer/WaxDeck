/// The native artwork store: a disk cache that authenticates, and pins
/// that survive going offline.
library;

import 'dart:async';
import 'dart:convert';
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
import 'art_slot.dart';
import 'artwork_store.dart';
import 'pin_refresh.dart';

/// The native store. Web and tests get [NetworkArtworkStore] instead; a
/// test that hands in a disk [cache] of its own gets the native one.
ArtworkStore createArtworkStore({
  required String baseUrl,
  required ArtworkPinStore pins,
  String? Function()? token,
  TransferGate pinGate = const OpenGate(),
  required bool Function() reachable,
  @visibleForTesting CacheManager? cache,
}) {
  // A widget test has no application-support directory to cache into and
  // no server to fetch from; the plain network store draws monograms
  // there, which is what a test that does not stub artwork wants.
  if (inFlutterTest && cache == null) {
    return NetworkArtworkStore(baseUrl: baseUrl, token: token);
  }
  return CachedArtworkStore(
    baseUrl: baseUrl,
    pins: pins,
    token: token,
    pinGate: pinGate,
    reachable: reachable,
    cache: cache,
  );
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
///
/// With the server not known to be reachable, what the device holds is
/// drawn and nothing is asked: the cache's copy of the size asked for,
/// then the pin. A cover drawn off a pin is remembered until it is next
/// named, so one whose pin was owed a refresh is told replaced when the
/// refresh lands or the server is back in reach, whichever is first, and
/// one drawn there by a fetch that failed in reach a walk's retry later.
///
/// When covers changed and nothing says which, the disk cache is emptied
/// and every pin is asked about again, in the background and no faster
/// than [PinRefresh] allows. Both are owed from the moment they are
/// promised ([oweEvictAll]) and written to [owedFile], so a session that
/// ends first leaves them to the next start.
///
/// A download found with no pin, as a sign-out leaves every one, has
/// its pins made by the same walk when [pinHeld] names it. A size the
/// server answers it has no cover at is kept in [owedFile] too, so it is
/// asked once and not once a launch, until the item is named replaced,
/// every cover is, or a sign-out.
class CachedArtworkStore extends ArtworkStore {
  CachedArtworkStore({
    required this.baseUrl,
    required this.pins,
    this.token,
    Dio? client,
    CacheManager? cache,
    Directory? pinDirectory,
    TransferGate pinGate = const OpenGate(),
    Duration pinPace = const Duration(milliseconds: 250),
    Duration pinRetry = const Duration(minutes: 2),
    required this._reachable,
    super.replaced,
  }) : _dio = client ?? artworkTransport(),
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
           ) {
    _refresh = PinRefresh(
      pins: pins,
      gate: pinGate,
      ask: _askAbout,
      make: _askFor,
      remember: (walk) {
        _owed.pins = walk;
        return _owed.save();
      },
      pace: pinPace,
      retryAfter: pinRetry,
    );
    _ready = _start();
  }

  /// The file in the pin directory that says what is still owed.
  static const String owedFile = 'owed.json';

  @override
  final String baseUrl;

  final ArtworkPinStore pins;
  final String? Function()? token;

  /// Whether the server is known to be reachable now.
  final bool Function() _reachable;

  /// The covers whose picture under the name they have now came off a
  /// pin, each by its art URL, with the pid that pin is held under.
  final Map<String, String> _offPin = <String, String>{};

  /// Moves each time the server is reached: a draw that found it out of
  /// reach tells by it, as it records a pin, that a check went past it.
  int _reached = 0;

  /// The owed check a failed fetch in reach set going, until it runs.
  Timer? _askingLater;

  /// Told the covers this store names anew by itself.
  final Set<void Function(String artUrl)> _renamed =
      <void Function(String artUrl)>{};

  /// Done once nothing this store set going in the background is still
  /// running: its start, a promise being written, a walk of the pins.
  @visibleForTesting
  Future<void> get settled async {
    await _ready;
    await _owing;
    await _wanting;
    await _refresh.settled;
    await _owed.save();
  }

  late final PinRefresh _refresh;

  /// The last [pinHeld] being taken up.
  Future<void> _wanting = Future<void>.value();

  /// Hears each pid [pinHeld] has a cover pinned for, and the pids it
  /// has heard since the last call.
  void Function(String pid)? _landed;
  final Set<String> _landedFor = <String>{};

  /// The pid whose pin is being made, and whether its cover was named
  /// replaced while the server was asked.
  String? _making;
  bool _madeStale = false;

  /// How many pins one read of them all takes at a time.
  static const int _pinPage = 512;

  /// What is still owed, as [owedFile] holds it.
  late final _Owed _owed = _Owed(_pinDirectory);

  /// Done once what an earlier session owed is known, and its disk
  /// cache emptied where that was owed. Every read of the cache waits
  /// on it.
  late final Future<void> _ready;

  /// The last promise being written.
  Future<void> _owing = Future<void>.value();

  /// Counts promises, so one made while another is being kept is not
  /// written off with it.
  int _promises = 0;

  /// Moves at each sign-out: a cover fetched from before one is not
  /// kept.
  int _forgot = 0;

  /// The emptying under way. A read of the cache waits it out, so a file
  /// fetched under the new name is not swept with the old ones.
  Future<void>? _emptying;

  Future<void> _cacheReady() async {
    await _ready;
    for (var emptying = _emptying; emptying != null; emptying = _emptying) {
      try {
        await emptying;
      } catch (_) {
        // The caller of evictAll hears of it.
      }
    }
  }

  final Dio _dio;
  final CacheManager _cache;

  /// Where pinned covers are written. Resolved once, and supplied
  /// directly by tests, which have no application-support directory.
  Future<Directory>? _pinDir;

  @override
  ImageProvider? imageFor(String? artUrl, int px) {
    if (artUrl == null || artUrl.isEmpty) return null;
    final draw = artworkDrawSize(px);
    if (knownAbsent(artUrl, absentRung(artUrl, draw))) return null;
    return _StoredArtwork(
      store: this,
      artUrl: artUrl,
      px: draw,
      asked: requestUrl(artUrl, draw),
    );
  }

  Future<void> _start() async {
    try {
      await _owed.load();
      if (_owed.pins case final walk?) _refresh.resume(walk);
      if (!_owed.cache) return;
      // No floor with it: nothing is decoded yet, and with the files
      // gone the untagged names answer afresh.
      await _cache.emptyCache();
      _owed.cache = false;
      // Every cover is asked for afresh, one a download was told it has
      // none of included.
      _owed.none.clear();
      _refresh.request();
      await _owed.save();
    } catch (_) {
      // No directory to read, or a cache that will not empty: what is
      // owed stays owed.
    }
  }

  @override
  Future<Uint8List?> bytesFor(String artUrl, int px) async {
    final rung = absentRung(artUrl, px);
    if (knownAbsent(artUrl, rung)) return null;
    // Out of reach, what the device holds is drawn and nothing is asked:
    // a fetch nobody can answer holds the row on its placeholder for as
    // long as the connect hangs. Only a draw with nothing held goes on to
    // ask.
    final away = !_reachable();
    final reached = _reached;
    if (away) {
      await _cacheReady();
      try {
        final held = await _fallbackBytes(
          artUrl,
          requestUrl(artUrl, px),
          px,
          awayAt: reached,
        );
        if (held != null) return held;
      } catch (_) {
        // A pin that cannot be read: the fetch is what is left.
      }
    }
    await _cacheReady();
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
        noteAbsent(artUrl, rung);
        return null;
      }
      return away ? null : _fallbackBytes(artUrl, url, px);
    } catch (_) {
      // Offline, server down, or a credential the server refused. Out of
      // reach, what is held was read before the asking.
      return away ? null : _fallbackBytes(artUrl, url, px);
    }
  }

  /// What can be drawn when the server could not be asked. A stale copy
  /// of exactly this size beats a pin of another size, and either beats
  /// an empty tile. [awayAt] is [_reached] where the draw found the server
  /// out of reach, null in reach.
  Future<Uint8List?> _fallbackBytes(
    String artUrl,
    String url,
    int px, {
    int? awayAt,
  }) async {
    try {
      final stale = await _cache.getFileFromCache(url);
      if (stale != null && stale.file.existsSync()) {
        // Awaited inside the try on purpose: a read that fails after the
        // existsSync - a file swept between the two - is exactly what
        // the catch below is here to fall back from.
        return await stale.file.readAsBytes();
      }
    } catch (_) {
      // The cache itself is unavailable (no storage to open, a corrupt
      // index). The pin is the layer that does not depend on it.
    }
    return _pinnedBytes(artUrl, px, awayAt);
  }

  @override
  Future<void> warm(String artUrl, int px) async {
    if (knownAbsent(artUrl, absentRung(artUrl, px))) return;
    // Out of reach there is nothing to warm from, and the disk cache
    // fetches a few at a time: warms hung on the connect would hold up
    // the draws queued behind them.
    if (!_reachable()) return;
    await _cacheReady();
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
    // Only for an item the device holds and is not freeing: the caller
    // checked that the audio is on disk, and this is where that is still
    // true. See [ArtworkPinStore.mayPin].
    final forgot = _forgot;
    if (!await pins.mayPin(pid)) return;
    final dir = await _pinDirectory();
    final held = <int, ArtworkPinRecord>{
      for (final pin in await pins.pinsFor(pid)) pin.sizePx: pin,
    };
    for (final rung in kOfflineArtworkRungs) {
      // Absence is per rung: the server refuses some sizes of a cover
      // it still serves at others.
      if (knownAbsent(artUrl, rung)) continue;
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
        // there is no cover at this rung as a draw is.
        onAbsent: () => noteAbsent(artUrl, rung),
      );
      if (fetched == null) {
        // Absent, unchanged, or unreachable; the next rung asks its
        // own question either way.
        continue;
      }
      try {
        if (!await _keep(dir, pid, artUrl, rung, fetched, forgot)) return;
      } catch (_) {
        // A full disk, a revoked directory. This runs beside a download
        // that has already succeeded, and a cover that could not be kept
        // is not a failed download - the next one tries again, and until
        // then the item plays offline under a monogram.
      }
    }
  }

  @override
  void pinHeld(Map<String, String> held, {void Function(String pid)? landed}) {
    _landed = landed;
    _landedFor.clear();
    final forgot = _forgot;
    final wanting = _wanting = _wanting
        .then((_) => _wantHeld(held, forgot))
        // Pins that cannot be read: the next call asks again.
        .catchError((Object _) {});
    unawaited(wanting);
  }

  /// Hands the walk each pin [held] lacks, from one read of what is
  /// pinned however many are held: nothing is looked up, and no gate
  /// looked at, for a download that needs nothing.
  Future<void> _wantHeld(Map<String, String> held, int forgot) async {
    // After the start has taken up what an earlier session left.
    await _ready;
    final pinned = held.isEmpty ? const <PinCursor>{} : await _pinned();
    // Signed out since: the next account's reach names its own.
    if (forgot != _forgot) return;
    // What the server said of a download no longer held is not kept.
    final answered = _owed.none.length;
    _owed.none.removeWhere((pid, _) => !held.containsKey(pid));
    final wanted = <PinCursor, String>{};
    for (final MapEntry(key: pid, value: artUrl) in held.entries) {
      if (!isWaxDeckUrl(artUrl, baseUrl)) continue;
      final none = _owed.none[pid];
      for (final rung in kOfflineArtworkRungs) {
        final at = (pid: pid, sizePx: rung);
        if (pinned.contains(at)) continue;
        if (none != null && none.contains(rung)) continue;
        // A draw learned it this session: no need to ask again yet.
        if (knownAbsent(artUrl, rung)) continue;
        wanted[at] = artUrl;
      }
    }
    _refresh.want(wanted);
    if (_owed.none.length != answered) await _owed.save();
  }

  /// Where every pin is.
  Future<Set<PinCursor>> _pinned() async {
    final pinned = <PinCursor>{};
    PinCursor? after;
    while (true) {
      final page = await pins.pinsAfter(after, limit: _pinPage);
      for (final pin in page) {
        pinned.add(after = (pid: pin.pid, sizePx: pin.sizePx));
      }
      if (page.length < _pinPage) return pinned;
    }
  }

  /// Asks for a pin [PinRefresh] has to make: one size of the cover of a
  /// download held without it.
  Future<PinAnswer> _askFor(PinCursor at, String artUrl) async {
    final (:pid, sizePx: rung) = at;
    if (!isWaxDeckUrl(artUrl, baseUrl)) return PinAnswer.skipped;
    final forgot = _forgot;
    // Only for an item the device holds and is not freeing, as in
    // [pinForOffline].
    if (!await pins.mayPin(pid)) return PinAnswer.skipped;
    _making = pid;
    _madeStale = false;
    try {
      final answer = await askArtwork(
        _dio,
        sizedArtUrl(artUrl, rung),
        headers: authHeadersFor(artUrl, baseUrl, token),
      );
      // Signed out meanwhile: the answer was for the last account.
      if (forgot != _forgot) return PinAnswer.skipped;
      switch (answer) {
        case ArtworkAbsent():
          // Said before its cover was named replaced, it is no answer to
          // keep: asked again with the walk's refusals.
          if (_madeStale) return PinAnswer.refused;
          noteAbsent(artUrl, rung);
          // Written when the walk next tells its place.
          (_owed.none[pid] ??= <int>{}).add(rung);
          return PinAnswer.gone;
        case ArtworkUnanswered():
          return PinAnswer.unanswered;
        case ArtworkRefused(:final ofTheServer):
          return ofTheServer ? PinAnswer.unanswered : PinAnswer.refused;
        case ArtworkUnchanged():
          // No validator went with it: nothing to keep.
          return PinAnswer.refused;
        case ArtworkFetched(:final art):
          try {
            final dir = await _pinDirectory();
            if (!await _keep(dir, pid, artUrl, rung, art, forgot)) {
              return PinAnswer.skipped;
            }
          } catch (_) {
            // A full disk, a revoked directory: tried again with the
            // walk's refusals.
            return PinAnswer.refused;
          }
          if (_landedFor.add(pid)) {
            try {
              _landed?.call(pid);
            } catch (_) {
              // What hears it may be gone, a container torn down.
            }
          }
          // Fetched before its cover was named replaced: asked about
          // again as any pin named is.
          if (_madeStale) _refresh.requestFor([at]);
          return PinAnswer.replaced;
      }
    } finally {
      _making = null;
    }
  }

  /// Writes one fetched rung of [pid]'s cover and records it. False
  /// where the item was freed meanwhile, or the pins cleared since
  /// [forgot], the cover taken back.
  Future<bool> _keep(
    Directory dir,
    String pid,
    String artUrl,
    int rung,
    ArtworkBytes fetched,
    int forgot,
  ) async {
    final file = File(p.join(dir.path, '${_fileSafe(pid)}-$rung.img'));
    await writeFileDurably(file, fetched.bytes);
    final record = ArtworkPinRecord(
      pid: pid,
      sizePx: rung,
      artUrl: artUrl,
      etag: fetched.etag,
      localPath: file.path,
      sizeBytes: fetched.bytes.length,
      pinnedAt: DateTime.now().toUtc(),
    );
    await pins.put(record);
    // The cover took its time coming, and the item may have been freed,
    // or promised to the free, meanwhile. Asked after the row is
    // written: a commit that lands later finds the pin and lists it,
    // and one that landed first is seen here, so the cover takes
    // itself back rather than be stranded for an item that is gone.
    if (forgot == _forgot && await pins.mayPin(pid)) {
      // A picture drawn off the copy this replaced is not left on screen.
      _replaceDrawnOff((held) => held == pid);
      return true;
    }
    await _delete([record]);
    await pins.removeExactly(pid, [(sizePx: rung, pinnedAt: record.pinnedAt)]);
    return false;
  }

  /// Asks the server about one pinned cover, for [PinRefresh].
  Future<PinAnswer> _askAbout(ArtworkPinRecord pin) async {
    // Asked where it is recorded, under the pid it is held under: a kind
    // change moves a pin and leaves its URL naming the old pid. A pin
    // from another address, which this server has not named since, is
    // not asked for with this one's credential, and one for an item
    // being freed is not asked for.
    final url = pin.artUrl.replaceFirst(
      _itemArt,
      '/items/${Uri.encodeComponent(pin.pid)}/art',
    );
    if (!isWaxDeckUrl(url, baseUrl)) return PinAnswer.skipped;
    final forgot = _forgot;
    if (!await pins.mayPin(pin.pid)) return PinAnswer.skipped;
    final answer = await askArtwork(
      _dio,
      sizedArtUrl(url, pin.sizePx),
      headers: authHeadersFor(url, baseUrl, token),
      // Only against the file it validates, as in [pinForOffline].
      ifNoneMatch: File(pin.localPath).existsSync() ? pin.etag : null,
    );
    // Signed out meanwhile: the pin is gone, and its answer with it.
    if (forgot != _forgot) return PinAnswer.skipped;
    switch (answer) {
      case ArtworkUnchanged():
        return PinAnswer.unchanged;
      case ArtworkAbsent():
        return PinAnswer.gone;
      case ArtworkUnanswered():
        return PinAnswer.unanswered;
      case ArtworkRefused(:final ofTheServer):
        return ofTheServer ? PinAnswer.unanswered : PinAnswer.refused;
      case ArtworkFetched(:final art):
        try {
          final dir = await _pinDirectory();
          // Recorded where it was asked, under its own pid.
          final kept = await _keep(dir, pin.pid, url, pin.sizePx, art, forgot);
          if (!kept && forgot != _forgot) return PinAnswer.skipped;
        } catch (_) {
          // A full disk: the copy it had is still the one it has.
          return PinAnswer.unchanged;
        }
        return PinAnswer.replaced;
    }
  }

  @override
  Future<void> unpinExact(String pid, List<OwedPin> owed) async {
    // The files before the rows, as in [unpin], and only the covers that
    // match what was listed, by size and by the instant they were pinned.
    final listed = {
      for (final o in owed) (o.sizePx, o.pinnedAt.millisecondsSinceEpoch),
    };
    await _delete([
      for (final pin in await pins.pinsFor(pid))
        if (listed.contains((pin.sizePx, pin.pinnedAt.millisecondsSinceEpoch)))
          pin,
    ]);
    await pins.removeExactly(pid, owed);
  }

  @override
  Future<void> unpin(String pid) async {
    // The files before the rows: an unpin is retried (the free a commit
    // promised is finished at the next start), and a retry can only find
    // what the rows still say, so one cut short must leave a row and not a
    // file nothing names. Only the rows it read: a cover pinned meanwhile
    // keeps its row and its file.
    final held = await pins.pinsFor(pid);
    await _delete(held);
    await pins.removeExactly(pid, [
      for (final pin in held) (sizePx: pin.sizePx, pinnedAt: pin.pinnedAt),
    ]);
  }

  @override
  Future<void> evict(String artUrl) async {
    final dropping = _replace(artUrl);
    try {
      await _askAgainAbout(artUrl);
    } finally {
      await dropping;
    }
  }

  /// [evict] less the ask about the pin: the cover is named anew, what
  /// was held under its old names dropped, and one on screen told.
  Future<void> _replace(String artUrl) async {
    await replaceCover(artUrl, (covers) {
      // Both ladders, for every role: every size the decode can be keyed
      // at, and every rung a file can be held under, each role's file
      // under its own URL. The untagged names too: a floor moves a cover
      // off them without emptying them, and the next launch asks there
      // again.
      final held = <ImageProvider?>[
        for (final url in covers)
          for (final draw in kArtworkDrawSizes) imageFor(url, draw),
      ];
      final files = <String>{
        for (final url in covers)
          for (final rung in kArtworkRungs) ...<String>[
            requestUrl(url, rung),
            requestUrl(url, rung, tagged: false),
          ],
      };
      return () async {
        for (final image in held) {
          await image?.evict();
        }
        for (final file in files) {
          await _cache.removeFile(file);
        }
      };
    });
  }

  /// Names anew each cover whose picture came off a pin of a pid [stale]
  /// holds for, as a replacement names it.
  void _replaceDrawnOff(bool Function(String pid) stale) {
    final drawn = <String>[
      for (final MapEntry(key: url, value: pid) in _offPin.entries)
        if (stale(pid)) url,
    ];
    // What was read off the old bytes elsewhere goes with them.
    for (final url in drawn) {
      for (final told in _renamed) {
        told(url);
      }
    }
    final entities = <String>{};
    for (final url in drawn) {
      if (entities.add(coverKeyOf(url))) {
        unawaited(_replace(url).catchError((Object _) {}));
      }
    }
  }

  @override
  void onRenamed(void Function(String artUrl) told) => _renamed.add(told);

  @protected
  @override
  void noteReplaced(String artUrl) {
    // Nothing under the new name has come off a pin yet.
    coverUrlsOf(artUrl).forEach(_offPin.remove);
    if (artworkPidOf(artUrl) case final pid?) _askHeldAgain(pid);
    super.noteReplaced(artUrl);
  }

  @protected
  @override
  void noteAllReplaced() {
    _offPin.clear();
    _askHeldAgain(null);
    super.noteAllReplaced();
  }

  /// A download of [pid], or any where null, that the server said had no
  /// cover, or would not give one, may have one now: what it said is
  /// dropped, an answer on its way with it, and the next [pinHeld] asks.
  void _askHeldAgain(String? pid) {
    if (pid == null || pid == _making) _madeStale = true;
    _refresh.wantAgain(pid);
    unawaited(() async {
      // After the start has read what an earlier session kept.
      await _ready;
      if (pid == null) {
        if (_owed.none.isEmpty) return;
        _owed.none.clear();
      } else if (_owed.none.remove(pid) == null) {
        return;
      }
      await _owed.save();
    }());
  }

  @override
  void serverReached() {
    _reached++;
    unawaited(_askOwedAfresh());
  }

  /// A pin's refresh can wait at the walk's gate long after the server
  /// is back in reach (wifi-only downloads, on mobile data): a cover
  /// drawn off a pin still owed one asks the server now.
  Future<void> _askOwedAfresh() async {
    // After the start has taken up what an earlier session left.
    await _ready;
    if (_owedNow() case final owed?) _replaceDrawnOff(owed);
  }

  /// Whether the pins held under a pid are owed their refresh, null with
  /// nothing owed: every pin while the walk of them all is under way,
  /// else the named and the refused.
  bool Function(String pid)? _owedNow() {
    final walk = _owed.pins;
    if (walk == null) return null;
    if (walk.whole && walk.retried == null) return (_) => true;
    return <String>{
      for (final at in walk.named) at.pid,
      for (final at in walk.passed) at.pid,
    }.contains;
  }

  /// A fetch in reach failed and drew a pin of [pid] still owed its
  /// refresh, and no turn to online follows: the owed check runs once a
  /// stopped walk would look again, and no sooner.
  void _askLater(String pid) {
    if (_askingLater != null || !(_owedNow()?.call(pid) ?? false)) return;
    _askingLater = Timer(_refresh.retryAfter, () {
      _askingLater = null;
      // Out of reach, the next turn to online asks.
      if (_reachable()) unawaited(_askOwedAfresh());
    });
  }

  /// A pin is a promise that a downloaded item has a cover offline, and
  /// the promise is for the cover it has now: the pin of the picture
  /// [artUrl] names is asked about again, by the walk, under its gate and
  /// pace. Wherever its bytes came from: a kind change leaves a pin's
  /// URL naming the old pid and a move of the server the old address, so
  /// the pin is recorded at [artUrl] first, which is where the walk asks,
  /// in a later session too. Only that picture's: an item's other roles
  /// share its pid, and one of those replaced is not its offline cover.
  Future<void> _askAgainAbout(String artUrl) async {
    final pid = artworkPidOf(artUrl);
    if (pid == null || !isWaxDeckUrl(artUrl, baseUrl)) return;
    final role = _roleOf(artUrl);
    final named = <PinCursor>[];
    for (final pin in await pins.pinsFor(pid)) {
      if (_roleOf(pin.artUrl) != role) continue;
      if (pin.artUrl != artUrl) await pins.recordUrl(pin, artUrl);
      named.add((pid: pin.pid, sizePx: pin.sizePx));
    }
    if (named.isEmpty) return;
    // After the start has taken up what an earlier session left.
    await _ready;
    _refresh.requestFor(named);
  }

  @override
  Future<void> evictAll() async {
    noteAllReplaced();
    final emptying = _emptying = _empty();
    try {
      await emptying;
    } finally {
      if (identical(_emptying, emptying)) _emptying = null;
    }
  }

  Future<void> _empty() async {
    await _ready;
    // Owed until the files are gone, for a kill part-way.
    final promised = ++_promises;
    if (!_owed.cache) {
      _owed.cache = true;
      await _owed.save();
    }
    // The files too: a later launch remembers no floor and asks under
    // the untagged names again.
    await _cache.emptyCache();
    if (_promises == promised) _owed.cache = false;
    _refresh.request();
    await _owed.save();
  }

  @override
  void oweEvictAll() {
    _promises++;
    final owing = _owing = _owe();
    unawaited(owing);
  }

  Future<void> _owe() async {
    await _ready;
    if (_owed.cache) return;
    _owed.cache = true;
    await _owed.save();
  }

  @override
  Future<void> forgetEverything() async {
    _forgot++;
    _offPin.clear();
    // Nothing is asked for from here on: the next account's reach names
    // its own.
    _refresh.forget();
    _landed = null;
    dropDecodedArtwork();
    forgetAbsences();
    await _ready;
    // Again, for a walk the start took up meanwhile.
    _refresh.forget();
    await _delete(await pins.clear());
    await _cache.emptyCache();
    // With no pin and no cached file there is nothing left to owe, and
    // what the server said of the last account's downloads is not the
    // next one's.
    _promises++;
    _owed
      ..cache = false
      ..pins = null
      ..none.clear();
    await _owed.save();
  }

  @override
  void dispose() {
    _askingLater?.cancel();
    _refresh.dispose();
    // Another store may stand over the same directory from here on.
    _owed.close();
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
  /// one big enough is the tightest fit. [awayAt] as [_fallbackBytes].
  Future<Uint8List?> _pinnedBytes(String artUrl, int px, int? awayAt) async {
    final pid = artworkPidOf(artUrl);
    if (pid == null) return null;
    final held = await pins.pinsToDraw(pid);
    if (held.isEmpty) return null;
    var chosen = held.first;
    for (final pin in held) {
      if (pin.sizePx >= px) chosen = pin;
    }
    final file = File(chosen.localPath);
    if (!file.existsSync()) return null;
    // Before the read: a refresh that lands during it finds this draw.
    _offPin[artUrl] = chosen.pid;
    if (awayAt == null) {
      _askLater(chosen.pid);
    } else if (awayAt != _reached) {
      // Reached since this draw found the server out of reach: the check
      // that turn made went before this record.
      unawaited(_askOwedAfresh());
    }
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

/// What the native store still owes after covers changed and nothing
/// said which: its disk cache an emptying, its pins a walk. With it,
/// what the server answered it has no cover for among the downloads
/// held without one, which is not owed again. One small file beside the
/// pins, there only while it has something to say.
class _Owed {
  _Owed(this._directory);

  final Future<Directory> Function() _directory;

  /// The disk cache holds covers from before the change.
  bool cache = false;

  /// The walk of the pins that is owed or under way.
  PinWalk? pins;

  /// The sizes, by pid, at which the server answered it has no cover for
  /// a download held without one: not asked for again.
  final Map<String, Set<int>> none = <String, Set<int>>{};

  /// What the file holds, null for no file.
  String? _written;

  Future<void> _last = Future<void>.value();

  bool _closed = false;

  /// Nothing is written from here on, a write still queued included.
  void close() => _closed = true;

  Future<File> _file() async =>
      File(p.join((await _directory()).path, CachedArtworkStore.owedFile));

  /// Reads what an earlier session left. A file that cannot be read was
  /// still written for something: everything is owed.
  Future<void> load() async {
    final file = await _file();
    if (!file.existsSync()) return;
    try {
      final raw = file.readAsStringSync();
      final held = jsonDecode(raw) as Map<String, dynamic>;
      _written = raw;
      cache = held['cache'] == true;
      if (held['pins'] case final Map<String, dynamic> walk) {
        pins = PinWalk(
          after: _readCursor(walk['after']),
          again: walk['again'] == true,
          tries: switch (walk['tries']) {
            final int tries when tries > 0 => tries,
            _ => 0,
          },
          passed: switch (walk['passed']) {
            final List<dynamic> passed => [
              for (final at in passed) ?_readCursor(at),
            ],
            _ => const <PinCursor>[],
          },
          retried: switch (walk['retried']) {
            final int retried when retried >= 0 => retried,
            _ => null,
          },
          named: switch (walk['named']) {
            final List<dynamic> named => [
              for (final at in named) ?_readCursor(at),
            ],
            _ => const <PinCursor>[],
          },
          whole: walk['whole'] != false,
        );
      }
      // Absent from a file written before these were kept.
      if (held['none'] case final Map<String, dynamic> answered) {
        for (final MapEntry(key: pid, value: sizes) in answered.entries) {
          if (sizes is! List<dynamic>) continue;
          final read = sizes.whereType<int>().toSet();
          if (read.isNotEmpty) none[pid] = read;
        }
      }
    } catch (_) {
      cache = true;
      pins = const PinWalk();
      none.clear();
    }
  }

  /// Writes what is owed now, after any write still under way. Never
  /// throws: a promise that cannot be kept on disk holds for the session.
  Future<void> save() => _last = _last.then((_) => _write()).catchError((_) {});

  Future<void> _write() async {
    if (_closed) return;
    final walk = pins;
    final raw = !cache && walk == null && none.isEmpty
        ? null
        : jsonEncode(<String, Object>{
            if (cache) 'cache': true,
            if (none.isNotEmpty)
              'none': <String, Object>{
                for (final MapEntry(key: pid, value: sizes) in none.entries)
                  pid: sizes.toList(),
              },
            if (walk != null)
              'pins': <String, Object>{
                if (walk.after case final after?) 'after': _cursorJson(after),
                if (walk.again) 'again': true,
                if (walk.tries > 0) 'tries': walk.tries,
                if (walk.passed.isNotEmpty)
                  'passed': [for (final at in walk.passed) _cursorJson(at)],
                'retried': ?walk.retried,
                if (walk.named.isNotEmpty)
                  'named': [for (final at in walk.named) _cursorJson(at)],
                if (!walk.whole) 'whole': false,
              },
          });
    if (raw == _written) return;
    final file = await _file();
    if (raw == null) {
      if (file.existsSync()) await file.delete();
    } else {
      await writeFileDurably(file, utf8.encode(raw));
    }
    _written = raw;
  }

  static List<Object> _cursorJson(PinCursor at) => <Object>[at.pid, at.sizePx];

  static PinCursor? _readCursor(Object? held) => switch (held) {
    [final String pid, final int sizePx] => (pid: pid, sizePx: sizePx),
    _ => null,
  };
}

/// The item an art URL names, for naming another in its place.
final RegExp _itemArt = RegExp(r'/items/[^/?#]+/art');

/// Which of its item's pictures an art URL names: null for the front.
String? _roleOf(String artUrl) {
  final role = Uri.tryParse(artUrl)?.queryParameters['role'];
  return role == ArtSlot.front.role ? null : role;
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
/// under it. The name it was asked under is part of it too, so a
/// replaced cover is another image: an `Image` handed an equal provider
/// keeps the picture it has.
@immutable
class _StoredArtwork extends ImageProvider<_StoredArtwork> {
  const _StoredArtwork({
    required this.store,
    required this.artUrl,
    required this.px,
    required this.asked,
  });

  final CachedArtworkStore store;
  final String artUrl;

  /// The request this stood for when it was handed out, tag and all.
  /// The fetch asks under whatever name is current by then.
  final String asked;

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
      other.asked == asked &&
      other.px == px &&
      identical(other.store, store);

  @override
  int get hashCode => Object.hash(asked, px, identityHashCode(store));

  @override
  String toString() => 'Artwork($artUrl at ${px}px)';
}
