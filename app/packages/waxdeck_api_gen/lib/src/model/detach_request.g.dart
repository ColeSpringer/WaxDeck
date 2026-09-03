// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'detach_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DetachRequest extends DetachRequest {
  @override
  final bool? writeBack;

  factory _$DetachRequest([void Function(DetachRequestBuilder)? updates]) =>
      (DetachRequestBuilder()..update(updates))._build();

  _$DetachRequest._({this.writeBack}) : super._();
  @override
  DetachRequest rebuild(void Function(DetachRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DetachRequestBuilder toBuilder() => DetachRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DetachRequest && writeBack == other.writeBack;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, writeBack.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'DetachRequest',
    )..add('writeBack', writeBack)).toString();
  }
}

class DetachRequestBuilder
    implements Builder<DetachRequest, DetachRequestBuilder> {
  _$DetachRequest? _$v;

  bool? _writeBack;
  bool? get writeBack => _$this._writeBack;
  set writeBack(bool? writeBack) => _$this._writeBack = writeBack;

  DetachRequestBuilder() {
    DetachRequest._defaults(this);
  }

  DetachRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _writeBack = $v.writeBack;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DetachRequest other) {
    _$v = other as _$DetachRequest;
  }

  @override
  void update(void Function(DetachRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DetachRequest build() => _build();

  _$DetachRequest _build() {
    final _$result = _$v ?? _$DetachRequest._(writeBack: writeBack);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
