// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cue_split_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CueSplitRequest extends CueSplitRequest {
  @override
  final bool? keepOriginals;

  factory _$CueSplitRequest([void Function(CueSplitRequestBuilder)? updates]) =>
      (CueSplitRequestBuilder()..update(updates))._build();

  _$CueSplitRequest._({this.keepOriginals}) : super._();
  @override
  CueSplitRequest rebuild(void Function(CueSplitRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CueSplitRequestBuilder toBuilder() => CueSplitRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CueSplitRequest && keepOriginals == other.keepOriginals;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, keepOriginals.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'CueSplitRequest',
    )..add('keepOriginals', keepOriginals)).toString();
  }
}

class CueSplitRequestBuilder
    implements Builder<CueSplitRequest, CueSplitRequestBuilder> {
  _$CueSplitRequest? _$v;

  bool? _keepOriginals;
  bool? get keepOriginals => _$this._keepOriginals;
  set keepOriginals(bool? keepOriginals) =>
      _$this._keepOriginals = keepOriginals;

  CueSplitRequestBuilder() {
    CueSplitRequest._defaults(this);
  }

  CueSplitRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _keepOriginals = $v.keepOriginals;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CueSplitRequest other) {
    _$v = other as _$CueSplitRequest;
  }

  @override
  void update(void Function(CueSplitRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CueSplitRequest build() => _build();

  _$CueSplitRequest _build() {
    final _$result = _$v ?? _$CueSplitRequest._(keepOriginals: keepOriginals);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
