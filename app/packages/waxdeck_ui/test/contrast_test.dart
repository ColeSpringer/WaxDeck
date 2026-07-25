import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// One foreground/background pairing the tokens actually land on, with
/// the WCAG level it owes.
class _Pair {
  const _Pair(this.what, this.foreground, this.background, this.minimum);

  final String what;
  final Color foreground;
  final Color background;
  final double minimum;
}

/// Every pair for one theme.
///
/// The list is the point: a canvas-only check passes while hint text on a
/// dialog quietly fails, so this enumerates text on all four surfaces,
/// text on containers, accents on washes, and borders on everything.
List<_Pair> _pairsFor(String theme, WaxColors c) {
  final surfaces = <String, Color>{
    'canvas': c.canvas,
    'surface1': c.surface1,
    'surface2': c.surface2,
    'surface3': c.surface3,
  };

  // Foregrounds that carry words: full 4.5:1 text contrast.
  final text = <String, Color>{
    'textPrimary': c.textPrimary,
    'textSecondary': c.textSecondary,
    'textTertiary': c.textTertiary,
    'accent': c.accent,
    'success': c.success,
    'error': c.error,
  };

  // Foregrounds that draw shapes: 3:1, the bar for non-text UI. Domain
  // hues live here because words inside a domain-tinted surface use that
  // domain's onContainer token instead.
  final ui = <String, Color>{
    'outline': c.outline,
    'music hue': c.music.hue,
    'podcast hue': c.podcasts.hue,
    'audiobook hue': c.audiobooks.hue,
    'radio hue': c.radio.hue,
  };

  final pairs = <_Pair>[];
  for (final surface in surfaces.entries) {
    for (final fg in text.entries) {
      pairs.add(
        _Pair(
          '$theme: ${fg.key} on ${surface.key}',
          fg.value,
          surface.value,
          WaxContrast.aaText,
        ),
      );
    }
    for (final fg in ui.entries) {
      pairs.add(
        _Pair(
          '$theme: ${fg.key} on ${surface.key}',
          fg.value,
          surface.value,
          WaxContrast.aaLarge,
        ),
      );
    }
  }

  // Fills and their on-colours.
  pairs.addAll(<_Pair>[
    _Pair(
      '$theme: onAccent on accent',
      c.onAccent,
      c.accent,
      WaxContrast.aaText,
    ),
    _Pair(
      '$theme: onSuccess on success',
      c.onSuccess,
      c.success,
      WaxContrast.aaText,
    ),
    _Pair('$theme: onError on error', c.onError, c.error, WaxContrast.aaText),
    _Pair(
      '$theme: accent fill on canvas',
      c.accent,
      c.canvas,
      WaxContrast.aaLarge,
    ),
  ]);

  // Containers: chip and badge fills, with the text that sits in them.
  final containers = <String, WaxDomainColors>{
    'music': c.music,
    'podcast': c.podcasts,
    'audiobook': c.audiobooks,
    'radio': c.radio,
  };
  for (final entry in containers.entries) {
    final domain = entry.value;
    pairs.addAll(<_Pair>[
      _Pair(
        '$theme: ${entry.key} onContainer on container',
        domain.onContainer,
        domain.container,
        WaxContrast.aaText,
      ),
      _Pair(
        '$theme: textPrimary on ${entry.key} container',
        c.textPrimary,
        domain.container,
        WaxContrast.aaText,
      ),
      _Pair(
        '$theme: ${entry.key} container on canvas',
        domain.container,
        c.canvas,
        1.05,
      ),
    ]);
  }
  pairs.add(
    _Pair(
      '$theme: onAccentContainer on accentContainer',
      c.onAccentContainer,
      c.accentContainer,
      WaxContrast.aaText,
    ),
  );

  // The focus ring's outer stroke has to be visible against every
  // surface it can land on, including an active amber element: that is
  // what the two-tone ring's inner stroke is for, so the pair that
  // matters is inner-against-accent.
  pairs.add(
    _Pair(
      '$theme: focus ring inner on accent fill',
      c.surface1,
      c.accent,
      WaxContrast.aaLarge,
    ),
  );

  return pairs;
}

void main() {
  group('token contrast', () {
    final themes = <String, WaxColors>{
      'dark': WaxColors.dark,
      'light': WaxColors.light,
      'oled': WaxColors.oled,
    };

    for (final theme in themes.entries) {
      for (final pair in _pairsFor(theme.key, theme.value)) {
        test('${pair.what} holds ${pair.minimum}:1', () {
          final ratio = WaxContrast.ratio(pair.foreground, pair.background);
          expect(
            ratio,
            greaterThanOrEqualTo(pair.minimum - 0.005),
            reason:
                '${pair.what} is ${ratio.toStringAsFixed(2)}:1, below the '
                '${pair.minimum}:1 this pairing owes. Fix the token, not '
                'this test: every pair here is one a screen actually '
                'renders.',
          );
        });
      }
    }

    // WCAG exempts disabled controls, and WaxDeck never signals disabled
    // by colour alone. The tokens are still held apart from the readable
    // tertiary tone so "disabled" and "quiet" never look alike, and held
    // above a visibility floor so "disabled" never becomes "absent":
    // a control nobody can see is not a disabled control, it is a bug.
    test('disabled text is dimmer than tertiary but still visible', () {
      for (final theme in themes.entries) {
        final c = theme.value;
        expect(
          WaxContrast.ratio(c.textDisabled, c.canvas),
          lessThan(WaxContrast.ratio(c.textTertiary, c.canvas)),
          reason: '${theme.key}: disabled must sit below the tertiary tone',
        );
        for (final surface in <String, Color>{
          'canvas': c.canvas,
          'surface1': c.surface1,
          'surface2': c.surface2,
          'surface3': c.surface3,
        }.entries) {
          expect(
            WaxContrast.ratio(c.textDisabled, surface.value),
            greaterThanOrEqualTo(1.8),
            reason:
                '${theme.key}: disabled text on ${surface.key} has faded '
                'into the surface',
          );
        }
      }
    });

    test('scrim reaches AA over the worst-case artwork backdrop', () {
      // A blown-out white cover is the hard case: the backdrop scrim has
      // to be able to claw primary text back to 4.5:1 without going
      // fully opaque, or the artwork would be invisible behind it.
      for (final theme in <WaxColors>[WaxColors.dark, WaxColors.oled]) {
        final alpha = WaxContrast.scrimAlphaFor(
          text: theme.textPrimary,
          backdrop: const Color(0xFFFFFFFF),
          scrim: theme.scrim.withValues(alpha: 1),
        );
        expect(alpha, lessThan(0.9));
        expect(
          WaxContrast.meets(
            theme.textPrimary,
            WaxContrast.flatten(
              theme.scrim.withValues(alpha: alpha),
              const Color(0xFFFFFFFF),
            ),
            WaxContrast.aaText,
          ),
          isTrue,
        );
      }
    });
  });
}
