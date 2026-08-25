import 'dart:io';

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/l10n/l10n.dart';
import 'package:waxdeck/src/playlists/add_to_playlist_sheet.dart';
import 'package:waxdeck/src/playlists/playlist_screen.dart';
import 'package:waxdeck/src/playlists/playlists_screen.dart';
import 'package:waxdeck/src/playlists/rule_editor_screen.dart';
import 'package:waxdeck/src/playlists/rule_vocabulary.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

const _track = ItemSummary(
  pid: 'tr-01JZX5N8QW3F4V9T2B7KD3M9R6',
  mediaType: MediaType.music,
  title: 'Prancing Pony Blues',
  artist: 'The Bree Trio',
  durationMs: 214000,
);

const _second = ItemSummary(
  pid: 'tr-01JZX5N8QW3F4V9T2B7KD3M9R7',
  mediaType: MediaType.music,
  title: 'Barliman Reel',
  artist: 'The Bree Trio',
  durationMs: 180000,
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
  Future<List<PickedAudioFile>> pickAudioFiles({
    String audioLabel = '',
    String anyLabel = '',
    UploadFormatSets formats = const UploadFormatSets(),
  }) async => const [];

  @override
  Future<FolderPick> pickAudioFolder({
    UploadFormatSets formats = const UploadFormatSets(),
  }) async => const FolderPick();

  @override
  Future<PickedAudioFile?> pickFile({
    required Set<String> extensions,
    required String label,
    String anyLabel = '',
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

/// Somebody else's shared list, which this caller may open and not edit.
Playlist _theirs({String pid = 'pl-THEIRS'}) => Playlist(
  pid: pid,
  name: 'House Mix',
  kind: 'static',
  visibility: 'shared',
  ownerName: 'Rosie',
  isOwner: false,
  itemCount: 1,
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
    // The header says what the list is, how much is in it, and how long
    // it runs, summed from the members the wire never totals.
    expect(
      find.textContaining('Manual playlist · 1 item · 3 min'),
      findsOneWidget,
    );
  });

  testWidgets('the empty state invites the first playlist', (tester) async {
    final repo = FakeRepository();
    await tester.pumpWidget(_host(repo, const PlaylistsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('No playlists yet'), findsOneWidget);
    // The invitation carries its action: the button opens the create
    // dialog rather than pointing at the plus somewhere else.
    await tester.tap(find.text('New playlist'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistNameField),
      findsOneWidget,
    );
  });

  testWidgets('yours and the server\'s are separate sections', (tester) async {
    final repo = FakeRepository(items: const [_track]);
    await repo.createPlaylist(name: 'Mine', kind: 'static');
    repo.playlistsByPid['pl-THEIRS'] = _theirs();
    repo.playlistMembers['pl-THEIRS'] = [_track.pid];
    await tester.pumpWidget(_host(repo, const PlaylistsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Yours'), findsOneWidget);
    expect(find.text('Shared with the server'), findsOneWidget);
    expect(find.text('Shared by Rosie'), findsOneWidget);
  });

  testWidgets('one section on its own carries no header', (tester) async {
    final repo = FakeRepository(items: const [_track]);
    await repo.createPlaylist(name: 'Mine', kind: 'static');
    await tester.pumpWidget(_host(repo, const PlaylistsScreen()));
    await tester.pumpAndSettle();

    // A header over the whole screen names nothing.
    expect(find.text('Yours'), findsNothing);
    expect(find.text('Shared with the server'), findsNothing);
  });

  testWidgets('a smart list wears its badge on the card', (tester) async {
    final repo = FakeRepository(items: const [_track]);
    await repo.createPlaylist(
      name: 'Best of',
      kind: 'smart',
      rule: const SmartRule(
        root: RuleNode.all([
          RuleNode.condition(field: 'genre', op: 'is', value: 'Rock'),
        ]),
      ),
    );
    await tester.pumpWidget(_host(repo, const PlaylistsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Smart'), findsOneWidget);
  });

  testWidgets('creates a manual playlist through the dialog', (tester) async {
    final repo = FakeRepository(items: const [_track]);
    await tester.pumpWidget(_host(repo, const PlaylistsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistAdd));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.playlistNameField),
      'Evening',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistCreateConfirm),
    );
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

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistEntryRemove(0)),
    );
    await tester.pumpAndSettle();

    expect(repo.playlistMembers[created.pid], isEmpty);
  });

  testWidgets('a member row opens the item menu from its kebab', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track]);
    final created = await repo.createPlaylist(
      name: 'Menu me',
      kind: 'static',
      itemPids: [_track.pid],
    );
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: created.pid)));
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistEntryMore(0)),
    );
    await tester.pumpAndSettle();
    // The track carries no entity handles, so the menu holds what a
    // bare music pid supports.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.itemMenuMix),
      findsOneWidget,
    );
    expect(find.text('Go to album'), findsNothing);
  });

  testWidgets('swiping a member away drops it', (tester) async {
    final repo = FakeRepository(items: const [_track, _second]);
    final created = await repo.createPlaylist(
      name: 'Swipe me',
      kind: 'static',
      itemPids: [_track.pid, _second.pid],
    );
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: created.pid)));
    await tester.pumpAndSettle();

    // The row has to leave the tree with the gesture rather than with the
    // round trip: a Dismissible still built after its own dismissal
    // throws, which is what an awaited removal would have left it doing.
    await tester.drag(
      find.bySemanticsIdentifier(SemanticsIds.playlistEntry(0)),
      const Offset(500, 0),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repo.playlistMembers[created.pid], [_second.pid]);
  });

  testWidgets('dragging a member sends the new order', (tester) async {
    final repo = FakeRepository(items: const [_track, _second]);
    final created = await repo.createPlaylist(
      name: 'Reorder me',
      kind: 'static',
      itemPids: [_track.pid, _second.pid],
    );
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: created.pid)));
    await tester.pumpAndSettle();

    await _dragUp(tester, 1);

    expect(repo.replacedPlaylistOrders.single, [_second.pid, _track.pid]);
    expect(repo.playlistMembers[created.pid], [_second.pid, _track.pid]);
  });

  testWidgets('a row carries the move actions a drag is not', (tester) async {
    final repo = FakeRepository(items: const [_track, _second]);
    final created = await repo.createPlaylist(
      name: 'Reachable',
      kind: 'static',
      itemPids: [_track.pid, _second.pid],
    );
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: created.pid)));
    await tester.pumpAndSettle();

    // SliverReorderableList adds none of the move actions
    // ReorderableListView gives itself, so the rows declare them: a
    // screen reader and a switch can move an entry without dragging.
    expect(_moveActionLabels(tester), containsAll(['Move up', 'Move down']));
  });

  testWidgets('a lost reorder race says so and puts the order back', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track, _second])
      ..playlistReplaceConflict = true;
    final created = await repo.createPlaylist(
      name: 'Contested',
      kind: 'static',
      itemPids: [_track.pid, _second.pid],
    );
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: created.pid)));
    await tester.pumpAndSettle();

    await _dragUp(tester, 1);

    // The banner carries the server's own sentence: `conflict` covers
    // three different refusals and only it says which.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistConflict),
      findsOneWidget,
    );
    expect(find.textContaining('changed since'), findsOneWidget);
    expect(repo.playlistMembers[created.pid], [_track.pid, _second.pid]);
  });

  testWidgets('the add row searches and appends what is chosen', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track, _second]);
    repo.searchResults['reel'] = SearchResults(
      query: 'reel',
      tracks: [
        SearchHit(
          pid: _second.pid,
          kind: 'track',
          title: 'Barliman Reel',
          subtitle: 'The Bree Trio',
        ),
      ],
    );
    final created = await repo.createPlaylist(
      name: 'Growing',
      kind: 'static',
      itemPids: [_track.pid],
    );
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: created.pid)));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.playlistAddField),
      'reel',
    );
    // The search is debounced by 300ms.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistAddResult(0)),
    );
    await tester.pumpAndSettle();

    expect(repo.playlistMembers[created.pid], [_track.pid, _second.pid]);
  });

  testWidgets('a search that finds nothing playable says so', (tester) async {
    final repo = FakeRepository(items: const [_track]);
    // An artist hit and nothing else: a real answer that this row has
    // nothing to offer from, which is different from not having asked.
    repo.searchResults['bree'] = const SearchResults(
      query: 'bree',
      artists: [SearchHit(pid: 'ar-1', kind: 'artist', title: 'The Bree Trio')],
    );
    final created = await repo.createPlaylist(
      name: 'Empty answer',
      kind: 'static',
      itemPids: [_track.pid],
    );
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: created.pid)));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.playlistAddField),
      'bree',
    );
    // Nothing while the debounce is still out: an unasked search is not
    // a search that found nothing.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Nothing here to add'), findsNothing);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing here to add'), findsOneWidget);
  });

  testWidgets('a membership write drops the cover it just changed', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track, _second]);
    repo.playlistsByPid['pl-COVERED'] = _covered();
    repo.playlistMembers['pl-COVERED'] = [_track.pid, _second.pid];
    final store = FakeArtworkStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          filePickerProvider.overrideWithValue(null),
          artworkStoreProvider.overrideWithValue(store),
        ],
        child: routedHost(
          const PlaylistScreen(pid: 'pl-COVERED'),
          pushed: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistEntryRemove(0)),
    );
    await tester.pumpAndSettle();

    // The server builds the cover from the first few members and keys it
    // on their order, so a removal changes it - at the same URL, which
    // is what every cache keys on.
    expect(store.evicted, ['/api/v1/items/pl-COVERED/art']);
  });

  testWidgets('the add-to-playlist sheet appends without opening the list', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track]);
    final target = await repo.createPlaylist(name: 'Target', kind: 'static');
    repo.playlistsByPid[target.pid] = Playlist(
      pid: target.pid,
      name: target.name,
      kind: 'static',
      visibility: 'private',
      ownerName: 'me',
      isOwner: true,
      itemCount: 0,
      artUrl: '/api/v1/items/${target.pid}/art',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final store = FakeArtworkStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          filePickerProvider.overrideWithValue(null),
          artworkStoreProvider.overrideWithValue(store),
        ],
        child: routedHost(const AddToPlaylistSheet(item: _track), pushed: true),
      ),
    );
    await tester.pumpAndSettle();
    repo.playlistItemPageCalls.clear();

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.addToPlaylistTarget(target.pid)),
    );
    await tester.pumpAndSettle();

    expect(repo.playlistMembers[target.pid], [_track.pid]);
    // Through the listing rather than the detail: building that notifier
    // would read the playlist and page its members to add one track.
    expect(repo.playlistItemPageCalls, isEmpty);
    // And the cover it just changed is dropped, which needs the artUrl
    // the listing already holds.
    expect(store.evicted, ['/api/v1/items/${target.pid}/art']);
  });

  testWidgets('a smart list shows its rules and no way to reorder', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track]);
    repo.previewResult = const PlaylistPreview(items: [_track], total: 1);
    final created = await repo.createPlaylist(
      name: 'Recent rock',
      kind: 'smart',
      rule: const SmartRule(
        root: RuleNode.all([
          RuleNode.condition(field: 'genre', op: 'is', value: 'Rock'),
          RuleNode.condition(field: 'addedAt', op: 'inTheLast', value: '90'),
        ]),
        limit: 50,
      ),
    );
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: created.pid)));
    await tester.pumpAndSettle();

    expect(find.text('Genre is Rock'), findsOneWidget);
    expect(find.text('Added at is in the last 90 days'), findsOneWidget);
    expect(find.text('Limit 50'), findsOneWidget);
    expect(
      find.text('Evaluated live, every time this list is opened.'),
      findsOneWidget,
    );
    // Membership is the rule's, so there is nothing to drag and nothing
    // to remove.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistEntryRemove(0)),
      findsNothing,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistAddField),
      findsNothing,
    );
  });

  testWidgets('somebody else\'s list offers no edits', (tester) async {
    final repo = FakeRepository(items: const [_track]);
    repo.playlistsByPid['pl-THEIRS'] = _theirs();
    repo.playlistMembers['pl-THEIRS'] = [_track.pid];
    await tester.pumpWidget(
      _host(repo, const PlaylistScreen(pid: 'pl-THEIRS')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Shared by Rosie'), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistOverflow));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistRename),
      findsNothing,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistDelete),
      findsNothing,
    );
    // Exporting somebody else's list is reading it, which this caller may
    // already do.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistExportM3u),
      findsOneWidget,
    );
  });

  testWidgets('rule editor builds a rule, previews, and saves', (tester) async {
    final repo = FakeRepository(items: const [_track]);
    repo.previewResult = const PlaylistPreview(items: [_track], total: 42);
    await tester.pumpWidget(
      _host(repo, const RuleEditorScreen(createName: 'Best of')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.ruleAddCondition));
    await tester.pumpAndSettle();

    // The default condition is the first vocabulary field with its first
    // operator; switch it to a user-state rule.
    await _pick(tester, SemanticsIds.ruleField(0), 'Rating');
    await _pick(tester, SemanticsIds.ruleOp(0), 'is at least');
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.ruleValue(0)),
      '80',
    );

    // The preview debounce is half a second.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Matches 42 items'), findsOneWidget);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.ruleSave));
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

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.ruleValue(0)),
      '90',
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.ruleSave));
    await tester.pumpAndSettle();

    expect(popped, isNotNull);
    expect(popped!.pid, created.pid);
    expect(popped!.previousPid, isNull);
    expect(repo.playlistsByPid.containsKey(created.pid), isTrue);
    expect(popped!.rule!.root.nodes.single.value, '90');
  });

  testWidgets('a negated group round-trips through the not node', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track]);
    repo.previewResult = const PlaylistPreview(items: [], total: 0);
    final created = await repo.createPlaylist(
      name: 'Not spoken word',
      kind: 'smart',
      rule: const SmartRule(
        root: RuleNode(
          type: 'not',
          node: RuleNode.any([
            RuleNode.condition(
              field: 'mediaType',
              op: 'is',
              value: 'audiobook',
            ),
          ]),
        ),
      ),
    );
    await tester.pumpWidget(_host(repo, RuleEditorScreen(editing: created)));
    await tester.pumpAndSettle();

    // It opens as an editable group rather than read-only, which is what
    // a `not` used to get.
    expect(find.textContaining('read-only'), findsNothing);
    expect(find.text('None of'), findsWidgets);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.ruleSave));
    await tester.pumpAndSettle();

    final saved = repo.playlistsByPid[created.pid]!;
    expect(saved.rule!.root.type, 'not');
    expect(saved.rule!.root.node!.type, 'any');
    expect(saved.rule!.root.node!.nodes.single.value, 'audiobook');
  });

  testWidgets('rule editor sets a random limit mode', (tester) async {
    final repo = FakeRepository(items: const [_track]);
    repo.previewResult = const PlaylistPreview(items: [_track], total: 5);
    await tester.pumpWidget(
      _host(repo, const RuleEditorScreen(createName: 'Shuffle')),
    );
    await tester.pumpAndSettle();

    await _pick(tester, SemanticsIds.ruleLimitMode, 'at random');
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.ruleLimitValue),
      '10',
    );
    await tester.pumpAndSettle();

    // The sorts card collapses to its random-mode note.
    expect(find.text('A random limit draws its own order.'), findsOneWidget);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.ruleSave));
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

    await _pick(tester, SemanticsIds.ruleLimitMode, 'by minutes');
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.ruleLimitValue),
      '60',
    );
    await tester.pumpAndSettle();

    // A budget without a pinned seed may sort; add one.
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.ruleAddSort));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.ruleAddSort),
      findsOneWidget,
    );

    // Pinning the selection makes the seed supply the order, so the sort
    // card collapses and the staged sort is dropped: the saved rule can
    // never carry the seed and sort pair the server rejects.
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key(SemanticsIds.ruleLimitSeed)),
        matching: find.byType(WaxSwitch),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('A pinned budget draws its own order.'), findsOneWidget);
    expect(find.bySemanticsIdentifier(SemanticsIds.ruleAddSort), findsNothing);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.ruleSave));
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

    await _pick(tester, SemanticsIds.ruleLimitMode, 'at random');

    // A random draw needs a positive count; leaving it blank blocks the
    // save so the missing limit is caught here, not as a 400.
    WaxButton saveButton() => tester.widget<WaxButton>(
      find.ancestor(
        of: find.bySemanticsIdentifier(SemanticsIds.ruleSave),
        matching: find.byType(WaxButton),
      ),
    );
    expect(saveButton().onPressed, isNull);

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.ruleLimitValue),
      '10',
    );
    await tester.pumpAndSettle();
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
    // mode picker.
    expect(find.text('This rule opens read-only'), findsOneWidget);
  });

  testWidgets('rule editor picks a playlist by name', (tester) async {
    final repo = FakeRepository(items: const [_track]);
    repo.previewResult = const PlaylistPreview(items: [_track], total: 1);
    // One static list to pick and one smart one that must not appear:
    // a smart list stores no membership for the field to test.
    final archive = await repo.createPlaylist(name: 'Archive', kind: 'static');
    await repo.createPlaylist(
      name: 'Rules elsewhere',
      kind: 'smart',
      rule: const SmartRule(
        root: RuleNode.all([
          RuleNode.condition(field: 'rating', op: 'gte', value: '60'),
        ]),
      ),
    );
    await tester.pumpWidget(
      _host(repo, const RuleEditorScreen(createName: 'The rest')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.ruleAddCondition));
    await tester.pumpAndSettle();
    await _pick(tester, SemanticsIds.ruleField(0), 'Playlist');
    await _pick(tester, SemanticsIds.ruleOp(0), 'is not');
    await tester.pumpAndSettle();

    // The picker offers the static list and not the smart one.
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.ruleValue(0)));
    await tester.pumpAndSettle();
    expect(find.text('Rules elsewhere'), findsNothing);
    await tester.tap(find.text('Archive').last);
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.ruleSave));
    await tester.pumpAndSettle();

    final saved = repo.playlistsByPid.values.singleWhere(
      (p) => p.name == 'The rest',
    );
    final condition = saved.rule!.root.nodes.single;
    expect(condition.field, 'playlist');
    expect(condition.op, 'isNot');
    // The pid rides, not the name: the name is presentation.
    expect(condition.value, archive.pid);
  });

  testWidgets('rule editor keeps a playlist value it cannot resolve', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track]);
    repo.previewResult = const PlaylistPreview(items: [_track], total: 1);
    await repo.createPlaylist(name: 'Archive', kind: 'static');
    // A rule naming a list the fetch does not carry: deleted since the
    // rule was saved, or beyond the first page. The editor must show it
    // as unavailable, not silently repoint it at somebody's first list.
    final orphan = await repo.createPlaylist(
      name: 'Elsewhere',
      kind: 'smart',
      rule: const SmartRule(
        root: RuleNode.all([
          RuleNode.condition(
            field: 'playlist',
            op: 'isNot',
            value: 'pl-departed',
          ),
        ]),
      ),
    );
    await tester.pumpWidget(_host(repo, RuleEditorScreen(editing: orphan)));
    await tester.pumpAndSettle();

    expect(find.text('Unavailable list'), findsOneWidget);

    // Saving untouched persists the stored pid, which the server
    // accepts and matches nothing - the rule means what it meant.
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.ruleSave));
    await tester.pumpAndSettle();
    final saved = repo.playlistsByPid[orphan.pid]!;
    expect(saved.rule!.root.nodes.single.value, 'pl-departed');
  });

  testWidgets('rule editor builds a relative-date condition', (tester) async {
    final repo = FakeRepository(items: const [_track]);
    repo.previewResult = const PlaylistPreview(items: [_track], total: 7);
    await tester.pumpWidget(
      _host(repo, const RuleEditorScreen(createName: 'Recent')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.ruleAddCondition));
    await tester.pumpAndSettle();
    await _pick(tester, SemanticsIds.ruleField(0), 'Added at');
    await _pick(tester, SemanticsIds.ruleOp(0), 'is in the last');
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.ruleValue(0)),
      '30',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.ruleSave));
    await tester.pumpAndSettle();

    final saved = repo.playlistsByPid.values.singleWhere(
      (p) => p.name == 'Recent',
    );
    final condition = saved.rule!.root.nodes.single;
    expect(condition.field, 'addedAt');
    expect(condition.op, 'inTheLast');
    expect(condition.value, '30');
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

    // Clipboard rides the platform channel, which has no host in widget
    // tests; without a mock the copy await never completes.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistOverflow));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistExportM3u),
    );
    await tester.pumpAndSettle();

    expect(repo.exportedM3uPids, [created.pid]);
    expect(find.textContaining('Prancing Pony Blues'), findsWidgets);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistExportCopy),
    );
    await tester.pumpAndSettle();
    expect(find.text('Playlist copied as M3U'), findsOneWidget);
  });

  testWidgets('a lossless NSP export goes straight to the document', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track])
      ..nspExport = const <String, Object?>{
        'name': 'Rock',
        'all': <Object?>[
          <String, Object?>{
            'is': <String, Object?>{'genre': 'Rock'},
          },
        ],
      };
    final created = await repo.createPlaylist(
      name: 'Rock',
      kind: 'smart',
      rule: const SmartRule(
        root: RuleNode.all([
          RuleNode.condition(field: 'genre', op: 'is', value: 'Rock'),
        ]),
      ),
    );
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: created.pid)));
    await tester.pumpAndSettle();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistOverflow));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistExportNsp),
    );
    await tester.pumpAndSettle();

    // Nothing to ask about, so nothing is asked: the loss dialog never
    // appears and the export is the strict one.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistExportNspLoss),
      findsNothing,
    );
    expect(repo.nspReports, [created.pid]);
    expect(repo.nspExports, [(pid: created.pid, partial: false)]);
    expect(find.textContaining('"genre"'), findsWidgets);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistExportCopy),
    );
    await tester.pumpAndSettle();
    expect(find.text('Playlist copied as NSP'), findsOneWidget);
  });

  testWidgets('a lossy NSP export lists the loss and can be backed out of', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track])
      ..nspReport = const NspReport(
        direction: 'export',
        gaps: [
          NspGap(
            kind: 'field',
            path: '/all/1',
            reason: 'nsp: no .nsp field for mediaType',
            field: 'mediaType',
          ),
        ],
        notes: [
          NspGap(
            kind: 'sort',
            path: '/sort',
            reason: 'nsp: .nsp sorts on one term, so title is dropped',
            field: 'title',
          ),
        ],
      );
    final created = await repo.createPlaylist(
      name: 'Music only',
      kind: 'smart',
      rule: const SmartRule(
        root: RuleNode.all([
          RuleNode.condition(field: 'mediaType', op: 'is', value: 'music'),
        ]),
      ),
    );
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: created.pid)));
    await tester.pumpAndSettle();

    Future<void> openMenu() async {
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.playlistOverflow),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.playlistExportNsp),
      );
      await tester.pumpAndSettle();
    }

    await openMenu();

    // Both a gap and a note, each in the converter's own words rather
    // than a phrase of ours - under the name the rule editor gives the
    // field, which is what ties the sentence to a row somebody built.
    expect(find.text('nsp: no .nsp field for mediaType'), findsOneWidget);
    expect(
      find.text('nsp: .nsp sorts on one term, so title is dropped'),
      findsOneWidget,
    );
    expect(find.text('Media type'), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
    // One row per gap rather than one paragraph of all of them.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistExportNspLossRow(1)),
      findsOneWidget,
    );
    // Counts what has no NSP form, not what the export drops: one of
    // the two is a note, which is a loss the format makes either way and
    // that a partial export does not drop.
    expect(find.text('2 parts of this rule have no NSP form.'), findsOneWidget);

    // Cancel exports nothing at all.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.nspExports, isEmpty);

    // Proceeding asks for the lossy one, which is the only way that
    // parameter is ever true.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    await openMenu();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistExportNspProceed),
    );
    await tester.pumpAndSettle();
    expect(repo.nspExports, [(pid: created.pid, partial: true)]);
  });

  testWidgets('a refused NSP export keeps the server\'s sentence', (
    tester,
  ) async {
    // The reachable refusal: the report answers, the person accepts the
    // loss, and then nothing survives - so the export 501s with a
    // sentence about the rule. `feature-unavailable` translated says
    // "this server is not running the feature that request needs", which
    // is both unhelpful and untrue.
    final repo = FakeRepository(items: const [_track])
      ..nspReport = const NspReport(
        direction: 'export',
        gaps: [
          NspGap(
            kind: 'field',
            path: '/root/nodes/0',
            reason: 'nsp: unsupported field: kind',
            field: 'mediaType',
          ),
        ],
      )
      ..nspExportError = const WaxDeckApiException(
        code: 'feature-unavailable',
        message:
            'nsp: nothing in this rule has an .nsp form, so a partial '
            'export would match the whole library',
      );
    final created = await repo.createPlaylist(
      name: 'Music only',
      kind: 'smart',
      rule: const SmartRule(
        root: RuleNode.all([
          RuleNode.condition(field: 'mediaType', op: 'is', value: 'music'),
        ]),
      ),
    );
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: created.pid)));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistOverflow));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistExportNsp),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistExportNspProceed),
    );
    await tester.pumpAndSettle();

    expect(repo.nspExports, [(pid: created.pid, partial: true)]);
    expect(find.textContaining('nothing in this rule'), findsOneWidget);
  });

  testWidgets('a report this playlist cannot answer never exports', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track])
      ..nspReportError = const WaxDeckApiException(
        code: 'catalog-maintenance',
        message: 'the catalog is temporarily under maintenance',
      );
    final created = await repo.createPlaylist(
      name: 'Unreachable',
      kind: 'smart',
      rule: const SmartRule(
        root: RuleNode.all([
          RuleNode.condition(field: 'genre', op: 'is', value: 'Rock'),
        ]),
      ),
    );
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: created.pid)));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistOverflow));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistExportNsp),
    );
    await tester.pumpAndSettle();

    // A code the table has a sentence for reads from the table, and
    // nothing is exported behind the failed question.
    expect(repo.nspExports, isEmpty);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistExportNspLoss),
      findsNothing,
    );
  });

  testWidgets('a manual playlist is not offered an NSP export', (tester) async {
    // There is no rule to write, and the server answers 501 for one:
    // offering the row would be an affordance that only ever refuses.
    final repo = FakeRepository(items: const [_track]);
    final created = await repo.createPlaylist(
      name: 'Road Trip',
      kind: 'static',
      itemPids: [_track.pid],
    );
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: created.pid)));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistOverflow));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistExportNsp),
      findsNothing,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistExportM3u),
      findsOneWidget,
      reason: 'the other two exports are unchanged',
    );
  });

  testWidgets('a playlist without a cover falls back to the monogram', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track]);
    repo.playlistsByPid['pl-BARE'] = _covered(pid: 'pl-BARE', artUrl: null);
    repo.playlistMembers['pl-BARE'] = [_track.pid];
    await tester.pumpWidget(_host(repo, const PlaylistsScreen()));
    await tester.pumpAndSettle();

    // The card is handed no artwork at all, which is what draws the
    // monogram rather than a broken image.
    final card = tester.widget<MediaCard>(find.byType(MediaCard));
    expect(card.data.artwork?.call(64), isNull);
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

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistOverflow));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistResetCover),
    );
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

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistOverflow));
    await tester.pumpAndSettle();
    // The hide-when-null port contract is what keeps a platform with no
    // picker from offering a dead action; reset needs no picker and
    // stays.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistSetCover),
      findsNothing,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistResetCover),
      findsOneWidget,
    );
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

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistOverflow));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistSetCover));
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

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistOverflow));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistSetCover));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not read that image'), findsOneWidget);
    expect(repo.entityArtworkCalls, isEmpty);
  });

  testWidgets('the add-to-playlist sheet marks the lists already holding it', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track]);
    await repo.createPlaylist(
      name: 'Holds it',
      kind: 'static',
      itemPids: [_track.pid],
    );
    final empty = await repo.createPlaylist(name: 'Empty', kind: 'static');
    await tester.pumpWidget(
      _host(repo, const AddToPlaylistSheet(item: _track)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Already in this list'), findsOneWidget);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.addToPlaylistTarget(empty.pid)),
    );
    await tester.pumpAndSettle();

    expect(repo.playlistMembers[empty.pid], [_track.pid]);
  });

  testWidgets('the sheet makes a new list and drops the item in it', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track]);
    await tester.pumpWidget(
      _host(repo, const AddToPlaylistSheet(item: _track)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.addToPlaylistNew));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.playlistNameField),
      'From the player',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistCreateConfirm),
    );
    await tester.pumpAndSettle();

    final made = repo.playlistsByPid.values.singleWhere(
      (p) => p.name == 'From the player',
    );
    expect(repo.playlistMembers[made.pid], [_track.pid]);
  });

  group('rule summaries', () {
    // The date symbols come with it: nothing here loads the global
    // Material delegate that normally supplies them.
    late AppLocalizations l10n;

    setUpAll(() async {
      await initializeDateFormatting();
      l10n = await AppLocalizations.delegate.load(const Locale('en'));
    });

    test('read as phrases rather than as field names', () {
      expect(
        describeRule(
          l10n,
          const SmartRule(
            root: RuleNode.all([
              RuleNode.condition(
                field: 'albumArtist',
                op: 'isNot',
                value: 'Various',
              ),
              RuleNode.condition(field: 'starred', op: 'is', value: 'true'),
            ]),
            sorts: [RuleSort(field: 'playCount', desc: true)],
            limit: 25,
            limitMode: 'random',
          ),
        ),
        [
          'Album artist is not Various',
          'Starred is yes',
          // The field's own label: lower-casing a noun mid-phrase is
          // an English rule, and the chip is a label.
          'By Play count, highest first',
          '25 at random',
        ],
      );
    });

    test('a date value reads as a day, not as an instant', () {
      expect(
        describeCondition(
          l10n,
          const RuleNode.condition(
            field: 'addedAt',
            op: 'after',
            value: '2026-01-15T00:00:00.000Z',
          ),
        ),
        startsWith('Added at is after Jan 1'),
      );
    });

    test('a tag key keeps the word its owner typed', () {
      expect(
        describeCondition(
          l10n,
          const RuleNode.condition(
            field: 'tag.mood',
            op: 'contains',
            value: 'rainy',
          ),
        ),
        'Tag: mood contains rainy',
      );
    });

    test('a negated group leads with what it excludes', () {
      expect(
        describeRule(
          l10n,
          const SmartRule(
            root: RuleNode(
              type: 'not',
              node: RuleNode.any([
                RuleNode.condition(
                  field: 'mediaType',
                  op: 'is',
                  value: 'audiobook',
                ),
                RuleNode.condition(
                  field: 'mediaType',
                  op: 'is',
                  value: 'podcast',
                ),
              ]),
            ),
          ),
        ),
        ['None of', 'Media type is audiobook', 'Media type is podcast'],
      );
    });

    test('a negation over one condition says so rather than heading it', () {
      expect(
        describeRule(
          l10n,
          const SmartRule(
            root: RuleNode(
              type: 'not',
              node: RuleNode.any([
                RuleNode.condition(field: 'genre', op: 'is', value: 'Ambient'),
              ]),
            ),
          ),
        ),
        ['Not', 'Genre is Ambient'],
      );
    });

    test('a shape the chip row cannot draw says so instead of lying', () {
      expect(
        describeRule(
          l10n,
          const SmartRule(
            root: RuleNode.all([
              RuleNode.any([
                RuleNode.condition(field: 'genre', op: 'is', value: 'Rock'),
              ]),
            ]),
          ),
        ),
        ['Nested conditions'],
      );
    });

    test('a playlist value reads as its name, and as its pid without one', () {
      const node = RuleNode.condition(
        field: 'playlist',
        op: 'isNot',
        value: 'pl-archive',
      );
      expect(
        describeCondition(
          l10n,
          node,
          playlistName: (pid) => pid == 'pl-archive' ? 'Archive' : null,
        ),
        'Playlist is not Archive',
      );
      // A rule pointing at a list this reader cannot see still has to
      // say something true.
      expect(describeCondition(l10n, node), 'Playlist is not pl-archive');
    });
  });
}

/// Drags the row at [index] onto the row above it by its handle.
///
/// The target comes from where that row actually is rather than from a
/// guessed offset: row height moves with the density and the text scale,
/// and a drag that falls short of the next row reorders nothing.
Future<void> _dragUp(WidgetTester tester, int index) async {
  Offset handleAt(int at) => tester.getCenter(
    find.bySemanticsIdentifier(SemanticsIds.playlistEntryDrag(at)),
  );
  final from = handleAt(index);
  final to = handleAt(index - 1);
  final gesture = await tester.startGesture(from);
  // The listener starts the drag on pointer down; the pump lets the list
  // take it before the move, and the steps let it settle each frame the
  // way a finger would.
  await tester.pump(kLongPressTimeout);
  for (var step = 1; step <= 4; step++) {
    await gesture.moveTo(Offset.lerp(from, to, step / 4)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Every custom action label the rows declare.
///
/// Read off the widgets rather than off the semantics tree: the actions
/// are what the rows promise, and a test that walks the compiled tree
/// would be testing the merge rules instead.
Set<String> _moveActionLabels(WidgetTester tester) => <String>{
  for (final widget in tester.widgetList<Semantics>(find.byType(Semantics)))
    for (final action
        in widget.properties.customSemanticsActions?.keys ??
            const <CustomSemanticsAction>[])
      if (action.label != null) action.label!,
};

/// Chooses [label] in the picker wearing [semanticsId].
///
/// A dropdown menu opens into an overlay, so the entry is tapped by its
/// text; the picker itself is found by its handle, which is what keeps
/// two pickers on one row apart.
Future<void> _pick(
  WidgetTester tester,
  String semanticsId,
  String label,
) async {
  await tester.tap(find.bySemanticsIdentifier(semanticsId));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}
