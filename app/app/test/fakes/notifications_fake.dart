import 'dart:async';

import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// In-memory [NotificationsApi] for `FakeRepository`.
mixin FakeNotifications on FakeRepositoryState implements NotificationsApi {
  /// Push registrations served and mutated by the legacy push
  /// endpoints; rows mirror into [myNotificationTargets] as
  /// unifiedpush targets, like the server.
  final List<PushRegistration> pushRegistrations = [];

  @override
  Future<List<PushRegistration>> listPushRegistrations() async =>
      List.of(pushRegistrations);

  @override
  Future<PushRegistration> createPushRegistration({
    required String endpoint,
    String? label,
  }) async {
    final reg = PushRegistration(
      pid: 'nt-FAKEUP${pushRegistrations.length}',
      endpoint: endpoint,
      label: label,
      createdAt: DateTime.utc(2026),
    );
    pushRegistrations.add(reg);
    myNotificationTargets.add(
      NotificationTarget(
        pid: reg.pid,
        kind: 'unifiedpush',
        scope: 'user',
        label: label,
        config: {'endpoint': endpoint},
        enabledEvents: const ['episode-downloaded', 'feed-disabled'],
        createdAt: reg.createdAt,
      ),
    );
    return reg;
  }

  @override
  Future<void> deletePushRegistration(String pid) async {
    pushRegistrations.removeWhere((r) => r.pid == pid);
    myNotificationTargets.removeWhere((t) => t.pid == pid);
  }

  /// The notification event catalog, server scope first.
  List<NotifyEvent> notifyEvents = const [
    NotifyEvent(
      name: 'signup-requested',
      scope: 'server',
      description: 'A new account request is waiting for approval.',
    ),
    NotifyEvent(
      name: 'backup-completed',
      scope: 'server',
      description: 'A backup archive finished building.',
    ),
    NotifyEvent(
      name: 'episode-downloaded',
      scope: 'user',
      description: 'A new episode finished downloading.',
    ),
    NotifyEvent(
      name: 'feed-disabled',
      scope: 'user',
      description: 'A subscribed feed kept failing and was disabled.',
    ),
  ];

  /// Notification targets per scope, plus per-pid test counts.
  final List<NotificationTarget> serverNotificationTargets = [];
  final List<NotificationTarget> myNotificationTargets = [];
  final Map<String, int> notificationTargetTests = {};
  var _notificationTargetSeq = 0;

  /// When set, target saves throw this (the server-rejection path).
  WaxDeckApiException? notificationTargetError;

  @override
  Future<List<NotifyEvent>> listNotificationEvents() async =>
      List.of(notifyEvents);

  NotificationTarget _storeTarget(
    List<NotificationTarget> into, {
    required String scope,
    required String kind,
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
    bool muted = false,
    int minIntervalSeconds = 0,
  }) {
    final target = NotificationTarget(
      pid: 'nt-FAKE${_notificationTargetSeq++}',
      kind: kind,
      scope: scope,
      label: label,
      config: Map.of(config),
      enabledEvents: List.of(enabledEvents),
      muted: muted,
      minIntervalSeconds: minIntervalSeconds,
      createdAt: DateTime.utc(2026),
    );
    into.insert(0, target);
    return target;
  }

  NotificationTarget _replaceTarget(
    List<NotificationTarget> into,
    String pid, {
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
    bool muted = false,
    int minIntervalSeconds = 0,
  }) {
    final index = into.indexWhere((t) => t.pid == pid);
    if (index < 0) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no notification target',
        statusCode: 404,
      );
    }
    final old = into[index];
    final updated = NotificationTarget(
      pid: old.pid,
      kind: old.kind,
      scope: old.scope,
      label: label,
      config: Map.of(config),
      enabledEvents: List.of(enabledEvents),
      muted: muted,
      minIntervalSeconds: minIntervalSeconds,
      createdAt: old.createdAt,
      lastSuccessAt: old.lastSuccessAt,
      lastError: old.lastError,
      lastErrorAt: old.lastErrorAt,
    );
    into[index] = updated;
    return updated;
  }

  @override
  Future<List<NotificationTarget>> listServerNotificationTargets() async =>
      List.of(serverNotificationTargets);

  @override
  Future<NotificationTarget> createServerNotificationTarget({
    required String kind,
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
    bool muted = false,
    int minIntervalSeconds = 0,
  }) async {
    if (notificationTargetError != null) throw notificationTargetError!;
    return _storeTarget(
      serverNotificationTargets,
      scope: 'server',
      kind: kind,
      label: label,
      config: config,
      enabledEvents: enabledEvents,
      muted: muted,
      minIntervalSeconds: minIntervalSeconds,
    );
  }

  @override
  Future<NotificationTarget> updateServerNotificationTarget({
    required String pid,
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
    bool muted = false,
    int minIntervalSeconds = 0,
  }) async {
    if (notificationTargetError != null) throw notificationTargetError!;
    return _replaceTarget(
      serverNotificationTargets,
      pid,
      label: label,
      config: config,
      enabledEvents: enabledEvents,
      muted: muted,
      minIntervalSeconds: minIntervalSeconds,
    );
  }

  @override
  Future<void> deleteServerNotificationTarget(String pid) async {
    serverNotificationTargets.removeWhere((t) => t.pid == pid);
  }

  @override
  Future<void> testServerNotificationTarget(String pid) async {
    notificationTargetTests[pid] = (notificationTargetTests[pid] ?? 0) + 1;
  }

  @override
  Future<List<NotificationTarget>> listMyNotificationTargets() async =>
      List.of(myNotificationTargets);

  @override
  Future<NotificationTarget> createMyNotificationTarget({
    required String kind,
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
    bool muted = false,
    int minIntervalSeconds = 0,
  }) async {
    if (notificationTargetError != null) throw notificationTargetError!;
    return _storeTarget(
      myNotificationTargets,
      scope: 'user',
      kind: kind,
      label: label,
      config: config,
      enabledEvents: enabledEvents,
      muted: muted,
      minIntervalSeconds: minIntervalSeconds,
    );
  }

  @override
  Future<NotificationTarget> updateMyNotificationTarget({
    required String pid,
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
    bool muted = false,
    int minIntervalSeconds = 0,
  }) async {
    if (notificationTargetError != null) throw notificationTargetError!;
    return _replaceTarget(
      myNotificationTargets,
      pid,
      label: label,
      config: config,
      enabledEvents: enabledEvents,
      muted: muted,
      minIntervalSeconds: minIntervalSeconds,
    );
  }

  @override
  Future<void> deleteMyNotificationTarget(String pid) async {
    myNotificationTargets.removeWhere((t) => t.pid == pid);
  }

  @override
  Future<void> testMyNotificationTarget(String pid) async {
    notificationTargetTests[pid] = (notificationTargetTests[pid] ?? 0) + 1;
    onNotificationTargetTest?.call(pid);
  }

  /// Runs after a target test is queued, standing in for the delivery
  /// landing on the target's health fields.
  void Function(String pid)? onNotificationTargetTest;

  /// The notification inbox, newest first, as the server would hold it.
  List<ServerNotification> inbox = <ServerNotification>[];

  /// Every id list `markMyNotificationsRead` was called with; an empty
  /// list is the mark-everything call.
  final List<List<String>> inboxReadCalls = <List<String>>[];
  final List<String> inboxDeleted = <String>[];
  int inboxCleared = 0;

  /// Thrown by the next inbox read, for the offline peek.
  WaxDeckApiException? inboxError;

  /// Held open, so a test can land a write mid-read.
  Completer<void>? inboxHold;

  @override
  Future<ServerNotificationPage> listMyNotifications({
    String? cursor,
    int? limit,
  }) async {
    final held = inboxHold;
    if (held != null) await held.future;
    final failure = inboxError;
    if (failure != null) throw failure;
    return ServerNotificationPage(
      notifications: List<ServerNotification>.of(inbox),
      unreadCount: inbox.where((n) => !n.read).length,
    );
  }

  @override
  Future<void> markMyNotificationsRead({
    List<String> ids = const <String>[],
  }) async {
    inboxReadCalls.add(List<String>.of(ids));
    final at = DateTime.now();
    inbox = <ServerNotification>[
      for (final row in inbox)
        if (row.read || (ids.isNotEmpty && !ids.contains(row.id)))
          row
        else
          ServerNotification(
            id: row.id,
            event: row.event,
            title: row.title,
            body: row.body,
            targetPid: row.targetPid,
            createdAt: row.createdAt,
            readAt: at,
          ),
    ];
  }

  @override
  Future<void> deleteMyNotification(String id) async {
    inboxDeleted.add(id);
    inbox = <ServerNotification>[
      for (final row in inbox)
        if (row.id != id) row,
    ];
  }

  @override
  Future<void> clearMyNotifications() async {
    inboxCleared++;
    inbox = <ServerNotification>[];
  }
}
