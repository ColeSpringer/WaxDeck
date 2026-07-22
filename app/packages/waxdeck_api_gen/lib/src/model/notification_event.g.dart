// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_event.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$NotificationEvent extends NotificationEvent {
  @override
  final String name;
  @override
  final NotificationScope scope;
  @override
  final String description;

  factory _$NotificationEvent([
    void Function(NotificationEventBuilder)? updates,
  ]) => (NotificationEventBuilder()..update(updates))._build();

  _$NotificationEvent._({
    required this.name,
    required this.scope,
    required this.description,
  }) : super._();
  @override
  NotificationEvent rebuild(void Function(NotificationEventBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  NotificationEventBuilder toBuilder() =>
      NotificationEventBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is NotificationEvent &&
        name == other.name &&
        scope == other.scope &&
        description == other.description;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, scope.hashCode);
    _$hash = $jc(_$hash, description.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'NotificationEvent')
          ..add('name', name)
          ..add('scope', scope)
          ..add('description', description))
        .toString();
  }
}

class NotificationEventBuilder
    implements Builder<NotificationEvent, NotificationEventBuilder> {
  _$NotificationEvent? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  NotificationScope? _scope;
  NotificationScope? get scope => _$this._scope;
  set scope(NotificationScope? scope) => _$this._scope = scope;

  String? _description;
  String? get description => _$this._description;
  set description(String? description) => _$this._description = description;

  NotificationEventBuilder() {
    NotificationEvent._defaults(this);
  }

  NotificationEventBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _scope = $v.scope;
      _description = $v.description;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(NotificationEvent other) {
    _$v = other as _$NotificationEvent;
  }

  @override
  void update(void Function(NotificationEventBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  NotificationEvent build() => _build();

  _$NotificationEvent _build() {
    final _$result =
        _$v ??
        _$NotificationEvent._(
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'NotificationEvent',
            'name',
          ),
          scope: BuiltValueNullFieldError.checkNotNull(
            scope,
            r'NotificationEvent',
            'scope',
          ),
          description: BuiltValueNullFieldError.checkNotNull(
            description,
            r'NotificationEvent',
            'description',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
