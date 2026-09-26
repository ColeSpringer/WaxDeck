import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Clamps its child to a pixel budget and reports whether there was more,
/// which only layout can know for arbitrary content. The report is
/// against [budget] whether or not [clamped] is set.
class ClampedBox extends SingleChildRenderObjectWidget {
  const ClampedBox({
    required this.budget,
    required this.clamped,
    required this.onOverflow,
    required Widget super.child,
    super.key,
  });

  final double budget;
  final bool clamped;

  /// Called after the frame whenever the answer changes, so the caller
  /// can offer or withdraw a Show more.
  final ValueChanged<bool> onOverflow;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderClampedBox(budget, clamped, onOverflow);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderClampedBox)
      ..budget = budget
      ..clamped = clamped
      ..onOverflow = onOverflow;
  }
}

class _RenderClampedBox extends RenderProxyBox {
  _RenderClampedBox(this._budget, this._clamped, this.onOverflow);

  /// Landing on the budget by rounding is not more to offer, and would
  /// flip the control as the window resized.
  static const double _epsilon = 0.5;

  double _budget;
  set budget(double value) {
    if (value == _budget) return;
    _budget = value;
    markNeedsLayout();
  }

  bool _clamped;
  set clamped(bool value) {
    if (value == _clamped) return;
    _clamped = value;
    markNeedsLayout();
  }

  ValueChanged<bool> onOverflow;

  bool? _reported;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(
      BoxConstraints(
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
      ),
      parentUsesSize: true,
    );
    final natural = child.size.height;
    // One test for the clip and the report, or content a fraction over
    // is cut off with no control to open it.
    final overflows = natural - _budget > _epsilon;
    size = constraints.constrain(
      Size(child.size.width, _clamped && overflows ? _budget : natural),
    );
    if (overflows == _reported) return;
    _reported = overflows;
    // After the frame: the caller rebuilds, and a build inside layout
    // reenters it.
    WidgetsBinding.instance.addPostFrameCallback((_) => onOverflow(overflows));
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _clamp(super.computeMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _clamp(super.computeMaxIntrinsicHeight(width));

  double _clamp(double height) =>
      _clamped && height - _budget > _epsilon ? _budget : height;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    final natural = child.getDryLayout(
      BoxConstraints(
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
      ),
    );
    return constraints.constrain(Size(natural.width, _clamp(natural.height)));
  }

  /// Geometry rather than [_clamped]: under a height-bounding ancestor
  /// an unclamped box is still smaller than its child.
  bool get _clips => child != null && child!.size.height > size.height;

  final LayerHandle<ClipRectLayer> _clipLayer = LayerHandle<ClipRectLayer>();

  @override
  void dispose() {
    _clipLayer.layer = null;
    super.dispose();
  }

  /// Semantics stop where the paint does, so a screen reader does not
  /// read the clipped-away rest beside a Show more.
  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      _clips ? Offset.zero & size : null;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (!_clips) {
      _clipLayer.layer = null;
      context.paintChild(child, offset);
      return;
    }
    _clipLayer.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (context, offset) => context.paintChild(child, offset),
      oldLayer: _clipLayer.layer,
    );
  }
}
