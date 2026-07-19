import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/playlists/playlist_screen.dart';
import 'package:waxdeck/src/playlists/playlists_screen.dart';
import 'package:waxdeck/src/playlists/rule_editor_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

const _track = ItemSummary(
  pid: 'tr-01JZX5N8QW3F4V9T2B7KD3M9R6',
  mediaType: MediaType.music,
  title: 'Prancing Pony Blues',
  artist: 'The Bree Trio',
  durationMs: 214000,
);

Widget _host(FakeRepository repo, Widget home) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: MaterialApp(home: home),
);

void main() {
  testWidgets('lists playlists and opens the detail screen', (tester) async {
    final repo = FakeRepository(items: const [_track]);
    await repo.createPlaylist(
      name: 'Road Trip',
      kind: 'static',
      itemPids: [_track.pid],
    );
    await tester.pumpWidget(_host(repo, const PlaylistsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Road Trip'), findsOneWidget);
    await tester.tap(find.text('Road Trip'));
    await tester.pumpAndSettle();

    expect(find.text('Prancing Pony Blues'), findsOneWidget);
    expect(find.textContaining('Manual playlist'), findsOneWidget);
  });

  testWidgets('creates a manual playlist through the dialog', (tester) async {
    final repo = FakeRepository(items: const [_track]);
    await tester.pumpWidget(_host(repo, const PlaylistsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('playlist-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('playlist-name-field')),
      'Evening',
    );
    await tester.tap(find.byKey(const Key('playlist-create-confirm')));
    await tester.pumpAndSettle();

    expect(repo.playlistsByPid.values.map((p) => p.name), contains('Evening'));
  });

  testWidgets('removes a member through the row affordance', (tester) async {
    final repo = FakeRepository(items: const [_track]);
    final created = await repo.createPlaylist(
      name: 'Trim me',
      kind: 'static',
      itemPids: [_track.pid],
    );
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: created.pid)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('playlist-entry-remove-0')));
    await tester.pumpAndSettle();

    expect(repo.playlistMembers[created.pid], isEmpty);
  });

  testWidgets('rule editor builds a rule, previews, and saves', (tester) async {
    final repo = FakeRepository(items: const [_track]);
    repo.previewResult = const PlaylistPreview(items: [_track], total: 42);
    await tester.pumpWidget(
      _host(repo, const RuleEditorScreen(createName: 'Best of')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('rule-add-condition')));
    await tester.pump();

    // The default condition is the first vocabulary field with its
    // first operator; switch it to a user-state rule.
    await tester.tap(find.byKey(const Key('rule-field-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('rating').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rule-op-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('gte').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rule-value-field')), '80');

    // The preview debounce is half a second.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Matches 42 items'), findsOneWidget);

    await tester.tap(find.byKey(const Key('rule-save')));
    await tester.pumpAndSettle();

    final saved = repo.playlistsByPid.values.singleWhere(
      (p) => p.name == 'Best of',
    );
    expect(saved.isSmart, isTrue);
    final condition = saved.rule!.root.nodes.single;
    expect(condition.field, 'rating');
    expect(condition.op, 'gte');
    expect(condition.value, '80');
  });

  testWidgets('editing a rule pops with the reissued playlist', (tester) async {
    final repo = FakeRepository(items: const [_track]);
    final created = await repo.createPlaylist(
      name: 'Smart',
      kind: 'smart',
      rule: const SmartRule(
        root: RuleNode.all([
          RuleNode.condition(field: 'rating', op: 'gte', value: '60'),
        ]),
      ),
    );
    Playlist? popped;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await Navigator.of(context).push<Playlist>(
                      MaterialPageRoute(
                        builder: (_) => RuleEditorScreen(editing: created),
                      ),
                    );
                  },
                  child: const Text('edit'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('edit'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('rule-value-field')), '90');
    await tester.tap(find.byKey(const Key('rule-save')));
    await tester.pumpAndSettle();

    expect(popped, isNotNull);
    expect(popped!.pid, isNot(created.pid));
    expect(popped!.previousPid, created.pid);
    expect(repo.playlistsByPid.containsKey(created.pid), isFalse);
  });

  testWidgets('imports a pasted M3U as a playlist', (tester) async {
    final repo = FakeRepository(items: const [_track])
      ..importMatched = 2
      ..importUnmatched = 1;
    await tester.pumpWidget(_host(repo, const PlaylistsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('playlist-import')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('m3u-name-field')),
      'From Another Player',
    );
    await tester.enterText(
      find.byKey(const Key('m3u-content-field')),
      '#EXTM3U\n/music/pony.flac\n',
    );
    await tester.tap(find.byKey(const Key('m3u-import-confirm')));
    await tester.pumpAndSettle();

    expect(repo.importedM3uContents.single, contains('/music/pony.flac'));
    expect(
      repo.playlistsByPid.values.map((p) => p.name),
      contains('From Another Player'),
    );
    expect(
      find.textContaining('2 matched, 1 not in the library'),
      findsOneWidget,
    );
  });

  testWidgets('exports a playlist as M3U with a copy affordance', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track])
      ..exportM3uResult =
          '#EXTM3U\n#EXTINF:214,Prancing Pony Blues\npony.flac\n';
    final created = await repo.createPlaylist(
      name: 'Road Trip',
      kind: 'static',
      itemPids: [_track.pid],
    );
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: created.pid)));
    await tester.pumpAndSettle();

    // Clipboard rides the platform channel, which has no host in
    // widget tests; without a mock the copy await never completes.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );

    await tester.tap(find.byKey(const Key('playlist-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export M3U'));
    await tester.pumpAndSettle();

    expect(repo.exportedM3uPids, [created.pid]);
    expect(find.textContaining('Prancing Pony Blues'), findsWidgets);
    await tester.tap(find.byKey(const Key('m3u-export-copy')));
    await tester.pumpAndSettle();
    expect(find.text('Playlist copied as M3U'), findsOneWidget);
  });
}
