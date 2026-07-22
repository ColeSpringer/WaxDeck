// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'schedule_put.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SchedulePut extends SchedulePut {
  @override
  final String cron;
  @override
  final bool enabled;

  factory _$SchedulePut([void Function(SchedulePutBuilder)? updates]) =>
      (SchedulePutBuilder()..update(updates))._build();

  _$SchedulePut._({required this.cron, required this.enabled}) : super._();
  @override
  SchedulePut rebuild(void Function(SchedulePutBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SchedulePutBuilder toBuilder() => SchedulePutBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SchedulePut &&
        cron == other.cron &&
        enabled == other.enabled;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, cron.hashCode);
    _$hash = $jc(_$hash, enabled.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SchedulePut')
          ..add('cron', cron)
          ..add('enabled', enabled))
        .toString();
  }
}

class SchedulePutBuilder implements Builder<SchedulePut, SchedulePutBuilder> {
  _$SchedulePut? _$v;

  String? _cron;
  String? get cron => _$this._cron;
  set cron(String? cron) => _$this._cron = cron;

  bool? _enabled;
  bool? get enabled => _$this._enabled;
  set enabled(bool? enabled) => _$this._enabled = enabled;

  SchedulePutBuilder() {
    SchedulePut._defaults(this);
  }

  SchedulePutBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _cron = $v.cron;
      _enabled = $v.enabled;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SchedulePut other) {
    _$v = other as _$SchedulePut;
  }

  @override
  void update(void Function(SchedulePutBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SchedulePut build() => _build();

  _$SchedulePut _build() {
    final _$result =
        _$v ??
        _$SchedulePut._(
          cron: BuiltValueNullFieldError.checkNotNull(
            cron,
            r'SchedulePut',
            'cron',
          ),
          enabled: BuiltValueNullFieldError.checkNotNull(
            enabled,
            r'SchedulePut',
            'enabled',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
