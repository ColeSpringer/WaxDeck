import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import 'async_face.dart';

/// The one face a hub's main sliver wears: rows, an empty state, a
/// failure, or a skeleton, decided by [resolveAsyncFace].
///
/// It lives in app code rather than in `waxdeck_ui` because it takes an
/// `AsyncValue`, which is Riverpod's, and the design system depends on
/// Flutter alone. [AsyncBoxFace] is the same decision for a body that is
/// a box rather than a sliver.
class AsyncSliverFace<T> extends StatelessWidget {
  const AsyncSliverFace({
    required this.state,
    required this.builder,
    required this.errorTitle,
    required this.onRetry,
    this.skeleton = SkeletonShape.list,
    this.skeletonFills = false,
    this.isEmpty,
    this.empty,
    super.key,
  }) : assert(
         (isEmpty == null) == (empty == null),
         'an empty predicate needs an empty face, and the other way round: '
         'one without the other reads as handled and is not',
       );

  final AsyncValue<T> state;

  /// The loaded face. A sliver: this sits directly in a sliver list.
  final Widget Function(BuildContext context, T value) builder;

  /// Heading for the failure card; the sentence under it comes from
  /// [BuildContextL10n.explain].
  final String errorTitle;

  final VoidCallback onRetry;

  final SkeletonShape skeleton;

  /// Whether the skeleton fills the rest of the viewport rather than
  /// sitting at its own height.
  ///
  /// It follows what the sliver is: a screen whose whole body is this
  /// one list fills, so the wait is the page, and so does its failure
  /// card. A hub with shelves above and below it must not, or the
  /// content under it is pushed past the fold while the middle loads.
  final bool skeletonFills;

  /// Whether a loaded value is the empty case. Without it (or without
  /// [empty]) an empty value goes to [builder] like any other, which is
  /// right for a list that draws its own empty row.
  final bool Function(T value)? isEmpty;

  /// The empty face, as a sliver, handed the value it is empty for: a
  /// face that has to say why - filtered to nothing, or nothing at all -
  /// reads that off the value rather than off state it re-derives.
  final Widget Function(BuildContext context, T value)? empty;

  @override
  Widget build(BuildContext context) {
    return switch (resolveAsyncFace(state, isEmpty: isEmpty)) {
      AsyncFaceFailed(:final error, :final retrying) => SliverFillRemaining(
        hasScrollBody: false,
        child: ErrorState(
          title: errorTitle,
          message: context.explain(error),
          onRetry: onRetry,
          retrying: retrying,
        ),
      ),
      AsyncFaceEmpty(:final value) => empty!(context, value),
      AsyncFaceLoaded(:final value) => builder(context, value),
      AsyncFaceWaiting() when skeletonFills => SliverFillRemaining(
        hasScrollBody: false,
        child: SkeletonShapes(shape: skeleton),
      ),
      AsyncFaceWaiting() => SliverToBoxAdapter(
        child: SkeletonShapes(shape: skeleton),
      ),
    };
  }
}
