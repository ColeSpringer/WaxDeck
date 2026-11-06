import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import 'async_face.dart';

/// [AsyncSliverFace] for a screen whose body is a box rather than a
/// sliver, deciding by the same [resolveAsyncFace].
class AsyncBoxFace<T> extends StatelessWidget {
  const AsyncBoxFace({
    required this.state,
    required this.builder,
    required this.errorTitle,
    required this.onRetry,
    this.skeleton = SkeletonShape.list,
    this.isEmpty,
    this.empty,
    super.key,
  }) : assert(
         (isEmpty == null) == (empty == null),
         'an empty predicate needs an empty face, and the other way round: '
         'one without the other reads as handled and is not',
       );

  final AsyncValue<T> state;

  /// The loaded face, as an ordinary box widget.
  final Widget Function(BuildContext context, T value) builder;

  /// Heading for the failure card; the sentence under it comes from
  /// [BuildContextL10n.explain].
  final String errorTitle;

  /// What the failure card's Try again runs. Not offered where the thing
  /// is gone (see [AsyncFaceFailed.gone]).
  final VoidCallback onRetry;

  final SkeletonShape skeleton;

  /// Whether a loaded value is the empty case; see [AsyncSliverFace].
  final bool Function(T value)? isEmpty;

  /// The empty face, handed the value it is empty for.
  final Widget Function(BuildContext context, T value)? empty;

  @override
  Widget build(BuildContext context) {
    return switch (resolveAsyncFace(state, isEmpty: isEmpty)) {
      final AsyncFaceFailed<T> failed => AsyncFailureCard(
        failed: failed,
        title: errorTitle,
        onRetry: onRetry,
      ),
      AsyncFaceEmpty(:final value) => empty!(context, value),
      AsyncFaceLoaded(:final value) => builder(context, value),
      AsyncFaceWaiting() => SkeletonShapes(shape: skeleton),
    };
  }
}

/// The failure card both faces draw, so what it offers is decided in one
/// place: no Try again where the thing is gone (see
/// [AsyncFaceFailed.gone]), and a busy one while the read asks again.
///
/// A switch that draws its own faces takes [AsyncFailureCard.from] for its
/// failure arm, so it cannot forget either.
class AsyncFailureCard extends StatelessWidget {
  const AsyncFailureCard({
    required this.failed,
    required this.onRetry,
    this.title,
    super.key,
  }) : message = null,
       semanticsId = null,
       retrySemanticsId = null;

  /// The card for [state], a read that failed: retrying while it is
  /// loading again, which Riverpod's own retry is.
  AsyncFailureCard.from(
    AsyncValue<Object?> state, {
    required this.onRetry,
    this.title,
    this.message,
    this.semanticsId,
    this.retrySemanticsId,
    super.key,
  }) : assert(state.hasError, 'a failure card for a read that did not fail'),
       failed = AsyncFaceFailed<Object?>(
         state.error!,
         retrying: state.isLoading,
       );

  final AsyncFaceFailed<Object?> failed;

  /// The heading; the design system's own where null.
  final String? title;

  /// The sentence under the heading; the error's own explanation where
  /// null.
  final String? message;

  final VoidCallback onRetry;

  final String? semanticsId;
  final String? retrySemanticsId;

  @override
  Widget build(BuildContext context) => ErrorState(
    title: title,
    message: message ?? context.explain(failed.error),
    onRetry: failed.gone ? null : onRetry,
    retrying: failed.retrying,
    semanticsId: semanticsId,
    retrySemanticsId: retrySemanticsId,
  );
}
