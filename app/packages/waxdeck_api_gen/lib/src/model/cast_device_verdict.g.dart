// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cast_device_verdict.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CastDeviceVerdict extends CastDeviceVerdict {
  @override
  final String verdict;
  @override
  final String? detail;
  @override
  final int latencyMs;

  factory _$CastDeviceVerdict([
    void Function(CastDeviceVerdictBuilder)? updates,
  ]) => (CastDeviceVerdictBuilder()..update(updates))._build();

  _$CastDeviceVerdict._({
    required this.verdict,
    this.detail,
    required this.latencyMs,
  }) : super._();
  @override
  CastDeviceVerdict rebuild(void Function(CastDeviceVerdictBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CastDeviceVerdictBuilder toBuilder() =>
      CastDeviceVerdictBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CastDeviceVerdict &&
        verdict == other.verdict &&
        detail == other.detail &&
        latencyMs == other.latencyMs;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, verdict.hashCode);
    _$hash = $jc(_$hash, detail.hashCode);
    _$hash = $jc(_$hash, latencyMs.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CastDeviceVerdict')
          ..add('verdict', verdict)
          ..add('detail', detail)
          ..add('latencyMs', latencyMs))
        .toString();
  }
}

class CastDeviceVerdictBuilder
    implements Builder<CastDeviceVerdict, CastDeviceVerdictBuilder> {
  _$CastDeviceVerdict? _$v;

  String? _verdict;
  String? get verdict => _$this._verdict;
  set verdict(String? verdict) => _$this._verdict = verdict;

  String? _detail;
  String? get detail => _$this._detail;
  set detail(String? detail) => _$this._detail = detail;

  int? _latencyMs;
  int? get latencyMs => _$this._latencyMs;
  set latencyMs(int? latencyMs) => _$this._latencyMs = latencyMs;

  CastDeviceVerdictBuilder() {
    CastDeviceVerdict._defaults(this);
  }

  CastDeviceVerdictBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _verdict = $v.verdict;
      _detail = $v.detail;
      _latencyMs = $v.latencyMs;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CastDeviceVerdict other) {
    _$v = other as _$CastDeviceVerdict;
  }

  @override
  void update(void Function(CastDeviceVerdictBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CastDeviceVerdict build() => _build();

  _$CastDeviceVerdict _build() {
    final _$result =
        _$v ??
        _$CastDeviceVerdict._(
          verdict: BuiltValueNullFieldError.checkNotNull(
            verdict,
            r'CastDeviceVerdict',
            'verdict',
          ),
          detail: detail,
          latencyMs: BuiltValueNullFieldError.checkNotNull(
            latencyMs,
            r'CastDeviceVerdict',
            'latencyMs',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
