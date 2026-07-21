// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'health_fix_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$HealthFixResult extends HealthFixResult {
  @override
  final int queued;

  factory _$HealthFixResult([void Function(HealthFixResultBuilder)? updates]) =>
      (HealthFixResultBuilder()..update(updates))._build();

  _$HealthFixResult._({required this.queued}) : super._();
  @override
  HealthFixResult rebuild(void Function(HealthFixResultBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  HealthFixResultBuilder toBuilder() => HealthFixResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is HealthFixResult && queued == other.queued;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, queued.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'HealthFixResult',
    )..add('queued', queued)).toString();
  }
}

class HealthFixResultBuilder
    implements Builder<HealthFixResult, HealthFixResultBuilder> {
  _$HealthFixResult? _$v;

  int? _queued;
  int? get queued => _$this._queued;
  set queued(int? queued) => _$this._queued = queued;

  HealthFixResultBuilder() {
    HealthFixResult._defaults(this);
  }

  HealthFixResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _queued = $v.queued;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(HealthFixResult other) {
    _$v = other as _$HealthFixResult;
  }

  @override
  void update(void Function(HealthFixResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  HealthFixResult build() => _build();

  _$HealthFixResult _build() {
    final _$result =
        _$v ??
        _$HealthFixResult._(
          queued: BuiltValueNullFieldError.checkNotNull(
            queued,
            r'HealthFixResult',
            'queued',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
