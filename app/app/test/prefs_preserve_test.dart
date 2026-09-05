import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/prefs_controller.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

const _user = WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']);

/// One clearable preference: how to clear it, and how to read it back.
typedef _Clear = ({
  String name,
  Future<void> Function(PrefsController) clear,
  String? Function(Prefs) read,
});

const _stored = Prefs(
  timezone: 'America/Denver',
  locale: 'es',
  theme: ThemePref.oled,
  sharedStatsOptOut: true,
  radioFavorites: <String>['rs-01JZX5N8QW3F4V9T2B7KD3M9R6'],
  radioScrobbleMutedStations: <String>['rs-01JZX5N8QW3F4V9T2B7KD3M9R7'],
  pinned: <String>['al-01JZX5N8QW3F4V9T2B7KD3M9R6'],
  crossfadeSeconds: 4.5,
  replayGain: true,
  radioScrobbleOptOut: true,
  identifyOptOut: true,
  browseShowUnknown: false,
  browseSorts: <String, String>{'artist': 'label'},
  autoplay: false,
);

final _clears = <_Clear>[
  (name: 'timezone', clear: (n) => n.clearTimezone(), read: (p) => p.timezone),
  (name: 'locale', clear: (n) => n.clearLocale(), read: (p) => p.locale),
];

void main() {
  test(
    'an early setting change never wipes stored timezone and locale',
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

      // Tap a setting before the initial prefs fetch has resolved. The
      // stored document must survive: the endpoint replaces the whole
      // object, so building the update from an empty default would wipe
      // the timezone and locale. (The theme used to be this test's
      // subject; it is a per-device setting now and never written here.)
      final notifier = container.read(prefsControllerProvider.notifier);
      await notifier.setSharedStatsOptOut(true);

      expect(repo.prefs.sharedStatsOptOut, isTrue);
      expect(
        repo.prefs.timezone,
        'America/Denver',
        reason: 'replace semantics must start from the loaded document',
      );
      expect(repo.prefs.locale, 'en-US');
      expect(
        repo.prefs.theme,
        ThemePref.system,
        reason: 'the deprecated field is carried, not dropped',
      );
    },
  );

  // The clears are the one kind of write that rebuilds the document by
  // hand, because copyWith cannot null a field. Every preference added
  // to Prefs has to reach that literal too, or clearing anything
  // silently deletes it - which for a pin list is a home shelf emptying
  // itself. Tabled, so whichever clear lands next costs one line.
  for (final subject in _clears) {
    test(
      'clearing the ${subject.name} keeps every other stored field',
      () async {
        final repo = FakeRepository()
          ..sessionState = const SessionState(authenticated: true, user: _user)
          ..prefs = _stored;
        final container = ProviderContainer(
          overrides: [repositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        await subject.clear(container.read(prefsControllerProvider.notifier));

        final kept = repo.prefs;
        expect(subject.read(kept), isNull);
        for (final other in _clears.where((o) => o.name != subject.name)) {
          expect(
            other.read(kept),
            other.read(_stored),
            reason: 'clearing the ${subject.name} kept the ${other.name}',
          );
        }
        expect(kept.theme, ThemePref.oled);
        expect(kept.sharedStatsOptOut, isTrue);
        expect(kept.radioFavorites, <String>['rs-01JZX5N8QW3F4V9T2B7KD3M9R6']);
        expect(kept.radioScrobbleMutedStations, <String>[
          'rs-01JZX5N8QW3F4V9T2B7KD3M9R7',
        ]);
        expect(kept.pinned, <String>['al-01JZX5N8QW3F4V9T2B7KD3M9R6']);
        expect(kept.crossfadeSeconds, 4.5);
        expect(kept.replayGain, isTrue);
        expect(kept.radioScrobbleOptOut, isTrue);
        expect(kept.identifyOptOut, isTrue);
        expect(kept.browseShowUnknown, isFalse);
        expect(kept.browseSorts, <String, String>{'artist': 'label'});
        expect(kept.autoplay, isFalse);
      },
    );
  }
}
