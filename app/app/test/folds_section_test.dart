import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/books/series_screen.dart';
import 'package:waxdeck/src/health/folds_section.dart';
import 'package:waxdeck/src/health/health_controller.dart';
import 'package:waxdeck/src/health/health_screen.dart';
import 'package:waxdeck/src/l10n/formats.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/music/album_screen.dart';
import 'package:waxdeck/src/music/artist_screen.dart';
import 'package:waxdeck/src/music/listing_screen.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';
import 'wax_finders.dart';

const _admin = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  username: 'admin',
  roles: ['admin'],
);

/// An album's key, separators and all: the app never reads it.
const _albumKey = 'al:rg:joni\u001fblue\u001f\u001f\u001fmusic blue again';

EntityFold _fold(
  String type,
  String key,
  String pid,
  String name, {
  String? spelling,
  String? facet,
  String? folder,
  String? library,
  DateTime? createdAt,
}) => EntityFold(
  entityType: type,
  key: key,
  spelling: spelling ?? key,
  facet: facet,
  folder: folder,
  library: library,
  entityPid: pid,
  entityName: name,
  createdAt: createdAt ?? DateTime.utc(2026, 10, 1),
);

/// A page and one fold more, keyed so they sort in the order listed.
List<EntityFold> _pageAndOne() => [
  for (var i = 0; i <= FoldsController.pageSize; i++)
    _fold('artist', 'name ${i.toString().padLeft(3, '0')}', 'ar-1', 'X'),
];

FakeRepository _repo() =>
    FakeRepository(
        sessionState: const SessionState(authenticated: true, user: _admin),
      )
      ..healthSummary = const HealthSummary(
        score: 90,
        totalItems: 1,
        evaluatedItems: 1,
      );

ProviderContainer _container(FakeRepository repo) {
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeRepository repo,
) async {
  tester.view.physicalSize = const Size(1280, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = _container(repo);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: routedHost(const HealthScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('folded names are grouped by type with the entry each files '
      'under', (tester) async {
    final repo = _repo()
      ..entityFolds = [
        _fold('album', _albumKey, 'al-1', 'Blue', spelling: 'joni - blue'),
        _fold('artist', 'beatles', 'ar-1', 'The Beatles'),
        _fold(
          'genre',
          'genre:hip hop',
          '01JZX5N8QW3F4V9T2B7KDGENRE',
          'Hip-Hop',
          spelling: 'hip hop',
        ),
      ];
    await _pump(tester, repo);

    expect(find.text('Folded names'), findsOneWidget);
    for (final (type, heading) in [
      ('album', 'Albums'),
      ('artist', 'Artists'),
      ('genre', 'Genres'),
    ]) {
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier(SemanticsIds.foldGroup(type)),
          matching: find.text(heading),
        ),
        findsOneWidget,
        reason: 'the $type folds sit under their own heading',
      );
    }
    final album = find.bySemanticsIdentifier(
      SemanticsIds.foldRow('album', _albumKey),
    );
    expect(album, findsOneWidget);
    expect(
      find.descendant(of: album, matching: find.text('joni - blue')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: album, matching: find.text('Blue')),
      findsOneWidget,
    );
    expect(
      find.text(_albumKey),
      findsNothing,
      reason: 'the key is a handle, never shown',
    );
  });

  testWidgets('unfolding asks first, says what moves, and drops the row', (
    tester,
  ) async {
    final repo = _repo()
      ..entityFolds = [_fold('artist', 'beatles', 'ar-1', 'The Beatles')];
    final container = await _pump(tester, repo);
    final unfold = find.bySemanticsIdentifier(
      SemanticsIds.foldUnfold('artist', 'beatles'),
    );

    await _tap(tester, unfold);
    expect(find.text('Unfold this name?'), findsOneWidget);
    expect(
      find.textContaining('added, moved, replaced or retagged'),
      findsOneWidget,
    );
    expect(
      find.textContaining('even through a rescan with Re-read unchanged files'),
      findsOneWidget,
      reason: 'the dialog says a rescan leaves the filed ones where they are',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.unfoldCalls, isEmpty);

    await _tap(tester, unfold);
    final reads = repo.listEntityFoldsCalls;
    await _tap(
      tester,
      find.bySemanticsIdentifier(SemanticsIds.foldUnfoldConfirm),
    );
    expect(repo.unfoldCalls.single.entityType, 'artist');
    expect(repo.unfoldCalls.single.keys, ['beatles']);
    expect(repo.listEntityFoldsCalls, reads, reason: 'the row is dropped');
    expect(
      find.bySemanticsIdentifier(SemanticsIds.foldRow('artist', 'beatles')),
      findsNothing,
    );
    expect(find.text('No folded names'), findsOneWidget);
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      '"beatles" is unfolded',
    );
  });

  testWidgets('a pressed Load more stays, busy, over the ghost row', (
    tester,
  ) async {
    final repo = _repo()..entityFolds = _pageAndOne();
    await _pump(tester, repo);
    final more = waxControl<WaxButton>(SemanticsIds.foldsMore);
    await tester.ensureVisible(more);
    await tester.pumpAndSettle();

    repo.listEntityFoldsGate = Completer<void>();
    await expectLoadMoreHolds(tester, more);
    repo.listEntityFoldsGate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('an unfold past the first page keeps every row read', (
    tester,
  ) async {
    final repo = _repo()..entityFolds = _pageAndOne();
    await _pump(tester, repo);
    await _tap(tester, find.bySemanticsIdentifier(SemanticsIds.foldsMore));
    final last = 'name ${FoldsController.pageSize}';
    final reads = repo.listEntityFoldsCalls;

    await _tap(
      tester,
      find.bySemanticsIdentifier(SemanticsIds.foldUnfold('artist', last)),
    );
    await _tap(
      tester,
      find.bySemanticsIdentifier(SemanticsIds.foldUnfoldConfirm),
    );
    expect(repo.unfoldCalls.single.keys, [last]);
    expect(repo.listEntityFoldsCalls, reads, reason: 'nothing is read again');
    expect(
      find.bySemanticsIdentifier(SemanticsIds.foldRow('artist', last)),
      findsNothing,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.foldRow('artist', 'name 000')),
      findsOneWidget,
      reason: 'the first page stays',
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.foldsMore),
      findsNothing,
      reason: 'the second page was read already',
    );
  });

  testWidgets('a name another session unfolded first drops its row', (
    tester,
  ) async {
    final repo = _repo()
      ..entityFolds = [_fold('artist', 'beatles', 'ar-1', 'The Beatles')];
    final container = await _pump(tester, repo);
    await _tap(
      tester,
      find.bySemanticsIdentifier(SemanticsIds.foldUnfold('artist', 'beatles')),
    );
    repo.entityFolds = const [];
    await _tap(
      tester,
      find.bySemanticsIdentifier(SemanticsIds.foldUnfoldConfirm),
    );
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'That name was unfolded already',
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.foldRow('artist', 'beatles')),
      findsNothing,
    );
  });

  testWidgets('an unfold refused for another reason keeps the row', (
    tester,
  ) async {
    final repo = _repo()
      ..entityFolds = [_fold('artist', 'beatles', 'ar-1', 'The Beatles')];
    final container = await _pump(tester, repo);
    await _tap(
      tester,
      find.bySemanticsIdentifier(SemanticsIds.foldUnfold('artist', 'beatles')),
    );
    repo.unfoldError = const WaxDeckApiException(
      code: 'catalog-maintenance',
      message: 'down',
      statusCode: 503,
    );
    await _tap(
      tester,
      find.bySemanticsIdentifier(SemanticsIds.foldUnfoldConfirm),
    );
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      AppLocalizationsEn().errorCatalogMaintenance,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.foldRow('artist', 'beatles')),
      findsOneWidget,
    );
  });

  testWidgets('an unfold confirmed after the section went still lands', (
    tester,
  ) async {
    final repo = _repo()
      ..entityFolds = [_fold('artist', 'beatles', 'ar-1', 'The Beatles')];
    final container = await _pump(tester, repo);
    await _tap(
      tester,
      find.bySemanticsIdentifier(SemanticsIds.foldUnfold('artist', 'beatles')),
    );
    // The summary reloaded (as a change of server does) and held: the
    // screen draws its placeholder, so the section and its listing go
    // while the dialog stays up.
    final gate = Completer<void>();
    repo.healthGate = gate;
    container.invalidate(healthProvider, asReload: true);
    await tester.pump();
    await tester.pump();
    expect(find.byType(FoldsSection), findsNothing);
    expect(container.exists(foldsProvider), isFalse);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.foldUnfoldConfirm),
    );
    await tester.pump();
    await tester.pump();
    expect(repo.unfoldCalls.single.keys, ['beatles']);
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      '"beatles" is unfolded',
    );
    gate.complete();
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.foldRow('artist', 'beatles')),
      findsNothing,
      reason: 'the section comes back reading the server afresh',
    );
  });

  testWidgets('folds that spell alike show what tells them apart', (
    tester,
  ) async {
    final repo = _repo()
      ..entityFolds = [
        _fold(
          'album',
          'al:a',
          'al-1',
          'Blue',
          spelling: 'joni - blue',
          folder: 'Joni/Blue Again',
          library: 'Music',
        ),
        _fold(
          'album',
          'al:b',
          'al-1',
          'Blue',
          spelling: 'joni - blue',
          library: 'Music',
        ),
        _fold(
          'genre',
          'genre:chill',
          '01JZX5N8QW3F4V9T2B7KDGENRE',
          'Chill',
          spelling: 'chill',
          facet: 'genre',
        ),
        _fold(
          'genre',
          'mood:chill',
          '01JZX5N8QW3F4V9T2B7KDMOOD0',
          'Chill',
          spelling: 'chill',
          facet: 'mood',
        ),
      ];
    await _pump(tester, repo);
    Finder within(String type, String key, String text) => find.descendant(
      of: find.bySemanticsIdentifier(SemanticsIds.foldRow(type, key)),
      matching: find.text(text),
    );
    expect(
      within('album', 'al:a', 'In Joni/Blue Again in Music'),
      findsOneWidget,
    );
    expect(within('album', 'al:b', 'At the top of Music'), findsOneWidget);
    expect(within('genre', 'genre:chill', 'Genre'), findsOneWidget);
    expect(within('genre', 'mood:chill', 'Mood'), findsOneWidget);
  });

  testWidgets('two folds that spell alike unfold apart', (tester) async {
    final repo = _repo()
      ..entityFolds = [
        _fold(
          'album',
          'al:a',
          'al-1',
          'Blue',
          spelling: 'joni - blue',
          folder: 'Joni/Blue Again',
          library: 'Music',
        ),
        _fold(
          'album',
          'al:b',
          'al-1',
          'Blue',
          spelling: 'joni - blue',
          folder: 'Joni/Blue Three',
          library: 'Music',
        ),
      ];
    final container = await _pump(tester, repo);
    String unfoldLabel(String key) => tester
        .getSemantics(
          find.bySemanticsIdentifier(SemanticsIds.foldUnfold('album', key)),
        )
        .label;
    expect(
      unfoldLabel('al:a'),
      'Unfold "joni - blue" (In Joni/Blue Again in Music)',
    );
    expect(
      unfoldLabel('al:b'),
      'Unfold "joni - blue" (In Joni/Blue Three in Music)',
    );

    await _tap(
      tester,
      find.bySemanticsIdentifier(SemanticsIds.foldUnfold('album', 'al:b')),
    );
    expect(
      find.text('"joni - blue" (In Joni/Blue Three in Music)'),
      findsOneWidget,
      reason: 'the dialog names which of the two it unfolds',
    );
    await _tap(
      tester,
      find.bySemanticsIdentifier(SemanticsIds.foldUnfoldConfirm),
    );
    expect(repo.unfoldCalls.single.keys, ['al:b']);
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      '"joni - blue" (In Joni/Blue Three in Music) is unfolded',
    );
  });

  testWidgets('album folds no file places say when each was folded', (
    tester,
  ) async {
    final first = DateTime.utc(2026, 10, 1, 9, 30);
    final second = DateTime.utc(2026, 10, 2, 18, 5);
    final repo = _repo()
      ..entityFolds = [
        _fold(
          'album',
          'al:a',
          'al-1',
          'Blue',
          spelling: 'joni - blue',
          createdAt: first,
        ),
        _fold(
          'album',
          'al:b',
          'al-1',
          'Blue',
          spelling: 'joni - blue',
          createdAt: second,
        ),
      ];
    await _pump(tester, repo);
    final l10n = AppLocalizationsEn();
    final firstAt = 'Folded ${l10n.formatStamp(first)}';
    final secondAt = 'Folded ${l10n.formatStamp(second)}';
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.foldRow('album', 'al:a')),
        matching: find.text(firstAt),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.foldRow('album', 'al:b')),
        matching: find.text(secondAt),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .getSemantics(
            find.bySemanticsIdentifier(
              SemanticsIds.foldUnfold('album', 'al:b'),
            ),
          )
          .label,
      'Unfold "joni - blue" ($secondAt)',
    );
  });

  testWidgets('album folds folded together are numbered apart', (tester) async {
    final at = DateTime.utc(2026, 10, 1, 9, 30);
    final repo = _repo()
      ..entityFolds = [
        _fold(
          'album',
          'al:a',
          'al-1',
          'Blue',
          spelling: 'joni - blue',
          createdAt: at,
        ),
        _fold(
          'album',
          'al:b',
          'al-1',
          'Blue',
          spelling: 'joni - blue',
          createdAt: at,
        ),
        _fold(
          'album',
          'al:c',
          'al-2',
          'Hejira',
          spelling: 'joni - hejira',
          createdAt: at,
        ),
      ];
    final container = await _pump(tester, repo);
    final folded = 'Folded ${AppLocalizationsEn().formatStamp(at)}';
    String rowLabel(String key) => tester
        .getSemantics(
          find.bySemanticsIdentifier(SemanticsIds.foldRow('album', key)),
        )
        .label;
    expect(rowLabel('al:a'), 'joni - blue, $folded, 1 of 2, Blue (Album)');
    expect(rowLabel('al:b'), 'joni - blue, $folded, 2 of 2, Blue (Album)');
    expect(
      rowLabel('al:c'),
      'joni - hejira, $folded, Hejira (Album)',
      reason: 'a fold no other reads like goes unnumbered',
    );

    await _tap(
      tester,
      find.bySemanticsIdentifier(SemanticsIds.foldUnfold('album', 'al:b')),
    );
    expect(
      find.text('"joni - blue" ($folded, 2 of 2)'),
      findsOneWidget,
      reason: 'the dialog names which of the two it unfolds',
    );
    await _tap(
      tester,
      find.bySemanticsIdentifier(SemanticsIds.foldUnfoldConfirm),
    );
    expect(repo.unfoldCalls.single.keys, ['al:b']);
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      '"joni - blue" ($folded, 2 of 2) is unfolded',
    );
  });

  testWidgets('an unfold that empties the rows read reads the next page', (
    tester,
  ) async {
    final repo = _repo()..entityFolds = _pageAndOne();
    final container = await _pump(tester, repo);
    final rows = container.read(foldsProvider).value!.folds;
    for (final fold in rows.take(rows.length - 1)) {
      await container.read(foldsProvider.notifier).drop(fold);
    }
    await tester.pumpAndSettle();
    final last = rows.last.key;
    await _tap(
      tester,
      find.bySemanticsIdentifier(SemanticsIds.foldUnfold('artist', last)),
    );
    await _tap(
      tester,
      find.bySemanticsIdentifier(SemanticsIds.foldUnfoldConfirm),
    );
    expect(find.text('No folded names'), findsNothing);
    expect(
      find.bySemanticsIdentifier(
        SemanticsIds.foldRow('artist', 'name ${FoldsController.pageSize}'),
      ),
      findsOneWidget,
      reason: 'the fold past the page read comes in its place',
    );
  });

  testWidgets('a phone card keeps the Files under label', (tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _repo()
      ..entityFolds = [_fold('artist', 'beatles', 'ar-1', 'The Beatles')];
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: _container(repo),
        child: routedHost(const HealthScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final row = find.bySemanticsIdentifier(
      SemanticsIds.foldRow('artist', 'beatles'),
    );
    expect(
      find.descendant(of: row, matching: find.text('Files under')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('The Beatles')),
      findsOneWidget,
    );
  });

  testWidgets('a row says its spelling, what it files under and its type', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final repo = _repo()
      ..entityFolds = [
        _fold(
          'album',
          _albumKey,
          'al-1',
          'Blue',
          spelling: 'joni - blue',
          folder: 'Joni/Blue Again',
          library: 'Music',
        ),
        _fold(
          'genre',
          'mood:chill',
          '01JZX5N8QW3F4V9T2B7KDMOOD0',
          'Chill',
          spelling: 'chill',
          facet: 'mood',
        ),
      ];
    await _pump(tester, repo);
    String label(String type, String key) => tester
        .getSemantics(
          find.bySemanticsIdentifier(SemanticsIds.foldRow(type, key)),
        )
        .label;
    expect(
      label('album', _albumKey),
      'joni - blue, In Joni/Blue Again in Music, Blue (Album)',
    );
    expect(label('genre', 'mood:chill'), 'chill, Mood, Chill (Mood)');
    handle.dispose();
  });

  testWidgets('a merge lists the folds again and says how many names it '
      'folded', (tester) async {
    final repo = _repo()
      ..duplicateGroups = const [
        DuplicateGroup(
          entityType: 'artist',
          survivor: DuplicateEntity(pid: 'ar-1', name: 'The Cardinal Waves'),
          losers: [
            DuplicateEntity(pid: 'ar-2', name: 'Cardinal Waves'),
            DuplicateEntity(pid: 'ar-3', name: 'Cardinal Waves!'),
          ],
        ),
      ];
    final container = await _pump(tester, repo);
    expect(find.text('No folded names'), findsOneWidget);

    await _tap(
      tester,
      find.bySemanticsIdentifier(SemanticsIds.duplicateMerge('ar-1')),
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.confirmField),
      'merge',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.confirmAccept));
    await tester.pumpAndSettle();

    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'Merged 2 entries\n2 spellings now file under The Cardinal Waves',
    );
    for (final key in ['cardinal waves', 'cardinal waves!']) {
      expect(
        find.bySemanticsIdentifier(SemanticsIds.foldRow('artist', key)),
        findsOneWidget,
        reason: 'the merge folded $key, and the list was read again',
      );
    }
  });

  for (final (fold, opens) in <(EntityFold, Matcher)>[
    (
      _fold('artist', 'beatles', 'ar-1', 'The Beatles'),
      isA<ArtistScreen>().having((s) => s.pid, 'pid', 'ar-1'),
    ),
    (
      _fold('album', _albumKey, 'al-1', 'Blue', spelling: 'joni - blue'),
      isA<AlbumScreen>().having((s) => s.pid, 'pid', 'al-1'),
    ),
    (
      _fold('release-group', 'rg:joni\u001fblue', 'rg-1', 'Blue'),
      isA<MusicListingScreen>()
          .having((s) => s.dimension, 'dimension', MusicDimension.releaseGroups)
          .having((s) => s.segment, 'segment', 'rg-1')
          // The fold list covers every medium, and so does what it opens.
          .having((s) => s.domain, 'domain', BrowseDomain.wholeLibrary),
    ),
    (
      _fold('genre', 'genre:hip hop', '01JZX5N8QW3F4V9T2B7KDGENRE', 'Hip-Hop'),
      isA<MusicListingScreen>()
          .having((s) => s.dimension, 'dimension', MusicDimension.genres)
          .having((s) => s.segment, 'segment', '01JZX5N8QW3F4V9T2B7KDGENRE')
          // The fold list covers every medium, and so does what it opens.
          .having((s) => s.domain, 'domain', BrowseDomain.wholeLibrary),
    ),
    (
      _fold('series', 'series:harbor tales', 'sr-1', 'Harbor Tales'),
      isA<BookSeriesScreen>().having((s) => s.pid, 'pid', 'sr-1'),
    ),
  ]) {
    testWidgets('a ${fold.entityType} row opens the entry it files under', (
      tester,
    ) async {
      await _pump(tester, _repo()..entityFolds = [fold]);
      await _tap(
        tester,
        find.bySemanticsIdentifier(
          SemanticsIds.foldRow(fold.entityType, fold.key),
        ),
      );
      expect(find.byType(HealthScreen), findsNothing);
      final shown = tester.widgetList(
        find.byWidgetPredicate(
          (w) =>
              w is ArtistScreen ||
              w is AlbumScreen ||
              w is MusicListingScreen ||
              w is BookSeriesScreen,
        ),
      );
      expect(shown.single, opens);
    });
  }

  testWidgets('coming back from an entry reads the list again', (tester) async {
    final repo = _repo()
      ..entityFolds = [_fold('artist', 'beatles', 'ar-1', 'The Beatles')];
    await _pump(tester, repo);
    await _tap(
      tester,
      find.bySemanticsIdentifier(SemanticsIds.foldRow('artist', 'beatles')),
    );
    final entry = find.byType(ArtistScreen);
    expect(entry, findsOneWidget);
    // Folded meanwhile, by a merge or a locked rename made from there.
    repo.entityFolds = [
      ...repo.entityFolds,
      _fold('artist', 'the beatles', 'ar-1', 'The Beatles'),
    ];
    GoRouter.of(tester.element(entry)).pop();
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.foldRow('artist', 'the beatles')),
      findsOneWidget,
    );
  });

  testWidgets('more folds that fail to come say why and keep the rows', (
    tester,
  ) async {
    final repo = _repo()..entityFolds = _pageAndOne();
    final container = await _pump(tester, repo);
    repo.foldsError = const WaxDeckApiException(
      code: 'catalog-maintenance',
      message: 'down',
      statusCode: 503,
    );
    await _tap(tester, find.bySemanticsIdentifier(SemanticsIds.foldsMore));
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      AppLocalizationsEn().errorCatalogMaintenance,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.foldRow('artist', 'name 000')),
      findsOneWidget,
    );
    final more = tester.widget<WaxButton>(
      waxControl<WaxButton>(SemanticsIds.foldsMore),
    );
    expect(more.onPressed, isNotNull, reason: 'asking again is offered');
  });

  testWidgets('more folds come a page at a time', (tester) async {
    final repo = _repo()..entityFolds = _pageAndOne();
    await _pump(tester, repo);
    final last = find.bySemanticsIdentifier(
      SemanticsIds.foldRow('artist', 'name ${FoldsController.pageSize}'),
    );
    expect(last, findsNothing);

    await _tap(tester, find.bySemanticsIdentifier(SemanticsIds.foldsMore));
    expect(last, findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.foldsMore),
      findsNothing,
      reason: 'the last page came',
    );
  });

  testWidgets('a listing that fails says so and asks again', (tester) async {
    final repo = _repo()
      ..foldsError = const WaxDeckApiException(
        code: 'catalog-maintenance',
        message: 'down',
        statusCode: 503,
      );
    await _pump(tester, repo);
    expect(find.text('Could not load folded names'), findsOneWidget);

    repo
      ..foldsError = null
      ..entityFolds = [_fold('artist', 'beatles', 'ar-1', 'The Beatles')];
    await _tap(tester, find.bySemanticsIdentifier(SemanticsIds.foldsRetry));
    expect(
      find.bySemanticsIdentifier(SemanticsIds.foldRow('artist', 'beatles')),
      findsOneWidget,
    );
  });
}
