// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'oidc_exchange_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OidcExchangeRequest extends OidcExchangeRequest {
  @override
  final String code;
  @override
  final String? verifier;
  @override
  final String? deviceName;

  factory _$OidcExchangeRequest([
    void Function(OidcExchangeRequestBuilder)? updates,
  ]) => (OidcExchangeRequestBuilder()..update(updates))._build();

  _$OidcExchangeRequest._({required this.code, this.verifier, this.deviceName})
    : super._();
  @override
  OidcExchangeRequest rebuild(
    void Function(OidcExchangeRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  OidcExchangeRequestBuilder toBuilder() =>
      OidcExchangeRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OidcExchangeRequest &&
        code == other.code &&
        verifier == other.verifier &&
        deviceName == other.deviceName;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, verifier.hashCode);
    _$hash = $jc(_$hash, deviceName.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OidcExchangeRequest')
          ..add('code', code)
          ..add('verifier', verifier)
          ..add('deviceName', deviceName))
        .toString();
  }
}

class OidcExchangeRequestBuilder
    implements Builder<OidcExchangeRequest, OidcExchangeRequestBuilder> {
  _$OidcExchangeRequest? _$v;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  String? _verifier;
  String? get verifier => _$this._verifier;
  set verifier(String? verifier) => _$this._verifier = verifier;

  String? _deviceName;
  String? get deviceName => _$this._deviceName;
  set deviceName(String? deviceName) => _$this._deviceName = deviceName;

  OidcExchangeRequestBuilder() {
    OidcExchangeRequest._defaults(this);
  }

  OidcExchangeRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _code = $v.code;
      _verifier = $v.verifier;
      _deviceName = $v.deviceName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OidcExchangeRequest other) {
    _$v = other as _$OidcExchangeRequest;
  }

  @override
  void update(void Function(OidcExchangeRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OidcExchangeRequest build() => _build();

  _$OidcExchangeRequest _build() {
    final _$result =
        _$v ??
        _$OidcExchangeRequest._(
          code: BuiltValueNullFieldError.checkNotNull(
            code,
            r'OidcExchangeRequest',
            'code',
          ),
          verifier: verifier,
          deviceName: deviceName,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
