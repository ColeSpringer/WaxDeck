import 'package:waxdeck/src/l10n/l10n.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// Hosts one widget with the app's localization delegates installed.
///
/// A test written as a bare `MaterialApp(home:)` installs no delegates,
/// so anything reaching for `context.l10n` throws there rather than
/// rendering. This is that host with the delegates on: use it for a
/// screen that draws its own copy, and `routedHost` for one that
/// navigates.
Widget localizedHost(
  Widget child, {
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) {
  return MaterialApp(
    locale: locale,
    theme: theme,
    localizationsDelegates: waxLocalizationsDelegates,
    supportedLocales: waxSupportedLocales,
    home: child,
  );
}
