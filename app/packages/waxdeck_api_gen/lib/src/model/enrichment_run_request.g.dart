// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enrichment_run_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EnrichmentRunRequest extends EnrichmentRunRequest {
  @override
  final bool? force;

  factory _$EnrichmentRunRequest([
    void Function(EnrichmentRunRequestBuilder)? updates,
  ]) => (EnrichmentRunRequestBuilder()..update(updates))._build();

  _$EnrichmentRunRequest._({this.force}) : super._();
  @override
  EnrichmentRunRequest rebuild(
    void Function(EnrichmentRunRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  EnrichmentRunRequestBuilder toBuilder() =>
      EnrichmentRunRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EnrichmentRunRequest && force == other.force;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, force.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'EnrichmentRunRequest',
    )..add('force', force)).toString();
  }
}

class EnrichmentRunRequestBuilder
    implements Builder<EnrichmentRunRequest, EnrichmentRunRequestBuilder> {
  _$EnrichmentRunRequest? _$v;

  bool? _force;
  bool? get force => _$this._force;
  set force(bool? force) => _$this._force = force;

  EnrichmentRunRequestBuilder() {
    EnrichmentRunRequest._defaults(this);
  }

  EnrichmentRunRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _force = $v.force;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EnrichmentRunRequest other) {
    _$v = other as _$EnrichmentRunRequest;
  }

  @override
  void update(void Function(EnrichmentRunRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EnrichmentRunRequest build() => _build();

  _$EnrichmentRunRequest _build() {
    final _$result = _$v ?? _$EnrichmentRunRequest._(force: force);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
