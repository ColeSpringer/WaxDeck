import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/music/album_editor_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

const _album = 'al-01JZX5N8QW3F4V9T2B7KDALBUM';

Finder _byId(String id) => find.bySemanticsIdentifier(id);

FakeRepository _repo({
  AlbumDetail? album,
  List<EntityCuratedField> curation = const <EntityCuratedField>[],
}) {
  // Signed in as an administrator: the entity-edit endpoint is
  // administrators-only and the screen says so, so every test about the
  // form itself needs the role that can reach it.
  final repo = FakeRepository(
    sessionState: const SessionState(
      authenticated: true,
      user: WaxDeckUser(
        id: 'us-1',
        username: 'admin',
        roles: <String>['admin'],
      ),
    ),
  );
  repo.albums[_album] =
      album ??
      const AlbumDetail(
        pid: _album,
        title: 'Long Exposure',
        barcode: '036000291452',
        label: 'Meridian Sound',
        country: 'US & Europe',
      );
  repo.entityCurationByKey['album/$_album'] = curation;
  return repo;
}

Future<void> _pump(WidgetTester tester, FakeRepository repo) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        audioEngineProvider.overrideWithValue(FakeEngine()),
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      ],
      child: routedHost(const AlbumEditorScreen(pid: _album)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the stored identity is what the fields open on', (tester) async {
    final repo = _repo();
    await _pump(tester, repo);

    expect(_byId(SemanticsIds.albumEditor), findsOneWidget);
    expect(find.text('036000291452'), findsOneWidget);
    expect(find.text('Meridian Sound'), findsOneWidget);
    // Shown as stored, never client-validated: a scan keeps the tag
    // verbatim and an edit normalizes, so the two disagree by policy and
    // this is a value the write path would refuse.
    expect(find.text('US & Europe'), findsOneWidget);
  });

  testWidgets('only the fields that changed are sent, and they lock', (
    tester,
  ) async {
    final repo = _repo();
    await _pump(tester, repo);

    await tester.enterText(
      _byId(SemanticsIds.metadataField('catalog_number')),
      'MER-114',
    );
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.metadataSave));
    await tester.pumpAndSettle();

    final edit = repo.entityEdits.single;
    expect(edit.entityType, 'album');
    expect(edit.entityPid, _album);
    // Sparse, because the endpoint locks what it is sent: the untouched
    // four must not be locked by a one-word change.
    expect(edit.edits, <String, String>{'catalog_number': 'MER-114'});
    expect(edit.lock, isTrue);
    expect(edit.force, isFalse);
    expect(edit.writeBack, isFalse);
  });

  testWidgets('nothing typed leaves Save with nothing to do', (tester) async {
    final repo = _repo();
    await _pump(tester, repo);

    final save = tester.widget<WaxButton>(
      find.ancestor(
        of: _byId(SemanticsIds.metadataSave),
        matching: find.byType(WaxButton),
      ),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('the write-back and force switches reach the call', (
    tester,
  ) async {
    final repo = _repo();
    await _pump(tester, repo);

    await tester.enterText(_byId(SemanticsIds.metadataField('label')), 'Nine');
    await tester.tap(_byId(SemanticsIds.metadataWriteback));
    await tester.tap(_byId(SemanticsIds.metadataForce));
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.metadataSave));
    await tester.pumpAndSettle();

    final edit = repo.entityEdits.single;
    expect(edit.writeBack, isTrue);
    expect(edit.force, isTrue);
  });

  // The refetch a save triggers can bring back a value somebody else
  // changed, and adopting it writes a controller - which notifies, which
  // rebuilds. Done while building, that is `setState` called during
  // build; the fields have to take the new value from outside the build
  // phase, the way the item editor's do.
  testWidgets('a field nobody typed in takes a value changed elsewhere', (
    tester,
  ) async {
    final repo = _repo();
    await _pump(tester, repo);

    // Another administrator edits the barcode while this screen is open.
    repo.albums[_album] = const AlbumDetail(
      pid: _album,
      title: 'Long Exposure',
      barcode: '999999999999',
      label: 'Meridian Sound',
      country: 'US & Europe',
    );

    // Saving an unrelated field is what refetches, so this is the screen's
    // own path rather than a poke at the provider.
    await tester.enterText(_byId(SemanticsIds.metadataField('label')), 'Nine');
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.metadataSave));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('999999999999'), findsOneWidget);
    // And the field the listener was typing in keeps what they typed.
    expect(find.text('Nine'), findsOneWidget);
  });

  testWidgets('a typed field outranks a value that changed under it', (
    tester,
  ) async {
    final repo = _repo();
    await _pump(tester, repo);

    await tester.enterText(
      _byId(SemanticsIds.metadataField('barcode')),
      'typed-by-hand',
    );
    await tester.pumpAndSettle();
    repo.albums[_album] = const AlbumDetail(
      pid: _album,
      title: 'Long Exposure',
      barcode: '999999999999',
      label: 'Meridian Sound',
    );
    await tester.enterText(_byId(SemanticsIds.metadataField('label')), 'Nine');
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.metadataSave));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('typed-by-hand'), findsOneWidget);
    expect(find.text('999999999999'), findsNothing);
  });

  // The server normalizes barcode and country on the way in, so what
  // comes back is not what was typed. Without re-seeding what was sent,
  // the field reads as an edit in flight for ever: Save stays lit and
  // re-sends the same un-normalized string on every press.
  testWidgets('a normalized value comes back and the field settles', (
    tester,
  ) async {
    final repo = _repo();
    // Standing in for the server's own normalizer, which strips the
    // separators a listener types.
    repo.normalizeEntityEdit = (field, value) =>
        field == 'barcode' ? value.replaceAll('-', '') : value;
    await _pump(tester, repo);

    await tester.enterText(
      _byId(SemanticsIds.metadataField('barcode')),
      '0-36000-29145-3',
    );
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.metadataSave));
    await tester.pumpAndSettle();

    expect(find.text('036000291453'), findsOneWidget);
    final save = tester.widget<WaxButton>(
      find.ancestor(
        of: _byId(SemanticsIds.metadataSave),
        matching: find.byType(WaxButton),
      ),
    );
    expect(
      save.onPressed,
      isNull,
      reason: 'the field took the stored value, so nothing is left to save',
    );
  });

  testWidgets('the album says what it is before it offers to change it', (
    tester,
  ) async {
    // The complaint the rebuild answers: five text fields and a Save,
    // with no cover, no title, and no sign of what an edit reaches.
    final repo = _repo(
      album: const AlbumDetail(
        pid: _album,
        title: 'Long Exposure',
        year: 1975,
        itemCount: 2,
        totalDurationMs: 2460000,
      ),
    );
    repo.facetItems['album ${_album.substring(3)}'] = <ItemSummary>[
      testItem('tr-A', title: 'Salt Harbour'),
      testItem('tr-B', title: 'Nightjar'),
    ];
    await _pump(tester, repo);

    expect(find.text('Long Exposure'), findsWidgets);
    expect(find.textContaining('1975'), findsOneWidget);
    expect(_byId(SemanticsIds.albumEditorTracks), findsOneWidget);
    expect(find.text('Salt Harbour'), findsOneWidget);
    expect(find.text('Nightjar'), findsOneWidget);
    // The cover grid, in entity mode: the front slot is what an album
    // holds, and the pin is what explains one refusing every cover.
    expect(_byId(SemanticsIds.artSlot('front')), findsOneWidget);
    expect(_byId(SemanticsIds.artLock), findsOneWidget);
  });

  testWidgets('total tracks is a derived number, not a field', (tester) async {
    // The album bug asked to edit it; nothing stores it. The row says
    // the count and why there is no input, so the answer is on the
    // screen rather than silently missing from the form.
    final repo = _repo(
      album: const AlbumDetail(
        pid: _album,
        title: 'Long Exposure',
        itemCount: 9,
      ),
    );
    await _pump(tester, repo);

    final row = _byId(SemanticsIds.albumEditorTotalTracks);
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('9')), findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('Derived')),
      findsOneWidget,
    );
    // Read-only: no text box to type a different count into.
    expect(
      find.descendant(of: row, matching: find.byType(TextField)),
      findsNothing,
    );
  });

  testWidgets('the sort name and MusicBrainz id are editable', (tester) async {
    // Two fields the endpoint has always taken and the screen never
    // offered, so the only way to set them was another client.
    final repo = _repo(
      album: const AlbumDetail(
        pid: _album,
        title: 'Long Exposure',
        sortKey: 'Long Exposure',
      ),
    );
    await _pump(tester, repo);

    expect(_byId(SemanticsIds.albumEditorNames), findsOneWidget);
    expect(_byId(SemanticsIds.metadataField('sort')), findsOneWidget);
    expect(_byId(SemanticsIds.metadataField('mbid')), findsOneWidget);

    await tester.enterText(
      _byId(SemanticsIds.metadataField('mbid')),
      '1f3a9d2e-0000-4000-8000-abcdefabcdef',
    );
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.metadataSave));
    await tester.pumpAndSettle();

    expect(repo.entityEdits, hasLength(1));
    expect(repo.entityEdits.single.edits, <String, String>{
      'mbid': '1f3a9d2e-0000-4000-8000-abcdefabcdef',
    });
  });

  testWidgets('the cover pin is written through the entity endpoint', (
    tester,
  ) async {
    // The one way out of a cover cleared and left pinned: setting
    // artwork cannot say "stop refusing", and clearing it again does
    // nothing at all.
    final repo = _repo();
    await _pump(tester, repo);

    await tester.tap(_byId(SemanticsIds.artLock));
    await tester.pumpAndSettle();

    expect(repo.entityArtworkLocks['album/$_album'], isTrue);
  });

  testWidgets('a member gets the refusal rather than an editable form', (
    tester,
  ) async {
    final repo = _repo()
      ..sessionState = const SessionState(
        authenticated: true,
        user: WaxDeckUser(
          id: 'us-2',
          username: 'listener',
          roles: <String>['member'],
        ),
      );
    await _pump(tester, repo);

    expect(_byId(SemanticsIds.albumEditor), findsNothing);
    expect(find.text('Only administrators can edit a release'), findsOneWidget);
  });

  testWidgets('an album that will not load says so and offers a retry', (
    tester,
  ) async {
    final repo = _repo()..albums.clear();
    await _pump(tester, repo);

    expect(find.text('Could not load this album'), findsOneWidget);
    expect(_byId(SemanticsIds.albumEditor), findsNothing);
  });
}
