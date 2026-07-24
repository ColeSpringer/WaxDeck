// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_diagnostic.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$FileDiagnostic extends FileDiagnostic {
  @override
  final String path;
  @override
  final String origin;
  @override
  final String code;
  @override
  final String severity;
  @override
  final String? tagKey;
  @override
  final String? detail;
  @override
  final DateTime seenAt;

  factory _$FileDiagnostic([void Function(FileDiagnosticBuilder)? updates]) =>
      (FileDiagnosticBuilder()..update(updates))._build();

  _$FileDiagnostic._({
    required this.path,
    required this.origin,
    required this.code,
    required this.severity,
    this.tagKey,
    this.detail,
    required this.seenAt,
  }) : super._();
  @override
  FileDiagnostic rebuild(void Function(FileDiagnosticBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  FileDiagnosticBuilder toBuilder() => FileDiagnosticBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is FileDiagnostic &&
        path == other.path &&
        origin == other.origin &&
        code == other.code &&
        severity == other.severity &&
        tagKey == other.tagKey &&
        detail == other.detail &&
        seenAt == other.seenAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, path.hashCode);
    _$hash = $jc(_$hash, origin.hashCode);
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, severity.hashCode);
    _$hash = $jc(_$hash, tagKey.hashCode);
    _$hash = $jc(_$hash, detail.hashCode);
    _$hash = $jc(_$hash, seenAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'FileDiagnostic')
          ..add('path', path)
          ..add('origin', origin)
          ..add('code', code)
          ..add('severity', severity)
          ..add('tagKey', tagKey)
          ..add('detail', detail)
          ..add('seenAt', seenAt))
        .toString();
  }
}

class FileDiagnosticBuilder
    implements Builder<FileDiagnostic, FileDiagnosticBuilder> {
  _$FileDiagnostic? _$v;

  String? _path;
  String? get path => _$this._path;
  set path(String? path) => _$this._path = path;

  String? _origin;
  String? get origin => _$this._origin;
  set origin(String? origin) => _$this._origin = origin;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  String? _severity;
  String? get severity => _$this._severity;
  set severity(String? severity) => _$this._severity = severity;

  String? _tagKey;
  String? get tagKey => _$this._tagKey;
  set tagKey(String? tagKey) => _$this._tagKey = tagKey;

  String? _detail;
  String? get detail => _$this._detail;
  set detail(String? detail) => _$this._detail = detail;

  DateTime? _seenAt;
  DateTime? get seenAt => _$this._seenAt;
  set seenAt(DateTime? seenAt) => _$this._seenAt = seenAt;

  FileDiagnosticBuilder() {
    FileDiagnostic._defaults(this);
  }

  FileDiagnosticBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _path = $v.path;
      _origin = $v.origin;
      _code = $v.code;
      _severity = $v.severity;
      _tagKey = $v.tagKey;
      _detail = $v.detail;
      _seenAt = $v.seenAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(FileDiagnostic other) {
    _$v = other as _$FileDiagnostic;
  }

  @override
  void update(void Function(FileDiagnosticBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  FileDiagnostic build() => _build();

  _$FileDiagnostic _build() {
    final _$result =
        _$v ??
        _$FileDiagnostic._(
          path: BuiltValueNullFieldError.checkNotNull(
            path,
            r'FileDiagnostic',
            'path',
          ),
          origin: BuiltValueNullFieldError.checkNotNull(
            origin,
            r'FileDiagnostic',
            'origin',
          ),
          code: BuiltValueNullFieldError.checkNotNull(
            code,
            r'FileDiagnostic',
            'code',
          ),
          severity: BuiltValueNullFieldError.checkNotNull(
            severity,
            r'FileDiagnostic',
            'severity',
          ),
          tagKey: tagKey,
          detail: detail,
          seenAt: BuiltValueNullFieldError.checkNotNull(
            seenAt,
            r'FileDiagnostic',
            'seenAt',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
