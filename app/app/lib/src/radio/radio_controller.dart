import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../artwork/artwork_providers.dart';
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

  @override
  RadioPlayback build() {
    ref.onDispose(_stopTitlePoll);
    return const RadioPlayback();
  }

  Future<void> play(RadioStation station) async {
    // A paused session stops writing checkpoints, so taking the engine
    // from it cannot corrupt the item's saved position. The session
    // surface exposes a toggle, so pause only when actually playing.
    final session = ref.read(currentSessionRegistryProvider).current;
    if (session != null && ref.read(audioEngineProvider).playing) {
      await session.toggle();
    }
    _stopTitlePoll();
    state = RadioPlayback(station: station, starting: true);
    try {
      final info = await ref
          .read(repositoryProvider)
          .getRadioPlayInfo(station.pid);
      final engine = ref.read(audioEngineProvider);
      await engine.load(info.url);
      await engine.play();
      state = RadioPlayback(station: station, nowPlaying: info.nowPlaying);
      _startTitlePoll(station.pid);
    } on WaxDeckApiException {
      state = const RadioPlayback();
      rethrow;
    }
  }

  Future<void> stop() async {
    if (state.station == null) return;
    _stopTitlePoll();
    state = const RadioPlayback();
    await ref.read(audioEngineProvider).stop();
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

  /// Clears radio state without touching the engine; the player screen
  /// calls this as it hands the engine to a new item session.
  void markInterrupted() {
    if (state.station != null) {
      _stopTitlePoll();
      state = const RadioPlayback();
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
