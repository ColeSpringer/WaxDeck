import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

/// What the members derived from a model's fields answer, and what the
/// copies that replace one field keep.
void main() {
  group('a derived value read through an extends chain', () {
    const summary = ItemSummary(
      pid: 'tr-1',
      mediaType: MediaType.music,
      title: 'Long Division',
      durationMs: 1000,
      artist: 'The Band',
      artistSort: 'Band, The',
    );
    const keyed = ItemSummary(
      pid: 'tr-2',
      mediaType: MediaType.music,
      title: 'Long Division',
      durationMs: 1000,
      artist: 'The Band',
      sortKey: 'long division',
      artistSortKey: 'band',
    );

    test('titleOrderKey and artistOrderKey read an item detail', () {
      const detail = ItemDetail(
        pid: 'tr-3',
        mediaType: MediaType.music,
        title: 'Long Division',
        durationMs: 1000,
        artist: 'The Band',
        sortKey: 'long division',
        artistSortKey: 'band',
      );

      expect(detail.titleOrderKey, 'long division');
      expect(detail.artistOrderKey, 'band');
      expect(keyed.titleOrderKey, 'long division');
    });

    test('they fall back to the lowercase title and the sort spelling', () {
      final episode = EpisodeSummary(
        pid: 'ep-1',
        mediaType: MediaType.podcast,
        title: 'Pilot',
        durationMs: 1000,
        artist: 'The Show',
        showPid: 'pc-1',
        publishedAt: DateTime.utc(2026),
        downloaded: false,
      );

      expect(episode.titleOrderKey, 'pilot');
      expect(episode.artistOrderKey, 'the show');
      expect(summary.artistOrderKey, 'band, the');
    });

    test('they read an episode detail, one level further down', () {
      final episode = EpisodeDetail(
        pid: 'ep-2',
        mediaType: MediaType.podcast,
        title: 'Finale',
        durationMs: 1000,
        showPid: 'pc-1',
        publishedAt: DateTime.utc(2026),
        downloaded: true,
      );

      expect(episode.titleOrderKey, 'finale');
      expect(episode.artistOrderKey, '');
    });

    test('label reads a user account', () {
      final account = UserAccount(
        id: 'u-1',
        username: 'ada',
        displayName: 'Ada',
        createdAt: DateTime.utc(2026),
        libraryAccess: const LibraryAccess(mode: 'all'),
      );
      final unnamed = UserAccount(
        id: 'u-2',
        username: 'grace',
        createdAt: DateTime.utc(2026),
        libraryAccess: const LibraryAccess(mode: 'all'),
      );

      expect(account.label, 'Ada');
      expect(unnamed.label, 'grace');
    });

    test('expired reads a created invite', () {
      final stale = InviteCreated(
        id: 'iv-1',
        maxUses: 1,
        expiresAt: DateTime.utc(2000),
        createdAt: DateTime.utc(1999),
        token: 'secret',
      );
      final fresh = InviteCreated(
        id: 'iv-2',
        maxUses: 1,
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)),
        createdAt: DateTime.utc(1999),
        token: 'secret',
      );

      expect(stale.expired, isTrue);
      expect(fresh.expired, isFalse);
    });
  });

  group('copyWith', () {
    test('Prefs changes the named field and keeps the rest', () {
      const base = Prefs(
        timezone: 'Europe/Amsterdam',
        locale: 'en-US',
        theme: ThemePref.dark,
        radioFavorites: ['RS-1'],
        pinned: ['AL-1'],
        crossfadeSeconds: 3,
        browseSorts: {'genre': 'alphabetical'},
        autoplay: true,
      );

      final next = base.copyWith(locale: 'es-ES');

      expect(next.locale, 'es-ES');
      expect(next.timezone, 'Europe/Amsterdam');
      expect(next.theme, ThemePref.dark);
      expect(next.radioFavorites, ['RS-1']);
      expect(next.pinned, ['AL-1']);
      expect(next.crossfadeSeconds, 3);
      expect(next.browseSorts, {'genre': 'alphabetical'});
      expect(next.autoplay, isTrue);
    });

    test('Prefs carries an emptied list as a value', () {
      const base = Prefs(radioFavorites: ['RS-1']);

      expect(
        base.copyWith(radioFavorites: const <String>[]).radioFavorites,
        isEmpty,
      );
    });

    test('LibraryMatching changes one field and keeps the other', () {
      const base = LibraryMatching(mode: 'auto', singlesAutoApply: true);

      final mode = base.copyWith(mode: 'review');
      final singles = base.copyWith(singlesAutoApply: false);

      expect(mode.mode, 'review');
      expect(mode.singlesAutoApply, isTrue);
      expect(singles.mode, 'auto');
      expect(singles.singlesAutoApply, isFalse);
    });

    test('GenreNode changes a field, keeps the rest and clears the parent', () {
      const base = GenreNode(
        name: 'Shoegaze',
        parent: 'Rock',
        aliases: ['Shoe-gaze'],
      );

      final renamed = base.copyWith(name: 'Dream Pop');
      final reparented = base.copyWith(parent: 'Pop');
      final cleared = base.copyWith(clearParent: true);
      final both = base.copyWith(parent: 'Pop', clearParent: true);

      expect(renamed.name, 'Dream Pop');
      expect(renamed.parent, 'Rock');
      expect(renamed.aliases, ['Shoe-gaze']);
      expect(reparented.parent, 'Pop');
      expect(cleared.parent, isNull);
      expect(cleared.name, 'Shoegaze');
      expect(cleared.aliases, ['Shoe-gaze']);
      expect(both.parent, isNull);
    });

    test('AdminSettings changes a field and keeps the rest', () {
      const base = AdminSettings(
        signupEnabled: true,
        readOnly: false,
        sonicAnalysis: true,
        backupKeepCount: 5,
        backupKeepBytes: 1024,
        trashRetentionDays: 14,
        taskRetentionDays: 30,
        radioExternalArt: false,
      );

      final next = base.copyWith(readOnly: true, trashRetentionDays: 7);

      expect(next.readOnly, isTrue);
      expect(next.trashRetentionDays, 7);
      expect(next.signupEnabled, isTrue);
      expect(next.sonicAnalysis, isTrue);
      expect(next.backupKeepCount, 5);
      expect(next.backupKeepBytes, 1024);
      expect(next.taskRetentionDays, 30);
      expect(next.radioExternalArt, isFalse);
    });
  });

  test(
    'Prefs.browseSortFor reads a stored order and ignores an unknown one',
    () {
      const facet = FacetSort.label;
      final prefs = Prefs(
        browseSorts: {'genre': facet.wireName, 'decade': 'sideways'},
      );

      expect(prefs.browseSortFor('genre'), facet);
      expect(prefs.browseSortFor('decade'), isNull);
      expect(prefs.browseSortFor('year'), isNull);
      expect(const Prefs().browseSortFor('genre'), isNull);
    },
  );
}
