import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// What the sleep timer is currently doing.
class SleepTimerState {
  const SleepTimerState({this.remaining, this.endOfChapterEndMs});

  /// Time left on a countdown timer; null when no countdown runs.
  final Duration? remaining;

  /// Book-timeline millisecond where end-of-chapter mode pauses; null
  /// when end-of-chapter mode is off.
  final int? endOfChapterEndMs;

  bool get active => remaining != null || endOfChapterEndMs != null;

  /// Short label for the player button badge, empty when inactive.
  String get label {
    final remaining = this.remaining;
    if (remaining != null) {
      final minutes = (remaining.inSeconds / 60).ceil();
      return '${minutes}m';
    }
    if (endOfChapterEndMs != null) return 'ch';
    return '';
  }
}

/// Wall clock behind the countdown, injectable so tests can drive it
/// in step with their fake timers.
final sleepClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// The sleep timer: counts down wall time (or watches for a chapter
/// boundary) and pauses the engine when it fires.
///
/// No fade-out: the engine port carries no volume control, so the timer
/// pauses cleanly instead of ramping.
class SleepTimerController extends Notifier<SleepTimerState> {
  Timer? _tick;
  DateTime? _deadline;

  @override
  SleepTimerState build() {
    ref.onDispose(() => _tick?.cancel());
    return const SleepTimerState();
  }

  /// Starts (or restarts) a countdown of [minutes].
  void startMinutes(int minutes) {
    _tick?.cancel();
    // The countdown is a wall-clock deadline, never a decremented
    // remainder: mobile systems throttle or freeze background timers,
    // and a stretched tick cadence must not stretch the countdown.
    // The first tick after a wake-up snaps remaining back to truth,
    // or fires immediately when the deadline passed while asleep.
    final now = ref.read(sleepClockProvider);
    _deadline = now().add(Duration(minutes: minutes));
    state = SleepTimerState(remaining: Duration(minutes: minutes));
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final deadline = _deadline;
      if (deadline == null) return;
      final remaining = deadline.difference(now());
      if (remaining <= Duration.zero) {
        _fire();
      } else {
        state = SleepTimerState(remaining: remaining);
      }
    });
  }

  /// Arms end-of-chapter mode: pause when the book position crosses
  /// [chapterEndMs]. Books only; the caller supplies the boundary.
  void startEndOfChapter(int chapterEndMs) {
    _tick?.cancel();
    _tick = null;
    _deadline = null;
    state = SleepTimerState(endOfChapterEndMs: chapterEndMs);
  }

  /// Position feed for end-of-chapter mode; the playback layer calls
  /// this with display-timeline positions.
  void onPosition(Duration position) {
    final endMs = state.endOfChapterEndMs;
    if (endMs == null) return;
    if (position.inMilliseconds >= endMs) _fire();
  }

  /// Drops end-of-chapter mode, leaving a countdown running.
  ///
  /// The boundary is a bare position on the item that armed it, so it
  /// means nothing on the next one: playback calls this when the item
  /// changes, or a chapter end of 42 minutes would pause a three minute
  /// track that never had a chapter. A countdown is wall clock and
  /// belongs to the listener, not to any item, so it stays.
  void clearEndOfChapter() {
    if (state.endOfChapterEndMs == null) return;
    state = const SleepTimerState();
  }

  void cancel() {
    _tick?.cancel();
    _tick = null;
    _deadline = null;
    state = const SleepTimerState();
  }

  void _fire() {
    cancel();
    ref.read(audioEngineProvider).pause();
  }
}

final sleepTimerProvider =
    NotifierProvider<SleepTimerController, SleepTimerState>(
      SleepTimerController.new,
    );
