import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/plain_text_style.dart';

/// A modal bottom sheet, opened the one way the app opens them. Its
/// handle drags it everywhere; its body only where fingers are the
/// pointer, since a mouse dragging there is selecting the text.
///
/// The content sits on a plain text style, not on the one the sheet's
/// Material eases into a new theme.
Future<T?> showWaxSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  Color? backgroundColor,
  BoxConstraints? constraints,
}) => showModalBottomSheet<T>(
  context: context,
  builder: (context) => WaxPlainTextStyle(child: builder(context)),
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
