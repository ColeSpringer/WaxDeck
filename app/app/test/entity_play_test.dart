import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/music/album_play.dart';
import 'package:waxdeck/src/playlists/playlist_play.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'player_host.dart';

const _album = 'al-01JZX5N8QW3F4V9T2B7KDALBUM1';

ItemSummary _track(String pid, int number) => ItemSummary(
  pid: pid,
  mediaType: MediaType.music,
  title: 'Side $number',
  artist: 'Nightjar',
  album: 'Salt Harbour',
  albumPid: _album,
  trackNumber: number,
  durationMs: 200000,
);

/// A ref to call the verbs with, the way a tile's build hands one over.
Future<WidgetRef> _ref(WidgetTester tester, ProviderContainer container) async {
  late WidgetRef ref;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (_, r, _) {
          ref = r;
          return const SizedBox();
        },
      ),
    ),
  );
  return ref;
}

void main() {
  testWidgets('an album plays in pressing order, drilled by its bare key', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..facetItems['album ${_album.substring(3)}'] = <ItemSummary>[
        _track('tr-01JZX5N8QW3F4V9T2B7KDTRACK2', 2),
        _track('tr-01JZX5N8QW3F4V9T2B7KDTRACK1', 1),
      ];
    final container = playbackContainer(repo: repo, engine: FakeEngine());
    final ref = await _ref(tester, container);

    await playAlbumPid(ref, _album);
    await tester.pumpAndSettle();

    expect(repo.facetDrills.last, ('album', _album.substring(3)));
    final queue = container.read(queueControllerProvider);
    expect(
      <String>[for (final e in queue.entries) e.pid],
      <String>[
        'tr-01JZX5N8QW3F4V9T2B7KDTRACK1',
        'tr-01JZX5N8QW3F4V9T2B7KDTRACK2',
      ],
    );
    expect(queue.source.kind, QueueSourceKind.album);
    expect(queue.source.pid, _album);
    expect(queue.source.label, 'Salt Harbour');
    await PlayerHarness(container).endPlayback(tester);
  });

  testWidgets('an album plays under the name its card showed', (tester) async {
    final repo = FakeRepository()
      ..facetItems['album ${_album.substring(3)}'] = <ItemSummary>[
        _track('tr-01JZX5N8QW3F4V9T2B7KDTRACK1', 1),
      ];
    final container = playbackContainer(repo: repo, engine: FakeEngine());
    final ref = await _ref(tester, container);

    await playAlbumPid(ref, _album, label: 'Salt Harbour Deluxe');
    await tester.pumpAndSettle();

    expect(
      container.read(queueControllerProvider).source.label,
      'Salt Harbour Deluxe',
    );
    await PlayerHarness(container).endPlayback(tester);
  });

  testWidgets('an album with nothing in it leaves the queue alone', (
    tester,
  ) async {
    final repo = FakeRepository();
    final container = playbackContainer(repo: repo, engine: FakeEngine());
    final ref = await _ref(tester, container);

    await playAlbumPid(ref, _album);
    await tester.pumpAndSettle();
    expect(container.read(queueControllerProvider).isEmpty, isTrue);
  });

  testWidgets('a playlist plays its members as the playlist, shuffled too', (
    tester,
  ) async {
    final first = testItem('tr-01JZX5N8QW3F4V9T2B7KDTRACK1', title: 'One');
    final second = testItem('tr-01JZX5N8QW3F4V9T2B7KDTRACK2', title: 'Two');
    final repo = FakeRepository(items: <ItemSummary>[first, second]);
    final playlist = await repo.createPlaylist(
      name: 'Road',
      kind: 'static',
      itemPids: <String>[first.pid, second.pid],
    );
    final container = playbackContainer(repo: repo, engine: FakeEngine());
    final ref = await _ref(tester, container);

    await playPlaylistPid(ref, playlist.pid, shuffle: true);
    await tester.pumpAndSettle();

    final queue = container.read(queueControllerProvider);
    expect(
      <String>{for (final e in queue.entries) e.pid},
      <String>{first.pid, second.pid},
    );
    expect(queue.shuffled, isTrue);
    expect(queue.source.kind, QueueSourceKind.playlist);
    expect(queue.source.pid, playlist.pid);
    expect(queue.source.label, 'Road');
    await PlayerHarness(container).endPlayback(tester);
  });

  testWidgets('a long playlist starts from its first page', (tester) async {
    final members = <ItemSummary>[
      for (var i = 0; i < 600; i++)
        testItem('tr-LONG${i.toString().padLeft(4, '0')}', title: 'Track $i'),
    ];
    final repo = FakeRepository(items: members);
    final playlist = await repo.createPlaylist(
      name: 'Long Road',
      kind: 'static',
      itemPids: <String>[for (final item in members) item.pid],
    );
    final container = playbackContainer(repo: repo, engine: FakeEngine());
    final ref = await _ref(tester, container);

    // In order the queue keeps only the first 500, so one page starts it.
    await playPlaylistPid(ref, playlist.pid);
    await tester.pumpAndSettle();
    expect(repo.playlistItemPageCalls, <String>[playlist.pid]);
    expect(container.read(queueControllerProvider).entries, hasLength(500));

    // A shuffle draws from the whole list.
    repo.playlistItemPageCalls.clear();
    await playPlaylistPid(ref, playlist.pid, shuffle: true);
    await tester.pumpAndSettle();
    expect(repo.playlistItemPageCalls, hasLength(2));
    await PlayerHarness(container).endPlayback(tester);
  });

  testWidgets('a playlist that will not load says so at once', (tester) async {
    final repo = FakeRepository()
      ..getPlaylistError = const WaxDeckApiException(
        code: 'unavailable',
        message: 'the server is restarting',
        statusCode: 503,
      );
    final container = playbackContainer(repo: repo, engine: FakeEngine());
    final ref = await _ref(tester, container);

    unawaited(playPlaylistPid(ref, 'pl-1'));
    await tester.pump(const Duration(seconds: 1));
    expect(container.read(shellMessengerProvider), isNotNull);
    expect(container.read(queueControllerProvider).isEmpty, isTrue);
  });
}
