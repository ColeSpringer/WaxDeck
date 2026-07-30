import 'package:flutter/material.dart';

import '../icons/wax_icon.dart';
import '../theme/wax_layout.dart';
import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'controls.dart';

/// The right panel's chrome: a titled surface beside the content.
///
/// The panel is where a wide window keeps something open next to what it
/// is about - the queue, lyrics, the session playing on another device -
/// rather than covering the page with a sheet. It owns its own frame and
/// nothing else: what goes inside is the caller's, and the shell decides
/// whether it docks beside the content or lies over its trailing edge.
///
/// It is a region of its own to assistive tech, named by its title, so
/// moving into it is a landmark jump rather than a walk through whatever
/// the page happened to leave in the traversal order.
class WaxSidePanel extends StatelessWidget {
  const WaxSidePanel({
    required this.title,
    required this.child,
    this.actions = const <Widget>[],
    this.onClose,
    this.semanticsId,
    this.closeSemanticsId,
    super.key,
  });

  /// Names the panel in its header and to assistive tech.
  final String title;

  final Widget child;

  /// Header controls that belong to the panel's contents ("Clear
  /// queue"), drawn before the close button.
  final List<Widget> actions;

  /// Null leaves the panel without a close affordance, for a shell that
  /// closes it some other way. Every panel the shell opens has one.
  final VoidCallback? onClose;

  final String? semanticsId;
  final String? closeSemanticsId;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final layout = WaxLayout.of(context);

    return Semantics(
      identifier: semanticsId,
      container: true,
      explicitChildNodes: true,
      label: title,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface1,
          border: BorderDirectional(
            start: BorderSide(
              color: colors.hairline,
              width: layout.hairlineWidth,
            ),
          ),
        ),
        // Its own Material: the panel is mounted straight into the
        // shell's frame, and the ink and menu machinery inside it needs
        // one that is not the content pane's.
        child: Material(
          type: MaterialType.transparency,
          child: SafeArea(
            left: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    WaxSpace.s16,
                    WaxSpace.s12,
                    WaxSpace.s8,
                    WaxSpace.s8,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WaxType.headline.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      ...actions,
                      if (onClose != null)
                        WaxIconButton(
                          glyph: WaxIcons.close,
                          label: 'Close panel',
                          size: 18,
                          onPressed: onClose,
                          semanticsId: closeSemanticsId,
                        ),
                    ],
                  ),
                ),
                Divider(color: colors.hairline, height: layout.hairlineWidth),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
