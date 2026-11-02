import 'dart:math' as math;

import 'package:flutter/rendering.dart'
    show OverflowBoxFit, RenderConstrainedBox;
import 'package:material_ui/material_ui.dart';

import '../icons/wax_icon.dart';
import '../l10n/wax_l10n.dart';
import '../tokens/colors.dart';
import '../tokens/motion.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'controls.dart';
import 'prose.dart';

/// An empty state: an invitation with exactly one next action.
///
/// "No podcasts yet. Follow a show to see new episodes here." plus a
/// button. Never a shrug, never a dead end. The message is optional: drop
/// it when the title or the button already says it.
///
/// Fits whatever room it is given, so it needs no wrapper: centred where
/// there is room, scrolling within a fixed box shorter than itself, its
/// own height in an unbounded column, and its true height to a filling
/// sliver, which then lengthens the page.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    this.message,
    this.glyph,
    this.actionLabel,
    this.onAction,
    this.actionBusy = false,
    this.semanticsId,
    this.actionSemanticsId,
    super.key,
  });

  final String title;
  final String? message;
  final WaxGlyph? glyph;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// The work the action started is under way: its button keeps its
  /// place and its focus and draws busy, rather than greying out.
  final bool actionBusy;

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
      label: message == null
          ? title
          : context.waxL10n.statesSpoken(title, message!),
      child: _StatePane(
        maxWidth: 360,
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
            // find it. Announced twice is the smaller price. One
            // block, so a selection runs from the title through the
            // message; the button stays outside it.
            WaxProse.block(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: WaxType.headline.copyWith(color: colors.textPrimary),
                  ),
                  if (message != null) ...<Widget>[
                    const SizedBox(height: WaxSpace.s8),
                    Text(
                      message!,
                      textAlign: TextAlign.center,
                      style: WaxType.body.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            if (actionLabel != null) ...<Widget>[
              const SizedBox(height: WaxSpace.s20),
              WaxButton(
                label: actionLabel!,
                semanticsId: actionSemanticsId,
                busy: actionBusy,
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The foot of a paged list that the person pages by hand: a Load more
/// button pointing down, and a one-row ghost under it while the next
/// page loads.
///
/// A press keeps its button in place, busy, so keyboard focus stays on
/// it; a page asked for by a scroll is the ghost alone. The press ends
/// once the page lands, so the next one may be a scroll's.
class LoadMoreFooter extends StatefulWidget {
  const LoadMoreFooter({
    required this.label,
    required this.loading,
    required this.onLoadMore,
    this.semanticsId,
    this.padding = const EdgeInsets.all(WaxSpace.s16),
    super.key,
  });

  final String label;

  /// The next page is on its way.
  final bool loading;

  final VoidCallback onLoadMore;
  final String? semanticsId;

  /// Around the button; the ghost runs the list's full width.
  final EdgeInsetsGeometry padding;

  @override
  State<LoadMoreFooter> createState() => _LoadMoreFooterState();
}

class _LoadMoreFooterState extends State<LoadMoreFooter> {
  /// Whether the page now loading was asked for here.
  var _pressed = false;

  @override
  void didUpdateWidget(LoadMoreFooter old) {
    super.didUpdateWidget(old);
    if (!widget.loading) _pressed = false;
  }

  // The list's full width in every state, so the button sits in one
  // place whether or not the ghost is under it.
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      if (!widget.loading || _pressed)
        Padding(
          padding: widget.padding,
          child: Center(
            child: WaxButton(
              label: widget.label,
              kind: WaxButtonKind.text,
              // Down, to where the rows it brings in will land.
              icon: WaxIcons.caretDown,
              semanticsId: widget.semanticsId,
              busy: widget.loading,
              onPressed: () {
                setState(() => _pressed = true);
                widget.onLoadMore();
              },
            ),
          ),
        ),
      if (widget.loading)
        const SkeletonShapes(shape: SkeletonShape.list, count: 1),
    ],
  );
}

/// An error state: what happened, and what to do next.
///
/// No apologies, no "oops", and never a raw error code outside the
/// diagnostic channel.
///
/// Fits whatever room it is given, as [EmptyState] does: no wrapper.
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
  /// and draws busy, rather than going away: it takes no press and keeps
  /// its focus, a control that vanishes under the finger reads as a
  /// mis-tap, and one that looks live for the length of a slow fetch
  /// reads as dead.
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
      child: _StatePane(
        maxWidth: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            WaxIcon(WaxIcons.errorCircle, size: 28, color: colors.error),
            const SizedBox(height: WaxSpace.s12),
            // Kept in the tree for the same reason as EmptyState's:
            // the live region above announces the failure once, and
            // these are what a reader navigates to afterwards. One
            // block with the technical line, which is the part most
            // worth pasting into a report.
            WaxProse.block(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
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
                ],
              ),
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: WaxSpace.s20),
              WaxButton(
                label: l10n.statesTryAgain,
                kind: WaxButtonKind.tonal,
                icon: WaxIcons.refresh,
                busy: retrying,
                onPressed: onRetry,
                semanticsId: retrySemanticsId,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The frame both state panes share: centred in the room it is given,
/// and scrolling within it when that room is fixed and shorter than the
/// pane (a pane beside a list). The scroll view sits inside the centring,
/// so it shrink-wraps where the pane fits and is clamped to the room where
/// it does not; a host with no height of its own gets the pane at its own
/// height, and a host that asks how tall the pane wants to be (a filling
/// sliver) is told its true height, so the page grows instead.
class _StatePane extends StatelessWidget {
  const _StatePane({required this.maxWidth, required this.child});

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      // Never the page's own controller: the pane is not the page.
      primary: false,
      child: _PaneWidth(
        maxWidth: maxWidth,
        child: Padding(
          padding: const EdgeInsets.all(WaxSpace.s32),
          child: child,
        ),
      ),
    ),
  );
}

/// Caps the pane's width, and answers a height query at that cap: a plain
/// ConstrainedBox passes the window's width down, so a filling sliver
/// measured the column one or two lines short and the pane scrolled within
/// itself instead of lengthening the page.
class _PaneWidth extends SingleChildRenderObjectWidget {
  const _PaneWidth({required this.maxWidth, required super.child});

  final double maxWidth;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPaneWidth(maxWidth);

  @override
  void updateRenderObject(BuildContext context, _RenderPaneWidth renderObject) {
    renderObject.additionalConstraints = BoxConstraints(maxWidth: maxWidth);
  }
}

class _RenderPaneWidth extends RenderConstrainedBox {
  _RenderPaneWidth(double maxWidth)
    : super(additionalConstraints: BoxConstraints(maxWidth: maxWidth));

  double _capped(double width) =>
      math.min(width, additionalConstraints.maxWidth);

  @override
  double computeMinIntrinsicHeight(double width) =>
      super.computeMinIntrinsicHeight(_capped(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      super.computeMaxIntrinsicHeight(_capped(width));
}

/// The shape of the thing that is loading.
enum SkeletonShape { shelf, grid, list, detail }

/// Loading is drawn as the shape of what is coming, never as a spinner
/// in a content area: a ghost of the layout keeps the page from jumping
/// when the real thing lands.
///
/// Fits whatever room it is given, so it needs no wrapper: laid out at
/// its own height, then cut off at the edge of a host shorter than that
/// (a dialog, a sheet, a short tab) instead of overflowing it, and its
/// own height where nothing bounds it.
class SkeletonShapes extends StatefulWidget {
  const SkeletonShapes({required this.shape, this.count = 6, super.key});

  final SkeletonShape shape;

  /// How many shelf cards, grid cells or list rows the ghost draws. The
  /// detail shape draws one, whatever this says.
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
          // Laid out at its own height whatever the host offers, then
          // fitted to it: a dialog or sheet stays near the size of what
          // is coming, and a host shorter than the ghost cuts it off at
          // the edge instead of overflowing. With no height to fit, it
          // is simply its own height.
          return ClipRect(
            child: OverflowBox(
              fit: OverflowBoxFit.deferToChild,
              alignment: AlignmentDirectional.topStart,
              minHeight: 0,
              maxHeight: double.infinity,
              child: switch (widget.shape) {
                SkeletonShape.shelf => _row(tint, 168, 168 + 40),
                SkeletonShape.grid => _grid(tint),
                SkeletonShape.list => _list(tint),
                SkeletonShape.detail => _detail(tint),
              },
            ),
          );
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
    mainAxisSize: MainAxisSize.min,
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
