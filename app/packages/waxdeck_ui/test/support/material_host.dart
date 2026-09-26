import 'package:waxdeck_ui/waxdeck_ui.dart';

/// The theme, Material and localizations a golden's widgets look up.
/// Alchemist wraps every golden in the SDK's own, which are other types
/// to material_ui's widgets.
Widget materialHost(ThemeData theme, Widget child) => Localizations(
  locale: const Locale('en', 'US'),
  delegates: waxLocalizationsDelegates,
  child: Theme(
    data: theme,
    child: Material(type: MaterialType.transparency, child: child),
  ),
);
