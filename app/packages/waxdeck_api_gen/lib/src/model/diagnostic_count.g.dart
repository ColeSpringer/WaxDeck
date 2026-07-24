// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'diagnostic_count.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DiagnosticCount extends DiagnosticCount {
  @override
  final String origin;
  @override
  final String code;
  @override
  final String severity;
  @override
  final int count;

  factory _$DiagnosticCount([void Function(DiagnosticCountBuilder)? updates]) =>
      (DiagnosticCountBuilder()..update(updates))._build();

  _$DiagnosticCount._({
    required this.origin,
    required this.code,
    required this.severity,
    required this.count,
  }) : super._();
  @override
  DiagnosticCount rebuild(void Function(DiagnosticCountBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DiagnosticCountBuilder toBuilder() => DiagnosticCountBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DiagnosticCount &&
        origin == other.origin &&
        code == other.code &&
        severity == other.severity &&
        count == other.count;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, origin.hashCode);
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, severity.hashCode);
    _$hash = $jc(_$hash, count.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DiagnosticCount')
          ..add('origin', origin)
          ..add('code', code)
          ..add('severity', severity)
          ..add('count', count))
        .toString();
  }
}

class DiagnosticCountBuilder
    implements Builder<DiagnosticCount, DiagnosticCountBuilder> {
  _$DiagnosticCount? _$v;

  String? _origin;
  String? get origin => _$this._origin;
  set origin(String? origin) => _$this._origin = origin;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  String? _severity;
  String? get severity => _$this._severity;
  set severity(String? severity) => _$this._severity = severity;

  int? _count;
  int? get count => _$this._count;
  set count(int? count) => _$this._count = count;

  DiagnosticCountBuilder() {
    DiagnosticCount._defaults(this);
  }

  DiagnosticCountBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _origin = $v.origin;
      _code = $v.code;
      _severity = $v.severity;
      _count = $v.count;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DiagnosticCount other) {
    _$v = other as _$DiagnosticCount;
  }

  @override
  void update(void Function(DiagnosticCountBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DiagnosticCount build() => _build();

  _$DiagnosticCount _build() {
    final _$result =
        _$v ??
        _$DiagnosticCount._(
          origin: BuiltValueNullFieldError.checkNotNull(
            origin,
            r'DiagnosticCount',
            'origin',
          ),
          code: BuiltValueNullFieldError.checkNotNull(
            code,
            r'DiagnosticCount',
            'code',
          ),
          severity: BuiltValueNullFieldError.checkNotNull(
            severity,
            r'DiagnosticCount',
            'severity',
          ),
          count: BuiltValueNullFieldError.checkNotNull(
            count,
            r'DiagnosticCount',
            'count',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
