import 'package:waxdeck_api/waxdeck_api.dart';

/// Album covers for presence, from the Cover Art Archive: an album's
/// release id, then the archive's front image for it. A cover found is
/// remembered, a miss for a day, and a release id across retries.
class DiscordCoverResolver {
  DiscordCoverResolver({
    required this.album,
    required this.front,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Future<AlbumDetail> Function(String pid) album;

  /// The release's front image as a URL Discord can fetch, null for none;
  /// throws when the archive could not answer.
  final Future<String?> Function(String mbid) front;

  final DateTime Function() _clock;

  /// In insertion order, which is the eviction order; a miss with when.
  final _covers = <String, ({String? url, DateTime at})>{};
  final _mbids = <String, String>{};
  final _inFlight = <String>{};
  final _retryAt = <String, DateTime>{};

  static const _remembered = 256;

  /// A failure that may clear (the server or the archive unreachable) is
  /// asked again after this, rather than remembered as a miss.
  static const _retryAfter = Duration(minutes: 5);

  /// A miss is asked again after this: a pass may identify the album, or
  /// the archive gain its cover, the way the server's own client forgets.
  static const _missFor = Duration(days: 1);

  /// The cover found for [albumPid], or null for none or not yet known.
  String? coverOf(String albumPid) => _covers[albumPid]?.url;

  /// Looks [albumPid] up, or answers null when it is known, in flight, or
  /// failed too recently to ask again.
  Future<void>? lookUp(String albumPid) {
    final known = _covers[albumPid];
    if (known != null &&
        known.url == null &&
        !_clock().isBefore(known.at.add(_missFor))) {
      _covers.remove(albumPid);
    }
    if (_covers.containsKey(albumPid) || _inFlight.contains(albumPid)) {
      return null;
    }
    final retry = _retryAt[albumPid];
    if (retry != null && _clock().isBefore(retry)) return null;
    _inFlight.add(albumPid);
    return _settle(albumPid);
  }

  Future<void> _settle(String albumPid) async {
    try {
      final cover = await _find(albumPid);
      _retryAt.remove(albumPid);
      _covers[albumPid] = (url: cover, at: _clock());
      if (_covers.length > _remembered) {
        _mbids.remove(_covers.keys.first);
        _covers.remove(_covers.keys.first);
      }
    } on Object {
      // An Error too: a cover is decoration, and a malformed answer
      // should cost the cover for a while, not the presence update.
      _remember(_retryAt, albumPid, _clock().add(_retryAfter));
    } finally {
      _inFlight.remove(albumPid);
    }
  }

  /// The album's release id is read once; a retry after the archive
  /// failed asks the archive alone.
  Future<String?> _find(String albumPid) async {
    var mbid = _mbids[albumPid];
    if (mbid == null) {
      final AlbumDetail detail;
      try {
        detail = await album(albumPid);
      } on WaxDeckApiException catch (e) {
        if (e.code == 'not-found') return null;
        rethrow;
      }
      mbid = detail.mbid;
      if (mbid == null || mbid.isEmpty) return null;
      _remember(_mbids, albumPid, mbid);
    }
    return front(mbid);
  }

  /// Sets [key] as the newest entry, dropping the oldest past what is
  /// remembered: a lookup that keeps failing never reaches [_covers].
  static void _remember<V>(Map<String, V> map, String key, V value) {
    map
      ..remove(key)
      ..[key] = value;
    if (map.length > _remembered) map.remove(map.keys.first);
  }
}
