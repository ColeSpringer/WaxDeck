// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_target.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$NotificationTarget extends NotificationTarget {
  @override
  final String pid;
  @override
  final NotificationTargetKind kind;
  @override
  final NotificationScope scope;
  @override
  final String? label;
  @override
  final BuiltMap<String, JsonObject?> config;
  @override
  final BuiltList<String> enabledEvents;
  @override
  final DateTime? lastSuccessAt;
  @override
  final String? lastError;
  @override
  final DateTime? lastErrorAt;
  @override
  final bool? muted;
  @override
  final int? minIntervalSeconds;
  @override
  final DateTime createdAt;

  factory _$NotificationTarget([
    void Function(NotificationTargetBuilder)? updates,
  ]) => (NotificationTargetBuilder()..update(updates))._build();

  _$NotificationTarget._({
    required this.pid,
    required this.kind,
    required this.scope,
    this.label,
    required this.config,
    required this.enabledEvents,
    this.lastSuccessAt,
    this.lastError,
    this.lastErrorAt,
    this.muted,
    this.minIntervalSeconds,
    required this.createdAt,
  }) : super._();
  @override
  NotificationTarget rebuild(
    void Function(NotificationTargetBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  NotificationTargetBuilder toBuilder() =>
      NotificationTargetBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is NotificationTarget &&
        pid == other.pid &&
        kind == other.kind &&
        scope == other.scope &&
        label == other.label &&
        config == other.config &&
        enabledEvents == other.enabledEvents &&
        lastSuccessAt == other.lastSuccessAt &&
        lastError == other.lastError &&
        lastErrorAt == other.lastErrorAt &&
        muted == other.muted &&
        minIntervalSeconds == other.minIntervalSeconds &&
        createdAt == other.createdAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, scope.hashCode);
    _$hash = $jc(_$hash, label.hashCode);
    _$hash = $jc(_$hash, config.hashCode);
    _$hash = $jc(_$hash, enabledEvents.hashCode);
    _$hash = $jc(_$hash, lastSuccessAt.hashCode);
    _$hash = $jc(_$hash, lastError.hashCode);
    _$hash = $jc(_$hash, lastErrorAt.hashCode);
    _$hash = $jc(_$hash, muted.hashCode);
    _$hash = $jc(_$hash, minIntervalSeconds.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'NotificationTarget')
          ..add('pid', pid)
          ..add('kind', kind)
          ..add('scope', scope)
          ..add('label', label)
          ..add('config', config)
          ..add('enabledEvents', enabledEvents)
          ..add('lastSuccessAt', lastSuccessAt)
          ..add('lastError', lastError)
          ..add('lastErrorAt', lastErrorAt)
          ..add('muted', muted)
          ..add('minIntervalSeconds', minIntervalSeconds)
          ..add('createdAt', createdAt))
        .toString();
  }
}

class NotificationTargetBuilder
    implements Builder<NotificationTarget, NotificationTargetBuilder> {
  _$NotificationTarget? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  NotificationTargetKind? _kind;
  NotificationTargetKind? get kind => _$this._kind;
  set kind(NotificationTargetKind? kind) => _$this._kind = kind;

  NotificationScope? _scope;
  NotificationScope? get scope => _$this._scope;
  set scope(NotificationScope? scope) => _$this._scope = scope;

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

  DateTime? _lastSuccessAt;
  DateTime? get lastSuccessAt => _$this._lastSuccessAt;
  set lastSuccessAt(DateTime? lastSuccessAt) =>
      _$this._lastSuccessAt = lastSuccessAt;

  String? _lastError;
  String? get lastError => _$this._lastError;
  set lastError(String? lastError) => _$this._lastError = lastError;

  DateTime? _lastErrorAt;
  DateTime? get lastErrorAt => _$this._lastErrorAt;
  set lastErrorAt(DateTime? lastErrorAt) => _$this._lastErrorAt = lastErrorAt;

  bool? _muted;
  bool? get muted => _$this._muted;
  set muted(bool? muted) => _$this._muted = muted;

  int? _minIntervalSeconds;
  int? get minIntervalSeconds => _$this._minIntervalSeconds;
  set minIntervalSeconds(int? minIntervalSeconds) =>
      _$this._minIntervalSeconds = minIntervalSeconds;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  NotificationTargetBuilder() {
    NotificationTarget._defaults(this);
  }

  NotificationTargetBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _kind = $v.kind;
      _scope = $v.scope;
      _label = $v.label;
      _config = $v.config.toBuilder();
      _enabledEvents = $v.enabledEvents.toBuilder();
      _lastSuccessAt = $v.lastSuccessAt;
      _lastError = $v.lastError;
      _lastErrorAt = $v.lastErrorAt;
      _muted = $v.muted;
      _minIntervalSeconds = $v.minIntervalSeconds;
      _createdAt = $v.createdAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(NotificationTarget other) {
    _$v = other as _$NotificationTarget;
  }

  @override
  void update(void Function(NotificationTargetBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  NotificationTarget build() => _build();

  _$NotificationTarget _build() {
    _$NotificationTarget _$result;
    try {
      _$result =
          _$v ??
          _$NotificationTarget._(
            pid: BuiltValueNullFieldError.checkNotNull(
              pid,
              r'NotificationTarget',
              'pid',
            ),
            kind: BuiltValueNullFieldError.checkNotNull(
              kind,
              r'NotificationTarget',
              'kind',
            ),
            scope: BuiltValueNullFieldError.checkNotNull(
              scope,
              r'NotificationTarget',
              'scope',
            ),
            label: label,
            config: config.build(),
            enabledEvents: enabledEvents.build(),
            lastSuccessAt: lastSuccessAt,
            lastError: lastError,
            lastErrorAt: lastErrorAt,
            muted: muted,
            minIntervalSeconds: minIntervalSeconds,
            createdAt: BuiltValueNullFieldError.checkNotNull(
              createdAt,
              r'NotificationTarget',
              'createdAt',
            ),
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
          r'NotificationTarget',
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
