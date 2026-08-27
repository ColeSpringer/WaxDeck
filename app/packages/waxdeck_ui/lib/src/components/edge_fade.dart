import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Fades a horizontal edge where content continues past it (dstIn).
/// Its own render object, not a conditional ShaderMask: swapping the
/// mask in and out re-inflates the child, dropping scroll state.
class EdgeFade extends SingleChildRenderObjectWidget {
  const EdgeFade({
    required Widget child,
    this.start = 0,
    this.end = 0,
    super.key,
  }) : super(child: child);

  /// Fade width at the reading-direction start edge.
  final double start;

  /// Fade width at the reading-direction end edge.
  final double end;

  (double, double) _sides(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final left = math.max(0.0, rtl ? end : start);
    final right = math.max(0.0, rtl ? start : end);
    return (left, right);
  }

  @override
  RenderObject createRenderObject(BuildContext context) {
    final (left, right) = _sides(context);
    return _RenderEdgeFade(left, right);
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final (left, right) = _sides(context);
    (renderObject as _RenderEdgeFade)
      ..left = left
      ..right = right;
  }
}

class _RenderEdgeFade extends RenderProxyBox {
  _RenderEdgeFade(this._left, this._right);

  double _left;
  set left(double value) {
    if (value == _left) return;
    _left = value;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  double _right;
  set right(double value) {
    if (value == _right) return;
    _right = value;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  bool get _hasFade => _left > 0 || _right > 0;

  // On the widths alone: a size change would leave the bit stale.
  @override
  bool get alwaysNeedsCompositing => child != null && _hasFade;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    // A slot too narrow for its fade gets none.
    if (!_hasFade || size.width < math.max(_left, _right) * 3) {
      layer = null;
      context.paintChild(child, offset);
      return;
    }
    const opaque = Color(0xFFFFFFFF);
    const clear = Color(0x00FFFFFF);
    final shader = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: <Color>[
        _left > 0 ? clear : opaque,
        opaque,
        opaque,
        _right > 0 ? clear : opaque,
      ],
      stops: <double>[0, _left / size.width, 1 - _right / size.width, 1],
    ).createShader(Offset.zero & size);
    layer ??= ShaderMaskLayer();
    (layer! as ShaderMaskLayer)
      ..shader = shader
      ..maskRect = offset & size
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(layer!, super.paint, offset);
  }
}
