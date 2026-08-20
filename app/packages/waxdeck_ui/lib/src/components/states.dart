import 'package:flutter/material.dart';

import '../icons/wax_icon.dart';
import '../l10n/wax_l10n.dart';
import '../tokens/colors.dart';
import '../tokens/motion.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'controls.dart';

/// An empty state: an invitation with exactly one next action.
///
/// "No podcasts yet. Follow a show to see new episodes here." plus a
/// button. Never a shrug, never a dead end.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    required this.message,
    this.glyph,
    this.actionLabel,
    this.onAction,
    this.semanticsId,
    this.actionSemanticsId,
    super.key,
  });

  final String title;
  final String message;
  final WaxGlyph? glyph;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? semanticsId;

  /// The handle on the invitation's own button, where a test or a spec
  /// has to press it. Separate from [semanticsId], which names the state
  /// rather than the way out of it.
  final String? actionSemanticsId;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Semantics(
      identifier: semanticsId,
      container: true,
      // Without this the button's own node folds into this one, and this
      // one wraps a Center filling the whole remaining viewport: on web a
      // tappable node draws flt-tappable with pointer-events over its
      // entire rect, so a click anywhere on an empty page fires the
      // invitation's action. WaxBanner documents the same failure.
      explicitChildNodes: true,
      // A container that stops merging its descendants keeps no text of
      // its own, so the label has to be carried across with the boundary.
      label: context.waxL10n.statesSpoken(title, message),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(WaxSpace.s32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (glyph != null) ...<Widget>[
                  WaxIcon(glyph!, size: 32, color: colors.textTertiary),
                  const SizedBox(height: WaxSpace.s16),
                ],
                // Left in the tree, unlike WaxBanner's message, which the
                // banner excludes because its label repeats it verbatim
                // on a one-line bar. Here the lines are the page's own
                // content: excluding them costs a reader the ability to
                // navigate to the text, and costs a spec the ability to
                // find it. Announced twice is the smaller price.
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: WaxType.headline.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: WaxSpace.s8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: WaxType.body.copyWith(color: colors.textSecondary),
                ),
                if (actionLabel != null) ...<Widget>[
                  const SizedBox(height: WaxSpace.s20),
                  WaxButton(
                    label: actionLabel!,
                    semanticsId: actionSemanticsId,
                    onPressed: onAction,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An error state: what happened, and what to do next.
///
/// No apologies, no "oops", and never a raw error code outside the
/// diagnostic channel.
class ErrorState extends StatelessWidget {
  const ErrorState({
    required this.message,
    this.title,
    this.onRetry,
    this.retrying = false,
    this.detail,
    this.semanticsId,
    this.retrySemanticsId,
    super.key,
  });

  /// The heading over [message]. Null takes the design system's own,
  /// which is what nearly every caller wants.
  final String? title;
  final String message;
  final VoidCallback? onRetry;

  /// Whether the retry is already running. The button stays where it is
  /// and disables, rather than going away: a control that vanishes under
  /// the finger reads as a mis-tap, and one that looks live for the
  /// length of a slow fetch reads as dead.
  final bool retrying;

  /// The technical line, for the power-user channel: set in mono, shown
  /// under the human sentence, never instead of it.
  final String? detail;

  final String? semanticsId;

  /// The retry button's own handle. Its own, not the pane's: the pane is a
  /// live region a screen reader reads, and the button is the one thing on
  /// it a spec can press.
  final String? retrySemanticsId;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.waxL10n;
    final heading = title ?? l10n.statesErrorTitle;
    return Semantics(
      identifier: semanticsId,
      container: true,
      // As on EmptyState: the pane fills the viewport, so without a
      // boundary the retry button's tap belongs to the whole page.
      explicitChildNodes: true,
      liveRegion: true,
      // Carried across with the boundary, and here it is load-bearing
      // twice over: this pane is a live region, so a container with no
      // text of its own would announce an empty string on every error.
      label: l10n.statesSpoken(heading, message),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(WaxSpace.s32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                WaxIcon(WaxIcons.errorCircle, size: 28, color: colors.error),
                const SizedBox(height: WaxSpace.s12),
                // Kept in the tree for the same reason as EmptyState's:
                // the live region above announces the failure once, and
                // these are what a reader navigates to afterwards.
                Text(
                  heading,
                  textAlign: TextAlign.center,
                  style: WaxType.headline.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: WaxSpace.s8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: WaxType.body.copyWith(color: colors.textSecondary),
                ),
                if (detail != null) ...<Widget>[
                  const SizedBox(height: WaxSpace.s12),
                  Text(
                    detail!,
                    textAlign: TextAlign.center,
                    style: WaxType.monoData.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
                if (onRetry != null) ...<Widget>[
                  const SizedBox(height: WaxSpace.s20),
                  WaxButton(
                    label: l10n.statesTryAgain,
                    kind: WaxButtonKind.tonal,
                    icon: WaxIcons.refresh,
                    onPressed: retrying ? null : onRetry,
                    semanticsId: retrySemanticsId,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The shape of the thing that is loading.
enum SkeletonShape { shelf, grid, list, detail }

/// Loading is drawn as the shape of what is coming, never as a spinner
/// in a content area: a ghost of the layout keeps the page from jumping
/// when the real thing lands.
class SkeletonShapes extends StatefulWidget {
  const SkeletonShapes({required this.shape, this.count = 6, super.key});

  final SkeletonShape shape;
  final int count;

  @override
  State<SkeletonShapes> createState() => _SkeletonShapesState();
}

class _SkeletonShapesState extends State<SkeletonShapes>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (WaxMotion.of(context).animationsEnabled) {
      _controller.repeat(reverse: true);
    } else {
      _controller.value = 0.5;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final tint = Color.lerp(
            colors.surface1,
            colors.surface3,
            _controller.value,
          )!;
          return switch (widget.shape) {
            SkeletonShape.shelf => _row(tint, 168, 168 + 40),
            SkeletonShape.grid => _grid(tint),
            SkeletonShape.list => _list(tint),
            SkeletonShape.detail => _detail(tint),
          };
        },
      ),
    );
  }

  Widget _block(Color tint, double w, double h, [BorderRadius? radius]) =>
      Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: tint,
          borderRadius: radius ?? WaxRadius.thumb,
        ),
      );

  Widget _row(Color tint, double size, double height) => SizedBox(
    height: height,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s16),
      itemCount: widget.count,
      separatorBuilder: (_, _) => const SizedBox(width: WaxSpace.s12),
      itemBuilder: (_, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _block(tint, size, size),
          const SizedBox(height: WaxSpace.s8),
          _block(tint, size * 0.7, 12, WaxRadius.chip),
        ],
      ),
    ),
  );

  Widget _grid(Color tint) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s16),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 180,
      mainAxisSpacing: WaxSpace.s12,
      crossAxisSpacing: WaxSpace.s12,
      childAspectRatio: 0.78,
    ),
    itemCount: widget.count,
    itemBuilder: (_, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: _block(tint, double.infinity, double.infinity)),
        const SizedBox(height: WaxSpace.s8),
        _block(tint, 100, 12, WaxRadius.chip),
      ],
    ),
  );

  Widget _list(Color tint) => Column(
    children: List<Widget>.generate(
      widget.count,
      (_) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WaxSpace.s16,
          vertical: WaxSpace.s8,
        ),
        child: Row(
          children: <Widget>[
            _block(tint, 40, 40),
            const SizedBox(width: WaxSpace.s12),
            Expanded(child: _block(tint, double.infinity, 14, WaxRadius.chip)),
          ],
        ),
      ),
    ),
  );

  Widget _detail(Color tint) => Padding(
    padding: const EdgeInsets.all(WaxSpace.s16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _block(tint, 160, 160, WaxRadius.hero),
        const SizedBox(width: WaxSpace.s20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _block(tint, 220, 24, WaxRadius.chip),
              const SizedBox(height: WaxSpace.s12),
              _block(tint, 160, 14, WaxRadius.chip),
              const SizedBox(height: WaxSpace.s8),
              _block(tint, 120, 14, WaxRadius.chip),
            ],
          ),
        ),
      ],
    ),
  );
}
