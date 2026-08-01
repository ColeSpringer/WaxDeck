import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'output_volume.dart';

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
/// The countdown fades out; end-of-chapter mode does not, deliberately.
/// [onPosition] fires once the position has *crossed* the boundary, so a
/// ramp there would fade the next chapter, and pre-arming one would fade
/// the end of the chapter the listener stayed awake for.
class SleepTimerController extends Notifier<SleepTimerState> {
  Timer? _tick;
  DateTime? _deadline;

  /// Bumped by anything that disarms or re-arms the timer, so a fade in
  /// flight can tell it should no longer pause.
  var _generation = 0;

  /// Long enough to read as a fade, short enough that a listener still
  /// awake can cancel in time. Fixed on purpose: a fade length is not a
  /// decision worth a setting.
  static const fadeDuration = Duration(seconds: 10);

  static const fadeStep = Duration(milliseconds: 250);

  @override
  SleepTimerState build() {
    ref.onDispose(() {
      _tick?.cancel();
      _generation++;
    });
    return const SleepTimerState();
  }

  /// Starts (or restarts) a countdown of [minutes].
  void startMinutes(int minutes) {
    _tick?.cancel();
    _generation++;
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
        unawaited(_fadeAndFire());
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
    _generation++;
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
    _generation++;
    state = const SleepTimerState();
  }

  void _fire() {
    cancel();
    ref.read(audioEngineProvider).pause();
  }

  /// Ramps the output down, pauses, and puts the level back.
  ///
  /// Through [outputVolumeProvider], so the slider follows the fade. The
  /// timer stays active until the pause lands.
  ///
  /// However it ends, the level goes back if the ramp still owns it: a
  /// cancel or re-arm part way down is a listener who is awake, and a
  /// refused write leaves the ramp's own attenuation behind. Only a
  /// level somebody else moved is left alone.
  Future<void> _fadeAndFire() async {
    _tick?.cancel();
    _tick = null;
    _deadline = null;
    final generation = _generation;

    final volume = ref.read(outputVolumeProvider.notifier);
    final before = ref.read(outputVolumeProvider);
    var lastGood = before;
    // Undoes the ramp when it still owns the level, which a drag or a
    // refused write means it does not.
    Future<void> unwind() async {
      if (before > 0 && _sameLevel(ref.read(outputVolumeProvider), lastGood)) {
        await volume.set(before);
      }
    }

    if (before > 0) {
      final steps = fadeDuration.inMilliseconds ~/ fadeStep.inMilliseconds;
      for (var i = 1; i <= steps; i++) {
        await Future<void>.delayed(fadeStep);
        if (!ref.mounted) return;
        if (generation != _generation) return unwind();
        // Before writing, not only after: a drag lands between steps,
        // and the next write would paper over it.
        if (!_sameLevel(ref.read(outputVolumeProvider), lastGood)) break;
        final target = before * (1 - i / steps);
        await volume.set(target);
        if (!ref.mounted) return;
        if (generation != _generation) return unwind();
        final level = ref.read(outputVolumeProvider);
        if (_sameLevel(level, target)) {
          lastGood = target;
          continue;
        }
        // Either the platform refused (the state went back to the
        // engine's level, still the last good write) or somebody moved
        // it. unwind tells them apart by ownership.
        break;
      }
    }
    if (!ref.mounted) return;
    if (generation != _generation) return unwind();

    // The timer fired, so it pauses however the ramp ended.
    ref.read(audioEngineProvider).pause();
    // Or the next play starts silent. A refusal part way down leaves the
    // level lowered and still owned, so it unwinds like any other end.
    await unwind();
    if (!ref.mounted || generation != _generation) return;
    state = const SleepTimerState();
  }

  /// A tolerance, since the ramp's targets are floating point.
  static bool _sameLevel(double a, double b) => (a - b).abs() < 1e-6;
}

final sleepTimerProvider =
    NotifierProvider<SleepTimerController, SleepTimerState>(
      SleepTimerController.new,
    );
