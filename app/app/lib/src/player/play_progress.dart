import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../auth/auth_controller.dart';
import '../providers.dart';
import '../recency_map.dart';
import '../sync/streamed_play_states.dart';

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

  /// Split once: [apply] asks every live window on every report.
  late final List<String> pids = key.isEmpty
      ? const <String>[]
      : key.split(separator);

  late final Set<String> _members = pids.toSet();

  /// Where every count this window answers is kept for the rows that
  /// draw it after the window has gone.
  late AnsweredPlayCounts _answered;

  /// How many pids one read carries. The endpoint documents pages of
  /// 500; a listing page is smaller, so this only bites where something
  /// accumulated many pages before asking.
  static const batchSize = 500;

  @override
  Future<Map<String, PlayProgress>> build() async {
    // The notifier outlives its builds and `ref` is always the newest
    // one's, so a read that answers late asks about this build's own.
    final self = ref;
    final live = self.read(liveProgressWindowsProvider)..add(this);
    self.onDispose(() => live.remove(this));
    _answered = self.read(answeredPlayCountsProvider);
    final all = pids;
    if (all.isEmpty) return const <String, PlayProgress>{};
    final repository = self.watch(repositoryProvider);
    final out = <String, PlayProgress>{};
    for (var at = 0; at < all.length; at += batchSize) {
      final slice = all.sublist(at, (at + batchSize).clamp(0, all.length));
      for (final state in await repository.listPlayStates(slice)) {
        out[state.pid] = PlayProgress.of(state);
      }
    }
    // Superseded: by a reload, or by another account's session.
    if (!self.mounted) return out;
    // What the stream reported while the read was out is newer than what
    // the read brought back, and a window with no value yet had nothing
    // for [apply] to write it into; folded by the same rule.
    final streamed = self.read(streamedPlayStatesProvider);
    for (final pid in all) {
      final report = streamed[pid];
      if (report == null) continue;
      final held = out[pid];
      out[pid] = held == null
          ? PlayProgress.of(report)
          : newerProgress(held, report);
    }
    for (final pid in all) {
      _answered.record(pid, out[pid]?.playCount ?? 0);
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
    final self = ref;
    await self.read(repositoryProvider).putPlayState(pid, durationMs);
    // A window read again meanwhile holds the newer answer. For the same
    // account the stream brings this mark to it; another account's
    // window must not get it, and that account's stream never sends it.
    if (!self.mounted) return true;
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

  /// Takes [state] as the user stream reported it, without a read; a pid
  /// outside this window is ignored, and so is a report older than what
  /// the window already holds.
  void apply(PlayState state) {
    if (!_members.contains(state.pid)) return;
    final held = this.state.value?[state.pid];
    final next = held == null
        ? PlayProgress.of(state)
        : newerProgress(held, state);
    if (!identical(next, held)) _write(state.pid, next);
  }

  /// Puts [progress] into the held answer without a read.
  void _write(String pid, PlayProgress progress) {
    final current = state.value;
    if (current == null) return;
    _answered.record(pid, progress.playCount);
    state = AsyncData(<String, PlayProgress>{...current, pid: progress});
  }
}

/// The count a window last answered for each pid, which a row draws while
/// its own window is read: a window goes with the last row built from it,
/// so a row scrolled back to, or moved by a playlist edit into a window
/// nobody has read, would otherwise blank its count until the read lands.
///
/// Counts above zero only, the newest [capacity] of them.
class AnsweredPlayCounts {
  static const capacity = 2000;

  final Map<String, int> _counts = <String, int>{};

  /// Zero for a pid with no count kept.
  int operator [](String pid) => _counts[pid] ?? 0;

  void record(String pid, int count) {
    if (count > 0) {
      _counts.putNewest(pid, count, capacity: capacity);
    } else {
      _counts.remove(pid);
    }
  }
}

/// Kept for the session, and one account's counts are not another's: a
/// sign-out or another account's session starts it empty.
final answeredPlayCountsProvider = Provider<AnsweredPlayCounts>((ref) {
  ref.watch(signedInAccountProvider);
  return AnsweredPlayCounts();
});

/// The progress windows alive in a container: an echo reaches them here
/// rather than through a read, which would bring a stale one back to life
/// with a fetch nobody on screen asked for.
final liveProgressWindowsProvider = Provider<Set<PlayProgressController>>(
  (ref) => <PlayProgressController>{},
);

/// `autoDispose`, because the key is the set of rows on screen: a
/// listing that pages mints a new key per page, and a family that held
/// every one of them would keep a read alive for every page anybody has
/// ever scrolled through.
final playProgressProvider = AsyncNotifierProvider.autoDispose
    .family<PlayProgressController, Map<String, PlayProgress>, String>(
      PlayProgressController.new,
    );

/// The progress family's key for [pids]: sorted, deduplicated, and joined,
/// so the same set of rows in a different order is the same provider
/// rather than a second read of the same pids.
String playPidsKey(Iterable<String> pids) =>
    (pids.toSet().toList()..sort()).join(PlayProgressController.separator);

/// How many rows one progress read covers.
///
/// The same size the listings page at, and the two are the same
/// decision: a read keyed by the whole accumulated list would mint a new
/// provider on every page and re-read every pid before it, so the fifth
/// page of a show costs five pages of play states. Windows are stable
/// because a listing only ever appends, so a completed window is
/// answered once and a new page disturbs at most the last one. A
/// playlist edit is the exception: it moves the rows after it into new
/// windows.
const int kPlayProgressWindow = 50;

/// The keys covering [loaded], in windows.
List<String> playProgressKeys(List<ItemSummary> loaded) =>
    playProgressKeysOf(<String>[for (final item in loaded) item.pid]);

/// The same, for rows that carry a pid rather than a summary.
List<String> playProgressKeysOf(List<String> pids) => <String>[
  for (var at = 0; at < pids.length; at += kPlayProgressWindow)
    playPidsKey(
      pids.sublist(at, (at + kPlayProgressWindow).clamp(0, pids.length)),
    ),
];

/// The progress windows of a list of rows, each key made when a row of it
/// first asks and kept for the rest of the build that made this value.
///
/// A listing builds this where it builds its rows, from the list it
/// already holds, and only the windows its built rows sit in ever cost
/// anything: sorting and joining the pids of every window on every build
/// grew with the list, and a few thousand rows is a hundred of them. Each
/// key is exactly the one [playProgressKeysOf] gives, so a window is the
/// same provider whoever asks.
class PlayWindows {
  /// [length] rows, row `i` having the pid [pidAt] gives. The caller's own
  /// list is read in place; none of it is copied.
  PlayWindows(this.length, this._pidAt);

  /// The windows of a list of summaries.
  PlayWindows.ofItems(List<ItemSummary> items)
    : this(items.length, (index) => items[index].pid);

  final int length;
  final String Function(int index) _pidAt;
  final Map<int, String> _keys = <int, String>{};

  /// The windows a key was made for, in the order rows first asked, so a
  /// test can see which windows a list asked about.
  @visibleForTesting
  Iterable<int> get windowsAsked => _keys.keys;

  /// The key of the window row [index] sits in.
  String keyFor(int index) {
    assert(index >= 0 && index < length, 'row $index of $length');
    return _keys[index ~/ kPlayProgressWindow] ??= _make(
      index ~/ kPlayProgressWindow,
    );
  }

  String _make(int window) {
    final from = window * kPlayProgressWindow;
    final to = math.min(from + kPlayProgressWindow, length);
    return playPidsKey(<String>[for (var i = from; i < to; i++) _pidAt(i)]);
  }
}

/// Watches the progress of [items], one window of [kPlayProgressWindow]
/// rows at a time so a listing that pages never re-reads the pages before
/// it.
PlayProgressView watchPlayProgress(WidgetRef ref, List<ItemSummary> items) {
  final states = <String, PlayProgress>{};
  for (final key in playProgressKeys(items)) {
    states.addAll(ref.watch(playProgressProvider(key)).value ?? const {});
  }
  return PlayProgressView(states);
}

/// The caller's play counts for [items], by pid, with nothing for a pid
/// never played through.
///
/// Watches every window [items] spans, so it suits a short list built
/// whole; a list that builds its rows lazily reads through
/// [PlayCountBuilder], a window per row drawn.
Map<String, int> playCountsOf(WidgetRef ref, Iterable<ItemSummary> items) =>
    watchPlayProgress(ref, items.toList()).playCounts;

/// Builds row [index] of a lazily built list with the play count of its
/// [pid], watching only that count in the window that holds the row.
/// [windows] is the list's own, so a list reads the windows its built rows
/// sit in rather than every window it holds, and a position checkpoint,
/// which moves no count, rebuilds no row.
///
/// A row starts to watch only once it is on screen: after the frame that
/// built it, and not while its scrollable is moving faster than the screen
/// is long a second, the framework's own signal that what goes by is not
/// being read. A far jump lays out every row on the way and drops them in
/// the same pass, and a fling shows a window for a frame or two; neither
/// should read a window nobody looks at.
///
/// Until that window answers, and until the row watches, it draws what
/// [answeredPlayCountsProvider] kept for [pid].
class PlayCountBuilder extends ConsumerStatefulWidget {
  const PlayCountBuilder({
    required this.windows,
    required this.index,
    required this.pid,
    required this.builder,
    super.key,
  });

  final PlayWindows windows;
  final int index;
  final String pid;
  final Widget Function(BuildContext context, int playCount) builder;

  @override
  ConsumerState<PlayCountBuilder> createState() => _PlayCountBuilderState();
}

class _PlayCountBuilderState extends ConsumerState<PlayCountBuilder> {
  /// The row's count in its window once the row watches, null until the
  /// window answers. Listened to rather than watched, so starting it
  /// builds nothing: only a count other than the one drawn does.
  ProviderSubscription<int?>? _count;
  int? _drawn;

  /// Whether the row is in view, by its tickers: out of it the count waits,
  /// as a watch does, and catches up on the way back.
  ValueListenable<TickerModeData>? _ticking;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _checkAfterFrame();
  }

  @override
  void activate() {
    super.activate();
    // Moved in the tree, under tickers that may be another's.
    if (_ticking != null) _followTicking();
  }

  @override
  void dispose() {
    _ticking?.removeListener(_pauseOutOfView);
    super.dispose();
  }

  @override
  void didUpdateWidget(PlayCountBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Another window or another pid. The build that follows draws it.
    if (_count != null &&
        (widget.pid != oldWidget.pid ||
            widget.windows.keyFor(widget.index) !=
                oldWidget.windows.keyFor(oldWidget.index))) {
      _count!.close();
      _watch();
    }
  }

  void _checkAfterFrame() {
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      // Rows a sliver built to measure its way past are gone by now.
      if (!mounted) return;
      if (Scrollable.recommendDeferredLoadingForContext(context)) {
        _checkAfterFrame();
        binding.scheduleFrame();
        return;
      }
      _watch();
      _drawAgainIfMoved();
    });
  }

  void _watch() {
    final pid = widget.pid;
    _count = ref.listenManual(
      playProgressProvider(widget.windows.keyFor(widget.index)).select(
        (window) =>
            window.hasValue ? (window.value![pid]?.playCount ?? 0) : null,
      ),
      (_, _) => _drawAgainIfMoved(),
    );
    _paused = false;
    _followTicking();
  }

  void _followTicking() {
    final ticking = TickerMode.getValuesNotifier(context);
    if (!identical(ticking, _ticking)) {
      _ticking?.removeListener(_pauseOutOfView);
      _ticking = ticking..addListener(_pauseOutOfView);
    }
    _pauseOutOfView();
  }

  void _pauseOutOfView() {
    final count = _count;
    final pause = !(_ticking?.value.enabled ?? true);
    if (count == null || pause == _paused) return;
    _paused = pause;
    if (pause) {
      count.pause();
    } else {
      count.resume();
    }
  }

  int _counted() =>
      _count?.read() ?? ref.read(answeredPlayCountsProvider)[widget.pid];

  void _drawAgainIfMoved() {
    if (_counted() != _drawn) setState(() {});
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _drawn = _counted());
}

/// How far through each of a set of items the caller is; an item with no
/// state reads as [PlayProgress.none] rather than as missing, so call
/// sites never branch on null.
class PlayProgressView {
  const PlayProgressView(this._states);

  final Map<String, PlayProgress> _states;

  static const empty = PlayProgressView(<String, PlayProgress>{});

  PlayProgress operator [](String pid) => _states[pid] ?? PlayProgress.none;

  /// The counts above zero, by pid.
  Map<String, int> get playCounts => <String, int>{
    for (final MapEntry(:key, :value) in _states.entries)
      if (value.playCount > 0) key: value.playCount,
  };
}
