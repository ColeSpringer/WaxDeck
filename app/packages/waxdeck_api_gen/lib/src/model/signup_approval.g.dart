// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'signup_approval.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SignupApproval extends SignupApproval {
  @override
  final BuiltList<Role>? roles;
  @override
  final LibraryAccess? libraryAccess;
  @override
  final Permissions? permissions;
  @override
  final bool? uploadEnabled;
  @override
  final int? uploadQuotaBytes;

  factory _$SignupApproval([void Function(SignupApprovalBuilder)? updates]) =>
      (SignupApprovalBuilder()..update(updates))._build();

  _$SignupApproval._({
    this.roles,
    this.libraryAccess,
    this.permissions,
    this.uploadEnabled,
    this.uploadQuotaBytes,
  }) : super._();
  @override
  SignupApproval rebuild(void Function(SignupApprovalBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SignupApprovalBuilder toBuilder() => SignupApprovalBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SignupApproval &&
        roles == other.roles &&
        libraryAccess == other.libraryAccess &&
        permissions == other.permissions &&
        uploadEnabled == other.uploadEnabled &&
        uploadQuotaBytes == other.uploadQuotaBytes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, roles.hashCode);
    _$hash = $jc(_$hash, libraryAccess.hashCode);
    _$hash = $jc(_$hash, permissions.hashCode);
    _$hash = $jc(_$hash, uploadEnabled.hashCode);
    _$hash = $jc(_$hash, uploadQuotaBytes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SignupApproval')
          ..add('roles', roles)
          ..add('libraryAccess', libraryAccess)
          ..add('permissions', permissions)
          ..add('uploadEnabled', uploadEnabled)
          ..add('uploadQuotaBytes', uploadQuotaBytes))
        .toString();
  }
}

class SignupApprovalBuilder
    implements Builder<SignupApproval, SignupApprovalBuilder> {
  _$SignupApproval? _$v;

  ListBuilder<Role>? _roles;
  ListBuilder<Role> get roles => _$this._roles ??= ListBuilder<Role>();
  set roles(ListBuilder<Role>? roles) => _$this._roles = roles;

  LibraryAccessBuilder? _libraryAccess;
  LibraryAccessBuilder get libraryAccess =>
      _$this._libraryAccess ??= LibraryAccessBuilder();
  set libraryAccess(LibraryAccessBuilder? libraryAccess) =>
      _$this._libraryAccess = libraryAccess;

  PermissionsBuilder? _permissions;
  PermissionsBuilder get permissions =>
      _$this._permissions ??= PermissionsBuilder();
  set permissions(PermissionsBuilder? permissions) =>
      _$this._permissions = permissions;

  bool? _uploadEnabled;
  bool? get uploadEnabled => _$this._uploadEnabled;
  set uploadEnabled(bool? uploadEnabled) =>
      _$this._uploadEnabled = uploadEnabled;

  int? _uploadQuotaBytes;
  int? get uploadQuotaBytes => _$this._uploadQuotaBytes;
  set uploadQuotaBytes(int? uploadQuotaBytes) =>
      _$this._uploadQuotaBytes = uploadQuotaBytes;

  SignupApprovalBuilder() {
    SignupApproval._defaults(this);
  }

  SignupApprovalBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _roles = $v.roles?.toBuilder();
      _libraryAccess = $v.libraryAccess?.toBuilder();
      _permissions = $v.permissions?.toBuilder();
      _uploadEnabled = $v.uploadEnabled;
      _uploadQuotaBytes = $v.uploadQuotaBytes;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SignupApproval other) {
    _$v = other as _$SignupApproval;
  }

  @override
  void update(void Function(SignupApprovalBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SignupApproval build() => _build();

  _$SignupApproval _build() {
    _$SignupApproval _$result;
    try {
      _$result =
          _$v ??
          _$SignupApproval._(
            roles: _roles?.build(),
            libraryAccess: _libraryAccess?.build(),
            permissions: _permissions?.build(),
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
        _$failedField = 'permissions';
        _permissions?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'SignupApproval',
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
