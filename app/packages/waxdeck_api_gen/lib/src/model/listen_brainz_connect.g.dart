// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'listen_brainz_connect.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ListenBrainzConnect extends ListenBrainzConnect {
  @override
  final String token;
  @override
  final String? apiUrl;

  factory _$ListenBrainzConnect([
    void Function(ListenBrainzConnectBuilder)? updates,
  ]) => (ListenBrainzConnectBuilder()..update(updates))._build();

  _$ListenBrainzConnect._({required this.token, this.apiUrl}) : super._();
  @override
  ListenBrainzConnect rebuild(
    void Function(ListenBrainzConnectBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  ListenBrainzConnectBuilder toBuilder() =>
      ListenBrainzConnectBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ListenBrainzConnect &&
        token == other.token &&
        apiUrl == other.apiUrl;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, token.hashCode);
    _$hash = $jc(_$hash, apiUrl.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ListenBrainzConnect')
          ..add('token', token)
          ..add('apiUrl', apiUrl))
        .toString();
  }
}

class ListenBrainzConnectBuilder
    implements Builder<ListenBrainzConnect, ListenBrainzConnectBuilder> {
  _$ListenBrainzConnect? _$v;

  String? _token;
  String? get token => _$this._token;
  set token(String? token) => _$this._token = token;

  String? _apiUrl;
  String? get apiUrl => _$this._apiUrl;
  set apiUrl(String? apiUrl) => _$this._apiUrl = apiUrl;

  ListenBrainzConnectBuilder() {
    ListenBrainzConnect._defaults(this);
  }

  ListenBrainzConnectBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _token = $v.token;
      _apiUrl = $v.apiUrl;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ListenBrainzConnect other) {
    _$v = other as _$ListenBrainzConnect;
  }

  @override
  void update(void Function(ListenBrainzConnectBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ListenBrainzConnect build() => _build();

  _$ListenBrainzConnect _build() {
    final _$result =
        _$v ??
        _$ListenBrainzConnect._(
          token: BuiltValueNullFieldError.checkNotNull(
            token,
            r'ListenBrainzConnect',
            'token',
          ),
          apiUrl: apiUrl,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
