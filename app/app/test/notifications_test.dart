import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_es.dart';
import 'package:waxdeck/src/notifications/notifications_binder.dart';
import 'package:waxdeck/src/notifications/notifications_controller.dart';
import 'package:waxdeck/src/notifications/notifications_screen.dart';
import 'package:waxdeck/src/review/review_entry_screen.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/sync/server_event_bus.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
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
  String? id,
  String? target,
  DateTime? at,
  DateTime? readAt,
  DateTime? resolvedAt,
  int count = 1,
  String title = 'Server title',
  String body = 'Server body',
}) => ServerNotification(
  id: id ?? 'nf-${_nf++}',
  event: event,
  title: title,
  body: body,
  targetPid: target,
  createdAt: at ?? DateTime.now(),
  updatedAt: at ?? DateTime.now(),
  count: count,
  resolvedAt: resolvedAt,
  readAt: readAt,
);

/// A time [minutes] ago, so a test can say which row is the newer.
DateTime _ago(int minutes) =>
    DateTime.now().subtract(Duration(minutes: minutes));

/// A container whose account is signed in, so the inbox is read.
ProviderContainer _signedIn(FakeRepository repo) => appContainer(repo: repo);

void main() {
  group('the vocabulary a row is addressed by', () {
    // The token is the handle a spec locates a row with. One that
    // drifted from the event name is a locator matching nothing, which
    // `toBeHidden` would pass.
    test('every kind carries the event name it comes from', () {
      const events = <NotificationKind, String>{
        NotificationKind.signupRequested: 'signup-requested',
        NotificationKind.backupCompleted: 'backup-completed',
        NotificationKind.backupFailed: 'backup-failed',
        NotificationKind.catalogReset: 'catalog-reset',
        NotificationKind.reviewReady: 'review-ready',
        NotificationKind.feedDisabled: 'feed-disabled',
        NotificationKind.subscriptionFailed: 'subscription-failed',
        NotificationKind.gpodderDeviceRemoved: 'gpodder-device-removed',
        NotificationKind.importCompleted: 'import-completed',
        NotificationKind.episodeDownloaded: 'episode-downloaded',
        NotificationKind.episodeArrived: 'episode-arrived',
        NotificationKind.playlistSynced: 'playlist-synced',
        NotificationKind.jobFinished: 'job-finished',
        NotificationKind.jobFailed: 'job-failed',
        NotificationKind.toolTaskFailed: 'tool-task-failed',
        NotificationKind.healthFixFinished: 'health-fix-finished',
      };
      for (final entry in events.entries) {
        expect(entry.key.token, entry.value);
        expect(NotificationKind.forEvent(entry.value), entry.key);
      }
      // A signup request is answered on the users screen's requests.
      expect(NotificationKind.signupRequested.location, WaxRoute.userRequests);
      // The one kind this client mints for itself: it has a token so a
      // spec can address its row, and no event on the stream is called
      // that.
      expect(NotificationKind.download.token, 'download');
      expect(NotificationKind.forEvent('download'), isNull);
      // The three refetch markers have no row of their own any more.
      final tokens = NotificationKind.values.map((kind) => kind.token);
      expect(tokens, isNot(contains('review')));
      expect(tokens, isNot(contains('upload')));
      expect(tokens, isNot(contains('task')));
    });

    // The announcements ride the same emit as the catalog event of the
    // same name, so a client that drew both would draw each one twice.
    test('the announcements are the inbox half', () {
      for (final token in <String>[
        'feed-disabled',
        'episode-downloaded',
        'import-completed',
        'playlist-synced',
      ]) {
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

    // The markers still refetch their surfaces, and that is all they do:
    // a row that says "something changed" gave nobody anything to act on.
    test('the review, upload and task markers mint no rows', () async {
      final bus = ServerEventBus();
      addTearDown(bus.dispose);
      final binderContainer = appContainer(
        extra: [
          serverEventBusProvider.overrideWithValue(bus),
          syncEngineProvider.overrideWithValue(null),
        ],
      );
      final alive = binderContainer.listen(
        notificationsBinderProvider,
        (_, _) {},
      );
      addTearDown(alive.close);

      for (final event in <ServerSyncEvent>[
        _marker('review'),
        _marker('upload', pid: 'up-1'),
        _marker('task', pid: 'tk-1'),
        _marker('task-progress', pid: 'tk-1'),
        const ServerSyncEvent(kind: 'play-state'),
        const ServerSyncEvent(kind: 'invented'),
      ]) {
        bus.add(event);
      }
      await Future<void>.delayed(Duration.zero);

      expect(binderContainer.read(localNotificationsProvider), isEmpty);
      expect(binderContainer.read(unseenNotificationsProvider), 0);
    });

    test('a burst of one kind is one row', () {
      // A sweep finishing forty downloads arrives as forty identical
      // completions.
      for (var i = 0; i < 40; i++) {
        local.recordDownloadCompleted();
      }
      expect(container.read(localNotificationsProvider), hasLength(1));
    });

    test('the badge counts what arrived since the bell was opened', () {
      local.recordDownloadCompleted();
      expect(local.unseen, 1);

      local.markSeen(container.read(notificationRowsProvider));
      expect(local.unseen, 0);

      local.recordDownloadCompleted(
        at: DateTime.now().add(const Duration(seconds: 1)),
      );
      expect(local.unseen, 1);
    });

    test('going where a row points is what clears it', () {
      local.recordDownloadCompleted(at: DateTime(2026, 8, 12, 9));

      // Somewhere else answers nothing.
      local.dismissUnder(WaxRoute.review);
      expect(container.read(localNotificationsProvider), hasLength(1));

      local.dismissUnder(WaxRoute.downloads);
      expect(container.read(localNotificationsProvider), isEmpty);
    });

    test('an entry under a surface answers the surface', () {
      // A reader deals with a row by opening something in the place it
      // points at, which is a location under it rather than the location
      // itself.
      local.recordDownloadCompleted();
      local.dismissUnder('${WaxRoute.downloads}/tr-1');
      expect(container.read(localNotificationsProvider), isEmpty);
    });

    test('a later event for the same thing is news again', () {
      local.recordDownloadCompleted();
      local.dismissUnder(WaxRoute.downloads);
      expect(container.read(localNotificationsProvider), isEmpty);

      // Somewhere else, and then it happens again: the reader has not
      // seen this one.
      local.dismissUnder(WaxRoute.home);
      local.recordDownloadCompleted();
      expect(container.read(localNotificationsProvider), hasLength(1));
    });

    test('news about the screen in front of you never lands', () {
      local.dismissUnder(WaxRoute.downloads);
      local.recordDownloadCompleted();
      expect(container.read(localNotificationsProvider), isEmpty);
      expect(local.unseen, 0);
    });

    test('news about the screen in front of you never lands, whatever query '
        'it carries', () {
      local.dismissUnder('${WaxRoute.downloads}?view=all');
      local.recordDownloadCompleted();
      expect(container.read(localNotificationsProvider), isEmpty);
    });

    // The router reports the query with the path, and a target that names
    // one is a view of its screen rather than the screen.
    test('a target naming a query is reached only where the location '
        'carries it', () {
      bool under(String location, String target) =>
          LocalNotifications.under(location, target);
      const requests = WaxRoute.userRequests;
      expect(under(requests, requests), isTrue);
      expect(under('$requests&from=bell', requests), isTrue);
      expect(under(WaxRoute.users, requests), isFalse);
      expect(under(WaxRoute.userInvites, requests), isFalse);
      expect(under(WaxRoute.userEdit, requests), isFalse);
      // A path-only target keeps its rule, whatever query the location
      // carries.
      expect(under(requests, WaxRoute.users), isTrue);
      expect(under('${WaxRoute.review}/rv-1?x=1', WaxRoute.review), isTrue);
      expect(under('${WaxRoute.review}er', WaxRoute.review), isFalse);
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
          .recordDownloadCompleted();
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
      expect(repo.inboxReadCalls, isEmpty, reason: 'named by event, not id');
      expect(
        repo.inboxEventReads.any(
          (c) => c.pid == 'pc-A' && c.events.contains('feed-disabled'),
        ),
        isTrue,
      );
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
          .recordDownloadCompleted();
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
      await other.read(authControllerProvider.future);
      other.read(localNotificationsProvider.notifier).recordDownloadCompleted();

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
    local.recordDownloadCompleted();
    expect(container.read(notificationsViewProvider).rows.single.read, isFalse);

    local.markSeen(container.read(notificationRowsProvider));
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
    // Kept alive so the rebuild below is observable rather than a fresh
    // read of a provider nobody was listening to.
    final alive = container.listen(localNotificationsProvider, (_, _) {});
    addTearDown(alive.close);

    await container.read(authControllerProvider.future);
    container
        .read(localNotificationsProvider.notifier)
        .recordDownloadCompleted();
    expect(container.read(localNotificationsProvider), hasLength(1));

    // Signing out and back in as somebody else: what the previous
    // session observed is not this one's.
    repo.signsIn = const WaxDeckUser(
      id: 'u-2',
      username: 'rosie',
      roles: <String>[],
    );
    final auth = container.read(authControllerProvider.notifier);
    await auth.logout();
    await auth.login(username: 'rosie', password: 'pw');
    expect(container.read(signedInAccountProvider), 'u-2');
    expect(container.read(localNotificationsProvider), isEmpty);
  });

  test("the binder announces this device's own finished transfers", () async {
    final downloads = FakeDownloads();
    final container = appContainer(
      downloads: downloads,
      extra: [
        // Web's shape: no engine, so the download listener has to be
        // registered before the puller branch returns.
        syncEngineProvider.overrideWithValue(null),
      ],
    );
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
          userId: 'us-ann',
          events: <ServerSyncEvent>[_marker('review')],
          nextSince: 'c1',
          more: true,
        ),
        ServerSyncPage(
          userId: 'us-ann',
          events: <ServerSyncEvent>[_marker('upload', pid: 'up-1')],
          nextSince: 'c2',
        ),
      ];
      await puller.pull();
      expect(seen.map((e) => e.kind), <String>['review', 'upload']);

      // And it resumes from where it stopped rather than re-reading.
      repo.pages = <ServerSyncPage>[
        const ServerSyncPage(
          userId: 'us-ann',
          events: <ServerSyncEvent>[],
          nextSince: 'c3',
        ),
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
          userId: 'us-ann',
          events: <ServerSyncEvent>[_marker('review')],
          nextSince: 'c1',
          more: true,
        ),
      ];
      repo.failAfter = 1;
      await puller.pull();
      expect(seen.map((e) => e.kind), <String>['review']);

      repo.pages = <ServerSyncPage>[
        const ServerSyncPage(
          userId: 'us-ann',
          events: <ServerSyncEvent>[],
          nextSince: 'c2',
        ),
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
          userId: 'us-ann',
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

    test(
      'a reset says the walk lost its place, and mints again at once',
      () async {
        // A change after the reset would otherwise wait for a hint whose
        // walk only mints, and go unreported too.
        final repo = _SyncRepository();
        final seen = <ServerSyncEvent>[];
        var resets = 0;
        final puller = UserEventPuller(
          repository: repo,
          onEvent: seen.add,
          onReset: () => resets++,
        );
        await puller.pull();

        repo.resetOnce = true;
        await puller.pull();
        expect(resets, 1);
        expect(repo.sinceCalls, <String?>[null, 'c0', null]);

        repo.pages = <ServerSyncPage>[
          ServerSyncPage(
            userId: 'us-ann',
            events: <ServerSyncEvent>[_marker('review')],
            nextSince: 'c1',
          ),
        ];
        await puller.pull();
        expect(seen.map((e) => e.kind), <String>['review']);
      },
    );

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
        const ServerSyncPage(
          userId: 'us-ann',
          events: <ServerSyncEvent>[],
          nextSince: 'fresh',
        ),
      ];
      await puller.pull();
      expect(repo.sinceCalls.last, isNull);
    });

    test('a page that answers for another account is dropped: nothing is '
        'reported, the cursor stays where it was, and the session is '
        'suspected; a page for the walk\'s own account goes on', () async {
      final repo = _SyncRepository();
      final seen = <ServerSyncEvent>[];
      var suspected = 0;
      final puller = UserEventPuller(
        repository: repo,
        onEvent: seen.add,
        account: 'us-ann',
        onAnotherAccount: () => suspected++,
      );
      await puller.pull();

      // The cookie another tab signed Ben in over: the walk reads his.
      repo.pages = <ServerSyncPage>[
        ServerSyncPage(
          userId: 'us-ben',
          events: <ServerSyncEvent>[_marker('account')],
          nextSince: 'c1',
          more: true,
        ),
      ];
      await puller.pull();
      expect(seen, isEmpty);
      expect(suspected, 1);

      repo.pages = <ServerSyncPage>[
        ServerSyncPage(
          userId: 'us-ann',
          events: <ServerSyncEvent>[_marker('review')],
          nextSince: 'c2',
        ),
      ];
      await puller.pull();
      expect(repo.sinceCalls, <String?>[null, 'c0', 'c0']);
      expect(seen.map((e) => e.kind), <String>['review']);
      expect(suspected, 1);
    });

    test('a mint that answers for another account takes no cursor', () async {
      final repo = _SyncRepository()..account = 'us-ben';
      var suspected = 0;
      final puller = UserEventPuller(
        repository: repo,
        onEvent: (_) {},
        account: 'us-ann',
        onAnotherAccount: () => suspected++,
      );
      await puller.pull();
      expect(suspected, 1);

      repo.account = 'us-ann';
      await puller.pull();
      expect(repo.sinceCalls, <String?>[null, null]);
    });
  });

  group('a row that counts and resolves', () {
    late FakeRepository repo;
    late ProviderContainer container;

    setUp(() async {
      repo = FakeRepository(
        sessionState: const SessionState(authenticated: true, user: _user),
      );
      container = _signedIn(repo);
      await container.read(authControllerProvider.future);
    });

    Future<NotificationsView> view() async {
      await container.read(notificationsProvider.future);
      return container.read(notificationsViewProvider);
    }

    test(
      'a count words a plural title, and one reads as the singular',
      () async {
        repo.inbox = <ServerNotification>[
          _inboxRow('review-ready', count: 3, at: _ago(1)),
          _inboxRow('review-ready', count: 1, at: _ago(2)),
          _inboxRow('import-completed', target: 'rv-1', count: 2, at: _ago(3)),
          _inboxRow('import-completed', target: 'rv-2', at: _ago(4)),
        ];
        final rows = (await view()).rows;
        final en = AppLocalizationsEn();
        final es = AppLocalizationsEs();
        expect(rows.map((r) => r.messageOf(en)), <String>[
          '3 waiting for review',
          'Waiting for review',
          '2 added to the library',
          'Added to the library',
        ]);
        expect(rows.map((r) => r.messageOf(es)), <String>[
          '3 pendientes de revisión',
          'Pendiente de revisión',
          '2 añadidos a la biblioteca',
          'Añadido a la biblioteca',
        ]);
      },
    );

    test(
      'a resolved queue row is worded as cleared and wears the check',
      () async {
        repo.inbox = <ServerNotification>[
          _inboxRow(
            'review-ready',
            count: 4,
            resolvedAt: DateTime.now(),
            at: _ago(1),
          ),
          _inboxRow(
            'signup-requested',
            resolvedAt: DateTime.now(),
            at: _ago(2),
          ),
          _inboxRow('review-ready', count: 2, at: _ago(3)),
          _inboxRow('signup-requested', at: _ago(4)),
        ];
        final rows = (await view()).rows;
        final en = AppLocalizationsEn();
        expect(rows.map((r) => r.messageOf(en)), <String>[
          'Review queue cleared',
          'Request decided',
          '2 waiting for review',
          'Account request',
        ]);
        expect(rows[0].glyph, WaxIcons.check);
        expect(rows[1].glyph, WaxIcons.check);
        // The check means done, so the rows still waiting wear another.
        expect(rows[2].glyph, isNot(WaxIcons.check));
        expect(rows[3].glyph, isNot(WaxIcons.check));
      },
    );

    test('a row resolved because its playlist went keeps its own glyph and '
        'words', () async {
      repo.inbox = <ServerNotification>[
        _inboxRow(
          'playlist-synced',
          target: 'pl-1',
          resolvedAt: DateTime.now(),
        ),
      ];
      final row = (await view()).rows.single;
      expect(row.resolved, isTrue);
      expect(row.glyph, NotificationKind.playlistSynced.glyph);
      expect(row.messageOf(AppLocalizationsEn()), 'Playlist synced');
    });

    test('a row shows and orders by its latest occurrence', () async {
      final old = DateTime.now().subtract(const Duration(days: 3));
      final latest = DateTime.now().subtract(const Duration(minutes: 1));
      repo.inbox = <ServerNotification>[
        ServerNotification(
          id: 'nf-counted',
          event: 'backup-completed',
          title: 't',
          body: 'b',
          createdAt: old,
          updatedAt: latest,
          count: 5,
        ),
        _inboxRow(
          'backup-failed',
          at: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      ];
      final rows = (await view()).rows;
      expect(rows.first.id, 'nf-counted');
      expect(rows.first.at, latest);
    });

    test('a keyed row that counted up is the same row', () async {
      final first = _inboxRow('review-ready', id: 'nf-keyed', count: 1);
      repo.inbox = <ServerNotification>[first];
      final before = (await view()).rows.single;

      repo.inbox = <ServerNotification>[
        ServerNotification(
          id: 'nf-keyed',
          event: 'review-ready',
          title: 't',
          body: 'b',
          createdAt: first.createdAt,
          updatedAt: first.updatedAt.add(const Duration(minutes: 5)),
          count: 3,
        ),
      ];
      container.invalidate(notificationsProvider);
      final after = (await view()).rows.single;

      expect(after.id, before.id);
      expect(after.semanticsId, before.semanticsId);
      expect(after.count, 3);
      expect(after.at.isAfter(before.at), isTrue);
    });

    // The bell draws a line a row, so two rows of one event have to say
    // something different: the count where it folded, the body where it
    // did not.
    test('the bell line is the count or the body, so rows differ', () async {
      repo.inbox = <ServerNotification>[
        _inboxRow(
          'review-ready',
          count: 3,
          body: 'The newest one',
          at: _ago(1),
        ),
        _inboxRow(
          'feed-disabled',
          target: 'pc-A',
          body: 'Alpha stopped refreshing',
          at: _ago(2),
        ),
        _inboxRow(
          'feed-disabled',
          target: 'pc-B',
          body: 'Beta stopped refreshing',
          at: _ago(3),
        ),
        _inboxRow('backup-failed', body: '', at: _ago(4)),
      ];
      final rows = (await view()).rows;
      final en = AppLocalizationsEn();
      expect(rows.map((r) => r.bellLineOf(en)), <String>[
        '3 waiting for review',
        'Alpha stopped refreshing',
        'Beta stopped refreshing',
        'Backup failed',
      ]);
    });

    test('Clear completed removes only the resolved rows', () async {
      repo.inbox = <ServerNotification>[
        _inboxRow('review-ready', resolvedAt: DateTime.now()),
        _inboxRow('signup-requested', resolvedAt: DateTime.now()),
        _inboxRow('backup-completed'),
        _inboxRow('backup-failed', readAt: DateTime.now()),
      ];
      final keep = repo.inbox.skip(2).map((r) => r.id).toSet();
      await view();
      await container.read(notificationsProvider.notifier).clearCompleted();

      final held = container.read(notificationsViewProvider);
      expect(held.rows.map((r) => r.id).toSet(), keep);
      expect(held.unreadInbox, 1);
      expect(repo.inboxClearedResolved, 1);
      expect(repo.inbox.map((r) => r.id).toSet(), keep);
    });

    // Visiting a destination settles its rows on the server too, which is
    // what reaches the ones past the page this client holds.
    test('visiting a destination marks its rows read by event', () async {
      repo.inbox = <ServerNotification>[
        _inboxRow('review-ready', count: 2),
        _inboxRow('backup-completed'),
      ];
      await view();
      container
          .read(notificationsProvider.notifier)
          .dismissUnder(WaxRoute.review);
      await Future<void>.delayed(Duration.zero);

      expect(repo.inboxEventReads, hasLength(1));
      expect(repo.inboxEventReads.single.events, contains('review-ready'));
      expect(
        repo.inboxEventReads.single.events,
        isNot(contains('backup-completed')),
      );
      expect(repo.inboxEventReads.single.pid, isNull);
      // The loaded row is covered by that call; ids and events never mix.
      expect(repo.inboxReadCalls, isEmpty);
      final held = container.read(notificationsViewProvider);
      expect(held.unreadInbox, 1);
      expect(
        held.rows.where((r) => r.read).single.kind,
        NotificationKind.reviewReady,
      );
    });

    test(
      'an entity a visit is at is named by pid, and only that one',
      () async {
        repo.inbox = <ServerNotification>[
          _inboxRow('feed-disabled', target: 'pc-A'),
          _inboxRow('feed-disabled', target: 'pc-B'),
        ];
        await view();
        container
            .read(notificationsProvider.notifier)
            .dismissUnder(WaxRoute.show('pc-A'));
        await Future<void>.delayed(Duration.zero);

        // The show's own news is named by its pid, and no call without one
        // reaches the other show's rows.
        final byPid = repo.inboxEventReads.where((c) => c.pid != null).single;
        expect(byPid.pid, 'pc-A');
        expect(byPid.events, contains('feed-disabled'));
        for (final call in repo.inboxEventReads.where((c) => c.pid == null)) {
          expect(call.events, isNot(contains('feed-disabled')));
        }
        final rows = container.read(notificationsViewProvider).rows;
        expect(rows.where((r) => r.read).map((r) => r.targetPid), <String?>[
          'pc-A',
        ]);
      },
    );

    // The body names the last entry; under "cleared" it would contradict.
    test('a resolved queue row has no server body under its wording', () async {
      repo.inbox = <ServerNotification>[
        _inboxRow(
          'review-ready',
          resolvedAt: DateTime.now(),
          body: 'The last entry',
          at: _ago(1),
        ),
        _inboxRow('review-ready', body: 'The newest entry', at: _ago(2)),
        _inboxRow(
          'playlist-synced',
          target: 'pl-1',
          resolvedAt: DateTime.now(),
          body: 'Two tracks moved',
          at: _ago(3),
        ),
      ];
      final rows = (await view()).rows;
      final en = AppLocalizationsEn();
      expect(rows[0].detailOf(en), isEmpty);
      expect(rows[1].detailOf(en), 'The newest entry');
      expect(
        rows[2].detailOf(en),
        'Two tracks moved',
        reason: 'only a queue that was answered drops its body',
      );
    });

    // A write that fails leaves the list and the badge guessing: the next
    // read is what puts them right.
    for (final (name, act)
        in <(String, Future<void> Function(NotificationsController, String))>[
          ('Clear completed', (n, _) => n.clearCompleted()),
          ('Clear', (n, _) => n.clear()),
          ('delete', (n, id) => n.delete(id)),
        ]) {
      test('a failed $name is read back from the server', () async {
        final failing = _FailingWrites(
          sessionState: const SessionState(authenticated: true, user: _user),
        );
        failing.inbox = <ServerNotification>[
          _inboxRow('review-ready', resolvedAt: DateTime.now(), at: _ago(1)),
          _inboxRow('backup-completed', at: _ago(2)),
        ];
        final other = _signedIn(failing);
        await other.read(authControllerProvider.future);
        await other.read(notificationsProvider.future);
        final id = failing.inbox.first.id;

        await act(other.read(notificationsProvider.notifier), id);
        await other.read(notificationsProvider.future);

        expect(failing.listCalls, 2, reason: 'the list was read again');
        final held = other.read(notificationsViewProvider);
        expect(held.rows, hasLength(2), reason: 'the server kept them');
        expect(held.unreadInbox, 2);
      });
    }

    // One by-event call settles everything of its events, hidden rows
    // included, so asking again for the same thing is noise.
    test(
      'the reach past the page is made once until the inbox changes',
      () async {
        final past = _PagedInbox(
          hiddenUnread: 120,
          keepHidden: true,
          sessionState: const SessionState(authenticated: true, user: _user),
        );
        final other = _signedIn(past);
        await other.read(authControllerProvider.future);
        await other.read(notificationsProvider.future);
        final notifier = other.read(notificationsProvider.notifier);

        notifier.dismissUnder(WaxRoute.review);
        await Future<void>.delayed(Duration.zero);
        await other.read(notificationsProvider.future);
        notifier.dismissUnder('${WaxRoute.review}?again=1');
        notifier.dismissUnder(WaxRoute.review);
        await Future<void>.delayed(Duration.zero);
        expect(past.inboxEventReads, hasLength(1));

        // A marker's refetch is the inbox changing.
        other.invalidate(notificationsProvider);
        await other.read(notificationsProvider.future);
        notifier.dismissUnder(WaxRoute.review);
        await Future<void>.delayed(Duration.zero);
        expect(past.inboxEventReads, hasLength(2));

        // So is Mark all read.
        await notifier.markAllRead();
        past.hiddenUnread = 120;
        other.invalidate(notificationsProvider);
        await other.read(notificationsProvider.future);
        notifier.dismissUnder(WaxRoute.review);
        await Future<void>.delayed(Duration.zero);
        expect(past.inboxEventReads, hasLength(3));
      },
    );

    // A refused call settled nothing, so the next visit asks again.
    test(
      'a refused reach past the page is asked again on the next visit',
      () async {
        final past = _PagedInbox(
          hiddenUnread: 120,
          keepHidden: true,
          sessionState: const SessionState(authenticated: true, user: _user),
        )..refuseEventReads = 1;
        final other = _signedIn(past);
        await other.read(authControllerProvider.future);
        await other.read(notificationsProvider.future);
        final notifier = other.read(notificationsProvider.notifier);

        notifier.dismissUnder(WaxRoute.review);
        await Future<void>.delayed(Duration.zero);
        await other.read(notificationsProvider.future);
        expect(past.inboxEventReads, isEmpty, reason: 'the call was refused');

        notifier.dismissUnder(WaxRoute.review);
        await Future<void>.delayed(Duration.zero);
        expect(past.inboxEventReads, hasLength(1));

        // Made, it is not made again.
        await other.read(notificationsProvider.future);
        notifier.dismissUnder(WaxRoute.review);
        await Future<void>.delayed(Duration.zero);
        expect(past.inboxEventReads, hasLength(1));
      },
    );

    test('a visit with nothing unread to settle sends nothing', () async {
      repo.inbox = <ServerNotification>[
        _inboxRow('review-ready', readAt: DateTime.now()),
      ];
      await view();
      container
          .read(notificationsProvider.notifier)
          .dismissUnder(WaxRoute.review);
      await Future<void>.delayed(Duration.zero);
      expect(repo.inboxEventReads, isEmpty);
      expect(repo.inboxReadCalls, isEmpty);
    });

    // The page holds fifty and the rest are unread on the server: the
    // visit reaches them, and the count is read back rather than guessed.
    test('rows past the page the client holds settle on a visit', () async {
      final past = _PagedInbox(
        hiddenUnread: 120,
        sessionState: const SessionState(authenticated: true, user: _user),
      );
      past.inbox = <ServerNotification>[
        _inboxRow('backup-completed', readAt: DateTime.now()),
      ];
      final other = _signedIn(past);
      await other.read(authControllerProvider.future);
      await other.read(notificationsProvider.future);
      expect(other.read(notificationsViewProvider).unreadInbox, 120);

      other.read(notificationsProvider.notifier).dismissUnder(WaxRoute.review);
      await Future<void>.delayed(Duration.zero);
      await other.read(notificationsProvider.future);

      expect(past.inboxEventReads, hasLength(1));
      expect(past.inboxEventReads.single.events, contains('review-ready'));
      expect(past.listCalls, 2, reason: 'the count is read back');
      expect(other.read(notificationsViewProvider).unreadInbox, 0);
    });
  });

  group('the notifications screen', () {
    late FakeRepository repo;
    late ProviderContainer container;

    Future<void> pump(WidgetTester tester, {Size? size}) async {
      tester.view.physicalSize = size ?? const Size(1000, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      repo = FakeRepository(
        sessionState: const SessionState(authenticated: true, user: _user),
      );
      container = appContainer(repo: repo);
    }

    Future<void> mount(WidgetTester tester) async {
      await pumpApp(tester, const NotificationsScreen(), container: container);
      await tester.pumpAndSettle();
    }

    String location(WidgetTester tester) =>
        GoRouter.of(tester.element(find.byType(NotificationsScreen)))
            .routerDelegate
            .currentConfiguration
            .uri
            .toString();

    Finder rowOf(ServerNotification row) => find.bySemanticsIdentifier(
      SemanticsIds.notificationRow(row.event, row.id),
    );

    testWidgets('a resolved review row does not navigate, and an unresolved '
        'one does', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      final done = _inboxRow('review-ready', resolvedAt: DateTime.now());
      final waiting = _inboxRow(
        'review-ready',
        count: 2,
        at: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      repo.inbox = <ServerNotification>[done, waiting];
      await mount(tester);
      final before = location(tester);

      // No tap to answer: the row is not offered as one.
      final doneNode = tester.getSemantics(rowOf(done));
      expect(
        doneNode.getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
      );
      await tester.tap(rowOf(done), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(location(tester), before);
      // Its delete is still there.
      expect(
        find.bySemanticsIdentifier(SemanticsIds.notificationDelete(done.id)),
        findsOneWidget,
      );

      final router = GoRouter.of(
        tester.element(find.byType(NotificationsScreen)),
      );
      await tester.tap(rowOf(waiting));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        WaxRoute.review,
      );
      handle.dispose();
    });

    for (final (name, size, narrow) in <(String, Size, bool)>[
      ('narrow', const Size(500, 1400), true),
      ('two-pane', const Size(1800, 1400), false),
    ]) {
      testWidgets('an import row opens its entry in the $name layout', (
        tester,
      ) async {
        await pump(tester, size: size);
        final entry = _inboxRow('import-completed', target: 'rv-1');
        repo.inbox = <ServerNotification>[entry];
        repo.reviewEntries = <ReviewEntry>[
          testReviewEntry('rv-1', status: 'approved', origin: 'upload'),
        ];
        repo.reviewEntryDetails['rv-1'] = ReviewEntryDetail(
          id: 'rv-1',
          kind: 'match',
          status: 'approved',
          mediaType: MediaType.music,
          origin: 'upload',
          trackCount: 1,
          createdAt: DateTime.utc(2026, 7, 1),
          title: 'Neon Meridian',
          artist: 'The Cardinal Waves',
        );
        await mount(tester);

        await tester.tap(
          find.bySemanticsIdentifier(
            SemanticsIds.notificationRow('import-completed', entry.id),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(NotificationsScreen), findsNothing);
        expect(find.byType(ReviewEntryView), findsOneWidget);
        expect(
          find.byType(ReviewEntryScreen),
          narrow ? findsOneWidget : findsNothing,
          reason: 'one pane is a page of its own; two sit beside the queue',
        );
      });
    }

    testWidgets('Clear completed shows only with a resolved row, and removes '
        'only those', (tester) async {
      await pump(tester);
      final waiting = _inboxRow('backup-completed');
      repo.inbox = <ServerNotification>[waiting];
      await mount(tester);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.notificationsClearCompleted),
        findsNothing,
      );

      final done = _inboxRow(
        'review-ready',
        resolvedAt: DateTime.now(),
        at: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      repo.inbox = <ServerNotification>[waiting, done];
      container.invalidate(notificationsProvider);
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.notificationsClearCompleted),
      );
      await tester.pumpAndSettle();

      expect(repo.inboxClearedResolved, 1);
      expect(rowOf(done), findsNothing);
      expect(rowOf(waiting), findsOneWidget);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.notificationsClearCompleted),
        findsNothing,
      );
    });

    testWidgets('an unread row is not announced as playing', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      final row = _inboxRow('backup-completed');
      repo.inbox = <ServerNotification>[row];
      await mount(tester);

      final label = tester.getSemantics(rowOf(row)).label;
      expect(label, isNot(contains('Playing')));
      expect(label, contains('Backup finished'));
      handle.dispose();
    });

    testWidgets('a row that counted up keeps its widget and says the count', (
      tester,
    ) async {
      await pump(tester);
      final first = _inboxRow('review-ready', id: 'nf-keyed');
      repo.inbox = <ServerNotification>[first];
      await mount(tester);
      final key = ValueKey(
        SemanticsIds.notificationRow('review-ready', 'nf-keyed'),
      );
      final before = tester.element(find.byKey(key));
      expect(find.text('Waiting for review'), findsOneWidget);

      repo.inbox = <ServerNotification>[
        ServerNotification(
          id: 'nf-keyed',
          event: 'review-ready',
          title: 't',
          body: 'b',
          createdAt: first.createdAt,
          updatedAt: first.updatedAt.add(const Duration(minutes: 5)),
          count: 3,
        ),
      ];
      container.invalidate(notificationsProvider);
      await tester.pumpAndSettle();

      expect(identical(tester.element(find.byKey(key)), before), isTrue);
      expect(find.text('3 waiting for review'), findsOneWidget);
      expect(find.text('Waiting for review'), findsNothing);
    });
  });

  // Through the real router: it is what reports where the visitor is, and
  // a location carrying a query is what a signup row points at.
  testWidgets('arriving at the signup requests marks a signup row read, and '
      'one that arrives while there', (tester) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _user),
    );
    final first = _inboxRow('signup-requested');
    repo.inbox = <ServerNotification>[first];
    final container = appContainer(repo: repo);
    await pumpWholeApp(tester, container: container);
    final router = container.read(routerProvider);
    // Held open, as the bell holds it.
    final inbox = container.listen(notificationsProvider, (_, _) {});
    addTearDown(inbox.close);
    await tester.pumpAndSettle();
    bool read(String id) => container
        .read(notificationsProvider)
        .value!
        .rows
        .singleWhere((row) => row.id == id)
        .read;

    // The users view is not the requests one.
    router.go(WaxRoute.users);
    await tester.pumpAndSettle();
    expect(read(first.id), isFalse);
    expect(repo.inboxEventReads, isEmpty);

    router.go(WaxRoute.userRequests);
    await tester.pumpAndSettle();
    expect(read(first.id), isTrue);
    expect(repo.inboxEventReads.map((c) => c.events), <List<String>>[
      <String>['signup-requested'],
    ]);

    final next = _inboxRow('signup-requested');
    repo.inbox = <ServerNotification>[next, ...repo.inbox];
    container.invalidate(notificationsProvider);
    await tester.pumpAndSettle();
    expect(read(next.id), isTrue);
    expect(repo.inboxEventReads, hasLength(2));
    expect(container.read(unseenNotificationsProvider), 0);
  });
}

/// A repository that answers the sync stream and records what it was
/// asked for.
class _SyncRepository extends FakeRepository {
  final List<String?> sinceCalls = <String?>[];

  /// The account the pages it makes up answer for.
  String account = 'us-ann';

  /// Pages to answer, consumed in order. An exhausted list answers an
  /// empty final page.
  List<ServerSyncPage> pages = <ServerSyncPage>[];

  WaxDeckApiException? failWith;

  /// Answers the next cursor-bearing read with `sync-reset`, once.
  bool resetOnce = false;

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
    if (resetOnce && since != null) {
      resetOnce = false;
      throw const WaxDeckApiException(
        code: 'sync-reset',
        message: 'cursor too old',
      );
    }
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
      return ServerSyncPage(
        userId: account,
        events: const <ServerSyncEvent>[],
        nextSince: 'c0',
      );
    }
    if (pages.isEmpty) {
      return ServerSyncPage(
        userId: account,
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

/// A repository whose inbox holds more unread rows than the page it
/// answers with, as one past the fifty the client reads does.
class _PagedInbox extends FakeRepository {
  _PagedInbox({
    required this.hiddenUnread,
    this.keepHidden = false,
    super.sessionState,
  });

  /// Unread rows on the server beyond the ones listed; a by-event
  /// mark-read settles them, unless [keepHidden] holds them there.
  int hiddenUnread;
  final bool keepHidden;
  int listCalls = 0;

  /// By-event calls to refuse before one goes through.
  int refuseEventReads = 0;

  @override
  Future<ServerNotificationPage> listMyNotifications({
    String? cursor,
    int? limit,
  }) async {
    listCalls++;
    final page = await super.listMyNotifications(cursor: cursor, limit: limit);
    return ServerNotificationPage(
      notifications: page.notifications,
      unreadCount: page.unreadCount + hiddenUnread,
    );
  }

  @override
  Future<void> markMyNotificationsRead({
    List<String> ids = const <String>[],
    List<String>? events,
    String? targetPid,
  }) async {
    if (events != null && events.isNotEmpty && refuseEventReads > 0) {
      refuseEventReads--;
      throw const WaxDeckApiException(
        code: 'transport',
        message: 'the server went away',
      );
    }
    await super.markMyNotificationsRead(
      ids: ids,
      events: events,
      targetPid: targetPid,
    );
    if (events != null && events.isNotEmpty && !keepHidden) hiddenUnread = 0;
  }
}

/// A repository whose inbox writes are refused, which the server does when
/// it is unreachable or the row is already gone.
class _FailingWrites extends FakeRepository {
  _FailingWrites({super.sessionState});

  int listCalls = 0;

  static const _refused = WaxDeckApiException(
    code: 'transport',
    message: 'the server went away',
  );

  @override
  Future<ServerNotificationPage> listMyNotifications({
    String? cursor,
    int? limit,
  }) {
    listCalls++;
    return super.listMyNotifications(cursor: cursor, limit: limit);
  }

  @override
  Future<void> clearMyNotifications({bool resolved = false}) async =>
      throw _refused;

  @override
  Future<void> deleteMyNotification(String id) async => throw _refused;
}
