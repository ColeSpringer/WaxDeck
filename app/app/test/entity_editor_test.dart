import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/l10n/explain_error.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_es.dart';
import 'package:waxdeck/src/metadata/entity_editor_screen.dart';
import 'package:waxdeck/src/shell/navigation_history.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
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

FakeRepository _repo({bool admin = true}) => FakeRepository(
  sessionState: SessionState(
    authenticated: true,
    user: WaxDeckUser(
      id: 'us-1',
      username: admin ? 'admin' : 'listener',
      roles: <String>[admin ? 'admin' : 'member'],
    ),
  ),
  items: [testItem('tr-1')],
);

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

/// The whole app at a desktop window, the artist's editor pushed over
/// Music as the artist's overflow opens it.
Future<(GoRouter, ProviderContainer)> _openInApp(
  WidgetTester tester,
  FakeRepository repo,
) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = appContainer(repo: repo);
  await pumpWholeApp(tester, container: container);
  final router = container.read(routerProvider)..go(WaxRoute.music);
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
      'back does not return to the editor merged away', (tester) async {
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

    tester.element(find.byType(WaxScaffold).last).back();
    await tester.pumpAndSettle();
    expect(_top(router), WaxRoute.music);
    expect(find.byType(EntityEditorScreen, skipOffstage: false), findsNothing);

    offer.onAction!();
    await tester.pumpAndSettle();
    expect(_top(router), WaxRoute.metadata(_survivor));
    expect(
      tester.widget<EntityEditorScreen>(find.byType(EntityEditorScreen)).pid,
      _survivor,
    );
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
}
