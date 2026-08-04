import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import '../icons/wax_icon.dart';
import 'artwork.dart';
import 'controls.dart';
import 'deck_bar.dart' show DeckBarActions;
import 'view_data.dart';

/// How large the mini player draws. The window is sized to it, so these
/// are the figures the desktop port asks the compositor for.
const double kMiniPlayerWidth = 320;
const double kMiniPlayerHeight = 96;

/// The mini player's e2e handles, supplied by the app for the same
/// reason [DeckBarIds] is: the design system emits no identifier strings
/// of its own.
@immutable
class MiniPlayerIds {
  const MiniPlayerIds({
    this.surface,
    this.play,
    this.next,
    this.previous,
    this.restore,
  });

  final String? surface;
  final String? play;
  final String? next;
  final String? previous;
  final String? restore;
}

/// The desktop mini player: a whole window, 320 by 96, holding artwork,
/// what is playing, three transports, and a progress hairline.
///
/// A component rather than a shrunken deck bar. The bar is a strip docked
/// under a screen and says so - a top hairline, a background that
/// continues the surface beneath it, a tap target that expands into the
/// player. This is the entire window: it has to be draggable by its own
/// background (a frameless window has no title bar to grab), it has a way
/// back rather than a way in, and it stands on a border of its own.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    required this.now,
    this.actions = const DeckBarActions(),
    this.ids = const MiniPlayerIds(),
    this.positionTicker,
    this.onRestore,
    this.onDrag,
    super.key,
  });

  final NowPlayingData now;
  final DeckBarActions actions;
  final MiniPlayerIds ids;

  /// The live position, fed into the hairline alone so the window does
  /// not rebuild several times a second.
  final ValueListenable<Duration>? positionTicker;

  /// Puts the window back the size it was. Always offered: a frameless
  /// window has no other way out, and one that kept its frame still
  /// needs a control that means "restore" rather than "close".
  final VoidCallback? onRestore;

  /// Somebody began dragging the window's background. The app hands this
  /// to the window port; the design system knows nothing about windows.
  final VoidCallback? onDrag;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Semantics(
      identifier: ids.surface,
      container: true,
      explicitChildNodes: true,
      label: 'Mini player',
      value: <String?>[
        now.playing ? 'Playing' : 'Paused',
        now.title,
        now.subtitle,
      ].nonNulls.join(', '),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface1,
          border: Border.all(color: colors.hairline),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: SizedBox(
            width: kMiniPlayerWidth,
            height: kMiniPlayerHeight,
            child: Column(
              children: <Widget>[
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: WaxSpace.s12,
                    ),
                    child: Row(
                      children: <Widget>[
                        // The handle stops before the transport: a pan
                        // recognizer over the buttons competes with them
                        // for every click, and a mouse's hit slop is one
                        // pixel, so it usually wins.
                        Expanded(
                          child: GestureDetector(
                            onPanStart: onDrag == null
                                ? null
                                : (_) => onDrag!(),
                            // The title-bar convention.
                            onDoubleTap: onRestore,
                            behavior: HitTestBehavior.opaque,
                            child: Row(
                              children: <Widget>[
                                ArtworkImage(
                                  size: 64,
                                  artwork: now.artwork,
                                  monogram: now.title,
                                  shape: now.shape,
                                  domain: now.domain,
                                ),
                                const SizedBox(width: WaxSpace.s12),
                                Expanded(
                                  child: ExcludeSemantics(
                                    child: _titles(colors),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        ..._transport(colors),
                      ],
                    ),
                  ),
                ),
                // The progress affordance, and the whole of it: a seek
                // bar in a window this size is a mis-tap generator, and
                // the full player is one click away.
                if (!now.live)
                  positionTicker == null
                      ? _hairline(colors, now.position)
                      : ValueListenableBuilder<Duration>(
                          valueListenable: positionTicker!,
                          builder: (context, position, _) =>
                              _hairline(colors, position),
                        ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hairline(WaxColors colors, Duration position) =>
      LinearProgressIndicator(
        value: now.fractionAt(position),
        minHeight: 2,
        backgroundColor: colors.hairline,
        valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
      );

  Widget _titles(WaxColors colors) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.center,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Text(
        now.title,
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        style: WaxType.titleItem.copyWith(color: colors.textPrimary),
      ),
      if (now.subtitle != null)
        Text(
          now.subtitle!,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: WaxType.caption.copyWith(color: colors.textSecondary),
        ),
    ],
  );

  List<Widget> _transport(WaxColors colors) => <Widget>[
    WaxIconButton(
      glyph: WaxIcons.previous,
      label: 'Previous',
      size: 18,
      semanticsId: ids.previous,
      onPressed: actions.onPrevious,
    ),
    WaxIconButton(
      glyph: now.playing ? WaxIcons.pause : WaxIcons.play,
      label: now.playing ? 'Pause' : 'Play',
      size: 22,
      active: true,
      semanticsId: ids.play,
      onPressed: actions.onPlayPause,
    ),
    WaxIconButton(
      glyph: WaxIcons.next,
      label: 'Next',
      size: 18,
      semanticsId: ids.next,
      onPressed: actions.onNext,
    ),
    WaxIconButton(
      glyph: WaxIcons.expand,
      label: 'Back to the full window',
      size: 16,
      semanticsId: ids.restore,
      onPressed: onRestore,
    ),
  ];
}
