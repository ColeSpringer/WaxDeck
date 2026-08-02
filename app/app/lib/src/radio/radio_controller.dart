import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../artwork/artwork_palette.dart';
import '../artwork/artwork_providers.dart';
import '../player/autoplay_gate.dart';
import '../player/session_registry.dart';
import '../providers.dart';
import '../settings/prefs_controller.dart';

/// The shared internet radio station library.
class RadioStationsController extends AsyncNotifier<List<RadioStation>> {
  @override
  Future<List<RadioStation>> build() =>
      ref.watch(repositoryProvider).listRadioStations();

  /// Adds a station and reloads. Errors propagate so dialogs surface the
  /// server's message (duplicate stream URLs, refused private hosts).
  Future<RadioStation> add({
    required String name,
    required String streamUrl,
    String? homepageUrl,
    String? logoUrl,
  }) async {
    final created = await ref
        .read(repositoryProvider)
        .createRadioStation(
          name: name,
          streamUrl: streamUrl,
          homepageUrl: homepageUrl,
          logoUrl: logoUrl,
        );
    ref.invalidateSelf();
    await future;
    return created;
  }

  /// Replaces a station's fields and reloads.
  Future<RadioStation> edit(
    String pid, {
    required String name,
    required String streamUrl,
    String? homepageUrl,
    String? logoUrl,
  }) async {
    final repository = ref.read(repositoryProvider);
    final updated = await repository.updateRadioStation(
      pid,
      name: name,
      streamUrl: streamUrl,
      homepageUrl: homepageUrl,
      logoUrl: logoUrl,
    );
    // The proxy URL is keyed by pid, which an edit does not change. The
    // server drops its copy; this drops ours, including the note that the
    // station had no logo, or the fix draws the old picture all session.
    await ref.read(artworkStoreProvider).evict(repository.radioLogoUrlFor(pid));
    ref.read(paletteCacheProvider).forget(repository.radioLogoUrlFor(pid));
    ref.invalidateSelf();
    await future;
    return updated;
  }

  Future<void> remove(String pid) async {
    await ref.read(repositoryProvider).deleteRadioStation(pid);
    ref.invalidateSelf();
    await future;
  }
}

final radioStationsProvider =
    AsyncNotifierProvider<RadioStationsController, List<RadioStation>>(
      RadioStationsController.new,
    );

/// The stations pinned to the dial, in dial order.
///
/// Per account, in the synced preference document, and that placement is
/// the decision worth stating. The station library is shared by the whole
/// household, so 6.10 read the absence of per-user station state as
/// "favourites are a client pref" - but ADR-0027's test is whether a
/// preference describes the *machine* or the *account*, and which six of
/// the household's stations are yours plainly describes you. A collapsed
/// sidebar is a fact about a screen and a pointer; a dial is not. So the
/// prefs document grew an ordered list of station pids (ADR-0034), which
/// also means a pin made on the desktop is on the phone, and signing out
/// takes it with the account rather than leaving it on a shared machine.
///
/// The state stays synchronous, like the theme's: the dial draws what is
/// loaded and nothing while the document is still in flight.
class RadioFavorites extends Notifier<List<String>> {
  /// How many stations the dial draws. Past about a dozen a band under a
  /// needle stops being a dial and becomes a list harder to use than the
  /// grid below it. The client's cap rather than the contract's - the
  /// document allows more, so a later design is not a spec change.
  static const limit = 12;

  /// What the document may hold, from the contract's `maxItems`. Separate
  /// from [limit] on purpose: presenting the stored list through the dial's
  /// cap and writing that back deletes another client's thirteenth pin.
  static const _stored = 64;

  /// One rule about what the list may hold: no duplicates, no blanks, never
  /// past what the document allows. Everything that builds one goes through
  /// it, so another client's document obeys it too.
  static List<String> _clean(Iterable<String> pids) {
    final seen = <String>{};
    final kept = <String>[];
    for (final pid in pids) {
      if (pid.isEmpty || !seen.add(pid)) continue;
      kept.add(pid);
      if (kept.length == _stored) break;
    }
    return kept;
  }

  @override
  List<String> build() {
    // Watched, so a pin made on another device lands here: the server
    // emits a prefs event and the document is refetched. Whatever the
    // document says replaces optimistic state, which is what keeps the
    // server the authority rather than this notifier.
    final prefs = ref.watch(prefsControllerProvider).value;
    return _clean(prefs?.radioFavorites ?? const <String>[]);
  }

  bool contains(String pid) => state.contains(pid);

  /// Whether the dial has room for another pin.
  bool get full => state.length >= limit;

  /// Pins or unpins. A pin goes on the end, so the dial's order is the
  /// order stations were pinned in and does not shuffle under a thumb.
  ///
  /// Answers null when the pin landed, or the message to show when it did
  /// not: a full dial, or the server's refusal. Returned rather than thrown
  /// because the callers are a glyph and a menu item, neither a place an
  /// unhandled rejection can be seen.
  ///
  /// Optimistic, because a star that waits for a round trip reads as a
  /// dropped tap; a refused write puts the old list back.
  Future<String?> toggle(String pid) async {
    final before = state;
    final pinned = state.contains(pid);
    if (!pinned && full) {
      // Said, not swallowed: dropping the pin and writing the unchanged
      // list back is a tap that reports success and does nothing.
      return 'The dial holds $limit stations. Unpin one to make room.';
    }
    state = pinned
        ? <String>[
            for (final favorite in state)
              if (favorite != pid) favorite,
          ]
        : _clean([...state, pid]);
    try {
      await ref.read(prefsControllerProvider.notifier).setRadioFavorites(state);
      return null;
    } on WaxDeckApiException catch (e) {
      if (ref.mounted) state = before;
      return e.message;
    }
  }
}

final radioFavoritesProvider = NotifierProvider<RadioFavorites, List<String>>(
  RadioFavorites.new,
);

/// The pinned stations that still exist, in dial order.
///
/// Resolved against the library rather than trusted: a station deleted on
/// another device leaves a pid behind in this device's list, and a dial
/// slot for a station nobody can tune is worse than one fewer slot. The
/// stale pid is left in storage on purpose - nothing here writes, so a
/// list read while the library is still loading does not prune itself
/// against an empty answer.
///
/// The dial's cap applies here, not to the stored list: a document holding
/// more than this client draws keeps every entry.
final radioDialProvider = Provider<List<RadioStation>>((ref) {
  final stations = ref.watch(radioStationsProvider).value;
  if (stations == null) return const <RadioStation>[];
  final byPid = <String, RadioStation>{
    for (final station in stations) station.pid: station,
  };
  return <RadioStation>[
    for (final pid in ref.watch(radioFavoritesProvider))
      if (byPid[pid] != null) byPid[pid]!,
  ].take(RadioFavorites.limit).toList(growable: false);
});

/// What the radio player is doing right now.
class RadioPlayback {
  const RadioPlayback({this.station, this.starting = false, this.nowPlaying});

  /// The station currently loaded through the engine, if any.
  final RadioStation? station;

  /// True while play-info resolves and the stream buffers.
  final bool starting;

  /// The station's current in-stream title, when it announces one.
  final String? nowPlaying;
}

/// Drives live radio through the shared audio engine. Radio has no
/// positions, checkpoints, or listen accounting, so it deliberately
/// bypasses PlaybackSession: it pauses any active session first, then
/// owns the engine until a session (or another station) takes it back.
class RadioPlaybackController extends Notifier<RadioPlayback> {
  Timer? _titlePoll;
  Timer? _firstTitleTick;

  /// Which tune owns the engine.
  ///
  /// Bumped by everything that takes it - another station, a stop, an item
  /// session - so the awaits inside a slow [play] can tell whether they are
  /// still the current one. A tune crosses a round trip and an engine load,
  /// and without this a station whose play-info crawled would open its
  /// stream over whatever replaced it in the meantime and then publish
  /// itself as what is on.
  int _tuning = 0;

  @override
  RadioPlayback build() {
    ref.onDispose(_stopTitlePoll);
    return const RadioPlayback();
  }

  Future<void> play(RadioStation station) async {
    // Claimed and published before anything here can suspend, which is
    // the whole point of the counter: a generation taken after an await
    // is handed out in completion order rather than in tap order, so the
    // tap that came first can wake last, outrank the station the listener
    // actually asked for, and win. The same window hid the tune from
    // [stop] and [interrupt], which used to look for a station this
    // had not published yet.
    final tuning = ++_tuning;
    _stopTitlePoll();
    final engine = ref.read(audioEngineProvider);
    // Whether a station holds the engine right now, asked before the state
    // is replaced with the one being tuned.
    final wasTuned = state.station != null;
    state = RadioPlayback(station: station, starting: true);
    try {
      // A paused session stops writing checkpoints, so taking the engine
      // from it cannot corrupt the item's saved position. Paused rather
      // than toggled: for a session that is playing these are the same
      // call, and a pause is the verb this actually wants, since the
      // other half of a toggle starts playback. just_audio drops its
      // playing flag before it asks the platform, so a second tune reads
      // the engine as stopped and never reaches here - but that is the
      // engine's timing rather than this controller's promise, and an
      // idempotent pause does not rest on it.
      final session = ref.read(currentSessionRegistryProvider).current;
      if (session != null && engine.playing) await engine.pause();
      if (tuning != _tuning) return;
      // The station being left goes quiet as the dial turns rather than
      // when the new stream opens: a stream that is down never gets that
      // far, and leaving the old one running is how the bar came to name
      // one station while another played.
      if (wasTuned) await engine.stop();
      if (tuning != _tuning) return;
      final info = await ref
          .read(repositoryProvider)
          .getRadioPlayInfo(station.pid);
      if (tuning != _tuning) return;
      await engine.load(info.url);
      if (tuning != _tuning) return;
      // Engine speed is player-level state and outlives sources, and
      // radio bypasses the session layer that manages it: without this a
      // station tuned after a 1.5x podcast broadcasts at 1.5x. A live
      // stream has no rate of its own, so the dial always means 1x.
      await engine.setSpeed(1.0);
      if (tuning != _tuning) return;
      await engine.play();
      if (tuning != _tuning) return;
      state = RadioPlayback(station: station, nowPlaying: info.nowPlaying);
      _startTitlePoll(station.pid);
    } on Object {
      // A tune that was overtaken is nobody's failure to hear about: it
      // owns neither the state nor the engine any more, and the station
      // that replaced it reports its own outcome. Raised, this one puts
      // "could not tune" on screen underneath a station tuning fine.
      if (tuning != _tuning) return;
      // Every failure, not only the server's: a stream that will not open
      // throws from the engine, and a catch that knew about API errors
      // alone left the state standing at a station making no sound.
      state = const RadioPlayback();
      rethrow;
    }
  }

  Future<void> stop() async {
    // Unconditional, and before the state check: a tune still in flight is
    // one of the things a stop stops, and reading `state.station` for that
    // answer misses the one already past its first await with a station on
    // the bar. Without the bump its remaining awaits would open the stream
    // this just silenced and put the station back.
    _tuning++;
    _stopTitlePoll();
    // Nothing tuned means nothing of the engine's to release: whatever is
    // holding it is an item session, and stopping that here would take the
    // media out from under the screen playing it.
    if (state.station == null) return;
    state = const RadioPlayback();
    await ref.read(audioEngineProvider).stop();
  }

  /// What the one transport control means, wherever it is drawn.
  ///
  /// Stop while sound is coming out, and start again otherwise. The
  /// second half is the part worth spelling out: a live stream ends on
  /// its own - a host that went away, a network that dropped, a
  /// playlist that ran out - and the engine simply stops. Both surfaces
  /// read that as "not playing", drew a play glyph, and called [stop] on
  /// it, so the one control on a dead station said play and tore the
  /// station down.
  ///
  /// Told apart by why it is not playing: a refused start still has the
  /// media loaded and wants the gesture the browser was waiting for,
  /// and anything else is a stream that has to be opened again.
  Future<void> toggle() async {
    final station = state.station;
    if (station == null) return;
    if (ref.read(audioEngineProvider).playing || state.starting) {
      await stop();
      return;
    }
    if (ref.read(autoplayBlockedProvider)) {
      await resume();
      return;
    }
    try {
      await play(station);
    } on Object {
      // A re-tune that fails leaves no station on the bar, which is the
      // truthful answer and the only one these two surfaces can give:
      // neither has anywhere to put a message. The hub is where a tune
      // reports why it did not work.
    }
  }

  /// Starts the loaded station's stream again after the platform turned
  /// a programmatic start down.
  ///
  /// The station is still tuned and its media still loaded: only the
  /// start was refused, so this is a play and not a re-tune, and the tap
  /// that reaches it is the gesture the browser was waiting for.
  Future<void> resume() async {
    if (state.station == null) return;
    await ref.read(audioEngineProvider).play();
  }

  /// Clears radio state as an item start takes the engine, and stops the
  /// engine when a station's sound was the engine's; the playback
  /// controller awaits this before it resolves the item.
  ///
  /// The generation goes up for the same reason [stop] raises it, and just
  /// as unconditionally: the item session owns the engine from here, and a
  /// tune still resolving would otherwise load its stream over the item
  /// that just started. Guarding the bump on a published station missed
  /// exactly the tune that had not published one yet, which is the window
  /// this is called in - the controller reaches here while loading an
  /// item, which is what a tune's own first await is waiting on.
  ///
  /// The stop is conditional on a published station - established or
  /// still tuning, either way the engine's sound is radio's, and an item
  /// start runs several round trips before its own load replaces the
  /// source, so a stream left running is audible under the item face for
  /// that whole window. No station published means the engine holds the
  /// outgoing item, and stopping that would break the seamless replace an
  /// item-to-item start does.
  ///
  /// A stop the platform refuses puts the station back before the
  /// rethrow: the stream is still audible, and a cleared state would
  /// leave it with no surface that names it and no control that can
  /// silence it. The restore re-fires the hand-over listener above
  /// playback, which supersedes the interrupted start - so the item
  /// never shows an error for a station that simply would not let go -
  /// and the rethrow is what stops that start from loading over the
  /// stream. Restored as established rather than mid-tune: an
  /// interrupted tune's awaits are dead (the generation moved), so a
  /// "starting" state would spin forever, while an established one is a
  /// working stop button.
  Future<void> interrupt() async {
    _tuning++;
    _stopTitlePoll();
    final held = state;
    final station = held.station;
    if (station == null) return;
    state = const RadioPlayback();
    try {
      await ref.read(audioEngineProvider).stop();
    } on Object {
      state = RadioPlayback(station: station, nowPlaying: held.nowPlaying);
      _startTitlePoll(station.pid);
      rethrow;
    }
  }

  /// The in-stream title lives in play-info and only exists while the
  /// proxy sees the stream, so it is polled during playback. The poll
  /// reads metadata only; the open stream is never re-tuned.
  void _startTitlePoll(String pid) {
    _titlePoll = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshTitle(pid),
    );
    // The first metadata block lands moments after the stream opens;
    // one early refresh beats waiting out a full period. (The station
    // guard in _refreshTitle already makes a stale firing a no-op;
    // tracking the handle just cancels it cleanly.)
    _firstTitleTick = Timer(
      const Duration(seconds: 4),
      () => _refreshTitle(pid),
    );
  }

  void _stopTitlePoll() {
    _titlePoll?.cancel();
    _titlePoll = null;
    _firstTitleTick?.cancel();
    _firstTitleTick = null;
  }

  Future<void> _refreshTitle(String pid) async {
    if (state.station?.pid != pid) return;
    try {
      final info = await ref.read(repositoryProvider).getRadioPlayInfo(pid);
      if (state.station?.pid != pid) return;
      // Only when it moved. This asks every fifteen seconds and a station
      // announces every few minutes, and [RadioPlayback] has no value
      // equality, so an identical assignment rebuilds the dial band, every
      // visible tile, and the deck bar for the same words.
      if (info.nowPlaying == state.nowPlaying) return;
      state = RadioPlayback(
        station: state.station,
        nowPlaying: info.nowPlaying,
      );
    } on WaxDeckApiException {
      // Metadata is decoration; playback carries on without it.
    }
  }
}

final radioPlaybackProvider =
    NotifierProvider<RadioPlaybackController, RadioPlayback>(
      RadioPlaybackController.new,
    );
