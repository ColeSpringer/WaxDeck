import 'package:intl/intl.dart';

import 'gen/app_localizations.dart';

/// The app's numbers and dates, worded once.
///
/// Every one of these was a private helper on the screen that needed it -
/// nine of them padding a year, a month and a day into `2026-08-12`, three
/// families of relative phrase, one byte formatter - and each was
/// locale-blind by construction. On the table so that a screen reads
/// `context.l10n.formatStamp(row.at)` and gets whatever this locale does
/// with a date.
///
/// The split of labour: a date or a time is CLDR's, through `DateFormat`,
/// because nobody should be writing month names into an ARB. A phrase
/// with a unit word in it - "12 min ago", "1.5 GB" - is the translator's,
/// because the word order and the unit itself are language, not
/// arithmetic. Timecodes are neither and stay in the design system, which
/// draws digits and a colon in every language.
///
/// Instants against calendar days: everything here takes an instant and
/// draws it in local time, except the `*OnDay` pair, which takes a field
/// the contract types as a date and leaves it alone. Reading a date-only
/// field in local time moves it: the wire carries `2026-08-12`, the
/// decoder makes it UTC midnight, and west of Greenwich `toLocal` lands
/// it on the eleventh.
extension WaxFormats on AppLocalizations {
  /// A calendar day: "Aug 12, 2026".
  ///
  /// In local time, because the server speaks UTC and a listener does
  /// not. For a field the contract types as a date rather than an
  /// instant, [formatDateOnDay].
  String formatDate(DateTime at) =>
      _dateFormat(localeName).format(at.toLocal());

  /// A day and the time of day: "Aug 12, 2026 3:04 PM".
  String formatStamp(DateTime at) =>
      _stampFormat(localeName).format(at.toLocal());

  /// A day without its year: "Aug 12".
  ///
  /// For a list whose rows are read in the order they arrived, where the
  /// year is the same on almost all of them and saying it every time is
  /// noise.
  String formatMonthDay(DateTime at) =>
      _monthDayFormat(localeName).format(at.toLocal());

  /// A day without its year, in digits: "8/12".
  ///
  /// For a chart axis, which has a few characters and no room for a
  /// month's name.
  String formatMonthDayNumeric(DateTime at) =>
      _numericFormat(localeName).format(at.toLocal());

  /// A calendar day the contract already resolved: "Aug 12, 2026".
  ///
  /// Drawn as it arrived. A `format: date` field is a day the server
  /// already worked out in the caller's timezone, so there is no instant
  /// here to convert and converting one moves the answer.
  String formatDateOnDay(DateTime day) => _dateFormat(localeName).format(day);

  /// The same day without its year, in digits: "8/12".
  String formatMonthDayNumericOnDay(DateTime day) =>
      _numericFormat(localeName).format(day);

  /// How long ago, abbreviated hard: "just now", "3m ago", "2h ago",
  /// "5d ago", "3mo ago".
  ///
  /// For the audit log, whose column is narrow and whose reader is
  /// scanning a page of rows rather than reading one. [now] is for tests;
  /// production reads the clock.
  String relativeCompact(DateTime at, {DateTime? now}) {
    final delta = (now ?? DateTime.now().toUtc()).difference(at.toUtc());
    if (delta.inMinutes < 1) return relJustNow;
    if (delta.inHours < 1) return relMinutesShort(delta.inMinutes);
    if (delta.inDays < 1) return relHoursShort(delta.inHours);
    if (delta.inDays < 30) return relDaysShort(delta.inDays);
    return relMonthsShort(delta.inDays ~/ 30);
  }

  /// How long ago, with room to breathe: "just now", "12 min ago",
  /// "3 h ago", "2 d ago".
  ///
  /// For the dashboard's tiles, which have a line each. A negative delta
  /// - a server clock a little ahead of this one - reads as just now
  /// rather than as a time in the future.
  String relativeSpaced(DateTime at, {DateTime? now}) {
    final delta = (now ?? DateTime.now()).difference(at);
    if (delta.isNegative) return relJustNow;
    if (delta.inHours < 1) return relMinutesAgo(delta.inMinutes);
    if (delta.inHours < 24) return relHoursAgo(delta.inHours);
    return relDaysAgo(delta.inDays);
  }

  /// How long until: "due now", "in 12 min", "in 3 h", "in 2 d".
  ///
  /// The forward half of [relativeSpaced], in the same shape, for a
  /// schedule's next run.
  String relativeUntil(DateTime at, {DateTime? now}) {
    final delta = at.difference(now ?? DateTime.now());
    if (delta.isNegative) return relDueNow;
    if (delta.inHours < 1) return relInMinutes(delta.inMinutes);
    if (delta.inHours < 24) return relInHours(delta.inHours);
    return relInDays(delta.inDays);
  }

  /// A wait as words: "6 hours", "1 day", "3 days".
  ///
  /// Days once the hours divide evenly into them: a week offered as
  /// "168 hours" is a number the reader has to do arithmetic on. Seconds
  /// and minutes are the design system's `spellDuration`, which every
  /// other duration on a control already goes through; this one is here
  /// because days are past where that stops.
  String spellHours(int hours) => hours >= 24 && hours % 24 == 0
      ? durationDays(hours ~/ 24)
      : durationHours(hours);

  /// The single letters a chart labels its months with, by month index
  /// from zero: CLDR's standalone narrow forms rather than a hand-kept
  /// table, since Spanish starts the year with E. Cached whole.
  Map<int, String> monthInitials() => _monthInitialsFor(localeName);

  /// A span in the tightest form a tile or a trailing column can hold:
  /// "2h 6m", "45s". Not `formatSpan`, which spells its units out.
  /// Episode durations share it; two copies were two sets of letters.
  String formatListenTime(int ms) {
    final span = Duration(milliseconds: ms);
    if (span.inHours > 0) {
      return durationHoursMinutesShort(
        span.inHours,
        span.inMinutes.remainder(60),
      );
    }
    if (span.inMinutes > 0) return durationMinutesShort(span.inMinutes);
    return durationSecondsShort(span.inSeconds);
  }

  /// A playback rate: "1x", "1.2x", never "1.0x".
  ///
  /// The separator is the locale's and the trailing zeros go, which is
  /// what intl's decimal pattern does by itself - the same shape the
  /// hand-trimmed `toStringAsFixed` drew, in every language rather than
  /// in English alone.
  String formatSpeed(double speed) =>
      speedMultiplier(_speedFormat(localeName).format(speed));

  /// A size in the largest unit that leaves a number worth reading:
  /// "512 B", "640 KB", "12.4 MB", "1.5 GB".
  ///
  /// Shared by every surface that shows one (quota, backups, trash,
  /// delete plans) so they can never drift apart in style.
  String formatBytes(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) return bytesGb(bytes / gb);
    if (bytes >= mb) return bytesMb(bytes / mb);
    // Rounded rather than truncated, and to a whole number: a kilobyte
    // count with a decimal on it is three digits of noise.
    if (bytes >= kb) return bytesKb((bytes / kb).round());
    return bytesB(bytes);
  }
}

/// The four patterns this app draws, one instance per locale.
///
/// Constructing a `DateFormat` parses its skeleton and verifies its
/// locale, which intl's own source calls an expensive operation and does
/// not cache; these are built inside list builders, so a table of a
/// hundred rows built one per cell. Keyed by locale name rather than held
/// in a single field, because the picker can change it under a running
/// app and a stale formatter would go on drawing the old language.
final Map<String, DateFormat> _dateCache = <String, DateFormat>{};
final Map<String, DateFormat> _stampCache = <String, DateFormat>{};
final Map<String, DateFormat> _monthDayCache = <String, DateFormat>{};
final Map<String, DateFormat> _numericCache = <String, DateFormat>{};
final Map<String, DateFormat> _monthInitialCache = <String, DateFormat>{};

/// The standalone narrow month, which is the axis label's case: `LLLLL`
/// rather than `MMMMM`, because a label stands on its own rather than
/// inside a date.
DateFormat _monthInitialFormat(String locale) =>
    _monthInitialCache[locale] ??= DateFormat('LLLLL', locale);

final Map<String, Map<int, String>> _monthInitialsCache =
    <String, Map<int, String>>{};

Map<int, String> _monthInitialsFor(String locale) =>
    _monthInitialsCache[locale] ??= Map<int, String>.unmodifiable(<int, String>{
      for (var month = 1; month <= 12; month++)
        month - 1: _monthInitialFormat(locale).format(DateTime(2000, month)),
    });

/// The one number pattern, held for the same reason and keyed the same
/// way. Trailing zeros are dropped by the pattern itself, so 1.0 reads
/// "1" and 1.5 reads "1,5" where that is how a decimal is written.
final Map<String, NumberFormat> _speedCache = <String, NumberFormat>{};

NumberFormat _speedFormat(String locale) =>
    _speedCache.putIfAbsent(locale, () => NumberFormat.decimalPattern(locale));

DateFormat _dateFormat(String locale) =>
    _dateCache.putIfAbsent(locale, () => DateFormat.yMMMd(locale));

DateFormat _stampFormat(String locale) =>
    _stampCache.putIfAbsent(locale, () => DateFormat.yMMMd(locale).add_jm());

DateFormat _monthDayFormat(String locale) =>
    _monthDayCache.putIfAbsent(locale, () => DateFormat.MMMd(locale));

DateFormat _numericFormat(String locale) =>
    _numericCache.putIfAbsent(locale, () => DateFormat.Md(locale));
