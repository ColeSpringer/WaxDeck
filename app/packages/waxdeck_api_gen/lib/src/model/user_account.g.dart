// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_account.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UserAccount extends UserAccount {
  @override
  final DateTime createdAt;
  @override
  final BuiltList<LinkedIdentity>? identities;
  @override
  final Permissions permissions;
  @override
  final bool pending;
  @override
  final LibraryAccess libraryAccess;
  @override
  final bool uploadEnabled;
  @override
  final bool disabled;
  @override
  final bool? hasPassword;
  @override
  final int? uploadQuotaBytes;
  @override
  final String id;
  @override
  final String username;
  @override
  final String? displayName;
  @override
  final BuiltList<String> roles;

  factory _$UserAccount([void Function(UserAccountBuilder)? updates]) =>
      (UserAccountBuilder()..update(updates))._build();

  _$UserAccount._({
    required this.createdAt,
    this.identities,
    required this.permissions,
    required this.pending,
    required this.libraryAccess,
    required this.uploadEnabled,
    required this.disabled,
    this.hasPassword,
    this.uploadQuotaBytes,
    required this.id,
    required this.username,
    this.displayName,
    required this.roles,
  }) : super._();
  @override
  UserAccount rebuild(void Function(UserAccountBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UserAccountBuilder toBuilder() => UserAccountBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UserAccount &&
        createdAt == other.createdAt &&
        identities == other.identities &&
        permissions == other.permissions &&
        pending == other.pending &&
        libraryAccess == other.libraryAccess &&
        uploadEnabled == other.uploadEnabled &&
        disabled == other.disabled &&
        hasPassword == other.hasPassword &&
        uploadQuotaBytes == other.uploadQuotaBytes &&
        id == other.id &&
        username == other.username &&
        displayName == other.displayName &&
        roles == other.roles;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, identities.hashCode);
    _$hash = $jc(_$hash, permissions.hashCode);
    _$hash = $jc(_$hash, pending.hashCode);
    _$hash = $jc(_$hash, libraryAccess.hashCode);
    _$hash = $jc(_$hash, uploadEnabled.hashCode);
    _$hash = $jc(_$hash, disabled.hashCode);
    _$hash = $jc(_$hash, hasPassword.hashCode);
    _$hash = $jc(_$hash, uploadQuotaBytes.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, username.hashCode);
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jc(_$hash, roles.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UserAccount')
          ..add('createdAt', createdAt)
          ..add('identities', identities)
          ..add('permissions', permissions)
          ..add('pending', pending)
          ..add('libraryAccess', libraryAccess)
          ..add('uploadEnabled', uploadEnabled)
          ..add('disabled', disabled)
          ..add('hasPassword', hasPassword)
          ..add('uploadQuotaBytes', uploadQuotaBytes)
          ..add('id', id)
          ..add('username', username)
          ..add('displayName', displayName)
          ..add('roles', roles))
        .toString();
  }
}

class UserAccountBuilder
    implements Builder<UserAccount, UserAccountBuilder>, UserBuilder {
  _$UserAccount? _$v;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(covariant DateTime? createdAt) => _$this._createdAt = createdAt;

  ListBuilder<LinkedIdentity>? _identities;
  ListBuilder<LinkedIdentity> get identities =>
      _$this._identities ??= ListBuilder<LinkedIdentity>();
  set identities(covariant ListBuilder<LinkedIdentity>? identities) =>
      _$this._identities = identities;

  PermissionsBuilder? _permissions;
  PermissionsBuilder get permissions =>
      _$this._permissions ??= PermissionsBuilder();
  set permissions(covariant PermissionsBuilder? permissions) =>
      _$this._permissions = permissions;

  bool? _pending;
  bool? get pending => _$this._pending;
  set pending(covariant bool? pending) => _$this._pending = pending;

  LibraryAccessBuilder? _libraryAccess;
  LibraryAccessBuilder get libraryAccess =>
      _$this._libraryAccess ??= LibraryAccessBuilder();
  set libraryAccess(covariant LibraryAccessBuilder? libraryAccess) =>
      _$this._libraryAccess = libraryAccess;

  bool? _uploadEnabled;
  bool? get uploadEnabled => _$this._uploadEnabled;
  set uploadEnabled(covariant bool? uploadEnabled) =>
      _$this._uploadEnabled = uploadEnabled;

  bool? _disabled;
  bool? get disabled => _$this._disabled;
  set disabled(covariant bool? disabled) => _$this._disabled = disabled;

  bool? _hasPassword;
  bool? get hasPassword => _$this._hasPassword;
  set hasPassword(covariant bool? hasPassword) =>
      _$this._hasPassword = hasPassword;

  int? _uploadQuotaBytes;
  int? get uploadQuotaBytes => _$this._uploadQuotaBytes;
  set uploadQuotaBytes(covariant int? uploadQuotaBytes) =>
      _$this._uploadQuotaBytes = uploadQuotaBytes;

  String? _id;
  String? get id => _$this._id;
  set id(covariant String? id) => _$this._id = id;

  String? _username;
  String? get username => _$this._username;
  set username(covariant String? username) => _$this._username = username;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(covariant String? displayName) =>
      _$this._displayName = displayName;

  ListBuilder<String>? _roles;
  ListBuilder<String> get roles => _$this._roles ??= ListBuilder<String>();
  set roles(covariant ListBuilder<String>? roles) => _$this._roles = roles;

  UserAccountBuilder() {
    UserAccount._defaults(this);
  }

  UserAccountBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _createdAt = $v.createdAt;
      _identities = $v.identities?.toBuilder();
      _permissions = $v.permissions.toBuilder();
      _pending = $v.pending;
      _libraryAccess = $v.libraryAccess.toBuilder();
      _uploadEnabled = $v.uploadEnabled;
      _disabled = $v.disabled;
      _hasPassword = $v.hasPassword;
      _uploadQuotaBytes = $v.uploadQuotaBytes;
      _id = $v.id;
      _username = $v.username;
      _displayName = $v.displayName;
      _roles = $v.roles.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(covariant UserAccount other) {
    _$v = other as _$UserAccount;
  }

  @override
  void update(void Function(UserAccountBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UserAccount build() => _build();

  _$UserAccount _build() {
    _$UserAccount _$result;
    try {
      _$result =
          _$v ??
          _$UserAccount._(
            createdAt: BuiltValueNullFieldError.checkNotNull(
              createdAt,
              r'UserAccount',
              'createdAt',
            ),
            identities: _identities?.build(),
            permissions: permissions.build(),
            pending: BuiltValueNullFieldError.checkNotNull(
              pending,
              r'UserAccount',
              'pending',
            ),
            libraryAccess: libraryAccess.build(),
            uploadEnabled: BuiltValueNullFieldError.checkNotNull(
              uploadEnabled,
              r'UserAccount',
              'uploadEnabled',
            ),
            disabled: BuiltValueNullFieldError.checkNotNull(
              disabled,
              r'UserAccount',
              'disabled',
            ),
            hasPassword: hasPassword,
            uploadQuotaBytes: uploadQuotaBytes,
            id: BuiltValueNullFieldError.checkNotNull(id, r'UserAccount', 'id'),
            username: BuiltValueNullFieldError.checkNotNull(
              username,
              r'UserAccount',
              'username',
            ),
            displayName: displayName,
            roles: roles.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'identities';
        _identities?.build();
        _$failedField = 'permissions';
        permissions.build();

        _$failedField = 'libraryAccess';
        libraryAccess.build();

        _$failedField = 'roles';
        roles.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'UserAccount',
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
