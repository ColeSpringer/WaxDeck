// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_info.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SessionInfo extends SessionInfo {
  @override
  final bool authenticated;
  @override
  final User? user;

  factory _$SessionInfo([void Function(SessionInfoBuilder)? updates]) =>
      (SessionInfoBuilder()..update(updates))._build();

  _$SessionInfo._({required this.authenticated, this.user}) : super._();
  @override
  SessionInfo rebuild(void Function(SessionInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SessionInfoBuilder toBuilder() => SessionInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SessionInfo &&
        authenticated == other.authenticated &&
        user == other.user;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, authenticated.hashCode);
    _$hash = $jc(_$hash, user.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SessionInfo')
          ..add('authenticated', authenticated)
          ..add('user', user))
        .toString();
  }
}

class SessionInfoBuilder implements Builder<SessionInfo, SessionInfoBuilder> {
  _$SessionInfo? _$v;

  bool? _authenticated;
  bool? get authenticated => _$this._authenticated;
  set authenticated(bool? authenticated) =>
      _$this._authenticated = authenticated;

  UserBuilder? _user;
  UserBuilder get user => _$this._user ??= UserBuilder();
  set user(UserBuilder? user) => _$this._user = user;

  SessionInfoBuilder() {
    SessionInfo._defaults(this);
  }

  SessionInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _authenticated = $v.authenticated;
      _user = $v.user?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SessionInfo other) {
    _$v = other as _$SessionInfo;
  }

  @override
  void update(void Function(SessionInfoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SessionInfo build() => _build();

  _$SessionInfo _build() {
    _$SessionInfo _$result;
    try {
      _$result =
          _$v ??
          _$SessionInfo._(
            authenticated: BuiltValueNullFieldError.checkNotNull(
              authenticated,
              r'SessionInfo',
              'authenticated',
            ),
            user: _user?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'user';
        _user?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'SessionInfo',
          _$failedField,
          e.toString(),
        );
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
