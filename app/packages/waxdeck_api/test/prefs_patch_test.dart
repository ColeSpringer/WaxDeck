import 'dart:convert';

import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

/// A preference change made offline waits as a patch: the fields it
/// changed, in the wire's own spelling, laid over whatever the document
/// holds when it is finally sent. A whole document replayed later would
/// put back every field another device changed in the meantime.
void main() {
  const base = Prefs(
    timezone: 'America/Denver',
    locale: 'en-US',
    radioFavorites: ['RS-1'],
    pinned: ['AL-1'],
  );

  group('a patch', () {
    test('names only what changed', () {
      final to = base.copyWith(pinned: ['AL-1', 'AL-2']);

      expect(prefsPatch(base, to), {
        'pinned': ['AL-1', 'AL-2'],
      });
    });

    test('names a cleared field as null', () {
      const to = Prefs(
        timezone: 'America/Denver',
        radioFavorites: ['RS-1'],
        pinned: ['AL-1'],
      );

      expect(prefsPatch(base, to), {'locale': null});
    });

    test('carries an emptied list as a value, not a clear', () {
      // What makes the last unpin stick once it is sent.
      final to = base.copyWith(radioFavorites: const <String>[]);

      expect(prefsPatch(base, to), {'radioFavorites': <Object?>[]});
    });

    test('is empty when nothing changed', () {
      const same = Prefs(
        timezone: 'America/Denver',
        locale: 'en-US',
        radioFavorites: ['RS-1'],
        pinned: ['AL-1'],
      );

      expect(prefsPatch(base, same), isEmpty);
    });
  });

  group('the browse sorts', () {
    // Merged per dimension rather than replaced, as setBrowseSort writes
    // them: another device's sort for another dimension is not this
    // change's to overwrite.
    const sorted = Prefs(browseSorts: {'genre': 'count', 'year': 'name'});

    test('a patch names only the sort that changed', () {
      final to = sorted.copyWith(
        browseSorts: {'genre': 'count', 'year': 'added'},
      );

      expect(prefsPatch(sorted, to), {
        'browseSorts': {'year': 'added'},
      });
    });

    test('a patch names a sort that went as null', () {
      final to = sorted.copyWith(browseSorts: {'genre': 'count'});

      expect(prefsPatch(sorted, to), {
        'browseSorts': {'year': null},
      });
    });

    test('a sort patch merges into the sorts the document holds', () {
      const elsewhere = Prefs(browseSorts: {'genre': 'count'});

      final patched = applyPrefsPatch(elsewhere, {
        'browseSorts': {'year': 'added'},
      });

      expect(patched.browseSorts, {'genre': 'count', 'year': 'added'});
    });

    test('a null sort removes that sort alone', () {
      final patched = applyPrefsPatch(sorted, {
        'browseSorts': {'year': null},
      });

      expect(patched.browseSorts, {'genre': 'count'});
    });

    test('two waiting patches keep both sorts', () {
      expect(
        mergePrefsPatches(
          {
            'browseSorts': {'year': 'name'},
            'locale': 'es',
          },
          {
            'browseSorts': {'genre': 'count'},
            'pinned': ['AL-1'],
          },
        ),
        {
          'browseSorts': {'year': 'name', 'genre': 'count'},
          'locale': 'es',
          'pinned': ['AL-1'],
        },
      );
    });

    test('what was sent of them is settled per sort', () {
      expect(
        unsettledPrefsPatch(
          {
            'browseSorts': {'year': 'name', 'genre': 'count'},
          },
          {
            'browseSorts': {'year': 'name'},
          },
        ),
        {
          'browseSorts': {'genre': 'count'},
        },
      );
    });
  });

  test('a later patch replaces a list rather than joining it', () {
    expect(
      mergePrefsPatches(
        {
          'pinned': ['AL-1'],
        },
        {
          'pinned': ['AL-2'],
        },
      ),
      {
        'pinned': ['AL-2'],
      },
    );
  });

  group('what is left of a patch once another is settled', () {
    test('keeps the fields the settled one does not name', () {
      expect(
        unsettledPrefsPatch(
          {
            'pinned': ['AL-1', 'AL-2'],
            'locale': 'es',
          },
          {
            'pinned': ['AL-1', 'AL-2'],
          },
        ),
        {'locale': 'es'},
      );
    });

    test('keeps a field whose value moved on since', () {
      expect(
        unsettledPrefsPatch(
          {
            'pinned': ['AL-1', 'AL-2', 'AL-3'],
          },
          {
            'pinned': ['AL-1', 'AL-2'],
          },
        ),
        {
          'pinned': ['AL-1', 'AL-2', 'AL-3'],
        },
      );
    });

    test('drops a field settled at the same value, however spelled', () {
      expect(
        unsettledPrefsPatch(
          {
            'browseSorts': {'year': 'name', 'genre': 'count'},
            'locale': null,
          },
          {
            'browseSorts': {'genre': 'count', 'year': 'name'},
            'locale': null,
          },
        ),
        isEmpty,
      );
    });
  });

  group('applying a patch', () {
    test('keeps every field it does not name', () {
      // The document moved on another device since the patch was made.
      const moved = Prefs(
        timezone: 'Europe/Madrid',
        pinned: ['AL-9'],
        crossfadeSeconds: 4,
      );

      final patched = applyPrefsPatch(moved, {
        'locale': 'es',
        'crossfadeSeconds': 2.5,
      });

      expect(patched.timezone, 'Europe/Madrid');
      expect(patched.pinned, ['AL-9']);
      expect(patched.locale, 'es');
      expect(patched.crossfadeSeconds, 2.5);
    });

    test('clears a field the patch names as null', () {
      final patched = applyPrefsPatch(base, {'locale': null});

      expect(patched.locale, isNull);
      expect(patched.timezone, 'America/Denver');
    });

    test('survives the patch being stored as text', () {
      const to = Prefs(
        timezone: 'Europe/Madrid',
        radioFavorites: ['RS-2'],
        radioScrobbleMutedStations: ['RS-3'],
        pinned: <String>[],
        sharedStatsOptOut: true,
        crossfadeSeconds: 2.5,
        replayGain: true,
        radioScrobbleOptOut: false,
        identifyOptOut: true,
        browseShowUnknown: false,
        browseSorts: {'genre': 'count', 'year': 'name'},
        autoplay: false,
      );

      final stored = jsonDecode(jsonEncode(prefsPatch(base, to)));
      final patched = applyPrefsPatch(base, stored as Map<String, Object?>);

      expect(patched.timezone, 'Europe/Madrid');
      expect(patched.locale, isNull);
      expect(patched.radioFavorites, ['RS-2']);
      expect(patched.radioScrobbleMutedStations, ['RS-3']);
      expect(patched.pinned, isEmpty);
      expect(patched.sharedStatsOptOut, isTrue);
      expect(patched.crossfadeSeconds, 2.5);
      expect(patched.replayGain, isTrue);
      expect(patched.radioScrobbleOptOut, isFalse);
      expect(patched.identifyOptOut, isTrue);
      expect(patched.browseShowUnknown, isFalse);
      expect(patched.browseSorts, {'genre': 'count', 'year': 'name'});
      expect(patched.autoplay, isFalse);
    });
  });
}
