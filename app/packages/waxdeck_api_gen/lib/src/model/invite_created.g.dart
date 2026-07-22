// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invite_created.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$InviteCreated extends InviteCreated {
  @override
  final String token;
  @override
  final String id;
  @override
  final String? note;
  @override
  final BuiltList<Role> roles;
  @override
  final LibraryAccess? libraryAccess;
  @override
  final Permissions? permissions;
  @override
  final bool uploadEnabled;
  @override
  final int maxUses;
  @override
  final int usedCount;
  @override
  final bool revoked;
  @override
  final DateTime? expiresAt;
  @override
  final DateTime createdAt;
  @override
  final String? createdBy;

  factory _$InviteCreated([void Function(InviteCreatedBuilder)? updates]) =>
      (InviteCreatedBuilder()..update(updates))._build();

  _$InviteCreated._({
    required this.token,
    required this.id,
    this.note,
    required this.roles,
    this.libraryAccess,
    this.permissions,
    required this.uploadEnabled,
    required this.maxUses,
    required this.usedCount,
    required this.revoked,
    this.expiresAt,
    required this.createdAt,
    this.createdBy,
  }) : super._();
  @override
  InviteCreated rebuild(void Function(InviteCreatedBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  InviteCreatedBuilder toBuilder() => InviteCreatedBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is InviteCreated &&
        token == other.token &&
        id == other.id &&
        note == other.note &&
        roles == other.roles &&
        libraryAccess == other.libraryAccess &&
        permissions == other.permissions &&
        uploadEnabled == other.uploadEnabled &&
        maxUses == other.maxUses &&
        usedCount == other.usedCount &&
        revoked == other.revoked &&
        expiresAt == other.expiresAt &&
        createdAt == other.createdAt &&
        createdBy == other.createdBy;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, token.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, note.hashCode);
    _$hash = $jc(_$hash, roles.hashCode);
    _$hash = $jc(_$hash, libraryAccess.hashCode);
    _$hash = $jc(_$hash, permissions.hashCode);
    _$hash = $jc(_$hash, uploadEnabled.hashCode);
    _$hash = $jc(_$hash, maxUses.hashCode);
    _$hash = $jc(_$hash, usedCount.hashCode);
    _$hash = $jc(_$hash, revoked.hashCode);
    _$hash = $jc(_$hash, expiresAt.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, createdBy.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'InviteCreated')
          ..add('token', token)
          ..add('id', id)
          ..add('note', note)
          ..add('roles', roles)
          ..add('libraryAccess', libraryAccess)
          ..add('permissions', permissions)
          ..add('uploadEnabled', uploadEnabled)
          ..add('maxUses', maxUses)
          ..add('usedCount', usedCount)
          ..add('revoked', revoked)
          ..add('expiresAt', expiresAt)
          ..add('createdAt', createdAt)
          ..add('createdBy', createdBy))
        .toString();
  }
}

class InviteCreatedBuilder
    implements Builder<InviteCreated, InviteCreatedBuilder>, InviteBuilder {
  _$InviteCreated? _$v;

  String? _token;
  String? get token => _$this._token;
  set token(covariant String? token) => _$this._token = token;

  String? _id;
  String? get id => _$this._id;
  set id(covariant String? id) => _$this._id = id;

  String? _note;
  String? get note => _$this._note;
  set note(covariant String? note) => _$this._note = note;

  ListBuilder<Role>? _roles;
  ListBuilder<Role> get roles => _$this._roles ??= ListBuilder<Role>();
  set roles(covariant ListBuilder<Role>? roles) => _$this._roles = roles;

  LibraryAccessBuilder? _libraryAccess;
  LibraryAccessBuilder get libraryAccess =>
      _$this._libraryAccess ??= LibraryAccessBuilder();
  set libraryAccess(covariant LibraryAccessBuilder? libraryAccess) =>
      _$this._libraryAccess = libraryAccess;

  PermissionsBuilder? _permissions;
  PermissionsBuilder get permissions =>
      _$this._permissions ??= PermissionsBuilder();
  set permissions(covariant PermissionsBuilder? permissions) =>
      _$this._permissions = permissions;

  bool? _uploadEnabled;
  bool? get uploadEnabled => _$this._uploadEnabled;
  set uploadEnabled(covariant bool? uploadEnabled) =>
      _$this._uploadEnabled = uploadEnabled;

  int? _maxUses;
  int? get maxUses => _$this._maxUses;
  set maxUses(covariant int? maxUses) => _$this._maxUses = maxUses;

  int? _usedCount;
  int? get usedCount => _$this._usedCount;
  set usedCount(covariant int? usedCount) => _$this._usedCount = usedCount;

  bool? _revoked;
  bool? get revoked => _$this._revoked;
  set revoked(covariant bool? revoked) => _$this._revoked = revoked;

  DateTime? _expiresAt;
  DateTime? get expiresAt => _$this._expiresAt;
  set expiresAt(covariant DateTime? expiresAt) => _$this._expiresAt = expiresAt;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(covariant DateTime? createdAt) => _$this._createdAt = createdAt;

  String? _createdBy;
  String? get createdBy => _$this._createdBy;
  set createdBy(covariant String? createdBy) => _$this._createdBy = createdBy;

  InviteCreatedBuilder() {
    InviteCreated._defaults(this);
  }

  InviteCreatedBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _token = $v.token;
      _id = $v.id;
      _note = $v.note;
      _roles = $v.roles.toBuilder();
      _libraryAccess = $v.libraryAccess?.toBuilder();
      _permissions = $v.permissions?.toBuilder();
      _uploadEnabled = $v.uploadEnabled;
      _maxUses = $v.maxUses;
      _usedCount = $v.usedCount;
      _revoked = $v.revoked;
      _expiresAt = $v.expiresAt;
      _createdAt = $v.createdAt;
      _createdBy = $v.createdBy;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(covariant InviteCreated other) {
    _$v = other as _$InviteCreated;
  }

  @override
  void update(void Function(InviteCreatedBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  InviteCreated build() => _build();

  _$InviteCreated _build() {
    _$InviteCreated _$result;
    try {
      _$result =
          _$v ??
          _$InviteCreated._(
            token: BuiltValueNullFieldError.checkNotNull(
              token,
              r'InviteCreated',
              'token',
            ),
            id: BuiltValueNullFieldError.checkNotNull(
              id,
              r'InviteCreated',
              'id',
            ),
            note: note,
            roles: roles.build(),
            libraryAccess: _libraryAccess?.build(),
            permissions: _permissions?.build(),
            uploadEnabled: BuiltValueNullFieldError.checkNotNull(
              uploadEnabled,
              r'InviteCreated',
              'uploadEnabled',
            ),
            maxUses: BuiltValueNullFieldError.checkNotNull(
              maxUses,
              r'InviteCreated',
              'maxUses',
            ),
            usedCount: BuiltValueNullFieldError.checkNotNull(
              usedCount,
              r'InviteCreated',
              'usedCount',
            ),
            revoked: BuiltValueNullFieldError.checkNotNull(
              revoked,
              r'InviteCreated',
              'revoked',
            ),
            expiresAt: expiresAt,
            createdAt: BuiltValueNullFieldError.checkNotNull(
              createdAt,
              r'InviteCreated',
              'createdAt',
            ),
            createdBy: createdBy,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'roles';
        roles.build();
        _$failedField = 'libraryAccess';
        _libraryAccess?.build();
        _$failedField = 'permissions';
        _permissions?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'InviteCreated',
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
