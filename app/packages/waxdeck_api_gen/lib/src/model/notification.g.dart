// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Notification extends Notification {
  @override
  final String id;
  @override
  final String event;
  @override
  final String title;
  @override
  final String body;
  @override
  final String? targetPid;
  @override
  final DateTime createdAt;
  @override
  final DateTime? readAt;

  factory _$Notification([void Function(NotificationBuilder)? updates]) =>
      (NotificationBuilder()..update(updates))._build();

  _$Notification._({
    required this.id,
    required this.event,
    required this.title,
    required this.body,
    this.targetPid,
    required this.createdAt,
    this.readAt,
  }) : super._();
  @override
  Notification rebuild(void Function(NotificationBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  NotificationBuilder toBuilder() => NotificationBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Notification &&
        id == other.id &&
        event == other.event &&
        title == other.title &&
        body == other.body &&
        targetPid == other.targetPid &&
        createdAt == other.createdAt &&
        readAt == other.readAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, event.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, body.hashCode);
    _$hash = $jc(_$hash, targetPid.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, readAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Notification')
          ..add('id', id)
          ..add('event', event)
          ..add('title', title)
          ..add('body', body)
          ..add('targetPid', targetPid)
          ..add('createdAt', createdAt)
          ..add('readAt', readAt))
        .toString();
  }
}

class NotificationBuilder
    implements Builder<Notification, NotificationBuilder> {
  _$Notification? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _event;
  String? get event => _$this._event;
  set event(String? event) => _$this._event = event;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _body;
  String? get body => _$this._body;
  set body(String? body) => _$this._body = body;

  String? _targetPid;
  String? get targetPid => _$this._targetPid;
  set targetPid(String? targetPid) => _$this._targetPid = targetPid;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  DateTime? _readAt;
  DateTime? get readAt => _$this._readAt;
  set readAt(DateTime? readAt) => _$this._readAt = readAt;

  NotificationBuilder() {
    Notification._defaults(this);
  }

  NotificationBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _event = $v.event;
      _title = $v.title;
      _body = $v.body;
      _targetPid = $v.targetPid;
      _createdAt = $v.createdAt;
      _readAt = $v.readAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Notification other) {
    _$v = other as _$Notification;
  }

  @override
  void update(void Function(NotificationBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Notification build() => _build();

  _$Notification _build() {
    final _$result =
        _$v ??
        _$Notification._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'Notification', 'id'),
          event: BuiltValueNullFieldError.checkNotNull(
            event,
            r'Notification',
            'event',
          ),
          title: BuiltValueNullFieldError.checkNotNull(
            title,
            r'Notification',
            'title',
          ),
          body: BuiltValueNullFieldError.checkNotNull(
            body,
            r'Notification',
            'body',
          ),
          targetPid: targetPid,
          createdAt: BuiltValueNullFieldError.checkNotNull(
            createdAt,
            r'Notification',
            'createdAt',
          ),
          readAt: readAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
