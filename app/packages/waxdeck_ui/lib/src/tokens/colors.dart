import 'package:flutter/material.dart';

/// The four content domains WaxDeck presents as first-class modes.
///
/// Domain hues tint content surfaces (glyphs, mode badges, hub header
/// washes, player fallback glow). They never colour shell chrome: a
/// navigation item's active state is amber in every domain, because five
/// differently hued active tabs is the rainbow-nav trap.
enum WaxDomain { music, podcasts, audiobooks, radio }

/// One domain's hue and its container pairing.
///
/// [hue] is an identity tint for glyphs and small identity moments and
/// holds at least 3:1 against every canvas and surface (the WCAG bar for
/// non-text UI). Text inside a domain-tinted chip uses [onContainer] over
/// [container], which holds 4.5:1.
@immutable
class WaxDomainColors {
  const WaxDomainColors({
    required this.hue,
    required this.container,
    required this.onContainer,
  });

  final Color hue;
  final Color container;
  final Color onContainer;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WaxDomainColors &&
          other.hue == hue &&
          other.container == container &&
          other.onContainer == onContainer;

  @override
  int get hashCode => Object.hash(hue, container, onContainer);

  static WaxDomainColors lerp(WaxDomainColors a, WaxDomainColors b, double t) =>
      WaxDomainColors(
        hue: Color.lerp(a.hue, b.hue, t)!,
        container: Color.lerp(a.container, b.container, t)!,
        onContainer: Color.lerp(a.onContainer, b.onContainer, t)!,
      );
}

/// The resolved colour set for one theme, reachable as
/// `WaxColors.of(context)`.
///
/// Three sets ship: [dark] ("charcoal"), [light] ("porcelain"), and
/// [oled], a substitution variant of dark rather than a third
/// hand-maintained palette. Every foreground/surface pair these tokens
/// actually land on is enumerated by `test/contrast_test.dart` and must
/// hold WCAG 2.1 AA: 4.5:1 for text, 3:1 for large text and non-text UI.
/// [textDisabled] is the one documented exemption (WCAG exempts disabled
/// controls), and disabled state is never signalled by colour alone.
@immutable
class WaxColors extends ThemeExtension<WaxColors> {
  const WaxColors({
    required this.brightness,
    required this.canvas,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.hairline,
    required this.outline,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.scrim,
    required this.accent,
    required this.onAccent,
    required this.accentContainer,
    required this.onAccentContainer,
    required this.success,
    required this.onSuccess,
    required this.error,
    required this.onError,
    required this.music,
    required this.podcasts,
    required this.audiobooks,
    required this.radio,
    required this.glowOpacity,
    required this.washOpacity,
    required this.grainOpacity,
  });

  final Brightness brightness;

  /// App background.
  final Color canvas;

  /// Cards, deck bar, rails.
  final Color surface1;

  /// Sheets, menus, raised cards, hover on [surface1].
  final Color surface2;

  /// Dialogs, highest elevation, hover on [surface2].
  final Color surface3;

  /// Decorative separators. No contrast requirement, and never the only
  /// signal for a boundary that carries meaning.
  final Color hairline;

  /// Interactive component borders. Holds 3:1 on every surface.
  final Color outline;

  final Color textPrimary;
  final Color textSecondary;

  /// Hint text, timestamps, tertiary metadata in dense lists. The floor
  /// for readable text.
  final Color textTertiary;

  /// Disabled controls only: sub-AA by design, always accompanied by a
  /// non-colour disabled signal.
  final Color textDisabled;

  /// Behind sheets and dialogs (carries its own alpha).
  final Color scrim;

  /// Interaction: active states, primary actions, progress fill, focus
  /// ring. Amber marks what you can do; artwork supplies atmosphere.
  final Color accent;
  final Color onAccent;
  final Color accentContainer;
  final Color onAccentContainer;

  final Color success;
  final Color onSuccess;
  final Color error;
  final Color onError;

  final WaxDomainColors music;
  final WaxDomainColors podcasts;
  final WaxDomainColors audiobooks;
  final WaxDomainColors radio;

  /// Peak opacity for the artwork-derived radial glow behind players.
  /// Halved on OLED, where deep gradients band worst; zero in light,
  /// which expresses warmth as tinted paper instead of luminescence.
  final double glowOpacity;

  /// Opacity of the flat artwork-tinted wash used on entity headers, and
  /// on the light-mode player backdrop in place of a glow.
  final double washOpacity;

  /// The player backdrop's tiled grain. Full strength in dark and OLED
  /// (it is what hides gradient banding), absent in light.
  final double grainOpacity;

  bool get isDark => brightness == Brightness.dark;

  WaxDomainColors domain(WaxDomain domain) => switch (domain) {
    WaxDomain.music => music,
    WaxDomain.podcasts => podcasts,
    WaxDomain.audiobooks => audiobooks,
    WaxDomain.radio => radio,
  };

  /// The surface one step above [surface] in the elevation ladder, which
  /// is what hover and pressed states move to.
  Color raise(Color surface) {
    if (surface == canvas) return surface1;
    if (surface == surface1) return surface2;
    return surface3;
  }

  static WaxColors of(BuildContext context) =>
      Theme.of(context).extension<WaxColors>() ?? dark;

  /// Charcoal: warm neutral darks, amber interaction, artwork as light.
  static const WaxColors dark = WaxColors(
    brightness: Brightness.dark,
    canvas: Color(0xFF16130F),
    surface1: Color(0xFF1E1913),
    surface2: Color(0xFF262017),
    surface3: Color(0xFF2F271C),
    hairline: Color(0xFF3B3226),
    outline: Color(0xFF827057),
    textPrimary: Color(0xFFF3EDE3),
    textSecondary: Color(0xFFC7BCAA),
    textTertiary: Color(0xFF9A8E78),
    textDisabled: Color(0xFF6F6350),
    scrim: Color(0x8C000000),
    accent: Color(0xFFE3A244),
    onAccent: Color(0xFF221807),
    accentContainer: Color(0xFF4A3416),
    onAccentContainer: Color(0xFFF2CD8D),
    success: Color(0xFF5FBE7F),
    onSuccess: Color(0xFF08210F),
    error: Color(0xFFF2655A),
    onError: Color(0xFF221807),
    music: WaxDomainColors(
      hue: Color(0xFFE3A244),
      container: Color(0xFF4A3416),
      onContainer: Color(0xFFF2CD8D),
    ),
    podcasts: WaxDomainColors(
      hue: Color(0xFF3FB3A7),
      container: Color(0xFF173B37),
      onContainer: Color(0xFF3FB3A7),
    ),
    audiobooks: WaxDomainColors(
      hue: Color(0xFFA98BDB),
      container: Color(0xFF332843),
      onContainer: Color(0xFFA98BDB),
    ),
    radio: WaxDomainColors(
      hue: Color(0xFFE2574B),
      container: Color(0xFF48211D),
      onContainer: Color(0xFFE77167),
    ),
    glowOpacity: 0.24,
    washOpacity: 0.14,
    grainOpacity: 0.02,
  );

  /// Porcelain: paper and ink. Light is a co-equal expression of the
  /// identity, not a dimmed dark: where dark renders warmth as glow,
  /// light renders it as tinted paper stock, hard hairlines, and print
  /// shadows.
  static const WaxColors light = WaxColors(
    brightness: Brightness.light,
    canvas: Color(0xFFFAF9F6),
    surface1: Color(0xFFFFFFFF),
    surface2: Color(0xFFF2EFE9),
    surface3: Color(0xFFE9E4DA),
    hairline: Color(0xFFE2DCD1),
    outline: Color(0xFF8A8070),
    textPrimary: Color(0xFF1C1813),
    textSecondary: Color(0xFF5A5344),
    textTertiary: Color(0xFF6C6555),
    textDisabled: Color(0xFFA79D8C),
    scrim: Color(0x66241E14),
    accent: Color(0xFF8A5A12),
    onAccent: Color(0xFFFFFFFF),
    accentContainer: Color(0xFFF3E2C3),
    onAccentContainer: Color(0xFF5C3C09),
    success: Color(0xFF1D7443),
    onSuccess: Color(0xFFFFFFFF),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    music: WaxDomainColors(
      hue: Color(0xFF8A5A12),
      container: Color(0xFFF3E2C3),
      onContainer: Color(0xFF5C3C09),
    ),
    podcasts: WaxDomainColors(
      hue: Color(0xFF1B7A70),
      container: Color(0xFFD3EBE7),
      onContainer: Color(0xFF197269),
    ),
    audiobooks: WaxDomainColors(
      hue: Color(0xFF6A4BA6),
      container: Color(0xFFE7DFF5),
      onContainer: Color(0xFF6A4BA6),
    ),
    radio: WaxDomainColors(
      hue: Color(0xFFB03A30),
      container: Color(0xFFF7DAD6),
      onContainer: Color(0xFFB03A30),
    ),
    glowOpacity: 0,
    washOpacity: 0.10,
    grainOpacity: 0,
  );

  /// True black for OLED panels: dark with its neutrals substituted and
  /// its glow halved. The backdrop grain stays at full strength, because
  /// true-black gradients band worst and the grain is the cure.
  static const WaxColors oled = WaxColors(
    brightness: Brightness.dark,
    canvas: Color(0xFF000000),
    surface1: Color(0xFF120F0B),
    surface2: Color(0xFF1B1712),
    surface3: Color(0xFF241E16),
    hairline: Color(0xFF453B2C),
    outline: Color(0xFF827057),
    textPrimary: Color(0xFFF3EDE3),
    textSecondary: Color(0xFFC7BCAA),
    textTertiary: Color(0xFF9A8E78),
    textDisabled: Color(0xFF6F6350),
    scrim: Color(0x8C000000),
    accent: Color(0xFFE3A244),
    onAccent: Color(0xFF221807),
    accentContainer: Color(0xFF4A3416),
    onAccentContainer: Color(0xFFF2CD8D),
    success: Color(0xFF5FBE7F),
    onSuccess: Color(0xFF08210F),
    error: Color(0xFFF2655A),
    onError: Color(0xFF221807),
    music: WaxDomainColors(
      hue: Color(0xFFE3A244),
      container: Color(0xFF4A3416),
      onContainer: Color(0xFFF2CD8D),
    ),
    podcasts: WaxDomainColors(
      hue: Color(0xFF3FB3A7),
      container: Color(0xFF173B37),
      onContainer: Color(0xFF3FB3A7),
    ),
    audiobooks: WaxDomainColors(
      hue: Color(0xFFA98BDB),
      container: Color(0xFF332843),
      onContainer: Color(0xFFA98BDB),
    ),
    radio: WaxDomainColors(
      hue: Color(0xFFE2574B),
      container: Color(0xFF48211D),
      onContainer: Color(0xFFE77167),
    ),
    glowOpacity: 0.12,
    washOpacity: 0.14,
    grainOpacity: 0.02,
  );

  /// Only the accent family is ever overridden at runtime (artwork never
  /// touches these tokens: extracted colour is atmosphere, and rides
  /// `WaxAccent` instead).
  @override
  WaxColors copyWith({
    Color? accent,
    Color? onAccent,
    Color? accentContainer,
    Color? onAccentContainer,
  }) => WaxColors(
    brightness: brightness,
    canvas: canvas,
    surface1: surface1,
    surface2: surface2,
    surface3: surface3,
    hairline: hairline,
    outline: outline,
    textPrimary: textPrimary,
    textSecondary: textSecondary,
    textTertiary: textTertiary,
    textDisabled: textDisabled,
    scrim: scrim,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    accentContainer: accentContainer ?? this.accentContainer,
    onAccentContainer: onAccentContainer ?? this.onAccentContainer,
    success: success,
    onSuccess: onSuccess,
    error: error,
    onError: onError,
    music: music,
    podcasts: podcasts,
    audiobooks: audiobooks,
    radio: radio,
    glowOpacity: glowOpacity,
    washOpacity: washOpacity,
    grainOpacity: grainOpacity,
  );

  // ThemeData equality walks its extensions, and an extension without
  // value equality makes every rebuilt theme look like a new one.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WaxColors &&
          other.brightness == brightness &&
          other.canvas == canvas &&
          other.surface1 == surface1 &&
          other.surface2 == surface2 &&
          other.surface3 == surface3 &&
          other.hairline == hairline &&
          other.outline == outline &&
          other.textPrimary == textPrimary &&
          other.textSecondary == textSecondary &&
          other.textTertiary == textTertiary &&
          other.textDisabled == textDisabled &&
          other.scrim == scrim &&
          other.accent == accent &&
          other.onAccent == onAccent &&
          other.accentContainer == accentContainer &&
          other.onAccentContainer == onAccentContainer &&
          other.success == success &&
          other.error == error &&
          other.music == music &&
          other.podcasts == podcasts &&
          other.audiobooks == audiobooks &&
          other.radio == radio &&
          other.glowOpacity == glowOpacity &&
          other.washOpacity == washOpacity &&
          other.grainOpacity == grainOpacity;

  @override
  int get hashCode => Object.hashAll(<Object>[
    brightness,
    canvas,
    surface1,
    surface2,
    surface3,
    hairline,
    outline,
    textPrimary,
    textSecondary,
    textTertiary,
    textDisabled,
    scrim,
    accent,
    onAccent,
    accentContainer,
    onAccentContainer,
    success,
    error,
    music,
    podcasts,
    audiobooks,
    radio,
    glowOpacity,
    washOpacity,
    grainOpacity,
  ]);

  @override
  WaxColors lerp(covariant WaxColors? other, double t) {
    if (other == null) return this;
    return WaxColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface1: Color.lerp(surface1, other.surface1, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      accentContainer: Color.lerp(accentContainer, other.accentContainer, t)!,
      onAccentContainer: Color.lerp(
        onAccentContainer,
        other.onAccentContainer,
        t,
      )!,
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      error: Color.lerp(error, other.error, t)!,
      onError: Color.lerp(onError, other.onError, t)!,
      music: WaxDomainColors.lerp(music, other.music, t),
      podcasts: WaxDomainColors.lerp(podcasts, other.podcasts, t),
      audiobooks: WaxDomainColors.lerp(audiobooks, other.audiobooks, t),
      radio: WaxDomainColors.lerp(radio, other.radio, t),
      glowOpacity: glowOpacity + (other.glowOpacity - glowOpacity) * t,
      washOpacity: washOpacity + (other.washOpacity - washOpacity) * t,
      grainOpacity: grainOpacity + (other.grainOpacity - grainOpacity) * t,
    );
  }
}
