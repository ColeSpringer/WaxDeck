// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'genre_normalize_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$GenreNormalizeRequest extends GenreNormalizeRequest {
  @override
  final bool? dryRun;

  factory _$GenreNormalizeRequest([
    void Function(GenreNormalizeRequestBuilder)? updates,
  ]) => (GenreNormalizeRequestBuilder()..update(updates))._build();

  _$GenreNormalizeRequest._({this.dryRun}) : super._();
  @override
  GenreNormalizeRequest rebuild(
    void Function(GenreNormalizeRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  GenreNormalizeRequestBuilder toBuilder() =>
      GenreNormalizeRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GenreNormalizeRequest && dryRun == other.dryRun;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, dryRun.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'GenreNormalizeRequest',
    )..add('dryRun', dryRun)).toString();
  }
}

class GenreNormalizeRequestBuilder
    implements Builder<GenreNormalizeRequest, GenreNormalizeRequestBuilder> {
  _$GenreNormalizeRequest? _$v;

  bool? _dryRun;
  bool? get dryRun => _$this._dryRun;
  set dryRun(bool? dryRun) => _$this._dryRun = dryRun;

  GenreNormalizeRequestBuilder() {
    GenreNormalizeRequest._defaults(this);
  }

  GenreNormalizeRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _dryRun = $v.dryRun;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GenreNormalizeRequest other) {
    _$v = other as _$GenreNormalizeRequest;
  }

  @override
  void update(void Function(GenreNormalizeRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  GenreNormalizeRequest build() => _build();

  _$GenreNormalizeRequest _build() {
    final _$result = _$v ?? _$GenreNormalizeRequest._(dryRun: dryRun);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
