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
  @override
  final String? csrfToken;
  @override
  final SessionServer? server;

  factory _$SessionInfo([void Function(SessionInfoBuilder)? updates]) =>
      (SessionInfoBuilder()..update(updates))._build();

  _$SessionInfo._({
    required this.authenticated,
    this.user,
    this.csrfToken,
    this.server,
  }) : super._();
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
        user == other.user &&
        csrfToken == other.csrfToken &&
        server == other.server;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, authenticated.hashCode);
    _$hash = $jc(_$hash, user.hashCode);
    _$hash = $jc(_$hash, csrfToken.hashCode);
    _$hash = $jc(_$hash, server.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SessionInfo')
          ..add('authenticated', authenticated)
          ..add('user', user)
          ..add('csrfToken', csrfToken)
          ..add('server', server))
        .toString();
  }
}

class SessionInfoBuilder implements Builder<SessionInfo, SessionInfoBuilder> {
  _$SessionInfo? _$v;

  bool? _authenticated;
  bool? get authenticated => _$this._authenticated;
  set authenticated(bool? authenticated) =>
      _$this._authenticated = authenticated;

  User? _user;
  User? get user => _$this._user;
  set user(User? user) => _$this._user = user;

  String? _csrfToken;
  String? get csrfToken => _$this._csrfToken;
  set csrfToken(String? csrfToken) => _$this._csrfToken = csrfToken;

  SessionServerBuilder? _server;
  SessionServerBuilder get server => _$this._server ??= SessionServerBuilder();
  set server(SessionServerBuilder? server) => _$this._server = server;

  SessionInfoBuilder() {
    SessionInfo._defaults(this);
  }

  SessionInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _authenticated = $v.authenticated;
      _user = $v.user;
      _csrfToken = $v.csrfToken;
      _server = $v.server?.toBuilder();
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
            user: user,
            csrfToken: csrfToken,
            server: _server?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'server';
        _server?.build();
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
