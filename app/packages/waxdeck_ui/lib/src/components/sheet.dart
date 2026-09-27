import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// A modal bottom sheet, opened the one way the app opens them. Its
/// handle drags it everywhere; its body only where fingers are the
/// pointer, since a mouse dragging there is selecting the text.
Future<T?> showWaxSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  Color? backgroundColor,
  BoxConstraints? constraints,
}) => showModalBottomSheet<T>(
  context: context,
  builder: builder,
  isScrollControlled: isScrollControlled,
  backgroundColor: backgroundColor,
  constraints: constraints,
  enableDrag: switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => true,
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => false,
  },
  showDragHandle: true,
);
