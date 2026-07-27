import 'package:flutter/material.dart';

import '../icons/wax_icon.dart';
import '../theme/wax_layout.dart';
import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'controls.dart';

/// How loud a banner is.
///
/// Tone is about the state, not about the wording: the same sentence
/// reads differently under a caution stripe, and a client that shouts
/// about a reconnect it is already handling teaches people to ignore the
/// stripe that matters.
enum WaxBannerTone {
  /// Something is underway and will settle on its own: reconnecting,
  /// catching up. Quiet by design.
  progress,

  /// Something is worth doing, when the visitor is ready: a new build to
  /// reload into.
  notice,

  /// Something is not working, and what is on screen is affected:
  /// offline, read-only, playback the browser refused.
  caution,
}

/// A standing message about the app's own state, drawn above the content.
///
/// Banners carry conditions nobody asked for and no single tap resolves:
/// the connection dropped, the server was upgraded underneath, the
/// library is read-only. Anything that answers one action is a toast, and
/// anything that needs a decision is a dialog.
///
/// It announces itself: the message is a live region, so a screen reader
/// hears the connection drop rather than discovering it by exploring.
/// The action and the dismiss keep their own nodes, so the announcement
/// never swallows the controls.
class WaxBanner extends StatelessWidget {
  const WaxBanner({
    required this.message,
    this.tone = WaxBannerTone.progress,
    this.glyph,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    this.semanticsId,
    this.actionSemanticsId,
    this.dismissSemanticsId,
    super.key,
  });

  /// One sentence, in the house voice: what is true, and what it means
  /// for what is on screen.
  final String message;

  final WaxBannerTone tone;

  /// Overrides the tone's own glyph.
  final WaxGlyph? glyph;

  /// The one thing to do about it, when there is one ("Reload").
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Offered only where dismissing is honest: a condition that clears
  /// itself has no dismiss, because hiding it would not end it.
  final VoidCallback? onDismiss;

  final String? semanticsId;
  final String? actionSemanticsId;
  final String? dismissSemanticsId;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final layout = WaxLayout.of(context);

    final (Color background, Color foreground, Color tint) = switch (tone) {
      WaxBannerTone.progress => (
        colors.surface2,
        colors.textPrimary,
        colors.textSecondary,
      ),
      WaxBannerTone.notice => (
        colors.accentContainer,
        colors.onAccentContainer,
        colors.onAccentContainer,
      ),
      WaxBannerTone.caution => (
        colors.surface2,
        colors.textPrimary,
        colors.error,
      ),
    };

    final glyph =
        this.glyph ??
        switch (tone) {
          WaxBannerTone.progress => WaxIcons.refresh,
          WaxBannerTone.notice => WaxIcons.info,
          WaxBannerTone.caution => WaxIcons.warning,
        };

    return Semantics(
      identifier: semanticsId,
      container: true,
      // Without this the action's own node merges into this one and the
      // banner becomes a single node that announces "…Reload" and
      // handles a tap nobody can find: a Semantics that is not a
      // container folds into the nearest one that is.
      explicitChildNodes: true,
      liveRegion: true,
      label: message,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          border: Border(
            bottom: BorderSide(
              color: colors.hairline,
              width: layout.hairlineWidth,
            ),
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: WaxSpace.s16,
              vertical: WaxSpace.s8,
            ),
            child: Row(
              children: <Widget>[
                WaxIcon(glyph, size: 16, color: tint),
                const SizedBox(width: WaxSpace.s12),
                // The message wraps rather than truncating: a banner is
                // the whole explanation, and half of one is worse than
                // none. Its own node is excluded because the region
                // above already speaks it.
                Expanded(
                  child: ExcludeSemantics(
                    child: Text(
                      message,
                      style: WaxType.bodySmall.copyWith(color: foreground),
                    ),
                  ),
                ),
                if (actionLabel != null) ...<Widget>[
                  const SizedBox(width: WaxSpace.s8),
                  WaxButton(
                    label: actionLabel!,
                    kind: WaxButtonKind.text,
                    onPressed: onAction,
                    semanticsId: actionSemanticsId,
                  ),
                ],
                if (onDismiss != null)
                  WaxIconButton(
                    glyph: WaxIcons.close,
                    label: 'Dismiss',
                    size: 16,
                    onPressed: onDismiss,
                    semanticsId: dismissSemanticsId,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
