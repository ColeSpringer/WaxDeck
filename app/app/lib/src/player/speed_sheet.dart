import 'dart:async';

import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../shell/semantics_ids.dart';
import 'playback_session.dart';

/// The speeds the sheet offers as one tap each (5.3).
///
/// Clustered where listening actually happens: the useful range for
/// spoken word is a narrow band just above 1x, and a picker with even
/// steps spends most of its width on rates nobody uses. The stepper
/// beside them reaches everything in between.
const speedPresets = <double>[0.8, 1.0, 1.1, 1.2, 1.35, 1.5, 1.75, 2.0];

/// What the fine stepper spans, matching the contract's own bounds on
/// the per-show and per-book speed fields.
const speedMin = 0.5;
const speedMax = 3.5;

/// One press of the stepper. Small enough to find the rate between two
/// presets, large enough that crossing the band does not take forty
/// presses.
const speedStep = 0.05;

/// The stable handle a preset carries, so a spec names the speed rather
/// than its position in the row.
int speedPercent(double speed) => (speed * 100).round();

/// Rounds to the step grid and clamps to the band, so the arithmetic of
/// repeated presses cannot drift off it.
double clampSpeed(double speed) {
  final snapped = (speed / speedStep).round() * speedStep;
  return snapped.clamp(speedMin, speedMax);
}

/// Opens the speed sheet over [session].
///
/// Every speed in one tap, which is the point of it: the button used to
/// cycle a fixed ladder, so reaching 1.1x from 1.5x meant walking
/// through everything in between and past the top.
Future<void> showSpeedSheet(BuildContext context, PlaybackSession session) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => _SpeedSheet(session: session),
  );
}

class _SpeedSheet extends StatelessWidget {
  const _SpeedSheet({required this.session});

  final PlaybackSession session;

  void _set(double speed) => unawaited(session.setSpeed(clampSpeed(speed)));

  /// A preset is a decision, so it lands and the sheet leaves: one tap
  /// total for the case the presets exist to serve. The stepper is a
  /// walk rather than a decision and keeps the sheet up, which is also
  /// what makes the readout above it worth drawing.
  void _pick(BuildContext context, double speed) {
    _set(speed);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return SafeArea(
      child: Semantics(
        identifier: SemanticsIds.playerSpeedSheet,
        container: true,
        explicitChildNodes: true,
        label: context.l10n.playerSpeed,
        child: StreamBuilder<double>(
          stream: session.engine.speedStream,
          initialData: session.engine.speed,
          builder: (context, snapshot) {
            final speed = snapshot.data ?? 1.0;
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                WaxSpace.s24,
                WaxSpace.s8,
                WaxSpace.s24,
                WaxSpace.s24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SectionHeader(title: context.l10n.playerSpeed),
                  const SizedBox(height: WaxSpace.s8),
                  _Stepper(speed: speed, onSet: _set),
                  const SizedBox(height: WaxSpace.s20),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: WaxSpace.s8,
                    runSpacing: WaxSpace.s8,
                    children: <Widget>[
                      for (final preset in speedPresets)
                        WaxPill(
                          semanticsId: SemanticsIds.playerSpeedPreset(
                            speedPercent(preset),
                          ),
                          label: context.l10n.formatSpeed(preset),
                          mono: true,
                          // Against the snapped value, not the raw one:
                          // a stepper walked onto 1.2 has to light the
                          // chip it landed on, and floating point makes
                          // equality on the nose a coin toss.
                          selected:
                              speedPercent(clampSpeed(speed)) ==
                              speedPercent(preset),
                          // A step above the sheet it sits on, where the
                          // player's own pills sit a step above the
                          // canvas: both lift off what is under them,
                          // which is what the two disagreed about while
                          // they were separate widgets.
                          surface: colors.surface3,
                          onPressed: () => _pick(context, preset),
                        ),
                    ],
                  ),
                  const SizedBox(height: WaxSpace.s16),
                  Text(
                    switch ((
                      session.isSpokenWord,
                      session.item.mediaType == MediaType.audiobook,
                    )) {
                      (false, _) => context.l10n.playerSpeedThisSession,
                      (true, true) => context.l10n.playerSpeedRememberedBook,
                      (true, false) => context.l10n.playerSpeedRememberedShow,
                    },
                    textAlign: TextAlign.center,
                    style: WaxType.caption.copyWith(color: colors.textTertiary),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Minus, the rate, plus. The readout is the sheet's own state rather
/// than a control: it changes under both the stepper and the presets,
/// and a listener needs to see where they are before deciding.
class _Stepper extends StatelessWidget {
  const _Stepper({required this.speed, required this.onSet});

  final double speed;
  final void Function(double speed) onSet;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final current = clampSpeed(speed);
    // Worded rather than a pair of glyphs: the icon set carries a plus
    // and no minus, and "Slower" and "Faster" say what a minus over a
    // rate means anyway, which a bare sign leaves to inference.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        WaxButton(
          label: context.l10n.playerSlower,
          kind: WaxButtonKind.text,
          semanticsId: SemanticsIds.playerSpeedSlower,
          onPressed: current <= speedMin
              ? null
              : () => onSet(current - speedStep),
        ),
        SizedBox(
          width: 116,
          child: Text(
            context.l10n.formatSpeed(current),
            textAlign: TextAlign.center,
            style: WaxType.display.copyWith(color: colors.textPrimary),
          ),
        ),
        WaxButton(
          label: context.l10n.playerFaster,
          kind: WaxButtonKind.text,
          semanticsId: SemanticsIds.playerSpeedFaster,
          onPressed: current >= speedMax
              ? null
              : () => onSet(current + speedStep),
        ),
      ],
    );
  }
}
