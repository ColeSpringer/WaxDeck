import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/metadata/artwork_manager.dart';
import 'package:waxdeck/src/metadata/metadata_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'localized_host.dart';
import 'routed_host.dart';

/// Hands back one in-memory image whatever is asked for.
class _ImagePicker implements FilePickerPort {
  _ImagePicker(this.image);

  final PickedAudioFile? image;

  @override
  bool get canPickFolders => false;

  @override
  Future<List<PickedAudioFile>> pickAudioFiles({
    String audioLabel = '',
    String anyLabel = '',
  }) async => const [];

  @override
  Future<FolderPick> pickAudioFolder() async => const FolderPick();

  @override
  Future<PickedAudioFile?> pickFile({
    required Set<String> extensions,
    required String label,
    String anyLabel = '',
  }) async => image;
}

PickedAudioFile _png({int size = 64}) => PickedAudioFile(
  name: 'cover.png',
  size: size,
  openRead: ([int? start, int? end]) =>
      Stream<List<int>>.value(Uint8List(size)),
);

ProviderContainer _container(FakeRepository repo, {FilePickerPort? picker}) {
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      filePickerProvider.overrideWithValue(picker),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _host(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: localizedHost(const MetadataScreen(pid: 'tr-1')),
);

Widget _routed(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: routedHost(const MetadataScreen(pid: 'tr-1')),
);

/// Tall and narrow: the single-column arrangement puts every section on
/// one scroll, which is what the sections tests reach into.
Future<void> _pump(WidgetTester tester, Widget host) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(host);
  await tester.pumpAndSettle();
}

FakeRepository _repo() {
  final repo = FakeRepository(items: [testItem('tr-1', title: 'Old Title')]);
  repo.itemFieldsByPid['tr-1'] = {
    'title': 'Old Title',
    'artist': 'The Bree Trio',
    'album': 'Prancing Pony Blues',
    'year': '2011',
  };
  return repo;
}

Finder _field(String name) =>
    find.bySemanticsIdentifier(SemanticsIds.metadataField(name));

void main() {
  testWidgets('the slot grid names every role and what fills it', (
    tester,
  ) async {
    final repo = _repo()
      ..ownArtworkPids.add('tr-1')
      ..artRoles.add(
        const ArtRoleInfo(
          role: 'front',
          format: 'jpeg',
          width: 600,
          height: 600,
        ),
      );
    await _pump(tester, _host(_container(repo)));

    for (final slot in ArtSlot.values) {
      expect(
        find.bySemanticsIdentifier(SemanticsIds.artSlot(slot.role)),
        findsOneWidget,
      );
    }
    expect(find.text('jpeg, 600 x 600'), findsOneWidget);
    // The four slots with nothing in them read as empty, not inherited:
    // only the front cover walks the chain.
    expect(find.text('Empty'), findsNWidgets(4));
  });

  testWidgets('every slot says where its picture came from', (tester) async {
    // The mark is always on and nothing gates it: a cover a third party
    // supplied names the third party.
    final repo = _repo()
      ..ownArtworkPids.add('tr-1')
      ..artRoles.addAll(const <ArtRoleInfo>[
        ArtRoleInfo(
          role: 'front',
          format: 'jpeg',
          width: 600,
          height: 600,
          source: 'enrichment',
          provider: 'coverartarchive',
        ),
        ArtRoleInfo(
          role: 'back',
          format: 'png',
          width: 600,
          height: 600,
          source: 'tag',
        ),
      ]);
    await _pump(tester, _host(_container(repo)));

    expect(find.text('From Cover Art Archive'), findsOneWidget);
    expect(find.text('Art from the file'), findsOneWidget);
  });

  testWidgets('an inherited front cover names the rung that answered', (
    tester,
  ) async {
    // The item holds nothing, so the caption describes the picture the
    // chain answered with rather than a slot this item owns.
    final repo = _repo()
      ..artworkPids.add('tr-1')
      ..artSource = const ArtSource(
        source: 'tag',
        level: 'album',
        derived: true,
      );
    await _pump(tester, _host(_container(repo)));

    expect(find.text('Inherited'), findsOneWidget);
    expect(
      find.text('Art from the file · Borrowed from a track'),
      findsOneWidget,
    );
  });

  testWidgets('a pinned empty cover is not an empty one', (tester) async {
    // A cover cleared and left pinned refuses every later write and
    // shows nothing. Reading "Empty" there is exactly the confusion the
    // upstream lock report exists to end.
    final repo = _repo()
      ..artRoles.add(const ArtRoleInfo(role: 'front', locked: true));
    await _pump(tester, _host(_container(repo)));

    expect(find.text('Pinned, no image'), findsOneWidget);
    expect(find.text('Empty'), findsNWidgets(4));
  });

  testWidgets('the summary counts fields, and names artifacts apart', (
    tester,
  ) async {
    // Upstream overlays an art row on every item holding a cover, so
    // counting the provenance list would shift this line on nearly every
    // item and stop "no recorded sources" meaning anything.
    final repo = _repo()
      ..ownArtworkPids.add('tr-1')
      ..lyricsByPid['tr-1'] = const LyricsState(
        synced: false,
        source: 'sidecar',
      )
      ..itemProvenance['tr-1'] = const <FieldProvenance>[
        FieldProvenance(field: 'title', source: 'user', locked: true),
        FieldProvenance(field: 'art', source: 'tag', locked: false),
        FieldProvenance(field: 'lyrics', source: 'sidecar', locked: false),
      ];
    await _pump(tester, _host(_container(repo)));

    expect(find.text('1 from you'), findsOneWidget);
    expect(find.text('Artwork · From the file'), findsOneWidget);
    // A cover's sidecar is a folder image; lyrics arrive as an .lrc, and
    // one wording cannot honestly describe both files.
    expect(find.text('Lyrics · From an .lrc file'), findsOneWidget);
  });

  testWidgets('an embedded lyric is not called art', (tester) async {
    // The art mark for `tag` says "Art from the file"; a lyric that
    // arrived the same way needs its own sentence, not that one.
    final repo = _repo()
      ..lyricsByPid['tr-1'] = const LyricsState(synced: false, source: 'tag')
      ..itemProvenance['tr-1'] = const <FieldProvenance>[
        FieldProvenance(field: 'lyrics', source: 'tag', locked: false),
      ];
    await _pump(tester, _host(_container(repo)));

    expect(find.text('Lyrics · From the file'), findsOneWidget);
    expect(find.text('Lyrics · Art from the file'), findsNothing);
  });

  testWidgets('a lock-only artifact row states no source', (tester) async {
    // Upstream keeps a row for an art or lyrics field locked with
    // nothing behind it, and the lock writers invent a source: the
    // curation paths stamp "user", `waxbin lock <pid> art` stamps
    // "tag". Neither knows where anything came from, and there is no
    // artwork here to have come from anywhere.
    final repo = _repo()
      ..itemProvenance['tr-1'] = const <FieldProvenance>[
        FieldProvenance(field: 'art', source: 'tag', locked: true),
        FieldProvenance(field: 'lyrics', source: 'user', locked: true),
      ];
    await _pump(tester, _host(_container(repo)));

    expect(find.textContaining('Artwork · '), findsNothing);
    expect(find.textContaining('Lyrics · '), findsNothing);
  });

  testWidgets('an item curated by nobody still says so with a cover', (
    tester,
  ) async {
    final repo = _repo()
      ..ownArtworkPids.add('tr-1')
      ..itemProvenance['tr-1'] = const <FieldProvenance>[
        FieldProvenance(field: 'art', source: 'tag', locked: false),
      ];
    await _pump(tester, _host(_container(repo)));

    expect(find.text('No recorded sources'), findsOneWidget);
    expect(find.text('Artwork · From the file'), findsOneWidget);
  });

  testWidgets('a front cover the item does not own reads as inherited', (
    tester,
  ) async {
    final repo = _repo()..artworkPids.add('tr-1');
    await _pump(tester, _host(_container(repo)));

    expect(find.text('Inherited'), findsOneWidget);
    // And there is nothing of its own to clear: an inherited cover
    // belongs to the album, which is not edited from here.
    expect(
      tester
          .widgetList<WaxIconButton>(find.byType(WaxIconButton))
          .firstWhere((b) => b.label == 'Clear the front cover')
          .onPressed,
      isNull,
    );
  });

  testWidgets('picking an image writes the slot it was picked for', (
    tester,
  ) async {
    final repo = _repo();
    final container = _container(repo, picker: _ImagePicker(_png()));
    await _pump(tester, _host(container));

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.artSlotSet('booklet')),
    );
    await tester.pumpAndSettle();

    expect(repo.setItemArtworkCalls, hasLength(1));
    expect(repo.setItemArtworkCalls.single.role, 'booklet');
    expect(repo.setItemArtworkCalls.single.bytes, 64);
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'Booklet replaced',
    );
  });

  testWidgets('a cover nothing could measure says so rather than nothing', (
    tester,
  ) async {
    // Zero is the catalog saying it never measured this picture - an
    // exotic container it has no decoder for. A row that just reads
    // "tiff" cannot be told from one whose numbers were left out.
    final repo = _repo()
      ..ownArtworkPids.add('tr-1')
      ..artRoles.add(const ArtRoleInfo(role: 'front', format: 'tiff'));
    await _pump(tester, _host(_container(repo)));

    expect(find.text('tiff, Size unknown'), findsOneWidget);
  });

  testWidgets('an image over the endpoint ceiling is refused before upload', (
    tester,
  ) async {
    final repo = _repo();
    final container = _container(
      repo,
      picker: _ImagePicker(
        PickedAudioFile(
          name: 'huge.png',
          size: kArtworkMaxBytes + 1,
          openRead: ([int? start, int? end]) => const Stream<List<int>>.empty(),
        ),
      ),
    );
    await _pump(tester, _host(container));

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.artSlotSet('front')),
    );
    await tester.pumpAndSettle();

    expect(repo.setItemArtworkCalls, isEmpty);
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'huge.png is larger than the 16 MB an image may be',
    );
  });

  testWidgets('clearing a slot confirms first', (tester) async {
    final repo = _repo()
      ..artRoles.add(const ArtRoleInfo(role: 'disc', format: 'png'));
    await _pump(tester, _host(_container(repo)));

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.artSlotClear('disc')),
    );
    await tester.pumpAndSettle();
    // A misclick through the dialog is not a delete.
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.confirmAccept));
    await tester.pumpAndSettle();
    expect(repo.clearItemArtworkCalls, isEmpty);

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.confirmField),
      'clear',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.confirmAccept));
    await tester.pumpAndSettle();

    expect(repo.clearItemArtworkCalls, hasLength(1));
    expect(repo.clearItemArtworkCalls.single.role, 'disc');
  });

  testWidgets('entity links open the three entities behind an item', (
    tester,
  ) async {
    final repo = _repo();
    repo.metadataEntityPids['tr-1'] = (
      artistPid: 'ar-01JZX5N8QW3F4V9T2B7KDBREE1',
      albumPid: 'al-01JZX5N8QW3F4V9T2B7KDBLUES',
      releaseGroupPid: 'rg-01JZX5N8QW3F4V9T2B7KDBWORK',
    );
    await _pump(tester, _routed(_container(repo)));

    expect(find.text('Open artist'), findsOneWidget);
    expect(find.text('Open album'), findsOneWidget);
    expect(find.text('Open release group'), findsOneWidget);

    // Pushed like a search hit's entity door, so the editor stays
    // underneath to come back to.
    await tester.tap(find.text('Open artist'));
    await tester.pumpAndSettle();
    expect(find.byType(MetadataScreen), findsNothing);
  });

  testWidgets('the release-group door opens its bucket listing', (
    tester,
  ) async {
    final repo = _repo();
    repo.metadataEntityPids['tr-1'] = (
      artistPid: null,
      albumPid: null,
      releaseGroupPid: 'rg-01JZX5N8QW3F4V9T2B7KDBWORK',
    );
    await _pump(tester, _routed(_container(repo)));

    // Alone: the outer gate opens on any one of the three.
    expect(find.text('Open artist'), findsNothing);
    final door = find.bySemanticsIdentifier(
      SemanticsIds.metadataOpenReleaseGroup,
    );
    expect(door, findsOneWidget);

    await tester.tap(door);
    await tester.pumpAndSettle();
    expect(find.byType(MetadataScreen), findsNothing);
  });

  testWidgets('no entity doors without pids to open', (tester) async {
    await _pump(tester, _routed(_container(_repo())));
    expect(find.text('Open artist'), findsNothing);
    expect(find.text('Open album'), findsNothing);
    expect(find.text('Open release group'), findsNothing);
  });

  testWidgets('builds the field form from the kind vocabulary', (tester) async {
    await _pump(tester, _host(_container(_repo())));

    // The fake vocabulary defines exactly these music fields.
    for (final field in [
      'title',
      'artist',
      'album',
      'year',
      'album_artist',
      'track_no',
    ]) {
      expect(_field(field), findsOneWidget);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.fieldLock(field)),
        findsOneWidget,
      );
    }
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: _field('title'),
              matching: find.byType(TextField),
            ),
          )
          .controller
          ?.text,
      'Old Title',
    );
  });

  testWidgets('save sends only the dirty fields', (tester) async {
    final repo = _repo();
    await _pump(tester, _host(_container(repo)));

    await tester.enterText(_field('title'), 'Neon Meridian');
    await tester.pump();
    final save = find.bySemanticsIdentifier(SemanticsIds.metadataSave);
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(repo.editItemMetadataCalls, hasLength(1));
    expect(repo.editItemMetadataCalls.single.fields, {
      'title': 'Neon Meridian',
    });
    expect(repo.editItemMetadataCalls.single.writeBack, isFalse);
  });

  testWidgets('the lock toggle calls setItemLocks', (tester) async {
    final repo = _repo();
    await _pump(tester, _host(_container(repo)));

    final lock = find.bySemanticsIdentifier(SemanticsIds.fieldLock('album'));
    await tester.ensureVisible(lock);
    await tester.pumpAndSettle();
    await tester.tap(lock);
    await tester.pumpAndSettle();

    expect(repo.setItemLocksCalls, hasLength(1));
    expect(repo.setItemLocksCalls.single.fields, ['album']);
    expect(repo.setItemLocksCalls.single.locked, isTrue);
    expect(repo.lockedFieldsByPid['tr-1'], contains('album'));
  });

  testWidgets('the unofficial switch calls setReleaseStatus', (tester) async {
    final repo = _repo();
    await _pump(tester, _host(_container(repo)));

    final unofficial = find.bySemanticsIdentifier(
      SemanticsIds.unofficialSwitch,
    );
    await tester.ensureVisible(unofficial);
    await tester.pumpAndSettle();
    await tester.tap(unofficial);
    await tester.pumpAndSettle();

    expect(repo.setReleaseStatusCalls, hasLength(1));
    expect(repo.setReleaseStatusCalls.single.unofficial, isTrue);
    expect(repo.unofficialPids, contains('tr-1'));
  });

  testWidgets('a locked-field rejection hints at force', (tester) async {
    final repo = _repo();
    repo.lockedFieldsByPid['tr-1'] = {'title'};
    final container = _container(repo);
    await _pump(tester, _host(container));

    await tester.enterText(_field('title'), 'Neon Meridian');
    await tester.pump();
    final save = find.bySemanticsIdentifier(SemanticsIds.metadataSave);
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    // The server's own sentence names the field that refused; the app
    // adds the switch that overrides it.
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'field locked. Check "Force" to overwrite locked fields.',
    );
  });

  testWidgets('a fetched field lands in the form and is not offered back', (
    tester,
  ) async {
    final repo = _repo();
    // Enrichment rewrites the stored title under the open form.
    repo.onEnrich = () =>
        repo.itemFieldsByPid['tr-1']!['title'] = 'Neon Meridian';
    final container = _container(repo);
    await _pump(tester, _host(container));

    final enrich = find.bySemanticsIdentifier(SemanticsIds.metadataEnrich);
    await tester.ensureVisible(enrich);
    await tester.pumpAndSettle();
    await tester.tap(enrich);
    await tester.pumpAndSettle();

    // The form shows what was fetched...
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: _field('title'),
              matching: find.byType(TextField),
            ),
          )
          .controller
          ?.text,
      'Neon Meridian',
    );
    // ...and Save is not offering to write the old title back over it.
    final save = tester.widget<WaxButton>(
      find.ancestor(of: find.text('Save'), matching: find.byType(WaxButton)),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('a field being edited keeps its text through a refetch', (
    tester,
  ) async {
    final repo = _repo();
    repo.onEnrich = () =>
        repo.itemFieldsByPid['tr-1']!['title'] = 'Fetched Title';
    final container = _container(repo);
    await _pump(tester, _host(container));

    await tester.enterText(_field('title'), 'Mine');
    await tester.pump();
    final enrich = find.bySemanticsIdentifier(SemanticsIds.metadataEnrich);
    await tester.ensureVisible(enrich);
    await tester.pumpAndSettle();
    await tester.tap(enrich);
    await tester.pumpAndSettle();

    // The edit outranks the refetch: nothing types over somebody.
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: _field('title'),
              matching: find.byType(TextField),
            ),
          )
          .controller
          ?.text,
      'Mine',
    );
  });

  testWidgets('the lyrics preview counts what is timed', (tester) async {
    await _pump(tester, _host(_container(_repo())));

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.lyricsField),
      '[00:12.00] First line\nsecond line, untimed',
    );
    await tester.pumpAndSettle();

    expect(find.text('2 lines, 1 timed'), findsOneWidget);
    expect(find.text('00:12'), findsOneWidget);
    expect(find.text('First line'), findsOneWidget);
  });

  testWidgets('rematch reports the queued review entry', (tester) async {
    final repo = _repo();
    final container = _container(repo);
    // Routed: the message offers a jump to the entry, which needs the
    // router the app always has.
    await _pump(tester, _routed(container));

    final rematch = find.bySemanticsIdentifier(SemanticsIds.metadataRematch);
    await tester.ensureVisible(rematch);
    await tester.pumpAndSettle();
    await tester.tap(rematch);
    await tester.pumpAndSettle();

    expect(repo.rematchCalls, ['tr-1']);
    final message = container.read(shellMessengerProvider);
    expect(shellMessageText(message), 'Queued for identification');
    expect(message?.actionLabel, 'Open review');
  });

  testWidgets('a caller who may not curate gets the refusal, not the form', (
    tester,
  ) async {
    final repo = _repo()..mayCurateItems = false;
    await _pump(tester, _routed(_container(repo)));

    expect(
      find.bySemanticsIdentifier(SemanticsIds.metadataForbidden),
      findsOneWidget,
    );
    expect(find.text('This one is not yours to edit'), findsOneWidget);
    // Its own handle, not the editor's: a refusal wearing the surface
    // it refuses is how a test passes on the wrong page.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.metadataEditor),
      findsNothing,
    );
    // Not merely a disabled Save: the whole form is withheld, because
    // this location is shareable and a form nothing can save is worse
    // than a sentence saying why.
    expect(_field('title'), findsNothing);
    expect(find.bySemanticsIdentifier(SemanticsIds.metadataSave), findsNothing);
  });

  testWidgets('a server that says nothing gets the form, not the refusal', (
    tester,
  ) async {
    // One too old to carry the field, or one whose ownership lookup
    // failed. Treating that silence as a no would hand an administrator
    // a "not yours" page for an item that server would save, and there
    // is nothing to retry: the read answered 200.
    final repo = _repo()..mayCurateItems = null;
    await _pump(tester, _routed(_container(repo)));

    expect(
      find.bySemanticsIdentifier(SemanticsIds.metadataForbidden),
      findsNothing,
    );
    expect(_field('title'), findsOneWidget);
  });

  testWidgets('field names are drawn in words rather than in wire keys', (
    tester,
  ) async {
    await _pump(tester, _host(_container(_repo())));

    // The vocabulary arrives as wire keys, which were only ever an
    // accessible name until the label started being drawn.
    expect(find.text('Album artist'), findsOneWidget);
    expect(find.text('album_artist'), findsNothing);
    expect(find.text('Track number'), findsOneWidget);
  });
}
