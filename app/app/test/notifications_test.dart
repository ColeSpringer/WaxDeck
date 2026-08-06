import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/notifications/notifications_binder.dart';
import 'package:waxdeck/src/notifications/notifications_controller.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import 'fakes.dart';

ServerSyncEvent _marker(String kind, {String pid = 'rv-1'}) =>
    ServerSyncEvent(kind: kind, pid: pid);

void main() {
  group('what a server-state change becomes', () {
    late ProviderContainer container;
    late NotificationsController notifications;

    setUp(() {
      container = ProviderContainer();
      notifications = container.read(notificationsProvider.notifier);
    });
    tearDown(() => container.dispose());

    test('the marker kinds become rows and the hydrated ones do not', () {
      notifications
        ..recordServerEvent(_marker('review'))
        ..recordServerEvent(_marker('upload', pid: 'up-1'))
        ..recordServerEvent(_marker('task', pid: 'tk-1'))
        // This client's own checkpoint coming back, and a preference it
        // just wrote. A bell that rang for these would ring constantly.
        ..recordServerEvent(const ServerSyncEvent(kind: 'play-state'))
        ..recordServerEvent(const ServerSyncEvent(kind: 'prefs'))
        // A kind from a newer server: skipped, never drawn as a row that
        // goes nowhere.
        ..recordServerEvent(const ServerSyncEvent(kind: 'invented'));

      final kinds = container.read(notificationsProvider).map((n) => n.kind);
      expect(kinds, <NotificationKind>[
        NotificationKind.task,
        NotificationKind.upload,
        NotificationKind.review,
      ], reason: 'newest first, and only the markers');
    });

    test('a burst of one kind is one row', () {
      // A scan opening forty review entries arrives as forty identical
      // markers, coalesced or not.
      for (var i = 0; i < 40; i++) {
        notifications.recordServerEvent(_marker('review', pid: 'rv-$i'));
      }
      expect(container.read(notificationsProvider), hasLength(1));
    });

    test('the list is capped', () {
      for (var i = 0; i < NotificationsController.cap * 2; i++) {
        notifications.record(
          NotificationKind.task,
          'task $i changed',
          at: DateTime(2026, 7, 31, 12, i),
        );
      }
      expect(
        container.read(notificationsProvider),
        hasLength(NotificationsController.cap),
      );
    });

    test('the badge counts what arrived since the bell was opened', () {
      notifications.recordServerEvent(_marker('review'));
      expect(container.read(unseenNotificationsProvider), 1);

      notifications.markSeen();
      expect(container.read(unseenNotificationsProvider), 0);

      notifications.record(
        NotificationKind.upload,
        'An upload changed.',
        at: DateTime.now().add(const Duration(seconds: 1)),
      );
      expect(container.read(unseenNotificationsProvider), 1);
    });

    test('every row goes somewhere', () {
      for (final kind in NotificationKind.values) {
        expect(kind.location, startsWith('/'));
      }
    });

    test('a disabled feed opens its own show', () {
      notifications.recordServerEvent(
        _marker('feed-disabled', pid: 'pc-01JZX5N8QW3F4V9T2B7KD3M9R6'),
      );
      final row = container.read(notificationsProvider).single;
      expect(row.kind, NotificationKind.feedDisabled);
      expect(row.location, '/podcasts/pc-01JZX5N8QW3F4V9T2B7KD3M9R6');
    });

    test('two failing feeds are two rows, not one', () {
      // Same sentence on both; collapsing loses one show.
      notifications
        ..recordServerEvent(_marker('feed-disabled', pid: 'pc-A'))
        ..recordServerEvent(_marker('feed-disabled', pid: 'pc-B'));
      final rows = container.read(notificationsProvider);
      expect(rows, hasLength(2));
      expect(rows.map((n) => n.location), <String>[
        '/podcasts/pc-B',
        '/podcasts/pc-A',
      ]);
    });

    test('a feed-disabled marker with no pid still opens the hub', () {
      notifications.recordServerEvent(
        const ServerSyncEvent(kind: 'feed-disabled'),
      );
      expect(
        container.read(notificationsProvider).single.location,
        '/podcasts',
      );
    });

    test('a fetched episode opens the episode', () {
      notifications.recordServerEvent(
        _marker('episode-downloaded', pid: 'ep-01JZX5N8QW3F4V9T2B7KD3M9R6'),
      );
      final row = container.read(notificationsProvider).single;
      expect(row.kind, NotificationKind.episodeDownloaded);
      expect(row.location, contains('ep-01JZX5N8QW3F4V9T2B7KD3M9R6'));
    });

    test('an automatic import says so', () {
      notifications.recordServerEvent(_marker('import-completed'));
      final row = container.read(notificationsProvider).single;
      expect(row.kind, NotificationKind.importCompleted);
      expect(row.location, NotificationKind.importCompleted.location);
    });

    test("this device's own finished transfer is a row", () {
      notifications.recordDownloadCompleted();
      expect(
        container.read(notificationsProvider).single.kind,
        NotificationKind.download,
      );
    });
  });

  test('a new account starts with an empty list', () async {
    final repo = FakeRepository(
      sessionState: const SessionState(
        authenticated: true,
        user: WaxDeckUser(id: 'u-1', username: 'sam', roles: <String>['admin']),
      ),
    );
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    // Kept alive so the rebuild below is observable rather than a fresh
    // read of a provider nobody was listening to.
    final alive = container.listen(notificationsProvider, (_, _) {});
    addTearDown(alive.close);

    await container.read(authControllerProvider.future);
    container
        .read(notificationsProvider.notifier)
        .recordServerEvent(_marker('review'));
    expect(container.read(notificationsProvider), hasLength(1));

    // Signing out and back in as somebody else: what the previous
    // session observed is not this one's.
    repo.sessionState = const SessionState(
      authenticated: true,
      user: WaxDeckUser(id: 'u-2', username: 'rosie', roles: <String>[]),
    );
    container.invalidate(authControllerProvider);
    await container.read(authControllerProvider.future);
    expect(container.read(notificationsProvider), isEmpty);
  });

  test("the binder announces this device's own finished transfers", () async {
    final downloads = FakeDownloads();
    final container = ProviderContainer(
      overrides: [
        downloadManagerProvider.overrideWithValue(downloads),
        // Web's shape: no engine, so the download listener has to be
        // registered before the puller branch returns.
        syncEngineProvider.overrideWithValue(null),
        repositoryProvider.overrideWithValue(FakeRepository()),
      ],
    );
    addTearDown(container.dispose);
    final alive = container.listen(notificationsBinderProvider, (_, _) {});
    addTearDown(alive.close);

    downloads.emit(
      const DownloadProgress(pid: 'tr-1', fraction: 0.4, complete: false),
    );
    downloads.emit(
      const DownloadProgress(pid: 'tr-1', fraction: 1, complete: true),
    );
    await Future<void>.delayed(Duration.zero);

    final rows = container.read(notificationsProvider);
    expect(rows, hasLength(1), reason: 'progress is not news; finishing is');
    expect(rows.single.kind, NotificationKind.download);
  });

  group('the web build walks the stream itself', () {
    test('the first pull mints a cursor and reports nothing', () async {
      final repo = _SyncRepository();
      final seen = <ServerSyncEvent>[];
      final puller = UserEventPuller(repository: repo, onEvent: seen.add);

      await puller.pull();
      expect(repo.sinceCalls, <String?>[null]);
      expect(
        seen,
        isEmpty,
        reason: 'a session that just started has observed nothing yet',
      );
    });

    test('later pulls report what arrived, across pages', () async {
      final repo = _SyncRepository();
      final seen = <ServerSyncEvent>[];
      final puller = UserEventPuller(repository: repo, onEvent: seen.add);
      await puller.pull();

      repo.pages = <ServerSyncPage>[
        ServerSyncPage(
          events: <ServerSyncEvent>[_marker('review')],
          nextSince: 'c1',
          more: true,
        ),
        ServerSyncPage(
          events: <ServerSyncEvent>[_marker('upload', pid: 'up-1')],
          nextSince: 'c2',
        ),
      ];
      await puller.pull();
      expect(seen.map((e) => e.kind), <String>['review', 'upload']);

      // And it resumes from where it stopped rather than re-reading.
      repo.pages = <ServerSyncPage>[
        const ServerSyncPage(events: <ServerSyncEvent>[], nextSince: 'c3'),
      ];
      await puller.pull();
      expect(repo.sinceCalls.last, 'c2');
    });

    test('a walk cut short keeps the pages it already handed out', () async {
      final repo = _SyncRepository();
      final seen = <ServerSyncEvent>[];
      final puller = UserEventPuller(repository: repo, onEvent: seen.add);
      await puller.pull();

      // Two pages, and the second one fails. The first page's events
      // were reported, so the cursor has to have moved past them.
      repo.pages = <ServerSyncPage>[
        ServerSyncPage(
          events: <ServerSyncEvent>[_marker('review')],
          nextSince: 'c1',
          more: true,
        ),
      ];
      repo.failAfter = 1;
      await puller.pull();
      expect(seen.map((e) => e.kind), <String>['review']);

      repo.pages = <ServerSyncPage>[
        const ServerSyncPage(events: <ServerSyncEvent>[], nextSince: 'c2'),
      ];
      await puller.pull();
      expect(
        repo.sinceCalls.last,
        'c1',
        reason: 'the next walk resumed after the page it had reported',
      );
      expect(seen, hasLength(1), reason: 'and reported nothing twice');
    });

    test('a reset re-mints rather than replaying an old week', () async {
      final repo = _SyncRepository();
      final seen = <ServerSyncEvent>[];
      final puller = UserEventPuller(repository: repo, onEvent: seen.add);
      await puller.pull();

      repo.failWith = const WaxDeckApiException(
        code: 'sync-reset',
        message: 'cursor too old',
      );
      await puller.pull();
      expect(seen, isEmpty);

      // Back to minting: the next pull asks with no cursor.
      repo.failWith = null;
      repo.pages = <ServerSyncPage>[
        const ServerSyncPage(events: <ServerSyncEvent>[], nextSince: 'fresh'),
      ];
      await puller.pull();
      expect(repo.sinceCalls.last, isNull);
    });
  });
}

/// A repository that answers the sync stream and records what it was
/// asked for.
class _SyncRepository extends FakeRepository {
  final List<String?> sinceCalls = <String?>[];

  /// Pages to answer, consumed in order. An exhausted list answers an
  /// empty final page.
  List<ServerSyncPage> pages = <ServerSyncPage>[];

  WaxDeckApiException? failWith;

  /// Throws once this many pages into the current walk, for the walk
  /// that is cut short halfway.
  int? failAfter;
  int _served = 0;

  @override
  Future<ServerSyncPage> syncServer({String? since, int? limit}) async {
    sinceCalls.add(since);
    final failure = failWith;
    if (failure != null) throw failure;
    if (failAfter != null && since != null) {
      if (_served >= failAfter!) {
        _served = 0;
        failAfter = null;
        throw const WaxDeckApiException(
          code: 'transport',
          message: 'the network went away mid-walk',
        );
      }
      _served++;
    }
    if (since == null) {
      return const ServerSyncPage(events: <ServerSyncEvent>[], nextSince: 'c0');
    }
    if (pages.isEmpty) {
      return ServerSyncPage(
        events: const <ServerSyncEvent>[],
        nextSince: since,
      );
    }
    return pages.removeAt(0);
  }
}
