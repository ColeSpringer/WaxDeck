// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bootstrap_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BootstrapRequest extends BootstrapRequest {
  @override
  final String username;
  @override
  final String password;
  @override
  final String? displayName;

  factory _$BootstrapRequest([
    void Function(BootstrapRequestBuilder)? updates,
  ]) => (BootstrapRequestBuilder()..update(updates))._build();

  _$BootstrapRequest._({
    required this.username,
    required this.password,
    this.displayName,
  }) : super._();
  @override
  BootstrapRequest rebuild(void Function(BootstrapRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BootstrapRequestBuilder toBuilder() =>
      BootstrapRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BootstrapRequest &&
        username == other.username &&
        password == other.password &&
        displayName == other.displayName;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, username.hashCode);
    _$hash = $jc(_$hash, password.hashCode);
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BootstrapRequest')
          ..add('username', username)
          ..add('password', password)
          ..add('displayName', displayName))
        .toString();
  }
}

class BootstrapRequestBuilder
    implements Builder<BootstrapRequest, BootstrapRequestBuilder> {
  _$BootstrapRequest? _$v;

  String? _username;
  String? get username => _$this._username;
  set username(String? username) => _$this._username = username;

  String? _password;
  String? get password => _$this._password;
  set password(String? password) => _$this._password = password;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(String? displayName) => _$this._displayName = displayName;

  BootstrapRequestBuilder() {
    BootstrapRequest._defaults(this);
  }

  BootstrapRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _username = $v.username;
      _password = $v.password;
      _displayName = $v.displayName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BootstrapRequest other) {
    _$v = other as _$BootstrapRequest;
  }

  @override
  void update(void Function(BootstrapRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BootstrapRequest build() => _build();

  _$BootstrapRequest _build() {
    final _$result =
        _$v ??
        _$BootstrapRequest._(
          username: BuiltValueNullFieldError.checkNotNull(
            username,
            r'BootstrapRequest',
            'username',
          ),
          password: BuiltValueNullFieldError.checkNotNull(
            password,
            r'BootstrapRequest',
            'password',
          ),
          displayName: displayName,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
