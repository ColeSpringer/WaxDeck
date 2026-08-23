import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:waxdeck/src/l10n/l10n.dart';

/// The app's dates, relative phrases, and byte sizes, at both locales.
///
/// `initializeDateFormatting` is here and nowhere in the app: the global
/// Material delegate loads the symbols for every bundled locale as it
/// resolves, and these tests bypass it by looking the table up directly.
void main() {
  late AppLocalizations en;
  late AppLocalizations es;

  setUpAll(() async {
    await initializeDateFormatting();
    en = await AppLocalizations.delegate.load(const Locale('en'));
    es = await AppLocalizations.delegate.load(const Locale('es'));
  });

  group('dates', () {
    final at = DateTime(2026, 8, 12, 15, 4);

    test('a day reads as a day, not as an ISO stamp', () {
      expect(en.formatDate(at), 'Aug 12, 2026');
      expect(es.formatDate(at), '12 ago 2026');
    });

    test('the es month abbreviations the server pages hand-copy hold', () {
      // server/internal/pagetext/es.go copies these from intl, so the
      // share and status pages agree with the app; an intl bump that
      // moves one has to move both, and this is what reds first.
      const copied = [
        'ene',
        'feb',
        'mar',
        'abr',
        'may',
        'jun',
        'jul',
        'ago',
        'sept',
        'oct',
        'nov',
        'dic',
      ];
      for (var month = 1; month <= 12; month++) {
        expect(
          es.formatDate(DateTime(2026, month, 3)),
          '3 ${copied[month - 1]} 2026',
        );
      }
    });

    test('a stamp carries the time of day', () {
      // The gap before the meridiem is CLDR's narrow no-break space, not
      // a plain one. Pinned here because it is invisible in a diff and a
      // `find.text` written with a space would never match.
      expect(en.formatStamp(at), 'Aug 12, 2026 3:04 PM');
      // Spanish is a 24-hour locale, which is the whole reason this is
      // CLDR's job rather than a padLeft.
      expect(es.formatStamp(at), '12 ago 2026 15:04');
    });

    test('a day without its year keeps both shapes', () {
      expect(en.formatMonthDay(at), 'Aug 12');
      expect(en.formatMonthDayNumeric(at), '8/12');
      expect(es.formatMonthDay(at), '12 ago');
      expect(es.formatMonthDayNumeric(at), '12/8');
    });
  });

  group('relative phrases', () {
    final now = DateTime.utc(2026, 8, 12, 12);
    DateTime ago(Duration d) => now.subtract(d);

    test('the compact family, as the audit log draws it', () {
      expect(en.relativeCompact(ago(Duration.zero), now: now), 'just now');
      expect(
        en.relativeCompact(ago(const Duration(seconds: 30)), now: now),
        'just now',
      );
      expect(
        en.relativeCompact(ago(const Duration(minutes: 3)), now: now),
        '3m ago',
      );
      expect(
        en.relativeCompact(ago(const Duration(hours: 2)), now: now),
        '2h ago',
      );
      expect(
        en.relativeCompact(ago(const Duration(days: 3)), now: now),
        '3d ago',
      );
      // Thirty days is the boundary: a month, not thirty days.
      expect(
        en.relativeCompact(ago(const Duration(days: 29)), now: now),
        '29d ago',
      );
      expect(
        en.relativeCompact(ago(const Duration(days: 30)), now: now),
        '1mo ago',
      );
      expect(
        en.relativeCompact(ago(const Duration(days: 400)), now: now),
        '13mo ago',
      );
    });

    test('the spaced family, as the dashboard draws it', () {
      expect(
        en.relativeSpaced(ago(const Duration(minutes: 12)), now: now),
        '12 min ago',
      );
      expect(
        en.relativeSpaced(ago(const Duration(hours: 3)), now: now),
        '3 h ago',
      );
      expect(
        en.relativeSpaced(ago(const Duration(days: 2)), now: now),
        '2 d ago',
      );
      // A server clock a little ahead of this one is not the future.
      expect(
        en.relativeSpaced(now.add(const Duration(minutes: 5)), now: now),
        'just now',
      );
    });

    test('the forward family, as a schedule draws it', () {
      expect(
        en.relativeUntil(now.subtract(const Duration(minutes: 1)), now: now),
        'due now',
      );
      expect(
        en.relativeUntil(now.add(const Duration(minutes: 12)), now: now),
        'in 12 min',
      );
      expect(
        en.relativeUntil(now.add(const Duration(hours: 3)), now: now),
        'in 3 h',
      );
      expect(
        en.relativeUntil(now.add(const Duration(days: 2)), now: now),
        'in 2 d',
      );
    });

    test('another language puts the same phrases the other way round', () {
      expect(es.relativeCompact(ago(Duration.zero), now: now), 'ahora mismo');
      expect(
        es.relativeCompact(ago(const Duration(hours: 2)), now: now),
        'hace 2 h',
      );
      expect(
        es.relativeSpaced(ago(const Duration(minutes: 12)), now: now),
        'hace 12 min',
      );
      expect(
        es.relativeUntil(now.add(const Duration(days: 2)), now: now),
        'en 2 d',
      );
    });
  });

  group('bytes', () {
    test('the largest unit that leaves a number worth reading', () {
      expect(en.formatBytes(0), '0 B');
      expect(en.formatBytes(1), '1 B');
      expect(en.formatBytes(1024), '1 KB');
      expect(en.formatBytes(640 * 1024), '640 KB');
      expect(en.formatBytes(1024 * 1024), '1.0 MB');
      expect(en.formatBytes((12.4 * 1024 * 1024).round()), '12.4 MB');
      expect(en.formatBytes(1024 * 1024 * 1024), '1.0 GB');
      expect(en.formatBytes((1.5 * 1024 * 1024 * 1024).round()), '1.5 GB');
    });

    test('every unit groups, or none of them would agree', () {
      // Each unit's band runs to 1023, so all four reach four digits and
      // a screen showing two of them would otherwise draw one grouped
      // and one not.
      expect(en.formatBytes(1023), '1,023 B');
      expect(en.formatBytes(1023 * 1024), '1,023 KB');
      expect(en.formatBytes(1023 * 1024 * 1024), '1,023.0 MB');
    });

    test('the separators follow the locale', () {
      expect(es.formatBytes((12.4 * 1024 * 1024).round()), '12,4 MB');
      expect(es.formatBytes(640 * 1024), '640 KB');
      // Spanish groups with a period where English uses a comma, which
      // is the whole reason this is a number format rather than a
      // toStringAsFixed.
      expect(es.formatBytes(1023 * 1024), '1.023 KB');
    });
  });
}
