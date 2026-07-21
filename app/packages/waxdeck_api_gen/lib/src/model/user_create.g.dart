// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_create.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UserCreate extends UserCreate {
  @override
  final String username;
  @override
  final String password;
  @override
  final String? displayName;
  @override
  final BuiltList<Role>? roles;
  @override
  final LibraryAccess? libraryAccess;
  @override
  final bool? uploadEnabled;
  @override
  final int? uploadQuotaBytes;

  factory _$UserCreate([void Function(UserCreateBuilder)? updates]) =>
      (UserCreateBuilder()..update(updates))._build();

  _$UserCreate._({
    required this.username,
    required this.password,
    this.displayName,
    this.roles,
    this.libraryAccess,
    this.uploadEnabled,
    this.uploadQuotaBytes,
  }) : super._();
  @override
  UserCreate rebuild(void Function(UserCreateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UserCreateBuilder toBuilder() => UserCreateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UserCreate &&
        username == other.username &&
        password == other.password &&
        displayName == other.displayName &&
        roles == other.roles &&
        libraryAccess == other.libraryAccess &&
        uploadEnabled == other.uploadEnabled &&
        uploadQuotaBytes == other.uploadQuotaBytes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, username.hashCode);
    _$hash = $jc(_$hash, password.hashCode);
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jc(_$hash, roles.hashCode);
    _$hash = $jc(_$hash, libraryAccess.hashCode);
    _$hash = $jc(_$hash, uploadEnabled.hashCode);
    _$hash = $jc(_$hash, uploadQuotaBytes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UserCreate')
          ..add('username', username)
          ..add('password', password)
          ..add('displayName', displayName)
          ..add('roles', roles)
          ..add('libraryAccess', libraryAccess)
          ..add('uploadEnabled', uploadEnabled)
          ..add('uploadQuotaBytes', uploadQuotaBytes))
        .toString();
  }
}

class UserCreateBuilder implements Builder<UserCreate, UserCreateBuilder> {
  _$UserCreate? _$v;

  String? _username;
  String? get username => _$this._username;
  set username(String? username) => _$this._username = username;

  String? _password;
  String? get password => _$this._password;
  set password(String? password) => _$this._password = password;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(String? displayName) => _$this._displayName = displayName;

  ListBuilder<Role>? _roles;
  ListBuilder<Role> get roles => _$this._roles ??= ListBuilder<Role>();
  set roles(ListBuilder<Role>? roles) => _$this._roles = roles;

  LibraryAccessBuilder? _libraryAccess;
  LibraryAccessBuilder get libraryAccess =>
      _$this._libraryAccess ??= LibraryAccessBuilder();
  set libraryAccess(LibraryAccessBuilder? libraryAccess) =>
      _$this._libraryAccess = libraryAccess;

  bool? _uploadEnabled;
  bool? get uploadEnabled => _$this._uploadEnabled;
  set uploadEnabled(bool? uploadEnabled) =>
      _$this._uploadEnabled = uploadEnabled;

  int? _uploadQuotaBytes;
  int? get uploadQuotaBytes => _$this._uploadQuotaBytes;
  set uploadQuotaBytes(int? uploadQuotaBytes) =>
      _$this._uploadQuotaBytes = uploadQuotaBytes;

  UserCreateBuilder() {
    UserCreate._defaults(this);
  }

  UserCreateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _username = $v.username;
      _password = $v.password;
      _displayName = $v.displayName;
      _roles = $v.roles?.toBuilder();
      _libraryAccess = $v.libraryAccess?.toBuilder();
      _uploadEnabled = $v.uploadEnabled;
      _uploadQuotaBytes = $v.uploadQuotaBytes;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UserCreate other) {
    _$v = other as _$UserCreate;
  }

  @override
  void update(void Function(UserCreateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UserCreate build() => _build();

  _$UserCreate _build() {
    _$UserCreate _$result;
    try {
      _$result =
          _$v ??
          _$UserCreate._(
            username: BuiltValueNullFieldError.checkNotNull(
              username,
              r'UserCreate',
              'username',
            ),
            password: BuiltValueNullFieldError.checkNotNull(
              password,
              r'UserCreate',
              'password',
            ),
            displayName: displayName,
            roles: _roles?.build(),
            libraryAccess: _libraryAccess?.build(),
            uploadEnabled: uploadEnabled,
            uploadQuotaBytes: uploadQuotaBytes,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'roles';
        _roles?.build();
        _$failedField = 'libraryAccess';
        _libraryAccess?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'UserCreate',
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
