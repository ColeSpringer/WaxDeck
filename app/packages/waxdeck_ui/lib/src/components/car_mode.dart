import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../icons/wax_icon.dart';
import '../theme/theme_builder.dart';
import '../theme/wax_layout.dart';
import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'artwork.dart';
import 'controls.dart';
import 'player_scaffold.dart';
import 'semantics_slots.dart';
import 'view_data.dart';

/// The palette car mode imposes, whatever the app is set to.
///
/// Its own widget rather than something [CarModeScaffold] does inside
/// itself, because the scaffold is only the branch where something is
/// playing: the screen also has an idle state and an error state, and
/// those drew app-theme text on a hard-coded black - light-mode primary
/// text at under 3:1, on the control that is the only way out.
/// Brightness here is a safety property rather than a preference, and a
/// listener who set the app to paper did not set their car to it. The
/// density setting travels with them, because that one is about their
/// eyes rather than about the room.
class CarModeTheme extends StatelessWidget {
  const CarModeTheme({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
    data: buildWaxTheme(
      variant: WaxThemeVariant.oled,
      density: WaxLayout.of(context).density,
    ),
    child: child,
  );
}

/// The player as a glance and a swipe.
///
/// Everything here is a decision about a driver's attention. The palette
/// is the OLED set whatever the app's theme is, because a bright screen
/// at night is the wrong thing in a dark car and pure black costs no
/// light at all. The title is display size, the transport is three
/// targets at 96 px, and a swipe anywhere across the surface is prev and
/// next, so nothing needs aiming at. There are no lists and nothing to
/// type into: the surface offers what can be done at a glance and
/// nothing that cannot.
///
/// The way out is a large corner control, not a gesture: a driver who
/// leaves this by accident is a driver looking at a screen to get back.
class CarModeScaffold extends StatelessWidget {
  const CarModeScaffold({
    required this.now,
    required this.onPlayPause,
    this.onPrevious,
    this.onNext,
    this.onExit,
    this.ids = const PlayerIds(),
    this.exitSemanticsId,
    super.key,
  });

  final NowPlayingData now;
  final VoidCallback? onPlayPause;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onExit;

  final PlayerIds ids;
  final String? exitSemanticsId;

  /// The play button's diameter, and the reason the rest of the layout
  /// is what it is. 5.6 asks for 96 px targets; this is that, and the
  /// two beside it are sized from it.
  static const double controlSize = 96;

  /// How far a swipe has to travel before it counts as a track change,
  /// in pixels a second. High on purpose: a hand steadying itself on a
  /// dashboard mount is not asking for the next track.
  static const double _flingVelocity = 400;

  @override
  Widget build(BuildContext context) =>
      CarModeTheme(child: Builder(builder: _surface));

  Widget _surface(BuildContext context) {
    final colors = WaxColors.of(context);
    return Material(
      color: colors.canvas,
      child: Semantics(
        identifier: ids.surface,
        container: true,
        explicitChildNodes: true,
        child: GestureDetector(
          // Opaque, so the swipe belongs to the whole surface rather
          // than to whatever happens to be drawn where a hand landed.
          behavior: HitTestBehavior.opaque,
          // A pointer gesture only. Left in the semantics tree a
          // horizontal drag publishes scroll actions, and a screen
          // reader swiping to read would change tracks; the buttons
          // underneath say what they do and are what assistive tech
          // drives.
          excludeFromSemantics: true,
          onHorizontalDragEnd: (details) {
            final velocity = details.velocity.pixelsPerSecond.dx;
            if (velocity.abs() < _flingVelocity) return;
            // Swipe left for the next track, which is the direction
            // every carousel in the world moves.
            (velocity < 0 ? onNext : onPrevious)?.call();
          },
          child: SafeArea(
            child: LayoutBuilder(builder: (context, c) => _body(colors, c)),
          ),
        ),
      ),
    );
  }

  Widget _body(WaxColors colors, BoxConstraints constraints) {
    // The artwork takes the top half and the controls the bottom, which
    // is 5.6's own division: the cover says what is playing from across
    // a cabin, and the buttons are where a hand goes without looking.
    final art = math.min(constraints.maxHeight * 0.5, constraints.maxWidth);
    return Column(
      children: <Widget>[
        Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(WaxSpace.s8),
            child: WaxIconButton(
              glyph: WaxIcons.close,
              label: 'Leave car mode',
              // Oversized like everything else here, and in the corner
              // furthest from the transport: leaving is deliberate.
              size: 36,
              onPressed: onExit,
              semanticsId: exitSemanticsId,
            ),
          ),
        ),
        // Gone rather than squeezed on a window with no room for it: a
        // landscape phone on a dashboard mount has the height for the
        // controls and nothing else, and the controls are the point.
        if (art >= 120)
          Expanded(
            child: Center(
              child: ArtworkImage(
                size: art,
                artwork: now.artwork,
                monogram: now.title,
                shape: now.shape,
                domain: now.domain,
              ),
            ),
          ),
        // Flexible, and it is the title that gives rather than the
        // transport. The hero above already yields its whole slot on a
        // short window, and past that there is nothing left but the two
        // lines of type - so on a landscape phone at a large text scale
        // the column ran off the bottom and took the play button with
        // it, which is the one thing on this screen a driver reaches for
        // without looking. Scrolling inside the slot rather than
        // shrinking the type: 5.6 asks for display size, and a title
        // quietly set smaller is a worse answer than a title that can be
        // pushed with a thumb.
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s24),
            child: Column(
              children: <Widget>[
                Text(
                  now.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: WaxType.display.copyWith(color: colors.textPrimary),
                ),
                if (now.subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: WaxSpace.s8),
                    child: Text(
                      now.subtitle!,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WaxType.headline.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: WaxSpace.s24),
        // The scaffold's own transport at car size, so the glyphs, the
        // states, and the accessible names are the ones every other
        // surface uses. Nothing about a car makes "Pause" a different
        // word.
        TransportCluster(
          ids: ids,
          playing: now.playing,
          live: now.live,
          size: controlSize,
          onPlayPause: onPlayPause,
          onPrevious: onPrevious,
          onNext: onNext,
        ),
        const SizedBox(height: WaxSpace.s32),
      ],
    );
  }
}
