import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';

/// How far through an item the caller is, as rows and cards draw it.
///
/// Not episode-shaped, though episodes were its first caller: every
/// spoken-word surface asks the same question of the same endpoint. A
/// book's progress ring, an episode's resume sliver, and a continue-
/// listening shelf are one read.
class PlayProgress {
  const PlayProgress({
    required this.positionMs,
    required this.played,
    required this.finished,
    this.playCount = 0,
    this.lastPlayedAt,
    this.updatedAt,
  });

  /// One server play state as the UI reads it.
  ///
  /// The one place the two shapes are mapped. Four screens wrote this
  /// out by hand and each one silently dropped whatever field the
  /// contract had grown since it was written, which is a shelf drawing
  /// a played item as never played and no test that can see it.
  PlayProgress.of(PlayState state)
    : positionMs = state.positionMs,
      played = state.played,
      finished = state.finished,
      playCount = state.playCount,
      lastPlayedAt = state.lastPlayedAt,
      updatedAt = state.updatedAt;

  static const none = PlayProgress(
    positionMs: 0,
    played: false,
    finished: false,
  );

  final int positionMs;

  /// How many plays the server has counted for the caller. Zero on an
  /// item nobody has finished, which is what a row showing nothing
  /// beside its duration means.
  final int playCount;

  /// When the last of those plays was counted; null when there were
  /// none. A manual played mark leaves it null.
  final DateTime? lastPlayedAt;

  /// When this position was last written, by any device. What orders a
  /// continue-listening shelf: a book left off on a phone leads the
  /// shelf on the desktop. Null on a state the server has never held.
  final DateTime? updatedAt;

  /// Past the server's played threshold, which is what the unplayed dot
  /// reads. Derived server-side from position against duration, so a
  /// speed change or a silence skip cannot distort it.
  final bool played;

  final bool finished;

  /// Started and not finished: the state a resume label and a
  /// continue-listening shelf are about.
  bool get inProgress => positionMs > 0 && !finished;

  /// How far through [durationMs] this is, from 0 to 1, or null when
  /// there is no duration to be a fraction of (a feed that declared
  /// none on an episode nobody has fetched).
  double? fractionOf(int durationMs) {
    if (durationMs <= 0 || positionMs <= 0) return null;
    return (positionMs / durationMs).clamp(0.0, 1.0);
  }

  /// What is left of [durationMs], or null when there is nothing to
  /// measure against or nothing left.
  Duration? remainingOf(int durationMs) {
    if (durationMs <= 0) return null;
    final left = durationMs - positionMs;
    return left <= 0 ? null : Duration(milliseconds: left);
  }
}

/// The caller's play state for a set of items, in one batch read.
///
/// Keyed by the pid set rather than held per item: a listing draws fifty
/// rows and each of them wants a position, and fifty single reads on
/// every page is what the batch endpoint exists to avoid. An absent pid
/// is a zero state, which is what the endpoint means by omitting it.
///
/// The key is one string rather than a list, and that is load-bearing: a
/// family keys its instances by `==`, a `List` has identity equality, and
/// a screen that built its key in `build` would mint a fresh provider on
/// every frame, each one fetching and settling into a rebuild.
/// Callers go through [playPidsKey], which sorts and deduplicates so the
/// same rows in a different order are the same read.
class PlayProgressController extends AsyncNotifier<Map<String, PlayProgress>> {
  PlayProgressController(this.key);

  /// The sorted, deduplicated pids, joined. Safe as one string because a
  /// pid is a prefixed ULID: the separator cannot occur inside one.
  final String key;

  static const separator = ',';

  List<String> get pids =>
      key.isEmpty ? const <String>[] : key.split(separator);

  /// How many pids one read carries. The endpoint documents pages of
  /// 500; a listing page is smaller, so this only bites where something
  /// accumulated many pages before asking.
  static const batchSize = 500;

  @override
  Future<Map<String, PlayProgress>> build() async {
    final all = pids;
    if (all.isEmpty) return const <String, PlayProgress>{};
    final repository = ref.watch(repositoryProvider);
    final out = <String, PlayProgress>{};
    for (var at = 0; at < all.length; at += batchSize) {
      final slice = all.sublist(at, (at + batchSize).clamp(0, all.length));
      for (final state in await repository.listPlayStates(slice)) {
        out[state.pid] = PlayProgress.of(state);
      }
    }
    return out;
  }

  /// Records [pid] as played by checkpointing at its full duration.
  ///
  /// Played is server-derived from the position reached, so this is the
  /// only way to say it: there is no played flag to set. A zero duration
  /// (a feed that declared none on an unfetched episode) has no position
  /// that means finished, so those are refused rather than checkpointed
  /// at zero, which would read as "not started".
  Future<bool> markPlayed(String pid, int durationMs) async {
    if (durationMs <= 0) return false;
    await ref.read(repositoryProvider).putPlayState(pid, durationMs);
    // The count and its stamp come along because the server just
    // counted this play: a fresh progress would read as never played
    // beside a row that has just been marked heard.
    //
    // Only on the first mark, though. The server counts one play per
    // listen-through and refuses a second on an item already played, so
    // marking a finished item again writes nothing there - and adding
    // one here would leave a count the next read silently corrects. The
    // player's menu offers the mark whether or not it is needed, so this
    // is a state a listener reaches by tapping twice.
    final held = state.value?[pid];
    final counted = !(held?.played ?? false);
    _write(
      pid,
      PlayProgress(
        positionMs: durationMs,
        played: true,
        finished: true,
        playCount: (held?.playCount ?? 0) + (counted ? 1 : 0),
        lastPlayedAt: counted ? DateTime.now().toUtc() : held?.lastPlayedAt,
      ),
    );
    return true;
  }

  /// Puts [progress] into the held answer without a read.
  void _write(String pid, PlayProgress progress) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(<String, PlayProgress>{...current, pid: progress});
  }
}

/// `autoDispose`, because the key is the set of rows on screen: a
/// listing that pages mints a new key per page, and a family that held
/// every one of them would keep a read alive for every page anybody has
/// ever scrolled through.
final playProgressProvider = AsyncNotifierProvider.autoDispose
    .family<PlayProgressController, Map<String, PlayProgress>, String>(
      PlayProgressController.new,
    );

/// The progress family's key for [items]: sorted, deduplicated, and
/// joined, so the same set of rows in a different order is the same
/// provider rather than a second read of the same pids.
String playProgressKey(Iterable<ItemSummary> items) =>
    playPidsKey(<String>[for (final item in items) item.pid]);

/// The same, for a caller holding pids rather than rows.
String playPidsKey(Iterable<String> pids) =>
    (pids.toSet().toList()..sort()).join(PlayProgressController.separator);

/// How many rows one progress read covers.
///
/// The same size the listings page at, and the two are the same
/// decision: a read keyed by the whole accumulated list would mint a new
/// provider on every page and re-read every pid before it, so the fifth
/// page of a show costs five pages of play states. Windows are stable
/// because a listing only ever appends, so a completed window is
/// answered once and a new page disturbs at most the last one.
const int kPlayProgressWindow = 50;

/// The keys covering [loaded], in windows.
List<String> playProgressKeys(List<ItemSummary> loaded) => <String>[
  for (var at = 0; at < loaded.length; at += kPlayProgressWindow)
    playProgressKey(
      loaded.sublist(at, (at + kPlayProgressWindow).clamp(0, loaded.length)),
    ),
];

/// How far through each of a set of items the caller is; an item with no
/// state reads as [PlayProgress.none] rather than as missing, so call
/// sites never branch on null.
class PlayProgressView {
  const PlayProgressView(this._states);

  final Map<String, PlayProgress> _states;

  static const empty = PlayProgressView(<String, PlayProgress>{});

  PlayProgress operator [](String pid) => _states[pid] ?? PlayProgress.none;
}
