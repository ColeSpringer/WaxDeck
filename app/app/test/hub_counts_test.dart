import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/books/series_merge.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/prefs_controller.dart';
import 'package:waxdeck/src/sync/sync_binder.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

/// Who is signed in, for the cases that change account mid-test.
final _account = NotifierProvider<_Account, String?>(_Account.new);

class _Account extends Notifier<String?> {
  @override
  String? build() => 'us-1';

  void set(String? id) => state = id;
}

const _artists = (
  dimension: MusicDimension.artists,
  domain: BrowseDomain.music,
);
const _authors = (
  dimension: MusicDimension.artists,
  domain: BrowseDomain.books,
);

/// The hub tiles' counts, held as a mounted hub holds them.
void _hold(ProviderContainer container) {
  final held = <ProviderSubscription<Object?>>[
    container.listen(musicIndexCountProvider(_artists), (_, _) {}),
    container.listen(musicIndexCountProvider(_authors), (_, _) {}),
    container.listen(bookSeriesCountProvider, (_, _) {}),
  ];
  addTearDown(() {
    for (final subscription in held) {
      subscription.close();
    }
  });
}

Future<void> _read(ProviderContainer container) async {
  await container.read(musicIndexCountProvider(_artists).future);
  await container.read(musicIndexCountProvider(_authors).future);
  await container.read(bookSeriesCountProvider.future);
}

/// The hubs' counts are cached for the session, and the session is what
/// moves them: another account, or the catalog changing under them.
void main() {
  test('another account reads its own counts', () async {
    final repo = FakeRepository();
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        signedInAccountProvider.overrideWith((ref) => ref.watch(_account)),
      ],
    );
    addTearDown(container.dispose);
    _hold(container);
    await _read(container);
    final facets = repo.facetReads.length;
    final series = repo.bookSeriesReads.length;

    container.read(_account.notifier).set('us-2');
    await _read(container);

    expect(repo.facetReads.length - facets, 2);
    expect(repo.bookSeriesReads.length - series, 1);
  });

  testWidgets('a catalog change counts the held tiles again', (tester) async {
    final db = inMemoryMirrorDatabase();
    addTearDown(db.close);
    final downloads = FakeDownloads();
    addTearDown(downloads.dispose);
    final repo = FakeRepository(
      items: [testItem('tr-01JZX5N8QW3F4V9T2B7KDCNT01')],
    );
    final sync = SyncEngine(
      db: db,
      repository: repo,
      channelFactory: deadChannelFactory(),
    );
    addTearDown(sync.dispose);
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        audioEngineProvider.overrideWithValue(FakeEngine()),
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        mirrorDatabaseProvider.overrideWithValue(db),
        downloadManagerProvider.overrideWithValue(downloads),
        artworkStoreProvider.overrideWithValue(FakeArtworkStore()),
        syncEngineProvider.overrideWithValue(sync),
      ],
    );
    // Also disposed by hand below, before the last pump flushes the
    // binder's timers; this one covers a failed assertion.
    addTearDown(container.dispose);
    container.listen(syncBinderProvider, (_, _) {});
    _hold(container);
    await tester.runAsync(() => _read(container));
    final facets = repo.facetReads.length;
    final series = repo.bookSeriesReads.length;

    // A scan lands a track.
    repo.libraryItems.add(testItem('tr-01JZX5N8QW3F4V9T2B7KDCNT02'));
    await sync.pullCatalog();
    await tester.pump(kCatalogRefreshWindow);
    await tester.pump();
    await tester.runAsync(() => _read(container));

    expect(
      repo.facetReads.sublist(facets).map((r) => r.facetKey),
      unorderedEquals(<String>['track', 'book']),
    );
    expect(repo.bookSeriesReads.length - series, 1);

    await tester.pump(const Duration(seconds: 1));
    container.dispose();
    await tester.pump();
  });

  for (final (shown, expected) in <(bool?, int)>[(null, 4), (false, 3)]) {
    test('a tile counts what its index lists (show unknown: $shown)', () async {
      final repo = FakeRepository()
        ..facets['artist|kind|book'] = <FacetBucket>[
          const FacetBucket(key: '01A', label: 'Ada', count: 1),
          const FacetBucket(key: '01B', label: 'Bea', count: 1),
          const FacetBucket(key: '01C', label: 'Cyd', count: 1),
          const FacetBucket(key: '', label: '', count: 1, unknown: true),
        ];
      final container = ProviderContainer(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          prefsControllerProvider.overrideWith(
            () => _StubPrefs(Prefs(browseShowUnknown: shown)),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(musicIndexCountProvider(_authors), (_, _) {});
      await container.read(prefsControllerProvider.future);

      final count = await container.read(
        musicIndexCountProvider(_authors).future,
      );

      expect(count.buckets, expected);
    });
  }
}

/// The account's document as given, past the session the real controller
/// waits on.
class _StubPrefs extends PrefsController {
  _StubPrefs(this._prefs);

  final Prefs _prefs;

  @override
  Future<Prefs> build() async => _prefs;
}
