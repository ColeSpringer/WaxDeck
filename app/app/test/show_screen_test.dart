import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/podcasts/show_screen.dart';
import 'package:waxdeck/src/providers.dart';

import 'fakes.dart';

const showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
const downloadedPid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';
const remotePid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0002';

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: const MaterialApp(home: ShowScreen(pid: showPid)),
);

FakeRepository _repo() => FakeRepository()
  ..addSubscription(testShow(showPid))
  ..episodesByShow[showPid] = [
    testEpisode(downloadedPid, title: 'Fetched Episode'),
    testEpisode(remotePid, title: 'Remote Episode', downloaded: false),
  ];

void main() {
  testWidgets('renders the header and the episode list', (tester) async {
    await tester.pumpWidget(_host(_repo()));
    await tester.pumpAndSettle();

    expect(find.text('The Prancing Pony Hour'), findsWidgets);
    expect(
      find.byKey(const ValueKey('episode-$downloadedPid')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('episode-$remotePid')), findsOneWidget);
    expect(find.text('Downloaded'), findsOneWidget);
    // Only the undownloaded row offers a fetch button.
    expect(
      find.byKey(const ValueKey('episode-fetch-$remotePid')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('episode-fetch-$downloadedPid')),
      findsNothing,
    );
  });

  testWidgets('the fetch button queues a server fetch optimistically', (
    tester,
  ) async {
    final repo = _repo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('episode-fetch-$remotePid')));
    await tester.pumpAndSettle();

    expect(repo.fetchEpisodeCalls, [remotePid]);
    expect(find.text('Queued'), findsOneWidget);
    expect(find.text('Fetching to server'), findsOneWidget);
  });

  testWidgets('the remove button reclaims a downloaded episode', (
    tester,
  ) async {
    final repo = _repo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    // Only the downloaded row offers removal.
    expect(
      find.byKey(const ValueKey('episode-remove-$downloadedPid')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('episode-remove-$remotePid')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('episode-remove-$downloadedPid')),
    );
    await tester.pumpAndSettle();

    expect(repo.removeDownloadCalls, [downloadedPid]);
    // The refetched list shows the row undownloaded: the remove icon is
    // gone and the fetch icon is back.
    expect(
      find.byKey(const ValueKey('episode-remove-$downloadedPid')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('episode-fetch-$downloadedPid')),
      findsOneWidget,
    );
    expect(find.textContaining('progress is kept'), findsOneWidget);
  });

  testWidgets('tapping an undownloaded episode fetches instead of playing', (
    tester,
  ) async {
    final repo = _repo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('episode-$remotePid')));
    await tester.pumpAndSettle();

    expect(repo.fetchEpisodeCalls, [remotePid]);
    expect(find.text('Fetching to server'), findsOneWidget);
    // No player was pushed.
    expect(find.byKey(const Key('player-toggle')), findsNothing);
  });

  testWidgets('the settings sheet saves the complete settings object', (
    tester,
  ) async {
    final repo = _repo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('podcast-settings-open')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('podcast-settings-trim')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('podcast-settings-retention')),
      '5',
    );
    await tester.tap(find.byKey(const Key('podcast-settings-save')));
    await tester.pumpAndSettle();

    expect(repo.putSubscriptionSettingsCalls, hasLength(1));
    final saved = repo.putSubscriptionSettingsCalls.single;
    expect(saved.pid, showPid);
    expect(saved.settings.trimSilence, isTrue);
    expect(saved.settings.retentionKeep, 5);
    expect(saved.settings.speed, closeTo(1.0, 0.001));
    // The sheet closed on success.
    expect(find.byKey(const Key('podcast-settings-save')), findsNothing);
  });

  testWidgets('unsubscribe and subscribe flip the button', (tester) async {
    final repo = _repo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    // A downloaded episode exists, so unsubscribing asks about the
    // files first; keeping them leaves the download in place.
    await tester.tap(find.byKey(const Key('podcast-unsubscribe')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('unsubscribe-keep-files')));
    await tester.pumpAndSettle();
    expect(repo.unsubscribeCalls, [showPid]);
    expect(repo.unsubscribeRemoveDownloadsCalls, isEmpty);
    expect(find.byKey(const Key('podcast-subscribe')), findsOneWidget);

    await tester.tap(find.byKey(const Key('podcast-subscribe')));
    await tester.pumpAndSettle();
    expect(repo.subscribeCalls, hasLength(1));
    expect(find.byKey(const Key('podcast-unsubscribe')), findsOneWidget);
  });

  testWidgets('unsubscribing can reclaim the server downloads', (tester) async {
    final repo = _repo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('podcast-unsubscribe')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('unsubscribe-remove-files')));
    await tester.pumpAndSettle();

    expect(repo.unsubscribeCalls, [showPid]);
    expect(repo.unsubscribeRemoveDownloadsCalls, [showPid]);
    // The refreshed list shows the episode undownloaded.
    expect(find.text('Downloaded'), findsNothing);
    expect(
      find.byKey(const ValueKey('episode-fetch-$downloadedPid')),
      findsOneWidget,
    );
  });

  testWidgets('unsubscribe skips the file question when nothing is fetched', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..addSubscription(testShow(showPid))
      ..episodesByShow[showPid] = [
        testEpisode(remotePid, title: 'Remote Episode', downloaded: false),
      ];
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('podcast-unsubscribe')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unsubscribe-keep-files')), findsNothing);
    expect(repo.unsubscribeCalls, [showPid]);
    expect(find.byKey(const Key('podcast-subscribe')), findsOneWidget);
  });
}
