import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/notifications/notifications_binder.dart';
import 'package:waxdeck/src/notifications/notifications_controller.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/sync/server_event_bus.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import 'fakes.dart';

ServerSyncEvent _marker(String kind, {String pid = 'rv-1'}) =>
    ServerSyncEvent(kind: kind, pid: pid);

const _user = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  username: 'sam',
  roles: <String>['admin'],
);

int _nf = 0;
ServerNotification _inboxRow(
  String event, {
  String? target,
  DateTime? at,
  DateTime? readAt,
  String title = 'Server title',
  String body = 'Server body',
}) => ServerNotification(
  id: 'nf-${_nf++}',
  event: event,
  title: title,
  body: body,
  targetPid: target,
  createdAt: at ?? DateTime.now(),
  readAt: readAt,
);

/// A container whose account is signed in, so the inbox is read.
ProviderContainer _signedIn(FakeRepository repo) =>
    ProviderContainer(overrides: [repositoryProvider.overrideWithValue(repo)]);

void main() {
  group('the vocabulary a row is addressed by', () {
    // The token is the handle a spec locates a row with. One that
    // drifted from the event name is a locator matching nothing, which
    // `toBeHidden` would pass.
    test('every kind carries the event name it comes from', () {
      const hints = <NotificationKind, String>{
        NotificationKind.review: 'review',
        NotificationKind.upload: 'upload',
        NotificationKind.task: 'task',
      };
      for (final entry in hints.entries) {
        expect(entry.key.token, entry.value);
        expect(NotificationKind.forMarker(entry.value), entry.key);
      }
      const events = <NotificationKind, String>{
        NotificationKind.signupRequested: 'signup-requested',
        NotificationKind.backupCompleted: 'backup-completed',
        NotificationKind.backupFailed: 'backup-failed',
        NotificationKind.reviewReady: 'review-ready',
        NotificationKind.feedDisabled: 'feed-disabled',
        NotificationKind.importCompleted: 'import-completed',
        NotificationKind.episodeDownloaded: 'episode-downloaded',
        NotificationKind.playlistSynced: 'playlist-synced',
      };
      for (final entry in events.entries) {
        expect(entry.key.token, entry.value);
        expect(NotificationKind.forEvent(entry.value), entry.key);
      }
      // The one kind this client mints for itself: it has a token so a
      // spec can address its row, and no event on the stream is called
      // that.
      expect(NotificationKind.download.token, 'download');
      expect(NotificationKind.forMarker('download'), isNull);
      expect(NotificationKind.forEvent('download'), isNull);
    });

    // The announcements ride the same emit as the catalog event of the
    // same name, so a client that drew both would draw each one twice.
    test('the announcements are the inbox half and not a marker', () {
      for (final token in <String>[
        'feed-disabled',
        'episode-downloaded',
        'import-completed',
        'playlist-synced',
      ]) {
        expect(NotificationKind.forMarker(token), isNull);
        expect(NotificationKind.forEvent(token), isNotNull);
      }
    });

    test('the kinds that name an entity are the ones that navigate to '
        'one', () {
      for (final kind in NotificationKind.values) {
        final named = kind.locationFor('pc-01JZX5N8QW3F4V9T2B7KD3M9R6');
        expect(
          named != kind.location,
          kind.namesEntity,
          reason: '${kind.name} disagrees with itself about carrying a pid',
        );
      }
    });

    test('every row goes somewhere', () {
      for (final kind in NotificationKind.values) {
        expect(kind.location, startsWith('/'));
      }
    });
  });

  group('what a sync marker becomes', () {
    late ProviderContainer container;
    late LocalNotifications local;

    setUp(() {
      container = ProviderContainer();
      local = container.read(localNotificationsProvider.notifier);
    });
    tearDown(() => container.dispose());

    test('the hint kinds become rows and the hydrated ones do not', () {
      local
        ..recordServerEvent(_marker('review'))
        ..recordServerEvent(_marker('upload', pid: 'up-1'))
        ..recordServerEvent(_marker('task', pid: 'tk-1'))
        // This client's own checkpoint coming back, and a preference it
        // just wrote. A bell that rang for these would ring constantly.
        ..recordServerEvent(const ServerSyncEvent(kind: 'play-state'))
        ..recordServerEvent(const ServerSyncEvent(kind: 'prefs'))
        // A kind from a newer server: skipped, never drawn as a row that
        // goes nowhere. An unknown *catalog event* is drawn from the
        // inbox instead, which is a different thing entirely.
        ..recordServerEvent(const ServerSyncEvent(kind: 'invented'));

      final kinds = container
          .read(localNotificationsProvider)
          .map((n) => n.kind);
      expect(kinds, <NotificationKind>[
        NotificationKind.task,
        NotificationKind.upload,
        NotificationKind.review,
      ], reason: 'newest first, and only the hints');
    });

    test('a burst of one kind is one row', () {
      // A scan opening forty review entries arrives as forty identical
      // markers, coalesced or not.
      for (var i = 0; i < 40; i++) {
        local.recordServerEvent(_marker('review', pid: 'rv-$i'));
      }
      expect(container.read(localNotificationsProvider), hasLength(1));
    });

    test('the list is capped', () {
      // Distinct tasks, because a row's identity is its kind and what it
      // is about: forty markers naming one task are one row by design.
      for (var i = 0; i < LocalNotifications.cap * 2; i++) {
        local.record(
          NotificationKind.task,
          at: DateTime(2026, 7, 31, 12, i),
          pid: 'tk-$i',
        );
      }
      expect(
        container.read(localNotificationsProvider),
        hasLength(LocalNotifications.cap),
      );
    });

    test('the badge counts what arrived since the bell was opened', () {
      local.recordServerEvent(_marker('review'));
      expect(local.unseen, 1);

      local.markSeen();
      expect(local.unseen, 0);

      local.record(
        NotificationKind.upload,
        at: DateTime.now().add(const Duration(seconds: 1)),
      );
      expect(local.unseen, 1);
    });

    test('going where a row points is what clears it', () {
      local
        ..recordServerEvent(_marker('review'))
        ..recordServerEvent(_marker('upload', pid: 'up-1'));

      // The queue itself, which is where the review row points.
      local.dismissUnder(WaxRoute.review);
      expect(
        container.read(localNotificationsProvider).map((n) => n.kind),
        <NotificationKind>[NotificationKind.upload],
        reason: 'a visit answers its own row and nobody else\'s',
      );
    });

    test('an entry under a surface answers the surface', () {
      // The review row points at the queue and a reader deals with it by
      // opening an entry, which is a location under it rather than the
      // location itself.
      local.recordServerEvent(_marker('review'));
      local.dismissUnder('${WaxRoute.review}/rv-1');
      expect(container.read(localNotificationsProvider), isEmpty);
    });

    test('a later event for the same thing is news again', () {
      local.recordServerEvent(_marker('review'));
      local.dismissUnder(WaxRoute.review);
      expect(container.read(localNotificationsProvider), isEmpty);

      // Somewhere else, and then it happens again: the reader has not
      // seen this one.
      local.dismissUnder(WaxRoute.home);
      local.recordServerEvent(_marker('review'));
      expect(container.read(localNotificationsProvider), hasLength(1));
    });

    test('news about the screen in front of you never lands', () {
      local.dismissUnder(WaxRoute.uploads);
      local.recordServerEvent(_marker('upload', pid: 'up-1'));
      expect(container.read(localNotificationsProvider), isEmpty);
      expect(local.unseen, 0);
    });

    test("this device's own finished transfer is a row", () {
      local.recordDownloadCompleted();
      expect(
        container.read(localNotificationsProvider).single.kind,
        NotificationKind.download,
      );
    });
  });

  group('what the inbox draws', () {
    late FakeRepository repo;
    late ProviderContainer container;

    setUp(() async {
      repo = FakeRepository(
        sessionState: const SessionState(authenticated: true, user: _user),
      );
      container = _signedIn(repo);
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);
    });

    /// Reads the inbox, then the merged view the surfaces draw.
    Future<NotificationsView> view() async {
      await container.read(notificationsProvider.future);
      return container.read(notificationsViewProvider);
    }

    test('a disabled feed opens its own show', () async {
      repo.inbox = <ServerNotification>[
        _inboxRow('feed-disabled', target: 'pc-01JZX5N8QW3F4V9T2B7KD3M9R6'),
      ];
      final row = (await view()).rows.single;
      expect(row.kind, NotificationKind.feedDisabled);
      expect(row.location, '/podcasts/pc-01JZX5N8QW3F4V9T2B7KD3M9R6');
    });

    test('two failing feeds are two rows, not one', () async {
      // Same sentence on both; collapsing loses one show.
      repo.inbox = <ServerNotification>[
        _inboxRow('feed-disabled', target: 'pc-B'),
        _inboxRow(
          'feed-disabled',
          target: 'pc-A',
          at: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      ];
      final rows = (await view()).rows;
      expect(rows, hasLength(2));
      expect(rows.map((n) => n.location), <String>[
        '/podcasts/pc-B',
        '/podcasts/pc-A',
      ]);
    });

    test('a feed-disabled row with no pid still opens the hub', () async {
      repo.inbox = <ServerNotification>[_inboxRow('feed-disabled')];
      expect((await view()).rows.single.location, '/podcasts');
    });

    test('a fetched episode opens the episode', () async {
      repo.inbox = <ServerNotification>[
        _inboxRow(
          'episode-downloaded',
          target: 'ep-01JZX5N8QW3F4V9T2B7KD3M9R6',
        ),
      ];
      final row = (await view()).rows.single;
      expect(row.kind, NotificationKind.episodeDownloaded);
      expect(row.location, contains('ep-01JZX5N8QW3F4V9T2B7KD3M9R6'));
    });

    test('an automatic import opens the entry that filed itself', () async {
      repo.inbox = <ServerNotification>[
        _inboxRow('import-completed', target: 'rv-1'),
      ];
      final row = (await view()).rows.single;
      expect(row.kind, NotificationKind.importCompleted);
      expect(row.location, WaxRoute.reviewEntry('rv-1'));
    });

    // The event name is the boundary, so a build that knows it says so
    // in its own language and a build that does not still says
    // something.
    test('a known event is worded here and an unknown one is worded by '
        'the server', () async {
      repo.inbox = <ServerNotification>[
        _inboxRow('backup-completed', title: 'Backup done', body: 'All of it'),
        _inboxRow(
          'invented-by-a-newer-server',
          title: 'Something happened',
          body: 'and here is what',
          at: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      ];
      final rows = (await view()).rows;
      final l10n = AppLocalizationsEn();
      expect(rows.first.messageOf(l10n), l10n.notifBackupCompletedTitle);
      expect(rows.last.kind, isNull, reason: 'nothing here knows that event');
      expect(rows.last.messageOf(l10n), 'Something happened');
      expect(rows.last.detailOf(l10n), 'and here is what');
      expect(
        rows.last.location,
        WaxRoute.notifications,
        reason: 'nowhere better to go than the screen it is drawn on',
      );
    });

    test('the badge counts unread inbox rows and unseen hints', () async {
      repo.inbox = <ServerNotification>[
        _inboxRow('backup-completed'),
        _inboxRow('backup-failed', readAt: DateTime.now()),
      ];
      await view();
      expect(container.read(unseenNotificationsProvider), 1);

      container
          .read(localNotificationsProvider.notifier)
          .recordServerEvent(_marker('review'));
      expect(container.read(unseenNotificationsProvider), 2);
    });

    test('a read row leaves the bell and stays on the screen', () async {
      repo.inbox = <ServerNotification>[
        _inboxRow('backup-completed'),
        _inboxRow('backup-failed', readAt: DateTime.now()),
      ];
      await view();
      expect(container.read(notificationRowsProvider), hasLength(1));
      expect(container.read(notificationsViewProvider).rows, hasLength(2));
    });

    test('visiting what a row points at marks it read, and only it', () async {
      repo.inbox = <ServerNotification>[
        _inboxRow('feed-disabled', target: 'pc-A'),
        _inboxRow('feed-disabled', target: 'pc-B'),
      ];
      await view();
      container
          .read(notificationsProvider.notifier)
          .dismissUnder(WaxRoute.show('pc-A'));
      await Future<void>.delayed(Duration.zero);

      final rows = container.read(notificationsViewProvider);
      expect(rows.unreadInbox, 1);
      expect(rows.rows.where((r) => r.read).map((r) => r.targetPid), <String>[
        'pc-A',
      ]);
      expect(repo.inboxReadCalls.single, hasLength(1));
    });

    test('mark all read empties the badge and says so once', () async {
      repo.inbox = <ServerNotification>[
        _inboxRow('backup-completed'),
        _inboxRow('backup-failed'),
      ];
      await view();
      await container.read(notificationsProvider.notifier).markAllRead();

      expect(container.read(unseenNotificationsProvider), 0);
      expect(container.read(notificationRowsProvider), isEmpty);
      expect(repo.inboxReadCalls.single, isEmpty, reason: 'all of them');
    });

    test('deleting a row removes it and unbadges it', () async {
      repo.inbox = <ServerNotification>[_inboxRow('backup-completed')];
      final id = repo.inbox.single.id;
      await view();
      await container.read(notificationsProvider.notifier).delete(id);

      expect(container.read(notificationsViewProvider).rows, isEmpty);
      expect(container.read(unseenNotificationsProvider), 0);
      expect(repo.inboxDeleted, <String>[id]);
    });

    test('clear empties both halves', () async {
      repo.inbox = <ServerNotification>[_inboxRow('backup-completed')];
      await view();
      container
          .read(localNotificationsProvider.notifier)
          .recordServerEvent(_marker('review'));
      await container.read(notificationsProvider.notifier).clear();

      expect(container.read(notificationsViewProvider).rows, isEmpty);
      expect(container.read(localNotificationsProvider), isEmpty);
      expect(repo.inboxCleared, 1);
    });

    // Two nightly backups are two rows saying the same thing. They used
    // to be impossible - the session list deduplicated on kind and pid -
    // and the inbox keeps ninety days, so a handle drawn from the event
    // alone would be one key and one identifier naming both.
    test('rows of one pid-less event are told apart', () async {
      repo.inbox = <ServerNotification>[
        _inboxRow('backup-completed'),
        _inboxRow(
          'backup-completed',
          at: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ];
      final rows = (await view()).rows;
      expect(rows, hasLength(2));
      expect(
        rows.map((r) => r.semanticsId).toSet(),
        hasLength(2),
        reason: 'two rows, two handles',
      );
    });

    // The heading says which kind of thing happened; the body is the
    // only place which one does.
    test('the detail line is the server own words', () async {
      repo.inbox = <ServerNotification>[
        _inboxRow(
          'episode-downloaded',
          target: 'ep-1',
          title: 'New episode: Cool Show',
          body: 'The one about badgers',
        ),
      ];
      final l10n = AppLocalizationsEn();
      final row = (await view()).rows.single;
      expect(row.messageOf(l10n), l10n.notifEpisodeDownloadedTitle);
      expect(row.detailOf(l10n), 'The one about badgers');
    });

    // Offline is not an error state on a peek: an unreachable inbox
    // leaves the session's own hints standing rather than putting a
    // failure where a bell was.
    test('an unreadable inbox still draws this session', () async {
      final broken = _UnreadableInbox(
        sessionState: const SessionState(authenticated: true, user: _user),
      );
      final other = _signedIn(broken);
      addTearDown(other.dispose);
      await other.read(authControllerProvider.future);
      other
          .read(localNotificationsProvider.notifier)
          .recordServerEvent(_marker('review'));

      await other.read(notificationsProvider.future);
      final rows = other.read(notificationsViewProvider);
      expect(rows.rows, hasLength(1));
      expect(rows.unreadInbox, 0);
    });
  });

  group('the inbox holds what it had', () {
    late FakeRepository repo;
    late ProviderContainer container;

    setUp(() async {
      repo = FakeRepository(
        sessionState: const SessionState(authenticated: true, user: _user),
      );
      container = _signedIn(repo);
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);
    });

    // A peek that cannot reach the server showed an empty bell over a
    // dozen unread rows, and nothing brought them back: no exception
    // escaped, so no retry ran, and the only other rebuild is an
    // account change.
    test('a failed refetch keeps the rows it already had', () async {
      repo.inbox = <ServerNotification>[_inboxRow('backup-completed')];
      await container.read(notificationsProvider.future);
      expect(container.read(notificationsViewProvider).rows, hasLength(1));

      repo.inboxError = const WaxDeckApiException(
        code: 'transport',
        message: 'the server went away',
      );
      container.invalidate(notificationsProvider);
      await container.read(notificationsProvider.future);

      final held = container.read(notificationsViewProvider);
      expect(held.rows, hasLength(1), reason: 'what was known is still known');
      expect(held.unreadInbox, 1);
    });

    // A read that started before a write must not answer over it: the
    // page it holds names rows the writer has already deleted.
    test(
      'a refetch in flight does not undo the write that overtook it',
      () async {
        repo.inbox = <ServerNotification>[_inboxRow('backup-completed')];
        await container.read(notificationsProvider.future);

        repo.inboxHold = Completer<void>();
        container.invalidate(notificationsProvider);
        final refetch = container.read(notificationsProvider.future);
        await container.read(notificationsProvider.notifier).clear();
        repo.inboxHold!.complete();
        repo.inboxHold = null;
        await refetch;

        expect(
          container.read(notificationsViewProvider).rows,
          isEmpty,
          reason: 'the clear stands; the stale page does not put it back',
        );
      },
    );

    // The router announces an arrival once, and a cold start into a deep
    // link announces it while the first read is still in flight.
    test('an arrival before the first read still marks its row', () async {
      repo.inbox = <ServerNotification>[
        _inboxRow('feed-disabled', target: 'pc-A'),
      ];
      container
          .read(localNotificationsProvider.notifier)
          .dismissUnder(WaxRoute.show('pc-A'));
      await container.read(notificationsProvider.future);
      await Future<void>.delayed(Duration.zero);

      final view = container.read(notificationsViewProvider);
      expect(view.unreadInbox, 0);
      expect(view.rows.single.read, isTrue);
    });
  });

  // A hint has nowhere durable to record a read stamp, so looking at the
  // bell is the whole of what reading one can mean. Without that it was
  // drawn "Unread" forever with no affordance but deleting it.
  test('a hint reads as read once the bell has been looked at', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final local = container.read(localNotificationsProvider.notifier);
    local.recordServerEvent(_marker('review'));
    expect(container.read(notificationsViewProvider).rows.single.read, isFalse);

    local.markSeen();
    expect(container.read(notificationsViewProvider).rows.single.read, isTrue);
    expect(container.read(notificationRowsProvider), isEmpty);
  });

  test('a new account starts with an empty list', () async {
    final repo = FakeRepository(
      sessionState: const SessionState(
        authenticated: true,
        user: WaxDeckUser(id: 'u-1', username: 'sam', roles: <String>['admin']),
      ),
    );
    final container = _signedIn(repo);
    addTearDown(container.dispose);
    // Kept alive so the rebuild below is observable rather than a fresh
    // read of a provider nobody was listening to.
    final alive = container.listen(localNotificationsProvider, (_, _) {});
    addTearDown(alive.close);

    await container.read(authControllerProvider.future);
    container
        .read(localNotificationsProvider.notifier)
        .recordServerEvent(_marker('review'));
    expect(container.read(localNotificationsProvider), hasLength(1));

    // Signing out and back in as somebody else: what the previous
    // session observed is not this one's.
    repo.sessionState = const SessionState(
      authenticated: true,
      user: WaxDeckUser(id: 'u-2', username: 'rosie', roles: <String>[]),
    );
    container.invalidate(authControllerProvider);
    await container.read(authControllerProvider.future);
    expect(container.read(localNotificationsProvider), isEmpty);
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

    final rows = container.read(localNotificationsProvider);
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

    test('a hint during the minting pull is answered, not dropped', () async {
      // The bell's failure mode on a quiet client: the change lands
      // mid-mint, and a dropped hint has no second one to recover on.
      final repo = _SyncRepository();
      final seen = <ServerSyncEvent>[];
      final puller = UserEventPuller(repository: repo, onEvent: seen.add);

      repo.hold = Completer<void>();
      final minting = puller.pull();
      unawaited(puller.pull());
      repo.pages = <ServerSyncPage>[
        ServerSyncPage(
          events: <ServerSyncEvent>[_marker('upload', pid: 'up-1')],
          nextSince: 'c1',
        ),
      ];
      repo.hold!.complete();
      repo.hold = null;
      await minting;

      expect(seen.map((e) => e.kind), <String>[
        'upload',
      ], reason: 'the walk the hint asked for ran once the mint was done');
      expect(repo.sinceCalls, <String?>[null, 'c0']);
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

  /// Held open, so a test can land a hint mid-walk.
  Completer<void>? hold;

  /// Throws once this many pages into the current walk, for the walk
  /// that is cut short halfway.
  int? failAfter;
  int _served = 0;

  @override
  Future<ServerSyncPage> syncServer({String? since, int? limit}) async {
    sinceCalls.add(since);
    final held = hold;
    if (held != null) await held.future;
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

/// A repository whose inbox is unreachable, which is what an offline
/// client and a server too old to hold one both look like.
class _UnreadableInbox extends FakeRepository {
  _UnreadableInbox({super.sessionState});

  @override
  Future<ServerNotificationPage> listMyNotifications({
    String? cursor,
    int? limit,
  }) async => throw const WaxDeckApiException(
    code: 'transport',
    message: 'the server is not there',
  );
}
