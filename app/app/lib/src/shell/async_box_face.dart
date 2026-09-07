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

  final VoidCallback onRetry;

  final SkeletonShape skeleton;

  /// Whether a loaded value is the empty case; see [AsyncSliverFace].
  final bool Function(T value)? isEmpty;

  /// The empty face, handed the value it is empty for.
  final Widget Function(BuildContext context, T value)? empty;

  @override
  Widget build(BuildContext context) {
    return switch (resolveAsyncFace(state, isEmpty: isEmpty)) {
      AsyncFaceFailed(:final error, :final retrying) => ErrorState(
        title: errorTitle,
        message: context.explain(error),
        onRetry: onRetry,
        retrying: retrying,
      ),
      AsyncFaceEmpty(:final value) => empty!(context, value),
      AsyncFaceLoaded(:final value) => builder(context, value),
      AsyncFaceWaiting() => SkeletonShapes(shape: skeleton),
    };
  }
}
