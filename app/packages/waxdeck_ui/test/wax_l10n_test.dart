import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// The design system's own copy, and the fallback that lets every other
/// test in this package go on pumping a bare `MaterialApp`.
void main() {
  group('WaxLocalizations resolution', () {
    testWidgets('a host with no delegate gets English', (tester) async {
      late WaxLocalizations resolved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              resolved = context.waxL10n;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(resolved.commonPlay, 'Play');
    });

    testWidgets('a host that installed the delegate gets its locale', (
      tester,
    ) async {
      late WaxLocalizations resolved;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: WaxLocalizations.localizationsDelegates,
          supportedLocales: WaxLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              resolved = context.waxL10n;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(resolved.commonPlay, 'Reproducir');
    });

    testWidgets('a component draws the host locale', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: WaxLocalizations.localizationsDelegates,
          supportedLocales: WaxLocalizations.supportedLocales,
          home: Scaffold(
            body: ErrorState(message: 'No hay red.', onRetry: () {}),
          ),
        ),
      );
      expect(find.text('Algo no se ha cargado'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });

    test('every supported locale resolves a table', () {
      for (final locale in WaxLocalizations.supportedLocales) {
        expect(
          lookupWaxLocalizations(locale).commonPlay,
          isNotEmpty,
          reason: '$locale has no table',
        );
      }
    });
  });

  group('formatSpan', () {
    final en = lookupWaxLocalizations(const Locale('en'));
    final es = lookupWaxLocalizations(const Locale('es'));

    test('answers how much, not what time it is', () {
      expect(en.formatSpan(const Duration(hours: 6)), '6 hr');
      expect(
        en.formatSpan(const Duration(hours: 1, minutes: 20)),
        '1 hr 20 min',
      );
      expect(en.formatSpan(const Duration(minutes: 45)), '45 min');
      // Minutes are noise past ten hours, and a span under a minute is
      // still a minute rather than none.
      expect(en.formatSpan(const Duration(hours: 12, minutes: 40)), '12 hr');
      expect(en.formatSpan(const Duration(seconds: 20)), '1 min');
      expect(en.formatSpan(Duration.zero), '1 min');
    });

    test('keeps its thresholds in another language', () {
      expect(es.formatSpan(const Duration(hours: 6)), '6 h');
      expect(
        es.formatSpan(const Duration(hours: 1, minutes: 20)),
        '1 h 20 min',
      );
      expect(es.formatSpan(const Duration(hours: 12, minutes: 40)), '12 h');
      expect(es.formatSpan(Duration.zero), '1 min');
    });
  });

  group('spellDuration', () {
    final en = lookupWaxLocalizations(const Locale('en'));
    final es = lookupWaxLocalizations(const Locale('es'));

    test('names every unit, and drops seconds past an hour', () {
      expect(en.spellDuration(Duration.zero), '0 seconds');
      expect(en.spellDuration(const Duration(seconds: 1)), '1 second');
      expect(en.spellDuration(const Duration(seconds: 59)), '59 seconds');
      expect(en.spellDuration(const Duration(minutes: 1)), '1 minute');
      expect(
        en.spellDuration(const Duration(minutes: 2, seconds: 41)),
        '2 minutes 41 seconds',
      );
      expect(en.spellDuration(const Duration(hours: 10)), '10 hours');
      expect(
        en.spellDuration(const Duration(hours: 8, minutes: 2, seconds: 30)),
        '8 hours 2 minutes',
      );
    });

    test('agrees with itself in another language', () {
      expect(es.spellDuration(const Duration(seconds: 1)), '1 segundo');
      expect(
        es.spellDuration(const Duration(minutes: 2, seconds: 41)),
        '2 minutos 41 segundos',
      );
      expect(
        es.spellDuration(const Duration(hours: 8, minutes: 2)),
        '8 horas 2 minutos',
      );
    });
  });

  group('formatTimecode', () {
    test('draws digits, which no language changes', () {
      expect(formatTimecode(const Duration(minutes: 4, seconds: 5)), '4:05');
      expect(
        formatTimecode(const Duration(hours: 1, minutes: 2, seconds: 41)),
        '1:02:41',
      );
    });
  });
}
