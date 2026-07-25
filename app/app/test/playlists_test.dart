import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/playlists/playlist_cover.dart';
import 'package:waxdeck/src/playlists/playlist_screen.dart';
import 'package:waxdeck/src/playlists/playlists_screen.dart';
import 'package:waxdeck/src/playlists/rule_editor_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';
import 'routed_host.dart';

const _track = ItemSummary(
  pid: 'tr-01JZX5N8QW3F4V9T2B7KD3M9R6',
  mediaType: MediaType.music,
  title: 'Prancing Pony Blues',
  artist: 'The Bree Trio',
  durationMs: 214000,
);

Widget _host(FakeRepository repo, Widget home, {FilePickerPort? picker}) =>
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        // The port is real on the host running these tests, so pin it:
        // null hides every pick affordance, a fake proves one shows.
        filePickerProvider.overrideWithValue(picker),
      ],
      // Every one of these screens is pushed in the app, and some pop
      // themselves on save or delete.
      child: routedHost(home, pushed: true),
    );

/// A picker that resolves pickFile to one fixed image.
class _CoverPicker implements FilePickerPort {
  _CoverPicker(this.image);

  final PickedAudioFile? image;

  @override
  bool get canPickFolders => false;

  @override
  Future<List<PickedAudioFile>> pickAudioFiles() async => const [];

  @override
  Future<List<PickedAudioFile>> pickAudioFolder() async => const [];

  @override
  Future<PickedAudioFile?> pickFile({
    required Set<String> extensions,
    required String label,
  }) async => image;
}

/// A playlist carrying a cover. The wire says only that one exists; the
/// repository layer turns that into the art endpoint's URL under the
/// playlist's own pid.
Playlist _covered({
  String pid = 'pl-COVERED',
  String? artUrl = '/api/v1/items/pl-COVERED/art',
}) => Playlist(
  pid: pid,
  name: 'Covered',
  kind: 'static',
  visibility: 'private',
  ownerName: 'me',
  isOwner: true,
  itemCount: 1,
  artUrl: artUrl,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
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

  testWidgets('editing a rule pops with the updated playlist in place', (
    tester,
  ) async {
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
        child: routedHost(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await context.push<Playlist>(
                      WaxRoute.playlistEdit(created.pid),
                      extra: created,
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
    expect(popped!.pid, created.pid);
    expect(popped!.previousPid, isNull);
    expect(repo.playlistsByPid.containsKey(created.pid), isTrue);
    expect(popped!.rule!.root.nodes.single.value, '90');
  });

  testWidgets('rule editor sets a random limit mode', (tester) async {
    final repo = FakeRepository(items: const [_track]);
    repo.previewResult = const PlaylistPreview(items: [_track], total: 5);
    await tester.pumpWidget(
      _host(repo, const RuleEditorScreen(createName: 'Shuffle')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('rule-limit-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('at random').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rule-limit-field')), '10');
    await tester.pump();

    // The sorts card collapses to its random-mode note.
    expect(find.text('A random limit draws its own order.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('rule-save')));
    await tester.pumpAndSettle();

    final saved = repo.playlistsByPid.values.singleWhere(
      (p) => p.name == 'Shuffle',
    );
    expect(saved.rule!.limitMode, 'random');
    expect(saved.rule!.limit, 10);
  });

  testWidgets('pinning a budget limit drops its sort order', (tester) async {
    final repo = FakeRepository(items: const [_track]);
    repo.previewResult = const PlaylistPreview(items: [_track], total: 3);
    await tester.pumpWidget(
      _host(repo, const RuleEditorScreen(createName: 'Hour')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('rule-limit-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('by minutes').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rule-limit-field')), '60');
    await tester.pump();

    // A budget without a pinned seed may sort; add one.
    await tester.tap(find.byKey(const Key('rule-add-sort')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rule-add-sort')), findsOneWidget);

    // Pinning the selection makes the seed supply the order, so the sort
    // card collapses and the staged sort is dropped: the saved rule can
    // never carry the seed+sort pair the server rejects.
    await tester.tap(find.byKey(const Key('rule-limit-seed')));
    await tester.pumpAndSettle();
    expect(find.text('A pinned budget draws its own order.'), findsOneWidget);
    expect(find.byKey(const Key('rule-add-sort')), findsNothing);

    await tester.tap(find.byKey(const Key('rule-save')));
    await tester.pumpAndSettle();

    final saved = repo.playlistsByPid.values.singleWhere(
      (p) => p.name == 'Hour',
    );
    expect(saved.rule!.limitMode, 'minutes');
    expect(saved.rule!.limitSeed, isNot(0));
    expect(saved.rule!.sorts, isEmpty);
  });

  testWidgets('a random limit with no count disables save', (tester) async {
    final repo = FakeRepository(items: const [_track]);
    repo.previewResult = const PlaylistPreview(items: [_track], total: 1);
    await tester.pumpWidget(
      _host(repo, const RuleEditorScreen(createName: 'Blank')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('rule-limit-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('at random').last);
    await tester.pumpAndSettle();

    // A random draw needs a positive count; leaving it blank blocks the
    // save so the missing limit is caught here, not as a 400.
    TextButton saveButton() =>
        tester.widget<TextButton>(find.byKey(const Key('rule-save')));
    expect(saveButton().onPressed, isNull);

    await tester.enterText(find.byKey(const Key('rule-limit-field')), '10');
    await tester.pump();
    expect(saveButton().onPressed, isNotNull);
  });

  testWidgets('a rule with an unknown limit mode opens read-only', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track]);
    final future = await repo.createPlaylist(
      name: 'Future',
      kind: 'smart',
      rule: const SmartRule(
        root: RuleNode.all([
          RuleNode.condition(field: 'rating', op: 'gte', value: '60'),
        ]),
        limitMode: 'weekly-rotation',
      ),
    );
    await tester.pumpWidget(_host(repo, RuleEditorScreen(editing: future)));
    await tester.pumpAndSettle();

    // The condition tree is representable, but the future limit mode is
    // not, so the whole rule opens read-only instead of crashing the
    // mode dropdown.
    expect(find.textContaining('opens read-only'), findsOneWidget);
  });

  testWidgets('rule editor builds a relative-date condition', (tester) async {
    final repo = FakeRepository(items: const [_track]);
    repo.previewResult = const PlaylistPreview(items: [_track], total: 7);
    await tester.pumpWidget(
      _host(repo, const RuleEditorScreen(createName: 'Recent')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('rule-add-condition')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('rule-field-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('addedAt').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rule-op-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('inTheLast').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rule-value-field')), '30');
    await tester.pump();

    await tester.tap(find.byKey(const Key('rule-save')));
    await tester.pumpAndSettle();

    final saved = repo.playlistsByPid.values.singleWhere(
      (p) => p.name == 'Recent',
    );
    final condition = saved.rule!.root.nodes.single;
    expect(condition.field, 'addedAt');
    expect(condition.op, 'inTheLast');
    expect(condition.value, '30');
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

  testWidgets('a playlist with a cover draws it instead of the kind icon', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track]);
    repo.playlistsByPid['pl-COVERED'] = _covered();
    repo.playlistMembers['pl-COVERED'] = [_track.pid];
    await tester.pumpWidget(_host(repo, const PlaylistsScreen()));
    await tester.pumpAndSettle();

    // The row hands the cover widget a URL rather than falling through
    // to the kind icon. (The image itself cannot load in a widget test,
    // so the drawn result is the error placeholder either way.)
    final cover = tester.widget<PlaylistCover>(find.byType(PlaylistCover));
    expect(cover.playlist.artUrl, '/api/v1/items/pl-COVERED/art');
  });

  testWidgets('a playlist without a cover falls back to the kind icon', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track]);
    repo.playlistsByPid['pl-BARE'] = _covered(pid: 'pl-BARE', artUrl: null);
    repo.playlistMembers['pl-BARE'] = [_track.pid];
    await tester.pumpWidget(_host(repo, const PlaylistsScreen()));
    await tester.pumpAndSettle();

    final cover = tester.widget<PlaylistCover>(find.byType(PlaylistCover));
    expect(cover.playlist.artUrl, isNull);
    expect(find.byIcon(Icons.queue_music), findsOneWidget);
  });

  testWidgets('resetting a cover hands the slot back to the generated one', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track]);
    repo.playlistsByPid['pl-COVERED'] = _covered();
    repo.playlistMembers['pl-COVERED'] = [_track.pid];
    await tester.pumpWidget(
      _host(repo, const PlaylistScreen(pid: 'pl-COVERED')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('playlist-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('playlist-reset-cover')));
    await tester.pumpAndSettle();

    expect(
      repo.clearEntityArtworkCalls,
      contains((entityType: 'playlist', entityPid: 'pl-COVERED')),
    );
  });

  testWidgets('the set-cover action hides without a file picker', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track]);
    repo.playlistsByPid['pl-COVERED'] = _covered();
    repo.playlistMembers['pl-COVERED'] = [_track.pid];
    await tester.pumpWidget(
      _host(repo, const PlaylistScreen(pid: 'pl-COVERED')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('playlist-menu')));
    await tester.pumpAndSettle();
    // The hide-when-null port contract is what keeps a platform with no
    // picker from offering a dead action; reset needs no picker and
    // stays.
    expect(find.byKey(const Key('playlist-set-cover')), findsNothing);
    expect(find.byKey(const Key('playlist-reset-cover')), findsOneWidget);
  });

  testWidgets('a picked image is uploaded as the playlist cover', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track]);
    repo.playlistsByPid['pl-COVERED'] = _covered();
    repo.playlistMembers['pl-COVERED'] = [_track.pid];
    final bytes = Uint8List.fromList(List<int>.filled(64, 7));
    final picker = _CoverPicker(
      PickedAudioFile(
        name: 'cover.png',
        size: bytes.length,
        openRead: ([int? start, int? end]) => Stream.value(bytes),
      ),
    );
    await tester.pumpWidget(
      _host(repo, const PlaylistScreen(pid: 'pl-COVERED'), picker: picker),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('playlist-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('playlist-set-cover')));
    await tester.pumpAndSettle();

    expect(
      repo.entityArtworkCalls,
      contains((
        entityType: 'playlist',
        entityPid: 'pl-COVERED',
        byteCount: bytes.length,
      )),
    );
  });

  testWidgets('an unreadable image reports instead of throwing', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track]);
    repo.playlistsByPid['pl-COVERED'] = _covered();
    repo.playlistMembers['pl-COVERED'] = [_track.pid];
    // A file that vanished between the dialog and the read, or one the
    // process cannot open: the platform throws, not the API.
    final picker = _CoverPicker(
      PickedAudioFile(
        name: 'gone.png',
        size: 10,
        openRead: ([int? start, int? end]) =>
            Stream<List<int>>.error(const FileSystemException('no such file')),
      ),
    );
    await tester.pumpWidget(
      _host(repo, const PlaylistScreen(pid: 'pl-COVERED'), picker: picker),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('playlist-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('playlist-set-cover')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not read that image'), findsOneWidget);
    expect(repo.entityArtworkCalls, isEmpty);
  });
}
