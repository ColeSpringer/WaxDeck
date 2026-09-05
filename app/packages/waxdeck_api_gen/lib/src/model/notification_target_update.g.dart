// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_target_update.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$NotificationTargetUpdate extends NotificationTargetUpdate {
  @override
  final String? label;
  @override
  final BuiltMap<String, JsonObject?> config;
  @override
  final BuiltList<String> enabledEvents;
  @override
  final bool? muted;
  @override
  final int? minIntervalSeconds;

  factory _$NotificationTargetUpdate([
    void Function(NotificationTargetUpdateBuilder)? updates,
  ]) => (NotificationTargetUpdateBuilder()..update(updates))._build();

  _$NotificationTargetUpdate._({
    this.label,
    required this.config,
    required this.enabledEvents,
    this.muted,
    this.minIntervalSeconds,
  }) : super._();
  @override
  NotificationTargetUpdate rebuild(
    void Function(NotificationTargetUpdateBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  NotificationTargetUpdateBuilder toBuilder() =>
      NotificationTargetUpdateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is NotificationTargetUpdate &&
        label == other.label &&
        config == other.config &&
        enabledEvents == other.enabledEvents &&
        muted == other.muted &&
        minIntervalSeconds == other.minIntervalSeconds;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, label.hashCode);
    _$hash = $jc(_$hash, config.hashCode);
    _$hash = $jc(_$hash, enabledEvents.hashCode);
    _$hash = $jc(_$hash, muted.hashCode);
    _$hash = $jc(_$hash, minIntervalSeconds.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'NotificationTargetUpdate')
          ..add('label', label)
          ..add('config', config)
          ..add('enabledEvents', enabledEvents)
          ..add('muted', muted)
          ..add('minIntervalSeconds', minIntervalSeconds))
        .toString();
  }
}

class NotificationTargetUpdateBuilder
    implements
        Builder<NotificationTargetUpdate, NotificationTargetUpdateBuilder> {
  _$NotificationTargetUpdate? _$v;

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

  bool? _muted;
  bool? get muted => _$this._muted;
  set muted(bool? muted) => _$this._muted = muted;

  int? _minIntervalSeconds;
  int? get minIntervalSeconds => _$this._minIntervalSeconds;
  set minIntervalSeconds(int? minIntervalSeconds) =>
      _$this._minIntervalSeconds = minIntervalSeconds;

  NotificationTargetUpdateBuilder() {
    NotificationTargetUpdate._defaults(this);
  }

  NotificationTargetUpdateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _label = $v.label;
      _config = $v.config.toBuilder();
      _enabledEvents = $v.enabledEvents.toBuilder();
      _muted = $v.muted;
      _minIntervalSeconds = $v.minIntervalSeconds;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(NotificationTargetUpdate other) {
    _$v = other as _$NotificationTargetUpdate;
  }

  @override
  void update(void Function(NotificationTargetUpdateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  NotificationTargetUpdate build() => _build();

  _$NotificationTargetUpdate _build() {
    _$NotificationTargetUpdate _$result;
    try {
      _$result =
          _$v ??
          _$NotificationTargetUpdate._(
            label: label,
            config: config.build(),
            enabledEvents: enabledEvents.build(),
            muted: muted,
            minIntervalSeconds: minIntervalSeconds,
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
          r'NotificationTargetUpdate',
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
