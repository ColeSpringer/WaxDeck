import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/play_progress.dart';
import 'package:waxdeck/src/podcasts/mark_older_played_dialog.dart';
import 'package:waxdeck/src/podcasts/show_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

const showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';

/// A show with a backlog: old enough for every preset to take them.
FakeRepository _repo({int episodes = 8}) {
  final repo = FakeRepository()..addSubscription(testShow(showPid));
  repo.episodesByShow[showPid] = <EpisodeSummary>[
    for (var i = 0; i < episodes; i++)
      testEpisode(
        'tr-ep$i',
        showPid: showPid,
        title: 'Episode $i',
        // Newest first, as the listing answers.
        publishedAt: DateTime.utc(2026, 1, episodes - i),
      ),
  ];
  return repo;
}

Future<ProviderContainer> _open(
  WidgetTester tester,
  FakeRepository repo,
) async {
  tester.view.physicalSize = const Size(900, 1800);
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

  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.showOverflow));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.markOlderPlayed));
  await tester.pumpAndSettle();
  expect(find.byType(MarkOlderPlayedDialog), findsOneWidget);
  return container;
}

void main() {
  testWidgets('marking a backlog played walks it oldest first', (tester) async {
    final repo = _repo(episodes: 4);
    await _open(tester, repo);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.markOlderConfirm));
    await tester.pumpAndSettle();

    // Every episode, at its own duration: played is derived from the
    // position reached, so there is no flag to set.
    expect(repo.putPlayStateCalls, hasLength(4));
    for (final call in repo.putPlayStateCalls) {
      expect(call.positionMs, 214000);
    }
    expect(find.byType(MarkOlderPlayedDialog), findsNothing);
    expect(find.text('4 episodes marked as played'), findsOneWidget);
  });

  testWidgets('stopping mid-run closes the dialog and nothing else', (
    tester,
  ) async {
    // The race this pins: Stop dismisses the dialog, and the checkpoint
    // already in flight lands during the dismissal animation, while the
    // State is still mounted. A run that then popped on its own way out
    // would pop the show screen out from under the visitor.
    final repo = _repo();
    final gate = Completer<void>();
    repo.putPlayStateGate = gate;
    await _open(tester, repo);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.markOlderConfirm));
    await tester.pump();

    await tester.tap(find.text('Stop'));
    await tester.pump();
    // The write lands inside the dismissal window.
    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(MarkOlderPlayedDialog), findsNothing);
    expect(
      find.byType(ShowScreen),
      findsOneWidget,
      reason: 'stopping must close the dialog, not the screen under it',
    );
  });

  testWidgets('what a stopped run already wrote still reaches the screen', (
    tester,
  ) async {
    // The listing and the positions beside it are stale the moment a
    // checkpoint lands, whether or not anybody is still looking at the
    // dialog that wrote it.
    final repo = _repo();
    final gate = Completer<void>();
    repo.putPlayStateGate = gate;
    final container = await _open(tester, repo);

    // Something is watching the progress read, as the show's list is.
    final key = playPidsKey(<String>['tr-ep7']);
    await container.read(playProgressProvider(key).future);
    final before = container.read(playProgressProvider(key));

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.markOlderConfirm));
    await tester.pump();
    await tester.tap(find.text('Stop'));
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();

    expect(repo.putPlayStateCalls, isNotEmpty);
    expect(
      identical(container.read(playProgressProvider(key)), before),
      isFalse,
      reason: 'a cancelled run still invalidates what it wrote past',
    );
  });
}
