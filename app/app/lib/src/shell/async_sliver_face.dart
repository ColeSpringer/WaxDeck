import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';

/// The one face a hub's main sliver wears: rows, an empty state, a
/// failure, or a skeleton, decided in that order from an [AsyncValue].
///
/// It lives in app code rather than in `waxdeck_ui` because it takes an
/// `AsyncValue`, which is Riverpod's, and the design system depends on
/// Flutter alone.
///
/// The order is the whole point, and it is not the order a `switch` on
/// the runtime type produces. A refresh hands the screen an
/// `AsyncLoading` **carrying the previous value**, which matches
/// neither `AsyncData` nor `AsyncError`, so a type switch falls through
/// to its default arm and replaces content the screen already has with
/// a skeleton: subscribing to a show blanked the whole subscription
/// grid, every radio pin blanked the station grid. Reading `.value`
/// and `hasError` instead means a reload redraws in place and a retry
/// keeps the error card it is retrying.
///
/// Failure comes before content deliberately, matching the stats
/// screen's `_SectionFace` this follows: a list that failed to reload
/// is a list that may be wrong, and saying so is better than showing
/// stale rows with no sign anything went wrong.
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

  /// The empty face, as a sliver.
  final Widget Function(BuildContext context)? empty;

  @override
  Widget build(BuildContext context) {
    if (state case AsyncValue<T>(hasError: true, error: final Object error)) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: ErrorState(
          title: errorTitle,
          message: context.explain(error),
          onRetry: onRetry,
          // Riverpod retries on its own, so the press has to show in
          // the control rather than in a face change.
          retrying: state.isLoading,
        ),
      );
    }
    final value = state.value;
    if (value != null) {
      if (empty != null && (isEmpty?.call(value) ?? false)) {
        return empty!(context);
      }
      return builder(context, value);
    }
    if (skeletonFills) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: SkeletonShapes(shape: skeleton),
      );
    }
    return SliverToBoxAdapter(child: SkeletonShapes(shape: skeleton));
  }
}
