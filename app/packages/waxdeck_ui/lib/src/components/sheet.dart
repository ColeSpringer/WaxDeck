import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/plain_text_style.dart';

/// A modal bottom sheet, opened the one way the app opens them. Its
/// handle drags it everywhere; its body only where fingers are the
/// pointer, since a mouse dragging there is selecting the text.
///
/// The content sits on a plain text style, not on the one the sheet's
/// Material eases into a new theme. It is handed a side inset of the
/// window only where the sheet reaches that side: a sheet narrower than
/// the window stands clear of a cutout beside it.
Future<T?> showWaxSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  Color? backgroundColor,
  BoxConstraints? constraints,
}) {
  final navigator = Navigator.of(context);
  final localizations = MaterialLocalizations.of(context);
  final theme = Theme.of(context).bottomSheetTheme;
  return navigator.push(
    _WaxSheetRoute<T>(
      builder: (context) => WaxPlainTextStyle(child: builder(context)),
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      isScrollControlled: isScrollControlled,
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      backgroundColor: backgroundColor,
      // Stated rather than left to the sheet's own default, so the width
      // its insets are measured against is the width it is drawn at.
      constraints:
          constraints ??
          theme.constraints ??
          const BoxConstraints(maxWidth: _maxWidth),
      modalBarrierColor: theme.modalBarrierColor,
      enableDrag: switch (defaultTargetPlatform) {
        TargetPlatform.android ||
        TargetPlatform.iOS ||
        TargetPlatform.fuchsia => true,
        TargetPlatform.linux ||
        TargetPlatform.macOS ||
        TargetPlatform.windows => false,
      },
      showDragHandle: true,
    ),
  );
}

/// Material 3's own widest sheet.
const double _maxWidth = 640;

class _WaxSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _WaxSheetRoute({
    required super.builder,
    required super.capturedThemes,
    required super.isScrollControlled,
    required super.barrierLabel,
    required super.barrierOnTapHint,
    required super.backgroundColor,
    required super.constraints,
    required super.modalBarrierColor,
    required super.enableDrag,
    required super.showDragHandle,
  });

  // The sheet is centred along the foot of its area at its own width, so
  // a side inset reaches it only by what lies past the gap beside it.
  // Laid out against the area: a resize or a cutout moving re-lays it.
  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => LayoutBuilder(
    builder: (context, area) {
      final width = math.min(area.maxWidth, constraints!.maxWidth);
      final gap = (area.maxWidth - width) / 2;
      final media = MediaQuery.of(context);
      EdgeInsets reaching(EdgeInsets insets) => insets.copyWith(
        left: math.max(0, insets.left - gap),
        right: math.max(0, insets.right - gap),
      );
      return MediaQuery(
        data: media.copyWith(
          padding: reaching(media.padding),
          viewPadding: reaching(media.viewPadding),
        ),
        child: Builder(
          builder: (context) =>
              super.buildPage(context, animation, secondaryAnimation),
        ),
      );
    },
  );
}
