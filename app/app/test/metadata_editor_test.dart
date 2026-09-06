import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/metadata/artwork_manager.dart';
import 'package:waxdeck/src/metadata/metadata_controller.dart';
import 'package:waxdeck/src/metadata/metadata_form.dart';
import 'package:waxdeck/src/metadata/metadata_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/routes.dart';
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
      // The session gate: without a working store the auth probe never
      // settles, and the admin-only reads (the genre vocabulary) gate
      // on the role that probe reports.
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
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

FakeRepository _repo({bool admin = false}) {
  final repo = FakeRepository(
    sessionState: admin
        ? const SessionState(
            authenticated: true,
            user: WaxDeckUser(
              id: 'us-1',
              username: 'admin',
              roles: <String>['admin'],
            ),
          )
        : null,
    items: [testItem('tr-1', title: 'Old Title')],
  );
  repo.itemFieldsByPid['tr-1'] = {
    'title': 'Old Title',
    'artist': 'The Bree Trio',
    'album': 'Prancing Pony Blues',
    'year': '2011',
  };
  return repo;
}

/// A music vocabulary of exactly [fields], for the typed-row tests the
/// default six-field fake does not cover.
MetadataFields _vocabulary(List<String> fields) => MetadataFields(
  kinds: [
    KindFields(
      kind: MediaType.music,
      fields: [
        for (final field in fields) EditableField(name: field, writeBack: true),
      ],
      creditRoles: const [EditableField(name: 'composer', writeBack: true)],
    ),
  ],
  entityTypes: const [],
);

Finder _field(String name) =>
    find.bySemanticsIdentifier(SemanticsIds.metadataField(name));

/// Presses the save bar's button and settles.
Future<void> _saveNow(WidgetTester tester) async {
  final save = find.bySemanticsIdentifier(SemanticsIds.metadataSave);
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  await tester.tap(save);
  await tester.pumpAndSettle();
}

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
    // One borrowed-form sentence, not two glued with a separator.
    expect(find.text("Art from a track's file"), findsOneWidget);
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

  testWidgets('a field chip names its producer rather than the wire word', (
    tester,
  ) async {
    // The chip used to print the server's own tokens - `enrichment`,
    // `musicbrainz` - at the reader. The provider is the answer when
    // one supplied the value, which is how the header tally keys it.
    final repo = _repo()
      ..itemProvenance['tr-1'] = const <FieldProvenance>[
        FieldProvenance(
          field: 'title',
          source: 'enrichment',
          provider: 'musicbrainz',
          locked: false,
        ),
        FieldProvenance(field: 'artist', source: 'tag', locked: false),
      ];
    await _pump(tester, _host(_container(repo)));

    expect(find.text('MusicBrainz'), findsOneWidget);
    expect(find.text('tags'), findsOneWidget);
    expect(find.text('enrichment'), findsNothing);
    expect(find.text('musicbrainz'), findsNothing);
  });

  testWidgets('the header states a recorded origin and offers to correct it', (
    tester,
  ) async {
    final repo = _repo()
      ..itemAcquisition['tr-1'] = ItemAcquisition(
        sourceType: 'manual',
        sourceUrl: 'https://feeds.example.test/show/ep-12.mp3',
        acquiredAt: DateTime.utc(2026, 8, 25),
      );
    await _pump(tester, _host(_container(repo)));

    expect(
      find.text(
        'Origin: an unnamed source - https://feeds.example.test/show/ep-12.mp3',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Recorded evidence of how this arrived. Tap to correct it.'),
      findsOneWidget,
    );
  });

  testWidgets('an unconfirmed permission draws the origin as read-only', (
    tester,
  ) async {
    // The server omits mayCurate when the lookup behind it failed, and
    // the pane still renders (only an explicit false forbids). The
    // header must not offer a correction it cannot promise, so it falls
    // back to the read-only wording.
    final repo = _repo()
      ..mayCurateItems = null
      ..itemAcquisition['tr-1'] = ItemAcquisition(sourceType: 'rss');
    await _pump(tester, _host(_container(repo)));

    expect(
      find.text(
        'Recorded evidence of how this arrived, not an editable field.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('an origin with no shareable address still names its kind', (
    tester,
  ) async {
    // The server drops a URL it cannot redact into something safe for
    // everyone who can see the item, so the kind is all that is left.
    final repo = _repo()
      ..itemAcquisition['tr-1'] = ItemAcquisition(
        sourceType: 'rss',
        acquiredAt: DateTime.utc(2026, 8, 25),
      );
    await _pump(tester, _host(_container(repo)));

    expect(find.text('Origin: a podcast feed'), findsOneWidget);
  });

  testWidgets('an item with no recorded origin still offers a curator one', (
    tester,
  ) async {
    // Stating an origin is the same write as correcting one, and there
    // is nowhere else to say where a file came from - so the row is
    // drawn, reading as the local file the absent row means.
    await _pump(tester, _host(_container(_repo())));

    expect(find.text('Origin: a local file'), findsOneWidget);
  });

  testWidgets('no origin and no curate permission draws no origin line', (
    tester,
  ) async {
    await _pump(tester, _host(_container(_repo()..mayCurateItems = null)));

    expect(find.textContaining('Origin: '), findsNothing);
  });

  testWidgets('correcting the origin sends every column as it stands', (
    tester,
  ) async {
    final repo = _repo()
      ..itemAcquisition['tr-1'] = ItemAcquisition(
        sourceType: 'manual',
        sourceUrl: 'https://wrong.example.test/ep-99.mp3',
        sourceId: 'ep-99',
      );
    final container = _container(repo);
    await _pump(tester, _host(container));

    await tester.tap(
      find.text(
        'Origin: an unnamed source - https://wrong.example.test/ep-99.mp3',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Where this came from'), findsOneWidget);

    // Retype the address and empty the identifier: an absent column is
    // cleared, which is what makes lowering a wrong value possible.
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.originUrl),
      'https://right.example.test/ep-1.mp3',
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.originId),
      '',
    );
    await tester.tap(find.text('Podcast feed'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.originSave));
    await tester.pumpAndSettle();

    expect(repo.setItemAcquisitionCalls, hasLength(1));
    final sent = repo.setItemAcquisitionCalls.single;
    expect(sent.sourceType, 'rss');
    expect(sent.sourceUrl, 'https://right.example.test/ep-1.mp3');
    expect(sent.sourceId, isNull);
    expect(sent.writeBack, isFalse);
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'Origin updated',
    );
  });

  testWidgets('an untouched address is left alone rather than resent', (
    tester,
  ) async {
    // The read redacts, so the box holds what the server was willing to
    // show and not what it stored. Resending that would replace a
    // ?v=XYZ with the truncated form - and with write-back on, in the
    // file's tags too. Only a typed change is authoritative.
    final repo = _repo()
      ..itemAcquisition['tr-1'] = ItemAcquisition(
        sourceType: 'youtube',
        sourceUrl: 'https://www.youtube.test/watch',
        sourceId: 'XYZ',
      );
    await _pump(tester, _host(_container(repo)));

    await tester.tap(
      find.text('Origin: YouTube - https://www.youtube.test/watch'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.originProvider),
      'waxtap',
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.originSave));
    await tester.pumpAndSettle();

    expect(repo.setItemAcquisitionCalls.single.sourceUrl, isNull);
    expect(repo.setItemAcquisitionCalls.single.provider, 'waxtap');
  });

  testWidgets('emptying the address box is how it comes off', (tester) async {
    final repo = _repo()
      ..itemAcquisition['tr-1'] = ItemAcquisition(
        sourceType: 'rss',
        sourceUrl: 'https://feeds.example.test/ep.mp3',
      );
    await _pump(tester, _host(_container(repo)));

    await tester.tap(
      find.text('Origin: a podcast feed - https://feeds.example.test/ep.mp3'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.originUrl),
      '',
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.originSave));
    await tester.pumpAndSettle();

    expect(repo.setItemAcquisitionCalls.single.sourceUrl, '');
  });

  testWidgets('the origin sheet can take the row off entirely', (tester) async {
    final repo = _repo()
      ..itemAcquisition['tr-1'] = ItemAcquisition(sourceType: 'rss');
    final container = _container(repo);
    await _pump(tester, _host(container));

    await tester.tap(find.text('Origin: a podcast feed'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.originClear));
    await tester.pumpAndSettle();

    expect(repo.clearItemAcquisitionCalls, hasLength(1));
    expect(repo.setItemAcquisitionCalls, isEmpty);
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'Origin removed',
    );
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

  testWidgets('the unofficial switch stages; the save commits', (tester) async {
    final repo = _repo();
    await _pump(tester, _host(_container(repo)));

    final unofficial = find.bySemanticsIdentifier(
      SemanticsIds.unofficialSwitch,
    );
    await tester.ensureVisible(unofficial);
    await tester.pumpAndSettle();
    await tester.tap(unofficial);
    await tester.pumpAndSettle();

    // Staged, not sent: the save bar is the only thing that writes.
    expect(repo.setReleaseStatusCalls, isEmpty);

    final save = find.bySemanticsIdentifier(SemanticsIds.metadataSave);
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
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
    // The fetch previews first; applying the (empty) preview is what
    // runs it.
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.enrichPreviewApply),
    );
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

  testWidgets('a count field refuses everything but digits', (tester) async {
    await _pump(tester, _host(_container(_repo())));

    await tester.enterText(_field('year'), '19x9');
    await tester.pump();

    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: _field('year'),
              matching: find.byType(TextField),
            ),
          )
          .controller
          ?.text,
      '199',
    );
  });

  testWidgets('compilation is a switch and saves the wire word', (
    tester,
  ) async {
    final repo = _repo()
      ..metadataFields = _vocabulary(['title', 'compilation']);
    await _pump(tester, _host(_container(repo)));

    final toggle = _field('compilation');
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(repo.editItemMetadataCalls, isEmpty);
    await _saveNow(tester);

    expect(repo.editItemMetadataCalls.single.fields, {'compilation': 'true'});
  });

  testWidgets('genres are chips; removing one stages the shorter set', (
    tester,
  ) async {
    final repo = _repo()..metadataFields = _vocabulary(['title', 'genre']);
    repo.itemFieldsByPid['tr-1']!['genre'] = 'Rock; Jazz';
    await _pump(tester, _host(_container(repo)));

    final chip = find.bySemanticsIdentifier(
      SemanticsIds.metadataGenreRemove('Jazz'),
    );
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await _saveNow(tester);

    expect(repo.editItemMetadataCalls.single.fields, {'genre': 'Rock'});
  });

  testWidgets('an administrator picks genres over the canonical tree', (
    tester,
  ) async {
    final repo = _repo(admin: true)
      ..metadataFields = _vocabulary(['title', 'genre']);
    repo.itemFieldsByPid['tr-1']!['genre'] = 'Rock';
    repo.genreTree = const [
      GenreNode(name: 'Electronic'),
      GenreNode(name: 'House', parent: 'Electronic'),
    ];
    await _pump(tester, _host(_container(repo)));

    final add = find.bySemanticsIdentifier(SemanticsIds.metadataGenreAdd);
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.metadataGenrePicker),
      findsOneWidget,
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.metadataGenreOption('House')),
    );
    await tester.pump();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.metadataGenrePickerApply),
    );
    await tester.pumpAndSettle();

    // Staged as a chip, then saved joined onto what was already there.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.metadataGenreRemove('House')),
      findsOneWidget,
    );
    await _saveNow(tester);
    expect(repo.editItemMetadataCalls.single.fields, {'genre': 'Rock; House'});
  });

  testWidgets('without the tree the picker takes genres as typed', (
    tester,
  ) async {
    // Not an administrator: the canonical vocabulary read is refused,
    // so the sheet has no list - and typing still works, because typing
    // is what every session may store.
    final repo = _repo()..metadataFields = _vocabulary(['title', 'genre']);
    repo.itemFieldsByPid['tr-1']!['genre'] = 'Rock';
    await _pump(tester, _host(_container(repo)));

    final add = find.bySemanticsIdentifier(SemanticsIds.metadataGenreAdd);
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.metadataGenrePickerSearch),
      'Zeuhl',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.metadataGenrePickerCustom),
    );
    await tester.pump();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.metadataGenrePickerApply),
    );
    await tester.pumpAndSettle();
    await _saveNow(tester);

    expect(repo.editItemMetadataCalls.single.fields, {'genre': 'Rock; Zeuhl'});
  });

  testWidgets('credits are chips per role; edits save the changed role', (
    tester,
  ) async {
    final repo = _repo();
    repo.creditsByPid['tr-1'] = const [
      Credit(role: 'artist', names: ['The Bree Trio']),
      Credit(role: 'composer', names: ['Ann Lee', 'Bob Ray']),
    ];
    await _pump(tester, _host(_container(repo)));

    // The vocabulary's role is chips; the artist credit is not - its
    // sanctioned edit path is the artist field that resolves it.
    expect(
      find.bySemanticsIdentifier(
        SemanticsIds.creditRemove('composer', 'Bob Ray'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(
        SemanticsIds.creditRemove('artist', 'The Bree Trio'),
      ),
      findsNothing,
    );

    final remove = find.bySemanticsIdentifier(
      SemanticsIds.creditRemove('composer', 'Bob Ray'),
    );
    await tester.ensureVisible(remove);
    await tester.pumpAndSettle();
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.creditsNames),
      'Cara Dune',
    );
    final add = find.bySemanticsIdentifier(SemanticsIds.creditAdd);
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    await _saveNow(tester);

    final composer = repo.creditsByPid['tr-1']!
        .where((c) => c.role == 'composer')
        .single;
    expect(composer.names, ['Ann Lee', 'Cara Dune']);
    // The untouched role was not rewritten alongside it.
    final artist = repo.creditsByPid['tr-1']!
        .where((c) => c.role == 'artist')
        .single;
    expect(artist.names, ['The Bree Trio']);
  });

  testWidgets('tag edits stage, and one save commits them all', (tester) async {
    final repo = _repo();
    repo.tagsByPid['tr-1'] = {
      'MOOD': ['calm'],
    };
    await _pump(tester, _host(_container(repo)));

    final remove = find.bySemanticsIdentifier(SemanticsIds.tagRemove('MOOD'));
    await tester.ensureVisible(remove);
    await tester.pumpAndSettle();
    await tester.tap(remove);
    await tester.pumpAndSettle();
    // Staged, not deleted - and reversible before the save.
    expect(repo.tagsByPid['tr-1'], containsPair('MOOD', ['calm']));
    expect(
      find.bySemanticsIdentifier(SemanticsIds.tagRestore('MOOD')),
      findsOneWidget,
    );

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.tagKey),
      'ENERGY',
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.tagValues),
      'high',
    );
    final add = find.bySemanticsIdentifier(SemanticsIds.tagAdd);
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(repo.tagsByPid['tr-1'], isNot(contains('ENERGY')));

    await tester.enterText(_field('title'), 'Neon Meridian');
    await tester.pump();
    await _saveNow(tester);

    // One save, three write paths.
    expect(repo.editItemMetadataCalls.single.fields, {
      'title': 'Neon Meridian',
    });
    expect(repo.tagsByPid['tr-1'], isNot(contains('MOOD')));
    expect(repo.tagsByPid['tr-1'], containsPair('ENERGY', ['high']));
  });

  testWidgets('a reserved key is refused at the tag field', (tester) async {
    final repo = _repo();
    await _pump(tester, _host(_container(repo)));

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.tagKey),
      'bpm',
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.tagValues),
      '128',
    );
    final add = find.bySemanticsIdentifier(SemanticsIds.tagAdd);
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();

    // Refused where it was typed, with the reason, rather than staged
    // and taking the whole draft's save down with it. Case-folded: the
    // server states the canonical key.
    expect(
      find.text('BPM is stored as its own field, not as a custom tag.'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.tagRemove('BPM')),
      findsNothing,
    );

    // Typing again clears the refusal, so the field is not stuck red.
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.tagKey),
      'ENERGY',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('BPM is stored as its own field, not as a custom tag.'),
      findsNothing,
    );
  });

  testWidgets('a staged tag removal can be taken back', (tester) async {
    final repo = _repo();
    repo.tagsByPid['tr-1'] = {
      'MOOD': ['calm'],
    };
    await _pump(tester, _host(_container(repo)));

    final remove = find.bySemanticsIdentifier(SemanticsIds.tagRemove('MOOD'));
    await tester.ensureVisible(remove);
    await tester.pumpAndSettle();
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.tagRestore('MOOD')),
    );
    await tester.pumpAndSettle();

    // Nothing staged: the save bar has nothing to do.
    final save = tester.widget<WaxButton>(
      find.ancestor(
        of: find.bySemanticsIdentifier(SemanticsIds.metadataSave),
        matching: find.byType(WaxButton),
      ),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('emptying the lyrics stages their removal', (tester) async {
    final repo = _repo();
    repo.lyricsByPid['tr-1'] = const LyricsState(
      synced: false,
      source: 'user',
      lrc: 'la la la',
    );
    await _pump(tester, _host(_container(repo)));

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.lyricsField),
      '',
    );
    await tester.pump();
    expect(repo.lyricsByPid, contains('tr-1'));
    await _saveNow(tester);

    expect(repo.lyricsByPid, isNot(contains('tr-1')));
  });

  testWidgets('the save bar counts everything staged', (tester) async {
    final repo = _repo();
    await _pump(tester, _host(_container(repo)));

    await tester.enterText(_field('title'), 'Neon Meridian');
    await tester.pump();
    final unofficial = find.bySemanticsIdentifier(
      SemanticsIds.unofficialSwitch,
    );
    await tester.ensureVisible(unofficial);
    await tester.pumpAndSettle();
    await tester.tap(unofficial);
    await tester.pumpAndSettle();

    expect(find.text('Save 2 changes'), findsOneWidget);
  });

  testWidgets('a staged draft does not follow a go to another item', (
    tester,
  ) async {
    // The player's Edit metadata rows `go` between /metadata/<pid>
    // locations, and go_router keys the page by the route pattern - so
    // without the pid key on the screen, the same State (and the whole
    // staged draft) would carry from one item onto the next.
    final repo = _repo();
    repo.libraryItems.add(testItem('tr-2', title: 'Second Title'));
    repo.itemFieldsByPid['tr-2'] = {'title': 'Second Title'};
    await _pump(tester, _routed(_container(repo)));

    final router = GoRouter.of(tester.element(find.byType(MetadataScreen)));
    router.go(WaxRoute.metadata('tr-2'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('title'), 'Staged On Two');
    await tester.pump();
    expect(find.text('Save 1 change'), findsOneWidget);

    router.go(WaxRoute.metadata('tr-1'));
    await tester.pumpAndSettle();

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
    expect(find.text('Save 1 change'), findsNothing);
  });

  testWidgets('a stray space in the lyrics box does not delete a fetch', (
    tester,
  ) async {
    final repo = _repo();
    repo.onEnrich = () => repo.lyricsByPid['tr-1'] = const LyricsState(
      synced: false,
      source: 'enrichment',
      lrc: 'la la la',
    );
    await _pump(tester, _host(_container(repo)));

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.lyricsField),
      ' ',
    );
    await tester.pump();
    final enrich = find.bySemanticsIdentifier(SemanticsIds.metadataEnrich);
    await tester.ensureVisible(enrich);
    await tester.pumpAndSettle();
    await tester.tap(enrich);
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.enrichPreviewApply),
    );
    await tester.pumpAndSettle();

    // The fetched lyrics land in the box - whitespace is not an edit
    // that outranks them - and nothing offers to save their removal.
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.bySemanticsIdentifier(SemanticsIds.lyricsField),
              matching: find.byType(TextField),
            ),
          )
          .controller
          ?.text,
      'la la la',
    );
    final save = tester.widget<WaxButton>(
      find.ancestor(
        of: find.bySemanticsIdentifier(SemanticsIds.metadataSave),
        matching: find.byType(WaxButton),
      ),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('typed genres split on the separators the catalog splits on', (
    tester,
  ) async {
    // `Singer/Songwriter` is two genres to the store; staged as one it
    // would come back split and read as dirty for ever.
    final repo = _repo()..metadataFields = _vocabulary(['title', 'genre']);
    repo.itemFieldsByPid['tr-1']!['genre'] = 'Rock';
    await _pump(tester, _host(_container(repo)));

    final add = find.bySemanticsIdentifier(SemanticsIds.metadataGenreAdd);
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.metadataGenrePickerSearch),
      'Singer/Songwriter',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.metadataGenrePickerCustom),
    );
    await tester.pump();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.metadataGenrePickerApply),
    );
    await tester.pumpAndSettle();
    await _saveNow(tester);

    expect(repo.editItemMetadataCalls.single.fields, {
      'genre': 'Rock; Singer; Songwriter',
    });
    // And the echo reads as saved, not as one more change to make.
    final save = tester.widget<WaxButton>(
      find.ancestor(
        of: find.bySemanticsIdentifier(SemanticsIds.metadataSave),
        matching: find.byType(WaxButton),
      ),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('a tag key stages canonical, so its echo reads as saved', (
    tester,
  ) async {
    // The server uppercases tag keys on store; a key staged as typed
    // would never match the row it comes back as, and the draft would
    // offer the identical write for ever.
    final repo = _repo();
    await _pump(tester, _host(_container(repo)));

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.tagKey),
      'mood',
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.tagValues),
      'calm',
    );
    final add = find.bySemanticsIdentifier(SemanticsIds.tagAdd);
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    await _saveNow(tester);

    expect(repo.tagsByPid['tr-1'], containsPair('MOOD', ['calm']));
    final save = tester.widget<WaxButton>(
      find.ancestor(
        of: find.bySemanticsIdentifier(SemanticsIds.metadataSave),
        matching: find.byType(WaxButton),
      ),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('a tag with no values does not stage', (tester) async {
    // Staged, it would be a row the change count cannot see: an
    // "Unsaved" chip over a save bar that stays off.
    final repo = _repo();
    await _pump(tester, _host(_container(repo)));

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.tagKey),
      'MOOD',
    );
    final add = find.bySemanticsIdentifier(SemanticsIds.tagAdd);
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.tagRemove('MOOD')),
      findsNothing,
    );
    final save = tester.widget<WaxButton>(
      find.ancestor(
        of: find.bySemanticsIdentifier(SemanticsIds.metadataSave),
        matching: find.byType(WaxButton),
      ),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('a refusal keeps the later staged parts staged', (tester) async {
    // The fields write refuses on a lock; the tag staged behind it must
    // neither be written nor lost.
    final repo = _repo();
    repo.lockedFieldsByPid['tr-1'] = {'title'};
    final container = _container(repo);
    await _pump(tester, _host(container));

    await tester.enterText(_field('title'), 'Neon Meridian');
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.tagKey),
      'MOOD',
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.tagValues),
      'calm',
    );
    final add = find.bySemanticsIdentifier(SemanticsIds.tagAdd);
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    await _saveNow(tester);

    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'field locked. Check "Force" to overwrite locked fields.',
    );
    // Not written, still staged: the count and the chip both stand.
    expect(repo.tagsByPid['tr-1'], isNot(contains('MOOD')));
    expect(find.text('Save 2 changes'), findsOneWidget);
  });

  testWidgets('one save is one request where the server has the route', (
    tester,
  ) async {
    // The point of the compound endpoint: a phone reaching a home
    // server through a proxy pays one round trip for a Save rather than
    // one per staged part.
    final repo = _repo();
    final container = _container(repo);
    await _pump(tester, _host(container));

    await tester.enterText(_field('title'), 'Neon Meridian');
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.tagKey),
      'MOOD',
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.tagValues),
      'calm',
    );
    final add = find.bySemanticsIdentifier(SemanticsIds.tagAdd);
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    await _saveNow(tester);

    expect(repo.commitCalls, hasLength(1));
    expect(repo.commitCalls.single.commit.fields, {'title': 'Neon Meridian'});
    expect(repo.commitCalls.single.commit.tagSets, {
      'MOOD': ['calm'],
    });
    expect(repo.itemFieldsByPid['tr-1']?['title'], 'Neon Meridian');
    expect(repo.tagsByPid['tr-1']?['MOOD'], ['calm']);
  });

  testWidgets('an older server takes the sequential path, once asked', (
    tester,
  ) async {
    // A server without the route answers the router's unmatched-path
    // 404 as plain text, which the transport reports as `transport`
    // rather than `not-found`. The answer is remembered: the next save
    // does not ask again.
    final repo = _repo()
      ..commitError = const WaxDeckApiException(
        code: 'transport',
        message: '404 page not found',
        statusCode: 404,
      );
    final container = _container(repo);
    await _pump(tester, _host(container));

    await tester.enterText(_field('title'), 'Neon Meridian');
    await _saveNow(tester);

    expect(repo.commitCalls, hasLength(1), reason: 'asked once');
    expect(repo.editItemMetadataCalls.single.fields, {
      'title': 'Neon Meridian',
    });
    expect(repo.itemFieldsByPid['tr-1']?['title'], 'Neon Meridian');
    expect(container.read(compoundSaveProvider), isFalse);

    await tester.enterText(_field('artist'), 'The Bree Trio Redux');
    await _saveNow(tester);

    expect(
      repo.editItemMetadataCalls,
      hasLength(2),
      reason: 'the second save runs sequentially',
    );
    expect(
      repo.commitCalls,
      hasLength(1),
      reason: 'and does not ask the missing route again',
    );
  });

  testWidgets(
    'an item that is gone does not put the session on the slow path',
    (tester) async {
      // A genuine item-404 carries the server's own `not-found`, and is a
      // refusal of this save rather than a verdict on the server. Reading
      // the status code alone would let one bad pid cost every later save
      // a round trip per part.
      final repo = _repo()
        ..commitError = const WaxDeckApiException(
          code: 'not-found',
          message: 'no item with pid tr-1',
          statusCode: 404,
        );
      final container = _container(repo);
      await _pump(tester, _host(container));

      await tester.enterText(_field('title'), 'Neon Meridian');
      await _saveNow(tester);

      expect(repo.editItemMetadataCalls, isEmpty);
      expect(container.read(compoundSaveProvider), isTrue);
    },
  );

  // Parity between the two save paths is what lets the sequential one
  // stand in as the fallback, so the same refusal is driven through both
  // and both are held to this one sentence.
  const lockedTitleRefusal =
      'field locked. Check "Force" to overwrite locked fields.';

  Future<void> saveOverALockedTitle(
    WidgetTester tester, {
    required bool compound,
  }) async {
    final repo = _repo()..lockedFieldsByPid['tr-1'] = {'title'};
    if (!compound) {
      repo.commitError = const WaxDeckApiException(
        code: 'transport',
        message: '404 page not found',
        statusCode: 404,
      );
    }
    final container = _container(repo);
    await _pump(tester, _host(container));
    await tester.enterText(_field('title'), 'Neon Meridian');
    await _saveNow(tester);
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      lockedTitleRefusal,
    );
    expect(repo.itemFieldsByPid['tr-1']?['title'], isNot('Neon Meridian'));
  }

  testWidgets('the compound path words a refused part like the server does', (
    tester,
  ) async {
    await saveOverALockedTitle(tester, compound: true);
  });

  testWidgets('the sequential fallback words the same refusal the same way', (
    tester,
  ) async {
    await saveOverALockedTitle(tester, compound: false);
  });

  testWidgets('plain lyrics go to the server as plain text', (tester) async {
    // The LRC parser drops unstamped lines and refuses the empty
    // result, so text with no stamps must say what it is.
    final repo = _repo();
    await _pump(tester, _host(_container(repo)));

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.lyricsField),
      'just some words',
    );
    await tester.pump();
    await _saveNow(tester);

    final stored = repo.lyricsByPid['tr-1']!;
    expect(stored.synced, isFalse);
    expect(stored.lrc, 'just some words');
  });

  testWidgets('no save bar over the load error page', (tester) async {
    final repo = _repo()
      ..metadataError = const WaxDeckApiException(
        code: 'internal',
        message: 'boom',
        statusCode: 500,
      );
    await _pump(tester, _host(_container(repo)));

    expect(find.text('Could not load the metadata'), findsOneWidget);
    expect(find.bySemanticsIdentifier(SemanticsIds.metadataSave), findsNothing);
  });

  testWidgets('episode type is a closed choice, not a text box', (
    tester,
  ) async {
    // The server refuses anything outside full|trailer|bonus, and a
    // typo there would take the whole unified save down with it.
    final repo = FakeRepository(
      items: [testItem('ep-1', mediaType: MediaType.podcast)],
    );
    repo.metadataFields = const MetadataFields(
      kinds: [
        KindFields(
          kind: MediaType.podcast,
          fields: [
            EditableField(name: 'title', writeBack: false),
            EditableField(name: 'episode_type', writeBack: false),
          ],
        ),
      ],
      entityTypes: [],
    );
    repo.itemFieldsByPid['ep-1'] = {'title': 'An Episode'};
    final container = _container(repo);
    addTearDown(container.dispose);
    await _pump(
      tester,
      UncontrolledProviderScope(
        container: container,
        child: localizedHost(const MetadataScreen(pid: 'ep-1')),
      ),
    );

    final choice = _field('episode_type');
    await tester.ensureVisible(choice);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: choice, matching: find.byType(TextField)),
      findsNothing,
    );
    await tester.tap(choice);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trailer').last);
    await tester.pumpAndSettle();
    await _saveNow(tester);

    expect(repo.editItemMetadataCalls.single.fields, {
      'episode_type': 'trailer',
    });
    // Episodes never write back, so the switch is not even offered -
    // and the cover pin is not either: the art lock applies to tracks
    // and books only, and the store refuses it for an episode.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.metadataWriteback),
      findsNothing,
    );
    expect(find.bySemanticsIdentifier(SemanticsIds.artLock), findsNothing);
    // The per-role pins go with it. The catalog curates art on tracks
    // and books, so `art.<role>` on an episode is refused outright -
    // offering four toggles that each answer 400 is worse than
    // offering none. The grid is drawn either way, which is what keeps
    // the assertions below from passing on an absent manager.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.artSlot('back')),
      findsOneWidget,
    );
    for (final role in <String>['back', 'disc', 'booklet', 'background']) {
      expect(
        find.bySemanticsIdentifier(SemanticsIds.artLockRole(role)),
        findsNothing,
        reason: 'an episode offered the $role pin',
      );
    }
  });

  testWidgets('an auxiliary pin stays offered on a slot the cover pin holds', (
    tester,
  ) async {
    // A slot the whole-artwork pin holds carries no pin of its own, so
    // the toggle offers to give it one - which outlives the cover pin
    // coming off. Disabling it here was the earlier bug: it disabled
    // the control on exactly the cleared-and-pinned slot it exists to
    // release. The caption is what explains the state instead.
    final repo = _repo()
      ..artRoles.add(
        const ArtRoleInfo(role: 'back', locked: true, roleLocked: false),
      );
    await _pump(tester, _host(_container(repo)));

    expect(find.text('Held by the cover pin'), findsOneWidget);

    final pin = find.bySemanticsIdentifier(SemanticsIds.artLockRole('back'));
    await tester.ensureVisible(pin);
    await tester.pumpAndSettle();
    await tester.tap(pin);
    await tester.pumpAndSettle();

    expect(repo.setItemLocksCalls, isNotEmpty);
    expect(repo.setItemLocksCalls.last.fields, const <String>[
      'art.back',
    ], reason: 'the pin wrote a different field');
    expect(
      repo.setItemLocksCalls.last.locked,
      isTrue,
      reason: 'the slot has no pin of its own, so the toggle sets one',
    );
  });

  testWidgets('a whole-artwork pin captions the slots it holds', (
    tester,
  ) async {
    // A pin with no image anywhere synthesizes a front row and nothing
    // else, so an auxiliary slot it holds carries no row of its own -
    // the caption has to come from the front row's pin, the way the
    // server's own lock read answers for the same slot.
    final repo = _repo()
      ..artRoles.add(
        const ArtRoleInfo(role: 'front', locked: true, roleLocked: true),
      );
    await _pump(tester, _host(_container(repo)));

    // One per auxiliary slot; the front's own pin is not "held by" it.
    expect(find.text('Held by the cover pin'), findsNWidgets(4));
  });

  testWidgets('a server with no role pin still releases a slot', (
    tester,
  ) async {
    // The field is absent from a server predating it, and absent is not
    // false: reading it as false would draw an own-pinned slot as open
    // and turn its toggle into a re-pin, with no way to release the
    // slot at all. The fallback is the effective lock, which is what
    // that server's reading meant.
    final repo = _repo()
      ..artRoles.add(const ArtRoleInfo(role: 'back', locked: true));
    await _pump(tester, _host(_container(repo)));

    expect(find.text('Held by the cover pin'), findsNothing);

    final pin = find.bySemanticsIdentifier(SemanticsIds.artLockRole('back'));
    await tester.ensureVisible(pin);
    await tester.pumpAndSettle();
    await tester.tap(pin);
    await tester.pumpAndSettle();

    expect(repo.setItemLocksCalls.last.fields, const <String>['art.back']);
    expect(
      repo.setItemLocksCalls.last.locked,
      isFalse,
      reason: 'the toggle re-pinned a slot instead of releasing it',
    );
  });

  testWidgets("a slot holding its own pin offers to release it", (
    tester,
  ) async {
    // Its own pin set: the toggle reads pinned and unpinning it is what
    // opens the slot, so no caption about the cover pin appears.
    final repo = _repo()
      ..artRoles.add(
        const ArtRoleInfo(role: 'back', locked: true, roleLocked: true),
      );
    await _pump(tester, _host(_container(repo)));

    expect(find.text('Held by the cover pin'), findsNothing);

    final pin = find.bySemanticsIdentifier(SemanticsIds.artLockRole('back'));
    await tester.ensureVisible(pin);
    await tester.pumpAndSettle();
    await tester.tap(pin);
    await tester.pumpAndSettle();

    expect(repo.setItemLocksCalls.last.fields, const <String>['art.back']);
    expect(repo.setItemLocksCalls.last.locked, isFalse);
  });

  test('a saved value settles onto its normalized echo', () {
    // The server trims what it stores: send `Neon `, get `Neon` back.
    // Re-seeded to what was sent, the field counts as untouched and
    // adopts the echo instead of offering the same write for ever.
    final draft = MetadataDraft();
    addTearDown(draft.dispose);
    MetadataEditorState stateWith(String title) => MetadataEditorState(
      metadata: ItemMetadata(
        pid: 'tr-1',
        mediaType: MediaType.music,
        fields: {'title': title},
      ),
      kindFields: const KindFields(
        kind: MediaType.music,
        fields: [EditableField(name: 'title', writeBack: true)],
      ),
    );

    draft.controllerFor('title', 'Old').text = 'Neon ';
    final before = stateWith('Old');
    expect(draft.changes(before).fields, {'title': 'Neon '});

    draft.markSaved(draft.changes(before));
    final after = stateWith('Neon');
    draft.adopt(after);

    expect(draft.controllerFor('title', 'Neon').text, 'Neon');
    expect(draft.changes(after).isEmpty, isTrue);
  });

  testWidgets('the fetch previews first, and applying commits the proposal', (
    tester,
  ) async {
    final repo = _repo();
    repo.enrichPreview = EnrichPreview(
      fields: const [
        EnrichFieldProposal(
          name: 'genre',
          proposed: 'Jazz',
          provider: 'listenfake',
        ),
      ],
      cover: EnrichCoverProposal(provider: 'coverfake', data: _onePixelPng),
      skipped: const ['lyrics: no provider'],
    );
    await _pump(tester, _host(_container(repo)));

    final enrich = find.bySemanticsIdentifier(SemanticsIds.metadataEnrich);
    await tester.ensureVisible(enrich);
    await tester.pumpAndSettle();
    await tester.tap(enrich);
    await tester.pumpAndSettle();

    // The sheet shows the diff before anything is written.
    expect(repo.previewEnrichItemCalls, hasLength(1));
    expect(repo.enrichItemCalls, isEmpty);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.enrichPreviewRow('genre')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.enrichPreviewCover),
      findsOneWidget,
    );
    expect(find.textContaining('lyrics: no provider'), findsOneWidget);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.enrichPreviewApply),
    );
    await tester.pumpAndSettle();

    // What was approved is what was sent back, cover bytes included.
    final call = repo.enrichItemCalls.single;
    expect(call.proposal?.fields.single.proposed, 'Jazz');
    expect(call.proposal?.cover?.provider, 'coverfake');
    expect(call.proposal?.cover?.data, _onePixelPng);
  });

  testWidgets('cancelling the preview fetches nothing', (tester) async {
    final repo = _repo();
    await _pump(tester, _host(_container(repo)));

    final enrich = find.bySemanticsIdentifier(SemanticsIds.metadataEnrich);
    await tester.ensureVisible(enrich);
    await tester.pumpAndSettle();
    await tester.tap(enrich);
    await tester.pumpAndSettle();

    // The default preview is a server with no providers: nothing
    // proposed, and the confirm reads as the blind fetch it would be.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.enrichPreview),
      findsOneWidget,
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.enrichPreviewCancel),
    );
    await tester.pumpAndSettle();

    expect(repo.enrichItemCalls, isEmpty);
  });

  testWidgets('an item cover pin shows on the switch and comes off there', (
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
          locked: true,
        ),
      );
    await _pump(tester, _host(_container(repo)));

    final lock = find.bySemanticsIdentifier(SemanticsIds.artLock);
    await tester.ensureVisible(lock);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<WaxSwitch>(
            find.ancestor(of: lock, matching: find.byType(WaxSwitch)),
          )
          .value,
      isTrue,
    );

    // Unpinning rides the field-lock surface under the `art` name -
    // the one way out of a pinned empty front on an item.
    await tester.tap(lock);
    await tester.pumpAndSettle();
    final call = repo.setItemLocksCalls.single;
    expect(call.pid, 'tr-1');
    expect(call.fields, ['art']);
    expect(call.locked, isFalse);
  });

  testWidgets('a single-file book stages its chapters into the one save', (
    tester,
  ) async {
    final repo = _bookRepo();
    await _pump(
      tester,
      UncontrolledProviderScope(
        container: _container(repo),
        child: localizedHost(const MetadataScreen(pid: 'bk-1')),
      ),
    );

    expect(
      find.bySemanticsIdentifier(SemanticsIds.bookChapterEditor),
      findsOneWidget,
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.bookChapterEditorTitle(0)),
      'Prologue',
    );
    await tester.pump();
    await _saveNow(tester);

    // Ends derive contiguous: each chapter runs to the next one's
    // start, and the last is open-ended.
    final sent = repo.chapterEditsByPid['bk-1']!;
    expect(sent, hasLength(2));
    expect(sent[0].index, 0);
    expect(sent[0].title, 'Prologue');
    expect(sent[0].startMs, 0);
    expect(sent[0].endMs, 61500);
    expect(sent[1].startMs, 61500);
    expect(sent[1].endMs, isNull);
  });

  testWidgets('restoring hands the marks back to the file', (tester) async {
    final repo = _bookRepo();
    await _pump(
      tester,
      UncontrolledProviderScope(
        container: _container(repo),
        child: localizedHost(const MetadataScreen(pid: 'bk-1')),
      ),
    );

    final restore = find.bySemanticsIdentifier(
      SemanticsIds.bookChapterEditorRestore,
    );
    await tester.ensureVisible(restore);
    await tester.pumpAndSettle();
    await tester.tap(restore);
    await tester.pumpAndSettle();
    await _saveNow(tester);

    // The empty list is the endpoint's "restore the embedded chapters".
    expect(repo.chapterEditsByPid['bk-1'], isEmpty);
  });

  testWidgets('a start that does not parse keeps chapters out of the save', (
    tester,
  ) async {
    final repo = _bookRepo();
    await _pump(
      tester,
      UncontrolledProviderScope(
        container: _container(repo),
        child: localizedHost(const MetadataScreen(pid: 'bk-1')),
      ),
    );

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.bookChapterEditorStart(1)),
      'later',
    );
    await tester.pump();
    expect(find.textContaining('in playing order'), findsOneWidget);

    // Another staged part keeps the save alive; the chapters stay out.
    await tester.enterText(_field('title'), 'A Better Title');
    await tester.pump();
    await _saveNow(tester);
    expect(repo.chapterEditsByPid.containsKey('bk-1'), isFalse);
    expect(repo.editItemMetadataCalls, hasLength(1));
  });

  testWidgets('a multi-file book shows no chapter editor', (tester) async {
    final repo = _bookRepo(
      parts: const [
        BookPart(index: 0, startMs: 0, durationMs: 100000),
        BookPart(index: 1, startMs: 100000, durationMs: 100000),
      ],
    );
    await _pump(
      tester,
      UncontrolledProviderScope(
        container: _container(repo),
        child: localizedHost(const MetadataScreen(pid: 'bk-1')),
      ),
    );

    expect(
      find.bySemanticsIdentifier(SemanticsIds.bookChapterEditor),
      findsNothing,
    );
  });

  testWidgets('an added chapter files where it plays, not where it was typed', (
    tester,
  ) async {
    final repo = _bookRepo();
    await _pump(
      tester,
      UncontrolledProviderScope(
        container: _container(repo),
        child: localizedHost(const MetadataScreen(pid: 'bk-1')),
      ),
    );

    final add = find.bySemanticsIdentifier(SemanticsIds.bookChapterEditorAdd);
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pump();
    // A mid-book start on the appended row: the save files it between
    // the stored chapters rather than refusing the row order.
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.bookChapterEditorStart(2)),
      '0:30',
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.bookChapterEditorTitle(2)),
      'Interlude',
    );
    await tester.pump();
    await _saveNow(tester);

    final sent = repo.chapterEditsByPid['bk-1']!;
    expect(sent.map((c) => c.title).toList(), ['One', 'Interlude', 'Two']);
    expect(sent.map((c) => c.startMs).toList(), [0, 30000, 61500]);
    // The first chapter's stored end (61500) no longer fits before the
    // insert, so it re-derives; the tail stays open-ended.
    expect(sent.map((c) => c.endMs).toList(), [30000, 61500, null]);
  });

  testWidgets('removing a chapter drops it from the save', (tester) async {
    final repo = _bookRepo();
    await _pump(
      tester,
      UncontrolledProviderScope(
        container: _container(repo),
        child: localizedHost(const MetadataScreen(pid: 'bk-1')),
      ),
    );

    final remove = find.bySemanticsIdentifier(
      SemanticsIds.bookChapterEditorRemove(0),
    );
    await tester.ensureVisible(remove);
    await tester.pumpAndSettle();
    await tester.tap(remove);
    await tester.pump();
    await _saveNow(tester);

    final sent = repo.chapterEditsByPid['bk-1']!;
    expect(sent.single.title, 'Two');
    expect(sent.single.index, 0);
  });

  testWidgets('the chapters lock has its own toggle', (tester) async {
    // Saved chapters lock by default, so without this the second edit's
    // only door is the global Force switch.
    final repo = _bookRepo();
    repo.lockedFieldsByPid['bk-1'] = {'chapters'};
    await _pump(
      tester,
      UncontrolledProviderScope(
        container: _container(repo),
        child: localizedHost(const MetadataScreen(pid: 'bk-1')),
      ),
    );

    final lock = find.bySemanticsIdentifier(SemanticsIds.fieldLock('chapters'));
    await tester.ensureVisible(lock);
    await tester.pumpAndSettle();
    await tester.tap(lock);
    await tester.pumpAndSettle();

    final call = repo.setItemLocksCalls.single;
    expect(call.fields, ['chapters']);
    expect(call.locked, isFalse);
  });

  testWidgets('an empty preview applies as the blind fetch', (tester) async {
    // "Fetch anyway" promises the one-shot: an empty-but-present
    // proposal would commit nothing and swallow the skip reasons.
    final repo = _repo();
    await _pump(tester, _host(_container(repo)));

    final enrich = find.bySemanticsIdentifier(SemanticsIds.metadataEnrich);
    await tester.ensureVisible(enrich);
    await tester.pumpAndSettle();
    await tester.tap(enrich);
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.enrichPreviewApply),
    );
    await tester.pumpAndSettle();

    expect(repo.enrichItemCalls.single.proposal, isNull);
  });

  test('parseTimecodeMs reads garbage as unparsed, never throws', () {
    // Both shapes threw before they were tryParsed: a 400-digit number
    // parses to infinity and round() throws on it, and a 20-digit
    // minute overflows the int parse.
    expect(parseTimecodeMs('9' * 400), isNull);
    expect(parseTimecodeMs('${'9' * 20}:00'), isNull);
    expect(parseTimecodeMs('1:02:03'), 3723000);
    expect(parseTimecodeMs('90'), 90000);
  });

  test('untouched chapter rows adopt refetched marks', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final draft = MetadataDraft();
    addTearDown(draft.dispose);
    ItemMetadata metadataWith(List<ChapterMark> chapters) => ItemMetadata(
      pid: 'bk-1',
      mediaType: MediaType.audiobook,
      fields: const {},
      chapters: chapters,
    );
    MetadataEditorState stateWith(List<ChapterMark> chapters) =>
        MetadataEditorState(
          metadata: metadataWith(chapters),
          kindFields: const KindFields(kind: MediaType.audiobook, fields: []),
        );

    const before = [ChapterMark(index: 0, title: 'One', startMs: 0)];
    const after = [ChapterMark(index: 0, title: 'Renamed', startMs: 0)];
    draft.chapterRows(before);

    // Untouched rows reseed from the moved marks: without this the next
    // save would write the stale list back over them.
    draft.adopt(stateWith(after));
    expect(draft.chapterRows(after).single.titleController.text, 'Renamed');
    expect(draft.changes(stateWith(after)).chapters, isNull);

    // A typed row is the user's and outranks the refetch.
    draft.chapterRows(after).single.titleController.text = 'Mine';
    draft.adopt(stateWith(before));
    expect(draft.chapterRows(before).single.titleController.text, 'Mine');
  });

  test('a millisecond start survives an untouched round trip', () {
    // The visible stamp is whole seconds, so an untouched row must
    // answer its stored precision rather than the floor of its text.
    final draft = MetadataDraft();
    addTearDown(draft.dispose);
    final rows = draft.chapterRows(const [
      ChapterMark(index: 0, title: 'One', startMs: 12500),
      ChapterMark(index: 1, title: 'Two', startMs: 61500),
    ]);
    expect(rows[0].startMs, 12500);

    // A typed stamp is the user's, at the second granularity they see.
    rows[0].startController.text = '0:11';
    expect(rows[0].startMs, 11000);
  });
}

/// A one-file audiobook with two stored chapters, for the chapter
/// editor tests. The second start is deliberately not a whole second,
/// and the default is one part - the server synthesizes a part for a
/// partless book, so zero is a shape it can never return and a fixture
/// holding it would green-light a parts.isNotEmpty guard that hides
/// the editor from every real book.
FakeRepository _bookRepo({
  List<BookPart> parts = const [
    BookPart(index: 0, startMs: 0, durationMs: 200000),
  ],
}) {
  final repo = FakeRepository(
    items: [
      testItem('bk-1', mediaType: MediaType.audiobook, title: 'The Long Walk'),
    ],
  );
  repo.metadataFields = const MetadataFields(
    kinds: [
      KindFields(
        kind: MediaType.audiobook,
        fields: [EditableField(name: 'title', writeBack: true)],
      ),
    ],
    entityTypes: [],
  );
  repo.itemFieldsByPid['bk-1'] = {'title': 'The Long Walk'};
  repo.chaptersByPid['bk-1'] = const [
    ChapterMark(index: 0, title: 'One', startMs: 0, endMs: 61500),
    ChapterMark(index: 1, title: 'Two', startMs: 61500),
  ];
  repo.books['bk-1'] = BookDetail(
    pid: 'bk-1',
    title: 'The Long Walk',
    durationMs: 200000,
    chapters: repo.chaptersByPid['bk-1']!,
    parts: parts,
  );
  return repo;
}

/// The canonical 1x1 transparent PNG, so the preview's cover thumbnail
/// decodes rather than exercising the error builder.
final _onePixelPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
]);
