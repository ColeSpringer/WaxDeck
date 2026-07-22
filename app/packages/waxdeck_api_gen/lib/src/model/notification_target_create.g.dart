// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_target_create.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$NotificationTargetCreate extends NotificationTargetCreate {
  @override
  final NotificationTargetKind kind;
  @override
  final String? label;
  @override
  final BuiltMap<String, JsonObject?> config;
  @override
  final BuiltList<String> enabledEvents;

  factory _$NotificationTargetCreate([
    void Function(NotificationTargetCreateBuilder)? updates,
  ]) => (NotificationTargetCreateBuilder()..update(updates))._build();

  _$NotificationTargetCreate._({
    required this.kind,
    this.label,
    required this.config,
    required this.enabledEvents,
  }) : super._();
  @override
  NotificationTargetCreate rebuild(
    void Function(NotificationTargetCreateBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  NotificationTargetCreateBuilder toBuilder() =>
      NotificationTargetCreateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is NotificationTargetCreate &&
        kind == other.kind &&
        label == other.label &&
        config == other.config &&
        enabledEvents == other.enabledEvents;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, label.hashCode);
    _$hash = $jc(_$hash, config.hashCode);
    _$hash = $jc(_$hash, enabledEvents.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'NotificationTargetCreate')
          ..add('kind', kind)
          ..add('label', label)
          ..add('config', config)
          ..add('enabledEvents', enabledEvents))
        .toString();
  }
}

class NotificationTargetCreateBuilder
    implements
        Builder<NotificationTargetCreate, NotificationTargetCreateBuilder> {
  _$NotificationTargetCreate? _$v;

  NotificationTargetKind? _kind;
  NotificationTargetKind? get kind => _$this._kind;
  set kind(NotificationTargetKind? kind) => _$this._kind = kind;

  String? _label;
  String? get label => _$this._label;
  set label(String? label) => _$this._label = label;

  MapBuilder<String, JsonObject?>? _config;
  MapBuilder<String, JsonObject?> get config =>
      _$this._config ??= MapBuilder<String, JsonObject?>();
  set config(MapBuilder<String, JsonObject?>? config) =>
      _$this._config = config;

  ListBuilder<String>? _enabledEvents;
  ListBuilder<String> get enabledEvents =>
      _$this._enabledEvents ??= ListBuilder<String>();
  set enabledEvents(ListBuilder<String>? enabledEvents) =>
      _$this._enabledEvents = enabledEvents;

  NotificationTargetCreateBuilder() {
    NotificationTargetCreate._defaults(this);
  }

  NotificationTargetCreateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _kind = $v.kind;
      _label = $v.label;
      _config = $v.config.toBuilder();
      _enabledEvents = $v.enabledEvents.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(NotificationTargetCreate other) {
    _$v = other as _$NotificationTargetCreate;
  }

  @override
  void update(void Function(NotificationTargetCreateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  NotificationTargetCreate build() => _build();

  _$NotificationTargetCreate _build() {
    _$NotificationTargetCreate _$result;
    try {
      _$result =
          _$v ??
          _$NotificationTargetCreate._(
            kind: BuiltValueNullFieldError.checkNotNull(
              kind,
              r'NotificationTargetCreate',
              'kind',
            ),
            label: label,
            config: config.build(),
            enabledEvents: enabledEvents.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'config';
        config.build();
        _$failedField = 'enabledEvents';
        enabledEvents.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'NotificationTargetCreate',
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
