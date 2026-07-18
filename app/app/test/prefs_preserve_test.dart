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
}
