// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invite_create.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$InviteCreate extends InviteCreate {
  @override
  final String? note;
  @override
  final BuiltList<Role>? roles;
  @override
  final LibraryAccess? libraryAccess;
  @override
  final Permissions? permissions;
  @override
  final bool? uploadEnabled;
  @override
  final int? maxUses;
  @override
  final DateTime? expiresAt;

  factory _$InviteCreate([void Function(InviteCreateBuilder)? updates]) =>
      (InviteCreateBuilder()..update(updates))._build();

  _$InviteCreate._({
    this.note,
    this.roles,
    this.libraryAccess,
    this.permissions,
    this.uploadEnabled,
    this.maxUses,
    this.expiresAt,
  }) : super._();
  @override
  InviteCreate rebuild(void Function(InviteCreateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  InviteCreateBuilder toBuilder() => InviteCreateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is InviteCreate &&
        note == other.note &&
        roles == other.roles &&
        libraryAccess == other.libraryAccess &&
        permissions == other.permissions &&
        uploadEnabled == other.uploadEnabled &&
        maxUses == other.maxUses &&
        expiresAt == other.expiresAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, note.hashCode);
    _$hash = $jc(_$hash, roles.hashCode);
    _$hash = $jc(_$hash, libraryAccess.hashCode);
    _$hash = $jc(_$hash, permissions.hashCode);
    _$hash = $jc(_$hash, uploadEnabled.hashCode);
    _$hash = $jc(_$hash, maxUses.hashCode);
    _$hash = $jc(_$hash, expiresAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'InviteCreate')
          ..add('note', note)
          ..add('roles', roles)
          ..add('libraryAccess', libraryAccess)
          ..add('permissions', permissions)
          ..add('uploadEnabled', uploadEnabled)
          ..add('maxUses', maxUses)
          ..add('expiresAt', expiresAt))
        .toString();
  }
}

class InviteCreateBuilder
    implements Builder<InviteCreate, InviteCreateBuilder> {
  _$InviteCreate? _$v;

  String? _note;
  String? get note => _$this._note;
  set note(String? note) => _$this._note = note;

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

  int? _maxUses;
  int? get maxUses => _$this._maxUses;
  set maxUses(int? maxUses) => _$this._maxUses = maxUses;

  DateTime? _expiresAt;
  DateTime? get expiresAt => _$this._expiresAt;
  set expiresAt(DateTime? expiresAt) => _$this._expiresAt = expiresAt;

  InviteCreateBuilder() {
    InviteCreate._defaults(this);
  }

  InviteCreateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _note = $v.note;
      _roles = $v.roles?.toBuilder();
      _libraryAccess = $v.libraryAccess?.toBuilder();
      _permissions = $v.permissions?.toBuilder();
      _uploadEnabled = $v.uploadEnabled;
      _maxUses = $v.maxUses;
      _expiresAt = $v.expiresAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(InviteCreate other) {
    _$v = other as _$InviteCreate;
  }

  @override
  void update(void Function(InviteCreateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  InviteCreate build() => _build();

  _$InviteCreate _build() {
    _$InviteCreate _$result;
    try {
      _$result =
          _$v ??
          _$InviteCreate._(
            note: note,
            roles: _roles?.build(),
            libraryAccess: _libraryAccess?.build(),
            permissions: _permissions?.build(),
            uploadEnabled: uploadEnabled,
            maxUses: maxUses,
            expiresAt: expiresAt,
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
          r'InviteCreate',
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
