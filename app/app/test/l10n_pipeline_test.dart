import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/l10n/l10n.dart';
import 'package:waxdeck/src/l10n/locale_warmup.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/prefs_controller.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';

const _user = WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']);

void main() {
  group('localeFromTag', () {
    test('reads the subtags a BCP 47 tag carries', () {
      expect(localeFromTag('en'), const Locale('en'));
      expect(localeFromTag('es'), const Locale('es'));
      final brazil = localeFromTag('pt-BR')!;
      expect(brazil.languageCode, 'pt');
      expect(brazil.countryCode, 'BR');
      expect(brazil.scriptCode, isNull);
      final taiwan = localeFromTag('zh-Hant-TW')!;
      expect(taiwan.languageCode, 'zh');
      expect(taiwan.scriptCode, 'Hant');
      expect(taiwan.countryCode, 'TW');
    });

    test('answers null for a tag it cannot parse', () {
      // Null is the answer that follows the system. Forcing a garbage
      // locale would leave the interface in a language nobody chose.
      expect(localeFromTag('not a tag'), isNull);
      expect(localeFromTag('***'), isNull);
      expect(localeFromTag(''), isNull);
    });
  });

  group('supported locales', () {
    test('English is first, so the fallback is not alphabetical luck', () {
      expect(waxSupportedLocales.first, const Locale('en'));
      expect(
        waxSupportedLocales.toSet(),
        AppLocalizations.supportedLocales.toSet(),
      );
    });

    test('the design system speaks every language the app offers', () {
      // Nothing else reports this. `context.waxL10n` answers English
      // when a locale has no table of its own, precisely so the
      // package's own tests can pump a bare MaterialApp - so an ARB
      // added to app/app alone would render every screen in the new
      // language with English transport buttons and error panes, and no
      // test would fail. This is that test.
      expect(
        WaxLocalizations.supportedLocales.toSet(),
        AppLocalizations.supportedLocales.toSet(),
        reason:
            'a locale the app offers and the design system has no ARB for '
            'renders its components in English; add the matching '
            'app/packages/waxdeck_ui/lib/src/l10n/arb/wax_<locale>.arb',
      );
    });

    test('resolution lands on es for a Spanish variant and en otherwise', () {
      // The list the app actually passes, run through the resolver
      // MaterialApp uses when no localeResolutionCallback is set.
      Locale resolve(List<Locale> preferred) =>
          basicLocaleListResolution(preferred, waxSupportedLocales);

      expect(resolve(const [Locale('es', 'MX')]), const Locale('es'));
      expect(resolve(const [Locale('es')]), const Locale('es'));
      expect(resolve(const [Locale('fr')]), const Locale('en'));
      expect(resolve(const [Locale('fr'), Locale('es')]), const Locale('es'));
      expect(resolve(const []), const Locale('en'));
    });
  });

  group('localeOverrideProvider', () {
    Future<Locale?> resolve(Prefs stored) async {
      final repo = FakeRepository()
        ..sessionState = const SessionState(authenticated: true, user: _user)
        ..prefs = stored;
      final container = ProviderContainer(
        overrides: [repositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      await container.read(prefsControllerProvider.future);
      return container.read(localeOverrideProvider);
    }

    test('a stored tag overrides the system', () async {
      expect(await resolve(const Prefs(locale: 'es')), const Locale('es'));
    });

    test('absent, empty, or unparseable all follow the system', () async {
      expect(await resolve(const Prefs()), isNull);
      expect(await resolve(const Prefs(locale: '')), isNull);
      expect(await resolve(const Prefs(locale: 'not a tag')), isNull);
    });
  });

  group('LocaleFontWarmup', () {
    testWidgets('warms once per resolved locale, with that locale\'s sample', (
      tester,
    ) async {
      final warmed = <String>[];
      Widget host(Locale locale) => MaterialApp(
        locale: locale,
        localizationsDelegates: waxLocalizationsDelegates,
        supportedLocales: waxSupportedLocales,
        home: LocaleFontWarmup(
          warm: (sample) async => warmed.add(sample),
          child: const SizedBox.shrink(),
        ),
      );

      await tester.pumpWidget(host(const Locale('en')));
      expect(warmed, ['Music, podcasts, and audiobooks.']);

      // A rebuild at the same locale has nothing new to load.
      await tester.pumpWidget(host(const Locale('en')));
      expect(warmed, hasLength(1));

      await tester.pumpWidget(host(const Locale('es')));
      expect(warmed, hasLength(2));
      expect(warmed.last, 'Música, pódcasts y audiolibros.');
    });

    testWidgets('resolves the locale from inside MaterialApp.builder', (
      tester,
    ) async {
      // Where the app installs it. Localizations wraps the builder's
      // subtree in this SDK; if that ever inverts, the warmup reads the
      // wrong locale and this is what says so.
      final warmed = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: waxLocalizationsDelegates,
          supportedLocales: waxSupportedLocales,
          builder: (context, child) => LocaleFontWarmup(
            warm: (sample) async => warmed.add(sample),
            child: child!,
          ),
          home: const SizedBox.shrink(),
        ),
      );

      expect(warmed, ['Música, pódcasts y audiolibros.']);
    });
  });
}
