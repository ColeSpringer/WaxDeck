import 'package:flutter/widgets.dart';
import 'package:intl/locale.dart' as intl;
import 'package:waxdeck_ui/waxdeck_ui.dart' show WaxLocalizations;

import 'explain_error.dart';
import 'gen/app_localizations.dart';

export 'explain_error.dart';
export 'formats.dart';
export 'gen/app_localizations.dart';

/// The single import for the app's copy: `context.l10n.<key>`.
///
/// Non-widget code never reaches through a BuildContext for this. A
/// controller hands the widget layer a code, a token, or a value, and the
/// leaf that draws it is what localizes.
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// The one sentence an error surface shows. See [explainError]: the
  /// boundary is the code, and the server's message is the fallback.
  String explain(Object error) => explainError(l10n, error);
}

/// Every delegate a WaxDeck host installs, in one list so the app and
/// the test hosts cannot drift apart.
///
/// The design system's table rides here too. Without it the components
/// still draw - `context.waxL10n` answers English when no delegate is
/// installed, which is what keeps the package's own tests plain - so its
/// absence in a host would show only as a Spanish screen with English
/// buttons on it.
const List<LocalizationsDelegate<dynamic>> waxLocalizationsDelegates =
    <LocalizationsDelegate<dynamic>>[
      ...AppLocalizations.localizationsDelegates,
      WaxLocalizations.delegate,
    ];

/// The locales the app offers, English first by construction.
///
/// `basicLocaleListResolution` falls back to `supportedLocales.first`,
/// and gen-l10n emits its list alphabetically: correct today, because
/// en sorts before es, and silently wrong the day a ca or de ARB lands.
/// Pinning it here makes the accident a contract instead.
///
/// Only plain `en` is hoisted: an `en_GB` ARB is a locale of its own,
/// and dropping it would resolve a British device to the template it
/// was written to differ from.
final List<Locale> waxSupportedLocales = List<Locale>.unmodifiable([
  const Locale('en'),
  ...AppLocalizations.supportedLocales.where((l) => l != const Locale('en')),
]);

/// What each supported language calls itself.
///
/// Not in the ARB, and beside the list it names rather than in the
/// screen that draws it: a language names itself the same on every
/// screen, and a Spanish reader looking for Spanish on an English
/// interface is looking for "Español". A locale missing from here falls
/// back to its own tag, which `settings_screen_test.dart` asserts never
/// happens for a locale [waxSupportedLocales] offers.
const Map<String, String> languageEndonyms = <String, String>{
  'en': 'English',
  'es': 'Español',
};

/// A stored BCP 47 tag as a Flutter Locale, via intl's parser (dart:ui
/// has no Locale.parse). An unparseable tag answers null: follow the
/// system rather than force a garbage locale.
Locale? localeFromTag(String tag) {
  final parsed = intl.Locale.tryParse(tag);
  if (parsed == null) return null;
  return Locale.fromSubtags(
    languageCode: parsed.languageCode,
    scriptCode: parsed.scriptCode,
    countryCode: parsed.countryCode,
  );
}

/// The locale this build would draw for a stored tag, or null where it
/// would draw none of them.
///
/// `es-MX` is a Spanish this build has and resolves to `es`; `fr` is not
/// a language it has at all. The difference matters because
/// `MaterialApp.locale` is a pin rather than a preference: a locale set
/// there is resolved on its own and the device's own languages are never
/// consulted (`widgets/localizations.dart`, where a non-null locale
/// resolves as a one-element list). Pinning a tag this build cannot draw
/// would answer a Spanish device in English and call it the listener's
/// choice, so an unresolvable tag answers null and the system decides.
Locale? supportedLocaleFor(String tag) {
  final parsed = localeFromTag(tag);
  if (parsed == null) return null;
  final resolved = basicLocaleListResolution(<Locale>[
    parsed,
  ], waxSupportedLocales);
  // Resolution always answers something - the first supported locale is
  // its fallback - so what says a tag was understood is that the answer
  // is in the language that was asked for.
  return resolved.languageCode == parsed.languageCode ? resolved : null;
}
