import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/player/bookmarks.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/sync/server_event_bus.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'player_host.dart';

const _bookPid = 'bk-01JZX5N8QW3F4V9T2B7KD3M9R6';
const _me = 'us-1';

ItemSummary _book() => testItem(
  _bookPid,
  mediaType: MediaType.audiobook,
  title: 'There And Back Again',
  durationMs: 3600000,
);

Bookmark _mark(String id, int positionMs, {String? note}) => Bookmark(
  id: id,
  positionMs: positionMs,
  note: note,
  createdAt: DateTime.utc(2026, 9, 27),
);

/// Counts who listens for bookmark changes.
class _CountingSync extends SyncEngine {
  _CountingSync({
    required super.db,
    required super.repository,
    required super.channelFactory,
  });

  var listening = 0;

  @override
  Stream<String> get bookmarksChanged => Stream<String>.multi((out) {
    listening++;
    final changes = super.bookmarksChanged.listen(out.add);
    out.onCancel = () {
      listening--;
      return changes.cancel();
    };
  });
}

/// What a request answers when nothing does.
const _unreachable = WaxDeckApiException(
  code: 'transport',
  message: 'network unreachable',
);

/// A book playing with a real sync engine over an in-memory mirror, as
/// the listener [_me]; offline, the link is down and nothing answers.
class _Rig {
  _Rig({required this.offline}) {
    db = inMemoryMirrorDatabase();
    repo = FakeRepository()
      ..books[_bookPid] = testBook(_bookPid, durationMs: 3600000);
    if (offline) {
      repo
        ..listBookmarksError = _unreachable
        ..createBookmarkError = _unreachable
        ..deleteBookmarkError = _unreachable;
    }
    sync = SyncEngine(
      db: db,
      repository: repo,
      channelFactory: deadChannelFactory(),
    )..account = _me;
    addTearDown(() async {
      sync.dispose();
      await db.close();
    });
  }

  final bool offline;
  late final MirrorDatabase db;
  late final FakeRepository repo;
  late final SyncEngine sync;
  late PlayerHarness harness;

  Future<void> pump(WidgetTester tester) async {
    final engine = FakeEngine(mediaDuration: const Duration(hours: 1));
    harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: _book(),
      container: playbackContainer(
        repo: repo,
        engine: engine,
        extra: [
          syncEngineProvider.overrideWithValue(sync),
          signedInAccountProvider.overrideWithValue(_me),
          offlineProvider.overrideWithValue(offline),
        ],
      ),
    );
    engine.advance(const Duration(minutes: 12));
    await tester.pump();
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerBookmarks));
    await tester.pumpAndSettle();
  }

  Future<void> mark(WidgetTester tester) async {
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playerBookmarkAdd),
    );
    await tester.pumpAndSettle();
  }

  Future<List<OutboxMutation>> outbox() => db.select(db.outboxMutations).get();
}

/// Whether the link is down, flipped by a test.
class _Link extends Notifier<bool> {
  @override
  bool build() => false;

  set down(bool value) => state = value;
}

final _linkDown = NotifierProvider<_Link, bool>(_Link.new);

Finder _state(int index) =>
    find.bySemanticsIdentifier(SemanticsIds.playerBookmarkState(index));

void main() {
  testWidgets('a mark made offline shows as not sent and waits', (
    tester,
  ) async {
    final rig = _Rig(offline: true);
    await rig.pump(tester);
    await rig.openSheet(tester);
    await rig.mark(tester);

    expect(
      find.bySemanticsIdentifier(SemanticsIds.playerBookmark(0)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _state(0), matching: find.text('Not sent yet')),
      findsOneWidget,
    );
    // Said once, with the mark it is about.
    expect(find.bySemanticsLabel(RegExp('Not sent yet')), findsOneWidget);
    final queued = (await rig.outbox()).single;
    expect(queued.kind, 'bookmark-create');
    expect(queued.payload, matches(RegExp(r'"id":"bm-[0-7][0-9A-Z]{25}"')));
    // Tried under the id it waits with.
    expect(queued.payload, contains(rig.repo.createBookmarkCalls.single.id!));
    await rig.harness.endPlayback(tester);
  });

  testWidgets('a mark the server cannot be reached for waits too', (
    tester,
  ) async {
    final rig = _Rig(offline: false);
    rig.repo.createBookmarkError = const WaxDeckApiException(
      code: 'transport',
      message: 'network unreachable',
    );
    await rig.pump(tester);
    await rig.openSheet(tester);
    await rig.mark(tester);

    // Tried once under the id it minted, then queued under the same id.
    final tried = rig.repo.createBookmarkCalls.single;
    expect(tried.id, startsWith('bm-'));
    expect((await rig.outbox()).single.payload, contains(tried.id!));
    expect(
      find.descendant(of: _state(0), matching: find.text('Not sent yet')),
      findsOneWidget,
    );
    expect(find.text('network unreachable'), findsNothing);
    await rig.harness.endPlayback(tester);
  });

  testWidgets('a mark sent from the outbox loses its caption', (tester) async {
    final rig = _Rig(offline: true);
    await rig.pump(tester);
    await rig.openSheet(tester);
    await rig.mark(tester);
    expect(_state(0), findsOneWidget);

    rig.repo.createBookmarkError = null;
    await rig.sync.flushOutbox();
    await tester.pumpAndSettle();

    expect(rig.repo.createBookmarkCalls, hasLength(2));
    expect(_state(0), findsNothing);
    await rig.harness.endPlayback(tester);
  });

  testWidgets('a mark the server refused says why, in its words', (
    tester,
  ) async {
    final rig = _Rig(offline: false);
    await rig.sync.queueBookmarkCreate(
      _bookPid,
      _mark('bm-01JZX5N8QW3F4V9T2B7KD3M9R6', 99),
      owner: _me,
    );
    rig.repo.createBookmarkError = const WaxDeckApiException(
      code: 'invalid-request',
      message: 'that position is past the end of the book',
      statusCode: 400,
    );
    await rig.sync.flushOutbox();
    rig.repo.createBookmarkError = null;

    await rig.pump(tester);
    await rig.openSheet(tester);

    // A refusal of what was typed keeps the server's sentence: the table's
    // would say only that something was wrong.
    expect(
      find.descendant(
        of: _state(0),
        matching: find.text(
          'Not saved: that position is past the end of the book',
        ),
      ),
      findsOneWidget,
    );
    await rig.harness.endPlayback(tester);
  });

  testWidgets('a refusal the app has words for is said in them', (
    tester,
  ) async {
    final rig = _Rig(offline: false);
    await rig.sync.queueBookmarkCreate(
      _bookPid,
      _mark('bm-01JZX5N8QW3F4V9T2B7KD3M9R6', 99),
      owner: _me,
    );
    rig.repo.createBookmarkError = const WaxDeckApiException(
      code: 'not-found',
      message: 'no such book: bk-gone',
      statusCode: 404,
    );
    await rig.sync.flushOutbox();
    rig.repo.createBookmarkError = null;

    await rig.pump(tester);
    await rig.openSheet(tester);

    expect(
      find.descendant(
        of: _state(0),
        matching: find.text('Not saved: That is not here any more.'),
      ),
      findsOneWidget,
    );
    await rig.harness.endPlayback(tester);
  });

  test('a list dropped while it reads leaves nothing listening', () async {
    final db = inMemoryMirrorDatabase();
    final repo = FakeRepository()..listBookmarksGate = Completer<void>();
    final sync = _CountingSync(
      db: db,
      repository: repo,
      channelFactory: deadChannelFactory(),
    )..account = _me;
    addTearDown(() async {
      sync.dispose();
      await db.close();
    });
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        syncEngineProvider.overrideWithValue(sync),
        signedInAccountProvider.overrideWithValue(_me),
        offlineProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    final listen = container.listen(bookmarksProvider(_bookPid), (_, _) {});
    await Future<void>.delayed(Duration.zero);
    listen.close();
    await Future<void>.delayed(Duration.zero);
    repo.listBookmarksGate!.complete();
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(sync.listening, 0);
  });

  testWidgets('a read the server refuses says so at once', (tester) async {
    final rig = _Rig(offline: false);
    rig.repo.listBookmarksError = const WaxDeckApiException(
      code: 'not-found',
      message: 'no such book',
      statusCode: 404,
    );
    await rig.pump(tester);
    // Not pumpAndSettle, which would spin out a retry backoff unseen.
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerBookmarks));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('That is not here any more.'), findsOneWidget);
    await rig.harness.endPlayback(tester);
  });

  testWidgets('offline, the sheet reads the marks this device holds', (
    tester,
  ) async {
    final rig = _Rig(offline: true);
    await rig.sync.storeBookmarks(_bookPid, [
      _mark('bm-01JZX5N8QW3F4V9T2B7KD3M9R6', 60000, note: 'the riddle'),
    ], owner: _me);
    await rig.pump(tester);
    await rig.openSheet(tester);

    final row = find.bySemanticsIdentifier(SemanticsIds.playerBookmark(0));
    expect(tester.getSemantics(row).label, contains('the riddle'));
    expect(_state(0), findsNothing);
    await rig.harness.endPlayback(tester);
  });

  testWidgets('what is marked and removed online is mirrored too', (
    tester,
  ) async {
    final rig = _Rig(offline: false);
    await rig.pump(tester);
    await rig.openSheet(tester);
    await rig.mark(tester);

    Future<Map<String, BookmarkSync>> mirrored() async => {
      for (final m in await rig.sync.localBookmarks(_bookPid, owner: _me))
        m.mark.id: m.sync,
    };
    final made = rig.repo.createBookmarkCalls.single;
    expect(await mirrored(), {made.id: BookmarkSync.synced});

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playerBookmarkDelete(0)),
    );
    await tester.pumpAndSettle();
    expect(rig.repo.deleteBookmarkCalls, hasLength(1));
    expect(await mirrored(), isEmpty);
    await rig.harness.endPlayback(tester);
  });

  testWidgets('removing a mark offline queues its removal', (tester) async {
    final rig = _Rig(offline: true);
    await rig.sync.storeBookmarks(_bookPid, [
      _mark('bm-01JZX5N8QW3F4V9T2B7KD3M9R6', 60000),
    ], owner: _me);
    await rig.pump(tester);
    await rig.openSheet(tester);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playerBookmarkDelete(0)),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.playerBookmark(0)),
      findsNothing,
    );
    expect((await rig.outbox()).single.kind, 'bookmark-delete');
    await rig.harness.endPlayback(tester);
  });

  testWidgets('a full book refuses the mark here, in the app language', (
    tester,
  ) async {
    final rig = _Rig(offline: true);
    await rig.sync.storeBookmarks(_bookPid, [
      for (var i = 0; i < 200; i++)
        _mark('bm-01JZX5N8QW3F4V9T2B7KD${i.toString().padLeft(3, '0')}', i),
    ], owner: _me);
    await rig.pump(tester);
    await rig.openSheet(tester);
    await rig.mark(tester);

    expect(
      find.text(
        'This book already holds as many bookmarks as it can. Remove one to '
        'mark another.',
      ),
      findsOneWidget,
    );
    expect(await rig.outbox(), isEmpty);
    await rig.harness.endPlayback(tester);
  });

  group('natively', () {
    late MirrorDatabase db;
    late FakeRepository repo;
    late _CountingSync sync;

    setUp(() {
      db = inMemoryMirrorDatabase();
      repo = FakeRepository();
      sync = _CountingSync(
        db: db,
        repository: repo,
        channelFactory: deadChannelFactory(),
      )..account = _me;
      addTearDown(() async {
        sync.dispose();
        await db.close();
      });
    });

    ProviderContainer session({bool offline = false}) {
      final container = ProviderContainer(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          syncEngineProvider.overrideWithValue(sync),
          signedInAccountProvider.overrideWithValue(_me),
          offlineProvider.overrideWith(
            (ref) => offline || ref.watch(_linkDown),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    Future<BookmarksController> opened(ProviderContainer container) async {
      container.listen(bookmarksProvider(_bookPid), (_, _) {});
      await container.read(bookmarksProvider(_bookPid).future);
      return container.read(bookmarksProvider(_bookPid).notifier);
    }

    test('a mark made as its list goes away is kept', () async {
      final container = session();
      final listen = container.listen(bookmarksProvider(_bookPid), (_, _) {});
      await container.read(bookmarksProvider(_bookPid).future);
      repo.createBookmarkGate = Completer<void>();
      final adding = container
          .read(bookmarksProvider(_bookPid).notifier)
          .add(1000);
      await pumpEventQueue();
      expect(repo.createBookmarkCalls, hasLength(1));

      listen.close();
      await pumpEventQueue();
      repo.createBookmarkError = _unreachable;
      repo.createBookmarkGate!.complete();
      await adding;

      final held = await sync.localBookmarks(_bookPid, owner: _me);
      expect(held.single.sync, BookmarkSync.pending);
      expect(await db.select(db.outboxMutations).get(), hasLength(1));
    });

    test('a mark removed while its create is out stays removed', () async {
      final controller = await opened(session());
      repo.createBookmarkGate = Completer<void>();
      final adding = controller.add(1000);
      await pumpEventQueue();
      final id = repo.createBookmarkCalls.single.id!;

      final removing = controller.remove(id);
      await pumpEventQueue();
      repo.createBookmarkGate!.complete();
      await adding;
      await removing;

      expect(repo.bookmarks[_bookPid], isEmpty);
      expect(await sync.localBookmarks(_bookPid, owner: _me), isEmpty);
      expect(await db.select(db.outboxMutations).get(), isEmpty);
    });

    test('a mark on its way out stays listed through a read', () async {
      final container = session();
      final controller = await opened(container);
      repo.createBookmarkGate = Completer<void>();
      final adding = controller.add(1000);
      await pumpEventQueue();

      container.invalidate(bookmarksProvider(_bookPid));
      final listed = await container.read(bookmarksProvider(_bookPid).future);

      expect(listed.single.sync, BookmarkSync.pending);
      repo.createBookmarkGate!.complete();
      await adding;
    });

    test('the list is not read again as the link comes and goes', () async {
      final container = session();
      await opened(container);

      container.read(_linkDown.notifier).down = true;
      await pumpEventQueue();
      container.read(_linkDown.notifier).down = false;
      await pumpEventQueue();

      expect(repo.listBookmarksCalls, 1);
    });

    test(
      'with the link down, a mark still goes if the server answers',
      () async {
        final controller = await opened(session(offline: true));

        await controller.add(1000);

        expect(repo.createBookmarkCalls, hasLength(1));
        final held = await sync.localBookmarks(_bookPid, owner: _me);
        expect(held.single.sync, BookmarkSync.synced);
      },
    );

    test('a read a proxy fails shows the marks this device holds', () async {
      await sync.storeBookmarks(_bookPid, [
        _mark('bm-01JZX5N8QW3F4V9T2B7KD3M9R6', 60000),
      ], owner: _me);
      repo.listBookmarksError = const WaxDeckApiException(
        code: 'internal',
        message: 'bad gateway',
        statusCode: 502,
      );
      final container = session();
      container.listen(bookmarksProvider(_bookPid), (_, _) {});

      final listed = await container.read(bookmarksProvider(_bookPid).future);

      expect(listed.single.mark.positionMs, 60000);
    });

    test('a list rebuilt while it reads listens once', () async {
      repo.listBookmarksGate = Completer<void>();
      final container = session();
      container.listen(bookmarksProvider(_bookPid), (_, _) {});
      await pumpEventQueue();
      container.invalidate(bookmarksProvider(_bookPid));
      await pumpEventQueue();

      repo.listBookmarksGate!.complete();
      await container.read(bookmarksProvider(_bookPid).future);
      await pumpEventQueue();

      expect(sync.listening, 1);
    });
  });

  group('on web', () {
    late FakeRepository repo;

    setUp(() => repo = FakeRepository());

    ProviderContainer session({ServerEventBus? bus}) {
      final container = ProviderContainer(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          syncEngineProvider.overrideWithValue(null),
          if (bus != null) serverEventBusProvider.overrideWith((ref) => bus),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a read that fails in passing is asked again', () async {
      repo.listBookmarksError = _unreachable;
      final container = session();
      container.listen(bookmarksProvider(_bookPid), (_, _) {});
      await pumpEventQueue();

      repo.listBookmarksError = null;
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(container.read(bookmarksProvider(_bookPid)).value, isEmpty);
    });

    test('a mark added to a list that would not load reads it again', () async {
      repo.bookmarks[_bookPid] = [
        _mark('bm-01JZX5N8QW3F4V9T2B7KD3M9R6', 60000),
      ];
      repo.listBookmarksError = const WaxDeckApiException(
        code: 'forbidden',
        message: 'not now',
        statusCode: 403,
      );
      final container = session();
      container.listen(bookmarksProvider(_bookPid), (_, _) {});
      await pumpEventQueue();
      repo.listBookmarksError = null;

      await container.read(bookmarksProvider(_bookPid).notifier).add(1000);
      final listed = await container.read(bookmarksProvider(_bookPid).future);

      expect(listed, hasLength(2));
    });

    test('a mark made on another device reaches an open list', () async {
      final bus = ServerEventBus();
      addTearDown(bus.dispose);
      final container = session(bus: bus);
      container.listen(bookmarksProvider(_bookPid), (_, _) {});
      await container.read(bookmarksProvider(_bookPid).future);

      bus.add(
        ServerSyncEvent(
          kind: 'bookmarks',
          pid: _bookPid,
          bookmarks: [_mark('bm-01JZX5N8QW3F4V9T2B7KD3M9R6', 60000)],
        ),
      );
      await pumpEventQueue();

      final listed = container.read(bookmarksProvider(_bookPid)).value;
      expect(listed?.single.mark.positionMs, 60000);
    });
  });
}
