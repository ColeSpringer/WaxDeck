import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import '../tokens/spacing.dart';
import 'info_tip.dart';

/// [title], then a [WaxInfoTip] holding [info] right after it, centred on
/// the title's line, which grows to the tip's 44 px target: for a host
/// with no room around its title, such as a section header. One shape
/// with or without an info, so the title stays put as one comes or goes.
Widget titleWithInfo(Widget title, String? info, {String? semanticsId}) => Row(
  children: <Widget>[
    Flexible(child: title),
    if (info != null) WaxInfoTip(message: info, semanticsId: semanticsId),
  ],
);

/// A host with room around its title, and a [WaxInfoTip] holding [info]
/// drawn over that room at the mark [builder] puts right after the title.
///
/// The title's line keeps its own height, so whatever is set against it
/// (a glyph, a help line, a control) stays put when an info arrives. The
/// tip's 44 px target lies over the host's padding instead, centred on the
/// mark as far as the host's own box allows: kept inside it, all of the
/// target takes a press.
class InfoOverRoom extends StatefulWidget {
  const InfoOverRoom({
    required this.info,
    required this.builder,
    this.semanticsId,
    super.key,
  });

  final String? info;
  final String? semanticsId;

  /// The host, with [mark] (null without an info) right after its title,
  /// on the title's line.
  final Widget Function(Widget? mark) builder;

  @override
  State<InfoOverRoom> createState() => _InfoOverRoomState();
}

class _InfoOverRoomState extends State<InfoOverRoom> {
  final GlobalKey _mark = GlobalKey(debugLabel: 'info-mark');

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    // The host first either way, so an info arriving or going rebuilds the
    // title's line and not the rest of the host.
    return _InfoRoom(
      mark: _mark,
      children: <Widget>[
        widget.builder(
          info == null
              ? null
              : SizedBox(key: _mark, width: WaxSpace.touchTarget),
        ),
        if (info != null)
          WaxInfoTip(message: info, semanticsId: widget.semanticsId),
      ],
    );
  }
}

/// The host as it lays itself out, with the tip over it.
class _InfoRoom extends MultiChildRenderObjectWidget {
  const _InfoRoom({required this.mark, super.children});

  final GlobalKey mark;

  @override
  _RenderInfoRoom createRenderObject(BuildContext context) =>
      _RenderInfoRoom(mark);

  @override
  void updateRenderObject(BuildContext context, _RenderInfoRoom renderObject) {
    renderObject.mark = mark;
  }
}

class _InfoRoomParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderInfoRoom extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _InfoRoomParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _InfoRoomParentData> {
  _RenderInfoRoom(GlobalKey mark) : _markKey = mark;

  GlobalKey _markKey;

  set mark(GlobalKey value) {
    if (value == _markKey) return;
    _markKey = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _InfoRoomParentData) {
      child.parentData = _InfoRoomParentData();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      firstChild?.getMinIntrinsicWidth(height) ?? 0;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      firstChild?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  double computeMinIntrinsicHeight(double width) =>
      firstChild?.getMinIntrinsicHeight(width) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      firstChild?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      firstChild?.getDistanceToActualBaseline(baseline);

  /// The slot's own constraints, so a tight one is filled and centred as
  /// it would be without a tip, but never tight on both axes: a tight child
  /// is a relayout boundary, and a title that moves inside the host has to
  /// lay this out again, and the tip with it. The host fills the width it
  /// is given either way.
  static BoxConstraints _forHost(BoxConstraints constraints) =>
      constraints.isTight ? constraints.copyWith(minWidth: 0) : constraints;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(
    firstChild?.getDryLayout(_forHost(constraints)) ?? Size.zero,
  );

  @override
  void performLayout() {
    final host = firstChild;
    if (host == null) {
      size = constraints.smallest;
      return;
    }
    host.layout(_forHost(constraints), parentUsesSize: true);
    size = constraints.constrain(host.size);
    final tip = childAfter(host);
    if (tip == null) return;
    tip.layout(const BoxConstraints(), parentUsesSize: true);
    final mark = _markKey.currentContext?.findRenderObject();
    if (mark is! RenderBox || !mark.attached) return;
    // The mark is as wide as the tip and has no height.
    final centre = mark.localToGlobal(
      const Offset(WaxSpace.touchTarget / 2, 0),
      ancestor: this,
    );
    (tip.parentData! as _InfoRoomParentData).offset = Offset(
      (centre.dx - tip.size.width / 2).clamp(
        0.0,
        math.max(0.0, size.width - tip.size.width),
      ),
      (centre.dy - tip.size.height / 2).clamp(
        0.0,
        math.max(0.0, size.height - tip.size.height),
      ),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
