import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

import '../artwork/artwork_providers.dart';
import '../connect/remote_session.dart';
import '../player/now_playing_controller.dart';
import '../player/playback_session.dart';
import '../providers.dart';
import '../queue/queue_controller.dart';
import '../queue/queue_state.dart';
import '../radio/radio_controller.dart';
import 'session_artwork.dart';

/// Keeps every OS media surface saying what this device is actually
/// playing: the lock screen and Android Auto, the browser's MediaSession,
/// MPRIS, and the Windows transport controls.
///
/// One feed for all of them, because they are one seam: the handler in
/// `waxdeck_player` is what each platform's implementation reads, so a
/// surface that told a different story would be a second source of truth
/// about what is playing.
///
/// What it names follows the deck bar's own order, with two faces
/// dropped. A station outranks an item, because a station has taken the
/// engine. A **remote session names nothing**: the sound is coming out of
/// another endpoint, and a lock screen that claimed otherwise would put a
/// transport over silence and a play button that starts nothing here. The
/// deck bar is the surface for a session playing elsewhere - it can say
/// "on the kitchen speaker", which a notification cannot. Same for the
/// restore offer: a queue nobody has accepted yet is not playing.
class MediaSessionFeed {
  MediaSessionFeed({
    required this.session,
    required this.artwork,
    this.stationLogoUrl,
  });

  /// The platform's session, or the holder that absorbs the calls until
  /// there is one.
  final MediaSessionPort session;

  /// Resolves a cover to something the OS can fetch on its own.
  final Future<Uri?> Function(String? artUrl) artwork;

  /// The proxied logo URL for a station, which is the one the app may
  /// fetch: a station's own host is a stranger's, and on the desktop
  /// surfaces most of them would not answer at all.
  final String Function(String pid)? stationLogoUrl;

  /// The item last published, so a rebuild that changed nothing the OS
  /// can see does not republish. Not an optimization: MPRIS and the
  /// Windows controls emit a change signal per publish, and the
  /// now-playing controller republishes on every position tick's
  /// preload reconcile.
  ({String id, String title, String? artist, Duration? duration})? _named;

  /// The queue last published, by pid and index. A drag reorder emits a
  /// queue state per frame and each publish is a list of five hundred.
  List<String>? _queuePids;
  int? _queueIndex;

  /// Which publish is current, so a cover that resolves after the track
  /// changed is dropped rather than hung on the one playing now.
  int _generation = 0;

  bool _closed = false;

  /// Says what this device is playing now.
  ///
  /// One method rather than one per source, because what the OS shows is
  /// a decision across all of them: a station ending is a change to the
  /// radio state that has to republish the *item*, and a handover to
  /// another endpoint is a change to neither. Split into a callback each,
  /// every one of those crossings is a surface left showing what stopped.
  ///
  /// A station's announced title is its artist line rather than its name:
  /// on a lock screen the station is what you tuned to and the song is
  /// what it happens to be playing, which is the shape of an artist under
  /// a title.
  ///
  /// The queue rows carry no artwork, deliberately: a head unit draws
  /// this list as text, and resolving five hundred covers to files the OS
  /// can read would be five hundred fetches for a list nobody reads with
  /// their eyes on the road. The cover belongs to what is playing.
  void update({
    required RadioPlayback radio,
    required NowPlaying now,
    required bool remote,
    required QueueState queue,
    required ItemSummary? Function(String pid) summaryFor,
  }) {
    final station = radio.station;
    if (station != null) {
      _publish(
        id: station.pid,
        title: station.name,
        artist: radio.nowPlaying,
        live: true,
        artUrl: station.logoUrl == null
            ? null
            : stationLogoUrl?.call(station.pid),
      );
      // A station is not a queue and cannot be stepped through; leaving
      // the last queue published would offer an up-next list that
      // skipping cannot reach.
      _publishQueue(const <QueueEntry>[], 0, (_) => null);
      return;
    }
    final item = now.item;
    if (remote || item == null) {
      _clear();
      return;
    }
    _publish(
      id: item.pid,
      title: item.title,
      artist: item.artist,
      album: item.album,
      // The session's length once the media is loaded, the catalog's
      // until then: a lock screen whose scrubber is the wrong length for
      // the first seconds of every track is worse than one that fills in.
      duration: _lengthOf(now.session, item),
      artUrl: item.artUrl,
    );
    _publishQueue(queue.entries, queue.currentIndex, summaryFor);
  }

  void dispose() {
    _closed = true;
    // Not cleared on the way out: this provider is scoped to the signed-in
    // session, and a sign-out already stops playback, so the last publish
    // to make is "nothing".
    _clear();
    unawaited(forgetMediaSessionArt());
  }

  void _clear() {
    _generation++;
    if (_named == null && _queuePids == null) return;
    _named = null;
    _queuePids = null;
    _queueIndex = null;
    session
      ..publish(null)
      ..publishQueue(const <MediaSessionItem>[]);
  }

  void _publish({
    required String id,
    required String title,
    String? artist,
    String? album,
    Duration? duration,
    bool live = false,
    String? artUrl,
  }) {
    final named = (id: id, title: title, artist: artist, duration: duration);
    if (_named == named) return;
    _named = named;
    final generation = ++_generation;
    // Published without the cover first, then again with it. Fetching one
    // crosses a disk and possibly a network, and a lock screen that shows
    // no title until the artwork lands is a lock screen that is wrong for
    // as long as the fetch takes.
    final item = MediaSessionItem(
      id: id,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      live: live,
    );
    session.publish(item);
    if (artUrl == null) return;
    unawaited(
      artwork(artUrl).then((uri) {
        if (uri == null || _closed || generation != _generation) return;
        session.publish(
          MediaSessionItem(
            id: id,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            live: live,
            artUri: uri,
          ),
        );
      }),
    );
  }

  void _publishQueue(
    List<QueueEntry> entries,
    int index,
    ItemSummary? Function(String pid) summaryFor,
  ) {
    final pids = <String>[for (final entry in entries) entry.pid];
    if (_sameQueue(pids)) {
      // A track advance: same queue, highlight one row down. Resending
      // the list would rebuild five hundred rows to say one number moved.
      if (_queueIndex == index) return;
      _queueIndex = index;
      session.publishQueueIndex(index < 0 ? 0 : index);
      return;
    }
    _queuePids = pids;
    _queueIndex = index;
    session.publishQueue(<MediaSessionItem>[
      for (final entry in entries) _row(entry.pid, summaryFor(entry.pid)),
    ], index: index < 0 ? 0 : index);
  }

  /// One up-next row. A pid nothing has named yet is a row that says so:
  /// the summaries resolve as the queue plays into them, and a row
  /// dropped for want of a title would put every index behind it out by
  /// one.
  MediaSessionItem _row(String pid, ItemSummary? item) => MediaSessionItem(
    id: pid,
    title: item?.title ?? 'Queued item',
    artist: item?.artist,
    album: item?.album,
    duration: item == null || item.durationMs <= 0
        ? null
        : Duration(milliseconds: item.durationMs),
  );

  bool _sameQueue(List<String> pids) {
    // Nothing published yet is not "the same": the first queue has to go
    // out whole before an index into it means anything.
    final published = _queuePids;
    if (published == null || published.length != pids.length) return false;
    for (var i = 0; i < pids.length; i++) {
      if (published[i] != pids[i]) return false;
    }
    return true;
  }

  Duration? _lengthOf(PlaybackSession? playing, ItemSummary item) {
    if (playing != null && playing.isLoaded) return playing.mediaDuration;
    final ms = item.durationMs;
    return ms <= 0 ? null : Duration(milliseconds: ms);
  }
}

/// Binds the OS media surfaces to the session: watched by the signed-in
/// scope, so what they say stops when the account does.
final mediaSessionFeedProvider = Provider.autoDispose<MediaSessionFeed>((ref) {
  final store = ref.watch(artworkStoreProvider);
  final feed = MediaSessionFeed(
    session: ref.watch(mediaSessionProvider),
    artwork: (artUrl) => mediaSessionArtUri(store, artUrl),
    stationLogoUrl: ref.watch(repositoryProvider).radioLogoUrlFor,
  );

  void publish() => feed.update(
    radio: ref.read(radioPlaybackProvider),
    now: ref.read(nowPlayingProvider),
    remote: ref.read(remoteSessionProvider) != null,
    queue: ref.read(queueControllerProvider),
    summaryFor: ref.read(nowPlayingProvider.notifier).summaryFor,
  );

  // Every source reads all four, because what the surfaces show is a
  // decision across them. The feed's own guards are what keep that from
  // being a publish per position tick.
  ref.listen(radioPlaybackProvider, (_, _) => publish());
  ref.listen(nowPlayingProvider, (_, _) => publish());
  ref.listen(remoteSessionProvider, (_, _) => publish());
  ref.listen(queueControllerProvider, (_, _) => publish());
  // Once at the start as well: this is scoped to the session while
  // playback outlives it, so a queue already playing when the binder
  // mounts - a restored one accepted before this built - would go unnamed
  // until its next track.
  publish();
  ref.onDispose(feed.dispose);
  return feed;
});
