import 'package:flutter/widgets.dart';

import 'gen/wax_localizations.dart';

export 'gen/wax_localizations.dart';

/// The English table, resolved once and held: it is the fallback below,
/// so it is asked for on most frames of most tests.
final WaxLocalizations _english = lookupWaxLocalizations(const Locale('en'));

/// The design system's own strings, the way `MaterialLocalizations`
/// serves Material's.
///
/// The components carry copy nobody can pass in - the accessibility
/// names on the deck bar's transport, the words the duration formatters
/// spell - so the package owns a table rather than pushing eighty
/// parameters up through every component API.
///
/// Resolves through `Localizations` when the host installed
/// [WaxLocalizations.delegate], and answers English when it did not, so a
/// bare `MaterialApp(home:)` pump renders exactly what it always has.
/// That fallback is what keeps the goldens and the widget tests of this
/// package free of localization setup.
extension WaxL10nX on BuildContext {
  WaxLocalizations get waxL10n =>
      Localizations.of<WaxLocalizations>(this, WaxLocalizations) ?? _english;
}

/// Durations as words.
///
/// Both forms are copy rather than arithmetic - the unit names, whether a
/// unit is abbreviated, and how two of them join are all the
/// translator's - so they live on the table. What stays numeric is
/// `formatTimecode`, which draws digits and a colon in every language.
extension WaxDurations on WaxLocalizations {
  /// A duration as a span rather than as a position: "6 hr",
  /// "1 hr 20 min", "45 min".
  ///
  /// For the readouts that answer "how much", where a timecode answers
  /// the wrong question - an audiobook with "7:50:12" left is telling you
  /// a clock time. Minutes are dropped past ten hours, where they are
  /// noise, and a span under a minute rounds up rather than reading
  /// "0 min".
  ///
  /// Abbreviated on purpose, because it lives in captions and cells that
  /// have room for a few characters. What a screen reader should hear is
  /// [spellDuration]; the components that draw one carry both.
  String formatSpan(Duration d) {
    final total = d.inSeconds.abs();
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    if (hours == 0) return spanMinutes(minutes == 0 ? 1 : minutes);
    if (minutes == 0 || hours >= 10) return spanHours(hours);
    return spanHoursMinutes(spanHours(hours), spanMinutes(minutes));
  }

  /// Spells a duration for screen readers and for prose: "2 minutes
  /// 41 seconds", "8 hours 2 minutes".
  ///
  /// Every unit is named and hours are their own step: this is the only
  /// positional feedback a screen-reader user gets, and an audiobook read
  /// as "482 minutes 13" is not feedback.
  String spellDuration(Duration d) {
    final total = d.inSeconds.abs();
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;

    if (hours > 0) {
      // Seconds are noise at this scale, and a screen reader reads every
      // word of them.
      return minutes == 0
          ? durationHours(hours)
          : durationHoursMinutes(
              durationHours(hours),
              durationMinutes(minutes),
            );
    }
    if (minutes == 0) return durationSeconds(seconds);
    if (seconds == 0) return durationMinutes(minutes);
    return durationMinutesSeconds(
      durationMinutes(minutes),
      durationSeconds(seconds),
    );
  }
}

/// A proportion, as the level controls announce it.
///
/// One place because two of them needed it and copied each other: a
/// slider says how loud, a splitter says how far along its travel, and
/// both are a fraction spoken as a percentage. The sign's spacing is
/// the translator's - Spanish puts one before it - which is the half
/// that made this worth a table entry rather than an interpolation.
extension WaxProportions on WaxLocalizations {
  String spellPercent(double fraction) =>
      percentOf((fraction.clamp(0.0, 1.0) * 100).round());
}
