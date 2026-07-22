// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'schedule.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Schedule extends Schedule {
  @override
  final ScheduleKind kind;
  @override
  final String cron;
  @override
  final bool enabled;
  @override
  final DateTime? lastRunAt;
  @override
  final String? lastStatus;
  @override
  final String? lastError;
  @override
  final DateTime? nextRunAt;

  factory _$Schedule([void Function(ScheduleBuilder)? updates]) =>
      (ScheduleBuilder()..update(updates))._build();

  _$Schedule._({
    required this.kind,
    required this.cron,
    required this.enabled,
    this.lastRunAt,
    this.lastStatus,
    this.lastError,
    this.nextRunAt,
  }) : super._();
  @override
  Schedule rebuild(void Function(ScheduleBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ScheduleBuilder toBuilder() => ScheduleBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Schedule &&
        kind == other.kind &&
        cron == other.cron &&
        enabled == other.enabled &&
        lastRunAt == other.lastRunAt &&
        lastStatus == other.lastStatus &&
        lastError == other.lastError &&
        nextRunAt == other.nextRunAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, cron.hashCode);
    _$hash = $jc(_$hash, enabled.hashCode);
    _$hash = $jc(_$hash, lastRunAt.hashCode);
    _$hash = $jc(_$hash, lastStatus.hashCode);
    _$hash = $jc(_$hash, lastError.hashCode);
    _$hash = $jc(_$hash, nextRunAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Schedule')
          ..add('kind', kind)
          ..add('cron', cron)
          ..add('enabled', enabled)
          ..add('lastRunAt', lastRunAt)
          ..add('lastStatus', lastStatus)
          ..add('lastError', lastError)
          ..add('nextRunAt', nextRunAt))
        .toString();
  }
}

class ScheduleBuilder implements Builder<Schedule, ScheduleBuilder> {
  _$Schedule? _$v;

  ScheduleKind? _kind;
  ScheduleKind? get kind => _$this._kind;
  set kind(ScheduleKind? kind) => _$this._kind = kind;

  String? _cron;
  String? get cron => _$this._cron;
  set cron(String? cron) => _$this._cron = cron;

  bool? _enabled;
  bool? get enabled => _$this._enabled;
  set enabled(bool? enabled) => _$this._enabled = enabled;

  DateTime? _lastRunAt;
  DateTime? get lastRunAt => _$this._lastRunAt;
  set lastRunAt(DateTime? lastRunAt) => _$this._lastRunAt = lastRunAt;

  String? _lastStatus;
  String? get lastStatus => _$this._lastStatus;
  set lastStatus(String? lastStatus) => _$this._lastStatus = lastStatus;

  String? _lastError;
  String? get lastError => _$this._lastError;
  set lastError(String? lastError) => _$this._lastError = lastError;

  DateTime? _nextRunAt;
  DateTime? get nextRunAt => _$this._nextRunAt;
  set nextRunAt(DateTime? nextRunAt) => _$this._nextRunAt = nextRunAt;

  ScheduleBuilder() {
    Schedule._defaults(this);
  }

  ScheduleBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _kind = $v.kind;
      _cron = $v.cron;
      _enabled = $v.enabled;
      _lastRunAt = $v.lastRunAt;
      _lastStatus = $v.lastStatus;
      _lastError = $v.lastError;
      _nextRunAt = $v.nextRunAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Schedule other) {
    _$v = other as _$Schedule;
  }

  @override
  void update(void Function(ScheduleBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Schedule build() => _build();

  _$Schedule _build() {
    final _$result =
        _$v ??
        _$Schedule._(
          kind: BuiltValueNullFieldError.checkNotNull(
            kind,
            r'Schedule',
            'kind',
          ),
          cron: BuiltValueNullFieldError.checkNotNull(
            cron,
            r'Schedule',
            'cron',
          ),
          enabled: BuiltValueNullFieldError.checkNotNull(
            enabled,
            r'Schedule',
            'enabled',
          ),
          lastRunAt: lastRunAt,
          lastStatus: lastStatus,
          lastError: lastError,
          nextRunAt: nextRunAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
