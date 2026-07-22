// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'signup_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SignupRequest extends SignupRequest {
  @override
  final String username;
  @override
  final String password;
  @override
  final String? displayName;
  @override
  final String? inviteToken;

  factory _$SignupRequest([void Function(SignupRequestBuilder)? updates]) =>
      (SignupRequestBuilder()..update(updates))._build();

  _$SignupRequest._({
    required this.username,
    required this.password,
    this.displayName,
    this.inviteToken,
  }) : super._();
  @override
  SignupRequest rebuild(void Function(SignupRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SignupRequestBuilder toBuilder() => SignupRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SignupRequest &&
        username == other.username &&
        password == other.password &&
        displayName == other.displayName &&
        inviteToken == other.inviteToken;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, username.hashCode);
    _$hash = $jc(_$hash, password.hashCode);
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jc(_$hash, inviteToken.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SignupRequest')
          ..add('username', username)
          ..add('password', password)
          ..add('displayName', displayName)
          ..add('inviteToken', inviteToken))
        .toString();
  }
}

class SignupRequestBuilder
    implements Builder<SignupRequest, SignupRequestBuilder> {
  _$SignupRequest? _$v;

  String? _username;
  String? get username => _$this._username;
  set username(String? username) => _$this._username = username;

  String? _password;
  String? get password => _$this._password;
  set password(String? password) => _$this._password = password;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(String? displayName) => _$this._displayName = displayName;

  String? _inviteToken;
  String? get inviteToken => _$this._inviteToken;
  set inviteToken(String? inviteToken) => _$this._inviteToken = inviteToken;

  SignupRequestBuilder() {
    SignupRequest._defaults(this);
  }

  SignupRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _username = $v.username;
      _password = $v.password;
      _displayName = $v.displayName;
      _inviteToken = $v.inviteToken;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SignupRequest other) {
    _$v = other as _$SignupRequest;
  }

  @override
  void update(void Function(SignupRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SignupRequest build() => _build();

  _$SignupRequest _build() {
    final _$result =
        _$v ??
        _$SignupRequest._(
          username: BuiltValueNullFieldError.checkNotNull(
            username,
            r'SignupRequest',
            'username',
          ),
          password: BuiltValueNullFieldError.checkNotNull(
            password,
            r'SignupRequest',
            'password',
          ),
          displayName: displayName,
          inviteToken: inviteToken,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
