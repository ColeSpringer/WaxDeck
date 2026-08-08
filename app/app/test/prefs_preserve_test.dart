import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/prefs_controller.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

const _user = WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']);

void main() {
  test(
    'an early theme change never wipes stored timezone and locale',
    () async {
      final repo = FakeRepository()
        ..sessionState = const SessionState(authenticated: true, user: _user)
        ..prefs = const Prefs(
          timezone: 'America/Denver',
          locale: 'en-US',
          theme: ThemePref.system,
        );
      final container = ProviderContainer(
        overrides: [repositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      // Tap the theme before the initial prefs fetch has resolved. The
      // stored document must survive: the endpoint replaces the whole
      // object, so building the update from an empty default would wipe
      // the timezone and locale.
      final notifier = container.read(prefsControllerProvider.notifier);
      await notifier.setTheme(ThemePref.oled);

      expect(repo.prefs.theme, ThemePref.oled);
      expect(
        repo.prefs.timezone,
        'America/Denver',
        reason: 'replace semantics must start from the loaded document',
      );
      expect(repo.prefs.locale, 'en-US');
    },
  );

  // clearTimezone is the one write that rebuilds the document by hand,
  // because copyWith cannot null a field. Every field added to Prefs has
  // to be added to that literal too, or clearing a timezone silently
  // deletes it - which for a pin list is a home shelf emptying itself.
  test('clearing the timezone keeps every other stored field', () async {
    final repo = FakeRepository()
      ..sessionState = const SessionState(authenticated: true, user: _user)
      ..prefs = const Prefs(
        timezone: 'America/Denver',
        locale: 'en-US',
        theme: ThemePref.oled,
        sharedStatsOptOut: true,
        radioFavorites: <String>['rs-01JZX5N8QW3F4V9T2B7KD3M9R6'],
        pinned: <String>['al-01JZX5N8QW3F4V9T2B7KD3M9R6'],
        crossfadeSeconds: 4.5,
        replayGain: true,
        radioScrobbleOptOut: true,
        browseShowUnknown: false,
        browseSorts: <String, String>{'artist': 'label'},
        autoplay: false,
      );
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    await container.read(prefsControllerProvider.notifier).clearTimezone();

    final stored = repo.prefs;
    expect(stored.timezone, isNull);
    expect(stored.locale, 'en-US');
    expect(stored.theme, ThemePref.oled);
    expect(stored.sharedStatsOptOut, isTrue);
    expect(stored.radioFavorites, <String>['rs-01JZX5N8QW3F4V9T2B7KD3M9R6']);
    expect(stored.pinned, <String>['al-01JZX5N8QW3F4V9T2B7KD3M9R6']);
    expect(stored.crossfadeSeconds, 4.5);
    expect(stored.replayGain, isTrue);
    expect(stored.radioScrobbleOptOut, isTrue);
    expect(stored.browseShowUnknown, isFalse);
    expect(stored.browseSorts, <String, String>{'artist': 'label'});
    expect(stored.autoplay, isFalse);
  });
}
