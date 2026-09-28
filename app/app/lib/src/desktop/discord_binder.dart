import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/now_playing_controller.dart';
import '../providers.dart';
import '../radio/radio_controller.dart';
import '../settings/client_prefs.dart';
import 'discord_ipc_io.dart'
    if (dart.library.js_interop) 'discord_ipc_stub.dart';
import 'discord_cover.dart';
import 'discord_presence.dart';

final discordPresencePortProvider = Provider<DiscordPresencePort>(
  (ref) => createDiscordPresencePort(),
);

/// Publishes what this desktop is playing as a Discord status.
///
/// Two rules shape all of it. Discord drops updates past about one every
/// fifteen seconds, so this coalesces rather than firing per change and
/// always sends the newest state rather than the oldest queued one. And
/// the position is deliberately not watched: Discord draws its own
/// progress bar from a start and an end timestamp, so a seek is worth
/// republishing and a tick is not.
class DiscordPresenceBinder {
  DiscordPresenceBinder(
    this._port, {
    Duration? interval,
    Duration? coverWait,
    this._covers,
  }) : _interval = interval ?? kDiscordUpdateInterval,
       _coverWait = coverWait ?? const Duration(seconds: 3) {
    _port.onImageRefused = _imageRefused;
  }

  DiscordCoverResolver? _covers;

  /// Covers switched on or off in place: the status is redrawn, the
  /// connection kept.
  set covers(DiscordCoverResolver? value) {
    if (identical(value, _covers)) return;
    _covers = value;
    final current = _wanted;
    if (current != null) show(current.withCover(null), albumPid: _album);
  }

  /// How long a new album's first send waits for its cover, rather than
  /// spending the rate-limited update on the logo and the next on it.
  final Duration _coverWait;

  /// The album whose cover a send waits on, and when it goes anyway.
  ({String album, DateTime due})? _coverWaited;

  final DiscordPresencePort _port;

  /// Injectable the way the queue persister's debounce is, so the
  /// coalescing can be tested without waiting fifteen real seconds.
  final Duration _interval;

  String? _applicationId;
  bool _connected = false;

  /// The newest state, and whether it is still to be sent.
  DiscordActivity? _wanted;

  /// The album behind [_wanted], whose cover may still be on its way.
  String? _album;
  bool _pending = false;
  DateTime? _sentAt;
  Timer? _flush;
  bool _closed = false;

  /// Which configure is current. Two can be in flight - the switch
  /// tapped off right after on - and without this the first resumes
  /// after the second and reconnects what was just turned off.
  int _generation = 0;

  /// Turns presence on for [applicationId], or off when it is null.
  ///
  /// Reconnects when the id changes, because the id is the identity
  /// Discord shows: publishing the same activity under the old one after
  /// it was changed would be the setting appearing not to work.
  Future<void> configure(String? applicationId) async {
    if (applicationId == _applicationId) return;
    _applicationId = applicationId;
    final generation = ++_generation;
    await _port.close();
    if (generation != _generation) return;
    _connected = false;
    // What is playing is kept, so switching back on shows it.
    if (applicationId == null || applicationId.isEmpty) {
      _pending = false;
      return;
    }
    final connected = await _port.connect(applicationId);
    // Superseded mid-dial; close rather than leak the stale socket.
    if (generation != _generation) {
      if (connected) await _port.close();
      return;
    }
    _connected = connected;
    if (!_connected) {
      debugPrint('no Discord client to publish presence to');
      return;
    }
    // Whatever is playing right now, rather than waiting for the next
    // track: turning the setting on mid-album should show the album.
    // Only if there is something, though - a status cleared before it
    // was ever set spends the rate-limit window on nothing.
    _wanted = _covered(_wanted);
    _pending = _wanted != null;
    _schedule();
  }

  /// The newest thing worth showing, or null for a status to clear.
  /// [albumPid] names the album whose cover it shows.
  void show(DiscordActivity? activity, {String? albumPid}) {
    if (_closed) return;
    _album = activity == null ? null : albumPid;
    final wanted = _covered(activity);
    if (_same(wanted, _wanted) && !_pending) return;
    _wanted = wanted;
    _pending = true;
    _schedule();
  }

  /// [activity] with its album's cover once known. An unknown one is
  /// looked up while there is a Discord to show it to, then shown.
  DiscordActivity? _covered(DiscordActivity? activity) {
    final album = _album;
    final covers = _covers;
    if (activity == null || album == null || covers == null) return activity;
    if (!_port.takesImageUrls) return activity.withCover(null);
    final lookup = _connected && !_closed ? covers.lookUp(album) : null;
    if (lookup != null) {
      _coverWaited = (album: album, due: DateTime.now().add(_coverWait));
      unawaited(
        lookup.then((_) {
          if (_closed || _album != album) return;
          _coverWaited = null;
          // Waited for, so sent now rather than at the end of the wait.
          _flush?.cancel();
          _flush = null;
          show(_wanted, albumPid: album);
        }),
      );
    }
    return activity.withCover(covers.coverOf(album));
  }

  /// Discord refused the image: the activity again, on this clock.
  void _imageRefused() {
    if (_closed || _wanted == null) return;
    _wanted = _wanted!.withCover(null);
    _pending = true;
    _schedule();
  }

  Future<void> dispose() async {
    _closed = true;
    _flush?.cancel();
    _flush = null;
    // Cleared before the socket goes: a Discord left showing a track
    // this app stopped playing is the failure people notice.
    if (_connected) await _port.publish(null);
    await _port.close();
  }

  /// Sends now if the last send is far enough behind, and otherwise arms
  /// one for the moment it will be.
  void _schedule() {
    if (!_connected || !_pending || _closed) return;
    final now = DateTime.now();
    final sent = _sentAt;
    var wait = sent == null ? Duration.zero : _interval - now.difference(sent);
    final waited = _coverWaited;
    final cover = waited?.album == _album ? waited?.due.difference(now) : null;
    if (cover != null && cover > wait) wait = cover;
    // Armed afresh each time: a newer album's cover moves the moment.
    _flush?.cancel();
    _flush = null;
    if (wait <= Duration.zero) {
      _send();
      return;
    }
    _flush = Timer(wait, () {
      _flush = null;
      _send();
    });
  }

  void _send() {
    if (!_connected || _closed) return;
    _pending = false;
    _sentAt = DateTime.now();
    unawaited(_port.publish(_wanted));
  }

  /// Compared on what Discord draws, so a rebuild that changed nothing
  /// visible does not spend the fifteen-second budget.
  ///
  /// The start gets slack: it is wall clock minus position, so two
  /// readings of one playback never match exactly and an exact
  /// comparison would find every state different from itself.
  bool _same(DiscordActivity? a, DiscordActivity? b) {
    if (a == null || b == null) return a == null && b == null;
    return a.title == b.title &&
        a.artist == b.artist &&
        a.album == b.album &&
        a.largeImageUrl == b.largeImageUrl &&
        _sameStart(a.start, b.start);
  }

  bool _sameStart(DateTime? a, DateTime? b) {
    if (a == null || b == null) return a == null && b == null;
    return a.difference(b).abs() < _startSlack;
  }

  /// Above the feed's granularity, below any seek this app performs.
  static const Duration _startSlack = Duration(seconds: 2);
}

/// What presence says of [now], or null for nothing. A skip still loading
/// names its track without the bar: cleared, the status would wait out
/// Discord's fifteen seconds to come back.
DiscordActivity? presenceOf(NowPlaying now, {required bool playing}) {
  final item = now.item;
  if (item == null) return null;
  final session = now.session;
  if (session == null) {
    if (!now.loading) return null;
    return DiscordActivity(
      title: item.title,
      artist: item.artist,
      album: item.album,
    );
  }
  // From where the item started in wall-clock terms, so Discord keeps
  // time itself; none while paused, or its bar would run on regardless.
  final start = playing
      ? DateTime.now().subtract(session.displayPosition)
      : null;
  final duration = session.isLoaded
      ? session.mediaDuration
      : Duration(milliseconds: item.durationMs);
  return DiscordActivity(
    title: item.title,
    artist: item.artist,
    album: item.album,
    start: start,
    end: start != null && duration > Duration.zero ? start.add(duration) : null,
  );
}

/// Album covers for presence, remembered for as long as the app runs.
final discordCoversProvider = Provider<DiscordCoverResolver>(
  (ref) => DiscordCoverResolver(
    album: (pid) => ref.read(repositoryProvider).getAlbum(pid),
    front: coverArtLookup(),
  ),
);

/// Binds Discord presence to the signed-in session on a desktop.
final discordPresenceProvider = Provider.autoDispose<DiscordPresenceBinder>((
  ref,
) {
  DiscordCoverResolver? covers() => ref.read(discordCoversEnabledProvider)
      ? ref.read(discordCoversProvider)
      : null;
  final binder = DiscordPresenceBinder(
    ref.watch(discordPresencePortProvider),
    covers: covers(),
  );

  void configure() {
    final on = ref.read(discordPresenceEnabledProvider);
    unawaited(
      binder.configure(
        on
            ? discordApplicationId(ref.read(discordApplicationIdProvider))
            : null,
      ),
    );
  }

  void publish() {
    final station = ref.read(radioPlaybackProvider).station;
    if (station != null) {
      // A station has no length and no place in one, so it gets a name
      // and the title it announced and no progress bar.
      binder.show(
        DiscordActivity(
          title: station.name,
          artist: ref.read(radioPlaybackProvider).nowPlaying,
        ),
      );
      return;
    }
    final now = ref.read(nowPlayingProvider);
    // An entry still resolving keeps what is shown until it has a name.
    if (now.loading && now.item == null) return;
    binder.show(
      presenceOf(now, playing: ref.read(audioEngineProvider).playing),
      albumPid: now.item?.albumPid,
    );
  }

  ref.listen(discordPresenceEnabledProvider, (_, _) => configure());
  ref.listen(discordApplicationIdProvider, (_, _) => configure());
  ref.listen(discordCoversEnabledProvider, (_, _) => binder.covers = covers());
  ref.listen(radioPlaybackProvider, (_, _) => publish());
  // The engine is not a provider, and pause is the other half of what
  // presence follows.
  final transport = ref
      .read(audioEngineProvider)
      .playingStream
      .listen((_) => publish());
  ref.onDispose(() => unawaited(transport.cancel()));
  ref.listen(nowPlayingProvider, (_, _) => publish());
  configure();
  publish();
  ref.onDispose(() => unawaited(binder.dispose()));
  return binder;
});
