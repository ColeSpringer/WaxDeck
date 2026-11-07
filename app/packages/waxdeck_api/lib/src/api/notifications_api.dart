import '../models.dart';

/// Push registrations, notification targets and the in-app inbox.
abstract interface class NotificationsApi {
  /// `GET /users/me/push-registrations`: the caller's UnifiedPush
  /// registrations.
  Future<List<PushRegistration>> listPushRegistrations();

  /// `POST /users/me/push-registrations`: registers a UnifiedPush
  /// endpoint.
  Future<PushRegistration> createPushRegistration({
    required String endpoint,
    String? label,
  });

  /// `DELETE /users/me/push-registrations/{id}`: removes one
  /// registration.
  Future<void> deletePushRegistration(String pid);

  /// `GET /notifications/events`: the event catalog for the
  /// per-target checklist.
  Future<List<NotifyEvent>> listNotificationEvents();

  /// `GET /admin/notification-targets`: the server-scope targets
  /// (administrators).
  Future<List<NotificationTarget>> listServerNotificationTargets();

  /// `POST /admin/notification-targets`: creates a server-scope
  /// target (administrators).
  Future<NotificationTarget> createServerNotificationTarget({
    required String kind,
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
    bool muted = false,
    int minIntervalSeconds = 0,
  });

  /// `PUT /admin/notification-targets/{id}`: replaces a server-scope
  /// target's label, config, and events (administrators).
  Future<NotificationTarget> updateServerNotificationTarget({
    required String pid,
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
    bool muted = false,
    int minIntervalSeconds = 0,
  });

  /// `DELETE /admin/notification-targets/{id}` (administrators).
  Future<void> deleteServerNotificationTarget(String pid);

  /// `POST /admin/notification-targets/{id}/test`: queues one test
  /// delivery; the outcome lands on the target's health fields
  /// (administrators).
  Future<void> testServerNotificationTarget(String pid);

  /// `GET /users/me/notification-targets`: the caller's personal
  /// targets.
  Future<List<NotificationTarget>> listMyNotificationTargets();

  /// `POST /users/me/notification-targets`: creates a personal
  /// target.
  Future<NotificationTarget> createMyNotificationTarget({
    required String kind,
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
    bool muted = false,
    int minIntervalSeconds = 0,
  });

  /// `PUT /users/me/notification-targets/{id}`: replaces a personal
  /// target's label, config, and events.
  Future<NotificationTarget> updateMyNotificationTarget({
    required String pid,
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
    bool muted = false,
    int minIntervalSeconds = 0,
  });

  /// `DELETE /users/me/notification-targets/{id}`.
  Future<void> deleteMyNotificationTarget(String pid);

  /// `POST /users/me/notification-targets/{id}/test`: queues one test
  /// delivery; the outcome lands on the target's health fields.
  Future<void> testMyNotificationTarget(String pid);

  /// `GET /users/me/notifications`: one page of the inbox, newest
  /// first. Written on every emit, so it is what happened to this
  /// account whether or not a delivery target carried it anywhere.
  Future<ServerNotificationPage> listMyNotifications({
    String? cursor,
    int? limit,
  });

  /// `POST /users/me/notifications/read`: stamps the named rows read,
  /// or every unread row when [ids] is empty.
  Future<void> markMyNotificationsRead({List<String> ids = const <String>[]});

  /// `DELETE /users/me/notifications/{id}`: removes one row.
  Future<void> deleteMyNotification(String id);

  /// `DELETE /users/me/notifications`: empties the inbox.
  Future<void> clearMyNotifications();
}
