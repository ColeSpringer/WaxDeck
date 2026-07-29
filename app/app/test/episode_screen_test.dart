import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/player_screen.dart';
import 'package:waxdeck/src/podcasts/episode_screen.dart';
import 'package:waxdeck/src/podcasts/podcasts_screen.dart';
import 'package:waxdeck/src/podcasts/show_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'player_host.dart';
import 'routed_host.dart';

const showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
const episodePid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';

FakeRepository _repo() => FakeRepository()
  ..addSubscription(testShow(showPid))
  ..episodesByShow[showPid] = <EpisodeSummary>[
    testEpisode(episodePid, hasTranscript: true),
  ]
  ..transcripts[episodePid] = const Transcript(
    format: 'vtt',
    cues: <TranscriptCue>[
      TranscriptCue(startMs: 30000, text: 'Welcome back to the inn'),
    ],
  );

Widget _host(FakeRepository repo, FakeEngine engine, Widget home) =>
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        audioEngineProvider.overrideWithValue(engine),
      ],
      child: MaterialApp(home: home),
    );

void main() {
  testWidgets('the transcript lazy-loads on expand and shows cues', (
    tester,
  ) async {
    final repo = _repo();
    await tester.pumpWidget(
      _host(repo, FakeEngine(), const EpisodeScreen(pid: episodePid)),
    );
    await tester.pumpAndSettle();

    // Nothing fetched until the section expands.
    expect(find.text('Welcome back to the inn'), findsNothing);
    await tester.tap(find.text('Transcript'));
    await tester.pumpAndSettle();

    expect(find.text('0:30'), findsOneWidget);
    expect(find.text('Welcome back to the inn'), findsOneWidget);

    // Opening the transcript also indexes it for search (streamed episodes
    // become findable by their words), fired once.
    expect(repo.captureTranscriptCalls, <String>[episodePid]);
  });

  testWidgets('a cue tap without a matching player shows the timestamp', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_repo(), FakeEngine(), const EpisodeScreen(pid: episodePid)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transcript'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Welcome back to the inn'));
    await tester.pump();

    expect(find.text('Cue starts at 0:30'), findsOneWidget);
  });

  testWidgets('a cue tap seeks the live player when the episode matches', (
    tester,
  ) async {
    final repo = _repo();
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testEpisode(episodePid),
    );
    expect(engine.playing, isTrue);

    // Open the episode detail on top of the live player.
    final context = tester.element(find.byType(PlayerScreen));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const EpisodeScreen(pid: episodePid),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transcript'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Welcome back to the inn'));
    await tester.pumpAndSettle();

    expect(engine.position, const Duration(seconds: 30));
    await harness.endPlayback(tester);
  });

  testWidgets('leaving an episode opened from a link lands on the hub', (
    tester,
  ) async {
    // Nothing to pop, and the show-less location names no show to return
    // to, so the hub is the nearest real place.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(_repo()),
          audioEngineProvider.overrideWithValue(FakeEngine()),
        ],
        child: routedHost(const EpisodeScreen(pid: episodePid)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();

    expect(find.byType(PodcastsScreen), findsOneWidget);
  });

  testWidgets('leaving an episode opened at its show location lands on the '
      'show', (tester) async {
    // The canonical location carries the show, so a stranger opening the
    // link gets the same back behaviour a tap from the list does.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(_repo()),
          audioEngineProvider.overrideWithValue(FakeEngine()),
        ],
        child: routedHost(
          const EpisodeScreen(pid: episodePid, showPid: showPid),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();

    expect(find.byType(ShowScreen), findsOneWidget);
  });

  testWidgets('the action bar queues and marks played', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _repo();
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
        child: routedHost(
          const EpisodeScreen(pid: episodePid, showPid: showPid),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.episodeQueue));
    await tester.pumpAndSettle();
    expect(
      container.read(queueControllerProvider).entries.map((e) => e.pid),
      <String>[episodePid],
    );
    expect(find.text('Added to the queue'), findsOneWidget);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.episodeMarkPlayed),
    );
    await tester.pumpAndSettle();
    // Played is a position at the full duration; there is no flag to set.
    expect(repo.putPlayStateCalls.single.pid, episodePid);
    expect(repo.putPlayStateCalls.single.positionMs, 214000);
    expect(find.text('Marked as played'), findsOneWidget);

    container.read(queueControllerProvider.notifier).clear();
    await tester.pumpAndSettle();
  });

  testWidgets('an episode whose feed named no audio offers a fetch, not a '
      'play', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = FakeRepository()
      ..addSubscription(testShow(showPid))
      ..episodesByShow[showPid] = <EpisodeSummary>[
        testEpisode(episodePid, downloaded: false, hasEnclosure: false),
      ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          audioEngineProvider.overrideWithValue(FakeEngine()),
        ],
        child: routedHost(
          const EpisodeScreen(pid: episodePid, showPid: showPid),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fetch to play'), findsOneWidget);
    // Queueing something that cannot play is refused rather than
    // dropping a dead entry into the queue.
    expect(
      tester
          .widget<WaxButton>(
            find.ancestor(
              of: find.text('Add to queue'),
              matching: find.byType(WaxButton),
            ),
          )
          .onPressed,
      isNull,
    );
  });
}
