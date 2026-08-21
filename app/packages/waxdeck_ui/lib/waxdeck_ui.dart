/// WaxDeck's design system: tokens, themes, and the components every
/// client screen composes.
///
/// This library re-exports `package:flutter/material.dart`, and the house
/// rule for all new client code is to import
/// `package:waxdeck_ui/waxdeck_ui.dart` only. Material's canonical home
/// is moving to the `material_ui` package; routing every screen's import
/// through this one line makes that migration a dependency swap here
/// rather than a sweep across hundreds of files.
library;

export 'package:flutter/material.dart';

export 'src/color/contrast.dart';
export 'src/components/artwork.dart';
export 'src/components/backdrop.dart';
export 'src/components/banner.dart';
export 'src/components/car_mode.dart';
export 'src/components/cards.dart';
export 'src/components/command_palette.dart';
export 'src/components/console.dart';
export 'src/components/controls.dart';
export 'src/components/deck_bar.dart';
export 'src/components/document_dialog.dart';
export 'src/components/entity_header.dart';
export 'src/components/fast_scroll.dart';
export 'src/components/indicators.dart';
export 'src/components/inputs.dart';
export 'src/components/lyrics.dart';
export 'src/components/mini_player.dart';
export 'src/components/navigation.dart';
export 'src/components/panel.dart';
export 'src/components/player_scaffold.dart';
export 'src/components/reading_column.dart';
export 'src/components/scaffold.dart';
export 'src/components/semantics_slots.dart';
export 'src/components/settings.dart';
export 'src/components/splitter.dart';
export 'src/components/states.dart';
export 'src/components/station_dial.dart';
export 'src/components/view_data.dart';
export 'src/components/visualizer.dart';
export 'src/components/wordmark.dart';
export 'src/l10n/wax_l10n.dart';
export 'src/color/palette.dart';
export 'src/color/palette_extractor.dart';
export 'src/fonts/wax_fonts.dart';
export 'src/icons/wax_icon.dart';
export 'src/theme/theme_builder.dart';
export 'src/theme/wax_accent.dart';
export 'src/theme/wax_layout.dart';
export 'src/tokens/breakpoints.dart';
export 'src/tokens/colors.dart';
export 'src/tokens/density.dart';
export 'src/tokens/elevation.dart';
export 'src/tokens/motion.dart';
export 'src/tokens/radii.dart';
export 'src/tokens/spacing.dart';
export 'src/tokens/typography.dart';
