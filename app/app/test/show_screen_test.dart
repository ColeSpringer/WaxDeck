import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/metadata/artwork_manager.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/podcasts/podcasts_controller.dart';
import 'package:waxdeck/src/podcasts/show_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

const showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
const downloadedPid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';
const remotePid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0002';

FakeRepository _repo() => FakeRepository()
  ..addSubscription(testShow(showPid))
  ..episodesByShow[showPid] = <EpisodeSummary>[
    testEpisode(downloadedPid, title: 'Fetched Episode'),
    testEpisode(remotePid, title: 'Remote Episode', downloaded: false),
  ];

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeRepository repo, {
  Size size = const Size(900, 1800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      audioEngineProvider.overrideWithValue(FakeEngine()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: routedHost(const ShowScreen(pid: showPid)),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Stops what a test started: a playing engine keeps a ticker running,
/// and a pending timer fails at teardown rather than where it began.
Future<void> _stop(WidgetTester tester, ProviderContainer container) async {
  container.read(queueControllerProvider.notifier).clear();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the header and the episode list', (tester) async {
    await _pump(tester, _repo());

    expect(find.text('The Prancing Pony Hour'), findsWidgets);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.episode(downloadedPid)),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.episode(remotePid)),
      findsOneWidget,
    );
    // Only the undownloaded row offers a fetch button, and only the
    // downloaded one offers removal.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.episodeFetch(remotePid)),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.episodeFetch(downloadedPid)),
      findsNothing,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.episodeRemove(downloadedPid)),
      findsOneWidget,
    );
  });

  testWidgets('the fetch button queues a server fetch optimistically', (
    tester,
  ) async {
    final repo = _repo();
    await _pump(tester, repo);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.episodeFetch(remotePid)),
    );
    await tester.pumpAndSettle();

    expect(repo.fetchEpisodeCalls, <String>[remotePid]);
    expect(find.text('Queued for download'), findsOneWidget);
    expect(find.text('Fetching to server'), findsOneWidget);
  });

  testWidgets('the remove button reclaims a downloaded episode', (
    tester,
  ) async {
    final repo = _repo();
    await _pump(tester, repo);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.episodeRemove(downloadedPid)),
    );
    await tester.pumpAndSettle();

    expect(repo.removeDownloadCalls, <String>[downloadedPid]);
    // The refetched list shows the row undownloaded: the remove control
    // is gone and the fetch control is back.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.episodeRemove(downloadedPid)),
      findsNothing,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.episodeFetch(downloadedPid)),
      findsOneWidget,
    );
    expect(find.textContaining('progress is kept'), findsOneWidget);
  });

  testWidgets('an unfetched episode with an enclosure plays rather than '
      'queueing a fetch', (tester) async {
    // The passthrough contract: `downloaded` no longer decides whether an
    // episode plays. This row streams relayed from the feed's own host.
    final repo = _repo();
    final container = await _pump(tester, repo);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.episode(remotePid)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.fetchEpisodeCalls, isEmpty);
    expect(
      container.read(queueControllerProvider).entries.map((e) => e.pid),
      <String>[remotePid],
    );
    await _stop(tester, container);
  });

  testWidgets('an episode whose feed named no audio falls back to fetching', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..addSubscription(testShow(showPid))
      ..episodesByShow[showPid] = <EpisodeSummary>[
        testEpisode(
          remotePid,
          title: 'Silent Feed',
          downloaded: false,
          hasEnclosure: false,
        ),
      ];
    final container = await _pump(tester, repo);

    expect(find.text('No audio in the feed'), findsOneWidget);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.episode(remotePid)),
    );
    await tester.pumpAndSettle();

    expect(repo.fetchEpisodeCalls, <String>[remotePid]);
    expect(container.read(queueControllerProvider).entries, isEmpty);
    expect(find.textContaining('named no audio to stream'), findsOneWidget);
  });

  testWidgets('the unplayed filter hides what the caller has heard', (
    tester,
  ) async {
    final repo = _repo()
      // Played is server-derived from the position reached, so a finished
      // pid is what the fake reports played.
      ..finishedPids.add(downloadedPid);
    await _pump(tester, repo);

    expect(find.text('Fetched Episode'), findsOneWidget);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.showEpisodeFilter('unplayed')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fetched Episode'), findsNothing);
    expect(find.text('Remote Episode'), findsOneWidget);
  });

  testWidgets('the unplayed filter means never started', (tester) async {
    final repo = _repo()
      ..finishedPids.add(downloadedPid)
      // Five minutes into the other episode: in progress, which the
      // server's unplayed shelf excludes, so this chip must too.
      ..playPositions[remotePid] = 300000;
    await _pump(tester, repo);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.showEpisodeFilter('unplayed')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fetched Episode'), findsNothing);
    expect(find.text('Remote Episode'), findsNothing);
  });

  testWidgets('search within the show narrows the loaded pages', (
    tester,
  ) async {
    await _pump(tester, _repo());

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.showEpisodeSearch),
      'remote',
    );
    await tester.pumpAndSettle();

    expect(find.text('Fetched Episode'), findsNothing);
    expect(find.text('Remote Episode'), findsOneWidget);
  });

  testWidgets('the unplayed filter means never started', (tester) async {
    final repo = _repo()
      ..finishedPids.add(downloadedPid)
      // Five minutes into the other episode: in progress, which the
      // server's unplayed shelf excludes, so this chip must too.
      ..playPositions[remotePid] = 300000;
    await _pump(tester, repo);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.showEpisodeFilter('unplayed')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fetched Episode'), findsNothing);
    expect(find.text('Remote Episode'), findsNothing);
  });

  testWidgets('no season chip where the feed numbers none', (tester) async {
    await _pump(tester, _repo());
    expect(find.text('Season 2'), findsNothing);
  });

  testWidgets('a season chip narrows to its own season', (tester) async {
    final repo = FakeRepository()
      ..addSubscription(testShow(showPid))
      ..episodesByShow[showPid] = <EpisodeSummary>[
        testEpisode(downloadedPid, title: 'S1', season: 1, episodeNumber: 1),
        testEpisode(remotePid, title: 'S2', season: 2, episodeNumber: 1),
      ];
    await _pump(tester, repo);

    expect(find.text('Season 2'), findsOneWidget);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.showEpisodeFilter('season-2')),
    );
    await tester.pumpAndSettle();
    expect(find.text('S1'), findsNothing);
    expect(find.text('S2'), findsOneWidget);
  });

  testWidgets('a long press starts a selection and the batch marks played', (
    tester,
  ) async {
    final repo = _repo();
    await _pump(tester, repo);

    await tester.longPress(
      find.bySemanticsIdentifier(SemanticsIds.episode(remotePid)),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.selectionMarkPlayed),
    );
    await tester.pumpAndSettle();

    // Played is a position at the full duration; there is no flag to set.
    expect(repo.putPlayStateCalls, hasLength(1));
    expect(repo.putPlayStateCalls.single.pid, remotePid);
    expect(repo.putPlayStateCalls.single.positionMs, 214000);
    expect(find.text('1 marked played'), findsOneWidget);
  });

  testWidgets('add to queue appends and does not touch what is playing', (
    tester,
  ) async {
    final repo = _repo();
    final container = await _pump(tester, repo);

    // Something is already playing, started the way the app starts it:
    // through the play verb, which records the summary the session
    // resolves from. Writing straight to the queue would leave the
    // session fetching a pid the fake's item table has never heard of.
    container.read(nowPlayingProvider.notifier).play(<ItemSummary>[
      testEpisode(downloadedPid),
    ], source: QueueSource.none);
    await tester.pumpAndSettle();

    await tester.longPress(
      find.bySemanticsIdentifier(SemanticsIds.episode(remotePid)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.selectionQueue));
    await tester.pumpAndSettle();

    // Appended, and the entry that was playing is still the current one:
    // the replace-and-start verb would have thrown it away.
    final queue = container.read(queueControllerProvider);
    expect(queue.entries.map((e) => e.pid), <String>[downloadedPid, remotePid]);
    expect(queue.currentEntry?.pid, downloadedPid);
    expect(find.text('1 added to the queue'), findsOneWidget);
    await _stop(tester, container);
  });

  testWidgets('an episode with no audio is refused rather than queued', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..addSubscription(testShow(showPid))
      ..episodesByShow[showPid] = <EpisodeSummary>[
        testEpisode(
          remotePid,
          title: 'Silent Feed',
          downloaded: false,
          hasEnclosure: false,
        ),
      ];
    final container = await _pump(tester, repo);

    await tester.longPress(
      find.bySemanticsIdentifier(SemanticsIds.episode(remotePid)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.selectionQueue));
    await tester.pumpAndSettle();

    expect(container.read(queueControllerProvider).entries, isEmpty);
    expect(find.textContaining('had no audio in the feed'), findsOneWidget);
  });

  testWidgets('a filter that empties the loaded pages can still reach the '
      'rest', (tester) async {
    // The trap: a list with no rows does not scroll, so the notification
    // that pages the next one can never fire. The way out has to be a
    // control.
    final repo = FakeRepository()..addSubscription(testShow(showPid));
    repo.episodesByShow[showPid] = <EpisodeSummary>[
      // A first page's worth, all played, with one unplayed behind it.
      for (var i = 0; i < EpisodesController.pageSize; i++)
        testEpisode('tr-old$i', showPid: showPid, title: 'Heard $i'),
      testEpisode('tr-fresh', showPid: showPid, title: 'Unheard'),
    ];
    for (var i = 0; i < EpisodesController.pageSize; i++) {
      repo.finishedPids.add('tr-old$i');
    }
    await _pump(tester, repo);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.showEpisodeFilter('unplayed')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nothing matches yet'), findsOneWidget);

    await tester.tap(find.text('Load more episodes'));
    await tester.pumpAndSettle();
    expect(find.text('Unheard'), findsOneWidget);
  });

  testWidgets('a filter that leaves one of fifty can still reach the rest', (
    tester,
  ) async {
    // One step short of empty, and worse: a row reads as an answer, and
    // is still too short to scroll the next page in.
    final repo = FakeRepository()..addSubscription(testShow(showPid));
    repo.episodesByShow[showPid] = <EpisodeSummary>[
      for (var i = 0; i < EpisodesController.pageSize; i++)
        testEpisode('tr-old$i', showPid: showPid, title: 'Cassette $i'),
      testEpisode('tr-fresh', showPid: showPid, title: 'Cassette later'),
    ];
    await _pump(tester, repo);

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.showEpisodeSearch),
      'sette 7',
    );
    await tester.pumpAndSettle();
    expect(find.text('Cassette 7'), findsOneWidget);

    await tester.tap(find.text('Load more episodes'));
    await tester.pumpAndSettle();

    // Out of pages, so the control goes: what is on screen is the whole
    // answer now.
    expect(find.text('Load more episodes'), findsNothing);
  });

  testWidgets('an unnarrowed list pages by scrolling alone', (tester) async {
    final repo = FakeRepository()..addSubscription(testShow(showPid));
    repo.episodesByShow[showPid] = <EpisodeSummary>[
      for (var i = 0; i < EpisodesController.pageSize + 1; i++)
        testEpisode('tr-$i', showPid: showPid, title: 'Episode $i'),
    ];
    await _pump(tester, repo);
    expect(find.text('Load more episodes'), findsNothing);
  });

  testWidgets('paging reads the play states of the new page only', (
    tester,
  ) async {
    // Keyed by the whole loaded list, page five would cost five pages of
    // play states; keyed by window, it costs one.
    final repo = FakeRepository()..addSubscription(testShow(showPid));
    repo.episodesByShow[showPid] = <EpisodeSummary>[
      for (var i = 0; i < EpisodesController.pageSize + 5; i++)
        testEpisode('tr-$i', showPid: showPid, title: 'Episode $i'),
    ];
    final container = await _pump(tester, repo);
    final afterFirst = repo.playStateBatches.length;
    expect(afterFirst, greaterThan(0));

    await container.read(episodesProvider(showPid).notifier).loadMore();
    await tester.pumpAndSettle();

    // The window that just arrived, not everything before it: five rows
    // rather than the fifty-five now loaded.
    expect(repo.playStateBatches.length, greaterThan(afterFirst));
    expect(repo.playStateBatches.last, hasLength(5));
  });

  testWidgets('the settings sheet saves the complete settings object', (
    tester,
  ) async {
    final repo = _repo();
    await _pump(tester, repo);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.podcastSettingsOpen),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('podcast-settings-trim')),
        matching: find.byType(WaxSwitch),
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('podcast-settings-retention')),
      '5',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.podcastSettingsSave),
    );
    await tester.pumpAndSettle();

    expect(repo.putSubscriptionSettingsCalls, hasLength(1));
    final saved = repo.putSubscriptionSettingsCalls.single;
    expect(saved.pid, showPid);
    expect(saved.settings.trimSilence, isTrue);
    expect(saved.settings.retentionKeep, 5);
    expect(saved.settings.speed, closeTo(1.0, 0.001));
    // The sheet closed on success.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.podcastSettingsSave),
      findsNothing,
    );
  });

  testWidgets('the keyword filter round-trips through the settings sheet', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..addSubscription(
        testShow(showPid),
        settings: const SubscriptionSettings(
          autoDownload: true,
          autoDownloadFilter: EpisodeFilter(include: <String>['mailbag']),
        ),
      )
      ..episodesByShow[showPid] = <EpisodeSummary>[testEpisode(downloadedPid)];
    await _pump(tester, repo);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.podcastSettingsOpen),
    );
    await tester.pumpAndSettle();

    // The stored filter is what the field shows.
    expect(find.text('mailbag'), findsOneWidget);
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.podcastSettingsExclude),
      'rerun, trailer',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.podcastSettingsSave),
    );
    await tester.pumpAndSettle();

    final saved = repo.putSubscriptionSettingsCalls.single.settings;
    expect(saved.autoDownloadFilter?.include, <String>['mailbag']);
    expect(saved.autoDownloadFilter?.exclude, <String>['rerun', 'trailer']);
  });

  testWidgets('an empty filter is saved as absent, not as empty lists', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..addSubscription(
        testShow(showPid),
        settings: const SubscriptionSettings(autoDownload: true),
      )
      ..episodesByShow[showPid] = <EpisodeSummary>[testEpisode(downloadedPid)];
    await _pump(tester, repo);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.podcastSettingsOpen),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.podcastSettingsSave),
    );
    await tester.pumpAndSettle();

    expect(
      repo.putSubscriptionSettingsCalls.single.settings.autoDownloadFilter,
      isNull,
    );
  });

  testWidgets('the numeric settings are held to what the contract takes', (
    tester,
  ) async {
    // A number keyboard still offers a minus sign, and a refusal from
    // the server for something the field could have prevented is a
    // round trip spent telling a listener off for typing.
    final repo = _repo();
    await _pump(tester, repo);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.podcastSettingsOpen),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('podcast-settings-skip-intro')),
      '-10',
    );
    await tester.enterText(
      find.byKey(const Key('podcast-settings-skip-outro')),
      '9000',
    );
    await tester.enterText(
      find.byKey(const Key('podcast-settings-retention')),
      '-5',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.podcastSettingsSave),
    );
    await tester.pumpAndSettle();

    final saved = repo.putSubscriptionSettingsCalls.single.settings;
    expect(saved.skipIntroSeconds, 0);
    expect(saved.skipOutroSeconds, 600);
    expect(saved.retentionKeep, 0);
  });

  testWidgets('unfollow and follow flip the button', (tester) async {
    final repo = _repo();
    await _pump(tester, repo);

    // A downloaded episode exists, so unfollowing asks about the files
    // first; keeping them leaves the download in place.
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.podcastUnsubscribe),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.unsubscribeKeepFiles),
    );
    await tester.pumpAndSettle();
    expect(repo.unsubscribeCalls, <String>[showPid]);
    expect(repo.unsubscribeRemoveDownloadsCalls, isEmpty);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.podcastSubscribe),
      findsOneWidget,
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.podcastSubscribe));
    await tester.pumpAndSettle();
    expect(repo.subscribeCalls, hasLength(1));
    expect(
      find.bySemanticsIdentifier(SemanticsIds.podcastUnsubscribe),
      findsOneWidget,
    );
  });

  testWidgets('unfollowing can reclaim the server downloads', (tester) async {
    final repo = _repo();
    await _pump(tester, repo);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.podcastUnsubscribe),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.unsubscribeRemoveFiles),
    );
    await tester.pumpAndSettle();

    expect(repo.unsubscribeCalls, <String>[showPid]);
    expect(repo.unsubscribeRemoveDownloadsCalls, <String>[showPid]);
    // The refreshed list shows the episode undownloaded.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.episodeFetch(downloadedPid)),
      findsOneWidget,
    );
  });

  testWidgets('unfollow skips the file question when nothing is fetched', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..addSubscription(testShow(showPid))
      ..episodesByShow[showPid] = <EpisodeSummary>[
        testEpisode(remotePid, title: 'Remote Episode', downloaded: false),
      ];
    await _pump(tester, repo);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.podcastUnsubscribe),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.unsubscribeKeepFiles),
      findsNothing,
    );
    expect(repo.unsubscribeCalls, <String>[showPid]);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.podcastSubscribe),
      findsOneWidget,
    );
  });

  testWidgets('explicit shows and episodes say so', (tester) async {
    final repo = FakeRepository()
      ..addSubscription(testShow(showPid, explicit: true))
      ..episodesByShow[showPid] = <EpisodeSummary>[
        testEpisode(downloadedPid, title: 'Marked Episode', explicit: true),
        testEpisode(remotePid, title: 'Clean Episode', downloaded: false),
      ];
    await _pump(tester, repo);

    // Once in the header's metadata line, once on the row that carries it.
    expect(find.textContaining('Explicit'), findsNWidgets(2));
  });

  testWidgets('the overflow offers the cover manager to a podcast curator', (
    tester,
  ) async {
    await _pumpAs(tester, _curatorRepo(managePodcasts: true));

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.showOverflow));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.showSetCover));
    await tester.pumpAndSettle();

    // The sheet hosts the artwork manager on the show's own pid, in its
    // entity branch (set, clear, and pin ride the podcast entity
    // endpoints).
    expect(find.byType(ShowCoverSheet), findsOneWidget);
    final manager = tester.widget<ArtworkManager>(find.byType(ArtworkManager));
    expect(manager.pid, showPid);
    expect(manager.entityType, 'podcast');
  });

  testWidgets('the overflow hides the cover entry without the permission', (
    tester,
  ) async {
    await _pumpAs(tester, _curatorRepo(managePodcasts: false));

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.showOverflow));
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier(SemanticsIds.showSetCover), findsNothing);
  });
}

/// A signed-in non-admin session whose podcast-curation right is the
/// server's effective answer, which is all the overflow gates on.
FakeRepository _curatorRepo({required bool managePodcasts}) =>
    FakeRepository(
        sessionState: SessionState(
          authenticated: true,
          user: WaxDeckUser(
            id: 'us-1',
            username: 'curator',
            roles: const <String>['member'],
            managePodcasts: managePodcasts,
          ),
        ),
      )
      ..addSubscription(testShow(showPid))
      ..episodesByShow[showPid] = <EpisodeSummary>[
        testEpisode(downloadedPid, title: 'Fetched Episode'),
      ];

/// _pump plus the credential store the auth controller reads on
/// non-web, which the session-gated tests need.
Future<void> _pumpAs(WidgetTester tester, FakeRepository repo) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        audioEngineProvider.overrideWithValue(FakeEngine()),
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      ],
      child: routedHost(const ShowScreen(pid: showPid)),
    ),
  );
  await tester.pumpAndSettle();
}
