import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:material_ui/material_ui.dart';

import '../tokens/typography.dart';
import 'secondary_tap.dart';

/// Prose a reader can select and copy: a help line, a state's sentence,
/// a dialog's message. Prose only, never a form: a selection takes focus,
/// and with it a field's caret.
class WaxProse extends StatefulWidget {
  /// One run of text.
  const WaxProse(
    String this.data, {
    this.style,
    this.textAlign,
    this.overflow,
    this.maxLines,
    this.onTap,
    super.key,
  }) : child = null;

  /// Any subtree of text, so one selection can run across all of it.
  const WaxProse.block({required Widget this.child, this.onTap, super.key})
    : data = null,
      style = null,
      textAlign = null,
      overflow = null,
      maxLines = null;

  final String? data;
  final Widget? child;

  final TextStyle? style;
  final TextAlign? textAlign;
  final TextOverflow? overflow;
  final int? maxLines;

  /// What a plain tap does, for prose inside a control whose tap the
  /// area would otherwise take. A drag or a long press still selects.
  final VoidCallback? onTap;

  @override
  State<WaxProse> createState() => _WaxProseState();
}

class _WaxProseState extends State<WaxProse> {
  final _ProseFocus _focus = _ProseFocus();

  /// Holds the child across its texts leaving the area and coming back,
  /// so it is moved rather than rebuilt.
  final GlobalKey _child = GlobalKey(debugLabel: 'wax-prose-child');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _selectionChanged(SelectedContent? content) {
    _focus.selected = content != null && content.plainText.isNotEmpty;
    if (_focus.selected && !_focus.hasFocus) _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    Widget content =
        widget.child ??
        Text(
          widget.data!,
          style: widget.style,
          textAlign: widget.textAlign,
          overflow: widget.overflow,
          maxLines: widget.maxLines,
        );
    if (widget.onTap != null) {
      // Deeper than the area's recognizers, so it takes a plain tap
      // anywhere in the box, beside a short line too.
      content = GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        child: content,
      );
    }
    content = KeyedSubtree(key: _child, child: content);
    // A covered page is never laid out, and the area orders its texts by
    // where they sit on screen: they join it once the page shows.
    if (!TickerMode.valuesOf(context).enabled) {
      content = SelectionContainer.disabled(child: content);
    }
    return WaxSecondaryTapRegion(
      child: SelectionArea(
        focusNode: _focus,
        contextMenuBuilder: _menu,
        onSelectionChanged: _selectionChanged,
        child: content,
      ),
    );
  }
}

/// The area's focus: never a tab stop, nor anything inside it (the web
/// build's context-menu view), and taken once there is a selection rather
/// than on the press that may start one, which would close a keyboard.
class _ProseFocus extends FocusNode {
  _ProseFocus()
    : super(
        debugLabel: 'wax-prose',
        skipTraversal: true,
        descendantsAreTraversable: false,
      );

  bool selected = false;

  @override
  void requestFocus([FocusNode? node]) {
    if (node == null && !selected) return;
    super.requestFocus(node);
  }
}

/// Material's menu on every platform, labels in the app's type (the stock
/// ones name no face, which the web build cannot fetch), and buttons that
/// never take focus: losing it clears the selection Copy acts on.
Widget _menu(BuildContext context, SelectableRegionState region) {
  final items = region.contextMenuButtonItems;
  if (items.isEmpty) return const SizedBox.shrink();
  final anchors = region.contextMenuAnchors;
  Widget label(ContextMenuButtonItem item) => Text(
    AdaptiveTextSelectionToolbar.getButtonLabel(context, item),
    style: WaxType.body,
  );
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.iOS:
      return TextSelectionToolbar(
        anchorAbove: anchors.primaryAnchor,
        anchorBelow: anchors.secondaryAnchor ?? anchors.primaryAnchor,
        children: <Widget>[
          for (final (index, item) in items.indexed)
            ExcludeFocus(
              child: TextSelectionToolbarTextButton(
                padding: TextSelectionToolbarTextButton.getPadding(
                  index,
                  items.length,
                ),
                onPressed: item.onPressed,
                child: label(item),
              ),
            ),
        ],
      );
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return DesktopTextSelectionToolbar(
        anchor: anchors.primaryAnchor,
        children: <Widget>[
          for (final item in items)
            ExcludeFocus(
              child: DesktopTextSelectionToolbarButton(
                onPressed: item.onPressed,
                child: label(item),
              ),
            ),
        ],
      );
  }
}
