import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/artwork/artwork_store.dart';
import 'package:waxdeck/src/l10n/explain_error.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_es.dart';
import 'package:waxdeck/src/metadata/entity_editor_screen.dart';
import 'package:waxdeck/src/music/artist_screen.dart';
import 'package:waxdeck/src/music/index_screen.dart';
import 'package:waxdeck/src/music/listing_screen.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/shell/navigation_history.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck/src/sync/catalog_reads.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';
import 'wax_finders.dart';

// The artist and release-group editors: curation-seeded fields, sparse
// saves through the entity endpoint, the write-back switch only where a
// value has files to reach, and the administrators-only refusal.

const _artist = 'ar-01HZX5N8QW3F4V9T2B7KD3M9R6';
const _group = 'rg-01HZX5N8QW3F4V9T2B7KD3M9R6';

SessionState _session({bool admin = true}) => SessionState(
  authenticated: true,
  user: WaxDeckUser(
    id: 'us-1',
    username: admin ? 'admin' : 'listener',
    roles: <String>[admin ? 'admin' : 'member'],
  ),
);

/// A library with nothing to say of any entity: no member lists under
/// one, and no card answers for one.
FakeRepository _bare({bool admin = true}) => FakeRepository(
  sessionState: _session(admin: admin),
  items: [testItem('tr-1')],
);

/// [_bare], with the entities these tests edit in it: each answers its
/// card, as one that is there does.
FakeRepository _repo({bool admin = true}) => _bare(admin: admin)
  ..entityCards[_artist] = _artistCard(_artist, _oldName)
  ..entityCards[_survivor] = _artistCard(_survivor, _newName)
  ..entityCards[_group] = const EntityCard(
    pid: _group,
    kind: EntityCardKind.releaseGroup,
    title: 'Long Exposure',
  );

/// A library whose card read fails.
class _CardReadFails extends FakeRepository {
  _CardReadFails() : super(sessionState: _session());

  @override
  Future<EntityResolution> resolveEntities(List<String> pids) async {
    throw const WaxDeckApiException(
      code: 'internal',
      message: 'boom',
      statusCode: 500,
    );
  }
}

/// A library whose card read does not answer until [answer] completes.
class _CardReadWaits extends FakeRepository {
  _CardReadWaits() : super(sessionState: _session());

  final answer = Completer<void>();

  @override
  Future<EntityResolution> resolveEntities(List<String> pids) async {
    await answer.future;
    return super.resolveEntities(pids);
  }
}

const _notHere = 'That is not here any more.';

Future<void> _pump(
  WidgetTester tester,
  FakeRepository repo, {
  required EditableEntity entity,
  required String pid,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpApp(
    tester,
    EntityEditorScreen(entity: entity, pid: pid),
    container: appContainer(repo: repo),
  );
}

/// Hands back one small image whatever is asked for.
class _OneImage implements FilePickerPort {
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
  }) async => PickedAudioFile(
    name: 'cover.png',
    size: 64,
    openRead: ([int? start, int? end]) =>
        Stream<List<int>>.value(Uint8List(64)),
  );
}

Finder _field(String name) =>
    find.bySemanticsIdentifier(SemanticsIds.metadataField(name));

const _survivor = 'ar-01HZX5N8QW3F4V9T2B7KD3M9SUR';

/// An artist whose MusicBrainz id, cleared, re-keys it onto [_survivor].
FakeRepository _merging() {
  final repo = _repo()..entityEditMergesInto = _survivor;
  repo.entityCurationByKey['artist/$_artist'] = const [
    EntityCuratedField(
      field: 'mbid',
      value: 'b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d',
      source: 'user',
      locked: false,
    ),
  ];
  return repo;
}

const _oldName = 'The Bree Trio';
const _newName = 'The Bree Quartet';

EntityCard _artistCard(String pid, String title) =>
    EntityCard(pid: pid, kind: EntityCardKind.artist, title: title);

FacetBucket _artistBucket(String pid, String label) =>
    FacetBucket(key: pid.substring(3), label: label, count: 1, entityPid: pid);

/// A library whose artists index holds [_artist] under [_oldName].
FakeRepository _indexed() {
  final repo = _repo();
  repo.facets['artist'] = [_artistBucket(_artist, _oldName)];
  repo.facetItems['artist ${_artist.substring(3)}'] = [testItem('tr-1')];
  repo.entityCards[_artist] = _artistCard(_artist, _oldName);
  return repo;
}

/// The whole app on the artists index, the artist's page opened from its
/// row and the editor from that page's overflow.
Future<GoRouter> _openFromIndex(
  WidgetTester tester,
  FakeRepository repo, {
  ArtworkStore? artwork,
  FilePickerPort? picker,
}) async {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = appContainer(
    repo: repo,
    artwork: artwork,
    extra: [if (picker != null) filePickerProvider.overrideWithValue(picker)],
  );
  await pumpWholeApp(tester, container: container);
  final router = container.read(routerProvider)
    ..go(WaxRoute.musicIndex(MusicDimension.artists));
  await tester.pumpAndSettle();
  await tester.tap(find.text(_oldName));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.entityOverflow));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.entityEditMetadata));
  await tester.pumpAndSettle();
  return router;
}

/// Types [_newName] into the rename box, applies and confirms; the
/// catalog becomes [after] while the server holds the answer.
Future<void> _rename(
  WidgetTester tester,
  FakeRepository repo, {
  required void Function() after,
}) async {
  final gate = repo.renameEntityGate = Completer<void>();
  final field = find.bySemanticsIdentifier(
    SemanticsIds.entityRenameField('name'),
  );
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, _newName);
  await tester.pumpAndSettle();
  final apply = find.bySemanticsIdentifier(SemanticsIds.entityRenameApply);
  await tester.ensureVisible(apply);
  await tester.pumpAndSettle();
  await tester.tap(apply);
  await tester.pumpAndSettle();
  await tester.tap(
    find.bySemanticsIdentifier(SemanticsIds.entityRenameConfirm),
  );
  await tester.pumpAndSettle();
  after();
  gate.complete();
  await tester.pumpAndSettle();
}

/// The arrow of the page on top.
Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.navBack).last);
  await tester.pumpAndSettle();
}

/// The credit of each row the artist page of [pid] holds.
List<String?> _credits(WidgetTester tester, String pid) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ArtistScreen)),
    listen: false,
  );
  final listing = (
    dimension: MusicDimension.artists,
    segment: pid,
    domain: BrowseDomain.wholeLibrary,
  );
  return [
    for (final item in container.read(musicItemsProvider(listing)).value!.items)
      item.artist,
  ];
}

/// The whole app at a desktop window, the artist's editor pushed over
/// Music as the artist's overflow opens it.
Future<(GoRouter, ProviderContainer)> _openInApp(
  WidgetTester tester,
  FakeRepository repo, {
  String from = WaxRoute.music,
}) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = appContainer(repo: repo);
  await pumpWholeApp(tester, container: container);
  final router = container.read(routerProvider)..go(from);
  await tester.pumpAndSettle();
  unawaited(router.push<void>(WaxRoute.metadata(_artist)));
  await tester.pumpAndSettle();
  return (router, container);
}

/// The page on top of [router]'s screen: a push keeps the location it
/// was made from.
String _top(GoRouter router) => pageOnTop(router)!.location;

/// Every message raised to the shell from here on, in order.
List<ShellMessage> _raised(WidgetTester tester) {
  final raised = <ShellMessage>[];
  final heard =
      ProviderScope.containerOf(
        tester.element(find.byType(Navigator).first),
        listen: false,
      ).listen(shellMessagesProvider, (_, next) {
        if (next != null) raised.add(next);
      });
  addTearDown(heard.close);
  return raised;
}

/// Clears the MusicBrainz id and saves.
Future<void> _clearMbid(WidgetTester tester) async {
  await tester.enterText(_field('mbid'), '');
  await tester.pump();
  await _save(tester);
}

Future<void> _save(WidgetTester tester) async {
  final save = find.bySemanticsIdentifier(SemanticsIds.metadataSave);
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  await tester.tap(save);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the artist editor seeds from curation and saves sparsely', (
    tester,
  ) async {
    final repo = _repo();
    repo.entityCurationByKey['artist/$_artist'] = const [
      EntityCuratedField(
        field: 'sort',
        value: 'Bree Trio, The',
        source: 'user',
        locked: true,
      ),
    ];
    await _pump(tester, repo, entity: EditableEntity.artist, pid: _artist);
    final raised = _raised(tester);

    // The curated override is what the input holds; the uncurated
    // field is honestly empty.
    expect(find.text('Bree Trio, The'), findsOneWidget);
    await tester.enterText(
      _field('mbid'),
      'b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d',
    );
    await tester.pump();
    await _save(tester);
    expect(raised.map(shellMessageText), ['Saved']);

    // Only the field that changed rides the write.
    final edit = repo.entityEdits.single;
    expect(edit.entityType, 'artist');
    expect(edit.entityPid, _artist);
    expect(edit.edits, {'mbid': 'b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d'});
    expect(edit.writeBack, isFalse);
  });

  testWidgets('a catalog refresh keeps what is being typed and takes what '
      'changed elsewhere', (tester) async {
    const elsewhere = 'c4d1a6e0-2f0b-4a53-9d8c-5d1f3e8a7b21';
    final repo = _repo();
    repo.entityCurationByKey['artist/$_artist'] = const [
      EntityCuratedField(
        field: 'sort',
        value: 'Bree Trio, The',
        source: 'user',
        locked: true,
      ),
    ];
    await _pump(tester, repo, entity: EditableEntity.artist, pid: _artist);
    await tester.enterText(_field('sort'), 'Half-typed');
    await tester.pump();

    // Another administrator changes both fields, and the catalog says so.
    repo.entityCurationByKey['artist/$_artist'] = const [
      EntityCuratedField(
        field: 'sort',
        value: 'Changed Elsewhere',
        source: 'user',
        locked: true,
      ),
      EntityCuratedField(
        field: 'mbid',
        value: elsewhere,
        source: 'user',
        locked: true,
      ),
    ];
    ProviderScope.containerOf(
      tester.element(find.byType(EntityEditorScreen)),
      listen: false,
    ).read(catalogFanOutProvider).sweep(CatalogRefresh.head);
    await tester.pumpAndSettle();

    expect(find.text('Half-typed'), findsOneWidget);
    expect(find.text('Changed Elsewhere'), findsNothing);
    expect(find.text(elsewhere), findsOneWidget);
  });

  testWidgets('an uncurated field has no source chip; a curated one names it', (
    tester,
  ) async {
    final repo = _repo();
    repo.entityCurationByKey['artist/$_artist'] = const [
      EntityCuratedField(
        field: 'sort',
        value: 'Bree Trio, The',
        source: 'user',
        locked: false,
      ),
    ];
    await _pump(tester, repo, entity: EditableEntity.artist, pid: _artist);

    expect(find.text('Source unknown'), findsNothing);
    expect(find.text('you'), findsOneWidget);
    // The curated row's chip is the only one: an uncurated field is empty.
    expect(find.byType(CodecChip), findsOneWidget);
    expect(find.text('tags'), findsNothing);
  });

  testWidgets('a field draws no help under it', (tester) async {
    final repo = _repo();
    repo.entityCurationByKey['artist/$_artist'] = const [
      EntityCuratedField(
        field: 'sort',
        value: 'Bree Trio, The',
        source: 'user',
        locked: false,
      ),
    ];
    await _pump(tester, repo, entity: EditableEntity.artist, pid: _artist);

    expect(find.textContaining('A-to-Z'), findsNothing);
    expect(find.textContaining('identifier this artist'), findsNothing);
    // Nor does the rename section's heading carry a kicker.
    expect(find.text('Name'), findsWidgets);
    expect(find.text('ON THE MEMBERS'), findsNothing);
  });

  testWidgets('the rename section says how far its write-back reaches', (
    tester,
  ) async {
    await _pump(tester, _repo(), entity: EditableEntity.artist, pid: _artist);

    // Two switches titled alike on one screen, each with its own scope.
    expect(find.text('Write tags to files'), findsNWidgets(2));
    expect(
      infoTipHolding('Also rewrites these tags inside each member\'s file'),
      findsOneWidget,
    );
  });

  testWidgets('an artist sort can fan out to the crediting files', (
    tester,
  ) async {
    final repo = _repo();
    await _pump(tester, repo, entity: EditableEntity.artist, pid: _artist);

    // The label says "files"; the tip says whose.
    expect(
      infoTipHolding(
        'Also rewrites the matching sort tag in every file crediting this '
        'artist',
      ),
      findsOneWidget,
    );

    final writeBack = find.bySemanticsIdentifier(
      SemanticsIds.metadataWriteback,
    );
    await tester.ensureVisible(writeBack);
    await tester.pumpAndSettle();
    await tester.tap(writeBack);
    await tester.pump();
    await tester.enterText(_field('sort'), 'Bree Trio, The');
    await tester.pump();
    await _save(tester);

    expect(repo.entityEdits.single.writeBack, isTrue);
  });

  testWidgets('the artist editor manages the entity artwork', (tester) async {
    final repo = _repo();
    await _pump(tester, repo, entity: EditableEntity.artist, pid: _artist);

    // The slot grid and the entity pin, exactly as the album pane
    // mounts them.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.artSlot('front')),
      findsOneWidget,
    );
    expect(find.bySemanticsIdentifier(SemanticsIds.artLock), findsOneWidget);
  });

  testWidgets('the release-group editor writes its closed type choice', (
    tester,
  ) async {
    final repo = _repo();
    await _pump(tester, repo, entity: EditableEntity.releaseGroup, pid: _group);

    // No artwork manager: a release group draws its releases' art.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.artSlot('front')),
      findsNothing,
    );
    // No write-back switch: every release-group field is database-only.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.metadataWriteback),
      findsNothing,
    );

    final choice = _field('type');
    await tester.ensureVisible(choice);
    await tester.pumpAndSettle();
    await tester.tap(choice);
    await tester.pumpAndSettle();
    await tester.tap(find.text('EP').last);
    await tester.pumpAndSettle();
    await _save(tester);

    final edit = repo.entityEdits.single;
    expect(edit.entityType, 'release-group');
    expect(edit.edits, {'type': 'ep'});
  });

  testWidgets('clearing an mbid that merges takes the screen to the '
      'survivor', (tester) async {
    final repo = _merging();
    await _pump(tester, repo, entity: EditableEntity.artist, pid: _artist);
    final raised = _raised(tester);
    await _clearMbid(tester);

    // The edited row is gone, so the editor moved onto the one that
    // absorbed it rather than sitting on a dead pid.
    expect(repo.entityEdits.single.edits, {'mbid': ''});
    expect(find.text(_survivor), findsNothing);
    expect(
      tester.widget<EntityEditorScreen>(find.byType(EntityEditorScreen)).pid,
      _survivor,
    );
    expect(raised.map(shellMessageText), ['Saved']);
    expect(raised.single.onAction, isNull);
    expect(
      raised.single.resolve(AppLocalizationsEs()),
      AppLocalizationsEs().musicAlbumEditorSaved,
      reason: 'worded in the locale that draws it',
    );
  });

  testWidgets('clearing an mbid that merges once a page was opened over the '
      'editor leaves that page up, offers the survivor in one message, and '
      "back returns to the survivor's editor, not the one merged away", (
    tester,
  ) async {
    final repo = _merging();
    final (router, _) = await _openInApp(tester, repo);
    repo.editEntityGate = Completer<void>();
    await _clearMbid(tester);
    final raised = _raised(tester);

    unawaited(router.push<void>(WaxRoute.settings));
    await tester.pumpAndSettle();
    repo.editEntityGate!.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(_top(router), WaxRoute.settings, reason: 'where the visitor went');
    final offer = raised.single;
    expect(shellMessageText(offer), AppLocalizationsEn().metadataMergedReady);
    expect(offer.actionLabelIn(AppLocalizationsEn()), 'Open');
    final es = AppLocalizationsEs();
    expect(
      offer.resolve(es),
      es.metadataMergedReady,
      reason: 'worded at the draw',
    );
    expect(offer.actionLabelIn(es), es.commonOpen);
    await tester.pumpAndSettle();
    expect(find.text(AppLocalizationsEn().metadataMergedReady), findsOneWidget);

    // The editor under that page is the survivor's now.
    tester.element(find.byType(WaxScaffold).last).back();
    await tester.pumpAndSettle();
    expect(_top(router), WaxRoute.metadata(_survivor));
    EntityEditorScreen editor() => tester.widget<EntityEditorScreen>(
      find.byType(EntityEditorScreen, skipOffstage: false),
    );
    expect(editor().pid, _survivor);

    // Offered where the visitor was; here it is up already.
    offer.onAction!();
    await tester.pumpAndSettle();
    expect(_top(router), WaxRoute.metadata(_survivor));
    expect(editor().pid, _survivor, reason: 'no second copy over itself');

    tester.element(find.byType(EntityEditorScreen)).back();
    await tester.pumpAndSettle();
    expect(_top(router), WaxRoute.music);
    expect(find.byType(EntityEditorScreen, skipOffstage: false), findsNothing);
  });

  testWidgets('clearing an mbid that merges once back left the editor offers '
      'the survivor in one message, and the editor is not shown again', (
    tester,
  ) async {
    final repo = _merging();
    final (router, container) = await _openInApp(tester, repo);
    repo.editEntityGate = Completer<void>();
    await _clearMbid(tester);
    final raised = _raised(tester);

    tester.element(find.byType(EntityEditorScreen)).back();
    await tester.pumpAndSettle();
    expect(_top(router), WaxRoute.music);
    repo.editEntityGate!.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(repo.entityEdits.single.edits, {'mbid': ''});
    expect(raised, hasLength(1));
    final offer = raised.single;
    expect(shellMessageText(offer), AppLocalizationsEn().metadataMergedReady);
    expect(offer.actionLabelIn(AppLocalizationsEn()), 'Open');
    await tester.pumpAndSettle();
    expect(_top(router), WaxRoute.music, reason: 'where the visitor went');
    expect(find.text(AppLocalizationsEn().metadataMergedReady), findsOneWidget);
    expect(find.byType(EntityEditorScreen, skipOffstage: false), findsNothing);
    expect(
      container.read(waxHistoryProvider)!.isBehind(WaxRoute.metadata(_artist)),
      isFalse,
    );

    offer.onAction!();
    await tester.pumpAndSettle();
    expect(_top(router), WaxRoute.metadata(_survivor));
    expect(
      tester.widget<EntityEditorScreen>(find.byType(EntityEditorScreen)).pid,
      _survivor,
    );
  });

  testWidgets('a rename that merges once back left the editor offers the '
      'survivor in one message', (tester) async {
    final repo = _repo()
      ..renameEntityResult = const EntityRenameResult(
        entityPid: _artist,
        outcome: EntityRenameOutcome.merged,
        members: 1,
        credits: 1,
        mergedInto: _survivor,
      );
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(
      tester,
      const EntityEditorScreen(entity: EditableEntity.artist, pid: _artist),
      container: appContainer(repo: repo),
      pushed: true,
    );
    final router = GoRouter.of(tester.element(find.byType(EntityEditorScreen)));
    final gate = repo.renameEntityGate = Completer<void>();
    final field = find.bySemanticsIdentifier(
      SemanticsIds.entityRenameField('name'),
    );
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'The Bree Quartet');
    await tester.pumpAndSettle();
    final apply = find.bySemanticsIdentifier(SemanticsIds.entityRenameApply);
    await tester.ensureVisible(apply);
    await tester.pumpAndSettle();
    await tester.tap(apply);
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.entityRenameConfirm),
    );
    await tester.pumpAndSettle();
    final raised = _raised(tester);

    router.pop();
    await tester.pumpAndSettle();
    final left = _top(router);
    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_top(router), left, reason: 'where the visitor went');
    expect(find.byType(EntityEditorScreen, skipOffstage: false), findsNothing);
    final offer = raised.single;
    expect(shellMessageText(offer), AppLocalizationsEn().metadataMergedReady);
    expect(offer.actionLabelIn(AppLocalizationsEn()), 'Open');

    offer.onAction!();
    await tester.pumpAndSettle();
    expect(_top(router), WaxRoute.metadata(_survivor));
  });

  /// The artist's editor pushed over a blank page, its sort typed in and
  /// saved, the server holding the answer; the arrow then leaves it.
  Future<List<ShellMessage>> saveThenLeave(
    WidgetTester tester,
    FakeRepository repo,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(
      tester,
      const EntityEditorScreen(entity: EditableEntity.artist, pid: _artist),
      container: appContainer(repo: repo),
      pushed: true,
    );
    repo.editEntityGate = Completer<void>();
    await tester.enterText(_field('sort'), 'Bree Trio, The');
    await tester.pump();
    await _save(tester);
    final raised = _raised(tester);
    tester.element(find.byType(EntityEditorScreen)).back();
    await tester.pumpAndSettle();
    expect(find.byType(EntityEditorScreen), findsNothing);
    return raised;
  }

  testWidgets('a save that lands once back left the editor says so where '
      'the visitor is', (tester) async {
    final repo = _repo();
    final raised = await saveThenLeave(tester, repo);

    repo.editEntityGate!.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repo.entityEdits.single.edits, {'sort': 'Bree Trio, The'});
    expect(raised.map(shellMessageText), ['Saved']);
  });

  testWidgets('a save refused once back left the editor says so where the '
      'visitor is', (tester) async {
    final repo = _repo();
    final raised = await saveThenLeave(tester, repo);

    const refusal = WaxDeckApiException(
      code: 'bad-request',
      message: 'sort is too long',
      statusCode: 400,
    );
    repo.metadataError = refusal;
    repo.editEntityGate!.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(raised.map(shellMessageText), [
      explainRefusal(AppLocalizationsEn(), refusal),
    ]);
  });

  testWidgets('the artist rename moves every crediting track', (tester) async {
    final repo = _repo();
    repo.facetItems['artist ${_artist.substring(3)}'] = <ItemSummary>[
      testItem('tr-1'),
    ];
    await _pump(tester, repo, entity: EditableEntity.artist, pid: _artist);

    // The box starts empty rather than seeded from the member's display
    // credit: that string is the whole ARTIST tag, which on a
    // collaboration names people this entity is not, and the rename
    // applies with force. The new name is stated in full.
    final field = find.bySemanticsIdentifier(
      SemanticsIds.entityRenameField('name'),
    );
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .controller
          .text,
      isEmpty,
      reason: 'a joined credit must not become the rename baseline',
    );
    await tester.enterText(field, 'The Bree Quartet');
    await tester.pumpAndSettle();

    final apply = find.bySemanticsIdentifier(SemanticsIds.entityRenameApply);
    await tester.ensureVisible(apply);
    await tester.pumpAndSettle();
    await tester.tap(apply);
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.entityRenameConfirm),
    );
    await tester.pumpAndSettle();

    // Force, because the rename locks what it writes: a second one
    // would otherwise refuse on the first one's locks.
    final call = repo.renameEntityCalls.single;
    expect(call.entityType, 'artist');
    expect(call.entityPid, _artist);
    expect(call.fields, {'name': 'The Bree Quartet'});
    expect(call.force, isTrue);
    // The entity edit endpoint is untouched: the two forms write
    // through different verbs.
    expect(repo.entityEdits, isEmpty);
  });

  testWidgets('an artist renamed from their page is under the new name on '
      'the page, on its rows and in the index behind it', (tester) async {
    final repo = _indexed();
    final router = await _openFromIndex(tester, repo);
    expect(_top(router), WaxRoute.metadata(_artist));

    await _rename(
      tester,
      repo,
      after: () {
        repo.facets['artist'] = [_artistBucket(_artist, _newName)];
        repo.facetItems['artist ${_artist.substring(3)}'] = [
          testItem('tr-1', artist: _newName),
        ];
        repo.entityCards[_artist] = _artistCard(_artist, _newName);
      },
    );
    expect(tester.takeException(), isNull);
    expect(_top(router), WaxRoute.metadata(_artist));

    await _back(tester);
    expect(_top(router), WaxRoute.musicBucket(MusicDimension.artists, _artist));
    final page = find.byType(ArtistScreen);
    expect(
      find.descendant(of: page, matching: find.text(_newName)),
      findsWidgets,
    );
    expect(find.text(_oldName), findsNothing);
    expect(_credits(tester, _artist), [_newName]);

    await _back(tester);
    expect(_top(router), WaxRoute.musicIndex(MusicDimension.artists));
    expect(find.byType(MusicIndexScreen), findsOneWidget);
    expect(find.text(_newName), findsOneWidget);
    expect(find.text(_oldName), findsNothing);
  });

  testWidgets('an artist cover set in the editor is asked for under a new '
      'name by the index row behind it', (tester) async {
    final repo = _indexed();
    final store = NetworkArtworkStore(baseUrl: '');
    addTearDown(store.dispose);
    final art = repo.artUrlFor(_artist);

    /// What the index row asks the network for, covered or not.
    String rowAsks() {
      final image = tester.widget<Image>(
        find.descendant(
          of: find.byType(MusicIndexScreen, skipOffstage: false),
          matching: find.byType(Image, skipOffstage: false),
          skipOffstage: false,
        ),
      );
      return ((image.image as ResizeImage).imageProvider as NetworkImage).url;
    }

    final router = await _openFromIndex(
      tester,
      repo,
      artwork: store,
      picker: _OneImage(),
    );
    expect(rowAsks(), '$art?size=64');

    final set = find.bySemanticsIdentifier(SemanticsIds.artSlotSet('front'));
    await tester.ensureVisible(set);
    await tester.pumpAndSettle();
    await tester.tap(set);
    await tester.pumpAndSettle();
    expect(repo.entityArtworkCalls.single.entityPid, _artist);

    await _back(tester);
    await _back(tester);
    expect(_top(router), WaxRoute.musicIndex(MusicDimension.artists));
    // The bucket the index read again is equal to the one it held: the
    // row is rebuilt all the same, and asks under the tag.
    expect(
      rowAsks(),
      matches(
        RegExp(
          '^${RegExp.escape(art)}'
          r'\?size=64&v=\d+$',
        ),
      ),
    );
  });

  testWidgets('an artist a rename merged away leaves the visitor on the '
      'survivor: its editor, then its page under its own name, then the '
      'index', (tester) async {
    final repo = _indexed()
      ..renameEntityResult = const EntityRenameResult(
        entityPid: _artist,
        outcome: EntityRenameOutcome.merged,
        members: 1,
        credits: 1,
        mergedInto: _survivor,
      );
    final router = await _openFromIndex(tester, repo);

    await _rename(
      tester,
      repo,
      after: () {
        repo.facets['artist'] = [_artistBucket(_survivor, _newName)];
        repo.facetItems
          ..remove('artist ${_artist.substring(3)}')
          ..['artist ${_survivor.substring(3)}'] = [
            testItem('tr-1', artist: _newName),
          ];
        repo.entityCards
          ..remove(_artist)
          ..[_survivor] = _artistCard(_survivor, _newName);
        repo.departedEntityPids.add(_artist);
      },
    );
    expect(tester.takeException(), isNull);
    expect(_top(router), WaxRoute.metadata(_survivor));
    expect(
      tester.widget<EntityEditorScreen>(find.byType(EntityEditorScreen)).pid,
      _survivor,
    );

    await _back(tester);
    expect(
      _top(router),
      WaxRoute.musicBucket(MusicDimension.artists, _survivor),
    );
    final page = find.byType(ArtistScreen);
    expect(tester.widget<ArtistScreen>(page).pid, _survivor);
    expect(
      find.descendant(of: page, matching: find.text(_newName)),
      findsWidgets,
    );
    expect(find.text(_oldName), findsNothing);
    expect(_credits(tester, _survivor), [_newName]);

    await _back(tester);
    expect(_top(router), WaxRoute.musicIndex(MusicDimension.artists));
    expect(find.byType(MusicIndexScreen), findsOneWidget);
    expect(find.text(_newName), findsOneWidget);
    expect(find.text(_oldName), findsNothing);
  });

  testWidgets('the release-group rename takes both keying fields', (
    tester,
  ) async {
    final repo = _repo();
    repo.facetItems['release-group ${_group.substring(3)}'] = <ItemSummary>[
      testItem('tr-1'),
    ];
    repo.itemFieldsByPid['tr-1'] = {
      'album': 'Long Exposure',
      'album_artist': 'The Bree Trio',
    };
    await _pump(tester, repo, entity: EditableEntity.releaseGroup, pid: _group);

    final album = find.bySemanticsIdentifier(
      SemanticsIds.entityRenameField('album'),
    );
    await tester.ensureVisible(album);
    await tester.pumpAndSettle();
    await tester.enterText(album, 'Short Exposure');
    await tester.pumpAndSettle();

    final apply = find.bySemanticsIdentifier(SemanticsIds.entityRenameApply);
    await tester.ensureVisible(apply);
    await tester.pumpAndSettle();
    await tester.tap(apply);
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.entityRenameConfirm),
    );
    await tester.pumpAndSettle();

    // Only what changed: album_artist was left alone, so it stays out
    // of the write.
    expect(repo.renameEntityCalls.single.fields, {'album': 'Short Exposure'});
  });

  testWidgets('waits for the session before it refuses anyone', (tester) async {
    final repo = _repo()..getSessionGate = Completer<void>();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await mountApp(
      tester,
      const EntityEditorScreen(entity: EditableEntity.artist, pid: _artist),
      container: appContainer(repo: repo),
    );
    await tester.pump();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.metadataForbidden),
      findsNothing,
    );
    expect(find.byType(SkeletonShapes), findsOneWidget);

    repo.getSessionGate!.complete();
    await tester.pumpAndSettle();
    expect(find.bySemanticsIdentifier(SemanticsIds.entityEditor), findsOne);
  });

  testWidgets('a member gets the refusal, not a form', (tester) async {
    final repo = _repo(admin: false);
    await _pump(tester, repo, entity: EditableEntity.artist, pid: _artist);

    expect(
      find.bySemanticsIdentifier(SemanticsIds.metadataForbidden),
      findsOneWidget,
    );
    expect(find.bySemanticsIdentifier(SemanticsIds.entityEditor), findsNothing);
    // Who may edit an artist, said as the title; not the track editor's
    // account of who may edit a track.
    expect(find.text('Only administrators can edit an artist'), findsOneWidget);
    expect(find.textContaining('Editing a track'), findsNothing);
  });

  group('an entity that is gone', () {
    // No member lists under it and its card answers nothing: deleted, or
    // merged away, elsewhere.
    for (final (entity, pid) in <(EditableEntity, String)>[
      (EditableEntity.artist, _artist),
      (EditableEntity.releaseGroup, _group),
    ]) {
      testWidgets('${entity.name}: with no member and a card that resolves '
          'nothing the editor says it is not here, and draws no form', (
        tester,
      ) async {
        final repo = _bare();
        await _pump(tester, repo, entity: entity, pid: pid);

        expect(repo.resolvedEntityPids, contains(equals(<String>[pid])));
        expect(find.text('Could not load the metadata'), findsOneWidget);
        expect(find.text(_notHere), findsOneWidget);
        expect(find.text('Try again'), findsNothing);
        expect(_field('sort'), findsNothing);
        expect(
          find.bySemanticsIdentifier(SemanticsIds.metadataSave),
          findsNothing,
        );
      });
    }

    testWidgets('with no member, the editor waits for the card: neither a '
        'form nor gone, then the form once the card answers', (tester) async {
      final repo = _CardReadWaits()
        ..entityCards[_artist] = _artistCard(_artist, _oldName);
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await mountApp(
        tester,
        const EntityEditorScreen(entity: EditableEntity.artist, pid: _artist),
        container: appContainer(repo: repo),
      );
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text(_notHere), findsNothing);
      expect(_field('sort'), findsNothing);
      expect(find.byType(SkeletonShapes), findsOneWidget);

      repo.answer.complete();
      await tester.pumpAndSettle();
      expect(find.text(_notHere), findsNothing);
      expect(_field('sort'), findsOneWidget);
    });

    testWidgets('with no member, a card read that fails leaves the form: a '
        'failed read says nothing of whether it is there', (tester) async {
      await _pump(
        tester,
        _CardReadFails(),
        entity: EditableEntity.artist,
        pid: _artist,
      );

      expect(tester.takeException(), isNull);
      expect(find.text(_notHere), findsNothing);
      expect(_field('sort'), findsOneWidget);
    });

    testWidgets('a member lists under it though no card answers: the form, '
        'under the name the member gives', (tester) async {
      final repo = _bare()
        ..facetItems['artist ${_artist.substring(3)}'] = [testItem('tr-1')];
      await _pump(tester, repo, entity: EditableEntity.artist, pid: _artist);

      expect(find.text(_notHere), findsNothing);
      expect(_field('sort'), findsOneWidget);
    });
  });

  for (final merged in [false, true]) {
    testWidgets('an artist ${merged ? 'a rename merged away' : 'renamed'} is '
        'read again by the index under its editor', (tester) async {
      final repo = _repo();
      if (merged) {
        repo.renameEntityResult = const EntityRenameResult(
          entityPid: _artist,
          outcome: EntityRenameOutcome.merged,
          members: 1,
          credits: 1,
          mergedInto: _survivor,
        );
      }
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = await pumpApp(
        tester,
        const EntityEditorScreen(entity: EditableEntity.artist, pid: _artist),
        container: appContainer(repo: repo),
        pushed: true,
      );
      // The artists index, as the page under the editor holds it.
      final index = container.listen(
        musicIndexProvider((
          dimension: MusicDimension.artists,
          sort: FacetSort.label,
          domain: BrowseDomain.music,
        )),
        (_, _) {},
      );
      addTearDown(index.close);
      await tester.pumpAndSettle();
      int indexReads() =>
          repo.facetReads.where((read) => read.dimension == 'artist').length;
      final before = indexReads();

      final field = find.bySemanticsIdentifier(
        SemanticsIds.entityRenameField('name'),
      );
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, 'The Bree Quartet');
      await tester.pumpAndSettle();
      final apply = find.bySemanticsIdentifier(SemanticsIds.entityRenameApply);
      await tester.ensureVisible(apply);
      await tester.pumpAndSettle();
      await tester.tap(apply);
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.entityRenameConfirm),
      );
      await tester.pumpAndSettle();

      expect(repo.renameEntityCalls, hasLength(1));
      expect(indexReads(), before + 1);
    });
  }

  // A save can dissolve a release group whether or not it merged the
  // artist: the group's page goes the way a merged record's does.
  for (final merged in [true, false]) {
    testWidgets('clearing an mbid that ${merged ? 'merges' : 'keeps'} the '
        'artist and folds a release group: back from the editor reaches the '
        'group it became', (tester) async {
      const goneGroup = 'rg-01HZX5N8QW3F4V9T2B7KDGONEG';
      const keptGroup = 'rg-01HZX5N8QW3F4V9T2B7KDKEPTG';
      final gonePage = WaxRoute.musicBucket(
        MusicDimension.releaseGroups,
        goneGroup,
      );
      final keptPage = WaxRoute.musicBucket(
        MusicDimension.releaseGroups,
        keptGroup,
      );
      final repo = _merging()
        ..entityEditResult = MetadataEditResult(
          applied: true,
          mergedInto: merged ? _survivor : null,
          folded: const [FoldedEntity(pid: goneGroup, into: keptGroup)],
        );
      for (final group in [goneGroup, keptGroup]) {
        repo.facetItems['release-group ${group.substring(3)}'] = [
          testItem('tr-1'),
        ];
      }
      final (router, _) = await _openInApp(tester, repo, from: gonePage);

      await _clearMbid(tester);

      expect(tester.takeException(), isNull);
      expect(_top(router), WaxRoute.metadata(merged ? _survivor : _artist));
      tester.element(find.byType(EntityEditorScreen)).back();
      await tester.pumpAndSettle();
      expect(_top(router), keptPage);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is MusicListingScreen && widget.segment == goneGroup,
          skipOffstage: false,
        ),
        findsNothing,
      );
    });
  }
}
