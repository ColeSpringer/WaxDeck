// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_page.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$NotificationPage extends NotificationPage {
  @override
  final BuiltList<Notification> notifications;
  @override
  final String? nextCursor;
  @override
  final int unreadCount;

  factory _$NotificationPage([
    void Function(NotificationPageBuilder)? updates,
  ]) => (NotificationPageBuilder()..update(updates))._build();

  _$NotificationPage._({
    required this.notifications,
    this.nextCursor,
    required this.unreadCount,
  }) : super._();
  @override
  NotificationPage rebuild(void Function(NotificationPageBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  NotificationPageBuilder toBuilder() =>
      NotificationPageBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is NotificationPage &&
        notifications == other.notifications &&
        nextCursor == other.nextCursor &&
        unreadCount == other.unreadCount;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, notifications.hashCode);
    _$hash = $jc(_$hash, nextCursor.hashCode);
    _$hash = $jc(_$hash, unreadCount.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'NotificationPage')
          ..add('notifications', notifications)
          ..add('nextCursor', nextCursor)
          ..add('unreadCount', unreadCount))
        .toString();
  }
}

class NotificationPageBuilder
    implements Builder<NotificationPage, NotificationPageBuilder> {
  _$NotificationPage? _$v;

  ListBuilder<Notification>? _notifications;
  ListBuilder<Notification> get notifications =>
      _$this._notifications ??= ListBuilder<Notification>();
  set notifications(ListBuilder<Notification>? notifications) =>
      _$this._notifications = notifications;

  String? _nextCursor;
  String? get nextCursor => _$this._nextCursor;
  set nextCursor(String? nextCursor) => _$this._nextCursor = nextCursor;

  int? _unreadCount;
  int? get unreadCount => _$this._unreadCount;
  set unreadCount(int? unreadCount) => _$this._unreadCount = unreadCount;

  NotificationPageBuilder() {
    NotificationPage._defaults(this);
  }

  NotificationPageBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _notifications = $v.notifications.toBuilder();
      _nextCursor = $v.nextCursor;
      _unreadCount = $v.unreadCount;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(NotificationPage other) {
    _$v = other as _$NotificationPage;
  }

  @override
  void update(void Function(NotificationPageBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  NotificationPage build() => _build();

  _$NotificationPage _build() {
    _$NotificationPage _$result;
    try {
      _$result =
          _$v ??
          _$NotificationPage._(
            notifications: notifications.build(),
            nextCursor: nextCursor,
            unreadCount: BuiltValueNullFieldError.checkNotNull(
              unreadCount,
              r'NotificationPage',
              'unreadCount',
            ),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'notifications';
        notifications.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'NotificationPage',
          _$failedField,
          e.toString(),
        );
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
