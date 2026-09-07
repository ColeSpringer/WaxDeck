import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which face an [AsyncValue] wears, decided in the one order every face
/// shares: a failure, then the value held - empty or not - then the wait.
///
/// The order is the whole point, and it is not the order a `switch` on
/// the runtime type produces. A refresh hands a screen an `AsyncLoading`
/// carrying the previous value, which matches neither `AsyncData` nor
/// `AsyncError`, so a type switch falls through to its skeleton arm and
/// replaces content the screen already has: subscribing to a show
/// blanked the whole subscription grid, every radio pin blanked the
/// station grid. Reading `.value` and `hasError` instead means a reload
/// redraws in place and a retry keeps the error card it is retrying.
///
/// Failure comes before content deliberately: a list that failed to
/// reload is a list that may be wrong, and saying so is better than
/// showing stale rows with no sign anything went wrong.
sealed class AsyncFace<T> {
  const AsyncFace();
}

/// The read failed. [retrying] says Riverpod is re-asking on its own, so
/// a press has to show in the control rather than in a face change.
final class AsyncFaceFailed<T> extends AsyncFace<T> {
  const AsyncFaceFailed(this.error, {required this.retrying});

  final Object error;
  final bool retrying;
}

/// A value the caller's own predicate called empty.
final class AsyncFaceEmpty<T> extends AsyncFace<T> {
  const AsyncFaceEmpty(this.value);

  final T value;
}

/// A value to draw.
final class AsyncFaceLoaded<T> extends AsyncFace<T> {
  const AsyncFaceLoaded(this.value);

  final T value;
}

/// Nothing held yet: the first load.
final class AsyncFaceWaiting<T> extends AsyncFace<T> {
  const AsyncFaceWaiting();
}

/// Decides the face for [state]. Without [isEmpty] an empty value is a
/// value like any other, which is right for a list that draws its own
/// empty row.
AsyncFace<T> resolveAsyncFace<T>(
  AsyncValue<T> state, {
  bool Function(T value)? isEmpty,
}) {
  if (state case AsyncValue<T>(hasError: true, error: final Object error)) {
    return AsyncFaceFailed(error, retrying: state.isLoading);
  }
  final value = state.value;
  if (value != null) {
    if (isEmpty?.call(value) ?? false) return AsyncFaceEmpty(value);
    return AsyncFaceLoaded(value);
  }
  return const AsyncFaceWaiting();
}
