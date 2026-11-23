/// The tags replaced covers are asked under, and where a browser keeps
/// them.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../settings/client_settings/browser_settings_store.dart';

/// How long after a cover is replaced a cache may still answer with the
/// bytes it fetched before: `max-age` plus `stale-while-revalidate` of
/// `artCacheControl` in `server/internal/api/handlers.go`. Past it the
/// old copy has to be revalidated, and the ETag has moved.
const Duration kArtworkCacheLifetime = Duration(seconds: 86400 + 604800);

/// The key a replaced cover is kept under: its entity's. An item's art
/// URL names one of its pictures by `role`, and a replacement of any of
/// them is kept as one of the entity's, so every role is asked afresh.
/// Any other URL is its own key.
String coverKeyOf(String artUrl) {
  if (!artUrl.contains('role=')) return artUrl;
  final uri = Uri.tryParse(artUrl);
  if (uri == null ||
      !isItemArt(uri) ||
      !uri.queryParameters.containsKey('role')) {
    return artUrl;
  }
  final rest = <String, String>{...uri.queryParameters}..remove('role');
  if (rest.isEmpty) return artUrl.substring(0, artUrl.indexOf('?'));
  return uri.replace(queryParameters: rest).toString();
}

/// Whether [uri] is an item's art, which has a picture per role.
bool isItemArt(Uri uri) => _itemArt.hasMatch(uri.path);

final RegExp _itemArt = RegExp(r'/items/[^/]+/art$');

/// Which covers were replaced, and the tag each is asked under since.
///
/// Artwork lives at one URL whatever it holds, and the endpoint answers
/// with a day of freshness, so after a cover write every cache between
/// here and the disk goes on serving the old image - the browser's most
/// stubbornly, since nothing in this process can reach into it. Asking
/// under a name no cache has seen is what can be done from this side.
///
/// The tag is the replacement's instant in microseconds since the epoch,
/// or one past the URL's last tag when the clock has not moved. A counter
/// would restart with the process and mint a name an earlier session had
/// already cached other bytes under; an instant cannot, short of a clock
/// set backwards, and there what [storage] holds is the least it mints.
///
/// A cover is an entity's ([coverKeyOf]): one entry, and one tag, for
/// every role it holds.
///
/// The memory is bounded without ever forgetting a replacement. Past
/// [maxEntries] the older half goes at once and the newest tag among it
/// stays behind as a floor: every cover with no entry of its own is
/// asked under the floor. A floor is no lower than any tag it stands in
/// for, and nothing was cached under it before it was set, so a dropped
/// cover cannot draw its old bytes. The price is every cover fetched
/// once more each time the floor moves, which the half keeps to once
/// per half-cap of replacements.
///
/// The same floor is how covers are asked afresh when they changed and
/// nothing says which ([raiseFloor]), at the same price. A raise that is
/// promised before it can be made ([owe]) is stored as soon as it is
/// promised, and a memory that starts over one makes it then.
///
/// A browser's cache outlives the page, so the web build hands in
/// [storage] and the tags and the floor outlive it too: across a reload,
/// and across a sign-out (as the floor alone, see [fold]), for
/// [kArtworkCacheLifetime] each. Native hands in nothing and keeps both
/// for the session: its cache is the store's own, emptied of a cover
/// when it is replaced.
class ReplacedCovers {
  ReplacedCovers({this._storage, DateTime Function()? now})
    : _now = now ?? DateTime.now {
    try {
      _takeUp();
    } catch (_) {
      // A private window: nothing is remembered, and nothing will be.
    }
    // A session ended owing every cover a fresh ask.
    if (_heldOwed != null) raiseFloor();
  }

  /// Where the memory is kept, as one JSON object: `tags`, tag by cover
  /// ([coverKeyOf]), `floor` once there is one, and `owed`, the instant
  /// a raise was promised, while one is. Tags stored by a role's own URL
  /// are read as their entity's.
  static const String storageKey = 'waxdeck.artwork.replaced';

  /// How many replaced covers keep a tag of their own. A scan can name
  /// every cover in a library, so this is a ceiling, not a working set.
  static const int maxEntries = 4096;

  /// The least time between two writes. A replacement after a quiet
  /// spell is written as soon as the batch it came in has ended; a scan's
  /// worth of them is one write an interval.
  static const Duration writeEvery = Duration(seconds: 2);

  final BrowserStorage? _storage;
  final DateTime Function() _now;

  /// Tag by cover, oldest replacement first.
  final Map<String, int> _tags = <String, int>{};

  /// The newest tag ever dropped from [_tags]. It only rises.
  int? _floor;

  /// When this promised a raise it has not made.
  int? _owed;

  /// The promise storage holds, this one's or another tab's.
  int? _heldOwed;

  /// What storage held when this last read or wrote it. A write that
  /// finds something else there is another tab's.
  String? _seen;

  bool _unsaved = false;

  /// Running while a write is owed or the last one is recent.
  Timer? _timer;

  /// The tag [artUrl] is asked under, or null when it is asked for as
  /// it stands: its own while that is the newer, else the floor's. A
  /// floor another tab stored can be past a tag held here, and then
  /// stands for a replacement this one never saw.
  int? tagFor(String artUrl) {
    final own = _tags[coverKeyOf(artUrl)];
    final floor = _floor;
    if (own == null || floor == null) return own ?? floor;
    return own > floor ? own : floor;
  }

  /// Records that the bytes behind [artUrl] changed, and so every
  /// picture of its entity. A URL that names its bytes itself (its own
  /// `v`) is asked under no tag and needs none.
  void note(String artUrl) {
    if (Uri.tryParse(artUrl)?.queryParameters.containsKey('v') ?? false) {
      return;
    }
    final key = coverKeyOf(artUrl);
    final now = _now().microsecondsSinceEpoch;
    final last = tagFor(key);
    _tags.remove(key);
    _tags[key] = last != null && last >= now ? last + 1 : now;
    _trim();
    _wantsSave();
  }

  void _wantsSave() {
    if (_storage == null) return;
    _unsaved = true;
    _timer ??= Timer(Duration.zero, _tick);
  }

  /// Promises a [raiseFloor] this cannot make yet, and stores the
  /// promise at once: the session that made it may not live to keep it.
  /// Once per promise, however often it is called.
  void owe() {
    if (_owed != null) return;
    _owed = _now().microsecondsSinceEpoch;
    if (_storage != null) _save();
  }

  /// Records that covers changed and nothing says which: the floor is
  /// raised past every tag held, to this instant where the clock has
  /// passed them, so every cover is asked under a name no cache has
  /// seen. The entries go, the floor now standing for each. A raise that
  /// was promised is kept by this one, and stored as kept at once.
  void raiseFloor() {
    try {
      _takeUp();
    } catch (_) {
      // Storage that cannot be read is not written below either.
    }
    final now = _now().microsecondsSinceEpoch;
    var newest = _floor ?? 0;
    for (final tag in _tags.values) {
      if (tag > newest) newest = tag;
    }
    _tags.clear();
    _floor = newest >= now ? newest + 1 : now;
    if (_owed == null && _heldOwed == null) return _wantsSave();
    _owed = null;
    _heldOwed = null;
    if (_storage != null) _save();
  }

  /// Writes what is still waiting. For an end that is announced; a
  /// reload is not, and loses at most [writeEvery] of replacements.
  void close() {
    _timer?.cancel();
    _timer = null;
    if (_unsaved) _save();
  }

  /// Folds every entry into the floor and writes that at once, so
  /// storage names no cover: after a sign-out the next user of the
  /// browser has no business reading which ones the last one changed.
  /// Nothing is forgotten by it, the floor being no lower than any tag
  /// that went; every cover is fetched once more, as when it moves.
  void fold() {
    try {
      _takeUp();
    } catch (_) {
      // Storage that cannot be read is not written below either.
    }
    // A promised raise is kept here: it names no cover either.
    if (_owed != null || _heldOwed != null) return raiseFloor();
    if (_tags.isEmpty) return;
    var floor = _floor ?? 0;
    for (final tag in _tags.values) {
      if (tag > floor) floor = tag;
    }
    _tags.clear();
    _floor = floor;
    if (_storage != null) _save();
  }

  void _tick() {
    _timer = null;
    if (!_unsaved) return;
    _save();
    _timer = Timer(writeEvery, _tick);
  }

  /// Past the cap, leaves the newer half and raises the floor to the
  /// newest tag that went.
  void _trim() {
    if (_tags.length <= maxEntries) return;
    final going = _tags.keys.take(_tags.length - maxEntries ~/ 2).toList();
    var floor = _floor ?? 0;
    for (final key in going) {
      final tag = _tags.remove(key)!;
      if (tag > floor) floor = tag;
    }
    _floor = floor;
  }

  void _save() {
    _unsaved = false;
    try {
      _takeUp();
      final raw = jsonEncode(<String, Object>{
        'floor': ?_floor,
        // Another tab's promise is not this one's to drop.
        'owed': ?(_owed ?? _heldOwed),
        'tags': _tags,
      });
      _storage?.setItem(storageKey, raw);
      _seen = raw;
    } catch (_) {
      // A private window, a full quota: the tags hold for the session.
    }
  }

  /// Takes up what storage holds that this has not seen: its own last
  /// session's memory at the start, another tab's after that.
  void _takeUp() {
    final held = _storage?.getItem(storageKey);
    if (held == _seen) return;
    _seen = held;
    final (:floor, :owed, :tags) = _decode(held);
    _heldOwed = owed;
    if (floor != null && floor > (_floor ?? 0)) _floor = floor;
    var grew = false;
    tags.forEach((String artUrl, int tag) {
      final key = coverKeyOf(artUrl);
      if ((_tags[key] ?? 0) >= tag) return;
      _tags[key] = tag;
      grew = true;
    });
    if (!grew) return;
    // Stable, so covers replaced in one tick keep the order they came in.
    final byAge = _tags.entries.toList();
    mergeSort(byAge, compare: (a, b) => a.value.compareTo(b.value));
    _tags
      ..clear()
      ..addEntries(byAge);
    _trim();
  }

  /// What is stored and still worth asking under. Anything else in the
  /// key - a hand edit, another app on the origin - reads as nothing
  /// stored.
  ({int? floor, int? owed, Map<String, int> tags}) _decode(String? raw) {
    const nothing = (floor: null, owed: null, tags: <String, int>{});
    if (raw == null) return nothing;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return nothing;
    }
    if (decoded is! Map<String, dynamic>) return nothing;
    final now = _now().microsecondsSinceEpoch;
    final life = kArtworkCacheLifetime.inMicroseconds;
    // Past its lifetime a tag has done its work. One further ahead than
    // a lifetime was minted by no sane clock: believed, it would never
    // expire and every tag after it would count up from it.
    bool live(Object? tag) =>
        tag is int && tag > now - life && tag <= now + life;
    final floor = decoded['floor'];
    final owed = decoded['owed'];
    final tags = decoded['tags'];
    return (
      // Whatever it stood for was replaced no later than it was.
      floor: live(floor) ? floor as int : null,
      // Past a lifetime no cache answers with what it was promised for.
      owed: live(owed) ? owed as int : null,
      tags: <String, int>{
        if (tags is Map<String, dynamic>)
          for (final MapEntry(:key, :value) in tags.entries)
            if (live(value)) key: value as int,
      },
    );
  }
}
