// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_event_list.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$NotificationEventList extends NotificationEventList {
  @override
  final BuiltList<NotificationEvent> events;

  factory _$NotificationEventList([
    void Function(NotificationEventListBuilder)? updates,
  ]) => (NotificationEventListBuilder()..update(updates))._build();

  _$NotificationEventList._({required this.events}) : super._();
  @override
  NotificationEventList rebuild(
    void Function(NotificationEventListBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  NotificationEventListBuilder toBuilder() =>
      NotificationEventListBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is NotificationEventList && events == other.events;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, events.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'NotificationEventList',
    )..add('events', events)).toString();
  }
}

class NotificationEventListBuilder
    implements Builder<NotificationEventList, NotificationEventListBuilder> {
  _$NotificationEventList? _$v;

  ListBuilder<NotificationEvent>? _events;
  ListBuilder<NotificationEvent> get events =>
      _$this._events ??= ListBuilder<NotificationEvent>();
  set events(ListBuilder<NotificationEvent>? events) => _$this._events = events;

  NotificationEventListBuilder() {
    NotificationEventList._defaults(this);
  }

  NotificationEventListBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _events = $v.events.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(NotificationEventList other) {
    _$v = other as _$NotificationEventList;
  }

  @override
  void update(void Function(NotificationEventListBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  NotificationEventList build() => _build();

  _$NotificationEventList _build() {
    _$NotificationEventList _$result;
    try {
      _$result = _$v ?? _$NotificationEventList._(events: events.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'events';
        events.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'NotificationEventList',
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
