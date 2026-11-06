import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/books/books_controller.dart';
import 'package:waxdeck/src/health/health_controller.dart';
import 'package:waxdeck/src/metadata/metadata_controller.dart';
import 'package:waxdeck/src/playlists/playlist_sync_controller.dart';
import 'package:waxdeck/src/playlists/playlists_controller.dart';
import 'package:waxdeck/src/podcasts/podcasts_controller.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/review/review_controller.dart';
import 'package:waxdeck/src/search/search_controller.dart';
import 'package:waxdeck/src/settings/integrations_controller.dart';
import 'package:waxdeck/src/settings/sessions_controller.dart';
import 'package:waxdeck/src/sharing/shares_controller.dart';
import 'package:waxdeck/src/stats/stats_controller.dart';
import 'package:waxdeck/src/tools/tool_tasks_provider.dart';
import 'package:waxdeck/src/uploads/uploads_controller.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

/// What one account read is read again for the next one on the same
/// server: the repository moves only with the server, so a list kept
/// for the session would otherwise show the last account's rows.

const _ann = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDACCANN',
  username: 'ann',
  roles: ['user'],
  uploadEnabled: true,
);
const _ben = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDACCBEN',
  username: 'ben',
  roles: ['user'],
  uploadEnabled: true,
);

/// What the server holds for [who]: Ann has two entries waiting, an
/// upload and a task; Ben one entry, and an upload and a task of his own.
void _holdFor(FakeRepository repo, WaxDeckUser who) {
  final ann = who == _ann;
  final at = DateTime.utc(2026, 10, 1);
  repo
    ..reviewEntries = [
      if (ann) ...[testReviewEntry('rv-ann1'), testReviewEntry('rv-ann2')],
      if (!ann) testReviewEntry('rv-ben1'),
    ]
    ..uploadsById.clear()
    ..uploadsById['up-${who.username}'] = UploadSession(
      id: 'up-${who.username}',
      fileName: '${who.username}.flac',
      sizeBytes: 8,
      receivedBytes: 8,
      idle: Duration.zero,
      mediaType: MediaType.music,
      state: 'staged',
      createdAt: at,
    )
    ..toolTasksById.clear()
    ..toolTasksById['tt-${who.username}'] = ToolTask(
      id: 'tt-${who.username}',
      type: 'acquire',
      state: 'done',
      createdAt: at,
    );
}

/// A server whose per-account reads answer for whoever is signed in, each
/// row named after that account.
class _PerCaller extends FakeRepository {
  _PerCaller()
    : super(sessionState: const SessionState(authenticated: true, user: _ann));

  String get _who => sessionState.user!.username;
  int get _ms => _who == _ann.username ? 1 : 2;
  static final _at = DateTime.utc(2026, 10, 1);

  Playlist _playlist(String pid) => Playlist(
    pid: pid,
    name: _who,
    kind: 'static',
    visibility: 'private',
    ownerName: _who,
    isOwner: true,
    createdAt: _at,
    updatedAt: _at,
  );

  @override
  Future<List<DeviceSession>> listSessions() async => [testSession('se-$_who')];

  @override
  Future<List<AppPassword>> listAppPasswords() async => [
    AppPassword(id: 'ap-$_who', label: _who, createdAt: _at),
  ];

  @override
  Future<List<NotificationTarget>> listMyNotificationTargets() async => [
    NotificationTarget(
      pid: 'nt-$_who',
      kind: 'ntfy',
      scope: 'user',
      config: const {},
      enabledEvents: const [],
      createdAt: _at,
    ),
  ];

  @override
  Future<PlaylistPage> listPlaylists({
    String? cursor,
    int? limit,
    String? containsItem,
  }) async => PlaylistPage(playlists: [_playlist('pl-$_who')]);

  @override
  Future<Playlist> getPlaylist(String pid) async => _playlist(pid);

  @override
  Future<PlaylistItemsPage> listPlaylistItems(
    String pid, {
    String? cursor,
    int? limit,
  }) async => const PlaylistItemsPage(entries: []);

  @override
  Future<PlaylistSource> getPlaylistSource(String pid) async => PlaylistSource(
    source: 'm3u',
    title: _who,
    live: false,
    mode: 'mirror',
    disabled: false,
    consecutiveFailures: 0,
  );

  @override
  Future<SubscriptionPage> listSubscriptions({
    String? cursor,
    int? limit,
  }) async => SubscriptionPage(
    items: [
      Subscription(
        show: testShow('pc-$_who'),
        settings: const SubscriptionSettings(),
        subscribedAt: _at,
      ),
    ],
  );

  @override
  Future<PodcastDetail> getPodcast(String pid) async =>
      PodcastDetail(show: testShow(pid, title: _who), subscribed: true);

  @override
  Future<EpisodePage> listEpisodes(
    String pid, {
    String? cursor,
    int? limit,
  }) async => EpisodePage(items: [testEpisode('ep-$_who', showPid: pid)]);

  @override
  Future<SharePage> listShares({
    String? cursor,
    int? limit,
    bool all = false,
  }) async => SharePage(
    shares: [
      Share(
        pid: 'sh-$_who',
        url: 'https://pony.example/s/$_who',
        targetPid: 'tr-1',
        targetKind: 'track',
        targetTitle: _who,
        allowDownload: false,
        createdAt: _at,
        plays: 0,
      ),
    ],
  );

  @override
  Future<ListeningStats> getListeningStats({
    String? range,
    String? bucket,
  }) async => ListeningStats(
    range: '30d',
    bucket: 'day',
    timezone: 'UTC',
    totalMs: _ms,
    sessions: 0,
    timeSavedMs: 0,
  );

  @override
  Future<ListeningHeatmap> getListeningHeatmap({int? year}) async =>
      ListeningHeatmap(
        year: 2026,
        timezone: 'UTC',
        currentStreakDays: _ms,
        longestStreakDays: _ms,
      );

  @override
  Future<TopList> getTopList({
    required String kind,
    String? range,
    int? limit,
  }) async => TopList(
    kind: kind,
    range: '30d',
    entries: [TopEntry(name: _who, plays: 1, ms: 1)],
  );

  @override
  Future<ListenLogPage> listListenLog({
    String? client,
    String? cursor,
    int? limit,
  }) async => ListenLogPage(
    sessions: [
      ListenLogEntry(
        pid: 'tr-$_who',
        mediaType: StatsMediaType.music,
        startedAt: _at,
        msPlayed: 1,
        finished: true,
        client: 'web',
        source: 'local',
      ),
    ],
  );

  @override
  Future<YearInReview> getYearInReview({int? year}) async => YearInReview(
    year: year ?? 2026,
    timezone: 'UTC',
    totalMs: _ms,
    sessions: 0,
    distinctItems: 0,
    newInLibrary: 0,
    timeSavedMs: 0,
    longestStreakDays: 0,
  );

  @override
  Future<ServerYearInReview> getServerYearInReview({int? year}) async =>
      ServerYearInReview(
        year: year ?? 2026,
        participants: 1,
        totalMs: _ms,
        sessions: 0,
      );

  // Each sees the issues of the items their grants offer.
  @override
  Future<HealthIssuePage> listHealthIssues({
    String? rule,
    String? cursor,
    int? limit,
  }) async => HealthIssuePage(
    items: [
      HealthIssue(
        pid: 'tr-$_who',
        title: _who,
        mediaType: MediaType.music,
        rules: [rule ?? 'missing-art'],
      ),
    ],
  );

  // Ann may edit the item, Ben may not.
  @override
  Future<ItemMetadata> getItemMetadata(String pid) async => ItemMetadata(
    pid: pid,
    mediaType: MediaType.audiobook,
    fields: const {},
    mayCurate: _who == _ann.username,
  );

  @override
  Future<ItemPage> listItems({
    MediaType? mediaType,
    String? facet,
    String? facetKey,
    String? cursor,
    int? limit,
  }) async =>
      ItemPage(items: [testItem('bk-$_who', mediaType: MediaType.audiobook)]);

  @override
  Future<SearchResults> search(String q, {int? limit}) async => SearchResults(
    query: q,
    tracks: [SearchHit(pid: 'tr-$_who', kind: 'track', title: _who)],
  );
}

void main() {
  // What the server answers per caller, read through a list kept alive
  // across a sign-in swap on the same server.
  for (final (name, provider, read, annSees, benSees)
      in <
        (
          String,
          ProviderListenable<Object?>,
          Future<Object?> Function(ProviderContainer),
          Object?,
          Object?,
        )
      >[
        (
          'the signed-in devices',
          sessionsControllerProvider,
          (c) async => [
            for (final s in await c.read(sessionsControllerProvider.future))
              s.id,
          ],
          ['se-ann'],
          ['se-ben'],
        ),
        (
          'the app passwords',
          appPasswordsProvider,
          (c) async => [
            for (final p in await c.read(appPasswordsProvider.future)) p.id,
          ],
          ['ap-ann'],
          ['ap-ben'],
        ),
        (
          'the personal notification targets',
          myNotificationTargetsProvider,
          (c) async => [
            for (final t in await c.read(myNotificationTargetsProvider.future))
              t.pid,
          ],
          ['nt-ann'],
          ['nt-ben'],
        ),
        (
          'the playlists',
          playlistsProvider,
          (c) async => [
            for (final p in await c.read(playlistsProvider.future)) p.pid,
          ],
          ['pl-ann'],
          ['pl-ben'],
        ),
        (
          'a playlist',
          playlistDetailProvider('pl-1'),
          (c) async => (await c.read(
            playlistDetailProvider('pl-1').future,
          )).playlist.name,
          'ann',
          'ben',
        ),
        (
          "a playlist's source",
          playlistSyncProvider('pl-1'),
          (c) async =>
              (await c.read(playlistSyncProvider('pl-1').future))?.title,
          'ann',
          'ben',
        ),
        (
          'the subscriptions',
          subscriptionsProvider,
          (c) async => [
            for (final s in await c.read(subscriptionsProvider.future))
              s.show.pid,
          ],
          ['pc-ann'],
          ['pc-ben'],
        ),
        (
          'a show',
          podcastDetailProvider('pc-1'),
          (c) async =>
              (await c.read(podcastDetailProvider('pc-1').future)).show.title,
          'ann',
          'ben',
        ),
        (
          "a show's episodes",
          episodesProvider('pc-1'),
          (c) async => [
            for (final e in (await c.read(
              episodesProvider('pc-1').future,
            )).items)
              e.pid,
          ],
          ['ep-ann'],
          ['ep-ben'],
        ),
        (
          'the share links',
          sharesProvider,
          (c) async => [
            for (final s in (await c.read(sharesProvider.future)).shares) s.pid,
          ],
          ['sh-ann'],
          ['sh-ben'],
        ),
        (
          'the listening stats',
          listeningStatsProvider,
          (c) async => (await c.read(listeningStatsProvider.future)).totalMs,
          1,
          2,
        ),
        (
          'the listening heatmap',
          listeningHeatmapProvider,
          (c) async =>
              (await c.read(listeningHeatmapProvider.future)).longestStreakDays,
          1,
          2,
        ),
        (
          'the top list',
          topListProvider,
          (c) async =>
              (await c.read(topListProvider.future)).entries.single.name,
          'ann',
          'ben',
        ),
        (
          'the listen log',
          listenLogProvider,
          (c) async => [
            for (final e in (await c.read(listenLogProvider.future)).entries)
              e.pid,
          ],
          ['tr-ann'],
          ['tr-ben'],
        ),
        (
          'the year in review',
          yearInReviewProvider(2026),
          (c) async =>
              (await c.read(yearInReviewProvider(2026).future)).totalMs,
          1,
          2,
        ),
        (
          'the server year in review',
          serverYearInReviewProvider(2026),
          (c) async =>
              (await c.read(serverYearInReviewProvider(2026).future)).totalMs,
          1,
          2,
        ),
        (
          'the health worklist',
          healthIssuesProvider('missing-art'),
          (c) async => [
            for (final i in (await c.read(
              healthIssuesProvider('missing-art').future,
            )).items)
              i.pid,
          ],
          ['tr-ann'],
          ['tr-ben'],
        ),
        (
          "an item's metadata and who may edit it",
          metadataControllerProvider('bk-1'),
          (c) async => (await c.read(
            metadataControllerProvider('bk-1').future,
          )).metadata.mayCurate,
          true,
          false,
        ),
        (
          'the audiobooks',
          booksProvider,
          (c) async => [
            for (final b in (await c.read(booksProvider.future)).books) b.pid,
          ],
          ['bk-ann'],
          ['bk-ben'],
        ),
        (
          'the search results',
          searchResultsProvider,
          (c) async {
            c.read(searchQueryProvider.notifier).submit('pony');
            return [
              for (final hit in (await c.read(
                searchResultsProvider.future,
              ))!.tracks)
                hit.pid,
            ];
          },
          ['tr-ann'],
          ['tr-ben'],
        ),
      ]) {
    test('reads $name again for the next account on the server', () async {
      final repo = _PerCaller();
      final container = ProviderContainer(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);
      // Kept alive, as the screen showing it would.
      final held = container.listen(provider, (_, _) {});
      addTearDown(held.close);
      expect(await read(container), annSees);

      // Ben signs in on the same server.
      repo.sessionState = const SessionState(authenticated: true, user: _ben);
      await container.read(authControllerProvider.notifier).refreshSession();

      expect(await read(container), benSees);
    });
  }

  for (final (name, provider, read, annSees, benSees)
      in <
        (
          String,
          ProviderListenable<Object?>,
          Future<Object?> Function(ProviderContainer),
          Object?,
          Object?,
        )
      >[
        (
          'the review counts',
          reviewStatsProvider,
          (c) async => (await c.read(reviewStatsProvider.future)).pending,
          2,
          1,
        ),
        (
          'home\'s review count',
          pendingReviewCountProvider,
          (c) => c.read(pendingReviewCountProvider.future),
          2,
          1,
        ),
        (
          'the review queue',
          reviewQueueProvider,
          (c) async => [
            for (final e in (await c.read(reviewQueueProvider.future)).entries)
              e.id,
          ],
          ['rv-ann1', 'rv-ann2'],
          ['rv-ben1'],
        ),
        (
          'the uploads',
          uploadsProvider,
          (c) async => [
            for (final u in (await c.read(uploadsProvider.future)).uploads)
              u.id,
          ],
          ['up-ann'],
          ['up-ben'],
        ),
        (
          'the tool tasks',
          toolTasksProvider,
          (c) async => [
            for (final t in (await c.read(toolTasksProvider.future)).tasks)
              t.id,
          ],
          ['tt-ann'],
          ['tt-ben'],
        ),
      ]) {
    test('reads $name again for the next account on the server', () async {
      final repo = FakeRepository(
        sessionState: const SessionState(authenticated: true, user: _ann),
      );
      _holdFor(repo, _ann);
      final container = ProviderContainer(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);
      // Kept alive, as the screen showing it would.
      final held = container.listen(provider, (_, _) {});
      addTearDown(held.close);
      expect(await read(container), annSees);

      // Ben signs in on the same server.
      _holdFor(repo, _ben);
      repo.sessionState = const SessionState(authenticated: true, user: _ben);
      await container.read(authControllerProvider.notifier).refreshSession();

      expect(await read(container), benSees);
    });
  }
}
