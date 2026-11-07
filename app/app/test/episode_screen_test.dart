import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/player_screen.dart';
import 'package:waxdeck/src/podcasts/episode_screen.dart';
import 'package:waxdeck/src/podcasts/podcasts_screen.dart';
import 'package:waxdeck/src/podcasts/show_screen.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';
import 'player_host.dart';
import 'wax_finders.dart';

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

/// The episode screen over [repo], one frame in. [show] opens it at
/// its show's location. Unrouted unless [routed], the reverse of
/// [mountApp]'s default: [routed] hosts it over the app's route table, for
/// the cases that navigate.
Future<void> _mount(
  WidgetTester tester,
  FakeRepository repo, {
  String? show,
  bool routed = false,
}) => mountApp(
  tester,
  EpisodeScreen(pid: episodePid, showPid: show),
  container: appContainer(repo: repo),
  routed: routed,
);

/// [_mount], then settled. Returns the container the screen runs over.
Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeRepository repo, {
  String? show,
  bool routed = false,
}) => pumpApp(
  tester,
  EpisodeScreen(pid: episodePid, showPid: show),
  container: appContainer(repo: repo),
  routed: routed,
);

void main() {
  group('a failed episode read', () {
    // A removed episode is final: it is asked once, and a Try again under
    // it could only answer the same. A dropped connection still retries.
    testWidgets('a removed episode is final, says so, and offers no retry', (
      tester,
    ) async {
      final repo = FakeRepository();
      await _mount(tester, repo);
      await tester.pump();
      await tester.pump();

      expect(find.text('That is not here any more.'), findsOneWidget);
      expect(find.widgetWithText(WaxButton, 'Try again'), findsNothing);
      expect(repo.getEpisodeCalls, hasLength(1), reason: 'not retried');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a dropped read still retries, drawn busy', (tester) async {
      final repo = _EpisodeDown();
      await _mount(tester, repo);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      final retry = find.widgetWithText(WaxButton, 'Try again');
      expect(tester.widget<WaxButton>(retry).busy, isTrue);
      expect(repo.getEpisodeCalls.length, greaterThan(1));
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('a transcript on its way draws ghost rows, not a spinner', (
    tester,
  ) async {
    final repo = _repo()..getTranscriptGate = Completer<void>();
    await _pump(tester, repo);

    await tester.tap(find.text('Transcript'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(SkeletonShapes), findsOneWidget);
    expect(find.byType(WaxSpinner), findsNothing);
    repo.getTranscriptGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonShapes), findsNothing);
  });

  testWidgets('the transcript lazy-loads on expand and shows cues', (
    tester,
  ) async {
    final repo = _repo();
    await _pump(tester, repo);

    // Nothing fetched until the section expands.
    expect(find.text('Welcome back to the inn'), findsNothing);
    expect(find.byType(WaxDisclosure), findsOneWidget);
    await tester.tap(find.text('Transcript'));
    await tester.pumpAndSettle();

    expect(find.text('0:30'), findsOneWidget);
    expect(find.text('Welcome back to the inn'), findsOneWidget);

    // Opening the transcript also indexes it for search (streamed episodes
    // become findable by their words), fired once.
    expect(repo.captureTranscriptCalls, <String>[episodePid]);
  });

  testWidgets('a transcript is captured once an app session, however often '
      'it is opened and even when the capture failed', (tester) async {
    final repo = _repo()
      ..captureTranscriptError = const WaxDeckApiException(
        code: 'feature-unavailable',
        message: 'the transcript host did not answer',
        statusCode: 502,
      );
    final container = appContainer(repo: repo);
    Future<void> openTranscript() async {
      await pumpApp(
        tester,
        const EpisodeScreen(pid: episodePid),
        container: container,
        routed: false,
      );
      await tester.tap(find.text('Transcript'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back to the inn'), findsOneWidget);
    }

    await openTranscript();
    // Left and opened again: a screen of its own each time.
    await leaveScreen(tester, container);
    await openTranscript();

    expect(repo.captureTranscriptCalls, <String>[episodePid]);
  });

  testWidgets('a cue tap without a matching player shows the timestamp', (
    tester,
  ) async {
    await _pump(tester, _repo());
    await tester.tap(find.text('Transcript'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Welcome back to the inn'));
    await tester.pump();

    expect(shellMessageText(raisedMessage(tester)), 'Cue starts at 0:30');
  });

  testWidgets('a cue tap seeks the live player when the episode matches', (
    tester,
  ) async {
    final repo = _repo();
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    await pumpPlayer(
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
  });

  testWidgets('leaving an episode opened from a link lands on the hub', (
    tester,
  ) async {
    // Nothing to pop, and the show-less location names no show to return
    // to, so the hub is the nearest real place.
    await _pump(tester, _repo(), routed: true);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();

    expect(find.byType(PodcastsScreen), findsOneWidget);
  });

  testWidgets('leaving an episode opened at its show location lands on the '
      'show', (tester) async {
    // The canonical location carries the show, so a stranger opening the
    // link gets the same back behaviour a tap from the list does.
    await _pump(tester, _repo(), show: showPid, routed: true);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();

    expect(find.byType(ShowScreen), findsOneWidget);
  });

  testWidgets('a long show name over the episode keeps to one line', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const name =
        'The Prancing Pony Hour of Tales Told Late by the Fire at Bree';
    final repo = _repo()
      ..episodesByShow[showPid] = <EpisodeSummary>[
        testEpisode(episodePid, artist: name),
      ];
    await _pump(tester, repo, show: showPid);

    final link = find.ancestor(
      of: find.text(name),
      matching: find.byType(WaxButton),
    );
    expect(tester.widget<WaxButton>(link).kind, WaxButtonKind.inline);
    final line = tester.renderObject<RenderParagraph>(find.text(name));
    expect(line.maxLines, 1);
    expect(line.didExceedMaxLines, isTrue);
    expect(tester.getSize(link).height, WaxSpace.touchTarget);
  });

  testWidgets('the action bar queues and marks played', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _repo();
    final container = await _pump(tester, repo, show: showPid, routed: true);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.episodeQueue));
    await tester.pumpAndSettle();
    expect(
      container.read(queueControllerProvider).entries.map((e) => e.pid),
      <String>[episodePid],
    );
    expect(shellMessageText(raisedMessage(tester)), 'Added to the queue');

    // The write is out: the pill draws busy and takes no second press.
    final write = repo.putPlayStateGate = Completer<void>();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.episodeMarkPlayed),
    );
    await tester.pump();
    expect(
      tester
          .widget<WaxButton>(
            waxControl<WaxButton>(SemanticsIds.episodeMarkPlayed),
          )
          .busy,
      isTrue,
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.episodeMarkPlayed),
    );
    await tester.pump();
    write.complete();
    await tester.pumpAndSettle();
    // Played is a position at the full duration; there is no flag to set.
    expect(repo.putPlayStateCalls.single.pid, episodePid);
    expect(repo.putPlayStateCalls.single.positionMs, 214000);
    expect(shellMessageText(raisedMessage(tester)), 'Marked as played');
    // Finished is a state to read, not an unavailable control.
    expect(
      tester.getSemantics(
        find.bySemanticsIdentifier(SemanticsIds.episodeMarkPlayed),
      ),
      isSemantics(label: 'Played', isButton: false, hasEnabledState: false),
    );

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
    await _pump(tester, repo, show: showPid, routed: true);

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

  testWidgets('a queued fetch is a status pill in the bar, not a chip', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = FakeRepository()
      ..addSubscription(testShow(showPid))
      ..episodesByShow[showPid] = <EpisodeSummary>[
        testEpisode(episodePid, downloaded: false, fetchState: 'queued'),
      ];
    await _pump(tester, repo, show: showPid);

    expect(find.byType(CodecChip), findsNothing);
    Finder pill(String label) =>
        find.ancestor(of: find.text(label), matching: find.byType(WaxButton));
    expect(pill('Queued for download'), findsOneWidget);
    // A state to read, in the one bar beside the verbs.
    expect(
      tester.widget<WaxButton>(pill('Queued for download')).status,
      isTrue,
    );
    expect(
      find.ancestor(
        of: pill('Queued for download'),
        matching: find.byType(WaxActionBar),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(of: pill('Share'), matching: find.byType(WaxActionBar)),
      findsOneWidget,
    );
  });

  testWidgets('a failed fetch is one retry pill carrying the reason', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = FakeRepository()
      ..addSubscription(testShow(showPid))
      ..episodesByShow[showPid] = <EpisodeSummary>[
        testEpisode(
          episodePid,
          downloaded: false,
          fetchState: 'failed',
          fetchError: 'the host refused',
        ),
      ];
    await _pump(tester, repo, show: showPid);

    expect(find.byType(CodecChip), findsNothing);
    expect(find.text('Retry download'), findsOneWidget);
    expect(find.textContaining('the host refused'), findsNothing);
    final withReason = find.byWidgetPredicate(
      (w) => w is WaxButton && (w.detail ?? '').contains('the host refused'),
    );
    expect(withReason, findsOneWidget);
    expect(
      tester.widget<WaxButton>(withReason).semanticsId,
      SemanticsIds.episodeFetch(episodePid),
    );
  });

  testWidgets('pressing the retry pill queues the fetch and the slot reads '
      'queued', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = FakeRepository()
      ..addSubscription(testShow(showPid))
      ..episodesByShow[showPid] = <EpisodeSummary>[
        testEpisode(
          episodePid,
          downloaded: false,
          fetchState: 'failed',
          fetchError: 'the host refused',
        ),
      ];
    await _pump(tester, repo, show: showPid);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.episodeFetch(episodePid)),
    );
    await tester.pumpAndSettle();

    expect(repo.fetchEpisodeCalls, <String>[episodePid]);
    expect(find.text('Queued for download'), findsOneWidget);
    expect(find.text('Retry download'), findsNothing);
  });

  testWidgets('tapping the show name goes to the show', (tester) async {
    await _pump(tester, _repo(), show: showPid, routed: true);

    final link = find.ancestor(
      of: find.text('Barliman Butterbur'),
      matching: find.byType(WaxButton),
    );
    expect(tester.getSize(link).height, WaxSpace.touchTarget);
    await tester.tap(find.text('Barliman Butterbur'));
    await tester.pumpAndSettle();

    expect(find.byType(ShowScreen), findsOneWidget);
    expect(find.byType(EpisodeScreen), findsNothing);
  });
}

/// Drops the first episode read and holds every retry, as a connection
/// that has gone away does.
class _EpisodeDown extends FakeRepository {
  @override
  Future<EpisodeDetail> getEpisode(String pid) async {
    getEpisodeCalls.add(pid);
    if (getEpisodeCalls.length > 1) await Completer<void>().future;
    throw const WaxDeckApiException(
      code: 'internal',
      message: 'down',
      statusCode: 500,
    );
  }
}
