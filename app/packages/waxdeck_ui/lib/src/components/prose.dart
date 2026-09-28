import 'package:cupertino_ui/cupertino_ui.dart'
    show
        cupertinoDesktopTextSelectionHandleControls,
        cupertinoTextSelectionHandleControls;
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
  GlobalKey _child = GlobalKey(debugLabel: 'wax-prose-child');

  /// The area, built once and handed back unchanged, so rebuilding the
  /// prose never rebuilds it. On the web it builds a different subtree
  /// while the browser menu is on, and rebuilt across a flip it swaps
  /// that subtree out from under its own selection state, which throws
  /// on the next flip - and hovering anything with a menu of its own
  /// flips it. What does change reaches the child through [_ProseContent].
  late Widget _area = _newArea();

  Widget _newArea() => SelectableRegion(
    // Keyed for [reassemble], which has to replace it.
    key: UniqueKey(),
    // Not left to the theme: a theme change would rebuild the area.
    selectionControls: switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.fuchsia => materialTextSelectionHandleControls,
      TargetPlatform.linux ||
      TargetPlatform.windows => desktopTextSelectionHandleControls,
      TargetPlatform.iOS => cupertinoTextSelectionHandleControls,
      TargetPlatform.macOS => cupertinoDesktopTextSelectionHandleControls,
    },
    magnifierConfiguration: TextMagnifier.adaptiveMagnifierConfiguration,
    focusNode: _focus,
    contextMenuBuilder: _menu,
    onSelectionChanged: _selectionChanged,
    child: _ProseChild(_child),
  );

  @override
  void reassemble() {
    super.reassemble();
    // A reload rebuilds every element, so a new area instead, with a new
    // child rather than one carried out of the old area.
    _child = GlobalKey(debugLabel: 'wax-prose-child');
    _area = _newArea();
  }

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
    return WaxSecondaryTapRegion(
      child: _ProseContent(content: content, child: _area),
    );
  }
}

/// The prose's current child, handed past the area it must not rebuild.
class _ProseContent extends InheritedWidget {
  const _ProseContent({required this.content, required super.child});

  final Widget content;

  @override
  bool updateShouldNotify(_ProseContent old) => content != old.content;
}

/// Where the child meets the area: rebuilt for a new child or a covered
/// page, neither of which rebuilds the area around it.
class _ProseChild extends StatelessWidget {
  const _ProseChild(this.childKey);

  final GlobalKey childKey;

  @override
  Widget build(BuildContext context) {
    final content = context
        .dependOnInheritedWidgetOfExactType<_ProseContent>()!
        .content;
    Widget child = KeyedSubtree(key: childKey, child: content);
    // A covered page is never laid out, and the area orders its texts by
    // where they sit on screen: they join it once the page shows.
    if (!TickerMode.valuesOf(context).enabled) {
      child = SelectionContainer.disabled(child: child);
    }
    return child;
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
