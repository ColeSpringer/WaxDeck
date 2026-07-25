import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/player_screen.dart';
import 'package:waxdeck/src/podcasts/episode_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'player_host.dart';

const showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
const episodePid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';

FakeRepository _repo() => FakeRepository()
  ..addSubscription(testShow(showPid))
  ..episodesByShow[showPid] = [testEpisode(episodePid, hasTranscript: true)]
  ..transcripts[episodePid] = const Transcript(
    format: 'vtt',
    cues: [TranscriptCue(startMs: 30000, text: 'Welcome back to the inn')],
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
    expect(repo.captureTranscriptCalls, [episodePid]);
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
}
