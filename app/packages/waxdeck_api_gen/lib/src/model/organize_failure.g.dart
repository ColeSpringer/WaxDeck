// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'organize_failure.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OrganizeFailure extends OrganizeFailure {
  @override
  final String path;
  @override
  final String reason;

  factory _$OrganizeFailure([void Function(OrganizeFailureBuilder)? updates]) =>
      (OrganizeFailureBuilder()..update(updates))._build();

  _$OrganizeFailure._({required this.path, required this.reason}) : super._();
  @override
  OrganizeFailure rebuild(void Function(OrganizeFailureBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OrganizeFailureBuilder toBuilder() => OrganizeFailureBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OrganizeFailure &&
        path == other.path &&
        reason == other.reason;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, path.hashCode);
    _$hash = $jc(_$hash, reason.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OrganizeFailure')
          ..add('path', path)
          ..add('reason', reason))
        .toString();
  }
}

class OrganizeFailureBuilder
    implements Builder<OrganizeFailure, OrganizeFailureBuilder> {
  _$OrganizeFailure? _$v;

  String? _path;
  String? get path => _$this._path;
  set path(String? path) => _$this._path = path;

  String? _reason;
  String? get reason => _$this._reason;
  set reason(String? reason) => _$this._reason = reason;

  OrganizeFailureBuilder() {
    OrganizeFailure._defaults(this);
  }

  OrganizeFailureBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _path = $v.path;
      _reason = $v.reason;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OrganizeFailure other) {
    _$v = other as _$OrganizeFailure;
  }

  @override
  void update(void Function(OrganizeFailureBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OrganizeFailure build() => _build();

  _$OrganizeFailure _build() {
    final _$result =
        _$v ??
        _$OrganizeFailure._(
          path: BuiltValueNullFieldError.checkNotNull(
            path,
            r'OrganizeFailure',
            'path',
          ),
          reason: BuiltValueNullFieldError.checkNotNull(
            reason,
            r'OrganizeFailure',
            'reason',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
