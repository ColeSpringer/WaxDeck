import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/now_playing_controller.dart';
import '../providers.dart';
import '../radio/radio_controller.dart';
import '../settings/client_prefs.dart';
import 'discord_ipc_io.dart'
    if (dart.library.js_interop) 'discord_ipc_stub.dart';
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
  DiscordPresenceBinder(this._port, {Duration? interval})
    : _interval = interval ?? kDiscordUpdateInterval;

  final DiscordPresencePort _port;

  /// Injectable the way the queue persister's debounce is, so the
  /// coalescing can be tested without waiting fifteen real seconds.
  final Duration _interval;

  String? _applicationId;
  bool _connected = false;

  /// The newest state, and whether it is still to be sent.
  DiscordActivity? _wanted;
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
    if (applicationId == null || applicationId.isEmpty) {
      _wanted = null;
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
    _pending = _wanted != null;
    _schedule();
  }

  /// The newest thing worth showing, or null for a status to clear.
  void show(DiscordActivity? activity) {
    if (_closed) return;
    if (_same(activity, _wanted) && !_pending) return;
    _wanted = activity;
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
    if (!_connected || !_pending || _closed || _flush != null) return;
    final sent = _sentAt;
    final since = sent == null ? _interval : DateTime.now().difference(sent);
    if (since >= _interval) {
      _send();
      return;
    }
    _flush = Timer(_interval - since, () {
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
        _sameStart(a.start, b.start);
  }

  bool _sameStart(DateTime? a, DateTime? b) {
    if (a == null || b == null) return a == null && b == null;
    return a.difference(b).abs() < _startSlack;
  }

  /// Above the feed's granularity, below any seek this app performs.
  static const Duration _startSlack = Duration(seconds: 2);
}

/// Binds Discord presence to the signed-in session on a desktop.
final discordPresenceProvider = Provider.autoDispose<DiscordPresenceBinder>((
  ref,
) {
  final binder = DiscordPresenceBinder(ref.watch(discordPresencePortProvider));

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
    final item = now.item;
    final session = now.session;
    if (item == null || session == null) {
      binder.show(null);
      return;
    }
    // The bar is drawn from where this item started in wall-clock terms,
    // which is what makes it keep time on Discord's side without this
    // republishing per second. A seek moves the derived start, which is
    // exactly when it should be republished.
    //
    // No timestamps while paused: Discord runs its bar from the start
    // regardless, so a pause for lunch reads as an hour into the song.
    final playing = ref.read(audioEngineProvider).playing;
    final position = session.displayPosition;
    final start = playing ? DateTime.now().subtract(position) : null;
    final duration = session.isLoaded
        ? session.mediaDuration
        : Duration(milliseconds: item.durationMs);
    binder.show(
      DiscordActivity(
        title: item.title,
        artist: item.artist,
        album: item.album,
        start: start,
        end: start != null && duration > Duration.zero
            ? start.add(duration)
            : null,
      ),
    );
  }

  ref.listen(discordPresenceEnabledProvider, (_, _) => configure());
  ref.listen(discordApplicationIdProvider, (_, _) => configure());
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
